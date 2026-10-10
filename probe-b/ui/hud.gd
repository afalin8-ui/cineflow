## Проба интерфейса: шапка, сетка команд, ростер, лента, меню паузы, вопрос.
## Всё собирается кодом — чтобы проба была одним файлом.
class_name ProbeHud
extends CanvasLayer

signal command(id: String)
signal field_click(pos: Vector2, button: int)

const CMDS := [["stop", "Стоп"], ["hold", "Держать"], ["guard", "Охрана"], ["hunt", "Охота"],
	["retreat", "Отход"], ["drift", "Дрифт"], ["int", "Перехватчик"], ["fig", "Истребитель"],
	["bomb", "Бомбардировщик"], ["hyper", "Гипер"], ["ecm", "Купол"], ["focus", "Фокус"]]

var root: Control
var top: PanelContainer
var bottom: PanelContainer
var grid: GridContainer
var roster: HBoxContainer
var feed: VBoxContainer
var pause_layer: CanvasLayer
var pause_panel: Control
var confirm: ConfirmationDialog
var buttons := {}        # id -> Button (обновляются НА МЕСТЕ, C30)
var pressed_log: Array = []
var rebuild_each_refresh := false   # проба ловушки C30
var theme_: Theme

func _ready() -> void:
	layer = 10
	theme_ = Theme.new()
	theme_.default_font_size = 15
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.11, 0.92)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6; sb.content_margin_right = 6
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	theme_.set_stylebox("panel", "PanelContainer", sb)
	root = Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE     # растянутое — прозрачно (C135)
	root.theme = theme_
	add_child(root)
	_top()
	_bottom()
	_roster()
	_feed()
	_pause()
	_confirm()

func _btn(id: String, text: String) -> Button:
	var b := Button.new()
	b.name = "btn_" + id
	b.text = text
	b.focus_mode = Control.FOCUS_NONE       # Пробел не нажимает её снова (ловушка 30)
	b.tooltip_text = "Команда: " + text
	b.custom_minimum_size = Vector2(96, 34)
	b.pressed.connect(func(): pressed_log.append(id); command.emit(id))
	return b

func _top() -> void:
	top = PanelContainer.new()
	top.name = "Top"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(top)
	var hb := HBoxContainer.new()
	top.add_child(hb)
	for sp in [["pause", "Пауза"], ["x1", "1×"], ["x2", "2×"], ["x4", "4×"], ["reinf", "Подкрепление"]]:
		var b := _btn(sp[0], sp[1])
		b.custom_minimum_size = Vector2(60, 30)
		hb.add_child(b)
		buttons[sp[0]] = b
	var title := Label.new()
	title.text = "Бой на орбите · Тройден против Плэктора"
	hb.add_child(title)

func _bottom() -> void:
	bottom = PanelContainer.new()
	bottom.name = "Bottom"
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position = Vector2(-640, -120)
	root.add_child(bottom)
	grid = GridContainer.new()
	grid.columns = 6
	bottom.add_child(grid)
	_fill_grid()

func _fill_grid() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for c in CMDS:
		var b := _btn(c[0], c[1])
		if c[1].length() > 10:
			b.add_theme_font_size_override("font_size", 12)   # длинное — мельче, не «…» (ловушка 6)
		grid.add_child(b)
		buttons[c[0]] = b

## Обновление панели раз в треть секунды: на месте, пересборка — только при смене состава
func refresh() -> void:
	if rebuild_each_refresh:
		_fill_grid()     # так делать НЕЛЬЗЯ (C30) — проба ловушки
	else:
		for id in buttons:
			var b: Button = buttons[id]
			b.disabled = false

func _roster() -> void:
	roster = HBoxContainer.new()
	roster.name = "Roster"
	roster.anchor_left = 0.0; roster.anchor_right = 1.0
	roster.anchor_top = 1.0; roster.anchor_bottom = 1.0
	roster.offset_left = 12; roster.offset_right = -12
	roster.offset_top = -250; roster.offset_bottom = -210   # над нижней панелью, постоянная высота
	roster.mouse_filter = Control.MOUSE_FILTER_IGNORE   # пустая полоса — поле (C135)
	root.add_child(roster)
	for k in ["Корвет ×7", "Фрегат ×7", "РЭБ ×3", "Крейсер ×5", "Флагман ×4", "Носитель ×4"]:
		var b := _btn("roster_" + k.split(" ")[0], k)
		b.custom_minimum_size = Vector2(120, 36)
		roster.add_child(b)

func _feed() -> void:
	feed = VBoxContainer.new()
	feed.name = "Feed"
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.position = Vector2(16, 400)
	root.add_child(feed)
	feed.process_mode = Node.PROCESS_MODE_ALWAYS

func add_feed(text: String) -> void:
	var l := Label.new()
	l.text = text
	feed.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

func _pause() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 60
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_layer.visible = false
	add_child(pause_layer)
	pause_panel = ColorRect.new()
	pause_panel.name = "PauseDim"
	(pause_panel as ColorRect).color = Color(0, 0, 0, 0.5)
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP      # окно глотает мышь целиком
	pause_panel.theme = theme_
	pause_layer.add_child(pause_panel)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.add_child(vb)
	for c in [["resume", "Продолжить"], ["restart", "Начать заново"], ["leave", "Выйти в меню"]]:
		var b := _btn(c[0], c[1])
		b.custom_minimum_size = Vector2(220, 40)
		vb.add_child(b)
		buttons[c[0]] = b

func _confirm() -> void:
	confirm = ConfirmationDialog.new()
	confirm.title = "Отход"
	confirm.dialog_text = "Увести флот в гипер? Бой будет проигран."
	confirm.ok_button_text = "Отходим"
	confirm.cancel_button_text = "Остаёмся"
	confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(confirm)

func show_pause(on: bool) -> void:
	pause_layer.visible = on
	get_tree().paused = on
