# Модель боя G1: шаг, полёт, приказы движения, гипер, подкрепление, повтор, память
# (план G1, «Проверки»; часть 02, 4.2; часть 01, 4.2 пп. 2–3, 8). Каждая проверка —
# с откатом: на копии без правки (или с выключенным правилом) она обязана краснеть.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Movement := preload("res://sim/movement.gd")
const Formation := preload("res://sim/formation.gd")

const CLASSES: Array[StringName] = [&"corvette", &"frigate", &"ecm", &"cruiser", &"carrier", &"capital", &"sinho"]
## Таблица 2.22 части 02 (проба в JS, шаг 1/30): вперёд 600, вбок 400, назад 600, с.
const ARRIVE_REF := {
	&"corvette": [12.67, 9.53, 13.07], &"frigate": [15.63, 11.73, 16.17], &"ecm": [17.7, 13.23, 18.3],
	&"cruiser": [20.77, 15.9, 21.63], &"carrier": [24.3, 18.33, 25.3], &"capital": [25.47, 19.37, 26.63],
	&"sinho": [27.53, 20.7, 28.7],
}
## Торможение с полного хода по «Держать» до скорости < 0,5: путь, замер JS.
const BRAKE_REF := {&"corvette": 99.0, &"frigate": 95.2, &"ecm": 91.2, &"cruiser": 119.7,
	&"carrier": 99.6, &"capital": 106.6, &"sinho": 94.5}
const GOALS: Array[Vector2] = [Vector2(0, -600), Vector2(400, 0), Vector2(0, 600)]

var defs: Defs


func _defs() -> Defs:
	if defs == null:
		defs = Defs.load_default() as Defs
	return defs


## Замер JS: model_len.hull выгрузки (часть 01, 2.17).
func _hull_ref(id: StringName) -> float:
	return _defs().ship(_clan(id), id).hull


static func _clan(id: StringName) -> StringName:
	return &"plektor" if id == &"sinho" else &"troyden"


## Пустое поле (02, 2.22: «противник далеко»): бой без кораблей, сюда ставим своих.
func _lab(clan: StringName = &"troyden", seed_n: int = 7, d: Defs = null) -> Battle:
	var dd := d if d != null else _defs()
	var b := Battle.create(dd, {"attacker": clan, "defender": &"plektor", "size": &"small", "seed": seed_n, "reserve": false}) as Battle
	b.ships.clear()
	return b


func _one(b: Battle, id: StringName, pos: Vector2 = Vector2.ZERO, side: int = Ship.ATTACKER) -> Ship:
	var clan := b.sides[side].clan if id != &"sinho" else &"plektor"
	return b.spawn(side, b.defs.ship(clan, id), pos)


## Приход в точку: {t — время снятия приказа (−1 — не пришёл), over — перелёт вдоль
## пути, near — у точки в миг прихода}.
func _go(b: Battle, s: Ship, goal: Vector2, max_s: float = 100.0) -> Dictionary:
	var start := s.pos
	var u := (goal - start).normalized()
	var dist := start.distance_to(goal)
	b.queue({"op": &"move", "ids": [s.uid], "x": goal.x, "z": goal.y})
	var over := 0.0
	var t := -1.0
	for i in roundi(max_s / Battle.STEP):
		b.step()
		over = maxf(over, (s.pos - start).dot(u) - dist)
		if not s.has_move:
			t = b.time
			break
	return {"t": t, "over": over, "near": s.pos.distance_to(goal)}


## Торможение с полного хода по «Держать»: путь до скорости < 0,5.
func _brake(b: Battle, s: Ship) -> float:
	s.vel = s.dir * s.max_speed()
	var p0 := s.pos
	b.queue({"op": &"stance", "ids": [s.uid], "stance": &"hold"})
	for i in 3000:
		b.step()
		if s.vel.length() < 0.5:
			break
	return s.pos.distance_to(p0)


# ───────────────────────── таблица 2.22: приход и торможение ─────────────────────────

func test_arrival_table_2_22() -> void:
	var d := _defs()
	var worst_dt := 0.0
	for id in CLASSES:
		var refs: Array = ARRIVE_REF[id]
		for k in 3:
			var b := _lab(_clan(id))
			var s := _one(b, id)
			var r := _go(b, s, GOALS[k])
			var t: float = r["t"]
			var over: float = r["over"]
			var near_d: float = r["near"]
			var want: float = refs[k]
			worst_dt = maxf(worst_dt, absf(t - want))
			ok(t > 0.0 and absf(t - want) <= Battle.STEP + 1e-6, "%s %s: пришёл за %.3f с, в JS %.2f (в пределах шага)" % [id, ["вперёд 600", "вбок 400", "назад 600"][k], t, want])
			ok(over <= 1e-6, "%s %s: перелёт %.3f (ждали 0)" % [id, ["вперёд 600", "вбок 400", "назад 600"][k], over])
			ok(near_d < 2.0, "%s: встал ближе 2 к точке (%.2f)" % [id, near_d])
			b.dispose()
		var b2 := _lab(_clan(id))
		var path := _brake(b2, _one(b2, id))
		var bref: float = BRAKE_REF[id]
		ok(absf(path - bref) <= bref * 0.02, "%s: тормозной путь %.1f, в JS %.1f (±2%%)" % [id, path, bref])
		b2.dispose()
	note("таблица 2.22: худшее расхождение времени прихода с JS %.3f с" % worst_dt)
	# откат (C70, ловушка 1 части 02): тормозить «от полной тяги», а тянуть — от 0,6 —
	# каждый класс проскакивает точку
	var bo := _lab()
	var so := _one(bo, &"cruiser")
	bo.mp.brake_k = 1.0 / d.reverse_k
	var ro := _go(bo, so, GOALS[0])
	var over_o: float = ro["over"]
	ok(over_o > 20.0, "откат «тормоз от полной тяги»: крейсер проскакивает точку на %.1f — проверка перелёта краснеет" % over_o)
	bo.dispose()


