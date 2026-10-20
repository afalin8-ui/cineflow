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
#   capella.x86_64 -- --table           сразу «Стол» (без замера)
#   capella.x86_64 -- --polygon         сразу лаборатория «Бой линий» (G4; проверки и разработчик)
#   capella.x86_64 -- --quick, --watch  сразу «Быстрый бой» с выбором меню по умолчанию —
#                                       играть или смотреть «ИИ против ИИ» (проверка с окном)
#   capella.x86_64 -- --make-replay=ФАЙЛ показательный бой «Полигона» БЕЗ вида → запись боя
#                                       (зерно + журнал команд + отпечаток на последнем шаге)
#   capella.x86_64 -- --replay=ФАЙЛ     проиграть запись боя на «Полигоне»; --replay-check —
#                                       сверить отпечаток на последнем шаге и выйти (код 0/1).
#                                       Частоту кадров задаёт --fixed-fps движка: бой с видом
#                                       на любой частоте и без вида обязан совпасть до бита
#   capella.x86_64 -- --old-ecm         «Бой линий» с помехами по-старому (откат 09, 1.7: главный
#                                       калибр под куполом бьёт только ближе lockRange)
#   capella.x86_64 -- --old-camera      камера JS-версии (обзор 52°, наклон 0,52 рад, старт 1100) —
#                                       откат проверок картинки М14 (план G8 и GЭ), не стенда
#   capella.x86_64 -- --bench …         стенд «бой без отрисовки» (tools/bench_core.gd): строка
#                                       JSON на бой, --load battle|skirmish|lines|brake|clear,
#                                       --n, --seed, --swap, флажки отката 09, 8.4 (--legacy-approach,
#                                       --no-share-close, --no-foe-brake, --clear-055, --ecm-01L); код 0/1
# Беда в данных или в моделях — текст на экране и в stderr, сцена и замер не
# начинаются; в режимах --selftest, --bench-render и --replay-check — ещё и код выхода 1.
# Без режима — меню «Быстрый бой» (G5): клан, противник, масштаб, сложность, «В бой» или
# «Смотреть: ИИ против ИИ»; бой кончается карточкой итога («Ещё раз», «В меню»). «Стол» (G0b) —
# по F6 из меню или F5 (минута замера кадров на нём); F3 — счётчик кадров, F8 — бой заново,
# F9 — запись боя, F11 — окно / полный экран.
extends Node

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Showcase := preload("res://tools/showcase.gd")
const Polygon := preload("res://tools/polygon.gd")
const FpsCounter := preload("res://ui/fps_counter.gd")
const CameraRig := preload("res://view/camera_rig.gd")
const FrameBench := preload("res://ui/frame_bench.gd")
const BenchReport := preload("res://ui/bench_report.gd")
const ShipModels := preload("res://view/ship_models.gd")
const BenchCore := preload("res://tools/bench_core.gd")
const QuickMenu := preload("res://ui/quick_menu.gd")
const SpaceEnv := preload("res://view/space_env.gd")
const PolygonHud := preload("res://ui/polygon_hud.gd")
## ТОЛЬКО для проверки отката: F4 (отладка пояса) не слушается.
static var rollback_no_f4 := false

const HINT_TABLE := "F3 — счётчик кадров · F5 — минута замера кадров · F6 — %s · F11 — окно / полный экран\nкамера: колесо — ближе и дальше, Q/E или правая кнопка — повернуть, стрелки и край экрана — сдвинуть"
const HINT_MENU := "F3 — счётчик кадров · F5 — замер кадров на «Столе» · F6 — «Стол» · F11 — окно / полный экран"
## Подсказка быстрого боя — узким столбиком слева над ростером (план GИ): широкая в две строки
## на 1366 ложилась на свои корабли у нижнего края, а приказы теперь на кнопках.
const HINT_BATTLE := "F3 — счётчик кадров · F8 — заново\nF9 — запись боя · F11 — полный экран\nколесо — ближе и дальше · Q/E — повернуть\nстрелки и край экрана — сдвинуть"
const HINT_POLYGON := "F3 — счётчик кадров · F5 — замер на «Столе»\nF6 — «Стол» · F8 — заново · F9 — запись боя\nF11 — полный экран · колесо — ближе и дальше\nQ/E — повернуть · стрелки и край — сдвинуть"

## --selftest: столько шагов «ИИ против ИИ» (60 с) — успевают первые тики обоих ИИ, общая цель,
## пуски звеньев и первые попадания.
const AI_SELFTEST_STEPS := 1800

