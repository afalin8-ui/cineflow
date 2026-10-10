extends SceneTree
# Микрозамер: сущность словарём (как объект JS) против типизированного класса.
class ShipT:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var hull := 0.0
	var side := 0
	var dead := false
	var max_speed := 30.0
	var hp := 100.0

func _init():
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	var n := 60
	var dicts: Array = []
	var typed: Array[ShipT] = []
	for i in n:
		var p := Vector3(rng.randf_range(-800, 800), rng.randf_range(-35, 35), rng.randf_range(-800, 800))
		dicts.append({"pos": p, "vel": Vector3.ZERO, "hull": 30.0, "side": i % 2, "dead": false, "def": {"maxSpeed": 30.0}, "hp": 100.0})
		var t := ShipT.new(); t.pos = p; t.hull = 30.0; t.side = i % 2
		typed.append(t)
	var steps := 900
	# словари
	var t0 := Time.get_ticks_usec()
	var acc := Vector3.ZERO
	for s in steps:
		for e in dicts:
			var desired := Vector3.ZERO
			for o in dicts:
				if o == e or o.dead: continue
				var foe: bool = o.side != e.side
				var dd: float = o.pos.distance_to(e.pos)
				var mn: float = (o.hull + e.hull) * (1.15 if foe else 1.0)
				if dd < mn and dd > 0.01:
					desired += (e.pos - o.pos) / dd * ((mn - dd) / mn * e.def.maxSpeed * (1.1 if foe else 0.8))
			acc += desired
	var t_dict := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	for s in steps:
		for e in typed:
			var desired := Vector3.ZERO
			for o in typed:
				if o == e or o.dead: continue
				var foe := o.side != e.side
				var dd := o.pos.distance_to(e.pos)
				var mn := (o.hull + e.hull) * (1.15 if foe else 1.0)
				if dd < mn and dd > 0.01:
					desired += (e.pos - o.pos) / dd * ((mn - dd) / mn * e.max_speed * (1.1 if foe else 0.8))
			acc += desired
	var t_typed := (Time.get_ticks_usec() - t0) / 1000.0
	print("push-apart 60x60, %d steps: dict %.1f ms (%.3f ms/step), typed %.1f ms (%.3f ms/step), x%.2f" % [steps, t_dict, t_dict/steps, t_typed, t_typed/steps, t_dict/t_typed])
	# Проверка ловушки: опечатка в имени поля
	var e0: Dictionary = dicts[0]
	e0.hpp = 5.0   # молча создаёт новый ключ — как в JS
	print("typo in dict silently created key: ", e0.has("hpp"))
	# Числа из JSON
	var j = JSON.parse_string('{"hp": 1451, "dmg": 16.099999999999998}')
	print("JSON int -> ", typeof(j.hp), " (TYPE_FLOAT=", TYPE_FLOAT, ") str=", str(j.hp), " fmt %d=", "%d" % j.hp, " dmg=", j.dmg, " str(dmg)=", str(j.dmg))
	var v := Vector3(0.1, 0.2, 0.3)
	print("Vector3 component 0.1 stored as: %.17f (float32?)" % v.x, "  float 0.1: %.17f" % 0.1)
	quit()
