class_name World
extends RefCounted
## Вся логика боя без графики. Шаг — 0,1 с. Экран только читает это состояние
## и отдаёт приказы через cmd_*; ИИ отдаёт приказы теми же cmd_*.

const DT := 0.1

var rng := RandomNumberGenerator.new()
var time := 0.0
var tick := 0
var winner := -1
var map_w := 60000.0
var map_size := "S"

var units: Array = []
var by_id := {}
var next_id := 1
var teams: Array = []        # [{fac, ore, station, rally, ai, vis, mined, color}]
var fields: Array = []       # [{pos, r, ore}]
var nebulas: Array = []      # [{pos, r}]
var planet := {"pos": Vector2.ZERO, "r": 4000.0}
var flashes: Array = []     # для экрана: вспышки попаданий и гибели [{pos, h, t, r}]
var projectiles: Array = []  # [{pos, tgt, dmg, cls, team, hp, life, spd, spoofed, dir}]
var shots: Array = []        # для экрана: [{a, b, cls, t, team}]
var reveals: Array = []      # [{team, pos, r, t}]
var events: Array = []       # [{team, text, t}] подсказки игроку
var ais: Array = [null, null]

var stats := {
	"big_far": 0.0, "big_close": 0.0,      # секунд: крупный корабль в бою дальше / ближе 3 км от крупного врага
	"sq_vs_sq": 0, "sq_kills_sq": 0,       # перехваты: попадания и сбитые звенья звеньями
	"bomber_kills": 0, "kills": [0, 0], "lost": [0, 0], "built": [0, 0],
	"retreats": [0, 0], "first_contact": -1.0, "dmg": [0.0, 0.0],
}

func setup(cfg: Dictionary) -> void:
	# cfg: {facs: [f0, f1], size: "S"|"M"|"L", seed, ai: [diff|"" , diff|""]}
	rng.seed = cfg.get("seed", 1)
	seed(cfg.get("seed", 1))
	map_size = cfg.get("size", "S")
	map_w = {"S": 60000.0, "M": 90000.0, "L": 120000.0}[map_size]
	_make_map()
	for t in 2:
		var fac: String = cfg.facs[t]
		var side := -1.0 if t == 0 else 1.0
		var tm := {"fac": fac, "ore": float(Defs.START_ORE), "station": null,
			"rally": Vector2(side * map_w * 0.28, 0), "vis": {}, "mined": 0.0, "spent": 0.0}
		teams.append(tm)
		var st := spawn(Defs.station_of(fac), t, Vector2(side * map_w * 0.36, 0))
		st.heading = 0.0 if t == 0 else PI
		tm.station = st
		for i in 2:
			var hv := spawn(Defs.harvester_of(fac), t, st.pos + Vector2(-side * 1500, (i - 0.5) * 2500))
			hv.order = "harvest"
		# Стартовый флот: немного корветов, чтобы с первой минуты было чем воевать.
		var start := ["warden", "tracer"] if fac == "troyden" else ["ogr", "ogr"]
		for i in start.size():
			var u := spawn(start[i], t, st.pos + Vector2(-side * 2500, (i - 0.5) * 2000))
			u.heading = st.heading
	for t in 2:
		var diff: String = cfg.ai[t] if cfg.has("ai") else ""
		if diff != "":
			ais[t] = AIPlayer.new(self, t, diff)
	_update_vis()

func _make_map() -> void:
	var W := map_w
	var fp := [Vector2(-0.25 * W, 0.14 * W), Vector2(0.25 * W, -0.14 * W),
		Vector2(0, 0.27 * W), Vector2(0, -0.27 * W)]
	if map_size == "M" or map_size == "L":
		fp.append(Vector2(0, 0))
	if map_size == "L":
		fp[4] = Vector2(-0.12 * W, -0.06 * W)
		fp.append(Vector2(0.12 * W, 0.06 * W))
	for p in fp:
		fields.append({"pos": p, "r": 3200.0, "ore": float(Defs.FIELD_ORE)})
	# Туманность не на прямой между станциями: иначе флоты вязнут в ней посередине.
	nebulas.append({"pos": Vector2(0, 0.17 * W), "r": 0.09 * W})
	if map_size != "S":
		nebulas.append({"pos": Vector2(-0.2 * W, -0.25 * W), "r": 0.06 * W})
		nebulas.append({"pos": Vector2(0.2 * W, -0.25 * W), "r": 0.06 * W})
	planet = {"pos": Vector2(0, 0), "r": 0.06 * W}

# ---------------------------------------------------------------- юниты

func spawn(type_id: String, team: int, p: Vector2) -> Unit:
	var u := Unit.new()
	u.id = next_id
	next_id += 1
	u.setup(Defs.ship(type_id), team, p)
	u.height = rng.randf_range(-150, 150) if not u.is_station() else 0.0
	u.heading = 0.0 if team == 0 else PI
	u.built_at = time
	units.append(u)
	by_id[u.id] = u
	if u.def.bays > 0:
		for i in u.def.start_sq:
			_launch_squad(u, u.def.sq_types[i % u.def.sq_types.size()])
	return u

func _launch_squad(carrier: Unit, type_id: String) -> Unit:
	var off := Vector2.from_angle(rng.randf() * TAU) * (carrier.radius() + 300)
	var s := Unit.new()
	s.id = next_id
	next_id += 1
	s.setup(Defs.ship(type_id), carrier.team, carrier.pos + off)
	s.home = carrier
	s.height = rng.randf_range(-100, 100)
	s.heading = carrier.heading
	s.built_at = time
	units.append(s)
	by_id[s.id] = s
	carrier.squads.append(s)
	return s

func active_bays(c: Unit) -> int:
	return min(c.def.bays, c.def.start_sq + c.bays_bought)

