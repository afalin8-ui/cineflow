## Бои «ИИ против ИИ» без окна и без сцены:
##   godot --headless --path . -s res://tools/bench.gd -- --load p30 --n 3 --seed 1
extends SceneTree

const Runner = preload("res://tools/runner.gd")

func _initialize() -> void:
	var out := Runner.run_from_args(OS.get_cmdline_user_args())
	print(JSON.stringify(out))
	quit()
