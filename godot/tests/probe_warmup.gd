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


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "warm"
	var out := args[1] if args.size() > 1 else ""
	await process_frame
	root.size = Vector2i(640, 360)
	await process_frame
	var defs := Defs.load_default({}) as Defs
	var sc := Showcase.new()
	root.add_child(sc)
	sc.setup(defs, mode != "cold")
	for i in 20:
		await process_frame
	var before := compilations()
	for i in 70:
		sc.drive(float(i) * 0.85)
		await process_frame
	var after := compilations()
	var res := {"mode": mode, "before": before, "after": after, "renderer": RenderingServer.get_current_rendering_method()}
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(res))
			f.close()
	print("WARMUP ", JSON.stringify(res))
	quit(0)
