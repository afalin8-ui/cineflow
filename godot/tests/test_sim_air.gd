# Модель авиации G3: ангар и звенья, машины, звено как цель, доктрина патруля и обхода
# (план G3, «Проверки»; часть 04, 4.2; доктрина 09, раздел 4). Каждая проверка — с
# откатом: на копии без правки (флажок отката, правка числа, прежнее правило) она обязана
# краснеть, и краснеть ОТ ТОГО, что проверяет.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Body := preload("res://sim/body.gd")
const Craft := preload("res://sim/craft.gd")
const Squad := preload("res://sim/squad.gd")
const Proj := preload("res://sim/proj.gd")
const Weapons := preload("res://sim/weapons.gd")
const Hangar := preload("res://sim/hangar.gd")
const Air := preload("res://sim/air.gd")
const Polygon := preload("res://tools/polygon.gd")

const BIG := 1.0e9

var defs: Defs


func _defs() -> Defs:
	if defs == null:
		defs = Defs.load_default() as Defs
	return defs


## Пустое поле: бой без кораблей.
func _lab(att: StringName = &"troyden", dfn: StringName = &"plektor", setup: Dictionary = {}, d: Defs = null) -> Battle:
	var st := {"attacker": att, "defender": dfn, "size": &"small", "seed": 7, "reserve": false}
	st.merge(setup, true)
	var b := Battle.create(d if d != null else _defs(), st) as Battle
	b.ships.clear()
	return b


func _put(b: Battle, side: int, id: StringName, pos: Vector2, look: Variant = null) -> Ship:
	var s := b.spawn(side, b.defs.ship(b.sides[side].clan, id), pos)
	if look != null:
		var at: Vector2 = look
		s.set_yaw(Ship.yaw_of(at - pos))
	return s


## Корабль-мишень: не летит, прочность поднята, оружия нет (ПВО — по желанию).
func _still(s: Ship, keep_pd: bool = false) -> Ship:
	s.switch_off(&"engines", BIG)
	s.stance = &"hold"
	s.hp = BIG
	s.max_hp = BIG
	s.main_cd = PackedFloat64Array()
	s.sec_cd = PackedFloat64Array()
	s.light_cd = PackedFloat64Array()
	s.mis_cd = PackedFloat64Array()
	if not keep_pd:
		s.pd_cd = PackedFloat64Array()
	return s


func _steps(b: Battle, seconds: float) -> void:
	for i in roundi(seconds / Battle.STEP):
		b.step()


## Инвариант C99 у каждого живого носителя: free + rebuild + живые звенья с этим домом
## ≤ bays. → пусто, если держится, иначе — где сломался.
static func _c99(b: Battle) -> String:
	for s in b.ships:
		if s.dead or s.hangar == null:
			continue
		var h := s.hangar
		var n := h.free + h.rebuild.size() + Hangar.live_at(b, s)
		if n > h.bays:
			return "%s: свободно %d + строится %d + в воздухе %d = %d > %d (шаг %d)" % [s.name, h.free, h.rebuild.size(), Hangar.live_at(b, s), n, h.bays, b.steps]
	return ""


## Все машины звена — у точки (посадка: ближе 2,4 радиуса дома).
static func _park(q: Squad, at: Vector2) -> void:
	for c in q.craft:
		c.pos = at + Vector2(float(c.slot) * 2.0, 0.0)
		c.vel = Vector2.ZERO


static func _count(b: Battle, text: String) -> int:
	var n := 0
	for e in b.toast_log:
		if str(e["text"]).contains(text):
			n += 1
	return n


# ───────────────────────── C99: ангар в каждом шаге (04, 4.2 п. 1) ─────────────────────────

