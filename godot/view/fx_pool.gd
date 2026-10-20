# view/fx_pool.gd — лучи и вспышки из пула MultiMesh (архитектура, 5.3).
# Два вызова отрисовки на весь пул. Новое событие пишет ОДИН экземпляр: кольцо
# отдаёт самый старый слот (часть 08, ловушка 5, C44), и слот заполняется
# ЦЕЛИКОМ — место, ось, цвет и (рождение, срок, толщина, яркость) — чтобы
# от прежнего жильца ничего не осталось (08, ловушки 19–20).
# Рост и угасание считает вершинный шейдер от `now`: процессор каждый кадр
# пишет одно число на материал. Время — часы того, кто зовёт (бой — часы модели,
# «Стол» — свои часы), а не часы кадра (08, ловушки 16–17).
# Не на emit_particle: в Compatibility его нет вовсе (архитектура, 5.1).
extends Node3D

const BEAM_SHADER := preload("res://view/shaders/beam.gdshader")
const FLASH_SHADER := preload("res://view/shaders/flash.gdshader")
const TRACER_SHADER := preload("res://view/shaders/tracer.gdshader")
const PARTICLE_SHADER := preload("res://view/shaders/particle.gdshader")
const SMOKE_SHADER := preload("res://view/shaders/smoke.gdshader")
## Вид частицы огня (particle.gdshader, basis.y.z) и дыма (smoke.gdshader).
const FIRE := 0
const SPARK := 1
const RING := 2
const GLOW := 3
const PUFF := 0
const DEBRIS := 1

var beams: MultiMeshInstance3D
var flashes: MultiMeshInstance3D
## Летящие отрезки (с G2): трассы ПВО и очереди батареи (08, ловушка 18). 0 слотов —
## пула нет («Стол» обходится лучами и вспышками).
var tracers: MultiMeshInstance3D
## Огонь, искры и кольца (сложение) и дым с обломками (смешивание) — пакет GЭ. 0 слотов — пула нет.
var parts: MultiMeshInstance3D
var smokes: MultiMeshInstance3D
var beam_mat: ShaderMaterial
var flash_mat: ShaderMaterial
var tracer_mat: ShaderMaterial
var part_mat: ShaderMaterial
var smoke_mat: ShaderMaterial
var now := 0.0
var _beam_next := 0
var _flash_next := 0
var _tracer_next := 0
var _part_next := 0
var _smoke_next := 0
var parts_written := 0
var smokes_written := 0
var beams_written := 0
var flashes_written := 0
var tracers_written := 0


func setup(beam_slots: int, flash_slots: int, tracer_slots: int = 0, part_slots: int = 0, smoke_slots: int = 0) -> void:
	beam_mat = ShaderMaterial.new()
	beam_mat.shader = BEAM_SHADER
	flash_mat = ShaderMaterial.new()
	flash_mat.shader = FLASH_SHADER
	beams = _pool(_quad(0.0, 1.0), beam_slots, beam_mat, "beams")
	flashes = _pool(_quad(-0.5, 0.5), flash_slots, flash_mat, "flashes")
	if tracer_slots > 0:
		tracer_mat = ShaderMaterial.new()
		tracer_mat.shader = TRACER_SHADER
		tracers = _pool(_quad(0.0, 1.0), tracer_slots, tracer_mat, "tracers")
	# пулы огня и дыма заводятся СРАЗУ, со всеми слотами мёртвыми: их конвейеры собираются
	# в первых кадрах, а не на первом взрыве (07, ловушка 29; 08, ловушка 15)
	add_pools(part_slots, smoke_slots)


## Пулы огня и дыма (пакет GЭ). Позже первого кадра их заводит только откат прогрева.
func add_pools(part_slots: int, smoke_slots: int) -> void:
	if part_slots > 0 and parts == null:
		part_mat = ShaderMaterial.new()
		part_mat.shader = PARTICLE_SHADER
		parts = _pool(_quad(-0.5, 0.5), part_slots, part_mat, "parts")
		part_mat.set_shader_parameter("now", now)
	if smoke_slots > 0 and smokes == null:
		smoke_mat = ShaderMaterial.new()
		smoke_mat.shader = SMOKE_SHADER
		smokes = _pool(_quad(-0.5, 0.5), smoke_slots, smoke_mat, "smokes")
		smoke_mat.set_shader_parameter("now", now)


