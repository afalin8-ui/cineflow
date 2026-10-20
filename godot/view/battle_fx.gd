# view/battle_fx.gd — огонь, снаряды, купола РЭБ, пояса и круги, орудие планеты на
# экране (план G2, п. 9; архитектура, 5.3–5.5; часть 08, 7.2 п. 6; доктрина 09, 6.7).
# С пакета GЭ — ещё взрывы (белым — только маленькое короткое ядро; огонь, искры, обломки, дым,
# ударная волна, у тяжёлых — вторичные взрывы и дольше), дым и огонь у подбитых, дымный след
# ракет и полный вид купола своим шейдером (view/shaders/dome.gdshader).
# Модель только ЧИТАЕТ: события шага (battle.events) и состояние (поля, снаряды,
# орудие планеты). Источники выстрела различимы глазом (08, 7.4; план GЭ, п. 4):
# - главный калибр — толстый долгий луч от дула башни (turret_i/muzzle_i) со вспышкой
#   у дула и у цели, перед ним — накачка (вспышка растёт у дула);
# - батарея — СВОЙ вид (08, 7.2 п. 6): короткие толстые росчерки очередью из точек
#   aux_i, своя пара оттенков по стороне, без тряски;
# - лёгкое орудие — тонкий быстрый луч от дула, своя пара оттенков (сиреневый / малиновый);
# - ПВО — длинные летящие отрезки (46 на 780, 08, ловушка 18) от точек pd_i;
# - авиация — короткие тонкие росчерки от машин (view/air_view.gd), ракеты и торпеды — огонёк
#   с ДЫМНЫМ следом, орудие планеты — толстый луч снизу, из планеты, с кольцом.
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
const Body := preload("res://sim/body.gd")
const Craft := preload("res://sim/craft.gd")
const FxPool := preload("res://view/fx_pool.gd")
const ShipVisual := preload("res://view/ship_visual.gd")
const Picking := preload("res://input/picking.gd")
const SpaceEnv := preload("res://view/space_env.gd")
const BELT_SHADER := preload("res://view/shaders/belt.gdshader")
const SPRITE_SHADER := preload("res://view/shaders/sprite.gdshader")
const DOME_SHADER := preload("res://view/shaders/dome.gdshader")

