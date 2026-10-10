extends RefCounted
## Порт createSpaceBattle (game/js/space.js) — вариант «C»: те же функции,
## те же имена (camelCase → snake_case), тот же порядок шага (sim_step =
## simStep). Картинка, звук, лента — только СОБЫТИЯ в журнал (emit_fx /
## feed), сам бой о сцене не знает и крутится без отрисовки.
## Доктрина (godot/spec/09) — ветками под флажками `flags`, чтобы
## «проверка откатом» (09, 8.4) была тем же кодом с другим флажком.

const Ent = preload("res://sim/ent.gd")

const FIELD := 2600.0
const UP := Vector3(0, 1, 0)
const ALT_UP := Vector3(0, 0, 1)

var D: Dictionary            # godot/data/space_data.json
var DOC: Dictionary          # godot/data/doctrine.json (дополняет D)
var cfg: Dictionary
var flags: Dictionary = {}   # doctrine, old_approach, old_ai, old_pd, ...
var rng := RandomNumberGenerator.new()      # ТОЛЬКО бой: от него зависит исход
var fx_rng := RandomNumberGenerator.new()   # картинка: на исход не влияет никогда

class State:
	var time: float = 0.0
	var ships: Array = []
	var craft: Array = []
	var proj: Array = []
	var squads: Array = []
	var retreat := {"attacker": false, "defender": false}
	var conceded: String = ""
	var stats := {"first_hit": 0.0, "first_gun": 0.0, "planet": 0.0}
	var ended: bool = false
	var result: String = ""
var state := State.new()
var feed_log: Array = []     # как state.feedLog: [время, текст, род]
var fx_count := 0            # сколько событий картинки выдал бой (журнал для стенда)
var sides := {}
var ais := {}                # сторона -> состояние ИИ (ИИ на КАЖДУЮ сторону, 05 5.2)
var uid := 1
var name_n := {"attacker": {}, "defender": {}}
var _fields: Array = []
var REV := 0.6
var ecm_prof := {}           # профиль помех клана + имя клана (для mainSlow)
var metrics := {}            # замеры доктрины (09, 8.2)
var max_hull := 0.0          # крупнейший корпус в бою — для отсечки в расталкивании

# ── вспомогательное ─────────────────────────────────────────────
func rnd(a: float, b: float) -> float: return rng.randf_range(a, b)
func enemy_of(s: String) -> String: return "defender" if s == "attacker" else "attacker"
func dmg_mult(weapon: String, cls: String) -> float:
	var t: Dictionary = D.space_dmg
	if t.has(weapon) and t[weapon].has(cls): return t[weapon][cls]
	return 1.0
func ai_mul(side: String) -> float:
	return 1.0 if not ais.has(side) else float(D.difficulty[ais[side].diff].aim)
func emit_fx(_kind: String, _a = null, _b = null) -> void:
	fx_count += 1       # в окне это вызов вида; в стенде — счёт
func feed(text: String, kind: String = "") -> void:
	feed_log.append([state.time, text, kind])

static func quat_from_dir(dir: Vector3) -> Quaternion:
	var up := ALT_UP if absf(dir.y) > 0.985 else UP
	return Quaternion(Basis.looking_at(dir, up))

func _init(data: Dictionary, doctrine: Dictionary, config: Dictionary, seed_: int, flags_: Dictionary = {}) -> void:
	D = data; DOC = doctrine; cfg = config; flags = flags_
	rng.seed = seed_; fx_rng.seed = seed_ ^ 0x5bd1e995
	REV = float(D.space_move.reverse)
	for f in D.ecm:
		ecm_prof[f] = D.ecm[f].duplicate(); ecm_prof[f]["fac"] = f
	if flags.get("doctrine", false) and not flags.get("old_pd", false):
		D = D.duplicate(true)
		D.space_dmg.pd.torpedo = DOC.space_dmg_pd_torpedo
		D.space_dmg["sec"] = DOC.space_dmg_sec
	sides = {
		"attacker": {"faction": cfg.attacker.faction, "id": "attacker", "sign": 1.0},
		"defender": {"faction": cfg.defender.faction, "id": "defender", "sign": -1.0},
	}
	for sd in cfg.get("ai_sides", ["defender"]):
		ais[sd] = {"side": sd, "diff": cfg.get("difficulty", "normal"), "next": 3.0, "focus": null,
			"hp0": 0.0, "had_heavy": false, "uid0": 0, "line_p": null, "line_ax": null}
		ais[sd].next = 3.0 * float(D.difficulty[ais[sd].diff].tempo)
	for k in ["belt_t", "close_t", "cap_t", "light_t", "light_between_t", "L_samples", "dmg"]:
		metrics[k] = [] if k == "L_samples" else ({} if k == "dmg" else 0.0)
	var dz := 650.0 if flags.get("doctrine", false) else 950.0
	spawn_fleet("attacker", cfg.attacker.ships, dz, false)
	spawn_fleet("defender", cfg.defender.ships, -dz, cfg.defender.get("station", false))
	for sd in ais: ais[sd].uid0 = first_uid(sd)
	# Свой флот приказов не получает; ИИ — на рубеж (легаси). Доктрина: места
	# ставит тик ИИ участками, а не moveTo (09, ловушка 15).
	if not flags.get("doctrine", false):
		for s in state.ships:
			if s.station or not ais.has(s.side): continue
			var line := 420.0 if s.pos.z > 0 else -420.0
			s.move_to = Vector3(s.pos.x * 0.7, s.pos.y * 0.7, line)

func first_uid(sd: String) -> int:
	for s in state.ships: if s.side == sd: return s.uid
	return 0

# ── корабли ──────────────────────────────────────────────────────
func ship_def(fac: String, id: String) -> Dictionary:
	for d in D.ships[fac]: if d.id == id: return d
	return {}

func spawn_ship(side_id: String, def: Dictionary, pos: Vector3) -> Ent.Ship:
	var side: Dictionary = sides[side_id]
	var e := Ent.Ship.new()
	e.uid = uid; uid += 1
	e.kind = "ship"; e.side = side_id; e.faction = side.faction; e.def = def
	var nn: Dictionary = name_n[side_id]
	nn[def.id] = nn.get(def.id, 0) + 1
	e.name = def.name + ((" " + str(nn[def.id])) if nn[def.id] > 1 else "")
	e.pos = pos
	e.dir = Vector3(0, 0, -1 if side.sign > 0 else 1)
	e.q = quat_from_dir(e.dir)
	e.hp = def.hp; e.max_hp = def.hp; e.armor = def.armor; e.cls = def.cls; e.radius = def.radius
	var key: String = "station" if def.get("station", false) else def.id
	if key == "station": e.len = D.model_len.station
	elif D.model_len.ship.has(key): e.len = D.model_len.ship[key]
	else: e.len = float(def.radius) * 6.0
	e.hull = maxf(def.radius * 1.6, e.len * 0.36)
	max_hull = maxf(max_hull, e.hull)
	e.retarget = rnd(0, 1)
	e.station = def.get("station", false)
	e.stance = "hold" if e.station else "guard"
	e.anchor = pos
	var i := 0
	for g in def.get("guns", []):
		var gun := Ent.Gun.new(); gun.def = g; gun.idx = i; gun.cd = rnd(0, g.cd)
		gun.role = "main" if g.type == "heavy" else ("missile" if g.type == "missile" else "light")
		e.guns.append(gun); i += 1
	if flags.get("doctrine", false) and e.cls == "capital":
		var b: Dictionary = DOC.sec_by_id.get(key, {})
		var mounts: int = b.get("mounts", 0)
		var main_r := main_range(e)
		var gm: Dictionary = DOC.gun_mod[e.faction]
		for m in mounts:
			var sg := Ent.Gun.new()
			sg.role = "sec"; sg.idx = m
			# множители клана — той же формулой, что data.js к орудиям (09, 0.1)
			var dmg := roundf(DOC.sec_base.dmg * (1.0 if e.station else gm.gunMod))
			var cdv := snappedf(DOC.sec_base.cd * (1.0 if e.station else gm.cdMod), 0.01)
			sg.def = {"type": "sec", "dmg": dmg, "cd": cdv, "range": main_r * DOC.sec_range_k}
			sg.cd = rnd(0, cdv)
			e.sec.append(sg)
	if def.get("pd") != null:
		e.pd_cd.resize(int(def.pd.count))
		for k in def.pd.count: e.pd_cd[k] = rnd(0, 0.4)
	e.stealth = def.get("stealth", false)
	e.seen_pos = pos; e.seen_at = state.time
	if def.get("ecm", false): e.ecm = {"mode": "jam", "power": 0.0}
	if def.get("hangar") != null: e.hangar = {"bays": int(def.hangar), "free": int(def.hangar), "rebuild": [], "launched": []}
	state.ships.append(e)
	return e

