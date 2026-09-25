#include "DeckCamSubsystem.h"

#include "DeckCamServer.h"
#include "DeckCamSettings.h"
#include "DeckCamVideo.h"

#include "CineCameraActor.h"
#include "CineCameraComponent.h"
#include "Dom/JsonObject.h"
#include "Editor.h"
#include "Editor/EditorPerformanceSettings.h"
#include "EngineUtils.h"
#include "Framework/Notifications/NotificationManager.h"
#include "IPAddress.h"
#include "Interfaces/IPluginManager.h"
#include "LevelEditorViewport.h"
#include "LevelSequence.h"
#include "LevelSequenceEditorBlueprintLibrary.h"
#include "ILevelSequenceEditorToolkit.h"
#include "ISequencer.h"
#include "Subsystems/AssetEditorSubsystem.h"
#include "MovieScene.h"
#include "MovieSceneTimeHelpers.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Recorder/TakeRecorderBlueprintLibrary.h"
#include "Recorder/TakeRecorderPanel.h"
#include "Selection.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "SocketSubsystem.h"
#include "TakeRecorderActorSource.h"
#include "TakeRecorderSource.h"
#include "TakeRecorderSources.h"
#include "Widgets/Notifications/SNotificationList.h"

DEFINE_LOG_CATEGORY_STATIC(LogDeckCam, Log, All);

namespace
{
	const FName CameraTag(TEXT("DeckCam"));

	void Toast(const FString& Text, float Seconds = 8.f)
	{
		FNotificationInfo Info(FText::FromString(Text));
		Info.ExpireDuration = Seconds;
		FSlateNotificationManager::Get().AddNotification(Info);
		UE_LOG(LogDeckCam, Log, TEXT("%s"), *Text);
	}

	float Num(const TSharedPtr<FJsonObject>& J, const TCHAR* Key)
	{
		double V = 0.0;
		J->TryGetNumberField(Key, V);
		return FMath::Clamp(float(V), -1.f, 1.f);
	}
}

// ---------------------------------------------------------------------------------------------
// Lifetime

void UDeckCamSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
	if (GetDefault<UDeckCamSettings>()->bAutoStart)
	{
		Start();
	}
}

void UDeckCamSubsystem::Deinitialize()
{
	Stop();
	Super::Deinitialize();
}

TStatId UDeckCamSubsystem::GetStatId() const
{
	RETURN_QUICK_DECLARE_CYCLE_STAT(UDeckCamSubsystem, STATGROUP_Tickables);
}

void UDeckCamSubsystem::Start()
{
	if (bRunning)
	{
		return;
	}
	const UDeckCamSettings* S = GetDefault<UDeckCamSettings>();

	FString Html;
	if (TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("DeckCam")))
	{
		Html = FPaths::ConvertRelativePathToFull(FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/Web/index.html")));
	}

	Server = MakeUnique<FDeckCamServer>();
	FString Error;
	if (!Server->Start(S->Port, Html, Error))
	{
		Server.Reset();
		Toast(FString::Printf(TEXT("DeckCam: could not start (%s)"), *Error), 12.f);
		return;
	}
	Video = MakeUnique<FDeckCamVideo>();

	SpeedIndex = FMath::Clamp(S->DefaultSpeedIndex, 0, FMath::Max(0, S->SpeedPresets.Num() - 1));
	Input = FDeckCamInput();
	bSynced = false;
	bWantPilot = S->bPilotViewport;
	bRunning = true;

	if (S->bNoThrottleInBackground)
	{
		UEditorPerformanceSettings* Perf = GetMutableDefault<UEditorPerformanceSettings>();
		bSavedThrottle = Perf->bThrottleCPUWhenNotForeground;
		Perf->bThrottleCPUWhenNotForeground = false;
	}

	// Tell the user which address to open on the Deck.
	TArray<FString> Urls;
	TArray<TSharedPtr<FInternetAddr>> Addrs;
	if (ISocketSubsystem* SS = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM))
	{
		SS->GetLocalAdapterAddresses(Addrs);
	}
	for (const TSharedPtr<FInternetAddr>& A : Addrs)
	{
		if (A.IsValid() && A->GetProtocolType() == FNetworkProtocolTypes::IPv4)
		{
			const FString Ip = A->ToString(false);
			if (!Ip.StartsWith(TEXT("127.")) && !Ip.StartsWith(TEXT("169.254.")))
			{
				Urls.Add(FString::Printf(TEXT("http://%s:%d"), *Ip, S->Port));
			}
		}
	}
	Toast(FString::Printf(TEXT("DeckCam is running. Open on the Steam Deck:\n%s"),
		Urls.Num() ? *FString::Join(Urls, TEXT("\n")) : TEXT("(no network address found)")), 20.f);
}

