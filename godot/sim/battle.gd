# sim/battle.gd — состояние боя и step(): ТОЛЬКО порядок шага (архитектура, 2.4),
# создание боя из состава (часть 01, 2.15), журналы, команды, dispose().
# Модель — чистый GDScript (RefCounted), ни одного узла: вид и интерфейс её только
# читают и меняют бой одной дверью — queue(команда) (архитектура, 1).
#
# Шаг постоянный — 1/30 с. ОТЛИЧИЕ от JS (ловушка 22 части 01): там на 4× шаг
# растягивался до 0,2 с; здесь скорость боя — ЧИСЛОМ шагов за кадр, шаг не меняется
# никогда (view/battle_view.gd), и баланс меряется на нём.
#
# Случайность — два генератора с первого дня (архитектура, 2.11): rng — только бой
# (зерно на бой), fx_rng — только картинка. Исход боя не зависит от того, рисуется ли он.
extends "res://sim/state.gd"

const Formation := preload("res://sim/formation.gd")
const Weapons := preload("res://sim/weapons.gd")
const Ecm := preload("res://sim/ecm.gd")
const GroundGun := preload("res://sim/ground_gun.gd")
const Vision := preload("res://sim/vision.gd")
const Air := preload("res://sim/air.gd")
const Hangar := preload("res://sim/hangar.gd")
const HeavyDoctrine := preload("res://sim/heavy_doctrine.gd")
const Ai := preload("res://sim/ai.gd")

const ROMAN: Array[String] = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
# space.js:836 dropIn: разброс места выхода ±15 по x (по высоте — нет: бой плоский)
const DROP_JITTER := 15.0
# space.js:3153: охрана своего — кольцом вокруг него, r = hull + hull + 50
const GUARD_RING_PAD := 50.0
const GUARD_RING_A0 := 0.4
# space.js:3184: безоружный на «Охоте» — при главном вооружённом (P5)
const LEAD_A_STEP := 2.3
const LEAD_A0 := 2.6
const LEAD_PAD := 70.0
# space.js:3206 moveGroup: шаг строя не меньше 90 — звенья в точке приказа встают рядом
const SQUAD_STEP := 90.0

## ТОЛЬКО для проверок отката (хвосты G1): в игре всегда false.
## «Идти» — каждый своей скоростью, а не по самому медленному (ловушка 6 части 02, C70).
static var rollback_move_own_speed := false
## «Идти» — все в одну точку, без сохранения взаимного расположения.
static var rollback_move_one_point := false
## Отпечаток боя — только положения и прочность, как в G1: приказов и сторон не видит.
static var rollback_fp_positions := false
## ТОЛЬКО для проверки отката (02, ловушка 20): безоружный на «Охоте» к главному
## вооружённому не пристраивается — держит свой участок посреди боя. В бою всегда false.
static var rollback_hunt_no_lead := false
## ТОЛЬКО для проверки отката (09, 4.6; 04, ловушка 2): тяжёлый по приказу на звено
## ИДЁТ к нему, «чтобы достало ПВО», как в JS, — уходит из пояса в свалку.
static var rollback_heavy_to_squad := false
## ТОЛЬКО для проверки отката (09, 5.5; план G4, п. 8): подкрепление выходит у своего края,
## как в JS (z = ±1200, по 5 в ряд), хотя идёт на свои места, — носитель проносится на ~570
## впереди своей линии тяжёлых. В бою всегда false.
static var rollback_drop_at_edge := false
## ТОЛЬКО для проверки отката: старт «как в JS» — флот стоит позади своих мест и получает
## приказ «идти» на них (ловушка 28 части 02: свой флот на старте приказов не получает).
static var rollback_start_move := false
## ТОЛЬКО для проверки отката: точка выхода прибывших без края поля (reinforce.exit_edge).
static var rollback_exit_no_edge := false
## ТОЛЬКО для проверки отката (09, 6.4): ПКМ по полю — прежний квадрат «как стояли»,
## без строя по ролям. В бою всегда false.
static var rollback_move_keep_layout := false
## ТОЛЬКО для проверки отката (09, 6.4; замечание к G4): ось строя ПКМ всегда по ходу марша,
## а не к центру видимых чужих тяжёлых. В бою всегда false.
static var rollback_axis_march := false
## ТОЛЬКО для проверки отката (05, ловушка 26; 2.12): «нечем бить» не проверяется — сторона
## с одним безоружным РЭБ стоит вечно, итога нет. В бою всегда false.
static var rollback_no_teeth := false
## ТОЛЬКО для проверки отката (05, ловушки 30–32): итог «Отход» — у любого проигрыша, где кто-то
## ушёл в гипер, а в снимок итога резерв не входит (как до P1). В бою всегда false.
static var rollback_outcome_old := false
## ТОЛЬКО для проверки отката (замер М6, находка стенда G5): подкрепление на подходе к месту
## считается «за тыловым рубежом», как до G5. В бою всегда false.
static var rollback_rear_arrivals := false
## ТОЛЬКО для проверок отката (замечание к G5 — правила хода боя без своих проверок):
## «… копит гипер — добить» пишется при каждом начале накачки, а не раз на корабль (05, ловушка 14);
static var rollback_flee_note_repeat := false
## ИИ, которому нечем бить, уходит сразу, не позвав свой резерв (05, 2.12);
static var rollback_teeth_no_reserve := false
## «есть чем бить» — только оружие кораблей: свободный ангар, звено в воздухе, машина с ракетами
## и резерв в пути не считаются (05, ловушка 27 — can_hurt щедрый намеренно).
static var rollback_can_hurt_strict := false
## ТОЛЬКО для проверки отката (хвост проверки G5, п. 3): «есть чем бить» не смотрит на машины
## в воздухе — звено с ракетами, у которого сбит носитель, не в счёт. В игре false.
static var rollback_can_hurt_no_craft := false

## ИИ сторон (sim/ai.gd): объект на сторону, в порядке сторон.
var ai: Array[Ai] = []


## Бой из состава быстрого боя (часть 01, 2.15). setup:
##   attacker, defender — кланы; size — &"small" | &"mid" | &"big";
##   seed — зерно боя; reserve — у атакующего (игрока) резерв = «Стычка» своего клана.
## Станция у защитника — в тех масштабах, где она есть (quick_battle.station_on).
## Сторона игрока — атакующий, как в JS (план, раздел 1).
static func create(p_defs: Defs, p_setup: Dictionary, p_build: String = "") -> RefCounted:
	var b := new()
	b._setup(p_defs, p_setup, p_build)
	return b