## Цвета по стороне (C43): свои — холодные, чужие — тёплые; у каждого источника своя пара.
const MAIN_OWN := Color(0.5, 0.85, 1.0)
const MAIN_FOE := Color(1.0, 0.56, 0.35)
const SEC_OWN := Color(0.45, 1.0, 0.75)        # батарея: мятно-зелёная у своих
const SEC_FOE := Color(1.0, 0.82, 0.3)         # …янтарная у чужих
const LIGHT_OWN := Color(0.72, 0.6, 1.0)        # лёгкое: сиреневое у своих
const LIGHT_FOE := Color(1.0, 0.42, 0.6)         # …малиновое у чужих
const PD_OWN := Color(0.56, 0.88, 1.0)         # space.js: 0x8fe0ff / 0xffb45a
const PD_FOE := Color(1.0, 0.7, 0.35)
const MISSILE := Color(1.0, 0.6, 0.35)
const HIT := Color(1.0, 0.78, 0.5)
const BOOM := Color(1.0, 0.52, 0.2)
## Взрыв: белое — только ядро (08, ловушка 6), огонь — оранжевый, дым — тёмный (08, 1.3).
const CORE := Color(1.0, 0.96, 0.88)
const FIRE_COL := Color(0.95, 0.34, 0.07)
const SPARK_COL := Color(1.0, 0.62, 0.28)
const SMOKE_COL := Color(0.07, 0.065, 0.06)
const DEBRIS_COL := Color(0.05, 0.045, 0.04)
const TRAIL_SMOKE := Color(0.16, 0.15, 0.14)
## Подбитый корабль дымит ниже HURT_SMOKE прочности и горит ниже HURT_FIRE (08, 1.3: «дым у горящего»):
## клуб — раз в HURT_EVERY_MAX…MIN игровой секунды, чем ниже прочность — тем чаще.
const HURT_SMOKE := 0.5
const HURT_FIRE := 0.25
const HURT_EVERY_MAX := 0.45
const HURT_EVERY_MIN := 0.12
const SideColors := preload("res://view/side_colors.gd")
const DOME_OWN := SideColors.OWN       # space.js: 0x8fffc8 — цвет стороны, одно место
const DOME_FOE := SideColors.FOE       # 0xff6b5a
const DOME_SHIELD := Color(0.81, 0.91, 1.0)    # 0xcfe8ff
const BELT_OWN := Color(0.62, 0.85, 1.0)       # круг дальности 0x9fd8ff
const BELT_FOE := Color(1.0, 0.45, 0.38)
## Кругов дальности на экране — не больше (P5; пояс — за один, 09, 6.7).
const MAX_CIRCLES := 3
## На большом флоте — не больше двух (07, 4.2: «круги — не больше двух на большом флоте»).
const MAX_CIRCLES_BIG := 2
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
## ТОЛЬКО для проверки отката (план GИ, п. 7): на большом флоте кругов три, как раньше. В игре false.
static var rollback_three_on_big := false
## Купол и пояса — мимо единого фильтра видимости (только «не погиб»), как было до
## доработки G2: со скрытностью купол скрытого РЭБ рисовался бы (04-33, C67).
static var rollback_no_shown := false
## Конец снаряда, не попавшего ни в один кадр, — в центре поля (0, 0, 0), как было в G2.
static var rollback_end_center := false
## Выстрел корабля по цели, сбитой этим же выстрелом, не рисуется вовсе, как было в G3.
static var rollback_fire_lost := false
## трасса ПВО по машине, сбитой этой очередью, — на высоте стрелявшего корабля, как в 0.4.1
## (вспышка гибели при этом — на высоте машины, разрыв до 80–120);
static var rollback_pd_ship_y := false
## Радиус попадания ушедшей цели (машина — 2,6, space.js:449): её самой уже нет.
const GONE_HIT_R := 2.6
## Свой нижний предел в точках экрана (хвост G2; 09, 11.8): общий «не меньше 1,6»
## делал на старте (3990) главный калибр и лёгкое ОДНОЙ толщины — их не отличить;
## ракета (3 точки) и трасса ПВО (1,6) на рабочем виде (2400) читались пылинкой.
## Главный калибр — широкий цветной луч с белой серединой, лёгкое — общий предел.
const MAIN_PX := 4.0
const MAIN_CORE_PX := 2.0
const PD_PX := 2.4
## Очередь батареи — толще ПВО (08, 7.2 п. 6: «короче и толще ПВО»), луч планеты — толще всех.
const SEC_PX := 3.2
const GUN_PX := 6.0
## Пятно ракеты гаснет от середины к краю, и видно его вдвое уже квада: 8 точек квада —
## это 4 видимых (замер снимком на 2400; при 3 — пылинка в 1,5 точки). Клубы следа — 4.
const MISSILE_PX := 8.0
const TORP_PX := 10.0
const PUFF_PX := 4.0
## ТОЛЬКО для проверки отката: один общий предел у всех, как в G2.
static var rollback_one_px := false
## ТОЛЬКО для проверки отката: общий предел у ОДНОГО источника (&"main", &"pd",
## &"missile", &"puff"), остальные — как в игре (замечание к G3: откат «все сразу» не
## показывал, нужен ли каждый предел по отдельности).
static var rollback_px_off: StringName = &""
## След ракеты кладётся по игровому времени (space.js:1693: раз в 0,035 с).
const TRAIL_EVERY := 0.035
## ТОЛЬКО для проверок отката (план GЭ), в игре false:
## все выстрелы — одним видом (тонкий луч одного цвета): источник не читается (08, 7.4);
static var rollback_one_look := false
## взрыв как до GЭ — большая вспышка с белой серединой во весь размер («белая клякса», 08, ловушка 6);
static var rollback_white_boom := false
## подбитые не дымят (08, 1.3: «дым у горящего»);
static var rollback_no_hurt_smoke := false
## купол полный и в покое, как в JS (04, ловушка 17; 08, ловушка 14: «в покое — одно кольцо»);
static var rollback_dome_full_rest := false
## прогрева нет (07-29, 08-15): пулы огня и дыма заводятся на первом взрыве, стенка купола,
## воронка и факел впервые рисуются при первом случае — конвейеры собираются посреди боя.
static var rollback_no_warm := false
const PART_SLOTS := 1536
const SMOKE_SLOTS := 1536

var battle: Battle
var my_side := 0
var gfx: FxPool
## Нарисованная точка корабля на доле шага: point.call(ship, alpha) → Vector3.
var point: Callable
## Модель корабля на сцене: visual.call(ship) → ShipVisual (или null).
var visual: Callable
## Нарисованная точка машины (view/air_view.gd, G3): craft_pt.call(craft, alpha) → Vector3.
## Цель ПВО, лёгкого орудия и ракеты истребителя бывает машиной, а хозяин торпеды — машина.
var craft_pt: Callable
## Точка машины по номеру (view/air_view.gd → point_by_uid): машина, сбитая этим же
## выстрелом, к виду уже не доходит — её место из события на её последней высоте.
var craft_at: Callable