## Двигатели × 0,5 (09, 10.4; 09, 9.5 п. 4): разгон и тормозной путь меняются вместе,
## перелёта нет. Откат — тормоз от тяги из таблицы, а не от thrust() корабля.
func test_engines_half_move_together() -> void:
	for id: StringName in [&"corvette", &"cruiser", &"capital"]:
		var b := _lab()
		var s := _one(b, id)
		s.engine_k = 0.5
		var r := _go(b, s, GOALS[0], 200.0)
		var over: float = r["over"]
		var t: float = r["t"]
		var refs: Array = ARRIVE_REF[id]
		var t_full: float = refs[0]
		ok(t > t_full * 1.2, "%s, двигатели × 0,5: приход дольше (%.2f против %.2f)" % [id, t, t_full])
		ok(over <= 1e-6, "%s, двигатели × 0,5: перелёта нет (%.3f)" % [id, over])
		b.dispose()
		var b2 := _lab()
		var s2 := _one(b2, id)
		s2.engine_k = 0.5
		var path := _brake(b2, s2)
		var bref: float = BRAKE_REF[id]
		ok(absf(path / bref - 2.0) <= 0.04, "%s, двигатели × 0,5: тормозной путь вдвое (%.1f против %.1f)" % [id, path, bref])
		b2.dispose()
	Movement.rollback_brake_table = true
	var bo := _lab()
	var so := _one(bo, &"cruiser")
	so.engine_k = 0.5
	var ro := _go(bo, so, GOALS[0], 200.0)
	Movement.rollback_brake_table = false
	var over_o: float = ro["over"]
	ok(over_o > 20.0, "откат «тормоз от тяги из таблицы»: побитый крейсер проскакивает точку на %.1f — проверка краснеет" % over_o)
	bo.dispose()


# ───────────────────────── «Держать» посреди марша ─────────────────────────

## H посреди марша — ПРИКАЗ ВСТАТЬ (ловушка 11 части 02; 09, 9.5 п. 2), и приказ
## «идти» снимает сама команда, а не проверка (02, 4.2 п. 2). Контрольный опыт —
## «Охрана» (манера, ловушка 12): марш доводит, путь много больше тормозного.
func _hold_mid_march(id: StringName, stance: StringName) -> Dictionary:
	var b := _lab()
	var s := _one(b, id)
	b.queue({"op": &"move", "ids": [s.uid], "x": 0.0, "z": -3000.0})
	for i in 3000:
		b.step()
		if s.vel.length() >= s.max_speed() * 0.97:
			break
	var v := s.vel.length()
	var p0 := s.pos
	b.queue({"op": &"stance", "ids": [s.uid], "stance": stance})
	for i in roundi(10.0 / Battle.STEP):
		b.step()
	var limit := v * v / (2.0 * b.defs.reverse_k * s.thrust()) * 1.15 + minf(s.length, 60.0)
	var out := {"path": s.pos.distance_to(p0), "limit": limit, "move": s.has_move, "stance": s.stance, "v": s.vel.length()}
	b.dispose()
	return out


func test_hold_mid_march_stops() -> void:
	for id: StringName in [&"corvette", &"cruiser", &"capital"]:
		var r := _hold_mid_march(id, &"hold")
		var path: float = r["path"]
		var limit: float = r["limit"]
		ok(path <= limit, "%s: H посреди марша — путь %.1f не больше тормозного %.1f" % [id, path, limit])
		ok(not flag(r["move"]), "%s: после H приказа «идти» нет" % id)
		eq(r["stance"], &"hold", "%s: тактика после H" % id)
		ok(num(r["v"]) < 3.0, "%s: через 10 с стоит (скорость %.2f)" % [id, num(r["v"])])
	# контрольный опыт: «Охрана» марш не прерывает — та же проверка пути краснела бы
	var g := _hold_mid_march(&"cruiser", &"guard")
	ok(num(g["path"]) > num(g["limit"]) * 1.5 and flag(g["move"]), "контроль: на «Охране» крейсер идёт дальше (%.0f при тормозном %.0f) — проверка различает" % [num(g["path"]), num(g["limit"])])


# ───────────────────────── расталкивание ─────────────────────────

func _push_pair(id: StringName, foe: bool, by_radius: bool) -> float:
	var b := _lab()
	var a := _one(b, id, Vector2(0, 0))
	var c := _one(b, id, Vector2(60, 0), Ship.DEFENDER if foe else Ship.ATTACKER)
	if by_radius:
		# откат C87: корпус по радиусу класса, а не по длине модели
		a.hull = a.def.radius * b.defs.consts.hull_formula_radius_k
		c.hull = c.def.radius * b.defs.consts.hull_formula_radius_k
	a.stance = &"hold"
	c.stance = &"hold"
	for i in roundi(40.0 / Battle.STEP):
		b.step()
	var dist := a.pos.distance_to(c.pos)
	b.dispose()
	return dist


func test_push_apart_by_hull() -> void:
	var h := _hull_ref(&"capital")
	var own := _push_pair(&"capital", false, false)
	ok(own >= 2.0 * h * 0.995, "два своих флагмана разошлись до %.1f (корпус + корпус = %.1f, ~149)" % [own, 2.0 * h])
	var foe := _push_pair(&"capital", true, false)
	ok(foe >= 2.0 * h * 1.15 * 0.99, "два чужих флагмана — до %.1f (×1,15 = %.1f, ~171)" % [foe, 2.0 * h * 1.15])
	var old := _push_pair(&"capital", false, true)
	ok(old < 2.0 * h * 0.8, "откат «корпус по радиусу» (C87): флагманы стоят в %.1f — проверка краснеет" % old)


# ───────────────────────── приход при соседях ─────────────────────────

## Соседи по строю не пускают в саму точку: «ближе 60 и медленнее 4 за 2,5 с» — тоже
## приход (ловушка 4 части 02). Откат — одно первое условие: оно здесь не выполнилось
## ни разу, то есть без второго приказ висел бы вечно.
func test_arrival_with_neighbours() -> void:
	# два фрегата в одну точку — каждый не пускает другого в саму точку
	var b := _lab()
	var goal := Vector2(0, -300)
	var pair: Array[Ship] = [_one(b, &"frigate", Vector2(-200, 0)), _one(b, &"frigate", Vector2(200, 0))]
	for s in pair:
		b.queue({"op": &"move", "ids": [s.uid], "x": goal.x, "z": goal.y})
	var first_rule := false
	var done := 0
	for i in roundi(60.0 / Battle.STEP):
		b.step()
		done = 0
		for s in pair:
			if s.has_move and s.pos.distance_to(goal) < 8.0 and s.vel.length() < 3.0:
				first_rule = true
			if not s.has_move:
				done += 1
		if done == 2:
			break
	eq(done, 2, "оба приказа при соседе сняты (за %.1f с)" % b.time)
	for s in pair:
		eq(s.anchor, goal, "пришёл — точка стала участком «Охраны» (ловушка 5)")
	ok(not first_rule, "откат «только ближе 8 и медленнее 3»: это условие не выполнилось ни разу — без второго приказы висели бы")
	b.dispose()


# ───────────────────────── дрифт ─────────────────────────

