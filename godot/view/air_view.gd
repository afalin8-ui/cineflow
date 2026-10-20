# view/air_view.gd — авиация на экране (план G3, п. 5; архитектура, 5.3; часть 04, 2.21).
# Модель только ЧИТАЕТ: машины (battle.crafts) и события шага (пуск, гибель, посадка,
# очередь перехватчика, перезарядка).
# - Машины — модели одним MultiMesh на вид машины (view/craft_layer.gd): сотни машин —
#   столько вызовов отрисовки, сколько видов, а не машин.
# - На рабочем виде (2400) модель машины — пара точек, поэтому поверх неё — ТОЧКА
#   не меньше min_px точек экрана (sprite.gdshader), цвет по стороне (C43): машины
#   видны точками, а не пропадают.
# - След — отрезками по ИГРОВОМУ времени (раз в TRAIL_EVERY с), а не по кадрам (04,
#   2.21; 08, ловушки 16–17): на 4× та же густота, на паузе следы стоят. Тонкие дуги
#   следа и превращают точки в звено, которое крутит вираж.
# - Своя интерполяция, как у кораблей (архитектура, 3): перед каждым шагом — прошлое
#   положение и курс; машина, появившаяся на этом шаге, не смешивается (телепорт).
# - Высота — только картинка (09, 11.6): у каждой машины СВОИ ДУГИ по высоте
#   ±view.craft_arc, как в JS (часть 04, 2.4 п. 7), а бомбардировщик на отвороте
#   уходит вверх. Число — из doctrine.json (раздел view), не из кода.
extends Node3D

const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Body := preload("res://sim/body.gd")
const Craft := preload("res://sim/craft.gd")
const Squad := preload("res://sim/squad.gd")
const Proj := preload("res://sim/proj.gd")
const FxPool := preload("res://view/fx_pool.gd")
const BattleFx := preload("res://view/battle_fx.gd")
const CraftLayer := preload("res://view/craft_layer.gd")
const SPRITE_SHADER := preload("res://view/shaders/sprite.gdshader")

## Цвета по стороне (C43; space.js:1521 след 0x8fc8ef / 0xdfae7e, очередь 0x9fe0ff / 0xffb070).
const TRAIL_OWN := Color(0.56, 0.78, 0.94)
const TRAIL_FOE := Color(0.87, 0.68, 0.49)
const DOT_OWN := Color(0.62, 0.95, 1.0)
const DOT_FOE := Color(1.0, 0.72, 0.42)
const DOT_SEL := Color(1.0, 1.0, 1.0)
const GUN_OWN := Color(0.62, 0.88, 1.0)
const GUN_FOE := Color(1.0, 0.69, 0.44)
## Очередь машины — тоньше трассы ПВО (2,4) и очереди батареи (3,2): свой нижний предел в точках.
const GUN_PX := 1.3
const BOOM := Color(1.0, 0.5, 0.2)
## След кладётся раз в 0,12 игровой секунды и живёт 0,9 с (space.js: клуб раз в 0,16 с
## жизнью 0,34 — у нас отрезок, и он должен пережить разворот, чтобы вираж читался).
const TRAIL_EVERY := 0.12
const TRAIL_LIFE := 0.9
const TRAIL_W := 0.35
## Точка машины — не меньше DOT_PX точек экрана (на 2400 модель машины — одна-две точки).
const DOT_PX := 5.0
const DOT_SIZE := 3.0
## Точка ближе к камере на 14 (в мире): иначе она внутри своей модели и не видна вовсе.
const DOT_LIFT := 14.0
## Дуги по высоте (09, 11.6): y = view.craft_arc · cos(фаза) + подъём. Фаза копится по
## ИГРОВОМУ времени: кружение, патруль и путь — 0,3 рад/с (space.js:1608, cos(0,3 t +
## slot)·40), свалка — 0,8 (space.js:1645, проход в свалке: cos(0,8 t + slot)·40).
## Копится, а не считается от t: иначе смена занятия давала бы скачок высоты. Начало
## фазы — номер машины в звене (slot) плюс своя фаза звена: звенья не качаются в лад.
const ARC_CALM := 0.3
const ARC_FIGHT := 0.8
## Отворот бомбардировщика — вверх (space.js:1626: точка ухода на 90 выше): подъём до
## view.craft_arc за LIFT_S игровых секунд, после отворота — так же вниз.
const LIFT_S := 1.5