void UDeckCamSubsystem::Stop()
{
	if (!bRunning)
	{
		return;
	}
	if (bPilot)
	{
		SetPilot(false);
	}
	Video.Reset();
	if (Server)
	{
		Server->Shutdown();
		Server.Reset();
	}
	if (GetDefault<UDeckCamSettings>()->bNoThrottleInBackground)
	{
		GetMutableDefault<UEditorPerformanceSettings>()->bThrottleCPUWhenNotForeground = bSavedThrottle;
	}
	bRunning = false;
	Toast(TEXT("DeckCam stopped"), 4.f);
}

// ---------------------------------------------------------------------------------------------
// Frame

UWorld* UDeckCamSubsystem::GetEditorWorld() const
{
	return GEditor ? GEditor->GetEditorWorldContext().World() : nullptr;
}

ACineCameraActor* UDeckCamSubsystem::EnsureCamera(UWorld* World)
{
	if (ACineCameraActor* Cam = Camera.Get())
	{
		if (Cam->GetWorld() == World && IsValid(Cam))
		{
			return Cam;
		}
	}
	bSynced = false;

	for (TActorIterator<ACineCameraActor> It(World); It; ++It)
	{
		if (It->ActorHasTag(CameraTag))
		{
			Camera = *It;
			return *It;
		}
	}

	// None yet: spawn where the viewport looks, so the first frame is the familiar view.
	FTransform Where = FTransform::Identity;
	if (FLevelEditorViewportClient* VC = GetViewport())
	{
		Where = FTransform(VC->GetViewRotation(), VC->GetViewLocation());
	}
	FActorSpawnParameters P;
	P.Name = MakeUniqueObjectName(World->PersistentLevel, ACineCameraActor::StaticClass(), TEXT("DeckCam"));
	ACineCameraActor* Cam = World->SpawnActor<ACineCameraActor>(ACineCameraActor::StaticClass(), Where, P);
	if (!Cam)
	{
		return nullptr;
	}
	Cam->SetActorLabel(TEXT("DeckCam"));
	Cam->Tags.AddUnique(CameraTag);
	Camera = Cam;
	return Cam;
}

FTransform UDeckCamSubsystem::GetFrame(ACineCameraActor* Cam, float& OutScale) const
{
	OutScale = 1.f;
	USceneComponent* Root = Cam->GetRootComponent();
	USceneComponent* Parent = Root ? Root->GetAttachParent() : nullptr;
	if (!Parent)
	{
		return FTransform::Identity;
	}
	FTransform F = Parent->GetSocketTransform(Root->GetAttachSocketName());
	// Aircraft are often imported scaled. Fly in world units regardless: remove the parent scale
	// here and divide it out when writing the relative location.
	OutScale = FMath::Max(1e-4f, float(FMath::Abs(F.GetScale3D().X)));
	F.SetScale3D(FVector::OneVector);
	return F;
}