func fleet_points(team: int) -> int:
	var p := 0
	for u in units:
		# Звенья в лимит флота не входят: их число держит вместимость ангаров.
		if u.alive and u.team == team and not u.is_station() and not u.is_squad():
			p += u.points()
		if u.alive and u.team == team:
			for q in u.build_queue:
				p += Defs.ship(q.id).pts
	return p

func fleet_cap(team: int) -> int:
	var st: Unit = teams[team].station
	return Defs.FLEET_CAP[st.level] if st and st.alive else 0

func count_type(team: int, pred: Callable) -> int:
	var n := 0
	for u in units:
		if u.alive and u.team == team and pred.call(u.def):
			n += 1
	var st: Unit = teams[team].station
	if st and st.alive:
		for q in st.build_queue:
			if pred.call(Defs.ship(q.id)):
				n += 1
	return n

# ------------------------------------------------------------- приказы

## Почему нельзя построить, или "" — можно.
func build_block(team: int, type_id: String) -> String:
	var st: Unit = teams[team].station
	if not st or not st.alive:
		return "нет станции"
	var d := Defs.ship(type_id)
	if d.fac != teams[team].fac:
		return "чужая фракция"
	if st.level < d.lvl:
		return "нужна станция ур. %d" % d.lvl
	if d.cls == "capital" and count_type(team, func(x): return x.cls == "capital") >= Defs.LIMIT_CAPITAL:
		return "флагман уже есть"
	if (d.cls == "cruiser" or d.cls == "carrier") and count_type(team, func(x): return x.cls == "cruiser" or x.cls == "carrier") >= Defs.LIMIT_BIG:
		return "предел крупных: %d" % Defs.LIMIT_BIG
	if fleet_points(team) + d.pts > fleet_cap(team):
		return "лимит флота"
	if teams[team].ore < d.cost:
		return "мало руды"
	if st.build_queue.size() >= 6:
		return "очередь полна"
	return ""

func cmd_build(team: int, type_id: String) -> bool:
	if build_block(team, type_id) != "":
		return false
	var d := Defs.ship(type_id)
	teams[team].ore -= d.cost
	teams[team].spent += d.cost
	teams[team].station.build_queue.append({"id": type_id, "t": d.build, "max": d.build})
	return true

func cmd_cancel_build(team: int, idx: int) -> void:
	var st: Unit = teams[team].station
	if st and idx < st.build_queue.size():
		teams[team].ore += Defs.ship(st.build_queue[idx].id).cost
		st.build_queue.remove_at(idx)

func upgrade_block(team: int) -> String:
	var st: Unit = teams[team].station
	if not st or not st.alive:
		return "нет станции"
	if st.level >= 4:
		return "наивысший уровень"
	if st.upgrading > 0:
		return "уже улучшается"
	if teams[team].ore < Defs.STATION_UPGRADE[st.level + 1]:
		return "мало руды"
	return ""

func cmd_upgrade(team: int) -> bool:
	if upgrade_block(team) != "":
		return false
	var st: Unit = teams[team].station
	teams[team].ore -= Defs.STATION_UPGRADE[st.level + 1]
	st.upgrading = Defs.STATION_UPGRADE_TIME[st.level + 1]
	return true

func squad_block(c: Unit) -> String:
	if c.def.bays == 0:
		return "нет ангара"
	if active_bays(c) >= c.def.bays:
		return "ангар полон"
	var type_id: String = c.def.sq_types[active_bays(c) % c.def.sq_types.size()]
	var d := Defs.ship(type_id)
	if teams[c.team].ore < d.cost:
		return "мало руды"
	return ""

func cmd_buy_squad(c: Unit) -> bool:
	if squad_block(c) != "":
		return false
	var type_id: String = c.def.sq_types[active_bays(c) % c.def.sq_types.size()]
	teams[c.team].ore -= Defs.ship(type_id).cost
	c.bays_bought += 1
	c.bay_queue.append({"type": type_id, "t": 15.0, "paid": true})
	return true

func cmd_move(list: Array, p: Vector2, attack_move := false) -> void:
	var movers := list.filter(func(u): return u.alive and not u.is_station() and u.charge <= 0 and u.in_hyper <= 0)
	var n := movers.size()
	var cols := int(ceil(sqrt(n)))
	var spacing := 0.0
	for u in movers:
		spacing = max(spacing, u.radius() * 2.2 + 150)
	for i in n:
		var u: Unit = movers[i]
		var off := Vector2((i % cols) - (cols - 1) * 0.5, (i / cols) - (cols - 1) * 0.5) * spacing
		if n == 1:
			off = Vector2.ZERO
		u.order = "amove" if attack_move else "move"
		u.order_pos = _clamp_map(p + off)
		u.target = null
		u.target_hp = ""
		u.siege = false

func cmd_attack(list: Array, tgt: Unit, hp_id := "") -> void:
	for u in list:
		if not u.alive or u.is_station() or u.cls == "harvester" or u.in_hyper > 0:
			continue
		u.order = "attack"
		u.target = tgt
		u.target_hp = hp_id

func cmd_stop(list: Array) -> void:
	for u in list:
		if u.alive and not u.is_station():
			u.order = "harvest" if u.cls == "harvester" else "idle"
			u.order_pos = u.pos
			u.target = null
			u.charge = 0.0

func cmd_retreat(list: Array) -> void:
	for u in list:
		if not u.alive or u.is_station() or u.in_hyper > 0 or u.charge > 0:
			continue
		if u.is_squad():
			u.order = "dock"     # звено возвращается в ангар
			continue
		u.order = "retreat"
		u.charge = Defs.RETREAT_CHARGE
		u.siege = false
		stats.retreats[u.team] += 1