var _rng := RandomNumberGenerator.new()
## Свой генератор частиц пакета GЭ (искры, обломки, огонь, дым): у прежнего (`_rng`) расход тот же,
## что до GЭ, и концы лучей и очередей легли бы туда же, куда ложились, — проверки картинки G2–G3
## мерят полоски в одну-две точки, и сдвиг конца на долю точки менял бы их счёт.
var _prng := RandomNumberGenerator.new()
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
## Подбитые: когда дымили в последний раз (игровое время).
var _hurt_t: Dictionary[int, float] = {}
## Прогрев (07-29, 08-15): стенка купола видна первые кадры, схлопнутая силой 0.
var _warm_wall: MeshInstance3D
## Прогрев кольца (купол в покое, пояс, кольцо орудия планеты — один шейдер пояса): до GЭ его
## конвейер собирался, когда РЭБ набирал мощность или выбирали тяжёлого (замер пробой прогрева).
var _warm_ring: MeshInstance3D
## Что нарисовано (проверки): взрывов, клубов дыма у подбитых.
var booms := 0
var hurt_puffs := 0
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
	_prng.seed = battle.battle_seed ^ 0x2f5a17c3
	gfx = FxPool.new()
	gfx.name = "GameFx"
	if rollback_no_warm:
		gfx.setup(192, 320, 512)
	else:
		gfx.setup(192, 320, 512, PART_SLOTS, SMOKE_SLOTS)
	add_child(gfx)
	_sprites = _sprite_pool()
	add_child(_sprites)
	_gun_ring = _belt_mesh("gun_ring")
	add_child(_gun_ring)
	_warm_wall = _dome_wall(null)
	_warm_wall.name = "warm_wall"
	add_child(_warm_wall)
	_warm_ring = _belt_mesh("warm_ring")
	add_child(_warm_ring)
	# огонь и дым — один кадр огня и клуба уже в начале боя (за камерой не спрятать: пул
	# рисуется весь, а мёртвые слоты складываются шейдером — конвейеры собраны с первого кадра)


## Прогрев (07, ловушка 29; 08, ловушка 15): первые кадры стенка купола видна с силой 0 у точки
## взгляда — её конвейер собирается сразу; потом прячется, а не освобождается.
func warm(on: bool) -> void:
	if _warm_wall == null:
		return
	if rollback_no_warm:
		_warm_wall.visible = false
		_warm_ring.visible = false
		return
	_warm_wall.visible = on
	_warm_ring.visible = on
	if on:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		var at := cam.global_position + (-cam.global_transform.basis.z) * 600.0 if cam != null else Vector3.ZERO
		_warm_wall.position = at
		_warm_wall.scale = Vector3(40.0, 1.0, 40.0)
		var wm := _warm_wall.material_override as ShaderMaterial
		wm.set_shader_parameter("power", 0.0)
		_warm_ring.position = at
		_warm_ring.scale = Vector3(40.0, 1.0, 40.0)
		var rm := _warm_ring.material_override as ShaderMaterial
		rm.set_shader_parameter("color", Color(0, 0, 0, 0))
		rm.set_shader_parameter("outer_alpha", 0.0)
		rm.set_shader_parameter("inner_alpha", 0.0)
		rm.set_shader_parameter("fill_alpha", 0.0)
		rm.set_shader_parameter("line_px", 0.0)


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


## Высота-картинка любого тела: корабль — его модель, машина — её точка (G3).
func _body_y(b: Body) -> float:
	var s := b as Ship
	if s != null:
		return _y(s)
	var c := b as Craft
	if c != null and craft_pt.is_valid():
		var p: Vector3 = craft_pt.call(c, 1.0)
		return p.y
	return 0.0


## Нарисованная точка цели: корабль, машина или снаряд; fallback — точка плоскости.
func _body_pt(b: Body, fallback: Vector2) -> Vector3:
	var s := b as Ship
	if s != null:
		return _pt(s)
	var c := b as Craft
	if c != null and craft_pt.is_valid():
		var p: Vector3 = craft_pt.call(c, _a)
		return p
	if b != null and _proj_at.has(b.uid):
		return _proj_at[b.uid]
	return Vector3(fallback.x, 0.0, fallback.y)


