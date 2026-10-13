# sim/air.gd — полёт и бой машин (space.js:1474 flyToward, 1489 leaveField, 1502
# updateCraft, 1097 craftAcquire, 514 fireMissile · часть 04, 2.4–2.10; доктрина
# 09, раздел 4). Перенос построчно с пометками `# space.js:NNNN имяJS · часть, раздел`;
# отличие — только помеченное `# ОТЛИЧИЕ: …` или `# ДОКТРИНА 09, …` (архитектура, 2.14).
#
# Механика машин — без изменений (09, 4.1): полёт, вираж, собачья свалка, заход
# и отворот бомбардировщика, ракеты, боезапас и перезарядка в космосе, посадка,
# уход пустых с поля. Доктрина меняет две вещи:
# - перехватчик без цели патрулирует над СВОЕЙ лёгкой линией — на air.patrol_k
#   отрезка между центрами линий тяжёлых, а не кружит у носителя (09, 4.2); чужой лёгкий
#   с патруля берёт только в полосе вокруг точки патруля (air.patrol_escort_*; поправлено
#   при доработке G3 — «эскорт ≤ 1000 от машины» уводил звено в ПВО чужих корветов);
# - бомбардировщик заходит С ФЛАНГА по двум точкам (0,5 и 1,0 того же отрезка,
#   полуширина чужого строя + air.bomber_flank_extra вбок) и возвращается за ракетами
#   тем же путём; цель — ближайший к точке 2 не-эскорт (09, 4.4). Флажок отката
#   «прямо на цель» — `--bomber-direct` (09, 8.4). Приказ «идти» — по прямой, без обхода
#   и без своих целей: звено летит в точку и ждёт там (09, 4.4, уточнено при доработке G3).
# Пока строя нет (G4), линия — центр тяжёлых в строю (sim/formation.gd → line_of): той
# же функцией, что потом.
#
# Бой плоский (09, 11.6): машины летают по плоскости; высота, «вверх» отворота
# и покачивание — картинка вида.
extends RefCounted

const State := preload("res://sim/state.gd")
const Defs := preload("res://sim/defs.gd")
const Ship := preload("res://sim/ship.gd")
const Body := preload("res://sim/body.gd")
const Craft := preload("res://sim/craft.gd")
const Squad := preload("res://sim/squad.gd")
const Proj := preload("res://sim/proj.gd")
const Weapons := preload("res://sim/weapons.gd")
const Hangar := preload("res://sim/hangar.gd")
const Formation := preload("res://sim/formation.gd")
const Vision := preload("res://sim/vision.gd")

# Числа JS, перенесённые как есть (часть 04, 2.4–2.10); числа доктрины — в doctrine.json.
const REV := 0.3                    # space.js:1127 thrustTo: против носа машины — 0,3 тяги
const INT_CRAFT := 1000.0           # space.js:1100: перехватчик — машина ≤ 1000
const INT_PROJ := 800.0             # …ракета или торпеда ≤ 800
const INT_ESCORT := 1000.0          # …эскорт ≤ 1000
const BMB_ANY := 2600.0             # space.js:1104: бомбардировщик — не-эскорт ≤ 2600, иначе любой
const FIG_CRAFT := 800.0            # space.js:1107: истребитель — машина ≤ 800
const FIG_ESCORT := 1300.0          # …эскорт ≤ 1300
const FIG_ANY := 1800.0             # …любой корабль ≤ 1800
const PATROL_R := 130.0             # space.js:1608: кружит в 130 у якоря
const PATROL_W := 0.35              # …угловая скорость 0,35 рад/с, фаза — номер машины
const T_PATROL := 0.7               # газ: кружить 0,7, к точке 0,9, на перезарядке 0,8
const T_MOVE := 0.9
const T_RELOAD := 0.8
const DOG_SHIP_K := 0.8             # space.js:1641: рабочая дистанция по кораблю min(0,8 wr, r + 34)
const DOG_SHIP_PAD := 34.0
const DOG_SMALL_K := 0.6            # …по машине и ракете 0,6 wr
const DOG_PASS_K := 0.75            # ближе 0,75 рабочей — проскочить
const DOG_PASS := 260.0             # …на 260 за цель
const DOG_PASS_WOBBLE := 60.0       # …с разводом по номеру машины
const DOG_AIM_WOBBLE := 20.0        # space.js:1649: на цель — с разводом ±20
const NOSE_DOT := 0.7               # space.js:1656: выстрел, если нос в ≈45,6° от цели
const BREAK_AWAY := 400.0           # space.js:1622: отворот — 400 назад от цели
const BREAK_MIN := 3.0              # space.js:1631: отворот 3,0…4,2 с
const BREAK_MAX := 4.2
const RAM_PAD := 30.0               # space.js:1634: ближе r + 30 — отворот на 3 с (не таранить)
const RAM_BREAK := 3.0
const LEAVE_OVER := 400.0           # space.js:1492: пустая машина уходит за край поля + 400
const LEAVE_EDGE := 40.0            # …исчезает дальше края − 40
const LEAVE_MAX := 25.0             # …или через 25 с (C8: не застрять)
const MISS_JITTER := 0.28           # space.js:520: промах — курс ракеты вбок до 0,28
## ДОКТРИНА 09, 4.4: точка маршрута бомбардировщика пройдена, если машина ближе этого.
## Постоянная кода, а не доктрины: радиус виража бомбардировщика v/ω = 72 / 1,05 ≈ 69,
## и с меньшим допуском машина кружила бы вокруг точки, а не проходила её.
const LEG_REACH := 90.0

