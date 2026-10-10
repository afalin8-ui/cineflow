## Прототип ядра боя (arch-B): данные, без узлов сцены.
## Нагрузка «как в бою»: поиск целей, расталкивание, пояса тяжёлых,
## батарея, лёгкие, ПВО по ракетам и машинам, авиация, ракеты, купол РЭБ.
## Не баланс — замер стоимости шага.
class_name BattleSim
extends RefCounted

const DT := 1.0 / 30.0
enum { CAPITAL, ESCORT, CARRIER, ECM, STRIKE, TORPEDO }
enum { K_HEAVY, K_MISSILE, K_LIGHT, K_PD, K_INT, K_FIG, K_TORP, K_SEC }
const KEY_NAMES := ["heavy", "missile", "light", "pd", "gunInt", "gunFig", "torp", "sec"]
const CLS_NAMES := ["capital", "escort", "carrier", "escort", "strike", "torpedo"]

signal damaged(target, amount: float, key: int, side: int)
signal destroyed(target, by_side: int)

class Gun:
	var key: int
	var dmg: float
	var cd: float
	var rng: float
	var dead: float
	var t: float

class Ship:
	var id: int
	var side: int
	var cls: int
	var kind: String
	var pos: Vector3
	var vel: Vector3
	var yaw: float
	var hp: float
	var max_hp: float
	var armor: float
	var max_speed: float
	var thrust: float
	var turn: float
	var hull: float
	var mains: Array[Gun] = []
	var light: Gun
	var sec: Gun
	var sec_t: PackedFloat32Array
	var pd_dmg: float
	var pd_cd: float
	var pd_range: float
	var pd_t: PackedFloat32Array
	var retarget: float
	var target: Ship
	var near: Ship
	var near_d: float
	var home: Vector3
	var state: int
	var ecm_r: float
	var jam: bool
	var alive := true
	var hangars: int

class Craft:
	var side: int
	var role: int   # 0 int, 1 fig, 2 bomb
	var pos: Vector3
	var vel: Vector3
	var yaw: float
	var hp: float
	var armor: float
	var max_speed: float
	var thrust: float
	var turn: float
	var key: int
	var dmg: float
	var cd: float
	var rng: float
	var t: float
	var ammo: int
	var ammo_max: int
	var reload: float
	var mspeed: float
	var mhp: float
	var retarget: float
	var t_ship: Ship
	var t_craft: Craft
	var home: Ship
	var alive := true

class Proj:
	var side: int
	var pos: Vector3
	var speed: float
	var t_ship: Ship
	var t_craft: Craft
	var dmg: float
	var key: int
	var life: float
	var hp: float
	var alive := true

var rng := RandomNumberGenerator.new()
var data: Dictionary
var dmg_tab: Array = []   # [key][cls] -> float
var ships: Array[Ship] = []
var craft: Array[Craft] = []
var proj: Array[Proj] = []
var t := 0.0
var steps := 0
var invulnerable := false
var ai_t := [0.0, 0.0]
# замеры доктрины (тяжёлый-секунды и т.п.)
var m_heavy_s := 0.0
var m_band_s := 0.0
var m_close_s := 0.0
var m_line_sum := 0.0
var m_line_n := 0
var dmg_by_key := PackedFloat64Array()
var first_hit := -1.0
var events: Array = []      # журнал для стенда: [время, вид, ...]
var fast := false
var phys_pd: Callable      # вариант «физика»: поиск целей ПВО запросом к миру
var ecm_external := false
var fx_on := false
var fx_shots: Array = []   # [откуда, куда, ключ] — картинка забирает и чистит
# быстрый путь: пары кораблей один раз за шаг, сетка для ПВО
var _push := PackedVector3Array()
var _near_i := PackedInt32Array()
var _near_d2 := PackedFloat32Array()
const CELL := 200.0
const GN := 28   # 28*200 = 5600 > 2*2600
var _grid: Array = []      # ячейка -> Array (проекты и машины)
var _grid_used := PackedInt32Array()