func _setup(p_defs: Defs, p_setup: Dictionary, p_build: String) -> void:
	var b := self
	b.defs = p_defs
	b.setup = p_setup.duplicate()
	b.build = p_build
	var sd: float = p_setup.get("seed", 1.0)
	b.battle_seed = roundi(sd)
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = b.battle_seed
	b.fx_rng = RandomNumberGenerator.new()
	b.fx_rng.seed = b.battle_seed ^ 0x5bd1e995
	var c := p_defs.consts
	b.mp.rev = p_defs.reverse_k
	b.mp.brake_k = c.brake_k
	b.mp.cap_k = c.ship_speed_cap_k
	b.mp.field = c.field_half
	var gs: Defs.StanceDef = p_defs.stances.get(&"guard")
	b.mp.guard_leash = gs.leash if gs != null else 0.0
	b.mp.amove_resume = p_defs.doctrine.amove_resume_s
	b.mp.clear_k = p_defs.doctrine.belt_clear_k
	b.space.heavy_r2 = Metrics.M9_HEAVY * Metrics.M9_HEAVY     # М9: пары чужих тяжёлых — проходом пар снимка
	# флажки отката доктрины тяжёлых и строя (09, 8.4) — ключи состава боя
	b.legacy_approach = p_setup.get("legacy_approach", false)
	b.old_ai = p_setup.get("old_ai", false)
	b.old_pd = p_setup.get("old_pd", false)
	b.no_share_close = p_setup.get("no_share_close", false)
	b.no_foe_brake = p_setup.get("no_foe_brake", false)
	b.clear_055 = p_setup.get("clear_055", false)
	b.ecm_01l = p_setup.get("ecm_01l", false)
	if b.clear_055:
		b.mp.clear_k = p_defs.doctrine.was.get(&"belt.clear_k", b.mp.clear_k)
	b.mp.craft_cap_k = c.craft_speed_cap_k
	b.old_ecm = p_setup.get("old_ecm", false)
	b.bomber_direct = p_setup.get("bomber_direct", false)
	b.patrol_mid = p_setup.get("patrol_mid", false)
	var att := StringName(str(p_setup.get("attacker", p_defs.quick.default_mine)))
	var dfn := StringName(str(p_setup.get("defender", p_defs.quick.default_foe)))
	var size := StringName(str(p_setup.get("size", p_defs.quick.default_size)))
	# сложность — только у ИИ (03, ловушка 27): игрок — атакующий (план, раздел 1)
	var dif: Defs.DifficultyDef = p_defs.difficulty.get(StringName(str(p_setup.get("difficulty", p_defs.quick.default_difficulty))))
	for i in 2:
		var s := SideState.new()
		s.clan = att if i == Ship.ATTACKER else dfn
		s.sign_z = 1.0 if i == Ship.ATTACKER else -1.0
		s.aim = 1.0 if i == b.player_side or dif == null else dif.aim
		b.sides.append(s)
	var side_ids: Array = []
	# стенд (план G4): составы-сценарии — только эти виды кораблей (пусто — все):
	# «линии» — только тяжёлые, подход линия на линию без лёгких посередине (09, 8.4:
	# «подход без доли сближения» — М3); «заслон» — тяжёлые и корветы
	var only: Variant = p_setup.get("only", [])
	var keep: Array = only if typeof(only) == TYPE_ARRAY else []
	for i in 2:
		var all_ids := ids_of(compose(p_defs, size, b.sides[i].clan))
		if not keep.is_empty():
			var hv: Array[StringName] = []
			for id in all_ids:
				var dd := p_defs.ship(b.sides[i].clan, id)
				if dd != null and ((dd.main != null and "heavy" in keep) or str(id) in keep):
					hv.append(id)
			all_ids = hv
		# стенд, М12 (09, 8.2; план G5, п. 4): те же составы БЕЗ кораблей РЭБ у стороны — отдельная
		# строка составов, а не флажок: «разница в победах с РЭБ и без»
		var ne: Variant = p_setup.get("no_ecm", [])
		if typeof(ne) == TYPE_ARRAY:
			var nea: Array = ne
			if float(i) in nea or i in nea:
				var keep_ids: Array[StringName] = []
				for id in all_ids:
					var dd := p_defs.ship(b.sides[i].clan, id)
					if dd != null and not dd.ecm:
						keep_ids.append(id)
				all_ids = keep_ids
		side_ids.append(all_ids)
	for i in 2:
		# расстановка строем по ролям на ±650 (09, 5.5): места — как участки, приказов нет
		var s := b.sides[i]
		var ids: Array[StringName] = side_ids[i]
		var foe_ids: Array[StringName] = side_ids[1 - i]
		for place: Array in Formation.start_places(p_defs, s.clan, ids, s.sign_z, foe_ids, b.sides[1 - i].clan, b.ecm_01l):
			var id: StringName = place[0]
			var p: Vector2 = place[1]
			var sh := b.spawn(i, p_defs.ship(s.clan, id), p + Vector2(0.0, s.sign_z * 300.0) if rollback_start_move else p)
			if rollback_start_move:
				sh.has_move = true
				sh.move_to = p
	if size in p_defs.quick.station_on:
		b.spawn(Ship.DEFENDER, p_defs.station, Formation.station_place(p_defs, -1.0))
	var extra: Variant = p_setup.get("extra", [])
	if typeof(extra) == TYPE_ARRAY:
		# добавочные корабли сценария («Перестрелка»: «Синхо» у Плэктора — по нему видно
		# ПВО против ракет): [сторона, id, x, z]
		var ex: Array = extra
		for e: Variant in ex:
			var row: Array = e
			var sd_f: float = row[0]
			var sd_i := roundi(sd_f)
			var x: float = row[2]
			var z: float = row[3]
			var def := p_defs.ship(b.sides[sd_i].clan, StringName(str(row[1])))
			if def != null:
				b.spawn(sd_i, def, Vector2(x, z))
	# сценарий «Перестрелки» (G2, ИИ — G5): противник с первого шага идёт атакой с ходу
	# на foe_amove вперёд — тяжёлые встают на встречного, лёгкие сходятся. Это
	# расстановка с заданием, а не приказ игрока: в журнал команд не пишется, в записи
	# боя едет вместе с setup. С G4 лаборатория «Бой линий» его не ставит (противника ведёт
	# ИИ строем, ai_lines) — ключ остался для проб.
	var adv: float = p_setup.get("foe_amove", 0.0)
	if adv != 0.0:
		var foe := 1 - b.player_side
		for s in b.ships:
			if s.side == foe and not s.station and s.def.hangar <= 0:
				s.has_amove = true
				s.amove = s.pos + Vector2(0.0, -b.sides[foe].sign_z * adv)
				s.amove_quiet = p_defs.doctrine.amove_resume_s
	# сценарий «Полигона» до ИИ (G5): противник поднимает звенья по кругу ролей — это
	# расстановка с заданием, как foe_amove: в журнал команд не пишется, едет в setup
	var fa: Variant = p_setup.get("foe_air", {})
	if typeof(fa) == TYPE_DICTIONARY:
		var fad: Dictionary = fa
		var roles: Variant = fad.get("roles", [])
		if typeof(roles) == TYPE_ARRAY:
			var ra: Array = roles
			for r: Variant in ra:
				b.foe_air_roles.append(StringName(str(r)))
		var ev: float = fad.get("every", 0.0)
		var first: float = fad.get("first", 0.0)
		b.foe_air_every = ev
		b.foe_air_next = first
	# ИИ (sim/ai.gd): «ai» — стороны, которые он ведёт ЦЕЛИКОМ (быстрый бой — противник,
	# «ИИ против ИИ» и стенд — обе); «ai_lines» — только строем (шаги 6–7, бывшая заглушка
	# G4): так лаборатория «Бой линий» ведёт противника. Ключи состава боя: запись их помнит.
	var full_sides: Array[int] = []
	for key: String in ["ai", "ai_lines"]:
		var lst: Variant = p_setup.get(key, [])
		if typeof(lst) != TYPE_ARRAY:
			continue
		var sa: Array = lst
		for v: Variant in sa:
			var sv: float = v
			var si := roundi(sv)
			if si < 0 or si >= b.sides.size() or b.sides[si].ai_on:
				continue
			b.ai.append(Ai.arm(b, si, key == "ai"))
			if key == "ai":
				full_sides.append(si)
	# «ИИ против ИИ»: ИИ у обеих сторон — человек смотрит; сложность — у ОБОИХ ИИ (03, ловушка
	# 27 — сложность только у ИИ; у игрока её нет, потому что игрока нет)
	b.watch = full_sides.size() == 2
	for si in full_sides:
		b.sides[si].aim = dif.aim if dif != null else 1.0
	var with_reserve: bool = p_setup.get("reserve", true)
	if with_reserve:
		b.sides[Ship.ATTACKER].reserve = compose(p_defs, &"small", att)
	# орудие планеты — ПОСЛЕ состояния боя (03, ловушка 29; 05, ловушка 40). В быстром
	# бою — у планеты защитника, всегда (01, ловушка 16); в пробах без него — "".
	var gg := str(p_setup.get("ground_gun", ""))
	if gg == "defender":
		gg = str(dfn)
	if gg != "":
		GroundGun.create(b, StringName(gg))
	b.events.clear()


## Состав стороны (часть 01, 2.15): масштаб → строки «вид × число»; нули выбрасываются
## ДО множителя клана (ловушка 19: max(1, …) Тройдена не превращает «флагман 0»
## в один флагман), затем множитель: Плэктор round(n × 2), Тройден max(1, round(n × 0,7)).
static func compose(p_defs: Defs, size: StringName, clan: StringName) -> Array[Defs.FleetEntry]:
	var out: Array[Defs.FleetEntry] = []
	var l: Defs.Lineup = p_defs.quick.sizes.get(size)
	var f: Defs.FactionDef = p_defs.factions.get(clan)
	if l == null or f == null:
		return out
	var sc: Defs.ScaleDef = p_defs.quick.scale.get(clan)
	for e in l.entries:
		if not f.ships.has(e.id):
			continue           # «regiments» — наземная операция, не корабль
		if e.count <= 0:
			continue           # нули — ДО множителя (ловушка 19 части 01)
		var n := e.count
		if sc != null:
			var m := float(e.count) * sc.mul
			n = maxi(sc.at_least, roundi(m)) if sc.rounds else roundi(m)
		if n <= 0:
			continue
		var o := Defs.FleetEntry.new()
		o.id = e.id
		o.count = n
		out.append(o)
	return out


static func ids_of(entries: Array[Defs.FleetEntry]) -> Array[StringName]:
	var out: Array[StringName] = []
	for e in entries:
		for i in e.count:
			out.append(e.id)
	return out


## Римский номер имени (space.js:316): 2 → «II», 11 → «XI».
static func roman(n: int) -> String:
	return ROMAN[n] if n <= 10 else "X" + roman(n - 10)


# space.js:320 spawnShip · часть 01, 2.7
func spawn(side: int, def: Defs.ShipDef, pos: Vector2) -> Ship:
	var sd := sides[side]
	var s := Ship.new()
	s.uid = next_uid()
	s.side = side
	s.sign_z = sd.sign_z
	s.def = def
	s.station = def.station
	var nn: int = sd.name_n.get(def.id, 0) + 1
	sd.name_n[def.id] = nn
	# имя с номером (P5, ловушка 11 части 01): «Рэш», «Рэш II», … «Рэш XI»
	s.name = def.name + (" " + roman(nn) if nn > 1 else "")
	s.pos = pos
	s.set_yaw(0.0 if sd.sign_z > 0.0 else PI)          # нос к противнику
	s.hp = def.hp
	s.max_hp = def.hp
	s.legacy = legacy_approach and def.main != null      # откат --legacy-approach (09, 8.4)
	s.belt = HeavyDoctrine.IDLE
	s.kind = Body.SHIP
	s.cls_i = def.cls_i
	s.hit_r = def.radius                                 # радиус КЛАССА, не модели (01, ловушка 8)
	s.armor = def.armor
	if def.hangar > 0:
		s.hangar = Hangar.make(def.hangar)              # ангар (04, 2.2): носитель и станция
	var c := defs.consts
	s.length = def.model_len if def.model_len > 0.0 else def.radius * c.len_fallback_k
	# корпус — от длины МОДЕЛИ, а не от радиуса класса (C87, C88; ловушка 6 части 01); та же
	# формула, по которой строит строй (sim/formation.gd → hull_of)
	s.hull = Formation.hull_of(defs, def)
	s.stance = c.default_stance_station if s.station else c.default_stance_ship
	s.anchor = pos
	s.jumped_at_step = steps
	s.stealth = def.stealth
	s.seen_pos = pos
	s.seen_at = time
	Weapons.arm(self, s)
	ships.append(s)
	events.append([&"spawn", s.uid])
	return s


