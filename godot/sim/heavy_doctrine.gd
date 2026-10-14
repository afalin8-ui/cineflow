# sim/heavy_doctrine.gd — доктрина тяжёлых (09, раздел 2; план G4, пп. 1–2): пояс главного
# калибра, подход, отход задним ходом, «не оторваться», рубежи, нос. ОДНА функция update()
# на шаг тяжёлого: чего он хочет (желаемая скорость по таблице 09, 2.9) и куда смотрит нос
# (09, 2.8); дальше — полёт части 02 как есть (sim/movement.gd → fly: расталкивание, тяга,
# предел скорости, разворот, перемещение). Тормозной путь — от той же thrust(), что разгон
# (Movement.arrive_speed; 09, 9.5 п. 4).
#
# Состояние пояса — явным значением (архитектура, 2.7) у каждого тяжёлого (Ship.belt);
# смена пишется в журнал боя (belt_log): по нему строится строка «чем занят» и считается М6.
# Состояний больше шести архитектурных: «идёт» (приказ), «стоит» (целей нет), «путь
# закрыт» и «край участка» — каждое строка «чем занят» говорит по-своему (09, 6.7).
#
# Лестница приказов 09, 6.6: гипер, ион, дрифт — физика (как сейчас); «идти» и охрана своего
# на ходу — сам НЕ отходит; «Держать» — стоит, сам НЕ отходит (09, 9.5 п. 2); фокус — пояс
# против цели фокуса, отход от неё без поводка; «Охрана» и «Охота» — автоматика пояса,
# самоотход («Охрана» — в поводке 0,5 R). Атака с ходу — движение до встречи, после неё —
# как фокус без поводка (6.5).
#
# Флажки отката 09, 8.4 — ключи СОСТАВА боя (State): `no_share_close` (подход без доли
# сближения), `no_foe_brake` (без торможения у чужих), `clear_055` (путь чист 0,55 R —
# число «было» записи belt.clear_k). «Старый подход» (`legacy_approach`) сюда не заходит
# вовсе: такой тяжёлый летит веткой лёгкого (sim/movement.gd → update).
extends RefCounted

const State := preload("res://sim/state.gd")
const Ship := preload("res://sim/ship.gd")
const Body := preload("res://sim/body.gd")
const Movement := preload("res://sim/movement.gd")
const Vision := preload("res://sim/vision.gd")

# состояния пояса (Ship.belt)
const MOVE := 0         # идёт по приказу: «идти», охрана своего, к участку, к точке атаки с ходу
const HOLD := 1         # «Держать»: стоит, сам не отходит
const IDLE := 2         # стоит: целей нет
const APPROACH := 3     # выходит на дистанцию (цель дальше 0,92 R, путь чист)
const BELT := 4         # держит дистанцию: цель в поясе
const BLOCKED := 5      # цель дальше пояса, а путь закрыт (чужой корабль ближе 0,45 R)
const RETREAT := 6      # враг вплотную — отходит задним ходом
const PINNED := 7       # отходить некуда (рубеж, край, «вперёд не отходят»)
const FUTILE := 8       # «не оторваться»: стоит и бьёт батареей
const LEASH := 9        # «Охрана»: цель дальше пояса, а участок не пускает дальше поводка
const NAMES: Array[String] = ["идёт", "держит позицию", "стоит", "выходит на дистанцию", "держит дистанцию",
	"путь закрыт", "отходит", "прижат", "не оторваться", "на краю участка"]

## Ближе этого к точке подхода — пришёл (space.js:1287 «ближе 8» — тот же допуск прихода).
const ARRIVED := 8.0