## Только для проверок: с чего начать, если аргументов нет (&"table" — «Стол», &"polygon» —
## лаборатория «Бой линий»; пусто — меню «Быстрый бой»).
static var boot := &""
## Только для проверок: куда класть отчёт и запись быстрого боя (пусто — рядом с программой,
## как у замера кадров) и зерно боя (−1 — от часов).
static var out_override := ""
static var seed_override := -1

var defs: Defs
## «Стол» (tools/showcase.gd) — когда открыт.
var view: Showcase
## «Полигон» (tools/polygon.gd) — когда открыт.
var polygon: Polygon
var mode := &""
## Меню «Быстрый бой» (ui/quick_menu.gd) и звёздное небо за ним — когда открыто.
var menu: QuickMenu
var menu_back: Node3D
## Последний выбор меню: «Ещё раз» и F8 начинают тот же бой с новым зерном, меню открывается
## с ним же.
var last_cfg: Dictionary = {}
## Откуда открыт «Стол» — туда же F6 возвращает (&"menu" или &"polygon").
var table_from := &"menu"
var fps: FpsCounter
var bench: FrameBench
var report: BenchReport
var bench_cli := false
var replay_check := false
## Текст беды на экране (данные или модели с ошибкой) — его же читают тесты.
var error_text := ""
## Последняя запись боя по F9 — путь к файлу (тесты читают его).
var last_record := ""
## Запись F9 — ещё и в буфер обмена (её вставляют в чат). false — ТОЛЬКО откат
## проверки tests/test_render_polygon.gd.
var record_to_clipboard := true


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
	if "--bench" in args:
		# стенд (архитектура, 8.6): в выгруженной сборке -s нет — дверь главной сцены
		get_tree().quit(BenchCore.main(defs, args, release_name()))
		return
	if not defs.ok:
		_fail("Игра не запустилась: данные боя с ошибкой.", "ДАННЫЕ", defs.errors, args)
		return
	apply_flags(args)
	for a in args:
		if a.begins_with("--make-replay="):
			_make_replay(a.substr("--make-replay=".length()))
			return
	var rec: Dictionary = {}
	replay_check = "--replay-check" in args
	for a in args:
		if a.begins_with("--replay="):
			var why := PackedStringArray()
			rec = read_record(a.substr("--replay=".length()), launch_dirs(), why)
			if rec.is_empty():
				_fail("Запись боя не открылась.", "ПОВТОР", why, args)
				return
	bench_cli = "--bench-render" in args
	var ok := false
	if bench_cli or "--table" in args or boot == &"table":
		ok = open_table()
	elif not rec.is_empty() or "--polygon" in args or boot == &"polygon":
		ok = open_polygon(rec)
	elif "--quick" in args or "--watch" in args:
		ok = open_battle(QuickMenu.default_cfg(defs, "--watch" in args))
	else:
		ok = open_menu()
	if not ok:
		return
	print("Капелла: отрисовщик %s · %s, видеокарта %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])
	for a in args:
		if a.begins_with("--bench-seconds="):
			bench.duration = maxf(a.get_slice("=", 1).to_float(), 0.5)
		elif a.begins_with("--bench-out="):
			bench.out_dir = a.substr("--bench-out=".length())
	if bench_cli:
		# секунда на прогрев: первые кадры — загрузка, а не отрисовка
		await get_tree().create_timer(1.0).timeout
		start_bench()


## Счётчик кадров, замер и его итог — одни на оба экрана; заводятся, когда первый
## экран открылся (с бедой на экране замера нет).
func _ensure_ui() -> void:
	if fps != null:
		return
	fps = FpsCounter.new()
	add_child(fps)
	report = BenchReport.new()
	add_child(report)
	bench = FrameBench.new()
	add_child(bench)
	bench.title = "Капелла %s" % release_name()
	bench.finished.connect(_bench_done)


## Открыть меню «Быстрый бой» (G5): выбор боя на фоне неба и планеты.
func open_menu() -> bool:
	_close_table()
	_close_polygon()
	_close_menu()
	menu_back = Node3D.new()
	menu_back.name = "MenuBack"
	add_child(menu_back)
	var cam := Camera3D.new()
	cam.fov = defs.doctrine.camera_fov_deg
	cam.far = defs.doctrine.camera_far
	menu_back.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 600.0, 3200.0), SpaceEnv.PLANET_CENTER * 0.55)
	var env := SpaceEnv.new()
	env.name = "SpaceEnv"
	menu_back.add_child(env)
	menu = QuickMenu.new()
	menu.name = "QuickMenu"
	menu.setup(defs, release_name())
	if not last_cfg.is_empty():
		menu.cfg = last_cfg.duplicate()
		menu.cfg["watch"] = false
	add_child(menu)
	menu.start.connect(_start_from_menu)
	mode = &"menu"
	_ensure_ui()
	fps.set_hint_text(HINT_MENU)
	fps.set_hint_top(14.0)
	return true