func spawn_fleet(side_id: String, list: Array, base_z: float, station: bool) -> void:
	var side: Dictionary = sides[side_id]
	var rows: Array = []
	for item in list:
		var def := ship_def(side.faction, item.id)
		if def.is_empty(): continue
		for n in item.count: rows.append(def)
	# устойчивая сортировка по radius по убыванию (как Array.sort в JS)
	var idx := range(rows.size())
	idx.sort_custom(func(a, b): return rows[a].radius > rows[b].radius or (rows[a].radius == rows[b].radius and a < b))
	var cols := int(ceil(sqrt(rows.size()))) + 1
	for i in idx.size():
		var def: Dictionary = rows[idx[i]]
		var col := i % cols; var row := i / cols
		var x: float = (col - (cols - 1) / 2.0) * 76.0 + rnd(-10, 10)
		var back := 90.0 if def.cls == "carrier" else 0.0
		var z: float = base_z + side.sign * (row * 72.0 + back) + rnd(-12, 12)
		var y := rnd(-35, 35) + (30.0 if def.cls == "carrier" else 0.0)
		spawn_ship(side_id, def, Vector3(x, y, z))
	if station:
		spawn_ship(side_id, D.station, Vector3(rnd(-70, 70), 40, base_z + side.sign * 190))

# ── авиация ─────────────────────────────────────────────────────
func launch_squadron(carrier: Ent.Ship, role: String) -> bool:
	if carrier.hangar.is_empty() or carrier.hangar.free <= 0 or carrier.dead: return false
	carrier.hangar.free -= 1
	var def: Dictionary = D.strike[carrier.faction][role]
	var squad := Ent.Squad.new()
	squad.uid = uid; uid += 1
	squad.kind = "squad"; squad.cls = "strike"; squad.side = carrier.side; squad.faction = carrier.faction
	squad.role = role; squad.def = def; squad.home = carrier; squad.pos = carrier.pos
	var size: int = D.squad_size[carrier.faction]
	squad.size = size
	for i in size:
		var c := Ent.Craft.new()
		c.uid = uid; uid += 1
		c.kind = "craft"; c.side = carrier.side; c.faction = carrier.faction; c.def = def
		c.cls = "strike"; c.role = role; c.squad = squad
		c.pos = carrier.pos + Vector3(rnd(-9, 9), rnd(-6, 6), rnd(-9, 9))
		c.dir = carrier.dir; c.vel = carrier.vel; c.q = carrier.q
		c.hp = def.hp; c.max_hp = def.hp; c.armor = def.armor
		c.cd = rnd(0, def.cd); c.radius = 2.6; c.slot = i
		c.ammo = int(def.get("ammo", 0) if def.get("ammo") != null else 0)
		c.reloads = int(def.get("reloads", 0) if def.get("reloads") != null else 0)
		squad.craft.append(c); state.craft.append(c)
		emit_fx("flash", c.pos)
	state.squads.append(squad)
	carrier.hangar.launched.append(squad)
	return true

func kill_squad(squad: Ent.Squad, landed: bool = false) -> void:
	if squad.dead: return
	squad.dead = true
	var carrier := squad.home
	if not landed and carrier and not carrier.dead and not carrier.hangar.is_empty():
		carrier.hangar.rebuild.append(state.time + 26.0)

func rehome(squad: Ent.Squad) -> Ent.Ship:
	var best: Ent.Ship = null; var bd := INF
	for s in state.ships:
		if s.dead or not s.hyper.is_empty() or s.side != squad.side or s.hangar.is_empty() or s.hangar.free <= 0: continue
		var d: float = s.pos.distance_squared_to(squad.pos)
		if d < bd: bd = d; best = s
	if best:
		best.hangar.free -= 1
		best.hangar.launched.append(squad)
	squad.home = best
	return best

func fire_missile(c: Ent.Craft, t: Ent.Ent) -> Ent.Proj:
	var def := c.def
	var miss := rng.randf() < float(def.get("missChance", 0.0))
	var spd: float = def.get("missileSpeed", 120)
	if def.weapon == "torp" and flags.get("doctrine", false) and not flags.get("old_pd", false):
		spd = DOC.torp_speed
	var p := spawn_projectile(c, t, def.dmg, def.weapon, spd, def.get("missileHp", 24))
	if miss:
		p.target = null
		p.dir = (p.dir + Vector3(rnd(-1, 1), rnd(-0.5, 0.5), rnd(-1, 1)) * 0.28).normalized()
		p.life = 3.5
	emit_fx("flash", c.pos)
	c.ammo -= 1
	c.reveal_until = state.time + float(D.stealth.revealFor)
	return p

func spawn_projectile(owner: Ent.Ent, target: Ent.Ent, dmg: float, weapon: String, speed: float, hp: float) -> Ent.Proj:
	var p := Ent.Proj.new()
	p.uid = uid; uid += 1
	p.kind = "proj"; p.cls = "torpedo"; p.side = owner.side; p.faction = owner.faction
	p.pos = owner.pos; p.target = target; p.dmg = dmg; p.weapon = weapon; p.speed = speed; p.owner = owner
	p.hp = hp; p.max_hp = hp; p.armor = 0; p.life = 16; p.radius = 1.8
	p.dir = (target.pos - owner.pos).normalized()
	state.proj.append(p)
	return p

# ── РЭБ ─────────────────────────────────────────────────────────
func update_ecm(dt: float) -> void:
	_fields.clear()
	for e in state.ships:
		if e.ecm.is_empty() or e.dead: continue
		var want := 0.0 if (e.ecm.mode == "off" or not e.hyper.is_empty()) else 1.0
		var E: Dictionary = ecm_prof[e.faction]
		e.ecm.power += (want - e.ecm.power) * minf(1.0, dt / E.spinUp * 2.5)
		if e.ecm.power > 0.05:
			_fields.append({"pos": e.pos + Vector3(0, -e.radius * 1.25, 0), "mode": e.ecm.mode, "side": e.side, "prof": E, "src": e})

func in_field(f: Dictionary, pos: Vector3) -> bool:
	var E: Dictionary = f.prof
	if not flags.get("doctrine", false) and absf(pos.y - f.pos.y) > E.height * 1.6: return false
	var dx: float = pos.x - f.pos.x; var dz: float = pos.z - f.pos.z
	return dx * dx + dz * dz < E.radius * E.radius

func jam_profile(pos: Vector3, side: String):
	var hit = null
	for f in _fields:
		if f.mode != "jam" or f.side == side: continue
		if in_field(f, pos): hit = f.prof; break
	if hit == null: return null
	for f in _fields:
		if f.mode != "shield" or f.side != side: continue
		if in_field(f, pos): return null
	return hit
func jammed(pos: Vector3, side: String) -> bool: return jam_profile(pos, side) != null

# ── скрытность (в срезе — заглушка «видим всё», но точки входа на месте) ──
func reveal(e: Ent.Ent) -> void:
	if e is Ent.Ship and e.stealth: e.reveal_until = state.time + float(D.stealth.revealFor)
func hidden(e: Ent.Ship) -> bool:
	return e.stealth and state.time >= e.reveal_until and not e.exposed and e.hyper.is_empty()
func craft_hidden(c: Ent.Craft) -> bool:
	return bool(c.def.get("stealth", false)) and state.time >= c.reveal_until and not c.exposed
func update_exposure() -> void:
	for e in state.ships:
		if not e.dead and not hidden(e): e.seen_pos = e.pos; e.seen_at = state.time

# ── гипер ───────────────────────────────────────────────────────
func begin_jump(e: Ent.Ship) -> bool:
	if e.dead or not e.hyper.is_empty() or e.station: return false
	var total := float(e.def.get("hyperCharge", 8)) * float(D.hyper.jumpCharge)
	e.hyper = {"left": total, "total": total}; e.move_to = null; e.forced = null
	return true
func complete_jump(e: Ent.Ship) -> void:
	e.fled = true; e.dead = true
	if e.cls == "carrier" and state.conceded == "":
		state.conceded = e.side
		order_retreat(e.side)
func order_retreat(side: String) -> int:
	if state.retreat[side]: return 0
	state.retreat[side] = true
	var n := 0
	for s in state.ships:
		if s.side == side and not s.dead and begin_jump(s): n += 1
	if ais.has(side): feed("Противник отходит", "good")
	return n