func test_drift() -> void:
	var b := _lab()
	var s := _one(b, &"corvette", Vector2(0, 0))
	s.vel = Vector2(12.0, -40.0)
	b.queue({"op": &"drift", "ids": [s.uid]})
	b.step()
	ok(s.drift, "D включил дрифт")
	var v0 := s.vel
	var same := true
	for i in 90:
		b.step()
		same = same and s.vel == v0
	ok(same, "в дрифте скорость не меняется ни на шаг (%s → %s)" % [v0, s.vel])
	eq(s.thrust_fwd + s.thrust_rev, 0.0, "в дрифте тяги нет")
	b.queue({"op": &"move", "ids": [s.uid], "x": 0.0, "z": 0.0})
	b.step()
	ok(not s.drift, "ПКМ по полю (идти) выключил дрифт (ловушка 13)")
	b.queue({"op": &"drift", "ids": [s.uid]})
	b.step()
	b.queue({"op": &"stance", "ids": [s.uid], "stance": &"hold"})
	b.step()
	ok(not s.drift, "S / H выключили дрифт")
	b.dispose()
	# откат: приказ «идти» оставил дрифт — корабль скользит мимо точки
	var b2 := _lab()
	var s2 := _one(b2, &"corvette", Vector2(0, 0))
	s2.vel = Vector2(0.0, -40.0)
	b2.queue({"op": &"move", "ids": [s2.uid], "x": 0.0, "z": -100.0})
	b2.step()
	s2.drift = true
	for i in 150:
		b2.step()
	ok(s2.pos.y < -150.0, "откат «идти не выключает дрифт»: корабль проскользнул точку до %.0f — это и выглядит как поломка" % s2.pos.y)
	b2.dispose()


# ───────────────────────── ион: выключатель узла ─────────────────────────

## Ион выключает и тягу, и разворот, но не инерцию (ловушка 25 части 02).
func test_ion_switches_engines_off() -> void:
	var b := _lab()
	var s := _one(b, &"cruiser", Vector2(0, 0))
	s.vel = Vector2(0.0, -20.0)
	b.queue({"op": &"move", "ids": [s.uid], "x": 800.0, "z": 400.0})
	b.step()
	s.switch_off(&"engines", b.time + 10.0)
	var y0 := s.yaw
	var p0 := s.pos
	var v0 := s.vel
	for i in 60:
		b.step()
	ok(s.yaw == y0, "под ионом нос не доворачивается")
	ok(s.vel == v0 and s.thrust_fwd == 0.0 and s.thrust_rev == 0.0, "под ионом тяги нет, скорость прежняя")
	ok(s.pos.distance_to(p0) > 30.0, "под ионом корабль летит по инерции (%.0f)" % s.pos.distance_to(p0))
	for i in roundi(10.0 / Battle.STEP):
		b.step()
	ok(s.yaw != y0, "через 10 с двигатели снова работают")
	b.dispose()


# ───────────────────────── гипер ─────────────────────────

func test_hyper_one_ship() -> void:
	for id in CLASSES:
		var b := _lab(_clan(id))
		var s := _one(b, id, Vector2(100, 200))
		s.vel = Vector2(5.0, 0.0)          # скорость до накачки сохраняется (вопрос 5 части 02)
		b.queue({"op": &"hyper", "ids": [s.uid]})
		b.step()
		var hc := s.def.hyper_charge * b.defs.hyper.jump_charge
		ok(absf(s.hyper_left + Battle.STEP - hc) < 1e-6, "%s: накачка %.1f с (hyperCharge %.1f)" % [id, s.hyper_left + Battle.STEP, hc])
		var p0 := s.pos
		var still := true
		var gone := -1.0
		for i in roundi((hc + 1.0) / Battle.STEP):
			b.step()
			if s.hyper_left >= 2.0:
				still = still and s.pos == p0
			if s.fled and gone < 0.0:
				gone = b.time
				break
		ok(still, "%s: копящий гипер стоит на месте до последних 2 с (ловушка 26)" % id)
		ok(gone > 0.0 and absf(gone - hc) <= Battle.STEP + 1e-6, "%s: ушёл через %.2f с (накачка %.1f)" % [id, gone, hc])
		b.dispose()
	# станция в гипер не уходит (ловушка 24)
	var b2 := _lab()
	var st := b2.spawn(Ship.DEFENDER, b2.defs.station, Vector2(0, -1000))
	ok(not b2._begin_jump(st), "станция в гипер не уходит")
	# повторное G — отмена
	var c := _one(b2, &"frigate", Vector2(0, 0))
	b2.queue({"op": &"hyper", "ids": [c.uid]})
	b2.step()
	b2.queue({"op": &"hyper", "ids": [c.uid]})
	b2.step()
	ok(not c.charging(), "повторное G отменило гипер")
	b2.dispose()


## Уход носителя — отход всей стороны, и отменить его нельзя (C17; 05, ловушка 29).
func test_carrier_leaves_whole_side() -> void:
	var b := Battle.create(_defs(), {"attacker": &"troyden", "defender": &"plektor", "size": &"mid", "seed": 3, "reserve": true}) as Battle
	var carrier: Ship = null
	for s in b.side_ships(Ship.ATTACKER):
		if s.def.cls == &"carrier":
			carrier = s
	if not ok(carrier != null, "у Тройдена в «Сражении» есть носитель"):
		return
	b.queue({"op": &"reinforce", "side": Ship.ATTACKER})
	b.queue({"op": &"hyper", "ids": [carrier.uid]})
	for i in roundi((carrier.def.hyper_charge + 0.5) / Battle.STEP):
		b.step()
		if carrier.fled:
			break
	ok(carrier.fled, "носитель ушёл")
	var sd := b.sides[Ship.ATTACKER]
	ok(sd.retreat and sd.conceded, "уход носителя — отход стороны")
	eq(sd.reinforce_at, 0.0, "отход отменил вызванное подкрепление")
	var all_charging := true
	for s in b.side_ships(Ship.ATTACKER):
		all_charging = all_charging and s.charging()
	ok(all_charging, "все остальные корабли стороны копят гипер")
	b.cancel_retreat(Ship.ATTACKER)
	ok(sd.retreat, "отход после ухода носителя не отменить")
	b.queue({"op": &"hyper", "ids": [b.side_ships(Ship.ATTACKER)[0].uid]})
	b.step()
	ok(b.side_ships(Ship.ATTACKER)[0].charging(), "G не отменяет гипер, когда носитель ушёл")
	for i in roundi(20.0 / Battle.STEP):
		b.step()
	ok(b.over and b.winner == Ship.DEFENDER, "атакующий ушёл с орбиты — бой кончился")
	b.dispose()


# ───────────────────────── выход из гипера и подкрепление ─────────────────────────

