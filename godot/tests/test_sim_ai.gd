# ИИ стороны (sim/ai.gd; доктрина 09, раздел 7; план G5, п. 1) и ход боя (05, 2.6, 2.12, 2.13;
# план G5, п. 2). Каждая проверка — с откатом: флажок `rollback_*` модели, флажок состава боя
# (`old_ai`) или контроль, где причины нет.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Ai := preload("res://sim/ai.gd")
const Formation := preload("res://sim/formation.gd")
const Hangar := preload("res://sim/hangar.gd")
const Weapons := preload("res://sim/weapons.gd")
const Squad := preload("res://sim/squad.gd")
const HeavyDoctrine := preload("res://sim/heavy_doctrine.gd")
const BenchCore := preload("res://tools/bench_core.gd")
const Polygon := preload("res://tools/polygon.gd")

const BIG := 1.0e9

var defs: Defs


func _defs() -> Defs:
	if defs == null:
		defs = Defs.load_default() as Defs
	return defs


## Пустое поле: игрок — атакующий, без ИИ; ИИ заводится руками (_arm) после расстановки.
func _lab(setup: Dictionary = {}) -> Battle:
	var st := {"attacker": &"troyden", "defender": &"plektor", "size": &"small", "seed": 5, "reserve": false}
	st.merge(setup, true)
	var b := Battle.create(_defs(), st) as Battle
	b.ships.clear()
	return b


func _put(b: Battle, side: int, id: StringName, pos: Vector2) -> Ship:
	return b.spawn(side, b.defs.ship(b.sides[side].clan, id), pos)


static func _arm(b: Battle, side: int) -> Ai:
	var a := Ai.arm(b, side, true) as Ai
	b.ai.append(a)
	return a


func _steps(b: Battle, secs: float) -> void:
	for i in roundi(secs / Battle.STEP):
		b.step()


static func _feed_has(b: Battle, part: String) -> bool:
	for e in b.feed_log:
		if str(e["text"]).contains(part):
			return true
	return false


# ───────────────────────── роли после двух тиков (09, 7.2) ─────────────────────────

## «Сражение» Тройден × Плэктор под двумя ИИ (стенд): после двух тиков каждой стороны — роли
## таблицы 7.2. → число нарушений и их список.
func _roles(old_ai: bool) -> Dictionary:
	var b := Battle.create(_defs(), BenchCore.setup_for("battle", 1000, false, {"old_ai": old_ai})) as Battle
	var d := b.defs.doctrine
	# первый тик на 3 с, второй — не позже 3 + 4 с (THINK_MAX × tempo «Офицера»)
	_steps(b, Ai.THINK_FIRST + Ai.THINK_MAX + 0.5)
	var bad := PackedStringArray()
	var seen := 0
	for a in b.ai:
		var sd := b.sides[a.side]
		var p := sd.line_p
		var ax := sd.line_ax
		for s in b.ships:
			if s.dead or s.side != a.side or s.station:
				continue
			seen += 1
			var at_slot := s.has_slot and s.anchor.distance_to(s.slot) < 1.0
			if s.has_move:
				bad.append("%s: приказ «идти» (ИИ даёт места участками, 9.5 п. 15)" % s.name)
			if s.heavy():
				if s.stance != &"guard" or not at_slot or (s.slot_band != Formation.HEAVY and s.slot_band != Formation.HEAVY2):
					bad.append("%s: тяжёлый — «%s», место %s, полоса %d" % [s.name, s.stance, at_slot, s.slot_band])
			elif s.def.ecm:
				if s.slot_band != Formation.FRIGATE or not at_slot or s.forced != null:
					bad.append("%s: РЭБ не в шеренге фрегатов (полоса %d, место %s)" % [s.name, s.slot_band, at_slot])
			elif s.hangar != null:
				if s.slot_band != Formation.CARRIER or (s.anchor - p).dot(ax) > -0.9 * d.line_carrier_back:
					bad.append("%s: носитель не позади (%.0f по оси)" % [s.name, (s.anchor - p).dot(ax)])
			elif s.def.id == &"frigate":
				if s.stance != &"guard" or (s.slot_band == Formation.FRIGATE and absf(s.leash_set - d.leash_frigate_ai) > 1e-6):
					bad.append("%s: фрегат — «%s», поводок %.0f" % [s.name, s.stance, s.leash_set])
			elif s.def.id == &"corvette":
				if s.stance != &"guard" or s.slot_band != Formation.CORVETTE:
					bad.append("%s: корвет — «%s», полоса %d" % [s.name, s.stance, s.slot_band])
	b.dispose()
	return {"bad": bad, "seen": seen}