## Два носителя одной стороны поднимают все звенья, первый погибает; его звенья и одно
## своё звено второго — на посадку, все машины у второго. Своё звено обновляется первым
## (место освобождается в том же шаге), чужие садятся только на свободное.
func _rehome_case(no_take: bool) -> Dictionary:
	Hangar.rollback_rehome_no_take = no_take
	var b := _lab()
	var c2 := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(400, 900)))
	var c1 := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(-400, 900)))
	_still(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -2500)))     # бой не кончается
	var own: Array[Squad] = []
	for i in c2.hangar.bays:
		own.append(Hangar.launch(b, c2, &"interceptor"))
	var foreign: Array[Squad] = []
	for i in c1.hangar.bays:
		foreign.append(Hangar.launch(b, c1, &"fighter"))
	Weapons.destroy_ship(b, c1, null)
	var first := own[0]
	Air.order_recall(first)
	_park(first, c2.pos)
	for q in foreign:
		Air.order_recall(q)
		_park(q, c2.pos)
	var broke := ""
	var landed := 0
	for i in 90:
		b.step()
		var why := _c99(b)
		if broke == "" and why != "":
			broke = why
	for q in foreign:
		if q.dead and q.home == null:
			pass
	for q in foreign:
		if q.dead:
			landed += 1
	var out := {"broke": broke, "landed": landed, "free": c2.hangar.free, "lost": b.sides[Ship.ATTACKER].sq_lost}
	Hangar.rollback_rehome_no_take = false
	b.dispose()
	return out


func test_c99_rehome_takes_free_bay() -> void:
	var r := _rehome_case(false)
	eq(str(r["broke"]), "", "C99: free + rebuild + живые звенья ≤ bays в каждом шаге")
	ok(whole(r["landed"]) >= 1, "звено погибшего носителя село на второй (%d из 3)" % whole(r["landed"]))
	eq(whole(r["lost"]), 0, "севшие звенья — не потери")
	var o := _rehome_case(true)
	ok(str(o["broke"]) != "", "откат «rehome не занимает место»: инвариант ломается — %s" % str(o["broke"]))


## Посадка возвращает место СРАЗУ и без таймера; выбитое — через 26 с (C99, 04 4.2 п. 2).
func _land_case(timer: bool) -> Dictionary:
	Hangar.rollback_land_timer = timer
	var b := _lab()
	var car := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(0, 900)))
	_still(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -2500)))
	var q := Hangar.launch(b, car, &"fighter")
	var after_launch := car.hangar.free
	Air.order_recall(q)
	_park(q, car.pos)
	b.step()
	var landed := q.dead
	var free_land := car.hangar.free
	var rebuild_land := car.hangar.rebuild.size()
	var broke := _c99(b)
	# выбитое звено: место — через 26 с, не раньше и не больше bays
	var q2 := Hangar.launch(b, car, &"bomber")
	var kill: Array[Craft] = []
	kill.append_array(q2.craft)
	for c in kill:
		Weapons.damage(b, c, BIG, &"pd", null, Vector2.ZERO)
	var t_lost := b.time
	b.step()
	var rb := car.hangar.rebuild.duplicate()
	var free_lost := car.hangar.free
	_steps(b, 25.5)
	var free_25 := car.hangar.free
	_steps(b, 1.0)
	var free_27 := car.hangar.free
	var out := {"after_launch": after_launch, "landed": landed, "free_land": free_land, "rebuild_land": rebuild_land,
		"broke": broke, "rb": rb, "t_lost": t_lost, "free_lost": free_lost, "free_25": free_25, "free_27": free_27,
		"bays": car.hangar.bays, "lost": b.sides[Ship.ATTACKER].sq_lost, "feed": b.feed_log.duplicate()}
	Hangar.rollback_land_timer = false
	b.dispose()
	return out


func test_landing_no_timer_lost_26s() -> void:
	var r := _land_case(false)
	var bays := whole(r["bays"])
	eq(whole(r["after_launch"]), bays - 1, "пуск занял место")
	ok(flag(r["landed"]), "звено у носителя на «посадку» село за шаг")
	eq(whole(r["free_land"]), bays, "село — место вернулось СРАЗУ")
	eq(whole(r["rebuild_land"]), 0, "и без таймера постройки (C99)")
	eq(str(r["broke"]), "", "инвариант C99 после посадки")
	var rb: PackedFloat64Array = r["rb"]
	ok(rb.size() == 1 and absf(rb[0] - (num(r["t_lost"]) + 26.0)) < Battle.STEP + 1e-6, "выбитое звено — постройка через 26 с: %s" % str(rb))
	eq(whole(r["free_lost"]), bays - 1, "место выбитого — не сразу")
	eq(whole(r["free_25"]), bays - 1, "через 25,5 с — ещё строится")
	eq(whole(r["free_27"]), bays, "через 26 с — вернулось и не больше мест")
	eq(whole(r["lost"]), 1, "выбитое звено — потеря в итогах, севшее — нет")
	var fl: Array = r["feed"]
	var said := false
	for e: Variant in fl:
		var ed: Dictionary = e
		said = said or str(ed["text"]).begins_with("Потеряно наше звено бомбардировщиков")
	ok(said, "лента — словом «наше» (03, ловушка 31)")
	var o := _land_case(true)
	ok(whole(o["rebuild_land"]) > 0 and str(o["broke"]) != "", "откат «посадка тоже ставит 26 с»: таймер %d, инвариант — %s" % [whole(o["rebuild_land"]), str(o["broke"])])


