## «По-годотовски»: каждый корабль, машина и ракета — узел Node3D со скриптом,
## шаг — _physics_process узлов; вариант areas: купол РЭБ — Area3D,
## цели ПВО — intersect_shape физического мира.
## godot --headless --path proj --fixed-fps 30 -s res://bench/nodes_bench.gd -- variant=nodes|areas frames=1800
extends SceneTree

const COMP60 := {"corvette": 7, "frigate": 7, "ecm": 3, "cruiser": 5, "carrier": 4, "capital": 4}
const L_SHIP := 1
const L_AIR := 2

var sim: BattleSim
var variant := "nodes"
var frames := 1800
var frame := 0
var t_start := 0
var step_us := 0
var root3d: Node3D
var ship_nodes: Array = []
var craft_nodes: Array = []
var proj_nodes := {}   # Proj -> Node3D
var area_of := {}      # Area3D instance_id -> object (Craft/Proj)
var domes: Array = []  # [Area3D, Ship]
var query := PhysicsShapeQueryParameters3D.new()
var qshape := SphereShape3D.new()

class Mgr extends Node:
	var b
	func _physics_process(_d: float) -> void:
		b._pre()

class ShipNode extends Node3D:
	var b
	var s
	func _physics_process(_d: float) -> void:
		if s.alive:
			b.sim._ship_step(s)
			position = s.pos
			rotation.y = s.yaw

class CraftNode extends Node3D:
	var b
	var c
	func _physics_process(_d: float) -> void:
		if c.alive:
			b.sim._craft_step(c)
			position = c.pos
			rotation.y = c.yaw
		elif visible:
			visible = false
			process_mode = Node.PROCESS_MODE_DISABLED

class PostNode extends Node:
	var b
	func _physics_process(_d: float) -> void:
		b._post()

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv[0] == "variant": variant = kv[1]
		if kv[0] == "frames": frames = int(kv[1])
	var f := FileAccess.open("res://data/space_data.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	sim = BattleSim.new(data, 1)
	sim.fast = true
	sim.invulnerable = true
	sim.add_fleet(0, "plektor", COMP60, 10)
	sim.add_fleet(1, "troyden", COMP60, 10)
	root3d = Node3D.new()
	root.add_child(root3d)
	var m := Mgr.new(); m.b = self
	root3d.add_child(m)
	qshape.radius = 160.0
	query.shape = qshape
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = L_AIR
	for s in sim.ships:
		var n := ShipNode.new(); n.b = self; n.s = s
		n.position = s.pos
		root3d.add_child(n)
		ship_nodes.append(n)
		if variant == "areas" and s.cls == BattleSim.ECM:
			var a := Area3D.new()
			a.collision_layer = 0
			a.collision_mask = L_SHIP
			a.monitorable = false
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new(); cyl.radius = 420.0; cyl.height = 180.0
			cs.shape = cyl
			a.add_child(cs)
			n.add_child(a)
			domes.append([a, s])
		if variant == "areas":
			var a2 := Area3D.new()
			a2.collision_layer = L_SHIP
			a2.collision_mask = 0
			a2.monitoring = false
			var cs2 := CollisionShape3D.new()
			var sp := SphereShape3D.new(); sp.radius = s.hull
			cs2.shape = sp
			a2.add_child(cs2)
			a2.set_meta("ship", s.id)
			n.add_child(a2)
	for c in sim.craft:
		var n := CraftNode.new(); n.b = self; n.c = c
		n.position = c.pos
		root3d.add_child(n)
		craft_nodes.append(n)
		if variant == "areas":
			_add_air_area(n, c)
	var post := PostNode.new(); post.b = self
	root3d.add_child(post)
	if variant == "areas":
		sim.phys_pd = _phys_pd
		sim.ecm_external = true
	t_start = Time.get_ticks_usec()

func _add_air_area(n: Node3D, o: Object) -> void:
	var a := Area3D.new()
	a.collision_layer = L_AIR
	a.collision_mask = 0
	a.monitoring = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new(); sp.radius = 3.0
	cs.shape = sp
	a.add_child(cs)
	n.add_child(a)
	area_of[a.get_instance_id()] = o

func _pre() -> void:
	step_us -= Time.get_ticks_usec()
	sim.t += BattleSim.DT
	sim.steps += 1
	if variant == "areas":
		for s in sim.ships:
			s.jam = false
		for pair in domes:
			var dome: Area3D = pair[0]
			var e = pair[1]
			for a in dome.get_overlapping_areas():
				var sid: int = a.get_meta("ship", -1)
				if sid >= 0 and sim.ships[sid].side != e.side:
					sim.ships[sid].jam = true
	else:
		sim._update_ecm()
	for side in 2:
		sim.ai_t[side] -= BattleSim.DT
		if sim.ai_t[side] <= 0.0:
			sim.ai_t[side] = 0.5
			sim._ai(side)
	sim._pairs()
	sim._build_grid()

func _post() -> void:
	# ракеты — тоже узлы: рождаются и умирают
	for p in sim.proj:
		if p.alive:
			sim._proj_step(p)
		var n: Node3D = proj_nodes.get(p)
		if p.alive:
			if n == null:
				n = Node3D.new()
				root3d.add_child(n)
				proj_nodes[p] = n
				if variant == "areas":
					_add_air_area(n, p)
			n.position = p.pos
		elif n != null:
			proj_nodes.erase(p)
			if variant == "areas":
				area_of.erase(n.get_child(0).get_instance_id())
			n.queue_free()
	if sim.steps % 30 == 0:
		sim._compact()
	sim._measure()
	step_us += Time.get_ticks_usec()

func _phys_pd(s) -> Array:
	var space := root3d.get_world_3d().direct_space_state
	qshape.radius = s.pd_range
	query.transform = Transform3D(Basis.IDENTITY, s.pos)
	var best_p = null
	var best_c = null
	var bp := INF
	var bc := INF
	for hit in space.intersect_shape(query, 64):
		var o = area_of.get(hit.collider_id)
		if o == null or not o.alive or o.side == s.side:
			continue
		var d2: float = s.pos.distance_squared_to(o.pos)
		if o is BattleSim.Proj:
			if d2 < bp: bp = d2; best_p = o
		elif d2 < bc:
			bc = d2; best_c = o
	return [best_p, null if best_p else best_c]

func _process(_d: float) -> bool:
	frame += 1
	if frame >= frames:
		var tot := (Time.get_ticks_usec() - t_start) / 1e6
		print("NODES variant=%s frames=%d wall_s=%.3f per_frame_ms=%.3f sim_part_ms=%.3f proj_nodes=%d" % [variant, frame, tot, tot * 1000.0 / frame, step_us / 1000.0 / frame, proj_nodes.size()])
		return true
	return false
