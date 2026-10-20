# view/hyper_fx.gd — гипер на экране (08, 1.3 и 2.11; план GЭ, п. 2): упрощённая воронка со
# СРОКАМИ модели, игровым временем (на паузе стоит, на 4× идёт вчетверо).
# - Уход: воронка раскрывается перед носом за OPEN_LEFT (2,4 с) до перехода — по часам модели
#   `hyper_left` — и едет за кораблём; последние 2,0 с (sim/movement.gd → HYPER_RUN) корабль
#   разгоняется, и факел вытягивается (view/battle_view.gd). Пока копит — кольца накачки
#   затягиваются к корпусу. На переходе — росчерк вперёд, кольцо, вспышка, искры, и воронка
#   схлопывается за CLOSE_S.
# - Выход: вспышка, нитка из точки позади, кольцо и воронка ПОЗАДИ вышедшего — живёт IN_LIFE (2,0 с).
# Воронки — пул узлов (у каждого свой материал), заведённых сразу и всегда «видимых»: схлопнутую
# воронку рисует шейдер в точку, а её конвейер собран с первого кадра (прогрев, 07-29, 08-15).
# Модель только ЧИТАЕТ (hyper_left, события jump_out / jump_in).
extends Node3D

const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Movement := preload("res://sim/movement.gd")
const FxPool := preload("res://view/fx_pool.gd")
const ShipVisual := preload("res://view/ship_visual.gd")
const FUNNEL_SHADER := preload("res://view/shaders/funnel.gdshader")

## Воронка ухода раскрывается за 2,4 с до перехода (08, 2.11: «за 2,4 с до ухода перед носом
## раскрывается вращающаяся воронка»), раскрытие — за OPEN_S.
const OPEN_LEFT := 2.4
const OPEN_S := 0.5
## Воронка выхода живёт 2,0 с (план G8: «сроки 2,4 с / 2,0 с»), раскрытие и угасание — по четверти.
const IN_LIFE := 2.0
## Схлопывание воронки ухода после перехода.
const CLOSE_S := 0.35
## Кольца накачки — раз в 0,3 игровой секунды (08, 2.13).
const RING_EVERY := 0.3
const SLOTS := 12
const RING_COL := Color(0.62, 0.82, 1.0)
const STREAK := Color(0.75, 0.88, 1.0)

## ТОЛЬКО для проверки отката (план GЭ): воронки нет вовсе — уход и выход одной вспышкой, как до GЭ.
static var rollback_no_funnel := false

var battle: Battle
var gfx: FxPool
## Прогрев (07-29, 08-15): схлопнутые воронки всё равно рисуются — их конвейер собран сразу.
## false — откат прогрева: закрытая воронка спрятана, конвейер соберётся на первом гипере.
var warm := true
## Нарисованная точка и модель корабля: point.call(ship, alpha) → Vector3, visual.call(ship) → ShipVisual.
var point: Callable
var visual: Callable

var _slots: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
## Слот → (uid корабля или −1, вид: 0 — уход, 1 — выход, рождение, место для выхода).
var _owner: PackedInt32Array = PackedInt32Array()
var _kind: PackedInt32Array = PackedInt32Array()
var _birth: PackedFloat64Array = PackedFloat64Array()
var _ring_t: Dictionary[int, float] = {}
## Что раскрыто на этом кадре (проверки): uid → раскрытие воронки ухода; выходы — по слотам.
var drawn_open: Dictionary[int, float] = {}


func setup(p_battle: Battle, p_gfx: FxPool, p_point: Callable, p_visual: Callable) -> void:
	battle = p_battle
	gfx = p_gfx
	point = p_point
	visual = p_visual
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 1.0
	cm.height = 3.4
	cm.radial_segments = 40
	cm.rings = 10
	cm.cap_top = false
	cm.cap_bottom = false
	for i in SLOTS:
		var mat := ShaderMaterial.new()
		mat.shader = FUNNEL_SHADER
		var mi := MeshInstance3D.new()
		mi.name = "funnel_%d" % i
		mi.mesh = cm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# не отсекается по рамке: схлопнутая воронка обязана рисоваться (в точку) — прогрев
		mi.extra_cull_margin = 16384.0
		add_child(mi)
		_slots.append(mi)
		_mats.append(mat)
		_owner.append(-1)
		_kind.append(-1)
		_birth.append(-1e9)


func _vis(s: Ship) -> ShipVisual:
	var v: ShipVisual = visual.call(s)
	return v


## Радиус раструба — по нарисованной модели (ширина корпуса), а не по логическому радиусу.
func _radius(s: Ship) -> float:
	var v := _vis(s)
	if v == null:
		return s.def.radius * 3.0
	return maxf(v.width() * 0.75, v.length() * 0.18)


func _free_slot() -> int:
	var best := 0
	var oldest := INF
	for i in SLOTS:
		if _owner[i] < 0 and _kind[i] < 0:
			return i
		if _birth[i] < oldest:
			oldest = _birth[i]
			best = i
	return best


