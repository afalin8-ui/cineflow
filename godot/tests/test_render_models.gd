# Модели кораблей (план G0, п. 5; архитектура, 5.2; часть 08, П.3): то, что Godot
# ИМПОРТИРОВАЛ из view/ships/*.glb, а не то, что обещает обмер:
# - длина по AABB всей геометрии (эффектов в моделях нет) — в ±20% от model_len
#   выгрузки (C88): иначе разъедутся строй и расталкивание;
# - у каждой модели есть узлы из doctrine.json → nodes её корабля (09, 10.5):
#   слияние ВСЕГО корабля в 9 мешей (проба П.3) закрыло бы повреждения по узлам;
# - башня — узел с геометрией и дулом внутри: её можно повернуть.
# Откаты встроены: модель ×1,5 и модель без узла обязаны покраснеть.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const ShipModels := preload("res://view/ship_models.gd")
const FACTIONS: Array[StringName] = [&"troyden", &"plektor"]
const TOL := 0.2


## Рамка всей геометрии модели в её координатах.
static func model_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			var t := _to_root(mi, root)
			var b := t * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		for c in n.get_children():
			stack.append(c)
	return box


static func _to_root(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != root:
		var p3 := p as Node3D
		if p3 != null:
			t = p3.transform * t
		p = p.get_parent()
	return root.transform * t


## Беды модели: длина и узлы. Пусто — модель годится.
static func problems(root: Node3D, want_len: float, parts: Array[Defs.PartDef]) -> PackedStringArray:
	var bad := PackedStringArray()
	var box := model_aabb(root)
	var got := maxf(box.size.x, box.size.z)
	if absf(got - want_len) > want_len * TOL:
		bad.append("длина %.2f вне ±20%% от model_len %.2f" % [got, want_len])
	for p in parts:
		if not has_node_named(root, p.model):
			bad.append("нет узла %s (%s)" % [p.model, p.name])
	return bad


static func has_node_named(root: Node, model: String) -> bool:
	var star := model.ends_with("*")
	var pre := model.trim_suffix("*")
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var nm := String(n.name)
		if (star and nm.begins_with(pre) and nm.substr(pre.length()).is_valid_int()) or (not star and nm == model):
			return true
		for c in n.get_children():
			stack.append(c)
	return false


func _ship_list(defs: Defs, fac: StringName) -> Array[Defs.ShipDef]:
	var out: Array[Defs.ShipDef] = []
	var f: Defs.FactionDef = defs.factions[fac]
	for id in f.ship_order:
		out.append(f.ships[id])
	out.append(defs.station)
	return out


func test_models_length_and_nodes() -> void:
	var defs := Defs.load_default({}) as Defs
	if not ok(defs.ok, "данные загрузились"):
		return
	ok(ShipModels.error() == "", "обмер моделей прочитан: %s" % ShipModels.error())
	var n := 0
	for fac in FACTIONS:
		for s in _ship_list(defs, fac):
			var rec := ShipModels.ship(fac, s.id)
			var file: String = rec.get("file", "")
			if not ok(file != "", "%s.%s: модель есть в обмере" % [fac, s.id]):
				continue
			var ps := ShipModels.scene(file)
			if not ok(ps != null, "%s.%s: %s импортирован" % [fac, s.id, file]):
				continue
			var root := ps.instantiate() as Node3D
			var bad := problems(root, s.model_len, s.nodes)
			ok(bad.is_empty(), "%s.%s: %s" % [fac, s.id, "; ".join(bad)])
			# башни главного калибра — с геометрией и дулом внутри (её можно повернуть)
			for p in s.nodes:
				if p.model.begins_with("turret_"):
					var t := root.find_child(p.model, true, false) as MeshInstance3D
					ok(t != null and t.mesh != null and t.mesh.get_surface_count() > 0, "%s.%s: %s — узел с геометрией" % [fac, s.id, p.model])
					var mz := StringName("muzzle_" + p.model.trim_prefix("turret_"))
					ok(t != null and t.find_child(mz, false, false) != null, "%s.%s: %s внутри %s" % [fac, s.id, mz, p.model])
			# ширина в данных — для капсулы выбора (архитектура, 4)
			var w: float = rec.get("width", 0.0)
			near(w, model_aabb(root).size.x, 0.05, "%s.%s: ширина в обмере" % [fac, s.id])
			root.free()
			n += 1
		for role: StringName in [&"interceptor", &"fighter", &"bomber"]:
			var cr := ShipModels.craft(fac, role)
			var cd: Defs.StrikeRoleDef = defs.strike_roles.get(role)
			var craft: Defs.CraftDef = defs.factions[fac].strike.get(role)
			var want := craft.model_len if craft != null else 0.0
			var mesh := ShipModels.craft_mesh(fac, role)
			if ok(mesh != null, "%s: машина %s импортирована" % [fac, role]):
				var got := maxf(mesh.get_aabb().size.x, mesh.get_aabb().size.z)
				ok(want > 0.0 and absf(got - want) <= want * TOL, "%s: машина %s длиной %.2f при model_len %.2f" % [fac, role, got, want])
			ok(cr.size() > 0 and cd != null, "%s: машина %s в обмере" % [fac, role])
	eq(n, 15, "проверено моделей кораблей (Тройден 6 + станция, Плэктор 7 + станция)")


func test_models_rollback() -> void:
	# откат: модель ×1,5 и модель без узла — проверка обязана покраснеть
	var defs := Defs.load_default({}) as Defs
	var s := defs.ship(&"plektor", &"capital")
	var file: String = ShipModels.ship(&"plektor", &"capital").get("file", "")
	var ps := ShipModels.scene(file)
	var root := ps.instantiate() as Node3D
	ok(problems(root, s.model_len, s.nodes).is_empty(), "флагман Плэктора годится как есть")
	root.scale = Vector3.ONE * 1.5
	var big := problems(root, s.model_len, s.nodes)
	ok(big.size() == 1 and big[0].begins_with("длина"), "откат «модель ×1,5» краснеет на длине: %s" % "; ".join(big))
	root.scale = Vector3.ONE
	var t1 := root.find_child("turret_1", true, false)
	t1.name = "turret_9"
	var lost := problems(root, s.model_len, s.nodes)
	ok(lost.size() == 1 and lost[0].contains("turret_1"), "откат «нет башни turret_1» краснеет на узле: %s" % "; ".join(lost))
	# слитый в один меш корабль (проба П.3): узлов нет вовсе
	var flat := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "hull_0"
	mi.mesh = (root.find_child("hull", true, false) as MeshInstance3D).mesh
	flat.add_child(mi)
	var merged := problems(flat, s.model_len, s.nodes)
	ok(merged.size() >= s.nodes.size() - 1, "откат «весь корабль одним мешем» краснеет на узлах: %d бед" % merged.size())
	flat.free()
	root.free()
