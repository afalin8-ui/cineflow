extends Node3D
## Экран боя: рисует World и переводит мышь и клавиши в приказы.
## Сам ничего не решает — всё через world.cmd_*.

signal exit_to_menu

const S := 0.1   # метры -> единицы сцены
const TEAM_COL := [Color(0.35, 0.75, 1.0), Color(1.0, 0.42, 0.28)]

var world: World
var cfg := {}
var me := 0                 # чья сторона у игрока; -1 — зритель (ИИ против ИИ)
var speed := 1.0
var paused := false
var accum := 0.0

var cam: Camera3D
var pivot := Vector3.ZERO
var yaw := 0.0
var pitch := deg_to_rad(58)
var dist := 1500.0

var nodes := {}             # unit.id -> Node3D
var sel: Array = []         # выбранные юниты
var groups := {}            # цифра -> [юниты]
var attack_move := false
var drag_start = null
var drag_now := Vector2.ZERO
var mmb_drag := false
var hover = null

var shot_mesh: ImmediateMesh
var proj_mm: MultiMeshInstance3D
var hud

func start(c: Dictionary) -> void:
	cfg = c
	me = c.get("me", 0)
	world = World.new()
	world.setup(c)
	_build_scene()
	var st: Unit = world.teams[max(me, 0)].station
	pivot = Vector3(st.pos.x * S * 0.8, 0, st.pos.y * S)
	yaw = 0.0 if max(me, 0) == 0 else PI
	hud = preload("res://scripts/view/hud.gd").new()
	add_child(hud)
	hud.setup(self)

func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.02, 0.035)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.38, 0.45)
	e.ambient_light_energy = 0.6
	e.glow_enabled = true
	e.glow_intensity = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	sun.light_energy = 1.2
	add_child(sun)
	cam = Camera3D.new()
	cam.far = 60000.0
	cam.near = 5.0
	cam.fov = 50.0
	add_child(cam)
	_stars()
	_map_decor()
	shot_mesh = ImmediateMesh.new()
	var smi := MeshInstance3D.new()
	smi.mesh = shot_mesh
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smi.material_override = sm
	add_child(smi)
	proj_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sp := SphereMesh.new()
	sp.radius = 3.0
	sp.height = 6.0
	sp.radial_segments = 6
	sp.rings = 3
	mm.mesh = sp
	mm.instance_count = 800
	mm.visible_instance_count = 0
	proj_mm.multimesh = mm
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	proj_mm.material_override = pm
	add_child(proj_mm)

func _stars() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(14, 14)
	mm.mesh = q
	mm.instance_count = 1500
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in mm.instance_count:
		var d := Vector3(r.randf_range(-1, 1), r.randf_range(-1, -0.05), r.randf_range(-1, 1)).normalized()
		var p := d * 14000.0
		var t := Transform3D(Basis.IDENTITY, p).looking_at(Vector3.ZERO, Vector3.UP if abs(d.y) < 0.99 else Vector3.FORWARD)
		mm.set_instance_transform(i, t.scaled_local(Vector3.ONE * r.randf_range(0.4, 1.6)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.8, 0.85, 1.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mi.material_override = m
	add_child(mi)

func _map_decor() -> void:
	var W := world.map_w * S
	# Граница карты и сетка через 5 км — чтобы на глаз мерить дистанцию.
	var g := ImmediateMesh.new()
	g.surface_begin(Mesh.PRIMITIVE_LINES)
	var step := 500.0
	var n := int(W / step)
	for i in n + 1:
		var x := -W / 2 + i * step
		var c := Color(0.25, 0.3, 0.4, 0.22) if i % n != 0 else Color(0.5, 0.6, 0.8, 0.7)
		g.surface_set_color(c)
		g.surface_add_vertex(Vector3(x, -30, -W / 2))
		g.surface_set_color(c)
		g.surface_add_vertex(Vector3(x, -30, W / 2))
		g.surface_set_color(c)
		g.surface_add_vertex(Vector3(-W / 2, -30, x))
		g.surface_set_color(c)
		g.surface_add_vertex(Vector3(W / 2, -30, x))
	g.surface_end()
	var gi := MeshInstance3D.new()
	gi.mesh = g
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.vertex_color_use_as_albedo = true
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gi.material_override = gm
	add_child(gi)
	# Планета посередине — декор: плоский диск под плоскостью боя (объёмная лезла под корабли из-за перспективы).
	var pr: float = world.planet.r * S
	for k in 2:
		var pl := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = pr * (1.0 if k == 0 else 1.08)
		pc.bottom_radius = pc.top_radius
		pc.height = 4
		pc.radial_segments = 64
		pl.mesh = pc
		pl.position = Vector3(0, -60 - k * 4, 0)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.16, 0.24, 0.36) if k == 0 else Color(0.3, 0.45, 0.65, 0.35)
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if k == 1:
			pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pl.material_override = pmat
		add_child(pl)
	# Туманности: полупрозрачные диски.
	for nb in world.nebulas:
		for k in 3:
			var d := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			var rr: float = nb.r * S * (1.0 - k * 0.18)
			cm.top_radius = rr
			cm.bottom_radius = rr
			cm.height = 40 + k * 60
			cm.radial_segments = 48
			d.mesh = cm
			d.position = Vector3(nb.pos.x * S, -10 + k * 25, nb.pos.y * S)
			var nm := StandardMaterial3D.new()
			nm.albedo_color = Color(0.55, 0.3, 0.75, 0.09)
			nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			nm.cull_mode = BaseMaterial3D.CULL_DISABLED
			nm.no_depth_test = false
			d.material_override = nm
			add_child(d)
	# Поля астероидов.
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 1.6
	rock.radial_segments = 6
	rock.rings = 4
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.45, 0.4, 0.35)
	rm.roughness = 1.0
	var r := RandomNumberGenerator.new()
	r.seed = 11
	for f in world.fields:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = rock
		mm.instance_count = 160
		for i in mm.instance_count:
			var a := r.randf() * TAU
			var rad: float = sqrt(r.randf()) * f.r * S
			var p := Vector3(f.pos.x * S + cos(a) * rad, r.randf_range(-40, 40), f.pos.y * S + sin(a) * rad)
			var b := Basis.from_euler(Vector3(r.randf() * TAU, r.randf() * TAU, 0)).scaled(Vector3.ONE * r.randf_range(4, 22))
			mm.set_instance_transform(i, Transform3D(b, p))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = rm
		add_child(mi)
		f.node = mi

