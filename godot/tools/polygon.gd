# tools/polygon.gd — экран боя: «Быстрый бой» из меню (план G5, п. 3) и лаборатория «Бой линий».
#
# «Быстрый бой» (setup с cfg из ui/quick_menu.gd): клан игрока — атакующий, резерв игрока
# («Стычка» своего клана), орудие планеты защитника; противника ведёт ИИ целиком (sim/ai.gd),
# в «ИИ против ИИ» — обе стороны, человек только смотрит (приказов нет). Бой кончается итогом:
# карточка (ui/result_card.gd) с выжимкой отчёта, строка отчёта JSON и запись боя — в папку
# рядом с программой (план G5, п. 5).
#
# Лаборатория «Бой линий» (без cfg; для проверок — пользователь входит через меню): два флота
# «Сражения» (Тройден — игрок, атакующий, × Плэктор) расставлены строем по ролям на ±650 (09,
# 5.5), свой флот приказов не получает; противника ведёт ИИ ТОЛЬКО СТРОЕМ (шаги 6–7, бывшая
# заглушка G4) — у игрока он переписывал бы стойку и участок, то есть отдавал бы приказы (09,
# 9.5 п. 16; 5.6 — «следить за линией» у флота игрока нет), — плюс сценарий пусков звеньев
# FOE_AIR; показательный бой её даёт тот же отпечаток, что в G4. Чужая линия сходится с нашей
# на L = 0,85 R_line, тяжёлые держат пояс и отходят
# задним ходом; наш флот без приказов стоит на местах старта (тяжёлые — пояс в поводке
# 0,5 R), и чужие лёгкие доходят до НАШЕЙ линии. Выбор мышью
# и рамкой, ПКМ по полю — строй по ролям (09, 6.4), по врагу — встать в пояс против него,
# H/S — встали, G — гипер, D — дрифт, B — подкрепление (на свои места), Z/X/C/V — звенья,
# Пробел — пауза, 1/2/4 — скорость, F4 — строка-отладка пояса над тяжёлыми; камера как на
# «Столе».
# Собирается из тех же классов, что пойдут в бой: модель sim/battle.gd, вид
# view/battle_view.gd, ввод input/battle_input.gd, экран ui/polygon_hud.gd.
#
# Повтор (архитектура, 2.9): «Полигон» умеет проиграть запись боя (зерно + журнал
# команд). Приказы в повторе не принимаются; на шаге, на котором запись сделана,
# вид встаёт и отпечаток боя сверяется с записанным: бой с видом (на любой частоте
# кадров) и без вида обязан совпасть до бита.
extends Node3D

signal replay_checked(ok: bool, text: String)
## Карточка итога: «Ещё раз» и «В меню» (решает main.gd).
signal again_pressed
signal menu_pressed

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const BattleView := preload("res://view/battle_view.gd")
const BattleInput := preload("res://input/battle_input.gd")
const PolygonHud := preload("res://ui/polygon_hud.gd")
const ShipModels := preload("res://view/ship_models.gd")
const Report := preload("res://sim/report.gd")
const ResultCard := preload("res://ui/result_card.gd")

const ATTACKER := &"troyden"
const DEFENDER := &"plektor"
const SIZE := &"mid"
const SEED := 1010
## Показательная запись (--make-replay): столько шагов (60 с) — успевают подкрепление
## (32 с после вызова), залп планеты (23,8 с) и первые выстрелы главного калибра.
const DEMO_STEPS := 1800
## «Синхо» Плэктора: [сторона, id, x, z] — заглушка строя на первом тике ставит его в линию.
const EXTRA := [[1, "sinho", 0.0, -820.0]]
## Авиация противника до ИИ (G5): его носители поднимают звенья по кругу ролей —
## бомбардировщики (их встречает ПВО), перехватчики и истребители (их встречают свои
## перехватчики); с 4-й секунды, по звену с носителя раз в 6 с, пока есть места.
## С 4-й, а не с 8-й (доработка G3): тогда противник шёл атакой с ходу, и к 10-й секунде его
## корветы входили в полосу патруля наших перехватчиков (09, 4.2) — звено, поднятое на первой
## секунде, встречало первым корвет, а не звенья. С G4 атаки с ходу нет (его ведёт заглушка
## строя), а первый пуск на 4-й оставлен: звенья встречаются над нашей линией раньше корветов.
const FOE_AIR := {"roles": ["bomber", "interceptor", "bomber", "fighter"], "every": 6.0, "first": 4.0}

