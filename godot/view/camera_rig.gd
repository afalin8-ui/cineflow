# view/camera_rig.gd — камера «стол» (доктрина 09, раздел 11; архитектура, 5.8).
# Перспектива, обзор 30°, наклон 55° ПОСТОЯННЫЙ, точка взгляда всегда на y = 0,
# расстояние 500…5000. Поворот вокруг вертикали: Q/E и протяжка ПКМ вбок.
# Колесо — к курсору: точка стола под курсором остаётся под ним (06, 2.2.7).
# Стрелки и край экрана — сдвиг в осях экрана со скоростью dist × 0,44 в секунду.
# Точка взгляда и расстояние догоняют выбранные ОДНОЙ долей сглаживания
# (06, ловушка 7): иначе приближение к курсору шло бы не по прямой.
#
# Клавиши камера слушает сама, по нажатию и отпусканию (06, 2.2.4: не опрашивать
# Input глобально — так карту не заглушит ни одно окно); клавиши — по месту
# (physical_keycode), повтор (echo) не нажатие. Жест ПКМ, начатый на поле,
# дослушивается в _input (архитектура, 6.5).
extends Node3D

const Defs := preload("res://sim/defs.gd")

const SMOOTH_KEEP := 0.0012      # доля, что остаётся за секунду (06, 2.2.2)
const EDGE_PX := 10.0            # полоса края экрана (06, 2.1)
const DRAG_SLOP := 6.0           # порог «щёлкнул / потянул» (06, 2.1)

var camera: Camera3D
# Числа камеры — из доктрины (doctrine.json → camera.*) и поля боя (space_data →
# battle_constants.field_half), их ставит setup(); своих здесь нет.
var field := 0.0                 # точка взгляда заперта в ±field (06, 2.1)
var tilt_deg := 0.0
var dist_min := 0.0
var dist_max := 0.0
var edge_k := 0.0
var wheel_step := 0.0
var rotate_speed := 0.0
var drag_k := 0.0

## Куда камера хочет смотреть и откуда — выбор игрока.
var look := Vector3.ZERO
var dist := 0.0
var yaw := 0.0
## Где камера сейчас (догоняет look и dist).
var s_look := Vector3.ZERO
var s_dist := 0.0

## false — ввод не трогает камеру (замер кадров ведёт её сам по пути).
var input_enabled := true
## Край экрана двигает карту, только когда мышь уже была в окне: в окне без мыши
## (тесты, xvfb) курсор стоит в (0, 0) — это угол, и карта ехала бы сама.
var edge_enabled := true

var _keys: Dictionary[Key, bool] = {}
var _mouse_seen := false
var _drag := false
var _drag_from := Vector2.ZERO
var _drag_moved := false


func setup(d: Defs.Doctrine, field_half: float) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	field = field_half
	camera = Camera3D.new()
	camera.fov = d.camera_fov_deg
	camera.near = d.camera_near
	camera.far = d.camera_far
	camera.current = true
	add_child(camera)
	tilt_deg = d.camera_tilt_deg
	dist_min = d.camera_dist_min
	dist_max = d.camera_dist_max
	edge_k = d.camera_edge_speed_k
	wheel_step = d.camera_wheel_step
	rotate_speed = d.camera_rotate_speed
	drag_k = d.camera_drag_k
	start_view(d, true)


## Стартовый вид (09, 11.4): атакующий смотрит с yaw 0 на точку z = +start_look_z.
func start_view(d: Defs.Doctrine, attacker: bool) -> void:
	set_view(Vector3(0.0, 0.0, d.camera_start_look_z * (1.0 if attacker else -1.0)), 0.0 if attacker else PI, d.camera_dist_start, true)


## Поставить камеру; instant — сразу, без сглаживания.
func set_view(p_look: Vector3, p_yaw: float, p_dist: float, instant: bool) -> void:
	look = _clamp_look(p_look)
	yaw = p_yaw
	dist = clampf(p_dist, dist_min, dist_max)
	if instant:
		s_look = look
		s_dist = dist
	_place(s_look, s_dist)


func _clamp_look(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, -field, field), 0.0, clampf(p.z, -field, field))


## Положение камеры для точки взгляда и расстояния (06, 2.2.1, наклон постоянный).
func eye_for(p_look: Vector3, p_dist: float) -> Vector3:
	var t := deg_to_rad(tilt_deg)
	return p_look + Vector3(sin(yaw) * cos(t) * p_dist, sin(t) * p_dist, cos(yaw) * cos(t) * p_dist)


func _place(p_look: Vector3, p_dist: float) -> void:
	if camera == null:
		return
	camera.global_position = eye_for(p_look, p_dist)
	camera.look_at(p_look, Vector3.UP)


