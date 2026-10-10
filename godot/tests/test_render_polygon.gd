# «Полигон» под xvfb (ярус картинки; план G1, игровые проверки) — в ОБОИХ
# отрисовщиках. Плюс хвосты G0: итог замера в буфере обмена и F11 — событиями.
# - плавность: Movie Maker пишет кадры картинками с постоянным шагом времени
#   (tests/probe_smooth.gd, отдельный процесс), сдвиг корвета между соседними
#   кадрами меряется по точкам кадра — ровный на 60 Гц и на 144 (кадров больше, чем
#   шагов модели, — интерполяция работает и тут). Откат — без смешивания: на 60 Гц
#   сдвиг через кадр, на 144 — четыре кадра стоит, пятый прыгает;
# - итог F5 лежит в буфере обмена (DisplayServer.clipboard_get под xvfb), «Скопировать
#   ещё раз» кладёт его снова (откат — замер без записи в буфер краснеет);
# - F9 на «Полигоне» кладёт запись боя в буфер обмена: в нём была «проба», стала
#   запись (JSON, kind capella-replay), та же, что в файле, и она проигрывается
#   (откат — запись без буфера: в буфере осталась «проба»);
# - F11 — событием клавиши: режим окна до и после (откат — главная сцена не слушает
#   клавиши: режим не меняется);
# - снимки «Полигона» на 1920 и 1366 — в $CAPELLA_SHOTS; подсказка клавиш не лежит
#   на чужой линии, нижняя панель — на своих кораблях на старте.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Ship := preload("res://sim/ship.gd")
const FrameBench := preload("res://ui/frame_bench.gd")
const BenchReport := preload("res://ui/bench_report.gd")
const MainScene := preload("res://main.tscn")
const MainScript := preload("res://main.gd")
const Battle := preload("res://sim/battle.gd")


static func renderer() -> String:
	return RenderingServer.get_current_rendering_method()


static func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Кадры Movie Maker в отдельном процессе → x середины корабля на каждом кадре (в
## точках исходного кадра; −1 — корабля нет).
func _movie(mode: String, fps: int, frames: int) -> PackedFloat64Array:
	var dir := ProjectSettings.globalize_path("user://movie_%s_%s_%d" % [renderer(), mode, fps])
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--rendering-method", renderer(),
		"--write-movie", dir.path_join("f.png"), "--fixed-fps", str(fps), "--quit-after", str(frames),
		"-s", "res://tests/probe_smooth.gd", "--", mode])
	var pid := OS.create_process(OS.get_executable_path(), args)
	var t0 := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - t0 < 180000:
		await hooks.frames(5)
	if OS.is_process_running(pid):
		OS.kill(pid)
		ok(false, "проба плавности %s %d зависла" % [mode, fps])
		return PackedFloat64Array()
	var xs := PackedFloat64Array()
	var names := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			names.append(f)
	names.sort()
	for f in names:
		var img := Image.load_from_file(dir.path_join(f))
		xs.append(_center_x(img))
		DirAccess.remove_absolute(dir.path_join(f))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	return xs


## Середина светлых точек по x в полосе вокруг середины кадра (кадр уменьшен вчетверо
## с фильтром — середина пятна при этом сохраняется).
static func _center_x(img: Image) -> float:
	var k := 4
	var w := img.get_width() >> 2
	var h := img.get_height() >> 2
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var sum := 0.0
	var wsum := 0.0
	var band := floori(h * 0.2)
	for y in range((h >> 1) - band, (h >> 1) + band):
		for x in w:
			var l := lum(img.get_pixel(x, y))
			if l > 0.06:
				sum += l * x
				wsum += l
	return (sum / wsum) * k if wsum > 0.0 else -1.0


