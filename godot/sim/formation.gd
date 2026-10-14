# sim/formation.gd — строй по ролям (09, раздел 5 и 6.4; план G4, п. 3). ОДНА функция мест
# places() — для расстановки на старте (5.5), для ИИ (sim/ai.gd — шаги 6–7 тика 7.1),
# для подкрепления (5.5, план G4, п. 8) и для ПКМ игрока по полю (6.4).
# Вторая копия разъехалась бы с первой при первой правке, а строй, который ставит игрок,
# обязан совпадать с тем, по которому меряется стенд.
#
# Строй — полосы поперёк ОСИ ax «на противника» (5.1); точка P — центр линии тяжёлых;
# места — сдвиги от P вдоль ax (плюс — к противнику) и вбок по lat:
#   корветы +0,35 L · фрегаты и РЭБ в их середине +0,2 L · тяжёлые 0 (крупные в центре,
#   шаг hull + hull + 60, сжатый +20, не шире чужой линии + 500, вторая шеренга в 150 позади
#   в шахматном порядке — только кому хватает дальности) · носители −440 (враг рядом — −760)
#   · первый фрегат — зонт ПВО у носителя, если у противника есть авиация.
# L = 0,85 × наименьшая дальность главного калибра своей линии (5.2). Нет тяжёлых —
# шеренги лёгких от P: корветы в P, фрегаты в line.lights_alone_back за ними (6.4).
# Второй лёгкой шеренги НЕТ: лишние встают по флангам (5.3; откат --ecm-01L — «было»).
# Места раздаются по положению, а не по номеру (5.4): в каждой полосе — по видам — N-й слева
# получает N-е слева место. Строй шире расталкивания поперёк И по глубине (09, 9.5 пп. 9, 20).
# Свой флот приказов не получает: строй на старте — расстановка (09, 9.5 п. 16).
extends RefCounted

const Defs := preload("res://sim/defs.gd")
const Ship := preload("res://sim/ship.gd")

# полосы строя
const HEAVY := 0
const HEAVY2 := 1        # вторая шеренга тяжёлых (шахматный порядок)
const CORVETTE := 2
const FRIGATE := 3       # фрегаты и РЭБ — одна шеренга (5.1)
const CARRIER := 4
const UMBRELLA := 5      # первый фрегат — у носителя (3.3)
const ECM_OLD := 6       # РЭБ на 0,1 L — ТОЛЬКО откат --ecm-01L
const FRIGATE2 := 7      # вторая шеренга фрегатов «в 50 позади» — ТОЛЬКО откат --ecm-01L
const NONE := -1         # станция: не двигается
## ТОЛЬКО для проверки отката (в игре false): вторая шеренга фрегатов отката --ecm-01L ищет
## своих по первой шеренге, как в первой выкладке G4, — и они остаются без места (NONE).
static var rollback_rank2_by_fr := false

const BAND_NAMES: Array[String] = ["тяжёлые", "вторая шеренга тяжёлых", "корветы", "фрегаты", "носители", "зонт носителя", "РЭБ на 0,1 L", "вторая шеренга фрегатов"]


## Кто встаёт в строй: определение, корпус, где стоит сейчас и порядок, если положение
## не решает (старт — номер; заглушка — прежнее место, пока состав полосы не менялся).
class Member:
	var def: Defs.ShipDef
	var hull := 0.0
	var pos := Vector2.ZERO
	var key := 0.0


## Задание строя: точка линии тяжёлых, ось на противника и что известно о нём.
class Spec:
	var p := Vector2.ZERO
	var ax := Vector2(0.0, -1.0)
	var foe_width := -1.0         # ширина чужой линии тяжёлых (< 0 — не знаем: предела нет)
	var foe_air := false          # у противника носитель или станция с ангаром (3.3)
	var carrier_close := false    # чужой корабль ближе line.carrier_close_dist к носителю
	var advance_dead := -1.0      # ≥ 0: середина выиграна — корветы на L − advance_k × D чужих (3.5)
	var by_pos := true            # места по положению (5.4); false — по key
	var ecm_01l := false          # откат 09, 8.4: РЭБ на 0,1 L и вторая лёгкая шеренга позади


## Строй: место и полоса каждого (в порядке members), L и ширина линии тяжёлых.
class Out:
	var at := PackedVector2Array()
	var band := PackedInt32Array()
	var rank := PackedInt32Array()      # номер места слева в своей полосе и виде (5.4)
	var l := 0.0
	var width := 0.0


