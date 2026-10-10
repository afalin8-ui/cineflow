extends SceneTree
# Сто боёв «ИИ против ИИ» без отрисовки: время процессора на бой и на шаг.
# godot --headless --path proj --script res://tests/bench.gd -- scen=big_pp n=3 doctrine=0 seed=1 prof=1
const Battle = preload("res://sim/battle.gd")

func arg(name: String, def):
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="): return a.split("=")[1]
	return def

func _init():
	var D: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/space_data.json"))
	var DOC: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/doctrine.json"))
	var scen: String = arg("scen", "mid_tp")
	var n := int(arg("n", "3")); var seed0 := int(arg("seed", "1"))
	var doc: bool = arg("doctrine", "0") == "1"
	var prof: bool = arg("prof", "0") == "1"
	var tmax := float(arg("tmax", "900"))
	var F: Dictionary = D.quick_battle.fleets
	var A: Dictionary; var B: Dictionary
	match scen:
		"mid_tp": A = {"faction": "troyden", "ships": F.mid.troyden}; B = {"faction": "plektor", "ships": F.mid.plektor}
		"mid_pt": A = {"faction": "plektor", "ships": F.mid.plektor}; B = {"faction": "troyden", "ships": F.mid.troyden}
		"big_pp": A = {"faction": "plektor", "ships": F.big.plektor}; B = {"faction": "plektor", "ships": F.big.plektor, "station": true}
		"small_tp": A = {"faction": "troyden", "ships": F.small.troyden}; B = {"faction": "plektor", "ships": F.small.plektor}
	var results := []
	var cpu_total := 0.0
	for k in n:
		var b = Battle.new(D, DOC, {"attacker": A, "defender": B, "ai_sides": ["attacker", "defender"], "difficulty": "normal"},
			seed0 + k, {"doctrine": doc})
		b.prof_on = prof
		var dt := 1.0 / 30.0
		var steps := 0; var worst := 0; var peak_craft := 0; var peak_proj := 0; var peak_ships := 0
		var t_start := Time.get_ticks_usec()
		while not b.state.ended and b.state.time < tmax:
			var s0 := Time.get_ticks_usec()
			b.sim_step(dt)
			var s1 := Time.get_ticks_usec() - s0
			worst = maxi(worst, s1); steps += 1
			peak_craft = maxi(peak_craft, b.state.craft.size()); peak_proj = maxi(peak_proj, b.state.proj.size())
			var alive := 0
			for s in b.state.ships:
				if not s.dead: alive += 1
			peak_ships = maxi(peak_ships, alive)
		var cpu := (Time.get_ticks_usec() - t_start) / 1e6
		cpu_total += cpu
		var m: Dictionary = b.metrics
		var Ls: Array = m.L_samples.duplicate(); Ls.sort()
		var Lmed: float = Ls[Ls.size() / 2] if Ls.size() > 0 else -1.0
		var dm: Dictionary = m.dmg; var ship_total := 0.0
		for key in dm:
			if key.ends_with(":ship"): ship_total += dm[key]
		var share_s := ""
		for key in ["heavy:ship", "sec:ship", "light:ship", "missile:ship", "gunInt:ship", "gunFig:ship", "torp:ship"]:
			if dm.has(key): share_s += "%s %.0f%% " % [key.split(":")[0], 100.0 * dm[key] / maxf(1, ship_total)]
		var r := {"seed": seed0 + k, "result": b.state.result, "time": b.state.time, "cpu": cpu, "steps": steps,
			"ms_step": 1000.0 * cpu / steps, "worst_ms": worst / 1000.0, "peak_ships": peak_ships, "peak_craft": peak_craft,
			"peak_proj": peak_proj, "first_hit": b.state.stats.first_hit, "first_gun": b.state.stats.first_gun,
			"belt": m.belt_t / maxf(1e-6, m.cap_t), "close": m.close_t / maxf(1e-6, m.cap_t), "L_med": Lmed, "dmg": share_s, "fx": b.fx_count}
		results.append(r)
		if arg("dispose", "1") == "1": b.dispose()
		print(JSON.stringify(r))
		if prof:
			var tot := 0
			for kk in b.prof: tot += b.prof[kk]
			var line := ""
			for kk in b.prof: line += "%s %.0f%%  " % [kk, 100.0 * b.prof[kk] / tot]
			print("  профиль шага: ", line)
	print("объектов в памяти до разрыва ссылок: ", Performance.get_monitor(Performance.OBJECT_COUNT))
	print("ИТОГО %s doctrine=%s: боёв %d, процессор %.1f с, в среднем %.2f с на бой" % [scen, doc, n, cpu_total, cpu_total / n])
	quit()
