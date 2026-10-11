# «Перестрелка» без окна (ярус ui; план G2, п. 10): ввод настоящими событиями, как
# жмёт человек (архитектура, 8.3). Каждая проверка — с откатом.
# - ПКМ по врагу — фокус огня (откат «ПКМ — всегда идти», как в G1, краснеет);
# - ПКМ ТОЧНО в корпус своего невыделенного — охранять его; рядом (ближайший в 30
#   точках, но мимо корпуса) — «идти» (03, ловушка 14; откат «охрана по ближайшему»);
# - S/H/Y/T — тактики по МЕСТУ клавиши (русская раскладка), буква на чужом месте —
#   ничего;
# - A + щелчок: точка — атака с ходу, враг — фокус; Esc снимает только ожидание A,
#   выбор цел (откат «Esc снимает выбор»); ПКМ во время ожидания — обычный приказ;
# - под курсором чужой тяжёлый — его пояс (09, 6.7; откат «курсор не отслеживается»);
# - кругов дальности не больше трёх, больше трёх выделенных — только главный (P5;
#   откат «круги у всех»).
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Polygon := preload("res://tools/polygon.gd")
const BattleView := preload("res://view/battle_view.gd")
const BattleInput := preload("res://input/battle_input.gd")
const BattleFx := preload("res://view/battle_fx.gd")
const Picking := preload("res://input/picking.gd")
const MainScript := preload("res://main.gd")
const PolygonHud := preload("res://ui/polygon_hud.gd")
const Weapons := preload("res://sim/weapons.gd")

const BIG := 1.0e9

var _defs: Defs


func _get_defs() -> Defs:
	if _defs == null:
		_defs = Defs.load_default({}) as Defs
	return _defs


func _polygon() -> Polygon:
	await hooks.set_window_size(Vector2i(1366, 768))
	var p := Polygon.new()
	p.name = "Polygon"
	tree.root.add_child(p)
	ok(p.setup(_get_defs(), "проверка"), "«Полигон» собрался: %s" % "; ".join(p.problems))
	p.view.paused = true
	p.view.rig.edge_enabled = false
	await hooks.frames(2)
	return p


func _drop(p: Polygon) -> void:
	var b := p.battle
	p.queue_free()
	await hooks.frames(2)
	if b != null:
		b.dispose()


func _screen(p: Polygon, s: Ship) -> Vector2:
	return p.view.rig.camera.unproject_position(p.view.ship_point(s))


func _last(p: Polygon) -> Dictionary:
	var j := p.battle.cmds.journal
	return j[j.size() - 1] if not j.is_empty() else {}


func _first_of(p: Polygon, side: int, pred: Callable) -> Ship:
	for s in p.battle.ships:
		if not s.dead and s.side == side and pred.call(s):
			return s
	return null


func _select(p: Polygon, list: Array[Ship]) -> void:
	var sel: Array[int] = []
	for s in list:
		sel.append(s.uid)
	p.view.selection = sel


# ───────────────────────── ПКМ: фокус по врагу, охрана своего ─────────────────────────

func _rmb_on_enemy(rollback: bool) -> StringName:
	BattleInput.rollback_rmb_move_only = rollback
	var p := await _polygon()
	var own := p.battle.side_ships(Ship.ATTACKER)
	_select(p, own)
	var foe := _first_of(p, Ship.DEFENDER, func(s: Ship) -> bool: return s.def.id == &"cruiser")
	await hooks.click(_screen(p, foe), MOUSE_BUTTON_RIGHT)
	var c := _last(p)
	var op: StringName = c.get("op", &"")
	if op == &"focus" and not rollback:
		eq(whole(c["target"]), foe.uid, "фокус — на того, по кому щёлкнули")
	BattleInput.rollback_rmb_move_only = false
	await _drop(p)
	return op


func test_rmb_on_enemy_is_focus() -> void:
	eq(await _rmb_on_enemy(false), &"focus", "ПКМ по чужому крейсеру — фокус огня")
	eq(await _rmb_on_enemy(true), &"move", "откат «ПКМ — всегда идти»: вышло «идти» — проверка краснеет")


