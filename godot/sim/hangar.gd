# sim/hangar.gd — ангары и звенья: пуск, гибель машины и звена, посадка, rehome,
# места на постройке и уборка в конце шага (space.js:421 launchSquadron, 469 killSquad,
# 496 rehome, 954–973 destroy, 3947–3964 · часть 04, 2.2–2.3, 2.9–2.11; доктрина
# 09, 4.1: «механика ангара — без изменений»). Перенос построчно с пометками;
# отличие — только помеченное.
#
# Отдельным модулем, а не в sim/air.gd: гибель машины зовёт одна дверь урона
# (sim/weapons.gd → damage), а air.gd сам зовёт weapons.gd (пушки, ракеты) — общий
# модуль без них не даёт кольца preload (godot/CLAUDE.md, 1).
#
# Инвариант C99 (04, ловушки 4–5) держится тремя правилами, и все три — здесь:
# - посадка возвращает место СРАЗУ и без таймера; таймер 26 с — только за выбитое;
# - чужое звено садится только на СВОБОДНОЕ место и занимает его в момент выбора;
# - погибшие звенья уходят из launched в каждом шаге (ловушка 9).
extends RefCounted

const State := preload("res://sim/state.gd")
const Defs := preload("res://sim/defs.gd")
const Ship := preload("res://sim/ship.gd")
const Body := preload("res://sim/body.gd")
const Craft := preload("res://sim/craft.gd")
const Squad := preload("res://sim/squad.gd")

# Числа JS, перенесённые как есть (часть 04); числа доктрины — в doctrine.json.
const SPAWN_JITTER := 9.0          # space.js:441: машины у зева ангара ±9 (по высоте — картинка)
## Зев ангара — к носу носителя на 0,45 длины (space.js:439 bay: (0; 0,08 R; −0,55 L) ×
## 1,65 у процедурной модели; у .glb — 0,9 полудлины вперёд). Бой плоский: высоты нет.
const BAY_K := 0.45
const LAND_K := 2.4                # space.js:1572: машина садится ближе 2,4 радиуса дома
const ROLE_GEN := {&"interceptor": "перехватчиков", &"fighter": "истребителей", &"bomber": "бомбардировщиков"}

## ТОЛЬКО для проверок отката (часть 04, ловушки 4–6), в игре всегда false:
## посадка возвращает место и ЕЩЁ ставит таймер 26 с, как за выбитое (C99 — два
## механизма сразу: носитель на N ангаров держал бы больше N звеньев);
static var rollback_land_timer := false
## rehome не занимает место в момент выбора (C99: чужое звено «возвращало» чужое место);
static var rollback_rehome_no_take := false
## погибшие звенья не убираются из launched (04, ловушка 9);
static var rollback_keep_dead := false
## rehome выбирает и носитель, копящий гипер (04, ловушка 8: уход в гипер — гибель);
static var rollback_rehome_hyper := false
## севшее звено взлетает НЕ полным — с тем боезапасом, с каким село (01, ловушка 24).
static var rollback_relaunch_spent := false
static var _spent: Dictionary[int, int] = {}


## Ангар корабля при появлении (space.js:375): bays = free = def.hangar.
static func make(bays: int) -> Squad.Hangar:
	var h := Squad.Hangar.new()
	h.bays = bays
	h.free = bays
	return h