func test_ai_roles_after_two_ticks() -> void:
	var r := _roles(false)
	var bad: PackedStringArray = r["bad"]
	ok(whole(r["seen"]) > 20, "под двумя ИИ — оба флота (%d кораблей)" % whole(r["seen"]))
	ok(bad.is_empty(), "роли 7.2 после двух тиков: тяжёлые на «Охране» на своих местах, РЭБ в шеренге фрегатов, носители позади, фрегаты с поводком 100, корветы в передней шеренге — нарушений %d%s" % [bad.size(), (": " + "; ".join(bad.slice(0, 4))) if not bad.is_empty() else ""])
	var o := _roles(true)
	var obad: PackedStringArray = o["bad"]
	note("откат --old-ai: %s" % "; ".join(obad.slice(0, 3)))
	ok(obad.size() > 0, "откат --old-ai (кольцо охранения, тяжёлые на «Охоте»): нарушений %d — проверка краснеет" % obad.size())


# ───────────────────────── доля корабля своей стороны (7.2, 9.5 п. 12) ─────────────────────────

## Зеркало Тройден × Тройден: доли кораблей двух сторон — одни и те же по местам состава.
func _shares(global: bool) -> Array[PackedFloat64Array]:
	Ai.rollback_share_global = global
	var b := Battle.create(_defs(), BenchCore.setup_for("battle", 1000, false, {}, "troyden,troyden")) as Battle
	var out: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array()]
	for a in b.ai:
		for s in b.ships:
			if s.side == a.side:
				out[a.side].append(snappedf(a.share(s), 1e-9))
	Ai.rollback_share_global = false
	b.dispose()
	return out


func test_share_of_own_side() -> void:
	var sh := _shares(false)
	ok(sh[0].size() > 0 and sh[0] == sh[1], "зеркало: доли кораблей атакующего и защитника совпадают по местам состава (%d кораблей)" % sh[0].size())
	var g := _shares(true)
	ok(g[0] != g[1], "откат «доля от общего uid, как в JS»: доли сторон разные — проверка краснеет")


# ───────────────────────── общая цель — в поясе (7.3) ─────────────────────────

## Два крейсера ИИ (защитник) и две цели: чужой фрегат дальше дальности главного калибра и чужой
## крейсер в поясе. → [общая цель, счёт фрегата, счёт крейсера].
func _focus_case(any: bool) -> Dictionary:
	Ai.rollback_focus_any = any
	var b := _lab({"difficulty": "hard"})       # «Ветеран»: общую цель бьют все тяжёлые
	var c1 := _put(b, Ship.DEFENDER, &"cruiser", Vector2(-120.0, -650.0))
	var c2 := _put(b, Ship.DEFENDER, &"cruiser", Vector2(120.0, -650.0))
	var r := c1.def.main.rng
	var cr := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0.0, -650.0 + 0.8 * r))
	var fr := _put(b, Ship.ATTACKER, &"frigate", Vector2(600.0, -650.0 + 1.4 * r))
	var a := _arm(b, Ship.DEFENDER)
	b.step()
	var pl := a.think(b)
	var out := {"focus": pl.focus.name if pl != null and pl.focus != null else "—", "fr": fr.name, "cr": cr.name,
		"s_fr": a.focus_score(b, fr), "s_cr": a.focus_score(b, cr)}
	Ai.rollback_focus_any = false
	ok(c2 != null, "второй крейсер ИИ на месте")
	b.dispose()
	return out


