# ui/bench_report.gd — итог замера кадров на экране: текст, который уже лежит
# в буфере обмена, и три кнопки — «Скопировать ещё раз», «Открыть папку»
# (там файл с каждым кадром, по желанию) и «Закрыть». Пока идёт замер —
# строка «Замер кадров: N с из 60» вверху по центру.
# Правила интерфейса (00, 6.2–6.4): раскладочные узлы — IGNORE, кнопки —
# FOCUS_NONE (иначе Пробел жмёт последнюю нажатую ещё раз), окно — STOP целиком.
extends CanvasLayer

var panel: PanelContainer
var text_label: Label
var file_label: Label
var copy_btn: Button
var open_btn: Button
var close_btn: Button
var progress: Label
var summary := ""
var file := ""
## Сколько раз нажата каждая кнопка — для сканера кнопок в тестах.
var presses: Dictionary[String, int] = {}
## Тесты: кнопки нажимаются, но папка не открывается (в xvfb это запустило бы
## файловый менеджер) и буфер не трогается.
var dry := false


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	progress = Label.new()
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_theme_font_size_override("font_size", 18)
	progress.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	progress.position.y = 14
	progress.visible = false
	add_child(progress)

	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.94)
	sb.border_color = Color(0.35, 0.55, 0.8, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := Label.new()
	head.text = "Замер готов. Итог уже в буфере обмена — вставьте его в чат (Ctrl+V)."
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_font_size_override("font_size", 17)
	box.add_child(head)
	text_label = Label.new()
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.add_theme_font_size_override("font_size", 16)
	text_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	box.add_child(text_label)
	file_label = Label.new()
	file_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	file_label.add_theme_font_size_override("font_size", 13)
	file_label.modulate = Color(1, 1, 1, 0.6)
	file_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	file_label.custom_minimum_size = Vector2(560, 0)
	box.add_child(file_label)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	copy_btn = _button(row, "Скопировать ещё раз", _copy)
	open_btn = _button(row, "Открыть папку", _open)
	close_btn = _button(row, "Закрыть", hide_report)
	panel.visible = false
	add_child(panel)


func _button(row: HBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(func() -> void:
		var c: int = presses.get(text, 0)
		presses[text] = c + 1
		cb.call())
	row.add_child(b)
	return b


func show_progress(t: float, total: float) -> void:
	progress.visible = true
	progress.text = "Замер кадров: %d с из %d · не трогайте мышь и клавиши · F5 — прервать" % [int(t), int(total)]
	progress.reset_size()
	progress.position.x = (get_viewport().get_visible_rect().size.x - progress.size.x) * 0.5


func hide_progress() -> void:
	progress.visible = false


func show_report(p_summary: String, p_file: String) -> void:
	summary = p_summary
	file = p_file
	text_label.text = summary
	file_label.text = ("Каждый кадр — в файле: %s" % file) if file != "" else "Файл записать не удалось — хватит и текста выше."
	open_btn.disabled = file == ""
	panel.visible = true
	panel.reset_size()
	var vs := get_viewport().get_visible_rect().size
	panel.position = ((vs - panel.size) * 0.5).floor()


func hide_report() -> void:
	panel.visible = false


func is_open() -> bool:
	return panel.visible


func _copy() -> void:
	if not dry and DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(summary)


func _open() -> void:
	if not dry and file != "" and DisplayServer.get_name() != "headless":
		OS.shell_open(file.get_base_dir())