## Показательный бой: свои перехватчики бьют чужое звено бомбардировщиков (приказ звену на
## звено) и свои истребители садятся (V) — на 9-й и 11-й секунде, пока оба звена живы
## (к 20-й их сбивают; на шагах 720 и 900 приказов не было вовсе).
const AIR_FOCUS_STEP := 270
const AIR_RECALL_STEP := 330
## ТОЛЬКО для проверки отката: приказы своим звеньям на прежних шагах 720 и 900, когда
## звеньев уже нет, — в журнале их нет (tests/test_sim_air.gd).
static var rollback_late_air_orders := false

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
## «Быстрый бой» из меню (пусто — лаборатория «Бой линий»): attacker, defender, size,
## difficulty, watch, seed.
var cfg: Dictionary = {}
## Куда класть отчёт и запись боя (main.gd даёт папку рядом с программой; пусто — не писать:
## так зовут проверки без главной сцены, им файлы в user:// не нужны).
var out_dir := ""
var card: ResultCard
## Итог показан: отчёт, его выжимка и файл.
var report: Dictionary = {}
var brief := ""
var report_file := ""
var replay_file := ""
## Окно «Выйти в меню?» (кнопка в углу экрана боя).
var leave_panel: PanelContainer
var leave_btn: Button


## Лаборатория «Бой линий» (G4): «Сражение» быстрого боя как есть — резерв игрока, орудие
## планеты защитника (01, ловушка 16), — плюс «Синхо» у Плэктора (в быстрый бой он не попадает,
## а без его ракет ПВО на экране нечего сбивать); противника ведёт ИИ только строем (ai_lines),
## его авиация — сценарий пусков FOE_AIR.
static func setup_dict(seed_n: int) -> Dictionary:
	var d := {"attacker": ATTACKER, "defender": DEFENDER, "size": SIZE, "seed": seed_n, "reserve": true,
		"ground_gun": "defender", "extra": EXTRA, "ai_lines": [Ship.DEFENDER], "foe_air": FOE_AIR}
	d.merge(flags, true)
	return d


## «Быстрый бой» (01, 1.1; план, раздел 1): игрок — атакующий, резерв — «Стычка» своего клана,
## у планеты защитника — орудие его клана; противника ведёт ИИ целиком, в «ИИ против ИИ» —
## обе стороны (сложность — у обоих ИИ).
static func quick_setup(c: Dictionary, seed_n: int) -> Dictionary:
	var watch: bool = c.get("watch", false)
	var d := {"attacker": StringName(str(c.get("attacker", "troyden"))), "defender": StringName(str(c.get("defender", "plektor"))),
		"size": StringName(str(c.get("size", "mid"))), "seed": seed_n, "reserve": true, "ground_gun": "defender",
		"difficulty": str(c.get("difficulty", "normal")), "ai": [Ship.ATTACKER, Ship.DEFENDER] if watch else [Ship.DEFENDER]}
	d.merge(flags, true)
	return d


## Флажки отката из командной строки (main.gd → apply_flags; tools/bench_core.gd → FLAGS):
## `-- --old-ecm` (09, 1.7), `--bomber-direct`, `--patrol-mid` (авиация 09, 8.4),
## `--legacy-approach`, `--no-share-close`, `--no-foe-brake`, `--clear-055`, `--ecm-01L`
## (доктрина тяжёлых и строй, 09, 8.4). Это другой бой: ключи уходят в состав боя, запись F9
## их помнит, заголовок называет.
static var flags: Dictionary = {}


## Собрать «Полигон». rec — запись боя для повтора (пусто — новый бой).
## false — есть беды (problems).
func setup(p_defs: Defs, p_build: String, rec: Dictionary = {}, p_cfg: Dictionary = {}) -> bool:
	defs = p_defs
	build = p_build
	cfg = p_cfg
	problems.clear()
	if cfg.is_empty():
		problems.append_array(models_problems(defs))
	else:
		problems.append_array(quick_models_problems(defs, cfg))
	if not problems.is_empty():
		return false
	if rec.is_empty():
		var sf: float = cfg.get("seed", float(SEED))
		battle = Battle.create(defs, setup_dict(SEED) if cfg.is_empty() else quick_setup(cfg, roundi(sf)), build) as Battle
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
	hud.title = title_of(battle) + (" · повтор записи" if not replay.is_empty() else "") + flags_text(battle)
	hud.watch = battle.watch
	hud.quick = quick()
	hud.show_feed = hud.quick
	add_child(hud)
	input = BattleInput.new()
	input.name = "Input"
	input.view = view
	input.say = hud.say
	input.box_changed = hud.show_box
	input.orders_enabled = replay.is_empty() and not battle.watch
	if battle.watch and replay.is_empty():
		input.orders_off_text = "ИИ против ИИ: ты только смотришь — приказов нет"
	add_child(input)
	hud.input = input
	card = ResultCard.new()
	card.name = "ResultCard"
	add_child(card)
	card.again.connect(func() -> void: again_pressed.emit())
	card.to_menu.connect(func() -> void: menu_pressed.emit())
	if quick():
		_leave_ui()
	if not replay.is_empty():
		var st: float = replay.get("steps", 0.0)
		view.stop_at_step = roundi(st)
	return true