## ТОЛЬКО для проверок отката (в игре всегда false):
## перезарядка в космосе мгновенная (04, 2.9: 7 и 11 с на перезарядке машина не воюет);
static var rollback_instant_reload := false
## «садиться некуда» — на каждом шаге, а не один раз на звено (C8; 04, ловушка 6);
static var rollback_tell_always := false
## пустая машина без носителя не уходит с поля (04, ловушка 7);
static var rollback_no_leave := false
## перехватчик с патруля берёт чужой эскорт в 1000 от СЕБЯ, как в JS и в G3 до доработки
## (09, 4.2: звено уходило с патруля в ПВО чужих корветов и гибло за 10 с);
static var rollback_patrol_any_escort := false
## бомбардировщик с приказом «идти» сначала обходит строй и берёт свои цели — как в G3
## до доработки (09, 4.4: «идти» — по прямой).
static var rollback_move_route := false


## Геометрия строя стороны на этом шаге (prepare): своя и чужая линии.
class Geo:
	var ok := false                  # есть своя и чужая линии
	var patrol_ok := false           # своя линия — по тяжёлым (09, 4.2: «если обе видны»)
	var p := Vector2.ZERO            # центр своей линии тяжёлых
	var f := Vector2.ZERO            # центр чужой линии (F_h или F, 09, 5.1)
	var ax := Vector2(0.0, -1.0)     # от своей к чужой
	var lat := Vector2(1.0, 0.0)     # вбок
	var d := 0.0                     # расстояние между центрами линий (в строю G4 — L)
	var foe_w := 0.0                 # полуширина чужого строя (шеренги и линия)


# ───────────────────────────── геометрия строя (09, 4.2, 4.4) ─────────────────────────────

## Один раз на шаг, до машин: линии обеих сторон, оси, ширина строя.
static func prepare(b: State) -> void:
	if b.crafts.is_empty():
		b.air_geo = []
		return
	var out: Array = []
	for side in 2:
		out.append(_geo(b, side))
	b.air_geo = out


static func _geo(b: State, side: int) -> Geo:
	var g := Geo.new()
	var own := Formation.line_of(b.ships, side)
	var foe := Formation.line_of(b.ships, 1 - side)
	if not own.has or not foe.has:
		return g
	g.ok = true
	g.patrol_ok = own.heavy
	g.p = own.center
	g.f = foe.center
	var v := g.f - g.p
	g.d = v.length()
	g.ax = v / g.d if g.d > 1.0 else Vector2(0.0, -b.sides[side].sign_z)
	g.lat = Vector2(-g.ax.y, g.ax.x)
	g.foe_w = Formation.half_width(b.ships, 1 - side, g.f, g.lat)
	return g


static func geo_of(b: State, side: int) -> Geo:
	if b.air_geo.size() != 2:
		return null
	var g: Geo = b.air_geo[side]
	return g