## Подкрепление из всех классов; правки d — для отката. → {jump — наибольший скачок
## скорости за шаг (у кого), speed0 — скорость при выходе / maxSpeed, window — окно
## без предела закрылось за столько секунд (наибольшее), capped — превышал ли предел
## после окна, anchors — участки прибывших (z)}.
func _exit_run(d: Defs, clan: StringName, ids: Array[StringName]) -> Dictionary:
	var b := Battle.create(d, {"attacker": clan, "defender": &"plektor", "size": &"small", "seed": 5, "reserve": false}) as Battle
	var res: Array[Defs.FleetEntry] = []
	for id in ids:
		var e := Defs.FleetEntry.new()
		e.id = id
		e.count = 1
		res.append(e)
	b.sides[Ship.ATTACKER].reserve = res
	b.queue({"op": &"reinforce", "side": Ship.ATTACKER})
	var arrived: Array[Ship] = []
	var prev: Dictionary = {}
	var speed0: Dictionary = {}
	var t_in := 0.0
	var worst := 0.0
	var worst_who := ""
	var window := 0.0
	var capped := false
	for i in roundi(60.0 / Battle.STEP):
		b.step()
		for ev in b.events:
			if ev[0] == &"jump_in":
				var u: int = ev[1]
				arrived.append(b.ship_by_uid(u))
				t_in = b.time
		for s in arrived:
			var sp := s.vel.length()
			if not speed0.has(s.uid):
				speed0[s.uid] = sp / s.max_speed()
			elif prev.has(s.uid):
				var p: float = prev[s.uid]
				if absf(sp - p) > worst:
					worst = absf(sp - p)
					worst_who = "%s %.1f → %.1f на %.2f с после выхода" % [s.def.id, p, sp, b.time - t_in]
			prev[s.uid] = sp
			if s.exit_until > b.time:
				window = maxf(window, b.time - t_in)
			elif sp > s.max_speed() * d.consts.ship_speed_cap_k + 1e-6:
				capped = true
	var anchors := PackedFloat64Array()
	for s in arrived:
		anchors.append(s.anchor.y)
	var out := {"n": arrived.size(), "jump": worst, "who": worst_who, "speed0": speed0.values(), "window": window, "capped": capped, "anchors": anchors, "t_in": t_in}
	b.dispose()
	return out


func test_exit_from_hyper_no_jump() -> void:
	var d := _defs()
	var troy: Array[StringName] = [&"corvette", &"frigate", &"ecm", &"cruiser", &"carrier", &"capital"]
	for run: Array in [[&"troyden", troy], [&"plektor", [&"sinho", &"capital"] as Array[StringName]]]:
		var clan: StringName = run[0]
		var ids: Array[StringName] = run[1]
		var r := _exit_run(d, clan, ids)
		eq(r["n"], ids.size(), "%s: вышли все (%d)" % [clan, ids.size()])
		for k: Variant in r["speed0"]:
			var f: float = k
			ok(absf(f - d.consts.reinforce_drop_exit_speed_k) < 0.05, "%s: скорость выхода %.2f × maxSpeed (2,6)" % [clan, f])
		ok(num(r["jump"]) <= 2.0, "%s: скачка скорости больше 2 за шаг нет (наибольший %.2f: %s)" % [clan, num(r["jump"]), str(r["who"])])
		ok(num(r["window"]) <= d.doctrine.hyper_exit_free_max_s + 0.001, "%s: окно без предела закрылось за %.1f с (не дольше %.0f)" % [clan, num(r["window"]), d.doctrine.hyper_exit_free_max_s])
		ok(not flag(r["capped"]), "%s: после окна скорость не выше 1,25 × maxSpeed" % clan)
		note("%s: выход — наибольший скачок %.2f за шаг; окно до %.1f с" % [clan, num(r["jump"]), num(r["window"])])
	# откат «ровно 6 с» (как в JS): у тяжёлых скорость срезается скачком (крейсер 65,3 → 47,3)
	var d6 := Defs.load_default({"hyper.exit_free_max_s": 6.0}) as Defs
	var r6 := _exit_run(d6, &"troyden", troy)
	ok(num(r6["jump"]) > 10.0, "откат «окно ровно 6 с»: скачок %.1f за шаг (%s) — проверка краснеет" % [num(r6["jump"]), str(r6["who"])])


## Куда идут прибывшие (09, 5.5; план G4, п. 8): каждый — на СВОЁ место в строю от
## нынешней линии стороны (той же sim/formation.gd → places(), что строй на старте и ПКМ),
## а не в середину поля (x × 0,4; 0; ±120) из JS — пояс и мёртвая зона чужих тяжёлых. Точка
## выхода — тормозной путь с 2,6 × maxSpeed от той же thrust(), что разгон, плюс
## reinforce.exit_pad перед местом, не ближе reinforce.exit_edge к краю: корабль гасит
## скорость ровно к своему месту, а не пролетает его. Откат `rollback_drop_at_edge` —
## выход у своего края, как в JS.
static func arrivals_target_problems(rows: Array, l: float, carrier_back: float) -> PackedStringArray:
	var out := PackedStringArray()
	for r: Dictionary in rows:
		var ax: Vector2 = r["ax"]
		var anc: Vector2 = r["anchor"]
		var ln: Vector2 = r["line"]
		var off := (anc - ln).dot(ax)
		var band: int = r["band"]
		var ok_band := true
		match band:
			Formation.HEAVY, Formation.HEAVY2:
				ok_band = off <= 1.0 and off >= -151.0
			Formation.CORVETTE, Formation.FRIGATE, Formation.FRIGATE2, Formation.ECM_OLD:
				# фрегат может встать зонтом у носителя (09, 3.3)
				ok_band = (off > 1.0 and off <= 0.35 * l + 1.0) or (band == Formation.FRIGATE and off <= -carrier_back + 1.0)
			Formation.CARRIER:
				ok_band = off <= -carrier_back + 1.0
		if not ok_band:
			out.append("%s: место в %.0f от линии по оси (полоса %d)" % [str(r["id"]), off, band])
	return out