func test_focus_only_in_belt() -> void:
	var r := _focus_case(false)
	note("счёт цели: фрегат вне дальности %.4f, крейсер в поясе %.4f" % [num(r["s_fr"]), num(r["s_cr"])])
	ok(num(r["s_fr"]) > num(r["s_cr"]), "фрегат вне дальности по счёту лучше крейсера в поясе — иначе проверка ничего не различала бы")
	eq(str(r["focus"]), str(r["cr"]), "общая цель — крейсер в поясе у обоих тяжёлых, а не фрегат дальше R (7.3)")
	var o := _focus_case(true)
	eq(str(o["focus"]), str(o["fr"]), "откат «лучшая по счёту, без пояса»: общая цель — фрегат вне дальности — проверка краснеет")


# ───────────────────────── помощь прижатому (7.4) ─────────────────────────

## Крейсер ИИ и два его корвета; чужой корвет у крейсера в мёртвой зоне и гонится за ним
## (фокус на крейсер). → сколько раз позвали помощь и сколько корветов ИИ взяли чужого в фокус.
func _help_case(off: bool) -> Dictionary:
	Ai.rollback_no_help = off
	var b := _lab()
	var cr := _put(b, Ship.DEFENDER, &"cruiser", Vector2(0.0, -650.0))
	cr.hp = BIG
	cr.max_hp = BIG
	var k1 := _put(b, Ship.DEFENDER, &"corvette", Vector2(-260.0, -420.0))
	var k2 := _put(b, Ship.DEFENDER, &"corvette", Vector2(260.0, -420.0))
	for ks: Ship in [k1, k2]:
		ks.light_cd = PackedFloat64Array()        # не бьют сами: меряется фокус, а не исход
	var foe := _put(b, Ship.ATTACKER, &"corvette", Vector2(0.0, -650.0 + 0.7 * cr.def.main.dead))
	foe.hp = BIG
	foe.max_hp = BIG
	foe.stance = &"hunt"
	foe.forced = cr
	# своя дальняя линия игрока — чтобы стороны не кончились
	var far := _put(b, Ship.ATTACKER, &"frigate", Vector2(2600.0, 2400.0))
	far.switch_off(&"engines", BIG)
	far.stance = &"hold"
	var a := _arm(b, Ship.DEFENDER)
	var most := 0
	var first := -1.0
	for i in roundi(20.0 / Battle.STEP):
		b.step()
		var n := 0
		for ks: Ship in [k1, k2]:
			if not ks.dead and ks.forced == foe:
				n += 1
		if n > 0 and first < 0.0:
			first = b.time
		most = maxi(most, n)
	var out := {"calls": a.help_calls, "most": most, "first": first}
	Ai.rollback_no_help = false
	b.dispose()
	return out


func test_help_pinned_heavy() -> void:
	var r := _help_case(false)
	note("помощь прижатому: зовов %d, корветов на чужом сразу %d, с %.1f с" % [whole(r["calls"]), whole(r["most"]), num(r["first"])])
	ok(whole(r["calls"]) >= 1 and whole(r["most"]) == 2, "чужой корвет вплотную у крейсера дольше %.0f с — оба своих корвета получили его в фокус" % _defs().doctrine.ai_help_after_s)
	ok(num(r["first"]) >= _defs().doctrine.ai_help_after_s, "помощь — не раньше %.0f с «вплотную» (%.1f с)" % [_defs().doctrine.ai_help_after_s, num(r["first"])])
	var o := _help_case(true)
	ok(whole(o["most"]) == 0, "откат «помощи нет»: корветов на чужом %d — проверка краснеет" % whole(o["most"]))


