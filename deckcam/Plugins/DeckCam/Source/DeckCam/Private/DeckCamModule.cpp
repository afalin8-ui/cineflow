#include "DeckCamSubsystem.h"

#include "Editor.h"
#include "HAL/IConsoleManager.h"
#include "Modules/ModuleManager.h"
#include "ToolMenus.h"

#define LOCTEXT_NAMESPACE "DeckCam"

namespace
{
	UDeckCamSubsystem* GetDeckCam()
	{
		return GEditor ? GEditor->GetEditorSubsystem<UDeckCamSubsystem>() : nullptr;
	}
}

class FDeckCamModule : public IModuleInterface
{
public:
	virtual void StartupModule() override
	{
		UToolMenus::RegisterStartupCallback(FSimpleMulticastDelegate::FDelegate::CreateRaw(this, &FDeckCamModule::RegisterMenus));
	}

	virtual void ShutdownModule() override
	{
		UToolMenus::UnRegisterStartupCallback(this);
		UToolMenus::UnregisterOwner(this);
	}

private:
	void RegisterMenus()
	{
		FToolMenuOwnerScoped Owner(this);
		UToolMenu* Menu = UToolMenus::Get()->ExtendMenu("LevelEditor.MainMenu.Tools");
		FToolMenuSection& Section = Menu->FindOrAddSection("DeckCam", LOCTEXT("Section", "DeckCam"));
		Section.AddMenuEntry(
			"DeckCamToggle",
			LOCTEXT("Toggle", "DeckCam: Steam Deck camera"),
			LOCTEXT("ToggleTip", "Start or stop the Steam Deck controller server"),
			FSlateIcon(),
			FUIAction(
				FExecuteAction::CreateLambda([]()
				{
					if (UDeckCamSubsystem* D = GetDeckCam())
					{
						D->IsRunning() ? D->Stop() : D->Start();
					}
				}),
				FCanExecuteAction(),
				FIsActionChecked::CreateLambda([]()
				{
					const UDeckCamSubsystem* D = GetDeckCam();
					return D && D->IsRunning();
				})),
			EUserInterfaceActionType::ToggleButton);
	}
};

static FAutoConsoleCommand GDeckCamStart(
	TEXT("DeckCam.Start"), TEXT("Start the Steam Deck camera controller"),
	FConsoleCommandDelegate::CreateLambda([]() { if (UDeckCamSubsystem* D = GetDeckCam()) { D->Start(); } }));

static FAutoConsoleCommand GDeckCamStop(
	TEXT("DeckCam.Stop"), TEXT("Stop the Steam Deck camera controller"),
	FConsoleCommandDelegate::CreateLambda([]() { if (UDeckCamSubsystem* D = GetDeckCam()) { D->Stop(); } }));

#undef LOCTEXT_NAMESPACE

IMPLEMENT_MODULE(FDeckCamModule, DeckCam)