## Нарисованная точка снаряда (для очередей перехватчика по ракете, G3).
func proj_point(u: int, at: Vector2) -> Vector3:
	if _proj_at.has(u):
		return _proj_at[u]
	var y: float = _proj_y0.get(u, 0.0)
	return Vector3(at.x, y, at.y)


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
			var tat: Vector2 = e[5]
			var a := battle.ship_by_uid(u1)
			var t := battle.body_by_uid(u2)       # корабль или, по приказу на звено, машина
			if a != null and t != null:
				_fire(a, _body_pt(t, t.pos), t.hit_r, role, mount)
			elif a != null and not rollback_fire_lost:
				# цель сбита этим же выстрелом и уже убрана (машина — Hangar.tick в конце
				# шага): выстрел рисуется в её место из события (замечание к G3)
				_fire(a, _gone_pt(u2, tat), GONE_HIT_R, role, mount)
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
				var tc := battle.craft_by_uid(tu) if not _proj_at.has(tu) else null
				if tc != null:
					to = _body_pt(tc, to2)            # ПВО по машине (04, 2.12)
				elif not _proj_at.has(tu) and not rollback_pd_ship_y:
					# машина, сбитая этой очередью, уже убрана (Hangar.tick в конце шага): место —
					# из события, высота — у вида авиации, как у fire и craft_fire (вторая
					# доработка G3); снаряд, не успевший в кадр, — на высоте пускавшего
					to = _gone_pt(tu, to2)
				var from := _node_pt(s, "pd_", barrel)
				var col := PD_OWN if s.side == my_side else PD_FOE
				if rollback_one_look:
					gfx.beam(from, to, LIGHT_OWN, 0.9, 0.3, 1.9)
				else:
					gfx.tracer(from, to, col, 0.55, 780.0, 46.0, 2.0, 0.0, _px(PD_PX, &"pd"))
				_bump(&"pd")
		&"proj":
			var pu: int = e[1]
			for p in battle.projs:
				if p.uid == pu:
					var ow := p.owner as Body
					var tg := p.target as Body
					_proj_y0[pu] = _body_y(ow) if ow != null else 0.0
					_proj_d0[pu] = p.pos.distance_to(tg.pos) if tg != null else 1.0
					_proj_trail[pu] = -1.0
					var os := ow as Ship
					if os != null:
						gfx.flash(_node_pt(os, "missile_", 0), Color(1.0, 0.82, 0.62), os.def.radius * 0.7, 0.3, 1.6)
					elif ow != null:
						gfx.flash(_body_pt(ow, p.pos), Color(1.0, 0.82, 0.62), 4.0, 0.25, 1.6)
					break
		&"proj_hit":
			var hu: int = e[1]
			var hp2: Vector2 = e[2]
			_small_boom(_end_at(hu, hp2), 26.0)
			_forget(hu)
		&"proj_end":
			var eu: int = e[1]
			var ep2: Vector2 = e[2]
			gfx.flash(_end_at(eu, ep2), HIT, 7.0, 0.3, 1.6, 0.0, 0.3)
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


## Где рисовать конец снаряда: нарисованная точка, если снаряд успел попасть в кадр;
## иначе — его место из события на высоте пускавшего. Раньше запасной точкой был (0, 0, 0):
## снаряд, сбитый или попавший раньше первого кадра (ПВО на том же шаге, 4×), вспыхивал
## в центре поля (хвост G2).
func _end_at(u: int, at: Vector2) -> Vector3:
	if _proj_at.has(u):
		return _proj_at[u]
	if rollback_end_center:
		return Vector3.ZERO
	var y: float = _proj_y0.get(u, 0.0)
	return Vector3(at.x, y, at.y)


static func _px(v: float, what: StringName) -> float:
	return 0.0 if rollback_one_px or what == rollback_px_off else v


func _forget(u: int) -> void:
	_proj_prev.erase(u)
	_proj_y0.erase(u)
	_proj_d0.erase(u)
	_proj_trail.erase(u)
	_proj_at.erase(u)


## Где была цель, которой после шага уже нет: машина — у вида авиации, иначе — на плоскости.
func _gone_pt(u: int, at: Vector2) -> Vector3:
	if craft_at.is_valid():
		var p: Vector3 = craft_at.call(u, at)
		return p
	return Vector3(at.x, 0.0, at.y)


