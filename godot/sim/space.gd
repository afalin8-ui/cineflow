# sim/space.gd — упакованный снимок НАЧАЛА шага и проход пар (архитектура, 2.5).
# Замер: расталкивание объектами каждый с каждым 828 мкс, упакованными массивами
# пар 82 мкс — парные расчёты на объекты не возвращать (godot/CLAUDE.md, 3).
#
# space.js:1309 updateShip (расталкивание) · часть 02, 2.10.
# ОТЛИЧИЕ: в JS каждый корабль видел уже сдвинутых соседей (обход по порядку
# массива); здесь — положения начала шага. Разница — доля шага (≈2 ед. при 60 ед/с);
# эталоны наложений из JS перемеряются (godot/CLAUDE.md, 2).
extends RefCounted

const Ship := preload("res://sim/ship.gd")

## Чужому — больше места и сильнее толчок (C87, C59; space.js:1312–1315).
const FOE_ROOM := 1.15
const FOE_PUSH := 1.1
const OWN_PUSH := 0.8

var n := 0
var ships: Array[Ship] = []          # живые по порядку боя; ships[i].si == i
var pos := PackedVector2Array()
var hull := PackedFloat64Array()
var side := PackedInt32Array()
var vmax := PackedFloat64Array()
## Толчок расталкивания каждому — прибавка к желаемой скорости (через двигатель).
var push := PackedVector2Array()
## Ближайший чужой корабль (индекс в снимке; −1 — нет) и квадрат расстояния до него.
var near := PackedInt32Array()
var near_d2 := PackedFloat64Array()


## Собрать снимок живых и один проход пар i < j.
func rebuild(all: Array[Ship]) -> void:
	ships.clear()
	for s in all:
		if not s.dead:
			s.si = ships.size()
			ships.append(s)
		else:
			s.si = -1
	n = ships.size()
	pos.resize(n)
	hull.resize(n)
	side.resize(n)
	vmax.resize(n)
	push.resize(n)
	near.resize(n)
	near_d2.resize(n)
	for i in n:
		var s := ships[i]
		pos[i] = s.pos
		hull[i] = s.hull
		side[i] = s.side
		vmax[i] = s.max_speed()
		push[i] = Vector2.ZERO
		near[i] = -1
		near_d2[i] = INF
	_pairs()


## Проход пар (архитектура, 2.5). Без лямбд, словарей и чужих полей в цикле.
func _pairs() -> void:
	for i in n:
		var pi := pos[i]
		var hi := hull[i]
		var si := side[i]
		for j in range(i + 1, n):
			var off := pi - pos[j]
			var d2 := off.x * off.x + off.y * off.y
			var foe := side[j] != si
			if foe:
				if d2 < near_d2[i]:
					near_d2[i] = d2
					near[i] = j
				if d2 < near_d2[j]:
					near_d2[j] = d2
					near[j] = i
			var mn := (hull[j] + hi) * (FOE_ROOM if foe else 1.0)
			# space.js:1313: dd < min && dd > 0.01
			if d2 < mn * mn and d2 > 0.0001:
				var dd := sqrt(d2)
				var k := (mn - dd) / mn / dd * (FOE_PUSH if foe else OWN_PUSH)
				push[i] += off * (k * vmax[i])
				push[j] -= off * (k * vmax[j])


## Расстояние по плоскости боя — одна функция на весь бой (архитектура, 2.3).
static func battle_dist(a: Ship, b: Ship) -> float:
	return a.pos.distance_to(b.pos)


## Сколько пар «свой в чужом» ближе (hull + hull) × k — признак клубка (М9 с G4).
func foe_overlaps(k: float) -> int:
	var c := 0
	for i in n:
		for j in range(i + 1, n):
			if side[i] != side[j]:
				var mn := (hull[i] + hull[j]) * k
				if pos[i].distance_squared_to(pos[j]) < mn * mn:
					c += 1
	return c
