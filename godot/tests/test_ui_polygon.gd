# «Полигон» без окна (ярус ui; план G1, пп. 5–6 и «Проверки»): вид шагает модель
# по накопителю, интерполяция ровная, мышь и клавиши — настоящими событиями,
# как жмёт человек (архитектура, 8.3). Каждая проверка — с откатом.
# - ПКМ — приказ на ОТПУСКАНИИ; протяжка 8 × 15 точек — приказов 0, поворот больше
#   0,2; на месте — приказ; протяжка 5 × 5 (7 по прямой) — тоже приказ: порог по
#   КАЖДОЙ оси (06, ловушки 1–2; откат «по расстоянию» краснеет);
# - жест, начатый на поле и кончившийся над панелью, не «залипает» (06, ловушка 50;
#   откат — отпускание в _unhandled_input: рамка висит и после отпускания);
# - клавиши по МЕСТУ: H при русской раскладке («р») — «Держать», а буква H на чужом
#   месте — ничего (06, ловушка 49); повтор (echo) — не нажатие;
# - выбор щелчком и рамкой, Shift, Esc; кто под курсором — капсула корпуса, потом
#   ближайший в 30 точках; «малый за факелом» (C29; 08, ловушка 10; откат — рамка
#   всего нарисованного с факелами краснеет);
# - скорость — числом шагов за кадр, пауза — ноль, не больше 8 за кадр; таймер
#   подкрепления — по игровым часам: на 4× вчетверо меньше кадров, та же игровая
#   секунда (01, 4.2 п. 8);
# - интерполяция: сдвиг между кадрами 60 Гц ровный (откат — без смешивания:
#   сдвиг через кадр, 7, 0, 7, 0); новый корабль не смешивается с прошлым (телепорт);
# - главная сцена: «Полигон» по умолчанию, F6 — «Стол» и обратно, F5 с «Полигона» —
#   «Стол» и минута замера, F8 — заново, F9 — запись боя файлом.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Polygon := preload("res://tools/polygon.gd")
const BattleView := preload("res://view/battle_view.gd")
const BattleInput := preload("res://input/battle_input.gd")
const Picking := preload("res://input/picking.gd")
const CameraRig := preload("res://view/camera_rig.gd")
const MainScene := preload("res://main.tscn")
const MainScript := preload("res://main.gd")

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


func _drop(p: Node) -> void:
	var b: Battle = p.get("battle")
	p.queue_free()
	await hooks.frames(2)
	if b != null:
		b.dispose()


func _journal(p: Polygon) -> int:
	return p.battle.cmds.journal.size()


func _own(p: Polygon) -> Array[Ship]:
	return p.battle.side_ships(Ship.ATTACKER)


func _screen(p: Polygon, s: Ship) -> Vector2:
	return p.view.rig.camera.unproject_position(p.view.ship_point(s))


