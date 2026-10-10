## Проба картинки: камера «как Empire at War», небо Sky, планета под столом,
## корабли узлами, авиация MultiMesh, подписи 2D, пояс дальности, GPUParticles,
## свечение. Аргументы после «--»: shot=путь.png frames=N view=start|work|far
## halo=sky|rollback_far|rollback_sphere pos=0..8 yaw=0..2
extends Node3D

const FRIEND := Color(0.45, 0.95, 0.75)
const FOE := Color(1.0, 0.42, 0.35)
const COMP := {"corvette": 7, "frigate": 7, "ecm": 3, "cruiser": 5, "carrier": 4, "capital": 4}

var args := {}
var sim: BattleSim
var cam: Camera3D
var yaw := 0.0
var dist := 2400.0
var look := Vector3.ZERO
const PITCH := deg_to_rad(55.0)
const FOV := 30.0
var env: Environment
var ship_nodes: Array[Node3D] = []
var mm_craft: MultiMesh
var mm_proj: MultiMesh
var labels: Array[Label] = []
var label_layer: CanvasLayer
var belt: MeshInstance3D
var sel_ring: MeshInstance3D
var beams: ImmediateMesh
var beam_list: Array = []
var booms: Array[GPUParticles3D] = []
var boom_i := 0
var planet: MeshInstance3D
var planet_r := 1150.0
var frames := 0
var frame := 0
var sky_mat: ShaderMaterial
var stats := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	frames = int(args.get("frames", "0"))
	var f := FileAccess.open("res://data/space_data.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	if args.has("datacheck") or args.has("bench"):
		# сборка без -s: стенд вызывается аргументом главной сцены
		print("DATA ok=%s factions=%d plektor_ships=%d" % [f != null, data.factions.size(), data.ships.plektor.size()])
		if args.has("bench"):
			var b := BattleSim.new(data, 1)
			b.fast = true
			b.invulnerable = true
			b.add_fleet(0, "plektor", COMP, 10)
			b.add_fleet(1, "troyden", COMP, 10)
			var t0 := Time.get_ticks_usec()
			var n := int(args.get("steps", "900"))
			for i in n:
				b.step()
			var line := "BENCH release steps=%d mean_ms=%.3f os=%s" % [n, (Time.get_ticks_usec() - t0) / 1000.0 / n, OS.get_name()]
			print(line)
			if args.has("out"):
				var fo := FileAccess.open(args.out, FileAccess.WRITE)
				fo.store_line(line)
				fo.close()
			if not args.has("nodispose"):
				b.dispose()
		get_tree().quit()
		return
	sim = BattleSim.new(data, int(args.get("seed", "3")))
	sim.fast = true
	sim.fx_on = true
	sim.add_fleet(0, "troyden", COMP, 10)
	sim.add_fleet(1, "plektor", COMP, 10)
	sim.destroyed.connect(_on_destroyed)
	_build_env()
	_build_planet()
	_build_ships()
	_build_air()
	_build_rings()
	_build_fx()
	_build_labels()
	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 5.0
	cam.far = {"rollback_far": 4000.0, "rollback_sphere": 8000.0}.get(args.get("halo", ""), 20000.0)
	add_child(cam)
	match args.get("view", "work"):
		"start":
			dist = 3990.0; look = Vector3(0, 0, 470)
		"far":
			dist = 5000.0
			var P := [Vector3.ZERO, Vector3(0, 0, 2600), Vector3(2600, 0, 2600)]
			look = P[int(args.get("pos", "0")) % 3]
			yaw = [0.0, PI / 2.0, PI][int(args.get("yaw", "0")) % 3]
		_:
			dist = 2400.0; look = Vector3(0, 0, 155)
	_place_camera()
	# прогон боя до нужного момента без отрисовки — тот же шаг
	var pre := int(args.get("presteps", "0"))
	for i in pre:
		sim.step()
	sim.fx_shots.clear()

func _build_env() -> void:
	env = Environment.new()
	var halo: String = args.get("halo", "")
	if halo == "rollback_sphere":
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(1, 0, 1)
	else:
		env.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		sky_mat = ShaderMaterial.new()
		sky_mat.shader = load("res://render/nebula_sky.gdshader")
		sky_mat.set_shader_parameter("check_magenta", halo != "")
		sky.sky_material = sky_mat
		env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.85
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.5)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(30), 0)
	sun.light_energy = 1.3
	add_child(sun)
	if halo == "rollback_sphere":
		# старая ловушка: туманность-сфера вокруг центра поля
		var neb := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 6000.0; sm.height = 12000.0
		neb.mesh = sm
		var nm := StandardMaterial3D.new()
		nm.albedo_color = Color(0.05, 0.07, 0.15)
		nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		nm.cull_mode = BaseMaterial3D.CULL_FRONT
		neb.material_override = nm
		add_child(neb)

