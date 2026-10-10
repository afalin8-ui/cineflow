extends Node3D
## Проба сцены боя: небо Sky (панорама), планета под «столом», 69 кораблей
## (узлами из .glb), 200 машин авиации одним MultiMesh, кольца одним
## ImmediateMesh, подписи — пул Control, частицы, свечение. Камера —
## доктрина 11: обзор 30°, наклон 55°, расстояние 500…5000.
## Режимы (аргументы после --): shots=1 — девять снимков при отдалении,
## проверка ореола и целости диска планеты; far=4000 — откат.

var cam: Camera3D
var env: Environment
var we: WorldEnvironment
var planet: MeshInstance3D
var planet_c := Vector3(1900, -6200, -2600)
var planet_r := 3200.0
var ships: Array[Node3D] = []
var labels: Array[Label] = []
var label_layer: CanvasLayer
var rings: ImmediateMesh
var craft_mm: MultiMesh
var magenta_sky := false
var far_override := 0.0
var out_dir := "res://../out/shots"
var target := Vector3.ZERO
var dist := 2400.0
var yaw := 0.0
const TILT := deg_to_rad(55.0)

func arg(n: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(n + "="): return a.split("=")[1]
	return d

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	magenta_sky = arg("magenta", "0") == "1"
	far_override = float(arg("far", "0"))
	out_dir = arg("out", ProjectSettings.globalize_path("res://").path_join("../out/shots"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	build_env(); build_planet(); build_ships(); build_craft(); build_rings(); build_labels(); build_fx()
	cam = Camera3D.new(); cam.fov = 30.0; cam.near = 5.0; cam.far = far_override if far_override > 0 else 20000.0
	add_child(cam); cam.current = true
	place_cam()
	await run()

func build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	if magenta_sky:
		var sm := ShaderMaterial.new(); var sh := Shader.new()
		sh.code = "shader_type sky;\nvoid sky() { COLOR = vec3(1.0, 0.0, 1.0); }\n"
		sm.shader = sh; sky.sky_material = sm
	else:
		var pm := PanoramaSkyMaterial.new(); pm.panorama = make_nebula(); sky.sky_material = pm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.85
	env.glow_intensity = 0.8
	env.background_color = Color(1, 0, 1)   # пурпур очистки: дыра в небе видна сразу
	we = WorldEnvironment.new(); we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(40), 0); sun.light_energy = 1.2
	add_child(sun)

## Туманность «печётся» шумом с зерном — то же правило, что у Клото (08, 5.1)
func make_nebula() -> Texture2D:
	var nz := FastNoiseLite.new(); nz.seed = 11; nz.frequency = 0.004; nz.fractal_octaves = 5
	var w := 1024; var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	for y in h:
		for x in w:
			var v := (nz.get_noise_2d(x, y) + 1.0) * 0.5
			var band := exp(-pow((y - h * 0.5) / (h * 0.18), 2.0))
			var c := Color(0.02, 0.02, 0.05).lerp(Color(0.25, 0.12, 0.35), pow(v, 3.0) * (0.4 + band))
			img.set_pixel(x, y, c)
	for i in 3000:
		var b := rng.randf_range(0.5, 1.0)
		img.set_pixel(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1), Color(b, b, b))
	return ImageTexture.create_from_image(img)

func build_planet() -> void:
	planet = MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = planet_r; sm.height = planet_r * 2; sm.radial_segments = 96; sm.rings = 48
	planet.mesh = sm
	var mat := StandardMaterial3D.new()
	var nt := NoiseTexture2D.new(); nt.width = 1024; nt.height = 512; nt.seamless = true
	var fn := FastNoiseLite.new(); fn.seed = 1; nt.noise = fn
	var gr := Gradient.new(); gr.set_color(0, Color(0.15, 0.22, 0.35)); gr.set_color(1, Color(0.55, 0.5, 0.4)); nt.color_ramp = gr
	mat.albedo_texture = nt
	planet.material_override = mat
	planet.position = planet_c
	add_child(planet)
	var atm := MeshInstance3D.new(); var sm2 := SphereMesh.new(); sm2.radius = planet_r * 1.035; sm2.height = planet_r * 2.07
	atm.mesh = sm2
	var am := ShaderMaterial.new(); var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_front;
void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	ALBEDO = vec3(0.35, 0.6, 1.0) * rim * 1.6;
}"""
	am.shader = sh; atm.material_override = am; atm.position = planet_c
	add_child(atm)

func build_ships() -> void:
	var cap: PackedScene = load("res://assets/troyden_capital_godot.glb")
	var cor: PackedScene = load("res://assets/troyden_corvette_plain.glb")
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	for side in [1, -1]:
		for i in 34 + (1 if side < 0 else 0):
			var big := i < 6
			var n: Node3D = (cap if big else cor).instantiate()
			var z: float = side * (650.0 if big else 418.0 if i < 20 else 530.0)
			var x: float = ((i if big else i - 6) - (3 if big else 14)) * (180.0 if big else 60.0)
			n.position = Vector3(x, rng.randf_range(-40, 40), z + rng.randf_range(-15, 15))
			n.rotation.y = 0.0 if side > 0 else PI
			if not big: n.scale = Vector3.ONE * (42.0 / 12.0)  # корвет из .glb мелкий: по длине процедурного (C88)
			add_child(n); ships.append(n)

func build_craft() -> void:
	var mmi := MultiMeshInstance3D.new()
	craft_mm = MultiMesh.new(); craft_mm.transform_format = MultiMesh.TRANSFORM_3D; craft_mm.use_colors = true
	var pm := PrismMesh.new(); pm.size = Vector3(6, 2, 12)
	craft_mm.mesh = pm; craft_mm.instance_count = 200
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	for i in 200:
		var t := Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)), Vector3(rng.randf_range(-700, 700), rng.randf_range(-40, 40), rng.randf_range(-300, 300)))
		craft_mm.set_instance_transform(i, t)
		craft_mm.set_instance_color(i, Color(0.55, 0.85, 1.0) if i % 2 else Color(1.0, 0.7, 0.45))
	var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true; mat.emission_enabled = true; mat.emission = Color(0.4, 0.4, 0.4)
	mmi.multimesh = craft_mm; mmi.material_override = mat
	add_child(mmi)

func build_rings() -> void:
	var mi := MeshInstance3D.new(); rings = ImmediateMesh.new(); mi.mesh = rings
	var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true; mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat; add_child(mi)
	rings.clear_surfaces()
	for s in ships.slice(0, 6):   # пояс крейсера: кольца 0,4 R и R у выделенного
		for r in [312.0, 780.0]:
			rings.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			rings.surface_set_color(Color(0.5, 1.0, 0.8, 0.6))
			for k in 97:
				var a := TAU * k / 96.0
				rings.surface_add_vertex(s.position + Vector3(cos(a) * r, 0, sin(a) * r))
			rings.surface_end()

func build_labels() -> void:
	label_layer = CanvasLayer.new(); add_child(label_layer)
	for s in ships:
		var l := Label.new(); l.text = "«Рэш» II"; l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		label_layer.add_child(l); labels.append(l)

func build_fx() -> void:
	for i in 6:
		var p := GPUParticles3D.new(); p.amount = 64; p.lifetime = 1.2; p.explosiveness = 0.9
		if arg("fixseed", "0") == "1": p.use_fixed_seed = true; p.seed = 1000 + i
		var pm := ParticleProcessMaterial.new(); pm.direction = Vector3.UP; pm.spread = 180; pm.initial_velocity_min = 20; pm.initial_velocity_max = 60
		pm.gravity = Vector3.ZERO; pm.color = Color(1.0, 0.6, 0.25)
		p.process_material = pm
		var q := QuadMesh.new(); q.size = Vector2(8, 8)
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; m.albedo_texture = load("res://assets/glow_tex.png"); m.albedo_color = Color(3, 1.6, 0.6)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		q.material = m; p.draw_pass_1 = q
		p.position = Vector3((i - 2.5) * 200, 0, 0)
		add_child(p)

func place_cam() -> void:
	var back := Vector3(sin(yaw), 0, cos(yaw))
	cam.position = target + back * (dist * cos(TILT)) + Vector3.UP * (dist * sin(TILT))
	cam.look_at(target, Vector3.UP)

func _process(_d: float) -> void:
	for i in ships.size():
		var p := ships[i].position + Vector3.UP * 30.0
		var l := labels[i]
		l.visible = not cam.is_position_behind(p)
		if l.visible: l.position = cam.unproject_position(p) - Vector2(30, 24)

func snap(name: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	return img

func planet_disk() -> Array:
	if cam.is_position_behind(planet_c): return [Vector2.ZERO, 0.0]
	var c := cam.unproject_position(planet_c)
	var d := cam.global_position.distance_to(planet_c)
	var ang := asin(clampf(planet_r / d, 0, 1))
	var px := tan(ang) / tan(deg_to_rad(cam.fov / 2.0)) * (get_viewport().get_visible_rect().size.y / 2.0)
	return [c, px]

func count_magenta(img: Image, disk: Array) -> Array:
	var all := 0; var inside := 0; var in_n := 0
	var c: Vector2 = disk[0]; var r: float = disk[1] * 0.9
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var p := img.get_pixel(x, y)
			var mag := p.r > 0.8 and p.b > 0.8 and p.g < 0.25
			if mag: all += 1
			if r > 0 and Vector2(x, y).distance_to(c) < r:
				in_n += 1
				if mag: inside += 1
	return [all, inside, in_n]

func run() -> void:
	for i in 10: await get_tree().process_frame
	var info := func() -> String:
		return "вызовов отрисовки %d, примитивов %d, сборок конвейеров (draw/spec) %d/%d" % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION)]
	print("рендер: ", RenderingServer.get_current_rendering_method(), " / ", RenderingServer.get_current_rendering_driver_name(), " / ", RenderingServer.get_video_adapter_name())
	dist = 2400; place_cam()
	await snap("work_view")
	print("рабочий вид (2400): ", info.call())
	dist = 3990; target = Vector3(0, 0, 470); place_cam(); await snap("start_view")
	print("стартовый вид (3990): ", info.call())
	if arg("shots", "0") != "1": get_tree().quit(); return
	# на время сравнения кадров частицы замирают: иначе «разница» — их ход, а не небо
	for p: GPUParticles3D in find_children("*", "GPUParticles3D", true, false): p.speed_scale = 0.0
	# 09, 11.7: дальний предел 5000, центр / край / угол, поворот 0, π/2, π
	var bad_all := 0; var bad_in := 0; var disks := 0; var halo_max := 0
	for pos in [Vector3.ZERO, Vector3(0, 0, 2600), Vector3(2600, 0, 2600)]:
		for yw in [0.0, PI / 2, PI]:
			target = pos; yaw = yw; dist = 5000; place_cam()
			var nm := "far_%d_%d_%d" % [int(pos.x), int(pos.z), int(round(yw * 100))]
			var img := await snap(nm)
			var disk := planet_disk()
			var m := count_magenta(img, disk)
			bad_all += m[0]; bad_in += m[1]
			if m[2] > 0: disks += 1
			# ореол способом 08, 4.2 п.6: тот же вид с дальней плоскостью ×2
			if not magenta_sky:
				var f0 := cam.far; cam.far = f0 * 2.0
				var img2 := await snap(nm + "_far2")
				cam.far = f0
				var diff := 0
				for y in range(0, img.get_height(), 3):
					for x in range(0, img.get_width(), 3):
						var a := img.get_pixel(x, y); var b := img2.get_pixel(x, y)
						if (b.r + b.g + b.b) - (a.r + a.g + a.b) > 6.0 / 255.0 * 3.0: diff += 1
				halo_max = maxi(halo_max, diff)
			print("  %s: пурпур всего %d, в диске планеты %d из %d точек" % [nm, m[0], m[1], m[2]])
	print("ИТОГ снимков: пурпур всего %d, в дисках %d (дисков в кадре %d), точек «ореола» (светлее при far×2) — не больше %d" % [bad_all, bad_in, disks, halo_max])
	get_tree().quit()
