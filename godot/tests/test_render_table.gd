# «Стол» под xvfb (план G0, проверки; архитектура, 8.5): ярус картинки, гоняется
# в ОБОИХ отрисовщиках (Forward+ на lavapipe и Compatibility на llvmpipe).
# Проверки — замеры по точкам, а не сравнение с эталоном: на видеокарте
# пользователя эталоны не совпадут (архитектура, 8.5).
# - ореол (09, 11.7; часть 08, ловушка 2): девять снимков на дальнем пределе 5000;
#   небо проверочной сборки сплошное пурпурное — внутри диска планеты пурпура
#   нет, кольцо венца не чёрное; при обычном небе и пурпурном цвете очистки —
#   пурпура нет нигде. Откаты: дальняя плоскость 4000, фон без неба;
# - стартовый кадр (09, 11.4): своя линия около 0,57 высоты, чужая около 0,13;
# - прогрев (07, ловушка 29; 08, ловушка 15): счётчики сборок конвейеров не
#   растут после первых кадров (откат — эффекты впервые на 30-м кадре);
# - сканер кнопок (07, ловушка 10): щелчок в центр каждой видимой кнопки доходит
#   до неё (откат — прозрачная панель STOP поверх);
# - строка «Замер кадров…» не ложится ни на подсказку, ни на счётчик F3 — на 1920
#   и 1366 (замечание к G0b: на 1366 она минуту лежала на подсказке; откат —
#   подсказка на месте);
# - снимки «Стола» на 1920 и 1366 — в $CAPELLA_SHOTS для глаз; плюс замеры:
#   корабли видны, звёзды — точки, а не пятна (откат — звезда вчетверо шире).
# Минута замера кадров (F5) — укороченной: файл и итог текстом.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Showcase := preload("res://tools/showcase.gd")
const SpaceEnv := preload("res://view/space_env.gd")
const FrameBench := preload("res://ui/frame_bench.gd")
const BenchReport := preload("res://ui/bench_report.gd")
const FpsCounter := preload("res://ui/fps_counter.gd")
const MainScene := preload("res://main.tscn")

const MAGENTA := Color(1, 0, 1)

var _defs: Defs


func _table(prewarm: bool = true) -> Showcase:
	if _defs == null:
		_defs = Defs.load_default({}) as Defs
	var sc := Showcase.new()
	sc.name = "Showcase"
	tree.root.add_child(sc)
	sc.setup(_defs, prewarm)
	await hooks.frames(2)
	return sc


func _drop(sc: Node) -> void:
	sc.queue_free()
	RenderingServer.set_default_clear_color(Color(0.012, 0.014, 0.025))
	await hooks.frames(2)


func _shot() -> Image:
	await hooks.frames(3)
	return tree.root.get_texture().get_image()


static func renderer() -> String:
	return RenderingServer.get_current_rendering_method()


static func is_magenta(c: Color) -> bool:
	return c.r > 0.5 and c.b > 0.5 and c.g < 0.3 and absf(c.r - c.b) < 0.3


static func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _shots_dir() -> String:
	var d := OS.get_environment("CAPELLA_SHOTS")
	if d == "":
		d = ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(d)
	return d


# ───────────────────────── ореол ─────────────────────────

## Диск планеты на экране: центр и полуоси (по правому и верхнему векторам камеры).
## null — планета за камерой.
static func planet_disk(cam: Camera3D) -> Variant:
	var c := SpaceEnv.PLANET_CENTER
	if cam.is_position_behind(c):
		return null
	var cc := cam.unproject_position(c)
	var b := cam.global_transform.basis
	var rx := cam.unproject_position(c + b.x * SpaceEnv.PLANET_RADIUS).distance_to(cc)
	var ry := cam.unproject_position(c + b.y * SpaceEnv.PLANET_RADIUS).distance_to(cc)
	return [cc, rx, ry]


