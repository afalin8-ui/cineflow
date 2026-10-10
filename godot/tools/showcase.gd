# tools/showcase.gd — «Стол» (план G0, п. 6): худший бой, какой может собрать игрок,
# без самого боя. «Генеральное» Плэктор × Плэктор С РЕЗЕРВОМ игрока — 83 корабля
# (34 + 14 резерва у атакующего, 34 и станция у защитника; план, раздел 0,
# критерий 3) стоят линиями по местам 09, 5; 240 машин кружат над серединой;
# по линиям бегут лучи и вспышки из пула — нагрузка, похожая на бой.
# Расстановка ВРЕМЕННАЯ: простая таблица мест 09, 5.1–5.5 без логики строя
# (сжатого шага и второй шеренги нет — в П × П линия влезает и так); строй боя —
# sim/formation.gd, пакет G4. Классы вида — те же, что пойдут в бой: ShipVisual,
# CameraRig, CraftLayer, FxPool, SpaceEnv. Сценарий эффектов — по своим часам
# и своему генератору с постоянным зерном: замер кадров повторяем.
extends Node3D

const Defs := preload("res://sim/defs.gd")
const SpaceEnv := preload("res://view/space_env.gd")
const CameraRig := preload("res://view/camera_rig.gd")
const ShipVisual := preload("res://view/ship_visual.gd")
const ShipVisualScene := preload("res://view/ship_visual.tscn")
const CraftLayer := preload("res://view/craft_layer.gd")
const FxPool := preload("res://view/fx_pool.gd")

const ShipModels := preload("res://view/ship_models.gd")

const FACTION := &"plektor"
const SIZE := &"big"
const CRAFT_ROLES: Array[StringName] = [&"interceptor", &"fighter", &"bomber"]
const CRAFT_PER_ROLE := 80
const SQUAD := 6
const SEED := 20261010
# Числа доктрины (высота-картинка ±40 и покачивание ±3 — 09, 11.6; носители по 260
# вбок — 09, 5.1; расстояния камеры в пути замера — 09, 11.2) — из doctrine.json,
# своих здесь нет. Здесь — только сценарий «Стола»: зерно, звенья, маршрут камеры.

## Цвета сторон (C43): свои — холодные, чужие — тёплые.
const OWN_MAIN := Color(0.55, 0.85, 1.0)
const FOE_MAIN := Color(1.0, 0.5, 0.32)
const OWN_LIGHT := Color(0.56, 0.88, 1.0)
const FOE_LIGHT := Color(1.0, 0.7, 0.35)

var defs: Defs
var env: SpaceEnv
var rig: CameraRig
var crafts: CraftLayer
var fx: FxPool
var ships: Array[ShipVisual] = []
var side_of: PackedInt32Array = []          # +1 атакующий (игрок), −1 защитник
var base_pos: PackedVector3Array = []
var bob_phase: PackedFloat32Array = []
var clock := 0.0
## false — эффекты появляются только на 30-м кадре (откат проверки прогрева).
var prewarm := true

var _rng := RandomNumberGenerator.new()
var _guns: Array[Dictionary] = []           # кто стреляет: корабль, узел, оружие, следующий выстрел
var _squads: Array[Dictionary] = []
var _craft_pos: PackedVector3Array = []
var _pd_next := 0.0
var _frame := 0
var _path: Array[Array] = []

## Беды сборки «Стола»: нет модели или файла обмера, в данных нет резерва. Главная
## сцена показывает их на экране и в stderr, и замер кадров не начинается: замер на
## облегчённой сцене обещал бы кадры, которых игрок на худшем бое не получит
## (замечание к G0b; план, раздел 0, критерий 3).
var problems := PackedStringArray()