## Выстрел корабля в точку цели at (hr — её радиус попадания). У каждого источника свой вид
## (08, 7.4; план GЭ, п. 4): толщина, цвет, длина, вспышка у ствола, попадание у цели.
func _fire(a: Ship, at: Vector3, hr: float, role: StringName, mount: int) -> void:
	var own := a.side == my_side
	var to := at + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.2, 0.3), _rng.randf_range(-0.3, 0.3)) * hr
	_bump(role)
	if rollback_one_look:
		# откат: все выстрелы — одним видом, источник не читается
		var f0 := _node_pt(a, "muzzle_", mount)
		gfx.beam(f0, to, LIGHT_OWN, 0.9, 0.3, 1.9)
		return
	match role:
		&"main":
			# лазер: белое ядро в цветном ореоле, вспышки на стволе и на цели, через 0,06 с —
			# послесвечение канала, искры и брызги НАВСТРЕЧУ выстрелу (08, 1.3 и 2.13)
			var from := _node_pt(a, "muzzle_", mount)
			var c := MAIN_OWN if own else MAIN_FOE
			var w := 0.9 + a.def.radius * 0.07
			gfx.beam(from, to, c, w * 1.4, 0.55, 2.8, _px(MAIN_PX, &"main"))
			gfx.beam(from, to, Color(1, 1, 1), w * 0.45, 0.35, 2.0, _px(MAIN_CORE_PX, &"main"))
			gfx.beam(from, to, c, w * 0.9, 0.45, 0.6, 0.0, 0.06)
			gfx.flash(from, c, a.def.radius * 1.5, 0.35, 2.2, 0.0, 0.6)
			gfx.flash(to, HIT, hr * 2.2, 0.6, 1.8, 0.0, 0.0)
			gfx.flash(to, CORE, hr * 0.7, 0.12, 1.8, 4.0, 1.0)
			gfx.particle(to, Vector3.ZERO, c, hr * 0.8, hr * 4.0, 0.45, FxPool.RING, 0.0, 0.8)
			# прежний расход _rng (три вспышки попадания до GЭ): концы лучей — те же, что до GЭ
			for i in 9:
				_rng.randf()
			var back := (from - to).normalized()
			for i in 6:
				var v := (back + Vector3(_prng.randf_range(-0.7, 0.7), _prng.randf_range(-0.4, 0.6), _prng.randf_range(-0.7, 0.7))).normalized() * hr * _prng.randf_range(3.0, 7.0)
				gfx.particle(to, v, SPARK_COL, 1.6, 0.6, _prng.randf_range(0.25, 0.5), FxPool.SPARK, 2.0, 1.5)
			for i in 2:
				var v2 := (back + Vector3(_prng.randf_range(-0.5, 0.5), _prng.randf_range(0.0, 0.6), _prng.randf_range(-0.5, 0.5))).normalized() * hr * _prng.randf_range(1.5, 3.0)
				gfx.smoke(to, v2, DEBRIS_COL, 1.4, 1.0, _prng.randf_range(0.8, 1.3), FxPool.DEBRIS, 0.8, 0.9)
		&"sec":
			# очередь из трёх коротких толстых росчерков от точки батареи — свой вид, без тряски
			# (08, 7.2 п. 6); у цели — короткие оранжевые вспышки попаданий
			var from2 := _node_pt(a, "aux_", mount)
			var c2 := SEC_OWN if own else SEC_FOE
			var d2 := from2.distance_to(to)
			for k in 3:
				var jit := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1)) * hr * 0.5
				gfx.tracer(from2, to + jit, c2, 2.4, 1100.0, 24.0, 2.4, k * 0.07, SEC_PX)
				gfx.flash(to + jit, HIT, hr * 0.9, 0.22, 1.5, 0.0, 0.0, k * 0.07 + d2 / 1100.0)
			gfx.flash(from2, c2, 7.0, 0.22, 2.0, 0.0, 0.5)
		_:
			# лёгкое орудие: тонкий быстрый луч своей пары оттенков, искорка у цели
			var from3 := _node_pt(a, "muzzle_", mount)
			var c3 := LIGHT_OWN if own else LIGHT_FOE
			# яркость — с поправкой на сиреневый (он темнее прежнего голубого): луч на старте тоньше
			# главного калибра вдвое, но виден (test_render_air, «на 3990»)
			gfx.beam(from3, to, c3, 0.9, 0.18, 2.4)
			gfx.flash(from3, c3, a.def.radius * 0.6, 0.12, 1.6, 0.0, 0.4)
			gfx.flash(to, c3, hr * 1.2, 0.3, 1.5, 0.0, 0.3)


## Небольшой взрыв (попадание ракеты или торпеды): ядро, огонь, искры, клуб дыма.
func _small_boom(at: Vector3, size: float) -> void:
	gfx.add_pools(PART_SLOTS, SMOKE_SLOTS)
	gfx.flash(at, CORE, size * 0.25, 0.1, 2.0, 4.0, 1.0)
	gfx.flash(at, FIRE_COL, size * 0.9, 0.45, 1.4, 0.0, 0.0)
	for i in 4:
		var v := Vector3(_prng.randf_range(-1, 1), _prng.randf_range(-0.4, 0.8), _prng.randf_range(-1, 1)).normalized() * size * _prng.randf_range(0.6, 1.4)
		gfx.particle(at, v, FIRE_COL, size * 0.2, size * 0.5, _prng.randf_range(0.4, 0.7), FxPool.FIRE, 2.5, 1.1)
	for i in 5:
		var v2 := Vector3(_prng.randf_range(-1, 1), _prng.randf_range(-0.6, 1.0), _prng.randf_range(-1, 1)).normalized() * size * _prng.randf_range(2.0, 4.0)
		gfx.particle(at, v2, SPARK_COL, 1.5, 0.5, _prng.randf_range(0.3, 0.6), FxPool.SPARK, 1.5, 1.4)
	gfx.smoke(at, Vector3(0.0, size * 0.15, 0.0), SMOKE_COL, size * 0.3, size * 0.9, 1.4, FxPool.PUFF, 0.8, 0.5, 0.1)


