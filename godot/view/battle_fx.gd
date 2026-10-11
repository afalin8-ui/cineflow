# view/battle_fx.gd — огонь, снаряды, купола РЭБ, пояса и круги, орудие планеты на
# экране (план G2, п. 9; архитектура, 5.3–5.5; часть 08, 7.2 п. 6; доктрина 09, 6.7).
# Модель только ЧИТАЕТ: события шага (battle.events) и состояние (поля, снаряды,
# орудие планеты). Четыре источника урона различимы глазом:
# - главный калибр — толстый долгий луч от дула башни (turret_i/muzzle_i) со вспышкой
#   у дула и у цели, перед ним — накачка (вспышка растёт у дула);
# - батарея — СВОЙ вид (08, 7.2 п. 6): короткие толстые росчерки очередью из точек
#   aux_i, своя пара оттенков по стороне, без тряски;
# - лёгкое орудие — тонкий быстрый луч от дула;
# - ПВО — длинные летящие отрезки (46 на 780, 08, ловушка 18) от точек pd_i.
# Время эффектов — ИГРОВОЕ (на паузе стоят, на 4× бегут вчетверо; 08, ловушки 16–17):
# рождение — начало шага, на котором выстрел случился, а рисуются они по той же
# доле шага, что и корабли.
# Купол РЭБ в покое — ОДНО кольцо ровно по границе поля (04, ловушка 17; 08, ловушка
# 14: граница, а не стена; в JS кольцо было на 0,66 радиуса), полный вид — у
# выделенных одних РЭБ или под курсором; цвет — по стороне (C43). Пояс тяжёлого —
# квад с шейдером (view/shaders/belt.gdshader); кругов на экране не больше трёх, пояс
# считается за один (07, 7.2 п. 1).
extends Node3D

const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Proj := preload("res://sim/proj.gd")
const Defs := preload("res://sim/defs.gd")
const FxPool := preload("res://view/fx_pool.gd")
const ShipVisual := preload("res://view/ship_visual.gd")
const SpaceEnv := preload("res://view/space_env.gd")
const BELT_SHADER := preload("res://view/shaders/belt.gdshader")
const SPRITE_SHADER := preload("res://view/shaders/sprite.gdshader")

## Цвета по стороне (C43): свои — холодные, чужие — тёплые; у каждого источника своя пара.
const MAIN_OWN := Color(0.5, 0.85, 1.0)
const MAIN_FOE := Color(1.0, 0.56, 0.35)
const SEC_OWN := Color(0.45, 1.0, 0.75)        # батарея: мятно-зелёная у своих
const SEC_FOE := Color(1.0, 0.82, 0.3)         # …янтарная у чужих
const LIGHT_OWN := Color(0.7, 0.8, 1.0)
const LIGHT_FOE := Color(1.0, 0.62, 0.55)
const PD_OWN := Color(0.56, 0.88, 1.0)         # space.js: 0x8fe0ff / 0xffb45a
const PD_FOE := Color(1.0, 0.7, 0.35)
const MISSILE := Color(1.0, 0.6, 0.35)
const HIT := Color(1.0, 0.78, 0.5)
const BOOM := Color(1.0, 0.6, 0.3)
const DOME_OWN := Color(0.56, 1.0, 0.78)       # space.js: 0x8fffc8
const DOME_FOE := Color(1.0, 0.42, 0.35)       # 0xff6b5a
const DOME_SHIELD := Color(0.81, 0.91, 1.0)    # 0xcfe8ff
const BELT_OWN := Color(0.62, 0.85, 1.0)       # круг дальности 0x9fd8ff
const BELT_FOE := Color(1.0, 0.45, 0.38)
## Кругов дальности на экране — не больше (P5; пояс — за один, 09, 6.7).
const MAX_CIRCLES := 3
## Кольцо в квадe шейдера пояса стоит на 0,985 половины стороны: квад шире на 1/0,985.
const RING_AT := 0.985
const PROJ_SLOTS := 256
## Смешение идёт в линейном цвете: 0,05 там — это четверть яркости на экране. Заливка
## пояса «бледная» (09, 6.7) — поэтому сотые доли.
const FILL_OWN := 0.012
const FILL_FOE := 0.016
## Кольцо купола в покое в JS стояло на 0,6625 радиуса поля (04, 2.18).
const JS_DOME_K := 0.6625

