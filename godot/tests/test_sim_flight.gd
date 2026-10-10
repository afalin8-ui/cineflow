# Модель боя G1: шаг, полёт, приказы движения, гипер, подкрепление, повтор, память
# (план G1, «Проверки»; часть 02, 4.2; часть 01, 4.2 пп. 2–3, 8). Каждая проверка —
# с откатом: на копии без правки (или с выключенным правилом) она обязана краснеть.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Movement := preload("res://sim/movement.gd")

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


## Куда идут прибывшие: ЦЕЛЬ — своя линия старта (±deploy.heavy_z), а не середина
## поля (x × 0,4; 0; ±120) из JS — пояс и мёртвая зона чужих тяжёлых (09, 5.5 и 9.1;
## план G1, п. 3). Проверяется цель, а не место: проскок с 2,6 × maxSpeed мимо неё —
## G4, п. 8.
static func arrivals_target_problems(anchors: PackedFloat64Array, line_z: float, sign_z: float) -> PackedStringArray:
	var out := PackedStringArray()
	for z in anchors:
		if absf(z - sign_z * line_z) > 1e-6:
			out.append("участок прибывшего на z = %.0f, а линия старта — %.0f" % [z, sign_z * line_z])
		if absf(z) < line_z * 0.5:
			out.append("участок прибывшего на z = %.0f — середина поля" % z)
	return out


func test_reinforcement_goes_to_own_line() -> void:
	var d := _defs()
	var b := Battle.create(d, {"attacker": &"troyden", "defender": &"plektor", "size": &"mid", "seed": 9, "reserve": true}) as Battle
	b.queue({"op": &"reinforce", "side": Ship.ATTACKER})
	b.queue({"op": &"reinforce", "side": Ship.ATTACKER})
	var t_in := -1.0
	var anchors := PackedFloat64Array()
	var n_in := 0
	for i in roundi(40.0 / Battle.STEP):
		b.step()
		for ev in b.events:
			if ev[0] == &"jump_in":
				var u: int = ev[1]
				anchors.append(b.ship_by_uid(u).anchor.y)
				n_in += 1
				if t_in < 0.0:
					t_in = b.time
	var t_call: float = b.toast_log[0]["t"] if not b.toast_log.is_empty() else 0.0
	var waited := t_in - t_call
	ok(waited >= d.hyper.reinforce_delay - 1e-6 and waited < d.hyper.reinforce_delay + Battle.STEP, "резерв вышел через %.3f с после вызова по игровым часам (32)" % waited)
	eq(n_in, 5, "вышли все пять кораблей резерва Тройдена")
	var texts := PackedStringArray()
	for t: Dictionary in b.toast_log:
		texts.append(str(t["text"]))
	ok("\n".join(texts).contains("уже в пути"), "второй вызов не зовёт резерв второй раз — полоска «уже в пути»: %s" % " | ".join(texts))
	var bad := arrivals_target_problems(anchors, d.doctrine.deploy_heavy_z, 1.0)
	ok(bad.is_empty(), "прибывшие встают на своей линии старта: %s" % "; ".join(bad))
	# откат: цель из JS — (x × 0,4; 0; +120), середина поля
	var js := PackedFloat64Array()
	for z in anchors:
		js.append(d.consts.reinforce_drop_goto_z)
	ok(not arrivals_target_problems(js, d.doctrine.deploy_heavy_z, 1.0).is_empty(), "откат «цель — середина поля, как в JS» краснеет")
	b.dispose()


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
