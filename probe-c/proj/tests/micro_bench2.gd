extends SceneTree
const Ent = preload("res://sim/ent.gd")
func _init():
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	var n := 69
	var untyped: Array = []
	var typed: Array[Ent.Ship] = []
	for i in n:
		var s := Ent.Ship.new()
		s.pos = Vector3(rng.randf_range(-700, 700), rng.randf_range(-35, 35), rng.randf_range(-700, 700))
		s.hull = [15.1, 19.7, 40.6, 74.5][i % 4]; s.side = "attacker" if i % 2 else "defender"
		s.def = {"maxSpeed": 30.0}
		untyped.append(s); typed.append(s)
	var steps := 600
	var acc := Vector3.ZERO
	var t0 := Time.get_ticks_usec()
	for k in steps:
		for e in untyped:
			var desired := Vector3.ZERO
			var ms: float = e.def.maxSpeed
			for o in untyped:
				if o == e or o.dead: continue
				var foe: bool = o.side != e.side
				var mn: float = (o.hull + e.hull) * (1.15 if foe else 1.0)
				var dv: Vector3 = e.pos - o.pos
				var dd2 := dv.length_squared()
				if dd2 >= mn * mn: continue
				var dd := sqrt(dd2)
				if dd > 0.01: desired += dv / dd * ((mn - dd) / mn * ms * (1.1 if foe else 0.8))
			acc += desired
	var tA := (Time.get_ticks_usec() - t0) / 1000.0 / steps
	t0 = Time.get_ticks_usec()
	for k in steps:
		for e: Ent.Ship in typed:
			var desired := Vector3.ZERO
			var ms: float = e.def.maxSpeed
			var ep := e.pos; var eh := e.hull; var es := e.side
			var lim := eh + 74.5 * 1.15 + 1.0       # самый крупный корпус — отсечка по оси
			for o: Ent.Ship in typed:
				var op := o.pos
				var dx := ep.x - op.x
				if dx > lim or dx < -lim: continue
				var dz := ep.z - op.z
				if dz > lim or dz < -lim: continue
				if o == e or o.dead: continue
				var foe := o.side != es
				var mn := (o.hull + eh) * (1.15 if foe else 1.0)
				var dv := ep - op
				var dd2 := dv.length_squared()
				if dd2 >= mn * mn: continue
				var dd := sqrt(dd2)
				if dd > 0.01: desired += dv / dd * ((mn - dd) / mn * ms * (1.1 if foe else 0.8))
			acc += desired
	var tB := (Time.get_ticks_usec() - t0) / 1000.0 / steps
	# Сетка по клеткам 200: пары только из соседних клеток (порядок сложения другой)
	t0 = Time.get_ticks_usec()
	for k in steps:
		var grid := {}
		for i in n:
			var p: Vector3 = typed[i].pos
			var key := Vector2i(floori(p.x / 200.0), floori(p.z / 200.0))
			if not grid.has(key): grid[key] = PackedInt32Array()
			grid[key].append(i)
		for i in n:
			var e: Ent.Ship = typed[i]
			var desired := Vector3.ZERO
			var c := Vector2i(floori(e.pos.x / 200.0), floori(e.pos.z / 200.0))
			for gx in range(c.x - 1, c.x + 2):
				for gz in range(c.y - 1, c.y + 2):
					var cell = grid.get(Vector2i(gx, gz))
					if cell == null: continue
					for j in cell:
						if j == i: continue
						var o: Ent.Ship = typed[j]
						var foe := o.side != e.side
						var mn := (o.hull + e.hull) * (1.15 if foe else 1.0)
						var dv := e.pos - o.pos
						var dd2 := dv.length_squared()
						if dd2 >= mn * mn: continue
						var dd := sqrt(dd2)
						if dd > 0.01: desired += dv / dd * ((mn - dd) / mn * 30.0 * (1.1 if foe else 0.8))
			acc += desired
	var tC := (Time.get_ticks_usec() - t0) / 1000.0 / steps
	print("расталкивание 69 кораблей, мс на шаг: как в JS (нетипизированный цикл) %.3f; типизированный цикл + отсечка по оси %.3f (x%.1f); сетка %.3f (x%.1f)" % [tA, tB, tA / tB, tC, tA / tC])
	# Цикл по 200 машинам — поиск ближайшей (ПВО)
	var craft: Array = []
	for i in 200:
		var c := Ent.Craft.new(); c.pos = Vector3(rng.randf_range(-900, 900), 0, rng.randf_range(-900, 900)); c.side = "attacker" if i % 2 else "defender"
		craft.append(c)
	t0 = Time.get_ticks_usec()
	var found := 0
	for k in 10000:
		var best = null; var bd := 160.0 * 160.0
		var from: Vector3 = typed[k % n].pos
		for e in craft:
			if e.dead or e.side != "attacker": continue
			var d: float = e.pos.distance_squared_to(from)
			if d < bd: bd = d; best = e
		if best: found += 1
	print("поиск ближайшей машины среди 200: %.1f мкс на поиск" % ((Time.get_ticks_usec() - t0) / 10000.0))
	quit()
