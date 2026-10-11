# Авиация на «Полигоне» без окна (ярус ui; план G3, п. 5): ввод настоящими событиями,
# как жмёт человек (архитектура, 8.3). Каждая проверка — с откатом.
# - Z / X / C с выделенным носителем — пуск звена своей роли по МЕСТУ клавиши (русская
#   раскладка); без носителя — подсказка словами и никакого пуска (откат «пуск с любого»);
# - щелчок по машине выбирает её звено целиком, рамка берёт и свои звенья (04, 1.1;
#   откат «машины под курсором не ищутся»); V — выбранные звенья на посадку;
# - ПКМ по чужому звену: лёгкие — фокус на звено (бьют его машины, C14), тяжёлый — тот же
#   приказ, но модель отказывает словами и тяжёлый остаётся на месте (09, 4.6; откат
#   «тяжёлый идёт к звену, как в JS»);
# - подсказка ввода «A — щёлкните точку или врага» держится поверх потока полосок модели
#   (хвост G2; откат «подсказки после полосок»);
# - строка «чем занят»: тяжёлый на «Охоте» со своей целью вне пояса и лёгкий под помехами
#   дальше lockRange говорят правду (хвост G2; откат — прежние строки).
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Craft := preload("res://sim/craft.gd")
const Squad := preload("res://sim/squad.gd")
const Polygon := preload("res://tools/polygon.gd")
const BattleInput := preload("res://input/battle_input.gd")
const Picking := preload("res://input/picking.gd")
const PolygonHud := preload("res://ui/polygon_hud.gd")
const Weapons := preload("res://sim/weapons.gd")

const BIG := 1.0e9
## Рабочий вид (09, 11): машины на нём — точки, и выбирать их надо именно здесь.
const WORK_DIST := 2400.0

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


## Прогнать бой secs игровых секунд постоянным шагом и нарисовать кадр.
func _run(p: Polygon, secs: float) -> void:
	p.view.paused = false
	for i in roundi(secs / Battle.STEP):
		p.view.advance(Battle.STEP)
	p.view.paused = true
	p.view.draw_state()
	await hooks.frames(1)


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


func _squad(p: Polygon, side: int, role: StringName) -> Squad:
	for q in p.battle.squads:
		if not q.dead and q.side == side and q.role == role and not q.craft.is_empty():
			return q
	return null


## Камера рабочего вида над центром звена (мгновенно).
func _look_at_squad(p: Polygon, q: Squad) -> void:
	p.view.rig.set_view(Vector3(q.pos.x, 0.0, q.pos.y), p.view.rig.yaw, WORK_DIST, true)
	p.view.draw_state()
	await hooks.frames(2)
	p.view.draw_state()


## Точка экрана на машине звена, где под курсором — именно это звено (не корпус корабля
## и не соседнее звено). INF — не нашлось.
func _craft_spot(p: Polygon, q: Squad) -> Vector2:
	var cam := p.view.rig.camera
	var vr := tree.root.get_visible_rect()
	var panel := p.hud.panel.get_global_rect()
	for c in q.craft:
		if c.dead:
			continue
		var w := p.view.craft_point(c)
		if cam.is_position_behind(w):
			continue
		var at := cam.unproject_position(w)
		if not vr.grow(-40.0).has_point(at) or panel.has_point(at):
			continue
		if Picking.pick_any(p.view, at) == q:
			return at
	return Vector2.INF


# ───────────────────────── Z / X / C — пуск с носителя ─────────────────────────