## Севшее звено взлетает полным (01, ловушка 24): звено с почти пустым боезапасом село,
## новое с того же места — с полным.
func _relaunch(spent: bool) -> int:
	Hangar.rollback_relaunch_spent = spent
	var b := _lab()
	var car := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(0, 900)))
	_still(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -2500)))
	var q := Hangar.launch(b, car, &"fighter")
	for c in q.craft:
		c.ammo = 2
	Air.order_recall(q)
	_park(q, car.pos)
	b.step()
	var q2 := Hangar.launch(b, car, &"fighter")
	var ammo := q2.craft[0].ammo
	Hangar.rollback_relaunch_spent = false
	Hangar._spent.clear()
	b.dispose()
	return ammo


func test_relaunch_full() -> void:
	var full := _defs().factions[&"troyden"].strike[&"fighter"].ammo
	eq(_relaunch(false), full, "севшее звено взлетает с полным боезапасом (%d)" % full)
	ok(_relaunch(true) < full, "откат «взлетает с тем, с чем село»: боезапас меньше полного — проверка краснеет")


# ───────────────────────── звено как цель (C14; 09, 4.6) ─────────────────────────

func _c14(as_target: bool) -> Dictionary:
	Weapons.rollback_squad_as_target = as_target
	var b := _lab()
	var car := _still(_put(b, Ship.DEFENDER, &"carrier", Vector2(0, -900)))
	var q := Hangar.launch(b, car, &"interceptor")
	for c in q.craft:
		c.pos = Vector2(float(c.slot) * 8.0, -150.0)
		c.vel = Vector2.ZERO
	var fr := _put(b, Ship.ATTACKER, &"frigate", Vector2(0, 0), Vector2(0, -150))
	fr.pd_cd = PackedFloat64Array()               # бьёт только лёгкое орудие
	fr.hp = BIG
	fr.max_hp = BIG
	b.queue({"op": &"focus", "ids": PackedInt32Array([fr.uid]), "target": q.uid})
	var light_on_craft := 0.0
	var nan := false
	for i in 150:
		b.step()
		for x in b.crafts:
			nan = nan or is_nan(x.hp) or is_inf(x.hp)
		for s in b.ships:
			nan = nan or is_nan(s.hp)
	light_on_craft = num(b.metrics.dmg[Ship.ATTACKER].get(&"light", PackedFloat64Array([0, 0, 0, 0, 0]))[3]) if b.metrics.dmg[Ship.ATTACKER].has(&"light") else 0.0
	var out := {"craft_dmg": light_on_craft, "nan": nan, "target_is_craft": (fr.target as Craft) != null or q.dead,
		"squad_dmg": Weapons.damage(b, q, 100.0, &"pd", fr, Vector2.ZERO)}
	Weapons.rollback_squad_as_target = false
	b.dispose()
	return out


func test_c14_squad_is_order_to_hit_craft() -> void:
	var r := _c14(false)
	ok(num(r["craft_dmg"]) > 0.0, "приказ «бить звено» лёгкому — его орудие бьёт машины (урон %.0f)" % num(r["craft_dmg"]))
	ok(flag(r["target_is_craft"]), "цель лёгкого — машина звена, а не звено")
	ok(not flag(r["nan"]), "ни одной прочности NaN или бесконечности")
	eq(num(r["squad_dmg"]), 0.0, "урон «по звену» не принимается — у звена нет прочности")
	var o := _c14(true)
	ok(num(o["craft_dmg"]) <= 0.0, "откат «цель — само звено»: машины не получают урона (%.0f) — проверка краснеет" % num(o["craft_dmg"]))


