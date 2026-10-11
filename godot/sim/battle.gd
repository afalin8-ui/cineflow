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

## ТОЛЬКО для проверок отката (хвосты G1): в игре всегда false.
## «Идти» — каждый своей скоростью, а не по самому медленному (ловушка 6 части 02, C70).
static var rollback_move_own_speed := false
## «Идти» — все в одну точку, без сохранения взаимного расположения.
static var rollback_move_one_point := false
## Отпечаток боя — только положения и прочность, как в G1: приказов и сторон не видит.
static var rollback_fp_positions := false


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
	b.old_ecm = p_setup.get("old_ecm", false)
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
	for i in 2:
		var s := b.sides[i]
		var ids := ids_of(compose(p_defs, size, s.clan))
		for place: Array in Formation.start_places(p_defs, s.clan, ids, s.sign_z):
			var id: StringName = place[0]
			var p: Vector2 = place[1]
			b.spawn(i, p_defs.ship(s.clan, id), p)
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
	# боя едет вместе с setup.
	var adv: float = p_setup.get("foe_amove", 0.0)
	if adv != 0.0:
		var foe := 1 - b.player_side
		for s in b.ships:
			if s.side == foe and not s.station and s.def.hangar <= 0:
				s.has_amove = true
				s.amove = s.pos + Vector2(0.0, -b.sides[foe].sign_z * adv)
				s.amove_quiet = p_defs.doctrine.amove_resume_s
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
	var c := defs.consts
	s.length = def.model_len if def.model_len > 0.0 else def.radius * c.len_fallback_k
	# корпус — от длины МОДЕЛИ, а не от радиуса класса (C87, C88; ловушка 6 части 01)
	s.hull = maxf(def.radius * c.hull_formula_radius_k, s.length * c.hull_formula_len_k)
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
# на своих местах порядка: ИИ обеих сторон по ОДНОМУ снимку — G5; машины — G3.
func step() -> void:
	steps += 1
	time = float(steps) * STEP            # часы — от числа шагов: без накопления ошибки
	events.clear()
	for c in cmds.take_due(steps):        # приказы, поставленные на этот шаг
		_apply(c)
	space.rebuild(ships)                  # живые + упакованный снимок, пары (2.5)
	Ecm.update(self)                      # поля помех — один раз, по положениям начала шага
	GroundGun.update(self)                # орудие планеты
	Vision.update(self)                   # кто кого видит; seen_pos — ДО ИИ (05, ловушка 39)
	_arrive_reinforcements()              # прибывшие — до ИИ
	# ИИ: orders по одному снимку начала шага, потом применить — G5
	for s in ships:
		if not s.dead:
			_update_ship(s)               # гипер → ион → цели → движение → оружие → ПВО
	# Air.update_craft — G3
	for p in projs:
		if not p.dead:
			Weapons.update_proj(self, p)  # снаряд, пущенный на этом шаге, летит уже сейчас (03, 2.1)
	_clean_projs()                        # ангары — G3
	# _check_teeth() — G5 («нечем бить» — ДО конца боя)
	_check_end()
	# metrics.sample(self) — G5


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
			if s.side == player_side:
				toast("%s: повреждения критические, уходим в гипер" % s.name)
		return
	Weapons.think(self, s)                # цели по ролям оружия и помехи (03, 2.7–2.9)
	if s.station:
		# станция не летает (02, 2.8 п. 5) — только доворачивает корпус на цель (03, 2.1 п. 6)
		var t := s.target as Ship
		if t != null and not t.dead:
			Movement.face(s, t.pos - s.pos, STEP, time)
	else:
		var push := space.push[s.si] if s.si >= 0 else Vector2.ZERO
		var nf := sqrt(space.near_d2[s.si]) if s.si >= 0 else INF
		Movement.update(s, push, STEP, time, mp, nf)
	Weapons.fire(self, s)                 # оружие — ПОСЛЕ движения этого шага (03, 2.1 п. 6)


## Мёртвые снаряды — из списка в конце шага (space.js:3950).
func _clean_projs() -> void:
	var keep: Array[Proj] = []
	for p in projs:
		if not p.dead:
			keep.append(p)
		else:
			p.unlink()
	projs = keep


# space.js:3785 sideOut, 3903 checkEnd (итог — G5)
func _check_end() -> void:
	if over:
		return
	var a_out := _side_out(Ship.ATTACKER)
	var d_out := _side_out(Ship.DEFENDER)
	if a_out or d_out:
		over = true
		winner = -1 if (a_out and d_out) else (Ship.DEFENDER if a_out else Ship.ATTACKER)
		events.append([&"over", winner])


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
	if s.side != player_side and not sd.retreat:
		feed("Противник: %s ушёл в гипер" % s.name, &"warn")
	# уход носителя = отход всей стороны, честно, накачкой (C17; ловушка 22 части 02)
	if s.def.cls == &"carrier" and not sd.conceded:
		sd.conceded = true
		order_retreat(s.side)
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
	if side == player_side:
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
			if i == player_side:
				toast("Подкрепление вышло из гипера")
				feed("Подкрепление: %d %s вышли из гипера" % [got.size(), "корабль" if got.size() == 1 else ("корабля" if got.size() < 5 else "кораблей")], &"good")
			else:
				toast("Противник получил подкрепление")


