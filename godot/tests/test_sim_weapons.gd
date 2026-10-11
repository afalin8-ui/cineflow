# Модель боя G2: оружие по ролям, урон, ПВО, ракеты, РЭБ, орудие планеты, тактики и
# фокус (план G2, «Проверки»; часть 03, 4.2; часть 04, 4.2; доктрина 09, 1). Каждая
# проверка — с откатом: на копии без правки (флажок отката, правка числа или прежний
# порядок) она обязана краснеть, и краснеть ОТ ТОГО, что проверяет.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Proj := preload("res://sim/proj.gd")
const Weapons := preload("res://sim/weapons.gd")
const Ecm := preload("res://sim/ecm.gd")
const GroundGun := preload("res://sim/ground_gun.gd")
const Movement := preload("res://sim/movement.gd")
const Polygon := preload("res://tools/polygon.gd")

const BIG := 1.0e9

var defs: Defs


func _defs() -> Defs:
	if defs == null:
		defs = Defs.load_default() as Defs
	return defs


## Пустое поле: бой без кораблей, атакующий — att, защитник — dfn.
func _lab(att: StringName = &"troyden", dfn: StringName = &"plektor", setup: Dictionary = {}, d: Defs = null) -> Battle:
	var st := {"attacker": att, "defender": dfn, "size": &"small", "seed": 5, "reserve": false}
	st.merge(setup, true)
	var b := Battle.create(d if d != null else _defs(), st) as Battle
	b.ships.clear()
	return b


## Корабль стороны; нос — на точку look (если задана), обездвижен по желанию.
func _put(b: Battle, side: int, id: StringName, pos: Vector2, look: Variant = null) -> Ship:
	var clan := b.sides[side].clan
	var s := b.spawn(side, b.defs.ship(clan, id), pos)
	if look != null:
		var at: Vector2 = look
		s.set_yaw(Ship.yaw_of(at - pos))
	return s


## Мишень: не летит и не поворачивается (ион «навсегда»), прочность поднята, оружия нет.
func _dummy(s: Ship) -> Ship:
	s.switch_off(&"engines", BIG)
	s.stance = &"hold"
	s.hp = BIG
	s.max_hp = BIG
	s.main_cd = PackedFloat64Array()
	s.sec_cd = PackedFloat64Array()
	s.light_cd = PackedFloat64Array()
	s.mis_cd = PackedFloat64Array()
	s.pd_cd = PackedFloat64Array()
	return s


func _steps(b: Battle, secs: float) -> void:
	for i in roundi(secs / Battle.STEP):
		b.step()


## Шагать secs секунд и собрать события [время, событие].
func _log(b: Battle, secs: float) -> Array:
	var out: Array = []
	for i in roundi(secs / Battle.STEP):
		b.step()
		for e in b.events:
			out.append([b.time, e])
	return out


## Выстрелы из лога: [время, кто, в кого, роль].
static func _shots(log: Array, role: StringName, who: int = -1) -> Array:
	var out: Array = []
	for r: Array in log:
		var e: Array = r[1]
		if e[0] == &"fire" and e[3] == role and (who < 0 or e[1] == who):
			out.append([r[0], e[1], e[2]])
	return out


static func _first(log: Array, kind: StringName) -> float:
	for r: Array in log:
		var e: Array = r[1]
		if e[0] == kind:
			var t: float = r[0]
			return t
	return -1.0


# ───────────────────────── урон по таблице (03, 2.19; 01, 2.16) ─────────────────────────

func _hit(b: Battle, by: Ship, t: Ship, amount: float, key: StringName) -> float:
	return Weapons.damage(b, t, amount, key, by, (t.pos - by.pos).normalized())


func test_damage_table_pairs() -> void:
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0))
	var tf := _put(b, Ship.ATTACKER, &"frigate", Vector2(-300, 0))
	var pc := _put(b, Ship.DEFENDER, &"corvette", Vector2(0, -600))
	var pcr := _put(b, Ship.DEFENDER, &"cruiser", Vector2(300, -600))
	var tco := _put(b, Ship.ATTACKER, &"corvette", Vector2(600, 0))
	for s in [tc, tf, pc, pcr, tco] as Array[Ship]:
		s.hp = BIG
		s.max_hp = BIG
	# пары 03, 2.19 (dmg × множитель × (1 − броня)) — до сотых
	near(_hit(b, tc, pc, tc.def.main.dmg, &"heavy"), 538.04, 0.005, "крейсер Тройдена (473) по корвету Плэктора: 473 × 1,25 × 0,91")
	near(_hit(b, pcr, tco, pcr.def.main.dmg, &"heavy"), 355.94, 0.005, "крейсер Плэктора (335) по корвету Тройдена: 335 × 1,25 × 0,85")
	near(_hit(b, tf, pcr, tf.def.light.dmg, &"light"), 16.97, 0.005, "фрегат Тройдена (73) по крейсеру Плэктора: 73 × 0,30 × 0,775")
	near(_hit(b, tc, pc, tc.def.sec.dmg, &"sec"), 23.66, 0.005, "батарея крейсера Тройдена (26) по корвету Плэктора: 26 × 1,00 × 0,91")
	near(_hit(b, tc, pcr, tc.def.sec.dmg, &"sec"), 6.045, 0.005, "батарея по тяжёлому — ×0,30: 26 × 0,3 × 0,775")
	near(Weapons.damage(b, pcr, 900.0, &"heavy", null, Vector2.ZERO, &"planet"), 697.5, 0.005, "ионный луч по крейсеру Плэктора: 900 × 1,0 × 0,775 (03, 2.19)")
	# переубийство не в счёт: корвет 759, луч планеты даёт 1023,75
	var pc2 := _put(b, Ship.DEFENDER, &"corvette", Vector2(-600, -600))
	near(Weapons.damage(b, pc2, 900.0, &"heavy", null, Vector2.ZERO, &"planet"), 759.0, 1e-9, "ион по корвету Плэктора (1023,75 по формуле) — в учёт ровно 759, переубийство не в счёт")
	ok(pc2.dead and pc2.hp == 0.0, "корвет погиб, прочность 0, а не минус")
	b.dispose()


## Контрольные выстрелы 01, 2.16: выстрелов до гибели из полной прочности.
func _shots_to_kill(b: Battle, by: Ship, t: Ship, amount: float, key: StringName) -> int:
	var n := 0
	while not t.dead and n < 500:
		_hit(b, by, t, amount, key)
		n += 1
	return n


func test_control_shots_01_2_16() -> void:
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0))
	var tcap := _put(b, Ship.ATTACKER, &"capital", Vector2(400, 0))
	var pcr := _put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -600))
	eq(_shots_to_kill(b, tc, _put(b, Ship.DEFENDER, &"corvette", Vector2(0, -500)), tc.def.main.dmg, &"heavy"), 2, "крейсер Тройдена по корвету Плэктора")
	eq(_shots_to_kill(b, tcap, _put(b, Ship.DEFENDER, &"corvette", Vector2(100, -500)), tcap.def.main.dmg, &"heavy"), 1, "флагман Тройдена по корвету Плэктора")
	eq(_shots_to_kill(b, pcr, _put(b, Ship.ATTACKER, &"corvette", Vector2(200, 0)), pcr.def.main.dmg, &"heavy"), 5, "крейсер Плэктора по корвету Тройдена")
	# торпеда Плэктора (260) по флагману Тройдена — 93: правка pd → torpedo меняет урон ПВО
	# по торпеде, а не торпеды по кораблю
	var bomber: Defs.CraftDef = b.defs.factions[&"plektor"].strike[&"bomber"]
	var t2 := _put(b, Ship.ATTACKER, &"capital", Vector2(-400, 0))
	eq(_shots_to_kill(b, pcr, t2, bomber.dmg, bomber.weapon), 93, "торпеда Плэктора по флагману Тройдена")
	near(b.defs.dmg_mult(&"torp", 0), 1.0, 1e-12, "torp → capital по-прежнему 1,0")
	near(b.defs.dmg_mult(&"pd", Defs.CLASSES.find(&"torpedo")), 0.7, 1e-12, "pd → torpedo 0,7 (было 1,4; 09, 4.4)")
	near(bomber.missile_speed, 130.0, 1e-12, "торпеда 130 (было 88; 09, 4.4)")
	b.dispose()


## Ноль в таблице проверяется ВЕЗДЕ (09, 9.5 п. 6): батарея по авиации и ракетам — 0
## в выборе цели, выстреле, damage и hitsStrike; главный калибр по ракетам — 0; ПВО по
## кораблям — 0. Откат — строка батареи с ненулём по машинам: тогда «достаёт авиацию»
## у тяжёлых (и они пошли бы к звену в свою мёртвую зону, 09, 1.3).
func test_zero_in_table_everywhere() -> void:
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0), Vector2(0, -100))
	var tf := _put(b, Ship.ATTACKER, &"frigate", Vector2(-300, 0))
	var strike := Defs.CLASSES.find(&"strike")
	var torp := Defs.CLASSES.find(&"torpedo")
	near(b.defs.dmg_mult(&"sec", strike), 0.0, 0.0, "строка sec: по машинам 0")
	near(b.defs.dmg_mult(&"sec", torp), 0.0, 0.0, "строка sec: по ракетам 0")
	ok(not Weapons.hits_strike(b, tc), "у тяжёлого (главный калибр + батарея) авиацию не достаёт ничто")
	ok(Weapons.hits_strike(b, tf), "контроль: лёгкое орудие фрегата машины достаёт (×0,2)")
	# ракета у самого носа крейсера: батарея её не берёт и урона не наносит
	var pcr := _put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -900))
	var m := Weapons.spawn_proj(b, pcr, tc, 100.0, &"missile", 1.0, 26.0, Vector2(0, 1))
	m.pos = Vector2(0, -60)
	eq(Weapons.damage(b, m, 50.0, &"sec", tc, Vector2.ZERO), 0.0, "damage: батарея по ракете — 0")
	eq(Weapons.damage(b, m, 50.0, &"heavy", tc, Vector2.ZERO), 0.0, "damage: главный калибр по ракете — 0")
	eq(Weapons.damage(b, pcr, 50.0, &"pd", tf, Vector2.ZERO), 0.0, "damage: ПВО по кораблю — 0")
	tc.sec_target = null
	Weapons.think(b, tc)
	ok(tc.sec_target == null, "выбор цели: батарея ракету целью не берёт")
	near(m.hp, 26.0, 0.0, "ракета цела")
	var d2 := Defs.load_default({"space_dmg.sec.strike": 0.2}) as Defs
	if ok(d2.ok, "откат: строка батареи с 0,2 по машинам грузится"):
		var b2 := _lab(&"troyden", &"plektor", {}, d2)
		var c2 := _put(b2, Ship.ATTACKER, &"cruiser", Vector2.ZERO)
		ok(Weapons.hits_strike(b2, c2), "откат «батарея по машинам 0,2»: тяжёлый «достаёт авиацию» — проверка краснеет")
		b2.dispose()
	b.dispose()