## ТОЛЬКО для проверок отката (в игре всегда false):
## «не оторваться» — окно было с НАЧАЛА отхода, 6 с (was), часы идут и при гашении хода
## (09, 0.2 п. 4): тяжёлый, шедший вперёд, объявлял «не оторваться» там, где оторваться можно;
static var rollback_futile_from_start := false
## враг «не повод отходить» забывается через 15 с, даже если он рядом (09, 0.2 п. 4): погоня
## рядом запускала отход каждые ~22 с, и тяжёлый уползал на 700–800 за две минуты;
static var rollback_forget_15s := false
## отход ведёт и вперёд — составляющая к противнику не обрезается (09, 0.2 п. 5);
static var rollback_retreat_forward := false
## у края поля и у тылового рубежа — никаких рубежей отхода (09, 2.6 п. 3–4);
static var rollback_no_edge := false
## «Держать» отходит сам, как «Охрана» (09, 9.5 п. 2: «H не останавливает»).
static var rollback_hold_retreats := false
## тяжёлый стоит с целью вне пояса, как в G2 (тяжёлые к цели не ходили).
static var rollback_g2_stand := false
## нос по ходу (как отход разворотом кормой, 2.4): главный калибр при отходе молчит.
static var rollback_nose_along := false
## «не оторваться» живёт один шаг, как в первой выкладке G4: враг из futile выпадает из
## «повода отходить», и со следующего шага тяжёлый «держит дистанцию» или «путь закрыт»,
## хотя тот же корвет у него под носом (замечание к G4; 09, 2.6 и 6.3);
static var rollback_futile_one_step := false
## «не оторваться» засчитывается только тому, от кого считались часы: погоня двумя-тремя
## корветами запускала отход заново от каждого, и тяжёлый уползал на 430–730 (замечание к G4).
static var rollback_futile_one_foe := false
## охрана своего на ходу — как «Охрана» на месте: самоотход и торможение у чужих (замечание
## к G4: крейсер отходил от корвета и отставал от идущего носителя на ~600; 09, 6.6 п. 2).
static var rollback_escort_retreats := false
## «на ходу» — по СКОРОСТИ охраняемого, как в первой доработке G4: корвет или фрегат на «Охоте»
## или «Охране» облетает свою цель весь бой, и тяжёлый, охраняющий его, бросал пояс и самоотход
## и шёл за ним в чужой строй (второе замечание к G4: «идёт» 59,8 с из 60, чужой ближе D 52,9 с).
static var rollback_escort_by_speed := false
## «не оторваться» стаей — отметка всем, кто держится рядом, по МГНОВЕННОЙ скорости, без
## разбора, кто это (первая доработка G4): проходящий рядом чужой тяжёлый, сближаясь, тоже
## «держался рядом», и от него переставали отходить — а по 09, 2.5 от чужого тяжёлого отход
## работает (второе замечание к G4);
static var rollback_futile_stamp_all := false
## выигрыш окна «не оторваться» не обнуляется с новым эпизодом: F4 показывал «окно 0,0 с +93»
## — выигрыш ПРОШЛОГО окна (второе замечание к G4).
static var rollback_keep_gain := false
## охраняемый ТЯЖЁЛЫЙ в атаке с ходу «идёт», только пока его состояние — «идёт» (MOVE), как во
## второй доработке G4: захватив цель главного калибра на 1,3–1,8 R (Weapons, по тактике), он
## уходит в «выходит на дистанцию» РАНЬШЕ встречи 6.5 — и охрана на ходу кончалась на захвате,
## а на «Охоте» не начиналась вовсе (третье замечание к G4).
static var rollback_amove_by_belt := false
## …или только по часам встречи, без «в пути» (предложение третьего замечания к G4 как есть):
## охраняемый, пятящийся от чужого в 0,4–0,5 R дольше 3 с после встречи, считался бы идущим —
## и охрана шла бы за ним без пояса и самоотхода, хотя он не идёт, а отходит (09, 6.5).
static var rollback_amove_quiet_only := false
## расталкивание выносит тяжёлого за тыловой рубеж стороны под ИИ (до находки стенда G5:
## прижатого у рубежа корвет врага или свой фрегат выталкивали за него на 13–52 и тяжёлый там
## стоял до гибели — отход сам за рубеж не ведёт, а толчок вёл).
static var rollback_push_past_rear := false