## Квад: x от x0 до x1 (вдоль луча или вширь вспышки), y — от −0,5 до 0,5.
static func _quad(x0: float, x1: float) -> ArrayMesh:
	var v := PackedVector3Array([Vector3(x0, -0.5, 0), Vector3(x1, -0.5, 0), Vector3(x1, 0.5, 0), Vector3(x0, 0.5, 0)])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _pool(mesh: ArrayMesh, slots: int, mat: ShaderMaterial, nm: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = slots
	# все слоты — мёртвые (рождение далеко в будущем): шейдер складывает их за камеру
	for i in slots:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3.ZERO))
		mm.set_instance_custom_data(i, Color(1e9, 1.0, 0.0, 0.0))
	# экземпляры разлетаются по всему полю: рамку — на всё поле, иначе пул отсечётся целиком
	mm.custom_aabb = AABB(Vector3(-6000, -3000, -6000), Vector3(12000, 6000, 12000))
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Луч или трасса от a до b: толщина в мире (не меньше min_px точек экрана), цвет,
## срок жизни, яркость (больше 1 — светится). px — свой нижний предел в точках экрана
## (0 — общий у материала): главный калибр толще лёгкого и там, где оба упёрлись в предел.
## delay — родиться позже (послесвечение канала главного калибра через 0,06 с, 08, 2.13).
func beam(a: Vector3, b: Vector3, color: Color, width: float, life: float, power: float = 1.0, px: float = 0.0, delay: float = 0.0) -> void:
	var mm := beams.multimesh
	var i := _beam_next
	_beam_next = (_beam_next + 1) % mm.instance_count
	mm.set_instance_transform(i, Transform3D(Basis(b - a, Vector3(px, 1.0, 0.0), Vector3(color.r, color.g, color.b)), a))
	mm.set_instance_custom_data(i, Color(now + delay, life, width, power))
	beams_written += 1


## Вспышка: размер в мире (не меньше min_px точек; px — свой предел, 0 — общий).
## core — сила белой середины (1 — как было; 0 — без неё: огонь взрыва и попаданий БЕЛЫМ быть не
## должен, белым — только маленькое короткое ядро, 08, ловушка 6). delay — родиться позже.
func flash(p: Vector3, color: Color, size: float, life: float, power: float = 1.0, px: float = 0.0, core: float = 1.0, delay: float = 0.0) -> void:
	var mm := flashes.multimesh
	var i := _flash_next
	_flash_next = (_flash_next + 1) % mm.instance_count
	mm.set_instance_transform(i, Transform3D(Basis(Vector3.RIGHT, Vector3(px, core, 0.0), Vector3(color.r, color.g, color.b)), p))
	mm.set_instance_custom_data(i, Color(now + delay, life, size, power))
	flashes_written += 1


## Частица огня (вид FIRE, SPARK, RING, GLOW): летит со скоростью vel, гаснет с сопротивлением drag.
func particle(p: Vector3, vel: Vector3, color: Color, size0: float, size1: float, life: float, kind: int, drag: float = 0.0, power: float = 1.0, delay: float = 0.0) -> void:
	if parts == null:
		return
	var mm := parts.multimesh
	var i := _part_next
	_part_next = (_part_next + 1) % mm.instance_count
	mm.set_instance_transform(i, Transform3D(Basis(vel, Vector3(size0, size1, float(kind)), Vector3(color.r, color.g, color.b)), p))
	mm.set_instance_custom_data(i, Color(now + delay, life, drag, power))
	parts_written += 1


## Клуб дыма (PUFF) или обломок (DEBRIS): alpha — непрозрачность в начале.
func smoke(p: Vector3, vel: Vector3, color: Color, size0: float, size1: float, life: float, kind: int, drag: float = 0.0, alpha: float = 0.6, delay: float = 0.0) -> void:
	if smokes == null:
		return
	var mm := smokes.multimesh
	var i := _smoke_next
	_smoke_next = (_smoke_next + 1) % mm.instance_count
	mm.set_instance_transform(i, Transform3D(Basis(vel, Vector3(size0, size1, float(kind)), Vector3(color.r, color.g, color.b)), p))
	mm.set_instance_custom_data(i, Color(now + delay, life, drag, alpha))
	smokes_written += 1


## Летящий отрезок от a к b: голова проходит путь за dist / speed, хвост — seg позади;
## delay — родиться позже (очередь батареи: росчерк за росчерком), px — свой нижний
## предел толщины в точках экрана (0 — общий). Слот — самый старый.
func tracer(a: Vector3, b: Vector3, color: Color, width: float, speed: float, seg: float, power: float = 1.0, delay: float = 0.0, px: float = 0.0) -> void:
	if tracers == null:
		return
	var mm := tracers.multimesh
	var i := _tracer_next
	_tracer_next = (_tracer_next + 1) % mm.instance_count
	var d := maxf(a.distance_to(b), 1e-3)
	var frac := minf(seg / d, 1.0)
	mm.set_instance_transform(i, Transform3D(Basis(b - a, Vector3(frac, px, 0.0), Vector3(color.r, color.g, color.b)), a))
	mm.set_instance_custom_data(i, Color(now + delay, d / maxf(speed, 1.0), width, power))
	tracers_written += 1


## Часы эффектов: зовёт хозяин каждый кадр.
func set_time(t: float) -> void:
	now = t
	beam_mat.set_shader_parameter("now", t)
	flash_mat.set_shader_parameter("now", t)
	if tracer_mat != null:
		tracer_mat.set_shader_parameter("now", t)
	if part_mat != null:
		part_mat.set_shader_parameter("now", t)
	if smoke_mat != null:
		smoke_mat.set_shader_parameter("now", t)