func _init(d: Dictionary, seed_: int) -> void:
	data = d
	rng.seed = seed_
	dmg_by_key.resize(8)
	var tab: Dictionary = d.space_dmg
	for k in KEY_NAMES:
		var row: Array = []
		for c in CLS_NAMES:
			var v := 0.0
			if k == "sec":
				v = {"capital":0.3, "carrier":0.45, "escort":1.0}.get(c, 0.0)
			elif tab.has(k):
				v = float(tab[k].get(c, 0.0))
			row.append(v)
		dmg_tab.append(row)

func ship_def(faction: String, id: String) -> Dictionary:
	for s in data.ships[faction]:
		if s.id == id:
			return s
	return {}

func add_fleet(side: int, faction: String, comp: Dictionary, craft_squads: int) -> void:
	var z0 := 650.0 if side == 0 else -650.0
	var n := 0
	var carriers: Array[Ship] = []
	for id in comp:
		var def := ship_def(faction, id)
		for i in int(comp[id]):
			var s := Ship.new()
			s.id = ships.size()
			s.side = side
			s.kind = id
			s.cls = {"capital": CAPITAL, "escort": ESCORT, "carrier": CARRIER}[def.cls]
			if id == "ecm":
				s.cls = ECM
				s.ecm_r = 420.0
			s.hp = float(def.hp) * 1.8
			s.max_hp = s.hp
			s.armor = float(def.armor)
			s.max_speed = float(def.maxSpeed)
			s.thrust = float(def.thrust)
			s.turn = float(def.turn)
			s.hull = float(data.model_len.hull.get(id, 20.0))
			for g in def.guns:
				var gun := Gun.new()
				gun.dmg = float(g.dmg)
				gun.cd = float(g.cd)
				gun.rng = float(g.range)
				gun.t = rng.randf() * gun.cd
				if g.type == "heavy":
					gun.key = K_HEAVY
					gun.dead = 0.4 * gun.rng
					s.mains.append(gun)
				elif g.type == "light":
					gun.key = K_LIGHT
					s.light = gun
			if s.cls == CAPITAL:
				var sec := Gun.new()
				sec.key = K_SEC
				sec.dmg = 24.0
				sec.cd = 2.5
				sec.rng = 0.45 * s.mains[0].rng
				s.sec = sec
				var nsec := 4 if id == "capital" else 2
				s.sec_t.resize(nsec)
				for k in nsec:
					s.sec_t[k] = rng.randf() * sec.cd
			s.pd_dmg = float(def.pd.dmg)
			s.pd_cd = float(def.pd.cd)
			s.pd_range = float(def.pd.range)
			s.pd_t.resize(int(def.pd.count))
			for k in s.pd_t.size():
				s.pd_t[k] = rng.randf() * s.pd_cd
			s.pos = Vector3((n % 10 - 4.5) * 90.0 + rng.randf_range(-20, 20), 0.0, z0 + (n / 10) * 60.0 * (1 if side == 0 else -1))
			s.yaw = 0.0 if side == 0 else PI
			s.retarget = rng.randf() * 1.6
			s.home = s.pos
			s.hangars = int(def.hangar) if def.hangar != null else 0
			if s.cls == CARRIER:
				carriers.append(s)
			ships.append(s)
			n += 1
	# авиация: звенья по 6
	var roles := ["interceptor", "fighter", "bomber"]
	var keys := [K_INT, K_FIG, K_TORP]
	for q in craft_squads:
		var r := q % 3
		var cdef: Dictionary = data.strike[faction][roles[r]]
		var home: Ship = carriers[q % carriers.size()] if carriers.size() > 0 else ships[ships.size() - 1]
		for k in 6:
			var c := Craft.new()
			c.side = side
			c.role = r
			c.pos = home.pos + Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-40, 40))
			c.hp = float(cdef.hp)
			c.armor = float(cdef.armor)
			c.max_speed = float(cdef.maxSpeed)
			c.thrust = float(cdef.thrust)
			c.turn = float(cdef.turn)
			c.key = keys[r]
			c.dmg = float(cdef.dmg)
			c.cd = float(cdef.cd)
			c.rng = float(cdef.range)
			c.ammo_max = int(cdef.get("ammo", 0))
			c.ammo = c.ammo_max
			c.mspeed = float(cdef.get("missileSpeed", 120))
			c.mhp = float(cdef.get("missileHp", 24))
			c.t = rng.randf() * c.cd
			c.home = home
			c.yaw = home.yaw
			craft.append(c)