## Шаг тяжёлого доктрины: состояние, желаемая скорость, нос и полёт. Звать для живого
## тяжёлого (main), не станции, не копящего гипер и не под флажком --legacy-approach.
## push — толчок расталкивания из снимка начала шага.
static func update(b: State, s: Ship, push: Vector2, dt: float) -> void:
	var p := b.mp
	var dc := b.defs.doctrine
	var r := s.def.main.rng
	var dead := s.def.main.dead
	var ms := s.max_speed()
	var vmax := s.group_speed if s.group_speed > 0.0 else ms
	Movement.sync_ward(s)
	_forget(b, s, r)
	# кто рядом: ближайший видимый чужой КОРАБЛЬ (путь чист и торможение у чужих — по всем),
	# ближайший, кто «повод отходить» (без тех, от кого «не оторваться»), и чужой тяжёлый
	# для носа (2.8, п. 3). Машины и ракеты не считаются (2.1).
	var near_d := INF
	var intr: Ship = null
	var intr_d := INF
	var futile_close := false
	var futile_near := false             # «не оторваться» от врага ближе 0,5 R (2.6)
	for o in b.ships:
		if o.dead or o.side == s.side or not Vision.sees(b, s.side, o):
			continue
		var d := s.pos.distance_to(o.pos)
		if d < near_d:
			near_d = d
		if s.futile.has(o.uid):
			futile_close = futile_close or d < dead
			futile_near = futile_near or d < dc.retreat_futile_forget_k * r
			continue
		if d < intr_d:
			intr_d = d
			intr = o
	var clear := near_d >= p.clear_k * r
	var t := _move_target(b, s)
	# атака с ходу: встреча — цель главного калибра в R или чужой корабль ближе D (6.5)
	if s.has_amove:
		var tm := s.target as Ship
		var meet := (tm != null and not tm.dead and s.pos.distance_to(tm.pos) <= r) or near_d < dead
		s.amove_quiet = 0.0 if meet else s.amove_quiet + dt
	var desired := Vector2.ZERO
	var st := IDLE
	var retreating := s.belt == RETREAT or s.belt == PINNED
	if s.has_move:
		# приказ игрока на движение сильнее всего: на ходу самоотхода нет (6.6, п. 2)
		desired = Movement.go_to(s, s.move_to, vmax, dt, p)
		st = MOVE
	elif escorting(b, s) and not rollback_escort_retreats:
		# охрана своего НА ХОДУ — тоже прямой приказ на движение (6.6, п. 2): за своим местом
		# в кольце, без самоотхода и без торможения у чужих («даже сквозь чужой строй»).
		# Охраняемый встал — дальше «Охрана» вокруг места в кольце, с самоотходом в поводке
		desired = Movement.arrive(s, s.anchor, ms, p.rev, p.brake_k)
		st = MOVE
	elif s.stance == &"hold" and not rollback_hold_retreats:
		st = HOLD                        # «Держать» — приказ встать (09, 9.5 п. 2)
	elif intr != null and (intr_d < dead or (retreating and intr_d < dc.belt_back_off_k * r)):
		desired = _retreat(b, s, r, dt, intr, intr_d)
		st = PINNED if desired == Vector2.ZERO else RETREAT
		if st == RETREAT and _futile_tick(b, s, intr, intr_d, dt):
			st = FUTILE                  # «не оторваться»: со следующего шага этот враг — не повод
			desired = Vector2.ZERO
	elif futile_near and not rollback_futile_one_step:
		# «не оторваться» ДЕРЖИТСЯ, пока тот враг ближе 0,5 R (2.6: «этот враг не повод отходить,
		# пока он ближе 0,5 R… тяжёлый стоит и бьёт батареей»; 6.3). Раньше ветки цели: иначе со
		# следующего шага тяжёлый «держал дистанцию» до корвета в своей мёртвой зоне или стоял
		# «путь закрыт», а строка «чем занят» говорила неправду. Главный калибр бьёт свою цель
		# в поясе, как и был (Weapons), батарея — того, от кого не оторваться
		st = FUTILE
	elif t != null:
		var d := s.pos.distance_to(t.pos)
		var leash := _leashed(s)
		var going := s.belt == APPROACH and d > dc.belt_work_k * r + ARRIVED
		if (d > dc.belt_far_k * r or going) and clear and not rollback_g2_stand:
			desired = _approach(b, s, t, r, vmax, leash, near_d)
			if desired != Vector2.ZERO:
				st = APPROACH
			else:
				st = LEASH if d > dc.belt_far_k * r else BELT
		elif d > dc.belt_far_k * r:
			st = BLOCKED                 # путь закрыт: дальних бьёт, когда подойдут (2.1)
		else:
			st = BELT
		if (st == BELT or st == BLOCKED) and leash and s.pos.distance_to(s.anchor) > leash_r(b, s, r) and clear:
			# пояс держит в поводке: участок уехал дальше поводка — к краю поводка (5.6)
			var rel := s.pos - s.anchor
			desired = _cap(Movement.arrive(s, s.anchor + rel.normalized() * leash_r(b, s, r), vmax, p.rev, p.brake_k), _foe_brake(b, s, r, near_d, vmax))
			st = MOVE
	elif s.has_amove:
		if clear and s.amove_quiet >= p.amove_resume:
			desired = _cap(Movement.go_to(s, s.amove, vmax, dt, p), _foe_brake(b, s, r, near_d, vmax))
			st = MOVE
		else:
			st = BLOCKED if not clear else IDLE
	elif s.stance == &"guard" and s.pos.distance_to(s.anchor) > Movement.ANCHOR_SLOP and clear:
		desired = _cap(Movement.arrive(s, s.anchor, vmax, p.rev, p.brake_k), _foe_brake(b, s, r, near_d, vmax))
		st = MOVE
	if st == IDLE and futile_close:
		st = FUTILE
	if st != RETREAT and st != PINNED and st != FUTILE:
		s.ret_foe = null
	set_state(b, s, st)
	# толчок расталкивания — тоже двигатель своего корабля (sim/space.gd), и за тыловой рубеж
	# стороны он не ведёт, как и отход (2.6): у рубежа выход наружу гасится приходом
	var sd := b.sides[s.side]
	if sd.rear_z < INF and not rollback_push_past_rear and push != Vector2.ZERO:
		push = _limit(b, s, desired + push, Vector2(0.0, sd.sign_z), sd.rear_z - s.pos.y * sd.sign_z) - desired
	Movement.fly(s, desired, push, dt, b.time, p, look(b, s, desired + push))


