#pragma once

#include "CoreMinimal.h"
#include "EditorSubsystem.h"
#include "TickableEditorObject.h"
#include "DeckCamDrone.h"
#include "DeckCamSubsystem.generated.h"

class ACineCameraActor;
class FDeckCamServer;
class FDeckCamVideo;
class FLevelEditorViewportClient;
class UWorld;

/**
 * Lives in the editor (no Play-In-Editor needed): Take Recorder and Sequencer work in the editor world,
 * so the camera flies there while the aircraft sequence plays.
 */
UCLASS()
class UDeckCamSubsystem : public UEditorSubsystem, public FTickableEditorObject
{
	GENERATED_BODY()

public:
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;

	virtual void Tick(float DeltaTime) override;
	virtual ETickableTickType GetTickableTickType() const override { return ETickableTickType::Conditional; }
	virtual bool IsTickable() const override { return bRunning; }
	virtual TStatId GetStatId() const override;

	void Start();
	void Stop();
	bool IsRunning() const { return bRunning; }

private:
	UWorld* GetEditorWorld() const;
	ACineCameraActor* EnsureCamera(UWorld* World);
	FLevelEditorViewportClient* GetViewport() const;

	void PumpMessages();
	void HandleCommand(const FString& Cmd);
	void ApplyInput(const TSharedPtr<class FJsonObject>& Json);

	void ToggleRecord();
	void ToggleAttach();
	void CycleTarget(int32 Dir);
	void RefreshTargets(UWorld* World);
	void TogglePlay();
	void Rewind();
	void SetPilot(bool bOn);

	/** Transform of the frame the drone flies in (parent without scale, or identity). */
	FTransform GetFrame(ACineCameraActor* Cam, float& OutScale) const;
	void SendStatus();
	void Notify(const FString& Code, const FString& Text = FString());

	FDeckCamTuning MakeTuning() const;

	TUniquePtr<FDeckCamServer> Server;
	TUniquePtr<FDeckCamVideo> Video;

	TWeakObjectPtr<ACineCameraActor> Camera;
	TWeakObjectPtr<AActor> LastParent;
	TArray<TWeakObjectPtr<AActor>> Targets;
	int32 TargetIndex = 0;

	FDeckCamDrone Drone;
	FDeckCamInput Input;
	double LastInputTime = 0.0;
	int32 SpeedIndex = 0;

	bool bRunning = false;
	bool bSynced = false;
	FTransform LastWritten = FTransform::Identity;
	FTransform LastFrame = FTransform::Identity;
	bool bPilot = false;
	bool bWantPilot = false;
	double NextStatus = 0.0;
	double RecordStart = 0.0;
	bool bWasRecording = false;
	bool bSavedThrottle = true;
};