## ТОЛЬКО для проверок отката (план G2, «Игровые»): в игре всегда false.
## Кольцо купола — на 0,6625 радиуса, как в JS (проверка «кольцо ровно по полю» краснеет).
static var rollback_dome_js := false
## Поясов и кругов не рисовать (проверка «пояс читается» краснеет).
static var rollback_no_belts := false
## Круги у всех выделенных, без правила «больше трёх — только главный» (P5).
static var rollback_all_circles := false
## След ракеты кладётся по игровому времени (space.js:1693: раз в 0,035 с).
const TRAIL_EVERY := 0.035

var battle: Battle
var my_side := 0
var gfx: FxPool
## Нарисованная точка корабля на доле шага: point.call(ship, alpha) → Vector3.
var point: Callable
## Модель корабля на сцене: visual.call(ship) → ShipVisual (или null).
var visual: Callable

var _rng := RandomNumberGenerator.new()
## Доля шага, по которой берутся точки кораблей: в событиях — нынешнее положение, в
## кадре — то, что нарисовано (кольца едут с кораблём плавно, а не рывками 30 Гц).
var _a := 1.0
var _sprites: MultiMeshInstance3D
var _proj_prev: Dictionary[int, Vector2] = {}
var _proj_y0: Dictionary[int, float] = {}
var _proj_d0: Dictionary[int, float] = {}
var _proj_trail: Dictionary[int, float] = {}
var _proj_at: Dictionary[int, Vector3] = {}
var _domes: Dictionary[int, Array] = {}        # uid РЭБ → [кольцо, стенка]
var _belts: Array[MeshInstance3D] = []
var _gun_ring: MeshInstance3D
## Что нарисовано на этом кадре (проверки читают это, а не пиксели): uid → [радиус,
## мёртвая зона, своя ли]; купола — uid → [радиус кольца, полный ли, видим ли].
var drawn_belts: Dictionary[int, Array] = {}
var drawn_domes: Dictionary[int, Array] = {}
## Счётчики выстрелов по виду (проверка «четыре источника различимы»).
var fired: Dictionary[StringName, int] = {}


func setup(p_battle: Battle, p_my_side: int, p_point: Callable, p_visual: Callable) -> void:
	battle = p_battle
	my_side = p_my_side
	point = p_point
	visual = p_visual
	_rng.seed = battle.battle_seed ^ 0x51ed270b      # свой генератор картинки: модель не тронута
	gfx = FxPool.new()
	gfx.name = "GameFx"
	gfx.setup(192, 320, 512)
	add_child(gfx)
	_sprites = _sprite_pool()
	add_child(_sprites)
	_gun_ring = _belt_mesh("gun_ring")
	add_child(_gun_ring)


func _sprite_pool() -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = FxPool._quad(-0.5, 0.5)
	mm.instance_count = PROJ_SLOTS
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-6000, -3000, -6000), Vector3(12000, 6000, 12000))
	var mat := ShaderMaterial.new()
	mat.shader = SPRITE_SHADER
	var mi := MultiMeshInstance3D.new()
	mi.name = "projs"
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Квад на плоскости с шейдером пояса (свой материал у каждого: цвет и мёртвая зона).
func _belt_mesh(nm: String) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = BELT_SHADER
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


func _vis(s: Ship) -> ShipVisual:
	var v: ShipVisual = visual.call(s)
	return v


## Высота-картинка корабля (09, 11.6): у снарядов — от неё к высоте цели.
func _y(s: Ship) -> float:
	var v := _vis(s)
	return v.global_position.y if v != null else 0.0


func _pt(s: Ship) -> Vector3:
	var p: Vector3 = point.call(s, _a)
	return p