func _launch_keys(rollback: bool) -> Dictionary:
	BattleInput.rollback_launch_any = rollback
	var p := await _polygon()
	var carrier := _first_of(p, Ship.ATTACKER, func(s: Ship) -> bool: return s.hangar != null and not s.station)
	var roles: Array[StringName] = []
	var only: Array[Ship] = [carrier]
	_select(p, only)
	await hooks.frames(2)
	var sel_line := p.hud.sel_label.text
	# русская раскладка: на месте Z — «я», X — «ч», C — «с»
	var cases: Array = [[KEY_Z, 1103], [KEY_X, 1095], [KEY_C, 1089]]
	for k: Array in cases:
		var phys: Key = k[0]
		var code: int = k[1]
		var n0 := p.battle.cmds.journal.size()
		await hooks.key(phys, code as Key)
		var c := _last(p)
		var role: StringName = c.get("role", &"")
		roles.append(role if p.battle.cmds.journal.size() > n0 and c.get("op", &"") == &"launch" else &"")
	await _run(p, Battle.STEP * 2.0)
	var up := 0
	for q in p.battle.squads:
		if q.side == Ship.ATTACKER and not q.dead:
			up += 1
	# без носителя: выделен корвет — пуска нет, подсказка словами
	var cor := _first_of(p, Ship.ATTACKER, func(s: Ship) -> bool: return s.def.id == &"corvette")
	var only_cor: Array[Ship] = [cor]
	_select(p, only_cor)
	await hooks.frames(1)
	var n1 := p.battle.cmds.journal.size()
	await hooks.key(KEY_Z, 1103 as Key)
	await hooks.frames(2)
	var out := {"roles": roles, "up": up, "sel": sel_line, "no_carrier_cmd": p.battle.cmds.journal.size() > n1,
		"hint": p.hud.toasts.text}
	BattleInput.rollback_launch_any = false
	await _drop(p)
	return out


func test_zxc_launch_from_carrier() -> void:
	var r := await _launch_keys(false)
	var roles: Array = r["roles"]
	eq(str(roles), str([&"interceptor", &"fighter", &"bomber"]), "Z / X / C по месту клавиши — перехватчики, истребители, бомбардировщики")
	eq(whole(r["up"]), 3, "три звена в воздухе")
	ok(str(r["sel"]).contains("Z — перехватчики") and str(r["sel"]).contains("свободно мест в ангаре"), "выбран носитель — панель подсказывает Z / X / C и свободные места: «%s»" % str(r["sel"]))
	ok(not flag(r["no_carrier_cmd"]), "без носителя в выборе Z пуска не шлёт")
	ok(str(r["hint"]).contains("Звенья поднимает носитель: выбери его"), "и говорит, что делать: «%s»" % str(r["hint"]))
	var o := await _launch_keys(true)
	ok(flag(o["no_carrier_cmd"]), "откат «пуск с любого выбранного»: Z с корветом шлёт пуск — проверка краснеет")


# ───────────────────────── щелчок по машине — звено, рамка, V ─────────────────────────

func _pick_squad(rollback: bool) -> Dictionary:
	BattleInput.rollback_no_squad_pick = rollback
	var p := await _polygon()
	var carrier := _first_of(p, Ship.ATTACKER, func(s: Ship) -> bool: return s.hangar != null and not s.station)
	p.battle.queue({"op": &"launch", "ids": [carrier.uid], "role": &"fighter"})
	await _run(p, 6.0)
	var q := _squad(p, Ship.ATTACKER, &"fighter")
	var out := {"found": false}
	if q == null:
		BattleInput.rollback_no_squad_pick = false
		await _drop(p)
		return out
	await _look_at_squad(p, q)
	var at := _craft_spot(p, q)
	out["found"] = at != Vector2.INF
	if at == Vector2.INF:
		BattleInput.rollback_no_squad_pick = false
		await _drop(p)
		return out
	p.view.selection = []
	await hooks.click(at)
	var sel: Array[int] = p.view.selection
	out["clicked"] = sel.size() == 1 and sel[0] == q.uid
	await hooks.frames(2)
	out["line"] = p.hud.sel_label.text
	out["name"] = PolygonHud.squad_name(q, p.battle)
	var n0 := p.battle.cmds.journal.size()
	await hooks.key(KEY_V, 1084 as Key)              # «м» на месте V
	var c := _last(p)
	out["recall"] = p.battle.cmds.journal.size() > n0 and c.get("op", &"") == &"recall" and q.uid in arr(c.get("ids", []))
	# рамка вокруг звена (своих она и берёт)
	p.view.selection = []
	await hooks.frames(1)
	var cen := p.view.rig.camera.unproject_position(p.view.squad_point(q))
	await _drag(cen - Vector2(40, 40), Vector2(16, 16), 5, MOUSE_BUTTON_LEFT)
	var sel2: Array[int] = p.view.selection
	out["box"] = q.uid in sel2
	BattleInput.rollback_no_squad_pick = false
	await _drop(p)
	return out


