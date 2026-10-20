# tests/case.gd — основа теста: проверки и счёт. Тест — файл tests/test_<ярус>_*.gd
# (`extends "res://tests/case.gd"`), в нём функции test_* (могут await).
# Провал печатается в stderr (printerr): при обрыве по timeout stdout теряется.
extends RefCounted

const Hooks := preload("res://tests/hooks.gd")

## Прежний темп боя (до пакета GТ, capella-v0.7.1) — ЧИСЛАМИ доктрины: расстановка ±650, тяжёлые
## без множителей хода, место линии без мёртвой зоны и с прежним сдвигом за тик, без «не
## дёргаться». Все правки GТ — числа doctrine.json, и с этими числами бой совпадает с 0.7.1 ДО БИТА
## (test_sim_flight → test_old_tempo_same_battle). Проверкам, чей случай нашёлся в прежнем темпе
## и в новом не возникает (тыловой рубеж, флажки 8.4), — сюда; в новом темпе они меряются отдельно.
const OLD_TEMPO := {"deploy.heavy_z": 650.0, "heavy.speed_k": 1.0, "heavy.thrust_k": 1.0, "heavy.turn_k": 1.0,
	"heavy.settle": 0.0, "line.shift_max": 120.0, "line.turn_max_deg": 15.0, "line.shift_dead": 0.0,
	"line.turn_dead_deg": 0.0}

## Ход как в JS — тяжёлые без множителей хода пакета GТ (heavy.speed_k, thrust_k, turn_k = 1).
## Эталоны таблиц 2.22 части 02, 2.20 части 03 и тормозного пути — замеры JS-версии, и сверяется с
## ними ФИЗИКА полёта (thrustTo, arriveSpeed, разворот), а не темп: множители GТ ходят одной дверью
## (Ship.thrust/turn/max_speed) и проверяются отдельно — tests/test_tempo_gt.gd.
const JS_MOVE := {"heavy.speed_k": 1.0, "heavy.thrust_k": 1.0, "heavy.turn_k": 1.0}

var tree: SceneTree
var hooks: Hooks
var checks := 0
var fails := 0
var current := ""
var started := 0


func ok(cond: bool, what: String) -> bool:
	checks += 1
	if not cond:
		fails += 1
		printerr("  ПРОВАЛ %s: %s" % [current, what])
	return cond


func eq(got: Variant, want: Variant, what: String) -> bool:
	var same: bool = got == want
	return ok(same and typeof(got) == typeof(want), "%s: получили %s, ждали %s" % [what, var_to_str(got), var_to_str(want)])


func near(got: float, want: float, eps: float, what: String) -> bool:
	return ok(absf(got - want) <= eps, "%s: получили %.9f, ждали %.9f (допуск %s)" % [what, got, want, str(eps)])


func note(msg: String) -> void:
	printerr("    · ", msg)


## ТОЛЬКО для проверки отката (хвост G1): все прогоны пишут в ОДНУ общую папку
## user://test_tmp, как было до правки. В тестах всегда false.
static var rollback_shared_tmp := false


## Папка ЭТОГО прогона для временных файлов (кадры Movie Maker, файлы замера, пробы):
## run_tests.sh даёт каждому прогону свою ($CAPELLA_TMP = $LOGS/tmp). Раньше тесты
## писали в общий user://, и два прогона на одной машине стирали друг другу кадры
## (хвост G1). Без $CAPELLA_TMP (тест запущен руками) — своя папка на процесс.
static func tmp(name: String) -> String:
	var base := OS.get_environment("CAPELLA_TMP")
	if rollback_shared_tmp:
		base = ProjectSettings.globalize_path("user://test_tmp")
	elif base.is_empty():
		base = ProjectSettings.globalize_path("user://test_tmp_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(base)
	return base.path_join(name)


# Помощники для данных JSON: в проекте нетипизированное — ошибка, а значения
# словаря JSON — Variant. Присваивание Variant типизированной переменной разрешено
# (и проверяется при работе), приведение `as` и int(Variant) — нет.
static func dict(v: Variant) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	return d


static func arr(v: Variant) -> Array:
	match typeof(v):
		TYPE_ARRAY:
			var a: Array = v
			return a
		TYPE_PACKED_FLOAT64_ARRAY:
			var p64: PackedFloat64Array = v
			return Array(p64)
		TYPE_PACKED_INT32_ARRAY:
			var p32: PackedInt32Array = v
			return Array(p32)
		TYPE_PACKED_STRING_ARRAY:
			var ps: PackedStringArray = v
			return Array(ps)
	return []


static func num(v: Variant) -> float:
	var f: float = v
	return f


static func whole(v: Variant) -> int:
	var i: int = v
	return i


static func flag(v: Variant) -> bool:
	var b: bool = v
	return b


static func strs(v: Variant) -> PackedStringArray:
	var p: PackedStringArray = v
	return p


static func obj(v: Variant) -> Object:
	var o: Object = v
	return o