## Прибытие резерва Тройдена в «Сражении» (seed 9). calm — без боя рядом: у противника
## один неподвижный крейсер в 3000 от своей линии, никто никого не видит в дальности, и
## проскок мимо места меряется чистым (иначе «Охрана» на поводке уводит корабль к цели —
## это не проскок). line_z — куда сдвинуть свой флот (край поля — выход вбок).
func _reinforce_run(calm: bool, line_z: float = 0.0) -> Dictionary:
	var d := _defs()
	var b := Battle.create(d, {"attacker": &"troyden", "defender": &"plektor", "size": &"mid", "seed": 9, "reserve": true}) as Battle
	if calm:
		var keep: Array[Ship] = []
		for s in b.ships:
			if s.side == Ship.ATTACKER:
				s.pos.y += line_z
				s.anchor.y += line_z
				keep.append(s)
		b.ships.assign(keep)
		var foe := b.spawn(Ship.DEFENDER, d.ship(&"plektor", &"cruiser"), Vector2(0.0, d.doctrine.deploy_heavy_z + line_z - 3000.0))
		foe.switch_off(&"engines", 1.0e9)
		foe.stance = &"hold"
		foe.main_cd = PackedFloat64Array()
		foe.sec_cd = PackedFloat64Array()
		foe.pd_cd = PackedFloat64Array()
	b.queue({"op": &"reinforce", "side": Ship.ATTACKER})
	b.queue({"op": &"reinforce", "side": Ship.ATTACKER})
	var t_in := -1.0
	var rows: Array = []
	var by: Dictionary = {}
	var lim := d.consts.field_half - d.doctrine.reinforce_exit_edge
	var car_ahead := -INF
	for i in roundi(70.0 / Battle.STEP):
		b.step()
		for ev in b.events:
			if ev[0] == &"jump_in":
				var u: int = ev[1]
				var s := b.ship_by_uid(u)
				var sd := b.sides[s.side]
				var r := {"id": s.def.id, "uid": u, "anchor": s.anchor, "line": sd.line, "ax": sd.ax, "exit": s.pos,
					"band": Formation.role_of(s.def), "over": 0.0, "settled": false,
					"edge": absf(s.pos.x) <= lim + 1e-6 and absf(s.pos.y) <= lim + 1e-6, "stop_t": -1.0, "rest": INF}
				rows.append(r)
				by[u] = r
				if t_in < 0.0:
					t_in = b.time
		# носитель впереди своей линии тяжёлых — ни на одном шаге (план G4, п. 8). Линия —
		# та, что стояла в миг выхода: прибывший крейсер сам двигает центр тяжёлых, и мерить
		# от него значило бы мерить носитель от проскочившего вместе с ним крейсера
		for u: int in by:
			var cs := b.ship_by_uid(u)
			var cr: Dictionary = by[u]
			if cs != null and not cs.dead and cs.hangar != null:
				var lax: Vector2 = cr["ax"]
				var lln: Vector2 = cr["line"]
				car_ahead = maxf(car_ahead, (cs.pos - lln).dot(lax))
		# проскок мимо места — по оси линии, пока корабль впервые не встал
		for u: int in by:
			var r: Dictionary = by[u]
			if flag(r["settled"]):
				continue
			var s := b.ship_by_uid(u)
			if s == null or s.dead:
				r["settled"] = true
				continue
			var ax: Vector2 = r["ax"]
			var anc: Vector2 = r["anchor"]
			r["over"] = maxf(num(r["over"]), (s.pos - anc).dot(ax))
			if b.time > t_in + 1.0 and s.vel.length() < 0.05 * s.max_speed():
				r["settled"] = true
				r["stop_t"] = b.time - t_in
				r["rest"] = s.pos.distance_to(anc)
	var t_call: float = b.toast_log[0]["t"] if not b.toast_log.is_empty() else 0.0
	var texts := PackedStringArray()
	for t: Dictionary in b.toast_log:
		texts.append(str(t["text"]))
	var out := {"rows": rows, "waited": t_in - t_call, "texts": "\n".join(texts), "l": 0.0, "car_ahead": car_ahead}
	var mine: Array[Ship] = []
	for s in b.ships:
		if not s.dead and s.side == Ship.ATTACKER and not s.station:
			mine.append(s)
	out["l"] = Formation.line_l(d, Formation.members_from(mine))
	b.dispose()
	return out


func test_reinforcement_goes_to_own_line() -> void:
	var d := _defs()
	var r := _reinforce_run(false)
	var waited := num(r["waited"])
	ok(waited >= d.hyper.reinforce_delay - 1e-6 and waited < d.hyper.reinforce_delay + Battle.STEP, "резерв вышел через %.3f с после вызова по игровым часам (32)" % waited)
	var rows: Array = r["rows"]
	eq(rows.size(), 5, "вышли все пять кораблей резерва Тройдена")
	ok(str(r["texts"]).contains("уже в пути"), "второй вызов не зовёт резерв второй раз — полоска «уже в пути»: %s" % str(r["texts"]))
	var bad := arrivals_target_problems(rows, num(r["l"]), d.doctrine.line_carrier_back)
	ok(bad.is_empty(), "прибывшие встают на свои места в строю от линии стороны: %s" % "; ".join(bad))
	# откат: цель из JS — (x × 0,4; 0; +120), середина поля
	var js: Array = []
	for row: Dictionary in rows:
		var j := row.duplicate()
		var anc: Vector2 = row["anchor"]
		j["anchor"] = Vector2(anc.x * d.consts.reinforce_drop_goto_x_k, d.consts.reinforce_drop_goto_z)
		js.append(j)
	ok(not arrivals_target_problems(js, num(r["l"]), d.doctrine.line_carrier_back).is_empty(), "откат «цель — середина поля, как в JS» краснеет")


## Выход — тормозной путь + reinforce.exit_pad перед местом: встаёт на месте без проскока.
## Без боя рядом (проскок «Охраны» к цели — не проскок). Откат — выход у края, как в JS.
static func _overshoot(rows: Array) -> Array:
	var worst := 0.0
	var who := ""
	var parts := PackedStringArray()
	var all_settled := true
	for row: Dictionary in rows:
		all_settled = all_settled and flag_of(row["settled"])
		var o: float = row["over"]
		if o > worst:
			worst = o
			who = str(row["id"])
		var st: float = row["stop_t"]
		var rest: float = row["rest"]
		parts.append("%s %.0f (встал на %.1f с в %.0f от места)" % [str(row["id"]), o, st, rest])
	return [worst, who, ", ".join(parts), all_settled]


static func flag_of(v: Variant) -> bool:
	var b: bool = v
	return b