# ---------------------------------------------------------------- кадр

func _process(delta: float) -> void:
	_camera(delta)
	if not paused and world.winner < 0:
		accum += delta * speed
		var steps := 0
		while accum >= World.DT and steps < 40:
			world.step()
			accum -= World.DT
			steps += 1
		if steps >= 40:
			accum = 0.0
	_sync_nodes()
	_draw_shots()
	sel = sel.filter(func(u): return u.alive and u.in_hyper <= 0)
	hover = _pick(get_viewport().get_mouse_position())

func seen(u: Unit) -> bool:
	if me < 0:
		return true
	return world.visible_to(me, u)

func _sync_nodes() -> void:
	var alpha: float = clamp(accum / World.DT, 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	var alive_ids := {}
	for u in world.units:
		if not u.alive:
			continue
		alive_ids[u.id] = true
		var n: Node3D = nodes.get(u.id)
		if n == null:
			n = _make_node(u)
			nodes[u.id] = n
		var vis: bool = u.in_hyper <= 0 and seen(u)
		n.visible = vis
		if not vis:
			continue
		var p: Vector2 = u.prev_pos.lerp(u.pos, alpha)
		var h: float = lerp_angle(u.prev_heading, u.heading, alpha)
		n.position = Vector3(p.x * S, u.height * S, p.y * S)
		n.rotation = Vector3(0, -h, 0)
		if u.charge > 0:
			n.position.y += sin(t * 20.0) * 2.0
		var spin = n.find_child("spin", true, false)
		if spin:
			spin.rotate_object_local(Vector3.UP if u.is_station() else Vector3.UP, 0.01)
		if u.is_squad():
			var k: int = u.craft_alive()
			for i in n.get_child_count():
				n.get_child(i).visible = i < k
	for id in nodes.keys():
		if not alive_ids.has(id):
			nodes[id].queue_free()
			nodes.erase(id)
	# Опустевшие поля темнеют.
	for f in world.fields:
		if f.has("node"):
			f.node.visible = f.ore > 0

func _make_node(u: Unit) -> Node3D:
	var col: Color = TEAM_COL[u.team]
	var n: Node3D
	if u.is_squad():
		n = Node3D.new()
		var cnt: int = u.def.squad_n
		for i in cnt:
			var c := ShipMesh.build(u.def, col)
			var row := int((i + 1) / 2)
			var side := 1.0 if i % 2 == 1 else -1.0
			c.position = Vector3(-row * 14.0, (i % 3) * 3.0, side * row * 12.0 if i > 0 else 0.0)
			n.add_child(c)
	else:
		n = ShipMesh.build(u.def, col)
	add_child(n)
	return n

func _draw_shots() -> void:
	shot_mesh.clear_surfaces()
	var now := world.time
	var any := false
	for s in world.shots:
		if now - s.t > 0.25:
			continue
		var a: Vector2 = s.a
		var b: Vector2 = s.b
		if me >= 0 and not (world.teams[me].vis.size() >= 0):
			pass
		if not any:
			shot_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			any = true
		var c := _shot_col(s.cls, s.team)
		c.a = 1.0 - (now - s.t) / 0.25
		var reps := 3 if s.cls == "main" else 1
		for k in reps:
			var o := Vector3(0, k * 2.0, 0)
			shot_mesh.surface_set_color(c)
			shot_mesh.surface_add_vertex(Vector3(a.x * S, s.ah * S, a.y * S) + o)
			shot_mesh.surface_set_color(c)
			shot_mesh.surface_add_vertex(Vector3(b.x * S, s.bh * S, b.y * S) + o)
	if any:
		shot_mesh.surface_end()
	var mm := proj_mm.multimesh
	var i := 0
	for p in world.projectiles:
		if i >= mm.instance_count:
			break
		var pos: Vector2 = p.pos
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (1.4 if p.cls == "torpedo" else 0.9)), Vector3(pos.x * S, p.h * S, pos.y * S)))
		mm.set_instance_color(i, Color(1, 0.9, 0.4) if not p.spoofed else Color(0.6, 0.6, 0.6))
		i += 1
	mm.visible_instance_count = i

