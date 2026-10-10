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


## ТОЛЬКО для проверки отката (09, 10.4; 09, 9.5 п. 4): тормозной путь — от тяги
## из таблицы, а не от thrust() корабля. С двигателями × 0,5 так возвращается
## проскок — проверка «двигатели × 0,5» обязана это увидеть. В бою всегда false.
static var rollback_brake_table := false


## Числа полёта из данных — собираются один раз на бой (в тике без словарей).
class Params:
	var rev: float                # space_move.reverse — доля тяги против носа
	var brake_k: float            # battle_constants.brake_k — запас торможения 0,85
	var cap_k: float              # battle_constants.ship_speed_cap_k — предел 1,25 × maxSpeed
	var field: float              # battle_constants.field_half — половина поля


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


# space.js:1211 updateShip (движение; цели — G2, подход тяжёлых — G4) · часть 02, 2.8
## Чего корабль хочет на этом шаге и как летит. Звать для живого, не станции и не
## копящего гипер (их ведёт battle.gd). push — толчок расталкивания из снимка
## начала шага (sim/space.gd).
static func update(s: Ship, push: Vector2, dt: float, now: float, p: Params) -> void:
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
	# space.js:1275: приказ «идти» (moveTo) важнее всего; атака с ходу — пока не бьёт
	# встречного (fighting — с целями, G2/G4)
	if s.has_move:
		goal_on = true
		goal = s.move_to
	elif s.has_amove:
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
	# space.js:1291–1293 (цель: подход, «Охрана» с целью) — G2; у тяжёлых — пояс, G4
	elif (s.stance == &"guard" or (s.stance == &"hunt" and not s.can_hurt())) and s.pos.distance_to(s.anchor) > ANCHOR_SLOP:
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

	# space.js:1338 куда смотрит нос (часть 02, 2.11; цели — G2, доктрина 2.8 — G4)
	var look := Vector2.ZERO
	if desired.length_squared() > LOOK_MIN_V2:
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
