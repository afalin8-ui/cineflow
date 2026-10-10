# main.gd — вход в игру. В выгруженной сборке `-s` нет (собрана с
# disable_path_overrides), поэтому режимы — аргументами ГЛАВНОЙ сцены
# после «--» (архитектура, 8.6; 10.1):
#   capella.x86_64 -- --selftest        проверка сборки: данные грузятся, числа сходятся; код 0/1
#   capella.x86_64 -- --set путь=число  правка числа (одно на прогон), --overrides=файл — набор
#                                       (относительный путь — от папки запуска, см. launch_dirs)
#   capella.x86_64 -- --bench-render    минута замера кадров на «Столе» и выход; итог — в вывод,
#                                       файл с каждым кадром — рядом с программой (план G0, п. 7);
#                                       --bench-seconds=N — короче, --bench-out=ПАПКА — куда файл
#   capella.x86_64 -- --ship-models=ФАЙЛ обмер моделей из другого файла (проверки громкого
#                                       отказа: пропал файл моделей или одна .glb)
# Беда в данных или в моделях — текст на экране и в stderr, «Стол» и замер не
# начинаются; в режимах --selftest и --bench-render — ещё и код выхода 1.
# Без режима — окно «Стол» (G0b): 83 корабля «Генерального», авиация, огонь-заглушка;
# F3 — счётчик кадров, F5 — минута замера, F11 — окно / полный экран.
extends Node

const Defs := preload("res://sim/defs.gd")
const Showcase := preload("res://tools/showcase.gd")
const FpsCounter := preload("res://ui/fps_counter.gd")
const FrameBench := preload("res://ui/frame_bench.gd")
const BenchReport := preload("res://ui/bench_report.gd")
const ShipModels := preload("res://view/ship_models.gd")

