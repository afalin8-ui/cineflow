# main.gd — вход в игру. В выгруженной сборке `-s` нет (собрана с
# disable_path_overrides), поэтому режимы — аргументами ГЛАВНОЙ сцены
# после «--» (архитектура, 8.6; 10.1):
#   capella.x86_64 -- --selftest        проверка сборки: данные грузятся, числа сходятся; код 0/1
#   capella.x86_64 -- --set путь=число  правка числа (одно на прогон), --overrides=файл — набор
# Без режима — окно: в G0a заглушка «космос» и счётчик кадров по F3.
extends Node

const Defs := preload("res://sim/defs.gd")
const SpaceStub := preload("res://view/space_stub.gd")
const FpsCounter := preload("res://ui/fps_counter.gd")

var defs: Defs
var view: SpaceStub
var fps: FpsCounter


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var ov: Dictionary = Defs.overrides_from_args(args)
	var ov_errors: PackedStringArray = ov["errors"]
	var ov_values: Dictionary = ov["overrides"]
	defs = Defs.load_default(ov_values) as Defs
	defs.errors.append_array(ov_errors)
	defs.ok = defs.errors.is_empty()
	if "--selftest" in args:
		_selftest()
		return
	if not defs.ok:
		_show_errors()
		return
	view = SpaceStub.new()
	add_child(view)
	view.setup(defs.doctrine)
	fps = FpsCounter.new()
	add_child(fps)
	print("Капелла: отрисовщик %s · %s, видеокарта %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()


## Отказ данных — словами на экране и в stderr: молча бой не начинаем.
func _show_errors() -> void:
	for e in defs.errors:
		printerr("ДАННЫЕ: ", e)
	var layer := CanvasLayer.new()
	var lab := Label.new()
	lab.text = "Игра не запустилась: данные боя с ошибкой.\n\n" + "\n".join(defs.errors.slice(0, 20))
	lab.position = Vector2(24, 24)
	lab.add_theme_font_size_override("font_size", 16)
	layer.add_child(lab)
	add_child(layer)


## --selftest: то, что выгруженная сборка обязана уметь сама (CI запускает обе).
func _selftest() -> void:
	var fails: PackedStringArray = []
	if not defs.ok:
		fails.append_array(defs.errors)
	else:
		if defs.faction_ids.size() != 4:
			fails.append("кланов %d, а не 4" % defs.faction_ids.size())
		var cr := defs.ship(&"troyden", &"cruiser")
		if cr == null or cr.sec == null:
			fails.append("у крейсера Тройдена нет батареи")
		else:
			var dps := snappedf(cr.sec.mounts * cr.sec.dmg / cr.sec.cd, 0.1)
			if absf(dps - 23.1) > 1e-6:
				fails.append("батарея крейсера Тройдена %.1f урона в секунду, а не 23,1" % dps)
	var line := "SELFTEST %s: данные %s, правок %d, отрисовщик %s, ОС %s, сборка %s" % [
		"ok" if fails.is_empty() else "ПРОВАЛ", defs.fingerprint, defs.overrides_applied.size(),
		RenderingServer.get_current_rendering_method(), OS.get_name(), "выгружена" if OS.has_feature("template") else "редактор"]
	print(line)
	printerr(line)
	for f in fails:
		printerr("  ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
