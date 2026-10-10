# sim/formation.gd — места по ролям (архитектура, 2.3): ОДНА функция для ИИ и для
# ПКМ игрока (09, 5 и 6.4). Строй боя целиком — пакет G4.
#
# Сейчас здесь только расстановка на старте — ВРЕМЕННАЯ простая таблица мест
# 09, 5.1–5.5 без логики строя (сжатого шага и второй шеренги нет): по ней стоят
# «Стол» (tools/showcase.gd) и «Полигон» (G1). Стороны появляются строем по ролям
# относительно своей линии старта ±deploy.heavy_z; свой флот приказов не получает
# (09, 9.5 п. 16) — это расстановка, а не приказ.
extends RefCounted

const Defs := preload("res://sim/defs.gd")


## Места стороны на старте: список [id, Vector2(x, z)] в порядке расстановки.
## sign_z: +1 — атакующий (z > 0), −1 — защитник. Корабли — по id клана.
static func start_places(defs: Defs, clan: StringName, ids: Array[StringName], sign_z: float) -> Array:
	var d := defs.doctrine
	var heavies: Array[Defs.ShipDef] = []
	var corv: Array[Defs.ShipDef] = []
	var frig: Array[Defs.ShipDef] = []
	var ecm: Array[Defs.ShipDef] = []
	var carr: Array[Defs.ShipDef] = []
	for id in ids:
		var s := defs.ship(clan, id)
		if s == null:
			continue
		if s.ecm:
			ecm.append(s)
		elif s.hangar > 0:
			carr.append(s)
		elif s.main != null:
			heavies.append(s)
		elif id == &"corvette":
			corv.append(s)
		else:
			frig.append(s)
	var out: Array = []
	# L = 0,85 × наименьшая дальность главного калибра своей линии (09, 5.2)
	var r_line := INF
	for s in heavies:
		r_line = minf(r_line, s.main.rng)
	var line_l := d.line_L_k * r_line if r_line < INF else 0.0
	var heavy_z := d.deploy_heavy_z
	# тяжёлые: крупные в центре, шаг hull + hull + 60 (09, 5.3)
	heavies.sort_custom(func(a: Defs.ShipDef, b: Defs.ShipDef) -> bool: return a.hull > b.hull)
	var row: Array[Defs.ShipDef] = []
	for i in heavies.size():
		if i % 2 == 0:
			row.append(heavies[i])
		else:
			row.push_front(heavies[i])
	var xs := PackedFloat64Array()
	var x := 0.0
	for i in row.size():
		if i > 0:
			x += row[i - 1].hull + row[i].hull + d.line_step_heavy
		xs.append(x)
	var width := x
	for i in row.size():
		out.append([row[i].id, Vector2((xs[i] - width * 0.5) * sign_z, sign_z * heavy_z)])
	# лёгкие шеренги той же ширины, что линия тяжёлых, но не уже 400; РЭБ — в середине
	# шеренги фрегатов (09, 5.1, 5.3)
	var rank_w := maxf(width, d.line_light_min_width)
	_rank(out, corv, sign_z * (heavy_z - d.line_corvette_k * line_l), rank_w, sign_z, d)
	var fr: Array[Defs.ShipDef] = []
	fr.append_array(frig)
	var mid := fr.size() >> 1
	for e in ecm:
		fr.insert(mid, e)
	_rank(out, fr, sign_z * (heavy_z - d.line_frigate_k * line_l), rank_w, sign_z, d)
	# носители — на line.carrier_back позади линии, по deploy.carrier_lat вбок
	for i in carr.size():
		var cx := (float(i) - (carr.size() - 1) * 0.5) * d.deploy_carrier_lat
		out.append([carr[i].id, Vector2(cx * sign_z, sign_z * (heavy_z + d.line_carrier_back))])
	return out


static func _rank(out: Array, list: Array[Defs.ShipDef], z: float, width: float, sign_z: float, d: Defs.Doctrine) -> void:
	var n := list.size()
	if n == 0:
		return
	var stp := 0.0
	if n > 1:
		var need := 0.0
		for i in range(1, n):
			need += list[i - 1].hull + list[i].hull + d.line_step_light
		stp = maxf(need, width) / (n - 1)
	for i in n:
		var cx := (float(i) - (n - 1) * 0.5) * stp
		out.append([list[i].id, Vector2(cx * sign_z, z)])


## Станция защитника — на deploy.station_back позади его линии старта (09, 5.5).
static func station_place(defs: Defs, sign_z: float) -> Vector2:
	return Vector2(0.0, sign_z * (defs.doctrine.deploy_heavy_z + defs.doctrine.deploy_station_back))