## Собрать «Стол». false — есть беды (problems), и сцена неполная: модели кораблей
## и машин проверяются ДО расстановки, пропавшая не даёт пустого места молча.
func setup(p_defs: Defs, p_prewarm: bool = true) -> bool:
	defs = p_defs
	prewarm = p_prewarm
	_rng.seed = SEED
	problems.clear()
	var sides := _fleets()
	var attacker: Array[StringName] = sides[0]
	var defender: Array[StringName] = sides[1]
	var need: Array[StringName] = [&"station"]
	for id: StringName in attacker + defender:
		if id not in need:
			need.append(id)
	problems.append_array(ShipModels.problems(FACTION, need, CRAFT_ROLES))
	if not problems.is_empty():
		return false
	env = SpaceEnv.new()
	env.name = "SpaceEnv"
	add_child(env)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.setup(defs.doctrine, defs.consts.field_half)
	env._fit_stars()
	_build_path()
	_place_side(attacker, 1)
	_place_side(defender, -1)
	# станция защитника — на station_back позади его линии старта
	_add_ship(&"station", Vector3(0.0, 0.0, -(defs.doctrine.deploy_heavy_z + defs.doctrine.deploy_station_back)), -1)
	crafts = CraftLayer.new()
	crafts.name = "Crafts"
	add_child(crafts)
	for r in CRAFT_ROLES:
		if not crafts.add_kind(r, FACTION, r, CRAFT_PER_ROLE):
			problems.append("машины %s.%s не встали: модель не загрузилась" % [FACTION, r])
	_make_squads()
	if prewarm:
		_make_fx()
	_update_crafts()
	return problems.is_empty()


## Пул эффектов. Создаётся сразу, вместе со всем остальным: его шейдеры обязаны
## собраться в первых кадрах, а не на первом выстреле (07, ловушка 29).
func _make_fx() -> void:
	fx = FxPool.new()
	fx.name = "Fx"
	fx.setup(512, 512)
	add_child(fx)


func ship_count() -> int:
	return ships.size()


func craft_count() -> int:
	var n := 0
	for r in CRAFT_ROLES:
		n += crafts.count(r)
	return n


# ───────────────────────── расстановка (09, 5.1–5.5) ─────────────────────────

## Составы сторон: [атакующий с резервом, защитник] — id по кораблю (станция
## защитника — отдельно, у неё своё место).
## Нет флота или резерва в данных — беда, а не «Стол» поменьше: без резерва вышло
## бы 69 кораблей вместо 83, и замер мерил бы не худший бой.
func _fleets() -> Array:
	var attacker := _lineup(defs.quick.fleet(SIZE, FACTION))
	var defender := _lineup(defs.quick.fleet(SIZE, FACTION))
	if attacker.is_empty():
		problems.append("в данных нет флота «%s» клана %s" % [SIZE, FACTION])
	var l: Defs.Lineup = defs.quick.reserve.get(FACTION)
	if l == null or l.entries.is_empty():
		problems.append("в данных нет резерва клана %s — «Стол» вышел бы без резерва, не худший бой" % FACTION)
	else:
		attacker.append_array(_lineup(l.entries))      # резерв игрока — на свои места по ролям (09, 5.5)
	return [attacker, defender]


static func _lineup(entries: Array[Defs.FleetEntry]) -> Array[StringName]:
	var out: Array[StringName] = []
	for e in entries:
		for i in e.count:
			out.append(e.id)
	return out


