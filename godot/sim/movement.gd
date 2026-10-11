# sim/movement.gd — полёт корабля: перенос части 02 построчно (space.js, коммит e8af7be).
# Над каждой функцией — откуда она: `# space.js:NNNN имяJS · часть 02, раздел`;
# отличие — только помеченное `# ОТЛИЧИЕ: …` или `# ДОКТРИНА 09, …` (архитектура, 2.14).
#
# Бой плоский (09, 11.6): Vector2(x, z), высота — только у вида. Поэтому разворот —
# угол курса, а не кватернион: slerp двух поворотов вокруг одной оси — это ровно
# линейный шаг угла по кратчайшей дуге (тот же доворот, что в JS, при y = 0).
#
# Все числа тяги и разворота — из функций корабля (thrust(), turn(), max_speed()):
# тормозной путь берёт ту же thrust(), что разгон (ловушка 2 части 02; 09, 9.5 п. 4).
extends RefCounted

const Ship := preload("res://sim/ship.gd")
const Defs := preload("res://sim/defs.gd")

# Числа JS, перенесённые как есть (часть 02, 2.7–2.12); числа доктрины — в doctrine.json.
const ARRIVE_STOP := 0.5          # space.js:1171: ближе 0,5 к точке — стоим
const ARRIVE_NEAR_K := 1.5        # space.js:1166: у точки скорость 1,5 × d (ловушка 3)
const ARRIVED_D := 8.0            # space.js:1287: «ближе 8 и медленнее 3»
const ARRIVED_V := 3.0
const ARRIVE_SLOW_D := 60.0       # space.js:1286: «2,5 с ближе 60 и медленнее 4» (ловушка 4)
const ARRIVE_SLOW_V := 4.0
const ARRIVE_SLOW_T := 2.5
const ANCHOR_SLOP := 12.0         # space.js:1294: дальше 12 от участка — вернуться
const LOOK_MIN_V2 := 1.0          # space.js:1343–1346: |желаемая|² > 1, |скорость|² > 1
const BOUNCE := -0.3              # space.js:1147: у края скорость наружу × (−0,3)
const HYPER_RUN := 2.0            # space.js:770: последние 2 с гипера — разгон по носу
const HYPER_RUN_K := 2.2          # space.js:771: thrust × 2,2
# Подход ЛЁГКОГО к цели (space.js:1180 approach, 1197 guardStation · часть 03, 2.13) —
# «как сейчас» (09, 6.1). У тяжёлых этого подхода нет ни в одном пакете: в G2 они
# приказ огня принимают как выбор цели и с места не сходят, в G4 — пояс доктрины
# (план G2, п. 4; архитектура, 2.14).
const LIGHT_WANT_K := 0.68        # рабочая дистанция лёгкого — 0,68 дальности его орудия
const BAND_FAR := 1.08            # полоса покоя [0,55; 1,08] × рабочей дистанции
const BAND_NEAR := 0.55
const BACK_K := 0.5               # ближе полосы — отход на 0,5 maxSpeed
const ORBIT_K := 0.45             # эскорт в полосе облетает цель вбок на 0,45 maxSpeed
const JAM_WANT_K := 0.8           # под помехами — на 0,8 lockRange (02, ловушка 18)
const STATION_SLOP := 10.0        # space.js:1206: ближе 10 к точке «Охраны» — стоим
const FIGHT_K := 1.3              # space.js:1272: атака с ходу лёгкого — встречный ближе 1,3 дальности
const LOOK_K := 1.5               # space.js:1347: нос на цель ближе 1,5 дальности
const LOOK_UNARMED := 400.0       # …у безоружного — 400


## ТОЛЬКО для проверки отката (09, 10.4; 09, 9.5 п. 4): тормозной путь — от тяги
## из таблицы, а не от thrust() корабля. С двигателями × 0,5 так возвращается
## проскок — проверка «двигатели × 0,5» обязана это увидеть. В бою всегда false.
static var rollback_brake_table := false
## ТОЛЬКО для проверки отката (план G2, п. 4): тяжёлый с целью подходит к ней «на 0,68
## дальности», как в JS, — проверка «тяжёлый с фокусом не сошёл с участка» обязана
## краснеть. В бою всегда false.
static var rollback_heavy_approach := false
## ТОЛЬКО для проверки отката (03, ловушка 8): «Держать» с целью подходит к ней, как
## «Охота», — и к глушителю тоже (sim/weapons.gd → jam_pick читает этот же флажок).
static var rollback_hold_approach := false
## ТОЛЬКО для проверки отката (02, ловушка 21): безоружный на «Охоте» без вооружённого
## не возвращается на участок — стоит, где его вынесло. В бою всегда false.
static var rollback_unarmed_hunt_stays := false


