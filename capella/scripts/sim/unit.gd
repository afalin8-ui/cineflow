class_name Unit
extends RefCounted
## Один юнит боя: корабль, звено, станция или харвестер.
## Звено — один юнит, его число машин считается от общего запаса прочности.

var id := 0
var team := 0
var def: Dictionary
var cls := ""
var fac := ""

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var heading := 0.0          # радианы, 0 = +x
var height := 0.0           # лёгкий разброс по высоте, только для вида

var hull := 0.0
var hull_max := 0.0
var shield := 0.0
var shield_max := 0.0
var shield_delay := 0.0
var hps := []               # [{id, kind, max, hp, label}]
var weapons := []           # копии из def + {t: перезарядка}
var alive := true

# Звено
var craft_hp := 0.0
var squad_n := 1
var home = null             # носитель / станция
var linked := true          # связь с носителем (РЭБ рвёт)
var jam := 0.0              # секунд глушения

# Приказы
var order := "idle"         # idle, move, attack, amove, retreat, harvest, guard
var order_pos := Vector2.ZERO
var target = null
var target_hp := ""
var player_ordered := false

# Отступление
var charge := 0.0           # >0 — заряжается гиперпрыжок
var in_hyper := 0.0         # >0 — в гиперпространстве

# Способности
var abil_cd := {}
var abil_on := {}           # id -> секунд осталось
var siege := false

# Носитель
var squads := []            # свои звенья в полёте
var bay_queue := []         # [{type, t}] звенья на восстановлении
var bays_bought := 0        # сколько звеньев «в лимите» сверх стартовых

# Харвестер
var cargo := 0.0
var field = null
var h_state := "go"

# Станция
var level := 1
var build_queue := []       # [{id, t}]
var upgrading := 0.0

# Статистика / вспомогательное
var last_hit_by := -1
var built_at := 0.0
var spoofed_t := 0.0
var want := Vector2.ZERO   # желаемая скорость (решает поведение)
var face = null            # точка, куда смотреть носом
var cur = null             # текущая цель звена
var docked := false
var prev_pos := Vector2.ZERO
var prev_heading := 0.0

func setup(d: Dictionary, t: int, p: Vector2) -> void:
	def = d
	cls = d.cls
	fac = d.fac
	team = t
	pos = p
	if Defs.is_squad(cls):
		craft_hp = d.hull
		squad_n = d.squad_n
		hull_max = d.hull * d.squad_n
	else:
		hull_max = d.hull
	hull = hull_max
	shield_max = d.shield
	shield = shield_max
	for h in d.hps:
		var c: Dictionary = h.duplicate()
		c.hp = c.max
		hps.append(c)
	for wd in d.weapons:
		var c2: Dictionary = wd.duplicate()
		c2.t = randf() * c2.cd
		weapons.append(c2)
	for a in d.abil:
		abil_cd[a] = 0.0

func is_squad() -> bool:
	return Defs.is_squad(cls)

func is_big() -> bool:
	return Defs.is_big(cls)

func is_station() -> bool:
	return cls == "station"

func target_class() -> int:
	return Defs.CLS_TARGET[cls]

func radius() -> float:
	if is_squad():
		return 60.0
	return def.size * 0.45

func craft_alive() -> int:
	if not is_squad():
		return 1
	return int(ceil(hull / craft_hp))

func hp_alive(kind: String) -> bool:
	# Есть ли хоть один живой хардпоинт этого вида (или вида нет вовсе — тогда «работает»).
	var has := false
	for h in hps:
		if h.kind == kind:
			has = true
			if h.hp > 0:
				return true
	return not has

func hp_by_id(hid: String):
	for h in hps:
		if h.id == hid:
			return h
	return null

func weapon_ok(wp: Dictionary) -> bool:
	if wp.hp == "":
		return true
	var h = hp_by_id(wp.hp)
	return h == null or h.hp > 0

func speed() -> float:
	var s: float = def.speed
	if not hp_alive("engine"):
		s *= 0.3
	if abil_on.get("boost", 0.0) > 0 or abil_on.get("dash", 0.0) > 0:
		s *= 1.8
	if abil_on.get("engine_power", 0.0) > 0:
		s *= 1.8
	if abil_on.get("ram", 0.0) > 0:
		s *= 2.2
	if siege:
		s = 0.0
	return s

func shield_works() -> bool:
	return shield_max > 0 and hp_alive("shieldgen")

func points() -> int:
	return def.pts