## Тяжёлый приказ на звено не принимает (09, 4.6): с пояса не сходит, цели не берёт;
## полоска словами. Безоружный — держится (C100).
func _heavy_case(to_squad: bool) -> Dictionary:
	Battle.rollback_heavy_to_squad = to_squad
	var b := _lab()
	var car := _still(_put(b, Ship.DEFENDER, &"carrier", Vector2(0, -900)))
	var q := Hangar.launch(b, car, &"bomber")
	var cr := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 300), Vector2(0, -300))
	var own_car := _put(b, Ship.ATTACKER, &"carrier", Vector2(300, 600), Vector2(300, 0))
	var p0 := cr.pos
	b.queue({"op": &"focus", "ids": PackedInt32Array([cr.uid, own_car.uid]), "target": q.uid})
	_steps(b, 3.0)
	var out := {"moved": cr.pos.distance_to(p0), "forced": cr.forced != null, "move": cr.has_move,
		"said": _count(b, "Тяжёлые держат дистанцию"), "held": _count(b, "безоружны")}
	Battle.rollback_heavy_to_squad = false
	b.dispose()
	return out


func test_heavy_refuses_squad_order() -> void:
	var r := _heavy_case(false)
	ok(num(r["moved"]) < 1.0 and not flag(r["forced"]) and not flag(r["move"]), "крейсер приказ на звено не принял: сдвиг %.1f, фокуса и «идти» нет" % num(r["moved"]))
	eq(whole(r["said"]), 1, "полоска «Тяжёлые держат дистанцию — авиацию бьют ПВО и звенья»")
	eq(whole(r["held"]), 1, "носитель (безоружный) — «держатся позади» (C100)")
	var o := _heavy_case(true)
	ok(num(o["moved"]) > 20.0 or flag(o["move"]), "откат «тяжёлый идёт к звену, как в JS»: сдвиг %.0f — проверка краснеет" % num(o["moved"]))


# ───────────────────────── звено без дома (C8, 04 4.2 п. 4) ─────────────────────────

## Звено ракетчиков без носителя, все ангары заняты: игрок жмёт «На посадку» каждые 2 с
## минуту — «садиться некуда» ровно один раз на звено (C8).
func _c8(always: bool) -> int:
	Air.rollback_tell_always = always
	var b := _lab()
	var c1 := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(-400, 900)))
	var c2 := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(400, 900)))
	_still(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -2500)))
	var q := Hangar.launch(b, c1, &"fighter")
	for i in c2.hangar.bays:
		Hangar.launch(b, c2, &"interceptor")        # у второго мест нет
	Weapons.destroy_ship(b, c1, null)
	for k in 30:
		b.queue({"op": &"recall", "ids": PackedInt32Array([q.uid])})
		_steps(b, 2.0)
	var n := _count(b, "садиться некуда — все ангары заняты")
	Air.rollback_tell_always = false
	b.dispose()
	return n


func test_c8_no_home_said_once() -> void:
	eq(_c8(false), 1, "«садиться некуда — все ангары заняты» — один раз на звено за минуту (C8)")
	var n := _c8(true)
	ok(n > 1, "откат «говорит каждый раз»: %d полосок — проверка краснеет" % n)


## Пустые машины без носителя уходят с поля не позже чем через 25 с (04, ловушка 7):
## звено снимается без потери в итогах.
func _leave(stay: bool) -> Dictionary:
	Air.rollback_no_leave = stay
	var b := _lab()
	var c1 := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(0, 0)))
	_still(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -2500)))
	var q := Hangar.launch(b, c1, &"fighter")
	for c in q.craft:
		c.ammo = 0
		c.reloads = 0
	Weapons.destroy_ship(b, c1, null)
	_steps(b, 26.0)
	var out := {"left": q.craft.size(), "dead": q.dead, "lost": b.sides[Ship.ATTACKER].sq_lost,
		"told": _count(b, "ракет нет, садиться некуда — машины выходят из боя")}
	Air.rollback_no_leave = false
	b.dispose()
	return out


func test_empty_craft_leave_field() -> void:
	var r := _leave(false)
	ok(whole(r["left"]) == 0 and flag(r["dead"]), "пустые машины без носителя ушли с поля за 26 с (осталось %d)" % whole(r["left"]))
	eq(whole(r["lost"]), 0, "ушедшее звено — не потеря")
	eq(whole(r["told"]), 1, "«ракет нет, садиться некуда» — один раз")
	var o := _leave(true)
	ok(whole(o["left"]) > 0, "откат «пустые висят над боем»: машин осталось %d — проверка краснеет" % whole(o["left"]))


# ───────────────────────── перезарядка в космосе (04, 2.9; 4.2 п. 5) ─────────────────────────

