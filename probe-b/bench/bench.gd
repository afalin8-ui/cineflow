## godot --headless --path proj -s res://bench/bench.gd -- mode=steady steps=3000 seed=1 comp=60
extends SceneTree

const COMP60 := {"corvette": 7, "frigate": 7, "ecm": 3, "cruiser": 5, "carrier": 4, "capital": 4}
const COMP68 := {"corvette": 8, "frigate": 8, "ecm": 4, "cruiser": 6, "carrier": 4, "capital": 4}

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var mode: String = args.get("mode", "steady")
	var steps := int(args.get("steps", "3000"))
	var seed_ := int(args.get("seed", "1"))
	var comp: Dictionary = COMP68 if args.get("comp", "60") == "68" else COMP60
	var squads := int(args.get("squads", "10"))
	var fa: String = args.get("a", "plektor")
	var fb: String = args.get("b", "troyden")
	var listen := args.has("listen")
	var f := FileAccess.open("res://data/space_data.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var t0 := Time.get_ticks_usec()
	var sim := BattleSim.new(data, seed_)
	sim.add_fleet(0, fa, comp, squads)
	sim.add_fleet(1, fb, comp, squads)
	sim.prof = args.has("prof")
	sim.fast = args.has("fast")
	if listen:
		var cnt := [0]
		sim.damaged.connect(func(_t, _a, _k, _s): cnt[0] += 1)
	var tload := Time.get_ticks_usec() - t0
	if mode == "steady":
		sim.invulnerable = true
		var times := PackedFloat64Array()
		times.resize(steps)
		var t1 := Time.get_ticks_usec()
		var maxproj := 0
		for i in steps:
			var a := Time.get_ticks_usec()
			sim.step()
			times[i] = (Time.get_ticks_usec() - a) / 1000.0
			maxproj = maxi(maxproj, sim.proj.size())
		var total := (Time.get_ticks_usec() - t1) / 1e6
		if sim.prof:
			print("PROF ms/step ecm+ai=%.3f ships=%.3f craft=%.3f proj=%.3f measure=%.3f" % [sim.prof_us[0]/1000.0/steps, sim.prof_us[1]/1000.0/steps, sim.prof_us[2]/1000.0/steps, sim.prof_us[3]/1000.0/steps, sim.prof_us[4]/1000.0/steps])
		var sorted := times.duplicate()
		sorted.sort()
		print("STEADY ships=%d craft=%d steps=%d total_s=%.3f mean_ms=%.3f p50=%.3f p99=%.3f max=%.3f maxproj=%d load_ms=%.1f" % [
			sim.ships.size(), sim.craft.size(), steps, total, total * 1000.0 / steps,
			sorted[steps / 2], sorted[int(steps * 0.99)], sorted[steps - 1], maxproj, tload / 1000.0])
	else:
		var runs := int(args.get("runs", "1"))
		var tall := Time.get_ticks_usec()
		for r in runs:
			if r > 0:
				sim = BattleSim.new(data, seed_ + r)
				sim.fast = args.has("fast")
				sim.add_fleet(0, fa, comp, squads)
				sim.add_fleet(1, fb, comp, squads)
			_battle(sim, args, seed_ + r)
		print("ALL runs=%d wall_s=%.2f" % [runs, (Time.get_ticks_usec() - tall) / 1e6])
	quit()

func _battle(sim: BattleSim, args: Dictionary, seed_: int) -> void:
	if true:
		var maxs := int(args.get("max_t", "900")) * 30
		var t1 := Time.get_ticks_usec()
		var i := 0
		while i < maxs:
			sim.step()
			i += 1
			if sim.alive_count(0) == 0 or sim.alive_count(1) == 0:
				break
		var total := (Time.get_ticks_usec() - t1) / 1e6
		var winner := -1
		if sim.alive_count(0) == 0:
			winner = 1
		elif sim.alive_count(1) == 0:
			winner = 0
		var dk := sim.dmg_by_key
		var dsum := 0.0
		for v in dk:
			dsum += v
		print("BATTLE seed=%d game_s=%.1f cpu_s=%.3f ms_per_step=%.3f winner=%d alive=%d/%d first_hit=%.1f band=%.2f close=%.2f L=%.0f hash=%d dmg%%: main=%.0f sec=%.0f light=%.0f air=%.0f" % [
			seed_, sim.t, total, total * 1000.0 / maxi(i, 1), winner, sim.alive_count(0), sim.alive_count(1), sim.first_hit,
			sim.m_band_s / maxf(sim.m_heavy_s, 0.001), sim.m_close_s / maxf(sim.m_heavy_s, 0.001),
			sim.m_line_sum / maxi(sim.m_line_n, 1), sim.state_hash(),
			100.0 * dk[0] / dsum, 100.0 * dk[7] / dsum, 100.0 * dk[2] / dsum, 100.0 * (dk[4] + dk[5] + dk[6]) / dsum])

