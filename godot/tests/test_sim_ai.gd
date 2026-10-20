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
const State := preload("res://sim/state.gd")
const Air := preload("res://sim/air.gd")
const QuickMenu := preload("res://ui/quick_menu.gd")
const Craft := preload("res://sim/craft.gd")

const BIG := 1.0e9

var defs: Defs


func _defs() -> Defs:
	if defs == null:
		defs = Defs.load_default() as Defs
	return defs


var _old: Defs
## Прежний темп (до пакета GТ) числами доктрины — OLD_TEMPO в tests/case.gd.
func _old_defs() -> Defs:
	if _old == null:
		_old = Defs.load_default(OLD_TEMPO) as Defs
	return _old


## Пустое поле: игрок — атакующий, без ИИ; ИИ заводится руками (_arm) после расстановки.
## d — свои данные (откат правкой числа), по умолчанию — общие.
func _lab(setup: Dictionary = {}, d: Defs = null) -> Battle:
	var st := {"attacker": &"troyden", "defender": &"plektor", "size": &"small", "seed": 5, "reserve": false}
	st.merge(setup, true)
	var b := Battle.create(d if d != null else _defs(), st) as Battle
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


## Общая цель держится, пока не хуже лучшей в ai.focus_keep раз (05, ловушка 5; 09, 7.3): два
## крейсера ИИ, две чужие цели в поясе у обоих, нынешняя общая — A; у B счёт в ratio раз лучше
## (прочность в ratio раз меньше). → имя общей цели после тика.
func _focus_keep(d: Defs, ratio: float) -> Dictionary:
	var b := _lab({"difficulty": "hard"}, d)
	var c1 := _put(b, Ship.DEFENDER, &"cruiser", Vector2(-120.0, -650.0))
	_put(b, Ship.DEFENDER, &"cruiser", Vector2(120.0, -650.0))
	var r := c1.def.main.rng
	var ta := _put(b, Ship.ATTACKER, &"cruiser", Vector2(-160.0, -650.0 + 0.75 * r))
	var tb := _put(b, Ship.ATTACKER, &"cruiser", Vector2(160.0, -650.0 + 0.75 * r))
	ta.hp = 0.8 * ta.max_hp
	tb.hp = ta.hp / ratio
	var a := _arm(b, Ship.DEFENDER)
	b.step()
	a.focus = ta
	var pl := a.think(b)
	var out := {"focus": pl.focus.name if pl != null and pl.focus != null else "—", "a": ta.name, "b": tb.name,
		"k": a.focus_score(b, tb) / a.focus_score(b, ta)}
	b.dispose()
	return out


func test_focus_keeps_until_worse() -> void:
	var d := _defs()
	var keep := d.doctrine.ai_focus_keep
	var r := _focus_keep(d, 0.85 * keep)
	note("счёт B / счёт A: %.2f (держать до %.1f)" % [num(r["k"]), keep])
	eq(str(r["focus"]), str(r["a"]), "у другой цели счёт лучше в %.2f раза (< %.1f) — общая цель прежняя (05, ловушка 5)" % [num(r["k"]), keep])
	var w := _focus_keep(d, 1.25 * keep)
	eq(str(w["focus"]), str(w["b"]), "у другой цели счёт лучше в %.2f раза (> %.1f) — общая цель сменилась" % [num(w["k"]), keep])
	var o := _focus_keep(Defs.load_default({"ai.focus_keep": 1.0}) as Defs, 0.85 * keep)
	eq(str(o["focus"]), str(o["b"]), "откат «не держать» (ai.focus_keep = 1): общая цель скачет на лучшую — проверка краснеет")


## «В поясе у БОЛЬШИНСТВА бьющих» (09, 7.3): три крейсера ИИ («Ветеран» — бьют все) через 1,15 R,
## одна чужая цель — в поясе у одного из трёх (two = false) или у двух. → имя общей цели.
func _focus_majority(two: bool, any: bool) -> String:
	Ai.rollback_focus_any = any
	var b := _lab({"difficulty": "hard"})
	var c0 := _put(b, Ship.DEFENDER, &"cruiser", Vector2(0.0, -650.0))
	var r := c0.def.main.rng
	_put(b, Ship.DEFENDER, &"cruiser", Vector2(-1.15 * r, -650.0))
	_put(b, Ship.DEFENDER, &"cruiser", Vector2(1.15 * r, -650.0))
	var at := Vector2(0.575 * r, -650.0 + 0.5 * r) if two else Vector2(1.15 * r, -650.0 + 0.8 * r)
	var t := _put(b, Ship.ATTACKER, &"cruiser", at)
	var a := _arm(b, Ship.DEFENDER)
	b.step()
	var pl := a.think(b)
	var out := pl.focus.name if pl != null and pl.focus != null else "—"
	ok(t != null, "цель на месте")
	Ai.rollback_focus_any = false
	b.dispose()
	return out


func test_focus_needs_majority_in_belt() -> void:
	eq(_focus_majority(false, false), "—", "цель в поясе у одного из трёх бьющих общей не становится (7.3: у большинства)")
	ok(_focus_majority(true, false) != "—", "контроль: цель в поясе у двух из трёх — общая")
	ok(_focus_majority(false, true) != "—", "откат «без пояса»: цель в поясе у одного из трёх стала общей — проверка краснеет")