# ───────────────────────────── шаг ─────────────────────────────

## Поставить команду (архитектура, 2.9): применится в начале следующего шага.
func queue(c: Dictionary) -> void:
	cmds.queue(c, steps + 1)


# space.js:3925 simStep · часть 05, 2.2; архитектура, 2.4. Пустые пока модули —
# на своих местах порядка: ИИ обеих сторон по ОДНОМУ снимку — G5.
func step() -> void:
	steps += 1
	time = float(steps) * STEP            # часы — от числа шагов: без накопления ошибки
	metrics.now = time
	events.clear()
	for c in cmds.take_due(steps):        # приказы, поставленные на этот шаг
		_apply(c)
	space.rebuild(ships)                  # живые + упакованный снимок, пары (2.5)
	_side_lines()                         # центры линий и оси сторон (09, 5.1) — по началу шага
	Ecm.update(self)                      # поля помех — один раз, по положениям начала шага
	GroundGun.update(self)                # орудие планеты
	Vision.update(self)                   # кто кого видит; seen_pos — ДО ИИ (05, ловушка 39)
	_arrive_reinforcements()              # прибывшие — до ИИ
	# ИИ обеих сторон — по ОДНОМУ состоянию начала шага: сначала планы, потом применить
	# (архитектура, 2.4; 09, 4.5 и 8.1); тик каждого — по своему таймеру
	_ai_tick()
	_foe_air()                            # сценарий лаборатории «Бой линий»: пуски противника
	for s in ships:
		if not s.dead:
			_update_ship(s)               # гипер → ион → цели → движение → оружие → ПВО
	Air.prepare(self)                     # линии и оси для патруля и обхода — раз на шаг
	for c in crafts:
		if not c.dead:
			Air.update_craft(self, c)     # машины — после кораблей (04, 2.4; 04, ловушка 20)
	for p in projs:
		if not p.dead:
			Weapons.update_proj(self, p)  # снаряд, пущенный на этом шаге, летит уже сейчас (03, 2.1)
	_clean_projs()
	Hangar.tick(self)                     # места ангаров, уборка, звенья (04, 2.2)
	_check_teeth()                        # «нечем бить» — ДО конца боя (05, ловушка 39)
	_check_end()
	_sample_air()                         # metrics.sample(self) целиком — G5; здесь М5
	_sample_lines()                       # фазы, М1–М4, М6, М9, М10 (G4; 09, 8.2)


# space.js:1211 updateShip · часть 03, 2.1 (порядок внутри)
func _update_ship(s: Ship) -> void:
	if s.charging():
		# копит гипер — только накачка, ни целей, ни огня (02, 2.8 п. 1; 03, 2.1 п. 1)
		if Movement.update_hyper(s, STEP):
			_complete_jump(s)
		return
	# флагман и «Синхо» ниже flee — в гипер сами (space.js:1220)
	if s.def.flee > 0.0 and not s.station and s.hp_frac() < s.def.flee:
		if _begin_jump(s):
			if s.side == player_side and not clan_voice():
				toast("%s: повреждения критические, уходим в гипер" % s.name)
			else:
				_flee_note(s)
		return
	Weapons.think(self, s)                # цели по ролям оружия и помехи (03, 2.7–2.9)
	if s.station:
		# станция не летает (02, 2.8 п. 5) — только доворачивает корпус на цель (03, 2.1 п. 6)
		var t := s.target as Ship
		if t != null and not t.dead:
			Movement.face(s, t.pos - s.pos, STEP, time)
	else:
		var push := space.push[s.si] if s.si >= 0 else Vector2.ZERO
		if s.heavy() and not s.legacy:
			HeavyDoctrine.update(self, s, push, STEP)     # пояс, подход, отход (09, 2.9)
		else:
			Movement.update(s, push, STEP, time, mp)
	Weapons.fire(self, s)                 # оружие — ПОСЛЕ движения этого шага (03, 2.1 п. 6)


## Центры линий и оси сторон на этом шаге (09, 5.1): от центра своей линии тяжёлых к центру
## чужой. Отход тяжёлого вперёд по оси не ведёт (2.6); считается по началу шага.
func _side_lines() -> void:
	for i in sides.size():
		var own := Formation.line_of(ships, i)
		var foe := Formation.line_of(ships, 1 - i)
		var sd := sides[i]
		sd.has_line = own.heavy
		sd.line = own.center
		var v := foe.center - own.center
		sd.ax = v.normalized() if own.has and foe.has and v.length() > 1.0 else Vector2(0.0, -sd.sign_z)


## ИИ сторон (sim/ai.gd; архитектура, 2.4): кому пора — думают по ОДНОМУ состоянию начала
## шага (планы обеих сторон собираются до того, как применяется первый), потом планы
## применяются по порядку сторон. Гипер, отход всем флотом и резерв — здесь: это двери боя.
func _ai_tick() -> void:
	if ai.is_empty():
		return
	var plans: Array = []
	for a in ai:
		plans.append(a.think(self) if a.due(self) else null)
	for i in ai.size():
		var a := ai[i]
		var pl: Ai.Plan = plans[i]
		if pl == null:
			continue
		if not a.full:
			a.apply(self, pl)
			continue
		if pl.reserve and call_reinforcements(a.side) and a.side != player_side and not clan_voice():
			toast("Противник вызвал подкрепление")
		a.set_dome(self, pl.dome)
		for l: Array in pl.launch:
			var c: Ship = l[0]
			a.launch_q.append([c.uid, l[1]])
		if pl.retreat:
			# отход всем флотом (05, 2.6 пп. 5, 7) — строкой в ленте с подсказкой, чем ответить:
			# копящий гипер беззащитен, а «Охрана» за ним не пойдёт (05, ловушка 13)
			if order_retreat(a.side) > 0:
				if clan_voice():
					feed("%s отходит всем флотом: копит гипер" % clan_tag(a.side), &"warn")
				elif a.side != player_side:
					feed("Противник отходит: копит гипер — добить: «Охота» (T) или ПКМ по кораблю", &"warn")
			continue
		for s in pl.jumps:
			if _begin_jump(s):
				_flee_note(s)
		a.apply(self, pl)
	for a in ai:
		a.step(self)


## «Противник: «…» копит гипер — добить, пока не ушёл» — раз на корабль, не при отходе всем
## флотом (05, 2.16; ловушка 14): иначе игрок не узнает, что его можно добить.
func _flee_note(s: Ship) -> void:
	var sd := sides[s.side]
	if sd.retreat or (s.flee_told and not rollback_flee_note_repeat):
		return
	s.flee_told = true
	if clan_voice():
		feed("%s: %s копит гипер" % [clan_tag(s.side), Weapons.short_name(s)], &"warn")
	elif s.side != player_side:
		feed("Противник: %s копит гипер — добить, пока не ушёл" % Weapons.short_name(s), &"warn")


# space.js:2051 canHurt · часть 05, 2.12 — щедрый намеренно (ловушка 27): ангар со свободным
## местом, место на постройке, звено в воздухе, ракетная машина с запасом или на перезарядке,
## резерв в пути — всё это «есть чем бить».
func can_hurt_side(side: int) -> bool:
	for s in ships:
		if s.dead or s.side != side or s.charging():
			continue
		if s.can_hurt():
			return true
		if rollback_can_hurt_strict:
			continue
		if s.hangar != null and (s.hangar.free > 0 or not s.hangar.rebuild.is_empty()):
			return true
		if s.hangar != null:
			for q: RefCounted in s.hangar.launched:
				var sq := q as Squad
				if sq != null and not sq.dead:
					return true
	if rollback_can_hurt_strict:
		return false
	for c in crafts:
		if rollback_can_hurt_no_craft:
			break
		if c.side == side and not c.dead and not c.leaving and (c.def.weapon_kind != &"missile" or c.ammo > 0 or c.reloads > 0 or c.reloading > 0.0):
			return true
	return sides[side].reinforce_at > 0.0


# space.js:2062 checkTeeth · часть 05, 2.12 — каждый шаг, для обеих сторон, ДО конца боя
## (05, ловушка 39): сторона, которой НЕЧЕМ бить, уходит сама (ловушка 26). Игроку — строка
## в ленте и ai.teeth_player_s на вызов резерва; ИИ сперва зовёт свой резерв, потом уходит
## через ai.teeth_ai_s.
func _check_teeth() -> void:
	# бой кончен — «нечем бить» не о чем (лаборатории с одной стороной кончаются на первом шаге,
	# а шагают дальше: без этого одинокий РЭБ таблицы прихода 2.22 уходил в гипер на 12-й с)
	if rollback_no_teeth or over:
		return
	var dc := defs.doctrine
	for side in sides.size():
		var sd := sides[side]
		var any := false
		for s in ships:
			any = any or (not s.dead and not s.charging() and s.side == side)
		if sd.retreat or not any or can_hurt_side(side):
			sd.teeth = -1.0
			continue
		var human := side == player_side and not watch
		var spare := 0
		for e in sd.reserve:
			spare += e.count
		if sd.teeth < 0.0:
			sd.teeth = time
			if not human and spare > 0 and not rollback_teeth_no_reserve and call_reinforcements(side):
				sd.teeth = -1.0
				continue
			if human:
				feed("Флоту нечем бить: ни орудий, ни авиации — через %d с уцелевшие уйдут в гипер%s" % [roundi(dc.ai_teeth_player_s), " · B — вызвать резерв" if spare > 0 else ""], &"bad")
		if time - sd.teeth < (dc.ai_teeth_player_s if human else dc.ai_teeth_ai_s) - 1e-9:
			continue
		sd.teeth = -1.0
		if order_retreat(side) == 0:
			continue
		if human:
			feed("Нечем бить — уцелевшие уходят в гипер", &"bad")
		elif clan_voice():
			feed("%s: нечем бить — флот уходит в гипер" % clan_tag(side), &"warn")
		elif side != player_side:
			feed("Противнику нечем бить — его флот уходит в гипер", &"good")
		else:
			feed("Нашему флоту нечем бить — уходит в гипер", &"bad")