# ───────────────────────── перехват корветов в своей полосе (3.4) ─────────────────────────

## Корвет ИИ на своём месте и чужое звено: у его места (near = true) или у своего фрегата вдали
## от места корвета. → перехватил ли.
func _intercept_case(near: bool, any: bool) -> bool:
	Ai.rollback_intercept_any = any
	var b := _lab()
	var d := b.defs.doctrine
	var a := _arm(b, Ship.DEFENDER)
	var kv: Ship = null
	for i in 8:
		var k := _put(b, Ship.DEFENDER, &"corvette", Vector2(-400.0 + 110.0 * float(i), -300.0))
		if kv == null and a.share(k) < d.ai_corvette_intercept_share:
			kv = k
	kv.has_slot = true
	kv.slot = kv.pos
	var fr := _put(b, Ship.DEFENDER, &"frigate", kv.pos + Vector2(0.0, -700.0))
	var at := kv.pos + Vector2(0.0, 0.6 * d.ai_corvette_intercept_take) if near else fr.pos + Vector2(0.0, -200.0)
	var car := _put(b, Ship.ATTACKER, &"carrier", at)
	var q := Hangar.launch(b, car, &"fighter")
	b.step()
	var got := a._intercept(b, kv) and kv.forced == q
	Ai.rollback_intercept_any = false
	b.dispose()
	return got


func test_corvette_intercepts_in_its_band() -> void:
	ok(_intercept_case(true, false), "звено у места корвета (ближе %.0f) — корвет из перехватывающей доли его берёт" % _defs().doctrine.ai_corvette_intercept_take)
	ok(not _intercept_case(false, false), "звено у своего фрегата, в 700 от места корвета, — корвет шеренгу не бросает (3.4)")
	ok(_intercept_case(false, true), "откат «звено у любого своего ближе 750, как в JS»: корвет бросает шеренгу — проверка краснеет")


# ───────────────────────── роли звеньев по снимку (4.5) ─────────────────────────

## Носитель ИИ, видны чужой крейсер и чужое звено истребителей в воздухе (три машины: больше,
## чем своих перехватчиков + ai.air_e_over_i). → роль первого пуска.
func _air_role(js: bool) -> String:
	Ai.rollback_air_js = js
	var b := _lab()
	var car := _put(b, Ship.DEFENDER, &"carrier", Vector2(0.0, -800.0))
	_put(b, Ship.ATTACKER, &"cruiser", Vector2(0.0, 700.0))
	var foe_car := _put(b, Ship.ATTACKER, &"carrier", Vector2(300.0, 900.0))
	var q := Hangar.launch(b, foe_car, &"fighter")
	# машин три: больше своих перехватчиков (0) + ai.air_e_over_i (2) — правило 4.5, — но не больше
	# 0 + 4 — порог JS: только здесь два правила расходятся
	for i in range(3, q.craft.size()):
		q.craft[i].dead = true
	var a := _arm(b, Ship.DEFENDER)
	b.step()
	var pl := a.think(b)
	var role := "—"
	if pl != null:
		for l: Array in pl.launch:
			var c: Ship = l[0]
			if c == car:
				role = str(l[1])
				break
	Ai.rollback_air_js = false
	b.dispose()
	return role


func test_air_roles_by_snapshot() -> void:
	var r := _air_role(false)
	eq(r, "interceptor", "чужих машин в воздухе больше своих перехватчиков + %d — ИИ поднимает перехватчиков (4.5)" % roundi(_defs().doctrine.ai_air_e_over_i))
	var o := _air_role(true)
	eq(o, "bomber", "откат «как в JS — бомбардировщики, пока видна чужая не-мелочь»: проверка краснеет")


# ───────────────────────── «нечем бить» (05, 2.12; P5) ─────────────────────────

