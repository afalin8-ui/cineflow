## Где уходит время шага: повторяет Battle.step по частям с замером.
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
	var acc := {"lists": 0, "ai": 0, "ship_total": 0, "push": 0, "pd": 0, "craft": 0, "proj": 0, "metrics": 0, "cleanup": 0}
	var dt := Battle.STEP
	var n := 0
	while b.time < 60.0:
		b.time += dt; b.steps += 1; b.events.clear()
		var t := Time.get_ticks_usec()
		b._rebuild_lists(); b._update_ecm()
		acc["lists"] += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		b._build_spatial()
		acc["push"] += Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		for a in b.ai: a.snapshot()
		for a in b.ai: a.tick(dt)
		acc["ai"] += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		for s in b.ships:
			if not s.dead: b._update_ship(s, dt)
		acc["ship_total"] += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		for s in b.ships:
			if not s.dead: b._fire_pd(s, 0.0)
		acc["pd"] += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		for c in b.crafts:
			if not c.dead: b._update_craft(c, dt)
		acc["craft"] += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		for p in b.projs:
			if not p.dead: b._update_proj(p, dt)
		acc["proj"] += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		b._cleanup()
		acc["cleanup"] += Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		b.metrics.sample(b, dt)
		acc["metrics"] += Time.get_ticks_usec() - t
		n += 1
	var out := {}
	for k in acc: out[k] = snappedf(acc[k] / 1000.0 / n, 0.001)
	print("ms per step: ", JSON.stringify(out))
	quit()