# ---------------- шаг ----------------
var prof := false
var prof_us := PackedFloat64Array([0, 0, 0, 0, 0, 0])
func step() -> void:
	t += DT
	steps += 1
	var a := Time.get_ticks_usec() if prof else 0
	_update_ecm()
	for side in 2:
		ai_t[side] -= DT
		if ai_t[side] <= 0.0:
			ai_t[side] = 0.5
			_ai(side)
	if fast:
		_pairs()
		_build_grid()
	var b := Time.get_ticks_usec() if prof else 0
	for s in ships:
		if s.alive:
			_ship_step(s)
	var c_ := Time.get_ticks_usec() if prof else 0
	for c in craft:
		if c.alive:
			_craft_step(c)
	var d_ := Time.get_ticks_usec() if prof else 0
	for p in proj:
		if p.alive:
			_proj_step(p)
	var e_ := Time.get_ticks_usec() if prof else 0
	if steps % 30 == 0:
		_compact()
	_measure()
	if prof:
		var f_ := Time.get_ticks_usec()
		prof_us[0] += b - a; prof_us[1] += c_ - b; prof_us[2] += d_ - c_; prof_us[3] += e_ - d_; prof_us[4] += f_ - e_

func _update_ecm() -> void:
	for s in ships:
		s.jam = false
	for e in ships:
		if not e.alive or e.cls != ECM:
			continue
		var r2 := e.ecm_r * e.ecm_r
		for s in ships:
			if s.alive and s.side != e.side and s.pos.distance_squared_to(e.pos) < r2:
				s.jam = true

func _ai(side: int) -> void:
	# строй от тяжёлых: P — центр линии, ось — к противнику
	var P := Vector3.ZERO
	var n := 0
	var E := Vector3.ZERO
	var m := 0
	for s in ships:
		if not s.alive:
			continue
		if s.cls == CAPITAL:
			if s.side == side:
				P += s.pos; n += 1
			else:
				E += s.pos; m += 1
	if n == 0 or m == 0:
		return
	P /= n
	E /= m
	var axis := (E - P)
	axis.y = 0.0
	var L := axis.length()
	axis = axis / maxf(L, 1.0)
	var side_v := Vector3(-axis.z, 0, axis.x)
	var Lw := 663.0
	var idx := [0, 0, 0, 0]
	for s in ships:
		if not s.alive or s.side != side:
			continue
		var row := 0.0
		var spread := 100.0
		match s.kind:
			"corvette": row = 0.35 * Lw; spread = 70.0
			"frigate": row = 0.2 * Lw; spread = 80.0
			"ecm": row = 0.2 * Lw; spread = 80.0
			"carrier": row = -440.0; spread = 120.0
			_: row = 0.0; spread = 150.0
		var k: int = idx[s.cls]
		idx[s.cls] = k + 1
		var off := (float(k) - 3.0) * spread
		s.home = P + axis * row + side_v * off

