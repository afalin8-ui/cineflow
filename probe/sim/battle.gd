## Модель боя на орбите (проба архитектуры): чистый GDScript, без узлов.
## Постоянный шаг, своя случайность с зерном, никаких обращений к сцене.
## Вид читает поля и журнал событий; сам в модель не пишет.
extends RefCounted

const Defs = preload("res://sim/defs.gd")
const Metrics = preload("res://sim/metrics.gd")

const STEP := 1.0 / 30.0
const FIELD := 2600.0
const REV := 0.6
const BRAKE_K := 0.85

# --- сущности -------------------------------------------------------------

class Ship:
	var kind := 0
	var uid: int
	var side: int
	var clan: String
	var d: Defs.ShipDef
	var cls: int
	var pos := Vector3.ZERO    # y == 0 всегда: бой плоский (09, 11.6); высота — только у вида
	var vel := Vector3.ZERO
	var yaw := 0.0
	var fwd := Vector3.FORWARD
	var hp: float
	var max_hp: float
	var dead := false
	var anchor := Vector3.ZERO
	var leash := 240.0
	var main_t = null
	var sec_t = null
	var light_t = null
	var retarget := 0.0
	var main_cd := PackedFloat32Array()
	var sec_cd := PackedFloat32Array()
	var light_cd := 0.0
	var miss_cd := 0.0
	var pd_cd := PackedFloat32Array()
	var state := 0             # 0 стоит/держит · 1 подход · 2 отход · 3 к участку
	var retreating := false
	var win_t := 0.0
	var win_d0 := 0.0
	var futile_from = null
	var futile_until := 0.0
	var jam_slow := 1.0        # множитель хода перезарядки главного калибра под помехами
	var jammed := false
	var hangar_free := 0
	var rebuild := PackedFloat32Array()
	var ecm_on := false
	var sp_i := -1
	var thrust_k := 1.0        # задел на узлы: «двигатели» (09, 10.3)

	func thrust() -> float: return d.thrust * thrust_k
	func max_speed() -> float: return d.max_speed
	func turn() -> float: return d.turn * thrust_k
	func armor_toward(_dir: Vector3) -> float: return d.armor

class Craft:
	var kind := 1
	var uid: int
	var side: int
	var d: Defs.CraftDef
	var squad
	var slot: int
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var yaw := 0.0
	var fwd := Vector3.FORWARD
	var hp: float
	var dead := false
	var target = null
	var cd := 0.0
	var ammo := 0
	var reloads := 0
	var reloading := 0.0
	var phase := 0             # бомбардировщик: 0 заход, 1 отворот
	var break_until := 0.0
	var cls := 3
	var radius := 2.6

class Squad:
	var side: int
	var role: StringName
	var home                   # Ship
	var craft: Array = []
	var dead := false
	var recall := false

class Proj:
	var kind := 2
	var side: int
	var owner
	var target
	var pos := Vector3.ZERO
	var dir := Vector3.FORWARD
	var speed: float
	var dmg: float
	var key: StringName
	var hp: float
	var life := 16.0
	var k := 1.8
	var dead := false
	var cls := 4
	var radius := 1.8

# --- состояние боя ---------------------------------------------------------

var defs: Defs
var rng := RandomNumberGenerator.new()
var time := 0.0
var steps := 0
var ships: Array[Ship] = []
var side_ships: Array = [[], []]       # Array[Ship] по сторонам (живые), пересобираются раз в шаг
var crafts: Array[Craft] = []
var side_craft: Array = [[], []]
var squads: Array[Squad] = []
var projs: Array[Proj] = []
var side_proj: Array = [[], []]
# снимок начала шага в упакованных массивах — для всех парных расчётов (замер: в 10 раз быстрее обхода объектов)
var sp_ref: Array = []
var sp_pos := PackedVector3Array()
var sp_push := PackedVector3Array()
var sp_near := PackedInt32Array()
var sp_near_d := PackedFloat32Array()
var side_cpos: Array = [PackedVector3Array(), PackedVector3Array()]
var side_ppos: Array = [PackedVector3Array(), PackedVector3Array()]
var ecm_fields: Array = [[], []]       # поля помех, которые накрывают сторону i (то есть ЧУЖИЕ купола)
var uid_seq := 0
var ai: Array = []                     # по объекту ИИ на сторону
var events: Array = []                 # журнал шага: [вид, ...] — вид и метрики его читают
var metrics: Metrics
var winner := -1
var clans := ["", ""]
var ended := false
var doc: Dictionary

func setup(p_defs: Defs, seed_value: int, fleets: Array, p_clans: Array) -> void:
	defs = p_defs
	doc = defs.doctrine
	rng.seed = seed_value
	clans = p_clans
	metrics = Metrics.new()
	var AiScript = load("res://sim/ai.gd")
	for side in 2:
		var a = AiScript.new()
		a.side = side
		a.battle = self
		a.next_tick = 3.0
		ai.append(a)
		_deploy(side, fleets[side])

