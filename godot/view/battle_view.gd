# view/battle_view.gd — бой на экране (архитектура, 3): модель шагает по 1/30 с,
# экран — 60+ кадров, и между ними — своя интерполяция.
# - Свой цикл по накопителю: скорость 1×/2×/4× — ЧИСЛОМ шагов за кадр, пауза —
#   ноль шагов, не больше MAX_STEPS за кадр (лучше медленнее, чем рывками). Шаг
#   модели не растягивается никогда (архитектура, 1 п. 4; ловушка 22 части 01).
# - Перед каждым шагом запоминаем прошлое положение и курс каждого корабля,
#   рисуем смесь прошлого и нынешнего с долей acc / STEP. Без неё сдвиг корабля
#   между кадрами на 60 Гц — 7, 0, 7, 0 точек (проба C). Корабль, появившийся
#   или прыгнувший на этом шаге (jumped_at_step), не смешивается — телепорт.
# - События забираем после КАЖДОГО шага (на 4× за кадр бывает несколько шагов,
#   а список событий шага чистится в его начале).
# - Высота — только картинка (09, 11.6): у каждого корабля своя постоянная высота
#   ±view.height_spread и покачивание ±view.bob; логика её не видит.
# - Факел — двумя числами модели (08, 7.2 п. 7): маршевый — от тяги по носу,
#   у носа — короткий огонь реверса. Тяжёлый по доктрине пятится носом к врагу,
#   и маршевый факел от реверса рисовал бы «газует вперёд, уезжая назад».
# Вид модель только ЧИТАЕТ: приказы идут дверью battle.queue (input/battle_input.gd).
extends Node3D

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const SpaceEnv := preload("res://view/space_env.gd")
const CameraRig := preload("res://view/camera_rig.gd")
const ShipVisual := preload("res://view/ship_visual.gd")
const ShipVisualScene := preload("res://view/ship_visual.tscn")
const FxPool := preload("res://view/fx_pool.gd")
const Picking := preload("res://input/picking.gd")
const BattleFx := preload("res://view/battle_fx.gd")

## 4× при 30 кадрах — 4 шага; больше — бой замедляется, а не дробит шаг (архитектура, 3).
const MAX_STEPS := 8
const SPEEDS: Array[int] = [1, 2, 4]

## Цвета сторон (C43): свои — холодные, чужие — тёплые.
const OWN_RING := Color(0.56, 1.0, 0.78)
const FOE_RING := Color(1.0, 0.42, 0.35)
const ORDER_FLASH := Color(0.56, 1.0, 0.78)
const PLUME := Color(0.55, 0.8, 1.0)
const PLUME_FOE := Color(1.0, 0.68, 0.38)
## Линия скорости выбранного — «скорость × 3 с» (06, 1.2).
const VEL_LINE_S := 3.0
## Линия к цели фокуса — красная, к точке атаки с ходу — оранжевая (03, 2.14–2.15).
const FOCUS_LINE := Color(1.0, 0.48, 0.35)
const AMOVE_LINE := Color(1.0, 0.66, 0.38)

var defs: Defs
var battle: Battle
var env: SpaceEnv
var rig: CameraRig
var fx: FxPool
## Огонь, снаряды, купола, пояса, орудие планеты — игровыми часами (с G2).
var bfx: BattleFx
## Корабль под курсором (uid, 0 — никого): его пояс и полный купол (09, 6.7; 04, ловушка 17).
var hover_uid := 0
## Сторона, за которую смотрит игрок (её корабли — «свои»).
var my_side := Ship.ATTACKER

var speed := 1
var paused := false
var acc := 0.0
## Своя интерполяция включена. false — рисуем нынешнее положение без смешивания:
## откат проверки плавности (tests/probe_smooth.gd) — сдвиг между кадрами 7, 0, 7, 0.
var smooth := true
## Сколько шагов модели сделал прошлый кадр (проверки скорости и паузы).
var steps_last_frame := 0
var steps_total := 0
## Повтор записи: на этом шаге вид встаёт (−1 — не встаёт). На нём сверяют отпечаток.
var stop_at_step := -1
## Настоящее время вида: покачивание, вспышки приказов — идут и на паузе.
var clock := 0.0

## Выбранные (uid). Состояние вида, а не модели: модель о выборе не знает.
var selection: Array[int] = []