## Беды одного снимка с пурпурным небом: пурпур внутри диска, чёрное кольцо венца.
## Возвращает [беды, диск в кадре (bool)].
static func halo_problems(img: Image, disk: Variant, tag: String) -> Array:
	var bad := PackedStringArray()
	if disk == null:
		return [bad, false]
	var d: Array = disk
	var cc: Vector2 = d[0]
	var rx: float = d[1]
	var ry: float = d[2]
	var w := img.get_width()
	var h := img.get_height()
	if cc.x + rx < 0 or cc.y + ry < 0 or cc.x - rx > w or cc.y - ry > h:
		return [bad, false]
	var inside := 0
	var magenta := 0
	var ring := 0
	var black := 0
	var y0 := maxi(0, int(cc.y - ry * 1.15))
	var y1 := mini(h - 1, int(cc.y + ry * 1.15))
	var x0 := maxi(0, int(cc.x - rx * 1.15))
	var x1 := mini(w - 1, int(cc.x + rx * 1.15))
	for y in range(y0, y1 + 1, 2):
		for x in range(x0, x1 + 1, 2):
			var e := Vector2((x - cc.x) / rx, (y - cc.y) / ry).length()
			var col := img.get_pixel(x, y)
			if e <= 0.85:
				inside += 1
				if is_magenta(col):
					magenta += 1
			elif e >= 1.03 and e <= 1.1:
				ring += 1
				if lum(col) < 0.02:
					black += 1
	if inside < 20:
		return [bad, false]
	if magenta > 0:
		bad.append("%s: внутри диска планеты %d пурпурных точек из %d" % [tag, magenta, inside])
	if ring > 0 and black > 0:
		bad.append("%s: кольцо венца чёрное в %d точках из %d" % [tag, black, ring])
	return [bad, true]


## Девять снимков на дальнем пределе 5000 (09, 11.7): центр, край (0, 0, 2600),
## угол (2600, 0, 2600) × поворот 0, π/2, π (2600 — field_half выгрузки). Отдаёт [беды, сколько раз диск в кадре].
func _nine(sc: Showcase, magenta_sky: bool) -> Array:
	var bad := PackedStringArray()
	var seen := 0
	sc.env.set_test_magenta(magenta_sky)
	# карта окружения (отражения) пересчитывается за несколько кадров: без ожидания
	# океан планеты ещё отражает прежнее, пурпурное небо (замечено в Compatibility)
	await hooks.frames(12)
	var fh := _defs.consts.field_half
	for look: Vector3 in [Vector3.ZERO, Vector3(0, 0, fh), Vector3(fh, 0, fh)]:
		for yaw: float in [0.0, PI * 0.5, PI]:
			sc.rig.set_view(look, yaw, 5000.0, true)
			var img := await _shot()
			var tag := "взгляд (%d, %d), поворот %.2f" % [int(look.x), int(look.z), yaw]
			if magenta_sky:
				var r := halo_problems(img, planet_disk(sc.rig.camera), tag)
				var rb: PackedStringArray = r[0]
				bad.append_array(rb)
				var vis: bool = r[1]
				if vis:
					seen += 1
			else:
				var m := 0
				for y in range(0, img.get_height(), 4):
					for x in range(0, img.get_width(), 4):
						if is_magenta(img.get_pixel(x, y)):
							m += 1
				if m > 0:
					bad.append("%s: пурпур цвета очистки виден в %d точках" % [tag, m])
	sc.env.set_test_magenta(false)
	return [bad, seen]


func _hide_fleet(sc: Showcase, hidden: bool) -> void:
	for s in sc.ships:
		s.visible = not hidden
	sc.crafts.visible = not hidden
	sc.fx.visible = not hidden