## Охрана своего на ходу (09, 6.6, п. 2): охраняемый жив и идёт ПО ПРИКАЗУ ИГРОКА — «идти»
## или атака с ходу до встречи (6.5). Тогда для тяжёлого это приказ движения: самоотхода нет.
## Иначе — «Охрана» вокруг места в кольце, с поясом и самоотходом в поводке. По скорости
## охраняемого судить нельзя (второе замечание к G4): лёгкий на «Охоте» или «Охране» облетает
## свою цель весь бой, и тяжёлый шёл бы за ним в чужой строй, бросив пояс.
static func escorting(b: State, s: Ship) -> bool:
	var ward := s.guard_of as Ship
	if ward == null or ward.dead or ward.charging():
		return false
	if rollback_escort_by_speed:
		return ward.has_move or ward.has_amove or ward.vel.length() > Movement.ARRIVED_V
	return ward.has_move or amove_going(b, ward)


## Атака с ходу ещё идёт — встречи не было (09, 6.5). У тяжёлого доктрины встреча — цель
## главного калибра в R или чужой корабль ближе D: при ней update() обнуляет amove_quiet, и
## «идёт» он, пока встречи не было resume_s (3 с: приказ ставит это значение сразу) и он
## действительно в пути — марш («идёт») или подход к цели («выходит на дистанцию»). По одному
## состоянию «идёт» судить нельзя (третье замечание к G4): захватив цель главного калибра на
## 1,3–1,8 R, он уходит в подход РАНЬШЕ встречи. Стоит («путь закрыт») или пятится от чужого
## в 0,4–0,5 R — не в пути. Значения — этого шага, если охраняемый шагал раньше охраняющего,
## иначе прошлого. У лёгкого, носителя и под флажком --legacy-approach — «встречный ближе
## 1,3 дальности» (03, 2.15; Movement.amove_fighting).
static func amove_going(b: State, w: Ship) -> bool:
	if not w.has_amove:
		return false
	if w.heavy() and not w.legacy and not w.station:
		if rollback_amove_by_belt:
			return w.belt == MOVE
		if rollback_amove_quiet_only:
			return w.amove_quiet >= b.mp.amove_resume
		return w.amove_quiet >= b.mp.amove_resume and (w.belt == MOVE or w.belt == APPROACH)
	return not Movement.amove_fighting(w)


## Смена состояния — в журнал боя (архитектура, 2.7; 09, 8.4: первый шаг поиска ошибки).
static func set_state(b: State, s: Ship, st: int) -> void:
	if s.belt == st:
		return
	b.belt_log.append([b.time, s.uid, s.belt, st])
	s.belt = st


## Цель, против которой тяжёлый встаёт в пояс (09, 2.9: «фокус первым»): цель фокуса, пока
## жива и видна (даже вне пояса — тогда главный калибр бьёт свою, 6.3), иначе своя цель
## главного калибра.
static func _move_target(b: State, s: Ship) -> Ship:
	var fz := s.forced as Ship
	if fz != null and not fz.dead and Vision.sees(b, s.side, fz):
		return fz
	var t := s.target as Ship
	if t != null and not t.dead:
		return t
	return null