var _vis: Dictionary[int, ShipVisual] = {}
var _prev: Dictionary[int, Vector3] = {}     # (x, z, курс) на прошлом шаге
var _height: Dictionary[int, float] = {}
var _bob: Dictionary[int, float] = {}
var _ring: Dictionary[int, MeshInstance3D] = {}
var _plume: Dictionary[int, Array] = {}      # [маршевые MeshInstance3D…], реверс — последним
var _plume_len: Dictionary[int, PackedFloat64Array] = {}
var _nose: Dictionary[int, Vector2] = {}     # (z носа, y середины) в осях модели
var _lines: MeshInstance3D
var _lines_mesh: ImmediateMesh
var _lines_mat: StandardMaterial3D
var _plume_mesh: CylinderMesh
var _plume_mat: StandardMaterial3D
var _plume_mat_foe: StandardMaterial3D
var _ring_mat_own: StandardMaterial3D
var _ring_mat_foe: StandardMaterial3D
var _fx_rng := RandomNumberGenerator.new()


## Собрать вид боя. with_env = false — без неба и планеты (проба плавности: на чёрном
## фоне корабль меряется по точкам кадра).
func setup(p_defs: Defs, p_battle: Battle, with_env: bool = true) -> void:
	defs = p_defs
	battle = p_battle
	my_side = battle.player_side
	# высота и покачивание — свой генератор картинки с зерном боя: исход боя от того,
	# рисуется ли он, не зависит (архитектура, 2.11), а картинка повторяема
	_fx_rng.seed = battle.battle_seed ^ 0x2c1b3c6d
	if with_env:
		env = SpaceEnv.new()
		env.name = "SpaceEnv"
		add_child(env)
	else:
		_bare_env()
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.setup(defs.doctrine, defs.consts.field_half)
	rig.start_view(defs.doctrine, my_side == Ship.ATTACKER)
	if env != null:
		env._fit_stars()
	fx = FxPool.new()
	fx.name = "Fx"
	fx.setup(64, 128)
	add_child(fx)
	_make_materials()
	_lines_mesh = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.name = "Lines"
	_lines.mesh = _lines_mesh
	_lines.material_override = _lines_mat
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)
	bfx = BattleFx.new()
	bfx.name = "BattleFx"
	add_child(bfx)
	bfx.setup(battle, my_side, point_of, visual_of)
	for s in battle.ships:
		_add_visual(s)
	draw_state()


## Чёрный фон и простой свет — для пробы плавности.
func _bare_env() -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	var we := WorldEnvironment.new()
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	add_child(sun)


func _make_materials() -> void:
	_lines_mat = StandardMaterial3D.new()
	_lines_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lines_mat.vertex_color_use_as_albedo = true
	_lines_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lines_mat.no_depth_test = true
	_plume_mesh = CylinderMesh.new()
	_plume_mesh.top_radius = 0.0
	_plume_mesh.bottom_radius = 1.0
	_plume_mesh.height = 1.0
	_plume_mesh.radial_segments = 10
	_plume_mesh.rings = 1
	_plume_mat = _glow(PLUME)
	_plume_mat_foe = _glow(PLUME_FOE)
	_ring_mat_own = _flat(OWN_RING)
	_ring_mat_foe = _flat(FOE_RING)


static func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c.r, c.g, c.b, 0.8)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c.r, c.g, c.b, 0.85)
	m.no_depth_test = true
	m.disable_receive_shadows = true
	return m


func clan_of(s: Ship) -> StringName:
	return battle.sides[s.side].clan


func _add_visual(s: Ship) -> void:
	if _vis.has(s.uid):
		return
	var v := ShipVisualScene.instantiate() as ShipVisual
	if not v.setup(clan_of(s), s.def.id):
		v.free()
		push_error("корабль %s.%s не встал: модель не загрузилась" % [clan_of(s), s.def.id])
		return
	v.name = "ship_%d" % s.uid
	add_child(v)
	_vis[s.uid] = v
	var spread := defs.doctrine.view_height_spread
	_height[s.uid] = _fx_rng.randf_range(-spread, spread)
	_bob[s.uid] = _fx_rng.randf_range(0.0, TAU)
	_add_ring(s, v)
	_add_plumes(s, v)