func test_reinforcement_stops_at_place() -> void:
	var d := _defs()
	var r := _reinforce_run(true)
	var rows: Array = r["rows"]
	eq(rows.size(), 5, "без боя: вышли все пять")
	var w := _overshoot(rows)
	ok(flag(w[3]), "все встали")
	ok(num(w[0]) <= d.doctrine.reinforce_exit_pad, "проскок мимо своего места не больше reinforce.exit_pad: худший %.1f (%s)" % [num(w[0]), str(w[1])])
	for row: Dictionary in rows:
		ok(num(row["rest"]) < 30.0, "%s встал у своего места (в %.0f)" % [str(row["id"]), num(row["rest"])])
	note("подкрепление: проскок по оси — %s; носитель от своей линии тяжёлых не ближе %.0f позади" % [str(w[2]), -num(r["car_ahead"])])
	ok(num(r["car_ahead"]) < 0.0, "носитель ни на одном шаге не впереди своей линии тяжёлых (ближе всего %.0f позади)" % -num(r["car_ahead"]))
	Battle.rollback_drop_at_edge = true
	var o := _reinforce_run(true)
	Battle.rollback_drop_at_edge = false
	var ow := _overshoot(arr(o["rows"]))
	ok(num(ow[0]) > d.doctrine.reinforce_exit_pad, "откат «выход у края, как в JS»: проскок %.0f (%s) — проверка краснеет" % [num(ow[0]), str(ow[1])])
	ok(num(o["car_ahead"]) > 0.0, "откат «выход у края»: носитель выходит на %.0f впереди своей линии тяжёлых — проверка краснеет" % num(o["car_ahead"]))
	note("откат «выход у края»: %s; носитель на %.0f впереди своей линии" % [str(ow[2]), num(o["car_ahead"])])
	# линия у самого края поля: выход вбок, не ближе reinforce.exit_edge к краю
	var shift := 1900.0 - d.doctrine.deploy_heavy_z
	var e := _reinforce_run(true, shift)
	for row: Dictionary in arr(e["rows"]):
		ok(flag(row["edge"]), "линия у края: %s выходит не ближе reinforce.exit_edge к краю (%s)" % [str(row["id"]), str(row["exit"])])
	var we := _overshoot(arr(e["rows"]))
	ok(num(we[0]) <= d.doctrine.reinforce_exit_pad, "линия у края: проскок не больше exit_pad (%.0f, %s)" % [num(we[0]), str(we[1])])
	Battle.rollback_exit_no_edge = true
	var eo := _reinforce_run(true, shift)
	Battle.rollback_exit_no_edge = false
	var out_n := 0
	var eor := arr(eo["rows"])
	for row: Dictionary in eor:
		if not flag(row["edge"]):
			out_n += 1
	ok(out_n > 0, "откат «выход без края»: за краем %d из %d — проверка краснеет" % [out_n, eor.size()])


# ───────────────────────── составы и имена ─────────────────────────

func test_compositions_from_sizes() -> void:
	var d := _defs()
	var rows := 0
	for size in d.quick.size_ids:
		for f in d.faction_ids:
			var got := Battle.compose(d, size, f)
			var want := d.quick.fleet(size, f)
			var gs := PackedStringArray()
			for e in got:
				gs.append("%s %d" % [e.id, e.count])
			var ws := PackedStringArray()
			for e in want:
				ws.append("%s %d" % [e.id, e.count])
			eq(", ".join(gs), ", ".join(ws), "состав %s %s из масштаба и множителя клана" % [size, f])
			rows += 1
	eq(rows, 12, "сверено составов: все строки 01, 2.15")
	for f in d.faction_ids:
		var rs := Battle.compose(d, &"small", f)
		var l: Defs.Lineup = d.quick.reserve.get(f)
		eq(Battle.ids_of(rs).size(), Battle.ids_of(l.entries).size(), "резерв %s — «Стычка» своего клана" % f)
	# числа 01, 4.2 п. 2
	var b := Battle.create(d, {"attacker": &"troyden", "defender": &"plektor", "size": &"mid", "seed": 1, "reserve": true}) as Battle
	eq(b.side_ships(Ship.ATTACKER).size(), 8, "«Сражение»: у Тройдена 8")
	eq(b.side_ships(Ship.DEFENDER).size(), 22, "«Сражение»: у Плэктора 22")
	eq(Battle.ids_of(b.sides[Ship.ATTACKER].reserve).size(), 5, "резерв Тройдена — 5")
	var has_station := false
	for s in b.ships:
		has_station = has_station or s.station
	ok(not has_station, "в «Сражении» станции нет")
	b.dispose()
	var g := Battle.create(d, {"attacker": &"troyden", "defender": &"plektor", "size": &"big", "seed": 1, "reserve": false}) as Battle
	var st := 0
	for s in g.side_ships(Ship.DEFENDER):
		if s.station:
			st += 1
	eq(st, 1, "«Генеральное»: у защитника станция")
	eq(g.side_ships(Ship.ATTACKER).size(), 11, "Тройден «Генеральное» — 11")
	g.dispose()
	eq(Battle.ids_of(Battle.compose(d, &"small", &"plektor")).size(), 14, "Плэктор «Стычка» — 14")
	# откат ловушки 19: множитель до выброса нулей — у Тройдена в «Стычке» появился бы флагман
	var sc: Defs.ScaleDef = d.quick.scale[&"troyden"]
	var cap0 := maxi(sc.at_least, roundi(0.0 * sc.mul))
	ok(cap0 == 1, "откат «нули после множителя»: max(1, round(0 × 0,7)) = %d флагман — сверка составов краснела бы" % cap0)


static func name_problems(ships: Array[Ship]) -> PackedStringArray:
	var out := PackedStringArray()
	var seen: Dictionary = {}
	for s in ships:
		var k := "%d:%s" % [s.side, s.name]
		if seen.has(k):
			out.append("имя повторяется: %s" % s.name)
		seen[k] = true
	return out


func test_names_numbered() -> void:
	var d := _defs()
	var b := Battle.create(d, {"attacker": &"plektor", "defender": &"troyden", "size": &"big", "seed": 2, "reserve": true}) as Battle
	b.call_reinforcements(Ship.ATTACKER)
	for i in roundi(33.0 / Battle.STEP):
		b.step()
	ok(name_problems(b.ships).is_empty(), "у стороны имена уникальны: %s" % "; ".join(name_problems(b.ships)))
	var corv := PackedStringArray()
	for s in b.ships:
		if s.side == Ship.ATTACKER and s.def.id == &"corvette":
			corv.append(s.name)
	var base := d.ship(&"plektor", &"corvette").name
	ok(corv.size() >= 11, "корветов Плэктора с резервом %d" % corv.size())
	ok(base + " II" in corv, "второй корабль вида — « II»: %s" % ", ".join(corv))
	ok(base + " XI" in corv, "одиннадцатый — « XI»")
	eq(Battle.roman(11), "XI", "римский номер 11")
	eq(Battle.roman(20), "XX", "римский номер 20")
	# откат: имена без номера (как до P5) — три «Рэш» подряд
	var bare: Array[Ship] = []
	for s in b.ships:
		var t := Ship.new()
		t.side = s.side
		t.name = s.def.name
		bare.append(t)
	ok(not name_problems(bare).is_empty(), "откат «имя без номера» краснеет")
	b.dispose()


## hull — от длины модели (C87, C88): max(1,6 × radius, 0,36 × len) = замер JS.
func test_hull_from_model_length() -> void:
	var d := _defs()
	var b := _lab(&"plektor")
	for id in CLASSES:
		var s := _one(b, id)
		near(s.hull, _hull_ref(id), 0.01, "%s: корпус от длины модели" % id)
	var st := b.spawn(Ship.DEFENDER, d.station, Vector2.ZERO)
	near(st.hull, d.station.hull, 0.01, "станция: корпус от длины модели")
	b.dispose()


