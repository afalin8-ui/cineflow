## Общая часть стенда: зовут и bench.gd (редактор), и main.gd (выгруженная сборка).
extends RefCounted

const Defs = preload("res://sim/defs.gd")
const Battle = preload("res://sim/battle.gd")

const LOADS := {
	# 60 кораблей, до 144 машин (Плэктор зеркально, 3 носителя по 4 ангара × 6)
	"p30": [["plektor", [["corvette", 8], ["frigate", 8], ["ecm", 2], ["cruiser", 6], ["carrier", 3], ["capital", 3]]],
			["plektor", [["corvette", 8], ["frigate", 8], ["ecm", 2], ["cruiser", 6], ["carrier", 3], ["capital", 3]]]],
	# «Генеральное» Плэктор против Плэктора: 68 кораблей, до 192 машин (09, М15)
	"p34": [["plektor", [["corvette", 8], ["frigate", 8], ["ecm", 4], ["cruiser", 6], ["carrier", 4], ["capital", 4]]],
			["plektor", [["corvette", 8], ["frigate", 8], ["ecm", 4], ["cruiser", 6], ["carrier", 4], ["capital", 4]]]],
	# «Сражение» быстрого боя: Тройден (×0,7) против Плэктора (×2)
	"mid": [["troyden", [["corvette", 2], ["frigate", 2], ["ecm", 1], ["cruiser", 1], ["carrier", 1], ["capital", 1]]],
			["plektor", [["corvette", 6], ["frigate", 6], ["ecm", 2], ["cruiser", 4], ["carrier", 2], ["capital", 2]]]],
}

static func _pct(t: PackedInt32Array, q: float) -> float:
	var c := t.duplicate()
	c.sort()
	return snappedf(c[mini(c.size() - 1, int(c.size() * q))] / 1000.0, 0.001) if c.size() > 0 else 0.0

static func fleet(rows: Array) -> Array:
	var out := []
	for r in rows:
		out.append({"id": r[0], "count": r[1]})
	return out

static func run_from_args(args: PackedStringArray) -> Dictionary:
	var load_id := "p30"
	var n := 1
	var seed0 := 1
	var max_sec := 900.0
	var swap := false
	var i := 0
	while i < args.size():
		match args[i]:
			"--load": load_id = args[i + 1]; i += 1
			"--n": n = int(args[i + 1]); i += 1
			"--seed": seed0 = int(args[i + 1]); i += 1
			"--sec": max_sec = float(args[i + 1]); i += 1
			"--swap": swap = true
		i += 1
	var t0 := Time.get_ticks_usec()
	var defs := Defs.new()
	defs.load_all()
	var load_us := Time.get_ticks_usec() - t0
	var cfg: Array = LOADS[load_id]
	if swap:
		cfg = [cfg[1], cfg[0]]
	var runs := []
	var total_us := 0
	for k in n:
		var b := Battle.new()
		b.setup(defs, seed0 + k, [fleet(cfg[0][1]), fleet(cfg[1][1])], [cfg[0][0], cfg[1][0]])
		var peak_craft := 0
		var peak_proj := 0
		var worst_us := 0
		var t1 := Time.get_ticks_usec()
		var times := PackedInt32Array()
		var worst_step := 0
		while not b.ended and b.time < max_sec:
			var ts := Time.get_ticks_usec()
			b.step()
			var dt_us := Time.get_ticks_usec() - ts
			times.append(dt_us)
			if dt_us > worst_us:
				worst_us = dt_us; worst_step = b.steps
			if b.steps % 15 == 0:
				peak_craft = maxi(peak_craft, b.side_craft[0].size() + b.side_craft[1].size())
				peak_proj = maxi(peak_proj, b.side_proj[0].size() + b.side_proj[1].size())
		var us := Time.get_ticks_usec() - t1
		total_us += us
		var alive := [0, 0]
		for s in b.ships:
			if not s.dead: alive[s.side] += 1
		runs.append({
			"seed": seed0 + k, "sim_sec": snappedf(b.time, 0.1), "steps": b.steps,
			"cpu_sec": snappedf(us / 1e6, 0.001), "ms_per_step": snappedf(us / 1000.0 / maxf(b.steps, 1), 0.001),
			"worst_step_ms": snappedf(worst_us / 1000.0, 0.01), "worst_at_step": worst_step,
			"p50_ms": _pct(times, 0.5), "p99_ms": _pct(times, 0.99), "p999_ms": _pct(times, 0.999), "winner": b.winner, "alive": alive,
			"peak_craft": peak_craft, "peak_proj": peak_proj, "hash": b.state_hash(),
			"metrics": b.metrics.report(),
			"objects_after": Performance.get_monitor(Performance.OBJECT_COUNT),
		})
		if not args.has("--nodispose"):
			b.dispose()
		runs[-1]["objects_after_dispose"] = Performance.get_monitor(Performance.OBJECT_COUNT)
	return {"load": load_id, "n": n, "data_load_ms": load_us / 1000.0, "total_cpu_sec": total_us / 1e6, "runs": runs,
		"build": "debug" if OS.is_debug_build() else "release", "engine": Engine.get_version_info()["string"]}