func _reload(instant: bool) -> Dictionary:
	Air.rollback_instant_reload = instant
	var b := _lab()
	var car := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(0, 600)))
	_still(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, 300)))   # цель рядом
	var q := Hangar.launch(b, car, &"fighter")
	var c := q.craft[0]
	c.ammo = 0
	var reloads0 := c.reloads
	var fired_while := 0
	var ammo_mid := -1
	var dist_home := 0.0
	var mine: Array[int] = []
	for i in roundi(6.5 / Battle.STEP):
		b.step()
		for e in b.events:
			if e[0] == &"proj":
				var u: int = e[1]
				for p in b.projs:
					if p.uid == u and p.owner == c:
						fired_while += 1
		if i == roundi(3.0 / Battle.STEP):
			ammo_mid = c.ammo
			dist_home = c.pos.distance_to(car.pos)
	var reloading_6 := c.reloading
	_steps(b, 1.0)
	var ammo_after := c.ammo
	# комплекты кончились — на посадку всё звено, а не одна машина
	var c2 := q.craft[1]
	c2.ammo = 0
	c2.reloads = 0
	b.step()
	var out := {"reloads": reloads0 - c.reloads, "fired": fired_while, "ammo_mid": ammo_mid, "home": dist_home,
		"left_6": reloading_6, "ammo_after": ammo_after, "full": c.def.ammo, "recall": q.recall,
		"told": _count(b, "ракеты кончились, звено уходит на носитель")}
	Air.rollback_instant_reload = false
	b.dispose()
	return out


func test_reload_in_space() -> void:
	var r := _reload(false)
	eq(whole(r["reloads"]), 1, "пустой истребитель взял запасной комплект")
	eq(whole(r["fired"]), 0, "7 с перезарядки ракет не пускает")
	eq(whole(r["ammo_mid"]), 0, "через 3 с — всё ещё пусто")
	ok(num(r["left_6"]) > 0.0, "через 6,5 с перезарядка ещё идёт (осталось %.2f с)" % num(r["left_6"]))
	eq(whole(r["ammo_after"]), whole(r["full"]), "через 7 с — полный боезапас")
	ok(flag(r["recall"]) and whole(r["told"]) == 1, "комплекты кончились — на посадку всё звено, сказано один раз")
	var o := _reload(true)
	ok(whole(o["ammo_mid"]) > 0, "откат «перезарядка мгновенная»: через 3 с боезапас %d — проверка краснеет" % whole(o["ammo_mid"]))


# ───────────────────────── торпеда слепнет под куполом (03, ловушка 24) ─────────────────────────

func _blind(temp: bool) -> Dictionary:
	Weapons.rollback_blind_temporary = temp
	var b := _lab()
	var tg := _still(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -400)))
	var ecm := _still(_put(b, Ship.DEFENDER, &"ecm", Vector2(-900, 0)))
	ecm.ecm_mode = &"jam"
	var car := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(0, 2000)))
	var q := Hangar.launch(b, car, &"bomber")
	_steps(b, 0.3)                                   # купол набрал мощность
	var c := q.craft[0]
	c.pos = Vector2(-700, 0)                         # под чужим куполом (радиус поля 420)
	var p := Air.fire_missile(b, c, tg)
	p.target = tg
	p.life = 30.0
	p.dir = Vector2(1, 0)                            # летит вбок, наружу из-под купола
	b.step()
	var blind_in := p.blind
	for i in 90:
		b.step()
	var out := {"in": blind_in, "out": p.blind, "dist": p.pos.distance_to(ecm.pos)}
	Weapons.rollback_blind_temporary = false
	b.dispose()
	return out


func test_craft_torpedo_blind_forever() -> void:
	var r := _blind(false)
	ok(flag(r["in"]), "торпеда машины под чужим куполом слепнет")
	ok(flag(r["out"]) and num(r["dist"]) > 420.0, "и не прозревает, выйдя из-под купола (в %.0f от РЭБ)" % num(r["dist"]))
	var o := _blind(true)
	ok(not flag(o["out"]), "откат «прозревает»: проверка краснеет")


# ───────────────────────── налёт по доктрине (09, 4.4) ─────────────────────────