func test_halo_nine_shots() -> void:
	await hooks.set_window_size(Vector2i(960, 540))
	var sc := await _table()
	RenderingServer.set_default_clear_color(MAGENTA)
	# корабли отражают небо: в пурпурной проверочной сборке они розовеют — убираем,
	# диск планеты и кольцо венца от них не зависят
	_hide_fleet(sc, true)
	var r := await _nine(sc, true)
	var bad: PackedStringArray = r[0]
	var seen: int = r[1]
	ok(bad.is_empty(), "пурпурное небо, дальняя 20 000: %s" % "; ".join(bad))
	ok(seen >= 2, "диск планеты в кадре хотя бы на двух снимках из девяти (вышло %d) — иначе проверка пустая" % seen)
	note("%s: диск планеты в кадре на %d снимках из 9" % [renderer(), seen])
	# откат: прежняя дальняя плоскость 4000 — планета за ней срезана, пурпур в диске
	sc.rig.camera.far = 4000.0
	var rb := await _nine(sc, true)
	var bad4: PackedStringArray = rb[0]
	ok(bad4.size() >= 2, "откат «дальняя 4000» краснеет: %d бед (%s)" % [bad4.size(), bad4[0] if bad4.size() > 0 else "бед нет"])
	sc.rig.camera.far = _defs.doctrine.camera_far
	# обычное небо и пурпурный цвет очистки: дыр в небе нет нигде (флот спрятан и тут:
	# сложение оранжевой вспышки с голубым лучом изредка даёт розовую точку)
	var rc := await _nine(sc, false)
	var badc: PackedStringArray = rc[0]
	ok(badc.is_empty(), "обычное небо: цвет очистки не виден: %s" % "; ".join(badc))
	# откат: фон — цвет очистки, а не небо (как «туманность-сфера» с дырой) — краснеет
	sc.env.env.background_mode = Environment.BG_CLEAR_COLOR
	sc.rig.set_view(Vector3.ZERO, 0.0, 5000.0, true)
	var img := await _shot()
	var m := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			if is_magenta(img.get_pixel(x, y)):
				m += 1
	ok(m > 100, "откат «фон без неба» виден пурпуром (%d точек)" % m)
	sc.env.env.background_mode = Environment.BG_SKY
	_hide_fleet(sc, false)
	# и числом: всё, что в кадре, ближе дальней плоскости — корабли у края поля и планета
	var far := sc.rig.camera.far
	var worst := 0.0
	var fh := _defs.consts.field_half
	for look: Vector3 in [Vector3.ZERO, Vector3(0, 0, fh), Vector3(fh, 0, fh), Vector3(-fh, 0, -fh)]:
		for yaw: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			sc.rig.set_view(look, yaw, 5000.0, true)
			var eye := sc.rig.camera.global_position
			worst = maxf(worst, eye.distance_to(SpaceEnv.PLANET_CENTER) + SpaceEnv.PLANET_RADIUS * SpaceEnv.CORONA_K)
			for s in sc.ships:
				worst = maxf(worst, eye.distance_to(s.global_position) + s.length())
	ok(worst < far * 0.9, "самое дальнее в кадре — %.0f, дальняя плоскость %.0f" % [worst, far])
	await _drop(sc)


# ───────────────────────── стартовый кадр ─────────────────────────

## Доли высоты экрана своей и чужой линий тяжёлых (09, 11.4) и все ли тяжёлые в кадре.
static func start_frame(sc: Showcase) -> Dictionary:
	var cam := sc.rig.camera
	var vs := sc.get_viewport().get_visible_rect().size
	var own := 0.0
	var foe := 0.0
	var no := 0
	var nf := 0
	var out := 0
	for i in sc.ships.size():
		var s := sc.ships[i]
		if not s.ship_id in [&"cruiser", &"capital"]:
			continue
		var p := cam.unproject_position(Vector3(s.global_position.x, 0.0, s.global_position.z))
		if p.x < 0.0 or p.x > vs.x or p.y < 0.0 or p.y > vs.y:
			out += 1
		if sc.side_of[i] > 0:
			own += p.y / vs.y
			no += 1
		else:
			foe += p.y / vs.y
			nf += 1
	return {"own": own / maxi(no, 1), "foe": foe / maxi(nf, 1), "out": out}