# space.js:827 dropIn · часть 02, 2.19
## Выход из гипера у своего края (z = ±1200, по 5 в ряд), на 2,6 × maxSpeed к середине,
## без предела скорости, пока не погасит её сама (вопрос 1 части 02).
## ДОКТРИНА 09, 5.5 и 9.1: прибывшие идут НЕ в (x × 0,4; 0; ±120) — это середина поля,
## пояс и мёртвая зона чужих тяжёлых, то есть свалка, внесённая заново. В G1 они
## встают участком «Охраны» на своей линии старта (±deploy.heavy_z); свои места
## по ролям и точка выхода от тормозного пути — G4, п. 8.
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
			var x := float(i % c.reinforce_drop_per_row - 2) * c.reinforce_drop_step_x + rng.randf_range(-DROP_JITTER, DROP_JITTER)
			var z := sd.sign_z * c.reinforce_drop_base_z + sd.sign_z * floorf(float(i) / c.reinforce_drop_per_row) * c.reinforce_drop_step_z
			var s := spawn(side, def, Vector2(x, z))
			s.vel = Vector2(0.0, -sd.sign_z * def.max_speed * c.reinforce_drop_exit_speed_k)
			s.exit_until = time + defs.doctrine.hyper_exit_free_max_s
			s.anchor = Vector2(x, sd.sign_z * defs.doctrine.deploy_heavy_z)
			events.append([&"jump_in", s.uid])
			got.append(s)
			i += 1
	return got


# ───────────────────────────── команды (архитектура, 2.9) ─────────────────────────────

func _apply(c: Dictionary) -> void:
	var op: StringName = c.get("op", &"")
	match op:
		&"move":
			var x: float = c.get("x", 0.0)
			var z: float = c.get("z", 0.0)
			_cmd_move(_mine(c), Vector2(x, z))
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
			_cmd_focus(_mine(c), ship_by_uid(tu))
		&"amove":
			var ax: float = c.get("x", 0.0)
			var az: float = c.get("z", 0.0)
			_cmd_move(_mine(c), Vector2(ax, az), true)
		&"guard":
			var wu: int = c.get("target", 0)
			_cmd_guard(_mine(c), ship_by_uid(wu))
		&"ecm":
			var mode: StringName = c.get("mode", &"jam")
			_cmd_ecm(_mine(c), mode)


## Корабли команды: живые, СВОИ (сторона игрока; space.js:3092 mineSelected), не станции.
## ОТЛИЧИЕ: станция в приказы движения не берётся (вопрос 20 части 02): щелчком её
## можно было выделить, и тогда скорость строя пропадала у всей группы.
func _mine(c: Dictionary) -> Array[Ship]:
	var out: Array[Ship] = []
	var ids: PackedInt32Array = c.get("ids", PackedInt32Array())
	for u in ids:
		var s := ship_by_uid(u)
		if s != null and not s.dead and s.side == player_side and not s.station:
			out.append(s)
	return out


# space.js:3206 moveGroup (строй — G4)
## ПКМ по полю: выделенные идут, СОХРАНЯЯ взаимное расположение (строй по ролям — G4),
## со скоростью самого медленного (C70; ловушка 6 части 02). Любой приказ «идти»
## выключает дрифт (ловушка 13). attack — атака с ходу (A + щелчок, 03, 2.15): та же
## точка, но amove и БЕЗ скорости строя (03, ловушка 17 — у атаки с ходу своя защита:
## встать на встречного); фокус, цель и охрана снимаются.
func _cmd_move(list: Array[Ship], click: Vector2, attack: bool = false) -> void:
	if list.is_empty():
		return
	var center := Vector2.ZERO
	var slow := INF
	for s in list:
		center += s.pos
		slow = minf(slow, s.max_speed())
	center /= float(list.size())
	for s in list:
		var dest := click if rollback_move_one_point else click + (s.pos - center)
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
	if attack:
		toast("Атака с ходу: идут и встают на встречного")


# space.js:3094 issueOrder (по врагу) · часть 03, 2.14; ДОКТРИНА 09, 6.1–6.3
## ПКМ по врагу — фокус огня: сильнее тактики, тактику НЕ стирает (03, ловушка 16);
## снимает «идти» и атаку с ходу. Безоружные приказ не принимают и держатся, где стоят
## (C100). Тяжёлый в G2 принимает фокус как ВЫБОР ЦЕЛИ и с места не сходит (план G2,
## п. 4): цель в поясе — бьёт главным калибром, вплотную — батареей. Лёгкие идут на цель.
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
		parts.append("тяжёлые бьют с места: главный калибр — от %d до %d" % [roundi(dz), roundi(far)])
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
		if lead != null and not s.can_hurt():
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
	# тексты — правда для G2: тяжёлые с места не сходят, пояс и отход — G4 (09, 6.7)
	var what := {
		&"hold": "встают на месте и бьют, кого достают",
		&"guard": "держат участок, лёгкие встречают подошедших",
		&"hunt": "лёгкие сами ищут цели, тяжёлые бьют с места",
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
			1.0 if s.drift else 0.0, s.group_speed, s.retarget, s.ecm_power, float(String(s.ecm_mode).hash()), s.dealt])
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
			a.append_array([float(n), sd.reinforce_at, 1.0 if sd.retreat else 0.0, 1.0 if sd.conceded else 0.0, float(sd.jumped.size())])
		a.append_array([1.0 if over else 0.0, float(winner)])
		if gun != null:
			a.append_array([gun.next, 1.0 if gun.warned else 0.0, gun.aim.x, gun.aim.y])
	return a.to_byte_array().hex_encode().sha256_text().substr(0, 16)


static func _uid_of(o: RefCounted) -> float:
	var s := o as Ship
	return float(s.uid) if s != null else 0.0


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
	for s in ships:
		s.unlink()
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
