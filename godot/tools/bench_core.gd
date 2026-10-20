# tools/bench_core.gd — ядро стенда «бой без отрисовки» (архитектура, 8.6; 09, 8.1; план G5,
# п. 4). Две двери: в редакторе `godot --headless --path godot -s res://tools/bench.gd -- …`;
# в выгруженной сборке `-s` нет — главная сцена читает `-- --bench …` (main.gd). Отчёт — строка
# JSON на бой (BENCH {…}, тот же, что пишет бой человека — sim/report.gd) и сводка (BENCH_SUM).
#
# С G5 обе стороны ведёт ИИ целиком (sim/ai.gd) и бой идёт до итога или до предела 900 с.
# Составы (09, 8.1): «Стычка», «Сражение» и «Генеральное» без резерва и без орудия планеты,
# «Офицер» у обеих; `battle_full` — быстрый бой как есть (резерв, орудие); `*_noecm_a`/`_d` —
# те же без кораблей РЭБ у атакующего/защитника (М12). Ключи: --load, --n N, --seed S (зёрна
# S…S+N−1), --clans A,B (атакующий и защитник; по умолчанию troyden,plektor), --swap (кланы
# меняются сторонами — 05, ловушка 41), --max-s (предел, с), --set/--overrides (правки чисел),
# флажки отката 09, 8.4: --legacy-approach, --no-share-close, --no-foe-brake, --clear-055,
# --ecm-01L, --old-ai, --old-pd, --old-ecm, --bomber-direct, --patrol-mid. Сто боёв — процессами
# по 25 (tools/bench_run.sh), а не потоками; сводку строит tools/summarize.py.
extends RefCounted

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Metrics := preload("res://sim/metrics.gd")
const Report := preload("res://sim/report.gd")

## Флажки отката 09, 8.4 → ключ состава боя (запись боя их помнит).
const FLAGS := {
	"--legacy-approach": "legacy_approach",
	"--no-share-close": "no_share_close",
	"--no-foe-brake": "no_foe_brake",
	"--clear-055": "clear_055",
	"--ecm-01L": "ecm_01l",
	"--old-ecm": "old_ecm",
	"--bomber-direct": "bomber_direct",
	"--patrol-mid": "patrol_mid",
	"--old-ai": "old_ai",
	"--old-pd": "old_pd",
}
const LOADS := {"skirmish": &"small", "battle": &"mid", "general": &"big", "lines": &"small", "lines_mid": &"mid",
	"screen": &"small", "screen_mid": &"mid", "battle_full": &"mid", "skirmish_full": &"small", "general_full": &"big"}
## Быстрый бой как есть (09, 8.1): резерв атакующего (его ИИ зовёт сразу) и орудие планеты.
## «Генеральное» с резервом — худший бой для времени шага модели (план G5: p50, p99, худший).
const FULL := ["battle_full", "skirmish_full", "general_full"]
## Составы-сценарии стенда: какие виды кораблей берутся (пусто — все).
const ONLY := {"lines": ["heavy"], "lines_mid": ["heavy"], "screen": ["heavy", "corvette"], "screen_mid": ["heavy", "corvette"]}
const MAX_S := 900.0
## Сценарий длится столько: подход и встреча — за первые 30 с.
const SCENARIO_S := 60.0


