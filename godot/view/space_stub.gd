# view/space_stub.gd — окно-заглушка G0a: космос, планета у края, камера «стол».
# Камера — числа доктрины (09, 11): обзор 30°, наклон 55°, старт ~3990, дальняя
# плоскость 20 000. Это не «Стол» G0b — только чтобы было что собрать и запустить.
extends Node3D

const Defs := preload("res://sim/defs.gd")
const SKY_SHADER := preload("res://view/shaders/stars_sky.gdshader")

var camera: Camera3D
var _yaw := 0.0
var _tilt := 55.0
var _dist := 3990.0


func setup(doctrine: Defs.Doctrine) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30.0, 115.0, 0.0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.92, 0.82)
	add_child(sun)

	# планета глубоко под столом и в стороне от оси сторон (09, 11.7)
	var planet := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2600.0
	sphere.height = 5200.0
	sphere.radial_segments = 96
	sphere.rings = 48
	planet.mesh = sphere
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.16, 0.30, 0.46)
	pm.roughness = 0.9
	planet.material_override = pm
	planet.position = Vector3(-5200.0, -6200.0, -2600.0)
	add_child(planet)

	camera = Camera3D.new()
	camera.fov = doctrine.camera_fov_deg
	camera.near = doctrine.camera_near
	camera.far = doctrine.camera_far
	add_child(camera)
	_tilt = doctrine.camera_tilt_deg
	_dist = doctrine.camera_dist_start
	_place()


func _place() -> void:
	var tilt := deg_to_rad(_tilt)
	var dist := _dist
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	camera.position = Vector3(0.0, sin(tilt) * dist, 0.0) + back * cos(tilt) * dist
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _process(delta: float) -> void:
	# медленный облёт — чтобы было видно, что окно живое
	_yaw += delta * 0.02
	if camera != null:
		_place()
