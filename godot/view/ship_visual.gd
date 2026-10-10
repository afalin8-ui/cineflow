# view/ship_visual.gd — корабль на сцене (архитектура, 5.2): модель .glb с узлами
# `hull`, `turret_i/muzzle_i`, `engines/engine_*`, `pd_*`, `aux_*`, `emitter`, `bay`,
# `launcher_0` — те же имена, что узлы в данных корабля (doctrine.json → nodes).
# Узлы здесь только находятся по имени; вращать башни и «выбивать» узлы будет бой.
extends Node3D

const ShipModels := preload("res://view/ship_models.gd")

var faction: StringName
var ship_id: StringName
var record: Dictionary = {}
var model: Node3D
## Узлы модели по имени (те, что перечислены в обмере).
var parts: Dictionary[StringName, Node3D] = {}


func setup(p_faction: StringName, p_id: StringName) -> bool:
	faction = p_faction
	ship_id = p_id
	record = ShipModels.ship(p_faction, p_id)
	var file: String = record.get("file", "")
	var ps := ShipModels.scene(file) if file != "" else null
	if ps == null:
		push_error("нет модели корабля %s.%s" % [p_faction, p_id])
		return false
	model = ps.instantiate() as Node3D
	add_child(model)
	var nodes: Dictionary = record.get("nodes", {})
	for key: String in nodes:
		var n := model.find_child(key, true, false) as Node3D
		if n != null:
			parts[StringName(key)] = n
	return true


func part(node_name: StringName) -> Node3D:
	return parts.get(node_name)


## Точка узла в мире (дуло, сопло…); нет узла — сам корабль.
func part_point(node_name: StringName) -> Vector3:
	var n := part(node_name)
	return n.global_position if n != null else global_position


func length() -> float:
	var v: float = record.get("len", 0.0)
	return v


func width() -> float:
	var v: float = record.get("width", 0.0)
	return v