## Точка узла модели (дуло, точка батареи, ствол ПВО); нет узла — центр корабля.
func _node_pt(s: Ship, base: String, i: int) -> Vector3:
	var v := _vis(s)
	if v == null:
		return _pt(s)
	var n := 0
	while v.part(StringName("%s%d" % [base, n])) != null:
		n += 1
	if n == 0:
		return v.global_position
	return v.part_point(StringName("%s%d" % [base, i % n]))


func _bump(kind: StringName) -> void:
	var c: int = fired.get(kind, 0)
	fired[kind] = c + 1


## Запомнить положения снарядов перед шагом (своя интерполяция, архитектура 3).
func remember() -> void:
	for p in battle.projs:
		if not p.dead:
			_proj_prev[p.uid] = p.pos


# ───────────────────────── события шага ─────────────────────────

## Событие ЭТОГО шага (зовёт вид после каждого шага). Эффекты рождаются в начале шага
## по игровым часам.
func consume(e: Array) -> void:
	gfx.now = battle.time - Battle.STEP
	_a = 1.0
	var kind: StringName = e[0]
	match kind:
		&"fire":
			var u1: int = e[1]
			var u2: int = e[2]
			var role: StringName = e[3]
			var mount: int = e[4]
			var a := battle.ship_by_uid(u1)
			var t := battle.ship_by_uid(u2)
			if a != null and t != null:
				_fire(a, t, role, mount)
		&"charge":
			var cu: int = e[1]
			var c := battle.ship_by_uid(cu)
			var frac: float = e[3]
			if c != null:
				var mi: int = e[2]
				gfx.flash(_node_pt(c, "muzzle_", mi), MAIN_OWN if c.side == my_side else MAIN_FOE, c.def.radius * frac * 1.7 + 2.0, 0.14, 1.8)
		&"pd":
			var su: int = e[1]
			var barrel: int = e[2]
			var s := battle.ship_by_uid(su)
			if s != null:
				var to2: Vector2 = e[3]
				var tu: int = e[4]
				var to: Vector3 = _proj_at.get(tu, Vector3(to2.x, _y(s), to2.y))
				var from := _node_pt(s, "pd_", barrel)
				var col := PD_OWN if s.side == my_side else PD_FOE
				gfx.tracer(from, to, col, 0.55, 780.0, 46.0, 2.0)
				_bump(&"pd")
		&"proj":
			var pu: int = e[1]
			for p in battle.projs:
				if p.uid == pu:
					var ow := p.owner as Ship
					var tg := p.target as Ship
					_proj_y0[pu] = _y(ow) if ow != null else 0.0
					_proj_d0[pu] = p.pos.distance_to(tg.pos) if tg != null else 1.0
					_proj_trail[pu] = -1.0
					if ow != null:
						gfx.flash(_node_pt(ow, "missile_", 0), Color(1.0, 0.82, 0.62), ow.def.radius * 0.7, 0.3, 1.6)
					break
		&"proj_hit":
			var hu: int = e[1]
			var at: Vector3 = _proj_at.get(hu, Vector3.ZERO)
			gfx.flash(at, BOOM, 18.0, 0.5, 2.2)
			_forget(hu)
		&"proj_end":
			var eu: int = e[1]
			var at2: Vector3 = _proj_at.get(eu, Vector3.ZERO)
			gfx.flash(at2, HIT, 7.0, 0.3, 1.6)
			_forget(eu)
		&"destroyed":
			var du: int = e[1]
			var d := battle.ship_by_uid(du)
			if d != null:
				_boom(d)
		&"gun_fire":
			var gk: StringName = e[1]
			var gat: Vector2 = e[2]
			var gh: PackedInt32Array = e[3]
			_gun_fire(gk, gat, gh)


func _forget(u: int) -> void:
	_proj_prev.erase(u)
	_proj_y0.erase(u)
	_proj_d0.erase(u)
	_proj_trail.erase(u)
	_proj_at.erase(u)