func cmd_ability(u: Unit, a: String) -> String:
	if not u.alive or not u.abil_cd.has(a) or u.abil_cd[a] > 0:
		return "не готово"
	var ad: Dictionary = Defs.ABIL[a]
	match a:
		"torp_salvo", "missile_salvo":
			for wp in u.weapons:
				wp.t = 0.0
				wp.salvo = true
		"scan":
			reveals.append({"team": u.team, "pos": u.pos, "r": 25000.0, "t": ad.dur})
		"shield_ally":
			var best = null
			for o in units:
				if o.alive and o.team == u.team and o != u and not o.is_squad() and o.shield_max > 0 and o.pos.distance_to(u.pos) < 4000:
					if best == null or o.shield / o.shield_max < best.shield / best.shield_max:
						best = o
			if best == null:
				return "нет союзника рядом"
			best.shield = best.shield_max
			best.abil_on["shielded"] = ad.dur
		"siege":
			u.siege = not u.siege
		"main_shot":
			var t = u.target
			if t == null or not t.alive or not visible_to(u.team, t):
				return "нет цели"
			if not u.hp_alive("reactor") or not u.weapon_ok({"hp": "main"}):
				return "главный калибр выбит"
			var d: float = u.pos.distance_to(t.pos)
			if d < 4000 or d > 16000:
				return "цель вне дистанции 4–16 км"
			if abs(angle_difference(u.heading, (t.pos - u.pos).angle())) > deg_to_rad(25):
				return "развернитесь к цели"
			_shot(u, t, "main")
			damage(t, 14000.0 * Defs.EFF.main[t.target_class()], u.target_hp, u)
		"ram":
			if u.target == null or not u.target.alive:
				return "нет цели"
		"emergency_launch":
			if u.bay_queue.is_empty():
				return "все звенья в полёте"
			u.bay_queue[0].t = 0.0
		"launch_all":
			if u.bay_queue.is_empty():
				return "все звенья в полёте"
			for b in u.bay_queue:
				b.t = 0.0
	u.abil_cd[a] = ad.cd
	if ad.dur > 0:
		u.abil_on[a] = ad.dur
	return ""

func _clamp_map(p: Vector2) -> Vector2:
	var h := map_w * 0.5 - 1000
	return Vector2(clamp(p.x, -h, h), clamp(p.y, -h, h))

# ------------------------------------------------------------ видимость

func in_nebula(p: Vector2) -> bool:
	for n in nebulas:
		if p.distance_to(n.pos) < n.r:
			return true
	return false

func in_field(p: Vector2):
	for f in fields:
		if f.ore > 0 and p.distance_to(f.pos) < f.r:
			return f
	return null

func visible_to(team: int, u: Unit) -> bool:
	if u.team == team:
		return true
	return teams[team].vis.has(u.id)

func _update_vis() -> void:
	for t in 2:
		var vis := {}
		var mine := []
		for u in units:
			if u.alive and u.team == t and u.in_hyper <= 0:
				mine.append(u)
		for e in units:
			if not e.alive or e.team == t or e.in_hyper > 0:
				continue
			if e.is_station():
				vis[e.id] = true
				continue
			var neb := in_nebula(e.pos)
			var seen := false
			for r in reveals:
				if r.team == t and e.pos.distance_to(r.pos) < r.r:
					seen = true
					break
			if not seen:
				for m in mine:
					var d: float = m.pos.distance_to(e.pos)
					if neb:
						if d < Defs.NEBULA_SIGHT or (m.def.sees_nebula and d < m.def.sensor * 0.6):
							seen = true
							break
					elif d < m.def.sensor:
						seen = true
						break
			if seen:
				vis[e.id] = true
				if stats.first_contact < 0 and not e.is_station() and e.cls != "harvester":
					stats.first_contact = time
		teams[t].vis = vis

# ---------------------------------------------------------------- шаг

func step() -> void:
	if winner >= 0:
		return
	time += DT
	tick += 1
	for u in units:
		u.prev_pos = u.pos
		u.prev_heading = u.heading
	_economy()
	for u in units:
		if u.alive:
			_timers(u)
	for u in units:
		if u.alive and u.in_hyper <= 0:
			if (u.id + tick) % 3 == 0 or u.is_squad():
				_behave(u)
			_move(u)
	for u in units:
		if u.alive and u.in_hyper <= 0 and u.charge <= 0 and u.abil_on.get("shield_boost", 0.0) <= 0:
			_fire(u)
	_projectiles()
	_hangars()
	_repair()
	if tick % 5 == 0:
		_update_vis()
		_spoof_check()
	_stats_step()
	_cleanup()
	for t in 2:
		if ais[t]:
			ais[t].step(DT)
	_victory()

func _economy() -> void:
	for t in 2:
		var st: Unit = teams[t].station
		if not st or not st.alive:
			continue
		teams[t].ore += Defs.STATION_INCOME[st.level] * DT
		if st.upgrading > 0:
			st.upgrading -= DT
			if st.upgrading <= 0:
				st.upgrading = 0.0
				st.level += 1
				st.hull_max = st.def.hull * (1.0 + 0.15 * (st.level - 1))
				st.hull = min(st.hull_max, st.hull + st.def.hull * 0.15)
				st.bays_bought += 1
				st.bay_queue.append({"type": st.def.sq_types[active_bays(st) % st.def.sq_types.size()], "t": 10.0, "paid": true})
				note(t, "Станция улучшена до уровня %d" % st.level)
		if not st.build_queue.is_empty():
			var q: Dictionary = st.build_queue[0]
			q.t -= DT
			if q.t <= 0:
				st.build_queue.pop_front()
				var side := -1.0 if t == 0 else 1.0
				var p: Vector2 = st.pos + Vector2(-side * 2600, rng.randf_range(-1500, 1500))
				var u := spawn(q.id, t, p)
				stats.built[t] += 1
				if u.cls == "harvester":
					u.order = "harvest"
				else:
					u.order = "move"
					u.order_pos = teams[t].rally + Vector2(rng.randf_range(-1500, 1500), rng.randf_range(-2500, 2500))
				note(t, "Готов: %s" % u.def.name)

