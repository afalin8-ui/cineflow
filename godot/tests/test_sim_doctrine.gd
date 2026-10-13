# tests/test_sim_doctrine.gd — доктрина тяжёлых и строй (план G4; 09, разделы 2, 3, 5, 8).
# Каждая проверка — с откатом: флажок модуля (`rollback_*`) или флажок состава боя (09, 8.4),
# и откат обязан краснеть ИМЕННО той проверкой, рядом с которой стоит.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const HeavyDoctrine := preload("res://sim/heavy_doctrine.gd")
const Formation := preload("res://sim/formation.gd")
const BenchCore := preload("res://tools/bench_core.gd")

const BIG := 1.0e9

var defs: Defs


func _defs() -> Defs:
	if defs == null:
		defs = Defs.load_default() as Defs
	return defs


func _lab(setup: Dictionary = {}, d: Defs = null) -> Battle:
	var st := {"attacker": &"troyden", "defender": &"plektor", "size": &"small", "seed": 5, "reserve": false}
	st.merge(setup, true)
	var b := Battle.create(d if d != null else _defs(), st) as Battle
	b.ships.clear()
	return b


func _put(b: Battle, side: int, clan: StringName, id: StringName, pos: Vector2) -> Ship:
	return b.spawn(side, b.defs.ship(clan, id), pos)


## Бессмертный и безоружный: проверяем движение, а не исход.
func _tough(s: Ship) -> Ship:
	s.hp = BIG
	s.max_hp = BIG
	s.main_cd = PackedFloat64Array()
	s.sec_cd = PackedFloat64Array()
	s.light_cd = PackedFloat64Array()
	s.mis_cd = PackedFloat64Array()
	s.pd_cd = PackedFloat64Array()
	return s


## Мишень: не летит и не поворачивается, прочная, без оружия.
func _dummy(s: Ship) -> Ship:
	s.switch_off(&"engines", BIG)
	s.stance = &"hold"
	return _tough(s)


func _steps(b: Battle, secs: float) -> void:
	for i in roundi(secs / Battle.STEP):
		b.step()


## Были ли у корабля такие состояния пояса за бой (журнал смен — belt_log).
static func _had(b: Battle, uid: int, st: int) -> bool:
	for r: Array in b.belt_log:
		var u: int = r[1]
		var to: int = r[3]
		if u == uid and to == st:
			return true
	return false


# ───────────────────────── подход: доля сближения (09, 2.3, п. 1) ─────────────────────────

## Два тяжёлых навстречу с 1300, оба на «Охоте», стреляют мимо (оружия нет — меряется
## подход). → [ближе всего, R пары].
func _head_on(a: StringName, d: StringName, no_share: bool) -> Vector2:
	var b := _lab({"no_share_close": no_share})
	var s1 := _tough(_put(b, Ship.ATTACKER, &"troyden", a, Vector2(0, 650)))
	var s2 := _tough(_put(b, Ship.DEFENDER, &"plektor", d, Vector2(0, -650)))
	s1.stance = &"hunt"
	s2.stance = &"hunt"
	var mind := INF
	for i in roundi(30.0 / Battle.STEP):
		b.step()
		mind = minf(mind, s1.pos.distance_to(s2.pos))
	var r := minf(s1.def.main.rng, s2.def.main.rng)
	b.dispose()
	return Vector2(mind, r)


func test_head_on_share_of_closing() -> void:
	for pr: Array in [[&"cruiser", &"cruiser"], [&"cruiser", &"capital"], [&"capital", &"capital"]]:
		var a: StringName = pr[0]
		var d: StringName = pr[1]
		var r := _head_on(a, d, false)
		note("навстречу %s — %s: ближе всего %.0f (%.3f R)" % [a, d, r.x, r.x / r.y])
		ok(r.x >= 0.75 * r.y, "%s и %s навстречу: сходятся не ближе 0,75 R — %.0f (%.2f R)" % [a, d, r.x, r.x / r.y])
	var o := _head_on(&"cruiser", &"cruiser", true)
	note("откат --no-share-close: два крейсера сходятся до %.0f (%.3f R)" % [o.x, o.x / o.y])
	ok(o.x < 0.7 * o.y, "откат «без доли сближения»: два крейсера проскакивают до %.0f (%.2f R; 09, 2.3 — 525) — проверка краснеет" % [o.x, o.x / o.y])


# ───────────────────────── отход задним ходом (09, 2.4) ─────────────────────────

## Корабль стоит, враг (неподвижный крейсер) в 200 по носу; отход продлён, чтобы мерить
## таблицу 2.4 (belt.back_off_k = 5: «до 0,5 R» наступило бы через пару секунд). →
## отошёл за 10 и 30 с и сколько из 30 с нос держал врага в конусе главного калибра.
func _back_off(clan: StringName, id: StringName, nose_along: bool) -> Vector3:
	HeavyDoctrine.rollback_nose_along = nose_along
	var d := Defs.load_default({"belt.back_off_k": 5.0}) as Defs
	var b := _lab({"attacker": clan}, d)
	var s := _tough(_put(b, Ship.ATTACKER, clan, id, Vector2(0, 0)))
	s.stance = &"hunt"
	var e := _dummy(_put(b, Ship.DEFENDER, &"plektor", &"cruiser", Vector2(0, -200)))
	var at10 := 0.0
	var cone := 0.0
	var cone_cos := b.defs.consts.turret_arc_ship      # конус главного калибра (03, 2.20)
	for i in roundi(30.0 / Battle.STEP):
		b.step()
		if s.dir.dot((e.pos - s.pos).normalized()) >= cone_cos:
			cone += Battle.STEP
		if i + 1 == roundi(10.0 / Battle.STEP):
			at10 = s.pos.length()
	var out := Vector3(at10, s.pos.length(), cone)
	b.dispose()
	HeavyDoctrine.rollback_nose_along = false
	return out


