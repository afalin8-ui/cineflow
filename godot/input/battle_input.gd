# input/battle_input.gd — мышь и клавиши боя, ядро части 06 (2.3; план G1, п. 6; G2, п. 10).
# Бой меняется ТОЛЬКО командой battle.queue (архитектура, 1): вид и интерфейс в модель
# не пишут. Клавиша и кнопка зовут одну команду.
# - ЛКМ: щелчок — выбор (Shift — добавить или убрать), протяжка — рамка; щелчок
#   по пустому снимает выбор. «Потянул» — дальше 6 точек по ЛЮБОЙ оси (06, ловушка 2);
#   рамка — только если обе стороны больше 8; щелчок — короче 900 мс (06, 2.3.5).
# - ПКМ: приказ — на ОТПУСКАНИИ и только если мышь не уехала дальше 6 точек по
#   любой оси; уехала — это был поворот камеры (его ведёт CameraRig), приказа нет
#   (06, ловушка 1). Предела по времени у ПКМ нет. ПКМ по врагу — фокус огня (G2);
#   ТОЧНО в корпус своего невыделенного — охранять его (03, 2.16, ловушка 14); иначе —
#   идти, сохраняя взаимное расположение (строй по ролям — G4).
# - A — атака с ходу: следующий щелчок ЛКМ — точка (amove) или враг (фокус); Esc —
#   отмена, ПКМ во время ожидания — обычный приказ (03, 2.15).
# - Жест, начатый на поле, дослушивается в _input (архитектура, 6.5): движение
#   и отпускание над панелью до поля не доходят, и без этого протяжка «залипла» бы.
#   Начинается жест только на поле: нажатие ловим в _unhandled_input — нажатие
#   по панели (STOP) сюда не придёт.
# - Клавиши — по МЕСТУ (physical_keycode), а не по букве: в русской раскладке
#   H — это «р» (06, ловушка 49); повтор (echo) — не нажатие.
#   H и S — «Держать» (приказ встать, 09, 9.5 п. 2), Y — «Охрана», T — «Охота»,
#   A — атака с ходу, G — гипер (повторно — отмена), D — дрифт, B — подкрепление,
#   Пробел — пауза (скорость прежняя), 1 / 2 / 4 — скорость, Esc — снять выбор.
# - Авиация (G3; 04, 1.1 и 2.13): щелчок по машине выбирает её ЗВЕНО целиком; рамка
#   берёт и свои звенья; Z / X / C — поднять звено перехватчиков, истребителей,
#   бомбардировщиков с первого выделенного носителя со свободным местом; V — выделенные
#   звенья на посадку. ПКМ по врагу или по чужому звену — бить (корабли — машины звена,
#   C14; тяжёлые такой приказ не принимают, 09, 4.6); ПКМ по полю — звенья летят туда.
# - Под курсором — корабль (hover): у чужого тяжёлого рисуется его пояс (09, 6.7).
# - КНОПКА И КЛАВИША — ОДНА ДВЕРЬ (план GИ, п. 5): клавиша ищет id команды в KEY_CMD
#   и зовёт command(id), кнопка экрана (ui/polygon_hud.gd) зовёт тот же command(id).
#   Своей ветки у кнопки нет: проверка сверяет журнал команд кнопки и клавиши.
#   J / K / L — режимы РЭБ (07, 2.10), N — выбрать прибывших, F2 — весь флот, I — знаки.
extends Node

const Ship := preload("res://sim/ship.gd")
const Squad := preload("res://sim/squad.gd")
const Picking := preload("res://input/picking.gd")
const CameraRig := preload("res://view/camera_rig.gd")
const Texts := preload("res://ui/texts.gd")