func _rmb_near_own(rollback: bool) -> Array:
	BattleInput.rollback_guard_by_near = rollback
	var p := await _polygon()
	var carrier := _first_of(p, Ship.ATTACKER, func(s: Ship) -> bool: return s.def.cls == &"carrier")
	var cor := _first_of(p, Ship.ATTACKER, func(s: Ship) -> bool: return s.def.id == &"corvette")
	var others: Array[Ship] = []
	for s in p.battle.side_ships(Ship.ATTACKER):
		if s != carrier and s != cor and s.def.light != null:
			others.append(s)
	_select(p, others)
	# точно в корпус носителя
	await hooks.click(_screen(p, carrier), MOUSE_BUTTON_RIGHT)
	var hull: StringName = _last(p).get("op", &"")
	var ward_ok := hull == &"guard" and whole(_last(p).get("target", 0)) == carrier.uid
	# рядом с корветом: в 30 точках от центра, но мимо капсулы корпуса
	var c := _screen(p, cor)
	var near := Vector2.INF
	for k in 16:
		var at := c + Vector2.RIGHT.rotated(TAU * k / 16.0) * 24.0
		if Picking.pick_hull(p.view, at) == null and Picking.pick(p.view, at) == cor:
			near = at
			break
	ok(near != Vector2.INF, "нашлась точка рядом с корветом, но мимо его корпуса")
	await hooks.click(near, MOUSE_BUTTON_RIGHT)
	var beside: StringName = _last(p).get("op", &"")
	BattleInput.rollback_guard_by_near = false
	await _drop(p)
	return [ward_ok, beside]


func test_rmb_guard_only_by_hull() -> void:
	var r := await _rmb_near_own(false)
	ok(flag(r[0]), "ПКМ точно в корпус своего невыделенного носителя — охранять его")
	eq(r[1], &"move", "ПКМ рядом со своим корветом (в 30 точках, мимо корпуса) — «идти», а не охрана")
	var o := await _rmb_near_own(true)
	eq(o[1], &"guard", "откат «охрана по ближайшему в 30 точках»: вышла охрана — проверка краснеет")


# ───────────────────────── тактики по месту клавиши ─────────────────────────

func test_stance_keys_by_place() -> void:
	var p := await _polygon()
	var own := p.battle.side_ships(Ship.ATTACKER)
	_select(p, own)
	var n0 := p.battle.cmds.journal.size()
	# русская раскладка: на месте Y — «н», на месте T — «е», на месте S — «ы»
	var cases: Array = [[KEY_Y, 1085, &"guard"], [KEY_T, 1077, &"hunt"], [KEY_S, 1099, &"hold"], [KEY_H, 1088, &"hold"]]
	for c: Array in cases:
		var phys: Key = c[0]
		var code: int = c[1]
		await hooks.key(phys, code as Key)
		var got: StringName = _last(p).get("stance", &"")
		eq(got, c[2], "клавиша на месте %s (буква «%s») — «%s»" % [OS.get_keycode_string(phys), String.chr(code), c[2]])
	eq(p.battle.cmds.journal.size(), n0 + 4, "четыре нажатия — четыре приказа")
	await hooks.key(KEY_Z, KEY_T)                  # буква T на чужом месте
	eq(p.battle.cmds.journal.size(), n0 + 4, "буква T на месте Z — ничего (06, ловушка 49)")
	await hooks.key(KEY_Y, KEY_Y, true)            # повтор — не нажатие
	eq(p.battle.cmds.journal.size(), n0 + 4, "повтор клавиши (echo) — не приказ")
	await _drop(p)


# ───────────────────────── A + щелчок ─────────────────────────