func update_hyper(e: Ent.Ship, dt: float) -> void:
	e.hyper.left -= dt
	if e.hyper.left < 2.0:
		e.vel += e.dir * float(e.def.thrust) * 2.2 * dt
		e.pos += e.vel * dt
	if e.hyper.left <= 0: complete_jump(e)

# ── урон ────────────────────────────────────────────────────────
func damage(target: Ent.Ent, amount: float, weapon: String, src) -> void:
	if target == null or target.dead or target is Ent.Squad: return
	if not (amount > 0): return
	var mult := dmg_mult(weapon, target.cls)
	if mult <= 0: return
	var before := target.hp
	target.hp -= amount * mult * (1.0 - target.armor)
	var dealt := before - maxf(0.0, target.hp)
	var who = src.owner if (src is Ent.Proj) else src
	credit(who, dealt, weapon, target)
	if target.hp <= 0: destroy(target, who)

func credit(who, dealt: float, weapon: String, target: Ent.Ent) -> void:
	if who == null or not (dealt > 0): return
	if is_zero_approx(state.stats.first_hit) and not (who is String): state.stats.first_hit = state.time
	# М7: учёт урона без остатка по ключу оружия, корабли и мелочь отдельно
	var key: String = weapon + (":ship" if target is Ent.Ship else ":small")
	metrics.dmg[key] = metrics.dmg.get(key, 0.0) + dealt
	if who is Ent.Ship: who.dealt += dealt

func destroy(e: Ent.Ent, by = null) -> void:
	if e.dead: return
	e.dead = true
	emit_fx("explosion", e.pos)
	if e is Ent.Ship:
		for k in range(3): emit_fx("flash", e.pos + Vector3(fx_rng.randf_range(-1, 1), fx_rng.randf_range(-1, 1), fx_rng.randf_range(-1, 1)) * e.radius)
		if not e.hangar.is_empty():
			for sq in e.hangar.launched: if not sq.dead: sq.home = null
		if by is Ent.Ship: by.kills += 1
		feed(("Потерян наш " if not ais.has(e.side) else "Уничтожен вражеский ") + e.name, "bad")
	if e is Ent.Craft and e.squad:
		e.squad.craft.erase(e)
		if e.squad.craft.is_empty(): kill_squad(e.squad)

# ── поиск целей ─────────────────────────────────────────────────
func unseen(e) -> bool:
	if e == null: return false
	if e is Ent.Ship: return hidden(e)
	if e is Ent.Craft: return craft_hidden(e)
	if e is Ent.Squad:
		for c in e.craft: if not c.dead and not craft_hidden(c): return false
		return true
	return false

func live_target(from: Ent.Ent, t):
	if t == null or t.dead: return null
	if not (t is Ent.Squad): return null if unseen(t) else t
	var best = null; var bd := INF
	for c in t.craft:
		if c.dead or craft_hidden(c): continue
		var d: float = c.pos.distance_squared_to(from.pos)
		if d < bd: bd = d; best = c
	return best

func nearest(from: Vector3, list: Array, max_dist: float, filter: Callable = Callable()):
	var best = null; var bd := max_dist * max_dist
	for e in list:
		if e.dead or (filter.is_valid() and not filter.call(e)): continue
		if e is Ent.Ship and hidden(e): continue
		if e is Ent.Craft and craft_hidden(e): continue
		var d: float = e.pos.distance_squared_to(from)
		if d < bd: bd = d; best = e
	return best

# Без Callable — та же логика для горячих мест (ПВО): лямбда в GDScript дорогая.
func nearest_foe(from: Vector3, list: Array, max_dist: float, foe: String):
	var best = null; var bd := max_dist * max_dist
	for e: Ent.Ent in list:
		var dx := e.pos.x - from.x
		if dx * dx >= bd: continue          # отсечка по оси: тот же ответ, без лишних длин
		if e.dead or e.side != foe: continue
		if e is Ent.Craft and craft_hidden(e): continue
		var d := e.pos.distance_squared_to(from)
		if d < bd: bd = d; best = e
	return best

func main_range(e: Ent.Ship) -> float:
	for g in e.guns: if g.role == "main" or g.role == "light": return g.def.range
	return 300.0
func leash_of(e: Ent.Ship) -> float:
	if flags.get("doctrine", false):
		if e.cls == "capital": return main_range(e) * DOC.leash_capital_k
		if e.def.id == "frigate" and ais.has(e.side): return DOC.leash_frigate_ai
	return maxf(240.0, (e.guns[0].def.range if not e.guns.is_empty() else 300.0) * 0.4)

func ship_acquire(e: Ent.Ship, reach: float = 0.0):
	var foe := enemy_of(e.side)
	if e.guns.is_empty(): return null
	var gun: Ent.Gun = e.guns[0]
	if reach == 0.0: reach = D.space_stances[e.stance].reach
	var range_: float = gun.def.range
	var fence := leash_of(e) + range_ if (e.stance == "guard" and not e.station and e.move_to == null and e.amove == null) else 0.0
	var best = null; var best_score := -INF; var near = null; var nd := INF
	for s in state.ships:
		if s.dead or s.side != foe or hidden(s): continue
		var m := dmg_mult(gun.def.type, s.cls)
		if m <= 0: continue
		var d: float = s.pos.distance_to(e.pos)
		if d < nd: nd = d; near = s
		if d > range_ * reach: continue
		if fence > 0 and s.pos.distance_to(e.anchor) > fence: continue
		var score: float = m * 1000.0 - d + (1.0 - s.hp / s.max_hp) * 400.0 + (250.0 if s.cls == "carrier" else 0.0)
		if score > best_score: best_score = score; best = s
	if best == null and e.stance == "hunt" and not e.station: return near
	return best

## Доктрина 1.2: своя цель главного калибра — пояс [D; R], эскорт с весом 0,6.
func main_acquire(e: Ent.Ship):
	var foe := enemy_of(e.side)
	var R := main_range(e); var Dz: float = R * DOC.main_dead_k
	var reach: float = D.space_stances[e.stance].reach
	var fence := leash_of(e) + R if (e.stance == "guard" and not e.station and e.move_to == null and e.amove == null) else 0.0
	var best = null; var bs := -INF; var near = null; var nd := INF
	for s in state.ships:
		if s.dead or s.side != foe or hidden(s): continue
		var m := dmg_mult("heavy", s.cls)
		if m <= 0: continue
		var d := battle_dist(s.pos, e.pos)
		if d < Dz: continue
		if d < nd: nd = d; near = s
		if d > R * reach: continue
		if fence > 0 and battle_dist(s.pos, e.anchor) > fence: continue
		var w: float = DOC.escort_weight if s.cls == "escort" else 1.0
		var sc: float = w * 1000.0 - d + (1.0 - s.hp / s.max_hp) * 400.0 + (250.0 if s.cls == "carrier" else 0.0)
		if sc > bs: bs = sc; best = s
	if best == null and e.stance == "hunt" and not e.station: return near
	return best

## Доктрина 11.6: бой плоский — все расстояния логики по горизонтали.
func battle_dist(a: Vector3, b: Vector3) -> float:
	if flags.get("doctrine", false): return Vector2(a.x - b.x, a.z - b.z).length()
	return a.distance_to(b)

func craft_acquire(c: Ent.Craft):
	var foe := enemy_of(c.side)
	if c.role == "interceptor":
		var r = nearest_foe(c.pos, state.craft, 1000, foe)
		if r == null: r = nearest_foe(c.pos, state.proj, 800, foe)
		if r == null: r = nearest(c.pos, state.ships, 1000, func(e): return e.side == foe and e.cls == "escort")
		return r
	if c.role == "bomber":
		var r = nearest(c.pos, state.ships, 2600, func(e): return e.side == foe and e.cls != "escort")
		if r == null: r = nearest(c.pos, state.ships, 2600, func(e): return e.side == foe)
		return r
	var r2 = nearest_foe(c.pos, state.craft, 800, foe)
	if r2 == null: r2 = nearest(c.pos, state.ships, 1300, func(e): return e.side == foe and e.cls == "escort")
	if r2 == null: r2 = nearest(c.pos, state.ships, 1800, func(e): return e.side == foe)
	return r2

# ── физика ──────────────────────────────────────────────────────
func face(e, dir: Vector3, dt: float, turn_rate: float) -> void:
	if e.ionized: return
	if dir.length_squared() < 1e-8: return
	var tq := quat_from_dir(dir.normalized())
	e.q = e.q.slerp(tq, clampf(turn_rate * dt, 0, 1))
	e.dir = e.q * Vector3(0, 0, -1)