func note(team: int, text: String) -> void:
	events.append({"team": team, "text": text, "t": time})
	if events.size() > 40:
		events.pop_front()

func _timers(u: Unit) -> void:
	for a in u.abil_cd:
		if u.abil_cd[a] > 0:
			u.abil_cd[a] -= DT
	for a in u.abil_on.keys():
		u.abil_on[a] -= DT
		if u.abil_on[a] <= 0:
			u.abil_on.erase(a)
	if u.jam > 0:
		u.jam -= DT
	u.linked = u.home != null and u.home.alive and u.jam <= 0
	# Щит
	if u.shield_works() and u.hp_alive("reactor"):
		if u.shield_delay > 0:
			u.shield_delay -= DT
		elif u.shield < u.shield_max and not in_nebula(u.pos):
			var k := 1.0
			if u.abil_on.has("shield_boost"):
				k = 4.0
			if u.abil_on.has("shielded"):
				k = 3.0
			u.shield = min(u.shield_max, u.shield + u.def.regen * k * DT)
	else:
		u.shield = 0.0
	# Гиперпрыжок
	if u.charge > 0:
		u.charge -= DT
		u.vel *= 0.9
		if u.charge <= 0:
			u.charge = 0.0
			u.in_hyper = Defs.HYPER_TIME
			for s in u.squads:
				if s.alive:
					s.in_hyper = Defs.HYPER_TIME
			note(u.team, "%s ушёл в гиперпространство" % u.def.name)
	elif u.in_hyper > 0:
		u.in_hyper -= DT
		if u.in_hyper <= 0:
			var st: Unit = teams[u.team].station
			var home_pos: Vector2 = st.pos if st and st.alive else teams[u.team].rally
			var side := -1.0 if u.team == 0 else 1.0
			if u.is_squad() and u.home and u.home.alive:
				u.pos = u.home.pos + Vector2.from_angle(rng.randf() * TAU) * (u.home.radius() + 300)
			else:
				u.pos = home_pos + Vector2(side * -3000, rng.randf_range(-3000, 3000))
			u.vel = Vector2.ZERO
			u.order = "idle"
			u.order_pos = u.pos
			u.target = null
			u.in_hyper = 0.0
	# Носитель восполняет звенья
	if u.def.bays > 0 and u.hp_alive("hangar"):
		var want := active_bays(u)
		var live := 0
		for s in u.squads:
			if s.alive:
				live += 1
		if live + u.bay_queue.size() < want:
			var ti: String = u.def.sq_types[(live + u.bay_queue.size()) % u.def.sq_types.size()]
			u.bay_queue.append({"type": ti, "t": Defs.SQUAD_REPLACE * (1.3 if u.def.self_build else 1.0), "paid": u.def.self_build})

# ------------------------------------------------------------ поведение

func enemies_of(u: Unit) -> Array:
	var out := []
	for e in units:
		if e.alive and e.team != u.team and e.in_hyper <= 0 and visible_to(u.team, e):
			out.append(e)
	return out

func _max_range(u: Unit) -> float:
	var m := 0.0
	for wp in u.weapons:
		if wp.cls != "flak" or m == 0.0:
			m = max(m, wp.max)
	return m * (1.35 if u.siege else 1.0)

func _min_range(u: Unit) -> float:
	var m := 0.0
	for wp in u.weapons:
		m = max(m, wp.min)
	return m

func _behave(u: Unit) -> void:
	if u.is_station() or u.charge > 0:
		u.want = Vector2.ZERO
		return
	if u.cls == "harvester":
		_behave_harvester(u)
		return
	if u.is_squad():
		_behave_squad(u)
		return
	var want := Vector2.ZERO
	var face = null   # куда смотреть носом, если не по ходу
	var t = u.target
	if t != null and (not t.alive or t.in_hyper > 0 or not visible_to(u.team, t)):
		u.target = null
		t = null
		if u.order == "attack":
			u.order = "idle"
			u.order_pos = u.pos
	match u.order:
		"move":
			want = _seek(u, u.order_pos)
			if u.pos.distance_to(u.order_pos) < max(300.0, u.radius()):
				u.order = "idle"
				u.order_pos = u.pos
		"attack":
			var r := _keep_range(u, t)
			want = r[0]
			face = r[1]
		"amove", "idle":
			var auto = _auto_target(u)
			if auto:
				if u.order == "idle" and not u.is_big() and auto.pos.distance_to(u.order_pos) > _max_range(u) + 5000:
					want = _seek(u, u.order_pos)   # не уходим далеко от места стоянки
				else:
					var r2 := _keep_range(u, auto)
					want = r2[0]
					face = r2[1]
					if not u.player_ordered or u.order == "amove":
						u.target = auto
			elif u.order == "amove":
				want = _seek(u, u.order_pos)
				if u.pos.distance_to(u.order_pos) < 500:
					u.order = "idle"
			else:
				want = _seek(u, u.order_pos) if u.pos.distance_to(u.order_pos) > 800 else Vector2.ZERO
	# Главное правило поясов: крупный сам отходит, если к нему подошли ближе минимума.
	if u.is_big() and u.order != "move":
		var mn: float = max(_min_range(u), Defs.BIG_MIN_RANGE)
		var threat = null
		var td := INF
		for e in enemies_of(u):
			if e.cls == "frigate" or e.is_big() or e.cls == "corvette":
				var d: float = e.pos.distance_to(u.pos)
				if d < mn + 1200 and d < td:
					td = d
					threat = e
		if threat:
			want = (u.pos - threat.pos).normalized() * u.speed()
			if face == null:
				face = threat.pos
	u.want = want
	u.face = face