func _close_menu() -> void:
	if menu != null:
		menu.queue_free()
		remove_child(menu)
		menu = null
	if menu_back != null:
		menu_back.queue_free()
		remove_child(menu_back)
		menu_back = null


## Кнопка меню жмётся посреди обработки ввода самого меню — бой открывается следующим
## кадром, когда меню уже ничего не обрабатывает.
func _start_from_menu(c: Dictionary) -> void:
	open_battle.call_deferred(c)


## Быстрый бой по выбору меню (план G5, п. 3): зерно — от часов (тесты дают своё), отчёт
## и запись — в папку рядом с программой (как файл замера кадров).
func open_battle(c: Dictionary) -> bool:
	var cc := c.duplicate()
	if not cc.has("seed"):
		var sd := seed_override if seed_override >= 0 else int(Time.get_ticks_usec() % 1000000007)
		cc["seed"] = float(sd)
	last_cfg = c.duplicate()
	last_cfg.erase("seed")
	_close_table()
	_close_polygon()
	_close_menu()
	polygon = Polygon.new()
	polygon.name = "Polygon"
	add_child(polygon)
	if not polygon.setup(defs, release_name(), {}, cc):
		var problems := polygon.problems
		polygon.free()
		polygon = null
		_fail("Бой не начался: модели кораблей с ошибкой.", "МОДЕЛИ", problems, OS.get_cmdline_user_args())
		return false
	mode = &"battle"
	_ensure_ui()
	polygon.out_dir = out_override if out_override != "" else bench.folder()
	polygon.again_pressed.connect(func() -> void: open_battle.call_deferred(last_cfg))
	polygon.menu_pressed.connect(func() -> void: open_menu.call_deferred())
	fps.set_hint_text(HINT_BATTLE)
	fps.set_hint_top(PolygonHud.HINT_TOP)
	return true


## Открыть «Стол» (G0b): худший бой без самого боя, на нём — минута замера кадров.
func open_table() -> bool:
	if mode == &"polygon":
		table_from = &"polygon"
	elif mode == &"menu":
		table_from = &"menu"
	_close_polygon()
	_close_menu()
	if view != null:
		return true
	view = Showcase.new()
	view.name = "Showcase"
	add_child(view)
	if not view.setup(defs):
		# пустого места на «Столе» молча не бывает: замер на облегчённой сцене
		# обещал бы кадры, которых на худшем бое нет (замечание к G0b)
		var problems := view.problems
		view.free()
		view = null
		_fail("Игра не запустилась: модели кораблей с ошибкой.", "МОДЕЛИ", problems, OS.get_cmdline_user_args())
		return false
	mode = &"table"
	_ensure_ui()
	# F6 ведёт туда, откуда пришли, — подсказка называет куда (лаборатория или меню)
	fps.set_hint_text(HINT_TABLE % ("«Полигон»" if table_from == &"polygon" else "меню «Быстрый бой»"))
	fps.set_hint_top(14.0)
	bench.driver = view.drive
	bench.extra_line = "На столе: %d %s, %d %s; синхронизация с экраном на время замера выключена" % [
		view.ship_count(), FrameBench.plural(view.ship_count(), "корабль", "корабля", "кораблей"),
		view.craft_count(), FrameBench.plural(view.craft_count(), "машина", "машины", "машин")]
	return true


## Открыть «Полигон» (G1). rec — запись боя для повтора (пусто — новый бой).
func open_polygon(rec: Dictionary = {}) -> bool:
	_close_table()
	_close_polygon()
	_close_menu()
	polygon = Polygon.new()
	polygon.name = "Polygon"
	add_child(polygon)
	if not polygon.setup(defs, release_name(), rec):
		var problems := polygon.problems
		polygon.free()
		polygon = null
		var head := "Игра не запустилась: модели кораблей с ошибкой." if rec.is_empty() else "Запись боя не проигрывается."
		_fail(head, "МОДЕЛИ" if rec.is_empty() else "ПОВТОР", problems, OS.get_cmdline_user_args())
		return false
	mode = &"polygon"
	_ensure_ui()
	fps.set_hint_text(HINT_POLYGON)
	fps.set_hint_top(PolygonHud.HINT_TOP)
	if not rec.is_empty():
		polygon.replay_checked.connect(_replay_checked)
	return true


func _close_table() -> void:
	if view == null:
		return
	if bench != null and bench.running:
		_cancel_bench()
	if report != null:
		report.hide_report()
	view.queue_free()
	remove_child(view)
	view = null