func thrust_to(e, desired_vel: Vector3, dt: float, thrust: float, rev: float = 0.3) -> void:
	if e.ionized: e.thrust_now = 0; return
	var v: Vector3 = desired_vel - e.vel
	var need := v.length()
	if need < 1e-4:
		if e is Ent.Ship: e.thrust_now = 0
		return
	v /= need
	var align := maxf(0.0, e.dir.dot(v))
	var power := thrust * (rev + (1.0 - rev) * align)
	var step := minf(need, power * dt)
	e.vel += v * step
	if e is Ent.Ship: e.thrust_now = step / maxf(1e-4, thrust * dt)

func integrate(e, dt: float) -> void:
	e.pos += e.vel * dt
	if e.pos.x > FIELD: e.pos.x = FIELD; if e.vel.x > 0: e.vel.x *= -0.3
	if e.pos.x < -FIELD: e.pos.x = -FIELD; if e.vel.x < 0: e.vel.x *= -0.3
	if e.pos.z > FIELD: e.pos.z = FIELD; if e.vel.z > 0: e.vel.z *= -0.3
	if e.pos.z < -FIELD: e.pos.z = -FIELD; if e.vel.z < 0: e.vel.z *= -0.3
	if e.pos.y > 500: e.pos.y = 500; if e.vel.y > 0: e.vel.y *= -0.3
	if e.pos.y < -500: e.pos.y = -500; if e.vel.y < 0: e.vel.y *= -0.3

func arrive_speed(e: Ent.Ship, dist: float, vmax: float) -> float:
	if dist <= 0: return 0.0
	var aB: float = float(e.def.thrust) * REV * 0.85
	return minf(minf(vmax, sqrt(2.0 * aB * dist)), dist * 1.5)
func arrive(e: Ent.Ship, goal: Vector3, vmax: float) -> Vector3:
	var v := goal - e.pos
	var d := v.length()
	if d < 0.5: return Vector3.ZERO
	return v * (arrive_speed(e, d, vmax) / d)

func approach(e: Ent.Ship, t: Ent.Ent, range0: float, vmax: float) -> Vector3:
	var def := e.def
	var want: float
	if t is Ent.Craft: want = minf(range0 * 0.68, def.pd.range * 0.7 if def.get("pd") != null else range0 * 0.5)
	elif e.jam != null: want = e.jam.lockRange * 0.8
	else: want = range0 * 0.68
	var v := t.pos - e.pos
	var d := v.length()
	if d == 0: d = 1
	v /= d
	if d > want * 1.08: return v * arrive_speed(e, d - want, vmax if vmax > 0 else float(def.maxSpeed))
	if d < want * 0.55: return v * (-float(def.maxSpeed) * 0.5)
	if def.cls == "escort": return v.cross(UP).normalized() * (float(def.maxSpeed) * 0.45)
	return Vector3.ZERO

func guard_station(e: Ent.Ship, t: Ent.Ent, range0: float) -> Vector3:
	var want: float = e.jam.lockRange * 0.8 if (e.jam != null and t is Ent.Ship) else range0 * 0.68
	var v := e.pos - t.pos
	var d := v.length()
	if d == 0: d = 1
	var r := want if (d > want * 1.08 or d < want * 0.55) else d
	var p := t.pos + v * (r / d)
	var v2 := p - e.anchor
	var L := leash_of(e)
	if v2.length() > L: p = e.anchor + v2 * (L / v2.length())
	return Vector3.ZERO if p.distance_to(e.pos) < 10 else arrive(e, p, e.def.maxSpeed)

# ── шаг корабля ─────────────────────────────────────────────────
func update_ship(e: Ent.Ship, dt: float) -> void:
	if not e.hyper.is_empty(): update_hyper(e, dt); return
	e.ionized = e.ion_until > 0 and state.time < e.ion_until
	if e.def.get("flee") != null and e.hp / e.max_hp < float(e.def.flee) and not e.station:
		begin_jump(e); return
	var tp := Time.get_ticks_usec() if prof_on else 0
	e.retarget -= dt
	if e.target and (e.target.dead or unseen(e.target)): e.target = null
	if e.forced and (e.forced.dead or unseen(e.forced)):
		e.forced = null
		if e.guard_of == null: e.anchor = e.pos
	e.jam = jam_profile(e.pos, e.side) if not e.guns.is_empty() else null
	var doc_cap: bool = flags.get("doctrine", false) and e.cls == "capital"
	if doc_cap:
		ship_targets_doctrine(e)
	else:
		if e.jam_shot and e.jam_shot != e.target: e.jam_shot = null
		if e.target == null or e.retarget <= 0 or (e.forced and e.target != e.forced and not (e.forced is Ent.Squad) and e.jam_shot == null):
			e.target = live_target(e, e.forced)
			if e.target == null: e.target = ship_acquire(e)
			e.jam_shot = null
			e.retarget = rnd(0.8, 1.6)
	var def := e.def
	if not e.station:
		var desired := Vector3.ZERO
		var range0 := main_range(e) if not e.guns.is_empty() else 300.0
		var vmax: float = e.group_speed if e.group_speed > 0 else float(def.maxSpeed)
		if e.guard_of and (e.guard_of.dead or not e.guard_of.hyper.is_empty()): e.guard_of = null; e.anchor = e.pos
		if e.guard_of: e.anchor = e.guard_of.pos + e.guard_off
		if doc_cap:
			desired = capital_desired(e, dt, vmax)
		else:
			var fighting: bool = e.amove != null and e.target != null and not e.target.dead and e.pos.distance_to(e.target.pos) < range0 * 1.3
			var goal = e.move_to if e.move_to != null else (e.amove if (e.amove != null and not fighting) else null)
			if goal != null:
				desired = arrive(e, goal, vmax)
				var d: float = e.pos.distance_to(goal); var v := e.vel.length()
				e.arrive_t = e.arrive_t + dt if (d < 60 and v < 4) else 0.0
				if (d < 8 and v < 3) or e.arrive_t > 2.5:
					if e.guard_of == null: e.anchor = goal
					if e.move_to != null: e.move_to = null
					else: e.amove = null
					e.group_speed = 0; e.arrive_t = 0
			elif e.target and (e.forced or fighting or e.stance == "hunt"):
				desired = approach(e, e.target, range0, vmax)
			elif e.target and e.stance == "guard":
				desired = guard_station(e, e.target, range0)
			elif (e.stance == "guard" or (e.stance == "hunt" and e.guns.is_empty())) and e.pos.distance_to(e.anchor) > 12:
				desired = arrive(e, e.anchor, vmax)
		if prof_on: tp = _pt("  ship:target+move", tp)
		# расталкивание — своих и чужих (C87, C59). Сравнение квадратов первым —
		# тот же результат, что у JS, только без корня на дальних парах.
		var ms: float = def.maxSpeed
		# Отсечка по осям x и z раньше длины: результат тот же, что у JS
		# (те же пары, тот же порядок сложения, живые позиции соседей).
		var ep := e.pos; var eh := e.hull; var es := e.side
		var lim := eh + max_hull * 1.15 + 1.0
		var flat: bool = flags.get("doctrine", false)
		for o: Ent.Ship in state.ships:
			var op := o.pos
			var dx := ep.x - op.x
			if dx > lim or dx < -lim: continue
			var dz := ep.z - op.z
			if dz > lim or dz < -lim: continue
			if o == e or o.dead: continue
			var foe := o.side != es
			var mn := (o.hull + eh) * (1.15 if foe else 1.0)
			var dv := ep - op
			if flat: dv.y = 0
			var dd2 := dv.length_squared()
			if dd2 >= mn * mn: continue
			var dd := sqrt(dd2)
			if dd > 0.01:
				desired += dv / dd * ((mn - dd) / mn * ms * (1.1 if foe else 0.8))
		if prof_on: tp = _pt("  ship:push", tp)
		if not e.drift:
			thrust_to(e, desired, dt, def.thrust, REV)
			var vlim: float = ms * 1.25
			if e.vel.length() > vlim and not (e.exit_until > state.time): e.vel = e.vel.normalized() * vlim
		else:
			e.thrust_now = 0
		var look := Vector3.ZERO
		if doc_cap:
			look = capital_look(e, desired)
		elif e.drift and e.target:
			look = e.target.pos - e.pos
		elif e.target and e.pos.distance_to(e.target.pos) < (main_range(e) if not e.guns.is_empty() else 400.0) * 1.5:
			look = e.target.pos - e.pos
		elif desired.length_squared() > 1:
			look = desired
		elif e.vel.length_squared() > 1:
			look = e.vel
		face(e, look, dt, def.turn)
		integrate(e, dt)
		if prof_on: _pt("  ship:look+face+integrate", tp)
		if doc_cap or (flags.get("doctrine", false)): e.pos.y = e.pos.y  # высота — картинка (11.6)
	elif e.target:
		face(e, e.target.pos - e.pos, dt, def.turn)
	var tq := Time.get_ticks_usec() if prof_on else 0
	fire_guns(e, dt)
	fire_sec(e, dt)
	if prof_on: tq = _pt("  ship:guns+sec", tq)
	fire_pd(e, dt)
	if prof_on: _pt("  ship:pd", tq)

