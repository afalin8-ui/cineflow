# view/ship_models.gd — модели кораблей и машин: файлы .glb, обмер и узлы из
# data/ship_models.json (выгрузка godot/tools/export_ships.mjs, руками не править).
#
# Обшивка: скан и нормали ОДНИ на все корабли (view/ships/tex/), в .glb их нет.
# Материалы с именем skin_* получают их здесь — один раз на файл модели: сцена
# из кэша ресурсов общая, и её материалы общие у всех кораблей этого вида.
extends RefCounted

const DATA_PATH := "res://data/ship_models.json"
const SKIN_ALBEDO := preload("res://view/ships/tex/hull_diff.jpg")
const SKIN_NORMAL := preload("res://view/ships/tex/hull_nor.jpg")

static var _data: Dictionary = {}
static var _error := ""
static var _scenes: Dictionary[String, PackedScene] = {}


## Весь файл обмера. Битый или пропавший — пустой словарь и текст беды в error().
static func data() -> Dictionary:
	if _data.is_empty() and _error == "":
		var text := FileAccess.get_file_as_string(DATA_PATH)
		if text == "":
			_error = "нет файла %s" % DATA_PATH
			return _data
		var j := JSON.new()
		if j.parse(text) != OK:
			_error = "%s: строка %d — %s" % [DATA_PATH, j.get_error_line() + 1, j.get_error_message()]
			return _data
		var d: Dictionary = j.data
		_data = d
	return _data


static func error() -> String:
	return _error


## Запись корабля: file, len, width, height, nodes {имя: {pos, parent, surfaces…}}.
static func ship(faction: StringName, id: StringName) -> Dictionary:
	var ships: Dictionary = data().get("ships", {})
	var fac: Dictionary = ships.get(String(faction), {})
	var rec: Dictionary = fac.get(String(id), {})
	return rec


static func craft(faction: StringName, role: StringName) -> Dictionary:
	var strike: Dictionary = data().get("strike", {})
	var fac: Dictionary = strike.get(String(faction), {})
	var rec: Dictionary = fac.get(String(role), {})
	return rec


## Сцена модели с уже поставленной обшивкой.
static func scene(file: String) -> PackedScene:
	if _scenes.has(file):
		return _scenes[file]
	var ps: PackedScene = load(file)
	if ps == null:
		push_error("модель не загрузилась: %s" % file)
		return null
	var probe := ps.instantiate()
	_dress(probe)
	probe.free()
	_scenes[file] = ps
	return ps


## Один меш машины (для MultiMesh): узел hull модели.
static func craft_mesh(faction: StringName, role: StringName) -> Mesh:
	var rec := craft(faction, role)
	var file: String = rec.get("file", "")
	var ps := scene(file)
	if ps == null:
		return null
	var probe := ps.instantiate()
	var hull := probe.find_child("hull", true, false) as MeshInstance3D
	var mesh: Mesh = hull.mesh if hull != null else null
	probe.free()
	return mesh


static func _dress(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null:
				continue
			# вдали обшивка рябит без анизотропии (08, 7.2 п. 12 — уровни выключены при импорте)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			if m.resource_name.begins_with("skin_") and m.albedo_texture == null:
				m.albedo_texture = SKIN_ALBEDO
				m.normal_enabled = true
				m.normal_texture = SKIN_NORMAL
				m.normal_scale = 0.8
				m.uv1_scale = Vector3(3.0, 3.0, 1.0)
	for c in n.get_children():
		_dress(c)