func _ship_step(s: Ship) -> void:
	# один проход по кораблям: ближайший чужой и расталкивание
	var near: Ship = null
	var nd2 := INF
	var push := Vector3.ZERO
	if fast:
		var ni := _near_i[s.id]
		if ni >= 0:
			near = ships[ni]
			nd2 = _near_d2[s.id]
		push = _push[s.id]
	for o in (ships if not fast else []):
		if o == s or not o.alive:
			continue
		var d := o.pos - s.pos
		var d2 := d.x * d.x + d.z * d.z
		if o.side != s.side and d2 < nd2:
			nd2 = d2
			near = o
		var rr := (s.hull + o.hull) * 1.15
		if d2 < rr * rr and d2 > 0.0001:
			var dl := sqrt(d2)
			push -= d / dl * ((rr - dl) / rr)
	s.near = near
	s.near_d = sqrt(nd2) if near else INF
	s.retarget -= DT
	if s.retarget <= 0.0 or s.target == null or not s.target.alive:
		s.retarget = rng.randf_range(0.8, 1.6)
		s.target = _acquire(s)
	var want := Vector3.ZERO
	var look := Vector3.ZERO
	if s.cls == CAPITAL and s.mains.size() > 0:
		var R := s.mains[0].rng
		var D := 0.4 * R
		if near and s.near_d < D:
			s.state = 2
			var away := (s.pos - near.pos)
			away.y = 0.0
			want = away.normalized() * s.max_speed * 0.6
			look = (s.target.pos - s.pos) if s.target else -away
		elif s.target:
			var to := s.target.pos - s.pos
			var d := to.length()
			look = to
			if d > 0.92 * R:
				s.state = 0
				want = to / d * minf(s.max_speed, sqrt(2.0 * s.thrust * maxf(d - 0.8 * R, 0.0)))
			else:
				s.state = 1
		else:
			want = _go(s, s.home)
	elif s.light:
		if s.target:
			var to := s.target.pos - s.pos
			var d := to.length()
			look = to
			var want_d := 0.68 * s.light.rng
			if d > want_d * 1.08:
				want = to / d * minf(s.max_speed, sqrt(2.0 * s.thrust * (d - want_d)))
			elif d < want_d * 0.55:
				want = -to / d * s.max_speed * 0.5
			else:
				want = Vector3(-to.z, 0, to.x) / d * s.max_speed * 0.3
		else:
			want = _go(s, s.home)
	else:
		want = _go(s, s.home)
	want += push * s.max_speed * 0.8
	if look == Vector3.ZERO:
		look = want
	_face(s, look)
	_thrust(s, want)
	_fire(s)

func _pairs() -> void:
	var n := ships.size()
	if _push.size() != n:
		_push.resize(n); _near_i.resize(n); _near_d2.resize(n)
	var px := PackedFloat32Array(); px.resize(n)
	var pz := PackedFloat32Array(); pz.resize(n)
	var hl := PackedFloat32Array(); hl.resize(n)
	var sd := PackedInt32Array(); sd.resize(n)
	for i in n:
		var a := ships[i]
		px[i] = a.pos.x; pz[i] = a.pos.z; hl[i] = a.hull
		sd[i] = a.side if a.alive else -1
		_push[i] = Vector3.ZERO; _near_i[i] = -1; _near_d2[i] = INF
	for i in n:
		if sd[i] < 0:
			continue
		var xi := px[i]
		var zi := pz[i]
		var hi := hl[i]
		var si := sd[i]
		for j in range(i + 1, n):
			var sj := sd[j]
			if sj < 0:
				continue
			var dx := px[j] - xi
			var dz := pz[j] - zi
			var d2 := dx * dx + dz * dz
			if sj != si:
				if d2 < _near_d2[i]:
					_near_d2[i] = d2; _near_i[i] = j
				if d2 < _near_d2[j]:
					_near_d2[j] = d2; _near_i[j] = i
			var rr := (hi + hl[j]) * 1.15
			if d2 < rr * rr and d2 > 0.0001:
				var dl := sqrt(d2)
				var k := (rr - dl) / rr / dl
				var pv := Vector3(dx * k, 0, dz * k)
				_push[i] -= pv
				_push[j] += pv

func _build_grid() -> void:
	if _grid.is_empty():
		_grid.resize(GN * GN)
		for i in GN * GN:
			_grid[i] = []
	for i in _grid_used:
		_grid[i].clear()
	_grid_used.clear()
	for p in proj:
		if p.alive:
			_grid_put(p, p.pos)
	for c in craft:
		if c.alive:
			_grid_put(c, c.pos)

func _grid_put(o: Object, pos: Vector3) -> void:
	var gx := clampi(int((pos.x + 2800.0) / CELL), 0, GN - 1)
	var gz := clampi(int((pos.z + 2800.0) / CELL), 0, GN - 1)
	var i := gx * GN + gz
	if _grid[i].is_empty():
		_grid_used.append(i)
	_grid[i].append(o)