## Числа полёта из данных — собираются один раз на бой (в тике без словарей).
class Params:
	var rev: float                # space_move.reverse — доля тяги против носа
	var brake_k: float            # battle_constants.brake_k — запас торможения 0,85
	var cap_k: float              # battle_constants.ship_speed_cap_k — предел 1,25 × maxSpeed
	var field: float              # battle_constants.field_half — половина поля
	var guard_leash: float        # space_stances.guard.leash — поводок «Охраны» лёгкого (240)
	var amove_resume: float       # doctrine amove.resume_s — тяжёлый идёт дальше через 3 с без встречи
	var clear_k: float            # doctrine belt.clear_k — «путь чист»: никого ближе 0,45 R


# space.js:1116 face · часть 02, 2.3
## Разворот носа к look: доля оставшегося угла clamp(turn × dt, 0, 1) за шаг. Ион
## выключает и разворот (ловушка 25 части 02).
static func face(s: Ship, look: Vector2, dt: float, now: float) -> void:
	if s.is_off(&"engines", now):
		return
	if look.length_squared() < 1e-8:
		return
	var want := Ship.yaw_of(look)
	var k := clampf(s.turn() * dt, 0.0, 1.0)
	s.set_yaw(s.yaw + wrapf(want - s.yaw, -PI, PI) * k)


# space.js:1127 thrustTo · часть 02, 2.4
## Тяга доводит скорость до желаемой: полная — по носу, против носа и вбок —
## rev (SPACE_MOVE.reverse 0,6). Не перелетает желаемую. Ион — тяги нет.
## ОТЛИЧИЕ: доля тяги для вида — ДВА числа, по носу и против носа (08, 7.2 п. 7),
## а не одно thrustNow: тяжёлый пятится носом к врагу, и маршевый факел от реверса
## рисовал бы «газует вперёд, уезжая назад».
static func thrust_to(s: Ship, desired: Vector2, dt: float, rev: float, now: float) -> void:
	s.thrust_fwd = 0.0
	s.thrust_rev = 0.0
	if s.is_off(&"engines", now):
		return
	var need_v := desired - s.vel
	var need := need_v.length()
	if need < 1e-4:
		return
	var nrm := need_v / need
	var along := s.dir.dot(nrm)
	var align := maxf(0.0, along)
	var thr := s.thrust()
	var power := thr * (rev + (1.0 - rev) * align)
	var stp := minf(need, power * dt)
	s.vel += nrm * stp
	var full := stp / maxf(1e-4, thr * dt)
	s.thrust_fwd = full * maxf(0.0, along)
	s.thrust_rev = full * maxf(0.0, -along)


# space.js:1143 integrate · часть 02, 2.5
## Перемещение и мягкие границы поля: у края — стоп и скорость наружу × (−0,3).
## Высоты в бою нет (09, 11.6) — предел ±500 по высоте не переносится.
static func integrate(s: Ship, dt: float, field: float) -> void:
	s.pos += s.vel * dt
	if s.pos.x > field:
		s.pos.x = field
		if s.vel.x > 0.0: s.vel.x *= BOUNCE
	if s.pos.x < -field:
		s.pos.x = -field
		if s.vel.x < 0.0: s.vel.x *= BOUNCE
	if s.pos.y > field:
		s.pos.y = field
		if s.vel.y > 0.0: s.vel.y *= BOUNCE
	if s.pos.y < -field:
		s.pos.y = -field
		if s.vel.y < 0.0: s.vel.y *= BOUNCE


# space.js:1163 arriveSpeed · часть 02, 2.7 (C70)
## Скорость, с которой ещё можно встать за dist: торможение от ОБРАТНОЙ тяги
## thrust × reverse × 0,85 (ловушка 1), у самой точки — 1,5 × d (ловушка 3).
static func arrive_speed(s: Ship, dist: float, vmax: float, rev: float, brake_k: float) -> float:
	if dist <= 0.0:
		return 0.0
	var thr := s.def.thrust if rollback_brake_table else s.thrust()
	var a_b := thr * rev * brake_k
	return minf(minf(vmax, sqrt(2.0 * a_b * dist)), dist * ARRIVE_NEAR_K)


# space.js:1168 arrive · часть 02, 2.7
static func arrive(s: Ship, goal: Vector2, vmax: float, rev: float, brake_k: float) -> Vector2:
	var v := goal - s.pos
	var d := v.length()
	if d < ARRIVE_STOP:
		return Vector2.ZERO
	return v * (arrive_speed(s, d, vmax, rev, brake_k) / d)