# ───────────────────────── главный калибр: мёртвая зона (09, 1.2) ─────────────────────────

func _dead_zone_case(rollback: bool) -> Dictionary:
	Weapons.rollback_no_dead_zone = rollback
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0), Vector2(0, -200))
	tc.switch_off(&"engines", BIG)
	tc.stance = &"hold"
	tc.stealth = true
	tc.sec_cd = PackedFloat64Array()          # батарея молчит: смотрим только на главный калибр
	var pc := _dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -250)))     # 250 < 312
	tc.main_cd = PackedFloat64Array([0.0])
	tc.target = pc                            # даже если цель уже взята — в мёртвой зоне не бьёт
	tc.retarget = BIG
	var log := _log(b, 3.0)
	var out := {"shots": _shots(log, &"main").size(), "cd": tc.main_cd[0], "reveal": tc.reveal_until,
		"first_gun": b.metrics.first_gun, "charge": _first(log, &"charge"), "reason": tc.idle_reason,
		"idle": b.metrics.idle[Ship.ATTACKER].get(&"dead_zone", 0.0)}
	b.dispose()
	Weapons.rollback_no_dead_zone = false
	return out


func test_main_dead_zone_no_shot() -> void:
	var r := _dead_zone_case(false)
	eq(whole(r["shots"]), 0, "цель в 250 (мёртвая зона крейсера 312): главный калибр не стреляет")
	ok(num(r["cd"]) <= 0.0, "перезарядку не тратит: таймер %.2f ≤ 0 — выстрелит сразу, как цель выйдет в пояс" % num(r["cd"]))
	ok(num(r["reveal"]) == 0.0 and num(r["first_gun"]) == 0.0 and num(r["charge"]) < 0.0, "не раскрывает, firstGun не ставит, накачки нет")
	eq(r["reason"], &"dead_zone", "причина молчания — «мёртвая зона»")
	ok(num(r["idle"]) > 2.9, "журнал причин: %.2f с «мёртвая зона»" % num(r["idle"]))
	var o := _dead_zone_case(true)
	ok(whole(o["shots"]) > 0, "откат «без мёртвой зоны»: выстрелов %d — проверка краснеет" % whole(o["shots"]))


# ───────────────────────── батарея (09, 1.3) ─────────────────────────

const SEC_DPS := {
	[&"troyden", &"cruiser"]: 23.1, [&"troyden", &"capital"]: 46.2,
	[&"plektor", &"cruiser"]: 15.2, [&"plektor", &"sinho"]: 22.8, [&"plektor", &"capital"]: 30.4,
	[&"reez", &"cruiser"]: 23.2, [&"reez", &"capital"]: 46.4,
	[&"devian", &"cruiser"]: 17.6, [&"devian", &"capital"]: 35.2,
}


func test_battery_by_clans() -> void:
	var d := _defs()
	for k: Array in SEC_DPS:
		var clan: StringName = k[0]
		var sid: StringName = k[1]
		var s := d.ship(clan, sid)
		var w := s.sec
		var dps := snappedf(w.mounts * w.dmg / w.cd, 0.1)
		near(dps, num(SEC_DPS[k]), 1e-6, "батарея %s.%s: %d × %d / %.2f — урон в секунду" % [k[0], k[1], w.mounts, roundi(w.dmg), w.cd])
		near(w.rng, 0.45 * s.main.rng, 1e-9, "%s.%s: дальность батареи 0,45 R" % [k[0], k[1]])
	var st := d.station
	near(st.main.dead, 368.0, 1e-9, "станция: мёртвая зона главного калибра 368 (09, вопрос 8)")
	ok(st.sec != null and st.sec.mounts == 4 and absf(st.sec.rng - 414.0) < 1e-9 and absf(st.sec.dmg - 24.0) < 1e-9, "станция: батарея 4 × 24 на 414, без множителей клана")
	# в бою: батарея крейсера Тройдена по фрегату Плэктора 60 с — темп установок и урон
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0), Vector2(0, -100))
	tc.switch_off(&"engines", BIG)
	tc.stance = &"hold"
	var cds: PackedFloat64Array = tc.sec_cd.duplicate()
	ok(cds.size() == 2 and cds[0] != cds[1] and cds[0] >= 0.0 and cds[0] < tc.def.sec.cd and cds[1] < tc.def.sec.cd, "две установки, у каждой свой таймер со случайным стартом: %s" % str(cds))
	var pf := _dummy(_put(b, Ship.DEFENDER, &"frigate", Vector2(120, -260)))     # 286: мёртвая зона, в батарее
	var log := _log(b, 60.0)
	var sh := _shots(log, &"sec", tc.uid)
	var want := 2.0 * 60.0 / tc.def.sec.cd
	ok(absf(sh.size() - want) <= 2.0, "за 60 с батарея дала %d выстрелов (2 установки × 60 / 2,25 = %.1f)" % [sh.size(), want])
	var per := tc.def.sec.dmg * 1.0 * (1.0 - pf.def.armor)
	near(BIG - pf.hp, per * sh.size(), 1e-3, "урон по фрегату — ровно выстрелы × 26 × 1,0 × (1 − броня)")
	eq(_shots(log, &"main", tc.uid).size(), 0, "главный калибр по цели в мёртвой зоне молчал все 60 с")
	b.dispose()


# ───────────────────────── конус и разворот (03, 2.20 п. 4) ─────────────────────────

const TURN_REF := {
	&"frigate": [0.03, 0.27, 1.20], &"cruiser": [0.03, 0.47, 2.17],
	&"capital": [0.03, 0.70, 3.33], &"sinho": [0.03, 0.73, 3.63],
}


func _first_shot(id: StringName, deg: float) -> float:
	var clan := &"plektor" if id == &"sinho" else &"troyden"
	var b := _lab(clan, &"troyden" if clan == &"plektor" else &"plektor")
	var s := _put(b, Ship.ATTACKER, id, Vector2.ZERO)
	s.set_yaw(0.0)
	var r0 := s.range0() * 0.68
	var a := deg_to_rad(deg)
	var at := Vector2(-sin(a), -cos(a)) * r0
	var t := _dummy(_put(b, Ship.DEFENDER, &"cruiser", at))
	t.set_yaw(Ship.yaw_of(at))                # кормой к нам — не стреляет
	s.main_cd.fill(0.0)                       # все орудия готовы (03, 2.20 п. 4)
	s.light_cd.fill(0.0)
	b.queue({"op": &"focus", "ids": [s.uid], "target": t.uid})
	var role := &"main" if s.heavy() else &"light"
	var got := -1.0
	for i in roundi(8.0 / Battle.STEP):
		b.step()
		for e in b.events:
			if e[0] == &"fire" and e[1] == s.uid and e[3] == role:
				got = b.time - Battle.STEP       # приказ встал на шаг 1: время от приказа
				break
		if got >= 0.0:
			break
	b.dispose()
	return got


func test_cone_and_turn_2_20_4() -> void:
	var worst := 0.0
	for id: StringName in TURN_REF:
		var refs: Array = TURN_REF[id]
		for k in 3:
			var deg: float = [0.0, 90.0, 180.0][k]
			var got := _first_shot(id, deg) + Battle.STEP
			var want: float = refs[k]
			worst = maxf(worst, absf(got - want))
			ok(got > 0.0 and absf(got - want) <= Battle.STEP + 0.006, "%s, цель под %d°: первый выстрел через %.2f с (JS %.2f, допуск ±1 шаг)" % [id, deg, got, want])
	note("конус и разворот: худшее расхождение с JS %.3f с" % worst)


# ───────────────────────── ПВО и снаряды (03, 2.11–2.12; 09, 1.5–1.6) ─────────────────────────

