# ui/polygon_hud.gd — экран «Полигона» (план G1): что выбрано и чем занято,
# время и скорость боя, полоски о приказах, рамка выбора, конец боя.
# Полный экран боя (панель команд, ростер, лента, подписи) — G6–G7; здесь — минимум,
# чтобы видеть, что сделали клавиши и мышь.
# - Полоски о приказах берутся из ЖУРНАЛА модели (toast_log, с игровым временем:
#   02, ловушка 30; 05, ловушка 38): интерфейс их только показывает и гасит по
#   игровым часам — на паузе полоска стоит. Свои полоски интерфейса («Сначала
#   выбери свои корабли») — по настоящему времени: боя они не касаются.
# - Раскладочные узлы — IGNORE (у Control по умолчанию STOP — C135); нижняя панель —
#   STOP целиком, как настоящая панель: щелчок по ней до поля не доходит, а жест,
#   начатый на поле и кончившийся над ней, дослушивается в _input (архитектура, 6.5).
# - Числа в текст — форматом, а не str() (07, 5.2).
extends CanvasLayer

const Ship := preload("res://sim/ship.gd")
const FrameBench := preload("res://ui/frame_bench.gd")

## Сколько игровых секунд живёт полоска модели и сколько настоящих — своя.
const TOAST_GAME_S := 4.5
const TOAST_REAL_MS := 4000
const TOASTS_MAX := 3
## Полоски — ниже подсказки клавиш (две строки слева сверху, ui/fps_counter.gd).
const TOAST_Y := 70.0

## Вид боя (view/battle_view.gd): модель, выбор, скорость.
var view: Node3D
var title := ""

var status: Label
var toasts: Label
var panel: PanelContainer
var sel_label: Label
var box: Panel
var banner: Label
## Свои полоски интерфейса: [текст, мс настоящего времени, когда гаснет].
var _local: Array[Array] = []
var _last_status := ""
var _last_sel := ""
var _last_toasts := ""


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	status = _label(18, Color(0.85, 0.92, 1.0))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(status)
	toasts = _label(17, Color(1.0, 0.93, 0.7))
	toasts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toasts)
	panel = PanelContainer.new()
	panel.name = "SelPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.86)
	sb.border_color = Color(0.35, 0.55, 0.8, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	sel_label = _label(15, Color(0.85, 0.92, 1.0))
	panel.add_child(sel_label)
	add_child(panel)
	box = Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.56, 1.0, 0.78, 0.08)
	bs.border_color = Color(0.56, 1.0, 0.78, 0.85)
	bs.set_border_width_all(1)
	box.add_theme_stylebox_override("panel", bs)
	box.visible = false
	add_child(box)
	banner = _label(24, Color(1.0, 0.9, 0.6))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.visible = false
	add_child(banner)


static func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	return l


## Своя полоска интерфейса (не о приказе): «Сначала выбери свои корабли».
func say(text: String) -> void:
	_local.append([text, Time.get_ticks_msec() + TOAST_REAL_MS])


## Рамка выбора: пустая — спрятать.
func show_box(r: Rect2) -> void:
	box.visible = r.has_area()
	if box.visible:
		box.position = r.position
		box.size = r.size


func _process(_delta: float) -> void:
	if view == null:
		return
	var b: Object = view.get("battle")
	if b == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var st := _status_text(b)
	if st != _last_status:
		_last_status = st
		status.text = st
	status.reset_size()
	status.position = Vector2(vs.x - status.size.x - 16.0, 12.0)
	var over: bool = b.get("over")
	# бой кончился — часы стоят, и полоски модели висели бы вечно; итог говорит баннер
	var tt := "" if over else _toast_text(b)
	if tt != _last_toasts:
		_last_toasts = tt
		toasts.text = tt
	toasts.reset_size()
	toasts.position = Vector2((vs.x - toasts.size.x) * 0.5, TOAST_Y)
	var sl := _sel_text(b)
	if sl != _last_sel:
		_last_sel = sl
		sel_label.text = sl
		panel.reset_size()
	panel.position = Vector2(((vs.x - panel.size.x) * 0.5), vs.y - panel.size.y - 14.0)
	banner.visible = over
	if over:
		var w: int = b.get("winner")
		var my_side: int = view.get("my_side")
		banner.text = "Бой окончен: %s.\nF8 — начать заново" % ("ничья" if w < 0 else ("наша сторона держит орбиту" if w == my_side else "орбиту держит противник"))
		banner.reset_size()
		banner.position = ((vs - banner.size) * 0.5).floor() - Vector2(0.0, vs.y * 0.18)