func test_click_on_craft_selects_squad() -> void:
	var r := await _pick_squad(false)
	if not ok(flag(r["found"]), "на рабочем виде нашлась машина своего звена, не над корпусом корабля"):
		return
	ok(flag(r["clicked"]), "щелчок по машине выбирает её звено целиком")
	ok(str(r["line"]).contains(str(r["name"])) and str(r["line"]).contains("V — на посадку"), "панель называет звено и подсказывает V: «%s»" % str(r["line"]))
	ok(flag(r["recall"]), "V — выбранное звено на посадку")
	ok(flag(r["box"]), "рамка вокруг звена берёт его")
	var o := await _pick_squad(true)
	ok(flag(o["found"]) and not flag(o["clicked"]) and not flag(o["recall"]) and not flag(o["box"]), "откат «машины под курсором не ищутся»: ни щелчок, ни V, ни рамка звена не берут — проверка краснеет")


# ───────────────────────── ПКМ по чужому звену ─────────────────────────

func _rmb_on_foe_squad(heavy: bool, rollback: bool) -> Dictionary:
	Battle.rollback_heavy_to_squad = rollback
	var p := await _polygon()
	var out := {"found": false}
	# чужое звено поднимается на 8-й секунде (FOE_AIR); ждём, пока оно отойдёт от носителя
	var fq: Squad = null
	for i in 12:
		await _run(p, 1.0)
		fq = _squad(p, Ship.DEFENDER, &"bomber")
		if fq != null and p.battle.time >= 12.0:
			break
	if fq == null:
		Battle.rollback_heavy_to_squad = false
		await _drop(p)
		return out
	var own: Array[Ship] = []
	for s in p.battle.side_ships(Ship.ATTACKER):
		var light := s.def.light != null and s.def.main == null
		if (heavy and s.def.main != null) or (not heavy and light):
			own.append(s)
	if heavy and not own.is_empty():
		own.resize(1)
	await _look_at_squad(p, fq)
	_select(p, own)
	await hooks.frames(1)
	var at := _craft_spot(p, fq)
	out["found"] = at != Vector2.INF and not own.is_empty()
	if not flag(out["found"]):
		Battle.rollback_heavy_to_squad = false
		await _drop(p)
		return out
	var n0 := p.battle.cmds.journal.size()
	await hooks.click(at, MOUSE_BUTTON_RIGHT)
	var c := _last(p)
	out["op"] = c.get("op", &"") if p.battle.cmds.journal.size() > n0 else &""
	out["target"] = whole(c.get("target", 0))
	out["squad"] = fq.uid
	var pos0 := own[0].pos
	await _run(p, 1.0)
	var said := PackedStringArray()
	for e in p.battle.toast_log:
		said.append(str(e["text"]))
	out["said"] = "\n".join(said)
	out["forced_squad"] = own[0].forced == fq
	out["moved"] = own[0].has_move
	out["shift"] = own[0].pos.distance_to(pos0)
	out["heavy_name"] = own[0].name
	Battle.rollback_heavy_to_squad = false
	await _drop(p)
	return out


func test_rmb_on_foe_squad_lights_focus() -> void:
	var r := await _rmb_on_foe_squad(false, false)
	if not ok(flag(r["found"]), "чужое звено бомбардировщиков на экране и под курсором"):
		return
	eq(r["op"], &"focus", "ПКМ лёгкими по чужому звену — фокус")
	eq(whole(r["target"]), whole(r["squad"]), "цель фокуса — само звено (бить его машины, C14)")
	ok(flag(r["forced_squad"]), "лёгкий взял звено целью")
	ok(str(r["said"]).contains("лёгкие бьют его машины"), "полоска: «%s»" % str(r["said"]).get_slice("\n", 0))


