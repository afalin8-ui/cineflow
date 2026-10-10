# tests/run.gd — свой прогонщик (архитектура, 8.1). Ярусы:
#   godot --headless --path godot -s res://tests/run.gd -- sim     модель, данные
#   godot --headless --path godot -s res://tests/run.gd -- ui      ввод и интерфейс без окна
#   xvfb-run … -s res://tests/run.gd -- render                     картинка (G0b)
# Вторым словом можно дать часть имени файла, третьим — часть имени функции:
# `-- sim defs`, `-- render table bench_progress` (для отладки одной проверки).
# Последняя строка вывода — RESULT checks=N fails=M; её нет — прогон провален
# (tools/run_tests.sh). Ни одной проверки — тоже провал: тест, который ничего
# не проверил, ничего и не охраняет.
#
# Счётчики — поля, а не локальные: прогон идёт через await, и так проще
# видеть итог из любого места.
extends SceneTree

const Case := preload("res://tests/case.gd")
const Hooks := preload("res://tests/hooks.gd")

var _checks := 0
var _fails := 0
var _files := 0
var _test: Case
var _fn_only := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var tier := args[0] if args.size() > 0 else "sim"
	var only := args[1] if args.size() > 1 else ""
	_fn_only = args[2] if args.size() > 2 else ""
	var names: PackedStringArray = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_%s_" % tier) and f.ends_with(".gd") and (only == "" or f.contains(only)):
			names.append(f)
	names.sort()
	var t0 := Time.get_ticks_msec()
	for f in names:
		await _run_file(f)
	if names.is_empty():
		printerr("ПРОВАЛ: нет тестов яруса «%s»" % tier)
		_fails += 1
	print("%s: %d файлов, %.1f с" % [tier, _files, (Time.get_ticks_msec() - t0) / 1000.0])
	print("RESULT checks=%d fails=%d" % [_checks, _fails])
	quit(1 if _fails > 0 or _checks == 0 else 0)


func _run_file(f: String) -> void:
	_files += 1
	var script := load("res://tests/" + f) as GDScript
	if script == null or not script.can_instantiate():
		printerr("ПРОВАЛ %s: тест не собирается" % f)
		_fails += 1
		return
	var inst: Object = script.new()
	_test = inst as Case
	if _test == null:
		printerr("ПРОВАЛ %s: тест не наследует tests/case.gd" % f)
		_fails += 1
		return
	_test.tree = self
	_test.hooks = Hooks.new(self)
	_test.started = Time.get_ticks_msec()
	for m: Dictionary in script.get_script_method_list():
		var mname: String = m["name"]
		if mname.begins_with("test_") and (_fn_only == "" or mname.contains(_fn_only)):
			_test.current = "%s · %s" % [f.get_basename(), mname]
			await _test.call(mname)
	print("%-34s проверок %4d, провалов %d, %d мс" % [f.get_basename(), _test.checks, _test.fails, Time.get_ticks_msec() - _test.started])
	_checks += _test.checks
	_fails += _test.fails