## ТОЛЬКО для проверок отката (план G3, п. 5): в игре всегда false.
## Точек поверх моделей нет — машина на 2400 остаётся моделью в пару точек.
static var rollback_no_dots := false
## Следа нет — звено читается россыпью точек, а не виражом.
static var rollback_no_trails := false
## Высота — постоянная у каждой машины, числами в коде (18 ± 22), как в G3 до доработки:
## дуг нет, отворот вверх не виден, правка view.craft_arc ничего не меняет.
static var rollback_fixed_height := false

var battle: Battle
var my_side := 0
var models: CraftLayer
var dots: MultiMeshInstance3D
var fx: FxPool
## Точка корабля на экране (вид кораблей): ship_pt.call(ship) → Vector3.
var ship_pt: Callable
## Точка снаряда на экране (BattleFx): proj_pt.call(uid, Vector2) → Vector3.
var proj_pt: Callable

var _rng := RandomNumberGenerator.new()
var _prev: Dictionary[int, Vector3] = {}         # (x, z, курс) на прошлом шаге
var _arc := 0.0                                  # view.craft_arc
var _h: Dictionary[int, float] = {}              # высота машины на последнем кадре
var _ph: Dictionary[int, float] = {}             # фаза дуги
var _lift: Dictionary[int, float] = {}           # подъём на отвороте (0…_arc)
var _ht: Dictionary[int, float] = {}             # игровое время последнего счёта высоты
var _qph: Dictionary[int, float] = {}            # своя фаза звена
var _trail_at: Dictionary[int, float] = {}
var _trail_pt: Dictionary[int, Vector3] = {}
## Нарисованные точки машин на этом кадре: выбор мышью и прицел эффектов читают их.
var drawn: Dictionary[int, Vector3] = {}
var trails_written := 0
var _keys: Dictionary[StringName, int] = {}
var _a := 1.0


func setup(p_battle: Battle, p_my_side: int) -> void:
	battle = p_battle
	my_side = p_my_side
	_rng.seed = battle.battle_seed ^ 0x6a09e667       # свой генератор картинки: модель не тронута
	_arc = battle.defs.doctrine.view_craft_arc
	models = CraftLayer.new()
	models.name = "CraftModels"
	add_child(models)
	for i in battle.sides.size():
		var clan := battle.sides[i].clan
		for role: StringName in [&"interceptor", &"fighter", &"bomber"]:
			var key := _key(clan, role)
			if not _keys.has(key) and models.add_kind(key, clan, role, 8):
				_keys[key] = 0
				models.ensure(key, 0)
	dots = _dot_pool()
	add_child(dots)
	fx = FxPool.new()
	fx.name = "AirFx"
	fx.setup(1024, 256, 256)
	add_child(fx)


static func _key(clan: StringName, role: StringName) -> StringName:
	return StringName("%s_%s" % [clan, role])


func _dot_pool() -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = FxPool._quad(-0.5, 0.5)
	mm.instance_count = 128
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-6000, -3000, -6000), Vector3(12000, 6000, 12000))
	var mat := ShaderMaterial.new()
	mat.shader = SPRITE_SHADER
	mat.set_shader_parameter("min_px", DOT_PX)
	mat.set_shader_parameter("lift", DOT_LIFT)
	var mi := MultiMeshInstance3D.new()
	mi.name = "craft_dots"
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Высота машины на этом кадре (посчитана в draw); машина, которую ещё не рисовали, —
## на начале своей дуги.
func _height(c: Craft) -> float:
	if not _h.has(c.uid):
		_start_arc(c)
	return _h[c.uid]


func _start_arc(c: Craft) -> void:
	if rollback_fixed_height:
		_h[c.uid] = 18.0 + _rng.randf_range(-22.0, 22.0)
		return
	var q := c.squad as Squad
	var qu := q.uid if q != null else 0
	if not _qph.has(qu):
		_qph[qu] = _rng.randf_range(0.0, TAU)
	_ph[c.uid] = float(c.slot) + _qph[qu]
	_lift[c.uid] = 0.0
	_ht[c.uid] = battle.time
	_h[c.uid] = _arc * cos(_ph[c.uid])


