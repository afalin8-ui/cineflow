# Отдельный процесс для обёртки (run_tests.sh, «математика Windows-сборки»): показательный бой
# «Полигона» и 60 с «ИИ против ИИ» — как в --selftest — и их отпечатки строкой «FMATH …».
# Аргумент libm — считать углы библиотекой C, как до пакета GТ (Fmath.rollback_libm): откат.
extends SceneTree

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Polygon := preload("res://tools/polygon.gd")
const QuickMenu := preload("res://ui/quick_menu.gd")
const MainScript := preload("res://main.gd")
const Fmath := preload("res://sim/fmath.gd")


func _initialize() -> void:
	var libm := OS.get_cmdline_user_args().has("libm")
	Fmath.rollback_libm = libm
	var d := Defs.load_default() as Defs
	var rec := Polygon.make_record(d, "capella-проба")
	var ab := Battle.create(d, Polygon.quick_setup(QuickMenu.default_cfg(d, true), Polygon.SEED), "capella-проба") as Battle
	for i in MainScript.AI_SELFTEST_STEPS:
		ab.step()
	print("FMATH %s бой %s ИИ %s" % ["libm" if libm else "свои", str(rec["fp"]), ab.fingerprint()])
	ab.dispose()
	Fmath.rollback_libm = false
	quit(0)