func fire_guns(e: Ent.Ship, dt: float) -> void:
	var doc: bool = flags.get("doctrine", false)
	for g in e.guns:
		var slow := 1.0
		if doc and g.role == "main" and e.jam != null: slow = 1.0 / float(DOC.main_slow.get(e.jam.fac, DOC.main_slow_default))
		g.cd -= dt * slow
		var t = e.target
		if doc and g.role == "main": t = e.main_target
		if t == null or t.dead: continue
		var d := battle_dist(e.pos, t.pos)
		if d > g.def.range: continue
		if doc and g.role == "main" and d < g.def.range * DOC.main_dead_k: continue  # мёртвая зона ДО накачки
		if dmg_mult(g.def.type, t.cls) <= 0: continue
		var to: Vector3 = (t.pos - e.pos) / (d if d > 0 else 1.0)
		if e.dir.dot(to) < (-0.3 if e.station else 0.25): continue
		if e.jam != null and d > e.jam.lockRange and not (doc and g.role == "main"): continue
		if g.def.get("charge") != null and g.cd <= g.def.charge and g.cd > 0:
			if state.time - g.charge_fx > 0.09: g.charge_fx = state.time; emit_fx("charge", e.pos)
		if g.cd > 0: continue
		g.cd = g.def.cd
		reveal(e)
		fire_main_gun(e, g, t)

func fire_main_gun(e: Ent.Ship, g: Ent.Gun, t: Ent.Ent) -> void:
	if is_zero_approx(e.fired_at): e.fired_at = state.time
	if g.def.type == "missile":
		for i in int(g.def.get("salvo", 1)):
			var p := spawn_projectile(e, t, g.def.dmg * ai_mul(e.side), "missile", 130, 26)
			p.dir = (p.dir + Vector3(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)) * float(g.def.get("spread", 0.05))).normalized()
			p.wobble = rnd(0, 6.28)
		return
	if g.def.type == "heavy" and is_zero_approx(state.stats.first_gun) and t is Ent.Ship: state.stats.first_gun = state.time
	emit_fx("laser", e.pos, t.pos)
	damage(t, g.def.dmg * ai_mul(e.side), g.def.type, e)

## Доктрина 1.3: батарея — своя цель, круговой сектор, только корабли.
func fire_sec(e: Ent.Ship, dt: float) -> void:
	if e.sec.is_empty(): return
	var R: float = e.sec[0].def.range
	var t := e.sec_target
	if t == null or t.dead or hidden(t) or battle_dist(t.pos, e.pos) > R:
		t = null
		if e.forced is Ent.Ship and not e.forced.dead and battle_dist(e.forced.pos, e.pos) <= R: t = e.forced
		else:
			var foe := enemy_of(e.side); var bd := R * R
			for s in state.ships:
				if s.dead or s.side != foe or hidden(s): continue
				var dv: Vector3 = s.pos - e.pos; dv.y = 0
				var d2 := dv.length_squared()
				if d2 < bd: bd = d2; t = s
		e.sec_target = t
	for g in e.sec:
		g.cd -= dt
		if t == null or g.cd > 0: continue
		var d := battle_dist(e.pos, t.pos)
		if e.jam != null and d > e.jam.lockRange: continue
		g.cd = g.def.cd
		reveal(e)
		emit_fx("aux", e.pos, t.pos)
		damage(t, g.def.dmg * ai_mul(e.side), "sec", e)

func fire_pd(e: Ent.Ship, dt: float) -> void:
	if e.def.get("pd") == null: return
	var pd: Dictionary = e.def.pd
	var foe := enemy_of(e.side)
	for i in e.pd_cd.size():
		e.pd_cd[i] -= dt
		if e.pd_cd[i] > 0: continue
		var t = nearest_foe(e.pos, state.proj, pd.range, foe)
		if t == null: t = nearest_foe(e.pos, state.craft, pd.range, foe)
		if t == null: e.pd_cd[i] = 0.2; continue
		e.pd_cd[i] = pd.cd * rnd(0.85, 1.2)
		var jp = jam_profile(e.pos, e.side)
		var mult: float = jp.pdPenalty if jp != null else 1.0
		reveal(e)
		emit_fx("shot", e.pos, t.pos)
		damage(t, pd.dmg * mult, "pd", e)

# ── доктрина: тяжёлый держит пояс (09, раздел 2) ─────────────────
func ship_targets_doctrine(e: Ent.Ship) -> void:
	if e.main_target and (e.main_target.dead or hidden(e.main_target)): e.main_target = null
	if e.main_target == null or e.retarget <= 0:
		var R := main_range(e)
		var ft = live_target(e, e.forced)
		if ft is Ent.Ship and battle_dist(ft.pos, e.pos) >= R * DOC.main_dead_k and battle_dist(ft.pos, e.pos) <= R:
			e.main_target = ft
		else:
			e.main_target = main_acquire(e)
		e.retarget = rnd(0.8, 1.6)
	e.target = e.main_target

func nearest_foe_ship_d(e: Ent.Ship) -> Array:
	var foe := enemy_of(e.side); var best = null; var bd := INF
	for s in state.ships:
		if s.dead or s.side != foe or hidden(s): continue
		var d := battle_dist(s.pos, e.pos)
		if d < bd: bd = d; best = s
	return [best, bd]

func capital_desired(e: Ent.Ship, dt: float, vmax: float) -> Vector3:
	var R := main_range(e); var Dz: float = R * DOC.main_dead_k
	var nf := nearest_foe_ship_d(e)
	var near: Ent.Ship = nf[0]; var dn: float = nf[1]
	if e.move_to != null:
		e.backing = false
		var goal: Vector3 = e.move_to
		var dd := battle_dist(e.pos, goal)
		e.arrive_t = e.arrive_t + dt if (dd < 60 and e.vel.length() < 4) else 0.0
		if (dd < 8 and e.vel.length() < 3) or e.arrive_t > 2.5:
			if e.guard_of == null: e.anchor = goal
			e.move_to = null; e.group_speed = 0; e.arrive_t = 0
		return arrive(e, goal, vmax)
	if e.stance == "hold": e.backing = false; return Vector3.ZERO
	# вплотную → отход (2.4, 2.6); «не оторваться» помнится по врагу
	if not flags.get("old_approach", false) and near and dn < Dz and e.futile.get(near.uid, -1.0) < state.time:
		if not e.backing or e.futile_uid != near.uid:
			e.backing = true; e.futile_uid = near.uid; e.futile_clock = 0.0; e.futile_d0 = dn
		var away := Vector3(e.pos.x - near.pos.x, 0, e.pos.z - near.pos.z).normalized()
		var axb := side_axis(e.side) * -1.0     # тыловая ось
		var dirv := (away + axb * 0.5)
		var fwd := -axb
		var f := dirv.dot(fwd)
		if f > 0: dirv -= fwd * f                # вперёд отход не ведёт
		if dirv.length() < 0.3: return Vector3.ZERO     # прижат
		var vel_away := e.vel.dot(away)
		if vel_away >= 0.5 * float(e.def.maxSpeed):
			e.futile_clock += dt
			if e.futile_clock >= DOC.retreat_futile_s:
				if dn - e.futile_d0 < DOC.retreat_futile_gain:
					e.futile[near.uid] = state.time + 15.0
					e.backing = false
					return Vector3.ZERO
				e.futile_clock = 0.0; e.futile_d0 = dn
		if absf(e.pos.x) > FIELD - 200 or absf(e.pos.z) > FIELD - 200: return Vector3.ZERO
		return dirv.normalized() * float(e.def.maxSpeed)
	if e.backing and near and dn < R * DOC.belt_back_off_k: return Vector3.ZERO if dn >= Dz else Vector3.ZERO
	e.backing = false
	var clear: bool = not near or dn >= R * DOC.belt_clear_k
	var t := e.main_target
	if t:
		var d := battle_dist(t.pos, e.pos)
		if d > R * DOC.belt_far_k and clear:
			var x: float = d - R * DOC.belt_work_k
			var rel := (e.pos - t.pos); rel.y = 0; rel = rel.normalized()
			var v_close := maxf(0.0, t.vel.dot(rel))
			x = x * float(e.def.maxSpeed) / (float(e.def.maxSpeed) + v_close)
			var to := -rel
			var sp := arrive_speed(e, x, vmax)
			if near: sp = minf(sp, arrive_speed(e, dn - R * DOC.belt_clear_k, vmax))
			var p := e.pos + to * sp
			if e.stance == "guard":
				var v2 := p - e.anchor; var L := leash_of(e)
				if v2.length() > L: return Vector3.ZERO
			return to * sp
		return Vector3.ZERO
	if e.stance == "guard" and battle_dist(e.pos, e.anchor) > 12 and clear:
		var v := arrive(e, e.anchor, vmax)
		if near: v = v.limit_length(arrive_speed(e, dn - R * DOC.belt_clear_k, vmax))
		return v
	return Vector3.ZERO