func _amove(rollback_esc: bool) -> Dictionary:
	BattleInput.rollback_esc_clears = rollback_esc
	var p := await _polygon()
	var own := p.battle.side_ships(Ship.ATTACKER)
	_select(p, own)
	var out := {}
	# A, щелчок по полю — атака с ходу в эту точку
	await hooks.key(KEY_A)
	out["armed"] = p.input.amove_armed
	var spot := Vector2(683, 300)
	await hooks.click(spot)
	var c := _last(p)
	out["op1"] = c.get("op", &"")
	out["sel_after_click"] = p.view.selection.size()
	# A, щелчок по врагу — фокус
	var foe := _first_of(p, Ship.DEFENDER, func(s: Ship) -> bool: return s.def.id == &"capital")
	await hooks.key(KEY_A)
	await hooks.click(_screen(p, foe))
	out["op2"] = _last(p).get("op", &"")
	# A, Esc — только отмена ожидания
	await hooks.key(KEY_A)
	await hooks.key(KEY_ESCAPE)
	out["armed_after_esc"] = p.input.amove_armed
	out["sel_after_esc"] = p.view.selection.size()
	# A, затем ПКМ — обычный приказ «идти»
	_select(p, own)
	await hooks.key(KEY_A)
	await hooks.click(Vector2(683, 500), MOUSE_BUTTON_RIGHT)
	out["op3"] = _last(p).get("op", &"")
	out["armed_after_rmb"] = p.input.amove_armed
	BattleInput.rollback_esc_clears = false
	await _drop(p)
	return out


func test_amove_by_a_and_click() -> void:
	var r := await _amove(false)
	ok(flag(r["armed"]), "A — ждём щелчка")
	eq(r["op1"], &"amove", "щелчок ЛКМ по полю после A — атака с ходу")
	ok(whole(r["sel_after_click"]) > 0, "щелчок после A не снял выбор")
	eq(r["op2"], &"focus", "A и щелчок по врагу — фокус")
	ok(not flag(r["armed_after_esc"]) and whole(r["sel_after_esc"]) > 0, "Esc после A — снято только ожидание, выбор цел")
	ok(str(r["op3"]) == "move" and not flag(r["armed_after_rmb"]), "ПКМ во время ожидания — обычный приказ «идти»")
	var o := await _amove(true)
	eq(whole(o["sel_after_esc"]), 0, "откат «Esc снимает выбор»: выбор пропал — проверка краснеет")


# ───────────────────────── пояс чужого по наведению, круги ─────────────────────────

func _hover_belt(rollback: bool) -> Dictionary:
	BattleInput.rollback_no_hover = rollback
	var p := await _polygon()
	var foe := _first_of(p, Ship.DEFENDER, func(s: Ship) -> bool: return s.def.id == &"cruiser")
	await hooks.move(_screen(p, foe))
	p.view.draw_state()
	var belt: Array = p.view.bfx.drawn_belts.get(foe.uid, [])
	var out := {"hover": p.view.hover_uid == foe.uid, "belt": belt}
	BattleInput.rollback_no_hover = false
	await _drop(p)
	return out


func test_hover_foe_heavy_belt() -> void:
	var r := await _hover_belt(false)
	ok(flag(r["hover"]), "курсор на чужом крейсере — он «под курсором»")
	var belt: Array = r["belt"]
	ok(belt.size() == 3 and absf(num(belt[0]) - 780.0) < 1e-6 and absf(num(belt[1]) - 312.0) < 1e-6 and not flag(belt[2]),
		"у чужого крейсера под курсором — его пояс: дальность 780, мёртвая зона 312, цветом противника (%s)" % str(belt))
	var o := await _hover_belt(true)
	ok(arr(o["belt"]).is_empty(), "откат «курсор не отслеживается»: пояса нет — проверка краснеет")


func _circles(rollback: bool) -> Array:
	BattleFx.rollback_all_circles = rollback
	var p := await _polygon()
	var own := p.battle.side_ships(Ship.ATTACKER)
	_select(p, own)
	p.view.hover_uid = 0
	p.view.draw_state()
	var list := p.view.bfx.drawn_belts.keys()
	var main_id := &""
	for u: int in list:
		var s := p.battle.ship_by_uid(u)
		main_id = s.def.id
	BattleFx.rollback_all_circles = false
	await _drop(p)
	return [list.size(), main_id]


func test_circles_at_most_three() -> void:
	var r := await _circles(false)
	eq(whole(r[0]), 1, "выделен весь флот (6 вооружённых) — один круг, у главного")
	eq(r[1], &"capital", "главный — флагман (наибольшая дальность)")
	var o := await _circles(true)
	ok(whole(o[0]) > 3, "откат «круги у всех»: кругов %d — проверка краснеет" % whole(o[0]))