# space.js:421 launchSquadron · часть 04, 2.3
## Поднять ОДНО звено роли с носителя. null — отказ (нет ангара, мест, носитель погиб).
## ЭМИ-капсул планеты Рииза в срезе нет — sabotage не проверяется.
static func launch(b: State, carrier: Ship, role: StringName) -> Squad:
	if carrier == null or carrier.dead or carrier.hangar == null or carrier.hangar.free <= 0:
		return null
	var fd: Defs.FactionDef = b.defs.factions.get(b.sides[carrier.side].clan)
	if fd == null or not fd.strike.has(role):
		return null
	carrier.hangar.free -= 1
	var def: Defs.CraftDef = fd.strike[role]
	var q := Squad.new()
	q.uid = b.next_uid()
	q.side = carrier.side
	q.clan = fd.id
	q.role = role
	q.def = def
	q.home = carrier
	q.pos = carrier.pos
	q.size = fd.squad_size
	q.launched_at = b.time
	q.flank = flank_of(b, carrier, q.uid)
	var origin := carrier.pos + carrier.dir * (carrier.length * BAY_K)
	var strike_i := Defs.CLASSES.find(&"strike")
	for i in q.size:
		var c := Craft.new()
		c.uid = b.next_uid()
		c.kind = Body.CRAFT
		c.side = carrier.side
		c.def = def
		c.role = role
		c.squad = q
		c.slot = i
		c.pos = origin + Vector2(b.rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), b.rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))
		c.set_yaw(carrier.yaw)
		c.vel = carrier.vel
		c.hp = def.hp
		c.max_hp = def.hp
		c.armor = def.armor
		c.cls_i = strike_i
		c.hit_r = b.defs.consts.craft_radius
		c.cd = b.rng.randf_range(0.0, def.cd)
		c.ammo = def.ammo                  # севшее звено взлетает полным (01, ловушка 24)
		if rollback_relaunch_spent and _spent.has(carrier.uid):
			c.ammo = _spent[carrier.uid]
		c.reloads = def.reloads
		c.jumped_at_step = b.steps
		q.craft.append(c)
		b.crafts.append(c)
	b.squads.append(q)
	carrier.hangar.launched.append(q)
	b.sides[q.side].sq_up += 1
	b.events.append([&"launch", q.uid])
	return q


## ДОКТРИНА 09, 4.4: фланг звена, если цель на оси, — постоянный: со стороны, где
## стоит носитель (носители — по deploy.carrier_lat вбок); носитель на оси — по
## чётности номера звена (не случайно: исход не зависит от того, кто первым спросил rng).
static func flank_of(b: State, carrier: Ship, u: int) -> float:
	var x := carrier.pos.x * b.sides[carrier.side].sign_z
	if absf(x) > 1.0:
		return signf(x)
	return 1.0 if u % 2 == 0 else -1.0


# space.js:1000 liveTarget (звено) · часть 04, 2.12 — приказ «бить звено» = бить его машины
## Ближайшая к from живая видимая машина звена q; null — нечего бить (C14).
static func live_craft(q: Squad, from: Vector2) -> Craft:
	if q == null or q.dead:
		return null
	var best: Craft = null
	var bd := INF
	for c in q.craft:
		if c.dead:
			continue
		var d := c.pos.distance_squared_to(from)
		if d < bd:
			bd = d
			best = c
	return best


# space.js:496 rehome · часть 04, 2.10
## Звено без дома ищет свой живой носитель НЕ в гипере со свободным местом — ближайший
## к звену — и СРАЗУ занимает место (C99, ловушка 5). → новый дом или null.
static func rehome(b: State, q: Squad) -> Ship:
	var best: Ship = null
	var bd := INF
	for s in b.ships:
		if s.dead or (s.charging() and not rollback_rehome_hyper) or s.side != q.side or s.hangar == null or s.hangar.free <= 0:
			continue
		var d := s.pos.distance_squared_to(q.pos)
		if d < bd:
			bd = d
			best = s
	if best != null:
		if not rollback_rehome_no_take:
			best.hangar.free -= 1
		best.hangar.launched.append(q)
	q.home = best
	return best


## Дом звена, если он ещё дом: жив и (для посадки) не ушёл в гипер — уход носителя
## в гипер для звеньев — гибель (04, ловушка 8): completeJump ставит dead.
static func home_of(q: Squad) -> Ship:
	var h := q.home as Ship
	if h == null or h.dead:
		return null
	return h


# space.js:1570–1580 — машина села на дом
## Села последняя — место возвращается сразу, без таймера (C99), звено — «севшее».
static func land(b: State, c: Craft, home: Ship) -> void:
	var q := c.squad as Squad
	_remove(b, c)
	b.events.append([&"craft_gone", c.uid])
	if rollback_relaunch_spent:
		_spent[home.uid] = c.ammo
	if q != null and q.craft.is_empty():
		home.hangar.free = mini(home.hangar.bays, home.hangar.free + 1)
		kill_squad(b, q, true)
		if q.side == b.player_side:
			b.toast("Звено село, ангар свободен")