## Кольцо выбора — плоское, по размеру модели; поверх всего (видно сквозь корпус).
func _add_ring(s: Ship, v: ShipVisual) -> void:
	var r := maxf(v.length(), v.width()) * 0.58
	var tm := TorusMesh.new()
	tm.inner_radius = r
	tm.outer_radius = r + maxf(2.0, r * 0.05)
	tm.rings = 48
	tm.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.name = "ring"
	mi.mesh = tm
	mi.scale = Vector3(1.0, 0.05, 1.0)
	mi.material_override = _ring_mat_own if s.side == my_side else _ring_mat_foe
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	v.add_child(mi)
	_ring[s.uid] = mi


## Факелы: конус у каждого сопла (узлы engine_i модели, размер — из обмера) и один —
## у носа, для реверса. Длину задаёт тяга шага (thrust_fwd / thrust_rev).
func _add_plumes(s: Ship, v: ShipVisual) -> void:
	var list: Array = []
	var lens := PackedFloat64Array()
	var nodes: Dictionary = v.record.get("nodes", {})
	var mat := _plume_mat if s.side == my_side else _plume_mat_foe
	for key: String in nodes:
		if not key.begins_with("engine_"):
			continue
		var rec: Dictionary = nodes[key]
		var size: float = rec.get("size", 10.0)
		var at := v.part(StringName(key))
		if at == null:
			continue
		var mi := _plume_instance(mat)
		# конус остриём назад (+z модели): ось цилиндра y поворотом +90° ложится на +z
		mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		at.add_child(mi)
		list.append(mi)
		lens.append(size)
	# реверс — короткий огонь у носа (08, 7.2 п. 7)
	var aabb: Array = v.record.get("aabb", [])
	var nose_z := -v.length() * 0.5
	var mid_y := 0.0
	if aabb.size() == 2:
		var lo: Array = aabb[0]
		var hi: Array = aabb[1]
		var lz: float = lo[2]
		var ly: float = lo[1]
		var hy: float = hi[1]
		nose_z = lz
		mid_y = (ly + hy) * 0.5
	var rv := _plume_instance(mat)
	rv.rotation_degrees = Vector3(-90.0, 0.0, 0.0)       # остриём вперёд (−z)
	rv.position = Vector3(0.0, mid_y, nose_z)
	v.add_child(rv)
	_nose[s.uid] = Vector2(nose_z, mid_y)
	list.append(rv)
	lens.append(maxf(v.width() * 0.22, 6.0))
	_plume[s.uid] = list
	_plume_len[s.uid] = lens


