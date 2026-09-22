#include "DeckCamServer.h"

#include "HAL/RunnableThread.h"
#include "HAL/PlatformProcess.h"
#include "Misc/Base64.h"
#include "Misc/FileHelper.h"
#include "Misc/SecureHash.h"
#include "SocketSubsystem.h"
#include "Sockets.h"
#include "IPAddress.h"

DEFINE_LOG_CATEGORY_STATIC(LogDeckCamServer, Log, All);

namespace
{
	constexpr int32 MaxHttpRequest = 16 * 1024;
	constexpr int32 MaxWsPayload = 1 << 20;
	constexpr int32 MaxOutBytes = 8 * 1024 * 1024;   // a client this far behind is dead
	constexpr int32 FrameBacklogBytes = 256 * 1024;   // do not queue video on top of this
	constexpr double FrameAckTimeout = 1.0;           // lost ack => resend

	FString BytesToString(const uint8* Data, int32 Len)
	{
		FUTF8ToTCHAR Conv(reinterpret_cast<const ANSICHAR*>(Data), Len);
		return FString(Conv.Length(), Conv.Get());
	}

	int32 FindHeaderEnd(const TArray<uint8>& In)
	{
		for (int32 i = 0; i + 3 < In.Num(); ++i)
		{
			if (In[i] == '\r' && In[i + 1] == '\n' && In[i + 2] == '\r' && In[i + 3] == '\n')
			{
				return i + 4;
			}
		}
		return INDEX_NONE;
	}

	void AppendString(TArray<uint8>& Out, const FString& S)
	{
		FTCHARToUTF8 Conv(*S);
		Out.Append(reinterpret_cast<const uint8*>(Conv.Get()), Conv.Length());
	}
}

FDeckCamServer::FDeckCamServer() = default;

FDeckCamServer::~FDeckCamServer()
{
	Shutdown();
}

bool FDeckCamServer::Start(int32 Port, const FString& InHtmlPath, FString& OutError)
{
	HtmlPath = InHtmlPath;
	ISocketSubsystem* SS = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
	if (!SS)
	{
		OutError = TEXT("No socket subsystem");
		return false;
	}

	TSharedRef<FInternetAddr> Addr = SS->CreateInternetAddr();
	Addr->SetAnyAddress();
	Addr->SetPort(Port);

	Listener = SS->CreateSocket(NAME_Stream, TEXT("DeckCamListener"), false);
	if (!Listener)
	{
		OutError = TEXT("Could not create socket");
		return false;
	}
	Listener->SetReuseAddr(true);
	Listener->SetNonBlocking(true);
	if (!Listener->Bind(*Addr) || !Listener->Listen(8))
	{
		OutError = FString::Printf(TEXT("Port %d is busy or blocked"), Port);
		SS->DestroySocket(Listener);
		Listener = nullptr;
		return false;
	}

	bStopping = false;
	Thread = FRunnableThread::Create(this, TEXT("DeckCamServer"), 0, TPri_AboveNormal);
	return Thread != nullptr;
}

void FDeckCamServer::Shutdown()
{
	if (Thread)
	{
		bStopping = true;
		Thread->WaitForCompletion();
		delete Thread;
		Thread = nullptr;
	}

	ISocketSubsystem* SS = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
	FScopeLock Guard(&Lock);
	for (TUniquePtr<FClient>& C : Clients)
	{
		if (C->Socket)
		{
			C->Socket->Close();
			SS->DestroySocket(C->Socket);
		}
	}
	Clients.Reset();
	if (Listener)
	{
		Listener->Close();
		SS->DestroySocket(Listener);
		Listener = nullptr;
	}
}

uint32 FDeckCamServer::Run()
{
	while (!bStopping)
	{
		Pump();
		FPlatformProcess::Sleep(0.002f);
	}
	return 0;
}

