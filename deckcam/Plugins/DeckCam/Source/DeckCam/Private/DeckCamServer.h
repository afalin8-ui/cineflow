#pragma once

#include "CoreMinimal.h"
#include <atomic>
#include "HAL/Runnable.h"
#include "Containers/Queue.h"

class FSocket;
class FRunnableThread;

/**
 * Minimal HTTP + WebSocket server on its own thread.
 *
 *  GET /      -> the controller page (read from disk on every request, so it can be edited live)
 *  WebSocket  -> text JSON both ways (input, commands, status) + binary JPEG frames to the Deck
 *
 * Video flow control: one frame in flight per client. The page sends {"t":"ack"} after drawing,
 * only then the next frame goes out. On bad Wi-Fi the frame rate drops, the latency does not grow.
 */
class FDeckCamServer : public FRunnable
{
public:
	FDeckCamServer();
	virtual ~FDeckCamServer() override;

	bool Start(int32 Port, const FString& InHtmlPath, FString& OutError);
	void Shutdown();

	// ---- Game thread API ----
	bool PopMessage(FString& Out);
	void BroadcastText(const FString& Text);
	/** At least one client is waiting for a video frame. */
	bool WantsFrame();
	void SendFrame(const TArray<uint8>& Jpeg);
	int32 NumClients();

	// ---- FRunnable ----
	virtual uint32 Run() override;
	virtual void Stop() override { bStopping = true; }

private:
	struct FClient
	{
		FSocket* Socket = nullptr;
		TArray<uint8> In;
		TArray<uint8> Out;
		bool bWebSocket = false;
		bool bCloseAfterSend = false;
		bool bDead = false;
		bool bFrameReady = true;
		double FrameSentAt = 0.0;
	};

	void Pump();
	void HandleHttp(FClient& C);
	void HandleWebSocket(FClient& C);
	void OnText(FClient& C, const FString& Text);
	static void AppendFrame(TArray<uint8>& Out, uint8 Opcode, const uint8* Data, int32 Len);

	FSocket* Listener = nullptr;
	TArray<TUniquePtr<FClient>> Clients;
	FCriticalSection Lock;
	TQueue<FString, EQueueMode::Mpsc> Incoming;
	FRunnableThread* Thread = nullptr;
	std::atomic<bool> bStopping { false };
	FString HtmlPath;
};