func test_start_frame() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		await hooks.set_window_size(size)
		var sc := await _table()
		var f := start_frame(sc)
		var own: float = f["own"]
		var foe: float = f["foe"]
		var out: int = f["out"]
		near(own, 0.57, 0.03, "%d×%d: своя линия тяжёлых на доле высоты" % [size.x, size.y])
		near(foe, 0.13, 0.03, "%d×%d: чужая линия тяжёлых на доле высоты (ниже шапки)" % [size.x, size.y])
		eq(out, 0, "%d×%d: все тяжёлые обеих линий в кадре" % [size.x, size.y])
		# откат: точка взгляда в середине поля (старая привычка «смотреть в центр») —
		# своя линия уходит вниз, чужая — к середине
		sc.rig.set_view(Vector3.ZERO, 0.0, _defs.doctrine.camera_dist_start, true)
		await hooks.frames(1)
		var g := start_frame(sc)
		var gown: float = g["own"]
		ok(absf(gown - 0.57) > 0.03, "откат «взгляд в центр поля» краснеет: своя линия на %.2f" % gown)
		await _drop(sc)


# ───────────────────────── прогрев ─────────────────────────

const PROBE_WAIT_MS := 240000


## Проба прогрева в своём процессе (tests/probe_warmup.gd): тот же отрисовщик.
func _warm_probe(mode: String) -> Dictionary:
	var out := ProjectSettings.globalize_path("user://probe_warmup_%s.json" % mode)
	DirAccess.remove_absolute(out)
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--rendering-method", renderer(),
		"-s", "res://tests/probe_warmup.gd", "--", mode, out])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if not ok(pid > 0, "проба прогрева %s запустилась" % mode):
		return {}
	var t0 := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - t0 < PROBE_WAIT_MS:
		await hooks.frames(1)
	if OS.is_process_running(pid):
		OS.kill(pid)                      # только свой PID, никакого pkill
		ok(false, "проба прогрева %s зависла" % mode)
		return {}
	var j := JSON.new()
	var text := FileAccess.get_file_as_string(out)
	DirAccess.remove_absolute(out)
	if not ok(j.parse(text) == OK and typeof(j.data) == TYPE_DICTIONARY, "проба прогрева %s оставила итог: «%s»" % [mode, text]):
		return {}
	return dict(j.data)


func test_warmup_no_compilations_mid_game() -> void:
	var r := await _warm_probe("warm")
	if r.is_empty():
		return
	var before := whole(r["before"])
	var after := whole(r["after"])
	if renderer() != "forward_plus":
		# в Compatibility конвейеров Vulkan нет — счётчики сборок молчат; проверка — в Forward+
		note("%s: сборок конвейеров %d → %d (проверка — в Forward+)" % [renderer(), before, after])
		ok(true, "Compatibility: проверка прогрева не применима")
		return
	ok(before > 0, "счётчики сборок конвейеров отвечают (%d к 20-му кадру)" % before)
	eq(after, before, "после первых кадров новых сборок конвейеров нет (облёт по пути замера)")
	var rb := await _warm_probe("cold")
	if rb.is_empty():
		return
	var b2 := whole(rb["before"])
	var a2 := whole(rb["after"])
	ok(a2 > b2, "откат «эффекты впервые на 30-м кадре» краснеет: %d → %d" % [b2, a2])
	note("прогрев: как в игре %d → %d, откат %d → %d" % [before, after, b2, a2])


# ───────────────────────── сканер кнопок и замер кадров ─────────────────────────

func _visible_buttons(n: Node, out: Array[Button]) -> void:
	var b := n as Button
	if b != null and b.is_visible_in_tree():
		out.append(b)
	for c in n.get_children():
		_visible_buttons(c, out)