## Тяжёлый ИИ ниже ai.flee_hp — на ближайшем тике в гипер, в ленте ОДНА строка «Противник: «…»
## копит гипер — добить, пока не ушёл» (05, ловушка 14); отменили накачку — ИИ отправит его снова,
## а строка не повторится. → когда начал копить, строк после первого раза и после повтора.
func _flee(d: Defs, repeat_note: bool) -> Dictionary:
	Battle.rollback_flee_note_repeat = repeat_note
	var b := _lab({}, d)
	var hurt := _put(b, Ship.DEFENDER, &"cruiser", Vector2(-200.0, -650.0))
	hurt.hp = 0.17 * hurt.max_hp
	_put(b, Ship.DEFENDER, &"cruiser", Vector2(200.0, -650.0))
	var foe := _put(b, Ship.ATTACKER, &"frigate", Vector2(0.0, 2400.0))
	foe.switch_off(&"engines", BIG)
	foe.stance = &"hold"
	_arm(b, Ship.DEFENDER)
	var t_jump := -1.0
	var tick := (Ai.THINK_FIRST + 0.2) * Ai.tempo(b)
	while b.time < tick:
		b.step()
		if t_jump < 0.0 and hurt.charging():
			t_jump = b.time
	var n1 := 0
	for e in b.feed_log:
		n1 += 1 if str(e["text"]).contains("копит гипер — добить") else 0
	# повтор: накачку отменили — на следующем тике ИИ отправит его снова
	if hurt.charging():
		b._cancel_jump(hurt)
	var again := false
	for i in roundi((Ai.THINK_MAX + 0.5) * Ai.tempo(b) / Battle.STEP):
		b.step()
		again = again or hurt.charging()
	var n2 := 0
	for e in b.feed_log:
		n2 += 1 if str(e["text"]).contains("копит гипер — добить") else 0
	var out := {"t_jump": t_jump, "n1": n1, "again": again, "n2": n2, "tick": tick}
	Battle.rollback_flee_note_repeat = false
	b.dispose()
	return out


func test_ai_heavy_below_flee_jumps_once() -> void:
	var d := _defs()
	var r := _flee(d, false)
	ok(num(r["t_jump"]) > 0.0 and num(r["t_jump"]) <= num(r["tick"]), "тяжёлый ИИ с 17%% прочности (ниже %.0f%%) на первом тике (%.1f с) копит гипер" % [100.0 * d.doctrine.ai_flee_hp, num(r["t_jump"])])
	eq(whole(r["n1"]), 1, "в ленте одна строка «Противник: «…» копит гипер — добить, пока не ушёл»")
	ok(flag(r["again"]) and whole(r["n2"]) == 1, "накачку отменили — ИИ отправил снова, строка не повторилась (%d)" % whole(r["n2"]))
	var o := _flee(Defs.load_default({"ai.flee_hp": 0.0}) as Defs, false)
	ok(num(o["t_jump"]) < 0.0, "откат «в гипер не уходит» (ai.flee_hp = 0): не копит — проверка краснеет")
	var rp := _flee(d, true)
	ok(whole(rp["n2"]) > 1, "откат «строка при каждом начале накачки»: %d строк — проверка краснеет" % whole(rp["n2"]))


## Отход всем флотом, когда все вооружённые побиты (05, ловушка 12; 2.6 п. 5): крейсер и корвет
## ИИ на 25% (ниже ai.hurt_hp, выше ai.flee_hp), носитель цел (безоружен — не в счёт). Контроль —
## корвет цел. → отдан ли отход на первом тике и строка в ленте.
func _all_broken(d: Defs, all: bool) -> Dictionary:
	var b := _lab({}, d)
	var cr := _put(b, Ship.DEFENDER, &"cruiser", Vector2(0.0, -650.0))
	var kv := _put(b, Ship.DEFENDER, &"corvette", Vector2(200.0, -500.0))
	_put(b, Ship.DEFENDER, &"carrier", Vector2(0.0, -1100.0))
	cr.hp = 0.25 * cr.max_hp
	if all:
		kv.hp = 0.25 * kv.max_hp
	var foe := _put(b, Ship.ATTACKER, &"frigate", Vector2(0.0, 2400.0))
	foe.switch_off(&"engines", BIG)
	foe.stance = &"hold"
	_arm(b, Ship.DEFENDER)
	while b.time < (Ai.THINK_FIRST + 0.2) * Ai.tempo(b):
		b.step()
	var out := {"retreat": b.sides[Ship.DEFENDER].retreat, "feed": _feed_has(b, "Противник отходит")}
	b.dispose()
	return out


func test_ai_retreats_when_all_armed_broken() -> void:
	var d := _defs()
	var r := _all_broken(d, true)
	ok(flag(r["retreat"]) and flag(r["feed"]), "все вооружённые ИИ ниже %.0f%% — на первом тике отход всем флотом, в ленте «Противник отходит…»" % (100.0 * d.doctrine.ai_hurt_hp))
	var c := _all_broken(d, false)
	ok(not flag(c["retreat"]), "контроль: корвет цел — отхода нет")
	var o := _all_broken(Defs.load_default({"ai.hurt_hp": 0.2}) as Defs, true)
	ok(not flag(o["retreat"]), "откат «побит — ниже 20%%» (25%% уже не побитые): отхода нет — проверка краснеет")


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


