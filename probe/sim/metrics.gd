## Замер читаемости (09, раздел 8) — подписчик модели, без узлов.
extends RefCounted

const Defs = preload("res://sim/defs.gd")

var first_hit := -1.0
var first_main := -1.0
var belt_t := 0.0          # М1: тяжёлый-секунды в поясе
var close_t := 0.0         # М2: тяжёлый-секунды «вплотную»
var heavy_t := 0.0
var retreat_t := 0.0       # М6
var l_samples := PackedFloat32Array()   # М3
var light_between := 0.0   # М4
var light_t := 0.0
var dmg_by_key := {}       # М7: урон по КОРАБЛЯМ по ключу оружия
var dmg_other := 0.0       # по машинам и снарядам
var squads_up := [0, 0]
var _l_clock := 0.0

func on_damage(b, t, dealt: float, key: StringName, src) -> void:
	if dealt <= 0.0:
		return
	if first_hit < 0.0 and t.kind == 0:
		first_hit = b.time
	if t.kind == 0:
		dmg_by_key[key] = dmg_by_key.get(key, 0.0) + dealt
		if key == &"heavy" and first_main < 0.0:
			first_main = b.time
	else:
		dmg_other += dealt

func sample(b, dt: float) -> void:
	if first_main < 0.0:
		return                                  # фаза «марш» не в счёт
	var centers := [Vector3.ZERO, Vector3.ZERO]
	var n := [0, 0]
	for side in 2:
		var foe: Array = b.side_ships[1 - side]
		for s in b.side_ships[side]:
			if s.dead:
				continue
			if s.d.main and s.d.max_speed > 0.0:
				heavy_t += dt
				var t = s.main_t
				if t != null and not t.dead:
					var dd: float = s.pos.distance_to(t.pos)
					if dd >= s.d.main.dead and dd <= s.d.main.rng:
						belt_t += dt
				if b.sp_near_d[s.sp_i] < s.d.main.dead:
					close_t += dt
				if s.state == 2:
					retreat_t += dt
				if s.hp >= 0.3 * s.max_hp:
					centers[side] += s.pos
					n[side] += 1
	_l_clock += dt
	if _l_clock >= 0.5 and n[0] > 0 and n[1] > 0:
		_l_clock = 0.0
		l_samples.append((centers[0] / n[0]).distance_to(centers[1] / n[1]))
	# М4 — лёгкие между линиями
	for side in 2:
		var ai = b.ai[side]
		for s in b.side_ships[side]:
			if s.d.light == null or s.dead:
				continue
			light_t += dt
			var p: float = (s.pos - ai.P).dot(ai.ax)
			if p >= 0.0 and p <= ai.L:
				light_between += dt

func report() -> Dictionary:
	var total := 0.0
	for k in dmg_by_key:
		total += dmg_by_key[k]
	var share := {}
	for k in dmg_by_key:
		share[k] = snappedf(dmg_by_key[k] / maxf(total, 1.0), 0.001)
	var ls := l_samples.duplicate()
	ls.sort()
	return {
		"first_hit": snappedf(first_hit, 0.1),
		"first_main": snappedf(first_main, 0.1),
		"M1_belt": snappedf(belt_t / maxf(heavy_t, 0.001), 0.001),
		"M2_close": snappedf(close_t / maxf(heavy_t, 0.001), 0.001),
		"M3_L_median": ls[ls.size() / 2] if ls.size() > 0 else -1.0,
		"M4_light_between": snappedf(light_between / maxf(light_t, 0.001), 0.001),
		"M6_retreat": snappedf(retreat_t / maxf(heavy_t, 0.001), 0.001),
		"M7_share": share,
		"squads_up": squads_up,
	}