## Корпус по определению — та же формула, что у корабля в бою (C87; часть 01, 2.17):
## max(radius × 1,6; 0,36 × длина модели). Строй и расталкивание считают по ней.
static func hull_of(defs: Defs, def: Defs.ShipDef) -> float:
	var c := defs.consts
	var length := def.model_len if def.model_len > 0.0 else def.radius * c.len_fallback_k
	return maxf(def.radius * c.hull_formula_radius_k, length * c.hull_formula_len_k)


static func role_of(def: Defs.ShipDef) -> int:
	if def.station:
		return NONE
	if def.ecm:
		return FRIGATE
	if def.hangar > 0:
		return CARRIER
	if def.main != null:
		return HEAVY
	if def.id == &"corvette":
		return CORVETTE
	return FRIGATE


## L = line.L_k × наименьшая дальность главного калибра тяжёлых (5.2); тяжёлых нет — 0.
static func line_l(defs: Defs, members: Array[Member]) -> float:
	var r := INF
	for m in members:
		if role_of(m.def) == HEAVY:
			r = minf(r, m.def.main.rng)
	return defs.doctrine.line_L_k * r if r < INF else 0.0


## Ширина линии тяжёлых обычным шагом (крупные в центре) — для предела «не шире чужой + 500».
static func heavy_width(defs: Defs, members: Array[Member]) -> float:
	var hv: Array[Member] = []
	for m in members:
		if role_of(m.def) == HEAVY:
			hv.append(m)
	return _row_width(_center_out(hv), defs.doctrine.line_step_heavy)