## Счёт окна ПВО (09, 4.4): залп звена разом со 120 от центра цели, торпеды летят прямо,
## ПВО по ближайшей; 40 залпов с разным стартом перезарядки ПВО. → доля дошедших.
func _salvo(d: Defs, att: StringName, dfn: StringName, frigate: bool) -> float:
	var hits := 0
	var sent := 0
	for sd in 40:
		var b := _lab(att, dfn, {"seed": sd + 1}, d)
		var tgt := _still(_put(b, Ship.DEFENDER, &"cruiser", Vector2.ZERO), true)
		if frigate:
			_still(_put(b, Ship.DEFENDER, &"frigate", Vector2(0, 133)), true)   # «рядом один фрегат» — зонт (3.3)
		var car := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(0, 2500)))
		var q := Hangar.launch(b, car, &"bomber")
		var n := q.craft.size()
		var mine: Array[int] = []
		for i in n:
			var a := deg_to_rad(-30.0 + 60.0 * float(i) / float(maxi(1, n - 1)))
			var at := Vector2(sin(a), cos(a)) * 120.0
			var c := q.craft[i]
			var p := Weapons.spawn_proj(b, c, tgt, c.def.dmg, c.def.weapon, c.def.missile_speed, c.def.missile_hp, (tgt.pos - at).normalized())
			p.pos = at
			mine.append(p.uid)
			c.pos = Vector2(2000, 2400)              # машины — вне боя: считается только окно ПВО
		sent += n
		for i in 120:
			b.step()
			for e in b.events:
				if e[0] == &"proj_hit":
					var u: int = e[1]
					if u in mine:
						hits += 1
		b.dispose()
	return float(hits) / float(sent)


func test_salvo_window_doctrine_44() -> void:
	var d := _defs()
	var old := Defs.load_default({"space_dmg.pd_torpedo": 1.4, "torp.speed": 88.0}) as Defs
	ok(old.ok, "старое ПВО (1,4 / 88) грузится правками --set")
	for pair: Array in [[&"plektor", &"troyden"], [&"troyden", &"plektor"]]:
		var a: StringName = pair[0]
		var df: StringName = pair[1]
		var lone := _salvo(d, a, df, false)
		var umb := _salvo(d, a, df, true)
		var was := _salvo(old, a, df, false)
		note("налёт %s → крейсер %s: одинокий пропускает %.0f%%, с фрегатом %.0f%%; при старом ПВО 1,4 / 88 — %.0f%% (09, 4.4: 65–78%%, 4–22%%, 2–17%%)" % [a, df, lone * 100.0, umb * 100.0, was * 100.0])
		ok(lone >= 0.6, "%s → %s: одинокий крейсер пропускает больше 60%% торпед залпа (%.0f%%)" % [a, df, lone * 100.0])
		ok(umb <= 0.3, "%s → %s: с фрегатом рядом — не больше 30%% (%.0f%%): у фрегатов работа зонта" % [a, df, umb * 100.0])
		ok(was <= 0.3, "%s → %s: откат «старое ПВО 1,4 / 88»: одинокий крейсер пропускает %.0f%% — проверка краснеет" % [a, df, was * 100.0])


## Звено бомбардировщиков, идущее с фланга, долетает и бьёт тяжёлых; флажок
## `--bomber-direct` (прямо на цель, сквозь шеренги) — звено гибнет целиком, не пустив
## ни одной торпеды (09, 4.4 и 8.4). Строй «Сражения» противника стоит (G4 ещё нет),
## ПВО его работает; своё звено одно, ПВО своих не мешает.
func _flank(direct: bool, att: StringName, dfn: StringName) -> Dictionary:
	var b := Battle.create(_defs(), {"attacker": att, "defender": dfn, "size": &"mid", "seed": 11, "reserve": false, "bomber_direct": direct}) as Battle
	var car: Ship = null
	for s in b.ships:
		var keep_pd := s.side == Ship.DEFENDER
		_still(s, keep_pd)
		if s.side == Ship.ATTACKER and s.hangar != null and car == null:
			car = s
	var q := Hangar.launch(b, car, &"bomber")
	var launched := 0
	var hits := 0
	var wide := 0.0
	for i in roundi(80.0 / Battle.STEP):
		b.step()
		for e in b.events:
			if e[0] == &"proj":
				launched += 1
			elif e[0] == &"proj_hit":
				hits += 1
		var g := Air.geo_of(b, Ship.ATTACKER)
		if g != null and g.ok:
			for c in q.craft:
				wide = maxf(wide, absf((c.pos - g.f).dot(g.lat)))
		if q.dead:
			break
	var out := {"launched": launched, "hits": hits, "torp": b.metrics.to_ships(Ship.ATTACKER, &"torp"),
		"dead": q.dead, "dealt": q.dealt, "wide": wide}
	b.dispose()
	return out