## Дуга по игровому времени game_t (09, 11.6): фаза — скоростью занятия, подъём — к
## отвороту бомбардировщика или обратно.
func _advance_arc(c: Craft, game_t: float) -> void:
	if not _h.has(c.uid):
		_start_arc(c)
	if rollback_fixed_height:
		return
	var dt := clampf(game_t - _ht[c.uid], 0.0, 1.0)
	_ht[c.uid] = game_t
	var fight := c.target != null and c.role != &"bomber" and not c.leaving
	_ph[c.uid] = _ph[c.uid] + (ARC_FIGHT if fight else ARC_CALM) * dt
	var want := _arc if c.role == &"bomber" and c.phase == &"break" else 0.0
	_lift[c.uid] = move_toward(_lift[c.uid], want, _arc / LIFT_S * dt)
	_h[c.uid] = _arc * cos(_ph[c.uid]) + _lift[c.uid]


## Подъём машины на отвороте сейчас (проверки, 09, 11.6).
func lift_of(u: int) -> float:
	return _lift.get(u, 0.0)


## Запомнить положения перед шагом (своя интерполяция).
func remember() -> void:
	for c in battle.crafts:
		if not c.dead:
			_prev[c.uid] = Vector3(c.pos.x, c.pos.y, c.yaw)


## Точка машины в мире на доле шага a.
func point_of(c: Craft, a: float = -1.0) -> Vector3:
	var k := _a if a < 0.0 else a
	var cur := Vector3(c.pos.x, c.pos.y, c.yaw)
	if c.jumped_at_step != battle.steps and _prev.has(c.uid):
		var p: Vector3 = _prev[c.uid]
		cur = Vector3(lerpf(p.x, cur.x, k), lerpf(p.y, cur.y, k), lerp_angle(p.z, cur.z, k))
	return Vector3(cur.x, _height(c), cur.y)


## Событие шага (зовёт вид после каждого шага): рождение — начало шага по игровым часам.
func consume(e: Array) -> void:
	fx.now = battle.time - Battle.STEP
	var kind: StringName = e[0]
	match kind:
		&"launch":
			var qu: int = e[1]
			var q := battle.squad_by_uid(qu)
			if q != null:
				for c in q.craft:
					fx.flash(Vector3(c.pos.x, _height(c), c.pos.y), Color(1.0, 0.82, 0.62), 5.0, 0.3, 1.8)
		&"craft_dead":
			var du: int = e[1]
			var at: Vector2 = e[2]
			var y: float = _h.get(du, 0.0)
			var p := Vector3(at.x, y, at.y)
			# машина гибнет огнём, а не белой кляксой: белое — маленькое короткое ядро (08, ловушка 6)
			fx.flash(p, BOOM, 10.0, 0.6, 1.4, 0.0, 0.0)
			fx.flash(p, Color(1, 0.95, 0.85), 3.0, 0.1, 2.0, 0.0, 1.0)
			_forget(du)
		&"craft_gone":
			var gu: int = e[1]
			_forget(gu)
		&"craft_fire":
			var cu: int = e[1]
			var tu: int = e[2]
			var tat: Vector2 = e[3]
			var c2 := battle.craft_by_uid(cu)
			if c2 != null:
				var from := point_of(c2, 1.0)
				var to := _target_pt(tu, tat)
				# очередь машины — СВОЙ вид (08, 7.4; план GЭ, п. 4): две короткие тонкие чёрточки
				# подряд, короче и тоньше трассы ПВО и очереди батареи
				if BattleFx.rollback_one_look:
					# откат проверки «источник читается»: все выстрелы — одним видом
					fx.beam(from, to, BattleFx.LIGHT_OWN, 0.9, 0.3, 1.9)
				else:
					for k in 2:
						fx.tracer(from + Vector3(c2.dir.x, 0.0, c2.dir.y) * 4.0, to, GUN_OWN if c2.side == my_side else GUN_FOE, 0.4, 700.0, 9.0, 2.2, k * 0.05, GUN_PX)
		&"reload":
			var ru: int = e[1]
			var c3 := battle.craft_by_uid(ru)
			if c3 != null:
				fx.flash(point_of(c3, 1.0), Color(0.62, 0.91, 1.0), 4.0, 0.3, 1.8)


## ТОЛЬКО для проверки отката: цели, которой после шага уже нет, — (0, 0, 0), как было.
static var rollback_target_zero := false


