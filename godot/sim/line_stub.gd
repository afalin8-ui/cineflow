# sim/line_stub.gd — ЗАГЛУШКА СТРОЯ вместо ИИ (план G4, п. 6): ровно шаги 6–7 тика ИИ
# 09, 7.1 и ничего больше. Без неё замеры G4 мерить нечем: линии стоят на старте в 1300 —
# дальше любой дальности (920), — и «Охрана» с поводком 0,5 R никого к бою не ведёт.
# Это НЕ второй ИИ: в G5 те же шаги станут частью ai.gd, а заглушка удалится.
#
# Раз в тик (как ИИ: первый на 3 × tempo с, дальше rnd(2,5; 4) × tempo, space.js:1757):
# 6. линия: F_h (центр видимых чужих тяжёлых в строю, нет — видимых чужих), R_line,
#    L = 0,85 R_line, P = F_h − ax × L; сдвиг P не больше line.shift_max за тик, поворот
#    оси не больше line.turn_max_deg; P не за тыловым рубежом (линия старта + line.rear)
#    и не ближе line.edge к краю поля вместе с носителями. P НЕ считается от своих
#    отходящих (09, 9.5 п. 3): ось — от прежнего P к F_h, L — число.
# 7. места по полосам той же sim/formation.gd → places(); раздача по положению — только
#    когда сменился состав (5.4), иначе каждый держит своё. Корабли — на «Охране» с участком
#    = место (не moveTo, 09, 9.5 п. 15); фрегаты — поводок leash.frigate_ai (3.1).
extends RefCounted

const State := preload("res://sim/state.gd")
const Defs := preload("res://sim/defs.gd")
const Ship := preload("res://sim/ship.gd")
const Formation := preload("res://sim/formation.gd")
const Vision := preload("res://sim/vision.gd")

# space.js:1757 aiThink — как часто думает ИИ: первый тик на 3 × tempo, дальше
# rnd(2,5; 4) × tempo (battle_constants.ai_think — «переносятся кодом»)
const THINK_FIRST := 3.0
const THINK_MIN := 2.5
const THINK_MAX := 4.0


## Завести заглушку стороне: первый тик, тыловой рубеж, место линии — линия старта.
static func arm(b: State, side: int) -> void:
	var sd := b.sides[side]
	sd.stub = true
	sd.stub_next = THINK_FIRST * _tempo(b)
	sd.rear_z = b.defs.doctrine.deploy_heavy_z + b.defs.doctrine.line_rear
	sd.stub_p = Vector2(0.0, sd.sign_z * b.defs.doctrine.deploy_heavy_z)
	sd.stub_ax = Vector2(0.0, -sd.sign_z)
	sd.stub_set = true


static func _tempo(b: State) -> float:
	var dif: Defs.DifficultyDef = b.defs.difficulty.get(StringName(str(b.setup.get("difficulty", b.defs.quick.default_difficulty))))
	if dif == null or dif.tempo <= 0.0:
		return 1.0
	return dif.tempo


## Тик заглушки обеих сторон — в порядке шага там, где думает ИИ (после прибывших, до
## кораблей; архитектура, 2.4). Обе стороны думают по ОДНОМУ состоянию начала шага: места
## сначала считаются обеим, потом раздаются.
static func tick(b: State) -> void:
	var plans: Array = []
	for side in b.sides.size():
		var sd := b.sides[side]
		if not sd.stub or sd.retreat or b.time < sd.stub_next:
			plans.append(null)
			continue
		sd.stub_next = b.time + b.rng.randf_range(THINK_MIN, THINK_MAX) * _tempo(b)
		plans.append(_plan(b, side))
	for side in plans.size():
		var pl: Variant = plans[side]
		if pl != null:
			var arr: Array = pl
			_apply(b, side, arr)