## «Синхо» Плэктора против фрегата Тройдена на 435 (0,68 × 640), 60 с. С правкой
## pd → torpedo 0,7 (09, 4.4) ракета «Синхо» — класс torpedo — сбивается с двух выстрелов
## фрегата Тройдена, а не с одного: перемерено (план G2).
func _sinho_vs_frigate(with_pd: bool, no_owner: bool = false) -> Dictionary:
	Weapons.rollback_proj_no_owner = no_owner
	var b := _lab(&"troyden", &"plektor")
	var tf := _put(b, Ship.ATTACKER, &"frigate", Vector2(0, 0), Vector2(0, -435))
	tf.switch_off(&"engines", BIG)
	tf.stance = &"hold"
	tf.hp = BIG
	tf.max_hp = BIG
	tf.light_cd = PackedFloat64Array()
	if not with_pd:
		tf.pd_cd = PackedFloat64Array()
	var sh := _put(b, Ship.DEFENDER, &"sinho", Vector2(0, -435), Vector2(0, 0))
	sh.switch_off(&"engines", BIG)
	sh.stance = &"hold"
	sh.hp = BIG
	sh.max_hp = BIG
	sh.main_cd = PackedFloat64Array()        # «с одним ракетным пакетом» (03, 2.20 п. 2)
	sh.sec_cd = PackedFloat64Array()
	sh.mis_cd = PackedFloat64Array([0.0])
	var fired := 0
	var hits := 0
	var pd_on_missiles := 0.0
	for i in roundi(60.0 / Battle.STEP):
		b.step()
		for e in b.events:
			if e[0] == &"proj":
				fired += 1
			elif e[0] == &"proj_hit":
				hits += 1
	pd_on_missiles = b.metrics.to_projs(Ship.ATTACKER)
	var lost := BIG - tf.hp
	var book := 0.0
	for k: StringName in b.metrics.dmg[Ship.DEFENDER]:
		book += b.metrics.to_ships(Ship.DEFENDER, k)
	var out := {"fired": fired, "hits": hits, "pd": pd_on_missiles, "lost": lost, "dealt": sh.dealt,
		"missile_book": b.metrics.to_ships(Ship.DEFENDER, &"missile"), "book": book}
	b.dispose()
	Weapons.rollback_proj_no_owner = false
	return out


func test_pd_vs_sinho_missiles() -> void:
	var r := _sinho_vs_frigate(true)
	eq(whole(r["fired"]), 36, "за 60 с выпущено 36 ракет (12 залпов по 3)")
	ok(whole(r["hits"]) <= 2, "ПВО фрегата Тройдена снимает ракеты «Синхо»: попало %d из 36 (в JS при ×1,4 — 0)" % whole(r["hits"]))
	note("ПВО против «Синхо» после правки pd → torpedo 0,7: попало %d из 36, ПВО набрало %.0f по ракетам" % [whole(r["hits"]), num(r["pd"])])
	var o := _sinho_vs_frigate(false)
	eq(whole(o["hits"]), 36, "откат «без ПВО»: попали все 36 — проверка краснеет")


## Урон снаряда — ВЛАДЕЛЬЦУ (07, ловушка 57; М7 — «все источники, включая ракеты
## «Синхо»», 09, 9.5 п. 11): 36 ракет без ПВО — урон фрегата записан «Синхо» (dealt) и
## в учёт его стороны по ключу missile, сумма по ключам — ровно потерянная прочность.
## Откат — урон снаряда не владельцу (кто = null): учёт пуст.
func test_missile_damage_to_owner() -> void:
	var r := _sinho_vs_frigate(false)
	ok(num(r["lost"]) > 1000.0, "36 ракет «Синхо» попали: фрегат потерял %.1f" % num(r["lost"]))
	near(num(r["dealt"]), num(r["lost"]), 1e-6, "урон ракет записан «Синхо» (dealt %.1f)" % num(r["dealt"]))
	near(num(r["missile_book"]), num(r["lost"]), 1e-6, "учёт стороны Плэктора по ключу missile — весь урон ракет")
	near(num(r["book"]), num(r["lost"]), 1e-6, "сумма по ключам — ровно потерянная прочность (М7)")
	var o := _sinho_vs_frigate(false, true)
	ok(num(o["dealt"]) == 0.0 and num(o["missile_book"]) == 0.0 and num(o["lost"]) > 1000.0, "откат «урон снаряда не владельцу»: учёт пуст (%.1f) при потерянных %.1f — проверка краснеет" % [num(o["missile_book"]), num(o["lost"])])


## Торпеда (класс torpedo) под ПВО — ×0,7, а не ×1,4 (09, 4.4): у фрегата Тройдена
## 22,1 × 0,7 = 15,47 за выстрел — торпеду (34) снимает с трёх, а не с двух.
func test_pd_torpedo_07() -> void:
	var b := _lab()
	var tf := _put(b, Ship.ATTACKER, &"frigate", Vector2(0, 0))
	var pcr := _put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -900))
	var bomber: Defs.CraftDef = b.defs.factions[&"plektor"].strike[&"bomber"]
	var tp := Weapons.spawn_proj(b, pcr, tf, bomber.dmg, bomber.weapon, bomber.missile_speed, bomber.missile_hp, Vector2(0, 1))
	near(Weapons.damage(b, tp, tf.def.pd.dmg, &"pd", tf, Vector2.ZERO), 15.47, 0.005, "выстрел ПВО фрегата Тройдена по торпеде: 22,1 × 0,7")
	var n := 1
	while not tp.dead and n < 10:
		Weapons.damage(b, tp, tf.def.pd.dmg, &"pd", tf, Vector2.ZERO)
		n += 1
	eq(n, 3, "торпеда (34) снята с трёх выстрелов (при ×1,4 — с двух)")
	b.dispose()


## Снаряд попадает ТОЛЬКО в свою цель и по радиусу КЛАССА + 5 (03, ловушка 23):
## корабль на пути он проходит насквозь.
func test_proj_hits_only_own_target() -> void:
	var b := _lab()
	var tf := _dummy(_put(b, Ship.ATTACKER, &"frigate", Vector2(0, 0)))
	var blocker := _dummy(_put(b, Ship.ATTACKER, &"corvette", Vector2(0, -150)))
	var pcr := _dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -900)))
	var p := Weapons.spawn_proj(b, pcr, tf, 100.0, &"missile", 130.0, 26.0, Vector2(0, 1))
	p.pos = Vector2(0, -300)
	var hit_at := Vector2.INF
	for i in roundi(5.0 / Battle.STEP):
		b.step()
		for e in b.events:
			if e[0] == &"proj_hit" and e[1] == p.uid:
				hit_at = e[2]
		if p.dead:
			break
	eq(blocker.hp, BIG, "корабль на пути ракеты цел: она прошла насквозь")
	ok(BIG - tf.hp > 0.0, "ракета попала в свою цель")
	ok(hit_at.distance_to(tf.pos) < tf.def.radius + 5.0 and hit_at.distance_to(tf.pos) > tf.def.radius + 5.0 - 130.0 / 30.0 - 0.01, "попадание — на радиусе класса + 5 (%.1f от центра при радиусе %.1f)" % [hit_at.distance_to(tf.pos), tf.def.radius])
	b.dispose()


## Ракета под чужим куполом слепнет НАВСЕГДА (03, ловушка 24): вылетев из-под купола,
## к цели не доворачивает. Откат — ослепление, пока под куполом.
func _blind_case(rollback: bool) -> Dictionary:
	Weapons.rollback_blind_temporary = rollback
	var b := _lab()
	var te := _put(b, Ship.ATTACKER, &"ecm", Vector2(0, 0))         # купол Тройдена, 420
	_dummy(te)
	var tf := _dummy(_put(b, Ship.ATTACKER, &"frigate", Vector2(900, 0)))
	var pcr := _dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -1500)))
	_steps(b, 0.2)                                                  # купол набрал мощность
	var p := Weapons.spawn_proj(b, pcr, tf, 100.0, &"missile", 130.0, 26.0, Vector2(0, 1))
	p.pos = Vector2(0, -100)                                        # под куполом, летит мимо цели
	b.step()
	var blind_in := p.blind
	p.pos = Vector2(0, -600)                                        # из-под купола
	var dir0 := p.dir
	_steps(b, 1.0)
	var out := {"in": blind_in, "out": p.blind, "turned": rad_to_deg(dir0.angle_to(p.dir))}
	b.dispose()
	Weapons.rollback_blind_temporary = false
	return out


func test_missile_blind_forever() -> void:
	var r := _blind_case(false)
	ok(flag(r["in"]), "ракета под чужим куполом ослепла")
	ok(flag(r["out"]) and absf(num(r["turned"])) < 1e-6, "вылетев из-под купола, она слепа и к цели не доворачивает (поворот %.3f°)" % num(r["turned"]))
	var o := _blind_case(true)
	ok(not flag(o["out"]) and absf(num(o["turned"])) > 1.0, "откат «слепнет, пока под куполом»: прозрела и довернула на %.1f° — проверка краснеет" % num(o["turned"]))


# ───────────────────────── выбор цели (03, 4.2 п. 7; 09, 1.2) ─────────────────────────

func test_target_choice_by_stance_and_fence() -> void:
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"corvette", Vector2(0, 0))
	tc.switch_off(&"engines", BIG)
	var pc := _dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -275)))    # 1,25 × 220
	tc.stance = &"hold"
	ok(Weapons.acquire(b, tc) == null, "«Держать»: цель на 1,25 дальности не берёт (захват 1,0)")
	tc.stance = &"guard"
	ok(Weapons.acquire(b, tc) == pc, "«Охрана»: берёт (захват 1,3)")
	tc.anchor = Vector2(0, 400)                 # участок за кормой: цель за «забором» 240 + 220
	ok(Weapons.acquire(b, tc) == null, "«Охрана»: та же цель за забором участка (650 > 460) — не берёт (03, ловушка 12)")
	tc.anchor = tc.pos
	pc.pos = Vector2(0, -1500)
	ok(Weapons.acquire(b, tc) == null, "«Охрана»: в 1500 — не берёт")
	tc.stance = &"hunt"
	ok(Weapons.acquire(b, tc) == pc, "«Охота»: целей в 1,8 нет — берёт ближайшего на поле")
	b.dispose()


func _main_pick(d: Defs) -> String:
	var b := _lab(&"troyden", &"plektor", {}, d)
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0))
	tc.stance = &"hold"
	_dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -600)))
	_dummy(_put(b, Ship.DEFENDER, &"frigate", Vector2(0, -600).rotated(0.2)))
	var t := Weapons.acquire(b, tc)
	var out := t.def.id if t != null else &"—"
	b.dispose()
	return str(out)