func _build_planet() -> void:
	planet = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = planet_r; sm.height = planet_r * 2.0
	sm.radial_segments = 96; sm.rings = 48
	planet.mesh = sm
	var pm := ShaderMaterial.new()
	pm.shader = load("res://render/planet.gdshader")
	planet.material_override = pm
	planet.position = Vector3(float(args.get("px", "2300")), float(args.get("py", "-3600")), float(args.get("pz", "-900")))
	add_child(planet)
	var atm := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = planet_r * 1.06; am.height = planet_r * 2.12
	am.radial_segments = 96; am.rings = 48
	atm.mesh = am
	var amat := ShaderMaterial.new()
	amat.shader = load("res://render/atmo.gdshader")
	atm.material_override = amat
	planet.add_child(atm)

func _side_mat(side: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.66, 0.72) if side == 0 else Color(0.66, 0.6, 0.58)
	m.metallic = 0.4
	m.roughness = 0.55
	return m

func _build_ships() -> void:
	var mats := [_side_mat(0), _side_mat(1)]
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.5, 0.8, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.5, 0.8, 1.0)
	glow.emission_energy_multiplier = 4.0
	var gm := SphereMesh.new(); gm.radius = 1.0; gm.height = 2.0; gm.radial_segments = 8; gm.rings = 4
	for s in sim.ships:
		var n := Node3D.new()
		n.name = "%s_%d" % [s.kind, s.id]
		var body := MeshInstance3D.new()
		var pm := PrismMesh.new()
		var L := s.hull * 2.0
		pm.size = Vector3(L * 0.45, L * 0.18, L)
		body.mesh = pm
		pass
		body.material_override = mats[s.side]
		n.add_child(body)
		var eng := MeshInstance3D.new()
		eng.mesh = gm
		eng.scale = Vector3.ONE * s.hull * 0.12
		eng.position = Vector3(0, 0, L * 0.5)
		eng.material_override = glow
		n.add_child(eng)
		add_child(n)
		ship_nodes.append(n)

func _build_air() -> void:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(5, 2, 9)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	mm_craft = MultiMesh.new()
	mm_craft.transform_format = MultiMesh.TRANSFORM_3D
	mm_craft.use_colors = true
	mm_craft.mesh = mesh
	mm_craft.instance_count = sim.craft.size()
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm_craft
	add_child(mi)
	var pmesh := SphereMesh.new(); pmesh.radius = 2.0; pmesh.height = 4.0; pmesh.radial_segments = 6; pmesh.rings = 3
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(1.0, 0.8, 0.4)
	pmat.emission_enabled = true
	pmat.emission = Color(1.0, 0.7, 0.3)
	pmat.emission_energy_multiplier = 3.0
	pmesh.material = pmat
	mm_proj = MultiMesh.new()
	mm_proj.transform_format = MultiMesh.TRANSFORM_3D
	mm_proj.mesh = pmesh
	mm_proj.instance_count = 256
	mm_proj.visible_instance_count = 0
	var pi := MultiMeshInstance3D.new()
	pi.multimesh = mm_proj
	add_child(pi)