## Щелчок в центр каждой видимой кнопки: под точкой — она, и её счётчик вырос.
func _scan(report: BenchReport) -> PackedStringArray:
	var bad := PackedStringArray()
	var buttons: Array[Button] = []
	_visible_buttons(report, buttons)
	var vis := tree.root.get_visible_rect()
	for b in buttons:
		if b.disabled:
			continue
		var r := b.get_global_rect()
		if not vis.encloses(r):
			bad.append("«%s» не целиком на экране" % b.text)
			continue
		var under := await hooks.hovered_at(r.get_center())
		var c0: int = report.presses.get(b.text, 0)
		if b.text == "Закрыть":
			continue          # закрывает окно — жмём последней
		await hooks.click(r.get_center())
		var c1: int = report.presses.get(b.text, 0)
		if under != b or c1 != c0 + 1:
			bad.append("«%s»: под центром %s, нажатий %d → %d" % [b.text, under, c0, c1])
	var close := report.close_btn
	if close.is_visible_in_tree():
		var cc := close.get_global_rect().get_center()
		var u := await hooks.hovered_at(cc)
		await hooks.click(cc)
		if u != close or report.is_open():
			bad.append("«Закрыть»: под центром %s, окно %s" % [u, "открыто" if report.is_open() else "закрыто"])
	return bad


func test_bench_and_buttons() -> void:
	await hooks.set_window_size(Vector2i(1366, 768))
	var sc := await _table()
	var report := BenchReport.new()
	report.dry = true
	tree.root.add_child(report)
	var bench := FrameBench.new()
	tree.root.add_child(bench)
	var out := ProjectSettings.globalize_path("user://bench_test")
	DirAccess.make_dir_recursive_absolute(out)
	bench.out_dir = out
	bench.duration = 1.5
	bench.driver = sc.drive
	bench.title = "Капелла проверка"
	var got: Array = []
	bench.finished.connect(func(s: String, f: String) -> void: got.append_array([s, f]))
	var vsync := DisplayServer.window_get_vsync_mode()
	bench.start()
	var t0 := Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t0 < 120000:
		await hooks.frames(1)
	if not ok(got.size() == 2, "замер кадров кончился сам"):
		await _drop(sc)
		return
	var summary: String = got[0]
	var file: String = got[1]
	var lines := summary.split("\n")
	ok(lines.size() >= 8, "итог — 8 строк и больше (%d)" % lines.size())
	for key: String in ["Видеокарта:", "Отрисовщик:", "Окно:", "Кадров:", "не дольше 16,7 мс", "99% кадров", "худший кадр", "Вызовов отрисовки"]:
		ok(summary.contains(key), "в итоге есть «%s»" % key)
	ok(summary.contains("1366 × 768"), "размер окна в итоге: %s" % lines[3] if lines.size() > 3 else "")
	ok(FileAccess.file_exists(file), "файл замера записан: %s" % file)
	var text := FileAccess.get_file_as_string(file)
	var rows := 0
	for l in text.split("\n"):
		if l != "" and l[0].is_valid_int():
			rows += 1
	eq(rows, bench.frame_count(), "в файле строка на каждый кадр")
	ok(text.begins_with("# "), "в начале файла — тот же итог")
	eq(DisplayServer.window_get_vsync_mode(), vsync, "синхронизация с экраном вернулась после замера")
	DirAccess.remove_absolute(file)
	# сканер кнопок итога
	report.show_report(summary, file)
	await hooks.frames(2)
	var bad := await _scan(report)
	ok(bad.is_empty(), "сканер кнопок: %s" % "; ".join(bad))
	eq(report.presses.get("Скопировать ещё раз", 0), 1, "«Скопировать ещё раз» нажата один раз")
	# откат: прозрачная панель с фильтром STOP поверх окна (C135) — щелчок не доходит
	report.show_report(summary, file)
	var cover := ColorRect.new()
	cover.color = Color(0, 0, 0, 0)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	var layer := CanvasLayer.new()
	layer.layer = 99
	layer.add_child(cover)
	tree.root.add_child(layer)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await hooks.frames(2)
	var bad2 := await _scan(report)
	ok(bad2.size() >= 2, "откат «прозрачная панель поверх» краснеет: %d бед" % bad2.size())
	layer.queue_free()
	report.queue_free()
	bench.queue_free()
	await _drop(sc)


# ───────────────────────── строка замера и подсказка ─────────────────────────