## Гибель корабля (08, 1.3 и 2.13; план GЭ, п. 3): белым — только маленькое короткое ядро; огненный
## шар, искры, обломки с дымом, кольцо ударной волны, тёмный дым; у тяжёлых — вторичные взрывы по
## корпусу. Размер и сроки — от НАРИСОВАННОЙ длины корабля: гибель флагмана крупнее и дольше корвета.
## Всё на игровом времени (рождение в будущем — вторичные взрывы): пауза — стоит, 4× — быстрее.
func _boom(d: Ship) -> void:
	booms += 1
	gfx.add_pools(PART_SLOTS, SMOKE_SLOTS)          # в игре уже есть; без прогрева — заводятся тут
	var at := _pt(d)
	var r := d.def.radius
	if rollback_white_boom:
		# откат — взрыв до GЭ слово в слово (вспышка с белой серединой во весь размер и вспышки вокруг)
		gfx.flash(at, BOOM, r * 6.0, 1.4, 2.6)
		gfx.flash(at, Color(1, 0.95, 0.8), r * 3.0, 0.6, 3.0)
		for i in maxi(2, roundi(r / 7.0)):
			var off := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-1, 1)) * r * 1.6
			gfx.flash(at + off, BOOM, r * _rng.randf_range(1.5, 3.0), _rng.randf_range(0.6, 1.2), 2.2)
		return
	# прежний расход _rng (вспышки гибели до GЭ: по пять чисел на каждую) — концы лучей те же, что до GЭ
	for i in maxi(2, roundi(r / 7.0)) * 5:
		_rng.randf()
	var v := _vis(d)
	var big := v.length() if v != null else r * 9.0
	# размер и сроки: корвет (~45) — 1, флагман (~207) — около 2,5 по размеру и 1,7 по сроку
	var k := clampf(big / 80.0, 0.5, 2.6)
	var tk := 0.8 + 0.35 * k
	gfx.flash(at, CORE, big * 0.12, 0.08 + 0.02 * k, 2.0, 6.0, 1.0)
	gfx.flash(at, FIRE_COL, big * 0.5, 0.4 * tk, 0.9, 0.0, 0.0)
	gfx.particle(at, Vector3.ZERO, Color(1.0, 0.45, 0.2), big * 0.1, big * 1.3, 0.7 * tk, FxPool.RING, 0.0, 0.35, 0.03)
	for i in 6 + roundi(4.0 * k):
		var dir := Vector3(_prng.randf_range(-1, 1), _prng.randf_range(-0.35, 0.5), _prng.randf_range(-1, 1)).normalized()
		gfx.particle(at + dir * big * 0.08, dir * big * _prng.randf_range(0.25, 0.7), FIRE_COL, big * _prng.randf_range(0.1, 0.15), big * _prng.randf_range(0.26, 0.4), _prng.randf_range(0.7, 1.2) * tk, FxPool.FIRE, 2.2, 0.5)
	for i in 8 + roundi(6.0 * k):
		var dir2 := Vector3(_prng.randf_range(-1, 1), _prng.randf_range(-0.5, 0.8), _prng.randf_range(-1, 1)).normalized()
		gfx.particle(at, dir2 * big * _prng.randf_range(1.0, 2.2), SPARK_COL, 1.8, 0.6, _prng.randf_range(0.35, 0.8), FxPool.SPARK, 1.2, 1.0)
	for i in 4 + roundi(4.0 * k):
		var dir3 := Vector3(_prng.randf_range(-1, 1), _prng.randf_range(-0.3, 0.7), _prng.randf_range(-1, 1)).normalized()
		var sz := big * _prng.randf_range(0.025, 0.05)
		gfx.smoke(at, dir3 * big * _prng.randf_range(0.35, 0.9), DEBRIS_COL, sz, sz * 0.8, _prng.randf_range(1.2, 2.2) * tk, FxPool.DEBRIS, 0.6, 0.95)
	for i in 3 + roundi(3.0 * k):
		var off := Vector3(_prng.randf_range(-1, 1), _prng.randf_range(-0.2, 0.4), _prng.randf_range(-1, 1)) * big * 0.2
		var drift := Vector3(_prng.randf_range(-1, 1), _prng.randf_range(0.2, 1.0), _prng.randf_range(-1, 1)) * big * 0.08
		gfx.smoke(at + off, drift, SMOKE_COL, big * 0.18, big * _prng.randf_range(0.5, 0.75), _prng.randf_range(2.0, 3.2) * tk, FxPool.PUFF, 0.7, 0.75, _prng.randf_range(0.08, 0.35))
	# вторичные взрывы по корпусу — у тяжёлых (у флагмана три, 08, 2.13)
	if d.heavy():
		for i in clampi(roundi(big / 70.0), 1, 3):
			var dt := _prng.randf_range(0.2, 1.1)
			var p := at + Vector3(_prng.randf_range(-1, 1), _prng.randf_range(-0.2, 0.4), _prng.randf_range(-1, 1)) * big * 0.3
			gfx.flash(p, CORE, big * 0.05, 0.08, 2.0, 4.0, 1.0, dt)
			gfx.flash(p, FIRE_COL, big * 0.22, 0.45, 1.2, 0.0, 0.0, dt)
			for j in 3:
				var dj := Vector3(_prng.randf_range(-1, 1), _prng.randf_range(-0.3, 0.6), _prng.randf_range(-1, 1)).normalized()
				gfx.particle(p, dj * big * 0.25, FIRE_COL, big * 0.06, big * 0.16, 0.6, FxPool.FIRE, 2.5, 1.0, dt)


