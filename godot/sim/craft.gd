# sim/craft.gd — машина звена: перехватчик, истребитель, бомбардировщик (space.js:443
# launchSquadron, 1502 updateCraft · часть 04, 2.1, 2.4–2.9). Поля; логика — sim/air.gd
# (полёт и бой), sim/hangar.gd (пуск, посадка, гибель, звено). Машины — данные, а не
# узлы (часть 04, 5.2): их сотни, и вид рисует их одним MultiMesh на вид машины.
#
# Бой плоский (09, 11.6): положение, скорость и курс — на плоскости (x, z); высота
# — только картинка вида. uid, side, pos, vel, hp, armor, cls_i (strike), hit_r
# (2,6 — радиус попадания ракеты по машине) — в sim/body.gd.
extends "res://sim/body.gd"

const Defs := preload("res://sim/defs.gd")
const Fmath := preload("res://sim/fmath.gd")

var def: Defs.CraftDef
var role: StringName             # &"interceptor" &"fighter" &"bomber"
var squad: RefCounted            # своё звено (Squad); кольцо ссылок рвёт unlink()
var slot := 0                    # номер в звене: им разводятся траектории (04, 2.1)
var yaw := 0.0
var dir := Vector2(0.0, -1.0)
var _dir_at := NAN          # курс, для которого посчитан dir (как у Ship)

var cd := 0.0                    # перезарядка оружия: случайный старт 0…cd (04, 2.3)
var target: RefCounted           # Body: корабль, машина или ракета; «прилипает» (04, 2.6)
## Бомбардировщик: &"out" — заход на цель, &"break" — отворот после пуска (04, 2.7).
var phase: StringName = &"out"
var break_until := 0.0
var ammo := 0
var reloads := 0                 # запасные комплекты
var reloading := 0.0             # > 0 — перезарядка в космосе идёт (04, 2.9)
var leaving := false             # пустая машина без носителя уходит с поля (04, 2.10)
var leave_t := 0.0
var reveal_until := 0.0          # выстрел раскрывает на 5 с (03, ловушка 25)

## ДОКТРИНА 09, 4.4: бомбардировщик обходит строй с фланга. leg — сколько точек
## маршрута туда пройдено (0 — летит к точке 1, 1 — к точке 2, 2 — заход на цель);
## back — обратного пути (0 — к точке 2, 1 — к точке 1, 2 — к носителю).
var leg := 0
var back := 0


func set_yaw(a: float) -> void:
	yaw = a
	if a != _dir_at:
		dir = Fmath.nose(a)     # свои синус и косинус (sim/fmath.gd)
		_dir_at = a


func unlink() -> void:
	squad = null
	target = null
