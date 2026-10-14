# sim/report.gd — отчёт боя одной строкой JSON (архитектура, 8.6; план, раздел 0 и G5, п. 5).
# ОДИН на стенд «ИИ против ИИ» (tools/bench_core.gd) и на бой человека (карточка итога):
# иначе М11 и М1–М10 мерились бы только у ИИ, а свалку человек увидел бы у себя. Отсюда же
# короткая выжимка для карточки итога и буфера обмена — человек присылает её в чат текстом.
#
# Модель — чистый GDScript: ни часов, ни ОС — время шагов и имя системы даёт тот, кто зовёт.
extends RefCounted

const Battle := preload("res://sim/battle.gd")
const Metrics := preload("res://sim/metrics.gd")
const Defs := preload("res://sim/defs.gd")
const Ship := preload("res://sim/ship.gd")

## Версия строки отчёта: меняется, если меняются поля (tools/summarize.py её читает).
const VERSION := 1


## Отчёт боя. times — время шагов в мс (по порядку шагов; пусто — не мерили).
static func of(b: Battle, times: PackedFloat64Array, build: String, os_name: String) -> Dictionary:
	var m := b.metrics
	var rep := m.lines_summary()
	var dm := {}
	var m7 := []
	var m5 := []
	var m8 := []
	for side in 2:
		var row := {}
		for k: StringName in Metrics.KEYS:
			var v := m.to_ships(side, k)
			if v > 0.0:
				row[str(k)] = snappedf(v, 0.1)
		dm[str(side)] = row
		var sh := m.m7(side)
		var r7 := {}
		for k: String in sh:
			var v: float = sh[k]
			r7[k] = snappedf(v, 0.001) if k != "total" else snappedf(v, 0.1)
		m7.append(r7)
		m5.append(snappedf(m.mid_share(side), 0.001))
		var sd := b.sides[side]
		var air := m.air_to_ships(side)
		m8.append({"up": sd.sq_up, "lost": sd.sq_lost, "lost_share": snappedf(float(sd.sq_lost) / float(sd.sq_up), 0.001) if sd.sq_up > 0 else -1.0,
			"per_squad": snappedf(air / float(sd.sq_up), 0.1) if sd.sq_up > 0 else -1.0, "air": snappedf(air, 0.1)})
	var ais := []
	for a in b.ai:
		ais.append({"side": a.side, "full": a.full, "dome_ticks": a.dome_ticks, "dome_flips": a.dome_flips,
			"help_calls": a.help_calls, "intercepts": a.intercepts})
	var sorted := times.duplicate()
	sorted.sort()
	var worst := 0.0
	var worst_step := 0
	for i in times.size():
		if times[i] > worst:
			worst = times[i]
			worst_step = i + 1
	var flags := []
	for k: String in FLAG_KEYS:
		var on: bool = b.get(k)
		if on:
			flags.append(k)
	var dif := StringName(str(b.setup.get("difficulty", b.defs.quick.default_difficulty)))
	rep.merge({
		"v": VERSION, "build": build, "os": os_name, "seed": b.battle_seed, "size": str(b.setup.get("size", "")),
		"attacker": str(b.sides[0].clan), "defender": str(b.sides[1].clan), "difficulty": str(dif),
		"player": b.player_side, "watch": b.watch, "result": str(b.result), "winner": b.winner,
		"winner_clan": str(b.sides[b.winner].clan) if b.winner >= 0 else "", "over": b.over,
		"len": snappedf(b.time, 0.01), "steps": b.steps, "dmg": dm, "m5": m5, "m7": m7, "m8": m8,
		"jam_block": snappedf(m.jam_block(Battle.STEP), 0.0001), "ai": ais, "flags": flags,
		"no_ecm": b.setup.get("no_ecm", []),
		"step_ms": {"p50": _q(sorted, 0.5), "p99": _q(sorted, 0.99), "worst": snappedf(worst, 0.001), "worst_step": worst_step},
		"belt_changes": b.belt_log.size(), "fp": b.fingerprint(), "overrides": Array(b.defs.overrides_applied),
		"outcome": b.outcome,
	}, true)
	return rep


