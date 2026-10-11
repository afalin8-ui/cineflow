# sim/ground_gun.gd — «Давление Земли», орудие планеты (space.js:137–217, 298–305 ·
# часть 03, 2.17; часть 01, ловушки 16–17). Ион — против Тройдена (у планеты Тройдена),
# ядерная — у Плэктора; в быстром бою орудие у планеты ЗАЩИТНИКА есть всегда и бьёт
# АТАКУЮЩЕГО (03, ловушка 28: не «противника игрока»), скрытых тоже.
# Заводится ПОСЛЕ состояния боя (03, ловушка 29; 05, ловушка 40) — create() зовёт
# battle.gd в конце сборки боя, до первого шага.
# Урон — через общую дверь damage() с ключом heavy (бронь, ×1,25 по эскорту), учёт —
# отдельной строкой «планета» (М7; 09, 9.5 п. 11); сложность на него не действует.
extends RefCounted

const State := preload("res://sim/state.gd")
const Defs := preload("res://sim/defs.gd")
const Ship := preload("res://sim/ship.gd")
const Weapons := preload("res://sim/weapons.gd")

## space.js:159: кольцо наводки у ядерной — радиус удара, у остальных — 60.
const AIM_RING := 60.0
## space.js:200: ЭМИ липнет к первым двум крупным.
const EMP_TARGETS := 2

## ТОЛЬКО для проверки отката: первый залп — через полный период, а не на 0,7 периода.
static var rollback_first_full := false


static func create(b: State, clan: StringName) -> void:
	var f: Defs.FactionDef = b.defs.factions.get(clan)
	if f == null or f.ground_gun == null:
		return
	var g := State.GunState.new()
	g.def = f.ground_gun
	g.clan = clan
	g.side = Ship.ATTACKER           # цель — всегда атакующий (space.js:300)
	g.next = g.def.period * (1.0 if rollback_first_full else b.defs.consts.ground_gun_first)
	b.gun = g


## Цели орудия: живые корабли атакующего, не копящие гипер (скрытые — тоже).
static func targets(b: State) -> Array[Ship]:
	var out: Array[Ship] = []
	for s in b.ships:
		if not s.dead and not s.charging() and s.side == b.gun.side:
			out.append(s)
	return out


# space.js:150 updateGroundGun · часть 03, 2.17
static func update(b: State) -> void:
	var g := b.gun
	if g == null:
		return
	var list := targets(b)
	if list.is_empty():
		return                       # next не сдвигается: залп ждёт первой цели (вопрос 5)
	# предупреждение: наводка загорается заранее, от неё можно уйти
	if not g.warned and b.time >= g.next - g.def.warn:
		g.warned = true
		g.has_aim = true
		g.aim = list[b.rng.randi_range(0, list.size() - 1)].pos
		b.toast("Планета наводит: %s" % g.def.name)
		var ring := g.def.radius if g.def.kind == &"nuke" else AIM_RING
		b.events.append([&"gun_warn", g.def.kind, g.aim, ring, g.def.warn])
	if b.time < g.next:
		return
	_fire(b, g, list)
	g.next = b.time + g.def.period
	g.warned = false
	g.has_aim = false


# space.js:173 fireGroundGun
static func _fire(b: State, g: State.GunState, list: Array[Ship]) -> void:
	var d := g.def
	var hit := PackedInt32Array()
	var at := g.aim if g.has_aim else list[0].pos
	match d.kind:
		&"beam":
			# ионный луч: корабль, ближайший к наводке В МОМЕНТ ЗАЛПА — урон и 10 с без
			# тяги и разворота (02, ловушка 25)
			var t := list[0]
			if g.has_aim:
				var bd := INF
				for s in list:
					var dd := s.pos.distance_squared_to(g.aim)
					if dd < bd:
						bd = dd
						t = s
			at = t.pos
			Weapons.damage(b, t, d.dmg, &"heavy", null, Vector2.ZERO, &"planet")
			t.switch_off(&"engines", b.time + d.disable)
			hit.append(t.uid)
			b.toast("%s: %s обездвижен" % [d.name, t.name])
		&"nuke":
			# площадь по месту наводки: кто ушёл, тот цел; на краю урон 0, но «накрыт»
			var n := 0
			for s in list:
				var dist := s.pos.distance_to(at)
				if dist > d.radius:
					continue
				Weapons.damage(b, s, d.dmg * (1.0 - dist / d.radius), &"heavy", null, Vector2.ZERO, &"planet")
				hit.append(s.uid)
				n += 1
			b.toast(("%s: накрыто кораблей — %d" % [d.name, n]) if n > 0 else ("%s: мимо" % d.name))
		&"blind":
			# весь флот ослеплён: наведение сбито (главный калибр — медленнее, 09, 1.7)
			for s in list:
				s.switch_off(&"aim", b.time + d.blind)
				hit.append(s.uid)
			b.toast("%s: флот ослеплён на %d с" % [d.name, roundi(d.blind)])
		&"emp":
			# ЭМИ-капсулы: липнут к крупным, глушат ангары
			var big: Array[Ship] = []
			for s in list:
				if s.def.hangar > 0 or s.def.cls == &"capital":
					big.append(s)
			var pool := big if not big.is_empty() else list
			for i in mini(EMP_TARGETS, pool.size()):
				pool[i].switch_off(&"hangar", b.time + d.sabotage)
				hit.append(pool[i].uid)
			b.toast("%s: ангары заглушены на %d с" % [d.name, roundi(d.sabotage)])
	b.events.append([&"gun_fire", d.kind, at, hit])
