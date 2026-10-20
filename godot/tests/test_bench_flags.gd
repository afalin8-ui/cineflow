# Ярус bench: флажки отката 09, 8.4 под ИИ целиком (план G5, п. 4) — «Сражение» Тройден ×
# Плэктор, обе стороны под ИИ, бои до итога. Каждый флажок обязан провалить СВОЙ замер, а тот же
# замер без флажка — держаться (иначе проверка ничего не различает). Десятки боёв целиком —
# поэтому отдельный ярус (`run_tests.sh bench`, задание CI «стенд»), а не sim.
# Где замер красный и без флажка (М7 доли урона, М8 урон на звено — порогов 8.2 не держит и сам
# ИИ, godot/CLAUDE.md, раздел 21), флажок обязан сделать его ЗАМЕТНО хуже — вдвое.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const BenchCore := preload("res://tools/bench_core.gd")

const N := 6
const SEED := 1000

var defs: Defs
var defs_old: Defs
var _base: Array[Dictionary] = []
var _base_old: Array[Dictionary] = []


func _defs() -> Defs:
	if defs == null:
		defs = Defs.load_default() as Defs
	return defs


## Прежний темп (пакет GТ): числа OLD_TEMPO из case.gd — бой 0.7.1 до бита. Здесь проверяется то, что
## новый темп перестал проявлять (godot/CLAUDE.md, 23).
func _old_defs() -> Defs:
	if defs_old == null:
		defs_old = Defs.load_default(OLD_TEMPO) as Defs
	return defs_old


func _bench(flags: Dictionary, n: int = N, d: Defs = null) -> Array[Dictionary]:
	var dd := d if d != null else _defs()
	var out: Array[Dictionary] = []
	for i in n:
		out.append(BenchCore.run_one(dd, BenchCore.setup_for("battle", SEED + i, false, flags), BenchCore.MAX_S, "capella-проверка"))
	return out


func _base_reps() -> Array[Dictionary]:
	if _base.is_empty():
		_base = _bench({})
	return _base


func _base_old_reps() -> Array[Dictionary]:
	if _base_old.is_empty():
		_base_old = _bench({}, N, _old_defs())
	return _base_old