# ───────────────────────── повторяемость и запись ─────────────────────────

## Сценарий: приказы на разных шагах, подкрепление (в нём — случайность rng боя).
func _scenario(b: Battle, steps_n: int) -> void:
	var mine := b.side_ships(Ship.ATTACKER)
	for i in steps_n:
		if i == 5:
			b.queue({"op": &"move", "ids": [mine[0].uid, mine[1].uid, mine[2].uid], "x": 200.0, "z": 100.0})
		if i == 40:
			b.queue({"op": &"reinforce", "side": Ship.ATTACKER})
		if i == 200:
			b.queue({"op": &"drift", "ids": [mine[0].uid]})
		if i == 400:
			b.queue({"op": &"stance", "ids": [mine[1].uid], "stance": &"hold"})
		if i == 600:
			b.queue({"op": &"hyper", "ids": [mine[3].uid]})
		b.step()


func _fresh(seed_n: int, d: Defs = null) -> Battle:
	var dd := d if d != null else _defs()
	return Battle.create(dd, {"attacker": &"troyden", "defender": &"plektor", "size": &"mid", "seed": seed_n, "reserve": true}, "capella-проверка") as Battle


func test_same_seed_same_battle_and_replay() -> void:
	var a := _fresh(11)
	_scenario(a, 1500)
	var b := _fresh(11)
	_scenario(b, 1500)
	eq(a.fingerprint(), b.fingerprint(), "один бой дважды — один отпечаток")
	var c := _fresh(12)
	_scenario(c, 1500)
	ok(c.fingerprint() != a.fingerprint(), "другое зерно — другой бой (зерно доходит до выхода резерва)")
	# запись → текст → повтор
	var text := JSON.stringify(a.record())
	var j := JSON.new()
	ok(j.parse(text) == OK, "запись боя — JSON")
	var rec := dict(j.data)
	var why := PackedStringArray()
	var r := Battle.from_record(_defs(), rec, "capella-проверка", why) as Battle
	if ok(r != null, "запись проигрывается своей сборкой: %s" % "; ".join(why)):
		var n: float = rec["steps"]
		for i in roundi(n):
			r.step()
		eq(r.fingerprint(), a.fingerprint(), "повтор по журналу команд — тот же бой")
		r.dispose()
	# чужая сборка и чужие числа — отказ словами, а не другой бой
	var why2 := PackedStringArray()
	ok(Battle.from_record(_defs(), rec, "capella-v9.9", why2) == null and "\n".join(why2).contains("другой сборкой"), "чужая сборка: отказ — «%s»" % "; ".join(why2))
	var d2 := Defs.load_default({"main.dead_k": 0.43}) as Defs
	var why3 := PackedStringArray()
	ok(Battle.from_record(d2, rec, "capella-проверка", why3) == null and "\n".join(why3).contains("других числах"), "другие числа боя: отказ — «%s»" % "; ".join(why3))
	# откат: повтор без журнала команд — другой бой
	var rec0 := rec.duplicate(true)
	rec0["cmds"] = []
	var r0 := Battle.from_record(_defs(), rec0, "capella-проверка", PackedStringArray()) as Battle
	for i in 1500:
		r0.step()
	ok(r0.fingerprint() != a.fingerprint(), "откат «повтор без журнала команд» — бой другой, сверка краснеет")
	for x: Battle in [a, b, c, r0] as Array[Battle]:
		x.dispose()


## Команда применяется в начале СЛЕДУЮЩЕГО шага (архитектура, 1 п. 3).
func test_command_applies_next_step() -> void:
	var b := _lab()
	var s := _one(b, &"corvette")
	b.queue({"op": &"move", "ids": [s.uid], "x": 0.0, "z": -500.0})
	ok(not s.has_move, "до шага приказ не применён")
	b.step()
	ok(s.has_move, "приказ применён в начале следующего шага")
	eq(b.cmds.journal.size(), 1, "приказ — в журнале")
	var c: Dictionary = b.cmds.journal[0]
	eq(c["step"], 1, "у приказа в журнале — номер шага")
	b.dispose()


# ───────────────────────── память ─────────────────────────

## Объектов после пяти боёв не больше, чем после первого (архитектура, 2.12). В бою —
## кольца ссылок (охрана друг друга), как будут цели с G2. Откат — без dispose().
func _battles(n: int, with_dispose: bool, keep: Array[Battle]) -> Array[int]:
	var counts: Array[int] = []
	for k in n:
		var b := _fresh(20 + k)
		var mine := b.side_ships(Ship.ATTACKER)
		mine[0].guard_of = mine[1]
		mine[1].guard_of = mine[0]
		mine[2].target = mine[3]
		mine[3].target = mine[2]
		for i in 200:
			b.step()
		if with_dispose:
			b.dispose()
		else:
			keep.append(b)      # откат: бой брошен без dispose(); после замера разберём
		b = null
		counts.append(roundi(Performance.get_monitor(Performance.OBJECT_COUNT)))
	return counts


func test_memory_after_battles() -> void:
	var keep: Array[Battle] = []
	var c := _battles(5, true, keep)
	ok(c[4] <= c[0], "объектов после пяти боёв (%d) не больше, чем после первого (%d)" % [c[4], c[0]])
	var r := _battles(5, false, keep)
	ok(r[4] > r[0], "откат «без dispose()»: объекты копятся (%d → %d) — проверка краснеет" % [r[0], r[4]])
	for b in keep:
		b.dispose()


# ───────────────────────── хвосты G1: строй «идти» и отпечаток ─────────────────────────

