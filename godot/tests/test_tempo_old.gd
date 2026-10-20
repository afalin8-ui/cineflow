# Ярус tempo (доработка GТ): правила, которых НОВЫЙ темп не проявляет, проверяются в ПРЕЖНЕМ —
# числами OLD_TEMPO из tests/case.gd (бой 0.7.1 до бита, test_tempo_gt → test_old_tempo_same_battle).
# Правило не снято — снят случай, где оно видно (godot/CLAUDE.md, 23): тыловой рубеж (четыре находки
# стенда G5), флажки 09, 8.4 `--legacy-approach` и `--no-share-close`, залипание цели патруля
# и приказы звеньям показательной записи. Вынесены из яруса sim, где жили рядом с проверками нового
# темпа: вместе sim доходил до 853 с из 900 (замер проверяющего в тихую минуту, нагрузка 1,0–1,5).
# Помощники — тех файлов, откуда проверки пришли (экземпляр теста — обычный объект): вторая копия
# помощника разошлась бы с первой при первой правке.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ai := preload("res://sim/ai.gd")
const HeavyDoctrine := preload("res://sim/heavy_doctrine.gd")
const BenchCore := preload("res://tools/bench_core.gd")
const Polygon := preload("res://tools/polygon.gd")
const SimDoctrine := preload("res://tests/test_sim_doctrine.gd")
const SimAir := preload("res://tests/test_sim_air.gd")

var _old: Defs
var _doc: SimDoctrine
var _air: SimAir


## Прежний темп (до пакета GТ) числами доктрины — OLD_TEMPO в tests/case.gd.
func _old_defs() -> Defs:
	if _old == null:
		_old = Defs.load_default(OLD_TEMPO) as Defs
	return _old


func _doctrine() -> SimDoctrine:
	if _doc == null:
		_doc = SimDoctrine.new()
	return _doc


func _airt() -> SimAir:
	if _air == null:
		_air = SimAir.new()
	return _air


# ───────────────────────── флажки 09, 8.4: беда видна только в прежнем темпе ─────────────────────────

## Откат --legacy-approach (подход тяжёлого «на 0,68», как в JS) проваливает М3 и М9 в ПРЕЖНЕМ темпе:
## «Сражение», зёрна 1000–1001. В новом (пакет GТ) тяжёлые идут × 0,6 и тормозят раньше: тот же откат
## даёт М3 ~0,79 R и ни одной пары ближе 360 — порога не переходит; это печатается заметкой.
## Контроль — тот же бой без флажка в прежнем темпе: линии держат 0,7–1,0 R.
func test_legacy_approach_fails_m3_m9_old_tempo() -> void:
	var dt := _doctrine()
	var base := dt._bench("battle", 1000, 2, {}, _old_defs())
	var lg := dt._bench("battle", 1000, 2, {"legacy_approach": true}, _old_defs())
	var lg_new := dt._bench("battle", 1000, 2, {"legacy_approach": true})
	note("откат --legacy-approach в новом темпе: М2 %.3f · М3 %.3f R · пар тяжёлых ближе 360 %.0f" % [SimDoctrine._med(lg_new, "m2"), SimDoctrine._med(lg_new, "m3_med_k"), SimDoctrine._worst(lg_new, "m9_heavy")])
	note("прежний темп: без флажка М3 %.3f R, пар ближе 360 %.0f; --legacy-approach — М2 %.3f · М3 %.3f R · пар %.0f" % [SimDoctrine._med(base, "m3_med_k"), SimDoctrine._worst(base, "m9_heavy"),
		SimDoctrine._med(lg, "m2"), SimDoctrine._med(lg, "m3_med_k"), SimDoctrine._worst(lg, "m9_heavy")])
	ok(SimDoctrine._med(base, "m3_med_k") >= 0.7 and SimDoctrine._worst(base, "m9_heavy") == 0.0, "прежний темп без флажка: линии на %.3f R, пар тяжёлых ближе 360 нет — контроль" % SimDoctrine._med(base, "m3_med_k"))
	ok(SimDoctrine._med(lg, "m3_med_k") < 0.7 and SimDoctrine._worst(lg, "m9_heavy") > 0.0, "откат --legacy-approach (прежний темп): линии сходятся до %.2f R и тяжёлые в упор — М3 и М9 краснеют" % SimDoctrine._med(lg, "m3_med_k"))