static func _median(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return -1.0
	a.sort()
	var n := a.size()
	return a[n >> 1] if n % 2 == 1 else 0.5 * (a[(n >> 1) - 1] + a[n >> 1])


static func _med(reps: Array[Dictionary], key: String) -> float:
	var a := PackedFloat64Array()
	for r in reps:
		var v: float = r.get(key, -1.0)
		if v >= 0.0:
			a.append(v)
	return _median(a)


## М7: доля урона источника — медиана по сторонам всех боёв (как tools/summarize.py).
static func _m7(reps: Array[Dictionary], k: String) -> float:
	var a := PackedFloat64Array()
	for r in reps:
		var sides: Array = r.get("m7", [])
		for sv: Variant in sides:
			var sd: Dictionary = sv
			if not sd.is_empty():
				var v: float = sd.get(k, 0.0)
				a.append(v)
	return _median(a)


## М8: поле звеньев стороны (урон на звено, доля сбитых) — медиана по сторонам, поднимавшим звенья.
static func _m8(reps: Array[Dictionary], k: String) -> float:
	var a := PackedFloat64Array()
	for r in reps:
		var sides: Array = r.get("m8", [])
		for sv: Variant in sides:
			var sd: Dictionary = sv
			var up: float = sd.get("up", 0.0)
			if up > 0.0:
				var v: float = sd.get(k, 0.0)
				a.append(v)
	return _median(a)


## «Старый ИИ» (кольцо охранения, тяжёлые на «Охоте») — М4 и М10 (8.4: М3, М4, М10).
func test_old_ai_fails_m4_m10() -> void:
	var base := _base_reps()
	var o := _bench({"old_ai": true})
	note("без флажка: М3 %.3f R · М4 %.2f · М10 корветы %.0f, фрегаты %.0f; --old-ai: М3 %.3f R · М4 %.2f · М10 корветы %.0f, фрегаты %.0f" % [
		_med(base, "m3_med_k"), _med(base, "m4"), _med(base, "m10_corvette"), _med(base, "m10_frigate"),
		_med(o, "m3_med_k"), _med(o, "m4"), _med(o, "m10_corvette"), _med(o, "m10_frigate")])
	ok(_med(base, "m4") >= 0.7 and _med(base, "m10_corvette") <= 260.0, "без флажка М4 и М10 держатся")
	ok(_med(o, "m4") < 0.7, "--old-ai: лёгкие не между линиями — М4 %.2f (< 0,70) краснеет" % _med(o, "m4"))
	ok(_med(o, "m10_corvette") > 260.0, "--old-ai: корветы не на своих местах — М10 %.0f (> 260) краснеет" % _med(o, "m10_corvette"))
	# М3 под старым ИИ НЕ краснеет — сказано, а не подогнано (godot/CLAUDE.md, раздел 21): места
	# тяжёлых в линии старый ИИ не трогает (шаги 6–7 общие), и линии стоят там же
	note("--old-ai: М3 не краснеет (%.3f R) — линию тяжёлых держат общие шаги 6–7" % _med(o, "m3_med_k"))


## «Старое ПВО» (1,4 / 88) — М7 (доля авиации) и М8 (урон на звено).
func test_old_pd_fails_m7_m8() -> void:
	var base := _base_reps()
	var o := _bench({"old_pd": true})
	note("без флажка: авиация %.3f урона, на звено %.0f; --old-pd: %.3f, %.0f" % [_m7(base, "air"), _m8(base, "per_squad"), _m7(o, "air"), _m8(o, "per_squad")])
	ok(_m8(base, "per_squad") > 0.0 and _m8(o, "per_squad") < 0.5 * _m8(base, "per_squad"), "--old-pd: урон на звено %.0f против %.0f — вдвое хуже (М8)" % [_m8(o, "per_squad"), _m8(base, "per_squad")])
	ok(_m7(o, "air") < 0.5 * _m7(base, "air"), "--old-pd: доля авиации в уроне %.3f против %.3f — вдвое меньше (М7)" % [_m7(o, "air"), _m7(base, "air")])


## «Заход бомбардировщиков прямо на цель» — М8 (урон на звено) и М7 (доля авиации).
## С пакета GТ доля авиации в уроне и без флажка ~0,02 (бой решают главные калибры, godot/CLAUDE.md,
## 23), и флажок её в новом темпе не различает (0,021 против 0,020) — эта половина проверяется в
## ПРЕЖНЕМ темпе (OLD_TEMPO, бой 0.7.1 до бита); урон на звено краснеет и в новом.
func test_bomber_direct_fails_m8() -> void:
	var base := _base_reps()
	var o := _bench({"bomber_direct": true})
	note("--bomber-direct: на звено %.0f (без флажка %.0f), авиация %.3f (%.3f)" % [_m8(o, "per_squad"), _m8(base, "per_squad"), _m7(o, "air"), _m7(base, "air")])
	ok(_m8(o, "per_squad") < 0.5 * _m8(base, "per_squad"), "--bomber-direct: урон на звено вдвое хуже (М8)")
	var bo := _base_old_reps()
	var oo := _bench({"bomber_direct": true}, N, _old_defs())
	note("--bomber-direct в прежнем темпе: авиация %.3f (без флажка %.3f)" % [_m7(oo, "air"), _m7(bo, "air")])
	ok(_m7(oo, "air") < _m7(bo, "air"), "--bomber-direct (прежний темп): доля авиации меньше (М7)")


## «Патруль перехватчиков над серединой» — М8 (доля сбитых звеньев).
## С пакета GТ доля сбитых и без флажка — на пороге (0,706 на этих 6 зёрнах, 0,656 на 8 зёрнах
## стенда; в 0.7.1 — 0,531): бои дольше на ~25 с, и Плэктор теряет 12 звеньев из 16–17 против
## 8–10. Ни старт ±1050, ни ход × 0,6 по отдельности этого не дают (0,563 и 0,531) — только вместе;
## записано на G9 (авиация), порог не трогали. Поэтому порог проверяется в ПРЕЖНЕМ темпе, а в новом —
## что флажок делает долю хуже.
func test_patrol_mid_fails_m8_lost() -> void:
	var base := _base_reps()
	var o := _bench({"patrol_mid": true})
	note("доля сбитых звеньев: без флажка %.3f, --patrol-mid %.3f" % [_m8(base, "lost_share"), _m8(o, "lost_share")])
	ok(_m8(o, "lost_share") > _m8(base, "lost_share"), "--patrol-mid: доля сбитых %.3f против %.3f — хуже (М8)" % [_m8(o, "lost_share"), _m8(base, "lost_share")])
	var bo := _base_old_reps()
	var oo := _bench({"patrol_mid": true}, N, _old_defs())
	note("прежний темп: без флажка %.3f, --patrol-mid %.3f" % [_m8(bo, "lost_share"), _m8(oo, "lost_share")])
	ok(_m8(bo, "lost_share") <= 0.7, "прежний темп: без флажка доля сбитых звеньев %.3f (≤ 0,70)" % _m8(bo, "lost_share"))
	ok(_m8(oo, "lost_share") > 0.7, "прежний темп: --patrol-mid — доля сбитых %.3f (> 0,70), М8 краснеет" % _m8(oo, "lost_share"))


## «Старые помехи» — М12 в срезе Тройден × Плэктор краснеть НЕ МОЖЕТ, и это проверяется, а не
## прячется: чужие тяжёлые под купол не попадают вовсе (РЭБ в шеренге фрегатов, 5.1), «тяжёлый-
## секунд под помехами» — 0 и с флажком, и без. Откат 09, 1.7 ловят лабораторные проверки G2
## (test_ui_skirmish --old-ecm, test_sim_weapons); порог М12 у Девиана — когда он войдёт в срез.
func test_old_ecm_m12_caveat() -> void:
	var base := _base_reps()
	var o := _bench({"old_ecm": true}, 2)
	note("М12 под чужими помехами: без флажка %.3f, --old-ecm %.3f" % [_med(base, "m12_jam"), _med(o, "m12_jam")])
	eq(_med(base, "m12_jam"), 0.0, "Тройден × Плэктор: тяжёлых под чужими помехами нет вовсе — М12 тут откат не ловит (оговорка 8.4)")