## Флажки отката боя — коротко для заголовка (другой бой обязан себя называть).
## Флажки отката 09, 8.4 в заголовке — словами (ключ состава боя → как назвать).
const FLAG_NAMES := {
	"old_ecm": "РЭБ по-старому", "bomber_direct": "бомбардировщики напрямик", "patrol_mid": "патруль над серединой",
	"legacy_approach": "тяжёлые по-старому", "no_share_close": "подход без доли сближения",
	"no_foe_brake": "подход без торможения у чужих", "clear_055": "путь чист 0,55 R", "ecm_01l": "РЭБ на 0,1 L",
	"old_ai": "ИИ по-старому", "old_pd": "ПВО по-старому",
}


static func flags_text(b: Battle) -> String:
	var parts := PackedStringArray()
	for k: String in FLAG_NAMES:
		var on: bool = b.get(k)
		if on:
			parts.append(str(FLAG_NAMES[k]))
	return "" if parts.is_empty() else " · откат: " + ", ".join(parts)


func _clan_name(id: StringName) -> String:
	var f: Defs.FactionDef = defs.factions.get(id)
	return f.short if f != null else str(id)


## Быстрый бой из меню (а не лаборатория).
func quick() -> bool:
	return not cfg.is_empty() or battle.has_full_ai()


## Заголовок справа сверху — КОРОТКО (на 1366 он встаёт рядом с подсказкой клавиш слева,
## tests/test_render_skirmish.gd меряет, что они не наезжают).
func title_of(b: Battle) -> String:
	if not quick():
		return "«Бой линий»: %s × %s" % [_clan_name(ATTACKER), _clan_name(DEFENDER)]
	var size := StringName(str(b.setup.get("size", "mid")))
	return "%s«%s»: %s × %s" % ["ИИ против ИИ · " if b.watch else "", defs.quick.size_names.get(size, str(size)),
		_clan_name(b.sides[0].clan), _clan_name(b.sides[1].clan)]


## Модели быстрого боя: обе стороны, резерв игрока, станция — ДО сцены (как у «Стола»).
static func quick_models_problems(p_defs: Defs, c: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var size := StringName(str(c.get("size", "mid")))
	var att := StringName(str(c.get("attacker", "troyden")))
	var dfn := StringName(str(c.get("defender", "plektor")))
	for clan: StringName in [att, dfn]:
		var ids: Array[StringName] = []
		for e in Battle.compose(p_defs, size, clan):
			if e.id not in ids:
				ids.append(e.id)
		if clan == att:
			for e in Battle.compose(p_defs, &"small", clan):
				if e.id not in ids:
					ids.append(e.id)
		if clan == dfn and size in p_defs.quick.station_on:
			ids.append(&"station")
		out.append_array(ShipModels.problems(clan, ids, [&"interceptor", &"fighter", &"bomber"]))
	return out


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
	if battle != null and battle.over and card != null and not card.is_open() and replay.is_empty():
		finish_card()
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


# ───────────────────────── итог (план G5, пп. 3, 5) ─────────────────────────

## Итог боя: отчёт (sim/report.gd, тот же, что у стенда) — строкой JSON в файл рядом
## с программой, туда же запись боя (её проигрывает --replay); карточка с выжимкой.
func finish_card() -> void:
	report = Report.of(battle, view.step_ms, build, OS.get_name())
	brief = Report.brief(report, defs)
	report_file = ""
	replay_file = ""
	if out_dir != "":
		var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
		DirAccess.make_dir_recursive_absolute(out_dir)
		report_file = _write(out_dir.path_join("capella_battle_%s.json" % stamp), Report.line(report))
		var rec := battle.record()
		rec["fp"] = battle.fingerprint()
		replay_file = _write(out_dir.path_join("capella_replay_%s.json" % stamp), JSON.stringify(rec))
	_hide_leave()
	card.show_result(battle, defs, brief, report_file)


static func _write(path: String, text: String) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text + "\n")
	f.close()
	return path


