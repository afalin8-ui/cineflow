#include "DeckCamDrone.h"

namespace
{
	// Exponential approach factor for a first-order lag with time constant Tau.
	float Lag(float Dt, float Tau)
	{
		return 1.f - FMath::Exp(-Dt / FMath::Max(Tau, 0.001f));
	}

	FQuat UptiltQuat(float Deg)
	{
		// Positive pitch = look up. Applied in body space: Camera = Body * Uptilt.
		return FQuat(FRotator(Deg, 0.f, 0.f));
	}
}

void FDeckCamDrone::SetPose(const FTransform& Camera, const FDeckCamTuning& T)
{
	Position = Camera.GetLocation();
	const FRotator R = Camera.Rotator();
	Yaw = R.Yaw;
	GimbalPitch = FMath::Clamp(R.Pitch, -90.f, 30.f);
	Body = (Camera.GetRotation() * UptiltQuat(T.FpvCameraTilt).Inverse()).GetNormalized();
}

void FDeckCamDrone::Step(const FDeckCamInput& In, const FDeckCamTuning& T, float Dt)
{
	if (Dt <= 0.f)
	{
		return;
	}
	if (Mode == EDeckCamMode::Cine)
	{
		StepCine(In, T, Dt);
	}
	else
	{
		StepFpv(In, T, Dt);
	}
}

void FDeckCamDrone::StepCine(const FDeckCamInput& In, const FDeckCamTuning& T, float Dt)
{
	const float K = In.bFine ? 0.3f : 1.f;
	const float Fwd = Shape(In.Pitch, T.Expo) * K;
	const float Right = Shape(In.Roll, T.Expo) * K;
	const float Up = Shape(In.Throttle, T.Expo) * K * T.VerticalFactor;

	// Velocity is commanded relative to heading; the horizon stays level.
	const FVector Target = FRotator(0.f, Yaw, 0.f).RotateVector(FVector(Fwd, Right, Up)) * T.Speed;
	Velocity += (Target - Velocity) * Lag(Dt, T.CineSmoothing);
	Position += Velocity * Dt;

	const float YawTarget = Shape(In.Yaw, T.Expo) * K * T.YawRate;
	YawRateNow += (YawTarget - YawRateNow) * Lag(Dt, 0.15f);
	Yaw = FRotator::NormalizeAxis(Yaw + YawRateNow * Dt);

	const float TiltTarget = In.Tilt * K * T.TiltRate;
	TiltRateNow += (TiltTarget - TiltRateNow) * Lag(Dt, 0.12f);
	GimbalPitch = FMath::Clamp(GimbalPitch + TiltRateNow * Dt, -90.f, 30.f);
}

void FDeckCamDrone::StepFpv(const FDeckCamInput& In, const FDeckCamTuning& T, float Dt)
{
	const float K = In.bFine ? 0.3f : 1.f;

	// Rates in body space. Stick forward = nose down (that is how a quad goes forward).
	const FVector RateTarget(
		Shape(In.Roll, T.Expo) * K * T.FpvRate,
		-Shape(In.Pitch, T.Expo) * K * T.FpvRate,
		Shape(In.Yaw, T.Expo) * K * T.FpvRate);
	BodyRates += (RateTarget - BodyRates) * Lag(Dt, 0.06f);

	const FQuat Delta(FRotator(BodyRates.Y * Dt, BodyRates.Z * Dt, BodyRates.X * Dt));
	Body = (Body * Delta).GetNormalized();

	// Scale the whole physics with the speed preset: a 30 m/s preset flies like a real quad
	// in a 3x bigger world, so the feel stays the same while covering aircraft distances.
	const float Scale = T.Speed / 1000.f;
	const float G = 980.f * Scale;

	// Gamepad sticks are centered, so center = hover, up = up to 3 g, down = 0.
	const float Th = FMath::Clamp(In.Throttle, -1.f, 1.f);
	const float Thrust = Th >= 0.f ? G * (1.f + 2.f * Th) : G * (1.f + Th);

	const float Drag = 0.98f; // 1/s: terminal speed at ~45 deg tilt and full thrust is ~2x the preset
	const FVector Acc = Body.GetUpVector() * Thrust - FVector(0.f, 0.f, G) - Velocity * Drag;
	Velocity += Acc * Dt;
	Position += Velocity * Dt;
}

FTransform FDeckCamDrone::GetCameraTransform(const FDeckCamTuning& T) const
{
	if (Mode == EDeckCamMode::Cine)
	{
		return FTransform(FRotator(GimbalPitch, Yaw, 0.f), Position);
	}
	return FTransform((Body * UptiltQuat(T.FpvCameraTilt)).GetNormalized(), Position);
}

void FDeckCamDrone::SwitchMode(EDeckCamMode NewMode, const FDeckCamTuning& T)
{
	if (NewMode == Mode)
	{
		return;
	}
	const FTransform Cam = GetCameraTransform(T);
	Mode = NewMode;
	if (Mode == EDeckCamMode::Fpv)
	{
		// Start level. Keeping the camera exactly would pitch the body nose-down by the uptilt,
		// and the quad would surge forward the moment the mode switches.
		Body = FQuat(FRotator(0.f, Cam.Rotator().Yaw, 0.f));
		BodyRates = FVector::ZeroVector;
	}
	else
	{
		const FRotator R = Cam.Rotator();
		Yaw = R.Yaw;
		GimbalPitch = FMath::Clamp(R.Pitch, -90.f, 30.f);
		YawRateNow = 0.f;
		TiltRateNow = 0.f;
	}
}

void FDeckCamDrone::Level()
{
	Velocity = FVector::ZeroVector;
	YawRateNow = 0.f;
	TiltRateNow = 0.f;
	BodyRates = FVector::ZeroVector;
	if (Mode == EDeckCamMode::Cine)
	{
		GimbalPitch = 0.f;
	}
	else
	{
		Body = FQuat(FRotator(0.f, Body.Rotator().Yaw, 0.f));
	}
}