var defs: Defs
var view: Showcase
var fps: FpsCounter
var bench: FrameBench
var report: BenchReport
var bench_cli := false
## Текст беды на экране (данные или модели с ошибкой) — его же читают тесты.
var error_text := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var ov: Dictionary = Defs.overrides_from_args(args, launch_dirs())
	var ov_errors: PackedStringArray = ov["errors"]
	var ov_values: Dictionary = ov["overrides"]
	defs = Defs.load_default(ov_values) as Defs
	defs.errors.append_array(ov_errors)
	defs.ok = defs.errors.is_empty()
	for a in args:
		if a.begins_with("--ship-models="):
			ShipModels.use_file(a.substr("--ship-models=".length()))
	if "--selftest" in args:
		_selftest()
		return
	if not defs.ok:
		_fail("Игра не запустилась: данные боя с ошибкой.", "ДАННЫЕ", defs.errors, args)
		return
	view = Showcase.new()
	view.name = "Showcase"
	add_child(view)
	if not view.setup(defs):
		# пустого места на «Столе» молча не бывает: замер на облегчённой сцене
		# обещал бы кадры, которых на худшем бое нет (замечание к G0b)
		var problems := view.problems
		view.free()
		view = null
		_fail("Игра не запустилась: модели кораблей с ошибкой.", "МОДЕЛИ", problems, args)
		return
	fps = FpsCounter.new()
	add_child(fps)
	report = BenchReport.new()
	add_child(report)
	bench = FrameBench.new()
	add_child(bench)
	bench.driver = view.drive
	bench.title = "Капелла %s" % release_name()
	bench.extra_line = "На столе: %d %s, %d %s; синхронизация с экраном на время замера выключена" % [
		view.ship_count(), FrameBench.plural(view.ship_count(), "корабль", "корабля", "кораблей"),
		view.craft_count(), FrameBench.plural(view.craft_count(), "машина", "машины", "машин")]
	bench.finished.connect(_bench_done)
	print("Капелла: отрисовщик %s · %s, видеокарта %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])
	for a in args:
		if a.begins_with("--bench-seconds="):
			bench.duration = maxf(a.get_slice("=", 1).to_float(), 0.5)
		elif a.begins_with("--bench-out="):
			bench.out_dir = a.substr("--bench-out=".length())
	if "--bench-render" in args:
		bench_cli = true
		# секунда на прогрев: первые кадры — загрузка, а не отрисовка
		await get_tree().create_timer(1.0).timeout
		start_bench()


## Номер сборки — первая строка godot/RELEASE (она едет в выгрузку, include_filter).
static func release_name() -> String:
	var t := FileAccess.get_file_as_string("res://RELEASE")
	var first := t.get_slice("\n", 0).strip_edges()
	return first if first != "" else "без номера"


func start_bench() -> void:
	if report != null:
		report.hide_report()
	view.rig.input_enabled = false
	fps.block_hint(true)
	bench.start()


func _process(_delta: float) -> void:
	if bench != null and bench.running and report != null:
		var avoid: Array[Rect2] = []
		if fps.panel.visible:
			avoid.append(fps.panel.get_global_rect())
		report.show_progress(bench.elapsed, bench.duration, avoid)


func _bench_done(summary: String, file: String) -> void:
	view.rig.input_enabled = true
	fps.block_hint(false)
	report.hide_progress()
	report.show_report(summary, file)
	if bench_cli:
		for l in summary.split("\n"):
			print("BENCH ", l)
		print("BENCH файл: ", file)
		get_tree().quit(0)


## Откуда искать относительный путь --overrides (архитектура, 7). Godot меняет текущую
## папку процесса: выгруженная сборка уходит в папку программы, редактор с --path —
## в папку проекта. Поэтому первой — папка, ИЗ КОТОРОЙ запустили: её отдаёт PWD
## (оболочки Linux, macOS, Git Bash); в cmd и PowerShell PWD нет — тогда путь от папки
## программы. Дальше — текущая папка процесса и, у выгруженной сборки, папка программы.
static func launch_dirs() -> PackedStringArray:
	var out := PackedStringArray()
	var pwd := OS.get_environment("PWD")
	if pwd != "" and DirAccess.dir_exists_absolute(pwd):
		out.append(pwd)
	var here := DirAccess.open(".")
	if here != null and here.get_current_dir() not in out:
		out.append(here.get_current_dir())
	var exe_dir := OS.get_executable_path().get_base_dir()
	if OS.has_feature("template") and exe_dir not in out:
		out.append(exe_dir)
	return out


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()
	elif k.physical_keycode == KEY_F5 and bench != null:
		# F5 — минута замера; F5 во время замера — прервать
		if bench.running:
			bench.cancel()
			view.rig.input_enabled = true
			fps.block_hint(false)
			report.hide_progress()
		else:
			start_bench()
		get_viewport().set_input_as_handled()


## Отказ — словами на экране и в stderr: молча «Стол» не начинаем. В режиме замера
## из командной строки — код выхода 1: замер на неполной сцене никому не нужен.
func _fail(head: String, tag: String, list: PackedStringArray, args: PackedStringArray) -> void:
	for e in list:
		printerr("%s: %s" % [tag, e])
	var layer := CanvasLayer.new()
	layer.name = "Errors"
	var lab := Label.new()
	error_text = head + "\n\n" + "\n".join(list.slice(0, 20))
	lab.text = error_text
	lab.position = Vector2(24, 24)
	lab.add_theme_font_size_override("font_size", 16)
	layer.add_child(lab)
	add_child(layer)
	if "--bench-render" in args:
		print("BENCH ОТКАЗ: ", head)
		get_tree().quit(1)


## --selftest: то, что выгруженная сборка обязана уметь сама (CI запускает обе).
func _selftest() -> void:
	var fails: PackedStringArray = []
	# модели кораблей и машин срезовых кланов доехали в сборку (обмер и .glb):
	# пропавшая модель иначе дала бы пустое место на «Столе» молча
	var roles: Array[StringName] = [&"interceptor", &"fighter", &"bomber"]
	for f: StringName in [&"troyden", &"plektor"]:
		var ids: Array[StringName] = [&"station"]
		var fd: Defs.FactionDef = defs.factions.get(f)
		if fd != null:
			ids.append_array(fd.ship_order)
		fails.append_array(ShipModels.problems(f, ids, roles))
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