func _auto_target(u: Unit):
	var best = null
	var bs := -1.0
	var reach := _max_range(u) + (6000.0 if u.order == "amove" else 2500.0)
	var flak_ship: bool = u.cls == "corvette" and u.weapons.size() > 0 and u.weapons[0].cls == "flak"
	for e in enemies_of(u):
		var d: float = e.pos.distance_to(u.pos)
		if d > reach:
			continue
		# Корабль не гоняется за звеньями — по ним стреляет само оружие. Исключение — зенитный корвет.
		if e.is_squad() and not flak_ship:
			continue
		var eff := _best_eff(u, e)
		if eff <= 0.05:
			continue
		var s := eff / (1.0 + d / 5000.0)
		if e.is_station():
			s *= 0.6
		if s > bs:
			bs = s
			best = e
	return best

func _best_eff(u: Unit, e: Unit) -> float:
	var m := 0.0
	for wp in u.weapons:
		m = max(m, Defs.EFF[wp.cls][e.target_class()])
	return m

func _keep_range(u: Unit, t) -> Array:
	if t == null:
		return [Vector2.ZERO, null]
	var d: float = u.pos.distance_to(t.pos)
	var wmax := _max_range(u)
	var desired: float
	if u.def.bays > 0 and u.cls != "capital":
		desired = 8000.0   # носитель держится сзади и работает звеньями
	elif u.is_big() and t.is_station():
		desired = wmax - 900   # станцию ломают с предела своей дальности, вне её батарей
	elif u.is_big():
		var mn: float = max(_min_range(u), Defs.BIG_MIN_RANGE)
		desired = clamp(wmax * 0.75, mn + 2500, wmax - 800)
	elif u.cls == "frigate" and (t.is_big() or t.is_station()):
		desired = 1800.0   # фрегат лезет под минимум крупного
	elif u.abil_on.has("ram"):
		desired = 0.0
	else:
		desired = wmax * 0.6
	desired += t.radius() * 0.5
	var dir: Vector2 = (t.pos - u.pos).normalized()
	var want := Vector2.ZERO
	if d > desired + 800:
		want = dir * u.speed()
	elif d < desired - 800:
		want = -dir * u.speed()
	else:
		want = dir.orthogonal() * u.speed() * 0.15 if not u.is_big() else Vector2.ZERO
	if u.abil_on.has("ram") and d < t.radius() + u.radius() + 150:
		damage(t, 1800.0, "", u)
		damage(u, 500.0, "", t)
		u.abil_on.erase("ram")
	return [want, t.pos]

func _seek(u: Unit, p: Vector2) -> Vector2:
	var d := p - u.pos
	var l := d.length()
	if l < 1.0:
		return Vector2.ZERO
	var sp := u.speed()
	var brake: float = clamp(l / max(sp * 6.0, 1.0), 0.15, 1.0) if not u.is_squad() else 1.0
	return d / l * sp * brake

func _behave_squad(u: Unit) -> void:
	if u.order == "dock" or (u.home and u.home.alive and u.home.charge > 0):
		var h = u.home if u.home and u.home.alive else teams[u.team].station
		if h == null or not h.alive:
			u.order = "idle"
		else:
			u.want = _seek(u, h.pos)
			if u.pos.distance_to(h.pos) < h.radius() + 200 and u.order == "dock":
				u.alive = false
				u.docked = true
				h.bay_queue.append({"type": u.def.id, "t": 8.0, "paid": true})
			return
	var t = u.target
	if t != null and (not t.alive or t.in_hyper > 0 or not visible_to(u.team, t)):
		t = null
		u.target = null
		if u.order == "attack":
			u.order = "idle"
	if t == null:
		# Звено действует само: цель носителя или ближайшая подходящая у носителя.
		var anchor: Vector2 = u.pos
		var reach := 4000.0
		if u.linked:
			anchor = u.home.pos
			reach = 12000.0
			if u.home.target and u.home.target.alive and visible_to(u.team, u.home.target) and _best_eff(u, u.home.target) > 0.2:
				t = u.home.target
		if u.order == "move" or u.order == "amove":
			anchor = u.order_pos
		if t == null:
			t = _squad_pick(u, anchor, reach)
	if t != null:
		var d: float = u.pos.distance_to(t.pos)
		var ring: float = 450.0 + t.radius()
		var dir: Vector2 = (t.pos - u.pos) / max(d, 1.0)
		var want: Vector2
		if d > ring + 300:
			want = dir * u.speed()
		else:
			want = (dir.orthogonal() * 0.9 + dir * (d - ring) / 400.0).normalized() * u.speed() * 0.8
		u.want = want
		u.cur = t
		return
	u.cur = null
	if u.order == "move" or u.order == "amove":
		u.want = _seek(u, u.order_pos)
		if u.pos.distance_to(u.order_pos) < 400:
			u.order = "idle"
		return
	# Без цели — кружим у носителя.
	var c: Vector2 = u.home.pos if u.linked else u.pos
	var off := u.pos - c
	var rr: float = (u.home.radius() if u.linked else 0.0) + 900.0
	var want2 := (off.orthogonal().normalized() * 0.8 + (-off.normalized()) * (off.length() - rr) / 600.0)
	u.want = want2.normalized() * u.speed() * 0.5 if off.length() > 1 else Vector2.ZERO