# space.js:1180 approach · часть 03, 2.13 — ТОЛЬКО у лёгких (09, 6.1: «как сейчас»)
## К рабочей дистанции 0,68 своей дальности (под помехами — 0,8 lockRange): дальше
## полосы покоя — подходит, ближе — отходит на полскорости, в полосе эскорт облетает
## цель вбок. Подход к звену — G3.
static func approach(s: Ship, t: Ship, range0: float, vmax: float, p: Params) -> Vector2:
	var want := range0 * LIGHT_WANT_K
	if s.jam != null:
		var jp: Defs.EcmDef = s.jam
		want = jp.lock_range * JAM_WANT_K        # под помехами наводится только вблизи
	var v := t.pos - s.pos
	var d := v.length()
	if d < 1e-6:
		d = 1.0
	var u := v / d
	if d > want * BAND_FAR:
		return u * arrive_speed(s, d - want, vmax if vmax > 0.0 else s.max_speed(), p.rev, p.brake_k)
	if d < want * BAND_NEAR:
		return u * (-s.max_speed() * BACK_K)
	if s.def.cls == &"escort":
		# cross(к цели, UP) в плоскости (x, z): (−z, x)
		return Vector2(-u.y, u.x).normalized() * (s.max_speed() * ORBIT_K)
	return Vector2.ZERO


# space.js:1197 guardStation · часть 03, 2.13 — ТОЛЬКО у лёгких
## «Охрана» с целью: встать на рабочую дистанцию от неё, но не дальше поводка от
## своего участка. Ушла за поводок — бьём, пока достаём; догонять не идём.
static func guard_station(s: Ship, t: Ship, range0: float, p: Params) -> Vector2:
	var want := range0 * LIGHT_WANT_K
	if s.jam != null:
		var jp: Defs.EcmDef = s.jam
		want = jp.lock_range * JAM_WANT_K
	var v := s.pos - t.pos
	var d := v.length()
	if d < 1e-6:
		d = 1.0
	var r := want if (d > want * BAND_FAR or d < want * BAND_NEAR) else d
	var at := t.pos + v * (r / d)
	var off := at - s.anchor
	var leash := maxf(p.guard_leash, range0 * 0.4)        # space.js:1031 leashOf
	if off.length() > leash:
		at = s.anchor + off * (leash / off.length())
	if at.distance_to(s.pos) < STATION_SLOP:
		return Vector2.ZERO
	return arrive(s, at, s.max_speed(), p.rev, p.brake_k)