## Клавиша по МЕСТУ → команда (одна дверь с кнопками экрана). Esc, камера и F-клавиши
## главной сцены — не здесь.
const KEY_CMD := {
	KEY_A: &"amove", KEY_H: &"hold", KEY_S: &"hold", KEY_Y: &"guard", KEY_T: &"hunt",
	KEY_D: &"drift", KEY_G: &"hyper", KEY_Z: &"launch_interceptor", KEY_X: &"launch_fighter",
	KEY_C: &"launch_bomber", KEY_V: &"recall", KEY_J: &"ecm_jam", KEY_K: &"ecm_shield",
	KEY_L: &"ecm_off", KEY_B: &"reinforce", KEY_N: &"arrived", KEY_SPACE: &"pause",
	KEY_1: &"speed1", KEY_2: &"speed2", KEY_4: &"speed4", KEY_F2: &"all", KEY_I: &"markers",
}
## Роль звена по команде пуска (04, 2.3).
const LAUNCH_ROLE := {&"launch_interceptor": &"interceptor", &"launch_fighter": &"fighter", &"launch_bomber": &"bomber"}
## Режим РЭБ по команде (04, 2.16).
const ECM_MODE := {&"ecm_jam": &"jam", &"ecm_shield": &"shield", &"ecm_off": &"off"}
## Подкрепление в ленте «прибывшие» — не дольше минуты (07, 2.5: ARRIVED_HINT).
const ARRIVED_HINT_S := 60.0

## Порог «щёлкнул / потянул» — тот же, что у камеры (06, 2.1): одно число на оба жеста.
const SLOP := CameraRig.DRAG_SLOP
const BOX_MIN := 8.0             # рамка — если обе стороны больше 8 точек
const CLICK_MS := 900            # ЛКМ дольше — не щелчок (06, 2.3.5)

## Вид боя (view/battle_view.gd): модель, камера, нарисованные положения, выбор.
var view: Node3D
## false — приказы не принимаются (повтор записи боя): мышь выбирает, клавиши
## вида (пауза, скорость) работают, а команд в бой нет.
var orders_enabled := true
## Что сказать на приказ, когда приказы выключены: повтор записи или «ИИ против ИИ».
var orders_off_text := "Повтор записи боя: приказы не принимаются"
## Короткие полоски интерфейса, не о приказе (06, 1.5: «Сначала выбери…»).
## Зовёт хозяин: say.call(текст).
var say: Callable
## Рамка на экране: box_changed.call(Rect2) — пустая рамка — спрятать.
var box_changed: Callable
## Вопрос перед отходом (ui/polygon_hud.gd → ask): ask.call(текст, «да», «нет», что сделать).
## Нет его (лаборатории проверок без экрана) — отход без вопроса.
var ask: Callable
## Сколько раз позвана каждая команда (кнопкой или клавишей) — проверки.
var commands_done: Dictionary[StringName, int] = {}

## ТОЛЬКО для проверки отката (06, ловушка 2): порог «потянул» по расстоянию, а не
## по каждой оси. В игре всегда false.
static var rollback_slop_by_distance := false
## ТОЛЬКО для проверок отката (план G2, п. 10): в игре всегда false.
## ПКМ — всегда «идти», как в G1 (фокуса по врагу и охраны своего нет).
static var rollback_rmb_move_only := false
## Охрана своего — по «ближайшему в 30 точках», а не только прямым попаданием в корпус
## (03, ловушка 14: «подвинь флот чуть вперёд» превращалось в «встаньте кольцом»).
static var rollback_guard_by_near := false
## Esc при ожидании A снимает выбор, а не только ожидание.
static var rollback_esc_clears := false
## Курсор не отслеживается: пояса чужого тяжёлого по наведению нет (09, 6.7).
static var rollback_no_hover := false
## Машины под курсором не ищутся (как в G2): звено не выбрать щелчком и не ударить ПКМ
## (04, 1.1 и 2.13).
static var rollback_no_squad_pick := false
## Z / X / C без носителя в выборе всё равно шлют пуск — подсказки «выбери носитель» нет.
static var rollback_launch_any := false
## ТОЛЬКО для проверки отката (09, 6.8): «Лёгкие» без кораблей РЭБ, как прежний «Эскорт» без них.
static var rollback_ecm_not_light := false
## ТОЛЬКО для проверки отката (07, 2.8): щелчок по ячейке ростера — всегда весь класс, по одному
## не перебрать. В игре false.
static var rollback_roster_whole := false

