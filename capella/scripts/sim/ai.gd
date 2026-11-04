class_name AIPlayer
extends RefCounted
## ИИ стороны. Отдаёт приказы теми же командами, что и игрок (world.cmd_*),
## поэтому видит только то, что видно его стороне, и ничего не «читерит».

var w: World
var team := 0
var diff := "medium"
var fac := ""
var think := 0.0
var interval := 2.0
var harv_target := 4
var attack_pts := 24
var state := "gather"
var wave := 0
var waypoint := Vector2.ZERO
var repairing := {}          # id -> true: ушёл чиниться
var wave_ids := {}           # кто идёт в нынешней волне
var wave_pts := 0

func _init(world: World, t: int, d: String) -> void:
	w = world
	team = t
	diff = d
	fac = w.teams[t].fac
	match diff:
		"easy":
			interval = 4.0
			harv_target = 3
			attack_pts = 14
		"medium":
			interval = 2.0
			harv_target = 4
			attack_pts = 20
		"hard":
			interval = 1.0
			harv_target = 5
			attack_pts = 24

func step(dt: float) -> void:
	think -= dt
	if think > 0:
		return
	think = interval
	var st: Unit = w.teams[team].station
	if st == null or not st.alive:
		return
	_economy(st)
	_army(st)
	if diff != "easy":
		_abilities()

# ----------------------------------------------------------- экономика

func _mine() -> Array:
	return w.units.filter(func(u): return u.alive and u.team == team)

func _economy(st: Unit) -> void:
	var ore: float = w.teams[team].ore
	var harv := 0
	for u in _mine():
		if u.cls == "harvester":
			harv += 1
	for q in st.build_queue:
		if Defs.ship(q.id).cls == "harvester":
			harv += 1
	var any_ore := false
	for f in w.fields:
		if f.ore > 0:
			any_ore = true
	if harv < harv_target and any_ore and w.cmd_build(team, Defs.harvester_of(fac)):
		return
	# Улучшение станции — когда есть запас на него.
	if st.level < 4 and st.upgrading <= 0 and state != "defend":
		var need: int = Defs.STATION_UPGRADE[st.level + 1]
		var min_time: float = {"easy": [0, 0, 240, 600, 900], "medium": [0, 0, 150, 420, 720], "hard": [0, 0, 100, 330, 600]}[diff][st.level + 1]
		if w.time >= min_time and ore >= need:
			w.cmd_upgrade(team)
			return
		if w.time >= min_time and ore < need:
			return   # копим на улучшение, ничего не строим
	if st.build_queue.size() >= 2:
		return
	var pick := _choose_ship(st)
	if pick != "":
		w.cmd_build(team, pick)
	# Докупить звенья на носителях, когда руды много.
	if diff != "easy" and w.teams[team].ore > 1200:
		for u in _mine():
			if u.def.bays > 0 and w.squad_block(u) == "":
				w.cmd_buy_squad(u)
				break

func _choose_ship(st: Unit) -> String:
	# Взвешенный выбор: доктрина фракции плюс ответ на то, что видно у врага.
	var enemy_sq := 0
	var enemy_big := 0
	var enemy_mid := 0
	for e in w.units:
		if e.alive and e.team != team and w.visible_to(team, e):
			if e.is_squad():
				enemy_sq += 1
			elif e.is_big():
				enemy_big += 1
			elif e.cls == "frigate" or e.cls == "corvette":
				enemy_mid += 1
	var weights := {}
	if fac == "troyden":
		weights = {"warden": 3, "tracer": 0.5, "dixon": 3, "silencer": 1.5, "howard": 4, "hunter": 2.5, "grosser": 2, "lancelot": 5}
	else:
		weights = {"ogr": 3, "troll": 4, "garpia": 1.5, "norman": 3, "whiteshark": 3, "ork": 3, "goliath": 5}
	if diff != "easy":
		for k in weights.keys():
			var d := Defs.ship(k)
			if enemy_sq > 4 and (k == "warden" or k == "ogr" or k == "silencer"):
				weights[k] *= 2.0
			if enemy_big > 1 and (d.cls == "frigate" or d.bays > 0):
				weights[k] *= 1.8
			if enemy_mid > 3 and Defs.is_big(d.cls):
				weights[k] *= 1.6
			if k == "garpia" and fac == "plector" and _enemy_has("palarmo"):
				weights[k] *= 2.5
			if k == "tracer" and _count("tracer") >= 1:
				weights[k] = 0.0
	# Мелочь не должна съесть лимит флота: под крупные держим место.
	var n_corv := 0
	var n_frig := 0
	for u in _mine():
		if u.cls == "corvette":
			n_corv += 1
		elif u.cls == "frigate":
			n_frig += 1
	for k in weights.keys():
		var dk := Defs.ship(k)
		if dk.cls == "corvette" and n_corv >= 2 + st.level:
			weights[k] = 0.0
		if dk.cls == "frigate" and n_frig >= 1 + st.level * (2 if fac == "plector" else 1):
			weights[k] = 0.0
		if (dk.ecm != "") and _count(k) >= 2:
			weights[k] = 0.0
		if Defs.is_big(dk.cls):
			weights[k] *= 3.0
	var options := []
	var total := 0.0
	var save_for := ""
	for k in weights:
		if weights[k] <= 0:
			continue
		var why := w.build_block(team, k)
		if why == "":
			options.append([k, weights[k]])
			total += weights[k]
		elif why == "мало руды" and Defs.ship(k).lvl >= 3 and diff != "easy":
			if save_for == "" or Defs.ship(k).lvl > Defs.ship(save_for).lvl:
				save_for = k
	# Есть доступный крупный, на который не хватает, — копим на него, а не тратим на мелочь.
	if save_for != "" and w.rng.randf() < (0.9 if diff == "hard" else 0.7):
		return ""
	if options.is_empty():
		return ""
	var r := w.rng.randf() * total
	for o in options:
		r -= o[1]
		if r <= 0:
			return o[0]
	return options[-1][0]