## Залп планеты (03, 2.17): луч с планеты — толстый, своего цвета, с белой серединой и кольцом
## у цели; у ядерной — взрыв во весь радиус (ядро маленькое, огонь — нет).
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
	if rollback_one_look:
		gfx.beam(from, at, LIGHT_OWN, 0.9, 0.3, 1.9)
		return
	gfx.beam(from, at, col, 5.0 if kind == &"nuke" else 3.2, 0.8, 3.0, GUN_PX)
	gfx.beam(from, at, Color(1, 1, 1), 1.4, 0.6, 2.0, GUN_PX * 0.4)
	gfx.particle(at, Vector3.ZERO, col, 10.0, 90.0, 0.7, FxPool.RING, 0.0, 1.2)
	match kind:
		&"nuke":
			gfx.flash(at, CORE, g.def.radius * 0.15, 0.15, 2.4, 6.0, 1.0)
			gfx.flash(at, FIRE_COL, g.def.radius * 1.1, 1.4, 1.4, 0.0, 0.0)
			for i in 14:
				var dir := Vector3(_prng.randf_range(-1, 1), _prng.randf_range(-0.2, 0.6), _prng.randf_range(-1, 1)).normalized()
				gfx.particle(at, dir * g.def.radius * _prng.randf_range(0.4, 0.9), FIRE_COL, g.def.radius * 0.12, g.def.radius * 0.35, _prng.randf_range(0.9, 1.5), FxPool.FIRE, 2.0, 1.0)
			for i in 6:
				gfx.smoke(at + Vector3(_prng.randf_range(-1, 1), 0.0, _prng.randf_range(-1, 1)) * g.def.radius * 0.4, Vector3(0.0, 8.0, 0.0), SMOKE_COL, g.def.radius * 0.2, g.def.radius * 0.6, _prng.randf_range(2.5, 3.5), FxPool.PUFF, 0.6, 0.55, 0.2)
		_:
			gfx.flash(at, col, 60.0, 0.8, 2.0, 0.0, 0.3)
			gfx.flash(at, CORE, 12.0, 0.12, 2.0, 4.0, 1.0)


# ───────────────────────── кадр ─────────────────────────

## Нарисовать кадр: a — доля шага, game_t — игровое время на этом кадре.
## sel — выбранные (uid), hover — корабль под курсором (0 — нет), only_ecm — выбраны одни РЭБ.
func draw(a: float, game_t: float, sel: Array[int], hover: int) -> void:
	_a = a
	gfx.set_time(game_t)
	_draw_projs(a, game_t)
	_draw_domes(sel, hover, game_t)
	_draw_belts(sel, hover)
	_draw_gun()
	_draw_hurt(game_t)