## У игрока один безоружный РЭБ, противник далеко. → итог и время конца, предупреждение в ленте.
func _teeth(off: bool) -> Dictionary:
	Battle.rollback_no_teeth = off
	var b := _lab()
	var ecm := _put(b, Ship.ATTACKER, &"ecm", Vector2(0.0, 650.0))
	var foe := _put(b, Ship.DEFENDER, &"cruiser", Vector2(2400.0, -2400.0))
	foe.switch_off(&"engines", BIG)
	foe.stance = &"hold"
	var warned := -1.0
	for i in roundi(40.0 / Battle.STEP):
		b.step()
		if warned < 0.0 and _feed_has(b, "нечем бить"):
			warned = b.time
		if b.over:
			break
	var out := {"over": b.over, "t": b.time, "result": str(b.result), "warned": warned, "fled": ecm.fled}
	Battle.rollback_no_teeth = false
	b.dispose()
	return out


func test_unarmed_ecm_retreats() -> void:
	var r := _teeth(false)
	note("одинокий РЭБ: предупреждение на %.1f с, конец на %.1f с, итог %s" % [num(r["warned"]), num(r["t"]), str(r["result"])])
	ok(num(r["warned"]) >= 0.0 and num(r["warned"]) < 1.0, "строка «нечем бить» в ленте сразу (%.1f с)" % num(r["warned"]))
	ok(flag(r["over"]) and str(r["result"]) == "retreat" and flag(r["fled"]), "одинокий безоружный РЭБ за 40 с ушёл в гипер, итог — «Отход» (%s на %.1f с)" % [str(r["result"]), num(r["t"])])
	var o := _teeth(true)
	ok(not flag(o["over"]), "откат «нечем бить не проверяется»: РЭБ стоит вечно, итога нет — проверка краснеет")


## ИИ без тяжёлых (тяжёлые были и кончились), у игрока тяжёлые и он сильнее — отход всем флотом
## (05, 2.6 п. 7). Контроль — у игрока один фрегат: ИИ сильнее, отхода нет.
func _leaderless(strong_foe: bool) -> Dictionary:
	var b := _lab()
	var hv := _put(b, Ship.DEFENDER, &"cruiser", Vector2(0.0, -650.0))
	for xf: float in [-200.0, 200.0]:
		_put(b, Ship.DEFENDER, &"corvette", Vector2(xf, -500.0))
	if strong_foe:
		_put(b, Ship.ATTACKER, &"capital", Vector2(-200.0, 2000.0))
		_put(b, Ship.ATTACKER, &"cruiser", Vector2(200.0, 2000.0))
	else:
		_put(b, Ship.ATTACKER, &"frigate", Vector2(0.0, 2000.0))
	for s in b.ships:
		if s.side == Ship.ATTACKER:
			s.switch_off(&"engines", BIG)
			s.stance = &"hold"
	var a := _arm(b, Ship.DEFENDER)
	_steps(b, Ai.THINK_FIRST + 0.2)            # первый тик видел своего тяжёлого
	var had := a.had_heavy
	Weapons.destroy_ship(b, hv, null)
	var t0 := b.time
	var ret := -1.0
	for i in roundi(12.0 / Battle.STEP):
		b.step()
		if b.sides[Ship.DEFENDER].retreat:
			ret = b.time - t0
			break
	var out := {"had": had, "ret": ret, "feed": _feed_has(b, "Противник отходит")}
	b.dispose()
	return out


func test_ai_without_heavies_retreats() -> void:
	var r := _leaderless(true)
	ok(flag(r["had"]), "первый тик ИИ видел своего тяжёлого")
	ok(num(r["ret"]) >= 0.0 and num(r["ret"]) <= Ai.THINK_MAX + 0.1, "тяжёлый погиб, у игрока два тяжёлых — ИИ отходит всем флотом на ближайшем тике (через %.1f с)" % num(r["ret"]))
	ok(flag(r["feed"]), "в ленте — «Противник отходит: копит гипер — добить…»")
	var c := _leaderless(false)
	ok(num(c["ret"]) < 0.0, "контроль: у игрока один фрегат, ИИ сильнее — отхода нет")