func test_retreat_backward_table_2_4() -> void:
	var want := {&"cruiser": [&"troyden", 260.0, 1020.0], &"capital": [&"troyden", 193.0, 793.0], &"sinho": [&"plektor", 176.0, 716.0]}
	for id: StringName in want:
		var w: Array = want[id]
		var clan: StringName = w[0]
		var w10: float = w[1]
		var w30: float = w[2]
		var r := _back_off(clan, id, false)
		note("отход задним ходом %s: за 10 с %.0f, за 30 с %.0f, главный калибр мог бить %.1f с из 30" % [id, r.x, r.y, r.z])
		near(r.x, w10, 5.0, "%s: задним ходом за 10 с — %.0f (09, 2.4: %.0f)" % [id, r.x, w10])
		near(r.y, w30, 5.0, "%s: за 30 с — %.0f (09, 2.4: %.0f)" % [id, r.y, w30])
		ok(r.z >= 29.0, "%s: нос на враге весь отход — главный калибр мог бить %.1f с из 30" % [id, r.z])
	var o := _back_off(&"troyden", &"cruiser", true)
	note("откат «нос по ходу» (разворот кормой): крейсер за 30 с %.0f, главный калибр мог бить %.1f с" % [o.y, o.z])
	ok(o.z < 5.0, "откат «нос по ходу отхода»: главный калибр молчит (%.1f с из 30) — проверка краснеет" % o.z)


# ───────────────────────── разворот на 180° (09, 2.4; часть 02, 2.3) ─────────────────────────

## Нос от врага, враг — цель главного калибра в поясе; корабль на «Держать» (стоит, только
## поворачивается). → сколько секунд до носа в ±5°. turn_k — множитель разворота (откат
## правкой числа, как --set).
func _turn_180(clan: StringName, id: StringName, turn_k: float) -> float:
	var over := {}
	if turn_k != 1.0:
		var t0: float = _defs().ship(clan, id).turn
		over["space.ships.%s.%s.turn" % [clan, id]] = t0 * turn_k
	var d := Defs.load_default(over) as Defs
	var b := _lab({"attacker": clan}, d)
	var s := _tough(_put(b, Ship.ATTACKER, clan, id, Vector2(0, 0)))
	s.stance = &"hold"
	s.set_yaw(PI)                                     # нос на +z, враг на −z
	var e := _dummy(_put(b, Ship.DEFENDER, &"plektor", &"cruiser", Vector2(0, -600)))
	s.target = e
	var got := -1.0
	for i in roundi(30.0 / Battle.STEP):
		b.step()
		if s.dir.dot((e.pos - s.pos).normalized()) >= cos(deg_to_rad(5.0)):
			got = b.time
			break
	b.dispose()
	return got


func test_turn_180() -> void:
	var want := {&"cruiser": [&"troyden", 9.0], &"capital": [&"troyden", 13.8], &"sinho": [&"plektor", 14.9]}
	for id: StringName in want:
		var w: Array = want[id]
		var clan: StringName = w[0]
		var t: float = w[1]
		var got := _turn_180(clan, id, 1.0)
		note("разворот на 180° %s: %.2f с (09, 2.4: %.1f)" % [id, got, t])
		near(got, t, 0.2, "%s: разворот на 180° до ±5° — %.2f с (09, 2.4: %.1f)" % [id, got, t])
	var o := _turn_180(&"troyden", &"cruiser", 1.5)
	ok(absf(o - 9.0) > 0.5, "откат «разворот × 1,5» (правка turn): крейсер за %.2f с — проверка краснеет" % o)


# ───────────────────────── «не оторваться» (09, 2.6, п. 2; 9.5 пп. 13, 19) ─────────────────────────

## Крейсер шёл вперёд на полном ходу, корвет-мишень вплотную по курсу. Первые секунды отход
## только гасит встречный ход — расстояние ПАДАЕТ, и это не «не оторваться». Откат —
## часы с начала отхода, окно «было» 6 с (rollback_futile_from_start).
func _braking_retreat(rollback: bool) -> Dictionary:
	HeavyDoctrine.rollback_futile_from_start = rollback
	var b := _lab()
	var s := _tough(_put(b, Ship.ATTACKER, &"troyden", &"cruiser", Vector2(0, 0)))
	s.stance = &"hunt"
	s.vel = Vector2(0, -s.max_speed())
	var e := _dummy(_put(b, Ship.DEFENDER, &"plektor", &"corvette", Vector2(0, -280)))
	var mind := INF
	for i in roundi(25.0 / Battle.STEP):
		b.step()
		mind = minf(mind, s.pos.distance_to(e.pos))
	var out := {"futile": _had(b, s.uid, HeavyDoctrine.FUTILE), "min": mind, "end": s.pos.distance_to(e.pos),
		"belt": HeavyDoctrine.NAMES[s.belt]}
	b.dispose()
	HeavyDoctrine.rollback_futile_from_start = false
	return out


func test_futile_not_on_braking() -> void:
	var dc := _defs().doctrine
	var r0: float = _defs().ship(&"troyden", &"cruiser").main.rng
	var r := _braking_retreat(false)
	note("отход с хода: ближе всего %.0f, в конце %.0f, «%s»" % [num(r["min"]), num(r["end"]), str(r["belt"])])
	ok(not flag(r["futile"]), "гашение встречного хода — не «не оторваться» (09, 9.5 п. 19)")
	ok(num(r["end"]) >= dc.belt_back_off_k * r0 - 10.0, "отход дошёл до 0,5 R: %.0f" % num(r["end"]))
	var o := _braking_retreat(true)
	ok(flag(o["futile"]), "откат «часы с начала отхода, окно 6 с»: объявлено «не оторваться» на гашении хода — проверка краснеет")