## Полоска на фокус говорит, что сделают тяжёлые и лёгкие (09, 6.2), а безоружные
## называют себя (C100); строка «чем занят» у тяжёлого, до которого цель фокуса не
## достаёт, НАЗЫВАЕТ её и говорит «вне пояса» (09, 6.3 и 6.7), а «главным» не бьёт.
## Откат — строка молчит о цели фокуса: прежняя проверка «не начинается с «главным»»
## была зелёной и тогда, когда о приказе не говорилось ничего (замечание к G2).
func _focus_line(rollback: bool) -> Dictionary:
	PolygonHud.rollback_focus_unnamed = rollback
	var p := await _polygon()
	var own := p.battle.side_ships(Ship.ATTACKER)
	_select(p, own)
	var foe := _first_of(p, Ship.DEFENDER, func(s: Ship) -> bool: return s.def.id == &"cruiser")
	await hooks.click(_screen(p, foe), MOUSE_BUTTON_RIGHT)
	p.view.paused = false
	p.view.advance(Battle.STEP * 2.0)
	p.view.paused = true
	var said := PackedStringArray()
	for t in p.battle.toast_log:
		said.append(str(t["text"]))
	var cru := _first_of(p, Ship.ATTACKER, func(s: Ship) -> bool: return s.def.id == &"cruiser")
	var out := {"said": "\n".join(said), "line": PolygonHud.doing(cru, p.battle), "foe": Weapons.short_name(foe),
		"d": roundi(cru.pos.distance_to(foe.pos)), "reach": Weapons.main_reach(cru, cru.pos.distance_to(foe.pos))}
	PolygonHud.rollback_focus_unnamed = false
	await _drop(p)
	return out


func test_focus_toast_and_doing() -> void:
	var r := await _focus_line(false)
	var all := str(r["said"])
	ok(all.contains("тяжёлые бьют с места: главный калибр — от 312 до 900") and all.contains("лёгкие идут на цель"), "полоска на фокус: «%s»" % all.replace("\n", " / "))
	ok(all.contains("безоружны — держатся позади"), "носитель и РЭБ безоружны — сказано")
	var line := str(r["line"])
	note("фокус всего флота: крейсер — «%s»" % line)
	ok(whole(r["reach"]) != 0, "цель фокуса вне пояса крейсера (%d)" % whole(r["d"]))
	ok(not line.begins_with("главным по %s" % str(r["foe"])) and line.contains(str(r["foe"])) and line.contains("вне пояса"), "строка крейсера называет цель фокуса и «вне пояса»: «%s»" % line)
	var o := await _focus_line(true)
	ok(not str(o["line"]).contains(str(o["foe"])), "откат «строка молчит о фокусе»: «%s» — проверка краснеет" % str(o["line"]))


## Бой-проба без вида: тяжёлый Тройдена, вокруг — что задаст setup.call(battle, крейсер).
func _lab(setup: Callable) -> Battle:
	var b := Battle.create(_get_defs(), {"attacker": &"troyden", "defender": &"plektor", "size": &"small", "seed": 5, "reserve": false}) as Battle
	b.ships.clear()
	var c := b.spawn(Ship.ATTACKER, b.defs.ship(&"troyden", &"cruiser"), Vector2.ZERO)
	c.set_yaw(Ship.yaw_of(Vector2(0, -100)))
	c.hp = BIG
	c.max_hp = BIG
	c.stance = &"hold"
	setup.call(b, c)
	return b


func _foe(b: Battle, id: StringName, at: Vector2) -> Ship:
	var s := b.spawn(Ship.DEFENDER, b.defs.ship(&"plektor", id), at)
	s.switch_off(&"engines", BIG)
	s.stance = &"hold"
	s.hp = BIG
	s.max_hp = BIG
	s.main_cd = PackedFloat64Array()
	s.sec_cd = PackedFloat64Array()
	s.light_cd = PackedFloat64Array()
	s.mis_cd = PackedFloat64Array()
	s.pd_cd = PackedFloat64Array()
	return s