## «Охрана» без фокуса и без атаки с ходу — пояс держится в поводке (2.6, п. 3). У фокуса
## и «Охоты» поводка нет.
static func _leashed(s: Ship) -> bool:
	return s.stance == &"guard" and s.forced == null and not s.has_amove


## Поводок «Охраны» тяжёлого: leash.capital_k × R (2.6), или заданный строем.
static func leash_r(b: State, s: Ship, r: float) -> float:
	return s.leash_set if s.leash_set > 0.0 else b.defs.doctrine.leash_capital_k * r


# ДОКТРИНА 09, 2.3: подход к точке на 0,8 R от цели по линии «цель → я» приходом
## Две поправки к приходу, обе обязательны: (1) цель идёт навстречу — тормозить по своей
## доле сближения: x × maxSpeed / (maxSpeed + v_сбл); (2) подход тормозит и у чужих
## кораблей: не быстрее arriveSpeed(d_ближ − 0,45 R). На «Охране» точка прижимается
## к поводку. → желаемая скорость (ноль — пришёл или поводок не пускает).
static func _approach(b: State, s: Ship, t: Ship, r: float, vmax: float, leash: bool, near_d: float) -> Vector2:
	var p := b.mp
	var dc := b.defs.doctrine
	var off := s.pos - t.pos
	var d := off.length()
	var u := off / d if d > 1e-6 else Vector2(0.0, s.sign_z)
	var at := t.pos + u * (dc.belt_work_k * r)
	if leash:
		var lr := leash_r(b, s, r)
		var rel := at - s.anchor
		if rel.length() > lr:
			at = s.anchor + rel * (lr / rel.length())
	var to := at - s.pos
	var x := to.length()
	if x < ARRIVED:
		return Vector2.ZERO
	var ms := s.max_speed()
	var xs := x
	if not b.no_share_close:
		var vc := maxf(0.0, t.vel.dot(u))          # её доля сближения: скорость цели к нам
		xs = x * ms / (ms + vc)
	var spd := Movement.arrive_speed(s, xs, vmax, p.rev, p.brake_k)
	spd = minf(spd, _foe_brake(b, s, r, near_d, vmax))
	return to / x * spd


## Торможение у чужих (09, 2.3, п. 2): не быстрее arriveSpeed(d_ближ − 0,45 R) — кольцо
## батареи вокруг ближайшего чужого корабля служит точкой прихода. --no-foe-brake — без него.
static func _foe_brake(b: State, s: Ship, r: float, near_d: float, vmax: float) -> float:
	if b.no_foe_brake or near_d == INF:
		return INF
	return Movement.arrive_speed(s, near_d - b.defs.doctrine.approach_foe_brake_k * r, vmax, b.mp.rev, b.mp.brake_k)


static func _cap(v: Vector2, top: float) -> Vector2:
	var l := v.length()
	return v * (top / l) if l > top and l > 1e-9 else v