## Помощник 7.4 побит посреди помощи (замечание к G5: _help на каждом тике снова ставил ему фокус,
## и побитый корвет держался в упор у чужого до конца помощи, хотя роли 7.2 только что отправили
## его за линию). → сколько шагов после удара он ещё бьёт «прижавшего», где его место после тика
## и держит ли помощь второй, целый корвет.
func _hurt_helper(rollback: bool) -> Dictionary:
	Ai.rollback_help_hurt = rollback
	var b := _lab()
	var d := b.defs.doctrine
	var cr := _put(b, Ship.DEFENDER, &"cruiser", Vector2(0.0, -650.0))
	cr.hp = BIG
	cr.max_hp = BIG
	var k1 := _put(b, Ship.DEFENDER, &"corvette", Vector2(-260.0, -420.0))
	var k2 := _put(b, Ship.DEFENDER, &"corvette", Vector2(260.0, -420.0))
	for ks: Ship in [k1, k2]:
		ks.light_cd = PackedFloat64Array()
	var foe := _put(b, Ship.ATTACKER, &"corvette", Vector2(0.0, -650.0 + 0.7 * cr.def.main.dead))
	foe.hp = BIG
	foe.max_hp = BIG
	foe.stance = &"hunt"
	foe.forced = cr
	var far := _put(b, Ship.ATTACKER, &"frigate", Vector2(2600.0, 2400.0))
	far.switch_off(&"engines", BIG)
	far.stance = &"hold"
	var a := _arm(b, Ship.DEFENDER)
	var kh: Ship = null
	while b.time < 15.0 and kh == null:
		b.step()
		for ks: Ship in [k1, k2]:
			if kh == null and ks.forced == foe:
				kh = ks
	var out := {"helped": kh != null, "t_help": b.time}
	if kh == null:
		Ai.rollback_help_hurt = false
		b.dispose()
		return out
	var other := k2 if kh == k1 else k1
	kh.hp = 0.2 * kh.max_hp                     # побит: ниже ai.hurt_hp
	var on_foe := 0
	var other_on := 0
	var n := roundi((Ai.THINK_MAX * Ai.tempo(b) + 0.5) / Battle.STEP)    # до следующего тика с запасом
	for i in n:
		b.step()
		if kh.forced == foe:
			on_foe += 1
		if other.forced == foe:
			other_on += 1
	var sd := b.sides[Ship.DEFENDER]
	out["on_foe"] = on_foe
	out["steps"] = n
	out["other_on"] = other_on
	out["back"] = (kh.slot - sd.line_p).dot(sd.line_ax)
	out["anchor_slot"] = kh.anchor.distance_to(kh.slot)
	out["hurt_back"] = d.ai_hurt_back
	Ai.rollback_help_hurt = false
	b.dispose()
	return out


## Помощник 7.4, у места которого появилось чужое звено: роли того же тика отправляют его на звено
## (3.4), и помощь не возвращает его на «прижавшего» (замечание к G5: возвращала, и счётчик
## перехватов врал). → куда смотрит помощник через тик и сколько перехватов насчитано.
func _intercepting_helper(rollback: bool) -> Dictionary:
	Ai.rollback_help_hurt = rollback
	var b := _lab()
	var cr := _put(b, Ship.DEFENDER, &"cruiser", Vector2(0.0, -650.0))
	cr.hp = BIG
	cr.max_hp = BIG
	var ks: Array[Ship] = []
	for xf: float in [-260.0, 260.0, -380.0, 380.0]:
		var k := _put(b, Ship.DEFENDER, &"corvette", Vector2(xf, -420.0))
		k.light_cd = PackedFloat64Array()
		ks.append(k)
	var foe := _put(b, Ship.ATTACKER, &"corvette", Vector2(0.0, -650.0 + 0.7 * cr.def.main.dead))
	foe.hp = BIG
	foe.max_hp = BIG
	foe.stance = &"hunt"
	foe.forced = cr
	var far := _put(b, Ship.ATTACKER, &"frigate", Vector2(2600.0, 2400.0))
	far.switch_off(&"engines", BIG)
	far.stance = &"hold"
	var a := _arm(b, Ship.DEFENDER)
	var kh: Ship = null
	while b.time < 15.0 and kh == null:
		b.step()
		for k in ks:
			if kh == null and k.forced == foe and a.share(k) < b.defs.doctrine.ai_corvette_intercept_share:
				kh = k
	var out := {"helper": kh != null}
	if kh == null:
		Ai.rollback_help_hurt = false
		b.dispose()
		return out
	kh.hp = BIG                                   # меряется выбор цели, а не исход
	kh.max_hp = BIG
	var spot := kh.slot + Vector2(0.0, 120.0)
	var car := _put(b, Ship.ATTACKER, &"carrier", spot)
	car.switch_off(&"engines", BIG)
	var q := Hangar.launch(b, car, &"fighter")
	var i0 := a.intercepts
	var n := roundi((Ai.THINK_MAX * Ai.tempo(b) + 0.2) / Battle.STEP)
	var on_q := 0
	for i in n:
		for c in q.craft:
			c.pos = spot                              # звено висит у места помощника
			c.vel = Vector2.ZERO
		b.step()
		if kh.forced == q:
			on_q += 1
	out["on_q"] = on_q
	out["on_foe"] = kh.forced == foe
	out["intercepts"] = a.intercepts - i0
	Ai.rollback_help_hurt = false
	b.dispose()
	return out


func test_intercepting_helper_leaves_help() -> void:
	var r := _intercepting_helper(false)
	ok(flag(r["helper"]), "помощник из перехватывающей доли нашёлся")
	note("помощник и звено у его места: на звене %d шагов, перехватов начато %d, в конце на «прижавшем» %s" % [whole(r["on_q"]), whole(r["intercepts"]), flag(r["on_foe"])])
	ok(whole(r["intercepts"]) >= 1 and whole(r["on_q"]) > 0 and not flag(r["on_foe"]), "звено у места помощника — он перехватывает, помощь его обратно не забирает")
	var o := _intercepting_helper(true)
	note("откат: на звене %d шагов, перехватов начато %d, в конце на «прижавшем» %s" % [whole(o["on_q"]), whole(o["intercepts"]), flag(o["on_foe"])])
	ok(whole(o["on_q"]) == 0 or flag(o["on_foe"]), "откат «помощь забирает и перехватывающего»: на звене %d шагов — проверка краснеет" % whole(o["on_q"]))