func test_bomber_flank_vs_direct() -> void:
	# своя сторона «Полигона» (Тройден) по строю Плэктора — с фланга торпеды доходят
	var r := _flank(false, &"troyden", &"plektor")
	note("с фланга Тройден → Плэктор: пущено %d, попало %d, урон %.0f, звено %s, вбок до %.0f от центра строя" % [whole(r["launched"]), whole(r["hits"]), num(r["torp"]), "выбито" if flag(r["dead"]) else "живо", num(r["wide"])])
	ok(whole(r["launched"]) > 0 and whole(r["hits"]) > 0 and num(r["torp"]) > 0.0, "с фланга звено долетает до тяжёлых и бьёт торпедами (урон %.0f)" % num(r["torp"]))
	near(num(r["dealt"]), num(r["torp"]), 1e-6, "урон торпед — звену (07, ловушка 57) и в учёт по ключу torp (М7)")
	var o := _flank(true, &"troyden", &"plektor")
	note("напрямик: пущено %d, попало %d" % [whole(o["launched"]), whole(o["hits"])])
	ok(flag(o["dead"]) and whole(o["hits"]) == 0 and num(o["torp"]) <= 0.0, "откат «--bomber-direct»: сквозь шеренги звено гибнет целиком, ни одна торпеда не дошла — проверка краснеет")
	# и в обратную сторону: ПВО Тройдена злее, но с фланга звено хотя бы долетает до пуска
	var r2 := _flank(false, &"plektor", &"troyden")
	var o2 := _flank(true, &"plektor", &"troyden")
	note("Плэктор → Тройден: с фланга пущено %d (попало %d), напрямик — %d" % [whole(r2["launched"]), whole(r2["hits"]), whole(o2["launched"])])
	ok(whole(r2["launched"]) > whole(o2["launched"]) and whole(o2["hits"]) == 0, "Плэктор → Тройден: с фланга до пуска доходит больше машин (%d против %d), напрямик ни одна торпеда не дошла" % [whole(r2["launched"]), whole(o2["launched"])])


# ───────────────────────── патруль перехватчиков (09, 4.2) ─────────────────────────

## Перехватчики без цели патрулируют над СВОЕЙ лёгкой линией — на air.patrol_k отрезка
## между линиями тяжёлых. У противника одни тяжёлые и носитель: машин, ракет и эскорта
## нет — целей перехватчику нет.
func _patrol(mid: bool) -> Dictionary:
	var b := _lab(&"troyden", &"plektor", {"patrol_mid": mid})
	var own := _still(_put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 650)))
	var car := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(260, 1090)))
	_still(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -650)))
	var q := Hangar.launch(b, car, &"interceptor")
	_steps(b, 20.0)
	var sum := Vector2.ZERO
	var n := 0
	var far := 0.0
	for k in 300:
		b.step()
		sum += q.pos
		n += 1
	var center := sum / float(n)
	var want := own.pos + (Vector2(0, -650) - own.pos) * b.defs.doctrine.air_patrol_k
	var out := {"center": center, "want": want, "off": center.distance_to(want), "home": center.distance_to(car.pos),
		"mid": b.metrics.mid_share(Ship.ATTACKER)}
	b.dispose()
	return out


func test_interceptor_patrol_over_own_line() -> void:
	var r := _patrol(false)
	var cen: Vector2 = r["center"]
	var want: Vector2 = r["want"]
	note("патруль: центр звена %s, точка %s (air.patrol_k = %.2f), до носителя %.0f, М5 %.2f" % [str(cen.round()), str(want.round()), _defs().doctrine.air_patrol_k, num(r["home"]), num(r["mid"])])
	ok(num(r["off"]) < 60.0, "перехватчики кружат над своей лёгкой линией: центр в %.0f от точки 0,15 отрезка" % num(r["off"]))
	ok(num(r["home"]) > 300.0, "а не у своего носителя (%.0f)" % num(r["home"]))
	ok(num(r["mid"]) >= 0.6, "М5: машина-секунды в середине — %.0f%% (цель ≥ 60%%)" % (num(r["mid"]) * 100.0))
	var o := _patrol(true)
	ok(num(o["off"]) > 300.0, "откат «--patrol-mid»: кружат над серединой, в %.0f от своей линии — проверка краснеет" % num(o["off"]))


