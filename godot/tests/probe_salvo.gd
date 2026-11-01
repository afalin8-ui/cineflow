# Отдельный процесс для обёртки (run_tests.sh, «повтор боя с залпом»): пишет запись боя с приказами
# «Залп» орудия планеты игрока (Polygon.salvo_record — тот же бой, что в --selftest) файлом, и рядом —
# ту же запись БЕЗ приказов «Залп» (откат: повтор обязан разойтись). Аргументы: <файл> <файл без залпа>.
extends SceneTree

const Defs := preload("res://sim/defs.gd")
const Polygon := preload("res://tools/polygon.gd")
const MainScript := preload("res://main.gd")


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var d := Defs.load_default() as Defs
	var rec := Polygon.salvo_record(d, MainScript.release_name())
	var guns := 0
	var keep: Array = []
	var cmds: Array = rec["cmds"]
	for c: Dictionary in cmds:
		if str(c.get("op", "")) == "gun":
			guns += 1
		else:
			keep.append(c)
	var f := FileAccess.open(a[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(rec))
	f.close()
	var lost := rec.duplicate(true)
	lost["cmds"] = keep
	var g := FileAccess.open(a[1], FileAccess.WRITE)
	g.store_string(JSON.stringify(lost))
	g.close()
	print("SALVO записана: приказов «Залп» %d, залпов %d, шагов %d, отпечаток %s" % [guns, MainScript.whole(rec["salvos"]), MainScript.whole(rec["steps"]), str(rec["fp"])])
	quit(0)