FDeckCamTuning UDeckCamSubsystem::MakeTuning() const
{
	const UDeckCamSettings* S = GetDefault<UDeckCamSettings>();
	FDeckCamTuning T;
	T.Speed = S->SpeedPresets.IsValidIndex(SpeedIndex) ? S->SpeedPresets[SpeedIndex] : 1000.f;
	T.CineSmoothing = S->CineSmoothing;
	T.YawRate = S->YawRate;
	T.TiltRate = S->TiltRate;
	T.VerticalFactor = S->VerticalFactor;
	T.FpvRate = S->FpvRate;
	T.FpvCameraTilt = S->FpvCameraTilt;
	T.Expo = S->Expo;
	T.GyroSmoothing = S->GyroSmoothing;
	return T;
}

void UDeckCamSubsystem::Tick(float DeltaTime)
{
	if (!bRunning || !Server)
	{
		return;
	}
	const UDeckCamSettings* S = GetDefault<UDeckCamSettings>();
	const double Now = FPlatformTime::Seconds();

	PumpMessages();

	UWorld* World = GetEditorWorld();
	if (!World)
	{
		return;
	}

	// Wi-Fi dropout: stop instead of flying away with the last stick position.
	if (Now - LastInputTime > S->InputTimeout)
	{
		Input = FDeckCamInput();
	}

	ACineCameraActor* Cam = EnsureCamera(World);
	if (!Cam)
	{
		return;
	}
	if (bWantPilot && GetViewport())
	{
		bWantPilot = false;
		SetPilot(true);
	}

	// Frame of reference. If the parent changed (our attach button, or the user in the Outliner),
	// carry the velocity over so the camera does not jerk.
	float Scale = 1.f;
	const FTransform Frame = GetFrame(Cam, Scale);
	AActor* Parent = Cam->GetAttachParentActor();
	if (bSynced && Parent != LastParent.Get())
	{
		const FVector WorldVel = LastFrame.TransformVectorNoScale(Drone.Velocity);
		Drone.Velocity = Frame.InverseTransformVectorNoScale(WorldVel);
		bSynced = false;
	}
	LastParent = Parent;
	LastFrame = Frame;

	USceneComponent* Root = Cam->GetRootComponent();
	const FTransform Local = Parent
		? FTransform(Root->GetRelativeRotation(), Root->GetRelativeLocation() * Scale)
		: FTransform(Cam->GetActorRotation(), Cam->GetActorLocation());

	const FDeckCamTuning T = MakeTuning();

	// Gyro turn since the last frame: hand it to the drone once, then forget it.
	if (Input.GyroYaw != 0.f || Input.GyroPitch != 0.f)
	{
		Drone.AddLook(Input.GyroYaw, Input.GyroPitch);
		Input.GyroYaw = 0.f;
		Input.GyroPitch = 0.f;
	}

	// Someone moved the camera by hand (gizmo, piloted viewport, undo): take their pose, keep flying.
	const bool bMovedByHand = !Local.GetLocation().Equals(LastWritten.GetLocation(), 0.5f)
		|| !Local.GetRotation().Equals(LastWritten.GetRotation(), 1e-3f);
	if (!bSynced || bMovedByHand)
	{
		Drone.SetPose(Local, T);
		bSynced = true;
	}

	// Fixed substeps: the flight feels the same at 30 and at 120 editor fps.
	const float Dt = FMath::Min(DeltaTime, 0.1f);
	const int32 Steps = FMath::Clamp(FMath::CeilToInt(Dt * 240.f), 1, 48);
	for (int32 i = 0; i < Steps; ++i)
	{
		Drone.Step(Input, T, Dt / Steps);
	}

	const FTransform Out = Drone.GetCameraTransform(T);
	if (Parent)
	{
		Root->SetRelativeLocationAndRotation(Out.GetLocation() / Scale, Out.GetRotation());
	}
	else
	{
		Cam->SetActorLocationAndRotation(Out.GetLocation(), Out.GetRotation());
	}
	LastWritten = Out;

	// Zoom: exponential, so it feels even from 18 to 300 mm.
	UCineCameraComponent* CC = Cam->GetCineCameraComponent();
	if (CC && FMath::Abs(Input.Zoom) > 0.01f)
	{
		const float K = Input.bFine ? 0.3f : 1.f;
		float F = CC->CurrentFocalLength * FMath::Exp(Input.Zoom * S->ZoomRate * K * Dt);
		F = FMath::Clamp(F, CC->LensSettings.MinFocalLength, CC->LensSettings.MaxFocalLength);
		CC->SetCurrentFocalLength(F);
	}

	if (Video)
	{
		Video->Tick(World, CC, *Server, *S);
	}

	const bool bRec = UTakeRecorderBlueprintLibrary::IsRecording();
	if (bRec && !bWasRecording)
	{
		RecordStart = Now;
		Notify(TEXT("rec_start"));
	}
	else if (!bRec && bWasRecording)
	{
		Notify(TEXT("rec_stop"));
	}
	bWasRecording = bRec;

	if (Now >= NextStatus)
	{
		NextStatus = Now + 0.1;
		SendStatus();
	}
}