## Сценарий «Полигона» до ИИ (G5): противник раз в foe_air_every с поднимает с каждого
## носителя со свободным местом по звену — роли по кругу. Без ИИ в «Полигоне» иначе
## не было бы чужих звеньев: перехватчикам некого встречать, ПВО — некого сбивать.
func _foe_air() -> void:
	if foe_air_roles.is_empty() or time < foe_air_next:
		return
	foe_air_next += foe_air_every
	var foe := 1 - player_side
	for s in ships:
		if s.dead or s.side != foe or s.hangar == null or s.charging() or s.hangar.free <= 0:
			continue
		var role := foe_air_roles[foe_air_i % foe_air_roles.size()]
		foe_air_i += 1
		Hangar.launch(self, s, role)      # по одному звену с носителя за раз — как ИИ (04, 2.14)


## М5 (09, 8.2) за шаг: машины в воздухе, без взлёта и посадки, — доля в середине.
func _sample_air() -> void:
	if crafts.is_empty() or air_geo.size() != 2:
		return
	var g0 := Air.geo_of(self, 0)
	var g1 := Air.geo_of(self, 1)
	var home_r := metrics.M5_HOME
	for c in crafts:
		if c.dead or c.leaving:
			continue
		var g := g0 if c.side == 0 else g1
		if not g.ok:
			continue
		var q := c.squad as Squad
		if q != null:
			var home := q.home as Ship
			if home != null and not home.dead and c.pos.distance_squared_to(home.pos) < home_r * home_r:
				continue
		metrics.sample_craft(c.side, (c.pos - g.p).dot(g.ax), g.d, STEP)


## Замеры доктрины тяжёлых и строя за шаг (09, 8.1–8.2; хранение — sim/metrics.gd).
## Почти все — по фазе «бой»: от первого выстрела главного калибра по кораблю до первого
## отхода стороны или конца боя; марш и развязка о доктрине не говорят.
func _sample_lines() -> void:
	var m := metrics
	if m.phase == 0 and m.first_gun > 0.0:
		m.phase = 1
		m.fight_t0 = time
	# «нечем бить» у стороны — тоже конец фазы «бой»: ИИ (G5) там уводит флот (05, 2.6 п. 5),
	# а без него носители, оставшиеся одни, кружат по полю и портят доли
	if m.phase == 1 and (over or sides[0].retreat or sides[1].retreat or not _armed(0) or not _armed(1) or _leaderless(0) or _leaderless(1)):
		m.phase = 2
		m.fight_t1 = time
		m.close_episodes(time)
	if m.phase != 1:
		return
	var dc := defs.doctrine
	var edge := mp.field - dc.retreat_edge
	var both := sides[0].has_line and sides[1].has_line
	var l := sides[0].line.distance_to(sides[1].line)
	if both:
		m.m3.append(l)
		if l < Metrics.M3_FLOOR:
			m.m3_short += 1
	if sides[0].ai_on and sides[1].ai_on:
		m.p_min = minf(m.p_min, sides[0].line_p.distance_to(sides[1].line_p))
	var hcount := [0, 0]
	for s in ships:
		if s.dead or s.station or s.charging():
			continue
		var sd := sides[s.side]
		if s.heavy():
			hcount[s.side] += 1
			m.r_line = minf(m.r_line, s.def.main.rng)
			m.heavy_s += STEP
			var t := s.target as Ship
			if t != null and not t.dead and Weapons.main_reach(s, s.pos.distance_to(t.pos)) == 0:
				m.m1_s += STEP
			# ближайший чужой — из снимка начала шага (sim/space.gd: тот же проход пар, что
			# расталкивание), а не перебором объектов (godot/CLAUDE.md, 3). Сдвиг на шаг — доли
			# единицы; видимость в срезе — «да» всегда (sim/vision.gd), появится скрытность —
			# спрашивать её здесь
			var close := s.si >= 0 and space.near_d2[s.si] < s.def.main.dead * s.def.main.dead
			if close:
				m.m2_s += STEP
			Metrics.episode(m.m2_run, m.m2_eps, s.uid, close, time)
			if s.jam != null:
				m.m12_jam_s += STEP           # М12: под чужими помехами (Weapons.think этого шага)
			var ret := s.belt == HeavyDoctrine.RETREAT
			if ret:
				m.m6_s += STEP
			Metrics.episode(m.m6_run, m.m6_eps, s.uid, ret, time)
			# «за рубежом» — дальше допуска прихода (8): место линии может стоять на самом рубеже
			if sd.rear_z < INF and s.pos.y * sd.sign_z > sd.rear_z + HeavyDoctrine.ARRIVED:
				if not m.m6_arriving.has(s.uid) or rollback_rear_arrivals:
					m.m6_rear += 1
			elif m.m6_arriving.has(s.uid):
				m.m6_arriving.erase(s.uid)
			if absf(s.pos.x) > edge + HeavyDoctrine.ARRIVED or absf(s.pos.y) > edge + HeavyDoctrine.ARRIVED:
				m.m6_edge += 1
		elif s.def.cls == &"escort" and s.hp_frac() >= Metrics.M4_HURT and both and s.slot_band != Formation.UMBRELLA:
			var p := (s.pos - sd.line).dot(sd.ax)
			m.light_s += STEP
			if p >= 0.0 and p <= l:
				m.m4_mid_s += STEP
			if p < -Metrics.M4_BEHIND:
				m.m4_back_s += STEP
		if s.has_slot and sd.ai_on:
			var dd := s.pos.distance_to(s.slot)
			if s.heavy():
				m.m10_heavy.append(dd)
			elif s.def.id == &"corvette":
				m.m10_corvette.append(dd)
			elif s.def.cls == &"escort":
				m.m10_frigate.append(dd)
	# М6: центр своей линии назад — сумма шагов назад по оси стороны, пока состав линии тот же
	for i in 2:
		var sd := sides[i]
		if not sd.has_line:
			m.m6_prev[i] = null
			continue
		var proj := sd.line.y * sd.sign_z
		var prev: Variant = m.m6_prev[i]
		if prev != null:
			var pa: Array = prev
			var pc: int = pa[0]
			var pp: float = pa[1]
			if pc == hcount[i] and proj > pp:
				m.m6_back[i] += proj - pp
		m.m6_prev[i] = [hcount[i], proj]
	# М10, строй против расталкивания: места двух своих ближе hull + hull (9.5 п. 20) — пары
	# посчитаны, когда ИИ раздавал места (sim/ai.gd → slot_clash); здесь — пока оба живы
	# и в строю
	for i in 2:
		var cl := sides[i].slot_clash
		if not sides[i].ai_on or cl.is_empty():
			continue
		for k in range(0, cl.size(), 2):
			var a := ship_by_uid(cl[k])
			var c := ship_by_uid(cl[k + 1])
			if a != null and c != null and not a.dead and not c.dead and not a.charging() and not c.charging():
				m.m10_self += 1
	# М9: входы пар «свой в чужом» (ближе (hull + hull) × 1,15 — пары расталкивания чужих) и пары
	# чужих тяжёлых ближе 360 — из того же прохода пар снимка (sim/space.gd)
	var now_in: Dictionary[int, bool] = {}
	for key in space.foe_in:
		now_in[key] = true
		if not m.m9_in.has(key):
			m.m9_entries += 1
	m.m9_heavy += space.heavy_close
	m.m9_in = now_in


## «Без тяжёлых — уход» (05, 2.6 п. 7): тяжёлые у стороны были и кончились, у противника
## тяжёлые с орудиями есть, и он сильнее по сумме прочности. ИИ (G5) тут отдаёт приказ
## отхода — конец фазы «бой» (09, 8.1); до ИИ стенд считает это тем же приказом, иначе
## лёгкие без своей линии меряются как строй.
func _leaderless(side: int) -> bool:
	var sd := sides[side]
	var mine_hp := 0.0
	var foe_hp := 0.0
	var mine_heavy := false
	var foe_heavy := false
	for s in ships:
		if s.dead:
			continue
		if s.side == side:
			mine_hp += maxf(0.0, s.hp)
			mine_heavy = mine_heavy or (s.heavy() and not s.station)
		else:
			foe_hp += maxf(0.0, s.hp)
			foe_heavy = foe_heavy or (s.heavy() and s.can_hurt())
	if mine_heavy:
		sd.had_heavy = true
		return false
	return sd.had_heavy and foe_heavy and mine_hp < foe_hp