void FDeckCamServer::Pump()
{
	ISocketSubsystem* SS = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM);
	FScopeLock Guard(&Lock);

	// Accept
	bool bPending = false;
	while (Listener && Listener->HasPendingConnection(bPending) && bPending)
	{
		FSocket* S = Listener->Accept(TEXT("DeckCamClient"));
		if (!S)
		{
			break;
		}
		S->SetNonBlocking(true);
		S->SetNoDelay(true);
		TUniquePtr<FClient> C = MakeUnique<FClient>();
		C->Socket = S;
		Clients.Add(MoveTemp(C));
	}

	const double Now = FPlatformTime::Seconds();
	uint8 Buf[16384];

	for (TUniquePtr<FClient>& CPtr : Clients)
	{
		FClient& C = *CPtr;

		// Receive
		while (!C.bDead)
		{
			int32 Read = 0;
			if (!C.Socket->Recv(Buf, sizeof(Buf), Read))
			{
				C.bDead = true; // closed by peer or error
				break;
			}
			if (Read <= 0)
			{
				break; // would block
			}
			C.In.Append(Buf, Read);
		}

		if (!C.bDead)
		{
			if (C.bWebSocket)
			{
				HandleWebSocket(C);
			}
			else
			{
				HandleHttp(C);
			}
		}

		if (C.bWebSocket && !C.bFrameReady && Now - C.FrameSentAt > FrameAckTimeout)
		{
			C.bFrameReady = true;
		}

		// Send
		while (!C.bDead && C.Out.Num() > 0)
		{
			int32 Sent = 0;
			if (!C.Socket->Send(C.Out.GetData(), C.Out.Num(), Sent))
			{
				if (SS->GetLastErrorCode() != SE_EWOULDBLOCK)
				{
					C.bDead = true;
				}
				break;
			}
			if (Sent <= 0)
			{
				break;
			}
			C.Out.RemoveAt(0, Sent, EAllowShrinking::No);
		}

		if (C.Out.Num() == 0 && C.bCloseAfterSend)
		{
			C.bDead = true;
		}
		if (C.Out.Num() > MaxOutBytes)
		{
			C.bDead = true;
		}
	}

	for (int32 i = Clients.Num() - 1; i >= 0; --i)
	{
		if (Clients[i]->bDead)
		{
			Clients[i]->Socket->Close();
			SS->DestroySocket(Clients[i]->Socket);
			Clients.RemoveAt(i);
		}
	}
}