func test_main_target_heavies_first() -> void:
	eq(_main_pick(_defs()), "cruiser", "главный калибр при фрегате и крейсере на одном расстоянии берёт КРЕЙСЕР (вес эскорта 0,6; ОТЛИЧИЕ от JS)")
	var js := Defs.load_default({"main.escort_weight": 1.25}) as Defs
	eq(_main_pick(js), "frigate", "откат «эскорт × 1,25 впереди» (счёт JS m × 1000): берёт фрегат — проверка краснеет")
	# мёртвая зона в выборе: «Охота» не берёт ближайшего под носом, а берёт дальнего
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0))
	tc.stance = &"hunt"
	_dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -200)))
	var far := _dummy(_put(b, Ship.DEFENDER, &"frigate", Vector2(0, -2000)))
	ok(Weapons.acquire(b, tc) == far, "«Охота» тяжёлого: запасной ближайший — НЕ ближе мёртвой зоны (03, 7.2 п. 2)")
	b.dispose()


## До G4 тяжёлый к цели не ходит — своя цель главного калибра СНАЧАЛА в поясе (замечание
## к G2; 09, 1.2 и 6.3 «главный калибр не стоит молча»): крейсер Плэктора в 950 (дальше
## R = 780, но в досягаемости «Охраны» 1,3 R и «Охоты» 1,8 R) и фрегат в 620 (в поясе).
## Откат — прежний захват одним счётом по стойке: крейсер весомее фрегата (вес эскорта
## 0,6), тяжёлый держит его целью и молчит «дальше дальности».
func _belt_first(stance: StringName, rollback: bool) -> Dictionary:
	Weapons.rollback_far_capture = rollback
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0), Vector2(0, -100))
	tc.stance = stance
	tc.hp = BIG
	tc.max_hp = BIG
	tc.sec_cd = PackedFloat64Array()
	var far := _dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -950)))
	var fr := _dummy(_put(b, Ship.DEFENDER, &"frigate", Vector2(300, -543)))     # 620 — в поясе
	var log := _log(b, 20.0)
	var mains := _shots(log, &"main", tc.uid)
	var at_fr := 0
	for m: Array in mains:
		if m[2] == fr.uid:
			at_fr += 1
	var out := {"mains": mains.size(), "at_fr": at_fr, "far_hp": far.hp,
		"too_far": b.metrics.idle[Ship.ATTACKER].get(&"too_far", 0.0), "moved": tc.pos.length()}
	b.dispose()
	Weapons.rollback_far_capture = false
	return out


func test_main_target_in_belt_first() -> void:
	for st: StringName in [&"guard", &"hunt"]:
		var r := _belt_first(st, false)
		ok(whole(r["at_fr"]) >= 2 and whole(r["at_fr"]) == whole(r["mains"]), "«%s»: крейсер в 950 и фрегат в 620 — главный калибр бьёт фрегата в поясе: %d выстрелов из %d за 20 с" % [st, whole(r["at_fr"]), whole(r["mains"])])
		ok(num(r["too_far"]) < 2.0, "«%s»: «дальше дальности» в журнале %.1f с, а не всё время" % [st, num(r["too_far"])])
		ok(num(r["moved"]) < 0.5, "«%s»: с места не сошёл (сдвиг %.2f)" % [st, num(r["moved"])])
		var o := _belt_first(st, true)
		note("«%s»: по фрегату в поясе %d выстрелов, «дальше дальности» %.1f с; откат — %d и %.1f с" % [st, whole(r["at_fr"]), num(r["too_far"]), whole(o["mains"]), num(o["too_far"])])
		ok(whole(o["mains"]) == 0 and num(o["too_far"]) > 10.0, "откат «захват одним счётом до R × reach» («%s»): выстрелов %d, «дальше дальности» %.1f с — проверка краснеет" % [st, whole(o["mains"]), num(o["too_far"])])
	# в поясе никого — дальняя цель «Охоты» остаётся целью (стоит с ней, G4 подведёт)
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0))
	tc.stance = &"hunt"
	var far := _dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -950)))
	ok(Weapons.acquire(b, tc) == far, "в поясе никого: «Охота» берёт дальнего в 950 (дальше пояса, в 1,8 R)")
	tc.stance = &"hold"
	ok(Weapons.acquire(b, tc) == null, "«Держать» (захват 1,0 R): дальнего не берёт")
	b.dispose()


# ───────────────────────── приказы: C100, «Держать», фокус, «Охота» ─────────────────────────

func test_c100_unarmed_hold_position() -> void:
	var b := _lab()
	var car := _put(b, Ship.ATTACKER, &"carrier", Vector2(-300, 0))
	var ecm := _put(b, Ship.ATTACKER, &"ecm", Vector2(300, 0))
	var cru := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0))
	var pc := _dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -700)))
	var p0: Array[Vector2] = [car.pos, ecm.pos]
	b.queue({"op": &"focus", "ids": [car.uid, ecm.uid, cru.uid], "target": pc.uid})
	_steps(b, 5.0)
	ok(car.forced == null and ecm.forced == null, "носитель и РЭБ фокуса не приняли (C100)")
	ok(cru.forced == pc, "крейсер принял фокус")
	ok(car.pos.distance_to(p0[0]) < 1.0 and ecm.pos.distance_to(p0[1]) < 1.0, "безоружные не сдвинулись")
	var said := false
	for t in b.toast_log:
		said = said or str(t["text"]).contains("безоружны — держатся позади")
	ok(said, "полоска «Носитель и РЭБ безоружны — держатся позади»")
	b.dispose()


func _heavy_focus_case(rollback: bool, stance: StringName, dist: float) -> float:
	Movement.rollback_heavy_approach = rollback
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0))
	tc.stance = stance
	var pc := _dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -dist)))
	b.queue({"op": &"focus", "ids": [tc.uid], "target": pc.uid})
	_steps(b, 15.0)
	var moved := tc.pos.length()
	b.dispose()
	Movement.rollback_heavy_approach = false
	return moved


func test_heavy_focus_stays_in_place() -> void:
	for st: StringName in [&"guard", &"hunt", &"hold"]:
		for dist: float in [700.0, 1100.0, 200.0]:
			var m := _heavy_focus_case(false, st, dist)
			ok(m < 0.5, "тяжёлый с фокусом на цель в %d (%s) за 15 с не сошёл с участка: сдвиг %.2f (план G2, п. 4)" % [roundi(dist), st, m])
	var o := _heavy_focus_case(true, &"guard", 700.0)
	ok(o > 100.0, "откат «подход на 0,68 R, как в JS»: от цели в 700 ушёл на %.0f к 530 — проверка краснеет" % o)
	var o2 := _heavy_focus_case(true, &"guard", 1100.0)
	ok(o2 > 100.0, "откат: к цели в 1100 — ушёл на %.0f" % o2)


## Фокус сильнее тактики и тактику не стирает (03, ловушка 16); цель погибла — участок
## там, где корабль стоит (ловушка 13).
func test_focus_keeps_stance_anchor_moves() -> void:
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"corvette", Vector2(0, 0))
	tc.stance = &"guard"
	var pc := _dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -600)))
	pc.hp = 300.0
	pc.max_hp = 300.0
	b.queue({"op": &"focus", "ids": [tc.uid], "target": pc.uid})
	var died_at := Vector2.INF
	for i in roundi(40.0 / Battle.STEP):
		b.step()
		if pc.dead and died_at == Vector2.INF:
			died_at = tc.pos
			b.step()
			break
	eq(tc.stance, &"guard", "фокус тактику не стёр")
	ok(pc.dead, "цель фокуса погибла")
	ok(tc.forced == null and tc.anchor.distance_to(died_at) < 5.0 and tc.anchor.distance_to(Vector2.ZERO) > 200.0, "участок «Охраны» — там, где стоит (%s), а не прежний" % str(tc.anchor))
	b.dispose()


## Безоружный на «Охоте» держится при главном вооружённом (02, ловушка 20; P5): флагман
## ушёл на 600 — носитель идёт с ним, а не стоит посреди боя. Откат — безоружный к
## вожаку не пристраивается (держит свой участок).
func _hunt_lead_case(rollback: bool) -> Dictionary:
	Battle.rollback_hunt_no_lead = rollback
	var b := _lab()
	var car := _put(b, Ship.ATTACKER, &"carrier", Vector2(-300, 0))
	var cru := _put(b, Ship.ATTACKER, &"capital", Vector2(0, 0))
	var cor := _put(b, Ship.ATTACKER, &"corvette", Vector2(200, 0))
	_dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -2500)))
	b.queue({"op": &"stance", "ids": [car.uid, cru.uid, cor.uid], "stance": &"hunt"})
	b.step()
	var lead_ok := car.guard_of == cru and cor.guard_of == null
	b.queue({"op": &"move", "ids": [cru.uid], "x": 600.0, "z": 0.0})
	_steps(b, 30.0)
	var out := {"lead": lead_ok, "gap": car.pos.distance_to(cru.pos), "lead_moved": cru.pos.distance_to(Vector2.ZERO),
		"ring": cru.hull + car.hull + Battle.LEAD_PAD}
	b.dispose()
	Battle.rollback_hunt_no_lead = false
	return out


func test_hunt_unarmed_with_lead() -> void:
	var r := _hunt_lead_case(false)
	ok(flag(r["lead"]), "безоружный носитель на «Охоте» — при главном вооружённом (флагман; 02, ловушка 20), вооружённый корвет охотится сам")
	ok(num(r["lead_moved"]) > 500.0, "флагман ушёл на %.0f" % num(r["lead_moved"]))
	ok(num(r["gap"]) < num(r["ring"]) + 30.0, "носитель держится при нём: %.0f от флагмана (кольцо %.0f)" % [num(r["gap"]), num(r["ring"])])
	var o := _hunt_lead_case(true)
	ok(num(o["gap"]) > 500.0, "откат «безоружный не пристраивается к вожаку»: остался в %.0f от флагмана — проверка краснеет" % num(o["gap"]))