func _plume_instance(mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "plume"
	mi.mesh = _plume_mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


# ───────────────────────── цикл: шаги по накопителю ─────────────────────────

func _process(delta: float) -> void:
	clock += delta
	if battle == null:
		return
	advance(delta)
	draw_state()


## Сделать столько шагов модели, сколько набежало за кадр (не больше MAX_STEPS).
## → сколько сделано. Тесты зовут её с постоянным delta.
func advance(delta: float) -> int:
	var n := 0
	if not paused and not battle.over:
		acc += minf(delta, 0.1) * float(speed)
		# допуск на двоичную дробь: 2 × (1/60) обязан дать ровно один шаг
		while acc >= Battle.STEP - 1e-9 and n < MAX_STEPS:
			if stop_at_step >= 0 and battle.steps >= stop_at_step:
				acc = 0.0
				break
			_remember_prev()
			battle.step()
			_consume(battle.events)
			acc -= Battle.STEP
			n += 1
		if n == MAX_STEPS:
			acc = 0.0               # не копим долг: лучше медленнее, чем рывками
		acc = maxf(acc, 0.0)
	steps_last_frame = n
	steps_total += n
	return n


func _remember_prev() -> void:
	for s in battle.ships:
		if not s.dead:
			_prev[s.uid] = Vector3(s.pos.x, s.pos.y, s.yaw)
	bfx.remember()


## События ЭТОГО шага (архитектура, 2.10): новые корабли, гипер, выход, итог; огонь
## и снаряды — в BattleFx.
func _consume(events: Array[Array]) -> void:
	for e in events:
		var kind: StringName = e[0]
		bfx.consume(e)
		match kind:
			&"spawn":
				var u: int = e[1]
				var s := battle.ship_by_uid(u)
				if s != null:
					_add_visual(s)
			&"jump_out", &"jump_in":
				var u2: int = e[1]
				var s2 := battle.ship_by_uid(u2)
				if s2 != null and _vis.has(u2):
					fx.flash(_point(s2, 1.0), Color(0.7, 0.85, 1.0), maxf(_vis[u2].length(), 30.0) * 1.6, 0.6, 2.5)


## Доля шага, которую рисуем: прошлое → нынешнее.
func alpha() -> float:
	return clampf(acc / Battle.STEP, 0.0, 1.0) if smooth else 1.0


## Нарисованное положение (x, z) и курс корабля на этом кадре.
func _blend(s: Ship, a: float) -> Vector3:
	var cur := Vector3(s.pos.x, s.pos.y, s.yaw)
	if s.jumped_at_step == battle.steps or not _prev.has(s.uid):
		return cur                       # телепорт: без смешивания (архитектура, 3)
	var p: Vector3 = _prev[s.uid]
	return Vector3(lerpf(p.x, cur.x, a), lerpf(p.y, cur.y, a), lerp_angle(p.z, cur.z, a))


## Точка корабля в мире на доле шага a (с высотой-картинкой).
func point_of(s: Ship, a: float) -> Vector3:
	return _point(s, a)


## Точка корабля в мире на этом кадре (с высотой-картинкой).
func _point(s: Ship, a: float) -> Vector3:
	var b := _blend(s, a)
	return Vector3(b.x, _y(s.uid), b.y)


func _y(uid: int) -> float:
	var h: float = _height.get(uid, 0.0)
	var ph: float = _bob.get(uid, 0.0)
	return h + sin(clock * 0.6 + ph) * defs.doctrine.view_bob


func draw_state() -> void:
	var a := alpha()
	clean_selection()
	for s in battle.ships:
		var v: ShipVisual = _vis.get(s.uid)
		if v == null:
			continue
		var show := Picking.shown(s, my_side)
		v.visible = show
		if not show:
			continue
		var b := _blend(s, a)
		v.position = Vector3(b.x, _y(s.uid), b.y)
		v.rotation = Vector3(0.0, b.z, 0.0)
		var ring: MeshInstance3D = _ring.get(s.uid)
		if ring != null:
			ring.visible = s.uid in selection
		_draw_plumes(s)
	_draw_lines(a)
	fx.set_time(clock)
	# игровые часы на этом кадре: начало шага + доля шага (на паузе стоят)
	bfx.draw(a, battle.time - Battle.STEP + a * Battle.STEP, selection, hover_uid)


func _draw_plumes(s: Ship) -> void:
	var list: Array = _plume.get(s.uid, [])
	var lens: PackedFloat64Array = _plume_len.get(s.uid, PackedFloat64Array())
	var n := list.size()
	for i in n:
		var mi: MeshInstance3D = list[i]
		var k := s.thrust_rev if i == n - 1 else s.thrust_fwd
		if k < 0.02:
			mi.visible = false
			continue
		mi.visible = true
		# маршевый: от 0,6 до 2 размеров сопла по тяге; реверс — короткий, у носа
		var l := lens[i] * (0.6 + 1.4 * k) if i < n - 1 else lens[i] * k
		var w := lens[i] * 0.22
		mi.scale = Vector3(w, l, w)
		# конус стоит основанием у сопла (у носа): центр — на половине длины по оси
		if i < n - 1:
			mi.position = Vector3(0.0, 0.0, l * 0.5)
		else:
			var nz: Vector2 = _nose.get(s.uid, Vector2.ZERO)
			mi.position = Vector3(0.0, nz.y, nz.x - l * 0.5)


## Линии выбранных: к точке приказа (мятная) и скорость × 3 с (белая).
func _draw_lines(a: float) -> void:
	_lines_mesh.clear_surfaces()
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	var go := Color(OWN_RING.r, OWN_RING.g, OWN_RING.b, 0.45)
	var vel := Color(1, 1, 1, 0.5)
	for u in selection:
		var s := battle.ship_by_uid(u)
		if s == null or not Picking.shown(s, my_side):
			continue
		var p := _point(s, a)
		if s.side == my_side and s.has_move:
			pts.append_array([p, Vector3(s.move_to.x, 0.0, s.move_to.y)])
			cols.append_array([go, go])
		if s.side == my_side and s.has_amove:
			var am := Color(AMOVE_LINE.r, AMOVE_LINE.g, AMOVE_LINE.b, 0.55)
			pts.append_array([p, Vector3(s.amove.x, 0.0, s.amove.y)])
			cols.append_array([am, am])
		var fz := s.forced as Ship
		if s.side == my_side and fz != null and not fz.dead and Picking.shown(fz, my_side):
			var fc := Color(FOCUS_LINE.r, FOCUS_LINE.g, FOCUS_LINE.b, 0.6)
			pts.append_array([p, _point(fz, a)])
			cols.append_array([fc, fc])
		if s.vel.length_squared() > 1.0:
			pts.append_array([p, p + Vector3(s.vel.x, 0.0, s.vel.y) * VEL_LINE_S])
			cols.append_array([vel, vel])
	if pts.is_empty():
		return                           # пустую поверхность ImmediateMesh не заводит
	_lines_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in pts.size():
		_lines_mesh.surface_set_color(cols[i])
		_lines_mesh.surface_add_vertex(pts[i])
	_lines_mesh.surface_end()


# ───────────────────────── что знает о кораблях выбор мышью ─────────────────────────

## Нарисованная точка корабля (та, что на экране сейчас).
func ship_point(s: Ship) -> Vector3:
	var v: ShipVisual = _vis.get(s.uid)
	return v.global_position if v != null else Vector3(s.pos.x, 0.0, s.pos.y)


func visual_of(s: Ship) -> ShipVisual:
	return _vis.get(s.uid)


## Капсула корпуса в мире (архитектура, 4): ось вдоль носа по длине модели,
## радиус — половина ширины. → [a, b, r]. Нет модели — шар по hull.
func capsule(s: Ship) -> Array:
	var v: ShipVisual = _vis.get(s.uid)
	if v == null:
		var c := Vector3(s.pos.x, 0.0, s.pos.y)
		return [c, c, s.hull]
	var r := v.width() * 0.5
	var z0 := -v.length() * 0.5
	var z1 := v.length() * 0.5
	var yc := 0.0
	var aabb: Array = v.record.get("aabb", [])
	if aabb.size() == 2:
		var lo: Array = aabb[0]
		var hi: Array = aabb[1]
		var lz: float = lo[2]
		var hz: float = hi[2]
		var ly: float = lo[1]
		var hy: float = hi[1]
		z0 = lz
		z1 = hz
		yc = (ly + hy) * 0.5
	var za := minf(z0 + r, (z0 + z1) * 0.5)
	var zb := maxf(z1 - r, (z0 + z1) * 0.5)
	var t := v.global_transform
	return [t * Vector3(0.0, yc, za), t * Vector3(0.0, yc, zb), r]


## Рамка всего нарисованного у корабля — с факелами и кольцом. Только для отката
## проверки «малый за факелом» (input/picking.gd, rollback_drawn_box).
func drawn_box(s: Ship) -> AABB:
	var v: ShipVisual = _vis.get(s.uid)
	if v == null:
		return AABB()
	var out := AABB(v.global_position, Vector3.ZERO)
	var stack: Array[Node] = [v]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var vi := n as VisualInstance3D
		if vi != null and vi.is_visible_in_tree():
			out = out.merge(vi.global_transform * vi.get_aabb())
		stack.append_array(n.get_children())
	return out


# ───────────────────────── скорость, пауза ─────────────────────────

## Пробел: пауза и обратно — с прежней скоростью, а не 1× (06, 1.6).
func toggle_pause() -> void:
	paused = not paused


func set_speed(n: int) -> void:
	speed = n if n in SPEEDS else 1
	paused = false


## Вспышка в точке приказа (06, 1.4): мятная — идти.
func order_flash(p: Vector3) -> void:
	fx.flash(p + Vector3(0.0, 2.0, 0.0), ORDER_FLASH, 46.0, 0.45, 1.6)


## Оранжевая — атака с ходу (03, 2.15).
func amove_flash(p: Vector3) -> void:
	fx.flash(p + Vector3(0.0, 2.0, 0.0), AMOVE_LINE, 46.0, 0.45, 1.6)


## Красная — на цели фокуса (03, 2.14).
func target_flash(s: Ship) -> void:
	fx.flash(ship_point(s), FOCUS_LINE, maxf(s.def.radius * 3.0, 24.0), 0.5, 1.8)


## Выбор без мёртвых и ушедших (06, 2.5: «выбор чистится сам»).
func clean_selection() -> void:
	var keep: Array[int] = []
	for u in selection:
		var s := battle.ship_by_uid(u)
		if s != null and Picking.shown(s, my_side):
			keep.append(u)
	selection = keep