void FDeckCamServer::HandleHttp(FClient& C)
{
	const int32 End = FindHeaderEnd(C.In);
	if (End == INDEX_NONE)
	{
		if (C.In.Num() > MaxHttpRequest)
		{
			C.bDead = true;
		}
		return;
	}

	const FString Req = BytesToString(C.In.GetData(), End);
	C.In.RemoveAt(0, End, EAllowShrinking::No);

	TArray<FString> Lines;
	Req.ParseIntoArray(Lines, TEXT("\r\n"), true);
	if (Lines.Num() == 0)
	{
		C.bDead = true;
		return;
	}

	TArray<FString> First;
	Lines[0].ParseIntoArrayWS(First);
	const FString Path = First.Num() > 1 ? First[1] : TEXT("/");

	FString WsKey;
	bool bUpgrade = false;
	for (int32 i = 1; i < Lines.Num(); ++i)
	{
		FString Name, Value;
		if (Lines[i].Split(TEXT(":"), &Name, &Value))
		{
			Name.TrimStartAndEndInline();
			Value.TrimStartAndEndInline();
			if (Name.Equals(TEXT("Upgrade"), ESearchCase::IgnoreCase) && Value.Equals(TEXT("websocket"), ESearchCase::IgnoreCase))
			{
				bUpgrade = true;
			}
			else if (Name.Equals(TEXT("Sec-WebSocket-Key"), ESearchCase::IgnoreCase))
			{
				WsKey = Value;
			}
		}
	}

	if (bUpgrade && !WsKey.IsEmpty())
	{
		const FString Combined = WsKey + TEXT("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
		FTCHARToUTF8 Utf(*Combined);
		uint8 Hash[20];
		FSHA1::HashBuffer(Utf.Get(), Utf.Length(), Hash);
		const FString Accept = FBase64::Encode(Hash, 20);

		AppendString(C.Out, FString::Printf(
			TEXT("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n"),
			*Accept));
		C.bWebSocket = true;
		C.bFrameReady = true;
		Incoming.Enqueue(TEXT("{\"t\":\"hello\"}"));
		UE_LOG(LogDeckCamServer, Log, TEXT("Controller connected"));
		HandleWebSocket(C); // frames may already be in the buffer
		return;
	}

	if (Path == TEXT("/") || Path.StartsWith(TEXT("/?")) || Path == TEXT("/index.html"))
	{
		TArray<uint8> Body;
		if (FFileHelper::LoadFileToArray(Body, *HtmlPath))
		{
			AppendString(C.Out, FString::Printf(
				TEXT("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"),
				Body.Num()));
			C.Out.Append(Body);
		}
		else
		{
			const FString Msg = FString::Printf(TEXT("DeckCam: page not found at %s"), *HtmlPath);
			AppendString(C.Out, FString::Printf(
				TEXT("HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"),
				FTCHARToUTF8(*Msg).Length()));
			AppendString(C.Out, Msg);
		}
	}
	else
	{
		AppendString(C.Out, TEXT("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"));
	}
	C.bCloseAfterSend = true;
}

void FDeckCamServer::HandleWebSocket(FClient& C)
{
	while (C.In.Num() >= 2 && !C.bDead)
	{
		const uint8 B0 = C.In[0];
		const uint8 B1 = C.In[1];
		const uint8 Opcode = B0 & 0x0F;
		const bool bMasked = (B1 & 0x80) != 0;
		uint64 Len = B1 & 0x7F;
		int32 Pos = 2;

		if (Len == 126)
		{
			if (C.In.Num() < 4) return;
			Len = (uint64(C.In[2]) << 8) | C.In[3];
			Pos = 4;
		}
		else if (Len == 127)
		{
			if (C.In.Num() < 10) return;
			Len = 0;
			for (int32 i = 0; i < 8; ++i)
			{
				Len = (Len << 8) | C.In[2 + i];
			}
			Pos = 10;
		}
		if (Len > uint64(MaxWsPayload))
		{
			C.bDead = true;
			return;
		}

		uint8 Mask[4] = { 0, 0, 0, 0 };
		if (bMasked)
		{
			if (C.In.Num() < Pos + 4) return;
			FMemory::Memcpy(Mask, C.In.GetData() + Pos, 4);
			Pos += 4;
		}
		if (uint64(C.In.Num()) < uint64(Pos) + Len)
		{
			return;
		}

		TArray<uint8> Payload;
		Payload.SetNumUninitialized(int32(Len));
		for (int32 i = 0; i < int32(Len); ++i)
		{
			Payload[i] = C.In[Pos + i] ^ Mask[i & 3];
		}
		C.In.RemoveAt(0, Pos + int32(Len), EAllowShrinking::No);

		switch (Opcode)
		{
		case 0x1: // text
			OnText(C, BytesToString(Payload.GetData(), Payload.Num()));
			break;
		case 0x8: // close
			AppendFrame(C.Out, 0x8, Payload.GetData(), FMath::Min(Payload.Num(), 2));
			C.bCloseAfterSend = true;
			UE_LOG(LogDeckCamServer, Log, TEXT("Controller disconnected"));
			return;
		case 0x9: // ping
			AppendFrame(C.Out, 0xA, Payload.GetData(), Payload.Num());
			break;
		default: // pong, binary, continuation: not used by the page
			break;
		}
	}
}

void FDeckCamServer::OnText(FClient& C, const FString& Text)
{
	// Fast path: frame acks never leave the network thread.
	if (Text.Contains(TEXT("\"t\":\"ack\"")))
	{
		C.bFrameReady = true;
		return;
	}
	Incoming.Enqueue(Text);
}

void FDeckCamServer::AppendFrame(TArray<uint8>& Out, uint8 Opcode, const uint8* Data, int32 Len)
{
	Out.Add(0x80 | Opcode);
	if (Len < 126)
	{
		Out.Add(uint8(Len));
	}
	else if (Len < 65536)
	{
		Out.Add(126);
		Out.Add(uint8(Len >> 8));
		Out.Add(uint8(Len & 0xFF));
	}
	else
	{
		Out.Add(127);
		for (int32 i = 7; i >= 0; --i)
		{
			Out.Add(uint8((uint64(Len) >> (8 * i)) & 0xFF));
		}
	}
	if (Len > 0)
	{
		Out.Append(Data, Len);
	}
}

bool FDeckCamServer::PopMessage(FString& Out)
{
	return Incoming.Dequeue(Out);
}

void FDeckCamServer::BroadcastText(const FString& Text)
{
	FTCHARToUTF8 Conv(*Text);
	FScopeLock Guard(&Lock);
	for (TUniquePtr<FClient>& C : Clients)
	{
		if (C->bWebSocket && !C->bDead && !C->bCloseAfterSend && C->Out.Num() < FrameBacklogBytes * 4)
		{
			AppendFrame(C->Out, 0x1, reinterpret_cast<const uint8*>(Conv.Get()), Conv.Length());
		}
	}
}

bool FDeckCamServer::WantsFrame()
{
	FScopeLock Guard(&Lock);
	for (TUniquePtr<FClient>& C : Clients)
	{
		if (C->bWebSocket && !C->bDead && C->bFrameReady && C->Out.Num() < FrameBacklogBytes)
		{
			return true;
		}
	}
	return false;
}

void FDeckCamServer::SendFrame(const TArray<uint8>& Jpeg)
{
	const double Now = FPlatformTime::Seconds();
	FScopeLock Guard(&Lock);
	for (TUniquePtr<FClient>& C : Clients)
	{
		if (C->bWebSocket && !C->bDead && C->bFrameReady && C->Out.Num() < FrameBacklogBytes)
		{
			AppendFrame(C->Out, 0x2, Jpeg.GetData(), Jpeg.Num());
			C->bFrameReady = false;
			C->FrameSentAt = Now;
		}
	}
}

int32 FDeckCamServer::NumClients()
{
	FScopeLock Guard(&Lock);
	int32 N = 0;
	for (TUniquePtr<FClient>& C : Clients)
	{
		N += C->bWebSocket ? 1 : 0;
	}
	return N;
}