## Есть ли у стороны чем бить (корабль с оружием, не станция).
func _armed(side: int) -> bool:
	for s in ships:
		if not s.dead and s.side == side and not s.station and s.can_hurt():
			return true
	return false


## Мёртвые снаряды — из списка в конце шага (space.js:3950).
func _clean_projs() -> void:
	var keep: Array[Proj] = []
	for p in projs:
		if not p.dead:
			keep.append(p)
		else:
			p.unlink()
	projs = keep


# space.js:3785 sideOut, 3903 checkEnd, 3792 finish · часть 05, 2.13
## Бой кончается, когда сторона ушла с орбиты ЦЕЛИКОМ (ловушка 28). Итог игрока: «Отход» —
## только если флот правда отходил (по приказу, за носителем, «нечем бить») или ушёл весь
## без потерь (ловушка 30); иначе «Флот разбит»; противник ушёл — «Орбита за нами». «ИИ против
## ИИ» — ничья, если обе стороны ушли на одном шаге (план, раздел 1). Снимок итога — в этот
## же миг (ловушки 31–32): живые не-станции, ушедшие в гипер и невышедший резерв.
func _check_end() -> void:
	if over:
		return
	var a_out := _side_out(Ship.ATTACKER)
	var d_out := _side_out(Ship.DEFENDER)
	if a_out or d_out:
		finish(Ship.DEFENDER if a_out and not d_out else (Ship.ATTACKER if d_out and not a_out else -1))


## Итог боя: winner — сторона, удержавшая орбиту (−1 — никто). Зовёт и стенд на пределе
## времени (result = &"limit").
func finish(p_winner: int, limit: bool = false) -> void:
	if over:
		return
	over = true
	winner = p_winner
	var p := player_side
	if limit:
		result = &"limit"
	elif watch:
		result = &"draw" if winner < 0 else (&"victory" if winner == p else &"defeat")
	elif winner != p:
		# орбиту игрок не удержал (ушёл сам, разбит или обе стороны ушли на одном шаге)
		var lost := false
		for s in ships:
			lost = lost or (s.dead and not s.fled and s.side == p and not s.station)
		var jumped := sides[p].jumped.size() > 0
		if rollback_outcome_old:
			result = &"retreat" if jumped else &"defeat"
		else:
			result = &"retreat" if jumped and (sides[p].retreat or not lost) else &"defeat"
	else:
		result = &"victory"
	outcome = {"result": result, "attacker": survivors(Ship.ATTACKER), "defender": survivors(Ship.DEFENDER)}
	events.append([&"over", winner])


## Уцелевшие стороны по id (05, 2.13): живые не-станции (копящие гипер тоже), ушедшие в гипер
## и резерв, который так и не вышел (вызванный, но не прибывший — тоже; C15).
func survivors(side: int) -> Dictionary:
	var out: Dictionary = {}
	for s in ships:
		if s.dead or s.side != side or s.station:
			continue
		_add(out, str(s.def.id), 1)
	for id in sides[side].jumped:
		_add(out, str(id), 1)
	if not rollback_outcome_old:
		for e in sides[side].reserve:
			_add(out, str(e.id), e.count)
	return out


static func _add(d: Dictionary, k: String, n: int) -> void:
	var v: int = d.get(k, 0)
	d[k] = v + n


## Сторона больше не держит орбиту: живых нет, или отход и живы одни станции.
func _side_out(side: int) -> bool:
	var live := 0
	var non_station := 0
	for s in ships:
		if not s.dead and s.side == side:
			live += 1
			if not s.station:
				non_station += 1
	return live == 0 or (sides[side].retreat and non_station == 0)


# ───────────────────────────── гипер (часть 02, 2.17–2.19) ─────────────────────────────

# space.js:681 beginJump
func _begin_jump(s: Ship) -> bool:
	if s.dead or s.charging() or s.station:
		return false                      # станция в гипер не уходит (ловушка 24)
	var base := s.def.hyper_charge if s.def.hyper_charge > 0.0 else defs.consts.hyper_default_charge
	var total := base * defs.hyper.jump_charge
	s.hyper_left = total
	s.hyper_total = total
	s.has_move = false
	s.forced = null
	events.append([&"hyper", s.uid])
	return true


func _cancel_jump(s: Ship) -> void:
	s.hyper_left = 0.0
	s.hyper_total = 0.0
	events.append([&"unhyper", s.uid])


# space.js:690 completeJump
func _complete_jump(s: Ship) -> void:
	s.fled = true
	s.dead = true
	s.hyper_left = 0.0
	s.thrust_fwd = 0.0
	var sd := sides[s.side]
	sd.jumped.append(s.def.id)
	events.append([&"jump_out", s.uid])
	if clan_voice() and not sd.retreat:
		feed("%s: %s ушёл в гипер" % [clan_tag(s.side), s.name], &"warn")
	elif s.side != player_side and not sd.retreat:
		feed("Противник: %s ушёл в гипер" % s.name, &"warn")
	# уход носителя = отход всей стороны, честно, накачкой (C17; ловушка 22 части 02)
	if s.def.cls == &"carrier" and not sd.conceded:
		sd.conceded = true
		order_retreat(s.side)
		if clan_voice():
			toast("%s: носитель ушёл в гипер — флот отходит следом" % clan_tag(s.side))
		else:
			toast("Носитель ушёл в гипер — флот отходит следом" if s.side == player_side else "Носитель противника ушёл — его флот отходит")


# space.js:730 orderRetreat — гипер всего флота с накачкой, а не конец боя (C17)
func order_retreat(side: int) -> int:
	var sd := sides[side]
	if sd.retreat:
		return 0
	sd.retreat = true
	sd.reinforce_at = 0.0                 # вызванное подкрепление отменяется
	var n := 0
	for s in ships:
		if not s.dead and s.side == side and _begin_jump(s):
			n += 1
	return n


# space.js:738 cancelRetreat
func cancel_retreat(side: int) -> void:
	var sd := sides[side]
	if not sd.retreat or sd.conceded:
		return                            # носитель ушёл — отход уже не отменить
	sd.retreat = false
	for s in ships:
		if not s.dead and s.side == side and s.charging():
			_cancel_jump(s)


# space.js:781 callReinforcements
func call_reinforcements(side: int) -> bool:
	var sd := sides[side]
	if sd.reserve.is_empty() or sd.reinforce_at > 0.0 or sd.retreat:
		return false
	sd.reinforce_at = time + defs.hyper.reinforce_delay
	if clan_voice():
		toast("%s: подкрепление выйдет из гипера через %d с" % [clan_tag(side), roundi(defs.hyper.reinforce_delay)])
	elif side == player_side:
		toast("Подкрепление выйдет из гипера через %d с" % roundi(defs.hyper.reinforce_delay))
	return true


# space.js:818 arriveReinforcements — по игровым часам (01, 4.2 п. 8)
func _arrive_reinforcements() -> void:
	for i in sides.size():
		var sd := sides[i]
		if sd.reinforce_at > 0.0 and time >= sd.reinforce_at:
			var list := sd.reserve
			sd.reserve = []
			sd.reinforce_at = 0.0
			var got := _drop_in(i, list)
			var many := "корабль" if got.size() == 1 else ("корабля" if got.size() < 5 else "кораблей")
			if clan_voice():
				toast("%s: подкрепление вышло из гипера" % clan_tag(i))
				feed("%s: подкрепление — %d %s вышли из гипера" % [clan_tag(i), got.size(), many], &"warn")
			elif i == player_side:
				toast("Подкрепление вышло из гипера")
				feed("Подкрепление: %d %s вышли из гипера" % [got.size(), many], &"good")
			else:
				toast("Противник получил подкрепление")


# space.js:827 dropIn · часть 02, 2.19; ДОКТРИНА 09, 5.5 и 9.1, план G4, п. 8
## Подкрепление — на СВОИ места: места той же sim/formation.gd от нынешней линии своей
## стороны (под заглушкой строя — её P; у игрока — к своей линии тяжёлых, нет её — к линии
## старта). Выход из гипера — 2,6 × maxSpeed к середине поля, без предела скорости, пока не
## погасит её сама (вопрос 1 части 02), — и ТОЧКА ВЫХОДА от тормозного пути: место плюс
## v² / (2 × reverse × thrust()) с выходной скорости и reinforce.exit_pad, не ближе
## reinforce.exit_edge к краю поля (место у края — выход вбок, вдоль своей линии). Выход
## «у своего края, как сейчас» проносил носитель на ~570 впереди своих тяжёлых — под чужие
## главные калибры (откат rollback_drop_at_edge).
func _drop_in(side: int, list: Array[Defs.FleetEntry]) -> Array[Ship]:
	var sd := sides[side]
	var c := defs.consts
	var got: Array[Ship] = []
	var i := 0
	for e in list:
		var def := defs.ship(sd.clan, e.id)
		if def == null:
			continue
		for _n in e.count:
			var x := float(i % c.reinforce_drop_per_row - 2) * c.reinforce_drop_step_x
			var z := sd.sign_z * c.reinforce_drop_base_z + sd.sign_z * floorf(float(i) / c.reinforce_drop_per_row) * c.reinforce_drop_step_z
			var s := spawn(side, def, Vector2(x, z))
			got.append(s)
			i += 1
	_place_arrivals(side, got)
	for s in got:
		events.append([&"jump_in", s.uid])
		metrics.m6_arriving[s.uid] = true
	return got