// ---------------------------------------------------------------------------------------------
// Messages from the Deck

void UDeckCamSubsystem::PumpMessages()
{
	FString Msg;
	while (Server && Server->PopMessage(Msg))
	{
		TSharedPtr<FJsonObject> J;
		TSharedRef<TJsonReader<>> R = TJsonReaderFactory<>::Create(Msg);
		if (!FJsonSerializer::Deserialize(R, J) || !J.IsValid())
		{
			continue;
		}
		FString Type;
		J->TryGetStringField(TEXT("t"), Type);
		if (Type == TEXT("in"))
		{
			ApplyInput(J);
		}
		else if (Type == TEXT("cmd"))
		{
			FString Cmd;
			J->TryGetStringField(TEXT("c"), Cmd);
			HandleCommand(Cmd);
		}
		else if (Type == TEXT("hello"))
		{
			if (UWorld* World = GetEditorWorld())
			{
				RefreshTargets(World);
			}
			SendStatus();
		}
	}
}

void UDeckCamSubsystem::ApplyInput(const TSharedPtr<FJsonObject>& J)
{
	Input.Throttle = Num(J, TEXT("th"));
	Input.Yaw = Num(J, TEXT("yw"));
	Input.Pitch = Num(J, TEXT("pt"));
	Input.Roll = Num(J, TEXT("rl"));
	Input.Tilt = Num(J, TEXT("tl"));
	Input.Zoom = Num(J, TEXT("zm"));
	Input.bFine = Num(J, TEXT("fn")) > 0.5f;

	// Gyro arrives as mouse pixels since the previous message. Summed, because several
	// messages can land between two editor frames and every one of them is a real turn.
	double GX = 0.0, GY = 0.0;
	J->TryGetNumberField(TEXT("gx"), GX);
	J->TryGetNumberField(TEXT("gy"), GY);
	const UDeckCamSettings* S = GetDefault<UDeckCamSettings>();
	if (S->bGyro)
	{
		const float K = S->GyroDegreesPerPixel;
		Input.GyroYaw += float(FMath::Clamp(GX, -2000.0, 2000.0)) * K * (S->bGyroInvertX ? -1.f : 1.f);
		// Mouse down (+Y) = Deck tilted forward = look down.
		Input.GyroPitch += -float(FMath::Clamp(GY, -2000.0, 2000.0)) * K * (S->bGyroInvertY ? -1.f : 1.f);
	}
	LastInputTime = FPlatformTime::Seconds();
}