static func _rect_of(c: Control) -> Rect2:
	return c.get_global_rect() if c.is_visible_in_tree() else Rect2()


func test_bench_progress_layout() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		await hooks.set_window_size(size)
		var main := MainScene.instantiate()
		tree.root.add_child(main)
		await hooks.frames(3)
		var fps: FpsCounter = main.get("fps")
		var report: BenchReport = main.get("report")
		var bench: FrameBench = main.get("bench")
		if not ok(fps != null and report != null and bench != null, "%d×%d: главная сцена завела счётчик, замер и итог" % [size.x, size.y]):
			main.queue_free()
			await hooks.frames(2)
			continue
		var tag := "%d×%d" % [size.x, size.y]
		ok(fps.hint.is_visible_in_tree(), "%s: в покое подсказка видна" % tag)
		var hint_rect := fps.hint.get_global_rect()
		await hooks.key(KEY_F5)
		await hooks.frames(2)
		ok(bench.running, "%s: F5 начал замер" % tag)
		var vis := tree.root.get_visible_rect()
		var pr := _rect_of(report.progress)
		ok(pr.has_area() and vis.encloses(pr), "%s: строка замера целиком на экране (%s)" % [tag, pr])
		ok(not fps.hint.is_visible_in_tree(), "%s: на время замера подсказка спрятана" % tag)
		ok(not pr.intersects(_rect_of(fps.hint)), "%s: строка замера не на подсказке" % tag)
		# откат: подсказка осталась на месте — на 1366 строка ложится прямо на неё
		var hit := pr.intersects(hint_rect)
		if size.x == 1366:
			ok(hit, "%s: откат «подсказка на месте» краснеет: строка %s, подсказка %s" % [tag, pr, hint_rect])
		# счётчик F3 открыт посреди замера — строка уходит под него, а не на него.
		# Название видеокарты бывает длинным («AMD Radeon RX 7900 XTX (Advanced Micro
		# Devices, Inc.)»), и счётчик шире, чем у llvmpipe здесь: ширина — как у такого
		await hooks.key(KEY_F3)
		fps.panel.custom_minimum_size.x = 560.0
		await hooks.frames(3)
		ok(fps.panel.is_visible_in_tree(), "%s: F3 открыл счётчик посреди замера" % tag)
		var pr2 := _rect_of(report.progress)
		var pan := _rect_of(fps.panel)
		ok(not pr2.intersects(pan), "%s: строка замера не на счётчике (строка %s, счётчик %s)" % [tag, pr2, pan])
		ok(vis.encloses(pr2), "%s: строка замера и под счётчиком целиком на экране" % tag)
		note("%s %s: строка замера %s, подсказка %s, счётчик %s, строка при счётчике %s" % [renderer(), tag, pr, hint_rect, pan, pr2])
		await hooks.key(KEY_F3)
		await hooks.frames(2)
		ok(not fps.hint.is_visible_in_tree(), "%s: F3 закрыт, замер идёт — подсказка всё ещё спрятана" % tag)
		await hooks.key(KEY_F5)
		await hooks.frames(2)
		ok(not bench.running and not report.progress.visible, "%s: F5 прервал замер, строки нет" % tag)
		ok(fps.hint.is_visible_in_tree(), "%s: замер прерван — подсказка вернулась" % tag)
		main.queue_free()
		await _drop_main()


func _drop_main() -> void:
	RenderingServer.set_default_clear_color(Color(0.012, 0.014, 0.025))
	await hooks.frames(3)


# ───────────────────────── снимки «Стола» ─────────────────────────

