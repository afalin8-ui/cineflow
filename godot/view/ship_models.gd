# view/ship_models.gd — модели кораблей и машин: файлы .glb, обмер и узлы из
# data/ship_models.json (выгрузка godot/tools/export_ships.mjs, руками не править).
#
# Обшивка: скан и нормали ОДНИ на все корабли (view/ships/tex/), в .glb их нет.
# Материалы с именем skin_* получают их здесь — один раз на файл модели: сцена
# из кэша ресурсов общая, и её материалы общие у всех кораблей этого вида.
#
# Ручные модели флота (view/hero/, ставит tools/install_model.py — CLAUDE.md, раздел 15):
# материалы trim_* — ОБЩИЙ трим-лист флота (view/hero/tex/trim_*.png), тоже один на все
# корабли; своё у корабля — карта AO во второй развёртке и цвет вершин (маска грязи и тона),
# цвет клана — baseColorFactor материала. Лист в .glb не кладётся (там заглушка 4×4).
extends RefCounted

const DATA_PATH := "res://data/ship_models.json"
const SKIN_ALBEDO := preload("res://view/ships/tex/hull_diff.jpg")
const SKIN_NORMAL := preload("res://view/ships/tex/hull_nor.jpg")
const TRIM_ALBEDO := preload("res://view/hero/tex/trim_basecolor.png")
const TRIM_NORMAL := preload("res://view/hero/tex/trim_normal.png")
const TRIM_ORM := preload("res://view/hero/tex/trim_orm.png")
const TRIM_EMIT := preload("res://view/hero/tex/trim_emission.png")
## Сила огней трим-листа (окна, щели): та, при которой модель проверял критик (круги 4–6).
const TRIM_EMIT_ENERGY := 3.0

## ТОЛЬКО для проверки отката (tests/test_ui_hero.gd), в игре false: материалы trim_* остаются
## как их дал импорт — без цвета вершин, без AO на прямом свете и без общего листа.
static var rollback_plain_trim := false

static var _path := DATA_PATH
static var _data: Dictionary = {}
static var _error := ""
static var _scenes: Dictionary[String, PackedScene] = {}


## Обмер из другого файла — для проверок «пропал файл моделей», «пропала одна
## .glb» (`-- --ship-models=ФАЙЛ`, tests/test_ui_table.gd). Пусто — обычный. Кэш
## сбрасывается.
static func use_file(path: String) -> void:
	_path = path if path != "" else DATA_PATH
	_data = {}
	_error = ""
	_scenes.clear()


## Весь файл обмера. Битый или пропавший — пустой словарь и текст беды в error().
static func data() -> Dictionary:
	if _data.is_empty() and _error == "":
		var text := FileAccess.get_file_as_string(_path)
		if text == "":
			_error = "нет файла %s" % _path
			return _data
		var j := JSON.new()
		if j.parse(text) != OK:
			_error = "%s: строка %d — %s" % [_path, j.get_error_line() + 1, j.get_error_message()]
			return _data
		if typeof(j.data) != TYPE_DICTIONARY:
			_error = "%s: ждали объект JSON" % _path
			return _data
		var d: Dictionary = j.data
		_data = d
	return _data


static func error() -> String:
	return _error


## Чего не хватает, чтобы показать эти корабли и машины, — беды словами (пусто —
## всё на месте). Спрашивать ДО сцены: пропавшая модель иначе молча дала бы пустое
## место на «Столе», а замер кадров мерил бы облегчённую сцену и честно писал бы
## «83 корабля» (замечание к G0b). Обмер — тоже данные, отказ у него громкий.
static func problems(faction: StringName, ship_ids: Array[StringName], craft_roles: Array[StringName]) -> PackedStringArray:
	var out := PackedStringArray()
	data()
	if _error != "":
		out.append("обмер моделей: " + _error)
		return out
	for id in ship_ids:
		_need(out, ship(faction, id), "корабля %s.%s" % [faction, id])
	for r in craft_roles:
		_need(out, craft(faction, r), "машины %s.%s" % [faction, r])
	return out


static func _need(out: PackedStringArray, rec: Dictionary, what: String) -> void:
	var file: String = rec.get("file", "")
	if file == "":
		out.append("нет модели %s в %s" % [what, _path])
	elif not ResourceLoader.exists(file):
		out.append("нет файла модели %s: %s" % [what, file])


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
			if m.resource_name.begins_with("trim_") and not rollback_plain_trim:
				_dress_trim(m)
			if m.resource_name.begins_with("skin_") and m.albedo_texture == null:
				m.albedo_texture = SKIN_ALBEDO
				m.normal_enabled = true
				m.normal_texture = SKIN_NORMAL
				m.normal_scale = 0.8
				m.uv1_scale = Vector3(3.0, 3.0, 1.0)
	for c in n.get_children():
		_dress(c)


## Материал trim_* ручной модели: цвет вершин — в цвет (импорт его читает, но в альбедо не
## включает), карта AO гасит и прямой свет (в ней не только AO, но и грязь, потёки, «верх светлее
## бортов»), лист — общий флота. Цвет материала (цвет клана) не трогаем.
static func _dress_trim(m: StandardMaterial3D) -> void:
	m.vertex_color_use_as_albedo = true
	if m.ao_enabled and m.ao_texture != null:
		m.ao_light_affect = 1.0
	if m.albedo_texture == null or m.albedo_texture.get_width() <= 4:
		m.albedo_texture = TRIM_ALBEDO
		m.normal_enabled = true
		m.normal_texture = TRIM_NORMAL
		m.roughness = 1.0
		m.roughness_texture = TRIM_ORM
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = TRIM_ORM
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_texture = TRIM_EMIT
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission_energy_multiplier = TRIM_EMIT_ENERGY
