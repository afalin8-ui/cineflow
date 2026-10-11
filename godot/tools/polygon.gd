# tools/polygon.gd — «Полигон» (план G1): два флота «Сражения» (Тройден — игрок,
# атакующий, × Плэктор) на столе. Боя ещё нет — только полёт: выбор мышью и рамкой,
# ПКМ — летят и тормозят у точки без проскока, H/S — встали, G — гипер, D — дрифт,
# B — подкрепление через 32 с выходит из гипера, Пробел — пауза, 1/2/4 — скорость;
# камера как на «Столе».
# Собирается из тех же классов, что пойдут в бой: модель sim/battle.gd, вид
# view/battle_view.gd, ввод input/battle_input.gd, экран ui/polygon_hud.gd.
#
# Повтор (архитектура, 2.9): «Полигон» умеет проиграть запись боя (зерно + журнал
# команд). Приказы в повторе не принимаются; на шаге, на котором запись сделана,
# вид встаёт и отпечаток боя сверяется с записанным: бой с видом (на любой частоте
# кадров) и без вида обязан совпасть до бита.
extends Node3D

signal replay_checked(ok: bool, text: String)

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const BattleView := preload("res://view/battle_view.gd")
const BattleInput := preload("res://input/battle_input.gd")
const PolygonHud := preload("res://ui/polygon_hud.gd")
const ShipModels := preload("res://view/ship_models.gd")

const ATTACKER := &"troyden"
const DEFENDER := &"plektor"
const SIZE := &"mid"
const SEED := 1010
## Показательная запись (--make-replay): столько шагов (60 с) — успевают подкрепление
## (32 с после вызова), залп планеты (23,8 с) и первые выстрелы главного калибра.
const DEMO_STEPS := 1800
## «Синхо» Плэктора во второй линии: [сторона, id, x, z].
const EXTRA := [[1, "sinho", 0.0, -820.0]]
## Насколько вперёд противник идёт атакой с ходу на первом шаге.
const FOE_ADVANCE := 900.0

var defs: Defs
var battle: Battle
var view: BattleView
var input: BattleInput
var hud: PolygonHud
var build := ""
## Беды сборки «Полигона»: нет модели, запись боя чужая. Главная сцена показывает их
## на экране и в stderr — пустого места молча не бывает (как у «Стола»).
var problems := PackedStringArray()
## Проигрываемая запись (пусто — обычный бой) и итог сверки.
var replay: Dictionary = {}
var replay_done := false
var replay_ok := false
var replay_text := ""


## «Перестрелка» (G2): «Сражение» быстрого боя как есть — резерв игрока, орудие планеты
## защитника (01, ловушка 16), — плюс «Синхо» у Плэктора во второй линии (в быстрый бой
## он не попадает, а без его ракет ПВО на экране нечего сбивать) и сценарий: противник
## с первого шага идёт атакой с ходу на FOE_ADVANCE вперёд (ИИ — G5).
static func setup_dict(seed_n: int) -> Dictionary:
	var d := {"attacker": ATTACKER, "defender": DEFENDER, "size": SIZE, "seed": seed_n, "reserve": true,
		"ground_gun": "defender", "extra": EXTRA, "foe_amove": FOE_ADVANCE}
	if old_ecm:
		d["old_ecm"] = true
	return d


## Флажок отката 09, 1.7 (`-- --old-ecm`, план G2): помехи у главного калибра — как
## в старой игре (стреляет только ближе lockRange), а не «перезарядка вдвое медленнее».
## Это другой бой: ключ уходит в состав боя, и запись F9 его помнит. Замер, который
## этот флажок проваливает, — стенд G5.
static var old_ecm := false


