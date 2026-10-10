# ui/frame_bench.gd — минута замера кадров (план G0, п. 7; критерий 3 раздела 0).
# F5 или `-- --bench-render`: 60 с облёта «Стола» по заданному пути камеры (в нём
# и рабочий вид 2400, и дальний предел 5000), время КАЖДОГО кадра — в файл рядом
# с программой (нельзя писать — в user://). Итог — коротким текстом на экране
# и в буфере обмена: его и вставляют в чат (пользователь не разработчик, файл
# в %APPDATA% он не найдёт — 00, 9.2).
# На время замера вертикальная синхронизация выключена: иначе кадр «прилипает»
# к частоте экрана, и на мониторе 60 Гц любой кадр выходит 16,7 ± дрожь —
# половина кадров «дольше 16,7» просто от дрожи часов, а не от нагрузки.
extends Node

signal finished(summary: String, file: String)

const STEP_MS := 16.7

var duration := 60.0
## Куда класть файл; пусто — рядом с программой, если можно, иначе user://.
var out_dir := ""
## Кто ведёт камеру: drive(t) на каждой секунде пути.
var driver: Callable
var title := ""
var extra_line := ""

var running := false
var elapsed := 0.0
var _ms := PackedFloat32Array()
var _draws := PackedInt32Array()
var _last_us := 0
var _vsync := DisplayServer.VSYNC_ENABLED


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start() -> void:
	running = true
	elapsed = 0.0
	_ms.clear()
	_draws.clear()
	_last_us = Time.get_ticks_usec()
	_vsync = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if driver.is_valid():
		driver.call(0.0)


func cancel() -> void:
	if not running:
		return
	running = false
	DisplayServer.window_set_vsync_mode(_vsync)


func _process(_delta: float) -> void:
	if not running:
		return
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	_ms.append(ms)
	# вызовы отрисовки — за ВЕСЬ прошлый кадр (часть 07, ловушка 62)
	_draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	elapsed += ms / 1000.0
	if driver.is_valid():
		driver.call(minf(elapsed, duration))
	if elapsed >= duration:
		_finish()


func _finish() -> void:
	running = false
	DisplayServer.window_set_vsync_mode(_vsync)
	var text := summary()
	var file := _write(text)
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(text)
	finished.emit(text, file)


## Итог по замеру: 8–9 строк для чата.
func summary() -> String:
	var n := _ms.size()
	var sorted := _ms.duplicate()
	sorted.sort()
	var fast := 0
	for v in _ms:
		if v <= STEP_MS:
			fast += 1
	var p99 := sorted[clampi(ceili(n * 0.99) - 1, 0, n - 1)] if n > 0 else 0.0
	var worst := sorted[n - 1] if n > 0 else 0.0
	var dsum := 0
	var dmax := 0
	for d in _draws:
		dsum += d
		dmax = maxi(dmax, d)
	var davg := roundi(float(dsum) / maxi(_draws.size(), 1))
	var size := get_viewport().get_visible_rect().size
	var mode := DisplayServer.window_get_mode()
	var full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var lines := PackedStringArray([
		"%s · замер кадров, %d с" % [title, roundi(duration)],
		"Видеокарта: %s" % gpu_name(),
		"Отрисовщик: %s" % renderer_name(),
		"Окно: %d × %d%s" % [int(size.x), int(size.y), ", полный экран" if full else ""],
		"Кадров: %d (в среднем %s в секунду)" % [n, _num(n / maxf(elapsed, 0.001), 0)],
		"Кадров не дольше 16,7 мс: %s%%" % _num(100.0 * fast / maxi(n, 1), 1),
		"99%% кадров не дольше %s мс, худший кадр %s мс" % [_num(p99, 1), _num(worst, 1)],
		"Вызовов отрисовки за кадр: в среднем %d, наибольшее %d" % [davg, dmax],
	])
	if extra_line != "":
		lines.append(extra_line)
	return "\n".join(lines)


## Склонение после числа: 1 корабль, 3 корабля, 83 корабля, 11 кораблей.
static func plural(n: int, one: String, few: String, many: String) -> String:
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return one
	if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14):
		return few
	return many


static func gpu_name() -> String:
	var n := RenderingServer.get_video_adapter_name()
	var v := RenderingServer.get_video_adapter_vendor()
	if n == "":
		return "не определилась"
	return n if v == "" or n.containsn(v) else "%s (%s)" % [n, v]


static func renderer_name() -> String:
	var m := RenderingServer.get_current_rendering_method()
	var d := RenderingServer.get_current_rendering_driver_name()
	var mn: String = {"forward_plus": "Forward+", "gl_compatibility": "Compatibility", "mobile": "Mobile"}.get(m, m)
	var dn: String = {"vulkan": "Vulkan", "d3d12": "Direct3D 12", "opengl3": "OpenGL 3", "metal": "Metal"}.get(d, d)
	return "%s (%s)" % [mn, dn]


## Число с запятой: «98,7», а не «98.7» (числа — форматом, не str(); 07, 5.2).
static func _num(v: float, digits: int) -> String:
	var fmt := "%." + str(digits) + "f"
	return (fmt % v).replace(".", ",")


## Папка для файла замера: рядом с программой, если туда можно писать.
func folder() -> String:
	if out_dir != "":
		return out_dir
	if OS.has_feature("template"):
		var exe_dir := OS.get_executable_path().get_base_dir()
		var probe := exe_dir.path_join(".capella_write_test")
		var f := FileAccess.open(probe, FileAccess.WRITE)
		if f != null:
			f.close()
			DirAccess.remove_absolute(probe)
			return exe_dir
	return ProjectSettings.globalize_path("user://")


## Файл: строка на кадр (номер, мс, вызовы отрисовки), в начале — итог.
func _write(text: String) -> String:
	var dir := folder()
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var path := dir.path_join("capella_frames_%s.csv" % stamp)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		path = ProjectSettings.globalize_path("user://").path_join("capella_frames_%s.csv" % stamp)
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	for l in text.split("\n"):
		f.store_line("# " + l)
	f.store_line("frame,ms,draw_calls")
	for i in _ms.size():
		f.store_line("%d,%.3f,%d" % [i, _ms[i], _draws[i]])
	f.close()
	return path


func frame_count() -> int:
	return _ms.size()
