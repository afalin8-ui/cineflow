using UnrealBuildTool;

public class DeckCam : ModuleRules
{
	public DeckCam(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core",
			"CoreUObject",
			"Engine",
			"DeveloperSettings",
		});

		PrivateDependencyModuleNames.AddRange(new string[]
		{
			"UnrealEd",
			"EditorSubsystem",
			"Slate",
			"SlateCore",
			"ToolMenus",
			"LevelEditor",
			"Projects",
			"Sockets",
			"Networking",
			"Json",
			"ImageWrapper",
			"RenderCore",
			"RHI",
			"CinematicCamera",
			"MovieScene",
			"LevelSequence",
			"LevelSequenceEditor",
			"Sequencer",
			"TakesCore",
			"TakeRecorder",
			"TakeRecorderSources",
		});
	}
}
