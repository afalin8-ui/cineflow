## Точка входа выгруженной сборки: с «-- --bench …» гоняет бои без окна.
extends Node

const Runner = preload("res://tools/runner.gd")

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--bench"):
		print(JSON.stringify(Runner.run_from_args(args)))
		get_tree().quit()