## Шаги 6–7 для стороны: → [корабли, места] (или null — никого не видно: поиск — G5).
static func _plan(b: State, side: int) -> Variant:
	var d := b.defs.doctrine
	var sd := b.sides[side]
	# F_h: видимые чужие тяжёлые в строю (без станции и копящих гипер); нет — видимые чужие
	var fh := Vector2.ZERO
	var nh := 0
	var fa := Vector2.ZERO
	var na := 0
	var foe_dead := INF
	var foe_air := false
	for o in b.ships:
		if o.dead or o.side == side or not Vision.sees(b, side, o):
			continue
		if o.hangar != null:
			foe_air = true
		if o.station:
			continue
		fa += o.pos
		na += 1
		if o.heavy() and not o.charging():
			fh += o.pos
			nh += 1
			foe_dead = minf(foe_dead, o.def.main.dead)
	if na == 0:
		return null
	var f := fh / float(nh) if nh > 0 else fa / float(na)
	var mine: Array[Ship] = []
	for s in b.ships:
		if not s.dead and s.side == side and not s.station and not s.charging():
			mine.append(s)
	if mine.is_empty():
		return null
	var members := Formation.members_from(mine)
	var l := Formation.line_l(b.defs, members)
	if l <= 0.0:
		# своих тяжёлых нет: шаги 6–7 без R_line не считаются (P = F_h — лёгкие шли бы прямо
		# в чужую линию, найдено стендом G4). У ИИ это «без тяжёлых — уход» и «Охота» лёгких
		# (05, 2.6 п. 7; 09, 7.2 leaderless) — G5; заглушка места не трогает
		return null
	# ось — от прежнего P к F_h, поворот не больше turn_max (5.6). БЕЗ atan2/sin/cos
	# библиотеки C: они у Linux (glibc) и Windows (MSVC) расходятся в последнем бите, и бой
	# расходился между системами (найдено CI G4: с правкой main.dead_k отпечатки разные).
	# Поворот на предел — сложением с постоянными cos/sin, посчитанными рядом (_cos_sin);
	# в пределе — сама желаемая ось
	var want_ax := f - sd.stub_p
	if want_ax.length_squared() < 1.0:
		want_ax = sd.stub_ax
	want_ax = want_ax.normalized()
	var ax := want_ax
	var cs := _cos_sin(deg_to_rad(d.line_turn_max_deg))
	if sd.stub_ax.dot(want_ax) < cs.x:
		var sgn := 1.0 if sd.stub_ax.cross(want_ax) >= 0.0 else -1.0
		ax = (sd.stub_ax * cs.x + Vector2(-sd.stub_ax.y, sd.stub_ax.x) * (sgn * cs.y)).normalized()
	var p_want := f - ax * l
	var step := p_want - sd.stub_p
	if step.length() > d.line_shift_max:
		step = step * (d.line_shift_max / step.length())
	var p := sd.stub_p + step
	# P не убегает вперёд своей линии тяжёлых дальше line.lead_max (найдено стендом G4: P
	# считается от чужих тяжёлых, которые ещё в пути, и P обеих сторон съезжались до 300 —
	# шеренги лёгких проходили сквозь друг друга). ТОЛЬКО ВПЕРЁД: если свои отошли, P на месте
	# — отход своих точку линии назад не тянет (09, 9.5 п. 3)
	var own := Formation.line_of(b.ships, side)
	if own.heavy:
		var lead := (p - own.center).dot(ax)
		var allow := maxf((sd.stub_p - own.center).dot(ax), d.line_lead_max)
		if lead > allow:
			p -= ax * (lead - allow)
	# тыловой рубеж: P не дальше линии старта + line.rear вглубь своей стороны (2.6). Упёрлись —
	# P встаёт на рубеж НА ОСИ от F_h (ближе L), а не срезается по z: срезанная только по z
	# точка уползала вбок с каждым тиком (ось считается от прежнего P)
	if p.y * sd.sign_z > sd.rear_z:
		var lim_y := sd.sign_z * sd.rear_z
		if absf(p.y - f.y) > 1e-6:
			p = f + (p - f) * ((lim_y - f.y) / (p.y - f.y))
		p.y = lim_y
	# край поля: P и носители позади (−carrier_back по оси) — не ближе line.edge к краю
	var edge := b.mp.field - d.line_edge
	var back := p - ax * d.line_carrier_back
	for k in 2:
		var over_p := maxf(absf(p[k]) - edge, 0.0)
		var over_b := maxf(absf(back[k]) - edge, 0.0)
		var sh := maxf(over_p, over_b)
		if sh > 0.0:
			var sgn := signf(p[k]) if over_p >= over_b else signf(back[k])
			p[k] -= sgn * sh
	sd.stub_p = p
	sd.stub_ax = ax
	# состав сменился (гибель, гипер, прибывшие) — места заново по положению (5.4)
	var roster := PackedStringArray()
	for s in mine:
		roster.append("%d" % s.uid)
	var key := ",".join(roster)
	var spec := Formation.Spec.new()
	spec.p = p
	spec.ax = ax
	spec.foe_width = Formation.line_width(b.ships, 1 - side, Vector2(-ax.y, ax.x))
	spec.foe_air = foe_air
	spec.by_pos = key != sd.stub_roster
	spec.ecm_01l = b.ecm_01l
	sd.stub_roster = key
	# носитель уходит на −760, если чужой корабль ближе line.carrier_close_dist к нему
	for s in mine:
		if s.hangar == null:
			continue
		for o in b.ships:
			if not o.dead and o.side != side and not o.station and Vision.sees(b, side, o) and o.pos.distance_to(s.pos) < d.line_carrier_close_dist:
				spec.carrier_close = true
	# середина выиграна (3.5): нет видимых чужих лёгких, кроме РЭБ, в полосе [0,2 L; 0,8 L]
	if l > 0.0 and foe_dead < INF:
		var held := false
		for o in b.ships:
			if o.dead or o.side == side or o.heavy() or o.def.ecm or o.hangar != null or o.station or not Vision.sees(b, side, o):
				continue
			var pr := (o.pos - p).dot(ax)
			if pr >= d.line_frigate_k * l and pr <= (1.0 - d.line_frigate_k) * l:
				held = true
				break
		if not held:
			spec.advance_dead = foe_dead
	var o := Formation.places(b.defs, members, spec)
	return [mine, o]