void UDeckCamSubsystem::HandleCommand(const FString& Cmd)
{
	const UDeckCamSettings* S = GetDefault<UDeckCamSettings>();
	const int32 NumSpeeds = S->SpeedPresets.Num();

	if (Cmd == TEXT("rec"))
	{
		ToggleRecord();
	}
	else if (Cmd == TEXT("spd+") && NumSpeeds > 0)
	{
		SpeedIndex = FMath::Min(SpeedIndex + 1, NumSpeeds - 1);
	}
	else if (Cmd == TEXT("spd-") && NumSpeeds > 0)
	{
		SpeedIndex = FMath::Max(SpeedIndex - 1, 0);
	}
	else if (Cmd == TEXT("mode"))
	{
		const EDeckCamMode Next = Drone.Mode == EDeckCamMode::Cine ? EDeckCamMode::Fpv : EDeckCamMode::Cine;
		Drone.SwitchMode(Next, MakeTuning());
		Notify(Next == EDeckCamMode::Cine ? TEXT("mode_cine") : TEXT("mode_fpv"));
	}
	else if (Cmd == TEXT("level"))
	{
		Drone.Level();
	}
	else if (Cmd == TEXT("attach"))
	{
		ToggleAttach();
	}
	else if (Cmd == TEXT("tgt+"))
	{
		CycleTarget(1);
	}
	else if (Cmd == TEXT("tgt-"))
	{
		CycleTarget(-1);
	}
	else if (Cmd == TEXT("play"))
	{
		TogglePlay();
	}
	else if (Cmd == TEXT("rewind"))
	{
		Rewind();
	}
	else if (Cmd == TEXT("pilot"))
	{
		SetPilot(!bPilot);
		Notify(bPilot ? TEXT("pilot_on") : TEXT("pilot_off"));
	}
	SendStatus();
}

// ---------------------------------------------------------------------------------------------
// Actions

void UDeckCamSubsystem::ToggleRecord()
{
	if (UTakeRecorderBlueprintLibrary::IsRecording())
	{
		UTakeRecorderBlueprintLibrary::StopRecording();
		return;
	}

	ACineCameraActor* Cam = Camera.Get();
	if (!Cam)
	{
		return;
	}

	UTakeRecorderPanel* Panel = UTakeRecorderBlueprintLibrary::GetTakeRecorderPanel();
	if (!Panel)
	{
		Panel = UTakeRecorderBlueprintLibrary::OpenTakeRecorderPanel();
	}
	if (!Panel)
	{
		Notify(TEXT("rec_no_panel"));
		return;
	}

	UTakeRecorderSources* Sources = Panel->GetSources();
	if (!Sources)
	{
		Notify(TEXT("rec_no_panel"));
		return;
	}

	bool bHasCamera = false;
	bool bHasSequence = false;
	for (UTakeRecorderSource* Source : Sources->GetSources())
	{
		if (const UTakeRecorderActorSource* A = Cast<UTakeRecorderActorSource>(Source))
		{
			bHasCamera |= A->Target.Get() == Cam;
		}
		// Matched by name: the Level Sequence source class is not exported by the engine.
		if (Source && Source->GetClass()->GetName().Contains(TEXT("LevelSequenceSource")))
		{
			bHasSequence = true;
		}
	}
	if (!bHasCamera)
	{
		UTakeRecorderActorSource::AddSourceForActor(Cam, Sources);
	}
	if (!bHasSequence)
	{
		Notify(TEXT("rec_no_seq")); // still record: maybe the aircraft are driven another way
	}

	FText Why;
	if (!Panel->CanStartRecording(Why))
	{
		Notify(TEXT("rec_err"), Why.ToString());
		return;
	}
	Panel->StartRecording();
}

void UDeckCamSubsystem::RefreshTargets(UWorld* World)
{
	const FName Tag = GetDefault<UDeckCamSettings>()->TargetTag;
	ACineCameraActor* Cam = Camera.Get();
	const TWeakObjectPtr<AActor> Current = Targets.IsValidIndex(TargetIndex) ? Targets[TargetIndex] : TWeakObjectPtr<AActor>();

	Targets.Reset();
	for (TActorIterator<AActor> It(World); It; ++It)
	{
		if (*It != Cam && It->ActorHasTag(Tag))
		{
			Targets.Add(*It);
		}
	}
	if (Targets.Num() == 0 && GEditor)
	{
		for (FSelectionIterator It(GEditor->GetSelectedActorIterator()); It; ++It)
		{
			AActor* A = Cast<AActor>(*It);
			if (A && A != Cam)
			{
				Targets.Add(A);
			}
		}
	}
	Targets.Sort([](const TWeakObjectPtr<AActor>& A, const TWeakObjectPtr<AActor>& B)
	{
		return A->GetActorLabel() < B->GetActorLabel();
	});

	const int32 Keep = Targets.IndexOfByKey(Current);
	TargetIndex = Keep != INDEX_NONE ? Keep : FMath::Clamp(TargetIndex, 0, FMath::Max(0, Targets.Num() - 1));
}

