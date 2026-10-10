# input/battle_input.gd — мышь и клавиши боя, ядро части 06 (2.3; план G1, п. 6).
# Бой меняется ТОЛЬКО командой battle.queue (архитектура, 1): вид и интерфейс в модель
# не пишут. Клавиша и кнопка зовут одну команду.
# - ЛКМ: щелчок — выбор (Shift — добавить или убрать), протяжка — рамка; щелчок
#   по пустому снимает выбор. «Потянул» — дальше 6 точек по ЛЮБОЙ оси (06, ловушка 2);
#   рамка — только если обе стороны больше 8; щелчок — короче 900 мс (06, 2.3.5).
# - ПКМ: приказ — на ОТПУСКАНИИ и только если мышь не уехала дальше 6 точек по
#   любой оси; уехала — это был поворот камеры (его ведёт CameraRig), приказа нет
#   (06, ловушка 1). Предела по времени у ПКМ нет.
# - Жест, начатый на поле, дослушивается в _input (архитектура, 6.5): движение
#   и отпускание над панелью до поля не доходят, и без этого протяжка «залипла» бы.
#   Начинается жест только на поле: нажатие ловим в _unhandled_input — нажатие
#   по панели (STOP) сюда не придёт.
# - Клавиши — по МЕСТУ (physical_keycode), а не по букве: в русской раскладке
#   H — это «р» (06, ловушка 49); повтор (echo) — не нажатие.
#   H и S — «Держать» (приказ встать, 09, 9.5 п. 2), G — гипер (повторно — отмена),
#   D — дрифт, B — подкрепление, Пробел — пауза (скорость прежняя), 1 / 2 / 4 —
#   скорость, Esc — снять выбор.
# ПКМ по полю пока ведёт выделенных, СОХРАНЯЯ их взаимное расположение (строй по
# ролям — G4); фокус по врагу и охрана своего — G2/G6.
extends Node

const Ship := preload("res://sim/ship.gd")
const Picking := preload("res://input/picking.gd")
const CameraRig := preload("res://view/camera_rig.gd")

## Порог «щёлкнул / потянул» — тот же, что у камеры (06, 2.1): одно число на оба жеста.
const SLOP := CameraRig.DRAG_SLOP
const BOX_MIN := 8.0             # рамка — если обе стороны больше 8 точек
const CLICK_MS := 900            # ЛКМ дольше — не щелчок (06, 2.3.5)

## Вид боя (view/battle_view.gd): модель, камера, нарисованные положения, выбор.
var view: Node3D
## false — приказы не принимаются (повтор записи боя): мышь выбирает, клавиши
## вида (пауза, скорость) работают, а команд в бой нет.
var orders_enabled := true
## Короткие полоски интерфейса, не о приказе (06, 1.5: «Сначала выбери…»).
## Зовёт хозяин: say.call(текст).
var say: Callable
## Рамка на экране: box_changed.call(Rect2) — пустая рамка — спрятать.
var box_changed: Callable

## ТОЛЬКО для проверки отката (06, ловушка 2): порог «потянул» по расстоянию, а не
## по каждой оси. В игре всегда false.
static var rollback_slop_by_distance := false

var _lmb := false
var _lmb_from := Vector2.ZERO
var _lmb_moved := false
var _lmb_t0 := 0
var _lmb_shift := false
var _rmb := false
var _rmb_from := Vector2.ZERO
var _rmb_moved := false


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


func _queue(c: Dictionary) -> void:
	if not orders_enabled:
		_say("Повтор записи боя: приказы не принимаются")
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
			_click(mb.position, _lmb_shift or mb.shift_pressed)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and _rmb:
		_rmb = false
		if not _rmb_moved:
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
	var s := Picking.pick(view, at)
	var my_side: int = view.get("my_side")
	if s == null:
		if not shift:
			_set_sel([])
		return
	if s.side != my_side:
		_set_sel([s.uid])
		return
	if shift:
		# чужой в выборе и Shift — свой добавляется к одним своим
		var keep: Array[int] = []
		var b := _battle()
		for u in _sel():
			var o: Ship = b.call("ship_by_uid", u)
			if o != null and o.side == my_side:
				keep.append(u)
		if s.uid in keep:
			keep.erase(s.uid)
		else:
			keep.append(s.uid)
		_set_sel(keep)
	else:
		_set_sel([s.uid])


## Рамка: свои корабли без станции; Shift — к выбору, без Shift — выбор ЗАМЕНЯЕТСЯ
## найденным, в том числе пустым (06, 2.5).
func _box(r: Rect2, shift: bool) -> void:
	var got := Picking.in_box(view, r)
	if shift:
		var sel: Array[int] = []
		sel.append_array(_sel())
		for u in got:
			if u not in sel:
				sel.append(u)
		_set_sel(sel)
	else:
		_set_sel(got)


## ПКМ по полю: выделенные свои идут в точку плоскости y = 0 под курсором (06, 2.4.7),
## сохраняя взаимное расположение. Нет своих выделенных — ничего (06, 2.6).
func order_at(at: Vector2) -> bool:
	var ids := own_selected()
	if ids.is_empty():
		return false
	var rig: CameraRig = view.get("rig")
	var hit: Variant = rig.ground_at(at, false)
	if hit == null:
		return false                    # луч над горизонтом — молча (06, 2.6)
	var p: Vector3 = hit
	_queue({"op": &"move", "ids": ids, "x": p.x, "z": p.z})
	if orders_enabled:
		view.call("order_flash", p)
	return true


# ───────────────────────── клавиши ─────────────────────────

## → true, если клавиша наша (по месту, physical_keycode).
func _key(k: InputEventKey) -> bool:
	if k.ctrl_pressed or k.meta_pressed or k.alt_pressed:
		return false                    # Ctrl / ⌘ / Alt с буквой — не нам (06, 1.5)
	match k.physical_keycode:
		KEY_H, KEY_S:
			var ids := own_selected()
			if ids.is_empty():
				_say("Сначала выбери свои корабли")
			else:
				_queue({"op": &"stance", "ids": ids, "stance": &"hold"})
		KEY_G:
			var ids2 := own_selected()
			if not ids2.is_empty():     # без выбора G — молча (06, 1.5)
				_queue({"op": &"hyper", "ids": ids2})
		KEY_D:
			var ids3 := own_selected()
			if ids3.is_empty():
				_say("Сначала выбери корабли")
			else:
				_queue({"op": &"drift", "ids": ids3})
		KEY_B:
			var my_side: int = view.get("my_side")
			_queue({"op": &"reinforce", "side": my_side})
		KEY_SPACE:
			view.call("toggle_pause")
		KEY_1:
			view.call("set_speed", 1)
		KEY_2:
			view.call("set_speed", 2)
		KEY_4:
			view.call("set_speed", 4)
		KEY_ESCAPE:
			_set_sel([])
		_:
			return false
	return true