func _count(id: String) -> int:
	var n := 0
	for u in _mine():
		if u.def.id == id:
			n += 1
	return n

func _enemy_has(id: String) -> bool:
	for e in w.units:
		if e.alive and e.team != team and e.def.id == id and w.visible_to(team, e):
			return true
	return false

# --------------------------------------------------------------- армия

func _army(st: Unit) -> void:
	var army := []
	var pts := 0
	for u in _mine():
		if u.is_squad() or u.is_station() or u.cls == "harvester" or u.in_hyper > 0 or u.charge > 0:
			continue
		if u.cls == "scout":
			_scout(u)
			continue
		if repairing.has(u.id):
			if u.hull >= u.hull_max * 0.85:
				repairing.erase(u.id)
			else:
				continue
		army.append(u)
		pts += u.points()
	# Ремонт: подбитый крупный уходит к станции (Тройден — прыжком, если далеко).
	if diff != "easy":
		for u in army.duplicate():
			if (u.is_big() or u.cls == "frigate") and u.hull < u.hull_max * 0.35:
				repairing[u.id] = true
				army.erase(u)
				pts -= u.points()
				if fac == "troyden" and u.pos.distance_to(st.pos) > 15000:
					w.cmd_retreat([u])
				else:
					w.cmd_move([u], st.pos + (w.teams[team].rally - st.pos).normalized() * 2500)
	var enemy_st: Unit = w.teams[1 - team].station
	# Оборона: враг у станции или у харвестеров.
	var threat = null
	for e in w.units:
		if e.alive and e.team != team and w.visible_to(team, e) and not e.is_station() and not e.is_squad() and e.cls != "scout" and e.cls != "harvester":
			if e.pos.distance_to(st.pos) < 12000:
				threat = e
				break
	if threat and state != "attack":
		w.cmd_move(army, threat.pos, true)
		state = "defend"
		return
	if state == "defend" and threat == null:
		state = "gather"
	var need := attack_pts + wave * 4
	if w.time > 660.0:
		need = min(need, int(w.fleet_cap(team) * 0.45))
	if state == "gather":
		if pts >= need or (w.time > 600 and pts >= 8):
			state = "attack"
			wave += 1
			wave_ids.clear()
			for u in army:
				wave_ids[u.id] = true
			wave_pts = pts
			waypoint = _center(army)
		else:
			var idle := army.filter(func(u): return u.order == "idle" and u.pos.distance_to(w.teams[team].rally) > 4000)
			if not idle.is_empty():
				w.cmd_move(idle, w.teams[team].rally)
			return
	if state == "attack":
		# Построенные во время атаки ждут следующую волну у станции, а не летят поодиночке.
		var home := army.filter(func(u): return not wave_ids.has(u.id))
		var idle_home := home.filter(func(u): return u.order == "idle" and u.pos.distance_to(w.teams[team].rally) > 4000)
		if not idle_home.is_empty():
			w.cmd_move(idle_home, w.teams[team].rally)
		army = army.filter(func(u): return wave_ids.has(u.id))
		var wp := 0
		for u in army:
			wp += u.points()
		var endgame: bool = w.time > 660.0   # после 15-й минуты — до конца, без отката
		if army.is_empty() or wp < wave_pts * (0.1 if endgame else 0.3):
			state = "gather"
			w.cmd_move(army, w.teams[team].rally)
			return
		# Тяжёлый ИИ уводит флот, если бой проигран.
		if diff == "hard" and not endgame and _losing(army, wp):
			w.cmd_retreat(army)
			state = "gather"
			return
		var c := _center(army)
		var goal: Vector2 = enemy_st.pos
		# Двигаемся волной: следующая точка — только когда флот собрался у прежней.
		var behind := 0
		for u in army:
			if u.pos.distance_to(waypoint) > 7000:
				behind += 1
		if behind <= army.size() / 3:
			waypoint = waypoint + (goal - waypoint).limit_length(7000)
		var near_station: bool = c.distance_to(goal) < 16000
		for u in army:
			if u.order == "attack" and u.target and u.target.alive:
				_pick_hp(u, u.target)
				continue
			if near_station and w.visible_to(team, enemy_st):
				w.cmd_attack([u], enemy_st, "")
				_pick_hp(u, enemy_st)
			elif u.order != "amove" or u.order_pos.distance_to(waypoint) > 3000:
				w.cmd_move([u], waypoint, true)