## Без орудий «Охота» = «Охрана» в выборе движения (02, ловушка 21; space.js:1294): у
## безоружного на «Охоте» нет вооружённого рядом — его вынесло со своего участка на 150
## (расталкивание, выход из гипера), и он ВОЗВРАЩАЕТСЯ на участок, а к врагу не идёт.
## Откат — безоружный «охотник» стоит, где его вынесло.
func _unarmed_hunt_case(rollback: bool) -> Dictionary:
	Movement.rollback_unarmed_hunt_stays = rollback
	var b := _lab()
	var car := _put(b, Ship.ATTACKER, &"carrier", Vector2.ZERO)
	var foe := _dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -700)))
	b.queue({"op": &"stance", "ids": [car.uid], "stance": &"hunt"})
	b.step()
	var anchor := car.anchor
	car.pos = Vector2(0, -150)                      # вынесло к врагу
	var closest := INF
	for i in roundi(30.0 / Battle.STEP):
		b.step()
		closest = minf(closest, car.pos.distance_to(foe.pos))
	var out := {"guard_of": car.guard_of, "anchor_d": car.pos.distance_to(anchor), "closest": closest}
	b.dispose()
	Movement.rollback_unarmed_hunt_stays = false
	return out


func test_unarmed_hunt_is_guard() -> void:
	var r := _unarmed_hunt_case(false)
	ok(obj(r["guard_of"]) == null, "носитель один на «Охоте»: вооружённого вожака нет")
	ok(num(r["anchor_d"]) < 15.0, "вернулся на участок: %.1f от него (02, ловушка 21)" % num(r["anchor_d"]))
	ok(num(r["closest"]) >= 549.0, "к врагу не шёл: ближе всего %.0f (вынесло на 550)" % num(r["closest"]))
	var o := _unarmed_hunt_case(true)
	ok(num(o["anchor_d"]) > 100.0, "откат «безоружный охотник стоит, где вынесло»: %.0f от участка — проверка краснеет" % num(o["anchor_d"]))


# ───────────────────────── РЭБ (04, 2.16–2.17; 09, 1.7) ─────────────────────────

func _field_case(att: StringName, dfn: StringName, at: float) -> Array:
	var b := _lab(att, dfn)
	var e := _dummy(_put(b, Ship.DEFENDER, &"ecm", Vector2.ZERO))
	var c := _dummy(_put(b, Ship.ATTACKER, &"corvette", Vector2(at, 0)))
	var on := []
	for i in 3:
		b.step()
		on.append(Ecm.jammed(b, c.pos, Ship.ATTACKER))
	b.dispose()
	return on


func test_ecm_field_numbers() -> void:
	eq(_field_case(&"troyden", &"plektor", 419.0), [false, true, true], "поле 420: в 419 — помехи со ВТОРОГО шага (мощность 0,033 → 0,066)")
	eq(_field_case(&"troyden", &"plektor", 421.0), [false, false, false], "в 421 — помех нет")
	var dev := _defs().factions[&"devian"].ecm
	near(dev.radius, 609.0, 1e-9, "купол Девиана — 609")
	eq(_field_case(&"troyden", &"devian", 608.0), [true, true, true], "Девиан: в 608 — помехи с ПЕРВОГО шага (spinUp 1,5)")
	eq(_field_case(&"troyden", &"devian", 610.0), [false, false, false], "Девиан: в 610 — нет")


func _silence_case(rollback: bool) -> Array:
	Ecm.rollback_mode_by_power = rollback
	var b := _lab()
	var e := _dummy(_put(b, Ship.ATTACKER, &"ecm", Vector2.ZERO))
	var c := _dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(200, 0)))
	_steps(b, 3.0)
	var before := Ecm.jammed(b, c.pos, Ship.DEFENDER)
	b.queue({"op": &"ecm", "ids": [e.uid], "mode": &"off"})
	b.step()
	var after := Ecm.jammed(b, c.pos, Ship.DEFENDER)
	var power := e.ecm_power
	b.dispose()
	Ecm.rollback_mode_by_power = false
	return [before, after, power]


func test_ecm_silence_next_step() -> void:
	var r := _silence_case(false)
	ok(flag(r[0]), "«Глушение»: корвет противника под помехами")
	ok(not flag(r[1]) and num(r[2]) > 0.9, "«Молчать» — помех нет уже на следующем шаге, хотя мощность ещё %.2f" % num(r[2]))
	var o := _silence_case(true)
	ok(flag(o[1]), "откат «глушит, пока есть мощность»: помехи ещё есть — проверка краснеет")


## Тяжёлый под чужим куполом (09, 1.7): к глушителю не идёт ни на какой тактике; главный
## калибр бьёт и дальше lockRange, но таймер перезарядки идёт вдвое медленнее; батарея —
## только ближе lockRange. Откат «старые помехи» — главный калибр молчит (причина
## «помехи»).
func _heavy_dome(stance: StringName, old: bool, focus: bool) -> Dictionary:
	var b := _lab(&"troyden", &"plektor", {"old_ecm": old})
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0), Vector2(0, -600))
	tc.stance = stance
	tc.hp = BIG
	tc.max_hp = BIG
	tc.main_cd = PackedFloat64Array([BIG])
	var jam := _dummy(_put(b, Ship.DEFENDER, &"ecm", Vector2(-260, -160)))       # 305: под куполом, не в батарее (170)
	var pc := _dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -600)))
	var far_l := _dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(250, -40)))  # 253: в батарее, но за lockRange
	_steps(b, 0.2)                                                             # купол набрал мощность
	tc.main_cd = PackedFloat64Array([0.0])
	if focus:
		b.queue({"op": &"focus", "ids": [tc.uid], "target": pc.uid})
	var log := _log(b, 40.0)
	var mains := _shots(log, &"main", tc.uid)
	var gaps := PackedFloat64Array()
	for i in range(1, mains.size()):
		gaps.append(num(mains[i][0]) - num(mains[i - 1][0]))
	var out := {"moved": tc.pos.length(), "mains": mains.size(), "gaps": gaps,
		"sec_far": _shots(log, &"sec", tc.uid).size(), "jam_hp": jam.hp, "far_hp": far_l.hp,
		"idle_jam": b.metrics.idle[Ship.ATTACKER].get(&"jam", 0.0), "jammed": tc.jam != null}
	# вплотную подошёл корвет — батарея по нему бьёт (ближе lockRange)
	far_l.pos = Vector2(120, -60)
	var log2 := _log(b, 8.0)
	out["sec_near"] = _shots(log2, &"sec", tc.uid).size()
	b.dispose()
	return out


func test_heavy_under_dome() -> void:
	for st: StringName in [&"hold", &"guard", &"hunt"]:
		for focus: bool in [false, true]:
			var r := _heavy_dome(st, false, focus)
			ok(flag(r["jammed"]), "крейсер под чужим куполом (%s%s)" % [st, ", фокус" if focus else ""])
			ok(num(r["moved"]) < 0.5, "%s%s: к глушителю не пошёл (сдвиг %.2f)" % [st, ", фокус" if focus else "", num(r["moved"])])
			ok(whole(r["mains"]) >= 2, "%s: главный калибр бьёт на 600 (дальше lockRange 170): %d выстрелов за 40 с" % [st, whole(r["mains"])])
			var gaps: PackedFloat64Array = r["gaps"]
			ok(gaps.size() > 0 and absf(gaps[0] - 16.2) <= Battle.STEP + 1e-6, "%s: между выстрелами %.2f с — перезарядка 8,1 вдвое медленнее" % [st, gaps[0] if gaps.size() > 0 else -1.0])
			eq(whole(r["sec_far"]), 0, "%s: батарея по корвету в 253 (за lockRange) молчит" % st)
			ok(whole(r["sec_near"]) > 0, "%s: корвет подошёл на 134 — батарея бьёт" % st)
			ok(num(r["jam_hp"]) == BIG, "%s: глушитель не тронут" % st)
	var o := _heavy_dome(&"hold", true, false)
	eq(whole(o["mains"]), 0, "откат «старые помехи»: главный калибр под куполом молчит — проверка краснеет")
	ok(num(o["idle_jam"]) > 30.0, "…и журнал называет причину «помехи» (%.1f с)" % num(o["idle_jam"]))


## Медленнее идёт ТАЙМЕР, а не «перезарядка × k после выстрела» (09, 1.7): вышедший
## из-под купола посреди перезарядки сразу стреляет в обычном темпе.
func _slow_timer(rollback: bool) -> float:
	Weapons.rollback_slow_cd = rollback
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0), Vector2(0, -600))
	tc.stance = &"hold"
	tc.hp = BIG
	tc.max_hp = BIG
	tc.main_cd = PackedFloat64Array([BIG])
	var jam := _dummy(_put(b, Ship.DEFENDER, &"ecm", Vector2(-260, -160)))
	_dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -600)))
	_steps(b, 0.2)                                    # купол набрал мощность — выстрел уже под помехами
	tc.main_cd = PackedFloat64Array([0.0])
	var t1 := -1.0
	var t2 := -1.0
	for i in roundi(30.0 / Battle.STEP):
		b.step()
		for e in b.events:
			if e[0] == &"fire" and e[3] == &"main":
				if t1 < 0.0:
					t1 = b.time
				elif t2 < 0.0:
					t2 = b.time
		if t1 > 0.0 and absf(b.time - (t1 + 4.0)) < 1e-6:
			jam.ecm_mode = &"off"                 # глушитель замолчал через 4 с после выстрела
		if t2 > 0.0:
			break
	b.dispose()
	Weapons.rollback_slow_cd = false
	return t2 - t1


func test_jam_slows_timer_not_cd() -> void:
	var g := _slow_timer(false)
	near(g, 4.0 + (8.1 - 4.0 / 2.0) + Battle.STEP, 2.0 * Battle.STEP, "4 с под помехами (2 с перезарядки) + 6,1 в обычном темпе: следующий выстрел через %.2f с" % g)
	var o := _slow_timer(true)
	ok(absf(o - g) > 3.0, "откат «перезарядка × 2 после выстрела»: через %.2f с — проверка краснеет" % o)