## Состав стенда (09, 8.1): быстрый бой без резерва и без орудия планеты, «Офицер», обе
## стороны — под заглушкой строя.
static func setup_for(load_id: String, seed_n: int, swap: bool, flags: Dictionary, clans: String = "troyden,plektor") -> Dictionary:
	# «…_noecm_a» / «…_noecm_d» — тот же состав без кораблей РЭБ у атакующего / защитника (М12)
	var no_ecm: Array = []
	if load_id.ends_with("_noecm_a"):
		no_ecm = [Ship.ATTACKER]
		load_id = load_id.trim_suffix("_noecm_a")
	elif load_id.ends_with("_noecm_d"):
		no_ecm = [Ship.DEFENDER]
		load_id = load_id.trim_suffix("_noecm_d")
	var size: StringName = LOADS.get(load_id, &"mid")
	var a := StringName(clans.get_slice(",", 0))
	var d := StringName(clans.get_slice(",", 1) if clans.contains(",") else clans)
	var att := d if swap else a
	var dfn := a if swap else d
	var st := {"attacker": att, "defender": dfn, "size": size, "seed": seed_n, "reserve": false,
		"ground_gun": "", "difficulty": "normal", "ai": [Ship.ATTACKER, Ship.DEFENDER]}
	if not no_ecm.is_empty():
		st["no_ecm"] = no_ecm
	if load_id in FULL:
		st["reserve"] = true
		st["ground_gun"] = "defender"
	if load_id in SCENARIOS:
		st["scenario"] = load_id
		st["size"] = &"small"
		st["ai"] = []
	if ONLY.has(load_id):
		st["only"] = ONLY[load_id]       # сценарий стенда: только эти виды (М3 линий, заслон)
	st.merge(flags, true)
	return st


## Сценарии стенда — расстановка руками, чтобы правило доктрины работало в чистом виде
## (09, 8.4: у части флажков отката беда видна только там, где правило решает исход):
## «brake» (2.3, п. 2) — свой крейсер подходит к чужому, а на пути, у самой точки подхода,
## стоит чужой корвет: без торможения у чужих крейсер по инерции въезжает к нему в мёртвую
## зону и отходит (М2, М6); «clear» (2.1, 0.2 п. 1) — чужой крейсер в 800 (дальше дальности),
## чужой корвет сбоку в 412 — между 0,45 R (351) и прежними 0,55 R (429): с прежним порогом
## подход заперт, и главный калибр не стреляет вовсе (М11, М1).
const SCENARIOS := ["brake", "clear"]


static func _scenario(b: Battle, id: String) -> void:
	b.ships.clear()
	b.sides[0].ai_on = false
	b.sides[1].ai_on = false
	b.ai.clear()
	var own := b.spawn(Ship.ATTACKER, b.defs.ship(b.sides[0].clan, &"cruiser"), Vector2(0.0, 0.0))
	own.stance = &"hunt"
	match id:
		"brake":
			_dummy(b.spawn(Ship.DEFENDER, b.defs.ship(b.sides[1].clan, &"cruiser"), Vector2(0.0, -950.0)))
			_dummy(b.spawn(Ship.DEFENDER, b.defs.ship(b.sides[1].clan, &"corvette"), Vector2(0.0, -600.0)))
		"clear":
			_dummy(b.spawn(Ship.DEFENDER, b.defs.ship(b.sides[1].clan, &"cruiser"), Vector2(0.0, -800.0)))
			_dummy(b.spawn(Ship.DEFENDER, b.defs.ship(b.sides[1].clan, &"corvette"), Vector2(200.0, -359.0)))
	b.events.clear()


## Мишень сценария: не летит, не стреляет, прочная.
static func _dummy(s: Ship) -> void:
	s.switch_off(&"engines", 1.0e9)
	s.stance = &"hold"
	s.hp = 1.0e9
	s.max_hp = 1.0e9
	s.main_cd = PackedFloat64Array()
	s.sec_cd = PackedFloat64Array()
	s.light_cd = PackedFloat64Array()
	s.pd_cd = PackedFloat64Array()


## Один бой без отрисовки до итога или до max_s → отчёт (sim/report.gd; строкой — report_line).
## until_phase — встать в конце фазы «бой» (так мерил стенд G4, когда развязки без ИИ не было;
## проверки G4 этим пользуются, чтобы замер не размывала развязка).
static func run_one(defs: Defs, setup: Dictionary, max_s: float = MAX_S, build: String = "", until_phase: bool = false) -> Dictionary:
	var b := Battle.create(defs, setup, build) as Battle
	var sc := str(setup.get("scenario", ""))
	if sc != "":
		_scenario(b, sc)
		max_s = minf(max_s, SCENARIO_S)
	var times := PackedFloat64Array()
	var limit := roundi(max_s / Battle.STEP)
	while not b.over and b.steps < limit and not (until_phase and b.metrics.phase >= 2):
		var t0 := Time.get_ticks_usec()
		b.step()
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	if not b.over and b.steps >= limit and sc == "" and not until_phase:
		b.finish(-1, true)                 # предел времени — только в стенде (05, вопрос 9)
	if b.metrics.phase == 1:
		b.metrics.fight_t1 = b.time
		b.metrics.close_episodes(b.time)
	var rep := Report.of(b, times, build, OS.get_name())
	rep["flags"] = _flags_of(setup)
	b.dispose()
	return rep