func _squad_pick(u: Unit, anchor: Vector2, reach: float):
	var best = null
	var bs := 0.0
	for e in enemies_of(u):
		var d: float = e.pos.distance_to(anchor)
		if d > reach:
			continue
		var eff := _best_eff(u, e)
		if eff <= 0.1:
			continue
		var s := eff / (1.0 + u.pos.distance_to(e.pos) / 3000.0)
		if u.cls == "bomber" and e.cls == "harvester":
			s *= 1.2
		if s > bs:
			bs = s
			best = e
	return best

func _behave_harvester(u: Unit) -> void:
	var st: Unit = teams[u.team].station
	if u.order == "move":
		u.want = _seek(u, u.order_pos)
		if u.pos.distance_to(u.order_pos) < 300:
			u.order = "harvest"
		return
	if u.order == "idle":
		u.order = "harvest"
	if st == null or not st.alive:
		u.want = Vector2.ZERO
		return
	if u.h_state == "go":
		if u.field == null or u.field.ore <= 0:
			u.field = _pick_field(u)
		if u.field == null:
			u.want = _seek(u, st.pos + Vector2(0, 2000))
			return
		if u.pos.distance_to(u.field.pos) < u.field.r * 0.6:
			u.h_state = "mine"
		u.want = _seek(u, u.field.pos)
	elif u.h_state == "mine":
		u.want = Vector2.ZERO
		if u.field == null or u.field.ore <= 0 or u.cargo >= Defs.HARVEST_CAP:
			u.h_state = "back"
		else:
			var take: float = min(Defs.HARVEST_RATE * DT * 3.0, u.field.ore, Defs.HARVEST_CAP - u.cargo)
			u.field.ore -= take
			u.cargo += take
	elif u.h_state == "back":
		u.want = _seek(u, st.pos)
		if u.pos.distance_to(st.pos) < st.radius() + 600:
			teams[u.team].ore += u.cargo
			teams[u.team].mined += u.cargo
			u.cargo = 0.0
			u.h_state = "go"

func _pick_field(u: Unit):
	var st: Unit = teams[u.team].station
	var best = null
	var bs := INF
	for f in fields:
		if f.ore <= 0:
			continue
		var d: float = f.pos.distance_to(st.pos)
		# Не лезем туда, где видны враги (кроме самых простых случаев).
		for e in units:
			if e.alive and e.team != u.team and not e.is_squad() and e.cls != "harvester" and visible_to(u.team, e) and e.pos.distance_to(f.pos) < 8000:
				d += 30000
				break
		var others := 0
		for o in units:
			if o.alive and o != u and o.team == u.team and o.cls == "harvester" and o.field == f:
				others += 1
		d += others * 4000
		if d < bs:
			bs = d
			best = f
	return best

# ------------------------------------------------------------ движение

func _move(u: Unit) -> void:
	if u.is_station():
		return
	var want: Vector2 = u.want
	var face = u.face
	var sp := u.speed()
	var f = in_field(u.pos)
	if f and not u.is_squad() and u.cls != "harvester":
		sp *= 0.5 if u.is_big() else 0.7
	if want.length() > sp:
		want = want.normalized() * sp
	var turn := deg_to_rad(u.def.turn)
	if u.is_squad():
		if want.length() > 1:
			u.heading = rotate_toward(u.heading, want.angle(), turn * DT)
		u.vel = u.vel.lerp(want, 0.25)
	else:
		var desired_face: float = u.heading
		var moving := want.length() > 5.0
		if face != null:
			desired_face = (face - u.pos).angle()
		elif moving:
			desired_face = want.angle()
		u.heading = rotate_toward(u.heading, desired_face, turn * DT)
		var actual := Vector2.ZERO
		if moving:
			var ang: float = abs(angle_difference(u.heading, want.angle()))
			var k: float
			if ang < deg_to_rad(60):
				k = 1.0 - ang / PI
			elif ang > deg_to_rad(120):
				k = u.def.reverse           # пятится на выносных двигателях
			else:
				k = 0.35                    # боком — медленно
			actual = want * k
		var acc := 1.0 / (8.0 if u.is_big() else 3.0)
		u.vel = u.vel.lerp(actual, acc * DT * 3.0)
	# Расталкивание: крупные не наезжают друг на друга.
	if not u.is_squad():
		for o in units:
			if o == u or not o.alive or o.is_squad() or o.in_hyper > 0:
				continue
			var dd: Vector2 = u.pos - o.pos
			var min_d: float = u.radius() + o.radius() + 100
			var l: float = dd.length()
			if l < min_d and l > 0.01:
				var push: Vector2 = dd / l * (min_d - l) * (0.05 if not u.is_station() else 0.0)
				if o.is_station():
					push *= 2.0
				u.pos += push
	u.pos += u.vel * DT
	u.pos = _clamp_map(u.pos)

# --------------------------------------------------------------- огонь

func _fire(u: Unit) -> void:
	for wp in u.weapons:
		if wp.t > 0:
			wp.t -= DT
			continue
		if not u.weapon_ok(wp):
			continue
		if u.is_squad() and not u.linked and u.home != null and u.jam <= 0:
			pass
		var tgt = _weapon_target(u, wp)
		if tgt == null:
			wp.t = 0.3
			continue
		var cd: float = wp.cd
		if u.siege:
			cd *= 0.75
		if wp.cls == "flak" and u.abil_on.has("barrage"):
			cd *= 0.4
		wp.t = cd
		var hp_id := u.target_hp if tgt == u.target else ""
		var n := u.craft_alive() * int(wp.shots)
		if wp.get("salvo", false):
			n *= 2
			wp.salvo = false
		if wp.cls == "torpedo" or wp.cls == "missile":
			for i in n:
				_launch_proj(u, tgt, wp, hp_id)
			continue
		var eff: float = Defs.EFF[wp.cls][tgt.target_class()]
		var p: float = wp.acc * min(eff, 1.0)
		if u.is_squad():
			if u.jam > 0:
				p *= 0.5
			elif not u.linked:
				p *= 0.8
		var dmg: float = wp.dmg * eff
		if hp_id != "" and u.abil_on.has("hp_volley"):
			dmg *= 1.6
		var total := 0.0
		for i in n:
			if rng.randf() < clamp(p, 0.0, 0.97):
				total += dmg
		if wp.cls == "heavy" or wp.cls == "main":
			_launch_shell(u, tgt, wp.cls, total, hp_id)
			continue
		_shot(u, tgt, wp.cls)
		if total > 0:
			if u.is_squad() and tgt.is_squad():
				stats.sq_vs_sq += 1
			damage(tgt, total, hp_id, u)