func _fire(a: Ship, t: Ship, role: StringName, mount: int) -> void:
	var own := a.side == my_side
	var to := _pt(t) + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.2, 0.3), _rng.randf_range(-0.3, 0.3)) * t.def.radius
	_bump(role)
	match role:
		&"main":
			var from := _node_pt(a, "muzzle_", mount)
			var c := MAIN_OWN if own else MAIN_FOE
			var w := 0.9 + a.def.radius * 0.07
			gfx.beam(from, to, c, w * 1.4, 0.55, 2.8)
			gfx.beam(from, to, Color(1, 1, 1), w * 0.45, 0.35, 2.0)
			gfx.flash(from, c, a.def.radius * 1.5, 0.35, 2.2)
			gfx.flash(to, HIT, t.def.radius * 2.6, 0.8, 2.4)
			for i in 3:
				gfx.flash(to + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 1), _rng.randf_range(-1, 1)) * t.def.radius, HIT, t.def.radius * 0.8, 0.45, 1.6)
		&"sec":
			# очередь из трёх росчерков от точки батареи — свой вид, без тряски (08, 7.2 п. 6)
			var from2 := _node_pt(a, "aux_", mount)
			var c2 := SEC_OWN if own else SEC_FOE
			for k in 3:
				var jit := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1)) * t.def.radius * 0.5
				gfx.tracer(from2, to + jit, c2, 2.4, 1100.0, 24.0, 2.4, k * 0.07)
			gfx.flash(from2, c2, 7.0, 0.22, 2.0)
		_:
			var from3 := _node_pt(a, "muzzle_", mount)
			var c3 := LIGHT_OWN if own else LIGHT_FOE
			gfx.beam(from3, to, c3, 0.9, 0.18, 1.9)
			gfx.flash(to, c3, t.def.radius * 1.2, 0.3, 1.5)


func _boom(d: Ship) -> void:
	var at := _pt(d)
	var r := d.def.radius
	gfx.flash(at, BOOM, r * 6.0, 1.4, 2.6)
	gfx.flash(at, Color(1, 0.95, 0.8), r * 3.0, 0.6, 3.0)
	for i in maxi(2, roundi(r / 7.0)):
		var off := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-1, 1)) * r * 1.6
		gfx.flash(at + off, BOOM, r * _rng.randf_range(1.5, 3.0), _rng.randf_range(0.6, 1.2), 2.2)


## Залп планеты (03, 2.17): луч с планеты, у ядерной — вспышка во весь радиус.
func _gun_fire(kind: StringName, at2: Vector2, hits: PackedInt32Array) -> void:
	var g := battle.gun
	if g == null:
		return
	var col := Color.hex(g.def.color << 8 | 0xff)
	var at := Vector3(at2.x, 0.0, at2.y)
	if hits.size() > 0 and kind == &"beam":
		var t := battle.ship_by_uid(hits[0])
		if t != null:
			at = _pt(t)
	var c := SpaceEnv.PLANET_CENTER
	var from := c + (at - c).normalized() * SpaceEnv.PLANET_RADIUS
	gfx.beam(from, at, col, 5.0 if kind == &"nuke" else 3.2, 0.8, 3.0)
	match kind:
		&"nuke":
			gfx.flash(at, BOOM, g.def.radius * 1.2, 1.6, 2.8)
			gfx.flash(at, Color(1, 0.95, 0.8), g.def.radius * 0.5, 0.7, 3.0)
		_:
			gfx.flash(at, col, 60.0, 0.8, 2.4)


# ───────────────────────── кадр ─────────────────────────

## Нарисовать кадр: a — доля шага, game_t — игровое время на этом кадре.
## sel — выбранные (uid), hover — корабль под курсором (0 — нет), only_ecm — выбраны одни РЭБ.
func draw(a: float, game_t: float, sel: Array[int], hover: int) -> void:
	_a = a
	gfx.set_time(game_t)
	_draw_projs(a, game_t)
	_draw_domes(sel, hover)
	_draw_belts(sel, hover)
	_draw_gun()