## Сдвиги между соседними кадрами на участке, где корабль уже на полном ходу и в кадре.
static func _shifts(xs: PackedFloat64Array, skip: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in range(skip + 1, xs.size()):
		if xs[i] < 0.0 or xs[i - 1] < 0.0:
			continue
		out.append(xs[i] - xs[i - 1])
	return out


static func _spread(d: PackedFloat64Array) -> Vector3:
	if d.is_empty():
		return Vector3(0, 0, 0)
	var lo := INF
	var hi := -INF
	var sum := 0.0
	for v in d:
		lo = minf(lo, v)
		hi = maxf(hi, v)
		sum += v
	return Vector3(lo, hi, sum / d.size())


func test_movie_smooth_60_and_144() -> void:
	for fps: int in [60, 144]:
		var frames := 50 if fps == 60 else 90
		var skip := 12
		var xs := await _movie("smooth", fps, frames)
		var d := _shifts(xs, skip)
		var sp := _spread(d)
		note("%s %d Гц: сдвиги %s" % [renderer(), fps, _fmt(d)])
		ok(d.size() >= frames - skip - 4, "%d Гц: корабль на всех кадрах (%d сдвигов)" % [fps, d.size()])
		ok(sp.x > 0.55 * sp.z and sp.y < 1.45 * sp.z, "%d Гц: сдвиг между кадрами ровный — от %.2f до %.2f при среднем %.2f точки" % [fps, sp.x, sp.y, sp.z])
		# откат: без смешивания — на 60 Гц через кадр, на 144 четыре стоит, пятый прыгает
		var raw := _shifts(await _movie("raw", fps, frames), skip)
		var rs := _spread(raw)
		note("%s %d Гц, откат: сдвиги %s" % [renderer(), fps, _fmt(raw)])
		ok(rs.x < 0.25 * rs.z, "%d Гц, откат «без смешивания»: сдвиг от %.2f до %.2f — проверка краснеет" % [fps, rs.x, rs.y])


static func _fmt(d: PackedFloat64Array) -> String:
	var parts := PackedStringArray()
	for i in mini(d.size(), 14):
		parts.append("%.1f" % d[i])
	return " ".join(parts)


# ───────────────────────── хвосты G0: буфер обмена и F11 ─────────────────────────

func _main_table() -> Node:
	MainScript.boot = &"table"
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	MainScript.boot = &""
	await hooks.frames(3)
	return main


func _bench_once(main: Node) -> String:
	var bench: FrameBench = main.get("bench")
	var report: BenchReport = main.get("report")
	bench.duration = 1.0
	bench.out_dir = ProjectSettings.globalize_path("user://bench_clip")
	await hooks.key(KEY_F5)
	var t0 := Time.get_ticks_msec()
	while not report.is_open() and Time.get_ticks_msec() - t0 < 60000:
		await hooks.frames(1)
	if report.file != "":
		DirAccess.remove_absolute(report.file)
	return report.summary


func test_bench_result_in_clipboard() -> void:
	await hooks.set_window_size(Vector2i(1366, 768))
	ok(DisplayServer.get_name() != "headless", "ярус с окном: буфер обмена настоящий (%s)" % DisplayServer.get_name())
	var main := await _main_table()
	DisplayServer.clipboard_set("проба буфера")
	var summary := await _bench_once(main)
	ok(summary.contains("замер кадров"), "замер кончился, итог есть")
	eq(DisplayServer.clipboard_get(), summary, "итог замера — в буфере обмена")
	# «Скопировать ещё раз» кладёт его снова
	var report: BenchReport = main.get("report")
	DisplayServer.clipboard_set("проба буфера")
	await hooks.click(report.copy_btn.get_global_rect().get_center())
	eq(DisplayServer.clipboard_get(), summary, "«Скопировать ещё раз» — итог снова в буфере")
	report.hide_report()
	# откат: замер без записи в буфер — в буфере осталось прежнее
	var bench: FrameBench = main.get("bench")
	bench.to_clipboard = false
	DisplayServer.clipboard_set("проба буфера")
	var s2 := await _bench_once(main)
	ok(DisplayServer.clipboard_get() != s2, "откат «итог не в буфер» краснеет: в буфере «%s»" % DisplayServer.clipboard_get())
	bench.to_clipboard = true
	main.queue_free()
	await hooks.frames(3)


## Буфер → запись боя: {} — в буфере не запись (не JSON или не объект).
static func _parse_record(text: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) != OK or typeof(j.data) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = j.data
	return d


## F9 — запись боя «Полигона» в буфер обмена (замечание к G1: это обещал текст
## выпуска, а проверялся только файл, и без окна — откат «clipboard_set убран» был
## зелёным во всех ярусах). Буфер под xvfb настоящий.
func test_f9_record_in_clipboard() -> void:
	await hooks.set_window_size(Vector2i(1366, 768))
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	await hooks.frames(10)            # бой идёт: в записи есть шаги
	var poly: Node = main.get("polygon")
	ok(poly != null, "главная сцена открыла «Полигон»")
	var bench: FrameBench = main.get("bench")
	bench.out_dir = ProjectSettings.globalize_path("user://record_clip")
	DirAccess.make_dir_recursive_absolute(bench.out_dir)
	DisplayServer.clipboard_set("проба буфера")
	await hooks.key(KEY_F9)
	var clip := DisplayServer.clipboard_get()
	var rec := _parse_record(clip)
	note("%s: F9 — в буфере %d знаков" % [renderer(), clip.length()])
	ok(str(rec.get("kind", "")) == "capella-replay", "F9 — в буфере запись боя (kind capella-replay), а не «%s»" % clip.left(40))
	var steps: float = rec.get("steps", 0.0)
	ok(steps > 0.0 and str(rec.get("fp", "")) != "", "в записи шаги (%d) и отпечаток боя" % int(steps))
	var path: String = main.get("last_record")
	ok(path != "" and FileAccess.get_file_as_string(path) == clip, "в буфере — то же, что в файле записи %s" % path)
	if path != "":
		DirAccess.remove_absolute(path)
	# запись из буфера проигрывается этой сборкой: заголовок сходится
	var why := PackedStringArray()
	var defs: Defs = main.get("defs")
	var again := Battle.from_record(defs, rec, MainScript.release_name(), why) as Battle
	ok(again != null, "запись из буфера проигрывается: %s" % "; ".join(why))
	if again != null:
		again.dispose()
	# откат: запись без буфера — в буфере осталась «проба»
	main.set("record_to_clipboard", false)
	DisplayServer.clipboard_set("проба буфера")
	await hooks.key(KEY_F9)
	var stale := DisplayServer.clipboard_get()
	ok(_parse_record(stale).is_empty(), "откат «запись не в буфер» краснеет: в буфере «%s»" % stale.left(40))
	main.set("record_to_clipboard", true)
	var p2: String = main.get("last_record")
	if p2 != "":
		DirAccess.remove_absolute(p2)
	main.queue_free()
	await hooks.frames(3)


func test_f11_by_key_event() -> void:
	await hooks.set_window_size(Vector2i(1366, 768))
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	await hooks.frames(3)
	var m0 := DisplayServer.window_get_mode()
	await hooks.key(KEY_F11)
	await hooks.frames(3)
	var m1 := DisplayServer.window_get_mode()
	await hooks.key(KEY_F11, KEY_NONE, true)
	await hooks.frames(2)
	var m_echo := DisplayServer.window_get_mode()
	await hooks.key(KEY_F11)
	await hooks.frames(3)
	var m2 := DisplayServer.window_get_mode()
	note("%s: режим окна %d → F11 %d → F11 %d" % [renderer(), m0, m1, m2])
	ok(m0 != DisplayServer.WINDOW_MODE_FULLSCREEN, "до F11 — окно, не полный экран")
	eq(m1, DisplayServer.WINDOW_MODE_FULLSCREEN, "F11 — полный экран")
	eq(m_echo, DisplayServer.WINDOW_MODE_FULLSCREEN, "повтор F11 (echo) — не нажатие")
	ok(m2 != DisplayServer.WINDOW_MODE_FULLSCREEN, "F11 ещё раз — снова окно (%d)" % m2)
	# откат: главная сцена клавиш не слушает — F11 режим не меняет
	main.set_process_input(false)
	await hooks.key(KEY_F11)
	await hooks.frames(3)
	ok(DisplayServer.window_get_mode() == m2, "откат «F11 не слушается» краснеет: режим тот же (%d)" % DisplayServer.window_get_mode())
	main.queue_free()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await hooks.set_window_size(Vector2i(1366, 768))


# ───────────────────────── снимки «Полигона» ─────────────────────────

func test_polygon_snapshots() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		var got := await hooks.set_window_size(size)
		var main := MainScene.instantiate()
		tree.root.add_child(main)
		await hooks.frames(8)
		var poly: Node = main.get("polygon")
		var view: Node3D = poly.get("view")
		var rig: Node3D = view.get("rig")
		var cam: Camera3D = rig.get("camera")
		var b: Object = poly.get("battle")
		var fps: Node = main.get("fps")
		var hint: Label = fps.get("hint")
		var hud: Node = poly.get("hud")
		var panel: Control = hud.get("panel")
		var tag := "%d×%d" % [got.x, got.y]
		var hint_r := hint.get_global_rect()
		var panel_r := panel.get_global_rect()
		var foe_top := INF
		var own_bottom := -INF
		var list: Array = b.get("ships")
		for so: Object in list:
			var s := so as Ship
			var wp: Vector3 = view.call("ship_point", s)
			var p := cam.unproject_position(wp)
			if s.side == Ship.DEFENDER and s.def.main != null:
				foe_top = minf(foe_top, p.y)      # чужая ЛИНИЯ — тяжёлые; носители позади неё
			else:
				own_bottom = maxf(own_bottom, p.y)
		ok(foe_top > hint_r.end.y, "%s: подсказка клавиш выше чужой линии (низ подсказки %.0f, чужие тяжёлые с %.0f)" % [tag, hint_r.end.y, foe_top])
		ok(own_bottom < panel_r.position.y, "%s: нижняя панель ниже своих кораблей (свои до %.0f, панель с %.0f)" % [tag, own_bottom, panel_r.position.y])
		var img := tree.root.get_texture().get_image()
		var shots := OS.get_environment("CAPELLA_SHOTS")
		if shots != "":
			img.save_png(shots.path_join("polygon_%s_%s.png" % [renderer(), tag]))
		main.queue_free()
		await hooks.frames(3)