var _lmb := false
var _lmb_from := Vector2.ZERO
var _lmb_moved := false
var _lmb_t0 := 0
var _lmb_shift := false
var _rmb := false
var _rmb_from := Vector2.ZERO
var _rmb_moved := false
## A нажата — ждём щелчка: точка — атака с ходу, враг — фокус (03, 2.15).
var amove_armed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _battle() -> Object:
	var b: Object = view.get("battle")
	return b


func _sel() -> Array[int]:
	var s: Array[int] = view.get("selection")
	return s


func _set_sel(list: Array[int]) -> void:
	view.set("selection", list)


## Свои живые выбранные, без станции (space.js:3092 mineSelected; станция приказов
## движения не получает — вопрос 20 части 02).
func own_selected() -> PackedInt32Array:
	var out := PackedInt32Array()
	var b := _battle()
	var my_side: int = view.get("my_side")
	for u in _sel():
		var s: Ship = b.call("ship_by_uid", u)
		if s != null and not s.dead and s.side == my_side and not s.station:
			out.append(u)
	return out


## Свои живые выбранные звенья (04, 2.13).
func own_squads() -> PackedInt32Array:
	var out := PackedInt32Array()
	var b := _battle()
	var my_side: int = view.get("my_side")
	for u in _sel():
		var q: Squad = b.call("squad_by_uid", u)
		if q != null and not q.dead and q.side == my_side:
			out.append(u)
	return out


## Свои выбранные носители (и станция): у кого есть ангар (04, 2.3).
func own_carriers() -> PackedInt32Array:
	var out := PackedInt32Array()
	var b := _battle()
	var my_side: int = view.get("my_side")
	for u in _sel():
		var s: Ship = b.call("ship_by_uid", u)
		if s != null and not s.dead and s.side == my_side and s.hangar != null:
			out.append(u)
	return out


## Кому отдаётся приказ мышью: свои корабли (без станции) и свои звенья.
func own_orders() -> PackedInt32Array:
	var out := own_selected()
	out.append_array(own_squads())
	return out


func _queue(c: Dictionary) -> void:
	if not orders_enabled:
		_say(orders_off_text)
		return
	_battle().call("queue", c)


func _say(text: String) -> void:
	if say.is_valid():
		say.call(text)


# ───────────────────────── мышь ─────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		# жест начинается только на поле (нажатие по панели сюда не дошло)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_lmb = true
			_lmb_from = mb.position
			_lmb_moved = false
			_lmb_t0 = Time.get_ticks_msec()
			_lmb_shift = mb.shift_pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_rmb = true
			_rmb_from = mb.position
			_rmb_moved = false
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		if _key(k):
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		_hover(mm.position)
		if _lmb:
			if not _lmb_moved and _far(mm.position, _lmb_from):
				_lmb_moved = true
			if _lmb_moved and box_changed.is_valid():
				box_changed.call(_rect(_lmb_from, mm.position))
		if _rmb and not _rmb_moved and _far(mm.position, _rmb_from):
			_rmb_moved = true
		return
	var mb := event as InputEventMouseButton
	if mb != null and not mb.pressed:
		# отпускание ловим где угодно — жест мог кончиться над панелью (архитектура, 6.5)
		release(mb)


