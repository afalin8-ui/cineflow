# tests/probe_tmp.gd — проба «у каждого прогона своя папка» (хвост G1). Запускает
# run_tests.sh ДВА раза разом, каждому — свой $CAPELLA_TMP, как двум прогонам обёртки:
#   godot --headless --path godot -s res://tests/probe_tmp.gd -- <папка встречи> <метка> [shared]
# Делает то же, что тесты с кадрами Movie Maker: чистит свою папку, пишет 20 файлов
# со своей меткой, ждёт, пока второй процесс тоже запишет (папка встречи — чтобы оба
# записали ДО того, как кто-то читает: без неё проверка зависела бы от скорости машины),
# и читает обратно. Чужая метка или пропавший файл — «clash», код 1.
# shared — откат: общая папка user://test_tmp, как было до правки; хоть один из двух
# обязан увидеть чужое.
extends SceneTree

const Case := preload("res://tests/case.gd")
const FILES := 20
const WAIT_MS := 30000


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("probe_tmp: нужны папка встречи и метка")
		quit(2)
		return
	var meet := args[0]
	var token := args[1]
	Case.rollback_shared_tmp = args.size() > 2 and args[2] == "shared"
	var dir := Case.tmp("probe_tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))          # как тесты: старые кадры прочь
	for i in FILES:
		var w := FileAccess.open(dir.path_join("f_%02d.txt" % i), FileAccess.WRITE)
		w.store_string(token)
		w.close()
	var mark := FileAccess.open(meet.path_join("written_" + token), FileAccess.WRITE)
	mark.store_string(token)
	mark.close()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < WAIT_MS:
		var n := 0
		for f in DirAccess.get_files_at(meet):
			if f.begins_with("written_"):
				n += 1
		if n >= 2:
			break
		OS.delay_msec(50)
	var own := 0
	for i in FILES:
		var p := dir.path_join("f_%02d.txt" % i)
		if FileAccess.file_exists(p) and FileAccess.get_file_as_string(p) == token:
			own += 1
	var good := own == FILES
	print("PROBE_TMP %s %s: своих файлов %d из %d (%s)" % ["ok" if good else "clash", token, own, FILES, dir])
	quit(0 if good else 1)