## Лёгкий под помехами бьёт глушителя (03, ловушки 5–6): «Охрана» — если дотянется,
## не сходя с поводка; «Держать» — не идёт (ловушка 8). Откат — «Держать» тоже идёт.
func _light_jam(stance: StringName, jam_at: Vector2, rollback: bool) -> Dictionary:
	Movement.rollback_hold_approach = rollback
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"corvette", Vector2(0, 0), Vector2(0, -300))
	tc.stance = stance
	tc.hp = BIG
	tc.max_hp = BIG
	var jam := _dummy(_put(b, Ship.DEFENDER, &"ecm", jam_at))
	jam.hp = 1700.0
	jam.max_hp = 1700.0
	_dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(2000, -2000)))
	_steps(b, 25.0)
	var out := {"moved": tc.pos.length(), "jam_hurt": 1700.0 - jam.hp, "target": tc.target == jam}
	b.dispose()
	Movement.rollback_hold_approach = false
	return out


func test_light_under_dome() -> void:
	var g := _light_jam(&"guard", Vector2(0, -300), false)
	ok(num(g["jam_hurt"]) > 0.0 and num(g["moved"]) > 100.0, "«Охрана»: глушитель в 300 (поводок 240 + 136) — подошла и бьёт его (урон %.0f)" % num(g["jam_hurt"]))
	# глушитель в 450 при поле 420: корвет ВНЕ купола — помех нет, глушитель обычная цель
	# дальше захвата «Охраны» (286). Поводок к глушителю ПОД куполом — test_guard_jammer_beyond_leash
	var far := _light_jam(&"guard", Vector2(0, -450), false)
	ok(num(far["moved"]) < 5.0 and num(far["jam_hurt"]) == 0.0, "«Охрана»: глушитель в 450 — корвет вне купола, цель дальше захвата: не идёт (сдвиг %.1f)" % num(far["moved"]))
	var h := _light_jam(&"hold", Vector2(0, -300), false)
	ok(num(h["moved"]) < 5.0 and num(h["jam_hurt"]) == 0.0, "«Держать» к глушителю не идёт (сдвиг %.1f; 03, ловушка 8)" % num(h["moved"]))
	var o := _light_jam(&"hold", Vector2(0, -300), true)
	ok(num(o["moved"]) > 100.0, "откат «Держать тоже вольный»: ушёл на %.0f — проверка краснеет" % num(o["moved"]))


# ───────────────────────── журнал причин (03, 7.5) ─────────────────────────

func _reason(setup: Callable) -> StringName:
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0), Vector2(0, -100))
	tc.switch_off(&"engines", BIG)
	tc.hp = BIG
	tc.max_hp = BIG
	tc.main_cd = PackedFloat64Array([0.0])
	tc.sec_cd = PackedFloat64Array()
	setup.call(b, tc)
	_steps(b, 1.0)
	var best: StringName = &""
	var bv := 0.0
	var idle: Dictionary = b.metrics.idle[Ship.ATTACKER]
	for k: StringName in idle:
		var v: float = idle[k]
		if v > bv:
			bv = v
			best = k
	b.dispose()
	return best


func test_idle_reasons() -> void:
	eq(_reason(func(b: Battle, _s: Ship) -> void: _dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -200)))), &"dead_zone", "чужой вплотную, цели в поясе нет — «мёртвая зона»")
	eq(_reason(func(b: Battle, _s: Ship) -> void: _dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -2000)))), &"no_target", "никого в досягаемости — «нет цели»")
	eq(_reason(func(b: Battle, s: Ship) -> void:
		s.stance = &"hunt"
		_dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -1200)))), &"too_far", "«Охота» взяла цель в 1200 — «дальше дальности»")
	eq(_reason(func(b: Battle, _s: Ship) -> void: _dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, 600)))), &"cone", "цель за кормой, разворота нет — «вне конуса»")
	var b0 := Battle.create(_defs(), {"old_ecm": true}) as Battle
	ok(b0.old_ecm, "флажок отката «старые помехи» доходит до боя")
	b0.dispose()


# ───────────────────────── орудие планеты (03, 2.17) ─────────────────────────

func _gun_lab(att: StringName, dfn: StringName) -> Battle:
	var b := _lab(att, dfn, {"ground_gun": "defender"})
	_dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(2000, -2400)))   # у защитника кто-то есть
	return b


func _gun_times(rollback: bool) -> Array:
	GroundGun.rollback_first_full = rollback
	var b := _gun_lab(&"troyden", &"plektor")
	var t := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0))
	t.hp = BIG
	t.max_hp = BIG
	t.switch_off(&"engines", BIG)
	var log := _log(b, 40.0)
	b.dispose()
	GroundGun.rollback_first_full = false
	return [_first(log, &"gun_warn"), _first(log, &"gun_fire")]


func test_ground_gun_first_salvo() -> void:
	var r := _gun_times(false)
	near(num(r[1]), 34.0 * 0.7, Battle.STEP + 1e-6, "ядерная Плэктора: первый залп на 0,7 периода (23,8 с)")
	near(num(r[0]), 34.0 * 0.7 - 7.0, Battle.STEP + 1e-6, "предупреждение — за 7 с до залпа")
	var o := _gun_times(true)
	ok(num(o[1]) < 0.0 or num(o[1]) > 30.0, "откат «первый залп через период»: залпа к 23,8 с нет — проверка краснеет")


func test_ground_gun_nuke_area() -> void:
	var b := _gun_lab(&"troyden", &"plektor")
	var list: Array[Ship] = []
	for x: float in [0.0, 95.0, 200.0]:
		var s := _put(b, Ship.ATTACKER, &"cruiser", Vector2(x * 1.0, 0.0) if x != 95.0 else Vector2(0.0, 95.0))
		s.switch_off(&"engines", BIG)
		s.stance = &"hold"
		s.hp = BIG
		s.max_hp = BIG
		list.append(s)
	while b.gun.next - b.time > 0.5:
		b.step()
	b.gun.warned = true
	b.gun.has_aim = true
	b.gun.aim = Vector2.ZERO                  # наводка — точно в первый крейсер
	_steps(b, 1.0)
	var full := 1500.0 * 1.0 * (1.0 - list[0].def.armor)
	near(BIG - list[0].hp, full, 1e-3, "в центре — полный урон 1500 × (1 − броня)")
	near(BIG - list[1].hp, full * 0.5, 1e-3, "в 95 — половина")
	near(BIG - list[2].hp, 0.0, 0.0, "в 200 (радиус 190) — ноль")
	near(b.metrics.to_ships(Ship.DEFENDER, &"planet"), full * 1.5, 1e-3, "урон планеты — отдельной строкой учёта (М7)")
	b.dispose()


func test_ground_gun_ion() -> void:
	var b := _gun_lab(&"plektor", &"troyden")       # ион — у планеты Тройдена
	var pc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0))
	pc.hp = BIG
	pc.max_hp = BIG
	var fire_t := -1.0
	for i in roundi(30.0 / Battle.STEP):
		b.step()
		for e in b.events:
			if e[0] == &"gun_fire":
				fire_t = b.time
		if fire_t > 0.0:
			break
	near(fire_t, 26.0 * 0.7, Battle.STEP + 1e-6, "ионный луч: первый залп на 18,2 с")
	near(BIG - pc.hp, 900.0 * (1.0 - pc.def.armor), 1e-3, "урон луча 900 × (1 − броня)")
	ok(pc.is_off(&"engines", fire_t + 9.9) and not pc.is_off(&"engines", fire_t + 10.05), "двигатели выключены ровно на 10 с")
	var yaw0 := pc.yaw
	var v0 := pc.vel
	b.queue({"op": &"move", "ids": [pc.uid], "x": 600.0, "z": 400.0})
	_steps(b, 5.0)
	ok(absf(pc.yaw - yaw0) < 1e-9 and pc.vel.distance_to(v0) < 1e-9, "под ионом нет ни тяги, ни разворота (02, ловушка 25)")
	_steps(b, 6.0)
	ok(pc.vel.length() > 1.0, "через 10 с полетел")
	b.dispose()


# ───────────────────────── учёт урона без остатка (М7; 09, 9.5 п. 11) ─────────────────────────

func _m7(rollback: bool) -> Dictionary:
	Weapons.rollback_no_planet_book = rollback
	# показательная «Перестрелка» (все приказы, планета, «Синхо») — 150 с: 60 с приказов
	# показательной записи и дальше без них; снаряды собираем по ходу: мёртвые уходят
	# из списка в конце шага. Раньше здесь стоял demo_battle(…, 0) — НОЛЬ шагов приказов:
	# бой без единого приказа, и ракет «Синхо» в нём не было вовсе (замечание к G2)
	var seen: Dictionary[int, Proj] = {}
	var grab := func(bb: Battle) -> void:
		for p in bb.projs:
			seen[p.uid] = p
	var b := Polygon.demo_battle(_defs(), "capella-проверка", Polygon.DEMO_STEPS, grab)
	for i in roundi(150.0 / Battle.STEP) - Polygon.DEMO_STEPS:
		b.step()
		grab.call(b)
	var lost_ships := 0.0
	for s in b.ships:
		lost_ships += s.max_hp - s.hp
	var lost_projs := 0.0
	for u: int in seen:
		lost_projs += seen[u].max_hp - seen[u].hp
	var by_key := 0.0
	var proj_book := 0.0
	var keys := {}
	for side in 2:
		proj_book += b.metrics.to_projs(side)
		for k: StringName in b.metrics.dmg[side]:
			var v := b.metrics.to_ships(side, k)
			by_key += v
			keys[k] = num(keys.get(k, 0.0)) + v
	var out := {"ships": lost_ships, "book": by_key, "projs": lost_projs, "proj_book": proj_book, "keys": keys,
		"first_gun": b.metrics.first_gun, "first_hit": b.metrics.first_hit, "shares": b.metrics.shares_text(Ship.ATTACKER) + " | " + b.metrics.shares_text(Ship.DEFENDER),
		"idle": b.metrics.idle_text(Ship.ATTACKER) + " | " + b.metrics.idle_text(Ship.DEFENDER)}
	b.dispose()
	Weapons.rollback_no_planet_book = false
	return out


