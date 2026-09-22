#include "DeckCamSettings.h"

UDeckCamSettings::UDeckCamSettings()
{
	// 0.5, 1, 3, 10, 30, 100, 300 m/s. Aircraft move at 50-250 m/s, so the top presets are for chasing them.
	SpeedPresets = { 50.f, 100.f, 300.f, 1000.f, 3000.f, 10000.f, 30000.f };
}
