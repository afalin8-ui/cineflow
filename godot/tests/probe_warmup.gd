# Проба прогрева ОТДЕЛЬНЫМ процессом (07, ловушка 29; 08, ловушка 15; 08, 4.2 п. 3):
#   godot --path godot [--rendering-method …] -s res://tests/probe_warmup.gd -- warm|cold <файл итога>
# Строит «Стол», ждёт 20 кадров, запоминает счётчики сборок конвейеров, облетает
# стол по пути замера 70 кадров и пишет {before, after} в файл.
# warm — как в игре (всё, что рисуется, есть с первого кадра); cold — откат:
# пул эффектов заводится только на 30-м кадре.
# Почему отдельным процессом: конвейер, однажды собранный, живёт до конца процесса,
# и в общем прогоне откат «поздних эффектов» ничего бы не собрал — их шейдеры уже
# собрали тесты раньше. Свежий процесс — свежий кэш.
extends SceneTree

const Defs := preload("res://sim/defs.gd")
const Showcase := preload("res://tools/showcase.gd")


func _initialize() -> void:
	_run.call_deferred()


static func compilations() -> int:
	var n := 0
	for k: RenderingServer.RenderingInfo in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		n += RenderingServer.get_rendering_info(k)
	return n


## Ход пробы — строками «мс от запуска · что» в файл <итог>.log: зависла проба — тест показывает,
## на каком шаге (иначе «зависла» в CI — тупик: вывод отдельного процесса никуда не попадает).
var _log: FileAccess
var _t0 := 0


func _mark(what: String) -> void:
	if _log != null:
		_log.store_line("%d мс · %s" % [Time.get_ticks_msec() - _t0, what])
		_log.flush()


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "warm"
	var out := args[1] if args.size() > 1 else ""
	if out != "":
		_log = FileAccess.open(out + ".log", FileAccess.WRITE)
	_mark("запуск, %s, процессоров %d" % [RenderingServer.get_current_rendering_method(), OS.get_processor_count()])
	await process_frame
	root.size = Vector2i(640, 360)
	await process_frame
	var defs := Defs.load_default({}) as Defs
	var sc := Showcase.new()
	root.add_child(sc)
	_mark("данные, строю «Стол»")
	sc.setup(defs, mode != "cold")
	_mark("«Стол» построен: кораблей %d, машин %d" % [sc.ship_count(), sc.craft_count()])
	for i in 20:
		await process_frame
		if i == 0 or i == 19:
			_mark("кадр %d" % (i + 1))
	var before := compilations()
	for i in 70:
		sc.drive(float(i) * 0.85)
		await process_frame
		if i % 10 == 9:
			_mark("облёт, кадр %d" % (i + 1))
	var after := compilations()
	var res := {"mode": mode, "before": before, "after": after, "renderer": RenderingServer.get_current_rendering_method()}
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(res))
			f.close()
	print("WARMUP ", JSON.stringify(res))
	quit(0)
