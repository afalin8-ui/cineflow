# sim/ship.gd — корабль в бою: поля состояния и свойства ФУНКЦИЯМИ (архитектура,
# 2.8; доктрина 09, 10.3). В срезе каждая функция отдаёт число из определения;
# потом — «база × состояние узла»: выбитые двигатели будут резать thrust() и turn(),
# и тормозной путь обязан взять ту же thrust(), что разгон (ловушка 2 части 02;
# 09, 9.5 п. 4) — поэтому движение читает их только отсюда.
#
# Бой плоский (09, 11.6): положение и скорость — Vector2(x, z) плоскости боя,
# высота — только у вида. Нос — местная −Z (как в Godot и в JS): курс yaw — угол
# поворота вокруг вертикали, dir = (−sin yaw, −cos yaw) в осях (x, z).
extends RefCounted

const Defs := preload("res://sim/defs.gd")

## Стороны: 0 — атакующий (z > 0, знак +1), 1 — защитник (z < 0, знак −1).
const ATTACKER := 0
const DEFENDER := 1

var uid: int
var si := -1                 # номер в снимке шага (sim/space.gd); −1 — не в снимке
var side: int
var sign_z: float            # +1 у атакующего, −1 у защитника (space.js:289)
var def: Defs.ShipDef
var name: String             # с номером: «Рэш II» (ловушка 11 части 01)
var station: bool

var pos := Vector2.ZERO      # (x, z) плоскости боя
var vel := Vector2.ZERO
var yaw := 0.0               # курс носа; 0 — нос в −Z
var dir := Vector2(0.0, -1.0)
## Положение на прошлом шаге и шаг, на котором корабль появился или прыгнул:
## на этом шаге вид не смешивает прошлое с нынешним (архитектура, 3: телепорт).
var jumped_at_step := -1

var hp: float
var max_hp: float
var dead := false
var fled := false            # ушёл в гипер (а не погиб)

## Полуразмер корпуса — расталкивание и строй (C87): max(1,6 × radius, 0,36 × len),
## len — длина МОДЕЛИ (часть 01, 2.17; ловушка 6 части 01, 8 части 02).
var hull: float
var length: float

# ── приказы и тактика (часть 02, 2.8, 2.15) ──
var stance: StringName = &"guard"
var anchor := Vector2.ZERO   # участок «Охраны»
var has_move := false        # приказ «идти» (moveTo)
var move_to := Vector2.ZERO
var has_amove := false       # атака с ходу (amove) — пути к ней с G4
var amove := Vector2.ZERO
var group_speed := 0.0       # скорость строя приказа (C70); 0 — своя
var arrive_t := 0.0
var drift := false
var guard_of: RefCounted     # охраняемый корабль (Ship) — с G2/G6
var guard_off := Vector2.ZERO
var target: RefCounted       # цель (Ship) — с G2
var forced: RefCounted       # фокус огня — с G2

# ── гипер (часть 02, 2.17, 2.19) ──
var hyper_left := 0.0        # > 0 — копит переход
var hyper_total := 0.0
## Окно после выхода из гипера: скорость не режется до 1,25 × maxSpeed, пока не
## опустится сама, но не дольше hyper.exit_free_max_s (вопрос 1 части 02).
var exit_until := 0.0

# ── тяга для вида: ДВА числа (08, 7.2 п. 7) — тяжёлый пятится носом к врагу,
# и маршевый факел от реверса рисовал бы «газует вперёд, уезжая назад» ──
var thrust_fwd := 0.0        # доля тяги по носу (маршевые)
var thrust_rev := 0.0        # доля тяги против носа (реверс)

## Состояние двигателей (09, 10.4): 1 — целы. С повреждениями по узлам (после среза)
## — доля от выбитых; в срезе его трогает только проверка «двигатели × 0,5»: разгон
## и тормозной путь обязаны меняться вместе, потому что оба берут thrust().
var engine_k := 1.0

## Выключатели узлов со сроком (архитектура, 2.8; 09, 10.3): ион с планеты —
## «двигатели выключены на 10 с». Выбитый узел потом — тот же выключатель без срока.
var off_until: Dictionary[StringName, float] = {}


func charging() -> bool:
	return hyper_left > 0.0


## Узел выключен на момент now (ион, ЭМИ, ослепление — один вид).
func is_off(node: StringName, now: float) -> bool:
	var t: float = off_until.get(node, 0.0)
	return t > now


func switch_off(node: StringName, until: float) -> void:
	var t: float = off_until.get(node, 0.0)
	off_until[node] = maxf(t, until)


# ── свойства функциями (09, 10.3) ──

func thrust() -> float:
	return def.thrust * engine_k


func turn() -> float:
	return def.turn * engine_k


func max_speed() -> float:
	return def.max_speed


func hp_frac() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0


func armor_toward(_from_dir: Vector2) -> float:
	return def.armor


## Вооружён ли: «нечем бить» и безоружные приказы спрашивают это, а не длину
## списка орудий (09, 10.4). Ангар — с G3.
func can_hurt() -> bool:
	return def.main != null or def.sec != null or def.light != null or def.missile != null


## Урон — одна дверь с направлением (архитектура, 2.8; 09, 10.2). G2 наполнит её
## бронёй, учётом М7 и событиями; здесь — заготовка: прочность и гибель.
func damage(amount: float, _key: StringName, _source: RefCounted, from_dir: Vector2) -> float:
	if dead:
		return 0.0
	var got := amount * (1.0 - armor_toward(from_dir))
	hp -= got
	if hp <= 0.0:
		hp = 0.0
		dead = true
	return got


func set_yaw(a: float) -> void:
	yaw = a
	dir = Vector2(-sin(a), -cos(a))


## Курс «нос по направлению» (x, z).
static func yaw_of(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


## Разорвать ссылки на другие корабли: RefCounted не собирает кольца (архитектура, 2.12).
func unlink() -> void:
	guard_of = null
	target = null
	forced = null