## Отпускание кнопки мыши: конец жеста, начатого на поле.
func release(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_LEFT and _lmb:
		_lmb = false
		if box_changed.is_valid():
			box_changed.call(Rect2())
		if _lmb_moved:
			var r := _rect(_lmb_from, mb.position)
			if r.size.x > BOX_MIN and r.size.y > BOX_MIN:
				_box(r, _lmb_shift or mb.shift_pressed)
		elif Time.get_ticks_msec() - _lmb_t0 < CLICK_MS:
			if amove_armed:
				amove_at(mb.position)
			else:
				_click(mb.position, _lmb_shift or mb.shift_pressed)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and _rmb:
		_rmb = false
		if not _rmb_moved:
			amove_armed = false             # ПКМ во время ожидания — обычный приказ
			order_at(mb.position)


## «Потянул» — по КАЖДОЙ оси, а не по расстоянию (06, 2.3.3; ловушка 2): протяжка
## на 5 точек вбок и 5 вниз (7 по прямой) — ещё щелчок, то есть приказ.
static func _far(p: Vector2, from: Vector2) -> bool:
	if rollback_slop_by_distance:
		return p.distance_to(from) > SLOP
	return absf(p.x - from.x) > SLOP or absf(p.y - from.y) > SLOP


static func _rect(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())


func _notification(what: int) -> void:
	# окно потеряло фокус посреди жеста — отпускание может не прийти
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_lmb = false
		_rmb = false
		if box_changed.is_valid():
			box_changed.call(Rect2())


## Щелчок ЛКМ (06, 2.5 selectEntity): по своему — выбрать (Shift — добавить или
## убрать), по чужому — только его (рассмотреть), по пустому — снять (без Shift).
func _click(at: Vector2, shift: bool) -> void:
	var hit := _under(at)
	var my_side: int = view.get("my_side")
	if hit == null:
		if not shift:
			_set_sel([])
		return
	var s := hit as Ship
	var q := hit as Squad
	var uid := s.uid if s != null else q.uid
	var side := s.side if s != null else q.side
	if side != my_side:
		_set_sel([uid])
		return
	if shift:
		# чужой в выборе и Shift — свой добавляется к одним своим
		var keep: Array[int] = []
		var b := _battle()
		for u in _sel():
			var o: Ship = b.call("ship_by_uid", u)
			var oq: Squad = b.call("squad_by_uid", u)
			if (o != null and o.side == my_side) or (oq != null and oq.side == my_side):
				keep.append(u)
		if uid in keep:
			keep.erase(uid)
		else:
			keep.append(uid)
		_set_sel(keep)
	else:
		_set_sel([uid])


## Кто под точкой: корабль или звено (Picking.pick_any); откат — только корабли.
func _under(at: Vector2) -> RefCounted:
	if rollback_no_squad_pick:
		return Picking.pick(view, at)
	return Picking.pick_any(view, at)


## Рамка: свои корабли без станции; Shift — к выбору, без Shift — выбор ЗАМЕНЯЕТСЯ
## найденным, в том числе пустым (06, 2.5).
func _box(r: Rect2, shift: bool) -> void:
	var got := Picking.in_box(view, r)
	if not rollback_no_squad_pick:
		got.append_array(Picking.squads_in_box(view, r))
	if shift:
		var sel: Array[int] = []
		sel.append_array(_sel())
		for u in got:
			if u not in sel:
				sel.append(u)
		_set_sel(sel)
	else:
		_set_sel(got)


## Кто под курсором — для пояса чужого тяжёлого и полного купола (09, 6.7).
func _hover(at: Vector2) -> void:
	if rollback_no_hover:
		return
	var s := Picking.pick(view, at)
	view.set("hover_uid", s.uid if s != null else 0)


## ПКМ (03, 2.14, 2.16; 06, 2.4.7): по врагу — фокус огня; ТОЧНО в корпус своего
## невыделенного — охранять его; иначе — выделенные свои идут в точку плоскости y = 0
## под курсором, сохраняя взаимное расположение. Нет своих выделенных — ничего (06, 2.6).
func order_at(at: Vector2) -> bool:
	var ids := own_orders()
	if ids.is_empty():
		return false
	var my_side: int = view.get("my_side")
	var under := _under(at) if not rollback_rmb_move_only else null
	var foe := under as Ship
	if foe != null and foe.side != my_side:
		_queue({"op": &"focus", "ids": ids, "target": foe.uid})
		if orders_enabled:
			view.call("target_flash", foe)
		return true
	var fq := under as Squad
	if fq != null and fq.side != my_side:
		# по чужому звену — бить его машины (C14); тяжёлые не примут (09, 4.6)
		_queue({"op": &"focus", "ids": ids, "target": fq.uid})
		if orders_enabled:
			view.call("order_flash", view.call("squad_point", fq))
		return true
	var ward: Ship = null
	if not rollback_rmb_move_only:
		ward = Picking.pick(view, at) if rollback_guard_by_near else Picking.pick_hull(view, at)
	if ward != null and ward.side == my_side and not ward.station and ward.uid not in _sel():
		_queue({"op": &"guard", "ids": ids, "target": ward.uid})
		if orders_enabled:
			view.call("order_flash", view.call("ship_point", ward))
		return true
	var rig: CameraRig = view.get("rig")
	var hit: Variant = rig.ground_at(at, false)
	if hit == null:
		return false                    # луч над горизонтом — молча (06, 2.6)
	var p: Vector3 = hit
	_queue({"op": &"move", "ids": ids, "x": p.x, "z": p.z})
	if orders_enabled:
		view.call("order_flash", p)
	return true


## Щелчок после A (03, 2.15): по врагу — фокус, иначе — атака с ходу в точку.
func amove_at(at: Vector2) -> bool:
	amove_armed = false
	var ids := own_orders()
	if ids.is_empty():
		return false
	var my_side: int = view.get("my_side")
	var under := _under(at)
	var foe := under as Ship
	if foe != null and foe.side != my_side:
		_queue({"op": &"focus", "ids": ids, "target": foe.uid})
		if orders_enabled:
			view.call("target_flash", foe)
		return true
	var fq := under as Squad
	if fq != null and fq.side != my_side:
		_queue({"op": &"focus", "ids": ids, "target": fq.uid})
		return true
	var rig: CameraRig = view.get("rig")
	var hit: Variant = rig.ground_at(at, false)
	if hit == null:
		return false
	var p: Vector3 = hit
	_queue({"op": &"amove", "ids": ids, "x": p.x, "z": p.z})
	if orders_enabled:
		view.call("amove_flash", p)
	return true


# ───────────────────────── клавиши ─────────────────────────

## → true, если клавиша наша (по месту, physical_keycode).
func _key(k: InputEventKey) -> bool:
	if k.ctrl_pressed or k.meta_pressed or k.alt_pressed:
		return false                    # Ctrl / ⌘ / Alt с буквой — не нам (06, 1.5)
	if k.physical_keycode == KEY_ESCAPE:
		if amove_armed and not rollback_esc_clears:
			amove_armed = false         # сначала — отмена ожидания A, выбор цел
		else:
			amove_armed = false
			_set_sel([])
		return true
	if not KEY_CMD.has(k.physical_keycode):
		return false
	var id: StringName = KEY_CMD[k.physical_keycode]
	command(id)
	return true


## Команда — кнопкой экрана или клавишей (одна дверь, план GИ, п. 5). id — из ui/texts.gd.
## → false, если такой команды нет.
func command(id: StringName) -> bool:
	var n: int = commands_done.get(id, 0)
	commands_done[id] = n + 1
	match id:
		&"hold", &"guard", &"hunt":
			var ids := own_selected()
			if ids.is_empty():
				_say(Texts.PICK_FIRST)
			else:
				_queue({"op": &"stance", "ids": ids, "stance": id})
		&"amove":
			if own_orders().is_empty():
				_say("Атака с ходу: сначала выбери свои корабли")
			else:
				amove_armed = true            # подсказку держит экран, пока A ждёт щелчка
		&"launch_interceptor", &"launch_fighter", &"launch_bomber":
			var cs := own_carriers() if not rollback_launch_any else own_selected()
			if cs.is_empty():
				_say("Звенья поднимает носитель: выбери его и нажми Z, X или C")
			else:
				_queue({"op": &"launch", "ids": cs, "role": LAUNCH_ROLE[id]})
		&"recall":
			var qs := own_squads()
			if qs.is_empty():
				_say("На посадку: сначала выбери свои звенья (щелчок по машине)")
			else:
				_queue({"op": &"recall", "ids": qs})
		&"hyper", &"unhyper":
			var ids2 := own_selected()
			if not ids2.is_empty():     # без выбора G — молча (06, 1.5)
				_queue({"op": &"hyper", "ids": ids2})
		&"drift":
			var ids3 := own_selected()
			if ids3.is_empty():
				_say("Сначала выбери корабли")
			else:
				_queue({"op": &"drift", "ids": ids3})
		&"ecm_jam", &"ecm_shield", &"ecm_off":
			var es := own_ecms()
			if es.is_empty():
				_say("Купол ставит корабль РЭБ: выбери его и нажми J, K или L")
			else:
				_queue({"op": &"ecm", "ids": es, "mode": ECM_MODE[id]})
		&"reinforce":
			# у кнопки в режиме «Прибывшие» B тоже выбирает их, а не зовёт (07, 1.3): резерв
			# уходит весь сразу, и после прихода звать уже некого
			var my_side: int = view.get("my_side")
			if arrived_left() > 0 and _reserve_left(my_side) == 0:
				select_arrived()
			else:
				_queue({"op": &"reinforce", "side": my_side})
		&"arrived":
			select_arrived()
		&"retreat":
			retreat_pressed()
		&"pause":
			view.call("toggle_pause")
		&"speed1":
			view.call("set_speed", 1)
		&"speed2":
			view.call("set_speed", 2)
		&"speed4":
			view.call("set_speed", 4)
		&"all", &"heavy", &"light", &"carriers":
			select_kind(id)
		&"squads":
			select_squads()
		&"markers":
			var on: bool = view.call("toggle_markers")
			_say(Texts.MARKERS_ON if on else Texts.MARKERS_OFF)
		_:
			return false
	return true


## Свои выбранные корабли РЭБ (04, 2.16).
func own_ecms() -> PackedInt32Array:
	var out := PackedInt32Array()
	var b := _battle()
	var my_side: int = view.get("my_side")
	for u in _sel():
		var s: Ship = b.call("ship_by_uid", u)
		if s != null and not s.dead and s.side == my_side and s.def.ecm:
			out.append(u)
	return out


## Быстрый выбор (07, 1.4; 09, 6.8): весь флот (без станции), тяжёлые (класс capital — флагман,
## крейсеры, «Синхо»), лёгкие (класс escort — корвет, фрегат и РЭБ: РЭБ стоит с лёгкими и
## выбирается с ними). Есть кого — камера к их середине, расстояние то же.
func select_kind(kind: StringName) -> Array[int]:
	var got: Array[int] = []
	var b := _battle()
	var my_side: int = view.get("my_side")
	var sum := Vector3.ZERO
	var ships: Array = b.get("ships")
	for o: Object in ships:
		var s := o as Ship
		if s.dead or s.side != my_side or s.station or not Picking.shown(s, my_side):
			continue
		if kind == &"heavy" and s.def.cls != &"capital":
			continue
		if kind == &"light" and (s.def.cls != &"escort" or (rollback_ecm_not_light and s.def.ecm)):
			continue
		if kind == &"carriers" and s.def.cls != &"carrier":
			continue
		got.append(s.uid)
		sum += view.call("ship_point", s)
	if got.is_empty():
		_say(Texts.NONE_OF_KIND)
		return got
	_set_sel(got)
	_look_at(sum / float(got.size()))
	return got


## «Авиация» (09, 6.8 — «как есть», 07, 2.9): все свои живые звенья в воздухе разом — так их
## уводят на посадку одной V. Камера — к их середине, как у быстрого выбора кораблей.
func select_squads() -> Array[int]:
	var got: Array[int] = []
	var b := _battle()
	var my_side: int = view.get("my_side")
	var sum := Vector3.ZERO
	var squads: Array = b.get("squads")
	for o: Object in squads:
		var q := o as Squad
		if q.dead or q.side != my_side or q.craft.is_empty():
			continue
		got.append(q.uid)
		sum += view.call("squad_point", q)
	if got.is_empty():
		_say(Texts.NO_SQUADS)
		return got
	_set_sel(got)
	_look_at(sum / float(got.size()))
	return got


func _look_at(p: Vector3) -> void:
	var rig: CameraRig = view.get("rig")
	if rig != null:
		rig.set_view(Vector3(p.x, 0.0, p.z), rig.yaw, rig.dist, false)


## Сколько прибывших из подкрепления ещё напоминает кнопка (07, 2.5): живы, не выбирали,
## прошло не больше минуты.
func arrived_left() -> int:
	var seen: bool = view.get("arrived_seen")
	var at: float = view.get("arrived_at")
	var b := _battle()
	var t: float = b.get("time")
	if seen or at < 0.0 or t - at > ARRIVED_HINT_S:
		return 0
	return _arrived_alive().size()


func _arrived_alive() -> Array[int]:
	var out: Array[int] = []
	var b := _battle()
	var my_side: int = view.get("my_side")
	var list: Array[int] = view.get("arrived")
	for u in list:
		var s: Ship = b.call("ship_by_uid", u)
		if s != null and not s.dead and s.side == my_side:
			out.append(u)
	return out


## Выбрать прибывших (07, 2.5 selectArrived): N работает и после минуты — предел только у кнопки.
func select_arrived() -> void:
	var list: Array[int] = view.get("arrived")
	if list.is_empty():
		_say(Texts.ARRIVED_NONE)
		return
	var alive := _arrived_alive()
	if alive.is_empty():
		_say(Texts.ARRIVED_GONE)
		return
	view.set("arrived_seen", true)
	_set_sel(alive)
	var sum := Vector3.ZERO
	var b := _battle()
	for u in alive:
		sum += view.call("ship_point", b.call("ship_by_uid", u))
	_look_at(sum / float(alive.size()))


## «Отход» (07, 2.4): нет отхода — спросить и уйти всем флотом; отходим — отменить без
## вопроса; носитель ушёл — отменить уже нельзя.
func retreat_pressed() -> void:
	if not orders_enabled:
		_say(orders_off_text)
		return
	var b := _battle()
	var my_side: int = view.get("my_side")
	var sides: Array = b.get("sides")
	var sd: Object = sides[my_side]
	if sd.get("conceded"):
		_say(Texts.RETREAT_LOCKED)
	elif sd.get("retreat"):
		_queue({"op": &"cancel_retreat", "side": my_side})
		_say(Texts.RETREAT_CANCELLED)
	elif ask.is_valid():
		ask.call(Texts.RETREAT_ASK, Texts.RETREAT_YES, Texts.RETREAT_NO, func() -> void: _queue({"op": &"retreat", "side": my_side}))
	else:
		_queue({"op": &"retreat", "side": my_side})


## Сколько кораблей стороны ещё в резерве (не вызваны).
func _reserve_left(side: int) -> int:
	var sides: Array = _battle().get("sides")
	var sd: Object = sides[side]
	var reserve: Array = sd.get("reserve")
	var n := 0
	for e: Object in reserve:
		var c: int = e.get("count")
		n += c
	return n


## Щелчок по ячейке ростера (07, 2.8 rosterClick): весь класс; следующий — по одному, после
## последнего — снова весь; Shift — добавить класс к выбранным. Камера — к выбранным.
func roster_click(uids: Array, shift: bool) -> void:
	var b := _battle()
	var list: Array[int] = []
	for v: Variant in uids:
		var u: int = v
		var s: Ship = b.call("ship_by_uid", u)
		var q: Squad = b.call("squad_by_uid", u) if s == null else null
		if (s != null and not s.dead) or (q != null and not q.dead):
			list.append(u)
	if list.is_empty():
		return
	var sel: Array[int] = []
	sel.append_array(_sel())
	var got: Array[int] = []
	if shift:
		got = sel.duplicate()
		for u in list:
			if u not in got:
				got.append(u)
	else:
		var all := sel.size() == list.size()
		for u in list:
			all = all and u in sel
		var one := sel.size() == 1 and sel[0] in list
		if rollback_roster_whole:
			got = list.duplicate()
		elif list.size() > 1 and all:
			got.append(list[0])           # не «got = [x]»: литерал — Array, а не Array[int]
		elif one and list.size() > 1:
			var i := list.find(sel[0])
			if i + 1 < list.size():
				got.append(list[i + 1])
			else:
				got = list.duplicate()
		else:
			got = list.duplicate()
	_set_sel(got)
	var sum := Vector3.ZERO
	var n := 0
	for u in got:
		var s2: Ship = b.call("ship_by_uid", u)
		if s2 != null:
			sum += view.call("ship_point", s2)
			n += 1
		else:
			var q2: Squad = b.call("squad_by_uid", u)
			if q2 != null:
				sum += view.call("squad_point", q2)
				n += 1
	if n > 0:
		_look_at(sum / float(n))