func _deploy(side: int, fleet: Array) -> void:
	var sgn := 1.0 if side == 0 else -1.0
	var z_heavy: float = doc["deploy"]["heavy_z"] * sgn
	var lanes := {Defs.CAPITAL: z_heavy, Defs.ESCORT: z_heavy - sgn * 232.0, Defs.CARRIER: z_heavy + sgn * 440.0}
	var counts := {}
	for row in fleet:
		for i in row["count"]:
			var d = defs.ships[clans[side]][StringName(row["id"])]
			var s := Ship.new()
			uid_seq += 1
			s.uid = uid_seq
			s.side = side
			s.clan = clans[side]
			s.d = d
			s.cls = d.cls
			s.hp = d.hp * 1.0
			s.max_hp = s.hp
			var lane: float = lanes.get(d.cls, z_heavy)
			if d.id == &"frigate" or d.id == &"ecm":
				lane = z_heavy - sgn * 133.0
			var n: int = counts.get(lane, 0)
			counts[lane] = n + 1
			var x: float = (n / 2 + 0.5) * (d.hull * 2.0 + 50.0) * (1.0 if n % 2 == 0 else -1.0)
			s.pos = Vector3(x, 0.0, lane)
			s.anchor = s.pos
			s.yaw = 0.0 if side == 0 else PI
			s.fwd = Vector3(-sin(s.yaw), 0.0, -cos(s.yaw))
			if d.main:
				for m in d.main.mounts:
					s.main_cd.append(rng.randf_range(0.0, d.main.cd))
			if d.sec:
				for m in d.sec.mounts:
					s.sec_cd.append(rng.randf_range(0.0, d.sec.cd))
			if d.light:
				s.light_cd = rng.randf_range(0.0, d.light.cd)
			for b in d.pd_count:
				s.pd_cd.append(rng.randf_range(0.0, 0.4))
			s.retarget = rng.randf()
			s.hangar_free = d.hangar
			s.leash = _leash_of(s)
			s.ecm_on = d.id == &"ecm"
			ships.append(s)

func _leash_of(s: Ship) -> float:
	if s.d.main:
		return s.d.main.rng * doc["leash"]["capital_k"]
	if s.d.id == &"frigate":
		return doc["leash"]["frigate"]
	return doc["leash"]["corvette"]

# --- шаг ------------------------------------------------------------------

func step() -> void:
	if ended:
		return
	var dt := STEP
	time += dt
	steps += 1
	events.clear()
	_rebuild_lists()
	_update_ecm()
	for a in ai:
		a.snapshot()                    # ИИ думают по снимку начала шага (09, 4.5)
	for a in ai:
		a.tick(dt)
	for s in ships:
		if not s.dead:
			_update_ship(s, dt)
	for c in crafts:
		if not c.dead:
			_update_craft(c, dt)
	for p in projs:
		if not p.dead:
			_update_proj(p, dt)
	_cleanup()
	metrics.sample(self, dt)
	_check_end()

func _rebuild_lists() -> void:
	for i in 2:
		side_ships[i].clear(); side_craft[i].clear(); side_proj[i].clear()
	for s in ships:
		if not s.dead:
			side_ships[s.side].append(s)
	for c in crafts:
		if not c.dead:
			side_craft[c.side].append(c)
	for p in projs:
		if not p.dead:
			side_proj[p.side].append(p)
	_build_spatial()

func _build_spatial() -> void:
	sp_ref.clear()
	for s in ships:
		s.sp_i = -1
		if not s.dead:
			s.sp_i = sp_ref.size()
			sp_ref.append(s)
	var n := sp_ref.size()
	sp_pos.resize(n); sp_push.resize(n); sp_near.resize(n); sp_near_d.resize(n)
	var hull := PackedFloat32Array(); hull.resize(n)
	var side := PackedInt32Array(); side.resize(n)
	var vmax := PackedFloat32Array(); vmax.resize(n)
	for i in n:
		var sh: Ship = sp_ref[i]
		sp_pos[i] = sh.pos; hull[i] = sh.d.hull; side[i] = sh.side; vmax[i] = sh.d.max_speed
	sp_push.fill(Vector3.ZERO)
	sp_near.fill(-1)
	sp_near_d.fill(INF)
	# один проход пар i<j: расталкивание (09, 5.7) и ближайший чужой корабль
	for i in n:
		var pi := sp_pos[i]; var hi := hull[i]; var si := side[i]
		for j in range(i + 1, n):
			var off := pi - sp_pos[j]
			var d2 := off.length_squared()
			var is_foe := side[j] != si
			if is_foe:
				if d2 < sp_near_d[i]: sp_near_d[i] = d2; sp_near[i] = j
				if d2 < sp_near_d[j]: sp_near_d[j] = d2; sp_near[j] = i
			var mn := (hull[j] + hi) * (1.15 if is_foe else 1.0)
			if d2 < mn * mn and d2 > 0.0001:
				var dd := sqrt(d2)
				var k := (mn - dd) / mn / dd * (1.1 if is_foe else 0.8)
				sp_push[i] += off * (k * vmax[i])
				sp_push[j] -= off * (k * vmax[j])
	for i in n:
		sp_near_d[i] = sqrt(sp_near_d[i])
	for sd in 2:
		var cp: PackedVector3Array = side_cpos[sd]
		cp.resize(side_craft[sd].size())
		for k in side_craft[sd].size(): cp[k] = side_craft[sd][k].pos
		var pp: PackedVector3Array = side_ppos[sd]
		pp.resize(side_proj[sd].size())
		for k in side_proj[sd].size(): pp[k] = side_proj[sd][k].pos