func _place_side(ids: Array[StringName], side: int) -> void:
	var d := defs.doctrine
	var heavies: Array[Defs.ShipDef] = []
	var corv: Array[Defs.ShipDef] = []
	var frig: Array[Defs.ShipDef] = []
	var ecm: Array[Defs.ShipDef] = []
	var carr: Array[Defs.ShipDef] = []
	for id in ids:
		var s := defs.ship(FACTION, id)
		if s.ecm:
			ecm.append(s)
		elif s.hangar > 0:
			carr.append(s)
		elif s.main != null:
			heavies.append(s)
		elif id == &"corvette":
			corv.append(s)
		else:
			frig.append(s)
	# L = 0,85 × наименьшая дальность главного калибра своей линии (09, 5.2)
	var r_line := INF
	for s in heavies:
		r_line = minf(r_line, s.main.rng)
	var L := d.line_L_k * r_line
	var heavy_z := d.deploy_heavy_z
	# тяжёлые: крупные в центре, шаг hull + hull + 60 (09, 5.3)
	heavies.sort_custom(func(a: Defs.ShipDef, b: Defs.ShipDef) -> bool: return a.hull > b.hull)
	var row: Array[Defs.ShipDef] = []
	for i in heavies.size():
		if i % 2 == 0:
			row.append(heavies[i])
		else:
			row.push_front(heavies[i])
	var xs := PackedFloat32Array()
	var x := 0.0
	for i in row.size():
		if i > 0:
			x += row[i - 1].hull + row[i].hull + d.line_step_heavy
		xs.append(x)
	var width := x
	for i in row.size():
		_add_ship(row[i].id, Vector3((xs[i] - width * 0.5) * side, 0.0, side * heavy_z), side)
	# лёгкие шеренги той же ширины, что линия тяжёлых, но не уже 400; РЭБ — в середине
	# шеренги фрегатов (09, 5.1, 5.3)
	var rank_w := maxf(width, d.line_light_min_width)
	_rank(corv, side * (heavy_z - d.line_corvette_k * L), rank_w, side)
	var fr: Array[Defs.ShipDef] = []
	fr.append_array(frig)
	var mid := fr.size() >> 1
	for e in ecm:
		fr.insert(mid, e)
	_rank(fr, side * (heavy_z - d.line_frigate_k * L), rank_w, side)
	# носители — на carrier_back позади линии, по carrier_lat (260) вбок
	for i in carr.size():
		var cx := (float(i) - (carr.size() - 1) * 0.5) * d.deploy_carrier_lat
		_add_ship(carr[i].id, Vector3(cx * side, 0.0, side * (heavy_z + d.line_carrier_back)), side)


func _rank(list: Array[Defs.ShipDef], z: float, width: float, side: int) -> void:
	var n := list.size()
	if n == 0:
		return
	var step := 0.0
	if n > 1:
		var need := 0.0
		for i in range(1, n):
			need += list[i - 1].hull + list[i].hull + defs.doctrine.line_step_light
		step = maxf(need, width) / (n - 1)
	for i in n:
		var cx := (float(i) - (n - 1) * 0.5) * step
		_add_ship(list[i].id, Vector3(cx * side, 0.0, z), side)


func _add_ship(id: StringName, pos: Vector3, side: int) -> void:
	var v := ShipVisualScene.instantiate() as ShipVisual
	if not v.setup(FACTION, id):
		# пустого места молча не бывает: корабль не встал — это беда «Стола»
		problems.append("корабль %s.%s не встал: модель не загрузилась" % [FACTION, id])
		v.free()
		return
	add_child(v)
	v.name = "%s_%s_%d" % ["own" if side > 0 else "foe", id, ships.size()]
	var spread := defs.doctrine.view_height_spread
	var h := _rng.randf_range(-spread, spread)
	var p := Vector3(pos.x, h, pos.z)
	v.position = p
	# нос модели — к −z: атакующий (z > 0) смотрит на защитника как есть, защитник — повёрнут
	v.rotation.y = 0.0 if side > 0 else PI
	ships.append(v)
	side_of.append(side)
	base_pos.append(p)
	bob_phase.append(_rng.randf_range(0.0, TAU))
	var s := defs.ship(FACTION, id) if id != &"station" else defs.station
	if s.main != null:
		var cd := s.main.cd
		_guns.append({"ship": ships.size() - 1, "node": &"muzzle_0", "kind": &"main", "cd": cd, "next": _rng.randf_range(1.0, cd)})
		if s.main.mounts > 1:
			_guns.append({"ship": ships.size() - 1, "node": &"muzzle_1", "kind": &"main", "cd": cd, "next": _rng.randf_range(1.0, cd)})
	if s.sec != null:
		for i in s.sec.mounts:
			_guns.append({"ship": ships.size() - 1, "node": StringName("aux_%d" % i), "kind": &"sec", "cd": s.sec.cd, "next": _rng.randf_range(0.2, s.sec.cd)})
	if s.light != null:
		_guns.append({"ship": ships.size() - 1, "node": &"muzzle_0", "kind": &"light", "cd": s.light.cd, "next": _rng.randf_range(0.2, s.light.cd)})


# ───────────────────────── авиация над серединой ─────────────────────────

