extends SceneTree
func _init():
	for p in ["res://assets/troyden_capital_godot.glb", "res://assets/troyden_corvette_plain.glb"]:
		var sc: PackedScene = load(p)
		var n: Node3D = sc.instantiate()
		var meshes := 0; var surfaces := 0; var tris := 0; var mats := {}
		var aabb := AABB()
		var first := true
		for m: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			meshes += 1
			surfaces += m.mesh.get_surface_count()
			for s in m.mesh.get_surface_count():
				var arr := m.mesh.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() / 3) if idx != null else (arr[Mesh.ARRAY_VERTEX].size() / 3)
				var mat = m.get_active_material(s)
				if mat: mats[mat.get_instance_id()] = true
		var mm := n.find_children("*", "MultiMeshInstance3D", true, false).size()
		print(p.get_file(), ": MeshInstance3D=", meshes, " поверхностей=", surfaces, " треугольников=", tris, " материалов=", mats.size(), " MultiMesh=", mm, " узлов всего=", n.find_children("*", "", true, false).size())
		n.free()
	quit()