# ДОКТРИНА 09, 2.4–2.7: отход — задним ходом (нос на цели главного калибра — look),
# прочь от тех, кто вплотную, с подмешанной тыловой осью; вперёд (к противнику) не ведёт;
# упёрлись в рубеж — скользить вдоль него; скользить некуда — «прижат» (ноль).
static func _retreat(b: State, s: Ship, r: float, dt: float, intr: Ship, intr_d: float) -> Vector2:
	var dc := b.defs.doctrine
	var ms := s.max_speed()
	var close := dc.belt_back_off_k * r
	var away := Vector2.ZERO
	for o in b.ships:
		if o.dead or o.side == s.side or s.futile.has(o.uid) or not Vision.sees(b, s.side, o):
			continue
		var off := s.pos - o.pos
		var d := off.length()
		if d < close and d > 1e-6:
			away += off / d
	if away.length_squared() < 1e-12:
		away = (s.pos - intr.pos).normalized() if intr_d > 1e-6 else Vector2.ZERO
	else:
		away = away.normalized()
	var ax := _axis(b, s)
	var w := away - ax * dc.retreat_rear_mix
	if w.length_squared() > 1e-12:
		w = w.normalized()
	var fwd := w.dot(ax)
	if fwd > 0.0 and not rollback_retreat_forward:
		w -= ax * fwd                  # отход вперёд не ведёт никогда (2.6; 09, 0.2 п. 5)
	var v := w * ms
	# рубежи (2.6, п. 3–4): поводок «Охраны», тыловой рубеж стороны под заглушкой строя,
	# край поля — скользить вдоль; у самого рубежа выход наружу гасится приходом
	if _leashed(s):
		var rel := s.pos - s.anchor
		var lr := leash_r(b, s, r)
		if rel.length() > 1e-6:
			v = _limit(b, s, v, rel / rel.length(), lr - rel.length())
	if rollback_no_edge:
		return v
	var sd := b.sides[s.side]
	if sd.rear_z < INF:
		var back := Vector2(0.0, sd.sign_z)
		v = _limit(b, s, v, back, sd.rear_z - s.pos.y * sd.sign_z)
	var lim := b.mp.field - dc.retreat_edge
	v = _limit(b, s, v, Vector2(1.0, 0.0), lim - s.pos.x)
	v = _limit(b, s, v, Vector2(-1.0, 0.0), lim + s.pos.x)
	v = _limit(b, s, v, Vector2(0.0, 1.0), lim - s.pos.y)
	v = _limit(b, s, v, Vector2(0.0, -1.0), lim + s.pos.y)
	if v.length() < dc.retreat_pinned_side_k * ms:
		return Vector2.ZERO              # прижат: стоит, бьёт батареей и главным в поясе (2.7)
	return v


## Скорость наружу (по n) не больше, чем ещё можно погасить до рубежа (gap).
static func _limit(b: State, s: Ship, v: Vector2, n: Vector2, gap: float) -> Vector2:
	var out := v.dot(n)
	if out <= 0.0:
		return v
	var top := Movement.arrive_speed(s, gap, s.max_speed(), b.mp.rev, b.mp.brake_k) if gap > 0.0 else 0.0
	if out > top:
		v -= n * (out - top)
	return v


## Ось стороны на этом шаге (от своей линии к чужой; нет — от своего края к середине).
static func _axis(b: State, s: Ship) -> Vector2:
	var ax := b.sides[s.side].ax
	return ax if ax.length_squared() > 0.5 else Vector2(0.0, -s.sign_z)


# ДОКТРИНА 09, 2.6, п. 2: «не оторваться» — за 4 с ХОДА расстояние до того, от кого отходят,
# выросло меньше чем на 20. Часы окна идут, только пока корабль уходит от врага не медленнее
# 0,5 maxSpeed (гашение встречного хода и разгон не считаются, 9.5 п. 19); окно СКОЛЬЗЯЩЕЕ —
# последние 4 с хода, а не куски по 4 с. Сработало — враг не повод отходить (помнится ПО
# ВРАГУ, 9.5 п. 13). → true, если сработало на этом шаге.
static func _futile_tick(b: State, s: Ship, foe: Ship, d: float, dt: float) -> bool:
	var dc := b.defs.doctrine
	# окно — от начала ЭПИЗОДА отхода, по расстоянию до БЛИЖАЙШЕГО, от кого отходят (d — до foe,
	# ближайшего «повода»). Сбрасывать окно, когда ближайшим стал другой, нельзя: три корвета
	# вровень сменяют друг друга почти на каждом шаге, и окно не набиралось 10 с вместо 4
	# (замечание к G4: крейсер уползал на 420). Откат «один враг» — прежнее правило
	if s.ret_foe == null or (rollback_futile_one_foe and s.ret_foe != foe):
		s.ret_foe = foe
		s.ret_clock = 0.0
		s.ret_hist = PackedFloat64Array()
		if not rollback_keep_gain:
			s.ret_gain = 0.0             # выигрыш — ЭТОГО окна; прошлый F4 не показывает
		return false
	s.ret_foe = foe
	var away := s.vel.dot((s.pos - foe.pos) / d) if d > 1e-6 else 0.0
	if away < dc.retreat_futile_speed_k * s.max_speed() and not rollback_futile_from_start:
		return false                     # не на ходу от врага — часы стоят
	s.ret_clock += dt
	s.ret_hist.append(s.ret_clock)
	s.ret_hist.append(d)
	var win := dc.retreat_futile_window_s
	if rollback_futile_from_start:
		win = dc.was.get(&"retreat.futile_window_s", win)
	if s.ret_clock < win - 1e-9:
		return false
	# расстояние win секунд хода назад: самая старая запись не моложе окна
	var i := 0
	while i + 2 < s.ret_hist.size() and s.ret_hist[i + 2] <= s.ret_clock - win + 1e-9:
		i += 2
	if i > 0:
		s.ret_hist = s.ret_hist.slice(i)
	var gain := d - s.ret_hist[1]
	s.ret_gain = gain
	if gain >= dc.retreat_futile_gain:
		return false
	s.futile[foe.uid] = b.time
	if not rollback_futile_one_foe:
		# отходят от ВСЕХ, кто ближе 0,5 R (_retreat), и «не оторваться» — от всех ЛЁГКИХ, кто так
		# же держится рядом: расстояние до них растёт не быстрее порога окна (gain / окно, 5 ед/с).
		# Иначе погоня двумя-тремя корветами запускала отход заново от каждого — тяжёлый уползал
		# на 430–730 вместо одного отхода (замечание к G4; 9.5 п. 13 — помнится по каждому врагу).
		# Чужой тяжёлый и носитель — НЕ стая (09, 2.5: от них отход работает): скорость тут
		# мгновенная, и тяжёлый, проходящий рядом, на этом шаге тоже «держится рядом» — а через
		# секунду в мёртвой зоне от него уже не отходили бы (второе замечание к G4). Догоняет он
		# по-настоящему — «не оторваться» от него сработает своим окном, как от любого
		var keep := dc.retreat_futile_gain / dc.retreat_futile_window_s
		var close := dc.belt_back_off_k * s.def.main.rng
		for o in b.ships:
			if o == foe or o.dead or o.side == s.side or s.futile.has(o.uid) or not Vision.sees(b, s.side, o):
				continue
			if (o.heavy() or o.hangar != null) and not rollback_futile_stamp_all:
				continue
			var off := s.pos - o.pos
			var dd := off.length()
			if dd < 1e-6 or dd >= close:
				continue
			if (s.vel - o.vel).dot(off / dd) < keep:
				s.futile[o.uid] = b.time
	s.ret_foe = null
	s.ret_clock = 0.0
	s.ret_hist = PackedFloat64Array()
	return true