func test_rmb_on_foe_squad_heavy_refuses() -> void:
	var r := await _rmb_on_foe_squad(true, false)
	if not ok(flag(r["found"]), "чужое звено на экране, выделен тяжёлый «%s»" % str(r.get("heavy_name", ""))):
		return
	eq(r["op"], &"focus", "ПКМ тяжёлым по звену — тот же приказ «бить»")
	ok(str(r["said"]).contains("Тяжёлые держат дистанцию — авиацию бьют ПВО и звенья"), "модель отказывает словами")
	ok(not flag(r["moved"]) and not flag(r["forced_squad"]), "тяжёлый не идёт к звену и не держит его целью (09, 4.6)")
	var o := await _rmb_on_foe_squad(true, true)
	ok(flag(o["moved"]) or num(o["shift"]) > 5.0, "откат «тяжёлый идёт к звену, как в JS»: пошёл (приказ «идти» %s, сдвиг %.0f) — проверка краснеет" % [str(o["moved"]), num(o["shift"])])


# ───────────────────────── подсказка A поверх полосок ─────────────────────────

func _a_hint(rollback: bool) -> Dictionary:
	PolygonHud.rollback_hints_last = rollback
	var p := await _polygon()
	var own: Array[Ship] = []
	for s in p.battle.side_ships(Ship.ATTACKER):
		if not s.station:
			own.append(s)
	_select(p, own)
	await hooks.frames(1)
	await hooks.key(KEY_A, 1092 as Key)              # «ф» на месте A
	await hooks.frames(2)
	var alone := p.hud.toasts.text
	# поток полосок модели: приказы, пуски, потери — три за одну секунду
	for t: String in ["Звенья атакуют «Рэш»", "Потеряно наше звено «Зонг»", "Сбито вражеское звено «Тэн»", "Звено село, ангар свободен"]:
		p.battle.toast(t)
	await hooks.frames(3)
	var flood := p.hud.toasts.text
	await hooks.key(KEY_ESCAPE)
	await hooks.frames(2)
	var after := p.hud.toasts.text
	PolygonHud.rollback_hints_last = false
	await _drop(p)
	return {"alone": alone, "flood": flood, "after": after}


func test_amove_hint_survives_toast_flood() -> void:
	const HINT := "A — щёлкните точку или врага"
	var r := await _a_hint(false)
	ok(str(r["alone"]).begins_with(HINT), "A ждёт щелчка — подсказка первой строкой: «%s»" % str(r["alone"]))
	ok(str(r["flood"]).begins_with(HINT), "четыре полоски модели подсказку не вытеснили: «%s»" % str(r["flood"]).replace("\n", " | "))
	ok(str(r["flood"]).contains("Звено село"), "и полоски модели тоже видны")
	ok(not str(r["after"]).contains(HINT), "Esc — подсказка ушла вместе с ожиданием")
	var o := await _a_hint(true)
	ok(not str(o["flood"]).contains(HINT), "откат «подсказки после полосок»: подсказку вытеснили — проверка краснеет")


# ───────────────────────── строка «чем занят» (хвост G2) ─────────────────────────

func _lab(setup: Callable) -> Battle:
	var b := Battle.create(_get_defs(), {"attacker": &"troyden", "defender": &"plektor", "size": &"small", "seed": 5, "reserve": false}) as Battle
	b.ships.clear()
	setup.call(b)
	return b


func _still(s: Ship) -> Ship:
	s.switch_off(&"engines", BIG)
	s.hp = BIG
	s.max_hp = BIG
	return s


## Тяжёлый на «Охоте» берёт свою цель до 1,8 R, а в пояс до G4 не ходит: стоит. Было —
## «охота · целей не видно» при цели на виду.
func _hunt_line(rollback: bool) -> Dictionary:
	PolygonHud.rollback_doing_g2 = rollback
	var own: Array[Ship] = []
	var foe: Array[Ship] = []
	var b := _lab(func(bb: Battle) -> void:
		var c := _still(bb.spawn(Ship.ATTACKER, bb.defs.ship(&"troyden", &"cruiser"), Vector2.ZERO))
		c.stance = &"hunt"
		own.append(c)
		var f := _still(bb.spawn(Ship.DEFENDER, bb.defs.ship(&"plektor", &"frigate"), Vector2(0, -1000)))
		f.stance = &"hold"
		foe.append(f))
	for i in roundi(3.0 / Battle.STEP):
		b.step()
	var out := {"line": PolygonHud.doing(own[0], b), "target": own[0].target == foe[0], "foe": Weapons.short_name(foe[0])}
	b.dispose()
	PolygonHud.rollback_doing_g2 = false
	return out