## cos и sin малого угла рядом Тейлора — одни сложения и умножения, то есть одинаково
## до бита на любой системе (в отличие от sin/cos библиотеки C). Для |x| ≤ π/2 двенадцати
## членов хватает с запасом до точности double.
static func _cos_sin(x: float) -> Vector2:
	var x2 := x * x
	var c := 1.0
	var s := x
	var tc := 1.0
	var ts := x
	for k in range(1, 13):
		tc *= -x2 / float((2 * k - 1) * (2 * k))
		ts *= -x2 / float((2 * k) * (2 * k + 1))
		c += tc
		s += ts
	return Vector2(c, s)


static func _apply(b: State, side: int, plan: Array) -> void:
	var mine: Array[Ship] = plan[0]
	var o: Formation.Out = plan[1]
	var d := b.defs.doctrine
	for i in mine.size():
		var s := mine[i]
		if o.band[i] == Formation.NONE:
			continue
		s.has_slot = true
		s.slot = o.at[i]
		s.anchor = o.at[i]
		s.stance = &"guard"
		# порядок в полосе для следующего тика: пока состав тот же, места держатся (5.4)
		s.slot_order = float(o.rank[i])
		s.slot_band = o.band[i]
		s.leash_set = d.leash_frigate_ai if o.band[i] == Formation.FRIGATE and not s.def.ecm else 0.0
	# М10, строй против расталкивания (9.5 п. 20): пары новых мест ближе hull + hull — один раз
	# на раздачу; замер (battle → _sample_lines) считает их по шагам, пока оба живы и в строю
	var sd := b.sides[side]
	sd.slot_clash = PackedInt32Array()
	for i in mine.size():
		if o.band[i] == Formation.NONE:
			continue
		for j in range(i + 1, mine.size()):
			if o.band[j] == Formation.NONE:
				continue
			var mn := mine[i].hull + mine[j].hull
			if o.at[i].distance_squared_to(o.at[j]) < mn * mn:
				sd.slot_clash.append(mine[i].uid)
				sd.slot_clash.append(mine[j].uid)