## ДОКТРИНА 09, 4.2: точка патруля перехватчиков — над своей лёгкой линией, на
## air.patrol_k отрезка между центрами линий (у игрока — та же доля, если обе линии
## есть; иначе — свой носитель, как сейчас). null-точки нет: ok = false.
static func patrol_point(b: State, side: int) -> Variant:
	var g := geo_of(b, side)
	if g == null or not g.ok or not g.patrol_ok:
		return null
	var k := 0.5 if b.patrol_mid else b.defs.doctrine.air_patrol_k
	return g.p + g.ax * (k * g.d)


## Перехватчик на патруле — без приказа игрока («бить», «идти», «на посадку») и есть точка
## патруля: → она, иначе null (тогда цели — как в JS, от самой машины).
static func _patrol_of(b: State, c: Craft) -> Variant:
	if c.role != &"interceptor" or rollback_patrol_any_escort:
		return null
	var q := c.squad as Squad
	if q == null or q.target != null or q.has_move or q.recall:
		return null
	return patrol_point(b, c.side)


## ДОКТРИНА 09, 4.4: две точки обхода с фланга: на глубине air.bomber_flank_points_k
## отрезка между линиями и на полуширину чужого строя + air.bomber_flank_extra вбок,
## со стороны цели (цель на оси — постоянный фланг звена). Пусто — геометрии нет.
static func route_points(b: State, q: Squad) -> PackedVector2Array:
	var out := PackedVector2Array()
	var g := geo_of(b, q.side)
	if g == null or not g.ok:
		return out
	var sgn := q.flank
	var t := q.target as Ship
	if t != null and not t.dead:
		var off := (t.pos - g.f).dot(g.lat)
		if absf(off) > 1.0:
			sgn = signf(off)
	var w := g.foe_w + b.defs.doctrine.air_bomber_flank_extra
	for k in b.defs.doctrine.air_bomber_flank_points_k:
		out.append(g.p + g.ax * (k * g.d) + g.lat * (sgn * w))
	return out


# ───────────────────────────── полёт (часть 04, 2.5) ─────────────────────────────

# space.js:1474 flyToward · часть 04, 2.5 (face, thrustTo, предел, integrate — часть 02)
## Нос — к точке (доля оставшегося угла turn × dt), тяга — ПО НОСУ на maxSpeed × газ:
## машина летит туда, куда смотрит, и разворачивается дугой — это и есть вираж.
static func fly(b: State, c: Craft, aim: Vector2, throttle: float) -> void:
	var dt := State.STEP
	var def := c.def
	var v := aim - c.pos
	if v.length_squared() > 1e-8:
		var want := atan2(-v.x, -v.y)
		var k := clampf(def.turn * dt, 0.0, 1.0)
		c.set_yaw(c.yaw + wrapf(want - c.yaw, -PI, PI) * k)
	var desired := c.dir * (def.max_speed * throttle)
	var need_v := desired - c.vel
	var need := need_v.length()
	if need > 1e-4:
		var nrm := need_v / need
		var align := maxf(0.0, c.dir.dot(nrm))
		var power := def.thrust * (REV + (1.0 - REV) * align)
		c.vel += nrm * minf(need, power * dt)
	var cap := def.max_speed * b.mp.craft_cap_k
	var spd := c.vel.length()
	if spd > cap:
		c.vel *= cap / spd
	c.pos += c.vel * dt
	var field := b.mp.field
	if c.pos.x > field:
		c.pos.x = field
		if c.vel.x > 0.0: c.vel.x *= -0.3
	if c.pos.x < -field:
		c.pos.x = -field
		if c.vel.x < 0.0: c.vel.x *= -0.3
	if c.pos.y > field:
		c.pos.y = field
		if c.vel.y > 0.0: c.vel.y *= -0.3
	if c.pos.y < -field:
		c.pos.y = -field
		if c.vel.y < 0.0: c.vel.y *= -0.3


# ───────────────────────────── шаг машины (часть 04, 2.4) ─────────────────────────────