func _update_ecm() -> void:
	ecm_fields[0].clear(); ecm_fields[1].clear()
	for s in ships:
		if not s.dead and s.ecm_on:
			ecm_fields[1 - s.side].append(s)

# --- корабль ----------------------------------------------------------------

func _update_ship(s: Ship, dt: float) -> void:
	var foe: Array = side_ships[1 - s.side]
	# помехи над кораблём
	s.jammed = false
	for e in ecm_fields[s.side]:
		if e.pos.distance_squared_to(s.pos) < 420.0 * 420.0:
			s.jammed = true
			break
	s.jam_slow = 0.5 if s.jammed else 1.0
	# цели
	s.retarget -= dt
	if s.main_t != null and s.main_t.dead: s.main_t = null
	if s.light_t != null and s.light_t.dead: s.light_t = null
	if s.sec_t != null and (s.sec_t.dead or s.sec_t.pos.distance_squared_to(s.pos) > s.d.sec.rng * s.d.sec.rng):
		s.sec_t = null
	if s.retarget <= 0.0:
		s.retarget = rng.randf_range(0.8, 1.6)
		if s.d.main: s.main_t = _main_acquire(s, foe)
		if s.d.light: s.light_t = _light_acquire(s, foe)
	if s.d.sec and s.sec_t == null:
		s.sec_t = _nearest_ship(s.pos, foe, s.d.sec.rng)
	# движение
	var want := Vector3.ZERO
	var near_d: float = sp_near_d[s.sp_i]
	var near = sp_ref[sp_near[s.sp_i]] if sp_near[s.sp_i] >= 0 else null
	if s.d.max_speed <= 0.0:
		pass
	elif s.d.main:
		want = _capital_want(s, foe, near, near_d, dt)
	elif s.d.light:
		want = _light_want(s)
	else:
		if s.pos.distance_to(s.anchor) > 12.0:
			want = _arrive(s, s.anchor, s.d.max_speed)
	# расталкивание: каждый с каждым (09, 5.7; 02, 2.10)
	if s.d.max_speed > 0.0:
		want += sp_push[s.sp_i]
		_thrust_to(s, want, dt)
		var cap := s.d.max_speed * 1.25
		if s.vel.length_squared() > cap * cap:
			s.vel = s.vel.normalized() * cap
		_face_ship(s, want, foe, dt)
		_integrate(s, dt)
	elif s.main_t != null:
		_face(s, s.main_t.pos - s.pos, s.d.turn, dt)
	# огонь
	if s.d.main: _fire_main(s, dt)
	if s.d.sec: _fire_sec(s, dt)
	if s.d.light: _fire_light(s, dt)
	if s.d.missile: _fire_missile(s, dt)
	_fire_pd(s, dt)

func _main_acquire(s: Ship, foe: Array) -> Ship:
	var w: Defs.WeaponDef = s.d.main
	var reach := w.rng * 1.3
	var best: Ship = null
	var best_score := -INF
	var ew: float = doc["main"]["escort_weight"]
	for o: Ship in foe:
		var m: float = defs.dmg_table[&"heavy"][o.cls]
		if m <= 0.0: continue
		var dd := s.pos.distance_to(o.pos)
		if dd < w.dead or dd > reach: continue
		var sc := (ew if o.cls == Defs.ESCORT else 1.0) * 1000.0 - dd + (1.0 - o.hp / o.max_hp) * 400.0
		if o.cls == Defs.CARRIER: sc += 250.0
		if sc > best_score:
			best_score = sc; best = o
	if best == null:
		var bd := INF
		for o: Ship in foe:
			var dd := s.pos.distance_to(o.pos)
			if dd >= w.dead and dd < bd:
				bd = dd; best = o
	return best

