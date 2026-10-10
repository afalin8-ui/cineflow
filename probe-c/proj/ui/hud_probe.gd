extends CanvasLayer
## Проба интерфейса боя: шапка, ростер во всю ширину, сетка команд, окно
## вопроса. Правила: контейнеры — IGNORE, ловят только кнопки (C135);
## кнопки HUD без фокуса (ловушка 30); панель обновляется НА МЕСТЕ (C30).
signal command(id: String)

var rebuild_each_refresh := false     # откат C30: пересобирать кнопки
var pressed_count := {}               # кто сколько раз нажат (журнал для стенда)
var refresh_n := 0
var grid: GridContainer
var roster: HBoxContainer
var confirm: ConfirmationDialog
var focus_btn: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # интерфейс живёт и на паузе
	var root := Control.new(); root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := HBoxContainer.new(); top.name = "TopBar"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE); top.custom_minimum_size.y = 40
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var title := Label.new(); title.text = "Быстрый бой · орбита"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)                  # у Label по умолчанию IGNORE
	top.add_child(_btn("speed1", "1×"))
	top.add_child(_btn("pause", "Пауза"))
	roster = HBoxContainer.new(); roster.name = "Roster"
	roster.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	roster.offset_top = -200; roster.offset_bottom = -160
	roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roster.add_theme_constant_override("separation", 30)
	root.add_child(roster)
	for k in ["Корвет ×2", "Фрегат ×2", "Крейсер"]: roster.add_child(_btn("roster_" + k, k))
	grid = GridContainer.new(); grid.name = "Commands"; grid.columns = 5
	grid.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grid.offset_left = -560; grid.offset_top = -150; grid.offset_right = -250; grid.offset_bottom = -10
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grid)
	_fill_grid()
	focus_btn = _btn("focus_default", "Фокус по умолчанию")
	focus_btn.focus_mode = Control.FOCUS_ALL      # как у Godot по умолчанию — для отката
	focus_btn.position = Vector2(40, 300)
	root.add_child(focus_btn)
	confirm = ConfirmationDialog.new(); confirm.name = "Ask"
	confirm.dialog_text = "Отход из боя? За носителем уходит весь флот."
	confirm.title = "Вопрос"
	confirm.confirmed.connect(func(): _hit("ask_yes"))
	confirm.canceled.connect(func(): _hit("ask_no"))
	add_child(confirm)
	var t := Timer.new(); t.wait_time = 0.34; t.autostart = true; t.process_mode = Node.PROCESS_MODE_ALWAYS
	t.timeout.connect(refresh); add_child(t)

func _btn(id: String, text: String) -> Button:
	var b := Button.new(); b.name = id.replace(" ", "_"); b.text = text; b.set_meta("id", id)
	b.focus_mode = Control.FOCUS_NONE             # ловушка 30 (C28)
	b.pressed.connect(func(): _hit(id))
	return b

func _hit(id: String) -> void:
	pressed_count[id] = pressed_count.get(id, 0) + 1
	command.emit(id)

func _fill_grid() -> void:
	for id in ["Стоп", "Держать", "Охрана", "Охота", "Выше", "Ниже", "Дрифт", "Гипер", "Перехватчик", "Бомбардировщик"]:
		grid.add_child(_btn("cmd_" + id, id))

## Обновление панели раз в 0,34 с: на месте (текст), а не пересборкой.
func refresh() -> void:
	refresh_n += 1
	if rebuild_each_refresh:
		for c in grid.get_children(): grid.remove_child(c); c.queue_free()
		_fill_grid()
	else:
		var b: Button = grid.get_node("cmd_Перехватчик")
		b.text = "Перехватчик" if refresh_n % 2 == 0 else "Перехватчик "
