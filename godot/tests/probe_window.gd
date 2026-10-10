# tests/probe_window.gd — канарейка ловушки «размер окна до первого кадра».
# Отдельный короткий процесс, а не тест прогонщика: ловушку видно только ДО первого
# кадра, а прогонщик зовёт тесты, когда кадры уже прошли (откат «без await» там
# оставался зелёным). Запускает её tests/test_ui_window.gd:
#   godot --headless --path godot -s res://tests/probe_window.gd -- raw|hooks <файл итога>
# raw   — размер задаём прямо в _initialize: после кадров он ОТКАТЫВАЕТСЯ к 64×64.
#         Перестал откатываться — ловушки в этой версии Godot нет, заметку пора править;
# hooks — зовём hooks.set_window_size прямо из _initialize: помощник обязан сам
#         дождаться первого кадра и удержать размер (откат: без первого await — 64×64).
extends SceneTree

const Hooks := preload("res://tests/hooks.gd")
const WANT := Vector2i(1366, 768)
const FRAMES := 6

var mode := ""
var out := ""
var frame := 0
var at_init := Vector2i.ZERO
var assigned := Vector2i.ZERO
var hooks_ret := Vector2i.ZERO


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	mode = args[0] if args.size() > 0 else ""
	out = args[1] if args.size() > 1 else ""
	at_init = root.size
	if mode == "raw":
		root.size = WANT
		assigned = root.size
	elif mode == "hooks":
		_by_hooks()          # без await: помощник засыпает на своём первом await


func _by_hooks() -> void:
	hooks_ret = await Hooks.new(self).set_window_size(WANT)


func _process(_delta: float) -> bool:
	frame += 1
	if frame < FRAMES:
		return false
	var res := {"mode": mode, "at_init": var_to_str(at_init), "assigned": var_to_str(assigned),
		"hooks_ret": var_to_str(hooks_ret), "final": var_to_str(root.size), "frames": frame}
	var line := JSON.stringify(res)
	print("PROBE ", line)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(line)
			f.close()
	return true