func _light_acquire(s: Ship, foe: Array) -> Ship:
	var w: Defs.WeaponDef = s.d.light
	var reach := w.rng * 1.3
	var lim := s.leash + w.rng
	var best: Ship = null
	var best_score := -INF
	for o: Ship in foe:
		var m: float = defs.dmg_table[&"light"][o.cls]
		if m <= 0.0: continue
		var dd := s.pos.distance_to(o.pos)
		if dd > reach + s.leash or o.pos.distance_to(s.anchor) > lim: continue
		var sc := m * 1000.0 - dd + (1.0 - o.hp / o.max_hp) * 400.0
		if sc > best_score:
			best_score = sc; best = o
	return best

func _nearest_ship(p: Vector3, list: Array, max_d: float) -> Ship:
	var best: Ship = null
	var bd := max_d * max_d
	for o: Ship in list:
		var dd := p.distance_squared_to(o.pos)
		if dd < bd:
			bd = dd; best = o
	return best

func _arrive_speed(s: Ship, dist: float, vmax: float) -> float:
	if dist <= 0.0: return 0.0
	var a_b := s.thrust() * REV * BRAKE_K        # тормоз — от ТОЙ ЖЕ тяги (ловушка 2 части 02)
	return min(vmax, sqrt(2.0 * a_b * dist), 1.5 * dist)

func _arrive(s: Ship, goal: Vector3, vmax: float) -> Vector3:
	var to := goal - s.pos
	var dd := to.length()
	if dd < 0.5: return Vector3.ZERO
	return to / dd * _arrive_speed(s, dd, vmax)

func _capital_want(s: Ship, foe: Array, near, near_d: float, dt: float) -> Vector3:
	var R: float = s.d.main.rng
	var D: float = s.d.main.dead
	var belt: Dictionary = doc["belt"]
	var clear: bool = near_d > R * belt["clear_k"]
	# «не оторваться» забывается, когда враг дальше 0,5 R и прошло 15 с
	if s.futile_from != null and (s.futile_from.dead or (time > s.futile_until and s.futile_from.pos.distance_to(s.pos) > R * belt["back_off_k"])):
		s.futile_from = null
	var intr: bool = near != null and near_d < D and near != s.futile_from
	if intr and not s.retreating:
		s.retreating = true; s.win_t = 0.0; s.win_d0 = near_d
	if s.retreating and (near == null or near_d >= R * belt["back_off_k"]):
		s.retreating = false
	if s.retreating:
		var ax: Vector3 = ai[s.side].ax
		var away := Vector3.ZERO
		for o in foe:
			var off: Vector3 = s.pos - o.pos
			var l2 := off.length_squared()
			if l2 < D * D and l2 > 1.0:
				away += off / sqrt(l2)
		away += -ax * 0.5
		var fwd_c := away.dot(ax)
		if fwd_c > 0.0: away -= ax * fwd_c            # отход вперёд не ведёт (09, 2.6)
		# края поля и рубеж
		if absf(s.pos.x) > FIELD - 200.0 and signf(away.x) == signf(s.pos.x): away.x = 0.0
		if absf(s.pos.z) > FIELD - 200.0 and signf(away.z) == signf(s.pos.z): away.z = 0.0
		if away.length_squared() < 0.09:
			s.state = 0
			return Vector3.ZERO                        # «прижат»
		# часы «не оторваться» — только на ходу от врага
		var away_speed := s.vel.dot((s.pos - near.pos).normalized())
		if away_speed >= 0.5 * s.d.max_speed:
			s.win_t += dt
			if s.win_t >= doc["retreat"]["window"]:
				if near_d - s.win_d0 < doc["retreat"]["gain"]:
					s.futile_from = near; s.futile_until = time + doc["retreat"]["forget"]
					s.retreating = false
				s.win_t = 0.0; s.win_d0 = near_d
		s.state = 2
		return away.normalized() * s.d.max_speed
	var t: Ship = s.main_t
	if t != null:
		var to: Vector3 = t.pos - s.pos
		var dd := to.length()
		if dd > R * belt["far_k"] and clear:
			var x: float = dd - R * belt["work_k"]
			var v_cl := maxf(0.0, t.vel.dot(-to / dd))
			x = x * s.d.max_speed / (s.d.max_speed + v_cl)           # доля сближения (09, 2.3)
			var sp := minf(_arrive_speed(s, x, s.d.max_speed), _arrive_speed(s, near_d - R * belt["clear_k"], s.d.max_speed))
			s.state = 1
			return to / dd * sp
		s.state = 0
		return Vector3.ZERO
	var to_a := s.anchor - s.pos
	if to_a.length() > 12.0 and clear:
		s.state = 3
		var sp2 := minf(_arrive_speed(s, to_a.length(), s.d.max_speed), _arrive_speed(s, near_d - R * belt["clear_k"], s.d.max_speed))
		return to_a.normalized() * sp2
	s.state = 0
	return Vector3.ZERO