func _make_squads() -> void:
	for r in CRAFT_ROLES:
		var n := crafts.count(r)
		var i := 0
		while i < n:
			var sq := {
				"kind": r, "first": i, "size": mini(SQUAD, n - i),
				"c": Vector3(_rng.randf_range(-350.0, 350.0), 0.0, _rng.randf_range(-260.0, 260.0)),
				"r": _rng.randf_range(140.0, 560.0),
				"w": (_rng.randf_range(70.0, 110.0)) * (1.0 if _rng.randf() < 0.5 else -1.0),
				"a": _rng.randf_range(0.0, TAU),
				"h": _rng.randf_range(50.0, 150.0),
				"b": _rng.randf_range(0.0, TAU),
			}
			_squads.append(sq)
			i += SQUAD
	_craft_pos.resize(craft_count())


func _update_crafts() -> void:
	var k := 0
	for sq in _squads:
		var r: float = sq["r"]
		var w: float = sq["w"]
		var a: float = sq["a"]
		var h: float = sq["h"]
		var b: float = sq["b"]
		var c: Vector3 = sq["c"]
		var kind: StringName = sq["kind"]
		var first: int = sq["first"]
		var size: int = sq["size"]
		var th := a + w / r * clock
		var dirw := signf(w)
		var center := c + Vector3(cos(th) * r, h + sin(clock * 0.7 + b) * 25.0, sin(th) * r)
		var fwd := Vector3(-sin(th), 0.0, cos(th)) * dirw
		var lat := fwd.cross(Vector3.UP)
		# звено клином: ведущий впереди, остальные уступом назад и в стороны
		var up := (Vector3.UP + lat * 0.25 * dirw).normalized()
		for m in size:
			var row := (m + 1) >> 1
			var sgn := 1.0 if m % 2 == 1 else -1.0
			var p := center - fwd * (row * 22.0) + lat * (sgn * row * 18.0) + Vector3(0.0, row * 3.0, 0.0)
			crafts.put(kind, first + m, p, fwd, up)
			_craft_pos[k] = p
			k += 1
	crafts.commit()


# ───────────────────────── огонь по расписанию ─────────────────────────

func _fire(delta: float) -> void:
	for g in _guns:
		var nxt: float = g["next"]
		if clock < nxt:
			continue
		var cd: float = g["cd"]
		g["next"] = nxt + cd * _rng.randf_range(0.8, 1.2)
		var si: int = g["ship"]
		var kind: StringName = g["kind"]
		var node: StringName = g["node"]
		var me := ships[si]
		var side := side_of[si]
		var from := me.part_point(node)
		var t := _target(side, kind)
		if t < 0:
			continue
		var to := ships[t].global_position + Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-4.0, 8.0), _rng.randf_range(-12.0, 12.0))
		match kind:
			&"main":
				var c := OWN_MAIN if side > 0 else FOE_MAIN
				fx.beam(from, to, c, 3.0, 0.55, 2.6)
				fx.flash(from, c, 26.0, 0.35, 2.0)
				fx.flash(to, Color(1.0, 0.75, 0.45), 70.0, 0.9, 2.2)
			&"sec":
				var c2 := OWN_LIGHT if side > 0 else FOE_LIGHT
				fx.beam(from, to, c2, 1.4, 0.14, 2.0)
				fx.flash(to, c2, 16.0, 0.25, 1.6)
			_:
				var c3 := OWN_LIGHT if side > 0 else FOE_LIGHT
				fx.beam(from, to, c3, 1.0, 0.18, 1.8)
				fx.flash(to, c3, 12.0, 0.3, 1.4)
	# ПВО и очереди над серединой: короткие трассы между машинами
	_pd_next -= delta
	while _pd_next <= 0.0 and _craft_pos.size() > 1:
		_pd_next += 1.0 / 30.0
		var a := _craft_pos[_rng.randi_range(0, _craft_pos.size() - 1)]
		var b := _craft_pos[_rng.randi_range(0, _craft_pos.size() - 1)]
		var dir := (b - a).normalized()
		var c4 := OWN_LIGHT if _rng.randf() < 0.5 else FOE_LIGHT
		fx.beam(a, a + dir * 46.0, c4, 0.55, 0.12, 2.2)
		if _rng.randf() < 0.3:
			fx.flash(a + dir * 46.0, c4, 8.0, 0.2, 1.5)


