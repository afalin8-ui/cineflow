# ui/fps_counter.gd — счётчик кадров по F3 (часть 07, ловушка 62; план G0 п. 7).
# Кадры в секунду, худший кадр за последние 0,5 с, вызовы отрисовки за ВЕСЬ
# кадр, какой отрисовщик поднялся, видеокарта и размер окна. Минута замера по F5
# и итог текстом в буфер обмена — ui/frame_bench.gd и ui/bench_report.gd.
extends CanvasLayer

const FrameBench := preload("res://ui/frame_bench.gd")
const WINDOW_US := 500000             # окно «худшего кадра» — 0,5 с НАСТОЯЩЕГО времени

var panel: PanelContainer
var label: Label
var hint: Label
var shown := false
## Подсказка спрятана на время минуты замера: строка «Замер кадров…» вверху по центру
## на 1366 ложилась прямо на неё (замечание к G0b), а мышь и клавиши тогда всё равно
## не нужны.
var hint_blocked := false
# Длительность кадра — по часам Time.get_ticks_usec(), как в ui/frame_bench.gd,
# а НЕ по delta из _process: Godot урезает delta до 8 шагов физики (8/60 ≈ 133 мс),
# и рывок в 400 мс (сборка шейдера, откат отрисовщика) счётчик показал бы как 133
# (замечание к G0b: на одном экране F3 писал 149 мс, а файл замера — 861).
var _times: PackedFloat64Array = []   # длительности кадров за окно, мс
var _ends: PackedInt64Array = []      # когда кадр кончился, мкс
var _last_us := 0
var _refresh_us := 0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(12, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.82)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 15)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	add_child(panel)
	panel.visible = false
	hint = Label.new()
	hint.text = "F3 — счётчик кадров · F5 — минута замера кадров · F11 — окно / полный экран\nкамера: колесо — ближе и дальше, Q/E или правая кнопка — повернуть, стрелки и край экрана — сдвинуть"
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.55)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.position = Vector2(14, 14)
	add_child(hint)


## Подсказка клавиш — своя у каждого экрана («Полигон», «Стол»).
func set_hint_text(text: String) -> void:
	hint.text = text


func toggle() -> void:
	shown = not shown
	panel.visible = shown
	hint.visible = not shown and not hint_blocked
	_refresh_us = 0


## Спрятать подсказку на время замера кадров и вернуть после.
func block_hint(on: bool) -> void:
	hint_blocked = on
	hint.visible = not shown and not hint_blocked


func _input(event: InputEvent) -> void:
	# клавиша по месту, а не по букве (06, ловушка 49); повтор (echo) — не нажатие (06-27)
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == KEY_F3:
		toggle()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_times.append((now - _last_us) / 1000.0)
		_ends.append(now)
	_last_us = now
	while _ends.size() > 0 and now - _ends[0] > WINDOW_US:
		_ends.remove_at(0)
		_times.remove_at(0)
	if not shown or now < _refresh_us:
		return
	_refresh_us = now + 250000
	label.text = summary()


## Худший кадр за последние 0,5 с настоящего времени, мс.
func worst_ms() -> float:
	var w := 0.0
	for t in _times:
		w = maxf(w, t)
	return w


func summary() -> String:
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var size := get_viewport().get_visible_rect().size
	return "\n".join(PackedStringArray([
		"кадров в секунду: %d" % int(Engine.get_frames_per_second()),
		"худший кадр за 0,5 с: %s мс" % ("%.1f" % worst_ms()).replace(".", ","),
		"вызовов отрисовки за кадр: %d" % draws,
		"отрисовщик: %s" % FrameBench.renderer_name(),
		"видеокарта: %s" % FrameBench.gpu_name(),
		"окно: %d × %d" % [int(size.x), int(size.y)],
	]))
