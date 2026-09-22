#include "DeckCamVideo.h"

#include "DeckCamServer.h"
#include "DeckCamSettings.h"

#include "Async/Async.h"
#include "CineCameraComponent.h"
#include "Components/SceneCaptureComponent2D.h"
#include "Engine/SceneCapture2D.h"
#include "Engine/TextureRenderTarget2D.h"
#include "Engine/World.h"
#include "IImageWrapper.h"
#include "IImageWrapperModule.h"
#include "Modules/ModuleManager.h"
#include "RHIGPUReadback.h"
#include "RenderingThread.h"
#include "TextureResource.h"

FDeckCamVideo::FDeckCamVideo()
{
	// Must be loaded on the game thread before worker threads use it.
	FModuleManager::LoadModuleChecked<IImageWrapperModule>(TEXT("ImageWrapper"));
	Encoded = MakeShared<FEncoded, ESPMode::ThreadSafe>();
	Readback = MakeShared<FRHIGPUTextureReadback, ESPMode::ThreadSafe>(TEXT("DeckCamReadback"));
}

FDeckCamVideo::~FDeckCamVideo()
{
	FlushRenderingCommands();
	if (ASceneCapture2D* C = Capture.Get())
	{
		C->Destroy();
	}
	Capture.Reset();
	Target.Reset();
}

bool FDeckCamVideo::EnsureTargets(UWorld* World, int32 W, int32 H)
{
	ASceneCapture2D* C = Capture.Get();
	if (C && C->GetWorld() != World)
	{
		C->Destroy();
		C = nullptr;
	}
	if (!C)
	{
		FActorSpawnParameters P;
		P.ObjectFlags |= RF_Transient; // never saved with the level, never recorded
		P.Name = MakeUniqueObjectName(World->PersistentLevel, ASceneCapture2D::StaticClass(), TEXT("DeckCamPreview"));
#if WITH_EDITOR
		P.bHideFromSceneOutliner = true;
#endif
		C = World->SpawnActor<ASceneCapture2D>(ASceneCapture2D::StaticClass(), FTransform::Identity, P);
		if (!C)
		{
			return false;
		}
#if WITH_EDITOR
		C->SetIsTemporarilyHiddenInEditor(true);
#endif
		USceneCaptureComponent2D* Comp = C->GetCaptureComponent2D();
		Comp->bCaptureEveryFrame = false;
		Comp->bCaptureOnMovement = false;
		Comp->bAlwaysPersistRenderingState = true; // keeps TAA history and auto exposure between captures
		Comp->CaptureSource = ESceneCaptureSource::SCS_FinalColorLDR;
		Comp->ShowFlags.SetMotionBlur(false);
		Capture = C;
	}

	UTextureRenderTarget2D* RT = Target.Get();
	if (!RT || RT->SizeX != W || RT->SizeY != H)
	{
		RT = NewObject<UTextureRenderTarget2D>(GetTransientPackage());
		RT->RenderTargetFormat = RTF_RGBA8;
		RT->ClearColor = FLinearColor::Black;
		RT->bAutoGenerateMips = false;
		RT->InitAutoFormat(W, H);
		RT->UpdateResourceImmediate(true);
		Target.Reset(RT);
	}
	C->GetCaptureComponent2D()->TextureTarget = RT;
	return true;
}