## Откат --no-share-close (подход без доли сближения, 2.3) — «линии» (одни тяжёлые линия на линию):
## в прежнем темпе линии сходятся ниже 0,7 R, в новом — 0,73 R (печатается). Лабораторная проверка
## самого правила — test_sim_doctrine → test_head_on_share_of_closing (откат краснеет и в новом темпе).
func test_no_share_close_fails_m3_old_tempo() -> void:
	var dt := _doctrine()
	var base := dt._bench("lines", 1000, 2, {}, _old_defs())
	var ns := dt._bench("lines", 1000, 2, {"no_share_close": true}, _old_defs())
	var ns_new := dt._bench("lines", 1000, 2, {"no_share_close": true})
	note("«линии», прежний темп: М3 %.3f R, откат --no-share-close — %.3f R (в новом темпе %.3f R)" % [SimDoctrine._med(base, "m3_med_k"), SimDoctrine._med(ns, "m3_med_k"), SimDoctrine._med(ns_new, "m3_med_k")])
	ok(SimDoctrine._med(base, "m3_med_k") >= 0.7, "«линии», прежний темп без флажка: %.3f R (≥ 0,7) — контроль" % SimDoctrine._med(base, "m3_med_k"))
	ok(SimDoctrine._med(ns, "m3_med_k") < 0.7, "откат --no-share-close (прежний темп): линии сходятся до %.3f R — М3 краснеет" % SimDoctrine._med(ns, "m3_med_k"))


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


# ───────────────────────── авиация: случаи, которых новый темп не даёт ─────────────────────────

## Откат «цель-корабль прилипает» (Air.rollback_patrol_ship_sticks) краснеет на зерне «Полигона»:
## корвет входит в полосу патруля, когда к линии подходят чужие звенья, и звено держится за него —
## по кораблям больше, чем по машинам. В новом темпе корвет в полосу патруля к приходу чужих звеньев
## не входит ни на одном из трёх зёрен, и откат не меняет ни шага (по машинам 4475 / 3480 / 3415 и
## с ним, и без); само правило держит лаборатория test_sim_air → test_patrol_band_craft, а место боя
## в новом темпе — test_sim_air → test_interceptor_meets_squads_in_polygon.
func test_interceptor_ship_sticks_old_tempo() -> void:
	for o in _airt()._polygon_place(20.0, &"sticks", 40.0, _old_defs()):
		note("откат «цель-корабль прилипает» (прежний темп), зерно %d: по машинам %d, по кораблям %d" % [whole(o["seed"]), whole(o["craft"]), whole(o["ship"])])
		if whole(o["seed"]) == Polygon.SEED:
			ok(whole(o["craft"]) < whole(o["ship"]), "откат «цель-корабль прилипает», зерно «Полигона» %d: по машинам %d против %d по кораблям — проверка краснеет" % [whole(o["seed"]), whole(o["craft"]), whole(o["ship"])])
	for r in _airt()._polygon_place(20.0, &"ok", 40.0, _old_defs()):
		if whole(r["seed"]) == Polygon.SEED:
			ok(whole(r["craft"]) > whole(r["ship"]), "контроль (прежний темп, без отката), зерно «Полигона»: по машинам %d против %d по кораблям" % [whole(r["craft"]), whole(r["ship"])])


## Приказы своим звеньям в показательной записи (пуск, фокус на звено, посадка V) отдаются, пока
## звенья живы. Откат «прежние шаги 720 и 900» краснеет в прежнем темпе, где его беда и нашлась:
## в новом бой идёт медленнее, и к этим шагам свои звенья ещё живы — приказы в журнале есть и в
## откате. Сама проверка журнала в новом темпе — test_sim_air → test_demo_record_air_orders.
func test_demo_air_orders_late_old_tempo() -> void:
	var r := _airt()._demo_air(false, _old_defs())
	var o := _airt()._demo_air(true, _old_defs())
	note("прежний темп, показательная запись: посадок своих звеньев %d, фокусов на чужое звено %d; откат — %d и %d" % [whole(r["recall"]), whole(r["focus"]), whole(o["recall"]), whole(o["focus"])])
	ok(whole(r["recall"]) >= 1 and whole(r["focus"]) >= 1, "прежний темп: в журнале есть посадка своего звена и фокус на чужое — контроль")
	ok(whole(o["recall"]) == 0 and whole(o["focus"]) == 0, "откат «прежние шаги 720 и 900» (прежний темп): своих звеньев к ним нет, приказов в журнале ни одного — проверка краснеет")