## Куда бьёт очередь: цель, если она ещё есть; сбитая этой же очередью (машину Hangar.tick
## убирает в конце шага, снаряд — уборка снарядов) — место из события на её последней
## высоте (замечание к G3: росчерк уходил в центр поля).
func _target_pt(u: int, at: Vector2) -> Vector3:
	var b := battle.body_by_uid(u)
	if b == null:
		return Vector3.ZERO if rollback_target_zero else point_by_uid(u, at)
	var s := b as Ship
	if s != null and ship_pt.is_valid():
		var sp: Vector3 = ship_pt.call(s)
		return sp
	var c := b as Craft
	if c != null:
		return point_of(c, 1.0)
	if proj_pt.is_valid():
		var pp: Vector3 = proj_pt.call(u, b.pos)
		return pp
	return Vector3(b.pos.x, 0.0, b.pos.y)


## Точка машины по номеру: живая — нарисованная сейчас; ушедшая на этом шаге — место
## из события на высоте, на которой её рисовали последний раз (BattleFx берёт её же для
## выстрела корабля по сбитой машине).
func point_by_uid(u: int, at: Vector2) -> Vector3:
	var c := battle.craft_by_uid(u)
	if c != null:
		return point_of(c, 1.0)
	if proj_pt.is_valid() and not _h.has(u):
		var pp: Vector3 = proj_pt.call(u, at)
		return pp
	var y: float = _h.get(u, 0.0)
	return Vector3(at.x, y, at.y)


func _forget(u: int) -> void:
	_prev.erase(u)
	_h.erase(u)
	_ph.erase(u)
	_lift.erase(u)
	_ht.erase(u)
	_trail_at.erase(u)
	_trail_pt.erase(u)
	drawn.erase(u)


## Кадр: a — доля шага, game_t — игровое время кадра, sel — выбранные (uid звеньев).
func draw(a: float, game_t: float, sel: Array[int]) -> void:
	_a = a
	fx.set_time(game_t)
	# сколько машин каждого вида — заранее: рост слоя пересоздаёт его буфер
	for key: StringName in _keys:
		_keys[key] = 0
	for c in battle.crafts:
		if not c.dead:
			var kq := c.squad as Squad
			var kk := _key(kq.clan if kq != null else battle.sides[c.side].clan, c.role)
			if _keys.has(kk):
				_keys[kk] = _keys[kk] + 1
	for key: StringName in _keys:
		models.ensure(key, _keys[key])
		_keys[key] = 0
	var mm := dots.multimesh
	var n_all := battle.crafts.size()
	if n_all > mm.instance_count:
		mm.instance_count = maxi(n_all, mm.instance_count * 2)
	var n := 0
	drawn.clear()
	for c in battle.crafts:
		if c.dead:
			continue
		_advance_arc(c, game_t)
		var p := point_of(c, a)
		drawn[c.uid] = p
		var q := c.squad as Squad
		var clan: StringName = q.clan if q != null else battle.sides[c.side].clan
		var key := _key(clan, c.role)
		if _keys.has(key):
			var i: int = _keys[key]
			var yaw := c.yaw
			if c.jumped_at_step != battle.steps and _prev.has(c.uid):
				var pv: Vector3 = _prev[c.uid]
				yaw = lerp_angle(pv.z, c.yaw, a)
			models.put(key, i, p, Vector3(-sin(yaw), 0.0, -cos(yaw)))
			_keys[key] = i + 1
		var own := c.side == my_side
		var picked := q != null and q.uid in sel
		var col := DOT_SEL if picked else (DOT_OWN if own else DOT_FOE)
		mm.set_instance_transform(n, Transform3D(Basis(Vector3.RIGHT, Vector3.UP, Vector3(col.r, col.g, col.b)), p))
		mm.set_instance_custom_data(n, Color(0.0, 0.0, DOT_SIZE * (1.6 if picked else 1.0), 2.4 if picked else 1.7))
		n += 1
		# след по игровому времени (04, 2.21): отрезок от прошлой точки следа
		var last: float = _trail_at.get(c.uid, -1.0)
		if last < 0.0:
			_trail_at[c.uid] = game_t
			_trail_pt[c.uid] = p
		elif game_t - last >= TRAIL_EVERY and not rollback_no_trails:
			fx.now = game_t
			var from: Vector3 = _trail_pt[c.uid]
			fx.beam(from, p, TRAIL_OWN if own else TRAIL_FOE, TRAIL_W, TRAIL_LIFE, 0.9)
			trails_written += 1
			_trail_at[c.uid] = game_t
			_trail_pt[c.uid] = p
	mm.visible_instance_count = 0 if rollback_no_dots else n
	models.commit()