## Кнопка «В меню» в углу экрана быстрого боя и окно «Выйти в меню?» (бой на это время стоит).
func _leave_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Leave"
	layer.layer = 30
	add_child(layer)
	leave_btn = Button.new()
	leave_btn.name = "LeaveBtn"
	leave_btn.text = "В меню"
	leave_btn.focus_mode = Control.FOCUS_NONE
	leave_btn.custom_minimum_size = Vector2(110.0, 32.0)
	leave_btn.pressed.connect(_ask_leave)
	layer.add_child(leave_btn)
	leave_panel = PanelContainer.new()
	leave_panel.name = "LeavePanel"
	leave_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.95)
	sb.border_color = Color(0.35, 0.55, 0.8, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	leave_panel.add_theme_stylebox_override("panel", sb)
	leave_panel.visible = false
	layer.add_child(leave_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 12)
	leave_panel.add_child(box)
	var l := Label.new()
	l.text = "Выйти в меню? Бой не будет засчитан." if not battle.watch else "Выйти в меню?"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 18)
	box.add_child(l)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for k: String in ["yes", "no"]:
		var b := Button.new()
		b.name = k
		b.text = "Выйти" if k == "yes" else "Продолжить бой"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150.0, 36.0)
		b.pressed.connect(_leave_answer.bind(k == "yes"))
		row.add_child(b)
	_place_leave()


var _paused_before := false


func _ask_leave() -> void:
	if card.is_open():
		menu_pressed.emit()
		return
	_paused_before = view.paused
	view.paused = true
	leave_panel.visible = true
	_place_leave()


func _leave_answer(yes: bool) -> void:
	leave_panel.visible = false
	if yes:
		menu_pressed.emit()
	else:
		view.paused = _paused_before


func _hide_leave() -> void:
	if leave_panel != null:
		leave_panel.visible = false
	if leave_btn != null:
		leave_btn.visible = false


func _place_leave() -> void:
	if leave_btn == null:
		return
	var vs := get_viewport().get_visible_rect().size
	leave_btn.position = Vector2(vs.x - leave_btn.size.x - 16.0, vs.y - leave_btn.size.y - 14.0)
	if leave_panel.visible:
		leave_panel.reset_size()
		leave_panel.position = ((vs - leave_panel.size) * 0.5).floor()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_place_leave()


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
	var carrier: int = by_cls.get(&"carrier", all[0])
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
			# авиация (G3): звенья с носителя — Z/X/C, приказы звеньям, перехват чужого
			# звена лёгкими (приказ бить его машины, C14) и посадка V
			30:
				b.queue({"op": &"launch", "ids": PackedInt32Array([carrier]), "role": &"bomber"})
			45:
				b.queue({"op": &"launch", "ids": PackedInt32Array([carrier]), "role": &"interceptor"})
			60:
				b.queue({"op": &"launch", "ids": PackedInt32Array([carrier]), "role": &"fighter"})
			780:
				var foe_q2 := _squad_of(b, Ship.DEFENDER, &"")
				if foe_q2 > 0:
					b.queue({"op": &"focus", "ids": PackedInt32Array([light[0]]), "target": foe_q2})
		# приказы СВОИМ звеньям — пока они живы (вторая доработка G3): на шагах 720 и 900 свои
		# перехватчики и истребители были уже сбиты, приказ мёртвому не отдавался вовсе, и в
		# журнале показательного боя не было ни фокуса звена на звено, ни посадки V
		if b.steps == (720 if rollback_late_air_orders else AIR_FOCUS_STEP):
			var foe_q := _squad_of(b, Ship.DEFENDER, &"bomber")
			var own_int := _squad_of(b, Ship.ATTACKER, &"interceptor")
			if foe_q > 0 and own_int > 0:
				b.queue({"op": &"focus", "ids": PackedInt32Array([own_int]), "target": foe_q})
		if b.steps == (900 if rollback_late_air_orders else AIR_RECALL_STEP):
			var own_fig := _squad_of(b, Ship.ATTACKER, &"fighter")
			if own_fig > 0:
				b.queue({"op": &"recall", "ids": PackedInt32Array([own_fig])})
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


## Первое живое звено стороны (роли role; &"" — любой); 0 — нет.
static func _squad_of(b: Battle, side: int, role: StringName) -> int:
	for q in b.squads:
		if not q.dead and q.side == side and (role == &"" or q.role == role):
			return q.uid
	return 0