func _weapon_target(u: Unit, wp: Dictionary):
	var rmax: float = wp.max * (1.35 if u.siege else 1.0)
	var rmin: float = wp.min
	var cur = u.target if u.target != null else u.cur
	if cur != null and cur.alive and cur.in_hyper <= 0 and visible_to(u.team, cur) and _in_arc(u, wp, cur):
		var d: float = u.pos.distance_to(cur.pos) - cur.radius() * 0.5
		if d >= rmin and d <= rmax and Defs.EFF[wp.cls][cur.target_class()] > 0.05:
			return cur
	var best = null
	var bs := 0.0
	for e in units:
		if not e.alive or e.team == u.team or e.in_hyper > 0 or not visible_to(u.team, e):
			continue
		var d2: float = u.pos.distance_to(e.pos) - e.radius() * 0.5
		if d2 < rmin or d2 > rmax:
			continue
		var eff: float = Defs.EFF[wp.cls][e.target_class()]
		if eff <= 0.05 or not _in_arc(u, wp, e):
			continue
		var s: float = eff / (1.0 + d2 / max(rmax, 1.0))
		if s > bs:
			bs = s
			best = e
	return best

func _in_arc(u: Unit, wp: Dictionary, e: Unit) -> bool:
	if wp.arc >= 360:
		return true
	return abs(angle_difference(u.heading, (e.pos - u.pos).angle())) < deg_to_rad(wp.arc * 0.5)

func _shot(a: Unit, b: Unit, cls: String) -> void:
	shots.append({"a": a.pos, "b": b.pos + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * b.radius() * 0.4,
		"ah": a.height, "bh": b.height, "cls": cls, "t": time, "team": a.team})
	if shots.size() > 600:
		shots = shots.slice(300)

func _launch_proj(u: Unit, tgt: Unit, wp: Dictionary, hp_id: String) -> void:
	var spd := 450.0 if wp.cls == "torpedo" else 650.0
	projectiles.append({"pos": u.pos + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40)),
		"tgt": tgt, "dmg": wp.dmg, "cls": wp.cls, "team": u.team, "hp": hp_id, "life": 9.0,
		"spd": spd, "spoofed": false, "dir": (tgt.pos - u.pos).normalized(), "src": u, "h": u.height})

## Снаряд крупного калибра: видно, как он летит, и урон приходит
## в момент попадания. Попал ли — решено при выстреле; промах летит мимо.
func _launch_shell(u: Unit, tgt: Unit, cls: String, dmg: float, hp_id: String) -> void:
	var miss := dmg <= 0.0
	var aim: Vector2 = tgt.pos
	if miss:
		aim += Vector2.from_angle(rng.randf() * TAU) * (tgt.radius() + rng.randf_range(300, 900))
	var spd := 7000.0 if cls == "main" else 5000.0
	var from: Vector2 = u.pos + Vector2.from_angle(u.heading) * u.radius() * 0.6
	projectiles.append({"pos": from, "tgt": tgt, "dmg": dmg, "cls": "shell", "big": cls == "main",
		"team": u.team, "hp": hp_id, "life": from.distance_to(aim) / spd + (1.5 if miss else 0.6),
		"spd": spd, "spoofed": miss, "dir": (aim - from).normalized(), "src": u, "h": u.height})

func _projectiles() -> void:
	var keep := []
	for p in projectiles:
		p.life -= DT
		if p.life <= 0:
			continue
		if p.cls == "shell":
			var st: Unit = p.tgt
			if not p.spoofed and st.alive and st.in_hyper <= 0:
				p.dir = (st.pos - p.pos).normalized()
			p.pos += p.dir * p.spd * DT
			if not p.spoofed and st.alive and p.pos.distance_to(st.pos) < st.radius() + 120:
				damage(st, p.dmg, p.hp, p.src if p.src.alive else null)
				flashes.append({"pos": p.pos, "h": st.height, "t": time, "r": 250.0 if p.big else 120.0})
				continue
			keep.append(p)
			continue
		var t: Unit = p.tgt
		if not p.spoofed and t.alive and t.in_hyper <= 0:
			p.dir = (t.pos - p.pos).normalized()
		p.pos += p.dir * p.spd * DT
		if not p.spoofed and t.alive and p.pos.distance_to(t.pos) < t.radius() + 60:
			var eff: float = Defs.EFF[p.cls][t.target_class()]
			var src = p.src if p.src.alive else null
			if rng.randf() < 0.9:
				damage(t, p.dmg * eff, p.hp, src)
				if src and src.is_squad():
					stats.bomber_kills += 0
			continue
		keep.append(p)
	projectiles = keep