void UDeckCamSubsystem::CycleTarget(int32 Dir)
{
	if (UWorld* World = GetEditorWorld())
	{
		RefreshTargets(World);
	}
	if (Targets.Num() == 0)
	{
		Notify(TEXT("no_target"));
		return;
	}
	TargetIndex = (TargetIndex + Dir + Targets.Num()) % Targets.Num();
}

void UDeckCamSubsystem::ToggleAttach()
{
	ACineCameraActor* Cam = Camera.Get();
	if (!Cam)
	{
		return;
	}
	if (AActor* Parent = Cam->GetAttachParentActor())
	{
		const FString Name = Parent->GetActorLabel();
		Cam->DetachFromActor(FDetachmentTransformRules::KeepWorldTransform);
		Notify(TEXT("detached"), Name);
		return;
	}

	if (UWorld* World = GetEditorWorld())
	{
		RefreshTargets(World);
	}
	AActor* Target = Targets.IsValidIndex(TargetIndex) ? Targets[TargetIndex].Get() : nullptr;
	if (!Target)
	{
		Notify(TEXT("no_target"));
		return;
	}
	// Keep world transform: the camera stays where it is and from now on rides with the target.
	Cam->AttachToActor(Target, FAttachmentTransformRules::KeepWorldTransform);
	Notify(TEXT("attached"), Target->GetActorLabel());
}

void UDeckCamSubsystem::TogglePlay()
{
	if (!ULevelSequenceEditorBlueprintLibrary::GetCurrentLevelSequence())
	{
		Notify(TEXT("no_seq_open"));
		return;
	}
	if (ULevelSequenceEditorBlueprintLibrary::IsPlaying())
	{
		ULevelSequenceEditorBlueprintLibrary::Pause();
	}
	else
	{
		ULevelSequenceEditorBlueprintLibrary::Play();
	}
}

void UDeckCamSubsystem::Rewind()
{
	ULevelSequence* Seq = ULevelSequenceEditorBlueprintLibrary::GetCurrentLevelSequence();
	UMovieScene* MS = Seq ? Seq->GetMovieScene() : nullptr;
	if (!MS)
	{
		Notify(TEXT("no_seq_open"));
		return;
	}
	UAssetEditorSubsystem* Editors = GEditor ? GEditor->GetEditorSubsystem<UAssetEditorSubsystem>() : nullptr;
	IAssetEditorInstance* Editor = Editors ? Editors->FindEditorForAsset(Seq, false) : nullptr;
	ILevelSequenceEditorToolkit* Toolkit = static_cast<ILevelSequenceEditorToolkit*>(Editor);
	TSharedPtr<ISequencer> Sequencer = Toolkit ? Toolkit->GetSequencer() : nullptr;
	if (!Sequencer.IsValid())
	{
		Notify(TEXT("no_seq_open"));
		return;
	}
	// Global time is in the root sequence's tick resolution, same units as its playback range.
	const FFrameNumber StartTick = UE::MovieScene::DiscreteInclusiveLower(MS->GetPlaybackRange());
	Sequencer->Pause();
	Sequencer->SetGlobalTime(FFrameTime(StartTick));
}

FLevelEditorViewportClient* UDeckCamSubsystem::GetViewport() const
{
	if (GCurrentLevelEditingViewportClient && GCurrentLevelEditingViewportClient->IsPerspective())
	{
		return GCurrentLevelEditingViewportClient;
	}
	if (GEditor)
	{
		for (FLevelEditorViewportClient* VC : GEditor->GetLevelViewportClients())
		{
			if (VC && VC->IsPerspective())
			{
				return VC;
			}
		}
	}
	return nullptr;
}