func _status_text(b: Object) -> String:
	var t: float = b.get("time")
	var paused: bool = view.get("paused")
	var speed: int = view.get("speed")
	var clock := "%d:%02d" % [floori(t / 60.0), floori(t) % 60]
	var lines := PackedStringArray([title, "%s · %s" % [clock, "пауза" if paused else "%d×" % speed]])
	var my_side: int = view.get("my_side")
	var sides: Array = b.get("sides")
	var sd: Object = sides[my_side]
	var res_at: float = sd.get("reinforce_at")
	var reserve: Array = sd.get("reserve")
	if res_at > 0.0:
		lines.append("Подкрепление выйдет через %d с" % ceili(res_at - t))
	elif not reserve.is_empty():
		var n := 0
		for e: Object in reserve:
			var c: int = e.get("count")
			n += c
		lines.append("В резерве %d %s · B — вызвать" % [n, FrameBench.plural(n, "корабль", "корабля", "кораблей")])
	return "\n".join(lines)


func _toast_text(b: Object) -> String:
	var out := PackedStringArray()
	var log: Array[Dictionary] = b.get("toast_log")
	var t: float = b.get("time")
	var i := log.size() - 1
	while i >= 0 and out.size() < TOASTS_MAX:
		var e: Dictionary = log[i]
		var et: float = e["t"]
		if t - et > TOAST_GAME_S:
			break
		out.append(str(e["text"]))
		i -= 1
	var now := Time.get_ticks_msec()
	var keep: Array[Array] = []
	for l in _local:
		var until: int = l[1]
		if until > now:
			keep.append(l)
	_local = keep
	for j in range(_local.size() - 1, -1, -1):
		if out.size() >= TOASTS_MAX:
			break
		out.append(str(_local[j][0]))
	return "\n".join(out)


## Что выбрано и чем занято: «Выбрано: 3 · идут», имена — до четырёх.
func _sel_text(b: Object) -> String:
	var sel: Array[int] = view.get("selection")
	var my_side: int = view.get("my_side")
	if sel.is_empty():
		return "Ничего не выбрано · ЛКМ — выбрать, протяжка — рамка\nB — подкрепление · Пробел — пауза · 1, 2, 4 — скорость"
	var names := PackedStringArray()
	var own := 0
	var acts: Dictionary[String, int] = {}
	for u in sel:
		var s: Ship = b.call("ship_by_uid", u)
		if s == null or s.dead:
			continue
		if names.size() < 4:
			names.append(s.name)
		if s.side == my_side:
			own += 1
			var a := doing(s)
			var c: int = acts.get(a, 0)
			acts[a] = c + 1
	var head := "Выбрано: %d" % sel.size() if own > 0 else "Противник"
	var act_list := PackedStringArray()
	for a: String in acts:
		act_list.append(a if acts.size() == 1 else "%s %d" % [a, acts[a]])
	var more := "" if sel.size() <= names.size() else ", …"
	var line := "%s — %s%s" % [head, ", ".join(names), more]
	if not act_list.is_empty():
		line += "\n" + ", ".join(act_list)
	if own > 0:
		line += "\nПКМ — лететь · H или S — встать · G — гипер · D — дрифт · B — подкрепление · Пробел — пауза"
	return line


## Чем занят свой корабль — одной строкой.
static func doing(s: Ship) -> String:
	if s.charging():
		return "копит гипер %d с" % ceili(s.hyper_left)
	if s.drift:
		return "дрейф"
	if s.has_move:
		return "идёт в точку"
	if s.vel.length() > 3.0:
		return "тормозит" if s.stance == &"hold" else "идёт на участок"
	return "стоит"
