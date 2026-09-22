#pragma once

#include "CoreMinimal.h"
#include <atomic>
#include "UObject/StrongObjectPtr.h"

class FDeckCamServer;
class FRHIGPUTextureReadback;
class ASceneCapture2D;
class UCineCameraComponent;
class UTextureRenderTarget2D;
class UDeckCamSettings;
class UWorld;

/**
 * Renders the DeckCam camera into a small render target, reads it back asynchronously
 * (no GPU stall), encodes JPEG on a worker thread and hands it to the server.
 * One frame in flight at a time; a frame is only produced when a client asked for one.
 */
class FDeckCamVideo
{
public:
	FDeckCamVideo();
	~FDeckCamVideo();

	void Tick(UWorld* World, UCineCameraComponent* Camera, FDeckCamServer& Server, const UDeckCamSettings& Settings);

	float GetFps() const { return Fps; }

private:
	struct FPending
	{
		std::atomic<bool> bDone { false };
		int32 Width = 0;
		int32 Height = 0;
		TArray<uint8> Pixels; // BGRA, tightly packed
	};

	struct FEncoded
	{
		FCriticalSection Lock;
		bool bReady = false;
		TArray<uint8> Jpeg;
		std::atomic<bool> bBusy { false }; // an encode task is running; shared so the task never touches a dead object
	};

	bool EnsureTargets(UWorld* World, int32 W, int32 H);

	TWeakObjectPtr<ASceneCapture2D> Capture;
	TStrongObjectPtr<UTextureRenderTarget2D> Target;
	TSharedPtr<FRHIGPUTextureReadback, ESPMode::ThreadSafe> Readback;
	TSharedPtr<FPending, ESPMode::ThreadSafe> Pending;
	TSharedPtr<FEncoded, ESPMode::ThreadSafe> Encoded;

	bool bInFlight = false;
	double InFlightSince = 0.0;
	double LastCapture = 0.0;

	double FpsWindowStart = 0.0;
	int32 FpsFrames = 0;
	float Fps = 0.f;
};