## Места строя (09, 5.1–5.4, 6.4). ОДНА функция на все случаи — см. шапку.
static func places(defs: Defs, members: Array[Member], spec: Spec) -> Out:
	var d := defs.doctrine
	var out := Out.new()
	out.at.resize(members.size())
	out.band.resize(members.size())
	out.rank.resize(members.size())
	for i in members.size():
		out.at[i] = spec.p
		out.band[i] = NONE
		out.rank[i] = 0
	var ax := spec.ax.normalized() if spec.ax.length_squared() > 1e-9 else Vector2(0.0, -1.0)
	var lat := Vector2(-ax.y, ax.x)
	var heavies: Array[Member] = []
	var corv: Array[Member] = []
	var frig: Array[Member] = []
	var ecm: Array[Member] = []
	var carr: Array[Member] = []
	for m in members:
		match role_of(m.def):
			HEAVY: heavies.append(m)
			CORVETTE: corv.append(m)
			CARRIER: carr.append(m)
			FRIGATE:
				if m.def.ecm:
					ecm.append(m)
				else:
					frig.append(m)
	var l := line_l(defs, members)
	out.l = l
	# слоты: [полоса, id, Vector2(вбок, вдоль оси)]
	var slots: Array[Array] = []
	# ── тяжёлые (5.3): крупные в центре; не шире чужой + 500 — сжатый шаг, потом вторая
	# шеренга (кому хватает дальности: L + 150 ≤ 0,92 R), в шахматном порядке ──
	var row := _center_out(heavies)
	var rank2: Array[Member] = []
	var limit := INF
	if spec.foe_width >= 0.0:
		limit = maxf(d.line_width_floor, spec.foe_width + d.line_width_over)
	var stp := d.line_step_heavy
	if _row_width(row, stp) > limit:
		stp = d.line_step_heavy_min
		while _row_width(row, stp) > limit:
			var moved := false
			for i in row.size():
				var m := row[i]
				if l + d.line_rank2_back <= d.belt_far_k * m.def.main.rng and row.size() > 1:
					rank2.append(m)
					row.remove_at(i)
					moved = true
					break
			if not moved:
				break
	var xs := _row_xs(row, stp)
	var width := 0.0
	if xs.size() > 0:
		width = xs[xs.size() - 1] - xs[0]
	out.width = width
	for i in row.size():
		slots.append([HEAVY, row[i].def.id, Vector2(xs[i], 0.0)])
	# вторая шеренга: в промежутках первой, ближние к центру первыми; не хватило — по краям
	if not rank2.is_empty():
		var gaps := PackedFloat64Array()
		for i in range(1, xs.size()):
			gaps.append((xs[i - 1] + xs[i]) * 0.5)
		var g_sorted := Array(gaps)
		g_sorted.sort_custom(func(a: float, b: float) -> bool: return absf(a) < absf(b) or (absf(a) == absf(b) and a < b))
		var edge_r := (xs[xs.size() - 1] if xs.size() > 0 else 0.0)
		var edge_l := (xs[0] if xs.size() > 0 else 0.0)
		for i in rank2.size():
			var x := 0.0
			if i < g_sorted.size():
				x = g_sorted[i]
			else:
				var h := rank2[i].hull * 2.0 + d.line_step_heavy_min
				if (i - g_sorted.size()) % 2 == 0:
					edge_r += h
					x = edge_r
				else:
					edge_l -= h
					x = edge_l
			slots.append([HEAVY2, rank2[i].def.id, Vector2(x, -d.line_rank2_back)])
	# ── лёгкие шеренги (5.1, 5.3): той же ширины, что линия, но не уже 400; лишние — по флангам ──
	var rank_w := maxf(width, d.line_light_min_width)
	var z_corv := d.line_corvette_k * l
	var z_frig := d.line_frigate_k * l
	if l <= 0.0:
		# без тяжёлых шеренги лёгких — от точки приказа как от своей линии (6.4): корветы в ней,
		# фрегаты в line.lights_alone_back за ними; нет корветов — фрегаты в самой точке
		z_corv = 0.0
		z_frig = -d.line_lights_alone_back if not corv.is_empty() else 0.0
	if spec.advance_dead >= 0.0 and l > 0.0:
		z_corv = l - d.line_advance_k * spec.advance_dead     # наступление (3.5)
	_rank(slots, CORVETTE, corv, z_corv, rank_w, d.line_step_light)
	# первый фрегат — зонт ПВО носителя, если у противника есть авиация (3.3)
	var umb: Member = null
	if spec.foe_air and not carr.is_empty() and not frig.is_empty():
		umb = frig[0]
		if spec.by_pos:
			var c0 := spec.p - ax * d.line_carrier_back
			for f in frig:
				if f.pos.distance_squared_to(c0) < umb.pos.distance_squared_to(c0):
					umb = f
		frig.erase(umb)
	var fr: Array[Member] = []
	fr.append_array(frig)
	var back: Array[Member] = []           # вторая шеренга фрегатов — ТОЛЬКО откат --ecm-01L
	if spec.ecm_01l:
		# откат 09, 8.4 (было): РЭБ у центра на 0,1 L; фрегаты, не влезшие шагом в ширину
		# линии, — второй шеренгой в line.light_rank2 (was) позади первой
		var ecm_k: float = d.was.get(&"line.ecm_k", d.line_ecm_k)
		var back_z: float = d.was.get(&"line.light_rank2", 0.0)
		_rank(slots, ECM_OLD, ecm, ecm_k * l, 0.0, d.line_step_light)
		var cap := _fit(fr, rank_w, d.line_step_light)
		while fr.size() > cap:
			back.append(fr.pop_back())
		_rank(slots, FRIGATE, fr, z_frig, rank_w, d.line_step_light)
		_rank(slots, FRIGATE2, back, z_frig - back_z, rank_w, d.line_step_light)
	else:
		var mid := fr.size() >> 1
		for e in ecm:
			fr.insert(mid, e)
		_rank(slots, FRIGATE, fr, z_frig, rank_w, d.line_step_light)
	# носители — позади линии, по deploy.carrier_lat вбок (5.1)
	var cb := d.line_carrier_back_close if spec.carrier_close else d.line_carrier_back
	if heavies.is_empty() and corv.is_empty() and frig.is_empty() and ecm.is_empty():
		cb = 0.0                           # одни носители — в самой точке приказа: впереди некого прикрывать
	for i in carr.size():
		var cx := (float(i) - (carr.size() - 1) * 0.5) * d.deploy_carrier_lat
		slots.append([CARRIER, carr[i].def.id, Vector2(cx, -cb)])
	if umb != null:
		var cx0 := (-(carr.size() - 1) * 0.5) * d.deploy_carrier_lat
		var side := 1.0 if cx0 <= 0.0 else -1.0
		var off := carr[0].hull + umb.hull + d.line_umbrella_lat
		slots.append([UMBRELLA, umb.def.id, Vector2(cx0 + side * off, -cb)])
	# ── раздача мест (5.4): по полосе и виду, N-й слева — на N-е слева место ──
	var groups: Dictionary = {}
	for sl in slots:
		var k := "%d:%s" % [sl[0], sl[1]]
		if not groups.has(k):
			groups[k] = []
		var ga: Array = groups[k]
		ga.append(sl)
	var taken: Dictionary = {}
	for k: String in groups:
		var band := k.get_slice(":", 0).to_int()
		var id := StringName(k.get_slice(":", 1))
		var list: Array = groups[k]
		list.sort_custom(func(a: Array, b2: Array) -> bool:
			var va: Vector2 = a[2]
			var vb: Vector2 = b2[2]
			return va.x < vb.x)
		var who: Array[int] = []
		for i in members.size():
			if taken.has(i):
				continue
			var m := members[i]
			if m.def.id != id:
				continue
			if not _in_band(m, band, row, rank2, corv, fr, back, ecm, carr, umb, spec):
				continue
			who.append(i)
		who.sort_custom(func(a: int, b2: int) -> bool:
			var ma := members[a]
			var mb := members[b2]
			var ka := (ma.pos - spec.p).dot(lat) if spec.by_pos else ma.key
			var kb := (mb.pos - spec.p).dot(lat) if spec.by_pos else mb.key
			return ka < kb or (ka == kb and ma.key < mb.key))
		for j in mini(who.size(), list.size()):
			var sl: Array = list[j]
			var v: Vector2 = sl[2]
			out.at[who[j]] = spec.p + lat * v.x + ax * v.y
			out.band[who[j]] = band
			out.rank[who[j]] = j
			taken[who[j]] = true
	return out