func _light_want(s: Ship) -> Vector3:
	var t: Ship = s.light_t
	if t == null:
		if s.pos.distance_to(s.anchor) > 12.0:
			return _arrive(s, s.anchor, s.d.max_speed)
		return Vector3.ZERO
	var rng0: float = s.d.light.rng
	var want_r := rng0 * 0.68
	var dd := s.pos.distance_to(t.pos)
	var r := want_r if (dd < want_r * 0.55 or dd > want_r * 1.08) else dd
	var point: Vector3 = t.pos + (s.pos - t.pos).normalized() * r
	var off := point - s.anchor
	if off.length() > s.leash:
		point = s.anchor + off.normalized() * s.leash
	if point.distance_to(s.pos) < 10.0:
		return Vector3.ZERO
	return _arrive(s, point, s.d.max_speed)

func _thrust_to(s, want: Vector3, dt: float) -> void:
	var need: Vector3 = want - s.vel
	var l := need.length()
	if l < 0.0001: return
	var n := need / l
	var align := maxf(0.0, s.fwd.dot(n))
	var th: float = s.thrust() if s is Ship else s.d.thrust
	var rev := REV if s is Ship else 0.3
	var power := th * (rev + (1.0 - rev) * align)
	s.vel += n * minf(l, power * dt)

func _face_ship(s: Ship, want: Vector3, foe: Array, dt: float) -> void:
	var look := Vector3.ZERO
	if s.main_t != null and s.main_t.pos.distance_to(s.pos) < s.d.main.rng * 1.5:
		look = s.main_t.pos - s.pos
	elif s.d.main:
		var fc := _nearest_capital(s, foe, s.d.main.rng * 1.5)
		if fc: look = fc.pos - s.pos
	elif s.light_t != null and s.light_t.pos.distance_to(s.pos) < s.d.light.rng * 1.5:
		look = s.light_t.pos - s.pos
	if look == Vector3.ZERO:
		if want.length_squared() > 1.0: look = want
		elif s.vel.length_squared() > 1.0: look = s.vel
	if look != Vector3.ZERO:
		_face(s, look, s.turn(), dt)

func _nearest_capital(s: Ship, foe: Array, max_d: float) -> Ship:
	var best: Ship = null
	var bd := max_d * max_d
	for o: Ship in foe:
		if o.cls != Defs.CAPITAL: continue
		var dd := s.pos.distance_squared_to(o.pos)
		if dd < bd:
			bd = dd; best = o
	return best

func _face(s, dir: Vector3, turn: float, dt: float) -> void:
	# плоский бой: «slerp вокруг вертикали» == доля оставшегося угла по рысканью
	var target_yaw := atan2(-dir.x, -dir.z)
	s.yaw = lerp_angle(s.yaw, target_yaw, clampf(turn * dt, 0.0, 1.0))
	s.fwd = Vector3(-sin(s.yaw), 0.0, -cos(s.yaw))

func _integrate(s, dt: float) -> void:
	s.pos += s.vel * dt
	if s.pos.x > FIELD:
		s.pos.x = FIELD
		if s.vel.x > 0.0: s.vel.x *= -0.3
	elif s.pos.x < -FIELD:
		s.pos.x = -FIELD
		if s.vel.x < 0.0: s.vel.x *= -0.3
	if s.pos.z > FIELD:
		s.pos.z = FIELD
		if s.vel.z > 0.0: s.vel.z *= -0.3
	elif s.pos.z < -FIELD:
		s.pos.z = -FIELD
		if s.vel.z < 0.0: s.vel.z *= -0.3

# --- оружие ------------------------------------------------------------------

func _fire_main(s: Ship, dt: float) -> void:
	var w: Defs.WeaponDef = s.d.main
	for i in s.main_cd.size():
		s.main_cd[i] -= dt * s.jam_slow                # под помехами медленнее идёт ТАЙМЕР (09, 1.7)
	var t: Ship = s.main_t
	if t == null: return
	var to := t.pos - s.pos
	var dd := to.length()
	if dd > w.rng or dd < w.dead: return               # мёртвая зона — до накачки (09, 1.2)
	if s.fwd.dot(to / dd) < 0.25: return
	for i in s.main_cd.size():
		if s.main_cd[i] <= 0.0 and not t.dead:
			s.main_cd[i] = w.cd
			damage(t, w.dmg, &"heavy", s, to / dd)
			events.append([&"beam", s, t, &"main"])

