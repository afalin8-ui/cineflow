#pragma once

#include "CoreMinimal.h"

/** Semantic controls, already mapped from the gamepad by the web page. All in -1..1. */
struct FDeckCamInput
{
	float Throttle = 0.f; // left stick up/down: altitude (cine) / thrust around hover (fpv)
	float Yaw = 0.f;      // left stick left/right
	float Pitch = 0.f;    // right stick up/down: forward (cine) / nose rate (fpv)
	float Roll = 0.f;     // right stick left/right: strafe (cine) / roll rate (fpv)
	float Tilt = 0.f;     // D-pad up/down: gimbal (cine) / camera uptilt (fpv)
	float Zoom = 0.f;     // RT - LT
	bool bFine = false;   // L3 held: everything x0.3

	// Gyro: degrees turned since the last tick (Steam maps the Deck gyro to mouse motion).
	// Accumulated, not a rate: consumed once per tick.
	float GyroYaw = 0.f;
	float GyroPitch = 0.f;
};

enum class EDeckCamMode : uint8
{
	Cine, // DJI-style: level horizon, velocity control with inertia
	Fpv,  // acro: rate control, thrust along body up, gravity
};

struct FDeckCamTuning
{
	float Speed = 1000.f; // cm/s at full stick; in FPV also the world scale (1000 = a real 10 m/s quad)
	float CineSmoothing = 0.35f;
	float YawRate = 60.f;
	float TiltRate = 45.f;
	float VerticalFactor = 0.6f;
	float FpvRate = 220.f;
	float FpvCameraTilt = 20.f;
	float Expo = 0.5f;
	float GyroSmoothing = 0.04f; // s: evens out the steps of mouse-rate gyro packets
};

/**
 * Pure flight model, no engine objects. Works in "frame space": world space when free,
 * parent space (with parent scale removed) when attached.
 */
class FDeckCamDrone
{
public:
	EDeckCamMode Mode = EDeckCamMode::Cine;

	FVector Position = FVector::ZeroVector;
	FVector Velocity = FVector::ZeroVector;

	// Cine
	float Yaw = 0.f;
	float GimbalPitch = 0.f;
	float YawRateNow = 0.f;
	float TiltRateNow = 0.f;

	// FPV
	FQuat Body = FQuat::Identity;
	FVector BodyRates = FVector::ZeroVector; // deg/s: X roll, Y pitch, Z yaw

	// Gyro look still to be applied
	float LookYaw = 0.f;
	float LookPitch = 0.f;

	/** Take pose from a camera transform. Velocity and rates are kept, so resyncing mid-flight is seamless. */
	void SetPose(const FTransform& Camera, const FDeckCamTuning& T);

	void Step(const FDeckCamInput& In, const FDeckCamTuning& T, float Dt);

	FTransform GetCameraTransform(const FDeckCamTuning& T) const;

	void SwitchMode(EDeckCamMode NewMode, const FDeckCamTuning& T);

	/** Stop and level the horizon, keep heading. */
	void Level();

	/** Queue a look turn from the gyro, degrees. Applied smoothly over the next substeps. */
	void AddLook(float YawDeg, float PitchDeg);

private:
	float Shape(float S, float Expo) const { return S * (1.f - Expo) + S * S * S * Expo; }
	void StepCine(const FDeckCamInput& In, const FDeckCamTuning& T, float Dt);
	void StepFpv(const FDeckCamInput& In, const FDeckCamTuning& T, float Dt);
	void StepLook(const FDeckCamTuning& T, float Dt);
};