## Флажки отката 09, 8.4 — поля состава боя (tools/bench_core.gd → FLAGS).
const FLAG_KEYS: Array[String] = ["legacy_approach", "no_share_close", "no_foe_brake", "clear_055", "ecm_01l", "old_ecm",
	"bomber_direct", "patrol_mid", "old_ai", "old_pd"]


static func _q(sorted: PackedFloat64Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return snappedf(sorted[clampi(floori(q * float(sorted.size())), 0, sorted.size() - 1)], 0.001)


## Строка отчёта: одна строка JSON (её же кладут рядом с программой).
static func line(rep: Dictionary) -> String:
	return JSON.stringify(rep, "", false)


const RESULT_TEXT := {"victory": "Орбита за нами", "retreat": "Отход", "defeat": "Флот разбит", "draw": "Ничья", "limit": "Время вышло"}


## Короткая выжимка для карточки итога и буфера обмена (план G5, п. 5): исход, длина, первое
## попадание, М1–М4, доли урона. Пять–восемь строк — их вставляют в чат.
static func brief(rep: Dictionary, defs: Defs) -> String:
	var lines := PackedStringArray()
	var att := _clan(defs, str(rep.get("attacker", "")))
	var dfn := _clan(defs, str(rep.get("defender", "")))
	var size := StringName(str(rep.get("size", "")))
	var dif: Defs.DifficultyDef = defs.difficulty.get(StringName(str(rep.get("difficulty", ""))))
	lines.append("Капелла %s · «%s» %s × %s · %s%s" % [str(rep.get("build", "")), defs.quick.size_names.get(size, str(size)), att, dfn,
		dif.name if dif != null else "", " · ИИ против ИИ" if rep.get("watch", false) else ""])
	var res := str(rep.get("result", ""))
	var t: float = rep.get("len", 0.0)
	var head: String = RESULT_TEXT.get(res, "бой идёт")
	var wc := str(rep.get("winner_clan", ""))
	var watch: bool = rep.get("watch", false)
	if watch and wc != "":
		head = "победил %s" % _clan(defs, wc)
	lines.append("Итог: %s · бой %s" % [head, _clock(t)])
	var fh: float = rep.get("first_hit", 0.0)
	var fg: float = rep.get("first_gun", 0.0)
	var gap: float = rep.get("m11_gap", 0.0)
	lines.append("Первое попадание: %s · первый залп главного калибра: %s · дольше всего без урона: %d с" % [
		_sec(fh), _sec(fg), roundi(gap)])
	lines.append("Тяжёлые в поясе %s · враг вплотную %s · между линиями %s R · лёгкие между линиями %s" % [
		_k(rep.get("m1", -1.0)), _k(rep.get("m2", -1.0)), _k(rep.get("m3_med_k", -1.0)), _k(rep.get("m4", -1.0))])
	var m7: Array = rep.get("m7", [])
	var who := ["атакующего", "защитника"]
	for side in mini(m7.size(), 2):
		var r: Dictionary = m7[side]
		if r.is_empty():
			continue
		lines.append("Урон %s (%s): главный калибр %s · батареи %s · лёгкие %s · авиация %s" % [
			who[side], att if side == 0 else dfn, _pct(r.get("main", 0.0)), _pct(r.get("sec", 0.0)), _pct(r.get("light", 0.0)), _pct(r.get("air", 0.0))])
	var sm: Dictionary = rep.get("step_ms", {})
	lines.append("Шаг модели: %s мс обычно, %s мс худший" % [_ms(sm.get("p50", 0.0)), _ms(sm.get("worst", 0.0))])
	return "\n".join(lines)


static func _clan(defs: Defs, id: String) -> String:
	var f: Defs.FactionDef = defs.factions.get(StringName(id))
	return f.name if f != null else id


static func _clock(t: float) -> String:
	return "%d:%02d" % [floori(t / 60.0), floori(t) % 60]


static func _sec(v: Variant) -> String:
	var f: float = v
	return "%d с" % roundi(f) if f > 0.0 else "не было"


static func _k(v: Variant) -> String:
	var f: float = v
	return ("%.2f" % f).replace(".", ",") if f >= 0.0 else "—"


static func _pct(v: Variant) -> String:
	var f: float = v
	return "%d%%" % roundi(f * 100.0)


static func _ms(v: Variant) -> String:
	var f: float = v
	return ("%.2f" % f).replace(".", ",")