func _fire_sec(s: Ship, dt: float) -> void:
	var w: Defs.WeaponDef = s.d.sec
	for i in s.sec_cd.size():
		s.sec_cd[i] -= dt
	var t: Ship = s.sec_t
	if t == null: return
	var dd := s.pos.distance_to(t.pos)
	if s.jammed and dd > 170.0: return
	for i in s.sec_cd.size():
		if s.sec_cd[i] <= 0.0 and not t.dead:
			s.sec_cd[i] = w.cd
			damage(t, w.dmg, &"sec", s, (t.pos - s.pos) / maxf(dd, 0.01))
			events.append([&"beam", s, t, &"sec"])

func _fire_light(s: Ship, dt: float) -> void:
	var w: Defs.WeaponDef = s.d.light
	s.light_cd -= dt
	var t: Ship = s.light_t
	if t == null or s.light_cd > 0.0: return
	var to := t.pos - s.pos
	var dd := to.length()
	if dd > w.rng or (s.jammed and dd > 170.0): return
	if s.fwd.dot(to / dd) < 0.25: return
	s.light_cd = w.cd
	damage(t, w.dmg, &"light", s, to / dd)
	events.append([&"beam", s, t, &"light"])

func _fire_missile(s: Ship, dt: float) -> void:
	var w: Defs.WeaponDef = s.d.missile
	s.miss_cd -= dt
	if s.miss_cd > 0.0: return
	var t: Ship = s.main_t if (s.main_t != null and s.main_t.pos.distance_to(s.pos) < w.rng) else _nearest_ship(s.pos, side_ships[1 - s.side], w.rng)
	if t == null: return
	s.miss_cd = w.cd
	for i in w.salvo:
		var dir := (t.pos - s.pos).normalized() + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.06
		_spawn_proj(s.side, s, t, s.pos, dir.normalized(), 130.0, 26.0, w.dmg, &"missile", 1.8)

func _fire_pd(s: Ship, dt: float) -> void:
	var r2: float = s.d.pd_range * s.d.pd_range
	for i in s.pd_cd.size():
		s.pd_cd[i] -= dt
		if s.pd_cd[i] > 0.0: continue
		var t = null
		var bd := r2
		var pp: PackedVector3Array = side_ppos[1 - s.side]
		var plist: Array = side_proj[1 - s.side]
		for k in pp.size():
			var dd := s.pos.distance_squared_to(pp[k])
			if dd < bd and not plist[k].dead:
				bd = dd; t = plist[k]
		if t == null:
			var cp: PackedVector3Array = side_cpos[1 - s.side]
			var clist: Array = side_craft[1 - s.side]
			for k in cp.size():
				var dd := s.pos.distance_squared_to(cp[k])
				if dd < bd and not clist[k].dead:
					bd = dd; t = clist[k]
		if t == null:
			s.pd_cd[i] = 0.2
			continue
		s.pd_cd[i] = s.d.pd_cd * rng.randf_range(0.85, 1.2)
		damage(t, s.d.pd_dmg * (0.6 if s.jammed else 1.0), &"pd", s, Vector3.ZERO)

func _spawn_proj(side: int, owner, target, at: Vector3, dir: Vector3, speed: float, hp: float, dmg: float, key: StringName, k: float) -> Proj:
	var p := Proj.new()
	p.side = side; p.owner = owner; p.target = target
	p.pos = at; p.dir = dir; p.speed = speed; p.hp = hp; p.dmg = dmg; p.key = key; p.k = k
	projs.append(p)
	side_proj[side].append(p)
	side_ppos[side].append(at)
	return p

## Урон — одна дверь на всё, с направлением с первого дня (09, 10.2).
func damage(t, amount: float, key: StringName, src, from_dir: Vector3) -> void:
	if t == null or t.dead or amount <= 0.0: return
	var m: float = defs.dmg_table[key][t.cls]
	if m <= 0.0: return
	var armor: float = t.armor_toward(from_dir) if t is Ship else (t.d.armor if t is Craft else 0.0)
	var before: float = t.hp
	t.hp -= amount * m * (1.0 - armor)
	var dealt := before - maxf(0.0, t.hp)
	metrics.on_damage(self, t, dealt, key, src)
	if t.hp <= 0.0:
		t.dead = true
		events.append([&"destroyed", t, src])

# --- авиация -----------------------------------------------------------------

func launch_squad(home: Ship, role: StringName) -> void:
	if home.hangar_free <= 0 or home.dead: return
	home.hangar_free -= 1
	var sq := Squad.new()
	sq.side = home.side; sq.role = role; sq.home = home
	var cd = defs.craft[home.clan][role]
	var n: int = defs.squad_size[home.clan]
	for i in n:
		var c := Craft.new()
		uid_seq += 1
		c.uid = uid_seq
		c.side = home.side; c.d = cd; c.squad = sq; c.slot = i
		c.hp = cd.hp; c.ammo = cd.ammo; c.reloads = cd.reloads
		c.cd = rng.randf_range(0.0, cd.cd)
		c.pos = home.pos + Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
		c.yaw = home.yaw; c.fwd = home.fwd; c.vel = home.vel
		sq.craft.append(c)
		crafts.append(c)
		side_craft[c.side].append(c)
		side_cpos[c.side].append(c.pos)
	squads.append(sq)
	metrics.squads_up[home.side] += 1

