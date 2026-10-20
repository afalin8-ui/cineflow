# ui/command_grid.gd — сетка команд (07, 1.8 и 2.10; план GИ, п. 5): каждая команда, которая
# раньше была только клавишей, — кнопкой со словом, мелкой строкой над ним («приказ»,
# «тактика», «ангар 3») и буквой клавиши в правом верхнем углу. Нажатие зовёт ту же дверь,
# что и клавиша (input/battle_input.gd → command).
# - КНОПКИ НЕ ПЕРЕСОЗДАЮТСЯ (C30; архитектура, 6.3): сетка пересобирается, только когда
#   сменился НАБОР команд (ключ — id через запятую); слово, мелкая строка, «горит»/«часть»,
#   «недоступна» — на месте. Иначе кнопка, пересозданная между нажатием и отпусканием,
#   теряет щелчок (проверено: медленный щелчок 150 мс и 9 кадров).
# - Длинное слово («Бомбардировщик», «Отменить гипер») — мельче, а не обрезано.
extends GridContainer

const Builder := preload("res://ui/builder.gd")
const Texts := preload("res://ui/texts.gd")

## ТОЛЬКО для проверки отката (C30): сетка пересобирается при каждом обновлении — медленный
## щелчок теряется. В игре false.
static var rollback_rebuild := false
## ТОЛЬКО для проверки отката: слово всегда кеглем 14 — длинное («Бомбардировщик») на узкой
## кнопке не помещается. В игре false.
static var rollback_word_14 := false

## Кнопок в ряду и зазор между ними (точки); ширину «что выбрано» считает от них экран боя.
const COLUMNS := 7
const GAP := 4.0

## Нажатие кнопки: on_press.call(id).
var on_press: Callable
## Подсказка (ui/hud_tooltip.gd): attach каждой новой кнопке.
var tooltip: Node
var buttons: Dictionary[StringName, Button] = {}
var key := ""
## Размер кнопки (точки) и сколько раз сетка пересобиралась (проверки).
var btn_size := Vector2(104.0, 46.0)
var rebuilds := 0


func _ready() -> void:
	columns = COLUMNS
	add_theme_constant_override("h_separation", roundi(GAP))
	add_theme_constant_override("v_separation", roundi(GAP))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Набор команд (порядок — ui/texts.gd → GRID_ORDER). Тот же набор — кнопки остаются.
func set_commands(ids: Array[StringName], size: Vector2) -> void:
	var k := ",".join(PackedStringArray(ids)) + "|%d" % roundi(size.x)
	if k == key and not rollback_rebuild:
		return
	key = k
	btn_size = size
	rebuilds += 1
	for id: StringName in buttons:
		var old := buttons[id]
		remove_child(old)
		old.queue_free()
	buttons.clear()
	for id in ids:
		var b := _make(id)
		add_child(b)
		buttons[id] = b
	Builder.finish(self)
	for id in ids:
		buttons[id].focus_mode = Control.FOCUS_NONE


func _make(id: StringName) -> Button:
	var b := Builder.button(str(id), "", btn_size)
	b.clip_contents = true
	var top := Builder.label(10, Builder.DIM)
	top.name = "top"
	top.position = Vector2(6.0, 3.0)
	top.size = Vector2(btn_size.x - 26.0, 13.0)
	top.clip_text = true
	top.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_child(top)
	var keyl := Builder.label(11, Color(1.0, 0.9, 0.65))
	keyl.name = "key"
	keyl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keyl.position = Vector2(btn_size.x - 26.0, 2.0)
	keyl.size = Vector2(21.0, 14.0)
	b.add_child(keyl)
	var word := Builder.label(14, Builder.TEXT)
	word.name = "word"
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	word.position = Vector2(2.0, 16.0)
	word.size = Vector2(btn_size.x - 4.0, btn_size.y - 18.0)
	b.add_child(word)
	b.pressed.connect(func() -> void:
		if on_press.is_valid():
			on_press.call(id))
	if tooltip != null:
		tooltip.call("attach", b)
	return b


## Слово, мелкая строка, вид и доступность кнопки — на месте (без пересоздания).
func update_cmd(id: StringName, word: String, top: String, how: Builder.Look) -> void:
	var b: Button = buttons.get(id)
	if b == null:
		return
	var wl := b.get_node("word") as Label
	var tl := b.get_node("top") as Label
	var kl := b.get_node("key") as Label
	if wl.text != word:
		wl.text = word
		wl.add_theme_font_size_override("font_size", word_size(word, btn_size.x - 8.0, wl))
	if tl.text != top:
		tl.text = top
	var k := Texts.cmd(id, "key")
	if kl.text != k:
		kl.text = k
	var off := how == Builder.Look.OFF
	b.disabled = off
	var was: int = b.get_meta(&"cf_look", -1)
	if was != how:
		Builder.look(b, how)
		var fg := Builder.ACCENT if how == Builder.Look.ON else (Color(Builder.DIM.r, Builder.DIM.g, Builder.DIM.b, 0.55) if off else Builder.TEXT)
		if how == Builder.Look.PART:
			fg = Color(Builder.ACCENT.r, Builder.ACCENT.g, Builder.ACCENT.b, 0.85)
		wl.add_theme_color_override("font_color", fg)
	b.set_meta(&"cf_tip", Texts.tip(id, word, off))


## Кегль слова: 14, длинное — мельче, пока не влезет (не меньше 10).
static func word_size(word: String, room: float, l: Control) -> int:
	if rollback_word_14:
		return 14
	for fs: int in [14, 13, 12, 11, 10]:
		if Builder.text_w(l, word, fs) <= room:
			return fs
	return 10
