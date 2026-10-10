# view/craft_layer.gd — авиация одним MultiMesh на вид машины (архитектура, 5.3):
# двести машин — вызовов отрисовки столько, сколько поверхностей у модели, а не
# по одному на машину. Положения пишутся пачкой — одним присваиванием буфера
# (12 чисел на машину: базис построчно и место), а не 240 вызовами в кадр.
extends Node3D

const ShipModels := preload("res://view/ship_models.gd")

var layers: Dictionary[StringName, MultiMeshInstance3D] = {}
var _buf: Dictionary[StringName, PackedFloat32Array] = {}


## Слой машин одного вида: клан, роль (interceptor/fighter/bomber), сколько.
func add_kind(key: StringName, faction: StringName, role: StringName, count: int) -> bool:
	var mesh := ShipModels.craft_mesh(faction, role)
	if mesh == null:
		push_error("нет модели машины %s.%s" % [faction, role])
		return false
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	mm.custom_aabb = AABB(Vector3(-6000, -3000, -6000), Vector3(12000, 6000, 12000))
	var mi := MultiMeshInstance3D.new()
	mi.name = "craft_%s" % key
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	layers[key] = mi
	var buf := PackedFloat32Array()
	buf.resize(count * 12)
	_buf[key] = buf
	return true


func count(key: StringName) -> int:
	var mi: MultiMeshInstance3D = layers.get(key)
	return mi.multimesh.instance_count if mi != null else 0


## Положение машины i: место и направление носа (нос модели — к −z).
func put(key: StringName, i: int, pos: Vector3, fwd: Vector3, up: Vector3 = Vector3.UP) -> void:
	var z := -fwd.normalized()
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	var b := _buf[key]
	var o := i * 12
	# формат буфера MultiMesh (TRANSFORM_3D): строки базиса, в конце каждой — место
	b[o] = x.x; b[o + 1] = y.x; b[o + 2] = z.x; b[o + 3] = pos.x
	b[o + 4] = x.y; b[o + 5] = y.y; b[o + 6] = z.y; b[o + 7] = pos.y
	b[o + 8] = x.z; b[o + 9] = y.z; b[o + 10] = z.z; b[o + 11] = pos.z


## Отдать накопленное в видеокарту — раз в кадр на вид.
func commit() -> void:
	for key: StringName in layers:
		layers[key].multimesh.buffer = _buf[key]