## Корвет преследует крейсер (своя «Охота», держит своё расстояние): отход не отрывается,
## «не оторваться» срабатывает, и, пока корвет рядом, повода отходить нет — тяжёлый стоит.
## Откат «забыть через 15 с, где бы враг ни был»: отход заново каждые ~20 с (09, 0.2 п. 4).
## Мерило — сколько раз отход начался: уползти за 120 с откат не успевает (каждый новый
## отход тут же снова «не оторваться», 108 против 277), а вот дёргаться — да.
func _chase(rollback: bool) -> Dictionary:
	HeavyDoctrine.rollback_forget_15s = rollback
	var b := _lab()
	var s := _tough(_put(b, Ship.ATTACKER, &"troyden", &"cruiser", Vector2(0, 0)))
	s.stance = &"hunt"
	var c := _put(b, Ship.DEFENDER, &"plektor", &"corvette", Vector2(0, -250))
	c.stance = &"hunt"
	c.hp = BIG
	c.max_hp = BIG
	var starts := 0
	var was := false
	for i in roundi(120.0 / Battle.STEP):
		b.step()
		var ret := s.belt == HeavyDoctrine.RETREAT
		if ret and not was:
			starts += 1
		was = ret
	var out := {"crawl": s.pos.length(), "starts": starts, "futile": _had(b, s.uid, HeavyDoctrine.FUTILE)}
	b.dispose()
	HeavyDoctrine.rollback_forget_15s = false
	return out


func test_chase_does_not_crawl() -> void:
	var r := _chase(false)
	note("погоня 120 с: крейсер сместился на %.0f, отходов %d" % [num(r["crawl"]), whole(r["starts"])])
	ok(flag(r["futile"]), "корвет держится рядом — «не оторваться» срабатывает")
	ok(whole(r["starts"]) <= 1, "погоня рядом не запускает отход заново: отходов за 120 с — %d (09, 9.5 п. 13)" % whole(r["starts"]))
	ok(num(r["crawl"]) <= 400.0, "тяжёлый не уползает: за 120 с погони %.0f (≤ 400)" % num(r["crawl"]))
	var o := _chase(true)
	note("откат «забыть через 15 с»: сместился на %.0f, отходов %d" % [num(o["crawl"]), whole(o["starts"])])
	ok(whole(o["starts"]) >= 4, "откат «забыть через 15 с где угодно»: отход заново каждые ~20 с — %d раз за 120 с — проверка краснеет" % whole(o["starts"]))


## Корвет гонится, а у тяжёлого есть цель главного калибра — чужой крейсер-мишень в 716
## (замечание к G4; 09, 2.6 и 6.3). «Не оторваться» обязано ДЕРЖАТЬСЯ, пока корвет ближе
## 0,5 R: тяжёлый стоит и бьёт батареей. Откат — «не оторваться» на один шаг (дальше
## «держит дистанцию» до корвета в мёртвой зоне или «путь закрыт»). → доля секунд
## в «не оторваться» после первого срабатывания и сдвиг.
func _futile_hold(rollback: bool, focus: bool) -> Vector2:
	HeavyDoctrine.rollback_futile_one_step = rollback
	var b := _lab()
	var s := _tough(_put(b, Ship.ATTACKER, &"troyden", &"cruiser", Vector2(0, 0)))
	s.stance = &"hunt"
	_dummy(_put(b, Ship.DEFENDER, &"plektor", &"cruiser", Vector2(0, -716)))
	var c := _tough(_put(b, Ship.DEFENDER, &"plektor", &"corvette", Vector2(0, -250)))
	c.stance = &"hunt"
	if focus:
		b.queue({"op": &"focus", "ids": [s.uid], "target": c.uid})
	var after := 0.0
	var held := 0.0
	var seen := false
	for i in roundi(40.0 / Battle.STEP):
		b.step()
		seen = seen or s.belt == HeavyDoctrine.FUTILE
		if seen:
			after += Battle.STEP
			if s.belt == HeavyDoctrine.FUTILE:
				held += Battle.STEP
	var out := Vector2(held / after if after > 0.0 else 0.0, s.pos.length())
	b.dispose()
	HeavyDoctrine.rollback_futile_one_step = false
	return out


func test_futile_holds_with_heavy_target() -> void:
	for focus: bool in [true, false]:
		var r := _futile_hold(false, focus)
		note("корвет гонится, чужой крейсер в 716%s: «не оторваться» %.0f%% времени после срабатывания, сдвиг %.0f" % [", фокус на корвете" if focus else "", r.x * 100.0, r.y])
		ok(r.x >= 0.99, "«не оторваться» держится, пока корвет рядом%s: %.0f%% времени" % [" (фокус на корвете)" if focus else "", r.x * 100.0])
		ok(r.y <= 300.0, "тяжёлый стоит, а не пятится дальше: сдвиг %.0f" % r.y)
	var o := _futile_hold(true, true)
	note("откат «не оторваться на один шаг»: %.1f%% времени" % (o.x * 100.0))
	ok(o.x < 0.1, "откат «не оторваться на один шаг»: %.1f%% времени после срабатывания — проверка краснеет" % (o.x * 100.0))


