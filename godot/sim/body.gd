# sim/body.gd — общее у всего, во что целятся и что принимает урон: корабль
# (sim/ship.gd), машина звена (sim/craft.gd), ракета или торпеда (sim/proj.gd).
# С G3 целью бывает не только корабль: ПВО бьёт машины, перехватчик — машины и ракеты,
# ракета истребителя — машину, лёгкий корабль по приказу на звено — его машины
# (часть 04, 2.12). Одна дверь урона (sim/weapons.gd → damage) берёт Body, и звено
# (sim/squad.gd) — НЕ Body: у звена нет прочности, урон «по звену» отбрасывается
# по устройству (C14; 04, ловушка 1).
#
# Бой плоский (09, 11.6): положение и скорость — Vector2(x, z) плоскости боя.
extends RefCounted

## Что это за тело — для вида и учёта (проверки типа `as` дороже числа).
const SHIP := 0
const CRAFT := 1
const PROJ := 2

var uid: int
var kind := SHIP
var side: int
var pos := Vector2.ZERO          # (x, z) плоскости боя
var vel := Vector2.ZERO
var dead := false
var hp: float
var max_hp: float
var armor := 0.0
## Столбец таблицы урона (Defs.CLASSES): у машины — strike, у снаряда — torpedo.
var cls_i := 0
## Радиус попадания снаряда — радиус КЛАССА, а не габарит модели (01, ловушка 8):
## корабль — radius класса, машина — 2,6, снаряд — 1,8 (space.js:449, 539).
var hit_r := 8.0
## Шаг появления или прыжка: на нём вид не смешивает прошлое с нынешним (архитектура, 3).
var jumped_at_step := -1


## Броня со стороны удара (09, 10.2): у машины и снаряда — одно число.
func armor_toward(_from_dir: Vector2) -> float:
	return armor


func hp_frac() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0