# space.js:1211 updateShip (движение) · часть 02, 2.8; часть 03, 2.13
## Чего корабль хочет на этом шаге и как летит. Звать для живого, не станции и не
## копящего гипер (их ведёт battle.gd). push — толчок расталкивания из снимка
## начала шага (sim/space.gd); near_foe — расстояние до ближайшего чужого корабля
## по тому же снимку («путь чист» атаки с ходу тяжёлого, 09, 6.5).
static func update(s: Ship, push: Vector2, dt: float, now: float, p: Params, near_foe: float = INF) -> void:
	var rev := p.rev
	var brake_k := p.brake_k
	var cap_k := p.cap_k
	var field := p.field
	var vmax := s.group_speed if s.group_speed > 0.0 else s.max_speed()       # C70
	# охраняемый погиб или ушёл — сторожим то место, где стоим (space.js:1268)
	var ward := s.guard_of as Ship
	if ward != null and (ward.dead or ward.charging()):
		s.guard_of = null
		ward = null
		s.anchor = s.pos
	if ward != null:
		s.anchor = ward.pos + s.guard_off
	var desired := Vector2.ZERO
	var goal_on := false
	var goal := Vector2.ZERO
	var heavy := s.heavy()
	var t := s.target as Ship
	if t != null and t.dead:
		t = null
	var range0 := s.range0()
	# атака с ходу: встретил — встал (09, 6.5; 03, 2.15)
	var fighting := false
	if s.has_amove:
		if heavy:
			# ДОКТРИНА 09, 6.5: встреча — цель главного калибра в R или чужой ближе D;
			# марш дальше — через amove.resume_s без встречи и если путь чист (0,45 R).
			# Отхода от встречного в G2 нет (пояс — G4): тяжёлый просто стоит.
			var meet := (t != null and s.pos.distance_to(t.pos) <= s.def.main.rng) or near_foe < s.def.main.dead
			s.amove_quiet = 0.0 if meet else s.amove_quiet + dt
			fighting = s.amove_quiet < p.amove_resume or near_foe < p.clear_k * s.def.main.rng
		else:
			fighting = t != null and s.pos.distance_to(t.pos) < range0 * FIGHT_K
	# space.js:1275: приказ «идти» (moveTo) важнее всего; атака с ходу — пока не бьёт
	# встречного
	if s.has_move:
		goal_on = true
		goal = s.move_to
	elif s.has_amove and not fighting:
		goal_on = true
		goal = s.amove
	if goal_on:
		desired = arrive(s, goal, vmax, rev, brake_k)
		var d := s.pos.distance_to(goal)
		var v := s.vel.length()
		# пришёл — точка становится участком (ловушка 5); соседи могут не пустить
		# в саму точку: «рядом и стоит» 2,5 с — тоже приход (ловушка 4)
		s.arrive_t = s.arrive_t + dt if d < ARRIVE_SLOW_D and v < ARRIVE_SLOW_V else 0.0
		if (d < ARRIVED_D and v < ARRIVED_V) or s.arrive_t > ARRIVE_SLOW_T:
			if s.guard_of == null:
				s.anchor = goal
			if s.has_move:
				s.has_move = false
			else:
				s.has_amove = false
			s.group_speed = 0.0
			s.arrive_t = 0.0
	elif heavy and not rollback_heavy_approach:
		# ДОКТРИНА (план G2, п. 4): тяжёлый приказ огня — фокус, «Охота», атака с ходу —
		# принимает как ВЫБОР ЦЕЛИ и с места не сходит; пояс, подход и отход — G4.
		# «Охрана» без приказов — назад на участок, как всегда.
		if s.stance == &"guard" and s.forced == null and not s.has_amove and s.pos.distance_to(s.anchor) > ANCHOR_SLOP:
			desired = arrive(s, s.anchor, vmax, rev, brake_k)
	# space.js:1291–1293: лёгкие — подход к цели и «Охрана» с целью (03, 2.13)
	elif t != null and (s.forced != null or fighting or s.stance == &"hunt" or rollback_hold_approach):
		desired = approach(s, t, range0, vmax, p)
	elif t != null and s.stance == &"guard":
		desired = guard_station(s, t, range0, p)
	elif (s.stance == &"guard" or (s.stance == &"hunt" and not s.can_hurt() and not rollback_unarmed_hunt_stays)) and s.pos.distance_to(s.anchor) > ANCHOR_SLOP:
		# безоружному «Охота» — та же «Охрана» (P5): целей нет — назад, на участок
		desired = arrive(s, s.anchor, vmax, rev, brake_k)
	# иначе — «Держать» и пустой участок: стоим (desired = 0)

	# space.js:1309 расталкивание — через двигатель, в желаемую скорость (C87, C59)
	desired += push

	# space.js:1327 дрифт: тяги нет совсем, предела скорости нет (часть 02, 2.12)
	if not s.drift:
		thrust_to(s, desired, dt, rev, now)
		# space.js:1332 предел 1,25 × maxSpeed — кроме окна после выхода из гипера.
		# ОТЛИЧИЕ (вопрос 1 части 02, по умолчанию плана): окно держится, пока скорость
		# сама не опустится до предела (но не дольше hyper.exit_free_max_s), — а не
		# ровно 6 с: у тяжёлых в момент exitUntil скорость срезалась скачком (крейсер
		# 65,3 → 47,3 за шаг, часть 02, 2.22)
		var cap := s.max_speed() * cap_k
		var spd := s.vel.length()
		if s.exit_until > now:
			if spd <= cap:
				s.exit_until = 0.0
		elif spd > cap:
			s.vel *= cap / spd
	else:
		s.thrust_fwd = 0.0
		s.thrust_rev = 0.0

	# space.js:1338 куда смотрит нос (часть 02, 2.11): цель важнее курса; в дрифте —
	# всегда на цель. ДОКТРИНА 09, 2.8 (нос по главному калибру и на чужого тяжёлого) — G4
	var look := Vector2.ZERO
	var look_r := (range0 if range0 > 0.0 else LOOK_UNARMED) * LOOK_K
	if s.drift and t != null:
		look = t.pos - s.pos
	elif t != null and s.pos.distance_to(t.pos) < look_r:
		look = t.pos - s.pos
	elif desired.length_squared() > LOOK_MIN_V2:
		look = desired
	elif s.vel.length_squared() > LOOK_MIN_V2:
		look = s.vel
	face(s, look, dt, now)
	integrate(s, dt, field)


# space.js:752 updateHyper · часть 02, 2.17
## Копит переход: стоит на месте (ловушка 26), в последние 2 с — разгон по носу.
## Нет разворота, тяги, расталкивания и границ поля. Скорость до накачки сохраняется,
## и ион разгону не мешает — как в JS (вопросы 5 и 7 части 02, по коду).
## true — переход закончен (уходит из боя).
static func update_hyper(s: Ship, dt: float) -> bool:
	s.hyper_left -= dt
	s.thrust_fwd = 0.0
	s.thrust_rev = 0.0
	if s.hyper_left < HYPER_RUN:
		s.vel += s.dir * (s.thrust() * HYPER_RUN_K * dt)
		s.pos += s.vel * dt
		s.thrust_fwd = 1.0
	return s.hyper_left <= 0.0
