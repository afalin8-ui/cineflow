# Размер окна (архитектура, 8.3; план G0 п. 3): ловушка «заданный до первого кадра
# размер откатывается к 64×64» и помощник hooks.set_window_size, который её обходит.
# Ловушку видно только до первого кадра, а прогонщик зовёт тесты позже, — поэтому
# канарейка идёт ОТДЕЛЬНЫМ процессом (tests/probe_window.gd), по процессу на режим.
extends "res://tests/case.gd"

const WANT := "Vector2i(1366, 768)"
const PROBE_WAIT_MS := 30000


## Запустить канарейку в своём процессе и вернуть её итог (пусто — не дождались).
func _probe(mode: String) -> Dictionary:
	var out := ProjectSettings.globalize_path("user://probe_window_%s.json" % mode)
	DirAccess.remove_absolute(out)
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/probe_window.gd", "--", mode, out])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if not ok(pid > 0, "канарейка %s запустилась" % mode):
		return {}
	var t0 := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - t0 < PROBE_WAIT_MS:
		await hooks.frames(1)
	if OS.is_process_running(pid):
		OS.kill(pid)                      # только свой PID, никакого pkill
		ok(false, "канарейка %s зависла (> %d мс)" % [mode, PROBE_WAIT_MS])
		return {}
	var text := FileAccess.get_file_as_string(out)
	DirAccess.remove_absolute(out)
	var j := JSON.new()
	if not ok(j.parse(text) == OK and typeof(j.data) == TYPE_DICTIONARY, "канарейка %s оставила итог: «%s»" % [mode, text]):
		return {}
	return dict(j.data)


func test_trap_before_first_frame_is_real() -> void:
	# канарейка: если Godot перестанет откатывать размер, это и есть новость —
	# заметку в godot/CLAUDE.md (9) и архитектуре (8.3, 12) пора править
	var r := await _probe("raw")
	if r.is_empty():
		return
	eq(str(r["at_init"]), "Vector2i(100, 100)", "в _initialize окно 100×100")
	eq(str(r["assigned"]), WANT, "присвоенный в _initialize размер сразу виден")
	eq(str(r["final"]), "Vector2i(64, 64)", "…а после первого кадра откатился к 64×64 (ловушка жива)")


func test_hooks_size_holds_even_from_initialize() -> void:
	# откат: убрать в hooks.set_window_size первый await — здесь 64×64
	var r := await _probe("hooks")
	if r.is_empty():
		return
	eq(str(r["hooks_ret"]), WANT, "set_window_size, позванный из _initialize, вернул заданный размер")
	eq(str(r["final"]), WANT, "и размер удержался через кадры")


func test_size_holds_in_runner() -> void:
	# в прогонщике кадры уже прошли — здесь проверяется только, что размер держится
	var got := await hooks.set_window_size(Vector2i(1366, 768))
	eq(got, Vector2i(1366, 768), "размер окна задан")
	await hooks.frames(3)
	eq(tree.root.size, Vector2i(1366, 768), "и удержался через три кадра")