# ───────────────────────── носитель в гипере, уборка launched ─────────────────────────

## Уход носителя в гипер — гибель для звеньев (04, ловушка 8): копящий гипер в дома
## не годится, ушедший — тоже.
func _hyper(take: bool) -> Dictionary:
	Hangar.rollback_rehome_hyper = take
	var b := _lab()
	var c1 := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(-400, 900)))
	var c2 := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(400, 900)))
	_still(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -2500)))
	var q := Hangar.launch(b, c1, &"interceptor")
	Weapons.destroy_ship(b, c1, null)
	c2.hyper_left = 30.0                               # копит гипер — не дом
	c2.hyper_total = 30.0
	Air.order_recall(q)
	_park(q, c2.pos)
	b.step()
	var out := {"home": q.home == c2, "landed": q.dead}
	Hangar.rollback_rehome_hyper = false
	b.dispose()
	return out


func test_hyper_carrier_is_no_home() -> void:
	var r := _hyper(false)
	ok(not flag(r["home"]) and not flag(r["landed"]), "носитель, копящий гипер, домом звену не становится")
	var o := _hyper(true)
	ok(flag(o["landed"]), "откат «rehome берёт и копящих гипер»: звено село на уходящий носитель — проверка краснеет")


## Погибшие звенья убираются из launched каждый шаг (04, ловушка 9).
func _launched(keep: bool) -> int:
	Hangar.rollback_keep_dead = keep
	var b := _lab()
	var car := _still(_put(b, Ship.ATTACKER, &"carrier", Vector2(0, 900)))
	_still(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -2500)))
	var q := Hangar.launch(b, car, &"interceptor")
	var kill: Array[Craft] = []
	kill.append_array(q.craft)
	for c in kill:
		Weapons.damage(b, c, BIG, &"pd", null, Vector2.ZERO)
	b.step()
	b.step()
	var n := car.hangar.launched.size()
	Hangar.rollback_keep_dead = false
	b.dispose()
	return n


func test_dead_squads_leave_launched() -> void:
	eq(_launched(false), 0, "выбитое звено ушло из списка носителя")
	ok(_launched(true) > 0, "откат «не убирать»: мёртвое звено числится за носителем — проверка краснеет")


# ───────────────────────── длинный бой: C99 и прочность в каждом шаге ─────────────────────────

## Показательный бой «Полигона» (все приказы, пуски игрока Z/X/C, посадка V, авиация
## противника по кругу ролей) и ещё 90 с: C99 в КАЖДОМ шаге у каждого носителя, ни одной
## прочности NaN, звенья поднимались, терялись и садились.
func test_c99_long_battle() -> void:
	var broke := ""
	var nan := false
	var check := func(bb: Battle) -> void:
		if broke == "":
			broke = _c99(bb)
		for x in bb.crafts:
			if is_nan(x.hp):
				nan = true
	var b := Polygon.demo_battle(_defs(), "capella-проверка", Polygon.DEMO_STEPS, check)
	for i in roundi(90.0 / Battle.STEP):
		b.step()
		check.call(b)
	var up := b.sides[Ship.ATTACKER].sq_up + b.sides[Ship.DEFENDER].sq_up
	var lost := b.sides[Ship.ATTACKER].sq_lost + b.sides[Ship.DEFENDER].sq_lost
	eq(broke, "", "C99 в каждом шаге 150 с «Авиации»")
	ok(not nan, "ни одной прочности NaN у машин")
	ok(up >= 8 and lost >= 2, "звенья поднимались (%d) и терялись (%d)" % [up, lost])
	note("«Авиация» 150 с: поднято %d, потеряно %d; урон авиации по кораблям %.0f / %.0f; М5 %.2f / %.2f; урон: %s | %s" % [up, lost,
		b.metrics.air_to_ships(Ship.ATTACKER), b.metrics.air_to_ships(Ship.DEFENDER), b.metrics.mid_share(Ship.ATTACKER), b.metrics.mid_share(Ship.DEFENDER),
		b.metrics.shares_text(Ship.ATTACKER), b.metrics.shares_text(Ship.DEFENDER)])
	b.dispose()