## Звёзды в пустом углу кадра: площади пятен ярких точек (не больше 400 пятен).
static func star_blobs(img: Image, rect: Rect2i) -> PackedInt32Array:
	var areas := PackedInt32Array()
	var seen := {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := lum(img.get_pixel(x, y))
			if c < 0.3 or seen.has(Vector2i(x, y)):
				continue
			# пятно — всё связное ярче половины пика
			var peak := c
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			var area := 0
			seen[Vector2i(x, y)] = true
			while not stack.is_empty() and area < 400:
				var p: Vector2i = stack.pop_back()
				area += 1
				for dpos: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q := p + dpos
					if not rect.has_point(q) or seen.has(q):
						continue
					if lum(img.get_pixel(q.x, q.y)) >= peak * 0.5:
						seen[q] = true
						stack.append(q)
			areas.append(area)
			if areas.size() >= 400:
				return areas
	return areas


static func median(a: PackedInt32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() >> 1])


func test_snapshots_1920_1366() -> void:
	var dir := _shots_dir()
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		await hooks.set_window_size(size)
		var sc := await _table()
		# стартовый вид: эффекты успели родиться — снимок «как в бою»
		for i in 6:
			await hooks.frames(1)
		var img := await _shot()
		var draws_start := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var path := dir.path_join("table_%s_%dx%d_start.png" % [renderer(), size.x, size.y])
		img.save_png(path)
		# корабли видны: у каждого тяжёлого рядом с его местом на экране есть светлая точка
		var cam := sc.rig.camera
		var dark := 0
		var heavy := 0
		for s in sc.ships:
			if not s.ship_id in [&"cruiser", &"capital"]:
				continue
			heavy += 1
			var p := cam.unproject_position(s.global_position)
			var best := 0.0
			for dy in range(-6, 7, 2):
				for dx in range(-6, 7, 2):
					var q := Vector2i(int(p.x) + dx, int(p.y) + dy)
					if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
						best = maxf(best, lum(img.get_pixel(q.x, q.y)))
			if best < 0.18:
				dark += 1
		eq(dark, 0, "%d×%d: все %d тяжёлых видны на снимке" % [size.x, size.y, heavy])
		# звёзды — точки: в пустом левом нижнем углу пятна маленькие
		var rect := Rect2i(4, int(size.y * 0.78), int(size.x * 0.16), int(size.y * 0.2))
		var blobs := star_blobs(img, rect)
		var med := median(blobs)
		ok(blobs.size() >= 5, "%d×%d: звёзд в углу кадра хватает для замера (%d)" % [size.x, size.y, blobs.size()])
		ok(med <= 6.0, "%d×%d: звезда — точка, а не пятно: медиана пятна %.0f точек" % [size.x, size.y, med])
		# откат: звёзды как на панораме 1024 в ширину (архитектура, 5.6: при обзоре 30°
		# звезда — пятно около 6 точек) — ячейка неба крупнее и звезда во всю ячейку
		sc.env.sky_mat.set_shader_parameter("star_cells", 160.0)
		sc.env.sky_mat.set_shader_parameter("px_angle", deg_to_rad(cam.fov) / size.y * 6.0)
		var img2 := await _shot()
		var med2 := median(star_blobs(img2, rect))
		ok(med2 > 6.0, "%d×%d: откат «звёзды панорамы 1024» краснеет: медиана пятна %.0f" % [size.x, size.y, med2])
		sc.env.sky_mat.set_shader_parameter("star_cells", 900.0)
		sc.env._fit_stars()
		# рабочий вид 2400 и дальний предел 5000 — для глаз и вызовов отрисовки
		sc.rig.set_view(Vector3(0, 0, 180), 0.0, 2400.0, true)
		var img3 := await _shot()
		img3.save_png(dir.path_join("table_%s_%dx%d_work.png" % [renderer(), size.x, size.y]))
		var draws_work := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		sc.rig.set_view(Vector3.ZERO, -0.5, 5000.0, true)
		var img4 := await _shot()
		img4.save_png(dir.path_join("table_%s_%dx%d_far.png" % [renderer(), size.x, size.y]))
		var draws_far := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		note("%s %d×%d: вызовов отрисовки — старт %d, рабочий вид %d, дальний предел %d; снимки в %s" % [renderer(), size.x, size.y, draws_start, draws_work, draws_far, dir])
		ok(draws_far > 0, "счётчик вызовов отрисовки отвечает")
		await _drop(sc)
