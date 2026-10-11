# sim/proj.gd — снаряд в полёте: ракета ракетного пакета «Синхо», ракета истребителя,
# торпеда бомбардировщика (space.js:531 spawnProjectile, 1673 updateProjectile ·
# часть 03, 2.11). Логика полёта — sim/weapons.gd (update_proj); здесь — поля.
#
# Бой плоский (09, 11.6): положение и курс — Vector2(x, z). Покачивание ракет
# «Синхо» в JS шло только по высоте — это картинка, в модели его нет.
extends RefCounted

var uid: int
var side: int
var owner: RefCounted            # кто пустил (Ship; с G3 — и машина): урон — ему (07, ловушка 57)
var target: RefCounted           # своя цель (Ship); попасть можно ТОЛЬКО в неё (03, ловушка 23)
var key: StringName              # строка таблицы урона: &"missile" &"gunFig" &"torp"
var dmg: float                   # урон уже со сложностью пускавшего (03, 2.18)
var speed: float
var turn_k: float                # доворот к цели в секунду: 1,8, у торпеды 1,1
var hp: float
var max_hp: float
var armor := 0.0
var cls_i: int                   # класс цели «torpedo» — для ПВО и перехватчиков
var radius := 1.8
var life: float
var pos := Vector2.ZERO
var dir := Vector2(0.0, -1.0)
## Под чужим куполом головка слепнет НАВСЕГДА (03, ловушка 24) и снаряд идёт прямо.
var blind := false
var dead := false
## Шаг появления: на нём вид не смешивает прошлое с нынешним (архитектура, 3).
var jumped_at_step := -1


func armor_toward(_from_dir: Vector2) -> float:
	return armor


func hp_frac() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0


func unlink() -> void:
	owner = null
	target = null