## Событие шага: переход (уход) и выход. Рождение — начало шага по игровым часам.
func consume(e: Array) -> void:
	var kind: StringName = e[0]
	if kind != &"jump_out" and kind != &"jump_in":
		return
	var u: int = e[1]
	var s := battle.ship_by_uid(u)
	if s == null:
		return
	gfx.now = battle.time - Battle.STEP
	var r := _radius(s)
	var at: Vector3 = point.call(s, 1.0)
	var dir := Vector3(s.dir.x, 0.0, s.dir.y)
	var col := Color(0.87, 0.94, 1.0)
	if kind == &"jump_out":
		gfx.beam(at, at + dir * 700.0, STREAK, r * 0.35, 0.32, 2.0)
		gfx.beam(at, at + dir * 700.0, Color(1, 1, 1), r * 0.1, 0.24, 1.6)
		gfx.particle(at, Vector3.ZERO, RING_COL, r * 0.8, r * 7.0, 0.7, FxPool.RING, 0.0, 1.2)
		gfx.flash(at, col, r * 2.2, 0.5, 1.8, 0.0, 0.4)
		for i in 10:
			var v := Vector3(_det(i, 0), _det(i, 1) * 0.5, _det(i, 2)).normalized() * r * 4.0
			gfx.particle(at, v, Color(0.8, 0.9, 1.0), 2.0, 0.6, 0.5, FxPool.SPARK, 1.5, 1.5)
		# воронка этого корабля схлопывается на месте перехода
		for i in SLOTS:
			if _owner[i] == u and _kind[i] == 0:
				_owner[i] = -1
				_kind[i] = 2
				_birth[i] = gfx.now
	else:
		gfx.flash(at, col, r * 2.6, 0.6, 1.8, 0.0, 0.4)
		gfx.beam(at - dir * 600.0, at, STREAK, r * 0.28, 0.3, 1.8)
		gfx.particle(at, Vector3.ZERO, RING_COL, r * 0.6, r * 5.0, 0.6, FxPool.RING, 0.0, 1.1)
		if rollback_no_funnel:
			return
		var i2 := _free_slot()
		_owner[i2] = -1
		_kind[i2] = 1
		_birth[i2] = gfx.now
		# воронка позади вышедшего: устье в 2,2 радиуса за кормой, горловина дальше назад
		var mi := _slots[i2]
		mi.global_transform = _xform(at - dir * (r * 2.2 + r * 1.7), -dir, r)


## Устойчивый «случайный» сдвиг искр: вид не трогает генератор боя, а свой ему здесь не нужен.
static func _det(i: int, axis: int) -> float:
	return sin(float(i * 3 + axis) * 12.9898 + 1.7) * 0.999


## Узел воронки: центр c, ось раструба (от устья к горловине) — fwd, масштаб r.
static func _xform(c: Vector3, fwd: Vector3, r: float) -> Transform3D:
	var y := fwd.normalized()
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x * r, y * r, z * r), c)


## Кадр: воронки копящих гипер (раскрываются за 2,4 с, едут за кораблём), кольца накачки,
## схлопывание ушедших и воронки выхода. a — доля шага, game_t — игровое время кадра.
func draw(a: float, game_t: float) -> void:
	drawn_open.clear()
	gfx.now = game_t
	for i in SLOTS:
		_mats[i].set_shader_parameter("now", game_t)
	# копящие гипер
	var live: Dictionary[int, bool] = {}
	for s in battle.ships:
		if s.dead or s.hyper_left <= 0.0:
			continue
		live[s.uid] = true
		var r := _radius(s)
		var at: Vector3 = point.call(s, a)
		# кольца накачки затягиваются к корпусу (раз в 0,3 игровой секунды)
		var last: float = _ring_t.get(s.uid, -1e9)
		if game_t - last >= RING_EVERY:
			_ring_t[s.uid] = game_t
			gfx.particle(at, Vector3.ZERO, RING_COL, r * 3.0, r * 1.2, 0.5, FxPool.RING, 0.0, 0.8)
		if s.hyper_left >= OPEN_LEFT or rollback_no_funnel:
			continue
		var open := clampf((OPEN_LEFT - s.hyper_left) / OPEN_S, 0.0, 1.0)
		var slot := -1
		for i in SLOTS:
			if _owner[i] == s.uid and _kind[i] == 0:
				slot = i
		if slot < 0:
			slot = _free_slot()
			_owner[slot] = s.uid
			_kind[slot] = 0
			_birth[slot] = game_t
		var v := _vis(s)
		var fwd := -(v.global_transform.basis.z.normalized()) if v != null else Vector3(s.dir.x, 0.0, s.dir.y)
		_slots[slot].global_transform = _xform(at + fwd * (r * 1.6 + r * 1.7), fwd, r)
		_mats[slot].set_shader_parameter("open", open)
		drawn_open[s.uid] = open
	# остальные слоты: ушедший копить перестал (отменил) — схлопнуть; уход и выход — по срокам
	for i in SLOTS:
		var k := _kind[i]
		if k == 0:
			if not live.has(_owner[i]) or rollback_no_funnel:
				_owner[i] = -1
				_kind[i] = -1
				_mats[i].set_shader_parameter("open", 0.0)
			continue
		var age := game_t - _birth[i]
		var op := 0.0
		if k == 1:
			var kk := age / IN_LIFE
			op = clampf(minf(kk / 0.25, (1.0 - kk) / 0.25), 0.0, 1.0) if kk >= 0.0 and kk <= 1.0 else 0.0
			if kk > 1.0:
				_kind[i] = -1
		elif k == 2:
			op = clampf(1.0 - age / CLOSE_S, 0.0, 1.0) if age >= 0.0 else 1.0
			if age > CLOSE_S:
				_kind[i] = -1
		_mats[i].set_shader_parameter("open", op)
		if op > 0.0:
			drawn_open[-1 - i] = op
	for i in SLOTS:
		_slots[i].visible = warm or _kind[i] >= 0
	for u: int in _ring_t.keys():
		if not live.has(u):
			_ring_t.erase(u)