static func _q(sorted: PackedFloat64Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return snappedf(sorted[clampi(floori(q * float(sorted.size())), 0, sorted.size() - 1)], 0.001)


static func _flags_of(setup: Dictionary) -> Array:
	var out: Array = []
	for f: String in FLAGS:
		var k: String = FLAGS[f]
		if setup.get(k, false):
			out.append(f)
	return out


static func report_line(rep: Dictionary) -> String:
	return "BENCH " + Report.line(rep)


## Флажки отката из аргументов → ключи состава боя.
static func flags_from_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	for f: String in FLAGS:
		if f in args:
			out[FLAGS[f]] = true
	return out


static func arg_value(args: PackedStringArray, key: String, def: String) -> String:
	for i in args.size():
		var a := args[i]
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
		if a == key and i + 1 < args.size():
			return args[i + 1]
	return def


## Прогон по аргументам: N боёв, строка JSON на бой и сводка. → код выхода (0 — прогон
## состоялся; данные с ошибкой — 1).
static func main(defs: Defs, args: PackedStringArray, build: String) -> int:
	if not defs.ok:
		for e in defs.errors:
			printerr("ДАННЫЕ: ", e)
		print("BENCH ОТКАЗ: данные боя с ошибкой")
		return 1
	var load_id := arg_value(args, "--load", "battle")
	var n := arg_value(args, "--n", "4").to_int()
	var seed0 := arg_value(args, "--seed", "1000").to_int()
	var max_s := arg_value(args, "--max-s", str(MAX_S)).to_float()
	var swap := "--swap" in args
	var clans := arg_value(args, "--clans", "troyden,plektor")
	var flags := flags_from_args(args)
	var until_phase := "--until-phase" in args
	var reps: Array[Dictionary] = []
	for i in maxi(n, 1):
		var rep := run_one(defs, setup_for(load_id, seed0 + i, swap, flags, clans), max_s, build, until_phase)
		print(report_line(rep))
		reps.append(rep)
	print("BENCH_SUM " + JSON.stringify(summary(reps), "", false))
	return 0


## Сводка по боям: медианы замеров и сколько боёв прошли пороги 09, 8.2 (подробно — G5,
## tools/summarize.py).
static func summary(reps: Array[Dictionary]) -> Dictionary:
	var keys := ["m1", "m2", "m2_ep_med", "m3_med", "m3_med_k", "m3_p5", "m3_short", "m4", "m4_back", "m6", "m6_ep_med",
		"m6_back", "m6_rear", "m6_edge", "m9_entries", "m9_heavy", "m10_heavy", "m10_corvette", "m10_frigate", "m10_self", "p_min", "first_gun", "first_hit", "len",
		"m11_gap", "m12_jam", "jam_block", "m16_path", "m16_flips", "m16_move"]
	var out := {"n": reps.size()}
	var wins := PackedInt32Array([0, 0, 0])
	for r in reps:
		var w: int = r.get("winner", -1)
		wins[w + 1] += 1
	out["wins_att"] = wins[1]
	out["wins_def"] = wins[2]
	out["draws"] = wins[0]
	for k: String in keys:
		var a := PackedFloat64Array()
		for r in reps:
			var v: float = r.get(k, -1.0)
			if v >= 0.0:
				a.append(v)
		out[k] = snappedf(Metrics.median(a), 0.001) if not a.is_empty() else -1.0
	return out