func _spoof_check() -> void:
	# РЭБ Плэктора сбивает наведение ракет и торпед; РЭБ Тройдена глушит звенья.
	for u in units:
		if not u.alive or u.def.ecm == "" or not u.hp_alive("ecm") or u.in_hyper > 0:
			continue
		var r: float = u.def.ecm_r * (2.0 if u.abil_on.has("wide_jam") else 1.0)
		if u.def.ecm == "spoof":
			var chance := 1.0 if u.abil_on.has("decoys") else 0.45
			for p in projectiles:
				if p.cls != "shell" and p.team != u.team and not p.spoofed and p.pos.distance_to(u.pos) < r:
					if rng.randf() < chance:
						p.spoofed = true
						p.dir = p.dir.rotated(rng.randf_range(-1.2, 1.2))
		elif u.def.ecm == "jam":
			for e in units:
				if e.alive and e.team != u.team and e.is_squad() and e.pos.distance_to(u.pos) < r:
					e.jam = 1.0

# ---------------------------------------------------------- повреждения

func damage(u: Unit, amount: float, hp_id: String, src) -> void:
	if not u.alive or amount <= 0:
		return
	u.last_hit_by = src.team if src else -1
	stats.dmg[1 - u.team] += amount
	var dmg := amount
	if u.shield_works() and u.hp_alive("reactor") and u.shield > 0:
		var ab: float = min(u.shield, dmg)
		u.shield -= ab
		dmg -= ab
		u.shield_delay = 5.0
	else:
		u.shield_delay = 5.0
	if dmg <= 0:
		return
	dmg *= (1.0 - u.def.armor)
	var h = u.hp_by_id(hp_id) if hp_id != "" else null
	if h != null and h.hp > 0:
		var k := 0.3 if (h.kind == "hangar" and u.abil_on.has("armor_hangars")) else 1.0
		var before: float = h.hp
		h.hp = max(0.0, h.hp - dmg * 0.85 * k)
		u.hull -= dmg * 0.3
		if before > 0 and h.hp <= 0:
			_hp_destroyed(u, h)
	else:
		u.hull -= dmg
		if not u.hps.is_empty() and rng.randf() < 0.5:
			var r: Dictionary = u.hps[rng.randi() % u.hps.size()]
			if r.hp > 0:
				r.hp = max(0.0, r.hp - dmg * 0.25)
				if r.hp <= 0:
					_hp_destroyed(u, r)
	if u.hull <= 0:
		_kill(u, src)

func _hp_destroyed(u: Unit, h: Dictionary) -> void:
	note(u.team, "%s: выбит «%s»" % [u.def.name, h.label])
	note(1 - u.team, "У врага выбит «%s» (%s)" % [h.label, u.def.name])
	if h.kind == "shieldgen" and not u.shield_works():
		u.shield = 0.0

func _kill(u: Unit, src) -> void:
	flashes.append({"pos": u.pos, "h": u.height, "t": time, "r": max(150.0, u.def.size * (0.15 if u.is_squad() else 0.6)), "die": true})
	if flashes.size() > 300:
		flashes = flashes.slice(150)
	u.alive = false
	u.hull = 0.0
	stats.lost[u.team] += 1
	if src:
		stats.kills[src.team] += 1
		if src.is_squad() and u.is_squad():
			stats.sq_kills_sq += 1
	if u.is_squad() and u.home:
		u.home.squads.erase(u)
	for s in u.squads:
		s.home = null
		s.linked = false
	if not u.is_squad():
		note(u.team, "Потерян: %s" % u.def.name)

func _cleanup() -> void:
	if tick % 20 != 0:
		return
	var keep := []
	for u in units:
		if u.alive:
			keep.append(u)
		else:
			by_id.erase(u.id)
	units = keep
	var tk := []
	for r in reveals:
		r.t -= DT * 20
		if r.t > 0:
			tk.append(r)
	reveals = tk

# ------------------------------------------------------- ангары, ремонт

func _hangars() -> void:
	for u in units:
		if not u.alive or u.def.bays == 0 or u.bay_queue.is_empty() or u.in_hyper > 0 or u.charge > 0:
			continue
		if not u.hp_alive("hangar"):
			continue
		var b: Dictionary = u.bay_queue[0]
		if not b.paid:
			var c: float = Defs.ship(b.type).cost
			if teams[u.team].ore < c:
				continue
			teams[u.team].ore -= c
			b.paid = true
		b.t -= DT
		if b.t <= 0:
			u.bay_queue.pop_front()
			_launch_squad(u, b.type)

func _repair() -> void:
	if tick % 5 != 0:
		return
	var dt := DT * 5
	for r in units:
		if not r.alive or r.def.repair <= 0 or r.in_hyper > 0:
			continue
		if not r.is_station() and not r.hp_alive("dock"):
			continue
		var rate: float = r.def.repair * (3.0 if r.abil_on.has("repair_surge") else 1.0)
		for o in units:
			if not o.alive or o.team != r.team or o == r or o.in_hyper > 0:
				continue
			if o.pos.distance_to(r.pos) > r.def.repair_r + o.radius():
				continue
			o.hull = min(o.hull_max, o.hull + rate * dt * (0.3 if o.is_squad() else 1.0))
			for h in o.hps:
				h.hp = min(h.max, h.hp + rate * 0.5 * dt)

# -------------------------------------------------- статистика, победа

func _stats_step() -> void:
	if tick % 5 != 0:
		return
	for u in units:
		if not u.alive or not u.is_big() or u.in_hyper > 0:
			continue
		var nd := INF
		for e in units:
			if e.alive and e.team != u.team and (e.is_big()) and e.in_hyper <= 0:
				nd = min(nd, e.pos.distance_to(u.pos))
		if nd < 16000:
			if nd > Defs.BIG_MIN_RANGE:
				stats.big_far += DT * 5
			else:
				stats.big_close += DT * 5

func _victory() -> void:
	for t in 2:
		var st: Unit = teams[t].station
		if st == null or not st.alive:
			winner = 1 - t
			note(0, "Станция %s уничтожена" % ("игрока" if t == 0 else "врага"))
			return