## Подбитые дымят и горят (08, 1.3; план GЭ, п. 3): ниже HURT_SMOKE прочности — клубы тёмного дыма
## с корпуса, ниже HURT_FIRE — ещё и языки огня. Чем ниже прочность, тем чаще. По игровому времени:
## на паузе дым стоит, на 4× идёт вчетверо быстрее.
func _draw_hurt(game_t: float) -> void:
	if rollback_no_hurt_smoke or gfx.smokes == null:
		return
	gfx.now = game_t
	for s in battle.ships:
		if s.dead or s.station or not _shown(s):
			continue
		var f := s.hp_frac()
		if f >= HURT_SMOKE:
			_hurt_t.erase(s.uid)
			continue
		var every := lerpf(HURT_EVERY_MIN, HURT_EVERY_MAX, f / HURT_SMOKE)
		var last: float = _hurt_t.get(s.uid, -1e9)
		if game_t - last < every:
			continue
		_hurt_t[s.uid] = game_t
		var v := _vis(s)
		if v == null:
			continue
		var l := v.length()
		var xf := v.global_transform
		var on := xf * Vector3(_prng.randf_range(-0.3, 0.3) * v.width(), 2.0, _prng.randf_range(-0.4, 0.4) * l)
		var drift := Vector3(_prng.randf_range(-3.0, 3.0), _prng.randf_range(4.0, 9.0), _prng.randf_range(-3.0, 3.0))
		gfx.smoke(on, drift, SMOKE_COL, l * 0.06, l * 0.22, _prng.randf_range(1.6, 2.4), FxPool.PUFF, 0.4, 0.55)
		hurt_puffs += 1
		if f < HURT_FIRE:
			gfx.particle(on, drift * 0.5, FIRE_COL, l * 0.04, l * 0.1, _prng.randf_range(0.3, 0.5), FxPool.FIRE, 1.5, 1.0)


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
		var t := p.target as Body
		if t != null:
			var d0: float = _proj_d0.get(p.uid, 1.0)
			y = lerpf(y0, _body_y(t), clampf(1.0 - xz.distance_to(t.pos) / maxf(d0, 1.0), 0.0, 1.0))
		var at := Vector3(xz.x, y, xz.y)
		_proj_at[p.uid] = at
		var torp := p.key == &"torp"
		mm.set_instance_transform(n, Transform3D(Basis(Vector3.RIGHT, Vector3(_px(TORP_PX if torp else MISSILE_PX, &"missile"), 1.0, 0.0), Vector3(MISSILE.r, MISSILE.g, MISSILE.b)), at))
		mm.set_instance_custom_data(n, Color(0.0, 0.0, 6.0 if torp else 4.0, 2.2))
		var last: float = _proj_trail.get(p.uid, -1.0)
		if game_t - last >= TRAIL_EVERY:
			_proj_trail[p.uid] = game_t
			var back := at - Vector3(p.dir.x, 0.0, p.dir.y) * 3.0
			gfx.now = game_t
			gfx.flash(back, Color(1.0, 0.7, 0.4), 2.6 if torp else 1.8, 0.18, 1.4, _px(PUFF_PX, &"puff"), 0.3)
			# дымный след (08, 2.13: клуб 0x8d8479 раз в 0,035 с) — ракету не спутать ни с трассой ПВО, ни с очередью
			gfx.smoke(back, Vector3.ZERO, TRAIL_SMOKE, 1.4 if torp else 1.0, 4.0 if torp else 3.0, 0.7, FxPool.PUFF, 0.0, 0.45)
		n += 1
	mm.visible_instance_count = n


func _draw_domes(sel: Array[int], hover: int, game_t: float = 0.0) -> void:
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
		# единый фильтр видимости (input/picking.gd → shown; 04, ловушка 33, C67)
		var on := _shown(s) and s.ecm_power > 0.02
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
		var full := rollback_dome_full_rest or hover == s.uid or (only_ecm and s.uid in sel)
		wall.visible = full
		if full:
			wall.position = at
			wall.scale = Vector3(r, 1.0, r)
			var wm := wall.material_override as ShaderMaterial
			wm.set_shader_parameter("color", Vector3(c.r, c.g, c.b))
			wm.set_shader_parameter("power", 0.25 + 0.5 * p)
			wm.set_shader_parameter("now", game_t)
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
	var m := ShaderMaterial.new()
	m.shader = DOME_SHADER
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
	if hs != null and _shown(hs) and hs.range0() > 0.0:
		out.append(hs)
	var own: Array[Ship] = []
	for u in sel:
		var s := battle.ship_by_uid(u)
		if s == null or not _shown(s):
			continue
		var fz := s.forced as Ship
		if fz != null and _shown(fz) and fz.range0() > 0.0 and fz not in out:
			out.append(fz)
		if s.side == my_side and s.range0() > 0.0:
			own.append(s)
	var big := own.size() > 3
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
	# на большом флоте (больше трёх выделенных своих вооружённых) — не больше двух кругов
	# (07, 4.2; план GИ, п. 7): под курсором и главный, или цель фокуса — паутины нет
	var cap := MAX_CIRCLES_BIG if big and not rollback_three_on_big else MAX_CIRCLES
	while out.size() > cap and not rollback_all_circles:
		out.pop_back()
	return out


## Тот же фильтр, что у корабля на экране и выбора (input/picking.gd).
func _shown(s: Ship) -> bool:
	return not s.dead if rollback_no_shown else Picking.shown(s, my_side)


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