# space.js:1502 updateCraft · часть 04, 2.4 — по порядку, первый return заканчивает шаг
static func update_craft(b: State, c: Craft) -> void:
	var q := c.squad as Squad
	var tb := c.target as Body
	if tb != null and (tb.dead or not Vision.sees_body(b, c.side, tb)):
		c.target = null                       # 1. цель погибла или скрылась (C18)
	elif tb != null and tb.kind == Body.SHIP:
		# ДОКТРИНА 09, 4.2: с патруля чужой лёгкий — только в своей полосе; ушёл дальше
		# air.patrol_escort_drop от точки патруля — бросить (не гнаться до чужой шеренги)
		var pp: Variant = _patrol_of(b, c)
		if pp != null:
			var ppv: Vector2 = pp
			if tb.pos.distance_to(ppv) > b.defs.doctrine.air_patrol_escort_drop:
				c.target = null
	# 2. след — картинка вида (по игровому времени, 04, 2.21)
	if c.leaving:                             # 3. пустая без носителя — с поля
		_leave_field(b, c)
		return
	if c.def.weapon_kind == &"missile":       # 4. боезапас — только у ракетных
		if c.reloading > 0.0:
			c.reloading -= State.STEP
			if c.reloading <= 0.0 or rollback_instant_reload:
				c.reloading = 0.0
				c.ammo = c.def.ammo
				c.leg = 0                     # ДОКТРИНА 09, 4.4: снова в обход
				c.back = 0
				b.events.append([&"reload", c.uid])
			else:
				# на перезарядке машина из боя выходит и держится у носителя (не воюет)
				_go_home(b, c, q, T_RELOAD)
				return
		elif c.ammo <= 0:
			if c.reloads > 0:
				c.reloads -= 1
				c.reloading = c.def.reload_time
				if c.slot == 0 and q != null and q.side == b.player_side:
					b.toast("%s: перезарядка, осталось %d %s" % [c.def.name, c.reloads, _plural(c.reloads, "комплект", "комплекта", "комплектов")])
				return
			if q != null and not q.recall:
				q.recall = true               # возвращается ВСЁ звено, а не машина (04, 2.9)
				if q.side == b.player_side and not q.told_empty:
					q.told_empty = true
					b.toast("%s: ракеты кончились, звено уходит на носитель" % c.def.name)
	if q != null and q.recall:                # 5. возврат и посадка
		var home := Hangar.home_of(q)
		if home == null:
			home = Hangar.rehome(b, q)
		if home != null:
			if c.pos.distance_to(home.pos) < home.def.radius * Hangar.LAND_K:
				Hangar.land(b, c, home)
				return
			_go_home(b, c, q, 1.0)
			return
		q.recall = false                      # садиться некуда
		var empty := c.def.weapon_kind == &"missile" and c.ammo <= 0 and c.reloads <= 0
		if empty and not rollback_no_leave:
			c.leaving = true
			if q.side == b.player_side and (not q.told_leave or rollback_tell_always):
				q.told_leave = true
				b.toast("%s: ракет нет, садиться некуда — машины выходят из боя" % c.def.name)
			return
		if q.side == b.player_side and (not q.told_no_home or rollback_tell_always):
			q.told_no_home = true
			var any := false
			for s in b.ships:
				any = any or (not s.dead and not s.charging() and s.side == q.side and s.hangar != null)
			b.toast("%s: садиться некуда — %s" % [c.def.name, "все ангары заняты" if any else "носителей не осталось"])
	var go := going(c)
	# ДОКТРИНА 09, 4.4: бомбардировщик сначала обходит строй с фланга
	if routing(b, c):
		if _route_out(b, c, q):
			return
	if c.target == null and not go:           # 6. цель: приказ звена или своя
		c.target = live_target(b, c, q.target if q != null else null)
		if c.target == null:
			c.target = acquire(b, c, c.pos)
	var t := c.target as Body
	if t == null:                             # 7. целей нет — к точке приказа или патруль
		if q != null and q.has_move:
			fly(b, c, q.move_to, T_MOVE)
			return
		var anchor := Vector2.ZERO
		var home2 := Hangar.home_of(q) if q != null else null
		if home2 != null:
			anchor = home2.pos
		if c.role == &"interceptor":
			var pp: Variant = patrol_point(b, c.side)
			if pp != null:
				anchor = pp                   # ДОКТРИНА 09, 4.2: над своей лёгкой линией
		var ph := b.time * PATROL_W + float(c.slot)
		fly(b, c, anchor + Vector2(sin(ph), cos(ph)) * PATROL_R, T_PATROL)
		return
	var d := c.pos.distance_to(t.pos)
	var wr := c.def.rng
	if c.role == &"bomber":                   # 8. заход, пуск, отворот
		_bomber(b, c, t, d, wr)
		return
	_dogfight(b, c, t, d, wr)                 # 9. собачья свалка