## Враг «не повод отходить» забывается, когда прошло не меньше 15 с И он дальше 0,5 R
## (2.6; 09, 0.2 п. 4) — или погиб.
static func _forget(b: State, s: Ship, r: float) -> void:
	if s.futile.is_empty():
		return
	var dc := b.defs.doctrine
	var drop: Array[int] = []
	for u: int in s.futile:
		var o := b.ship_by_uid(u)
		var t0: float = s.futile[u]
		if o == null or o.dead:
			drop.append(u)
		elif b.time - t0 >= dc.retreat_futile_forget_min_s and (rollback_forget_15s or s.pos.distance_to(o.pos) >= dc.retreat_futile_forget_k * r):
			drop.append(u)
	for u in drop:
		s.futile.erase(u)


# ДОКТРИНА 09, 2.8: куда смотрит нос — первое подошедшее: в дрифте — на цель главного
# калибра; цель главного калибра в 1,5 R (и при отходе, и при подходе); нет — чужой
# тяжёлый в 1,5 R (готовит главный калибр, пока ближних бьёт батарея: без этого отход от
# лёгкого шёл бы кормой к чужой линии); по желаемой скорости (с толчками расталкивания);
# по скорости; иначе не поворачивать.
static func look(b: State, s: Ship, want: Vector2) -> Vector2:
	if rollback_nose_along and want.length_squared() > Movement.LOOK_MIN_V2:
		return want
	var r := s.def.main.rng
	var lr := r * Movement.LOOK_K
	var t := s.target as Body
	if t != null and t.dead:
		t = null
	if s.drift and t != null:
		return t.pos - s.pos
	if t != null and s.pos.distance_to(t.pos) < lr:
		return t.pos - s.pos
	var hv: Ship = null
	var hd := lr
	for o in b.ships:
		if o.dead or o.side == s.side or not o.heavy() or not Vision.sees(b, s.side, o):
			continue
		var d := s.pos.distance_to(o.pos)
		if d < hd:
			hd = d
			hv = o
	if hv != null:
		return hv.pos - s.pos
	if want.length_squared() > Movement.LOOK_MIN_V2:
		return want
	if s.vel.length_squared() > Movement.LOOK_MIN_V2:
		return s.vel
	return Vector2.ZERO