## Погоня двумя-тремя корветами (у каждого фокус на тяжёлом): отход один, тяжёлый не уползает
## (09, 2.6; замечание к G4: по одному «не оторваться» на каждого корвета — отход заново
## от каждого, 1 корвет 277, 2 — 432, 3 — 583–728). → сдвиг за 120 с и сколько раз начался отход.
func _pack_chase(n: int, rollback: bool) -> Vector2:
	HeavyDoctrine.rollback_futile_one_foe = rollback
	var b := _lab()
	var s := _tough(_put(b, Ship.ATTACKER, &"troyden", &"cruiser", Vector2(0, 0)))
	s.stance = &"hunt"
	for k in n:
		var c := _tough(_put(b, Ship.DEFENDER, &"plektor", &"corvette", Vector2((k - (n - 1) * 0.5) * 80.0, -250.0)))
		c.stance = &"hunt"
		b.queue({"op": &"focus", "ids": [c.uid], "target": s.uid})
	var starts := 0
	var was := false
	var far := 0.0
	for i in roundi(120.0 / Battle.STEP):
		b.step()
		var ret := s.belt == HeavyDoctrine.RETREAT
		if ret and not was:
			starts += 1
		was = ret
		far = maxf(far, s.pos.length())
	b.dispose()
	HeavyDoctrine.rollback_futile_one_foe = false
	return Vector2(far, starts)


func test_chase_by_pack_does_not_crawl() -> void:
	for n: int in [2, 3]:
		var r := _pack_chase(n, false)
		note("погоня %d корветами, 120 с: сдвиг %.0f, отходов %d" % [n, r.x, roundi(r.y)])
		ok(r.x <= 400.0 and roundi(r.y) <= 1, "погоня %d корветами: один отход и не дальше 400 — %.0f, отходов %d" % [n, r.x, roundi(r.y)])
	var o := _pack_chase(3, true)
	note("откат «не оторваться только от одного»: сдвиг %.0f, отходов %d" % [o.x, roundi(o.y)])
	ok(o.x > 400.0 and roundi(o.y) >= 2, "откат «не оторваться только от одного»: %.0f, отходов %d — проверка краснеет" % [o.x, roundi(o.y)])


# ───────────────────────── отход не ведёт вперёд, «прижат», «Держать» ─────────────────────────

## Чужой крейсер — цель в поясе впереди (−z), корвет-мишень вплотную СЗАДИ: «прочь от него»
## — это вперёд, к противнику. Отход вперёд не ведёт (2.6): прижат и стоит. → сколько прошёл
## вперёд по оси.
func _retreat_forward(rollback: bool) -> Dictionary:
	HeavyDoctrine.rollback_retreat_forward = rollback
	var b := _lab()
	var s := _tough(_put(b, Ship.ATTACKER, &"troyden", &"cruiser", Vector2(0, 0)))
	s.stance = &"hunt"
	_dummy(_put(b, Ship.DEFENDER, &"plektor", &"cruiser", Vector2(0, -700)))
	_dummy(_put(b, Ship.DEFENDER, &"plektor", &"corvette", Vector2(0, 250)))
	var fwd := 0.0
	for i in roundi(15.0 / Battle.STEP):
		b.step()
		fwd = maxf(fwd, -s.pos.y)
	var out := {"fwd": fwd, "pinned": _had(b, s.uid, HeavyDoctrine.PINNED)}
	b.dispose()
	HeavyDoctrine.rollback_retreat_forward = false
	return out


func test_retreat_never_forward() -> void:
	var r := _retreat_forward(false)
	ok(num(r["fwd"]) < 5.0 and flag(r["pinned"]), "враг вплотную сзади: вперёд, к чужой линии, не отходит (%.1f) — «прижат»" % num(r["fwd"]))
	var o := _retreat_forward(true)
	ok(num(o["fwd"]) > 50.0, "откат «отход и вперёд»: ушёл на %.0f к чужой линии — проверка краснеет" % num(o["fwd"]))


## Крейсер у своего края поля (край отхода — field − retreat.edge), корвет-мишень вплотную
## со стороны противника: отходить некуда — «прижат», за край не уходит.
func _edge(rollback: bool) -> Dictionary:
	HeavyDoctrine.rollback_no_edge = rollback
	var b := _lab()
	var lim := b.mp.field - b.defs.doctrine.retreat_edge
	var s := _tough(_put(b, Ship.ATTACKER, &"troyden", &"cruiser", Vector2(0, lim - 50.0)))
	s.stance = &"hunt"
	_dummy(_put(b, Ship.DEFENDER, &"plektor", &"corvette", Vector2(0, lim - 300.0)))
	var far := 0.0
	for i in roundi(20.0 / Battle.STEP):
		b.step()
		far = maxf(far, s.pos.y - lim)
	var out := {"over": far, "pinned": _had(b, s.uid, HeavyDoctrine.PINNED)}
	b.dispose()
	HeavyDoctrine.rollback_no_edge = false
	return out


func test_pinned_at_edge() -> void:
	var r := _edge(false)
	ok(num(r["over"]) <= HeavyDoctrine.ARRIVED and flag(r["pinned"]), "у края поля: за край отхода не уходит (%.1f за краем) — «прижат»" % num(r["over"]))
	var o := _edge(true)
	ok(num(o["over"]) > 50.0, "откат «без края»: ушёл на %.0f за край отхода — проверка краснеет" % num(o["over"]))


## «Держать» — приказ встать (09, 9.5 п. 2): корвет вплотную, тяжёлый сам не отходит.
func _hold(rollback: bool) -> float:
	HeavyDoctrine.rollback_hold_retreats = rollback
	var b := _lab()
	var s := _tough(_put(b, Ship.ATTACKER, &"troyden", &"cruiser", Vector2(0, 0)))
	s.stance = &"hold"
	_dummy(_put(b, Ship.DEFENDER, &"plektor", &"corvette", Vector2(0, -200)))
	_steps(b, 15.0)
	var moved := s.pos.length()
	b.dispose()
	HeavyDoctrine.rollback_hold_retreats = false
	return moved


