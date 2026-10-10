# Камера «стол» без окна (ярус ui; 09, раздел 11; часть 06, 2.2): настоящими
# событиями ввода, как жмёт человек. Каждая проверка — с откатом.
# - колесо к курсору: точка стола под курсором остаётся под ним (откат —
#   приближение к середине экрана: точка уезжает);
# - Q/E вертят, повтор (echo) — не нажатие, отпускание останавливает;
# - стрелка «вверх» везёт вглубь со скоростью dist × 0,44;
# - протяжка ПКМ вбок вертит (0,005 рад на точку), отпускание где угодно её кончает;
# - пределы 500…5000, наклон постоянный;
# - край экрана не тянет карту, пока мыши в окне не было (откат — тянет).
# Плюс F5 в главной сцене: замер начинается, камера отдана пути, F5 — прервать.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const CameraRig := preload("res://view/camera_rig.gd")
const MainScene := preload("res://main.tscn")

var _defs: Defs


func _rig() -> CameraRig:
	if _defs == null:
		_defs = Defs.load_default({}) as Defs
	var rig := CameraRig.new()
	tree.root.add_child(rig)
	rig.setup(_defs.doctrine)
	rig.edge_enabled = false
	await hooks.frames(1)
	return rig


## Догнать выбранное мгновенно (сглаживание — своя проверка ниже).
static func settle(rig: CameraRig) -> void:
	rig.s_look = rig.look
	rig.s_dist = rig.dist
	rig.set_view(rig.look, rig.yaw, rig.dist, true)