func _losing(army: Array, pts: int) -> bool:
	var c := _center(army)
	var ep := 0
	for e in w.units:
		if e.alive and e.team != team and w.visible_to(team, e) and not e.is_squad() and not e.is_station() and e.pos.distance_to(c) < 18000:
			ep += e.points()
	return ep > 0 and pts < ep * 0.4 and c.distance_to(w.teams[team].station.pos) > 25000

func _center(list: Array) -> Vector2:
	if list.is_empty():
		return w.teams[team].rally
	var s := Vector2.ZERO
	for u in list:
		s += u.pos
	return s / list.size()

func _pick_hp(u: Unit, t: Unit) -> void:
	if diff == "easy" or t.hps.is_empty() or not (u.is_big() or u.cls == "frigate"):
		return
	var order := ["weapon"] if diff == "medium" else ["hangar", "weapon", "shieldgen", "engine"]
	for kind in order:
		for h in t.hps:
			if h.kind == kind and h.hp > 0:
				u.target = t
				u.target_hp = h.id
				return
	u.target_hp = ""

func _scout(u: Unit) -> void:
	if u.order != "idle":
		return
	var p := Vector2(w.rng.randf_range(-0.3, 0.3) * w.map_w, w.rng.randf_range(-0.35, 0.35) * w.map_w)
	w.cmd_move([u], p)

# ---------------------------------------------------------- способности

func _abilities() -> void:
	for u in _mine():
		if u.abil_cd.is_empty() or u.in_hyper > 0:
			continue
		for a in u.abil_cd:
			if u.abil_cd[a] > 0:
				continue
			if _want_abil(u, a):
				w.cmd_ability(u, a)

func _want_abil(u: Unit, a: String) -> bool:
	var near_enemy := false
	var near_sq := false
	for e in w.units:
		if e.alive and e.team != team and w.visible_to(team, e) and e.pos.distance_to(u.pos) < 9000:
			near_enemy = true
			if e.is_squad() and e.pos.distance_to(u.pos) < 4000:
				near_sq = true
	match a:
		"boost", "dash":
			return u.cur != null
		"torp_salvo", "missile_salvo":
			var c = u.cur
			return c != null and c.pos.distance_to(u.pos) < 1600 and not c.is_squad()
		"scan":
			return w.rng.randf() < 0.1
		"shield_ally":
			return near_enemy
		"wide_jam", "barrage":
			return near_sq
		"decoys":
			for p in w.projectiles:
				if p.team != team and p.pos.distance_to(u.pos) < 4000:
					return true
			return false
		"shield_boost":
			return u.shield_max > 0 and u.shield < u.shield_max * 0.2 and near_enemy
		"hp_volley":
			return u.target_hp != "" and u.target != null
		"repair_surge":
			return near_enemy
		"siege":
			var t = u.target
			return t != null and t.is_station() and not u.siege and u.pos.distance_to(t.pos) < 19000
		"main_shot":
			return u.target != null
		"ram":
			return u.target != null and (u.target.is_big() or u.target.cls == "frigate") and u.pos.distance_to(u.target.pos) < 4000
		"emergency_launch", "launch_all":
			return near_enemy and not u.bay_queue.is_empty()
		"armor_hangars":
			return near_enemy
		"engine_power":
			return repairing.has(u.id)
	return false