# space.js:1489 leaveField (конец) — пустая машина ушла с поля: как посадка, без потери
static func leave(b: State, c: Craft) -> void:
	var q := c.squad as Squad
	_remove(b, c)
	b.events.append([&"craft_gone", c.uid])
	if q != null and q.craft.is_empty():
		kill_squad(b, q, true)


## Машина уходит из звена (погибла, села, ушла с поля).
static func _remove(_b: State, c: Craft) -> void:
	c.dead = true
	var q := c.squad as Squad
	if q != null:
		q.craft.erase(c)


# space.js:936 destroy (машина) · часть 04, 2.11
## Машина сбита: уходит из звена; машин не осталось — звено выбито (место через 26 с).
static func destroy_craft(b: State, c: Craft, _by: Body) -> void:
	if c.dead:
		return
	c.hp = 0.0
	_remove(b, c)
	b.events.append([&"craft_dead", c.uid, c.pos])
	var q := c.squad as Squad
	if q != null and q.craft.is_empty():
		kill_squad(b, q, false)


# space.js:469 killSquad · часть 04, 2.11
## Звено кончилось. Не село — место вернётся через 26 с (если дом жив), потеря в итогах
## и лента словом «наше / вражеское» (03, ловушка 31). Село — место уже вернула посадка,
## второго таймера нет (C99).
static func kill_squad(b: State, q: Squad, landed: bool) -> void:
	if q.dead:
		return
	q.dead = true
	var home := home_of(q)
	if (not landed or rollback_land_timer) and home != null and home.hangar != null:
		home.hangar.rebuild.append(b.time + b.defs.consts.squad_rebuild)
	if not landed:
		b.sides[q.side].sq_lost += 1
		var what := "звено %s %s" % [ROLE_GEN.get(q.role, ""), q.def.name]
		if b.watch:
			b.feed("%s: сбито %s" % [b.clan_tag(q.side), what], &"warn")
		elif q.side == b.player_side:
			b.feed("Потеряно наше " + what, &"bad")
		else:
			b.feed("Сбито вражеское " + what, &"good")


## Носитель погиб или ушёл в гипер: у его живых звеньев дома больше нет (space.js:954).
static func orphan(carrier: Ship) -> void:
	if carrier.hangar == null:
		return
	for r in carrier.hangar.launched:
		var q := r as Squad
		if q != null and not q.dead and q.home == carrier:
			q.home = null


# space.js:3947–3964 · часть 04, 2.2 — места на постройке, уборка, звенья
## В конце шага: моменты постройки ≤ time возвращают места (не больше bays); погибшие
## звенья уходят из launched (ловушка 9); мёртвые машины — из списка; звено без машин —
## выбито (страховка); центр звена; цель звена погибла — снята.
static func tick(b: State) -> void:
	for s in b.ships:
		if s.dead or s.hangar == null:
			continue
		var h := s.hangar
		if not h.rebuild.is_empty():
			var keep := PackedFloat64Array()
			for t in h.rebuild:
				if b.time >= t:
					h.free = mini(h.bays, h.free + 1)
				else:
					keep.append(t)
			h.rebuild = keep
		if not rollback_keep_dead:
			var live: Array[RefCounted] = []
			for r in h.launched:
				var q := r as Squad
				if q != null and not q.dead:
					live.append(q)
			h.launched = live
	var alive: Array[Craft] = []
	for c in b.crafts:
		if not c.dead:
			alive.append(c)
		else:
			c.unlink()
	b.crafts = alive
	var qs: Array[Squad] = []
	for q in b.squads:
		if q.dead:
			continue
		if q.craft.is_empty():
			kill_squad(b, q, false)
			continue
		var sum := Vector2.ZERO
		for c in q.craft:
			sum += c.pos
		q.pos = sum / float(q.craft.size())
		var tb := q.target as Body
		var tq := q.target as Squad
		if (tb != null and tb.dead) or (tq != null and tq.dead):
			q.target = null
		qs.append(q)
	for q in b.squads:
		if q.dead:
			q.unlink()                     # кольца звено ↔ машина ↔ носитель (архитектура, 2.12)
	b.squads = qs


## Живые звенья с домом h — для инварианта C99 (проверки и стенд).
static func live_at(b: State, carrier: Ship) -> int:
	var n := 0
	for q in b.squads:
		if not q.dead and q.home == carrier:
			n += 1
	return n