func capital_look(e: Ent.Ship, desired: Vector3) -> Vector3:
	var R := main_range(e)
	if e.main_target and battle_dist(e.pos, e.main_target.pos) < R * 1.5: return e.main_target.pos - e.pos
	var foe := enemy_of(e.side)
	var best = null; var bd := R * 1.5
	for s in state.ships:
		if s.dead or s.side != foe or s.cls != "capital" or hidden(s): continue
		var d := battle_dist(s.pos, e.pos)
		if d < bd: bd = d; best = s
	if best: return best.pos - e.pos
	if desired.length_squared() > 1: return desired
	if e.vel.length_squared() > 1: return e.vel
	return Vector3.ZERO

func side_axis(side: String) -> Vector3:
	return Vector3(0, 0, -sides[side].sign)   # «на противника»

# ── авиация: шаг машины ─────────────────────────────────────────
func fly_toward(c: Ent.Craft, aim: Vector3, dt: float, throttle: float) -> void:
	var v := aim - c.pos
	var d := v.length()
	if d == 0: d = 1
	v /= d
	face(c, v, dt, c.def.turn)
	thrust_to(c, c.dir * (float(c.def.maxSpeed) * throttle), dt, c.def.thrust)
	var lim: float = float(c.def.maxSpeed) * 1.15
	if c.vel.length() > lim: c.vel = c.vel.normalized() * lim
	integrate(c, dt)

func leave_field(c: Ent.Craft, dt: float) -> void:
	c.leave_t += dt
	var sign: float = sides[c.side].sign
	fly_toward(c, Vector3(c.pos.x, c.pos.y, sign * (FIELD + 400)), dt, 1)
	if absf(c.pos.z) < FIELD - 40 and c.leave_t < 25: return
	c.dead = true
	var squad = c.squad
	if squad == null: return
	squad.craft.erase(c)
	if squad.craft.is_empty(): kill_squad(squad, true)

func update_craft(c: Ent.Craft, dt: float) -> void:
	var squad = c.squad
	if c.target and (c.target.dead or unseen(c.target)): c.target = null
	if c.leaving: leave_field(c, dt); return
	if c.def.weaponKind == "missile":
		if c.reloading > 0:
			c.reloading -= dt
			if c.reloading <= 0: c.ammo = int(c.def.ammo)
			else:
				var away: Vector3 = squad.home.pos if (squad and squad.home and not squad.home.dead) else Vector3.ZERO
				fly_toward(c, away, dt, 0.8)
				return
		elif c.ammo <= 0:
			if c.reloads > 0:
				c.reloads -= 1; c.reloading = c.def.reloadTime
				return
			if squad and not squad.recall: squad.recall = true
	if squad and squad.recall:
		var home: Ent.Ship = squad.home
		if home == null or home.dead: home = rehome(squad)
		if home:
			if c.pos.distance_to(home.pos) < home.radius * 2.4:
				c.dead = true
				squad.craft.erase(c)
				if squad.craft.is_empty():
					home.hangar.free = mini(home.hangar.bays, home.hangar.free + 1)
					kill_squad(squad, true)
				return
			fly_toward(c, home.pos, dt, 1)
			return
		squad.recall = false
		if c.def.weaponKind == "missile" and c.ammo <= 0 and not (c.reloads > 0):
			c.leaving = true
			return
	if c.target == null:
		c.target = live_target(c, squad.target if squad else null)
		if c.target == null: c.target = craft_acquire(c)
	if c.target == null:
		if squad and squad.move_to != null: fly_toward(c, squad.move_to, dt, 0.9); return
		var anchor: Vector3 = squad.home.pos if (squad and squad.home and not squad.home.dead) else Vector3.ZERO
		var t0: float = state.time
		fly_toward(c, anchor + Vector3(sin(t0 * 0.35 + c.slot) * 130, cos(t0 * 0.3 + c.slot) * 40, cos(t0 * 0.35 + c.slot) * 130), dt, 0.7)
		return
	var t: Ent.Ent = c.target
	var d := c.pos.distance_to(t.pos)
	var wr: float = c.def.range
	if c.role == "bomber":
		if c.phase == "break":
			if state.time > c.break_until: c.phase = "out"
			else:
				var aw := (c.pos - t.pos).normalized() * 400.0 + c.pos + Vector3(0, 90, 0)
				fly_toward(c, aw, dt, 1)
				return
		fly_toward(c, t.pos, dt, 1)
		c.cd -= dt
		if d < wr and c.cd <= 0 and c.ammo > 0:
			c.cd = c.def.cd
			fire_missile(c, t)
			c.phase = "break"; c.break_until = state.time + rnd(3.0, 4.2)
		if d < t.radius + 30: c.phase = "break"; c.break_until = state.time + 3
		return
	var desired_d: float = minf(wr * 0.8, t.radius + 34) if t is Ent.Ship else wr * 0.6
	var aim: Vector3
	if d < desired_d * 0.75:
		aim = (c.pos - t.pos).normalized() * 260.0 + c.pos
		aim.x += sin(state.time + c.slot * 2) * 60; aim.y += cos(state.time * 0.8 + c.slot) * 40
	else:
		aim = t.pos
		aim.x += sin(state.time * 1.3 + c.slot * 1.7) * 20; aim.y += cos(state.time * 1.1 + c.slot * 2.3) * 16
	fly_toward(c, aim, dt, 1)
	c.cd -= dt
	if d <= wr and c.cd <= 0:
		var to := (t.pos - c.pos) / (d if d > 0 else 1.0)
		if c.dir.dot(to) > 0.7:
			c.cd = c.def.cd
			if c.def.weaponKind == "missile":
				if c.ammo > 0: fire_missile(c, t)
			else:
				c.reveal_until = state.time + float(D.stealth.revealFor)
				emit_fx("tracer", c.pos, t.pos)
				damage(t, c.def.dmg * ai_mul(c.side), c.def.weapon, c)

func update_projectile(p: Ent.Proj, dt: float) -> void:
	p.life -= dt
	if p.life <= 0: destroy(p); return
	if p.target and p.target.dead: p.target = null
	if p.target and bool(D.ecm_base.missileBlind) and jammed(p.pos, p.side): p.blind = true
	if p.target and not p.blind:
		var to := (p.target.pos - p.pos).normalized()
		p.dir = p.dir.lerp(to, clampf((1.1 if p.weapon == "torp" else 1.8) * dt, 0, 1)).normalized()
	p.pos += p.dir * p.speed * dt
	if p.wobble >= 0:
		p.wobble += dt * 9
		p.pos.y += sin(p.wobble) * 6 * dt
	if p.target and p.pos.distance_to(p.target.pos) < p.target.radius + 5:
		emit_fx("explosion", p.pos)
		damage(p.target, p.dmg, p.weapon, p.owner)
		destroy(p)

# ── ИИ по ролям (легаси C59) и доктрина (09, раздел 7) ───────────
func ai_role(s: Ent.Ship) -> String:
	if s.station: return "station"
	if s.cls == "carrier": return "carrier"
	if not s.ecm.is_empty(): return "ecm"
	if s.cls == "capital": return "heavy"
	return "frigate" if s.def.id == "frigate" else "corvette"
func share(s: Ent.Ship) -> float:
	# 09, 7.2: от первого uid СВОЕЙ стороны (иначе зеркальный бой меряет сторону)
	var u: int = s.uid - (ais[s.side].uid0 if flags.get("share_own", true) and ais.has(s.side) else 0)
	return fmod(u * 0.6180339, 1.0)