# ───────────────────────── итог боя (05, 2.13; ловушки 30–32) ─────────────────────────

## Быстрый бой игрока с резервом: часть флота погибла, один ушёл в гипер, остальное — тоже
## гибнет; резерв не вызывали. retreat — был приказ отхода.
func _outcome(old: bool, retreat: bool) -> Dictionary:
	Battle.rollback_outcome_old = old
	var b := Battle.create(_defs(), Polygon.quick_setup({"attacker": "troyden", "defender": "plektor", "size": "small", "difficulty": "normal"}, 77)) as Battle
	var own := b.side_ships(Ship.ATTACKER)
	var reserve := 0
	for e in b.sides[Ship.ATTACKER].reserve:
		reserve += e.count
	var jumper := own[own.size() - 1]
	if retreat:
		b.sides[Ship.ATTACKER].retreat = true
	jumper.fled = true
	jumper.dead = true
	b.sides[Ship.ATTACKER].jumped.append(jumper.def.id)
	for s in own:
		if s != jumper and not s.dead:
			Weapons.destroy_ship(b, s, null)
	b.step()
	var att: Dictionary = b.outcome.get("attacker", {})
	var n := 0
	for k: String in att:
		var v: int = att[k]
		n += v
	var out := {"over": b.over, "result": str(b.result), "survivors": n, "reserve": reserve}
	# снимок итога — в миг итога (ловушка 31): шаги после него его не меняют
	b.step()
	b.step()
	out["same"] = b.outcome.get("attacker", {}) == att
	Battle.rollback_outcome_old = false
	b.dispose()
	return out


func test_outcome_and_result() -> void:
	var r := _outcome(false, false)
	ok(flag(r["over"]), "флот игрока ушёл с орбиты — бой кончен")
	eq(str(r["result"]), "defeat", "потери были, приказа отхода не было — «Флот разбит», хоть один и ушёл в гипер (ловушка 30)")
	eq(whole(r["survivors"]), 1 + whole(r["reserve"]), "уцелевшие игрока — ушедший в гипер и невышедший резерв (%d)" % whole(r["reserve"]))
	var rr := _outcome(false, true)
	eq(str(rr["result"]), "retreat", "был приказ отхода — «Отход»")
	var o := _outcome(true, false)
	ok(str(o["result"]) == "retreat" or whole(o["survivors"]) != whole(r["survivors"]), "откат «как до P1»: итог «%s», уцелевших %d — проверка краснеет" % [str(o["result"]), whole(o["survivors"])])
	ok(flag(r["same"]), "снимок итога снят в миг итога и потом не меняется (ловушка 31)")


# ───────────────────────── «ИИ против ИИ»: ничья и предел стенда ─────────────────────────

func test_watch_draw_and_limit() -> void:
	var b := Battle.create(_defs(), Polygon.quick_setup({"attacker": "troyden", "defender": "plektor", "size": "small", "difficulty": "normal", "watch": true}, 9)) as Battle
	ok(b.watch and b.ai.size() == 2, "«ИИ против ИИ»: ИИ у обеих сторон")
	for s in b.ships:
		s.dead = true
		if not s.station:
			s.fled = true
			b.sides[s.side].jumped.append(s.def.id)
	b.sides[0].reserve = []
	b.step()
	ok(b.over and b.winner == -1 and str(b.result) == "draw", "обе стороны ушли на одном шаге — ничья (%s, победитель %d)" % [str(b.result), b.winner])
	b.dispose()
	var rep := BenchCore.run_one(_defs(), BenchCore.setup_for("skirmish", 3, false, {}), 20.0, "capella-проверка")
	eq(str(rep.get("result", "")), "limit", "стенд: предел времени — итог «limit», без победителя")


# ───────────────────────── тыловой рубеж под ИИ (09, 2.6; находки стенда G5) ─────────────────────────