func _wheel(pos: Vector2, up: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.factor = 1.0
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	await hooks.frames(1)
	var rel := ev.duplicate() as InputEventMouseButton
	rel.pressed = false
	Input.parse_input_event(rel)
	await hooks.frames(1)


func test_wheel_zooms_to_cursor() -> void:
	await hooks.set_window_size(Vector2i(1366, 768))
	var rig := await _rig()
	var p := Vector2(1000, 300)
	var g0: Vector3 = rig.ground_at(p, false)
	var d0 := rig.dist
	for i in 3:
		await _wheel(p, true)
	ok(rig.dist < d0 * 0.75, "три щелчка колеса приблизили: %.0f → %.0f" % [d0, rig.dist])
	near(rig.dist, d0 * exp(-3.0 * _defs.doctrine.camera_wheel_step), 1.0, "шаг колеса exp(0,12) на щелчок")
	settle(rig)
	var g1: Vector3 = rig.ground_at(p, false)
	ok(g1.distance_to(g0) < 2.0, "точка под курсором осталась на месте: сдвиг %.2f" % g1.distance_to(g0))
	# откат: приближение к середине экрана (точка взгляда не едет) — точка под курсором уезжает
	rig.set_view(Vector3(0, 0, 470), 0.0, d0, true)
	var g2: Vector3 = rig.ground_at(p, false)
	rig.set_view(rig.look, rig.yaw, d0 * exp(-0.36), true)
	var g3: Vector3 = rig.ground_at(p, false)
	ok(g3.distance_to(g2) > 50.0, "откат «к середине экрана» краснеет: сдвиг %.0f" % g3.distance_to(g2))
	# пределы и наклон
	for i in 40:
		await _wheel(p, true)
	near(rig.dist, _defs.doctrine.camera_dist_min, 0.01, "ближе 500 не приближается")
	for i in 60:
		await _wheel(p, false)
	near(rig.dist, _defs.doctrine.camera_dist_max, 0.01, "дальше 5000 не отъезжает")
	settle(rig)
	var dir := (rig.camera.global_position - rig.s_look).normalized()
	near(rad_to_deg(asin(dir.y)), 55.0, 0.01, "наклон постоянный — 55°")
	rig.queue_free()
	await hooks.frames(1)


func _hold(code: Key, frames: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await hooks.frames(frames)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await hooks.frames(1)


func test_keys_rotate_and_pan() -> void:
	var rig := await _rig()
	var y0 := rig.yaw
	await _hold(KEY_Q, 10)
	ok(rig.yaw > y0, "Q вертит: %.3f → %.3f" % [y0, rig.yaw])
	var y1 := rig.yaw
	await hooks.frames(5)
	eq(rig.yaw, y1, "отпустил Q — поворот кончился")
	await _hold(KEY_E, 10)
	ok(rig.yaw < y1, "E вертит обратно")
	# повтор (echo) — не нажатие: одиночный echo без нажатия камеру не трогает
	var y2 := rig.yaw
	await hooks.key(KEY_Q, KEY_NONE, true)
	await hooks.frames(3)
	eq(rig.yaw, y2, "повтор Q (echo) камеру не вертит")
	# стрелка вверх везёт вглубь (−z при повороте 0)
	rig.set_view(Vector3(0, 0, 470), 0.0, 3990.0, true)
	var t0 := Time.get_ticks_usec()
	await _hold(KEY_UP, 8)
	var sec := (Time.get_ticks_usec() - t0) / 1e6
	ok(rig.look.z < 470.0, "стрелка вверх — вглубь стола: z %.1f" % rig.look.z)
	ok(470.0 - rig.look.z <= 3990.0 * _defs.doctrine.camera_edge_speed_k * sec * 1.05 + 1.0, "скорость не больше dist × 0,44 в секунду")
	# русская раскладка: клавиша по месту (06, ловушка 49) — «й» на месте Q
	var y3 := rig.yaw
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_Q
	ev.keycode = 1081 as Key
	ev.pressed = true
	Input.parse_input_event(ev)
	await hooks.frames(5)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await hooks.frames(1)
	ok(rig.yaw > y3, "Q по месту при русской раскладке вертит")
	rig.queue_free()
	await hooks.frames(1)


func test_rmb_drag_rotates() -> void:
	await hooks.set_window_size(Vector2i(1366, 768))
	var rig := await _rig()
	var c := Vector2(683, 384)
	var y0 := rig.yaw
	await hooks.move(c)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_RIGHT
	down.pressed = true
	down.button_mask = MOUSE_BUTTON_MASK_RIGHT
	down.position = c
	down.global_position = c
	Input.parse_input_event(down)
	await hooks.frames(1)
	# по одному движению на кадр: Input сливает движения одного кадра
	for i in 5:
		var mv := InputEventMouseMotion.new()
		mv.position = c + Vector2(20 * (i + 1), 0)
		mv.global_position = mv.position
		mv.relative = Vector2(20, 0)
		mv.button_mask = MOUSE_BUTTON_MASK_RIGHT
		Input.parse_input_event(mv)
		await hooks.frames(1)
	near(rig.yaw, y0 - 100.0 * _defs.doctrine.camera_drag_k, 1e-6, "протяжка ПКМ на 100 точек вправо — поворот на −0,5 рад")
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	up.button_mask = 0
	Input.parse_input_event(up)
	await hooks.frames(1)
	var y1 := rig.yaw
	var mv2 := InputEventMouseMotion.new()
	mv2.position = c + Vector2(300, 0)
	mv2.relative = Vector2(50, 0)
	Input.parse_input_event(mv2)
	await hooks.frames(1)
	eq(rig.yaw, y1, "после отпускания ПКМ движение мыши не вертит")
	rig.queue_free()
	await hooks.frames(1)


func test_edge_waits_for_mouse() -> void:
	await hooks.set_window_size(Vector2i(1366, 768))
	var rig := await _rig()
	rig.edge_enabled = true
	var l0 := rig.look
	await hooks.frames(10)
	eq(rig.look, l0, "мыши в окне не было — край экрана карту не тянет (курсор в (0, 0) — это угол)")
	ok(rig._edge_dir() == Vector2.ZERO, "направление края — ноль")
	# откат: «мышь уже была в окне» — курсор в углу (0, 0), и карта едет сама
	rig._mouse_seen = true
	await hooks.frames(10)
	ok(rig.look != l0, "откат «край без проверки мыши» краснеет: точка взгляда уехала в %s" % rig.look)
	rig.queue_free()
	await hooks.frames(1)


func test_f5_starts_and_cancels_bench() -> void:
	await hooks.set_window_size(Vector2i(1366, 768))
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	await hooks.frames(3)
	var bench: Node = main.get("bench")
	var view: Node = main.get("view")
	if not ok(bench != null and view != null, "в главной сцене есть замер и «Стол»"):
		main.queue_free()
		return
	var rig: CameraRig = view.get("rig")
	await hooks.key(KEY_F5)
	ok(flag(bench.get("running")), "F5 начал замер")
	ok(not rig.input_enabled, "на время замера камеру ведёт путь, а не ввод")
	await hooks.key(KEY_F5, KEY_NONE, true)
	ok(flag(bench.get("running")), "повтор F5 (echo) замер не прервал")
	await hooks.key(KEY_F5)
	ok(not flag(bench.get("running")), "F5 во время замера — прервать")
	ok(rig.input_enabled, "после прерывания камера снова у игрока")
	main.queue_free()
	await hooks.frames(2)