## Собрать «Полигон». rec — запись боя для повтора (пусто — новый бой).
## false — есть беды (problems).
func setup(p_defs: Defs, p_build: String, rec: Dictionary = {}) -> bool:
	defs = p_defs
	build = p_build
	problems.clear()
	problems.append_array(models_problems(defs))
	if not problems.is_empty():
		return false
	if rec.is_empty():
		battle = Battle.create(defs, setup_dict(SEED), build) as Battle
	else:
		var why := PackedStringArray()
		battle = Battle.from_record(defs, rec, build, why) as Battle
		if battle == null:
			problems.append("запись боя не проигрывается: %s" % ("; ".join(why)))
			return false
		replay = rec
	view = BattleView.new()
	view.name = "BattleView"
	add_child(view)
	view.setup(defs, battle)
	hud = PolygonHud.new()
	hud.name = "Hud"
	hud.view = view
	# коротко: на 1366 строка справа сверху встаёт рядом с подсказкой клавиш слева
	# (tests/test_render_skirmish.gd меряет, что они не наезжают)
	hud.title = "«Перестрелка»: %s × %s%s" % [_clan_name(ATTACKER), _clan_name(DEFENDER),
		(" · повтор записи" if not replay.is_empty() else "") + (" · РЭБ по-старому (--old-ecm)" if battle.old_ecm else "")]
	add_child(hud)
	input = BattleInput.new()
	input.name = "Input"
	input.view = view
	input.say = hud.say
	input.box_changed = hud.show_box
	input.orders_enabled = replay.is_empty()
	add_child(input)
	if not replay.is_empty():
		var st: float = replay.get("steps", 0.0)
		view.stop_at_step = roundi(st)
	return true


func _clan_name(id: StringName) -> String:
	var f: Defs.FactionDef = defs.factions.get(id)
	return f.short if f != null else str(id)


## Модели кораблей «Полигона» (обе стороны, резерв игрока) — ДО сцены (как у «Стола»).
static func models_problems(p_defs: Defs) -> PackedStringArray:
	var out := PackedStringArray()
	for clan: StringName in [ATTACKER, DEFENDER]:
		var ids: Array[StringName] = []
		for e in Battle.compose(p_defs, SIZE, clan):
			if e.id not in ids:
				ids.append(e.id)
		if clan == ATTACKER:
			for e in Battle.compose(p_defs, &"small", clan):
				if e.id not in ids:
					ids.append(e.id)
		if SIZE in p_defs.quick.station_on and clan == DEFENDER:
			ids.append(&"station")
		if clan == DEFENDER:
			for e: Array in EXTRA:
				if StringName(str(e[1])) not in ids:
					ids.append(StringName(str(e[1])))
		out.append_array(ShipModels.problems(clan, ids, []))
	return out


func _process(_delta: float) -> void:
	if replay.is_empty() or replay_done or battle == null:
		return
	var want: float = replay.get("steps", 0.0)
	if battle.steps >= roundi(want):
		replay_done = true
		var fp := battle.fingerprint()
		var rec_fp := str(replay.get("fp", ""))
		replay_ok = fp == rec_fp
		replay_text = ("совпало: шаг %d, отпечаток боя %s" % [battle.steps, fp]) if replay_ok else ("РАЗОШЛОСЬ: шаг %d, отпечаток боя %s, в записи %s" % [battle.steps, fp, rec_fp])
		hud.say("Повтор записи: " + replay_text)
		replay_checked.emit(replay_ok, replay_text)


# ───────────────────────── показательная запись ─────────────────────────

## Показательный бой без вида: все приказы «Полигона» по журналу — идти, дрифт,
## гипер, «Держать», подкрепление, фокус (лёгкие — на «Синхо»: его ракетный пакет бьёт
## только ближе 640, а сам он встаёт на 840 от цели, и без подлёта лёгких ракет в бою
## нет вовсе — ПВО нечего сбивать; тяжёлые — на крейсер), атака с ходу, «Охота»,
## охрана своего, РЭБ
## и в самом конце — «Охрана» одному корвету (её применяет последний шаг: такой приказ
## ещё не сдвинул ни одного корабля, и потерю его ловит только отпечаток с приказами).
## → запись с отпечатком на последнем шаге («fp»). Её проигрывает --replay с видом:
## отпечатки обязаны совпасть.
static func make_record(p_defs: Defs, p_build: String, steps_n: int = DEMO_STEPS) -> Dictionary:
	var b := demo_battle(p_defs, p_build, steps_n)
	var rec := b.record()
	rec["fp"] = b.fingerprint()
	b.dispose()
	return rec


