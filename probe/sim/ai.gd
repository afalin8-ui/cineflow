## ИИ одной стороны (проба). Свой объект на каждую сторону; тик по таймеру
## внутри шага модели; решения — по снимку начала шага (09, 4.5).
extends RefCounted

const Defs = preload("res://sim/defs.gd")

var side: int
var battle
var next_tick := 3.0
var ax := Vector3.FORWARD
var P := Vector3.ZERO
var p_init := false
var start := Vector3.ZERO
var patrol := Vector3.ZERO
var L := 663.0
# снимок начала шага
var s_foe_air := 0
var s_my_int := 0
var s_bomb_sq := 0
var s_foe_heavy := false

func snapshot() -> void:
	s_foe_air = 0; s_my_int = 0; s_bomb_sq = 0
	for c in battle.side_craft[1 - side]:
		if not c.dead: s_foe_air += 1
	for c in battle.side_craft[side]:
		if not c.dead and c.d.role == &"interceptor": s_my_int += 1
	for sq in battle.squads:
		if sq.side == side and not sq.dead and sq.role == &"bomber": s_bomb_sq += 1
	s_foe_heavy = false
	for s in battle.side_ships[1 - side]:
		if s.cls == Defs.CAPITAL or s.cls == Defs.CARRIER:
			s_foe_heavy = true
			break

func tick(_dt: float) -> void:
	if battle.time < next_tick:
		return
	next_tick = battle.time + battle.rng.randf_range(2.5, 4.0)
	var mine: Array = battle.side_ships[side]
	var foe: Array = battle.side_ships[1 - side]
	if mine.is_empty() or foe.is_empty():
		return
	var heavies: Array = []
	for s in mine:
		if s.d.main and s.hp >= 0.3 * s.max_hp:
			heavies.append(s)
	var fh := _center(foe.filter(func(s): return s.d.main != null))
	if fh == Vector3.INF:
		fh = _center(foe)
	var c := _center(heavies)
	if c == Vector3.INF:
		c = _center(mine)
	if not p_init:
		p_init = true
		P = c
		start = c
		ax = (fh - c).normalized()
	var ax_new := Vector3(fh.x - c.x, 0.0, fh.z - c.z).normalized()
	var ang := ax.signed_angle_to(ax_new, Vector3.UP)
	var lim := deg_to_rad(battle.doc["line"]["turn_max_deg"])
	ax = ax.rotated(Vector3.UP, clampf(ang, -lim, lim)).normalized()
	var r_line := 780.0
	if not heavies.is_empty():
		r_line = INF
		for s in heavies:
			r_line = minf(r_line, s.d.main.rng)
	L = battle.doc["line"]["L_k"] * r_line
	var pt := fh - ax * L
	var mv := pt - P
	var shift_max: float = battle.doc["line"]["shift_max"]
	if mv.length() > shift_max:
		mv = mv.normalized() * shift_max
	P += mv
	var back := (P - start).dot(ax)
	if back < -battle.doc["line"]["rear"]:
		P += ax * (-battle.doc["line"]["rear"] - back)
	var lat := Vector3(-ax.z, 0.0, ax.x)
	_lane(heavies, P, lat, 60.0)
	var fr: Array = []
	var cv: Array = []
	var cr: Array = []
	for s in mine:
		if s.d.main and s.hp < 0.3 * s.max_hp:
			s.anchor = P - ax * 120.0
		elif s.d.id == &"frigate" or s.d.id == &"ecm":
			fr.append(s)
		elif s.d.id == &"corvette":
			cv.append(s)
		elif s.d.hangar > 0:
			cr.append(s)
	_lane(fr, P + ax * (0.2 * L), lat, 40.0)
	_lane(cv, P + ax * (0.35 * L), lat, 40.0)
	_lane(cr, P - ax * 440.0, lat, 190.0)
	patrol = P + ax * (battle.doc["air"]["patrol_k"] * L)
	for s in cr:
		while s.hangar_free > 0:
			battle.launch_squad(s, _air_role(s))

## Места в полосе — по нынешнему положению вдоль lat, а не по номеру (09, 5.4).
func _lane(list: Array, at: Vector3, lat: Vector3, gap: float) -> void:
	if list.is_empty():
		return
	list.sort_custom(func(a, b): return a.pos.dot(lat) < b.pos.dot(lat))
	var width := 0.0
	for i in list.size():
		if i > 0:
			width += list[i - 1].d.hull + list[i].d.hull + gap
	var x := -width * 0.5
	for i in list.size():
		if i > 0:
			x += list[i - 1].d.hull + list[i].d.hull + gap
		list[i].anchor = at + lat * x

func _air_role(home) -> StringName:
	if s_foe_air > s_my_int + 2:
		s_my_int += 6
		return &"interceptor"
	if s_foe_heavy and s_bomb_sq < maxi(1, home.d.hangar / 2):
		s_bomb_sq += 1
		return &"bomber"
	return &"fighter"

func _center(list: Array) -> Vector3:
	if list.is_empty():
		return Vector3.INF
	var acc := Vector3.ZERO
	for s in list:
		acc += s.pos
	return acc / list.size()