func _shot_col(cls: String, team: int) -> Color:
	match cls:
		"flak": return Color(1.0, 0.85, 0.5)
		"gun", "intc": return TEAM_COL[team].lightened(0.3)
		"laser": return Color(0.5, 1.0, 0.6)
		"heavy": return Color(1.0, 0.6, 0.3)
		"main": return Color(1.0, 1.0, 1.0)
	return Color.WHITE

# --------------------------------------------------------------- камера

func _camera(delta: float) -> void:
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_UP): mv.y -= 1
	if Input.is_key_pressed(KEY_DOWN): mv.y += 1
	if Input.is_key_pressed(KEY_LEFT): mv.x -= 1
	if Input.is_key_pressed(KEY_RIGHT): mv.x += 1
	var vp := get_viewport().get_visible_rect().size
	var m := get_viewport().get_mouse_position()
	if DisplayServer.window_is_focused() and drag_start == null and not mmb_drag:
		var e := 6.0
		if m.x <= e: mv.x -= 1
		if m.x >= vp.x - e: mv.x += 1
		if m.y <= e: mv.y -= 1
		if m.y >= vp.y - e: mv.y += 1
	if Input.is_key_pressed(KEY_Q): yaw -= delta * 1.5
	if Input.is_key_pressed(KEY_E): yaw += delta * 1.5
	if mv != Vector2.ZERO:
		var fwd := Vector3(cos(yaw), 0, sin(yaw))
		var right := Vector3(-sin(yaw), 0, cos(yaw))
		var sp := dist * 0.9 * delta
		pivot += (fwd * -mv.y + right * mv.x) * sp
	var h := world.map_w * S * 0.5
	pivot.x = clamp(pivot.x, -h, h)
	pivot.z = clamp(pivot.z, -h, h)
	var off := Vector3(-cos(yaw) * cos(pitch), sin(pitch), -sin(yaw) * cos(pitch)) * dist
	cam.position = pivot + off
	cam.look_at(pivot, Vector3.UP)

func focus(p: Vector2) -> void:
	pivot = Vector3(p.x * S, 0, p.y * S)

func ground_at(screen: Vector2):
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if abs(d.y) < 0.0001:
		return null
	var t := -o.y / d.y
	if t < 0:
		return null
	var p := o + d * t
	return Vector2(p.x / S, p.z / S)

func screen_of(u: Unit):
	var p3 := Vector3(u.pos.x * S, u.height * S, u.pos.y * S)
	if cam.is_position_behind(p3):
		return null
	return cam.unproject_position(p3)

func screen_radius(u: Unit) -> float:
	var p3 := Vector3(u.pos.x * S, u.height * S, u.pos.y * S)
	var d := cam.position.distance_to(p3)
	var vl := ShipMesh.vis_len(u.def) * (2.5 if u.is_squad() else 0.5)
	var px: float = vl / max(d, 1.0) * get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(cam.fov * 0.5)))
	return max(px, 9.0)

func _pick(m: Vector2):
	var best = null
	var bd := INF
	for u in world.units:
		if not u.alive or u.in_hyper > 0 or not seen(u):
			continue
		var sp = screen_of(u)
		if sp == null:
			continue
		var d: float = (sp - m).length()
		var r := screen_radius(u) + 4.0
		if d < r and d < bd:
			bd = d
			best = u
	return best

