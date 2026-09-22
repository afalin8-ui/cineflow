#pragma once

#include "CoreMinimal.h"
#include "Engine/DeveloperSettings.h"
#include "DeckCamSettings.generated.h"

/**
 * Project Settings -> Plugins -> DeckCam.
 * Stored per user (EditorPerProjectUserSettings): tuning is a matter of taste of whoever holds the Deck.
 */
UCLASS(Config = EditorPerProjectUserSettings, meta = (DisplayName = "DeckCam"))
class DECKCAM_API UDeckCamSettings : public UDeveloperSettings
{
	GENERATED_BODY()

public:
	UDeckCamSettings();

	virtual FName GetCategoryName() const override { return TEXT("Plugins"); }

	/** TCP port. The Deck opens http://<this PC>:Port */
	UPROPERTY(Config, EditAnywhere, Category = "Connection", meta = (ClampMin = 1024, ClampMax = 65535))
	int32 Port = 8787;

	/** Start the server when the editor starts. */
	UPROPERTY(Config, EditAnywhere, Category = "Connection")
	bool bAutoStart = false;

	/** Sticks are zeroed if the Deck goes silent this long (Wi-Fi dropout => camera stops instead of flying away). */
	UPROPERTY(Config, EditAnywhere, Category = "Connection", meta = (ClampMin = 0.05, Units = "s"))
	float InputTimeout = 0.3f;

	/** Full-stick speed presets, cm/s. Bumpers step through them. */
	UPROPERTY(Config, EditAnywhere, Category = "Flight")
	TArray<float> SpeedPresets;

	UPROPERTY(Config, EditAnywhere, Category = "Flight")
	int32 DefaultSpeedIndex = 3;

	/** Cine mode: how long the drone takes to reach stick speed (inertia), seconds. */
	UPROPERTY(Config, EditAnywhere, Category = "Flight|Cine", meta = (ClampMin = 0.01, Units = "s"))
	float CineSmoothing = 0.35f;

	/** Cine mode: yaw rate at full stick, deg/s. */
	UPROPERTY(Config, EditAnywhere, Category = "Flight|Cine")
	float YawRate = 60.f;

	/** Cine mode: gimbal tilt rate (D-pad up/down), deg/s. */
	UPROPERTY(Config, EditAnywhere, Category = "Flight|Cine")
	float TiltRate = 45.f;

	/** Cine mode: vertical speed as a fraction of horizontal. */
	UPROPERTY(Config, EditAnywhere, Category = "Flight|Cine", meta = (ClampMin = 0.05, ClampMax = 2))
	float VerticalFactor = 0.6f;

	/** FPV mode: rotation rate at full stick, deg/s. */
	UPROPERTY(Config, EditAnywhere, Category = "Flight|FPV")
	float FpvRate = 220.f;

	/** FPV mode: camera uptilt relative to the drone body, deg. */
	UPROPERTY(Config, EditAnywhere, Category = "Flight|FPV", meta = (ClampMin = -30, ClampMax = 60))
	float FpvCameraTilt = 20.f;

	/** Stick expo 0..1: higher = finer control around center. */
	UPROPERTY(Config, EditAnywhere, Category = "Flight", meta = (ClampMin = 0, ClampMax = 1))
	float Expo = 0.5f;

	/** Zoom speed at full trigger: focal length changes by e^ZoomRate per second. */
	UPROPERTY(Config, EditAnywhere, Category = "Flight", meta = (ClampMin = 0.05))
	float ZoomRate = 0.7f;

	/** Actors with this tag are the attach targets. If none are tagged, the editor selection is used. */
	UPROPERTY(Config, EditAnywhere, Category = "Attach")
	FName TargetTag = TEXT("DeckCamTarget");

	/** Lock the level viewport to the DeckCam camera on start, so the PC monitor shows the shot. */
	UPROPERTY(Config, EditAnywhere, Category = "Viewport")
	bool bPilotViewport = true;

	/** Keep the editor at full speed when its window is not in focus (you hold the Deck, not the mouse). */
	UPROPERTY(Config, EditAnywhere, Category = "Viewport")
	bool bNoThrottleInBackground = true;

	/** Send the camera picture to the Deck. Costs a second render of the scene. */
	UPROPERTY(Config, EditAnywhere, Category = "Video")
	bool bVideo = true;

	/** Preview width in pixels; height follows the camera filmback. The Deck screen is 1280x800. */
	UPROPERTY(Config, EditAnywhere, Category = "Video", meta = (ClampMin = 320, ClampMax = 1920))
	int32 VideoWidth = 960;

	UPROPERTY(Config, EditAnywhere, Category = "Video", meta = (ClampMin = 5, ClampMax = 60))
	int32 VideoFps = 30;

	UPROPERTY(Config, EditAnywhere, Category = "Video", meta = (ClampMin = 20, ClampMax = 95))
	int32 JpegQuality = 70;
};
