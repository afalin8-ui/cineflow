extends SceneTree
## Автобой ИИ против ИИ без экрана. Печатает проверку «не свалка».
## godot --headless --path capella -s res://tools/autobattle.gd -- troyden plector hard S 1

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var f0: String = a[0] if a.size() > 0 else "troyden"
	var f1: String = a[1] if a.size() > 1 else "plector"
	var diff: String = a[2] if a.size() > 2 else "hard"
	var size: String = a[3] if a.size() > 3 else "S"
	var sd: int = int(a[4]) if a.size() > 4 else 1
	var w := World.new()
	w.setup({"facs": [f0, f1], "size": size, "seed": sd, "ai": [diff, diff]})
	var limit := 40.0 * 60.0
	var t0 := Time.get_ticks_msec()
	var next_log := 120.0
	while w.winner < 0 and w.time < limit:
		w.step()
		if w.time >= next_log:
			next_log += 120.0
			var line := "%5.0fс" % w.time
			for t in 2:
				var st: Unit = w.teams[t].station
				var n := 0
				for u in w.units:
					if u.alive and u.team == t and not u.is_station():
						n += 1
				line += "  | %s ур%d руда %5.0f юнитов %2d очки %2d/%2d станция %3.0f%%" % [Defs.fac_name(w.teams[t].fac), st.level, w.teams[t].ore, n, w.fleet_points(t), w.fleet_cap(t), 100.0 * st.hull / st.hull_max]
			print(line)
			for t in 2:
				var ai: AIPlayer = w.ais[t]
				var big := 0
				var xs := 0.0
				var n2 := 0
				for u in w.units:
					if u.alive and u.team == t and not u.is_squad() and not u.is_station() and u.cls != "harvester":
						n2 += 1
						xs += u.pos.x
						if u.is_big():
							big += 1
				var comp := {}
				for u in w.units:
					if u.alive and u.team == t and not u.is_station():
						comp[u.def.name] = comp.get(u.def.name, 0) + 1
				print("        ", comp)
				print("        ИИ%d: %s волна %d, кораблей %d (крупных %d), центр x=%.0f км, waypoint x=%.0f" % [t, ai.state, ai.wave, n2, big, xs / max(n2, 1) / 1000.0, ai.waypoint.x / 1000.0])
	var s := w.stats
	var big_total: float = s.big_far + s.big_close
	print("--- итог ---")
	print("победа: %s  время: %.1f мин  (счёт %.1f с)" % ["нет" if w.winner < 0 else Defs.fac_name(w.teams[w.winner].fac) + " (сторона %d)" % w.winner, w.time / 60.0, (Time.get_ticks_msec() - t0) / 1000.0])
	print("первый контакт: %.1f мин" % (s.first_contact / 60.0))
	print("крупные дальше 3 км от крупных врага: %.0f%% (%.0f с из %.0f)" % [100.0 * s.big_far / max(big_total, 1.0), s.big_far, big_total])
	print("перехваты звено-звено: попаданий %d, сбито звеньев звеньями %d" % [s.sq_vs_sq, s.sq_kills_sq])
	print("построено %s, потеряно %s, отступлений %s, добыто %.0f / %.0f" % [s.built, s.lost, s.retreats, w.teams[0].mined, w.teams[1].mined])
	var ok_far: bool = big_total > 0 and s.big_far / big_total > 0.5
	var ok_time: bool = w.winner >= 0 and w.time >= 15 * 60 and w.time <= 25 * 60
	var ok_sq: bool = s.sq_kills_sq > 0
	print("ПРОВЕРКА: дистанция %s, длительность %s, перехваты %s" % ["ok" if ok_far else "НЕТ", "ok" if ok_time else "НЕТ", "ok" if ok_sq else "НЕТ"])
	quit(0 if (ok_far and ok_time and ok_sq) else 1)