## ПКМ по полю (09, 6.4; план G4, п. 2): выделенные идут со скоростью самого медленного
## (ловушка 6 части 02, C70) и встают СТРОЕМ ПО РОЛЯМ у точки — той же sim/formation.gd →
## places(), что строй на старте и места прибывших: тяжёлые линией через точку (шаг
## hull + hull + 60 — шире расталкивания, ловушка 9), корветы на 0,35 L впереди по оси.
## Ось — от точки к чужим; никого не видно — по ходу марша. Откаты — «каждый своей
## скоростью», «все в одну точку» и «как стояли» (прежнее «клик + своё место от центра»).
func _march(own_speed: bool, one_point: bool, keep_layout: bool = false) -> Dictionary:
	Battle.rollback_move_own_speed = own_speed
	Battle.rollback_move_one_point = one_point
	Battle.rollback_move_keep_layout = keep_layout
	var b := _lab()
	var list: Array[Ship] = [_one(b, &"corvette", Vector2(-150, 0)), _one(b, &"cruiser", Vector2(0, 60)), _one(b, &"capital", Vector2(170, -20))]
	var ids := PackedInt32Array()
	var center := Vector2.ZERO
	var slow := INF
	for s in list:
		ids.append(s.uid)
		center += s.pos
		slow = minf(slow, s.max_speed())
	center /= 3.0
	var click := Vector2(40.0, -900.0)
	var ax := (click - center).normalized()
	var lat := Vector2(-ax.y, ax.x)
	var l := Formation.line_l(b.defs, Formation.members_from(list))
	b.queue({"op": &"move", "ids": ids, "x": click.x, "z": click.y})
	b.step()
	var corv := (list[0].move_to - click).dot(ax)
	var heavy_ax := maxf(absf((list[1].move_to - click).dot(ax)), absf((list[2].move_to - click).dot(ax)))
	var heavy_gap := absf((list[1].move_to - list[2].move_to).dot(lat))
	var need := Formation.hull_of(b.defs, list[1].def) + Formation.hull_of(b.defs, list[2].def)
	var spread_dest := 0.0
	for k in 3:
		for j in 3:
			spread_dest = maxf(spread_dest, list[k].move_to.distance_to(list[j].move_to))
	var fastest := 0.0
	var arrive: Array[float] = [-1.0, -1.0, -1.0]
	for i in roundi(90.0 / Battle.STEP):
		b.step()
		fastest = maxf(fastest, list[0].vel.length())
		for k in 3:
			if arrive[k] < 0.0 and not list[k].has_move:
				arrive[k] = b.time
	var spread := 0.0
	for k in 3:
		for j in 3:
			spread = maxf(spread, absf(arrive[k] - arrive[j]))
	var out := {"corv": corv, "want_corv": b.defs.doctrine.line_corvette_k * l, "heavy_ax": heavy_ax, "heavy_gap": heavy_gap,
		"need": need, "dest_spread": spread_dest, "fastest": fastest, "slow": slow, "spread": spread, "all": arrive.min() > 0.0}
	b.dispose()
	Battle.rollback_move_own_speed = false
	Battle.rollback_move_one_point = false
	Battle.rollback_move_keep_layout = false
	return out


static func march_layout_problems(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var corv: float = r["corv"]
	var want: float = r["want_corv"]
	if absf(corv - want) > 1.0:
		out.append("корвет в %.0f впереди точки по оси, а не в 0,35 L = %.0f" % [corv, want])
	var hx: float = r["heavy_ax"]
	if hx > 1.0:
		out.append("тяжёлые не на линии через точку (до %.0f по оси)" % hx)
	var gap: float = r["heavy_gap"]
	var need: float = r["need"]
	if gap < need:
		out.append("тяжёлые ближе hull + hull (%.0f < %.0f)" % [gap, need])
	return out


func test_move_group_slowest_and_layout() -> void:
	var r := _march(false, false)
	var bad := march_layout_problems(r)
	ok(bad.is_empty(), "ПКМ по полю: строй по ролям у точки — %s" % ("; ".join(bad) if not bad.is_empty() else "корвет %.0f впереди (0,35 L), тяжёлые на линии через точку, между ними %.0f (hull + hull %.0f)" % [num(r["corv"]), num(r["heavy_gap"]), num(r["need"])]))
	ok(num(r["fastest"]) <= num(r["slow"]) + 0.5, "корвет в строю не быстрее самого медленного: %.1f при %.1f (ловушка 6 части 02)" % [num(r["fastest"]), num(r["slow"])])
	ok(flag(r["all"]) and num(r["spread"]) < 8.0, "строй пришёл вместе: разброс прихода %.1f с" % num(r["spread"]))
	note("ПКМ по полю: корвет %.0f впереди, тяжёлые через %.0f, приход разошёлся на %.1f с" % [num(r["corv"]), num(r["heavy_gap"]), num(r["spread"])])
	var own := _march(true, false)
	ok(num(own["fastest"]) > num(own["slow"]) * 1.3, "откат «каждый своей скоростью»: корвет %.1f при самом медленном %.1f — проверка краснеет" % [num(own["fastest"]), num(own["slow"])])
	var one := _march(false, true)
	ok(num(one["dest_spread"]) < 1.0 and not march_layout_problems(one).is_empty(), "откат «все в одну точку»: строя нет — проверка краснеет")
	var keep := _march(false, false, true)
	ok(not march_layout_problems(keep).is_empty(), "откат «как стояли» (клик + место от центра): %s — проверка краснеет" % "; ".join(march_layout_problems(keep)))


## Отпечаток боя видит и ПРИКАЗЫ, и состояние СТОРОН (хвост G1): повтор, потерявший
## приказ, который ещё не успел сдвинуть ни один корабль, обязан дать «не совпало».
## Откат — прежний отпечаток (положения и прочность): он такой повтор не замечает.
func _lost_order(kind: String) -> Array:
	var make := func(with_last: bool) -> Battle:
		var b := _fresh(31)
		var mine := b.side_ships(Ship.ATTACKER)
		for i in 300:
			if i == 299 and with_last:
				match kind:
					"stance":
						# «Держать» кораблю, который стоит без цели: в этот шаг он не сдвинется
						# (с G4 «Охота» сразу ищет цель дальше и трогается с места)
						var calm := mine[0]
						for s in mine:
							if s.target == null and s.vel.length() < 1e-3 and not s.has_move:
								calm = s
								break
						b.queue({"op": &"stance", "ids": [calm.uid], "stance": &"hold"})
					"reserve":
						b.queue({"op": &"reinforce", "side": Ship.ATTACKER})
					"drift":
						b.queue({"op": &"drift", "ids": [mine[1].uid]})
			b.step()
		b.step()
		return b
	var full: Battle = make.call(true)
	var lost: Battle = make.call(false)
	var new_fp := [full.fingerprint(), lost.fingerprint()]
	Battle.rollback_fp_positions = true
	var old_fp := [full.fingerprint(), lost.fingerprint()]
	Battle.rollback_fp_positions = false
	full.dispose()
	lost.dispose()
	return [new_fp, old_fp]


func test_fingerprint_sees_orders_and_sides() -> void:
	for kind: String in ["stance", "reserve", "drift"]:
		var r := _lost_order(kind)
		var nf: Array = r[0]
		var of: Array = r[1]
		ok(str(nf[0]) != str(nf[1]), "повтор без последнего приказа (%s) — «не совпало»: %s против %s" % [kind, str(nf[0]), str(nf[1])])
		ok(str(of[0]) == str(of[1]), "откат «отпечаток по положениям» (%s): потерянный приказ не виден (%s = %s) — проверка краснеет" % [kind, str(of[0]), str(of[1])])