void FDeckCamVideo::Tick(UWorld* World, UCineCameraComponent* Camera, FDeckCamServer& Server, const UDeckCamSettings& S)
{
	const double Now = FPlatformTime::Seconds();

	// 1. Hand an encoded frame to the network.
	{
		TArray<uint8> Jpeg;
		{
			FScopeLock Guard(&Encoded->Lock);
			if (Encoded->bReady)
			{
				Jpeg = MoveTemp(Encoded->Jpeg);
				Encoded->bReady = false;
			}
		}
		if (Jpeg.Num() > 0)
		{
			Server.SendFrame(Jpeg);
			++FpsFrames;
		}
	}
	if (Now - FpsWindowStart >= 1.0)
	{
		Fps = FpsFrames / float(Now - FpsWindowStart);
		FpsFrames = 0;
		FpsWindowStart = Now;
	}

	// 2. Collect a finished readback and encode it off the game thread.
	if (bInFlight)
	{
		if (Pending->bDone)
		{
			bInFlight = false;
			Encoded->bBusy = true;
			TSharedPtr<FPending, ESPMode::ThreadSafe> Done = Pending;
			TSharedPtr<FEncoded, ESPMode::ThreadSafe> Out = Encoded;
			const int32 Quality = S.JpegQuality;
			AsyncTask(ENamedThreads::AnyBackgroundThreadNormalTask, [Done, Out, Quality]()
			{
				IImageWrapperModule& M = FModuleManager::GetModuleChecked<IImageWrapperModule>(TEXT("ImageWrapper"));
				TSharedPtr<IImageWrapper> W = M.CreateImageWrapper(EImageFormat::JPEG);
				if (W.IsValid() && Done->Pixels.Num() > 0 &&
					W->SetRaw(Done->Pixels.GetData(), Done->Pixels.Num(), Done->Width, Done->Height, ERGBFormat::BGRA, 8))
				{
					const TArray64<uint8>& Compressed = W->GetCompressed(Quality);
					FScopeLock Guard(&Out->Lock);
					Out->Jpeg = TArray<uint8>(Compressed.GetData(), int32(Compressed.Num()));
					Out->bReady = true;
				}
				Out->bBusy = false;
			});
		}
		else if (Now - InFlightSince > 1.0)
		{
			bInFlight = false; // readback lost (device reset, level change): start over
		}
		else
		{
			TSharedPtr<FRHIGPUTextureReadback, ESPMode::ThreadSafe> RB = Readback;
			TSharedPtr<FPending, ESPMode::ThreadSafe> P = Pending;
			ENQUEUE_RENDER_COMMAND(DeckCamPoll)([RB, P](FRHICommandListImmediate& RHICmdList)
			{
				if (P->bDone || !RB->IsReady())
				{
					return;
				}
				int32 PitchPixels = 0;
				const uint8* Src = static_cast<const uint8*>(RB->Lock(PitchPixels));
				if (Src)
				{
					const int32 RowBytes = P->Width * 4;
					P->Pixels.SetNumUninitialized(RowBytes * P->Height);
					for (int32 Y = 0; Y < P->Height; ++Y)
					{
						FMemory::Memcpy(P->Pixels.GetData() + Y * RowBytes, Src + Y * PitchPixels * 4, RowBytes);
					}
				}
				RB->Unlock();
				P->bDone = true;
			});
		}
		return;
	}

	// 3. Start a new capture if someone is waiting and we are not over the frame rate.
	if (!S.bVideo || Encoded->bBusy || !Camera || !World)
	{
		return;
	}
	if (Now - LastCapture < 1.0 / FMath::Max(1, S.VideoFps) || !Server.WantsFrame())
	{
		return;
	}

	const float Aspect = FMath::Max(0.1f, Camera->Filmback.SensorAspectRatio);
	const int32 W = FMath::Clamp(S.VideoWidth, 320, 1920) & ~1;
	const int32 H = FMath::Clamp(FMath::RoundToInt(W / Aspect), 90, 1920) & ~1;
	if (!EnsureTargets(World, W, H))
	{
		return;
	}

	USceneCaptureComponent2D* Comp = Capture->GetCaptureComponent2D();
	Capture->SetActorTransform(Camera->GetComponentTransform());
	Comp->FOVAngle = Camera->GetHorizontalFieldOfView();
	Comp->PostProcessSettings = Camera->PostProcessSettings;
	Comp->PostProcessBlendWeight = Camera->PostProcessBlendWeight;
	Comp->CaptureScene();

	LastCapture = Now;
	InFlightSince = Now;
	bInFlight = true;
	Pending = MakeShared<FPending, ESPMode::ThreadSafe>();
	Pending->Width = W;
	Pending->Height = H;

	FTextureRenderTargetResource* Res = Target->GameThread_GetRenderTargetResource();
	TSharedPtr<FRHIGPUTextureReadback, ESPMode::ThreadSafe> RB = Readback;
	ENQUEUE_RENDER_COMMAND(DeckCamCopy)([Res, RB](FRHICommandListImmediate& RHICmdList)
	{
		if (Res && Res->GetRenderTargetTexture())
		{
			RB->EnqueueCopy(RHICmdList, Res->GetRenderTargetTexture());
		}
	});
}