func test_hurt_helper_leaves_help() -> void:
	var r := _hurt_helper(false)
	ok(flag(r["helped"]), "помощь началась (%.1f с), одному из помощников — 20%% прочности" % num(r["t_help"]))
	note("побитый помощник: на «прижавшем» %d шагов из %d после удара, место после тика %.0f по оси от линии; второй на «прижавшем» %d шагов" % [whole(r["on_foe"]), whole(r["steps"]), num(r["back"]), whole(r["other_on"])])
	eq(whole(r["on_foe"]), 0, "побитый помощник с первого же шага после удара «прижавшего» не бьёт (7.2: фокус снимается)")
	ok(num(r["back"]) < -0.5 * num(r["hurt_back"]) and num(r["anchor_slot"]) < 1.0, "после тика его место — за линией (7.2: −%.0f), он идёт туда (%.0f)" % [num(r["hurt_back"]), num(r["back"])])
	eq(whole(r["other_on"]), whole(r["steps"]), "второй, целый, помощь держит")
	var o := _hurt_helper(true)
	ok(whole(o["on_foe"]) > whole(o["steps"]) / 2, "откат «помощь не смотрит на прочность»: побитый на «прижавшем» %d шагов из %d — проверка краснеет" % [whole(o["on_foe"]), whole(o["steps"])])


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


## Перехват по частям правила 3.4 (замечание к G5: прежняя проверка ставила корвет НА его место,
## и ни «к МЕСТУ», ни 300, ни доля 0,5, ни «бросить на 450» не различались — краснел только откат,
## ломавший всё разом). Корвет ИИ стоит в ICEPT_OFF сбоку от своего места; low — из перехватывающей
## доли (share < ai.corvette_intercept_share), иначе из держащей линию. Чужое звено — в точке rel
## от МЕСТА. → {got — взял ли, kv, q, a, b} (b не освобождён: проверка конца перехвата шагает дальше).
const ICEPT_OFF := 400.0


func _icept(d: Defs, low: bool, rel: Vector2, from_ship: bool = false) -> Dictionary:
	Ai.rollback_intercept_from_ship = from_ship
	var b := _lab({}, d)
	var a := _arm(b, Ship.DEFENDER)
	var line_k := _defs().doctrine.ai_corvette_intercept_share      # доля — по данным игры, не отката
	var kv: Ship = null
	for i in 8:
		var k := _put(b, Ship.DEFENDER, &"corvette", Vector2(-400.0 + 110.0 * float(i), -300.0))
		if kv == null and (a.share(k) < line_k) == low:
			kv = k
	var place := Vector2(0.0, -300.0)
	kv.has_slot = true
	kv.slot = place
	kv.anchor = place
	kv.pos = place + Vector2(ICEPT_OFF, 0.0)
	var car := _put(b, Ship.ATTACKER, &"carrier", place + rel)
	var q := Hangar.launch(b, car, &"fighter")
	var got := a._intercept(b, kv) and kv.forced == q
	Ai.rollback_intercept_from_ship = false
	return {"got": got, "kv": kv, "q": q, "a": a, "b": b, "share": a.share(kv)}


func _icept_got(d: Defs, low: bool, rel: Vector2, from_ship: bool = false) -> bool:
	var r := _icept(d, low, rel, from_ship)
	var b: Battle = r["b"]
	b.dispose()
	return flag(r["got"])


## Звено взято у самого места; потом уходит на `to` от места. → держит ли корвет перехват после шага ИИ.
func _icept_keeps(d: Defs, to: float) -> bool:
	var r := _icept(d, true, Vector2.ZERO)
	var b: Battle = r["b"]
	var kv: Ship = r["kv"]
	var q: Squad = r["q"]
	var a: Ai = r["a"]
	var place := kv.slot
	q.pos = place + Vector2(0.0, -to)
	a.step(b)                                 # конец перехвата — по шагу (Ai.step)
	var keep := flag(r["got"]) and kv.forced == q
	b.dispose()
	return keep


func test_corvette_intercept_rule_parts() -> void:
	var d := _defs()
	var dd := d.doctrine
	var take := dd.ai_corvette_intercept_take
	var drop := dd.ai_corvette_intercept_drop
	# к МЕСТУ, а не к корвету: корвет в 400 сбоку от своего места
	ok(_icept_got(d, true, Vector2.ZERO), "звено у самого места корвета (корвет в %.0f от места) — берёт" % ICEPT_OFF)
	ok(_icept_got(d, true, Vector2(0.0, 0.9 * take)), "звено в %.0f от места (ближе %.0f) — берёт" % [0.9 * take, take])
	ok(not _icept_got(d, true, Vector2(ICEPT_OFF, 0.0)), "звено у самого корвета, в %.0f от его места, — не берёт: считается от МЕСТА в шеренге" % ICEPT_OFF)
	ok(_icept_got(d, true, Vector2(ICEPT_OFF, 0.0), true), "откат «от самого корвета»: звено у корвета берёт — проверка краснеет")
	# 300, а не 750
	ok(not _icept_got(d, true, Vector2(0.0, 1.15 * take)), "звено в %.0f от места (дальше %.0f) — не берёт" % [1.15 * take, take])
	ok(not _icept_got(d, true, Vector2(0.0, 500.0)), "звено в 500 от места (между %.0f и 750 JS) — не берёт" % take)
	var wide := Defs.load_default({"ai.corvette_intercept_take": 750.0}) as Defs
	ok(_icept_got(wide, true, Vector2(0.0, 500.0)), "откат правкой числа ai.corvette_intercept_take = 750: звено в 500 берёт — проверка краснеет")
	# доля шеренги: вторая половина держит линию всегда
	ok(not _icept_got(d, false, Vector2.ZERO), "корвет из держащей линию доли (share ≥ %.1f) звено у своего места не берёт" % dd.ai_corvette_intercept_share)
	var all := Defs.load_default({"ai.corvette_intercept_share": 1.0}) as Defs
	ok(_icept_got(all, false, Vector2.ZERO), "откат ai.corvette_intercept_share = 1 (перехватывают все): берёт — проверка краснеет")
	# бросить дальше 450 от места; между 300 и 450 — держит (гистерезис)
	ok(not _icept_keeps(d, 1.1 * drop), "звено ушло на %.0f от места (дальше %.0f) — перехват снят" % [1.1 * drop, drop])
	ok(_icept_keeps(d, 0.5 * (take + drop)), "звено в %.0f от места (дальше «взять», ближе «бросить») — перехват держится" % (0.5 * (take + drop)))
	var never := Defs.load_default({"ai.corvette_intercept_drop": 1.0e9}) as Defs
	ok(_icept_keeps(never, 1.1 * drop), "откат «не бросать» (ai.corvette_intercept_drop = 1e9): держит и в %.0f — проверка краснеет" % (1.1 * drop))
	var tight := Defs.load_default({"ai.corvette_intercept_drop": take}) as Defs
	ok(not _icept_keeps(tight, 0.5 * (take + drop)), "откат «бросить там же, где взять» (drop = %.0f): в %.0f снят — проверка гистерезиса краснеет" % [take, 0.5 * (take + drop)])


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