## Цель фокуса вне пояса, а своя цель в поясе есть (09, 6.3): главный калибр бьёт её, и
## строка это говорит — «главным по «…» · «Рэш» вне пояса (950)». Было: «главным по
## «Исса» IV (749)» — ни слова о цели фокуса, приказ выглядел проигнорированным
## (замечание к G2). Откат — строка молчит о фокусе.
func _focus_with_own(rollback: bool) -> Dictionary:
	PolygonHud.rollback_focus_unnamed = rollback
	var far: Array[Ship] = []
	var near: Array[Ship] = []
	var b := _lab(func(bb: Battle, c: Ship) -> void:
		far.append(_foe(bb, &"cruiser", Vector2(0, -950)))
		near.append(_foe(bb, &"frigate", Vector2(300, -543)))
		bb.queue({"op": &"focus", "ids": [c.uid], "target": far[0].uid}))
	for i in 45:
		b.step()
	var c := b.ships[0]
	var out := {"line": PolygonHud.doing(c, b), "far": Weapons.short_name(far[0]), "near": Weapons.short_name(near[0]),
		"forced": c.forced == far[0], "target": c.target == near[0]}
	b.dispose()
	PolygonHud.rollback_focus_unnamed = false
	return out


func test_doing_focus_out_of_belt_with_own_target() -> void:
	var r := _focus_with_own(false)
	ok(flag(r["forced"]) and flag(r["target"]), "фокус — на крейсер в 950, главный калибр взял фрегат в поясе")
	var line := str(r["line"])
	note("фокус вне пояса при своей цели в поясе: «%s»" % line)
	ok(line.begins_with("главным по %s" % str(r["near"])) and line.contains("%s вне пояса (950)" % str(r["far"])), "строка: «%s»" % line)
	var o := _focus_with_own(true)
	ok(not str(o["line"]).contains(str(o["far"])), "откат «строка молчит о фокусе»: «%s» — проверка краснеет" % str(o["line"]))


## «Бьёт» — только когда выстрел возможен (09, 6.7): крейсер «Держать», РЭБ Плэктора
## в 305 и корвет в 253 — оба в мёртвой зоне и оба дальше lockRange 170: батарея под
## помехами не бьёт, и строка этого не обещает. Корвет подошёл на 134 — батарея бьёт,
## строка называет его. Откат — прежнее «· бьёт батарея» без проверки.
func _bat_claim(rollback: bool, cor_at: Vector2) -> Dictionary:
	PolygonHud.rollback_bat_claim = rollback
	var b := _lab(func(bb: Battle, c: Ship) -> void:
		c.switch_off(&"engines", BIG)
		c.main_cd = PackedFloat64Array([0.0])
		_foe(bb, &"ecm", Vector2(-260, -160))
		_foe(bb, &"corvette", cor_at))
	var sec := 0
	for i in roundi(4.0 / Battle.STEP):
		b.step()
		for e in b.events:
			if e[0] == &"fire" and e[3] == &"sec":
				sec += 1
	var c := b.ships[0]
	var out := {"line": PolygonHud.doing(c, b), "sec": sec, "reason": c.idle_reason}
	b.dispose()
	PolygonHud.rollback_bat_claim = false
	return out


func test_doing_no_battery_claim() -> void:
	var r := _bat_claim(false, Vector2(250, -40))
	eq(r["reason"], &"dead_zone", "главный калибр молчит: мёртвая зона")
	eq(whole(r["sec"]), 0, "батарея под помехами по корвету в 253 (дальше lockRange) не выстрелила ни разу")
	var line := str(r["line"])
	note("вплотную под помехами: «%s»" % line)
	ok(line.begins_with("враг вплотную — главный калибр не бьёт") and not line.contains("бьёт батарея") and not line.contains("батареей"), "строка не обещает батарею: «%s»" % line)
	ok(line.contains("вдвое реже"), "под помехами — «вдвое реже», словами доктрины: «%s»" % line)
	var near := _bat_claim(false, Vector2(120, -60))
	ok(whole(near["sec"]) > 0 and str(near["line"]).contains("батареей по"), "корвет подошёл на 134 — батарея бьёт, строка это говорит: «%s»" % str(near["line"]))
	var o := _bat_claim(true, Vector2(250, -40))
	ok(str(o["line"]).contains("бьёт батарея"), "откат «бьёт батарея без проверки»: «%s» — проверка краснеет" % str(o["line"]))


