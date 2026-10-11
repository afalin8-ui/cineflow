# sim/commands.gd — очередь команд с номером шага, журнал и запись боя (архитектура,
# 1 и 2.9). Вид и интерфейс меняют бой ТОЛЬКО так: battle.queue({...}); команда
# применяется в начале следующего шага и пишется в журнал. Бой = зерно + журнал:
# любой бой, сыгранный человеком, повторяется до шага.
#
# Ссылки в командах — по uid корабля, не по объекту: журнал переживает файл.
# Команды (op):
#   &"move"      ids, x, z     — идти (ПКМ по полю): строй сохраняет взаимное
#                                расположение (по ролям — G4), скорость — по самому медленному
#   &"stance"    ids, stance   — &"hold" (H и S — «Держать», приказ встать), &"guard", &"hunt"
#   &"drift"     ids           — гасители инерции: не все дрейфуют — включить всем, все — выключить
#   &"hyper"     ids           — в гипер; кто-то из них уже копит — отменить у копящих
#   &"reinforce" side          — вызвать резерв (B)
#   &"retreat"   side          — отход всем флотом; &"cancel_retreat" side — отменить
#   &"focus"     ids, target   — ПКМ по врагу: фокус огня (у тяжёлого в G2 — выбор цели,
#                                с места не сходит; безоружные не принимают, C100)
#   &"amove"     ids, x, z     — A + щелчок: атака с ходу (без скорости строя, 03, ловушка 17)
#   &"guard"     ids, target   — ПКМ точно в корпус своего: охранять его (03, 2.16)
#   &"ecm"       ids, mode     — РЭБ: &"jam" «Глушение», &"shield" «Прикрытие», &"off" «Молчать»
#
# У записи — заголовок: сборка, отпечаток данных и зерно. Запись верна только для той
# сборки и тех чисел, на которых сыграна: чужая сборка — отказ словами, а не молча
# другой бой (архитектура, 2.9; риск 21).
extends RefCounted

const KIND := "capella-replay"
const VERSION := 1

## Ждут своего шага: каждая — словарь с полем "step".
var pending: Array[Dictionary] = []
## Журнал всех поставленных команд по порядку — это и есть запись боя.
var journal: Array[Dictionary] = []


## Поставить команду на шаг next_step (обычно battle.steps + 1). Команда копируется
## и приводится к виду журнала: ссылка снаружи потом не меняет бой.
func queue(c: Dictionary, next_step: int) -> Dictionary:
	var n := normalize(c)
	n["step"] = next_step
	pending.append(n)
	journal.append(n)
	return n


## Команды, чей шаг пришёл (по порядку постановки); из очереди они уходят.
func take_due(step: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keep: Array[Dictionary] = []
	for c in pending:
		var at: int = c["step"]
		if at <= step:
			out.append(c)
		else:
			keep.append(c)
	pending = keep
	return out


## Команда в виде журнала: op — StringName, ids — PackedInt32Array, числа — float.
## После JSON все числа — float (godot/CLAUDE.md, 12): uid приводим к целому здесь.
static func normalize(c: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	out["op"] = StringName(str(c.get("op", "")))
	if c.has("ids"):
		var ids := PackedInt32Array()
		var src: Variant = c["ids"]
		if typeof(src) == TYPE_PACKED_INT32_ARRAY:
			var p: PackedInt32Array = src
			ids = p.duplicate()
		elif typeof(src) == TYPE_ARRAY:
			var a: Array = src
			for v: Variant in a:
				var f: float = v
				ids.append(roundi(f))
		out["ids"] = ids
	for k: String in ["x", "z"]:
		if c.has(k):
			var f: float = c[k]
			out[k] = f
	if c.has("side"):
		var sd: float = c["side"]
		out["side"] = roundi(sd)
	if c.has("stance"):
		out["stance"] = StringName(str(c["stance"]))
	if c.has("mode"):
		out["mode"] = StringName(str(c["mode"]))
	if c.has("target"):
		var tg: float = c["target"]
		out["target"] = roundi(tg)
	if c.has("step"):
		var st: float = c["step"]
		out["step"] = roundi(st)
	return out


## Запись боя: заголовок и журнал. setup — с чем бой создан (Battle.create).
func record(build: String, data_fp: String, battle_seed: int, setup: Dictionary, steps: int) -> Dictionary:
	var cmds: Array = []
	for c in journal:
		var j: Dictionary = {}
		for k: Variant in c:
			var v: Variant = c[k]
			if typeof(v) == TYPE_PACKED_INT32_ARRAY:
				var p: PackedInt32Array = v
				j[str(k)] = Array(p)
			elif typeof(v) == TYPE_STRING_NAME:
				j[str(k)] = str(v)
			else:
				j[str(k)] = v
		cmds.append(j)
	var st: Dictionary = {}
	for k: Variant in setup:
		st[str(k)] = str(setup[k]) if typeof(setup[k]) == TYPE_STRING_NAME else setup[k]
	return {"kind": KIND, "version": VERSION, "build": build, "data": data_fp, "seed": battle_seed,
		"setup": st, "steps": steps, "cmds": cmds}


## Разбор записи: {ok, why, setup, seed, steps, cmds}. Чужая сборка или чужие числа —
## отказ словами (а не молча другой бой).
static func check_record(rec: Dictionary, build: String, data_fp: String) -> Dictionary:
	var out := {"ok": false, "why": ""}
	if str(rec.get("kind", "")) != KIND:
		out["why"] = "это не запись боя «Капеллы»"
		return out
	var rb := str(rec.get("build", ""))
	if rb != build:
		out["why"] = "запись сделана другой сборкой (%s), а это %s — бой вышел бы другим" % [rb, build]
		return out
	var rd := str(rec.get("data", ""))
	if rd != data_fp:
		out["why"] = "запись сделана на других числах боя (данные %s, а здесь %s) — бой вышел бы другим" % [rd, data_fp]
		return out
	var cmds: Array[Dictionary] = []
	var raw: Variant = rec.get("cmds", [])
	if typeof(raw) == TYPE_ARRAY:
		var a: Array = raw
		for v: Variant in a:
			if typeof(v) == TYPE_DICTIONARY:
				var d: Dictionary = v
				cmds.append(normalize(d))
	var sd: float = rec.get("seed", 0.0)
	var stn: float = rec.get("steps", 0.0)
	var setup: Variant = rec.get("setup", {})
	out["ok"] = true
	out["seed"] = roundi(sd)
	out["steps"] = roundi(stn)
	out["setup"] = setup if typeof(setup) == TYPE_DICTIONARY else {}
	out["cmds"] = cmds
	return out