## У игрока один безоружный РЭБ, противник далеко. → итог и время конца, предупреждение в ленте,
## когда отдан отход (05, 2.12: игроку ai.teeth_player_s на резерв — 12 с, а не 2, как ИИ).
func _teeth(off: bool, d: Defs = null) -> Dictionary:
	Battle.rollback_no_teeth = off
	var b := _lab({}, d)
	var ecm := _put(b, Ship.ATTACKER, &"ecm", Vector2(0.0, 650.0))
	var foe := _put(b, Ship.DEFENDER, &"cruiser", Vector2(2400.0, -2400.0))
	foe.switch_off(&"engines", BIG)
	foe.stance = &"hold"
	var warned := -1.0
	var ret := -1.0
	for i in roundi(40.0 / Battle.STEP):
		b.step()
		if warned < 0.0 and _feed_has(b, "нечем бить"):
			warned = b.time
		if ret < 0.0 and b.sides[Ship.ATTACKER].retreat:
			ret = b.time
		if b.over:
			break
	var out := {"over": b.over, "t": b.time, "result": str(b.result), "warned": warned, "fled": ecm.fled, "ret": ret}
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
	# игроку — 12 с на резерв, а не 2 с, как ИИ (замечание к G5: правка «2 с всем» не краснила ничего)
	var dc := _defs().doctrine
	near(num(r["ret"]) - num(r["warned"]), dc.ai_teeth_player_s, 0.1, "от предупреждения до отхода — %.0f с игроку на вызов резерва (05, 2.12), а не %.0f, как ИИ" % [dc.ai_teeth_player_s, dc.ai_teeth_ai_s])
	var q := _teeth(false, Defs.load_default({"ai.teeth_player_s": dc.ai_teeth_ai_s}) as Defs)
	ok(absf(num(q["ret"]) - num(q["warned"]) - dc.ai_teeth_player_s) > 1.0, "откат «игроку столько же, сколько ИИ» (ai.teeth_player_s = %.0f): отход через %.1f с — проверка краснеет" % [dc.ai_teeth_ai_s, num(q["ret"]) - num(q["warned"])])


## ИИ, которому нечем бить, СНАЧАЛА зовёт свой резерв (05, 2.12) и не уходит, пока резерв в пути;
## без резерва — уходит через ai.teeth_ai_s. → позвал ли, ушёл ли и когда — до первого тика ИИ
## (3 с): резерв на первом тике ИИ зовёт и так, а здесь меряется «нечем бить».
func _ai_teeth(reserve: bool, no_call: bool) -> Dictionary:
	Battle.rollback_teeth_no_reserve = no_call
	var b := _lab()
	_put(b, Ship.DEFENDER, &"ecm", Vector2(0.0, -650.0))
	if reserve:
		var e := Defs.FleetEntry.new()
		e.id = &"corvette"
		e.count = 2
		b.sides[Ship.DEFENDER].reserve.append(e)
	var foe := _put(b, Ship.ATTACKER, &"cruiser", Vector2(2400.0, 2400.0))
	foe.switch_off(&"engines", BIG)
	foe.stance = &"hold"
	_arm(b, Ship.DEFENDER)
	var sd := b.sides[Ship.DEFENDER]
	var ret := -1.0
	while b.time < Ai.THINK_FIRST * Ai.tempo(b) - 0.3:
		b.step()
		if ret < 0.0 and sd.retreat:
			ret = b.time
	var out := {"called": sd.reinforce_at > 0.0, "ret": ret}
	Battle.rollback_teeth_no_reserve = false
	b.dispose()
	return out


func test_ai_teeth_calls_reserve_first() -> void:
	var r := _ai_teeth(true, false)
	ok(flag(r["called"]) and num(r["ret"]) < 0.0, "ИИ, у которого один безоружный РЭБ и резерв, — зовёт резерв и не уходит (позвал %s, отход %.1f с)" % [flag(r["called"]), num(r["ret"])])
	var c := _ai_teeth(false, false)
	near(num(c["ret"]), _defs().doctrine.ai_teeth_ai_s, 0.1, "контроль: без резерва ИИ уходит через %.0f с «нечем бить»" % _defs().doctrine.ai_teeth_ai_s)
	var o := _ai_teeth(true, true)
	ok(not flag(o["called"]) and num(o["ret"]) > 0.0, "откат «резерв не зовёт»: ушёл на %.1f с, не позвав — проверка краснеет" % num(o["ret"]))


