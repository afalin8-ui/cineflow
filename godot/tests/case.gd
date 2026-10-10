# tests/case.gd — основа теста: проверки и счёт. Тест — файл tests/test_<ярус>_*.gd
# (`extends "res://tests/case.gd"`), в нём функции test_* (могут await).
# Провал печатается в stderr (printerr): при обрыве по timeout stdout теряется.
extends RefCounted

const Hooks := preload("res://tests/hooks.gd")

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
