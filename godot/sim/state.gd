# sim/state.gd — состояние боя: поля, журналы, события и помощники, общие для всех
# модулей шага. sim/battle.gd наследует его и держит ТОЛЬКО порядок шага и создание
# боя (архитектура, 2.3–2.4); модули правил (weapons, ecm, ground_gun, vision) берут
# состояние отсюда. Так нет кольца preload: модули → state ← battle → модули
# (взаимный preload двух скриптов — кольцо зависимостей, godot/CLAUDE.md, 17).
#
# Модель — чистый GDScript (RefCounted), ни одного узла (архитектура, 1).
extends RefCounted

const Defs := preload("res://sim/defs.gd")
const Ship := preload("res://sim/ship.gd")
const Proj := preload("res://sim/proj.gd")
const Space := preload("res://sim/space.gd")
const Movement := preload("res://sim/movement.gd")
const Commands := preload("res://sim/commands.gd")
const Metrics := preload("res://sim/metrics.gd")

const STEP := 1.0 / 30.0


## Сторона боя: клан, знак оси, резерв, отход.
class SideState:
	var clan: StringName
	var sign_z: float               # +1 атакующий (z > 0), −1 защитник
	var reserve: Array[Defs.FleetEntry] = []
	var reinforce_at := 0.0         # > 0 — резерв вызван и выйдет в этот миг
	var retreat := false
	## ОТЛИЧИЕ: «сдалась» — у каждой стороны своё, а не одно на бой (вопрос 22 части 02):
	## в JS после ухода носителя ИИ уход носителя игрока уже не уводил его флот,
	## хотя правило C17 обещает обратное.
	var conceded := false
	var jumped: Array[StringName] = []
	var name_n: Dictionary[StringName, int] = {}
	## Множитель урона по сложности (space.js:309 aiMul): у игрока 1, у ИИ — aim
	## сложности. Главный калибр, батарея, лёгкие, ракетный пакет; НЕ ПВО и не планета.
	var aim := 1.0


## Поле помех РЭБ на этом шаге (space.js:552 updateEcm · часть 04, 2.16). Бой
## плоский (09, 11.6): поле — круг на плоскости, по высоте не ловит.
class Field:
	var pos := Vector2.ZERO
	var side := 0
	var mode: StringName = &"jam"   # &"jam" &"shield" &"off"
	var prof: Defs.EcmDef
	var src: Ship


## Орудие планеты (space.js:298 · часть 03, 2.17): бьёт АТАКУЮЩЕГО всегда (ловушка 28
## части 03), заводится ПОСЛЕ состояния боя (ловушка 29; 05, ловушка 40).
class GunState:
	var def: Defs.GroundGunDef
	var clan: StringName
	var side := 0                   # цель — атакующий (Ship.ATTACKER)
	var next := 0.0                 # время залпа
	var warned := false
	var has_aim := false
	var aim := Vector2.ZERO


var defs: Defs
var setup: Dictionary = {}
var build := ""
var battle_seed := 0
var rng: RandomNumberGenerator
var fx_rng: RandomNumberGenerator

var time := 0.0
var steps := 0
var ships: Array[Ship] = []
var projs: Array[Proj] = []
var sides: Array[SideState] = []
var player_side := Ship.ATTACKER
var over := false
var winner := -1                     # −1 — нет (или ничья)

## Поля помех ЭТОГО шага (sim/ecm.gd собирает их в начале шага).
var fields: Array[Field] = []
## Орудие планеты; null — его нет (в быстром бою есть всегда — у планеты защитника).
var gun: GunState
## ТОЛЬКО флажок отката 09, 8.4 «старые помехи» (план G2): главный калибр под чужим
## куполом бьёт лишь ближе lockRange, а не медленнее перезаряжается. Его замер
## проваливает М12 (G5); здесь — журнал причин «помехи». В игре false.
var old_ecm := false
## Лента «Наш … под помехами РЭБ» — одна на весь флот, не чаще раза в 25 с (space.js:2171).
var jam_feed_at := -99.0

## События ЭТОГО шага: вид забирает их после каждого шага (архитектура, 2.10).
## [&"spawn", uid], [&"hyper", uid], [&"unhyper", uid], [&"jump_out", uid],
## [&"jump_in", uid], [&"over", победитель]; оружие (sim/weapons.gd):
## [&"fire", кто, в кого, роль, установка] — мгновенный выстрел (main/light/sec);
## [&"charge", кто, установка, доля] — накачка главного калибра (картинка);
## [&"pd", кто, ствол, Vector2 цели, uid цели]; [&"proj", uid снаряда];
## [&"proj_hit", uid снаряда, Vector2]; [&"proj_end", uid снаряда, Vector2];
## [&"destroyed", uid, uid виновника или 0]; орудие планеты (sim/ground_gun.gd):
## [&"gun_warn", вид, Vector2 наводки, радиус, предупреждение с], [&"gun_fire", вид,
## Vector2 точки, PackedInt32Array задетых].
var events: Array[Array] = []
## Долгие журналы с игровым временем: лента и полоски их только показывают, тесты
## читают их, а не экран (часть 05, ловушка 38; часть 07, ловушка 42; 02, ловушка 30).
var feed_log: Array[Dictionary] = []
var toast_log: Array[Dictionary] = []

var cmds := Commands.new()
var space := Space.new()
var mp := Movement.Params.new()
var metrics := Metrics.new()
var _uid := 1


## Номер сущности боя: корабли и снаряды — из одного счётчика.
func next_uid() -> int:
	var u := _uid
	_uid += 1
	return u


func ship_by_uid(u: int) -> Ship:
	for s in ships:
		if s.uid == u:
			return s
	return null


func side_ships(side: int) -> Array[Ship]:
	var out: Array[Ship] = []
	for s in ships:
		if not s.dead and s.side == side:
			out.append(s)
	return out


func toast(text: String) -> void:
	toast_log.append({"t": time, "step": steps, "text": text})


func feed(text: String, kind: StringName) -> void:
	feed_log.append({"t": time, "step": steps, "text": text, "kind": kind})