func test_hold_no_self_retreat() -> void:
	var m := _hold(false)
	ok(m < 1.0, "«Держать»: корвет в 200 — тяжёлый стоит (сдвиг %.2f)" % m)
	var o := _hold(true)
	ok(o > 50.0, "откат «Держать тоже отходит»: ушёл на %.0f — проверка краснеет" % o)


## Охрана своего на ходу — прямой приказ на движение (09, 6.6, п. 2): носитель идёт
## к (0, −600), крейсер охраняет его, корвет-мишень у пути. Крейсер сам не отходит и не
## отстаёт от своего места в кольце. Откат — как «Охрана» на месте (самоотход, торможение
## у чужих): отходил и отставал на ~700 (замечание к G4). → [худшее отставание, был ли отход].
func _escort(rollback: bool) -> Array:
	HeavyDoctrine.rollback_escort_retreats = rollback
	var b := _lab()
	var car := _tough(_put(b, Ship.ATTACKER, &"troyden", &"carrier", Vector2(0, 200)))
	var s := _tough(_put(b, Ship.ATTACKER, &"troyden", &"cruiser", Vector2(0, 100)))
	_dummy(_put(b, Ship.DEFENDER, &"plektor", &"corvette", Vector2(150, -100)))
	b.queue({"op": &"guard", "ids": [s.uid], "target": car.uid})
	b.queue({"op": &"move", "ids": [car.uid], "x": 0.0, "z": -600.0})
	var lag := 0.0
	for i in roundi(30.0 / Battle.STEP):
		b.step()
		lag = maxf(lag, s.pos.distance_to(s.anchor))
	var out := [lag, _had(b, s.uid, HeavyDoctrine.RETREAT)]
	b.dispose()
	HeavyDoctrine.rollback_escort_retreats = false
	return out


func test_escort_no_self_retreat_on_the_move() -> void:
	var r := _escort(false)
	note("охрана идущего носителя, корвет у пути: отставание от места в кольце до %.0f" % num(r[0]))
	ok(not flag(r[1]) and num(r[0]) <= 250.0, "охрана своего на ходу: сам не отходит, отстаёт не больше 250 — %.0f" % num(r[0]))
	var o := _escort(true)
	note("откат «охрана на ходу как на месте»: отставание %.0f, отход %s" % [num(o[0]), str(flag(o[1]))])
	ok(flag(o[1]) and num(o[0]) > 500.0, "откат «охрана на ходу отходит сама»: отставание %.0f — проверка краснеет" % num(o[0]))


# ───────────────────────── строй (09, раздел 5; 9.5 пп. 9, 10, 20) ─────────────────────────