## Купол, пояс под курсором и круг цели фокуса спрашивают ЕДИНЫЙ фильтр видимости
## (input/picking.gd → shown; 04, ловушка 33, C67): скрытый (проверочный крючок
## Picking.test_hidden — скрытности в срезе ещё нет) не рисуется. Откат — купол и
## пояса мимо фильтра («не погиб»).
func _shown_case(rollback: bool) -> Dictionary:
	BattleFx.rollback_no_shown = rollback
	var p := await _polygon()
	var ecm := _first_of(p, Ship.DEFENDER, func(s: Ship) -> bool: return s.def.ecm)
	var foe := _first_of(p, Ship.DEFENDER, func(s: Ship) -> bool: return s.def.id == &"cruiser")
	var foe2 := _first_of(p, Ship.DEFENDER, func(s: Ship) -> bool: return s.def.id == &"capital")
	var cru := _first_of(p, Ship.ATTACKER, func(s: Ship) -> bool: return s.def.id == &"cruiser")
	p.view.paused = false
	for i in 12:
		p.view.advance(Battle.STEP)               # купол набрал мощность
	p.view.paused = true
	cru.forced = foe2
	_select(p, [cru] as Array[Ship])
	p.view.hover_uid = foe.uid
	p.view.draw_state()
	var before := {"dome": p.view.bfx.drawn_domes.has(ecm.uid), "hover": p.view.bfx.drawn_belts.has(foe.uid), "focus": p.view.bfx.drawn_belts.has(foe2.uid)}
	Picking.test_hidden = {ecm.uid: true, foe.uid: true, foe2.uid: true}
	p.view.draw_state()
	var after := {"dome": p.view.bfx.drawn_domes.has(ecm.uid), "hover": p.view.bfx.drawn_belts.has(foe.uid), "focus": p.view.bfx.drawn_belts.has(foe2.uid)}
	Picking.test_hidden = {}
	BattleFx.rollback_no_shown = false
	await _drop(p)
	return {"before": before, "after": after}


func test_domes_and_belts_by_shown() -> void:
	var r := await _shown_case(false)
	var b0: Dictionary = r["before"]
	var a0: Dictionary = r["after"]
	ok(flag(b0["dome"]) and flag(b0["hover"]) and flag(b0["focus"]), "видимые: купол чужого РЭБ, пояс под курсором и пояс цели фокуса нарисованы (%s)" % str(b0))
	ok(not flag(a0["dome"]) and not flag(a0["hover"]) and not flag(a0["focus"]), "скрытые фильтром — не нарисованы (%s)" % str(a0))
	var o := await _shown_case(true)
	var ao: Dictionary = o["after"]
	ok(flag(ao["dome"]) and flag(ao["hover"]) and flag(ao["focus"]), "откат «купол и пояса мимо фильтра»: скрытые нарисованы (%s) — проверка краснеет" % str(ao))


# ───────────────────────── флажок отката --old-ecm ─────────────────────────

## `-- --old-ecm` (план G2, п. 5 и «Проверки»): флажок доходит до боя «Полигона», запись
## боя его помнит (повтор — тот же бой), заголовок называет. Контроль — без флажка
## бой обычный: проверка краснела бы, если бы флажок включался сам.
func test_old_ecm_flag() -> void:
	for on: bool in [true, false]:
		MainScript.apply_flags(PackedStringArray(["--old-ecm"] if on else ["--table"]))
		eq(Polygon.old_ecm, on, "флажок %s" % ("--old-ecm передан" if on else "не передан"))
		var p := await _polygon()
		eq(p.battle.old_ecm, on, "бой «Полигона» с флажком %s" % str(on))
		ok(p.hud.title.contains("--old-ecm") == on, "заголовок: «%s»" % p.hud.title)
		var why := PackedStringArray()
		var rec := p.battle.record()
		var again := Battle.from_record(_get_defs(), rec, "проверка", why) as Battle
		ok(again != null and again.old_ecm == on, "повтор записи — с тем же флажком (%s)" % "; ".join(why))
		if again != null:
			again.dispose()
		await _drop(p)
	Polygon.old_ecm = false
