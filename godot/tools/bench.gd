# tools/bench.gd — стенд из редактора (архитектура, 8.6): `godot --headless --path godot -s
# res://tools/bench.gd -- --load battle --n 25 --seed 1000 [--swap] [флажки отката]`.
# В выгруженной сборке `-s` нет — там `capella.x86_64 --headless -- --bench …` (main.gd).
# Всё — в tools/bench_core.gd; правки чисел — --set/--overrides (как у главной сцены).
extends SceneTree

const Defs := preload("res://sim/defs.gd")
const BenchCore := preload("res://tools/bench_core.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ov: Dictionary = Defs.overrides_from_args(args, PackedStringArray([OS.get_environment("PWD")]))
	var ov_errors: PackedStringArray = ov["errors"]
	var ov_values: Dictionary = ov["overrides"]
	var defs := Defs.load_default(ov_values) as Defs
	defs.errors.append_array(ov_errors)
	defs.ok = defs.errors.is_empty()
	var rel := FileAccess.get_file_as_string("res://RELEASE").get_slice("\n", 0).strip_edges()
	quit(BenchCore.main(defs, args, rel))