## Места и точки выхода прибывших (09, 5.5; план G4, п. 8).
func _place_arrivals(side: int, got: Array[Ship]) -> void:
	if got.is_empty():
		return
	var sd := sides[side]
	var dc := defs.doctrine
	var c := defs.consts
	var spec := Formation.Spec.new()
	if sd.ai_on and sd.line_set:
		spec.p = sd.line_p
		spec.ax = sd.line_ax
	elif sd.has_line:
		spec.p = sd.line
		spec.ax = sd.ax
	else:
		spec.p = Vector2(0.0, sd.sign_z * dc.deploy_heavy_z)
		spec.ax = Vector2(0.0, -sd.sign_z)
	var lat := Vector2(-spec.ax.y, spec.ax.x)
	spec.foe_width = Formation.line_width(ships, 1 - side, lat)
	for o in ships:
		spec.foe_air = spec.foe_air or (not o.dead and o.side != side and o.hangar != null)
	var mine: Array[Ship] = []
	for s in ships:
		if not s.dead and s.side == side and not s.station and not s.charging():
			mine.append(s)
	var members := Formation.members_from(mine)
	for k in mine.size():
		if mine[k] in got:
			members[k].pos = spec.p - spec.ax * 2000.0          # ещё в гипере: места — по составу
	var out := Formation.places(defs, members, spec)
	var lim := c.field_half - dc.reinforce_exit_edge
	for k in mine.size():
		var s := mine[k]
		if not (s in got):
			continue
		var place := out.at[k] if out.band[k] != Formation.NONE else spec.p
		s.anchor = place
		var v := s.def.max_speed * c.reinforce_drop_exit_speed_k
		var u := spec.ax.normalized()
		if not rollback_drop_at_edge:
			# тормозной путь — от той же thrust(), что разгон (09, 9.5 п. 4); тормозят против носа
			var brake := v * v / (2.0 * mp.rev * s.thrust())
			var dist := brake + dc.reinforce_exit_pad
			var exit := place - u * dist
			if not rollback_exit_no_edge and (absf(exit.x) > lim or absf(exit.y) > lim):
				# место у края: выход вбок, вдоль своей линии, со стороны середины
				var sg := -signf(place.dot(lat)) if absf(place.dot(lat)) > 1.0 else 1.0
				u = lat * sg
				exit = place - u * dist
			if not rollback_exit_no_edge:
				exit.x = clampf(exit.x, -lim, lim)
				exit.y = clampf(exit.y, -lim, lim)
			s.pos = exit
		else:
			u = Vector2(0.0, -sd.sign_z)
		s.vel = u * v
		s.exit_until = time + dc.hyper_exit_free_max_s
		s.seen_pos = s.pos


# ───────────────────────────── команды (архитектура, 2.9) ─────────────────────────────

func _apply(c: Dictionary) -> void:
	var op: StringName = c.get("op", &"")
	match op:
		&"move":
			var x: float = c.get("x", 0.0)
			var z: float = c.get("z", 0.0)
			_cmd_move(_mine(c), Vector2(x, z))
			_cmd_squads_move(_mine_squads(c), Vector2(x, z))
		&"stance":
			var st: StringName = c.get("stance", &"guard")
			_set_stance(_mine(c), st)
		&"drift":
			_toggle_drift(_mine(c))
		&"hyper":
			_cmd_hyper(_mine(c))
		&"reinforce":
			var sd: int = c.get("side", player_side)
			if not call_reinforcements(sd) and sd == player_side:
				var s := sides[sd]
				if s.reinforce_at > 0.0:
					toast("Подкрепление уже в пути: %d с" % ceili(s.reinforce_at - time))
				elif s.retreat:
					toast("Флот отходит — подкрепление не зовём")
				else:
					toast("Резерва больше нет")
		&"retreat":
			var rs: int = c.get("side", player_side)
			order_retreat(rs)
		&"cancel_retreat":
			var cs: int = c.get("side", player_side)
			cancel_retreat(cs)
		&"focus":
			var tu: int = c.get("target", 0)
			var ts := ship_by_uid(tu)
			if ts != null:
				_cmd_focus(_mine(c), ts)
				_cmd_squads_attack(_mine_squads(c), ts)
			else:
				var tq := squad_by_uid(tu)
				_cmd_focus_squad(_mine(c), tq)
				_cmd_squads_attack(_mine_squads(c), tq)
		&"amove":
			var ax: float = c.get("x", 0.0)
			var az: float = c.get("z", 0.0)
			_cmd_move(_mine(c), Vector2(ax, az), true)
			_cmd_squads_move(_mine_squads(c), Vector2(ax, az))
		&"guard":
			var wu: int = c.get("target", 0)
			var ward := ship_by_uid(wu)
			_cmd_guard(_mine(c), ward)
			if ward != null and not ward.dead:
				_cmd_squads_move(_mine_squads(c), ward.pos)    # звенья — к точке, где он СЕЙЧАС (04, 2.13)
		&"ecm":
			var mode: StringName = c.get("mode", &"jam")
			_cmd_ecm(_mine(c), mode)
		&"launch":
			var role: StringName = c.get("role", &"")
			_cmd_launch(_mine(c, true), role)
		&"recall":
			_cmd_recall(_mine_squads(c))


## Корабли команды: живые, СВОИ (сторона игрока; space.js:3092 mineSelected), не станции.
## ОТЛИЧИЕ: станция в приказы движения не берётся (вопрос 20 части 02): щелчком её
## можно было выделить, и тогда скорость строя пропадала у всей группы.
## with_station — станцию тоже (пуск звена: ангар есть и у станции, 04, 1.1).
func _mine(c: Dictionary, with_station: bool = false) -> Array[Ship]:
	var out: Array[Ship] = []
	var ids: PackedInt32Array = c.get("ids", PackedInt32Array())
	for u in ids:
		var s := ship_by_uid(u)
		if s != null and not s.dead and s.side == player_side and (with_station or not s.station):
			out.append(s)
	return out


## Звенья команды: живые и свои (выбор держит uid звена — один счётчик с кораблями).
func _mine_squads(c: Dictionary) -> Array[Squad]:
	var out: Array[Squad] = []
	var ids: PackedInt32Array = c.get("ids", PackedInt32Array())
	for u in ids:
		var q := squad_by_uid(u)
		if q != null and not q.dead and q.side == player_side:
			out.append(q)
	return out


# space.js:3556 (кнопки Z/X/C) · часть 04, 1.1 и 2.3
## Поднять ОДНО звено роли с первого из выделенных носителей, у которого есть место.
func _cmd_launch(list: Array[Ship], role: StringName) -> void:
	var carriers := 0
	for s in list:
		if s.hangar == null:
			continue
		carriers += 1
		var q := Hangar.launch(self, s, role)
		if q != null:
			var rd: Defs.StrikeRoleDef = defs.strike_roles.get(role)
			toast("%s: звено «%s» в воздухе · свободно мест %d" % [Weapons.short_name(s), rd.label if rd != null else str(role), s.hangar.free])
			return
	if carriers == 0:
		toast("Звенья поднимает носитель — выдели его")
	else:
		toast("Мест в ангаре нет: место вернётся, когда звено сядет (V) или отстроится")


# space.js:3570 (V) · часть 04, 2.13 — «На посадку»
func _cmd_recall(list: Array[Squad]) -> void:
	if list.is_empty():
		return
	for q in list:
		Air.order_recall(q)
	toast("Звенья идут на посадку: место в ангаре вернётся, как только сядет последняя машина")


# space.js:3097–3128 issueOrder (по звену) · часть 04, 2.12; ДОКТРИНА 09, 4.6
## Приказ кораблям «бить звено»: лёгкие — бить его МАШИНЫ (C14), тяжёлые НЕ принимают
## (их оружие авиацию не берёт, а идти к звену — уйти из пояса в свалку), безоружные —
## держатся (C100).
func _cmd_focus_squad(list: Array[Ship], q: Squad) -> void:
	if list.is_empty() or q == null or q.dead or q.side == player_side:
		return
	var lights := 0
	var heavies := 0
	var held := 0
	for s in list:
		if not s.can_hurt():
			held += 1
			continue
		if not Weapons.hits_strike(self, s):
			heavies += 1
			if rollback_heavy_to_squad:
				# откат: как в JS — идёт к звену, фокус и цель сняты (04, 2.12)
				s.has_move = true
				s.move_to = q.pos
				s.forced = null
				s.target = null
			continue
		s.forced = q
		s.target = Hangar.live_craft(q, s.pos)
		s.jam_shot = null
		s.has_move = false
		s.has_amove = false
		s.group_speed = 0.0
		lights += 1
	if lights > 0:
		toast("Цель — звено %s: лёгкие бьют его машины, вблизи бьёт ПВО" % q.def.name)
	if heavies > 0:
		toast("Тяжёлые держат дистанцию — авиацию бьют ПВО и звенья")
	if held > 0:
		toast("Носитель и РЭБ безоружны — держатся позади")


## Звенья бьют цель — корабль или чужое звено (04, 2.13); бомбардировщики по авиации
## не стреляют — отказ словом.
func _cmd_squads_attack(list: Array[Squad], t: RefCounted) -> void:
	if list.is_empty() or t == null:
		return
	var took := 0
	var bombers := 0
	for q in list:
		if Air.order_attack(q, t):
			took += 1
		else:
			bombers += 1
	if bombers > 0:
		toast("Бомбардировщики по авиации не стреляют")
	if took > 0:
		var ts := t as Ship
		toast("Звенья атакуют %s" % (Weapons.short_name(ts) if ts != null else "чужое звено"))