func test_m7_damage_without_remainder() -> void:
	var r := _m7(false)
	near(num(r["book"]), num(r["ships"]), 1e-6, "М7: урон по кораблям по ключам (%.1f) = потерянной прочности (%.1f)" % [num(r["book"]), num(r["ships"])])
	near(num(r["proj_book"]), num(r["projs"]), 1e-6, "урон по ракетам — отдельно, и тоже без остатка (%.1f)" % num(r["projs"]))
	var keys: Dictionary = r["keys"]
	for k: StringName in [&"heavy", &"sec", &"light", &"missile", &"planet"]:
		ok(num(keys.get(k, 0.0)) > 0.0, "в «Перестрелке» за 150 с урон есть у ключа %s (%.0f)" % [k, num(keys.get(k, 0.0))])
	ok(num(r["proj_book"]) > 0.0, "ПВО сбивало ракеты «Синхо»")
	ok(num(r["first_gun"]) > 0.0 and num(r["first_gun"]) <= 90.0, "первый выстрел главного калибра на %.1f с (М11: ≤ 90)" % num(r["first_gun"]))
	note("Перестрелка 150 с: урон %s; молчание главного калибра: %s" % [str(r["shares"]), str(r["idle"])])
	var o := _m7(true)
	ok(absf(num(o["book"]) - num(o["ships"])) > 100.0, "откат «урон планеты не в учёте»: остаток %.0f — проверка краснеет" % (num(o["ships"]) - num(o["book"])))


# ───────────────────────── выстрел раскрывает; перезарядка; firstGun ─────────────────────────

## Каждый выстрел раскрывает (09, 9.5 п. 7; 03, ловушка 25): у КАЖДОГО источника свой
## скрытный стрелок и свой откат — откат одного источника обязан краснеть ровно в нём
## (замечание к G2: прежняя проверка ставила скрытность только батарее и ПВО, и откат
## «главный калибр не раскрывает» проходил зелёным).
## kind: &"main" — крейсер по крейсеру в поясе; &"light" — корвет по корвету; &"missile" —
## «Синхо» пускает ракеты; &"sec" — цель в мёртвой зоне, бьёт только батарея; &"pd" —
## безоружный РЭБ с ракетой рядом, бьёт только ПВО.
const REVEAL_FLAGS := {&"main": "rollback_quiet_main", &"light": "rollback_quiet_light",
	&"missile": "rollback_quiet_missile", &"sec": "rollback_quiet_shots", &"pd": "rollback_quiet_shots"}


static func _quiet_flag(kind: StringName, on: bool) -> void:
	match kind:
		&"main":
			Weapons.rollback_quiet_main = on
		&"light":
			Weapons.rollback_quiet_light = on
		&"missile":
			Weapons.rollback_quiet_missile = on
		_:
			Weapons.rollback_quiet_shots = on


func _reveal_case(kind: StringName, rollback: bool) -> Dictionary:
	_quiet_flag(kind, rollback)
	var b := _lab()
	var me: Ship = null
	match kind:
		&"main":
			me = _put(b, Ship.ATTACKER, &"cruiser", Vector2.ZERO, Vector2(0, -600))
			me.sec_cd = PackedFloat64Array()
			me.main_cd = PackedFloat64Array([0.0])
			_dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -600)))
		&"light":
			me = _put(b, Ship.ATTACKER, &"corvette", Vector2.ZERO, Vector2(0, -150))
			me.light_cd = PackedFloat64Array([0.0])
			_dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -150)))
		&"missile":
			me = _put(b, Ship.DEFENDER, &"sinho", Vector2.ZERO, Vector2(0, 435))
			me.main_cd = PackedFloat64Array()
			me.sec_cd = PackedFloat64Array()
			me.mis_cd = PackedFloat64Array([0.0])
			_dummy(_put(b, Ship.ATTACKER, &"frigate", Vector2(0, 435)))
		&"sec":
			me = _put(b, Ship.ATTACKER, &"cruiser", Vector2.ZERO, Vector2(0, -100))
			me.main_cd = PackedFloat64Array([0.0])
			_dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -250)))     # мёртвая зона: только батарея
		&"pd":
			me = _put(b, Ship.ATTACKER, &"ecm", Vector2.ZERO)
			var pcr := _dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -2000)))
			var p := Weapons.spawn_proj(b, pcr, me, 1.0, &"missile", 1.0, 1000.0, Vector2(0, 1))
			p.pos = Vector2(0, -60)
	me.switch_off(&"engines", BIG)
	me.stance = &"hold"
	me.stealth = true
	me.hp = BIG
	me.max_hp = BIG
	var roles: Dictionary = {}
	var log := _log(b, 1.5)
	for r: Array in log:
		var e: Array = r[1]
		if e[0] == &"fire" and e[1] == me.uid:
			roles[e[3]] = true
		elif e[0] == &"pd" and e[1] == me.uid:
			roles[&"pd"] = true
		elif e[0] == &"proj" and kind == &"missile":
			roles[&"missile"] = true
	var out := {"revealed": me.reveal_until > 0.0, "roles": roles.keys()}
	b.dispose()
	_quiet_flag(kind, false)
	return out


func test_every_shot_reveals() -> void:
	for kind: StringName in REVEAL_FLAGS:
		var r := _reveal_case(kind, false)
		var roles: Array = r["roles"]
		ok(roles == [kind], "%s: стрелял ровно этот источник (%s)" % [kind, str(roles)])
		ok(flag(r["revealed"]), "%s: выстрел раскрывает скрытного стрелка" % kind)
		var o := _reveal_case(kind, true)
		ok(not flag(o["revealed"]), "откат «%s не раскрывает» (%s): не раскрыт — проверка краснеет" % [kind, REVEAL_FLAGS[kind]])


# ───────────────────────── РЭБ: «Прикрытие», глушитель первым, поводок, ПВО ─────────────────────────

## Своё «Прикрытие» над кораблём снимает чужие помехи (04, 2.16; план G2, п. 5).
## Откат — щит не действует.
func _shield_case(own_mode: StringName, rollback: bool) -> Dictionary:
	Ecm.rollback_no_shield = rollback
	var b := _lab()
	_dummy(_put(b, Ship.DEFENDER, &"ecm", Vector2(0, -250)))              # чужое «Глушение»
	var me := _dummy(_put(b, Ship.ATTACKER, &"ecm", Vector2(0, 150)))      # своё поле, 420
	me.ecm_mode = own_mode
	var c := _put(b, Ship.ATTACKER, &"corvette", Vector2.ZERO, Vector2(0, -250))
	c.switch_off(&"engines", BIG)
	c.stance = &"hold"
	c.light_cd = PackedFloat64Array()
	_steps(b, 0.3)                                                         # оба поля набрали мощность
	var out := {"jammed": Ecm.jammed(b, c.pos, Ship.ATTACKER), "jam": c.jam != null,
		"shield_on": me.ecm_power > Ecm.ACTIVE}
	b.dispose()
	Ecm.rollback_no_shield = false
	return out


func test_ecm_shield_cancels_jam() -> void:
	var r := _shield_case(&"shield", false)
	ok(flag(r["shield_on"]), "своё «Прикрытие» поднято")
	ok(not flag(r["jammed"]) and not flag(r["jam"]), "корвет под своим «Прикрытием» и чужим «Глушением» — помех нет")
	var ctl := _shield_case(&"off", false)
	ok(flag(ctl["jammed"]) and flag(ctl["jam"]), "контроль: своё поле молчит — помехи есть")
	var o := _shield_case(&"shield", true)
	ok(flag(o["jammed"]), "откат «щит не снимает помех»: помехи есть — проверка краснеет")


## Под помехами первым — сам глушитель (03, 2.9; 09, 1.7): своя цель лёгкого — раненый
## фрегат в 210 (дальше lockRange 170), рядом в 160 — целый корвет (ближе, его счёт выше
## обычной цели), глушитель — в 300. Лёгкий берёт ГЛУШИТЕЛЯ. Откат — счёт глушителя без
## 3000 (как у обычной цели): берёт корвет.
func _jammer_first(rollback: bool) -> Dictionary:
	Weapons.rollback_jammer_not_first = rollback
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"corvette", Vector2.ZERO, Vector2(0, -200))
	tc.switch_off(&"engines", BIG)
	tc.stance = &"guard"
	tc.light_cd = PackedFloat64Array()
	var jam := _dummy(_put(b, Ship.DEFENDER, &"ecm", Vector2(0, -300)))
	var fr := _dummy(_put(b, Ship.DEFENDER, &"frigate", Vector2(-210, 0)))
	fr.hp = 1.0                                       # раненый: +400 к счёту — своя цель
	var co := _dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(160, 0)))
	_steps(b, 0.3)
	var out := {"jam": tc.jam != null, "target": tc.target, "jam_shot": tc.jam_shot, "jammer": jam, "corvette": co, "frigate": fr}
	b.dispose()
	Weapons.rollback_jammer_not_first = false
	return out


func test_jammer_first() -> void:
	var r := _jammer_first(false)
	ok(flag(r["jam"]), "корвет под чужим «Глушением»")
	ok(obj(r["target"]) == obj(r["jammer"]) and obj(r["jam_shot"]) == obj(r["jammer"]), "лёгкий бьёт глушителя первым (а не корвет в 160 и не свою цель в 210)")
	var o := _jammer_first(true)
	ok(obj(o["target"]) == obj(o["corvette"]), "откат «глушитель без 3000»: берёт корвет — проверка краснеет")