## Пары своих мест ближе hull + hull (расталкивание) — поперёк И по глубине.
static func spacing_problems(defs_: Defs, clan: StringName, places: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for i in places.size():
		var pi: Array = places[i]
		var di := defs_.ship(clan, StringName(str(pi[0])))
		var ai: Vector2 = pi[1]
		for j in range(i + 1, places.size()):
			var pj: Array = places[j]
			var dj := defs_.ship(clan, StringName(str(pj[0])))
			var aj: Vector2 = pj[1]
			var need := Formation.hull_of(defs_, di) + Formation.hull_of(defs_, dj)
			if ai.distance_to(aj) < need - 1e-6:
				out.append("%s %s и %s %s: %.0f < %.0f" % [pi[0], str(ai.round()), pj[0], str(aj.round()), ai.distance_to(aj), need])
	return out


## Места всех составов быстрого боя (три масштаба × кланы × противник) на старте, а также
## тот же строй с наступлением (корветы на L − 0,6 D) и с носителями у врага (−760).
func _all_spacing(ecm_01l: bool) -> Array:
	var d := _defs()
	var bad := PackedStringArray()
	var n := 0
	for size in d.quick.size_ids:
		for clan in d.faction_ids:
			for foe in d.faction_ids:
				var ids := Battle.ids_of(Battle.compose(d, size, clan))
				var foe_ids := Battle.ids_of(Battle.compose(d, size, foe))
				var pl := Formation.start_places(d, clan, ids, 1.0, foe_ids, foe, ecm_01l)
				for e in spacing_problems(d, clan, pl):
					bad.append("%s %s × %s: %s" % [size, clan, foe, e])
				n += 1
				for variant in 2:
					var members := Formation.members_of(d, clan, ids)
					var spec := Formation.Spec.new()
					spec.p = Vector2(0, 650)
					spec.ax = Vector2(0, -1)
					spec.by_pos = false
					spec.ecm_01l = ecm_01l
					if variant == 0:
						spec.advance_dead = 312.0
					else:
						spec.carrier_close = true
						spec.foe_air = true
					var o := Formation.places(d, members, spec)
					var pl2: Array = []
					for i in members.size():
						pl2.append([members[i].def.id, o.at[i]])
					for e in spacing_problems(d, clan, pl2):
						bad.append("%s %s (%s): %s" % [size, clan, "наступление" if variant == 0 else "носители −760", e])
					n += 1
	return [n, bad]


func test_formation_wider_than_push() -> void:
	var r := _all_spacing(false)
	var bad: PackedStringArray = r[1]
	ok(bad.is_empty(), "строй шире расталкивания поперёк и по глубине: %d расстановок — %s" % [whole(r[0]), "; ".join(bad.slice(0, 4))])
	var o := _all_spacing(true)
	var ob: PackedStringArray = o[1]
	note("откат --ecm-01L: пар ближе hull + hull — %d (%s)" % [ob.size(), "; ".join(ob.slice(0, 2))])
	ok(not ob.is_empty(), "откат --ecm-01L (РЭБ на 0,1 L и вторая шеренга в 50): %d пар ближе hull + hull — проверка краснеет" % ob.size())


## Откат --ecm-01L раскладывает ВСЕХ: вторая шеренга фрегатов получает свои места, а не
## остаётся без полосы посреди линии тяжёлых (замечание к G4) — иначе откат краснел бы не
## тем, что проверяет (раздел 9 CLAUDE.md). Все составы быстрого боя против линии каждого
## клана того же масштаба и против узкой (175 — «Сражение» Тройдена, 0 — один тяжёлый): у всех
## — полоса. Вторая шеренга фрегатов бывает только у Плэктора «Генерального» против узкой.
func _ecm01l_unplaced(rollback: bool) -> PackedStringArray:
	Formation.rollback_rank2_by_fr = rollback
	var d := _defs()
	var out := PackedStringArray()
	for size in d.quick.size_ids:
		for clan in d.faction_ids:
			var widths := PackedFloat64Array([175.0, 0.0])
			for foe in d.faction_ids:
				widths.append(Formation.heavy_width(d, Formation.members_of(d, foe, Battle.ids_of(Battle.compose(d, size, foe)))))
			for fw in widths:
				var ids := Battle.ids_of(Battle.compose(d, size, clan))
				var members := Formation.members_of(d, clan, ids)
				var spec := Formation.Spec.new()
				spec.p = Vector2(0, 650)
				spec.ax = Vector2(0, -1)
				spec.by_pos = false
				spec.ecm_01l = true
				spec.foe_width = fw
				var o := Formation.places(d, members, spec)
				for i in members.size():
					if o.band[i] == Formation.NONE:
						out.append("%s %s (чужая линия %.0f): %s в %s" % [size, clan, fw, members[i].def.id, str(o.at[i].round())])
	Formation.rollback_rank2_by_fr = false
	return out


func test_ecm01l_places_everyone() -> void:
	var r := _ecm01l_unplaced(false)
	ok(r.is_empty(), "откат --ecm-01L: без места (полоса NONE) — никого (%s)" % "; ".join(r.slice(0, 3)))
	var o := _ecm01l_unplaced(true)
	note("откат «вторая шеренга по первой»: без места — %d (%s)" % [o.size(), "; ".join(o.slice(0, 2))])
	ok(not o.is_empty(), "откат «вторая шеренга фрегатов ищет своих по первой»: %d без места — проверка краснеет" % o.size())


## Места по положению (5.4): корветы, переставленные вбок «не по номеру», получают места
## в том же порядке слева направо — никто не пересекает строй. Откат — по номеру.
func _crossings(by_pos: bool) -> int:
	var d := _defs()
	var ids: Array[StringName] = [&"cruiser", &"corvette", &"corvette", &"corvette", &"corvette"]
	var members := Formation.members_of(d, &"troyden", ids)
	# номера по порядку, а стоят наоборот: первый — справа
	var xs := [0.0, 300.0, 100.0, -100.0, -300.0]
	for i in members.size():
		var x: float = xs[i]
		members[i].pos = Vector2(x, 600.0)
	var spec := Formation.Spec.new()
	spec.p = Vector2(0, 650)
	spec.ax = Vector2(0, -1)
	spec.by_pos = by_pos
	var o := Formation.places(d, members, spec)
	var lat := Vector2(-spec.ax.y, spec.ax.x)
	var bad := 0
	for i in range(1, members.size()):
		for j in range(i + 1, members.size()):
			var a := (members[i].pos - spec.p).dot(lat) < (members[j].pos - spec.p).dot(lat)
			var b2 := (o.at[i] - spec.p).dot(lat) < (o.at[j] - spec.p).dot(lat)
			if a != b2:
				bad += 1
	return bad


func test_places_by_position() -> void:
	eq(_crossings(true), 0, "места по положению: корветы встают в том же порядке слева направо — пересечений строя нет")
	var o := _crossings(false)
	ok(o > 0, "откат «по номеру»: %d пар пересекают строй — проверка краснеет" % o)


## Свой флот на старте приказов не получает (09, 9.5 п. 16): стоит на своих местах строя,
## тяжёлые — на линии ±650, корветы впереди, носители позади, у всех «Охрана» без «идти».
func _start(rollback: bool) -> Dictionary:
	Battle.rollback_start_move = rollback
	var d := _defs()
	var b := Battle.create(d, {"attacker": &"troyden", "defender": &"plektor", "size": &"mid", "seed": 3, "reserve": true}) as Battle
	var orders := 0
	var off := 0.0
	var heavy_z := 0.0
	var corv_ahead := true
	var car_behind := true
	for side in 2:
		var sd := b.sides[side]
		var ids := Battle.ids_of(Battle.compose(d, &"mid", sd.clan))
		var foe_ids := Battle.ids_of(Battle.compose(d, &"mid", b.sides[1 - side].clan))
		var want := Formation.start_places(d, sd.clan, ids, sd.sign_z, foe_ids, b.sides[1 - side].clan)
		var mine := b.side_ships(side)
		for i in mine.size():
			var s := mine[i]
			if s.station:
				continue
			if s.has_move or s.has_amove or s.forced != null:
				orders += 1
			var w: Array = want[i]
			var wp: Vector2 = w[1]
			off = maxf(off, s.pos.distance_to(wp))
			var z := s.pos.y * sd.sign_z
			if s.heavy():
				heavy_z = maxf(heavy_z, absf(z - d.doctrine.deploy_heavy_z))
			elif s.def.id == &"corvette" and z >= d.doctrine.deploy_heavy_z:
				corv_ahead = false
			elif s.hangar != null and z <= d.doctrine.deploy_heavy_z:
				car_behind = false
	b.dispose()
	Battle.rollback_start_move = false
	return {"orders": orders, "off": off, "heavy_z": heavy_z, "corv": corv_ahead, "car": car_behind}


func test_start_without_orders() -> void:
	var r := _start(false)
	eq(whole(r["orders"]), 0, "свой и чужой флот на старте без приказов (ловушка 28 части 02)")
	ok(num(r["off"]) < 1e-6, "каждый — ровно на своём месте строя (расхождение %.3f)" % num(r["off"]))
	ok(num(r["heavy_z"]) < 1e-6 and flag(r["corv"]) and flag(r["car"]), "тяжёлые на линии ±650, корветы впереди неё, носители позади")
	var o := _start(true)
	ok(whole(o["orders"]) > 0, "откат «старт приказом идти, как в JS»: %d кораблей с приказом — проверка краснеет" % whole(o["orders"]))


# ───────────────────────── стенд: замеры 09, 8.2 (план G4, п. 6) ─────────────────────────

## «Сражение» без резерва и без орудия планеты, обе стороны под заглушкой строя, 8 зёрен
## (стенд, BenchCore). Медианы по боям — как в сводке стенда.
func _bench(load_id: String, seed0: int, n: int, flags: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in n:
		out.append(BenchCore.run_one(_defs(), BenchCore.setup_for(load_id, seed0 + i, false, flags), BenchCore.MAX_S, "capella-проверка"))
	return out


static func _med(reps: Array[Dictionary], key: String) -> float:
	var a := PackedFloat64Array()
	for r in reps:
		var v: float = r.get(key, -1.0)
		if v >= 0.0:
			a.append(v)
	a.sort()
	if a.is_empty():
		return -1.0
	var n := a.size()
	return a[n >> 1] if n % 2 == 1 else 0.5 * (a[(n >> 1) - 1] + a[n >> 1])


static func _worst(reps: Array[Dictionary], key: String) -> float:
	var w := 0.0
	for r in reps:
		var v: float = r.get(key, 0.0)
		w = maxf(w, v)
	return w


func test_bench_battle_measures() -> void:
	var reps := _bench("battle", 1000, 8, {})
	var m1 := _med(reps, "m1")
	var m2 := _med(reps, "m2")
	var m2e := _med(reps, "m2_ep_med")
	var m3k := _med(reps, "m3_med_k")
	var m4 := _med(reps, "m4")
	var m6 := _med(reps, "m6")
	var m6e := _med(reps, "m6_ep_med")
	var m6b := _med(reps, "m6_back")
	note("«Сражение», 8 боёв (зёрна 1000–1007): М1 %.2f · М2 %.3f (эпизод %.1f с) · М3 %.3f R (5%% худших %.0f) · М4 %.2f · М6 %.3f (эпизод %.1f с, назад %.0f) · М9 входов %.0f, пар тяжёлых %.0f · М10 тяжёлые %.0f, корветы %.0f, фрегаты %.0f · первый главный %.1f с · фаза «бой» до %.0f с" % [
		m1, m2, m2e, m3k, _med(reps, "m3_p5"), m4, m6, m6e, m6b, _med(reps, "m9_entries"), _worst(reps, "m9_heavy"),
		_med(reps, "m10_heavy"), _med(reps, "m10_corvette"), _med(reps, "m10_frigate"), _med(reps, "first_gun"), _med(reps, "fight_t1")])
	ok(m1 >= 0.65, "М1 тяжёлые в поясе: %.2f (≥ 0,65)" % m1)
	ok(m2 <= 0.15, "М2 вплотную: %.3f (≤ 0,15)" % m2)
	ok(m2e <= 10.0, "М2: медиана эпизода %.1f с (≤ 10)" % m2e)
	ok(m3k >= 0.7 and m3k <= 1.0, "М3 расстояние между линиями: медиана %.3f R (0,7–1,0)" % m3k)
	eq(_worst(reps, "m3_short"), 0.0, "М3: ни одного шага, где линии ближе 360")
	ok(m4 >= 0.7, "М4 лёгкие между линиями: %.2f (≥ 0,70)" % m4)
	ok(m6 <= 0.15, "М6 отход: %.3f (≤ 0,15)" % m6)
	eq(_worst(reps, "m6_rear") + _worst(reps, "m6_edge"), 0.0, "М6: за тыловым рубежом и у края поля — ни шага")
	eq(_worst(reps, "m9_heavy"), 0.0, "М9: пар чужих тяжёлых ближе 360 — 0")
	ok(_med(reps, "m9_entries") <= 10.0, "М9: входов «свой в чужом» %.0f (≤ 10)" % _med(reps, "m9_entries"))
	ok(_med(reps, "m10_heavy") <= 150.0 and _med(reps, "m10_corvette") <= 260.0 and _med(reps, "m10_frigate") <= 120.0,
		"М10 строй держится: тяжёлые %.0f (≤ 150), корветы %.0f (≤ 260), фрегаты %.0f (≤ 120)" % [_med(reps, "m10_heavy"), _med(reps, "m10_corvette"), _med(reps, "m10_frigate")])
	eq(_worst(reps, "m10_self"), 0.0, "М10: места двух своих ближе hull + hull — ни шага (9.5 п. 20)")
	# не дотягивают до 09, 8.2 — сказано, а не подогнано (пороги — «первая прикидка», 8.2):
	# эпизод отхода у флагмана, шедшего вперёд, — гашение хода и 90 единиц до 0,5 R
	note("не держат порогов 09, 8.2 (G5/G9): М6 — медиана эпизода %.1f с (порог 8), центр линии назад %.0f (порог 400)" % [m6e, m6b])
	# откат --legacy-approach (подход лёгкого «на 0,68», как в JS) — проваливает М2, М3 и М9
	var lg := _bench("battle", 1000, 2, {"legacy_approach": true})
	note("откат --legacy-approach: М2 %.3f · М3 %.3f R · пар тяжёлых ближе 360 %.0f" % [_med(lg, "m2"), _med(lg, "m3_med_k"), _worst(lg, "m9_heavy")])
	ok(_med(lg, "m3_med_k") < 0.7 and _worst(lg, "m9_heavy") > 0.0, "откат --legacy-approach: линии сходятся до %.2f R и тяжёлые в упор — М3 и М9 краснеют" % _med(lg, "m3_med_k"))
	# откат --ecm-01L — места двух своих ближе hull + hull (М10)
	var ec := _bench("battle", 1000, 1, {"ecm_01l": true})
	ok(_worst(ec, "m10_self") > 0.0, "откат --ecm-01L: мест ближе hull + hull — %.0f шагов — М10 краснеет" % _worst(ec, "m10_self"))


## Место линии P не убегает вперёд своих тяжёлых дальше line.lead_max (найдено стендом G4):
## P считается от чужих тяжёлых, которые ещё в пути, и без предела места обеих сторон
## съезжались до 300 — шеренги лёгких проходили сквозь друг друга. Беда видна в «Стычке» (две
## крейсерские линии, «Сражение» и «Генеральное» — слабее), и откат обязан краснеть ЭТОЙ
## проверкой: без неё правка числа не краснила ни одного замера «Сражения» (замечание к G4).
## Мерило — ближе всего места P двух сторон за фазу «бой» (p_min) против L = 0,85 R_line.
## Откат — правка числа line.lead_max = 1e9 (--set).
func test_bench_lead_max() -> void:
	var dc := _defs().doctrine
	var base := _bench("skirmish", 1000, 2, {})
	var off := Defs.load_default({"line.lead_max": 1.0e9}) as Defs
	var o: Array[Dictionary] = []
	for i in 2:
		o.append(BenchCore.run_one(off, BenchCore.setup_for("skirmish", 1000 + i, false, {}), BenchCore.MAX_S, "capella-проверка"))
	var l := dc.line_L_k * _med(base, "r_line")
	var pmin := 1.0e9
	var omin := 1.0e9
	for r in base:
		pmin = minf(pmin, num(r["p_min"]))
	for r in o:
		omin = minf(omin, num(r["p_min"]))
	note("«Стычка», 2 боя: места линий двух сторон не ближе %.0f (L = %.0f); откат line.lead_max = 1e9 — %.0f" % [pmin, l, omin])
	ok(pmin >= 0.7 * l, "места линий P двух сторон не съезжаются: ближе всего %.0f (≥ 0,7 L = %.0f)" % [pmin, 0.7 * l])
	ok(omin < 0.7 * l, "откат line.lead_max = 1e9: места линий съехались до %.0f — проверка краснеет" % omin)


## Флажки, беда которых видна только там, где правило решает исход (09, 8.4): «линии» —
## одни тяжёлые линия на линию; «brake» и «clear» — сценарии стенда (BenchCore).
func test_bench_flags_fail_their_measure() -> void:
	var base := _bench("lines", 1000, 2, {})
	var ns := _bench("lines", 1000, 2, {"no_share_close": true})
	note("«линии»: М3 %.3f R, откат --no-share-close — %.3f R" % [_med(base, "m3_med_k"), _med(ns, "m3_med_k")])
	ok(_med(base, "m3_med_k") >= 0.7, "«линии»: две линии тяжёлых стоят на %.3f R (≥ 0,7)" % _med(base, "m3_med_k"))
	ok(_med(ns, "m3_med_k") < 0.7, "откат --no-share-close: линии сходятся до %.3f R — М3 краснеет" % _med(ns, "m3_med_k"))
	var br := _bench("brake", 1, 1, {})
	var nb := _bench("brake", 1, 1, {"no_foe_brake": true})
	note("«brake»: М2 %.3f, М6 %.3f; откат --no-foe-brake — М2 %.3f, М6 %.3f" % [_med(br, "m2"), _med(br, "m6"), _med(nb, "m2"), _med(nb, "m6")])
	ok(_med(br, "m2") == 0.0 and _med(br, "m6") == 0.0, "«brake»: подход тормозит у чужого корвета — в мёртвую зону не въезжает, отходить не приходится")
	ok(_med(nb, "m2") > 0.0 and _med(nb, "m6") > 0.0, "откат --no-foe-brake: въехал к корвету (М2 %.3f) и отходит (М6 %.3f) — краснеет" % [_med(nb, "m2"), _med(nb, "m6")])
	var cl := _bench("clear", 1, 1, {})
	var c5 := _bench("clear", 1, 1, {"clear_055": true})
	note("«clear»: первый выстрел главного калибра %.1f с; откат --clear-055 — %.1f" % [_med(cl, "first_gun"), _med(c5, "first_gun")])
	ok(_med(cl, "first_gun") > 0.0, "«clear»: корвет в 412 (дальше 0,45 R) пути не закрывает — крейсер подошёл и бьёт (%.1f с)" % _med(cl, "first_gun"))
	ok(_med(c5, "first_gun") <= 0.0, "откат --clear-055 (путь чист с 0,55 R): подход заперт, главный калибр не выстрелил за 60 с — М11 краснеет")