func _annulus(r0: float, r1: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p00 := Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p01 := Vector3(cos(a0) * r1, 0, sin(a0) * r1)
		var p10 := Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var p11 := Vector3(cos(a1) * r1, 0, sin(a1) * r1)
		for v in [p00, p01, p11, p00, p11, p10]:
			st.add_vertex(v)
	return st.commit()

func _build_rings() -> void:
	# пояс главного калибра выделенного тяжёлого [0,4R; R]
	var s0: BattleSim.Ship = null
	for s in sim.ships:
		if s.side == 0 and s.kind == "cruiser":
			s0 = s
			break
	var R := s0.mains[0].rng
	belt = MeshInstance3D.new()
	belt.mesh = _annulus(0.4 * R, R, 128)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(FRIEND.r, FRIEND.g, FRIEND.b, 0.07)
	bm.no_depth_test = false
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	belt.material_override = bm
	add_child(belt)
	sel_ring = MeshInstance3D.new()
	sel_ring.mesh = _annulus(0.995 * R, R, 128)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = FRIEND
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sel_ring.material_override = rm
	add_child(sel_ring)
	belt.set_meta("ship", s0.id)
	beams = ImmediateMesh.new()
	var bmi := MeshInstance3D.new()
	bmi.mesh = beams
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	bmi.material_override = lm
	add_child(bmi)

func _build_fx() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 6.0
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 20.0
	pm.initial_velocity_max = 60.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 6.0
	pm.scale_max = 14.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
	grad.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
	var gt := GradientTexture1D.new(); gt.gradient = grad
	pm.color_ramp = gt
	var q := QuadMesh.new()
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = qm
	for i in 16:
		var p := GPUParticles3D.new()
		p.amount = 48
		p.lifetime = 1.2
		p.one_shot = true
		p.explosiveness = 0.9
		p.emitting = false
		p.process_material = pm
		p.draw_pass_1 = q
		p.visibility_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
		add_child(p)
		booms.append(p)

func _on_destroyed(t, _by: int) -> void:
	var p := booms[boom_i % booms.size()]
	boom_i += 1
	p.position = t.pos
	p.restart()

func _build_labels() -> void:
	label_layer = CanvasLayer.new()
	label_layer.layer = 1    # нижний слой интерфейса (C78)
	add_child(label_layer)
	for s in sim.ships:
		var l := Label.new()
		l.text = s.kind
		l.add_theme_color_override("font_color", FRIEND if s.side == 0 else FOE)
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_font_size_override("font_size", 14)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label_layer.add_child(l)
		labels.append(l)

func _place_camera() -> void:
	var back := Vector3(sin(yaw), 0, cos(yaw))
	cam.position = look + back * dist * cos(PITCH) + Vector3.UP * dist * sin(PITCH)
	cam.look_at(look, Vector3.UP)

func _physics_process(_d: float) -> void:
	if args.has("still") or sim == null:
		return
	sim.step()

func _process(dt: float) -> void:
	if sim == null:
		return
	var t0 := Time.get_ticks_usec()
	for i in sim.ships.size():
		var s := sim.ships[i]
		var n := ship_nodes[i]
		n.visible = s.alive
		n.position = s.pos + Vector3(0, (s.id % 7 - 3) * 12.0, 0)
		n.rotation.y = s.yaw
	var k := 0
	for c in sim.craft:
		if not c.alive:
			continue
		var tr := Transform3D(Basis(Vector3.UP, c.yaw), c.pos + Vector3(0, 20, 0))
		mm_craft.set_instance_transform(k, tr)
		mm_craft.set_instance_color(k, FRIEND if c.side == 0 else FOE)
		k += 1
	mm_craft.visible_instance_count = k
	k = 0
	for p in sim.proj:
		if p.alive and k < 256:
			mm_proj.set_instance_transform(k, Transform3D(Basis.IDENTITY, p.pos + Vector3(0, 15, 0)))
			k += 1
	mm_proj.visible_instance_count = k
	var sid: int = belt.get_meta("ship")
	var s0 := sim.ships[sid]
	belt.position = s0.pos
	sel_ring.position = s0.pos
	# лучи: живут 0,2 с
	for sh in sim.fx_shots:
		beam_list.append([sh[0], sh[1], sh[2], 0.2])
	sim.fx_shots.clear()
	beams.clear_surfaces()
	if beam_list.size() > 0:
		beams.surface_begin(Mesh.PRIMITIVE_LINES)
		var keep: Array = []
		for b in beam_list:
			b[3] -= dt
			if b[3] > 0.0:
				var col := Color(2.0, 1.6, 0.8) if b[2] == BattleSim.K_HEAVY else Color(0.8, 1.6, 2.0)
				beams.surface_set_color(col)
				beams.surface_add_vertex(b[0] + Vector3(0, 10, 0))
				beams.surface_set_color(col)
				beams.surface_add_vertex(b[1] + Vector3(0, 10, 0))
				keep.append(b)
		beam_list = keep
		if keep.is_empty():
			beams.surface_add_vertex(Vector3.ZERO); beams.surface_add_vertex(Vector3.ZERO)
		beams.surface_end()
	# подписи: проекция, «за камерой» — прячем
	for i in sim.ships.size():
		var s := sim.ships[i]
		var l := labels[i]
		var wp := s.pos + Vector3(0, s.hull * 1.2, 0)
		if not s.alive or cam.is_position_behind(wp):
			l.visible = false
			continue
		var sp := cam.unproject_position(wp)
		l.visible = true
		l.position = sp - Vector2(l.size.x * 0.5, 22)
	stats["view_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	frame += 1
	if frames > 0 and frame == frames:
		_finish()

func _finish() -> void:
	var img := get_viewport().get_texture().get_image()
	var out: String = args.get("shot", "")
	var info := {"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(),
		"size": [img.get_width(), img.get_height()], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"view_ms": stats.get("view_ms", 0.0), "proc_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0}
	if args.has("halo"):
		info["halo"] = _halo_check(img)
	if out != "":
		img.save_png(out)
	print("SHOT ", JSON.stringify(info))
	get_tree().quit()

func _is_magenta(c: Color) -> bool:
	return c.r > 0.8 and c.b > 0.8 and c.g < 0.25

func _halo_check(img: Image) -> Dictionary:
	# весь кадр: сколько пурпурных точек; диск планеты: проекция центра и края
	var w := img.get_width()
	var h := img.get_height()
	var total := 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			if _is_magenta(img.get_pixel(x, y)):
				total += 1
	var c := planet.global_position
	var res := {"magenta_frame_samples": total, "frame_samples": (w / 4) * (h / 4)}
	# точный диск: луч камеры через точку экрана пересекает шар планеты (радиус ×0,98 — запас на край)
	var rr := planet_r * 0.98
	var inside := 0
	var mag := 0
	var B := cam.global_transform.basis
	var o := cam.global_position
	var oc := o - c
	var ty := tan(deg_to_rad(cam.fov) * 0.5)
	var tx := ty * float(w) / float(h)
	for y in range(0, h, 4):
		var ny := 1.0 - 2.0 * (y + 0.5) / h
		for x in range(0, w, 4):
			var nx := 2.0 * (x + 0.5) / w - 1.0
			var dir := (-B.z + B.x * (nx * tx) + B.y * (ny * ty)).normalized()
			var bq := oc.dot(dir)
			var cq := oc.dot(oc) - rr * rr
			if bq > 0.0 or bq * bq - cq < 0.0:
				continue
			inside += 1
			if _is_magenta(img.get_pixel(x, y)):
				mag += 1
	res["disk_samples_on_screen"] = inside
	res["magenta_in_disk"] = mag
	res["planet_dist"] = int(cam.global_position.distance_to(c))
	res["cam_far"] = cam.far
	return res