## «Есть чем бить» щедро (05, ловушка 27): носитель со свободным ангаром, носитель без мест, но со
## звеньями в воздухе, безоружный РЭБ с вызванным резервом, и (план GИ, хвост G5 п. 3) машины
## с ракетами, чей носитель погиб, — стороне ЕСТЬ чем бить, и она не уходит. which 4 — те же машины
## без единой ракеты (контроль: бить нечем). → can_hurt_side и ушла ли сторона игрока за 15 с.
func _generous(which: int, strict: bool, no_craft: bool = false) -> Dictionary:
	Battle.rollback_can_hurt_strict = strict
	Battle.rollback_can_hurt_no_craft = no_craft
	var b := _lab({"reserve": which == 2})
	var foe := _put(b, Ship.DEFENDER, &"cruiser", Vector2(2400.0, -2400.0))
	foe.switch_off(&"engines", BIG)
	foe.stance = &"hold"
	foe.light_cd = PackedFloat64Array()
	foe.pd_cd = PackedFloat64Array()            # машины не сбиваются: меряется правило, а не ПВО
	if which >= 3:
		# безоружный РЭБ — чтобы сторона была в бою: без единого корабля бой просто кончается
		_put(b, Ship.ATTACKER, &"ecm", Vector2(300.0, 650.0))
		var c3 := _put(b, Ship.ATTACKER, &"carrier", Vector2(0.0, 650.0))
		Hangar.launch(b, c3, &"fighter")
		Weapons.destroy_ship(b, c3, null)
		for c in b.crafts:
			if which == 4 and c.side == Ship.ATTACKER:
				c.ammo = 0
				c.reloads = 0
				c.reloading = 0.0
	elif which == 2:
		_put(b, Ship.ATTACKER, &"ecm", Vector2(0.0, 650.0))
		b.call_reinforcements(Ship.ATTACKER)
	else:
		var car := _put(b, Ship.ATTACKER, &"carrier", Vector2(0.0, 650.0))
		if which == 1:
			while car.hangar.free > 0:
				Hangar.launch(b, car, &"interceptor")
	var can := b.can_hurt_side(Ship.ATTACKER)
	for i in roundi(15.0 / Battle.STEP):
		b.step()
	var out := {"can": can, "retreat": b.sides[Ship.ATTACKER].retreat, "warned": _feed_has(b, "нечем бить")}
	Battle.rollback_can_hurt_strict = false
	Battle.rollback_can_hurt_no_craft = false
	b.dispose()
	return out


func test_can_hurt_is_generous() -> void:
	var names := ["носитель со свободным ангаром", "носитель без мест, звенья в воздухе", "безоружный РЭБ, резерв в пути"]
	for w in 3:
		var r := _generous(w, false)
		ok(flag(r["can"]) and not flag(r["retreat"]) and not flag(r["warned"]), "%s — есть чем бить: стоит, без «нечем бить» (05, ловушка 27)" % names[w])
		var o := _generous(w, true)
		ok(not flag(o["can"]) and flag(o["retreat"]), "откат «только оружие кораблей»: %s — ушёл в гипер — проверка краснеет" % names[w])
	# четвёртый случай (хвост G5, п. 3): носитель погиб, его истребители с ракетами в воздухе
	var m := _generous(3, false)
	ok(flag(m["can"]) and not flag(m["retreat"]) and not flag(m["warned"]), "носитель погиб, машины с ракетами в воздухе — есть чем бить: стоит, без «нечем бить»")
	var e := _generous(4, false)
	ok(not flag(e["can"]) and flag(e["warned"]) and flag(e["retreat"]), "контроль: те же машины без ракет — бить нечем, «нечем бить» и отход")
	var om := _generous(3, false, true)
	ok(not flag(om["can"]) and flag(om["retreat"]), "откат «машины не в счёт»: с ракетами в воздухе — ушёл в гипер — проверка краснеет")


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
# Все четыре случая нашёл стенд G5 в ПРЕЖНЕМ темпе, и в нём они и проверяются (OLD_TEMPO: с этими
# числами бой совпадает с 0.7.1 до бита, отпечаток тот же). В новом темпе (пакет GТ: старт ±1050,
# тяжёлые ×0,6, спокойная доктрина) их нет вовсе — перебор с откатами: «Сражение» без РЭБ у
# защитника, зёрна 1000–1023 (толчок), Плэктор × Тройден 1000–1023 (гасить на рубеже), «Сражение»
# с резервом Тройден × Тройден 4000–4011 и «Генеральное» 4000–4005 (подходящие) — ни шага за рубежом
# и с откатом. Правила при этом не лишние: темп — числа доктрины, и вернись они — вернутся и случаи.

## Шагов, когда место тяжёлого под ИИ стоит за тыловым рубежом своей стороны (дальше допуска
## прихода), и наибольший заход — «Стычка» Тройден × Плэктор, зерно 1016, до итога.
func _hurt_slots(past_rear: bool) -> Dictionary:
	Ai.rollback_hurt_past_rear = past_rear
	var b := Battle.create(_old_defs(), BenchCore.setup_for("skirmish", 1016, false, {}), "capella-проверка") as Battle
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
	var b := Battle.create(_old_defs(), BenchCore.setup_for("battle_full", 4000, false, {}, "troyden,troyden"), "capella-проверка") as Battle
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


## Толчок расталкивания за тыловой рубеж не выносит (режется тем же `rear_gap`): прижатого у
## рубежа тяжёлого корвет врага или свой фрегат выталкивали за рубеж, и он стоял там до гибели.
## «Сражение» Тройден × Плэктор без РЭБ у защитника, зерно 1030 (до правки — 2757 шагов).
func _rear_pushed(old: bool) -> int:
	HeavyDoctrine.rollback_push_past_rear = old
	var b := Battle.create(_old_defs(), BenchCore.setup_for("battle_noecm_d", 1030, false, {}), "capella-проверка") as Battle
	while not b.over and b.time < 300.0:
		b.step()
	var n := b.metrics.m6_rear
	HeavyDoctrine.rollback_push_past_rear = false
	b.dispose()
	return n