## Звенья летят в точку (ПКМ по полю, A + щелчок — у звена то же, что «идти», 04, 2.13):
## рядом, по 90 вбок друг от друга (space.js:3206 moveGroup, шаг не меньше 90).
func _cmd_squads_move(list: Array[Squad], at: Vector2) -> void:
	var n := list.size()
	for i in n:
		Air.order_move(list[i], at + Vector2((float(i) - float(n - 1) * 0.5) * SQUAD_STEP, 0.0))


# space.js:3206 moveGroup · часть 02, 2.15; ДОКТРИНА 09, 6.4
## ПКМ по полю — строй по ролям (6.4): точка приказа — линия тяжёлых, ось — от неё к центру
## видимых чужих тяжёлых (нет — видимых чужих; никого — по маршу от центра группы), места
## той же sim/formation.gd, по нынешнему положению (5.4); скорость строя — по самому
## медленному (C70; ловушка 6 части 02). Любой приказ «идти» выключает дрифт (ловушка 13).
## attack — атака с ходу (A + щелчок, 03, 2.15): та же точка с сохранением взаимного
## расположения, amove и БЕЗ скорости строя (03, ловушка 17); фокус, цель и охрана снимаются.
func _cmd_move(list: Array[Ship], click: Vector2, attack: bool = false) -> void:
	if list.is_empty():
		return
	var center := Vector2.ZERO
	var slow := INF
	for s in list:
		center += s.pos
		slow = minf(slow, s.max_speed())
	center /= float(list.size())
	var dests := PackedVector2Array()
	for s in list:
		dests.append(click if rollback_move_one_point else click + (s.pos - center))
	var formed := not attack and not rollback_move_one_point and not rollback_move_keep_layout
	var spec := Formation.Spec.new()
	if formed:
		spec.p = click
		spec.ax = _order_axis(click, center)
		spec.foe_width = Formation.line_width(ships, 1 - player_side, Vector2(-spec.ax.y, spec.ax.x))
		for o in ships:
			spec.foe_air = spec.foe_air or (not o.dead and o.side != player_side and o.hangar != null and Vision.sees(self, player_side, o))
		var out := Formation.places(defs, Formation.members_from(list), spec)
		for i in list.size():
			if out.band[i] != Formation.NONE:
				dests[i] = out.at[i]
	var near_dead := 0.0
	for i in list.size():
		var s := list[i]
		var dest := dests[i]
		s.has_move = not attack
		s.move_to = dest
		s.has_amove = attack
		s.amove = dest
		s.amove_quiet = defs.doctrine.amove_resume_s      # встречи ещё не было — идёт сразу
		s.target = null
		s.guard_of = null
		s.group_speed = slow if (list.size() > 1 and not attack and not rollback_move_own_speed) else 0.0
		s.arrive_t = 0.0
		s.drift = false
		s.forced = null
		s.jam_shot = null
		if s.heavy() and not attack:
			for o in ships:
				if not o.dead and o.side != s.side and Vision.sees(self, s.side, o) and o.pos.distance_to(dest) < s.def.main.dead:
					near_dead = maxf(near_dead, s.def.main.dead)
	if attack:
		toast("Атака с ходу: идут и встают на встречного")
	elif near_dead > 0.0:
		# 09, 6.7: приказ «идти» в точку ближе D к чужому — иначе «пошёл, пришёл и попятился»
		toast("Тяжёлые дойдут и отойдут на дистанцию — ближе %d главный калибр не бьёт. Чтобы стояли — H" % roundi(near_dead))


## Ось строя приказа (09, 6.4): от точки приказа к центру видимых чужих тяжёлых, нет их —
## к центру видимых чужих, никого не видно — по направлению марша от центра группы к точке.
func _order_axis(click: Vector2, center: Vector2) -> Vector2:
	var fh := Vector2.ZERO
	var nh := 0
	var fa := Vector2.ZERO
	var na := 0
	for o in ships:
		if o.dead or o.side == player_side or o.station or not Vision.sees(self, player_side, o):
			continue
		fa += o.pos
		na += 1
		if o.heavy():
			fh += o.pos
			nh += 1
	var v := Vector2.ZERO
	if rollback_axis_march:
		pass
	elif nh > 0:
		v = fh / float(nh) - click
	elif na > 0:
		v = fa / float(na) - click
	if v.length_squared() < 1.0:
		v = click - center
	if v.length_squared() < 1.0:
		v = Vector2(0.0, -sides[player_side].sign_z)
	return v.normalized()


# space.js:3094 issueOrder (по врагу) · часть 03, 2.14; ДОКТРИНА 09, 6.1–6.3
## ПКМ по врагу — фокус огня: сильнее тактики, тактику НЕ стирает (03, ловушка 16);
## снимает «идти» и атаку с ходу. Безоружные приказ не принимают и держатся, где стоят
## (C100). Тяжёлый встаёт в пояс против цели (09, 6.1–6.3; sim/heavy_doctrine.gd): дальше
## 0,92 R — подходит на 0,8 R, если путь чист; вплотную — отходит от неё и бьёт батареей.
## Лёгкие идут на цель.
func _cmd_focus(list: Array[Ship], t: Ship) -> void:
	if list.is_empty() or t == null or t.dead or t.side == player_side or not Vision.sees(self, player_side, t):
		return
	var held := 0
	var heavies := 0
	var lights := 0
	var dz := INF
	var far := 0.0
	for s in list:
		if not s.can_hurt():
			held += 1                    # C100: безоружные остаются
			continue
		s.forced = t
		if not s.heavy() or Weapons.main_reach(s, s.pos.distance_to(t.pos)) == 0:
			s.target = t
		s.jam_shot = null
		s.has_move = false
		s.has_amove = false
		s.group_speed = 0.0
		if s.heavy():
			heavies += 1
			dz = minf(dz, s.def.main.dead)
			far = maxf(far, s.def.main.rng)
		else:
			lights += 1
	var parts := PackedStringArray()
	if heavies > 0:
		# 09, 6.2: «бить» для тяжёлого — встать в пояс против цели, а не идти в упор
		parts.append("тяжёлые встают на дистанцию %d–%d" % [roundi(dz), roundi(far)])
	if lights > 0:
		parts.append("лёгкие идут на цель")
	if not parts.is_empty():
		toast("Цель — %s: %s" % [Weapons.short_name(t), " · ".join(parts)])
	if held > 0:
		toast("Носитель и РЭБ безоружны — держатся позади")


# space.js:3149 guardShip · часть 03, 2.16
## ПКМ точно по корпусу своего — охранять его: кольцом вокруг, участок «Охраны» едет
## за ним; приказы и фокус снимаются.
func _cmd_guard(list: Array[Ship], ward: Ship) -> void:
	if ward == null or ward.dead or ward.side != player_side or ward.charging():
		return
	var mine: Array[Ship] = []
	for s in list:
		if s != ward:
			mine.append(s)
	if mine.is_empty():
		return
	for i in mine.size():
		var s := mine[i]
		var a := float(i) / float(mine.size()) * TAU + GUARD_RING_A0
		var r := ward.hull + s.hull + GUARD_RING_PAD
		s.guard_of = ward
		s.guard_off = Vector2(cos(a) * r, sin(a) * r)
		s.anchor = ward.pos + s.guard_off
		s.stance = &"guard"
		s.has_move = false
		s.has_amove = false
		s.forced = null
		s.target = null
		s.jam_shot = null
		s.drift = false
		s.group_speed = 0.0
	toast("Охраняют %s: держатся рядом и бьют подошедших" % Weapons.short_name(ward))


# space.js:3436 (кнопки РЭБ) · часть 04, 1.2: «Глушение» / «Прикрытие» / «Молчать»
func _cmd_ecm(list: Array[Ship], mode: StringName) -> void:
	if not (mode in [&"jam", &"shield", &"off"]):
		return
	var n := 0
	for s in list:
		if s.def.ecm:
			s.ecm_mode = mode
			n += 1
	if n > 0:
		var txt: String = {&"jam": "РЭБ: глушение — помехи чужим под куполом", &"shield": "РЭБ: прикрытие — свои под куполом без помех", &"off": "РЭБ: молчит"}[mode]
		toast(txt)


# space.js:3174 setStance
## «Держать» (H) и «Стоп» (S) — ПРИКАЗ ВСТАТЬ: снимают «идти», «с ходу», фокус и дрифт
## (ловушка 11 части 02; 09, 9.5 п. 2). «Охрана» и «Охота» — манера, марш не прерывают
## (ловушка 12). Участок — там, где корабль стоит.
func _set_stance(list: Array[Ship], id: StringName) -> void:
	if list.is_empty():
		return
	# безоружному охотиться нечем: на «Охоте» он идёт при главном вооружённом из
	# выделенных (P5; 02, ловушка 20), нет таких — держит свой участок
	var lead: Ship = null
	if id == &"hunt":
		for s in list:
			if s.can_hurt() and (lead == null or s.def.radius > lead.def.radius):
				lead = s
	var marching := 0
	var wi := 0
	for s in list:
		s.stance = id
		s.guard_of = null
		s.anchor = s.pos
		if lead != null and not s.can_hurt() and not rollback_hunt_no_lead:
			var a := float(wi) * LEAD_A_STEP + LEAD_A0
			wi += 1
			var r := lead.hull + s.hull + LEAD_PAD
			s.guard_of = lead
			s.guard_off = Vector2(cos(a) * r, sin(a) * r)
		if id != &"hunt":
			s.target = null
		if id == &"hold":
			s.has_move = false
			s.has_amove = false
			s.forced = null
			s.group_speed = 0.0
			s.arrive_t = 0.0
			s.drift = false
			s.jam_shot = null
		elif s.has_move or s.has_amove:
			marching += 1
	var st: Defs.StanceDef = defs.stances.get(id)
	var nm := st.name if st != null else str(id)
	# тексты доктрины (09, 6.7: «тексты, которые станут неправдой, переписываются»)
	var what := {
		&"hold": "встают на месте. Тяжёлые бьют главным калибром тех, кто в поясе, батареей — подошедших; сами не отходят",
		&"guard": "держат участок. Тяжёлые — на своей дистанции: подошёл враг — отходят в пределах участка и отстреливаются батареей",
		&"hunt": "сами ищут цели. Тяжёлые встают на дистанцию, лёгкие идут в бой",
	}
	var tail: String = what.get(id, "")
	if id == &"hold":
		toast("%s: %s" % [nm, tail])
	else:
		toast("%s%s: %s" % [nm, " — после прихода в точку" if marching > 0 else "", tail])


