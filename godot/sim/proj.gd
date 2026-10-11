# sim/proj.gd — снаряд в полёте: ракета ракетного пакета «Синхо», ракета истребителя,
# торпеда бомбардировщика (space.js:531 spawnProjectile, 1673 updateProjectile ·
# часть 03, 2.11; часть 04, 2.8). Логика полёта — sim/weapons.gd (update_proj);
# здесь — поля. uid, side, pos, hp, armor, cls_i (класс «torpedo» — цель ПВО
# и перехватчиков), hit_r (1,8) — в sim/body.gd.
#
# Бой плоский (09, 11.6): положение и курс — Vector2(x, z). Покачивание ракет
# «Синхо» в JS шло только по высоте — это картинка, в модели его нет.
extends "res://sim/body.gd"

var owner: RefCounted            # кто пустил: корабль или машина (Body); урон — ему (07, ловушка 57)
var target: RefCounted           # своя цель (Body: корабль или машина); попасть можно ТОЛЬКО в неё (03, ловушка 23)
var key: StringName              # строка таблицы урона: &"missile" &"gunFig" &"torp"
var dmg: float                   # урон уже со сложностью пускавшего (03, 2.18)
var speed: float
var turn_k: float                # доворот к цели в секунду: 1,8, у торпеды 1,1
var life: float
var dir := Vector2(0.0, -1.0)
## Под чужим куполом головка слепнет НАВСЕГДА (03, ловушка 24) и снаряд идёт прямо.
var blind := false


func unlink() -> void:
	owner = null
	target = null