## Цель «под помехами» — временная (03, ловушка 7): глушитель замолчал — лёгкий
## снимает jam_shot и берёт свою цель заново (раненый фрегат в 200). Откат — jam_shot
## держится, и лёгкий так и бьёт глушителя.
func _jam_shot_case(rollback: bool) -> Dictionary:
	Weapons.rollback_jam_shot_sticks = rollback
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"corvette", Vector2.ZERO, Vector2(0, -200))
	tc.switch_off(&"engines", BIG)
	tc.stance = &"guard"
	tc.light_cd = PackedFloat64Array()
	var jam := _dummy(_put(b, Ship.DEFENDER, &"ecm", Vector2(0, -300)))
	var fr := _dummy(_put(b, Ship.DEFENDER, &"frigate", Vector2(-200, 0)))
	fr.hp = 1.0
	_steps(b, 0.3)
	var under := {"target": tc.target == jam, "jam_shot": tc.jam_shot == jam}
	tc.retarget = BIG                                  # плановый пересмотр не мешает: смотрим правило
	jam.ecm_mode = &"off"
	_steps(b, 2.0 * Battle.STEP)                       # «Молчать» — помех нет со следующего шага
	var out := {"under": under, "jam": tc.jam != null, "jam_shot": tc.jam_shot, "target": tc.target, "jammer": jam, "frigate": fr}
	b.dispose()
	Weapons.rollback_jam_shot_sticks = false
	return out


func test_jam_shot_temporary() -> void:
	var r := _jam_shot_case(false)
	var under: Dictionary = r["under"]
	ok(flag(under["target"]) and flag(under["jam_shot"]), "под помехами лёгкий взял глушителя («цель под помехами»)")
	ok(not flag(r["jam"]) and obj(r["jam_shot"]) == null and obj(r["target"]) == obj(r["frigate"]), "глушитель замолчал: jam_shot снят, лёгкий вернулся к своей цели (раненый фрегат)")
	var o := _jam_shot_case(true)
	ok(obj(o["jam_shot"]) == obj(o["jammer"]) and obj(o["target"]) == obj(o["jammer"]), "откат «цель под помехами держится»: бьёт молчащего глушителя — проверка краснеет")


## «Охрана» к глушителю — только если дотянется (03, ловушка 6): корвет ПОД куполом
## (глушитель в 400 < 420), но глушитель дальше поводка 240 + 0,8 × 170 = 376 — не идёт.
## Откат — «Охрана» идёт к глушителю, где бы он ни был.
func _guard_leash_jam(rollback: bool) -> Dictionary:
	Weapons.rollback_guard_jam_any = rollback
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"corvette", Vector2.ZERO, Vector2(0, -300))
	tc.stance = &"guard"
	tc.hp = BIG
	tc.max_hp = BIG
	var jam := _dummy(_put(b, Ship.DEFENDER, &"ecm", Vector2(0, -400)))
	jam.hp = 1700.0
	jam.max_hp = 1700.0
	_dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(2000, -2000)))
	_steps(b, 0.3)
	var under := tc.jam != null
	_steps(b, 20.0)
	var out := {"under": under, "moved": tc.pos.length(), "jam_hurt": 1700.0 - jam.hp}
	b.dispose()
	Weapons.rollback_guard_jam_any = false
	return out


func test_guard_jammer_beyond_leash() -> void:
	var r := _guard_leash_jam(false)
	ok(flag(r["under"]), "корвет под чужим куполом (глушитель в 400, поле 420)")
	ok(num(r["moved"]) < 5.0 and num(r["jam_hurt"]) == 0.0, "«Охрана»: глушитель дальше поводка (400 > 376) — не идёт (сдвиг %.1f)" % num(r["moved"]))
	var o := _guard_leash_jam(true)
	ok(num(o["moved"]) > 100.0, "откат «Охрана к глушителю без поводка»: ушла на %.0f — проверка краснеет" % num(o["moved"]))


## ПВО под чужим куполом бьёт слабее: урон × pdPenalty (09, 1.5 и 1.7; 04, 2.17) — и у
## безоружного тоже. Откат — множитель 1.
func _pd_under_dome(dome: bool, rollback: bool) -> float:
	Weapons.rollback_no_pd_penalty = rollback
	var b := _lab()
	var tf := _dummy(_put(b, Ship.ATTACKER, &"frigate", Vector2.ZERO))
	tf.pd_cd = PackedFloat64Array([BIG])
	if dome:
		_dummy(_put(b, Ship.DEFENDER, &"ecm", Vector2(0, -300)))
	var pcr := _dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -2000)))
	_steps(b, 0.3)
	var p := Weapons.spawn_proj(b, pcr, tf, 1.0, &"missile", 1.0, 1000.0, Vector2(0, 1))
	p.pos = Vector2(0, -60)
	tf.pd_cd = PackedFloat64Array([0.0])
	var got := 0.0
	for i in 10:
		b.step()
		if p.hp < p.max_hp:
			got = p.max_hp - p.hp
			break
	b.dispose()
	Weapons.rollback_no_pd_penalty = false
	return got


func test_pd_penalty_under_dome() -> void:
	var free := _pd_under_dome(false, false)
	var jam := _pd_under_dome(true, false)
	var pen := _defs().factions[&"plektor"].ecm.pd_penalty
	ok(free > 0.0, "контроль: ПВО без помех сбивает ракету (%.2f за выстрел)" % free)
	near(jam, free * pen, 1e-6, "ПВО под чужим куполом — × pdPenalty %.2f (%.2f за выстрел)" % [pen, jam])
	var o := _pd_under_dome(true, true)
	near(o, free, 1e-6, "откат «ПВО под помехами в полную силу»: %.2f — проверка краснеет" % o)
	ok(absf(o - jam) > 1.0, "…и это не та же величина, что с правкой")


func _reload_case(rollback: bool) -> Dictionary:
	Weapons.rollback_freeze_cd = rollback
	var b := _lab()
	var tc := _put(b, Ship.ATTACKER, &"corvette", Vector2(0, 0), Vector2(0, -150))
	tc.switch_off(&"engines", BIG)
	tc.stance = &"hold"
	tc.light_cd = PackedFloat64Array([1.0])
	var pc := _dummy(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -2000)))
	_steps(b, 10.0)
	var cd_idle := tc.light_cd[0]
	pc.pos = Vector2(0, -150)                    # цель вышла под нос
	var t0 := b.time
	var shot := -1.0
	var cd_after := -1.0
	for i in roundi(3.0 / Battle.STEP):
		b.step()
		if tc.dealt > 0.0:
			shot = b.time - t0
			cd_after = tc.light_cd[0]
			break
	b.dispose()
	Weapons.rollback_freeze_cd = false
	return {"idle": cd_idle, "shot": shot, "cd": cd_after, "def": tc.def.light.cd}


func test_reload_always_then_exact_cd() -> void:
	var r := _reload_case(false)
	ok(num(r["idle"]) < -5.0, "без цели перезарядка шла: таймер %.2f" % num(r["idle"]))
	ok(num(r["shot"]) > 0.0 and num(r["shot"]) <= 2.0 * Battle.STEP + 1e-6, "цель появилась — выстрел через %.3f с (03, ловушка 19)" % num(r["shot"]))
	ok(absf(num(r["cd"]) - (num(r["def"]) - 0.0)) < 1e-9, "после выстрела таймер ровно cd = %.2f (а не cd + минус)" % num(r["cd"]))
	var o := _reload_case(true)
	ok(num(o["shot"]) < 0.0 or num(o["shot"]) > 0.5, "откат «перезарядка без цели стоит»: выстрел через %.2f с — проверка краснеет" % num(o["shot"]))


## firstGun — первый выстрел ГЛАВНОГО калибра по КОРАБЛЮ (03, ловушка 34): лёгкие его не
## ставят. Сверка — с временем первого выстрела главного калибра в журнале событий.
func test_first_gun_main_only() -> void:
	var b := _lab()
	var tl := _put(b, Ship.ATTACKER, &"corvette", Vector2(0, 0), Vector2(0, -150))
	tl.switch_off(&"engines", BIG)
	tl.light_cd = PackedFloat64Array([0.0])
	_dummy(_put(b, Ship.DEFENDER, &"frigate", Vector2(0, -150)))
	var tc := _put(b, Ship.ATTACKER, &"cruiser", Vector2(1000, 0), Vector2(1000, -600))
	tc.switch_off(&"engines", BIG)
	tc.main_cd = PackedFloat64Array([3.0])
	_dummy(_put(b, Ship.DEFENDER, &"cruiser", Vector2(1000, -600)))
	var log := _log(b, 6.0)
	var light := _shots(log, &"light")
	var main := _shots(log, &"main")
	ok(light.size() > 0 and main.size() > 0 and num(light[0][0]) < num(main[0][0]), "лёгкий выстрелил раньше главного калибра")
	near(b.metrics.first_gun, num(main[0][0]) if main.size() > 0 else -1.0, 1e-9, "firstGun — время первого выстрела ГЛАВНОГО калибра, а не лёгкого")
	near(b.metrics.first_hit, num(light[0][0]) if light.size() > 0 else -1.0, 1e-9, "а первое попадание — лёгкое (М11)")
	b.dispose()


# ───────────────────────── «Перестрелка»: повтор с оружием ─────────────────────────

## Бой с оружием, ракетами, РЭБ и планетой повторяется до бита (архитектура, 2.11):
## один и тот же бой дважды — один отпечаток; в нём есть и ракеты, и залп планеты.
func test_skirmish_repeats() -> void:
	var a := Polygon.make_record(_defs(), "capella-проверка", 2400)
	var c := Polygon.make_record(_defs(), "capella-проверка", 2400)
	eq(str(a["fp"]), str(c["fp"]), "показательная «Перестрелка» (80 с) дважды — один отпечаток")
