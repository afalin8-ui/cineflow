# sim/ship.gd — корабль в бою: поля состояния и свойства ФУНКЦИЯМИ (архитектура,
# 2.8; доктрина 09, 10.3). В срезе каждая функция отдаёт число из определения;
# потом — «база × состояние узла»: выбитые двигатели будут резать thrust() и turn(),
# и тормозной путь обязан взять ту же thrust(), что разгон (ловушка 2 части 02;
# 09, 9.5 п. 4) — поэтому движение читает их только отсюда.
#
# Бой плоский (09, 11.6): положение и скорость — Vector2(x, z) плоскости боя,
# высота — только у вида. Нос — местная −Z (как в Godot и в JS): курс yaw — угол
# поворота вокруг вертикали, dir = (−sin yaw, −cos yaw) в осях (x, z).
extends "res://sim/body.gd"

const Defs := preload("res://sim/defs.gd")
const Squad := preload("res://sim/squad.gd")

## Стороны: 0 — атакующий (z > 0, знак +1), 1 — защитник (z < 0, знак −1).
const ATTACKER := 0
const DEFENDER := 1

# uid, side, pos, vel, dead, hp, max_hp, hit_r, cls_i, jumped_at_step — в sim/body.gd
var si := -1                 # номер в снимке шага (sim/space.gd); −1 — не в снимке
var sign_z: float            # +1 у атакующего, −1 у защитника (space.js:289)
var def: Defs.ShipDef
var name: String             # с номером: «Рэш II» (ловушка 11 части 01)
var station: bool

var yaw := 0.0               # курс носа; 0 — нос в −Z
var dir := Vector2(0.0, -1.0)

var fled := false            # ушёл в гипер (а не погиб)
var flee_told := false       # лента «копит гипер — добить» уже сказала (05, 2.16: раз на корабль)

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
var guard_of: RefCounted     # охраняемый корабль (Ship): ПКМ точно в корпус своего (03, 2.16)
var guard_off := Vector2.ZERO
## Атака с ходу у тяжёлого: сколько секунд без встречи (09, 6.5 — марш дальше через
## amove.resume_s без цели, и если путь чист). Ставится приказом в resume_s: идёт сразу.
var amove_quiet := 0.0
## Поводок «Охраны» по заданию строя (0 — обычный: у тяжёлых 0,5 R, у лёгких 240):
## фрегаты стороны под заглушкой строя (ИИ) — leash.frigate_ai = 100 (09, 3.1).
var leash_set := 0.0

# ── доктрина тяжёлых (09, раздел 2; sim/heavy_doctrine.gd) ──
## Состояние пояса — явным значением (архитектура, 2.7): HeavyDoctrine.MOVE…FUTILE.
## Смена пишется в журнал боя (belt_log): по нему строится строка «чем занят» и М6.
var belt := 0
## Атака с ходу: встреча была (09, 6.5) — после неё марш дальше только через resume_s.
## «Не оторваться» (09, 2.6): от кого отходим, часы окна (идут только на ходу «от врага»),
## выигрыш расстояния за окно, прошлое расстояние.
var ret_foe: RefCounted
var ret_clock := 0.0
var ret_gain := 0.0
var ret_prev := 0.0
var ret_hist := PackedFloat64Array()   # [часы хода, расстояние] — скользящее окно (2.6)
## «Не повод отходить» — помнится ПО ВРАГУ (09, 9.5 п. 13): uid → когда сработало.
var futile: Dictionary[int, float] = {}
## Флажок отката --legacy-approach (09, 8.4): этот корабль — по-старому (тяжёлый на 0,68,
## без мёртвой зоны и самоотхода). В игре false.
var legacy := false
## Место в строю от заглушки строя (09, 5.1; М10): есть ли оно и где.
var has_slot := false
var slot := Vector2.ZERO
var slot_order := 0.0             # порядок в полосе — места переназначаются по составу (5.4)
var slot_band := -1               # полоса строя (Formation.HEAVY…): зонт носителя — не «лёгкая линия» (М4)

