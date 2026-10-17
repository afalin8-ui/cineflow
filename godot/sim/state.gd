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
const Body := preload("res://sim/body.gd")
const Craft := preload("res://sim/craft.gd")
const Squad := preload("res://sim/squad.gd")
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
	## сложности. Главный калибр, батарея, лёгкие, ракетный пакет, пушки перехватчика;
	## НЕ ПВО, не планета и не ракеты машин (04, 2.8).
	var aim := 1.0
	## Звенья: поднято и потеряно (не севших) — итоги и М8 (04, 2.11; 09, 4.7).
	var sq_up := 0
	var sq_lost := 0
	## Ось стороны на ЭТОМ шаге (09, 5.1): от центра своей линии тяжёлых к центру чужой
	## (F_h, нет — F). Отход вперёд по ней не ведёт (2.6). Считается в начале шага.
	var ax := Vector2.ZERO
	var line := Vector2.ZERO        # центр своей линии (тяжёлых в строю; нет — всех)
	var has_line := false           # у стороны есть линия тяжёлых в строю
	## ИИ стороны (sim/ai.gd; 09, раздел 7): ведёт ли он её, целиком или только строем
	## (шаги 6–7 — лаборатория «Бой линий»), место линии P и ось, когда думает в следующий
	## раз. Тыловой рубеж — линия старта плюс line.rear вглубь, по оси стороны (09, 2.6):
	## его не двигает ничто.
	var ai_on := false
	var ai_full := false
	var line_set := false
	var line_p := Vector2.ZERO
	var line_ax := Vector2.ZERO
	var ai_next := 0.0
	var roster := ""
	var had_heavy := false          # в линии стороны были тяжёлые (05, 2.6 п. 7 — «без тяжёлых — уход»)
	## Пары своих мест ближе hull + hull (uid, uid, …) — считаются, когда ИИ раздаёт места,
	## а не каждый шаг (М10, 9.5 п. 20; замечание к G4 о переборе пар объектами).
	var slot_clash := PackedInt32Array()
	var rear_z := INF               # |z| своей стороны не дальше (у стороны под ИИ)
	## «Нечем бить» (05, 2.12): когда заметили (−1 — есть чем).
	var teeth := -1.0


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
## Машины в воздухе (по порядку пуска) и звенья (04, 2.1). Мёртвые уходят из списков
## в конце шага (sim/hangar.gd → tick).
var crafts: Array[Craft] = []
var squads: Array[Squad] = []
var sides: Array[SideState] = []
var player_side := Ship.ATTACKER
var over := false
var winner := -1                     # −1 — нет (или ничья)
## Итог для стороны игрока (05, 2.13): &"victory" «Орбита за нами», &"retreat» «Отход»,
## &"defeat" «Флот разбит», &"draw" — ничья «ИИ против ИИ» (обе стороны ушли на одном шаге;
## план, раздел 1); &"limit" — предел времени стенда (900 с). Пусто — бой идёт.
var result: StringName = &""
## Снимок итога (05, 2.13; C65, C15, C16): уцелевшие сторон по id — живые не-станции
## (копящие гипер тоже), ушедшие в гипер и невышедший резерв. Снимается В МОМЕНТ итога.
var outcome: Dictionary = {}
## «ИИ против ИИ»: у обеих сторон ИИ, человек только смотрит (приказов нет).
var watch := false
## ТОЛЬКО для проверки отката (замечание к G5): «ИИ против ИИ» говорит с места атакующего —
## «Потерян наш …», «Противник отходит… (T)», «Подкрепление выйдет из гипера…» без клана.
static var rollback_watch_voice := false

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
## ТОЛЬКО флажки отката 09, 8.4 (ключи состава боя, запись их помнит; в игре false):
## «заход бомбардировщиков прямо на цель» (`--bomber-direct`) — без обхода с фланга
## (09, 4.4); «патруль перехватчиков над серединой» (`--patrol-mid`) — на 0,5 отрезка
## между линиями вместо air.patrol_k (09, 4.2). Их замеры — М7, М8 (стенд G5) и
## проверки G3 (tests/test_sim_air.gd).
var bomber_direct := false
var patrol_mid := false
## Флажки отката доктрины тяжёлых и строя 09, 8.4 (план G4; ключи состава боя):
## «старый подход» (тяжёлые на 0,68, без мёртвой зоны и самоотхода) — `--legacy-approach`;
## «подход без доли сближения» — `--no-share-close`; «подход без торможения у чужих» —
## `--no-foe-brake`; «путь чист 0,55 R» — `--clear-055`; «РЭБ на 0,1 L и вторая лёгкая
## шеренга позади» — `--ecm-01L`. Каждый проваливает свой замер стенда (tools/bench_core.gd).
var legacy_approach := false
## «Старый ИИ» (`--old-ai`, 09, 8.4): кольцо охранения, тяжёлые на «Охоте» — М3, М4, М10;
## «старое ПВО» (`--old-pd`): ПВО по торпедам 1,4 и торпеда 88 (was записей space_dmg.pd_torpedo
## и torp.speed) — М7 (доля авиации), М8. Ключи состава боя, в игре false.
var old_ai := false
var old_pd := false
var no_share_close := false
var no_foe_brake := false
var clear_055 := false
var ecm_01l := false
## Журнал смен состояния пояса тяжёлых (архитектура, 2.7; 09, 8.4 — первый шаг поиска
## ошибки доктрины): [время, uid, было, стало].
var belt_log: Array[Array] = []
## Геометрия строя для авиации на ЭТОМ шаге (sim/air.gd → prepare): центры линий
## тяжёлых, ось, полуширина строя. Считается один раз на шаг, до машин.
var air_geo: Array = []
## Сценарий «Полигона» до ИИ (G5): противник поднимает звенья по кругу ролей
## (setup "foe_air"); [роли, период, первый пуск]. Пусто — нет.
var foe_air_roles: Array[StringName] = []
var foe_air_every := 0.0
var foe_air_next := 0.0
var foe_air_i := 0

