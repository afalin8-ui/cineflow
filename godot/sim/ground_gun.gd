# sim/ground_gun.gd — «Давление Земли», орудие планеты (space.js:137–217, 298–305 ·
# часть 03, 2.17; часть 01, ловушки 16–17; решение пользователя 01.11.2026 — plan.md, раздел 5,
# «Решения… после 0.8.1», п. 3: «Орудие планеты это должна быть опция у игрока. Оно не автоматом
# работает»). Вид орудия — по клану ВЛАДЕЛЬЦА: ион у Тройдена, ядерная у Плэктора, ЭМИ у Рииза,
# ослепление у Девиана.
# С пакета «Орудие планеты» (capella-v0.10):
# - орудия в бою может НЕ БЫТЬ вовсе (галочка в меню «Быстрый бой», по умолчанию выключена);
# - у него есть ВЛАДЕЛЕЦ (owner) — сторона, чьё оно; бьёт другую сторону (side), скрытых тоже;
# - стреляет оно НЕ ПО ТАЙМЕРУ: у игрока — приказом «Залп» (команда &"gun" с точкой, кнопка
#   в шапке и клавиша P), у ИИ — его решением (Ai.gun_aim, 09, 7.8). Залп летит def.warn секунд
#   (кольцо горит — от него можно уйти), падает, и с МИГА ПРИКАЗА идёт перезарядка def.period.
#   Готово к первому залпу орудие через period × ground_gun_first выгрузки (0,7 периода, как
#   в JS) — это прогрев орудия к началу боя, а не назначенный залп.
# Заводится ПОСЛЕ состояния боя (03, ловушка 29; 05, ловушка 40) — create() зовёт
# battle.gd в конце сборки боя, до первого шага.
# Урон — через общую дверь damage() с ключом heavy (бронь, ×1,25 по эскорту), учёт —
# отдельной строкой «планета» (М7; 09, 9.5 п. 11); сложность на него не действует.
extends RefCounted

const State := preload("res://sim/state.gd")
const Defs := preload("res://sim/defs.gd")
const Ship := preload("res://sim/ship.gd")
const Weapons := preload("res://sim/weapons.gd")
const Ai := preload("res://sim/ai.gd")

## space.js:159: кольцо наводки у ядерной — радиус удара, у остальных — 60.
const AIM_RING := 60.0
## space.js:200: ЭМИ липнет к первым двум крупным.
const EMP_TARGETS := 2

## ТОЛЬКО для проверки отката: первый залп — через полный период, а не на 0,7 периода.
static var rollback_first_full := false
## ТОЛЬКО для проверки отката (доработка GТ): кольцо «ведёт» корабль — центр ядерного залпа ставится
## на ближайший к наводке корабль в МИГ ЗАЛПА, а не остаётся там, где загорелось кольцо. Так уйти из-под
## залпа было бы нельзя, и совет выпуска «уведите корабли из кольца» потерял бы смысл.
static var rollback_aim_at_fire := false
## ТОЛЬКО для проверки отката и для сверки «прежний бой до бита» (пакет «Орудие планеты»): орудие
## стреляет ПО ТАЙМЕРУ, как до capella-v0.10 — первый залп на 0,7 периода, дальше раз в период,
## наводка — на случайный корабль атакующего; игроку оно не подчиняется, ИИ не решает. С ним прежние
## числа (OLD_TEMPO) снова дают бой 0.7.1 до бита. В игре false.
static var rollback_timer := false


## Завести орудие клана clan у стороны owner (бьёт другую сторону). Человек стреляет им, только
## если это сторона игрока и её не ведёт ИИ (в «ИИ против ИИ» обе стороны — у ИИ).
static func create(b: State, clan: StringName, owner: int = Ship.DEFENDER) -> void:
	var f: Defs.FactionDef = b.defs.factions.get(clan)
	if f == null or f.ground_gun == null:
		return
	var g := State.GunState.new()
	g.def = f.ground_gun
	g.clan = clan
	g.timer = rollback_timer
	g.owner = owner
	g.side = 1 - owner
	if g.timer:
		g.owner = Ship.DEFENDER
		g.side = Ship.ATTACKER        # прежнее правило: цель — всегда атакующий (space.js:300)
	g.human = not g.timer and owner == b.player_side and not b.watch and not b.sides[owner].ai_on
	g.next = g.def.period * (1.0 if rollback_first_full else b.defs.consts.ground_gun_first)
	g.ai_next = g.next
	b.gun = g


## Цели орудия: живые корабли чужой владельцу стороны, не копящие гипер (скрытые — тоже).
static func targets(b: State) -> Array[Ship]:
	var out: Array[Ship] = []
	for s in b.ships:
		if not s.dead and not s.charging() and s.side == b.gun.side:
			out.append(s)
	return out