## ДОКТРИНА 09, 4.4: бомбардировщик с приказом «идти» летит в точку по прямой — без обхода
## и без своих целей. Свой поиск у бомбардировщика — не-эскорт в 2600, то есть всё поле,
## и у JS «идти» сразу становилось налётом напрямик сквозь шеренги (уточнено при
## доработке G3). Звено ждёт у точки, бьёт — по приказу.
static func going(c: Craft) -> bool:
	var q := c.squad as Squad
	return c.role == &"bomber" and q != null and q.has_move and not rollback_move_route


## Бомбардировщик сейчас на маршруте обхода (09, 4.4): не напрямик, точки не пройдены, не
## «идти». Одно правило на модель и строку «чем занято звено» (ui/polygon_hud.gd).
static func routing(b: State, c: Craft) -> bool:
	return c.role == &"bomber" and not b.bomber_direct and c.leg < 2 and not going(c)


## Цель по приказу звена (space.js:1000 liveTarget): корабль — он сам, если жив и
## виден; звено — ближайшая к машине живая машина этого звена (C14).
static func live_target(b: State, c: Craft, t: RefCounted) -> Body:
	if t == null:
		return null
	var s := t as Ship
	if s != null:
		return s if not s.dead and Vision.sees(b, c.side, s) else null
	var q := t as Squad
	if q != null:
		return Hangar.live_craft(q, c.pos)
	return null


# space.js:1097 craftAcquire · часть 04, 2.6 — ближайший подходящий в радиусе от from
static func acquire(b: State, c: Craft, from: Vector2) -> Body:
	var foe := 1 - c.side
	match c.role:
		&"interceptor":
			var x: Body = _near_craft(b, from, INT_CRAFT, foe)
			if x == null:
				x = _near_proj(b, from, INT_PROJ, foe)
			if x == null:
				var pp: Variant = _patrol_of(b, c)
				if pp == null:
					x = _near_ship(b, from, INT_ESCORT, foe, 1)
				else:
					# ДОКТРИНА 09, 4.2 (поправлено при доработке G3): с патруля — только чужой
					# лёгкий ближе air.patrol_escort_take к точке патруля, ближайший к машине
					var ppv: Vector2 = pp
					x = _near_ship(b, from, INT_ESCORT, foe, 1, ppv, b.defs.doctrine.air_patrol_escort_take)
			return x
		&"bomber":
			var s := _near_ship(b, from, BMB_ANY, foe, -1)
			if s == null:
				s = _near_ship(b, from, BMB_ANY, foe, 0)
			return s
	var y: Body = _near_craft(b, from, FIG_CRAFT, foe)
	if y == null:
		y = _near_ship(b, from, FIG_ESCORT, foe, 1)
	if y == null:
		y = _near_ship(b, from, FIG_ANY, foe, 0)
	return y


## Ближайший корабль стороны side СТРОГО ближе r. escort: 1 — только эскорт, −1 — только
## не-эскорт, 0 — любой (space.js:1012 nearest; РЭБ — класса escort, 04, 2.6).
## band > 0 — ещё и не дальше band от точки at (полоса патруля, 09, 4.2).
static func _near_ship(b: State, from: Vector2, r: float, side: int, escort: int, at: Vector2 = Vector2.ZERO, band: float = 0.0) -> Ship:
	var best: Ship = null
	var bd := r * r
	var band2 := band * band
	for s in b.ships:
		if s.dead or s.side != side or not Vision.sees(b, 1 - side, s):
			continue
		var is_e := s.def.cls == &"escort"
		if (escort == 1 and not is_e) or (escort == -1 and is_e):
			continue
		if band > 0.0 and s.pos.distance_squared_to(at) >= band2:
			continue
		var d := from.distance_squared_to(s.pos)
		if d < bd:
			bd = d
			best = s
	return best