## События ЭТОГО шага: вид забирает их после каждого шага (архитектура, 2.10).
## [&"spawn", uid], [&"hyper", uid], [&"unhyper", uid], [&"jump_out", uid],
## [&"jump_in", uid], [&"over", победитель]; оружие (sim/weapons.gd):
## [&"fire", кто, в кого, роль, установка, Vector2 цели] — мгновенный выстрел
## (main/light/sec); место цели — в самом событии: цель, сбитая этим выстрелом, к виду уже
## не доходит (машину убирает Hangar.tick в конце шага, замечание к G3);
## [&"charge", кто, установка, доля] — накачка главного калибра (картинка);
## [&"pd", кто, ствол, Vector2 цели, uid цели]; [&"proj", uid снаряда];
## [&"proj_hit", uid снаряда, Vector2]; [&"proj_end", uid снаряда, Vector2];
## [&"destroyed", uid, uid виновника или 0]; орудие планеты (sim/ground_gun.gd):
## [&"gun_warn", вид, Vector2 наводки, радиус, предупреждение с], [&"gun_fire", вид,
## Vector2 точки, PackedInt32Array задетых]; авиация (sim/hangar.gd, sim/air.gd, G3):
## [&"launch", uid звена], [&"craft_dead", uid машины, Vector2], [&"craft_gone",
## uid машины] (села или ушла с поля), [&"craft_fire", uid машины, uid цели, Vector2
## цели] — очередь перехватчика (место цели — по той же причине, что у «fire»),
## [&"reload", uid машины] — новый комплект ракет.
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


## Номер сущности боя: корабли, звенья, машины и снаряды — из одного счётчика.
func next_uid() -> int:
	var u := _uid
	_uid += 1
	return u


func ship_by_uid(u: int) -> Ship:
	for s in ships:
		if s.uid == u:
			return s
	return null


func squad_by_uid(u: int) -> Squad:
	for q in squads:
		if q.uid == u:
			return q
	return null


func craft_by_uid(u: int) -> Craft:
	for c in crafts:
		if c.uid == u:
			return c
	return null


## Всё, во что целятся, по номеру: корабль, машина или снаряд (null — нет).
func body_by_uid(u: int) -> Body:
	var s := ship_by_uid(u)
	if s != null:
		return s
	var c := craft_by_uid(u)
	if c != null:
		return c
	for p in projs:
		if p.uid == u:
			return p
	return null


func side_ships(side: int) -> Array[Ship]:
	var out: Array[Ship] = []
	for s in ships:
		if not s.dead and s.side == side:
			out.append(s)
	return out


func toast(text: String) -> void:
	toast_log.append({"t": time, "step": steps, "text": text})


## «ИИ против ИИ»: строка ленты называет сторону кланом («Тройден: …»), а не «наш» и «противник»
## — человек ни за одну из сторон не играет, и «наш» у атакующего читалось бы как чей-то выбор.
func clan_tag(side: int) -> String:
	var f: Defs.FactionDef = defs.factions.get(sides[side].clan)
	return f.short if f != null else str(sides[side].clan)


## Говорить ли кланами (тексты ленты и полосок; логика боя смотрит на сам watch): в «ИИ против
## ИИ» у зрителя нет «своих» и «чужих», и всё, что модель пишет человеку, — от имени клана.
func clan_voice() -> bool:
	return watch and not rollback_watch_voice


func feed(text: String, kind: StringName) -> void:
	feed_log.append({"t": time, "step": steps, "text": text, "kind": kind})