## Цель: тяжёлого бьют тяжёлые главным калибром, батарея и лёгкие — по лёгким.
func _target(side: int, kind: StringName) -> int:
	for _try in 12:
		var t := _rng.randi_range(0, ships.size() - 1)
		if side_of[t] == side:
			continue
		var heavy := ships[t].ship_id in [&"cruiser", &"capital", &"sinho", &"station"]
		if (kind == &"main") == heavy:
			return t
	return -1


func _process(delta: float) -> void:
	if crafts == null:
		return           # «Стол» не собран (беды в problems) — двигать нечего
	clock += delta
	_frame += 1
	if fx == null:
		if _frame >= 30:
			_make_fx()       # откат: эффекты впервые на 30-м кадре — их конвейеры соберутся посреди игры
		else:
			return
	var bob := defs.doctrine.view_bob
	for i in ships.size():
		var p := base_pos[i]
		ships[i].position = Vector3(p.x, p.y + sin(clock * 0.6 + bob_phase[i]) * bob, p.z)
	_update_crafts()
	fx.set_time(clock)
	_fire(delta)


# ───────────────────────── путь камеры для замера кадров ─────────────────────────

## Маршрут замера: (секунда, точка взгляда x, z, поворот, расстояние). Расстояния
## — ключи доктрины (camera.dist_start 3990, dist_work 2400, dist_max 5000: в пути
## и рабочий вид, и дальний предел — план G0, п. 7; на 5000 в кадре весь «стол»),
## z = &"start" — стартовая точка взгляда camera.start_look_z (470). Числа здесь —
## только сам маршрут: когда и куда смотреть.
const PATH_PLAN: Array[Array] = [
	[0.0, 0.0, &"start", 0.0, &"start"],
	[8.0, 0.0, 180.0, 0.0, &"work"],
	[18.0, -650.0, 60.0, 0.45, &"work"],
	[28.0, 650.0, -120.0, -0.5, &"work"],
	[36.0, 0.0, 0.0, -0.5, &"max"],
	[48.0, 0.0, 0.0, 2.0, &"max"],
	[55.0, 0.0, -300.0, 3.1, &"work"],
	[60.0, 0.0, &"start", TAU, &"start"],
]
const PATH_LEN := 60.0


## Маршрут с числами доктрины: [секунда, x, z, поворот, расстояние].
func _build_path() -> void:
	var d := defs.doctrine
	var dist: Dictionary[StringName, float] = {&"start": d.camera_dist_start, &"work": d.camera_dist_work, &"max": d.camera_dist_max}
	_path.clear()
	for row: Array in PATH_PLAN:
		var t: float = row[0]
		var x: float = row[1]
		var zv: Variant = row[2]
		var z := d.camera_start_look_z
		if typeof(zv) != TYPE_STRING_NAME:
			z = zv
		var yaw: float = row[3]
		var dk: StringName = row[4]
		_path.append([t, x, z, yaw, dist[dk]])


## Расстояния маршрута по порядку — для проверок (рабочий вид и дальний предел в пути).
func path_dists() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for row in _path:
		var dd: float = row[4]
		out.append(dd)
	return out


## Поставить камеру в точку пути на секунде t (0…60) — сразу, без сглаживания.
func drive(t: float) -> void:
	var tt := clampf(t, 0.0, PATH_LEN)
	var i := 0
	while i < _path.size() - 2:
		var nxt: Array = _path[i + 1]
		var tn: float = nxt[0]
		if tt <= tn:
			break
		i += 1
	var a: Array = _path[i]
	var b: Array = _path[i + 1]
	var t0: float = a[0]
	var t1: float = b[0]
	var k := smoothstep(0.0, 1.0, (tt - t0) / maxf(t1 - t0, 0.001))
	var ax: float = a[1]
	var az: float = a[2]
	var ay: float = a[3]
	var ad: float = a[4]
	var bx: float = b[1]
	var bz: float = b[2]
	var by: float = b[3]
	var bd: float = b[4]
	rig.set_view(Vector3(lerpf(ax, bx, k), 0.0, lerpf(az, bz, k)), lerpf(ay, by, k), exp(lerpf(log(ad), log(bd), k)), true)