func _draw_projs(a: float, game_t: float) -> void:
	var mm := _sprites.multimesh
	var n := 0
	for p in battle.projs:
		if p.dead or n >= PROJ_SLOTS:
			continue
		var cur := p.pos
		var prev: Vector2 = _proj_prev.get(p.uid, cur)
		if p.jumped_at_step == battle.steps:
			prev = cur
		var xz := prev.lerp(cur, a)
		var y0: float = _proj_y0.get(p.uid, 0.0)
		var y := y0
		var t := p.target as Ship
		if t != null:
			var d0: float = _proj_d0.get(p.uid, 1.0)
			y = lerpf(y0, _y(t), clampf(1.0 - xz.distance_to(t.pos) / maxf(d0, 1.0), 0.0, 1.0))
		var at := Vector3(xz.x, y, xz.y)
		_proj_at[p.uid] = at
		var torp := p.key == &"torp"
		mm.set_instance_transform(n, Transform3D(Basis(Vector3.RIGHT, Vector3.UP, Vector3(MISSILE.r, MISSILE.g, MISSILE.b)), at))
		mm.set_instance_custom_data(n, Color(0.0, 0.0, 6.0 if torp else 4.0, 2.2))
		var last: float = _proj_trail.get(p.uid, -1.0)
		if game_t - last >= TRAIL_EVERY:
			_proj_trail[p.uid] = game_t
			var back := at - Vector3(p.dir.x, 0.0, p.dir.y) * 3.0
			gfx.now = game_t
			gfx.flash(back, Color(1.0, 0.7, 0.4), 2.6 if torp else 1.8, 0.35, 1.4)
		n += 1
	mm.visible_instance_count = n


func _draw_domes(sel: Array[int], hover: int) -> void:
	drawn_domes.clear()
	var only_ecm := not sel.is_empty()
	for u in sel:
		var s0 := battle.ship_by_uid(u)
		only_ecm = only_ecm and s0 != null and s0.def.ecm
	var live: Dictionary[int, bool] = {}
	for f in battle.fields:
		live[f.src.uid] = true
	for s in battle.ships:
		if not s.def.ecm:
			continue
		var parts: Array = _domes.get(s.uid, [])
		if parts.is_empty():
			var r0 := _belt_mesh("dome_ring_%d" % s.uid)
			var w0 := _dome_wall(s)
			add_child(r0)
			add_child(w0)
			parts = [r0, w0]
			_domes[s.uid] = parts
		var ring: MeshInstance3D = parts[0]
		var wall: MeshInstance3D = parts[1]
		var on := not s.dead and s.ecm_power > 0.02
		ring.visible = on
		if not on:
			wall.visible = false
			continue
		var fd: Defs.FactionDef = battle.defs.factions.get(battle.sides[s.side].clan)
		var prof: Defs.EcmDef = fd.ecm if fd != null else battle.defs.ecm_base
		var r := prof.radius * (JS_DOME_K if rollback_dome_js else 1.0)
		var c := DOME_SHIELD if s.ecm_mode == &"shield" else (DOME_OWN if s.side == my_side else DOME_FOE)
		var at := _pt(s)
		ring.position = Vector3(at.x, at.y, at.z)
		ring.scale = Vector3(r / RING_AT, 1.0, r / RING_AT)
		var p := s.ecm_power * 0.55
		var mat := ring.material_override as ShaderMaterial
		mat.set_shader_parameter("color", Color(c.r, c.g, c.b, 1.0))
		mat.set_shader_parameter("inner", 0.0)
		mat.set_shader_parameter("outer_alpha", clampf(p * 1.2, 0.0, 0.7))
		mat.set_shader_parameter("line_px", 2.0)
		var full := hover == s.uid or (only_ecm and s.uid in sel)
		wall.visible = full
		if full:
			wall.position = at
			wall.scale = Vector3(r, 1.0, r)
			var wm := wall.material_override as StandardMaterial3D
			wm.albedo_color = Color(c.r, c.g, c.b, 0.06 + 0.1 * p)
		drawn_domes[s.uid] = [r, full, live.has(s.uid)]


