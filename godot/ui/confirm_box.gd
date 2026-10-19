# ui/confirm_box.gd — окно-вопрос экрана боя («Отступить всем флотом?»; план GИ: из G6 взято
# только оно — без вопроса «Отход» кнопка уводила бы флот одним случайным щелчком).
# Правила окна (06, 1.6 и 2.8; архитектура, 6.6): ставит бой на паузу и возвращает прежнюю
# скорость; подложка ловит мышь целиком (щелчок мимо окна до поля не доходит); пока открыто,
# окно глотает клавиши боя (кроме F3 и F11); Esc — «нет»; повтор Esc (echo) — не нажатие.
extends CanvasLayer

const Builder := preload("res://ui/builder.gd")

var back: ColorRect
var panel: PanelContainer
var text: Label
var yes_btn: Button
var no_btn: Button
## Вид боя — пауза на время вопроса.
var view: Node3D
var _cb: Callable
var _paused_before := false


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	back = ColorRect.new()
	back.name = "ConfirmBack"
	back.color = Color(0.0, 0.0, 0.02, 0.45)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	Builder.stop(back)
	add_child(back)
	panel = Builder.panel("ConfirmPanel", 18.0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	text = Builder.label(18, Builder.TEXT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	yes_btn = Builder.button("yes", "", Vector2(160.0, 38.0), 16)
	no_btn = Builder.button("no", "", Vector2(160.0, 38.0), 16)
	yes_btn.pressed.connect(_answer.bind(true))
	no_btn.pressed.connect(_answer.bind(false))
	row.add_child(yes_btn)
	row.add_child(no_btn)
	Builder.finish(self)
	_set_open(false)


func is_open() -> bool:
	return panel.visible


## Спросить: on_yes зовётся на «да». Бой на это время стоит.
func ask(msg: String, yes: String, no: String, on_yes: Callable) -> void:
	text.text = msg
	yes_btn.text = yes
	no_btn.text = no
	_cb = on_yes
	if view != null:
		_paused_before = view.get("paused")
		view.set("paused", true)
	_set_open(true)
	_place()


func _set_open(on: bool) -> void:
	back.visible = on
	panel.visible = on


func _answer(yes: bool) -> void:
	if not is_open():
		return
	_set_open(false)
	if view != null:
		view.set("paused", _paused_before)
	if yes and _cb.is_valid():
		_cb.call()
	_cb = Callable()


func _place() -> void:
	panel.reset_size()
	var vs := panel.get_viewport_rect().size
	panel.position = ((vs - panel.size) * 0.5).floor()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and panel != null and is_open():
		_place()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	var k := event as InputEventKey
	if k == null:
		return
	if k.physical_keycode in [KEY_F3, KEY_F11]:
		return
	if k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE:
		_answer(false)
	get_viewport().set_input_as_handled()