# ── цели по ролям оружия (09, 1.1; 03, 2.7–2.9; ловушка 1 09, 9.5: не guns[0]) ──
## Цель главного калибра у тяжёлого (Ship), лёгкого орудия — у лёгкого: корабль или,
## по приказу на звено, его машина (Craft; C14, 04, 2.12) — поэтому тип общий (Body).
var target: RefCounted
## Фокус огня: корабль (Ship) или звено (Squad, только у лёгких — 09, 4.6); сильнее
## тактики, тактику не стирает (03, ловушка 16).
var forced: RefCounted
var sec_target: RefCounted   # цель батареи (Ship): фокус в её дальности, иначе ближайший
var mis_target: RefCounted   # цель ракетного пакета «Синхо» (09, 1.6)
var retarget := 0.0          # пересмотр цели раз в 0,8–1,6 с (space.js:1244)
## Профиль помех над кораблём на этом шаге (null — помех нет); только у вооружённых
## (space.js:1236). ПВО спрашивает помехи сам — штраф и у безоружных (04, 2.17).
var jam: RefCounted          # Defs.EcmDef
var jam_shot: RefCounted     # цель «под помехами» — временная (03, ловушка 7); только у лёгких
## Почему готовый главный калибр молчит на этом шаге (&"" — выстрелил или не готов);
## строка «чем занят» и журнал причин (03, 7.5).
var idle_reason: StringName = &""

# ── оружие: таймер на установку (ствол), старт случайный (space.js:337) ──
var main_cd := PackedFloat64Array()
var sec_cd := PackedFloat64Array()
var light_cd := PackedFloat64Array()
var mis_cd := PackedFloat64Array()
var pd_cd := PackedFloat64Array()
var dealt := 0.0             # итоги боя: нанесённый урон и добитые (03, 2.5)
var kills := 0
var alarm_at := -99.0        # тревога «под огнём» (03, 2.5 underFire)

# ── скрытность (03, 2.6; sim/vision.gd): в срезе всех видно, но выстрел раскрывает
# уже сейчас (ловушка 25 части 03) — и где видели в последний раз пишется ──
var stealth := false
var reveal_until := 0.0
var seen_pos := Vector2.ZERO
var seen_at := 0.0

# ── РЭБ (04, 2.16): режим и мощность купола; только у корабля с излучателем ──
var ecm_mode: StringName = &"jam"
var ecm_power := 0.0

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

## Ангар носителя и станции (04, 2.2): места, постройка, поднятые звенья; null — нет.
## Отдельной частью корабля, а не флагами (04, 7.4: потом выбитый ангар — меньше bays).
var hangar: Squad.Hangar

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


func armor_toward(_from_dir: Vector2) -> float:
	return def.armor


## Вооружён ли: безоружные приказы спрашивают это, а не длину списка орудий (09, 10.4).
## Ангар оружием корабля не считается: носитель приказ «атаковать» не принимает (C100);
## «нечем бить» стороны (G5) спросит ангар отдельно (04, 2.15).
func can_hurt() -> bool:
	return def.main != null or def.sec != null or def.light != null or def.missile != null


## Вооружён главным калибром — «тяжёлый» для правил доктрины (09, 1.1: роль, а не класс).
func heavy() -> bool:
	return def.main != null


## Дальность «своего» оружия: главный калибр у тяжёлого, лёгкое орудие у лёгкого;
## безоружный — 0 (09, 1.1: всё, что брало «дальность первого орудия», берёт её по роли).
func range0() -> float:
	if def.main != null:
		return def.main.rng
	if def.light != null:
		return def.light.rng
	return 0.0


## Урон — одна дверь: sim/weapons.gd → damage(…, from_dir) (бронь armor_toward,
## учёт М7, события). Ship хранит только состояние.


func set_yaw(a: float) -> void:
	yaw = a
	dir = Vector2(-sin(a), -cos(a))


## Курс «нос по направлению» (x, z).
static func yaw_of(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


## Разорвать ссылки на другие корабли: RefCounted не собирает кольца (архитектура, 2.12).
func unlink() -> void:
	ret_foe = null
	guard_of = null
	target = null
	forced = null
	sec_target = null
	mis_target = null
	jam = null
	jam_shot = null
