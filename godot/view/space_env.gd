# view/space_env.gd — окружение боя: небо, свет, планета с венцом (архитектура,
# 5.6–5.7; 09, 11.7).
# - Небо — Sky со своим шейдером: рисуется без глубины, от дальней плоскости не
#   зависит; оно же — карта окружения для металла кораблей.
# - Свечение и тонмаппер ACES; порог свечения около 0,85.
# - Планета глубоко под столом и в стороне от оси сторон: со старта она в углу
#   кадра, а не под линиями; с поворотом камеры уходит и приходит.
#   Дальняя плоскость камеры 20 000 (doctrine camera.far) с запасом накрывает её
#   и с дальнего предела 5000 из любой точки поля: самое дальнее — около 15 600.
#   С прежней 4000 планета срезалась бы целиком — так и проверяет тест ореола.
extends Node3D

const SKY_SHADER := preload("res://view/shaders/stars_sky.gdshader")
const PLANET_SHADER := preload("res://view/shaders/planet.gdshader")
const CORONA_SHADER := preload("res://view/shaders/corona.gdshader")

## Место и размер планеты: снимком подобрано (часть 08, 7.2 п. 2) — со стартового
## вида атакующего она в правом верхнем углу кадра, около 4,6° радиусом.
const PLANET_CENTER := Vector3(3000.0, -4900.0, -5500.0)
const PLANET_RADIUS := 760.0
const CORONA_K := 1.07

var env: Environment
var sky_mat: ShaderMaterial
var planet: MeshInstance3D
var corona: MeshInstance3D
var sun: DirectionalLight3D


func _ready() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.42, 0.62)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.85
	env.glow_intensity = 0.7
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# тёплый ключ сбоку и сверху, холодный встречный снизу (часть 08, ловушка 22)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.88, 0.72)
	sun.light_energy = 1.7
	sun.rotation_degrees = Vector3(-38.0, -125.0, 0.0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.45, 0.42, 0.8)
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(25.0, 50.0, 0.0)
	add_child(fill)

	planet = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = PLANET_RADIUS
	sm.height = PLANET_RADIUS * 2.0
	sm.radial_segments = 96
	sm.rings = 48
	planet.mesh = sm
	var pm := ShaderMaterial.new()
	pm.shader = PLANET_SHADER
	planet.material_override = pm
	planet.position = PLANET_CENTER
	planet.rotation_degrees = Vector3(12.0, 30.0, -8.0)
	add_child(planet)

	corona = MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = PLANET_RADIUS * CORONA_K
	cm.height = PLANET_RADIUS * CORONA_K * 2.0
	cm.radial_segments = 96
	cm.rings = 48
	corona.mesh = cm
	var cmat := ShaderMaterial.new()
	cmat.shader = CORONA_SHADER
	corona.material_override = cmat
	corona.position = PLANET_CENTER
	add_child(corona)
	get_viewport().size_changed.connect(_fit_stars)
	_fit_stars()


## Звезда — точка в пикселях: угол одного пикселя по вертикали окна.
func _fit_stars() -> void:
	var h := get_viewport().get_visible_rect().size.y
	var fov := 30.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		fov = cam.fov
	sky_mat.set_shader_parameter("px_angle", deg_to_rad(fov) / maxf(h, 1.0))


## Проверочная сборка (тест ореола): небо одного пурпурного цвета.
func set_test_magenta(on: bool) -> void:
	sky_mat.set_shader_parameter("test_magenta", on)