## Тот же показательный бой — сам бой после steps_n шагов (проверки читают его замеры;
## dispose() — за тем, кто позвал). each — позвать после КАЖДОГО шага (проверка М7
## собирает снаряды: мёртвые уходят из списка в конце шага).
static func demo_battle(p_defs: Defs, p_build: String, steps_n: int = DEMO_STEPS, each: Callable = Callable()) -> Battle:
	var b := Battle.create(p_defs, setup_dict(SEED), p_build) as Battle
	var own := b.side_ships(Ship.ATTACKER)
	var all := PackedInt32Array()
	var heavy := PackedInt32Array()
	var light := PackedInt32Array()
	var by_cls: Dictionary[StringName, int] = {}
	for s in own:
		all.append(s.uid)
		if s.def.main != null:
			heavy.append(s.uid)
		elif s.def.light != null:
			light.append(s.uid)
		if not by_cls.has(s.def.id):
			by_cls[s.def.id] = s.uid
	var corvette: int = by_cls.get(&"corvette", all[0])
	var frigate: int = by_cls.get(&"frigate", all[0])
	var capital: int = by_cls.get(&"capital", all[0])
	var ecm: int = by_cls.get(&"ecm", all[0])
	var foe_cruiser := 0
	var foe_sinho := 0
	for s in b.side_ships(Ship.DEFENDER):
		if s.def.id == &"cruiser" and foe_cruiser == 0:
			foe_cruiser = s.uid
		elif s.def.id == &"sinho":
			foe_sinho = s.uid
	for i in steps_n:
		match b.steps:
			0:
				b.queue({"op": &"move", "ids": all, "x": 0.0, "z": 600.0})
			90:
				b.queue({"op": &"drift", "ids": PackedInt32Array([corvette])})
			150:
				b.queue({"op": &"reinforce", "side": Ship.ATTACKER})
			210:
				b.queue({"op": &"hyper", "ids": PackedInt32Array([frigate])})
			240:
				b.queue({"op": &"focus", "ids": light, "target": foe_sinho})
			300:
				b.queue({"op": &"stance", "ids": heavy, "stance": &"hold"})
			360:
				b.queue({"op": &"move", "ids": PackedInt32Array([corvette]), "x": -420.0, "z": 300.0})
			420:
				b.queue({"op": &"focus", "ids": heavy, "target": foe_cruiser})
			480:
				b.queue({"op": &"amove", "ids": light, "x": 0.0, "z": 150.0})
			540:
				b.queue({"op": &"stance", "ids": light, "stance": &"hunt"})
			600:
				b.queue({"op": &"ecm", "ids": PackedInt32Array([ecm]), "mode": &"shield"})
			660:
				b.queue({"op": &"guard", "ids": PackedInt32Array([light[light.size() - 1]]), "target": capital})
		if i == steps_n - 2:
			# последний приказ — ЖИВОМУ кораблю и с новой стойкой: его потерю в повторе
			# обязан увидеть отпечаток (run_tests.sh, откат «потерян последний приказ»);
			# корвет к концу боя бывает уже сбит, и приказ мёртвому не меняет ничего
			for s in b.side_ships(Ship.ATTACKER):
				if not s.dead and s.stance != &"guard":
					b.queue({"op": &"stance", "ids": PackedInt32Array([s.uid]), "stance": &"guard"})
					break
		b.step()
		if each.is_valid():
			each.call(b)
	return b