## Входит ли член строя в полосу. Вторая шеренга фрегатов (только откат --ecm-01L) — СВОИМ
## списком: её фрегаты сняты с первой (fr), и по fr им не досталось бы места вовсе — они
## стояли бы в P, посреди линии тяжёлых, и откат краснел бы не тем (замечание к G4).
static func _in_band(m: Member, band: int, row: Array[Member], rank2: Array[Member], corv: Array[Member],
		fr: Array[Member], back: Array[Member], ecm: Array[Member], carr: Array[Member], umb: Member, spec: Spec) -> bool:
	match band:
		HEAVY: return m in row
		HEAVY2: return m in rank2
		CORVETTE: return m in corv
		FRIGATE: return (m in fr) or (not spec.ecm_01l and m in ecm)
		FRIGATE2: return (m in fr) if rollback_rank2_by_fr else (m in back)
		ECM_OLD: return m in ecm
		CARRIER: return m in carr
		UMBRELLA: return m == umb
	return false


## Тяжёлые от центра наружу по убыванию корпуса (5.3): крупные — в центре линии.
static func _center_out(list: Array[Member]) -> Array[Member]:
	var sorted := list.duplicate()
	sorted.sort_custom(func(a: Member, b: Member) -> bool: return a.hull > b.hull or (a.hull == b.hull and a.key < b.key))
	var row: Array[Member] = []
	for i in sorted.size():
		if i % 2 == 0:
			row.append(sorted[i])
		else:
			row.push_front(sorted[i])
	return row


static func _row_xs(row: Array[Member], extra: float) -> PackedFloat64Array:
	var xs := PackedFloat64Array()
	var x := 0.0
	for i in row.size():
		if i > 0:
			x += row[i - 1].hull + row[i].hull + extra
		xs.append(x)
	var w := x
	for i in xs.size():
		xs[i] -= w * 0.5
	return xs


static func _row_width(row: Array[Member], extra: float) -> float:
	var w := 0.0
	for i in range(1, row.size()):
		w += row[i - 1].hull + row[i].hull + extra
	return w


## Шеренга лёгких: шагом hull + hull + 40, растянутая на ширину линии; не влезли —
## шире, по флангам поровну (5.3).
static func _rank(slots: Array[Array], band: int, list: Array[Member], z: float, width: float, extra: float) -> void:
	var n := list.size()
	if n == 0:
		return
	var stp := 0.0
	if n > 1:
		var need := 0.0
		for i in range(1, n):
			need += list[i - 1].hull + list[i].hull + extra
		stp = maxf(need, width) / (n - 1)
	for i in n:
		slots.append([band, list[i].def.id, Vector2((float(i) - (n - 1) * 0.5) * stp, z)])


## Сколько лёгких влезает в ширину шагом hull + hull + extra (только откат --ecm-01L).
static func _fit(list: Array[Member], width: float, extra: float) -> int:
	var need := 0.0
	for i in list.size():
		if i > 0:
			need += list[i - 1].hull + list[i].hull + extra
			if need > width:
				return i
	return list.size()