func _close_polygon() -> void:
	if polygon == null:
		return
	if polygon.battle != null:
		polygon.battle.dispose()
	polygon.queue_free()
	remove_child(polygon)
	polygon = null


func _replay_checked(good: bool, text: String) -> void:
	print("REPLAY %s" % text)
	if replay_check:
		get_tree().quit(0 if good else 1)


## Флажки боя из командной строки (tools/polygon.gd): `--old-ecm` — откат 09, 1.7;
## `--bomber-direct` и `--patrol-mid` — откаты авиации 09, 8.4 (G3). `--old-camera` — откат
## проверок картинки (М14; план G8 и GЭ): камера JS-версии — обзор 52°, наклон 0,52 рад, старт 1100.
static func apply_flags(args: PackedStringArray) -> void:
	Polygon.flags = BenchCore.flags_from_args(args)
	if "--old-camera" in args:
		CameraRig.old_camera = true


## Запись боя из файла (JSON). Относительный путь — от папок запуска (как --overrides).
## → пустой словарь и причина в why, если не открылась.
static func read_record(path: String, bases: PackedStringArray, why: PackedStringArray) -> Dictionary:
	var full := path
	if path.is_relative_path():
		for d in bases:
			if FileAccess.file_exists(d.path_join(path)):
				full = d.path_join(path)
				break
	var text := FileAccess.get_file_as_string(full)
	if text == "":
		why.append("нет файла %s" % full)
		return {}
	var j := JSON.new()
	if j.parse(text) != OK:
		why.append("%s: строка %d — %s" % [full, j.get_error_line() + 1, j.get_error_message()])
		return {}
	if typeof(j.data) != TYPE_DICTIONARY:
		why.append("%s: ждали объект JSON" % full)
		return {}
	var d: Dictionary = j.data
	return d


## --make-replay: показательный бой «Полигона» без вида → запись в файл, код 0.
func _make_replay(path: String) -> void:
	var rec := Polygon.make_record(defs, release_name())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("REPLAY не записалась: %s" % path)
		get_tree().quit(1)
		return
	f.store_string(JSON.stringify(rec))
	f.close()
	var cmds: Array = rec["cmds"]
	print("REPLAY записана: %s · шагов %d, команд %d, отпечаток боя %s" % [path, whole(rec["steps"]), cmds.size(), str(rec["fp"])])
	get_tree().quit(0)


static func whole(v: Variant) -> int:
	var f: float = v
	return roundi(f)


## Номер сборки — первая строка godot/RELEASE (она едет в выгрузку, include_filter).
static func release_name() -> String:
	var t := FileAccess.get_file_as_string("res://RELEASE")
	var first := t.get_slice("\n", 0).strip_edges()
	return first if first != "" else "без номера"


func start_bench() -> void:
	if view == null:
		return
	if report != null:
		report.hide_report()
	view.rig.input_enabled = false
	fps.block_hint(true)
	bench.start()


func _cancel_bench() -> void:
	bench.cancel()
	if view != null:
		view.rig.input_enabled = true
	fps.block_hint(false)
	report.hide_progress()


## F5 с «Полигона»: открыть «Стол» и через секунду начать замер — первые кадры
## «Стола» — загрузка, а не отрисовка (как у --bench-render).
func _bench_from_polygon() -> void:
	if not open_table():
		return
	await get_tree().create_timer(1.0).timeout
	if mode == &"table" and view != null and not bench.running:
		start_bench()


func _process(_delta: float) -> void:
	# подсказка клавиш боя — над ростером, гаснет через 16 игровых секунд (ui/polygon_hud.gd)
	if fps != null and polygon != null and polygon.hud != null and (mode == &"battle" or mode == &"polygon"):
		fps.set_hint_top(polygon.hud.hint_top(fps.hint.size.y))
		fps.set_hint_off(polygon.hud.hint_gone())
		polygon.hud.hint_rect = fps.hint.get_global_rect() if fps.hint.is_visible_in_tree() else Rect2()
	elif fps != null:
		fps.set_hint_off(false)
	if bench != null and bench.running and report != null:
		var avoid: Array[Rect2] = []
		if fps.panel.visible:
			avoid.append(fps.panel.get_global_rect())
		report.show_progress(bench.elapsed, bench.duration, avoid)