func test_push_not_past_rear() -> void:
	eq(_rear_pushed(false), 0, "М6 за рубежом: толчок своих и чужих тяжёлого за рубеж не выносит")
	var n := _rear_pushed(true)
	ok(n > 0, "откат «толчок без рубежа»: %d шагов за рубежом — проверка краснеет" % n)


## Отход у тылового рубежа гасит ход с допуском прихода внутрь (`rear_gap`): гася ровно
## на рубеже, тяжёлый перелетал его на 8–13 и стоял там до конца боя — за допуском замера М6.
## «Сражение» Плэктор × Тройден, зерно 1045 (флагман Тройдена).
func _rear_exact(old: bool) -> int:
	HeavyDoctrine.rollback_rear_exact = old
	var b := Battle.create(_old_defs(), BenchCore.setup_for("battle", 1045, false, {}, "plektor,troyden"), "capella-проверка") as Battle
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


# ───────────────────────── «ИИ против ИИ» говорит кланами (G5, замечание к G5) ─────────────────────────

## Зерно боя «ИИ против ИИ» по выбору меню (Тройден × Плэктор, «Сражение», «Офицер»): в нём есть
## всё, что лента и полоски говорят о сторонах, — потери обеих, звенья, помехи, «под огнём», гипер,
## отход всем флотом, вызов и выход подкрепления и уход носителя.
const VOICE_SEED := 4242


## Строка говорит с места одной из сторон: «наш», «вражеский», «противник» или совет приказом (T).
static func _first_person(line: String) -> bool:
	var lo := line.to_lower()
	return lo.begins_with("наш") or lo.contains(" наш") or lo.contains("вражеск") or lo.contains("противник") or line.contains("(T)")


static func _starts_with_any(line: String, heads: PackedStringArray) -> bool:
	for h in heads:
		if line.begins_with(h):
			return true
	return false


## Быстрый бой по выбору меню (watch — «Смотреть: ИИ против ИИ», иначе «В бой» без единого приказа)
## до итога или until с: что модель написала человеку — лента (текст и вид) и полоски.
func _voice(watch: bool, until: float, rollback: bool) -> Dictionary:
	State.rollback_watch_voice = rollback
	var b := Battle.create(_defs(), Polygon.quick_setup(QuickMenu.default_cfg(_defs(), watch), VOICE_SEED)) as Battle
	while not b.over and b.time < until:
		b.step()
	var feed := PackedStringArray()
	var kinds := PackedStringArray()
	for e in b.feed_log:
		feed.append(str(e["text"]))
		kinds.append(str(e["kind"]))
	var toasts := PackedStringArray()
	for e in b.toast_log:
		toasts.append(str(e["text"]))
	# кто вправе начинать строку в «ИИ против ИИ»: только кланы сторон — с GИ и полоски орудия
	# планеты («Тройден: Планета наводит…», хвост G5): до того они начинались именем орудия, и
	# зритель не знал, чьё оно
	var clans := PackedStringArray([b.clan_tag(Ship.ATTACKER), b.clan_tag(Ship.DEFENDER)])
	var heads := clans.duplicate()
	var gun_name := b.gun.def.name if b.gun != null else "—"
	var out := {"gun_name": gun_name, "feed": feed, "kinds": kinds, "toasts": toasts, "clans": clans, "heads": heads, "over": b.over, "t": b.time, "watch": b.watch}
	State.rollback_watch_voice = false
	b.dispose()
	return out


## Строки, которые в «ИИ против ИИ» говорят не кланом: с места стороны или без имени клана в начале.
static func _bad_voice(r: Dictionary) -> PackedStringArray:
	var bad := PackedStringArray()
	var clans: PackedStringArray = r["clans"]
	var heads: PackedStringArray = r["heads"]
	var feed: PackedStringArray = r["feed"]
	var toasts: PackedStringArray = r["toasts"]
	for l in feed:
		if _first_person(l) or not _starts_with_any(l, clans):
			bad.append("лента: " + l)
	for l in toasts:
		if _first_person(l) or not _starts_with_any(l, heads):
			bad.append("полоска: " + l)
	return bad


static func _count(lines: PackedStringArray, part: String) -> int:
	var n := 0
	for l in lines:
		if l.contains(part):
			n += 1
	return n