# space.js:2352 toggleDrift
func _toggle_drift(list: Array[Ship]) -> void:
	if list.is_empty():
		return
	var all_on := true
	for s in list:
		all_on = all_on and s.drift
	var on := not all_on
	for s in list:
		s.drift = on
	toast("Гасители инерции отключены: корабль скользит по вектору" if on else "Гасители инерции включены")


# space.js:3512–3550 («В гипер» / «Отменить гипер»; вопрос с носителем — G6)
func _cmd_hyper(list: Array[Ship]) -> void:
	if list.is_empty():
		return
	var jumping: Array[Ship] = []
	for s in list:
		if s.charging():
			jumping.append(s)
	if not jumping.is_empty():
		if sides[player_side].conceded:
			toast("Носитель ушёл — отход уже не отменить")
			return
		for s in jumping:
			_cancel_jump(s)
		var any := false
		for s in ships:
			any = any or (not s.dead and s.side == player_side and s.charging())
		if not any:
			sides[player_side].retreat = false
		toast("Гипер отменён")
		return
	var carrier := false
	var longest := 0.0
	for s in list:
		if _begin_jump(s):
			carrier = carrier or s.def.cls == &"carrier"
			longest = maxf(longest, s.hyper_left)
	if longest > 0.0:
		toast(("Авианосец копит гипер, %d с — за ним уйдёт весь флот · G — отменить" if carrier else "Гипер через %d с, всё это время беззащитны · G — отменить") % ceili(longest))


# ───────────────────────────── журналы, отпечаток, запись ─────────────────────────────

## Отпечаток состояния (повторяемость, архитектура 2.11) — побитно: время, шаги; у
## каждого корабля положение, скорость, курс, прочность, гибель, накачка, И ПРИКАЗЫ
## (идти, с ходу, тактика, участок, фокус и цели, охрана, дрифт, скорость строя), таймеры
## оружия, РЭБ; снаряды; стороны (резерв, вызов, отход, «сдалась»), итог и орудие
## планеты. Хвост G1: прежний отпечаток видел одни положения, и повтор, потерявший
## приказ, который ещё не успел сдвинуть корабль, давал «совпало».
func fingerprint() -> String:
	var a := PackedFloat64Array()
	a.append(time)
	a.append(float(steps))
	for s in ships:
		a.append_array([float(s.uid), s.pos.x, s.pos.y, s.vel.x, s.vel.y, s.yaw, s.hp, 1.0 if s.dead else 0.0, s.hyper_left])
		if rollback_fp_positions:
			continue
		a.append_array([1.0 if s.has_move else 0.0, s.move_to.x, s.move_to.y, 1.0 if s.has_amove else 0.0,
			s.amove.x, s.amove.y, float(String(s.stance).hash()), s.anchor.x, s.anchor.y,
			_uid_of(s.forced), _uid_of(s.target), _uid_of(s.sec_target), _uid_of(s.mis_target), _uid_of(s.guard_of),
			1.0 if s.drift else 0.0, s.group_speed, s.retarget, s.ecm_power, float(String(s.ecm_mode).hash()), s.dealt,
			float(s.belt), _uid_of(s.ret_foe), s.ret_clock, s.ret_gain, float(s.futile.size()), s.leash_set,
			1.0 if s.has_slot else 0.0, s.slot.x, s.slot.y, s.amove_quiet])
		a.append_array(s.main_cd)
		a.append_array(s.sec_cd)
		a.append_array(s.light_cd)
		a.append_array(s.mis_cd)
		a.append_array(s.pd_cd)
	if not rollback_fp_positions:
		for p in projs:
			a.append_array([float(p.uid), p.pos.x, p.pos.y, p.dir.x, p.dir.y, p.hp, p.life, 1.0 if p.blind else 0.0])
		for sd in sides:
			var n := 0
			for e in sd.reserve:
				n += e.count
			a.append_array([float(n), sd.reinforce_at, 1.0 if sd.retreat else 0.0, 1.0 if sd.conceded else 0.0, float(sd.jumped.size()),
				1.0 if sd.ai_on else 0.0, sd.line_p.x, sd.line_p.y, sd.line_ax.x, sd.line_ax.y, sd.ai_next])
		a.append_array([1.0 if over else 0.0, float(winner)])
		if gun != null:
			a.append_array([gun.next, 1.0 if gun.warned else 0.0, gun.aim.x, gun.aim.y])
		# авиация (G3): машины, звенья, ангары, пуски сценария
		for c in crafts:
			a.append_array([float(c.uid), c.pos.x, c.pos.y, c.vel.x, c.vel.y, c.yaw, c.hp, c.cd, float(c.ammo),
				float(c.reloads), c.reloading, float(String(c.phase).hash()), c.break_until, float(c.leg),
				float(c.back), 1.0 if c.leaving else 0.0, c.leave_t, _uid_of(c.target)])
		for q in squads:
			a.append_array([float(q.uid), 1.0 if q.dead else 0.0, 1.0 if q.recall else 0.0, 1.0 if q.has_move else 0.0,
				q.move_to.x, q.move_to.y, _uid_of(q.target), _uid_of(q.home), float(q.craft.size())])
		for s in ships:
			if s.hangar != null:
				a.append_array([float(s.hangar.free), float(s.hangar.launched.size())])
				a.append_array(s.hangar.rebuild)
		for sd in sides:
			a.append_array([float(sd.sq_up), float(sd.sq_lost)])
		a.append_array([foe_air_next, float(foe_air_i)])
		# ИИ целиком (G5): общая цель, помощь, очередь пусков, «нечем бить», итог. У лаборатории
		# «Бой линий» (ИИ только строем) этого нет — её отпечаток тот же, что в G4
		for x in ai:
			if x.full:
				a.append_array([float(x.side), _uid_of(x.focus), x.hp0, 1.0 if x.had_heavy else 0.0, float(x.helps.size()),
					float(x.launch_q.size()), float(x.dome_flips), float(x.intercepts), float(x.help_calls)])
				for s in ships:
					if s.side == x.side:
						a.append(1.0 if s.flee_told else 0.0)
		if watch or has_full_ai():
			for sd in sides:
				a.append(sd.teeth)
			a.append(float(String(result).hash()))
	return a.to_byte_array().hex_encode().sha256_text().substr(0, 16)


func has_full_ai() -> bool:
	for x in ai:
		if x.full:
			return true
	return false


## Номер цели в отпечатке: корабль, машина, снаряд или звено; 0 — нет.
static func _uid_of(o: RefCounted) -> float:
	var bo := o as Body
	if bo != null:
		return float(bo.uid)
	var q := o as Squad
	return float(q.uid) if q != null else 0.0


## Запись боя для повтора: заголовок (сборка, отпечаток данных, зерно) и журнал команд.
func record() -> Dictionary:
	return cmds.record(build, defs.fingerprint, battle_seed, setup, steps)


## Бой из записи: тот же состав и зерно, команды — на свои шаги. Чужая сборка или
## чужие числа — null и причина в why (архитектура, 2.9).
static func from_record(p_defs: Defs, rec: Dictionary, p_build: String, why: PackedStringArray) -> RefCounted:
	var r := Commands.check_record(rec, p_build, p_defs.fingerprint)
	var good: bool = r["ok"]
	if not good:
		why.append(str(r["why"]))
		return null
	var st: Dictionary = r["setup"]
	var s2 := st.duplicate()
	s2["seed"] = r["seed"]
	var b := new()
	b._setup(p_defs, s2, p_build)
	var list: Array[Dictionary] = r["cmds"]
	for c in list:
		b.cmds.pending.append(c)
		b.cmds.journal.append(c)
	return b


## Разорвать кольца ссылок после боя: RefCounted их не собирает (архитектура, 2.12).
func dispose() -> void:
	for x in ai:
		x.unlink()
	ai.clear()
	for q in squads:
		q.unlink()
	squads.clear()
	for c in crafts:
		c.unlink()
	crafts.clear()
	for s in ships:
		s.unlink()
		if s.hangar != null:
			s.hangar.launched.clear()
	ships.clear()
	for p in projs:
		p.unlink()
	projs.clear()
	for f in fields:
		f.src = null
	fields.clear()
	gun = null
	space.ships.clear()
	cmds.pending.clear()
	cmds.journal.clear()
	events.clear()
	sides.clear()