func _craft_acquire(c: Craft):
	var foe_c: Array = side_craft[1 - c.side]
	var foe_s: Array = side_ships[1 - c.side]
	match c.d.role:
		&"interceptor":
			var t = _nearest_in(c.pos, foe_c, 1000.0)
			if t == null: t = _nearest_in(c.pos, side_proj[1 - c.side], 800.0)
			if t == null: t = _nearest_cls(c.pos, foe_s, 1000.0, Defs.ESCORT, true)
			return t
		&"bomber":
			var t = _nearest_cls(c.pos, foe_s, 2600.0, Defs.ESCORT, false)
			if t == null: t = _nearest_in(c.pos, foe_s, 2600.0)
			return t
		_:
			var t = _nearest_in(c.pos, foe_c, 800.0)
			if t == null: t = _nearest_cls(c.pos, foe_s, 1300.0, Defs.ESCORT, true)
			if t == null: t = _nearest_in(c.pos, foe_s, 1800.0)
			return t

func _nearest_in(p: Vector3, list: Array, max_d: float):
	var best = null
	var bd := max_d * max_d
	for o in list:
		if o.dead: continue
		var dd: float = p.distance_squared_to(o.pos)
		if dd < bd:
			bd = dd; best = o
	return best

func _nearest_cls(p: Vector3, list: Array, max_d: float, cls: int, same: bool) -> Ship:
	var best: Ship = null
	var bd := max_d * max_d
	for o: Ship in list:
		if (o.cls == cls) != same: continue
		var dd := p.distance_squared_to(o.pos)
		if dd < bd:
			bd = dd; best = o
	return best

func _update_craft(c: Craft, dt: float) -> void:
	if c.target != null and c.target.dead: c.target = null
	var home: Ship = c.squad.home
	if c.d.missile:
		if c.reloading > 0.0:
			c.reloading -= dt
			if c.reloading <= 0.0:
				c.ammo = c.d.ammo
			else:
				_fly(c, home.pos if (home != null and not home.dead) else Vector3.ZERO, 0.8, dt)
				return
		elif c.ammo <= 0:
			if c.reloads > 0:
				c.reloads -= 1; c.reloading = c.d.reload_time
			else:
				c.squad.recall = true
	if c.squad.recall and home != null and not home.dead:
		_fly(c, home.pos, 1.0, dt)
		if c.pos.distance_squared_to(home.pos) < 40.0 * 40.0:
			c.dead = true                                   # села
			return
		return
	if c.target == null:
		c.target = _craft_acquire(c)
	if c.target == null:
		var anchor: Vector3 = ai[c.side].patrol if c.d.role == &"interceptor" else (home.pos if home != null and not home.dead else Vector3.ZERO)
		var a := time * 0.35 + c.slot
		_fly(c, anchor + Vector3(sin(a) * 130.0, 0.0, cos(a) * 130.0), 0.7, dt)
		return
	var t = c.target
	var to: Vector3 = t.pos - c.pos
	var dd := to.length()
	if c.d.role == &"bomber":
		if c.phase == 1:
			if time <= c.break_until:
				_fly(c, c.pos + (c.pos - t.pos).normalized() * 400.0, 1.0, dt)
				return
			c.phase = 0
		_fly(c, t.pos, 1.0, dt)
		c.cd -= dt
		if dd < c.d.rng and c.cd <= 0.0 and c.ammo > 0:
			c.cd = c.d.cd
			_craft_missile(c, t)
			c.phase = 1; c.break_until = time + rng.randf_range(3.0, 4.2)
		elif dd < (t.d.radius if t is Ship else 10.0) + 30.0:
			c.phase = 1; c.break_until = time + 3.0
		return
	var desired: float = minf(c.d.rng * 0.8, (t.d.radius if t is Ship else 8.0) + 34.0) if t is Ship else c.d.rng * 0.6
	var aim: Vector3
	if dd < desired * 0.75:
		aim = c.pos + (c.pos - t.pos).normalized() * 260.0 + Vector3(sin(time + c.slot * 2.0) * 60.0, 0, 0)
	else:
		aim = t.pos + Vector3(sin(1.3 * time + 1.7 * c.slot) * 20.0, 0, cos(1.1 * time + 2.3 * c.slot) * 16.0)
	_fly(c, aim, 1.0, dt)
	c.cd -= dt
	if dd <= c.d.rng and c.cd <= 0.0 and c.fwd.dot(to / maxf(dd, 0.01)) > 0.7:
		c.cd = c.d.cd
		if c.d.missile:
			if c.ammo > 0: _craft_missile(c, t)
		else:
			damage(t, c.d.dmg, c.d.key, c, to / maxf(dd, 0.01))