func _bench_done(summary: String, file: String) -> void:
	if view != null:
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
	match k.physical_keycode:
		KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_F5:
			if bench == null:
				return
			# F5 — минута замера на «Столе»; F5 во время замера — прервать
			if bench.running:
				_cancel_bench()
			elif mode == &"table":
				start_bench()
			elif mode == &"polygon" or mode == &"menu":
				_bench_from_polygon()
			else:
				return
		KEY_F6:
			# «Стол» — из меню и из лаборатории; из быстрого боя нет: бой пропал бы молча
			if mode == &"table":
				if table_from == &"polygon":
					open_polygon()
				else:
					open_menu()
			elif mode == &"polygon" or mode == &"menu":
				open_table()
			else:
				return
		KEY_F8:
			if mode == &"polygon":
				open_polygon()
			elif mode == &"battle":
				open_battle(last_cfg)
			else:
				return
		KEY_F9:
			if (mode != &"polygon" and mode != &"battle") or polygon == null:
				return
			save_record()
		KEY_F4:
			# строка-отладка пояса над тяжёлыми (09, 6.7; только разработчику — в подсказке нет)
			if (mode != &"polygon" and mode != &"battle") or polygon == null or rollback_no_f4:
				return
			polygon.hud.belt_debug = not polygon.hud.belt_debug
		_:
			return
	get_viewport().set_input_as_handled()


## F9 — запись боя «Полигона» (зерно + журнал команд + отпечаток): файлом рядом
## с программой (нельзя — в user://) и текстом в буфер обмена — его вставляют в чат,
## а --replay=ФАЙЛ проигрывает тот же бой (архитектура, 2.9).
func save_record() -> String:
	var b := polygon.battle
	var rec := b.record()
	rec["fp"] = b.fingerprint()
	var text := JSON.stringify(rec)
	var dir := bench.folder()
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var path := dir.path_join("capella_replay_%s.json" % stamp)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		path = ProjectSettings.globalize_path("user://").path_join("capella_replay_%s.json" % stamp)
		f = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	else:
		path = ""
	last_record = path
	if record_to_clipboard and DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(text)
	var cmds: Array = rec["cmds"]
	polygon.hud.say("Запись боя (%d %s) — в буфере обмена%s" % [cmds.size(), FrameBench.plural(cmds.size(), "приказ", "приказа", "приказов"), (" и в файле " + path) if path != "" else ""])
	return path


## Отказ — словами на экране и в stderr: молча «Стол» или «Полигон» не начинаем.
## В режиме замера и сверки повтора из командной строки — код выхода 1: замер на
## неполной сцене никому не нужен, а несыгранный повтор — не «совпало».
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
	elif "--replay-check" in args:
		print("REPLAY ОТКАЗ: ", head, " ", "; ".join(list))
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
	# бой: показательная запись «Полигона» (40 с полёта, все приказы) без вида — её
	# отпечаток CI сверяет между Linux и Windows (архитектура, 2.11: Windows не проверен)
	var battle_fp := "—"
	if defs.ok:
		fails.append_array(Polygon.models_problems(defs))
		var rec := Polygon.make_record(defs, release_name())
		battle_fp = str(rec["fp"])
		var why := PackedStringArray()
		var again := Battle.from_record(defs, rec, release_name(), why) as Battle
		if again == null:
			fails.append("запись боя не проигрывается: %s" % "; ".join(why))
		else:
			while again.steps < whole(rec["steps"]):
				again.step()
			if again.fingerprint() != battle_fp:
				fails.append("повтор записи разошёлся: %s против %s" % [again.fingerprint(), battle_fp])
			again.dispose()
	# «ИИ против ИИ» (G5): быстрый бой по выбору меню по умолчанию, обе стороны под ИИ, 60 с без
	# вида — второй отпечаток для сверки Linux и Windows (ИИ думает по жребию боя и считает углы
	# векторами: разойтись тут — находка о повторяемости, а не провал)
	var ai_fp := "—"
	if defs.ok:
		var ab := Battle.create(defs, Polygon.quick_setup(QuickMenu.default_cfg(defs, true), Polygon.SEED), release_name()) as Battle
		for i in AI_SELFTEST_STEPS:
			ab.step()
		if not ab.watch:
			fails.append("«ИИ против ИИ»: бой не под двумя ИИ")
		ai_fp = ab.fingerprint()
		ab.dispose()
	var line := "SELFTEST %s: данные %s, бой %s, ИИ %s, правок %d, отрисовщик %s, ОС %s, сборка %s" % [
		"ok" if fails.is_empty() else "ПРОВАЛ", defs.fingerprint, battle_fp, ai_fp, defs.overrides_applied.size(),
		RenderingServer.get_current_rendering_method(), OS.get_name(), "выгружена" if OS.has_feature("template") else "редактор"]
	print(line)
	printerr(line)
	for f in fails:
		printerr("  ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
