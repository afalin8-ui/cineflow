# Отдельный процесс для обёртки (run_tests.sh, «математика Windows-сборки»): показательный бой
# «Полигона», 60 с «ИИ против ИИ», «ИИ против ИИ» с орудием планеты и бой с залпами игрока — как
# в --selftest — и их отпечатки строкой «FMATH …».
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
	# орудие планеты (capella-v0.10): «ИИ против ИИ» с орудием у противника (залп — решение ИИ) и бой
	# с приказами «Залп» игрока — те же, что в --selftest
	var gc := QuickMenu.default_cfg(d, true)
	gc["gun"] = "foe"
	var gb := Battle.create(d, Polygon.quick_setup(gc, Polygon.SEED), "capella-проба") as Battle
	for i in MainScript.GUN_SELFTEST_STEPS:
		gb.step()
	var sr := Polygon.salvo_record(d, "capella-проба")
	print("FMATH %s бой %s ИИ %s орудие %s залп %s" % ["libm" if libm else "свои", str(rec["fp"]), ab.fingerprint(), gb.fingerprint(), str(sr["fp"])])
	ab.dispose()
	gb.dispose()
	Fmath.rollback_libm = false
	quit(0)
