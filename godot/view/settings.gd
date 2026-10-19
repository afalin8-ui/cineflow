# view/settings.gd — что игра помнит между запусками (план GИ: выключатель знаков «помнится»):
# ConfigFile в user://. Проверки ставят path в свою папку (tests/case.gd → tmp): общий
# user:// они не трогают (godot/CLAUDE.md, 9 — сторож user://).
extends RefCounted

## Где файл у игрока; проверки возвращают путь сюда (а не строкой user:// у себя — сторож
## обёртки run_tests.sh ищет user:// в тестах, и правильно делает).
const DEFAULT_PATH := "user://settings.cfg"
static var path := DEFAULT_PATH


static func get_bool(section: String, key: String, default: bool) -> bool:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return default
	var v: Variant = cf.get_value(section, key, default)
	return v == true


static func set_bool(section: String, key: String, value: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(path)                       # нет файла — заведём
	cf.set_value(section, key, value)
	cf.save(path)