## Сдвиг в осях экрана (06, 2.2.3): fx > 0 — вправо, fz > 0 — к себе.
func move_screen(fx: float, fz: float, amount: float) -> void:
	var s := sin(yaw)
	var c := cos(yaw)
	look = _clamp_look(look + Vector3((fx * c + fz * s) * amount, 0.0, (-fx * s + fz * c) * amount))


## Точка стола (y = 0) под точкой экрана — так, как камера ВСТАНЕТ (06, 2.2.7:
## «призрак» в выбранном положении), чтобы приближение шло по прямой.
func ground_at(screen: Vector2, ghost: bool = true) -> Variant:
	if camera == null:
		return null
	var keep := camera.global_transform
	if ghost:
		_place(look, dist)
	var o := camera.project_ray_origin(screen)
	var n := camera.project_ray_normal(screen)
	if ghost:
		camera.global_transform = keep
	if n.y > -0.02:
		return null
	return Plane(Vector3.UP, 0.0).intersects_ray(o, n)


## Колесо к курсору: точка под курсором остаётся на месте.
func zoom_at(factor: float, screen: Vector2) -> void:
	var d0 := dist
	var d1 := clampf(d0 * factor, dist_min, dist_max)
	if is_equal_approx(d1, d0):
		return
	var hit: Variant = ground_at(screen)
	dist = d1
	if hit == null:
		return
	var p: Vector3 = hit
	var k := 1.0 - d1 / d0
	look = _clamp_look(look + (p - look) * k)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var steps := mb.factor if mb.factor > 0.0 else 1.0
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			zoom_at(exp(dir * wheel_step * steps), mb.position)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = true
			_drag_moved = false
			_drag_from = mb.position
		return
	var k := event as InputEventKey
	if k != null and not k.echo and _camera_key(k.physical_keycode):
		_keys[k.physical_keycode] = k.pressed
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		_mouse_seen = true
		if _drag and input_enabled:
			if not _drag_moved and (absf(mm.position.x - _drag_from.x) > DRAG_SLOP or absf(mm.position.y - _drag_from.y) > DRAG_SLOP):
				_drag_moved = true
			if _drag_moved:
				# потянул вправо — yaw уменьшается, ближняя часть стола едет за мышью (06, 2.2.6)
				yaw -= mm.relative.x * drag_k
		return
	var mb := event as InputEventMouseButton
	# отпускание ПКМ ловим где угодно — жест мог кончиться над панелью (архитектура, 6.5)
	if mb != null and not mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		_drag = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_keys.clear()
		_drag = false


static func _camera_key(code: Key) -> bool:
	return code in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_Q, KEY_E]


func _held(code: Key) -> bool:
	return _keys.get(code, false)


func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	if input_enabled:
		var fx := 0.0
		var fz := 0.0
		if _held(KEY_UP): fz -= 1.0
		if _held(KEY_DOWN): fz += 1.0
		if _held(KEY_LEFT): fx -= 1.0
		if _held(KEY_RIGHT): fx += 1.0
		if _held(KEY_Q): yaw += rotate_speed * dt
		if _held(KEY_E): yaw -= rotate_speed * dt
		var e := _edge_dir()
		fx = clampf(fx + e.x, -1.0, 1.0)
		fz = clampf(fz + e.y, -1.0, 1.0)
		if fx != 0.0 or fz != 0.0:
			move_screen(fx, fz, dist * edge_k * dt)
	var t := 1.0 - pow(SMOOTH_KEEP, dt)
	s_look += (look - s_look) * t
	s_dist += (dist - s_dist) * t
	_place(s_look, s_dist)


## Край экрана: в полосе EDGE_PX у края — туда и едем (06, 2.3.9).
func _edge_dir() -> Vector2:
	if not edge_enabled or not _mouse_seen or not get_window().has_focus():
		return Vector2.ZERO
	var size := get_viewport().get_visible_rect().size
	var p := get_viewport().get_mouse_position()
	if p.x < 0.0 or p.y < 0.0 or p.x > size.x or p.y > size.y:
		return Vector2.ZERO
	var d := Vector2.ZERO
	if p.x <= EDGE_PX: d.x = -1.0
	elif p.x >= size.x - EDGE_PX: d.x = 1.0
	if p.y <= EDGE_PX: d.y = -1.0
	elif p.y >= size.y - EDGE_PX: d.y = 1.0
	return d


## Доля высоты экрана, на которой лежит точка стола (для стартового кадра, 09, 11.4).
func screen_frac_y(p: Vector3) -> float:
	var h := get_viewport().get_visible_rect().size.y
	return camera.unproject_position(p).y / h
