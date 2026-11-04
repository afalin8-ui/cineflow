class_name ShipMesh
## Серые силуэты из простых фигур. Тройден — прямой корпус с выносными
## двигателями и кольцом реактора; Плэктор — катамаран из двух корпусов.
## Пламя двигателей — цвет стороны. 1 единица сцены = 10 м.

const S := 0.1

static var _mats := {}

static func mat(c: Color, emit := false) -> StandardMaterial3D:
	var key := "%s|%s" % [c.to_html(), emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	m.metallic = 0.2
	if emit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 3.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m

static func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	mi.material_override = m
	parent.add_child(mi)
	return mi

static func _cyl(parent: Node3D, r: float, h: float, at: Vector3, m: Material, axis := "x") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	mi.mesh = c
	mi.position = at
	if axis == "x":
		mi.rotation = Vector3(0, 0, PI / 2)
	mi.material_override = m
	parent.add_child(mi)
	return mi

static func _flame(parent: Node3D, r: float, at: Vector3, team_col: Color) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r * 0.2
	c.height = r * 4.0
	c.radial_segments = 8
	mi.mesh = c
	mi.position = at + Vector3(-r * 2.0, 0, 0)
	mi.rotation = Vector3(0, 0, PI / 2)
	mi.material_override = mat(team_col, true)
	mi.name = "flame"
	parent.add_child(mi)

## Длина силуэта в единицах сцены: мелочь увеличена, иначе её не видно с высоты.
static func vis_len(d: Dictionary) -> float:
	var L: float = d.size * S
	if Defs.is_squad(d.cls):
		return 9.0 if d.cls == "craft" else 13.0
	return max(L, 22.0)

static func build(d: Dictionary, team_col: Color) -> Node3D:
	var root := Node3D.new()
	var L := vis_len(d)
	var troy: bool = d.fac == "troyden"
	var body := mat(Color(0.62, 0.66, 0.72) if troy else Color(0.5, 0.52, 0.46))
	var dark := mat(Color(0.32, 0.34, 0.38) if troy else Color(0.3, 0.3, 0.27))
	var accent := mat(team_col.lerp(Color(0.6, 0.6, 0.6), 0.45))
	match d.cls:
		"craft", "bomber":
			_box(root, Vector3(L, L * 0.12, L * (0.5 if d.cls == "craft" else 0.7)), Vector3.ZERO, accent)
			_box(root, Vector3(L * 0.5, L * 0.18, L * 0.18), Vector3(L * 0.1, L * 0.06, 0), body)
			_flame(root, L * 0.08, Vector3(-L * 0.5, 0, 0), team_col)
		"station":
			if troy:
				var ring := MeshInstance3D.new()
				var t := TorusMesh.new()
				t.inner_radius = L * 0.36
				t.outer_radius = L * 0.46
				ring.mesh = t
				ring.material_override = body
				ring.name = "spin"
				root.add_child(ring)
				_cyl(root, L * 0.12, L * 0.35, Vector3.ZERO, dark, "y")
				_box(root, Vector3(L * 0.9, L * 0.03, L * 0.05), Vector3.ZERO, dark)
				_box(root, Vector3(L * 0.05, L * 0.03, L * 0.9), Vector3.ZERO, dark)
				_box(root, Vector3(L * 0.16, L * 0.06, L * 0.16), Vector3(0, L * 0.2, 0), accent)
			else:
				_box(root, Vector3(L * 0.9, L * 0.12, L * 0.22), Vector3(0, 0, L * 0.25), body)
				_box(root, Vector3(L * 0.9, L * 0.12, L * 0.22), Vector3(0, 0, -L * 0.25), body)
				_box(root, Vector3(L * 0.3, L * 0.1, L * 0.7), Vector3.ZERO, dark)
				_box(root, Vector3(L * 0.14, L * 0.16, L * 0.14), Vector3(0, L * 0.1, 0), accent)
		"harvester":
			_box(root, Vector3(L, L * 0.3, L * 0.4), Vector3.ZERO, body)
			_box(root, Vector3(L * 0.3, L * 0.4, L * 0.55), Vector3(L * 0.4, 0, 0), dark)
			_flame(root, L * 0.1, Vector3(-L * 0.5, 0, 0), team_col)
		_:
			if troy:
				# прямой корпус, сзади двигательный отсек с выносами, впереди главное орудие
				_box(root, Vector3(L * 0.78, L * 0.08, L * 0.12), Vector3(L * 0.06, 0, 0), body)
				_box(root, Vector3(L * 0.2, L * 0.12, L * 0.22), Vector3(-L * 0.36, 0, 0), dark)
				for sgn in [-1.0, 1.0]:
					_box(root, Vector3(L * 0.05, L * 0.02, L * 0.14), Vector3(-L * 0.38, 0, sgn * L * 0.13), dark)
					_cyl(root, L * 0.035, L * 0.16, Vector3(-L * 0.4, 0, sgn * L * 0.2), body)
					_flame(root, L * 0.03, Vector3(-L * 0.48, 0, sgn * L * 0.2), team_col)
				_flame(root, L * 0.045, Vector3(-L * 0.46, 0, 0), team_col)
				if L > 60:
					var ring := MeshInstance3D.new()
					var t := TorusMesh.new()
					t.inner_radius = L * 0.06
					t.outer_radius = L * 0.085
					ring.mesh = t
					ring.rotation = Vector3(0, 0, PI / 2)
					ring.position = Vector3(-L * 0.18, 0, 0)
					ring.material_override = accent
					ring.name = "spin"
					root.add_child(ring)
				_cyl(root, L * 0.025, L * 0.25, Vector3(L * 0.55, 0, 0), dark)
				_box(root, Vector3(L * 0.12, L * 0.06, L * 0.04), Vector3(0, L * 0.06, 0), accent)
			else:
				# катамаран: два корпуса, оружие между ними
				for sgn in [-1.0, 1.0]:
					_box(root, Vector3(L * 0.95, L * 0.09, L * 0.11), Vector3(0, 0, sgn * L * 0.13), body)
					_flame(root, L * 0.04, Vector3(-L * 0.48, 0, sgn * L * 0.13), team_col)
				_box(root, Vector3(L * 0.45, L * 0.05, L * 0.16), Vector3(-L * 0.05, 0, 0), dark)
				_cyl(root, L * 0.03, L * 0.35, Vector3(L * 0.3, 0, 0), accent)
	return root
