# view/ship_visual.gd — корабль на сцене (архитектура, 5.2): модель .glb с узлами
# `hull`, `turret_i/muzzle_i`, `engines/engine_*`, `pd_*`, `aux_*`, `emitter`, `bay`,
# `launcher_0` — те же имена, что узлы в данных корабля (doctrine.json → nodes).
# Узлы здесь только находятся по имени; вращать башни и «выбивать» узлы будет бой.
# Ручная модель (view/hero/, CLAUDE.md, раздел 15) приходит в своём размере и уменьшается
# полем `scale` записи ровно до длины корабля в бою; обмер в записи — уже в единицах боя.
# Узлы со `spin_axis` (реактор крейсера Тройдена) вращаются — ТОЛЬКО картинка, от игрового
# времени вида (на паузе стоят, на 4× — вчетверо); модель боя об этом не знает.
extends Node3D

const ShipModels := preload("res://view/ship_models.gd")
## Скорость вращения узла со spin_axis, рад в игровую секунду, если в записи нет spin_rate.
const SPIN_RATE := 0.6

## ТОЛЬКО для проверки отката (tests/test_ui_hero.gd), в игре false: реактор крутится от
## НАСТОЯЩИХ часов кадра — на паузе он вертелся бы дальше, а на 4× — как на 1×.
static var rollback_spin_real_clock := false

var faction: StringName
var ship_id: StringName
var record: Dictionary = {}
var model: Node3D
## Узлы модели по имени (те, что перечислены в обмере).
var parts: Dictionary[StringName, Node3D] = {}
## Вращающиеся узлы: узел, его ось (в своих осях), скорость и исходный поворот.
var _spin: Array[Dictionary] = []


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
	var k := model_scale()
	if k != 1.0:
		model.scale = Vector3(k, k, k)
	add_child(model)
	var nodes: Dictionary = record.get("nodes", {})
	for key: String in nodes:
		var n := model.find_child(key, true, false) as Node3D
		if n != null:
			parts[StringName(key)] = n
			var rec: Dictionary = nodes[key]
			var ax: Array = rec.get("spin_axis", [])
			if ax.size() == 3:
				var ax0: float = ax[0]
				var ax1: float = ax[1]
				var ax2: float = ax[2]
				var a := Vector3(ax0, ax1, ax2)
				var rate: float = rec.get("spin_rate", SPIN_RATE)
				if a.length() > 0.0:
					_spin.append({"node": n, "axis": a.normalized(), "rate": rate, "base": n.basis})
	return true


## Во сколько вид уменьшает (увеличивает) модель: ручная модель встаёт в длину корабля
## в бою. У выгрузки из three.js — 1.
func model_scale() -> float:
	var v: float = record.get("scale", 1.0)
	return v if v > 0.0 else 1.0


## Повернуть вращающиеся узлы на миг игрового времени t (угол — от t, а не накоплением: тот
## же кадр при той же секунде боя на 60 и на 144 кадрах). real_t — настоящие часы вида
## (идут и на паузе), нужны только откату.
func spin(t: float, real_t: float = 0.0) -> void:
	if _spin.is_empty():
		return
	var at := real_t if rollback_spin_real_clock else t
	for d in _spin:
		var n: Node3D = d["node"]
		var axis: Vector3 = d["axis"]
		var rate: float = d["rate"]
		var base: Basis = d["base"]
		n.basis = base * Basis(axis, fposmod(rate * at, TAU))


## Узлы, которые вращаются (проверки).
func spinning() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for d in _spin:
		var n: Node3D = d["node"]
		out.append(n)
	return out


## Можно ли повернуть башню вокруг вертикали: спинальное орудие (`fixed` в записи узла) — нет.
## Башни вид пока не вращает; кто начнёт — спрашивает здесь.
func turret_can_turn(node_name: StringName) -> bool:
	var nodes: Dictionary = record.get("nodes", {})
	var rec: Dictionary = nodes.get(String(node_name), {})
	if rec.is_empty() or part(node_name) == null:
		return false
	var fixed: bool = rec.get("fixed", false)
	return not fixed


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
