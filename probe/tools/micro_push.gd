## Расталкивание 60 кораблей: четыре способа хранения/обхода, одинаковый результат.
extends SceneTree

const Defs = preload("res://sim/defs.gd")
const Battle = preload("res://sim/battle.gd")
const Runner = preload("res://tools/runner.gd")

func _initialize() -> void:
	var defs := Defs.new()
	defs.load_all()
	var cfg: Array = Runner.LOADS["p30"]
	var b := Battle.new()
	b.setup(defs, 1, [Runner.fleet(cfg[0][1]), Runner.fleet(cfg[1][1])], [cfg[0][0], cfg[1][0]])
	while b.time < 40.0: b.step()
	var ships: Array = b.ships.filter(func(s): return not s.dead)
	var n := ships.size()
	var REP := 300
	# (a) объекты, каждый с каждым
	var t := Time.get_ticks_usec()
	var res_a := PackedVector3Array(); res_a.resize(n)
	for r in REP:
		for i in n:
			var s = ships[i]
			var want := Vector3.ZERO
			for o in ships:
				if o == s: continue
				var is_foe: bool = o.side != s.side
				var mn: float = (o.d.hull + s.d.hull) * (1.15 if is_foe else 1.0)
				var off: Vector3 = s.pos - o.pos
				var d2 := off.length_squared()
				if d2 < mn * mn and d2 > 0.0001:
					var dd := sqrt(d2)
					want += off / dd * ((mn - dd) / mn) * s.d.max_speed * (1.1 if is_foe else 0.8)
			res_a[i] = want
	var ua := (Time.get_ticks_usec() - t) / float(REP)
	# (b) упакованные массивы, пары i<j
	var pos := PackedVector3Array(); var hull := PackedFloat32Array(); var side := PackedInt32Array(); var vmax := PackedFloat32Array()
	for s in ships:
		pos.append(s.pos); hull.append(s.d.hull); side.append(s.side); vmax.append(s.d.max_speed)
	t = Time.get_ticks_usec()
	var res_b := PackedVector3Array(); res_b.resize(n)
	for r in REP:
		res_b.fill(Vector3.ZERO)
		for i in n:
			var pi := pos[i]; var hi := hull[i]; var si := side[i]
			for j in range(i + 1, n):
				var is_foe := side[j] != si
				var mn := (hull[j] + hi) * (1.15 if is_foe else 1.0)
				var off := pi - pos[j]
				var d2 := off.length_squared()
				if d2 < mn * mn and d2 > 0.0001:
					var dd := sqrt(d2)
					var k := (mn - dd) / mn / dd
					var f := 1.1 if is_foe else 0.8
					res_b[i] += off * (k * vmax[i] * f)
					res_b[j] -= off * (k * vmax[j] * f)
	var ub := (Time.get_ticks_usec() - t) / float(REP)
	# (c) сетка 180×180 по объектам
	t = Time.get_ticks_usec()
	var res_c := PackedVector3Array(); res_c.resize(n)
	var CELL := 180.0
	for r in REP:
		var grid := {}
		for i in n:
			var p: Vector3 = ships[i].pos
			var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
			if grid.has(key): grid[key].append(i)
			else: grid[key] = [i]
		for i in n:
			var s = ships[i]
			var want := Vector3.ZERO
			var cx := floori(s.pos.x / CELL); var cz := floori(s.pos.z / CELL)
			for gx in range(cx - 1, cx + 2):
				for gz in range(cz - 1, cz + 2):
					var cell = grid.get(Vector2i(gx, gz))
					if cell == null: continue
					for j in cell:
						if j == i: continue
						var o = ships[j]
						var is_foe: bool = o.side != s.side
						var mn: float = (o.d.hull + s.d.hull) * (1.15 if is_foe else 1.0)
						var off: Vector3 = s.pos - o.pos
						var d2 := off.length_squared()
						if d2 < mn * mn and d2 > 0.0001:
							var dd := sqrt(d2)
							want += off / dd * ((mn - dd) / mn) * s.d.max_speed * (1.1 if is_foe else 0.8)
			res_c[i] = want
	var uc := (Time.get_ticks_usec() - t) / float(REP)
	var diff_b := 0.0; var diff_c := 0.0
	for i in n:
		diff_b = maxf(diff_b, res_a[i].distance_to(res_b[i])); diff_c = maxf(diff_c, res_a[i].distance_to(res_c[i]))
	print(JSON.stringify({"ships": n, "objects_all_pairs_us": ua, "packed_half_pairs_us": ub, "grid_objects_us": uc, "max_diff_b": diff_b, "max_diff_c": diff_c, "build": "debug" if OS.is_debug_build() else "release"}))
	quit()