func _go(s: Ship, p: Vector3) -> Vector3:
	var to := p - s.pos
	to.y = 0.0
	var d := to.length()
	if d < 5.0:
		return Vector3.ZERO
	return to / d * minf(s.max_speed, sqrt(2.0 * s.thrust * d))

func _face(s: Ship, dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var ty := atan2(-dir.x, -dir.z)
	s.yaw = lerp_angle(s.yaw, ty, clampf(s.turn * DT, 0.0, 1.0))

func _thrust(s: Ship, want: Vector3) -> void:
	var dv := want - s.vel
	var a := s.thrust * DT
	if dv.length_squared() > a * a:
		dv = dv.normalized() * a
	s.vel += dv
	if s.vel.length_squared() > s.max_speed * s.max_speed:
		s.vel = s.vel.normalized() * s.max_speed
	s.pos += s.vel * DT

func _acquire(s: Ship) -> Ship:
	var best: Ship = null
	var bs := -INF
	var reach := 1.3
	var R := 0.0
	var D := 0.0
	var key := K_LIGHT
	if s.mains.size() > 0:
		R = s.mains[0].rng
		D = s.mains[0].dead
		key = K_HEAVY
	elif s.light:
		R = s.light.rng
	else:
		return null
	var row: Array = dmg_tab[key]
	for o in ships:
		if not o.alive or o.side == s.side:
			continue
		var m: float = row[o.cls]
		if m <= 0.0:
			continue
		var d := s.pos.distance_to(o.pos)
		if d < D or d > R * reach * 3.0:
			continue
		var w := 0.6 if (key == K_HEAVY and o.cls == ESCORT) else 1.0
		var sc := w * m * 1000.0 - d + (1.0 - o.hp / o.max_hp) * 400.0 + (250.0 if o.cls == CARRIER else 0.0)
		if sc > bs:
			bs = sc
			best = o
	return best

func _fire(s: Ship) -> void:
	var fwd := Vector3(-sin(s.yaw), 0, -cos(s.yaw))
	for g in s.mains:
		g.t -= DT * (0.5 if s.jam else 1.0)
		var tg := s.target
		if tg == null or not tg.alive or g.t > 0.0:
			continue
		var to := tg.pos - s.pos
		var d := to.length()
		if d > g.rng or d < g.dead:
			continue
		if fwd.dot(to / d) < 0.25:
			continue
		g.t = g.cd
		if fx_on:
			fx_shots.append([s.pos, tg.pos, K_HEAVY])
		_hit_ship(tg, g.dmg, K_HEAVY, s.side)
	if s.light:
		var g := s.light
		g.t -= DT
		var tg := s.target
		if tg and tg.alive and g.t <= 0.0:
			var d := s.pos.distance_to(tg.pos)
			if d <= g.rng and (not s.jam or d < 170.0):
				g.t = g.cd
				_hit_ship(tg, g.dmg, K_LIGHT, s.side)
	if s.sec:
		var g := s.sec
		var tg := s.near
		var ok := tg != null and s.near_d <= g.rng and (not s.jam or s.near_d < 170.0)
		for k in s.sec_t.size():
			s.sec_t[k] -= DT
			if ok and s.sec_t[k] <= 0.0:
				s.sec_t[k] = g.cd
				if fx_on:
					fx_shots.append([s.pos, tg.pos, K_SEC])
				_hit_ship(tg, g.dmg, K_SEC, s.side)
	# ПВО: общий поиск цели, если готов хоть один ствол
	var ready := false
	for k in s.pd_t.size():
		s.pd_t[k] -= DT
		if s.pd_t[k] <= 0.0:
			ready = true
	if not ready:
		return
	var r2 := s.pd_range * s.pd_range
	var bp: Proj = null
	var bd := r2
	var bc: Craft = null
	if phys_pd.is_valid():
		var r: Array = phys_pd.call(s)
		bp = r[0]; bc = r[1]
	elif fast:
		var cx := int((s.pos.x + 2800.0) / CELL)
		var cz := int((s.pos.z + 2800.0) / CELL)
		var bdc := r2
		for gx in range(maxi(cx - 1, 0), mini(cx + 2, GN)):
			for gz in range(maxi(cz - 1, 0), mini(cz + 2, GN)):
				for o in _grid[gx * GN + gz]:
					if o is Proj:
						if o.alive and o.side != s.side:
							var d2: float = s.pos.distance_squared_to(o.pos)
							if d2 < bd:
								bd = d2; bp = o
					elif o.alive and o.side != s.side:
						var d2: float = s.pos.distance_squared_to(o.pos)
						if d2 < bdc:
							bdc = d2; bc = o
		if bp:
			bc = null
	for p in (proj if not (fast or phys_pd.is_valid()) else []):
		if p.alive and p.side != s.side:
			var d2 := s.pos.distance_squared_to(p.pos)
			if d2 < bd:
				bd = d2; bp = p
	if bp == null and not fast and not phys_pd.is_valid():
		bd = r2
		for c in craft:
			if c.alive and c.side != s.side:
				var d2 := s.pos.distance_squared_to(c.pos)
				if d2 < bd:
					bd = d2; bc = c
	if bp == null and bc == null:
		return
	var pen := 0.55 if s.jam else 1.0
	for k in s.pd_t.size():
		if s.pd_t[k] <= 0.0:
			s.pd_t[k] = s.pd_cd * rng.randf_range(0.85, 1.15)
			if bp and bp.alive:
				bp.hp -= s.pd_dmg * pen * 1.4
				if bp.hp <= 0.0:
					bp.alive = false
			elif bc and bc.alive:
				_hit_craft(bc, s.pd_dmg * pen, K_PD, s.side)

func _hit_ship(tg: Ship, amount: float, key: int, side: int) -> void:
	var m: float = dmg_tab[key][tg.cls]
	var dealt := amount * m * (1.0 - tg.armor)
	if dealt <= 0.0:
		return
	if first_hit < 0.0:
		first_hit = t
		events.append([t, "first_hit"])
	dmg_by_key[key] += dealt
	damaged.emit(tg, dealt, key, side)
	if invulnerable:
		return
	tg.hp -= dealt
	if tg.hp <= 0.0 and tg.alive:
		tg.alive = false
		events.append([t, "destroyed", tg.id, side])
		destroyed.emit(tg, side)

func _hit_craft(c: Craft, amount: float, key: int, side: int) -> void:
	var m: float = dmg_tab[key][STRIKE]
	var dealt := amount * m * (1.0 - c.armor)
	if dealt <= 0.0 or invulnerable:
		return
	c.hp -= dealt
	if c.hp <= 0.0:
		c.alive = false

# ---------------- авиация ----------------
func _craft_step(c: Craft) -> void:
	c.retarget -= DT
	if c.retarget <= 0.0 or (c.t_ship and not c.t_ship.alive) or (c.t_craft and not c.t_craft.alive):
		c.retarget = rng.randf_range(0.6, 1.2)
		_craft_pick(c)
	var tp := c.home.pos
	if c.t_craft:
		tp = c.t_craft.pos + c.t_craft.vel * 0.5
	elif c.t_ship:
		tp = c.t_ship.pos
	var to := tp - c.pos
	var d := to.length()
	# полёт: нос к цели, тяга по носу (как flyToward)
	if d > 0.001:
		var ty := atan2(-to.x, -to.z)
		c.yaw = lerp_angle(c.yaw, ty, clampf(c.turn * DT, 0.0, 1.0))
	var fwd := Vector3(-sin(c.yaw), 0, -cos(c.yaw))
	var want := fwd * c.max_speed
	if d < c.rng * 0.6 and c.t_ship:
		want = fwd * c.max_speed * 0.5
	var dv := want - c.vel
	var a := c.thrust * DT
	if dv.length_squared() > a * a:
		dv = dv.normalized() * a
	c.vel += dv
	c.pos += c.vel * DT
	c.t -= DT
	if c.reload > 0.0:
		c.reload -= DT
		if c.reload <= 0.0:
			c.ammo = c.ammo_max
		return
	if c.t <= 0.0 and d <= c.rng and (c.t_ship or c.t_craft):
		c.t = c.cd
		if c.role == 0:
			if c.t_craft:
				_hit_craft(c.t_craft, c.dmg, K_INT, c.side)
			else:
				_hit_ship(c.t_ship, c.dmg, K_INT, c.side)
		else:
			var p := Proj.new()
			p.side = c.side
			p.pos = c.pos
			p.speed = c.mspeed
			p.t_ship = c.t_ship
			p.t_craft = c.t_craft
			p.dmg = c.dmg
			p.key = c.key
			p.life = 16.0
			p.hp = c.mhp
			proj.append(p)
			c.ammo -= 1
			if c.ammo <= 0:
				c.reload = 7.0

func _craft_pick(c: Craft) -> void:
	c.t_ship = null
	c.t_craft = null
	var bd := INF
	if c.role != 2:
		for o in craft:
			if o.alive and o.side != c.side:
				var d2 := c.pos.distance_squared_to(o.pos)
				if d2 < bd:
					bd = d2; c.t_craft = o
		if c.t_craft and bd < 700.0 * 700.0:
			return
		c.t_craft = null
	bd = INF
	for s in ships:
		if s.alive and s.side != c.side and (c.role != 2 or s.cls != ESCORT):
			var d2 := c.pos.distance_squared_to(s.pos)
			if d2 < bd:
				bd = d2; c.t_ship = s

# ---------------- ракеты ----------------
func _proj_step(p: Proj) -> void:
	p.life -= DT
	if p.life <= 0.0:
		p.alive = false
		return
	var tp: Vector3
	var r := 4.0
	if p.t_craft:
		if not p.t_craft.alive:
			p.alive = false
			return
		tp = p.t_craft.pos
	elif p.t_ship:
		if not p.t_ship.alive:
			p.alive = false
			return
		tp = p.t_ship.pos
		r = p.t_ship.hull * 0.5
	else:
		p.alive = false
		return
	var to := tp - p.pos
	var d := to.length()
	if d <= r + p.speed * DT:
		p.alive = false
		if p.t_craft:
			_hit_craft(p.t_craft, p.dmg, p.key, p.side)
		else:
			_hit_ship(p.t_ship, p.dmg, p.key, p.side)
		return
	p.pos += to / d * p.speed * DT

func _compact() -> void:
	proj = proj.filter(func(p): return p.alive)
	if invulnerable:
		return
	craft = craft.filter(func(c): return c.alive)

func _measure() -> void:
	var cen := [Vector3.ZERO, Vector3.ZERO]
	var cnt := [0, 0]
	for s in ships:
		if not s.alive or s.cls != CAPITAL:
			continue
		m_heavy_s += DT
		if s.state == 1:
			m_band_s += DT
		if s.state == 2:
			m_close_s += DT
		cen[s.side] += s.pos
		cnt[s.side] += 1
	if cnt[0] > 0 and cnt[1] > 0:
		m_line_sum += (cen[0] / cnt[0]).distance_to(cen[1] / cnt[1])
		m_line_n += 1

func alive_count(side: int) -> int:
	var n := 0
	for s in ships:
		if s.alive and s.side == side:
			n += 1
	return n

func state_hash() -> int:
	var h := 17
	for s in ships:
		h = hash([h, snappedf(s.pos.x, 0.001), snappedf(s.pos.z, 0.001), snappedf(s.hp, 0.001), s.alive])
	return h

## Разорвать циклы ссылок (корабль → цель → корабль): RefCounted их сам не соберёт
func dispose() -> void:
	for s in ships:
		s.target = null
		s.near = null
	for c in craft:
		c.t_ship = null
		c.t_craft = null
		c.home = null
	for p in proj:
		p.t_ship = null
		p.t_craft = null
	ships.clear()
	craft.clear()
	proj.clear()