# ---------------------------------------------------------------- ввод

func _input(ev: InputEvent) -> void:
	# Рамку доводим до конца, даже если кнопку отпустили над панелью интерфейса.
	if drag_start == null:
		return
	if ev is InputEventMouseMotion:
		drag_now = ev.position
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		drag_now = ev.position
		_finish_select(ev.shift_pressed)
		drag_start = null
		get_viewport().set_input_as_handled()

func _unhandled_input(ev: InputEvent) -> void:
	if world.winner >= 0:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(0.85, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0 / 0.85, mb.position)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			mmb_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if attack_move and me >= 0:
					var g = ground_at(mb.position)
					if g != null:
						world.cmd_move(sel, g, true)
						_mark_player(sel)
					attack_move = false
					return
				drag_start = mb.position
				drag_now = mb.position
			elif drag_start != null:
				_finish_select(mb.shift_pressed)
				drag_start = null
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			attack_move = false
			_right_click(mb.position)
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if drag_start != null:
			drag_now = mm.position
		if mmb_drag:
			yaw += mm.relative.x * 0.005
			pitch = clamp(pitch - mm.relative.y * 0.004, deg_to_rad(20), deg_to_rad(85))
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		_key(ev as InputEventKey)

func _zoom(k: float, _m: Vector2) -> void:
	dist = clamp(dist * k, 250.0, world.map_w * S * 1.4)

func _finish_select(add: bool) -> void:
	var r := Rect2(drag_start, drag_now - drag_start).abs()
	var picked := []
	if r.size.length() < 6:
		var u = _pick(drag_start)
		if u != null and (u.team == me or me < 0):
			picked = [u]
		elif u != null:
			picked = [u]   # чужой — только посмотреть
	else:
		for u in world.units:
			if not u.alive or u.in_hyper > 0 or (me >= 0 and u.team != me) or u.is_station():
				continue
			var sp = screen_of(u)
			if sp != null and r.has_point(sp):
				picked.append(u)
		# Харвестеры — только если кроме них ничего нет.
		var combat := picked.filter(func(x): return x.cls != "harvester")
		if not combat.is_empty():
			picked = combat
	if add:
		for u in picked:
			if not sel.has(u):
				sel.append(u)
	else:
		sel = picked

func mine_sel() -> Array:
	return sel.filter(func(u): return me >= 0 and u.team == me)

func _mark_player(list: Array) -> void:
	for u in list:
		u.player_ordered = true

func _right_click(m: Vector2) -> void:
	var my := mine_sel()
	if my.is_empty():
		return
	var u = _pick(m)
	if u != null and u.team != me:
		world.cmd_attack(my, u, hud.hp_choice if hud.hp_target == u else "")
		_mark_player(my)
		hud.flash_target(u)
		return
	var g = ground_at(m)
	if g != null:
		world.cmd_move(my, g, Input.is_key_pressed(KEY_CTRL))
		_mark_player(my)
		hud.flash_point(g)

func _key(k: InputEventKey) -> void:
	var code := k.keycode
	if code == KEY_SPACE:
		paused = not paused
	elif code == KEY_ESCAPE:
		hud.toggle_menu()
	elif code == KEY_F1:
		hud.toggle_help()
	elif code == KEY_EQUAL or code == KEY_KP_ADD:
		speed = min(speed * 2.0, 8.0)
	elif code == KEY_MINUS or code == KEY_KP_SUBTRACT:
		speed = max(speed / 2.0, 0.25)
	elif me < 0:
		return
	elif code == KEY_A:
		attack_move = not mine_sel().is_empty()
	elif code == KEY_S:
		world.cmd_stop(mine_sel())
	elif code == KEY_R:
		world.cmd_retreat(mine_sel())
	elif code == KEY_H:
		var st: Unit = world.teams[me].station
		if st.alive:
			sel = [st]
			focus(st.pos)
	elif code == KEY_Z or code == KEY_X or code == KEY_C:
		var idx: int = {KEY_Z: 0, KEY_X: 1, KEY_C: 2}[code]
		hud.use_ability_slot(idx)
	elif code >= KEY_1 and code <= KEY_9:
		var g := code - KEY_1 + 1
		if k.ctrl_pressed:
			groups[g] = mine_sel()
		elif groups.has(g):
			var list: Array = groups[g].filter(func(u): return u.alive)
			if sel == list and not list.is_empty():
				focus(list[0].pos)
			sel = list