## Готово ли орудие к залпу сейчас (перезарядка кончилась, прежний залп не летит).
static func ready(b: State) -> bool:
	var g := b.gun
	return g != null and not g.warned and b.time >= g.next


## Залп в точку at: кольцо загорается сейчас, залп падает через def.warn секунд, перезарядка —
## def.period с этого мига. Одна дверь для приказа игрока и решения ИИ. → false — не готово.
static func order(b: State, at: Vector2) -> bool:
	var g := b.gun
	if not ready(b):
		return false
	g.warned = true
	g.has_aim = true
	g.aim = at
	g.fire_at = b.time + g.def.warn
	g.next = b.time + g.def.period
	g.salvos += 1
	if g.human:
		b.toast("Залп: %s — упадёт через %d с" % [g.def.name, roundi(g.def.warn)])
	else:
		b.toast(_voice(b, g, "Планета наводит: %s" % g.def.name))
	b.events.append([&"gun_warn", g.def.kind, g.aim, _ring(g), g.def.warn])
	return true


static func _ring(g: State.GunState) -> float:
	return g.def.radius if g.def.kind == &"nuke" else AIM_RING


# часть 03, 2.17 · решение 01.11.2026: летящий залп падает в свой срок; готовое орудие ИИ решает
# раз в ai.gun_every (09, 7.8); орудие игрока ждёт приказа.
static func update(b: State) -> void:
	var g := b.gun
	if g == null:
		return
	if g.timer:
		_update_timer(b, g)
		return
	if g.warned:
		if b.time >= g.fire_at:
			_fire(b, g, targets(b))
			g.warned = false
			g.has_aim = false
		return
	if g.human or b.over or b.time < g.next or b.time < g.ai_next:
		return
	g.ai_next = b.time + b.defs.doctrine.ai_gun_every
	var pick := Ai.gun_aim(b, g)
	var fire: bool = pick["fire"]
	if fire:
		var at: Vector2 = pick["at"]
		order(b, at)


# space.js:150 updateGroundGun · часть 03, 2.17 — ПРЕЖНЕЕ правило (только откат rollback_timer):
# залп по таймеру, наводка на случайный корабль атакующего.
static func _update_timer(b: State, g: State.GunState) -> void:
	var list := targets(b)
	if list.is_empty():
		return                       # next не сдвигается: залп ждёт первой цели (вопрос 5)
	# предупреждение: наводка загорается заранее, от неё можно уйти
	if not g.warned and b.time >= g.next - g.def.warn:
		g.warned = true
		g.has_aim = true
		g.aim = list[b.rng.randi_range(0, list.size() - 1)].pos
		b.toast(_voice(b, g, "Планета наводит: %s" % g.def.name))
		b.events.append([&"gun_warn", g.def.kind, g.aim, _ring(g), g.def.warn])
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
	if list.is_empty():
		# все цели погибли или ушли в гипер, пока залп летел
		b.toast(_voice(b, g, "%s: мимо" % d.name))
		b.events.append([&"gun_fire", d.kind, g.aim, hit])
		return
	var at := g.aim if g.has_aim else list[0].pos
	if rollback_aim_at_fire and g.has_aim:
		var bd := INF
		for s in list:
			var dd := s.pos.distance_squared_to(g.aim)
			if dd < bd:
				bd = dd
				at = s.pos
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
			b.toast(_voice(b, g, "%s: %s обездвижен" % [d.name, t.name]))
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
			b.toast(_voice(b, g, ("%s: накрыто кораблей — %d" % [d.name, n]) if n > 0 else ("%s: мимо" % d.name)))
		&"blind":
			# весь флот ослеплён: наведение сбито (главный калибр — медленнее, 09, 1.7)
			for s in list:
				s.switch_off(&"aim", b.time + d.blind)
				hit.append(s.uid)
			b.toast(_voice(b, g, "%s: флот ослеплён на %d с" % [d.name, roundi(d.blind)]))
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
			b.toast(_voice(b, g, "%s: ангары заглушены на %d с" % [d.name, roundi(d.sabotage)]))
	b.events.append([&"gun_fire", d.kind, at, hit])


## Полоска орудия планеты в «ИИ против ИИ» — от имени клана планеты («Плэктор: Ядерная ракета:
## мимо»), как вся лента и полоски зрителя (State.clan_voice; хвост проверки G5, п. 4: текст
## выпуска и godot/CLAUDE.md обещали клан, а полоски его не несли). В бою с приказами — как было.
static func _voice(b: State, g: State.GunState, text: String) -> String:
	if not b.clan_voice():
		return text
	return "%s: %s" % [b.clan_tag(g.owner), text]