func test_watch_feed_names_clans() -> void:
	var r := _voice(true, 400.0, false)
	var feed: PackedStringArray = r["feed"]
	var toasts: PackedStringArray = r["toasts"]
	var kinds: PackedStringArray = r["kinds"]
	var clans: PackedStringArray = r["clans"]
	ok(flag(r["watch"]) and flag(r["over"]), "«ИИ против ИИ» по выбору меню, зерно %d — бой дошёл до итога (%.0f с)" % [VOICE_SEED, num(r["t"])])
	# проверке есть что ловить: каждая из дверей, которые раньше говорили «наш» и «противник»
	ok(_count(feed, clans[0] + ": потерян") > 0 and _count(feed, clans[1] + ": потерян") > 0, "в ленте потери обеих сторон")
	ok(_count(feed, "копит гипер") > 0 and _count(feed, "сбито звено") > 0 and _count(feed, "под огнём") > 0, "в ленте гипер, сбитые звенья и «под огнём»")
	ok(_count(feed, "подкрепление") > 0 and _count(toasts, "подкрепление выйдет") > 0 and _count(toasts, "подкрепление вышло") > 0, "в ленте и полосках — вызов и выход подкрепления")
	var bad := _bad_voice(r)
	note("«ИИ против ИИ», зерно %d, %.0f с: строк ленты %d, полосок %d, не кланом — %d" % [VOICE_SEED, num(r["t"]), feed.size(), toasts.size(), bad.size()])
	ok(bad.is_empty(), "«ИИ против ИИ»: все %d строк ленты и %d полосок — от имени клана, без «наш», «вражеский», «противник» и «(T)»%s" % [feed.size(), toasts.size(), (": " + "; ".join(bad.slice(0, 4))) if not bad.is_empty() else ""])
	var guns := _count(toasts, "Планета наводит") + _count(toasts, str(r["gun_name"]))
	ok(guns > 0, "проверке есть что ловить и у орудия планеты: его полосок %d (все — с кланом)" % guns)
	var loud := 0
	for k in kinds:
		if k != "warn":
			loud += 1
	eq(loud, 0, "у зрителя нет «своего» успеха: строки ленты — нейтрального вида, ни зелёных, ни красных")
	# контроль: бой с игроком — «наш» и «вражеский» на месте (правило не стёрло их везде)
	var c := _voice(false, 60.0, false)
	var cfeed: PackedStringArray = c["feed"]
	note("контроль, бой с игроком 60 с: «Потерян наш» — %d, «вражеск» — %d из %d строк" % [_count(cfeed, "Потерян наш"), _count(cfeed, "вражеск"), cfeed.size()])
	ok(_count(cfeed, "Потерян наш") > 0 and _count(cfeed, "вражеск") > 0, "контроль: в бою с игроком лента говорит «наш» и «вражеский» (%d строк)" % cfeed.size())
	# откат: прежняя лента — с места атакующего
	var o := _voice(true, 60.0, true)
	var obad := _bad_voice(o)
	note("откат «ИИ против ИИ» с места атакующего: %d строк не кланом, например: %s" % [obad.size(), "; ".join(obad.slice(0, 3))])
	ok(obad.size() > 0, "откат rollback_watch_voice: %d строк «наш/противник» или без клана — проверка краснеет" % obad.size())


## Лента «под помехами» в «ИИ против ИИ» — раз в 25 с на КАЖДЫЙ флот (хвост G5): часы были одни
## на обе стороны, и второй флот о своих помехах молчал. Тяжёлый каждой стороны стоит под
## куполом глушения чужого РЭБ, 20 с.
func _jam_lines(shared: bool) -> PackedStringArray:
	Weapons.rollback_jam_feed_shared = shared
	var b := _lab()
	b.watch = true
	var ae := _put(b, Ship.ATTACKER, &"ecm", Vector2(0.0, 300.0))
	var dc := _put(b, Ship.DEFENDER, &"cruiser", Vector2(0.0, 160.0))
	var de := _put(b, Ship.DEFENDER, &"ecm", Vector2(2200.0, -300.0))
	var ac := _put(b, Ship.ATTACKER, &"cruiser", Vector2(2200.0, -160.0))
	var four: Array[Ship] = [ae, dc, de, ac]
	for s in four:
		s.switch_off(&"engines", BIG)
		s.stance = &"hold"
	_steps(b, 20.0)
	var out := PackedStringArray()
	for e in b.feed_log:
		if str(e["text"]).contains("под помехами"):
			out.append(str(e["text"]))
	Weapons.rollback_jam_feed_shared = false
	b.dispose()
	return out


func test_watch_jam_feed_per_fleet() -> void:
	var l := _jam_lines(false)
	note("«под помехами» за 20 с: %s" % " | ".join(l))
	ok(l.size() == 2 and _count(l, "Тройден:") == 1 and _count(l, "Плэктор:") == 1, "за 20 с — по одной строке на каждый флот, кланом (%d)" % l.size())
	var o := _jam_lines(true)
	ok(o.size() == 1, "откат «часы на оба флота одни» краснеет: строк %d" % o.size())


## Полоски о звеньях в «ИИ против ИИ» (перезарядка, ракеты кончились, звено село) — у обеих
## сторон и от имени клана; раньше их получал только атакующий, и с его места.
func _squad_voice(rollback: bool) -> PackedStringArray:
	State.rollback_watch_voice = rollback
	var b := Battle.create(_defs(), Polygon.quick_setup(QuickMenu.default_cfg(_defs(), true), VOICE_SEED)) as Battle
	b.step()
	var n0 := b.toast_log.size()
	for side in 2:
		var car: Ship = null
		for s in b.ships:
			if s.side == side and s.hangar != null and not s.dead:
				car = s
				break
		var q := Hangar.launch(b, car, &"bomber")
		var c := q.craft[0]
		c.ammo = 0
		c.reloads = 1
		Air.update_craft(b, c)               # перезарядка
		c.reloading = 0.0
		c.reloads = 0
		Air.update_craft(b, c)               # ракеты кончились — звено уходит на носитель
		var all: Array[Craft] = q.craft.duplicate()
		for m in all:
			Hangar.land(b, m, car)            # звено село
	var out := PackedStringArray()
	for i in range(n0, b.toast_log.size()):
		out.append(str(b.toast_log[i]["text"]))
	State.rollback_watch_voice = false
	b.dispose()
	return out


func test_watch_squad_toasts_name_clans() -> void:
	var t := _squad_voice(false)
	var a := _defs().factions[&"troyden"].short
	var d := _defs().factions[&"plektor"].short
	note("полоски звеньев: %s" % " | ".join(t))
	ok(_count(t, a + ": ") == 3 and _count(t, d + ": ") == 3, "полоски звеньев — у обеих сторон по три: перезарядка, ракеты кончились, звено село (%d)" % t.size())
	var bad := 0
	for l in t:
		if _first_person(l) or not (l.begins_with(a + ": ") or l.begins_with(d + ": ")):
			bad += 1
	eq(bad, 0, "каждая — от имени клана")
	var o := _squad_voice(true)
	var obad := 0
	for l in o:
		if not (l.begins_with(a + ": ") or l.begins_with(d + ": ")):
			obad += 1
	ok(obad > 0 or _count(o, d) == 0, "откат: полоски только у атакующего и без клана (%s) — проверка краснеет" % " | ".join(o))
