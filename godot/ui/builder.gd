# ui/builder.gd — строитель интерфейса боя (архитектура, 6.1–6.4; план GИ, п. 1).
# - Мышь (00, 6.2): у Control, Panel, PanelContainer, ColorRect по умолчанию STOP, у
#   контейнеров PASS — пустая полоса между кнопками глотала бы щелчок по полю (C135).
#   finish() проходит дерево и ставит IGNORE всем, кто не кнопка и не помечен «ловит»
#   (панель выделенного, окно-вопрос), а кнопкам — STOP и FOCUS_NONE.
# - Фокус (00, 6.4): у Button по умолчанию FOCUS_ALL — щёлкнул мышью, а Пробел (пауза) жмёт
#   её ещё раз. У кнопок боя фокуса нет.
# - Вид кнопки — ОДНИМ методом (look): обычная, «горит» (у всех выбранных), «часть» (у
#   некоторых), недоступна. Наслоение стилей по месту разъехалось бы при первой правке.
# - Числа в текст — форматом, а не str() (00, 6.6).
extends RefCounted

## Цвета (07, 2.1): свои — мятные, чужие — красные; «горит» — акцент.
const OWN := Color(0.56, 1.0, 0.78)
const FOE := Color(1.0, 0.42, 0.35)
const ACCENT := Color(0.91, 0.64, 0.24)
const TEXT := Color(0.85, 0.92, 1.0)
const DIM := Color(0.6, 0.66, 0.74)
const BG := Color(0.03, 0.04, 0.07, 0.86)
const EDGE := Color(0.35, 0.55, 0.8, 0.6)

## Метка «этот узел ловит мышь» (панель, окно): finish() её не трогает.
const STOP_META := &"cf_stop"

## Вид кнопки.
enum Look { NORMAL, ON, PART, OFF }

## ТОЛЬКО для проверки отката (план GИ, обратный сканер пустых мест): строитель фильтров
## не ставит — у контейнеров остаётся PASS, у панелей STOP, и промежуток между кнопками
## ростера глотает щелчок по полю (C135). В игре false.
static var rollback_no_ignore := false


## Пройти дерево: кнопкам — STOP и без фокуса, помеченным — STOP, остальным — IGNORE.
static func finish(root: Node) -> void:
	if rollback_no_ignore:
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var c := n as Control
		if c != null:
			if c is BaseButton:
				c.mouse_filter = Control.MOUSE_FILTER_STOP
				c.focus_mode = Control.FOCUS_NONE
			elif c.has_meta(STOP_META):
				c.mouse_filter = Control.MOUSE_FILTER_STOP
			else:
				c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.append_array(n.get_children())


## Пометить узел «ловит мышь» (панель, окно): щелчок по нему до поля не доходит.
static func stop(c: Control) -> Control:
	c.set_meta(STOP_META, true)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


static func label(size: int, color: Color, text: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	return l


static func box(bg: Color, edge: Color, margin: float, radius: int = 6, width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


## Панель, которая ловит мышь (нижняя панель, окно).
static func panel(name: String, margin: float = 10.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = name
	p.add_theme_stylebox_override("panel", box(BG, EDGE, margin))
	stop(p)
	return p


## Кнопка боя: без фокуса, своим видом. text — надпись (у кнопок сетки — пусто, слова
## рисуют дочерние Label).
static func button(name: String, text: String, size: Vector2, font: int = 15) -> Button:
	var b := Button.new()
	b.name = name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.custom_minimum_size = size
	b.clip_text = false
	b.add_theme_font_size_override("font_size", font)
	look(b, Look.NORMAL)
	return b


## Вид кнопки — одним методом (архитектура, 6.1): рамка и цвет надписи по состоянию.
static func look(b: Button, how: Look) -> void:
	var edge := EDGE
	var bg := Color(0.05, 0.07, 0.11, 0.9)
	var fg := TEXT
	var w := 1
	match how:
		Look.ON:
			edge = ACCENT
			bg = Color(0.1, 0.08, 0.03, 0.92)
			fg = ACCENT
			w = 2
		Look.PART:
			edge = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55)
			fg = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85)
		Look.OFF:
			edge = Color(EDGE.r, EDGE.g, EDGE.b, 0.25)
			fg = Color(DIM.r, DIM.g, DIM.b, 0.55)
	var n := box(bg, edge, 4.0, 5, w)
	var h := box(bg.lightened(0.12), edge.lightened(0.25), 4.0, 5, w)
	var pr := box(bg.lightened(0.22), edge.lightened(0.35), 4.0, 5, w)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("disabled", n)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(k, fg)
	b.set_meta(&"cf_look", how)


## Ширина строки шрифтом узла (кэш не нужен: зовётся при смене надписи, а не каждый кадр).
static func text_w(c: Control, text: String, size: int) -> float:
	var f := c.get_theme_font("font")
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