static func _near_craft(b: State, from: Vector2, r: float, side: int) -> Craft:
	var best: Craft = null
	var bd := r * r
	for x in b.crafts:
		if x.dead or x.side != side or not Vision.sees_body(b, 1 - side, x):
			continue
		var d := from.distance_squared_to(x.pos)
		if d < bd:
			bd = d
			best = x
	return best


static func _near_proj(b: State, from: Vector2, r: float, side: int) -> Proj:
	var best: Proj = null
	var bd := r * r
	for p in b.projs:
		if p.dead or p.side != side:
			continue
		var d := from.distance_squared_to(p.pos)
		if d < bd:
			bd = d
			best = p
	return best


# space.js:1640–1670 · часть 04, 2.7 — перехватчик и истребитель
static func _dogfight(b: State, c: Craft, t: Body, d: float, wr: float) -> void:
	var desired := minf(wr * DOG_SHIP_K, t.hit_r + DOG_SHIP_PAD) if t.kind == Body.SHIP else wr * DOG_SMALL_K
	var aim: Vector2
	if d < desired * DOG_PASS_K:
		aim = c.pos + (c.pos - t.pos).normalized() * DOG_PASS
		aim.x += sin(b.time + float(c.slot) * 2.0) * DOG_PASS_WOBBLE
	else:
		aim = t.pos
		aim.x += sin(b.time * 1.3 + float(c.slot) * 1.7) * DOG_AIM_WOBBLE
	fly(b, c, aim, 1.0)
	c.cd -= State.STEP                        # убывает ТОЛЬКО здесь (04, 2.7)
	if d <= wr and c.cd <= 0.0:
		var to := (t.pos - c.pos) / maxf(d, 1e-6)
		if c.dir.dot(to) > NOSE_DOT:
			c.cd = c.def.cd
			if c.def.weapon_kind == &"missile":
				if c.ammo > 0:
					fire_missile(b, c, t)
			else:
				# перехватчик — пушки без боезапаса, мгновенное попадание; урон со сложностью
				c.reveal_until = b.time + b.defs.stealth.reveal_for
				b.events.append([&"craft_fire", c.uid, t.uid, t.pos])
				Weapons.damage(b, t, c.def.dmg * Weapons.aim_of(b, c.side), c.def.weapon, c, to)


# space.js:1618–1637 · часть 04, 2.7 — бомбардировщик: заход, пуск, отворот
static func _bomber(b: State, c: Craft, t: Body, d: float, wr: float) -> void:
	if c.phase == &"break":
		if b.time > c.break_until:
			c.phase = &"out"
		else:
			# отворот — 400 назад по линии «цель → я» (после захода с фланга — наружу,
			# мимо шеренг, 09, 4.4); «вверх» — картинка
			fly(b, c, c.pos + (c.pos - t.pos).normalized() * BREAK_AWAY, 1.0)
			return
	fly(b, c, t.pos, 1.0)
	c.cd -= State.STEP
	if d < wr and c.cd <= 0.0 and c.ammo > 0:
		c.cd = c.def.cd
		fire_missile(b, c, t)
		c.phase = &"break"
		c.break_until = b.time + b.rng.randf_range(BREAK_MIN, BREAK_MAX)
	if d < t.hit_r + RAM_PAD:
		c.phase = &"break"
		c.break_until = b.time + RAM_BREAK


# space.js:514 fireMissile · часть 04, 2.8 — урон БЕЗ сложности; промах — без цели
static func fire_missile(b: State, c: Craft, t: Body) -> Proj:
	var miss := b.rng.randf() < c.def.miss_chance
	var co := b.defs.consts
	var spd := c.def.missile_speed if c.def.missile_speed > 0.0 else co.missile_defaults_speed
	var hp := c.def.missile_hp if c.def.missile_hp > 0.0 else co.missile_defaults_hp
	var p := Weapons.spawn_proj(b, c, t, c.def.dmg, c.def.weapon, spd, hp, (t.pos - c.pos).normalized())
	if miss:
		p.target = null                       # головка не захватила — уйдёт мимо и не попадёт ни в кого
		p.dir = (p.dir + Vector2(b.rng.randf_range(-1.0, 1.0), b.rng.randf_range(-1.0, 1.0)) * MISS_JITTER).normalized()
		p.life = co.missile_miss_life
	c.ammo -= 1
	c.reveal_until = b.time + b.defs.stealth.reveal_for
	return p


