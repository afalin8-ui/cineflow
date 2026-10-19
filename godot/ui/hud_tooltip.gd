# ui/hud_tooltip.gd — своя подсказка кнопок экрана боя (архитектура, 6.6; 07, 1.8): СРАЗУ при
# наведении (штатная ждёт 0,5 с и за край экрана не следит), над кнопкой, в пределах экрана.
# Текст — из метки кнопки "cf_tip" (её держит актуальной тот, кто ведёт кнопку: слово,
# буква, «сейчас недоступно»), поэтому подсказка над нажатой кнопкой не врёт после нажатия.
extends CanvasLayer

const Builder := preload("res://ui/builder.gd")

const MAX_W := 320.0
const GAP := 8.0

var panel: PanelContainer
var label: Label
## Над какой кнопкой стоит (null — спрятана).
var over: Control
## ТОЛЬКО для проверки отката (07, 1.8: подсказка СРАЗУ): как штатная — через 0,5 с. В игре false.
static var rollback_delay := false
var _since := 0


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "Tooltip"
	panel.add_theme_stylebox_override("panel", Builder.box(Color(0.02, 0.03, 0.05, 0.95), Color(0.5, 0.65, 0.85, 0.8), 8.0))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	add_child(panel)
	label = Builder.label(14, Builder.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	panel.add_child(label)


## Повесить подсказку на кнопку: наведение — показать сразу, уход и нажатие — спрятать.
func attach(b: Control) -> void:
	b.mouse_entered.connect(func() -> void: show_for(b))
	b.mouse_exited.connect(func() -> void: hide_for(b))
	var bb := b as BaseButton
	if bb != null:
		bb.button_down.connect(func() -> void: hide_for(b))


func show_for(b: Control) -> void:
	over = b
	_since = Time.get_ticks_msec()
	refresh()


func hide_for(b: Control) -> void:
	if over == b:
		over = null
		panel.visible = false


## Текст и место — по нынешней метке кнопки (зовёт экран боя каждый кадр, пока видна).
func refresh() -> void:
	if over == null or not is_instance_valid(over) or not over.is_visible_in_tree():
		over = null
		panel.visible = false
		return
	var text := str(over.get_meta(&"cf_tip", ""))
	if rollback_delay and Time.get_ticks_msec() - _since < 500:
		text = ""
	if text == "":
		panel.visible = false
		return
	if label.text != text:
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size = Vector2.ZERO
		panel.reset_size()
		if panel.size.x > MAX_W:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size = Vector2(MAX_W - 16.0, 0.0)
			label.size = Vector2(MAX_W - 16.0, 0.0)
		panel.reset_size()
	panel.visible = true
	var vs := panel.get_viewport_rect().size
	var r := over.get_global_rect()
	var x := clampf(r.get_center().x - panel.size.x * 0.5, 6.0, vs.x - panel.size.x - 6.0)
	var y := r.position.y - panel.size.y - GAP
	if y < 6.0:
		y = r.end.y + GAP                 # у верхнего края (шапка) — под кнопкой
	panel.position = Vector2(x, y).floor()