func _craft_missile(c: Craft, t) -> void:
	var p := _spawn_proj(c.side, c, t, c.pos, (t.pos - c.pos).normalized(), c.d.m_speed, c.d.m_hp, c.d.dmg, c.d.key, 1.1 if c.d.key == &"torp" else 1.8)
	if rng.randf() < c.d.miss:
		p.target = null
		p.dir = (p.dir + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.28).normalized()
		p.life = 3.5
	c.ammo -= 1

func _fly(c: Craft, point: Vector3, throttle: float, dt: float) -> void:
	_face(c, point - c.pos, c.d.turn, dt)
	_thrust_to(c, c.fwd * c.d.max_speed * throttle, dt)
	var cap: float = c.d.max_speed * 1.15
	if c.vel.length_squared() > cap * cap:
		c.vel = c.vel.normalized() * cap
	_integrate(c, dt)

# --- снаряды -----------------------------------------------------------------

func _update_proj(p: Proj, dt: float) -> void:
	p.life -= dt
	if p.life <= 0.0:
		p.dead = true
		return
	if p.target != null and p.target.dead: p.target = null
	if p.target != null:
		var to: Vector3 = (p.target.pos - p.pos).normalized()
		p.dir = p.dir.lerp(to, clampf(p.k * dt, 0.0, 1.0)).normalized()
	p.pos += p.dir * p.speed * dt
	if p.target != null:
		var rad: float = (p.target.d.radius if p.target is Ship else 2.6) + 5.0
		if p.pos.distance_squared_to(p.target.pos) < rad * rad:
			damage(p.target, p.dmg, p.key, p.owner, p.dir)
			p.dead = true

# --- уборка и конец ----------------------------------------------------------

func _cleanup() -> void:
	if steps % 30 == 0:
		var w := 0
		for i in projs.size():
			if not projs[i].dead:
				projs[w] = projs[i]; w += 1
		projs.resize(w)
		w = 0
		for i in crafts.size():
			if not crafts[i].dead:
				crafts[w] = crafts[i]; w += 1
		crafts.resize(w)
		for sq in squads:
			if sq.dead: continue
			var alive := false
			for c in sq.craft:
				if not c.dead: alive = true; break
			if not alive:
				sq.dead = true
				if sq.home != null and not sq.home.dead:
					if sq.recall: sq.home.hangar_free += 1                 # севшее — место сразу
					else: sq.home.rebuild.append(time + 26.0)
				for c in sq.craft: c.squad = null; c.target = null     # кольцо звено↔машина
				sq.craft.clear()
		w = 0
		for i in squads.size():
			if not squads[i].dead:
				squads[w] = squads[i]; w += 1
		squads.resize(w)
	for s in ships:
		if s.rebuild.size() > 0 and s.rebuild[0] <= time:
			s.rebuild.remove_at(0)
			s.hangar_free = mini(s.d.hangar, s.hangar_free + 1)

func _check_end() -> void:
	for side in 2:
		var armed := 0
		for s in side_ships[side]:
			if not s.dead and (s.d.main or s.d.light or s.d.sec): armed += 1
		if armed == 0:
			winner = 1 - side
			ended = true
			return
	if time > 900.0:
		ended = true

## Разорвать кольца ссылок (звено↔машина, бой↔ИИ, цели): RefCounted их сам не соберёт,
## и сотня боёв в одном процессе копила бы память.
func dispose() -> void:
	for s in ships:
		s.main_t = null; s.sec_t = null; s.light_t = null; s.futile_from = null
	for c in crafts:
		c.target = null; c.squad = null
	for sq in squads:
		sq.craft.clear(); sq.home = null
	for p in projs:
		p.target = null; p.owner = null
	for a in ai:
		a.battle = null
	ai.clear(); ships.clear(); crafts.clear(); squads.clear(); projs.clear(); sp_ref.clear()
	side_ships = [[], []]; side_craft = [[], []]; side_proj = [[], []]; ecm_fields = [[], []]
	events.clear()

## Отпечаток состояния — для проверки детерминизма.
func state_hash() -> int:
	var acc := PackedFloat64Array()
	for s in ships:
		acc.append(s.pos.x); acc.append(s.pos.z); acc.append(s.hp)
	acc.append(time); acc.append(crafts.size()); acc.append(projs.size())
	return hash(acc.to_byte_array())