# ───────────────────────────── маршрут бомбардировщика (09, 4.4) ─────────────────────────────

## Туда: носитель → точка 1 → точка 2 → заход на ближайший к точке 2 не-эскорт.
## → true, если шаг ушёл на маршрут.
static func _route_out(b: State, c: Craft, q: Squad) -> bool:
	if q == null:
		c.leg = 2
		return false
	var pts := route_points(b, q)
	if pts.size() < 2:
		c.leg = 2
		return false
	# уже дальше точки 1 по пути к точке 2 (поднят с фланга) — угол не срезаем
	if c.leg == 0 and c.pos.distance_to(pts[1]) < pts[0].distance_to(pts[1]):
		c.leg = 1
	if c.pos.distance_to(pts[c.leg]) < LEG_REACH:
		c.leg += 1
	if c.leg < 2:
		fly(b, c, pts[c.leg], 1.0)
		return true
	# дошли до точки 2: цель — приказ звена или ближайший к точке 2 не-эскорт
	c.phase = &"out"
	c.target = live_target(b, c, q.target)
	if c.target == null:
		c.target = acquire(b, c, pts[1])
	return false


## Домой (посадка или перезарядка): бомбардировщик — тем же путём назад, через точку 2
## и точку 1 (09, 4.4: прямой путь с фланга к носителю проходит в ПВО шеренги).
static func _go_home(b: State, c: Craft, q: Squad, throttle: float) -> void:
	var home := Hangar.home_of(q) if q != null else null
	var goal := home.pos if home != null else Vector2.ZERO
	if c.role == &"bomber" and not b.bomber_direct and c.leg > 0 and c.back < 2:
		var pts := route_points(b, q)
		if pts.size() >= 2:
			if c.back == 0 and c.pos.distance_to(pts[0]) < pts[1].distance_to(pts[0]):
				c.back = 1
			if c.back == 1 and c.pos.distance_to(goal) < pts[0].distance_to(goal):
				c.back = 2
			if c.back < 2:
				var at := pts[1 - c.back]
				if c.pos.distance_to(at) < LEG_REACH:
					c.back += 1
				if c.back < 2:
					fly(b, c, pts[1 - c.back], throttle)
					return
	fly(b, c, goal, throttle)


# space.js:1489 leaveField · часть 04, 2.10
static func _leave_field(b: State, c: Craft) -> void:
	c.leave_t += State.STEP
	var field := b.defs.consts.field_half
	fly(b, c, Vector2(c.pos.x, b.sides[c.side].sign_z * (field + LEAVE_OVER)), 1.0)
	if absf(c.pos.y) < field - LEAVE_EDGE and c.leave_t < LEAVE_MAX:
		return
	Hangar.leave(b, c)


static func _plural(n: int, one: String, few: String, many: String) -> String:
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return one
	if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14):
		return few
	return many


# ───────────────────────────── приказы звеньям (часть 04, 2.13) ─────────────────────────────

## Звено бьёт цель (корабль или чужое звено): recall и «идти» снимаются, цели машин
## сброшены. Бомбардировщики по авиации не стреляют — отказ. → принял ли.
static func order_attack(q: Squad, t: RefCounted) -> bool:
	if t is Squad and q.role == &"bomber":
		return false
	q.target = t
	q.recall = false
	q.has_move = false
	for c in q.craft:
		c.target = null
		c.back = 0
		if c.role == &"bomber":
			c.leg = 0                         # ДОКТРИНА 09, 4.4: приказ «атаковать» — тем же маршрутом
	return true


static func order_move(q: Squad, at: Vector2) -> void:
	q.has_move = true
	q.move_to = at
	q.target = null
	q.recall = false
	for c in q.craft:
		c.target = null
		c.back = 0


static func order_recall(q: Squad) -> void:
	q.recall = true
	for c in q.craft:
		c.back = 0