## Шагов, когда место тяжёлого под ИИ стоит за тыловым рубежом своей стороны (дальше допуска
## прихода), и наибольший заход — «Стычка» Тройден × Плэктор, зерно 1016, до итога.
func _hurt_slots(past_rear: bool) -> Dictionary:
	Ai.rollback_hurt_past_rear = past_rear
	var b := Battle.create(_defs(), BenchCore.setup_for("skirmish", 1016, false, {}), "capella-проверка") as Battle
	var bad := 0
	var worst := 0.0
	var hurt := 0
	while not b.over and b.time < 140.0:
		b.step()
		for s in b.ships:
			if s.dead or not s.heavy() or s.station or not s.has_slot:
				continue
			var sd := b.sides[s.side]
			if not sd.ai_on or sd.rear_z == INF:
				continue
			if s.hp_frac() < b.defs.doctrine.ai_hurt_hp:
				hurt += 1
			var over := s.slot.y * sd.sign_z - sd.rear_z
			if over > 8.0:
				bad += 1
				worst = maxf(worst, over)
	Ai.rollback_hurt_past_rear = false
	b.dispose()
	return {"bad": bad, "worst": worst, "hurt": hurt}


func test_hurt_heavy_not_past_rear() -> void:
	var r := _hurt_slots(false)
	ok(whole(r["hurt"]) > 0, "в бою есть побитый тяжёлый под ИИ (%d шагов) — проверке есть что ловить" % whole(r["hurt"]))
	eq(whole(r["bad"]), 0, "место побитого тяжёлого — не за тыловым рубежом (2.6)")
	var o := _hurt_slots(true)
	ok(whole(o["bad"]) > 0, "откат «дальний край пояса за рубежом»: место за рубежом %d шагов, до %.0f — проверка краснеет" % [whole(o["bad"]), num(o["worst"])])


## М6 «за рубежом» — подкрепление на подходе к месту не считается (точка выхода — место минус
## тормозной путь, то есть за рубежом по построению). «Генеральное» Тройден × Тройден, зерно 4000:
## резерв атакующего выходит на 32-й секунде.
func _rear_after_arrival(old: bool) -> int:
	Battle.rollback_rear_arrivals = old
	var b := Battle.create(_defs(), BenchCore.setup_for("battle_full", 4000, false, {}, "troyden,troyden"), "capella-проверка") as Battle
	while not b.over and b.time < 50.0:
		b.step()
	var n := b.metrics.m6_rear
	Battle.rollback_rear_arrivals = false
	b.dispose()
	return n


func test_m6_rear_skips_arrivals() -> void:
	eq(_rear_after_arrival(false), 0, "М6 за рубежом: подкрепление на подходе к месту — не «за рубежом»")
	var n := _rear_after_arrival(true)
	ok(n > 0, "откат «считать и подходящих»: %d шагов за рубежом — проверка краснеет" % n)


## Отход у тылового рубежа гасит ход с допуском прихода внутрь (`rear_gap`): гася ровно
## на рубеже, тяжёлый перелетал его на 8–13 и стоял там до конца боя — за допуском замера М6.
## «Сражение» Плэктор × Тройден, зерно 1045 (флагман Тройдена).
func _rear_exact(old: bool) -> int:
	HeavyDoctrine.rollback_rear_exact = old
	var b := Battle.create(_defs(), BenchCore.setup_for("battle", 1045, false, {}, "plektor,troyden"), "capella-проверка") as Battle
	while not b.over and b.time < 300.0:
		b.step()
	var n := b.metrics.m6_rear
	HeavyDoctrine.rollback_rear_exact = false
	b.dispose()
	return n


func test_rear_gap_with_pad() -> void:
	eq(_rear_exact(false), 0, "М6 за рубежом: отход у рубежа гасит ход с допуском прихода — перелёта нет")
	var n := _rear_exact(true)
	ok(n > 0, "откат «гасить ровно на рубеже»: %d шагов за рубежом — проверка краснеет" % n)