func test_doing_hunt_target_out_of_belt() -> void:
	var r := _hunt_line(false)
	ok(flag(r["target"]), "крейсер на «Охоте» взял фрегата в 1000 (дальность 780, охота до 1,8 R)")
	var line := str(r["line"])
	note("охота, цель вне пояса: «%s»" % line)
	ok(line.begins_with("цель %s вне пояса (1000) — стоит" % str(r["foe"])), "строка называет цель и что крейсер стоит: «%s»" % line)
	var o := _hunt_line(true)
	ok(not str(o["line"]).contains(str(o["foe"])), "откат — прежняя строка «%s» молчит о цели — проверка краснеет" % str(o["line"]))


## Лёгкий под чужими помехами бьёт только ближе lockRange (170): цель в 230 — в его
## дальности (270), но выстрела нет, и строка не обещает «бьёт».
func _jam_line(rollback: bool) -> Dictionary:
	PolygonHud.rollback_doing_g2 = rollback
	var own: Array[Ship] = []
	var foe: Array[Ship] = []
	var b := _lab(func(bb: Battle) -> void:
		var f := _still(bb.spawn(Ship.ATTACKER, bb.defs.ship(&"troyden", &"frigate"), Vector2.ZERO))
		f.stance = &"hold"
		own.append(f)
		var e := _still(bb.spawn(Ship.DEFENDER, bb.defs.ship(&"plektor", &"ecm"), Vector2(-260, -260)))
		e.stance = &"hold"
		var cor := _still(bb.spawn(Ship.DEFENDER, bb.defs.ship(&"plektor", &"corvette"), Vector2(0, -230)))
		cor.stance = &"hold"
		cor.light_cd = PackedFloat64Array()
		foe.append(cor))
	var shots := 0
	for i in roundi(3.0 / Battle.STEP):
		b.step()
		if b.time < 0.3:
			continue                                 # поле РЭБ набирает мощность (раздел 2 CLAUDE.md)
		for e in b.events:
			if e[0] == &"fire" and e[3] == &"light" and whole(e[1]) == own[0].uid:
				shots += 1
	var s := own[0]
	var out := {"line": PolygonHud.doing(s, b), "shots": shots, "target": s.target == foe[0],
		"reach": Weapons.light_reach(b, s), "foe": Weapons.short_name(foe[0])}
	b.dispose()
	PolygonHud.rollback_doing_g2 = false
	return out


func test_doing_light_under_jam() -> void:
	var r := _jam_line(false)
	ok(flag(r["target"]), "фрегат держит целью корвет в 230")
	near(num(r["reach"]), 170.0, 0.5, "под помехами лёгкое достаёт только до lockRange")
	eq(whole(r["shots"]), 0, "выстрелов по корвету в 230 под помехами — ни одного")
	var line := str(r["line"])
	note("лёгкий под помехами: «%s»" % line)
	ok(line.begins_with("под помехами — бьёт только вблизи") and line.contains("230"), "строка: «%s»" % line)
	var o := _jam_line(true)
	ok(str(o["line"]).begins_with("бьёт"), "откат — прежнее «%s» обещает выстрел — проверка краснеет" % str(o["line"]))


# ───────────────────────── протяжка (как в test_ui_polygon) ─────────────────────────

func _press(pos: Vector2, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(ev)
	await hooks.frames(1)


func _motion(pos: Vector2, rel: Vector2, button: MouseButton) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	mv.relative = rel
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(mv)
	await hooks.frames(1)


func _release(pos: Vector2, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = false
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	await hooks.frames(2)


func _drag(from: Vector2, d: Vector2, steps: int, button: MouseButton) -> void:
	await hooks.move(from)
	await _press(from, button)
	var p := from
	for i in steps:
		p += d
		await _motion(p, d, button)
	await _release(p, button)