func _dome_wall(_s: Ship) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 90.0                        # нарисованная толщина купола — E.height (04, 2.18)
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 96
	cm.rings = 1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	var mi := MeshInstance3D.new()
	mi.name = "dome_wall"
	mi.mesh = cm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


## Кого обвести (не больше MAX_CIRCLES): под курсором; цели фокуса выделенных (пояс
## чужого тяжёлого — 09, 6.7); выделенные свои вооружённые — до трёх все, до восьми —
## главный (наибольшая дальность), больше восьми — никого (03, 2.13, P5).
func circle_list(sel: Array[int], hover: int) -> Array[Ship]:
	var out: Array[Ship] = []
	var hs := battle.ship_by_uid(hover) if hover > 0 else null
	if hs != null and not hs.dead and hs.range0() > 0.0:
		out.append(hs)
	var own: Array[Ship] = []
	for u in sel:
		var s := battle.ship_by_uid(u)
		if s == null or s.dead:
			continue
		var fz := s.forced as Ship
		if fz != null and not fz.dead and fz.range0() > 0.0 and fz not in out:
			out.append(fz)
		if s.side == my_side and s.range0() > 0.0:
			own.append(s)
	if rollback_all_circles:
		pass
	elif own.size() > 8:
		own.clear()
	elif own.size() > 3:
		var best := own[0]
		for s in own:
			if s.range0() > best.range0() or (s.range0() == best.range0() and s.def.radius > best.def.radius):
				best = s
		own = [best]
	for s in own:
		if s not in out:
			out.append(s)
	while out.size() > MAX_CIRCLES and not rollback_all_circles:
		out.pop_back()
	return out


func _draw_belts(sel: Array[int], hover: int) -> void:
	drawn_belts.clear()
	var list := circle_list(sel, hover) if not rollback_no_belts else ([] as Array[Ship])
	while _belts.size() < list.size():
		var b := _belt_mesh("belt_%d" % _belts.size())
		add_child(b)
		_belts.append(b)
	for i in _belts.size():
		var mi := _belts[i]
		if i >= list.size():
			mi.visible = false
			continue
		var s := list[i]
		var r := s.range0()
		var dz := s.def.main.dead if s.heavy() else 0.0
		var own := s.side == my_side
		var c := BELT_OWN if own else BELT_FOE
		var at := _pt(s)
		mi.visible = true
		mi.position = at
		mi.scale = Vector3(r / RING_AT, 1.0, r / RING_AT)
		var mat := mi.material_override as ShaderMaterial
		mat.set_shader_parameter("color", c)
		mat.set_shader_parameter("inner", dz / r * RING_AT if dz > 0.0 else 0.0)
		# у своего мёртвая зона тусклее дальности, у чужого — ярче (09, 6.7)
		mat.set_shader_parameter("outer_alpha", 0.5 if own else 0.35)
		mat.set_shader_parameter("inner_alpha", 0.3 if own else 0.75)
		mat.set_shader_parameter("fill_alpha", (FILL_OWN if own else FILL_FOE) if dz > 0.0 else 0.0)
		mat.set_shader_parameter("line_px", 1.6)
		drawn_belts[s.uid] = [r, dz, own]


func _draw_gun() -> void:
	var g := battle.gun
	if g == null or not g.warned or not g.has_aim:
		_gun_ring.visible = false
		return
	var r := g.def.radius if g.def.kind == &"nuke" else 60.0
	_gun_ring.visible = true
	_gun_ring.position = Vector3(g.aim.x, 0.0, g.aim.y)
	_gun_ring.scale = Vector3(r / RING_AT, 1.0, r / RING_AT)
	var mat := _gun_ring.material_override as ShaderMaterial
	var col := Color.hex(g.def.color << 8 | 0xff)
	mat.set_shader_parameter("color", col)
	mat.set_shader_parameter("inner", 0.0)
	mat.set_shader_parameter("outer_alpha", 0.85)
	mat.set_shader_parameter("line_px", 2.6)