func center(list: Array) -> Vector3:
	var c := Vector3.ZERO
	for s in list: c += s.pos
	return c / maxf(1.0, list.size())

func update_ai(dt: float) -> void:
	# Снимок начала шага: оба ИИ решают по одному и тому же миру (05, 2.18)
	var order: Array = ais.keys()
	for sd in order: ai_tick(ais[sd], dt)

func ai_tick(ai: Dictionary, dt: float) -> void:
	ai.next -= dt
	if ai.next > 0: return
	var DIFF: Dictionary = D.difficulty[ai.diff]
	ai.next = rnd(2.5, 4) * float(DIFF.tempo)
	var side: String = ai.side
	var all := state.ships.filter(func(s): return not s.dead and s.side == side)
	var mine := all.filter(func(s): return s.hyper.is_empty())
	var foes := state.ships.filter(func(s): return not s.dead and s.side != side and not hidden(s))
	if mine.is_empty() or state.retreat[side]: return
	var my_ecm := mine.filter(func(s): return not s.ecm.is_empty())
	if not my_ecm.is_empty():
		var under := false
		for s in mine: if jammed(s.pos, s.side): under = true; break
		for s in my_ecm: s.ecm.mode = "shield" if under else "jam"
	var enemy_craft := 0; var my_craft := 0
	for c in state.craft:
		if c.side != side and not craft_hidden(c): enemy_craft += 1
		elif c.side == side: my_craft += 1
	var foe_big := false
	for f in foes: if f.cls != "escort": foe_big = true; break
	for s in mine:
		if s.hangar.is_empty() or s.hangar.free <= 0: continue
		var role := "fighter"
		if enemy_craft > my_craft + 4: role = "interceptor"
		elif foe_big: role = "bomber"
		launch_squadron(s, role)
	if foes.is_empty(): return
	var hp_of := func(list: Array) -> float:
		var a := 0.0
		for s in list: a += maxf(0.0, s.hp)
		return a
	var my_hp: float = hp_of.call(all)
	var foe_hp: float = hp_of.call(state.ships.filter(func(s): return not s.dead and s.side != side))
	ai.hp0 = maxf(ai.hp0, my_hp)
	var armed := mine.filter(func(s): return not s.station and not s.guns.is_empty())
	var broken := not armed.is_empty() and armed.all(func(s): return s.hp / s.max_hp < 0.3)
	if ((my_hp < ai.hp0 * 0.33 and my_hp * 2 < foe_hp) or broken) and mine.any(func(s): return not s.station):
		order_retreat(side); return
	var free := mine.filter(func(s): return not s.station)
	var heavies := free.filter(func(s): return ai_role(s) == "heavy")
	var F := center(foes)
	if not heavies.is_empty(): ai.had_heavy = true
	var foe_heavy := foes.any(func(f): return f.cls == "capital" and not f.guns.is_empty())
	if ai.had_heavy and heavies.is_empty() and foe_heavy and my_hp < foe_hp and not free.is_empty():
		order_retreat(side); return
	if flags.get("doctrine", false) and not flags.get("old_ai", false):
		ai_doctrine(ai, free, heavies, foes, F, DIFF); return
	var line := heavies.filter(func(s): return s.hp / s.max_hp >= 0.3)
	var C: Vector3
	if not line.is_empty(): C = center(line)
	else:
		var own := center(free if not free.is_empty() else mine)
		var back := own - F; back.y = 0
		if back.length_squared() < 1: back = Vector3(0, 0, sides[side].sign)
		back = back.normalized()
		var reach := 300.0
		for s in heavies: reach = maxf(reach, main_range(s))
		C = F + back * maxf(500.0, reach * 0.68); C.y = own.y
	var axis := F - C; axis.y = 0
	if axis.length_squared() < 1: axis = Vector3(0, 0, -sides[side].sign)
	var ax := axis.normalized(); var lat := Vector3(-ax.z, 0, ax.x)
	var spot := func(bk: float, la: float, y: float) -> Vector3:
		var p: Vector3 = C + ax * bk + lat * la; p.y = C.y + y; return p
	var maxR := 300.0
	for s in heavies: maxR = maxf(maxR, main_range(s))
	var threat := func(f: Ent.Ship) -> float:
		var a := 0.0
		for g in f.guns: a += float(g.def.dmg) * float(g.def.get("salvo", 1)) / float(g.def.cd)
		return a + (40.0 if not f.hangar.is_empty() else 0.0) + (120.0 if (not f.ecm.is_empty() and f.ecm.power > 0.5) else (40.0 if not f.ecm.is_empty() else 0.0))
	var focus_score := func(f: Ent.Ship) -> float:
		var d := f.pos.distance_to(C)
		var sc: float = threat.call(f) * dmg_mult("heavy", f.cls) * (1.0 - f.armor) / maxf(1.0, f.hp)
		return sc * 0.3 if d > maxR * 1.3 else sc
	var best_sc := -INF; var best = null
	for f in foes:
		var sc: float = focus_score.call(f)
		if sc > best_sc: best_sc = sc; best = f
	if ai.focus == null or ai.focus.dead or hidden(ai.focus) or ai.focus.pos.distance_to(C) > maxR * 1.8 or focus_score.call(ai.focus) * 1.6 < best_sc:
		ai.focus = best
	var slow_heavy := 0.0
	if heavies.size() > 1:
		slow_heavy = INF
		for s in heavies: slow_heavy = minf(slow_heavy, float(s.def.maxSpeed))
	var carriers := free.filter(func(s): return ai_role(s) == "carrier")
	var leaderless := heavies.is_empty()
	var threats := state.squads.filter(func(q): return not q.dead and q.side != side and not unseen(q) and free.any(func(s): return s.pos.distance_to(q.pos) < 750))
	var fi := 0; var ci := 0; var vi := 0
	var corv_n := free.filter(func(s): return ai_role(s) == "corvette").size()
	for s in free:
		var r := ai_role(s); var hp: float = s.hp / s.max_hp
		s.stance = "guard"
		if r == "heavy" and hp < 0.18: begin_jump(s); continue
		if hp < 0.3 and r != "carrier":
			s.forced = null; s.guard_of = null; s.group_speed = 0
			s.anchor = spot.call(-560, (share(s) - 0.5) * 300, 0.0); continue
		if r == "heavy":
			s.guard_of = null; s.group_speed = slow_heavy
			if ai.focus and share(s) < float(DIFF.focus): s.forced = ai.focus
			elif s.forced and not (s.forced is Ent.Ship): s.forced = null
			s.stance = "hunt"
		elif r == "carrier":
			var close := foes.any(func(f): return f.pos.distance_to(s.pos) < 520)
			s.anchor = spot.call(-760.0 if close else -440.0, (ci - (carriers.size() - 1) / 2.0) * 260, 30); ci += 1
		elif r == "ecm":
			s.anchor = spot.call(330, (share(s) - 0.5) * 260, 0.0)
		elif leaderless and (r == "frigate" or (r == "corvette" and threats.is_empty())):
			s.guard_of = null
			if ai.focus and share(s) < float(DIFF.focus): s.forced = ai.focus
			elif s.forced and not (s.forced is Ent.Ship): s.forced = null
			s.stance = "hunt"
		elif r == "frigate":
			var ward: Ent.Ship = carriers[0] if (fi == 0 and not carriers.is_empty()) else (heavies[fi % heavies.size()] if not heavies.is_empty() else (carriers[0] if not carriers.is_empty() else null))
			escort(s, ward, fi, spot); fi += 1
			s.forced = null
		else:
			var q = null; var qd := INF
			for t in threats:
				var dd: float = t.pos.distance_to(s.pos)
				if dd < qd: qd = dd; q = t
			if q and share(s) < 0.7: s.guard_of = null; s.forced = q; s.anchor = s.pos
			else:
				if s.forced is Ent.Squad: s.forced = null
				if not heavies.is_empty(): escort(s, heavies[vi % heavies.size()], vi + 3, spot)
				else: s.guard_of = null; s.anchor = spot.call(120, (vi - (corv_n - 1) / 2.0) * 110, 0.0)
				vi += 1

func escort(s: Ent.Ship, ward: Ent.Ship, n: int, spot: Callable) -> void:
	if ward == null or ward == s: s.guard_of = null; s.anchor = spot.call(80, (share(s) - 0.5) * 300, 0.0); return
	if s.guard_of == ward: return
	var a := n * 2.1 + 0.5
	s.guard_of = ward
	s.guard_off = Vector3(cos(a), 0, sin(a)) * (ward.hull + s.hull + 60)