void UDeckCamSubsystem::SetPilot(bool bOn)
{
	FLevelEditorViewportClient* VC = GetViewport();
	if (!VC)
	{
		return;
	}
	if (bOn && Camera.IsValid())
	{
		VC->SetActorLock(Camera.Get());
		VC->SetRealtime(true);
		bPilot = true;
	}
	else
	{
		VC->SetActorLock(nullptr);
		bPilot = false;
	}
	VC->Invalidate();
}

// ---------------------------------------------------------------------------------------------
// Status back to the Deck

void UDeckCamSubsystem::SendStatus()
{
	if (!Server)
	{
		return;
	}
	const UDeckCamSettings* S = GetDefault<UDeckCamSettings>();
	ACineCameraActor* Cam = Camera.Get();
	UCineCameraComponent* CC = Cam ? Cam->GetCineCameraComponent() : nullptr;
	AActor* Parent = Cam ? Cam->GetAttachParentActor() : nullptr;
	AActor* Target = Targets.IsValidIndex(TargetIndex) ? Targets[TargetIndex].Get() : nullptr;
	const bool bRec = UTakeRecorderBlueprintLibrary::IsRecording();

	TSharedRef<FJsonObject> J = MakeShared<FJsonObject>();
	J->SetStringField(TEXT("t"), TEXT("st"));
	J->SetStringField(TEXT("mode"), Drone.Mode == EDeckCamMode::Cine ? TEXT("cine") : TEXT("fpv"));
	J->SetNumberField(TEXT("spd"), MakeTuning().Speed / 100.0);
	J->SetNumberField(TEXT("si"), SpeedIndex);
	J->SetNumberField(TEXT("sn"), S->SpeedPresets.Num());
	J->SetNumberField(TEXT("foc"), CC ? CC->CurrentFocalLength : 0.0);
	J->SetNumberField(TEXT("tilt"), Drone.Mode == EDeckCamMode::Cine ? Drone.GimbalPitch : S->FpvCameraTilt);
	J->SetNumberField(TEXT("vel"), Drone.Velocity.Size() / 100.0);
	J->SetBoolField(TEXT("rec"), bRec);
	J->SetNumberField(TEXT("rt"), bRec ? FPlatformTime::Seconds() - RecordStart : 0.0);
	J->SetStringField(TEXT("tgt"), Target ? Target->GetActorLabel() : FString());
	J->SetNumberField(TEXT("tn"), Targets.Num());
	J->SetNumberField(TEXT("ti"), TargetIndex);
	J->SetStringField(TEXT("att"), Parent ? Parent->GetActorLabel() : FString());
	J->SetBoolField(TEXT("seq"), ULevelSequenceEditorBlueprintLibrary::GetCurrentLevelSequence() != nullptr);
	J->SetBoolField(TEXT("play"), ULevelSequenceEditorBlueprintLibrary::IsPlaying());
	J->SetBoolField(TEXT("pilot"), bPilot);
	J->SetBoolField(TEXT("video"), S->bVideo);
	J->SetNumberField(TEXT("vfps"), Video ? Video->GetFps() : 0.0);

	FString Out;
	TSharedRef<TJsonWriter<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>> W = TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Out);
	FJsonSerializer::Serialize(J, W);
	Server->BroadcastText(Out);
}

void UDeckCamSubsystem::Notify(const FString& Code, const FString& Text)
{
	UE_LOG(LogDeckCam, Log, TEXT("%s %s"), *Code, *Text);
	if (!Server)
	{
		return;
	}
	TSharedRef<FJsonObject> J = MakeShared<FJsonObject>();
	J->SetStringField(TEXT("t"), TEXT("msg"));
	J->SetStringField(TEXT("code"), Code);
	J->SetStringField(TEXT("text"), Text);
	FString Out;
	TSharedRef<TJsonWriter<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>> W = TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Out);
	FJsonSerializer::Serialize(J, W);
	Server->BroadcastText(Out);
}