## Места стороны на старте (09, 5.5): та же places() от линии старта ±deploy.heavy_z, ось —
## на противника; предел ширины — по чужой линии старта. → [id, Vector2(x, z)] по порядку
## расстановки. sign_z: +1 — атакующий (z > 0), −1 — защитник.
static func start_places(defs: Defs, clan: StringName, ids: Array[StringName], sign_z: float, foe_ids: Array[StringName] = [], foe_clan: StringName = &"", ecm_01l: bool = false) -> Array:
	var members := members_of(defs, clan, ids)
	var spec := Spec.new()
	spec.ecm_01l = ecm_01l
	spec.p = Vector2(0.0, sign_z * defs.doctrine.deploy_heavy_z)
	spec.ax = Vector2(0.0, -sign_z)
	spec.by_pos = false
	if not foe_ids.is_empty():
		var foe := members_of(defs, foe_clan, foe_ids)
		spec.foe_width = heavy_width(defs, foe)
		for m in foe:
			spec.foe_air = spec.foe_air or m.def.hangar > 0
	var o := places(defs, members, spec)
	var out: Array = []
	for i in members.size():
		out.append([members[i].def.id, o.at[i]])
	return out


static func members_of(defs: Defs, clan: StringName, ids: Array[StringName]) -> Array[Member]:
	var out: Array[Member] = []
	for id in ids:
		var s := defs.ship(clan, id)
		if s == null or s.station:
			continue
		var m := Member.new()
		m.def = s
		m.hull = hull_of(defs, s)
		m.key = float(out.size())
		out.append(m)
	return out


## Члены строя из кораблей боя: положение — нынешнее, порядок — прежнее место в полосе.
static func members_from(ships: Array[Ship]) -> Array[Member]:
	var out: Array[Member] = []
	for s in ships:
		var m := Member.new()
		m.def = s.def
		m.hull = s.hull
		m.pos = s.pos
		m.key = s.slot_order if s.has_slot else float(s.uid) * 1000.0
		out.append(m)
	return out


## Станция защитника — на deploy.station_back позади его линии старта (09, 5.5).
static func station_place(defs: Defs, sign_z: float) -> Vector2:
	return Vector2(0.0, sign_z * (defs.doctrine.deploy_heavy_z + defs.doctrine.deploy_station_back))


## Линия стороны (09, 5.1): центр её тяжёлых в строю — живых, без станции, не копящих
## гипер; тяжёлых нет — центр всех её кораблей (как F части 05, 2.7). ОДНА функция
## для авиации (G3: патруль, обход с фланга), доктрины тяжёлых (ось отхода) и строя.
class Line:
	var has := false             # у стороны есть хоть один корабль
	var heavy := false           # центр — по тяжёлым
	var center := Vector2.ZERO


static func line_of(ships: Array[Ship], side: int) -> Line:
	var out := Line.new()
	var sum := Vector2.ZERO
	var n := 0
	var all := Vector2.ZERO
	var m := 0
	for s in ships:
		if s.dead or s.side != side or s.station:
			continue
		all += s.pos
		m += 1
		if s.heavy() and not s.charging():
			sum += s.pos
			n += 1
	if n > 0:
		out.has = true
		out.heavy = true
		out.center = sum / float(n)
	elif m > 0:
		out.has = true
		out.center = all / float(m)
	return out


## Полуширина строя стороны поперёк оси (09, 4.4: «самая широкая из его шеренг и
## линии»): тяжёлые и лёгкие, без носителей и станции, — от центра линии вдоль lat.
static func half_width(ships: Array[Ship], side: int, center: Vector2, lat: Vector2) -> float:
	var w := 0.0
	for s in ships:
		if s.dead or s.side != side or s.station or s.def.hangar > 0:
			continue
		w = maxf(w, absf((s.pos - center).dot(lat)))
	return w


## Ширина линии тяжёлых стороны поперёк lat (для предела 5.3 «не шире чужой + 500»).
static func line_width(ships: Array[Ship], side: int, lat: Vector2) -> float:
	var lo := INF
	var hi := -INF
	for s in ships:
		if s.dead or s.side != side or s.station or not s.heavy() or s.charging():
			continue
		var x := s.pos.dot(lat)
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return hi - lo if hi >= lo else -1.0