func _press(pos: Vector2, button: MouseButton, shift: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.shift_pressed = shift
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


## Протяжка кнопкой: steps движений по d каждое (по одному на кадр — Input сливает
## движения одного кадра). → где отпустили.
func _drag(from: Vector2, d: Vector2, steps: int, button: MouseButton, release_at: Variant = null) -> Vector2:
	await hooks.move(from)
	await _press(from, button)
	var p := from
	for i in steps:
		p += d
		await _motion(p, d, button)
	var at: Vector2 = release_at if release_at != null else p
	if release_at != null:
		await _motion(at, at - p, button)
	await _release(at, button)
	return at


## Выбрать своих рамкой по всему экрану (своих рамка и берёт).
func _select_own(p: Polygon) -> void:
	var sel: Array[int] = []
	for s in _own(p):
		if not s.station:
			sel.append(s.uid)
	p.view.selection = sel


# ───────────────────────── ПКМ: приказ на отпускании, протяжка — поворот ─────────────────────────

func test_rmb_order_on_release_and_drag_rotates() -> void:
	var p := await _polygon()
	_select_own(p)
	var c := Vector2(683, 300)
	# ПКМ на месте: на нажатии приказа ещё нет, на отпускании — есть
	var n0 := _journal(p)
	await hooks.move(c)
	await _press(c, MOUSE_BUTTON_RIGHT)
	eq(_journal(p), n0, "ПКМ нажата — приказа ещё нет (приказ — на отпускании)")
	await _release(c, MOUSE_BUTTON_RIGHT)
	eq(_journal(p), n0 + 1, "ПКМ отпущена на месте — один приказ")
	var last: Dictionary = p.battle.cmds.journal[-1]
	eq(last["op"], &"move", "приказ — «идти»")
	var g: Vector3 = p.view.rig.ground_at(c, false)
	ok(absf(num(last["x"]) - g.x) < 0.01 and absf(num(last["z"]) - g.z) < 0.01, "точка приказа — плоскость y = 0 под курсором (%.1f, %.1f)" % [g.x, g.z])
	var ids: PackedInt32Array = last["ids"]
	eq(ids.size(), _own(p).size(), "приказ всем своим выбранным")
	# протяжка 8 × 15 точек — поворот камеры, приказов нет
	var y0 := p.view.rig.yaw
	var n1 := _journal(p)
	await _drag(c, Vector2(15, 0), 8, MOUSE_BUTTON_RIGHT)
	eq(_journal(p), n1, "протяжка ПКМ на 8 × 15 точек — приказов 0")
	ok(absf(p.view.rig.yaw - y0) > 0.2, "протяжка ПКМ повернула камеру: %.3f рад" % absf(p.view.rig.yaw - y0))
	# протяжка на 5 точек — ещё щелчок, то есть приказ
	await _drag(c, Vector2(5, 0), 1, MOUSE_BUTTON_RIGHT)
	eq(_journal(p), n1 + 1, "протяжка на 5 точек — приказ")
	# 5 вбок и 5 вниз (7 по прямой): порог — по каждой оси, это щелчок (06, ловушка 2)
	var n2 := _journal(p)
	await _drag(c, Vector2(5, 5), 1, MOUSE_BUTTON_RIGHT)
	eq(_journal(p), n2 + 1, "протяжка 5 × 5 — приказ: порог «потянул» по каждой оси")
	# откат: порог по расстоянию — 5 × 5 уже «потянул», приказа нет
	BattleInput.rollback_slop_by_distance = true
	await _drag(c, Vector2(5, 5), 1, MOUSE_BUTTON_RIGHT)
	BattleInput.rollback_slop_by_distance = false
	eq(_journal(p), n2 + 1, "откат «порог по расстоянию»: 5 × 5 приказа не дал — проверка краснеет")
	# без своих выделенных ПКМ — ничего (06, 2.6)
	p.view.selection = [] as Array[int]
	var n3 := _journal(p)
	await hooks.click(c, MOUSE_BUTTON_RIGHT)
	eq(_journal(p), n3, "без выбора ПКМ приказа не даёт")
	await _drop(p)


## Жест, начатый на поле и продолженный над панелью (STOP), дослушан и кончен
## (архитектура, 6.5: над панелью движение до _unhandled_input не доходит — проверено
## A и C, 0 из 7 событий; отпускание доходит).
class DeafInput extends "res://input/battle_input.gd":
	# откат: движение слушают в _unhandled_input — над панелью его нет
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			return
		super._input(event)

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			super._input(event)
			return
		super._unhandled_input(event)


func _gesture_over_panel(p: Polygon) -> Dictionary:
	var panel := p.hud.panel
	var pr := panel.get_global_rect()
	var under := await hooks.hovered_at(pr.get_center())
	var n0 := _journal(p)
	# рамка ЛКМ: нажали на поле над панелью, повели вниз — на панель и по ней
	var from := Vector2(pr.position.x + 40.0, pr.position.y - 120.0)
	await hooks.move(from)
	await _press(from, MOUSE_BUTTON_LEFT)
	await _motion(from + Vector2(20, 60), Vector2(20, 60), MOUSE_BUTTON_LEFT)
	var over := from + Vector2(160, 150)
	await _motion(over, Vector2(140, 90), MOUSE_BUTTON_LEFT)
	var box_on_panel := p.hud.box.get_global_rect()
	await _release(over, MOUSE_BUTTON_LEFT)
	var box_after := p.hud.box.visible
	await _motion(over + Vector2(30, -200), Vector2(30, -200), MOUSE_BUTTON_LEFT)
	var box_later := p.hud.box.visible
	# ПКМ: нажали на поле в 3 точках над панелью, дальше — только над панелью
	# (рамка выше заменила выбор найденным — выбираем своих снова: без них приказа нет)
	_select_own(p)
	await hooks.frames(2)             # панель выросла под новый выбор — край заново
	pr = panel.get_global_rect()
	var y0 := p.view.rig.yaw
	var at := Vector2(pr.get_center().x, pr.position.y - 3.0)
	await hooks.move(at)
	await _press(at, MOUSE_BUTTON_RIGHT)
	var q := at + Vector2(0, 14)
	await _motion(q, Vector2(0, 14), MOUSE_BUTTON_RIGHT)
	for i in 8:
		q += Vector2(15, 0)
		await _motion(q, Vector2(15, 0), MOUSE_BUTTON_RIGHT)
	await _release(q, MOUSE_BUTTON_RIGHT)
	var yaw_after := p.view.rig.yaw
	await _motion(q + Vector2(200, 0), Vector2(200, 0), MOUSE_BUTTON_RIGHT)
	return {"panel": under == panel, "box_on_panel": box_on_panel, "over": over, "box_after": box_after,
		"box_later": box_later, "orders": _journal(p) - n0, "turn": absf(yaw_after - y0),
		"spin": absf(p.view.rig.yaw - yaw_after)}


func test_gesture_over_panel_is_followed() -> void:
	var p := await _polygon()
	_select_own(p)
	var r := await _gesture_over_panel(p)
	ok(flag(r["panel"]), "под серединой нижней панели — она сама (панель STOP)")
	var br: Rect2 = r["box_on_panel"]
	var over: Vector2 = r["over"]
	ok(br.has_area() and br.end.distance_to(over) < 2.0, "рамка тянется за мышью и над панелью: угол %s, мышь %s" % [br.end, over])
	ok(not flag(r["box_after"]), "рамка, отпущенная над панелью, погасла")
	ok(not flag(r["box_later"]), "после отпускания над панелью рамка не тянется за мышью")
	eq(whole(r["orders"]), 0, "протяжка ПКМ над панелью — поворот, приказа нет")
	ok(num(r["turn"]) > 0.2, "протяжка ПКМ над панелью вертела камеру (%.3f рад)" % num(r["turn"]))
	ok(num(r["spin"]) < 1e-6, "после отпускания над панелью камера не вертится")
	# и следующий щелчок по своему — обычный выбор
	var s := _own(p)[0]
	await hooks.click(_screen(p, s))
	eq(p.view.selection, [s.uid] as Array[int], "следующий щелчок по своему — обычный выбор")
	await _drop(p)
	# откат: движение слушают в _unhandled_input — над панелью рамка замирает, а протяжка
	# ПКМ по панели считается щелчком и даёт приказ
	var p2 := await _polygon()
	_select_own(p2)
	p2.input.queue_free()
	var deaf := DeafInput.new()
	deaf.view = p2.view
	deaf.say = p2.hud.say
	deaf.box_changed = p2.hud.show_box
	p2.add_child(deaf)
	p2.input = deaf
	await hooks.frames(1)
	var r2 := await _gesture_over_panel(p2)
	var br2: Rect2 = r2["box_on_panel"]
	var over2: Vector2 = r2["over"]
	ok(br2.end.distance_to(over2) > 20.0, "откат «движение в _unhandled_input»: рамка над панелью замерла — проверка краснеет")
	ok(whole(r2["orders"]) > 0, "откат «движение в _unhandled_input»: протяжка по панели дала приказ — проверка краснеет")
	await _drop(p2)


# ───────────────────────── клавиши по месту ─────────────────────────

func _key_ev(physical: Key, keycode: Key = KEY_NONE, echo: bool = false) -> void:
	await hooks.key(physical, keycode, echo)


func test_keys_by_physical_code() -> void:
	var p := await _polygon()
	_select_own(p)
	var n0 := _journal(p)
	# H по месту при русской раскладке: буква «р» (1088)
	await _key_ev(KEY_H, 1088 as Key)
	eq(_journal(p), n0 + 1, "H по месту («р» в русской раскладке) — приказ")
	var last: Dictionary = p.battle.cmds.journal[-1]
	ok(flag(last["op"] == &"stance") and flag(last.get("stance") == &"hold"), "это «Держать»: %s" % [last])
	# буква H на чужом месте (физически J) — не «Держать»
	await _key_ev(KEY_J, KEY_H)
	eq(_journal(p), n0 + 1, "буква H на месте J — ничего: клавиши по месту, а не по букве")
	# повтор (echo) — не нажатие
	await _key_ev(KEY_S, KEY_S, true)
	eq(_journal(p), n0 + 1, "повтор S (echo) — не нажатие")
	await _key_ev(KEY_S)
	eq(_journal(p), n0 + 2, "S — «Держать» тоже (H = S)")
	await _key_ev(KEY_D)
	eq(p.battle.cmds.journal[-1]["op"], &"drift", "D — дрифт")
	await _key_ev(KEY_G)
	eq(p.battle.cmds.journal[-1]["op"], &"hyper", "G — гипер")
	await _key_ev(KEY_B)
	var lb: Dictionary = p.battle.cmds.journal[-1]
	ok(flag(lb["op"] == &"reinforce") and whole(lb["side"]) == Ship.ATTACKER, "B — подкрепление своей стороне")
	# без выбора: H — полоска словами, G — молча
	p.view.selection = [] as Array[int]
	var n1 := _journal(p)
	await _key_ev(KEY_H)
	await _key_ev(KEY_G)
	eq(_journal(p), n1, "без выбора H и G приказов не дают")
	ok(p.hud.toasts.text.contains("Сначала выбери свои корабли"), "без выбора H — «Сначала выбери свои корабли»: «%s»" % p.hud.toasts.text)
	# Пробел — пауза и обратно с прежней скоростью; 1/2/4 — скорость
	p.view.paused = false
	await _key_ev(KEY_4)
	eq(p.view.speed, 4, "4 — скорость 4×")
	await _key_ev(KEY_SPACE)
	ok(p.view.paused, "Пробел — пауза")
	await _key_ev(KEY_SPACE)
	ok(not p.view.paused and p.view.speed == 4, "Пробел ещё раз — с прежней скоростью 4×, а не 1×")
	await _key_ev(KEY_2)
	eq(p.view.speed, 2, "2 — скорость 2×")
	await _key_ev(KEY_1)
	eq(p.view.speed, 1, "1 — скорость 1×")
	await _drop(p)


# ───────────────────────── выбор: щелчок, рамка, кто под курсором ─────────────────────────

func test_click_and_box_selection() -> void:
	var p := await _polygon()
	var own := _own(p)
	var a := own[0]
	var b := own[own.size() - 1]
	await hooks.click(_screen(p, a))
	eq(p.view.selection, [a.uid] as Array[int], "щелчок по своему — выбран он один")
	await hooks.move(_screen(p, b))
	await _press(_screen(p, b), MOUSE_BUTTON_LEFT, true)
	await _release(_screen(p, b), MOUSE_BUTTON_LEFT)
	eq(p.view.selection.size(), 2, "Shift + щелчок — добавить к выбору")
	await hooks.key(KEY_ESCAPE)
	eq(p.view.selection.size(), 0, "Esc — снять выбор")
	# рамка по всему экрану — все свои, без чужих
	await _drag(Vector2(4, 4), Vector2(170, 95), 8, MOUSE_BUTTON_LEFT)
	var want: Array[int] = []
	for s in own:
		if not s.station:
			want.append(s.uid)
	want.sort()
	var got: Array[int] = []
	got.append_array(p.view.selection)
	got.sort()
	eq(got, want, "рамка через весь экран — все свои корабли, чужих нет")
	# щелчок по чужому — только он (рассмотреть)
	var foe := p.battle.side_ships(Ship.DEFENDER)[0]
	await hooks.click(_screen(p, foe))
	eq(p.view.selection, [foe.uid] as Array[int], "щелчок по чужому — выбран он один")
	var n0 := _journal(p)
	await hooks.click(Vector2(683, 300), MOUSE_BUTTON_RIGHT)
	eq(_journal(p), n0, "чужой в выборе — ПКМ приказа не даёт")
	# щелчок по пустому — снять
	await hooks.click(Vector2(60, 700))
	eq(p.view.selection.size(), 0, "щелчок по пустому полю снял выбор")
	await _drop(p)


func test_picking_hull_then_nearest() -> void:
	var p := await _polygon()
	var cap: Ship = null
	for s in _own(p):
		if s.def.id == &"capital":
			cap = s
	if not ok(cap != null, "у Тройдена есть флагман"):
		await _drop(p)
		return
	p.view.rig.set_view(Vector3(cap.pos.x, 0.0, cap.pos.y), 0.0, 700.0, true)
	await hooks.frames(2)
	var center := _screen(p, cap)
	# конец корпуса — дальше 30 точек от центра, но в капсуле
	var capsule: Array = p.view.capsule(cap)
	var nose: Vector3 = capsule[0]
	var nose_px := p.view.rig.camera.unproject_position(nose)
	ok(nose_px.distance_to(center) > Picking.NEAR_PX, "нос флагмана дальше 30 точек от центра (%.0f)" % nose_px.distance_to(center))
	ok(Picking.pick(p.view, nose_px) == cap, "по носу корпуса — флагман (капсула корпуса)")
	# мимо корпуса, но в 25 точках от центра малого — ближайший
	var cor: Ship = null
	for s in _own(p):
		if s.def.id == &"corvette":
			cor = s
	var cc := _screen(p, cor)
	var side := Vector2(0.0, 0.0)
	for dpx: Vector2 in [Vector2(25, 0), Vector2(-25, 0), Vector2(0, 25), Vector2(0, -25)]:
		var q: Vector2 = cc + dpx
		var o := p.view.rig.camera.project_ray_origin(q)
		var n := p.view.rig.camera.project_ray_normal(q)
		var cp: Array = p.view.capsule(cor)
		var ca: Vector3 = cp[0]
		var cb: Vector3 = cp[1]
		var cr: float = cp[2]
		if Picking.ray_capsule(o, n, ca, cb, cr) < 0.0:
			side = dpx
			break
	if ok(side != Vector2.ZERO, "нашлась точка в 25 точках от корвета мимо его корпуса"):
		ok(Picking.pick(p.view, cc + side) == cor, "мимо корпуса в 25 точках — ближайший корвет")
		var far := cc + side.normalized() * 40.0
		var who := Picking.pick(p.view, far)
		ok(who != cor, "в 40 точках от корвета он уже не выбирается (%s)" % [who.name if who != null else "никто"])
	# мёртвый не выбирается и не рисуется (единый фильтр)
	cor.dead = true
	p.view.draw_state()
	ok(Picking.pick(p.view, cc) != cor, "мёртвый не выбирается")
	ok(not p.view.visual_of(cor).visible, "мёртвый не рисуется — тот же фильтр")
	cor.dead = false
	await _drop(p)


## «Малый за факелом» (C29; 08, ловушка 10): корвет ниже и позади факела флагмана —
## луч к центру корвета сперва проходит через факел. Кораблём считается корпус: выбор —
## корвет. Откат — рамка всего нарисованного (с факелами) берёт флагман.
func test_small_behind_plume() -> void:
	var p := await _polygon()
	var cap: Ship = null
	var cor: Ship = null
	for s in _own(p):
		if s.def.id == &"capital":
			cap = s
		elif s.def.id == &"corvette" and cor == null:
			cor = s
	Hooks.place_ship(cap, Vector2(0.0, 0.0))
	cap.set_yaw(0.0)
	cap.thrust_fwd = 1.0
	Hooks.place_ship(cor, Vector2(0.0, 60.0))
	p.view._height[cap.uid] = 0.0
	p.view._height[cor.uid] = -40.0
	p.view._bob[cap.uid] = 0.0
	p.view._bob[cor.uid] = 0.0
	p.view.rig.set_view(Vector3(0.0, 0.0, 30.0), 0.0, 600.0, true)
	p.view._prev.clear()
	p.view.draw_state()
	await hooks.frames(2)
	p.view.draw_state()
	var at := _screen(p, cor)
	var plume_on := false
	for c in p.view.visual_of(cap).find_children("plume", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		plume_on = plume_on or mi.visible
	ok(plume_on, "у флагмана горит маршевый факел")
	var first := Picking.pick(p.view, at)
	ok(first == cor, "малый за факелом — выбран малый (кораблём считается корпус): %s" % [first.name if first != null else "никто"])
	Picking.rollback_drawn_box = true
	var got := Picking.pick(p.view, at)
	Picking.rollback_drawn_box = false
	ok(got == cap, "откат «рамка всего нарисованного, с факелами»: выбран флагман — проверка краснеет (%s)" % [got.name if got != null else "никто"])
	await _drop(p)


# ───────────────────────── вид: шаги, скорость, пауза, таймер ─────────────────────────

func _bare_view(speed: int) -> BattleView:
	var b := Battle.create(_get_defs(), Polygon.setup_dict(5), "проверка") as Battle
	var v := BattleView.new()
	tree.root.add_child(v)
	v.setup(_get_defs(), b, false)
	v.set_process(false)          # шагаем сами, постоянным delta
	v.speed = speed
	return v


func _drop_view(v: BattleView) -> void:
	var b := v.battle
	v.queue_free()
	await hooks.frames(1)
	b.dispose()


func test_speed_is_steps_per_frame() -> void:
	var v := _bare_view(1)
	var n := 0
	for i in 60:
		n += v.advance(1.0 / 60.0)
	eq(n, 30, "1×: 60 кадров по 1/60 — 30 шагов")
	v.set_speed(4)
	n = 0
	for i in 60:
		n += v.advance(1.0 / 60.0)
	eq(n, 120, "4×: 60 кадров — 120 шагов (по два за кадр), шаг тот же 1/30")
	v.toggle_pause()
	n = 0
	for i in 30:
		n += v.advance(1.0 / 60.0)
	eq(n, 0, "пауза — ноль шагов")
	v.toggle_pause()
	eq(v.speed, 4, "после паузы скорость прежняя")
	var t0 := v.battle.time
	n = v.advance(0.5)
	eq(n, BattleView.MAX_STEPS, "долгий кадр на 4× — не больше 8 шагов (бой медленнее, а не рывком)")
	near(v.acc, 0.0, 1e-12, "долг после предела не копится")
	near(v.battle.time - t0, BattleView.MAX_STEPS * Battle.STEP, 1e-9, "игровое время — ровно 8 шагов")
	await _drop_view(v)


## Подкрепление — 32 игровые секунды на любой скорости: на 4× вчетверо меньше кадров,
## та же игровая секунда (01, 4.2 п. 8). Таймер по кадрам или по настоящему времени
## дал бы поровну кадров на обеих скоростях — проверка различает.
func _reserve_frames(speed: int) -> Vector2:
	var v := _bare_view(speed)
	v.battle.queue({"op": &"reinforce", "side": Ship.ATTACKER})
	var frames := 0
	var arrived := -1.0
	var before := v.battle.side_ships(Ship.ATTACKER).size()
	while frames < 4000 and arrived < 0.0:
		v.advance(1.0 / 60.0)
		frames += 1
		var now := v.battle.side_ships(Ship.ATTACKER)
		if now.size() > before:
			# игровая секунда выхода — по шагу, на котором корабль появился (на 4× за
			# кадр два шага, и часы кадра ушли бы на шаг дальше)
			arrived = now[now.size() - 1].jumped_at_step * Battle.STEP
	await _drop_view(v)
	return Vector2(frames, arrived)


func test_reserve_timer_by_game_clock() -> void:
	var r1 := await _reserve_frames(1)
	var r4 := await _reserve_frames(4)
	var delay := _get_defs().hyper.reinforce_delay
	ok(r1.y > 0.0 and r4.y > 0.0, "подкрепление пришло на 1× и на 4×")
	near(r1.y, delay + Battle.STEP, Battle.STEP + 1e-9, "1×: вышло через %.0f игровых секунд" % delay)
	near(r4.y, r1.y, 1e-9, "4×: в ту же игровую секунду")
	ok(absf(r1.x / r4.x - 4.0) < 0.02, "на 4× вчетверо меньше кадров: %d против %d" % [int(r1.x), int(r4.x)])


## Интерполяция без картинки: x корабля на кадрах 60 Гц (откат smooth = false).
func _drawn_x(smooth: bool, fps: float) -> PackedFloat64Array:
	var v := _bare_view(1)
	v.smooth = smooth
	var b := v.battle
	var s := b.side_ships(Ship.ATTACKER)[0]
	Hooks.place_ship(s, Vector2(-300.0, 2000.0))
	s.vel = Vector2(s.max_speed(), 0.0)
	b.queue({"op": &"move", "ids": [s.uid], "x": 2500.0, "z": 2000.0})
	var xs := PackedFloat64Array()
	for i in int(fps):
		v.advance(1.0 / fps)
		v.draw_state()
		if i >= 10:
			xs.append(v.visual_of(s).position.x)
	await _drop_view(v)
	return xs


static func shift_spread(xs: PackedFloat64Array) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in range(1, xs.size()):
		var d := xs[i] - xs[i - 1]
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, hi)


func test_interpolation_even_steps() -> void:
	for fps: float in [60.0, 144.0]:
		var sm := shift_spread(await _drawn_x(true, fps))
		ok(sm.x > 0.0 and sm.y / sm.x < 1.2, "%d Гц: сдвиг между кадрами ровный — от %.3f до %.3f" % [int(fps), sm.x, sm.y])
		var raw := shift_spread(await _drawn_x(false, fps))
		ok(raw.x < 0.01, "%d Гц, откат «без смешивания»: сдвиг через кадр (от %.3f до %.3f) — проверка краснеет" % [int(fps), raw.x, raw.y])


## Новый корабль (выход подкрепления) рисуется сразу на своём месте, без смешивания.
func test_new_ship_not_blended() -> void:
	var v := _bare_view(1)
	v.battle.queue({"op": &"reinforce", "side": Ship.ATTACKER})
	var before := v.battle.ships.size()
	var guard := 0
	while v.battle.ships.size() == before and guard < 2000:
		v.advance(1.0 / 60.0)
		guard += 1
	v.draw_state()
	var s := v.battle.ships[v.battle.ships.size() - 1]
	var vis := v.visual_of(s)
	ok(vis != null and vis.visible, "у прибывшего есть корабль на экране")
	if vis != null:
		ok(Vector2(vis.position.x, vis.position.z).distance_to(s.pos) < 1e-6, "прибывший нарисован ровно на месте выхода (телепорт без смешивания)")
	await _drop_view(v)


# ───────────────────────── главная сцена ─────────────────────────

func test_main_polygon_table_keys() -> void:
	await hooks.set_window_size(Vector2i(1366, 768))
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	await hooks.frames(3)
	var poly: Node = main.get("polygon")
	ok(poly != null and main.get("view") == null, "по умолчанию — «Полигон»")
	var fps: Node = main.get("fps")
	var hint: Label = fps.get("hint")
	ok(hint.text.contains("F6 — «Стол»"), "подсказка «Полигона» называет F6: «%s»" % hint.text.get_slice("\n", 0))
	await hooks.key(KEY_F6)
	await hooks.frames(2)
	ok(main.get("view") != null and main.get("polygon") == null, "F6 — «Стол»")
	ok(hint.text.contains("F6 — «Полигон»"), "подсказка «Стола» — обратно на «Полигон»")
	await hooks.key(KEY_F6)
	await hooks.frames(2)
	ok(main.get("polygon") != null and main.get("view") == null, "F6 ещё раз — снова «Полигон»")
	# F8 — заново: новый бой
	var pn1: Node = main.get("polygon")
	var b1: Object = pn1.get("battle")
	await hooks.key(KEY_F8)
	await hooks.frames(2)
	var pn2: Node = main.get("polygon")
	var b2: Object = pn2.get("battle")
	ok(b2 != null and b2 != b1, "F8 — «Полигон» заново")
	# F9 — запись боя файлом; её проигрывает --replay
	await hooks.key(KEY_F9)
	var path: String = main.get("last_record")
	ok(path != "" and FileAccess.file_exists(path), "F9 — запись боя файлом: %s" % path)
	if path != "":
		var why := PackedStringArray()
		var rec := MainScript.read_record(path, PackedStringArray(), why)
		ok(str(rec.get("kind", "")) == "capella-replay" and str(rec.get("fp", "")) != "", "в записи заголовок и отпечаток: %s" % "; ".join(why))
		DirAccess.remove_absolute(path)
	# F5 с «Полигона» — «Стол» и минута замера (после секунды прогрева)
	await hooks.key(KEY_F5)
	await hooks.frames(2)
	ok(main.get("view") != null, "F5 с «Полигона» открыл «Стол»")
	var bench: Node = main.get("bench")
	var t0 := Time.get_ticks_msec()
	while not flag(bench.get("running")) and Time.get_ticks_msec() - t0 < 5000:
		await hooks.frames(1)
	ok(flag(bench.get("running")), "через секунду прогрева замер идёт")
	await hooks.key(KEY_F5)
	ok(not flag(bench.get("running")), "F5 — прервать замер")
	main.queue_free()
	await hooks.frames(2)


## Ушедший в гипер выпадает из выбора (06, 2.5: «выбор чистится сам»), и панель
## не пишет «Противник — , …» про пустое место (найдено глазом на снимке после G).
func test_selection_cleans_itself() -> void:
	var p := await _polygon()
	var fr: Ship = null
	for s in _own(p):
		if s.def.id == &"frigate":
			fr = s
	p.view.selection = [fr.uid] as Array[int]
	p.battle.queue({"op": &"hyper", "ids": [fr.uid]})
	p.view.paused = false
	var guard := 0
	while not fr.fled and guard < 2000:
		p.view.advance(1.0 / 30.0)
		guard += 1
	p.view.draw_state()
	ok(fr.fled, "фрегат ушёл в гипер")
	eq(p.view.selection.size(), 0, "ушедший выпал из выбора")
	var txt: String = p.hud.call("_sel_text", p.battle)
	ok(txt.begins_with("Ничего не выбрано"), "панель: «%s»" % txt.get_slice("\n", 0))
	# откат: выбор не чистится — панель пишет про пустое место
	p.view.selection = [fr.uid] as Array[int]
	var stale: String = p.hud.call("_sel_text", p.battle)
	ok(not stale.begins_with("Ничего не выбрано"), "откат «выбор не чистится»: панель «%s» — проверка краснеет" % stale.get_slice("\n", 0))
	await _drop(p)