## Доктрина, раздел 5 и 7 (упрощено для пробы): линия на L = 0,85 R_line от
## чужих тяжёлых, лёгкие шеренги впереди, носители позади; места — участками.
func ai_doctrine(ai: Dictionary, free: Array, heavies: Array, foes: Array, F: Vector3, DIFF: Dictionary) -> void:
	var side: String = ai.side
	var foe_heavy := foes.filter(func(f): return f.cls == "capital")
	var Fh := center(foe_heavy) if not foe_heavy.is_empty() else F
	var line := heavies.filter(func(s): return s.hp / s.max_hp >= 0.3)
	var Rl := 780.0
	if not line.is_empty():
		Rl = INF
		for s in line: Rl = minf(Rl, main_range(s))
	var L: float = DOC.line_L_k * Rl
	var own := center(line if not line.is_empty() else free)
	var axis := Fh - own; axis.y = 0
	if axis.length_squared() < 1: axis = side_axis(side)
	var ax := axis.normalized()
	if ai.line_ax != null:   # поворот оси ≤ 15° за тик
		var a0: Vector3 = ai.line_ax
		var ang := a0.signed_angle_to(ax, UP)
		ax = a0.rotated(UP, clampf(ang, -deg_to_rad(15), deg_to_rad(15)))
	var P := Fh - ax * L; P.y = 0
	if ai.line_p != null:     # сдвиг ≤ 120 за тик
		var p0: Vector3 = ai.line_p
		P = p0 + (P - p0).limit_length(DOC.line_shift_max)
	ai.line_p = P; ai.line_ax = ax
	var lat := Vector3(-ax.z, 0, ax.x)
	var place := func(list: Array, depth: float, step: float) -> void:
		# раздача мест по положению вдоль фронта (5.4), а не по номеру
		var srt := list.duplicate()
		srt.sort_custom(func(a, b): return a.pos.dot(lat) < b.pos.dot(lat))
		for i in srt.size():
			var s: Ent.Ship = srt[i]
			s.anchor = P + ax * depth + lat * ((i - (srt.size() - 1) / 2.0) * step)
	var ok := func(s): return s.hp / s.max_hp >= 0.3
	var hv := free.filter(func(s): return ai_role(s) == "heavy" and ok.call(s))
	var fr := free.filter(func(s): return (ai_role(s) == "frigate" or ai_role(s) == "ecm") and ok.call(s))
	var cv := free.filter(func(s): return ai_role(s) == "corvette" and ok.call(s))
	var cr := free.filter(func(s): return ai_role(s) == "carrier")
	var slow := INF
	for s in hv: slow = minf(slow, float(s.def.maxSpeed))
	for s in free:
		s.stance = "guard"; s.guard_of = null
		var r := ai_role(s)
		if r == "heavy" and s.hp / s.max_hp < 0.18: begin_jump(s); continue
		if not ok.call(s) and r != "carrier": s.forced = null; s.anchor = P - ax * 560.0 + lat * ((share(s) - 0.5) * 300)
		if r == "heavy": s.group_speed = slow if hv.size() > 1 else 0.0
	place.call(hv, 0.0, 170.0)
	place.call(fr, DOC.line_frigate_k * L, 90.0)
	place.call(cv, DOC.line_corvette_k * L, 70.0)
	place.call(cr, -440.0, 260.0)
	# общая цель тяжёлых — только в поясе у большинства (7.3), без подробностей пробы
	ai.focus = null

# ── «нечем бить» и конец боя ────────────────────────────────────
func can_hurt(side: String) -> bool:
	for s in state.ships:
		if s.dead or s.side != side or not s.hyper.is_empty(): continue
		if not s.guns.is_empty() or not s.sec.is_empty(): return true
	for c in state.craft:
		if not c.dead and c.side == side and not c.leaving: return true
	return false
func side_out(side: String) -> bool:
	for s in state.ships:
		if not s.dead and s.side == side and not (state.retreat[side] and s.station): return false
	return true
func check_teeth() -> void:
	for sd in ["attacker", "defender"]:
		if not state.retreat[sd] and not can_hurt(sd) and state.ships.any(func(s): return not s.dead and s.side == sd):
			order_retreat(sd)
func check_end() -> void:
	var a := side_out("attacker"); var d := side_out("defender")
	if a or d:
		state.ended = true
		state.result = "draw" if (a and d) else ("defender" if a else "attacker")

# ── замеры доктрины (09, 8.2) — каждый шаг фазы «бой» ───────────
func measure(dt: float) -> void:
	if is_zero_approx(state.stats.first_gun): return
	var lines := {}
	for sd in ["attacker", "defender"]: lines[sd] = []
	for e in state.ships:
		if e.dead or not e.hyper.is_empty(): continue
		if e.cls == "capital" and not e.station:
			var R := main_range(e); var Dz := R * 0.4
			metrics.cap_t += dt
			var t = e.main_target if flags.get("doctrine", false) else e.target
			if t is Ent.Ship and not t.dead:
				var d := battle_dist(t.pos, e.pos)
				if d >= Dz and d <= R: metrics.belt_t += dt
			var nf := nearest_foe_ship_d(e)
			if nf[0] != null and nf[1] < Dz: metrics.close_t += dt
			if e.hp / e.max_hp >= 0.3: lines[e.side].append(e)
	if not lines.attacker.is_empty() and not lines.defender.is_empty():
		var ca := center(lines.attacker); var cd := center(lines.defender)
		metrics.L_samples.append(Vector2(ca.x - cd.x, ca.z - cd.z).length())

# ── шаг боя (simStep) — порядок как в space.js:3925 ─────────────
var prof := {}                # стенд: время по частям шага (мкс), если включено
var prof_on := false
func _pt(k: String, t0: int) -> int:
	var t1 := Time.get_ticks_usec(); prof[k] = prof.get(k, 0) + (t1 - t0); return t1

func sim_step(dt: float) -> void:
	var t0 := Time.get_ticks_usec() if prof_on else 0
	state.time += dt
	update_ecm(dt)
	# update_ground_gun(dt) / update_far() — в пробе нет орудия планеты и кампании
	update_exposure()
	if prof_on: t0 = _pt("ecm+exposure", t0)
	update_ai(dt)
	if prof_on: t0 = _pt("ai", t0)
	for s in state.ships:
		if not s.dead: update_ship(s, dt)
	if prof_on: t0 = _pt("ships", t0)
	for c in state.craft:
		if not c.dead: update_craft(c, dt)
	if prof_on: t0 = _pt("craft", t0)
	for p in state.proj:
		if not p.dead: update_projectile(p, dt)
	if prof_on: t0 = _pt("proj", t0)
	for s in state.ships:
		if s.dead or s.hangar.is_empty(): continue
		var keep: Array = []
		for t in s.hangar.rebuild:
			if state.time >= t: s.hangar.free = mini(s.hangar.bays, s.hangar.free + 1)
			else: keep.append(t)
		s.hangar.rebuild = keep
		s.hangar.launched = s.hangar.launched.filter(func(q): return not q.dead)
	state.craft = state.craft.filter(func(c): return not c.dead)
	state.proj = state.proj.filter(func(p): return not p.dead)
	for sq in state.squads:
		if sq.dead: continue
		if sq.craft.is_empty(): kill_squad(sq); continue
		var c0 := Vector3.ZERO
		for c in sq.craft: c0 += c.pos
		sq.pos = c0 / sq.craft.size()
		if sq.target and (sq.target.dead or unseen(sq.target)): sq.target = null
	state.squads = state.squads.filter(func(q): return not q.dead)
	var tm := Time.get_ticks_usec() if prof_on else 0
	measure(dt)
	if prof_on: _pt("  rest:measure", tm)
	check_teeth()
	check_end()
	if prof_on: _pt("rest", t0)

## RefCounted не собирает циклы (корабль ↔ цель, звено ↔ машина): в JS это
## делал сборщик мусора. Без разрыва ссылок сто боёв подряд копят память.
func dispose() -> void:
	for s in state.ships:
		s.target = null; s.forced = null; s.guard_of = null; s.jam_shot = null
		s.main_target = null; s.sec_target = null; s.hangar = {}; s.jam = null
	for c in state.craft:
		c.target = null; c.squad = null
	for q in state.squads:
		q.craft.clear(); q.home = null; q.target = null
	for p in state.proj:
		p.target = null; p.owner = null
	for sd in ais: ais[sd].focus = null
	state.ships.clear(); state.craft.clear(); state.proj.clear(); state.squads.clear()
