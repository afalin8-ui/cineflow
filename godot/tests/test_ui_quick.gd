# Меню «Быстрый бой», «ИИ против ИИ», карточка итога и отчёт боя человека (план G5, пп. 3, 5;
# часть 01, 1.1; 05, 2.13; 07, 2.16). Всё — настоящими событиями ввода (hooks.gd): нажатие
# обязано попадать в кнопку (hovered_at), а не «кнопка есть в дереве». Каждая проверка —
# с откатом или с контролем, где причины нет.
extends "res://tests/case.gd"

const MainScene := preload("res://main.tscn")
const MainScript := preload("res://main.gd")
const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Report := preload("res://sim/report.gd")
const Polygon := preload("res://tools/polygon.gd")
const QuickMenu := preload("res://ui/quick_menu.gd")
const ResultCard := preload("res://ui/result_card.gd")
const BattleView := preload("res://view/battle_view.gd")
const PolygonHud := preload("res://ui/polygon_hud.gd")
const State := preload("res://sim/state.gd")


## Главная сцена с меню (по умолчанию с G5): отчёты — в свою папку, зерно — своё.
func _main(dir_name: String) -> Node:
	await hooks.set_window_size(Vector2i(1366, 768))
	MainScript.out_override = tmp(dir_name)
	MainScript.seed_override = 4242
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	await hooks.frames(4)
	return main


func _done(main: Node) -> void:
	MainScript.out_override = ""
	MainScript.seed_override = -1
	main.queue_free()
	await hooks.frames(2)


## Нажать кнопку меню или карточки настоящим щелчком; false — под её серединой не она.
func _press(b: Button) -> bool:
	var c := b.get_global_rect().get_center()
	var under := await hooks.hovered_at(c)
	if under != b:
		return false
	await hooks.click(c)
	return true


func _menu_btn(main: Node, key: String) -> Button:
	var m: QuickMenu = main.get("menu")
	return m.buttons.get(key) if m != null else null


## F6 из меню — «Стол», и подсказка «Стола» называет, куда ведёт F6: в меню (а с «Полигона» —
## на «Полигон», test_ui_polygon — это и есть контроль: подсказка зависит от того, откуда пришли).
func test_menu_table_and_back() -> void:
	var main := await _main("quick_table")
	await hooks.key(KEY_F6)
	await hooks.frames(4)
	ok(str(main.get("mode")) == "table" and main.get("menu") == null, "F6 в меню — «Стол», меню закрыто")
	var fps: Node = main.get("fps")
	var hint: Label = fps.get("hint")
	ok(hint.text.contains("F6 — меню «Быстрый бой»"), "подсказка «Стола» называет, куда F6: «%s»" % hint.text.get_slice("\n", 0))
	await hooks.key(KEY_F6)
	await hooks.frames(4)
	ok(str(main.get("mode")) == "menu" and main.get("menu") != null and main.get("view") == null, "F6 ещё раз — снова меню")
	await _done(main)


func test_menu_is_default_and_chooses() -> void:
	var main := await _main("quick_menu")
	eq(str(main.get("mode")), "menu", "без режима главная сцена открывает меню «Быстрый бой»")
	var m: QuickMenu = main.get("menu")
	if not ok(m != null, "меню собрано"):
		await _done(main)
		return
	eq(str(m.cfg["attacker"]), "troyden", "по умолчанию твой клан — Тройден")
	eq(str(m.cfg["defender"]), "plektor", "противник — Плэктор")
	eq(str(m.cfg["size"]), "mid", "масштаб — «Сражение»")
	eq(str(m.cfg["difficulty"]), "normal", "сложность — «Офицер»")
	ok(m.desc_label.text.contains("2,5–4,0 с") and m.desc_label.text.contains("7 из 10"), "под сложностью — что она меняет в бою: «%s»" % m.desc_label.text)
	# состав по умолчанию словами — эти числа повторяет текст выпуска capella-v0.6
	eq(m.lineup_label.text, "У тебя 8 кораблей и резерв из 5, у противника 22", "состав «Сражения» Тройден × Плэктор словами")
	ok(m.buttons["dif:normal"].button_pressed and not m.buttons["dif:hard"].button_pressed, "выбранная сложность нажата")
	# Рииз и Девиан видны, но выключены — «в следующих сборках»
	for k: String in ["mine:reez", "mine:devian", "foe:reez", "foe:devian"]:
		var b: Button = m.buttons.get(k)
		ok(b != null and b.visible and b.disabled and b.tooltip_text.contains("в следующих сборках"), "%s виден, выключен и говорит «в следующих сборках»" % k)
	ok(m.later_label.text.contains("в следующих сборках"), "строкой под кланами: «%s»" % m.later_label.text)
	# выключенный не нажимается (контроль — включённый в том же ряду нажимается)
	await hooks.click(m.buttons["foe:reez"].get_global_rect().get_center())
	eq(str(m.cfg["defender"]), "plektor", "щелчок по выключенному Риизу выбора не меняет")
	ok(await _press(m.buttons["foe:troyden"]), "под серединой «Тройден» в ряду противника — она сама")
	eq(str(m.cfg["defender"]), "troyden", "зеркальный бой можно: противник — Тройден")
	ok(await _press(m.buttons["dif:hard"]), "кнопка «Ветеран» нажимается")
	eq(str(m.cfg["difficulty"]), "hard", "сложность — «Ветеран»")
	ok(m.desc_label.text.contains("все его тяжёлые"), "описание сменилось: «%s»" % m.desc_label.text)
	ok(await _press(m.buttons["size:small"]), "масштаб «Стычка» нажимается")
	ok(m.lineup_label.text.begins_with("У тебя "), "что будет в бою — словами: «%s»" % m.lineup_label.text)
	# каждая кнопка меню под своей серединой — она сама, на 1366 ничто ни на что не наезжает
	var hidden := PackedStringArray()
	for k: String in m.buttons:
		var b: Button = m.buttons[k]
		if await hooks.hovered_at(b.get_global_rect().get_center()) != b:
			hidden.append(k)
	ok(hidden.is_empty(), "на 1366 все кнопки меню нажимаемы (под серединой — сама кнопка): закрыты %s" % ", ".join(hidden))
	await _done(main)


func test_go_and_watch() -> void:
	var main := await _main("quick_go")
	ok(await _press(_menu_btn(main, "go")), "кнопка «В бой» нажимается")
	await hooks.frames(3)
	eq(str(main.get("mode")), "battle", "«В бой» открывает быстрый бой")
	var p: Polygon = main.get("polygon")
	if not ok(p != null and p.battle != null, "бой собран"):
		await _done(main)
		return
	var b := p.battle
	ok(not b.watch and b.ai.size() == 1 and b.ai[0].side == Ship.DEFENDER and b.ai[0].full, "противника ведёт ИИ целиком, тебя — ты")
	eq(str(b.setup.get("attacker")), "troyden", "ты — атакующий, как в JS")
	ok(b.sides[Ship.ATTACKER].reserve.size() > 0 and b.gun != null, "резерв у тебя, орудие — у планеты противника")
	ok(p.input.orders_enabled, "приказы принимаются")
	var fps: Node = main.get("fps")
	var hl: Label = fps.get("hint")
	ok(hl != null and hl.text.contains("F8 — заново") and not hl.text.contains("F6"), "подсказка боя: F8 — заново, «Стола» из боя нет: «%s»" % (hl.text.get_slice("\n", 0) if hl != null else ""))
	# F8 — тот же бой заново (новое зерно)
	var seed0 := b.battle_seed
	MainScript.seed_override = 4343
	await hooks.key(KEY_F8)
	await hooks.frames(2)
	var p2: Polygon = main.get("polygon")
	ok(p2 != p and p2.battle.battle_seed != seed0 and str(p2.battle.setup.get("defender")) == "plektor", "F8 — тот же состав, новое зерно (%d → %d)" % [seed0, p2.battle.battle_seed])
	# в меню и «Смотреть: ИИ против ИИ»
	ok(await _press(p2.leave_btn), "кнопка «В меню» в углу экрана боя нажимается")
	ok(p2.leave_panel.visible and p2.view.paused, "окно «Выйти в меню?» открыто, бой на паузе")
	var no := p2.leave_panel.find_child("no", true, false) as Button
	ok(await _press(no), "«Продолжить бой» нажимается")
	ok(not p2.leave_panel.visible and not p2.view.paused, "окно закрылось, бой идёт")
	ok(await _press(p2.leave_btn), "снова «В меню»")
	ok(await _press(p2.leave_panel.find_child("yes", true, false) as Button), "«Выйти» нажимается")
	await hooks.frames(2)
	eq(str(main.get("mode")), "menu", "«Выйти» — в меню")
	ok(await _press(_menu_btn(main, "watch")), "кнопка «Смотреть: ИИ против ИИ» нажимается")
	await hooks.frames(3)
	var w: Polygon = main.get("polygon")
	ok(w.battle.watch and w.battle.ai.size() == 2, "«ИИ против ИИ»: обе стороны под ИИ")
	ok(not w.input.orders_enabled, "человек только смотрит — приказы не принимаются")
	ok(w.hud.sel_label.text.contains("ИИ против ИИ"), "панель внизу говорит, что ты смотришь: «%s»" % w.hud.sel_label.text.get_slice("\n", 0))
	# ПКМ по полю и клавиши приказов — в журнал ничего (контроль: в обычном бою ПКМ даёт приказ)
	w.view.paused = true
	# свой корабль выбран — иначе клавиши приказа сказали бы «сначала выбери свои корабли»
	var mine: Array[int] = []
	for s in w.battle.side_ships(Ship.ATTACKER):
		if s.heavy():
			mine.append(s.uid)
			break
	w.view.selection = mine
	var j0 := w.battle.cmds.journal.size()
	await hooks.key(KEY_H)
	await hooks.key(KEY_T)
	await hooks.click(Vector2(683, 300), MOUSE_BUTTON_RIGHT)
	await hooks.frames(2)
	eq(w.battle.cmds.journal.size(), j0, "в «ИИ против ИИ» клавиши и ПКМ приказов не дают")
	ok(w.hud._local.size() > 0 and str(w.hud._local[-1][0]).contains("ты только смотришь"), "и говорят почему — полоской «ты только смотришь»")
	# скорость и пауза — не приказы: в «ИИ против ИИ» работают (текст выпуска называет 1, 2 и 4)
	await hooks.key(KEY_2)
	eq(w.view.speed, 2, "клавиша 2 — скорость 2× и в «ИИ против ИИ»")
	await hooks.key(KEY_4)
	eq(w.view.speed, 4, "клавиша 4 — скорость 4× и в «ИИ против ИИ»")
	await hooks.key(KEY_1)
	eq(w.view.speed, 1, "клавиша 1 — снова обычная скорость")
	await hooks.key(KEY_4)
	var p0 := w.view.paused
	await hooks.key(KEY_SPACE)
	ok(w.view.paused != p0, "Пробел — пауза и снова ход")
	# щелчок по кораблю — выбрать и прочитать внизу, чем он занят (приказы тут ни при чём)
	w.view.paused = true
	await hooks.frames(2)
	var foe: Ship = null
	for s in w.battle.side_ships(Ship.DEFENDER):
		if s.heavy() and not s.dead:
			foe = s
			break
	var cam: Camera3D = w.view.rig.camera
	var pt: Vector3 = w.view.call("ship_point", foe)
	var at := cam.unproject_position(pt)
	await hooks.click(at)
	await hooks.frames(2)
	await hooks.frames(2)
	var doing := PolygonHud.doing(foe, w.battle)
	ok(w.view.selection == [foe.uid] and w.hud.sel_label.text.contains(foe.name) and w.hud.sel_label.text.contains(doing), "щелчок по чужому крейсеру в «ИИ против ИИ» — он выбран, внизу его имя и занятие («%s»): «%s»" % [doing, w.hud.sel_label.text.get_slice("\n", 0)])
	await _done(main)


## «ИИ против ИИ» на экране (текст выпуска capella-v0.6.1): строка вверху о подкреплении называет
## клан — «Тройден: подкрепление выйдет из гипера…», а не «Подкрепление выйдет…» с места атакующего,
## как в 0.6 (замечание к G5). Открывается кнопкой меню, бой идёт видом 3,5 игровых секунды: ИИ
## атакующего зовёт резерв на первом тике (3 с). Откат — State.rollback_watch_voice.
func _watch_top(rollback: bool) -> String:
	State.rollback_watch_voice = rollback
	var main := await _main("quick_watch_top")
	var txt := ""
	if await _press(_menu_btn(main, "watch")):
		await hooks.frames(3)
		var w: Polygon = main.get("polygon")
		for i in roundi(3.5 / Battle.STEP):
			w.view.advance(Battle.STEP)
		await hooks.frames(3)
		txt = w.hud.toasts.text
	State.rollback_watch_voice = false
	await _done(main)
	return txt


func test_watch_top_line_names_clan() -> void:
	var t := await _watch_top(false)
	note("«ИИ против ИИ», 3,5 с: строка вверху «%s»" % t.replace("\n", " | "))
	ok(t.contains("Тройден: подкрепление выйдет из гипера"), "строка вверху называет клан, который позвал подкрепление")
	var o := await _watch_top(true)
	ok(o.contains("Подкрепление выйдет из гипера") and not o.contains("Тройден:"), "откат «с места атакующего» (как в 0.6): «%s» — проверка краснеет" % o.replace("\n", " | "))


## «В бой»: приказы — те же клавиши, что на «Полигоне» (текст выпуска capella-v0.6 их называет):
## T — охота, H — стоять, B — подкрепление, F3 — счётчик кадров. Контроль — «ИИ против ИИ»
## (test_go_and_watch): там те же клавиши приказов не дают.
func test_quick_orders_by_keys() -> void:
	var main := await _main("quick_orders")
	ok(await _press(_menu_btn(main, "go")), "«В бой»")
	await hooks.frames(3)
	var p: Polygon = main.get("polygon")
	var h: Ship = null
	for s in p.battle.side_ships(Ship.ATTACKER):
		if s.heavy() and not s.dead:
			h = s
			break
	if not ok(h != null, "у тебя есть тяжёлый"):
		await _done(main)
		return
	p.view.selection = [h.uid]
	await hooks.key(KEY_T)
	await hooks.frames(6)
	eq(str(h.stance), "hunt", "T — охота")
	await hooks.key(KEY_H)
	await hooks.frames(6)
	eq(str(h.stance), "hold", "H — стоять")
	await hooks.key(KEY_B)
	await hooks.frames(6)
	ok(p.battle.sides[Ship.ATTACKER].reinforce_at > 0.0, "B — подкрепление в пути (выйдет на %.0f с)" % p.battle.sides[Ship.ATTACKER].reinforce_at)
	var fps: Node = main.get("fps")
	var was: bool = fps.get("shown")
	await hooks.key(KEY_F3)
	await hooks.frames(2)
	var now_shown: bool = fps.get("shown")
	ok(now_shown != was, "F3 — счётчик кадров и в бою")
	await hooks.key(KEY_F3)
	await _done(main)


## Быстрый бой до итога (итог ставим сами: ждать минуты боя проверке незачем), карточка.
func test_result_card() -> void:
	var main := await _main("quick_card")
	ok(await _press(_menu_btn(main, "go")), "«В бой»")
	await hooks.frames(3)
	var p: Polygon = main.get("polygon")
	p.view.speed = 4
	await hooks.frames(30)
	p.battle.finish(Ship.DEFENDER)
	await hooks.frames(3)
	var card: ResultCard = p.card
	ok(card.is_open(), "бой кончен — карточка итога")
	eq(card.title_label.text, "Флот разбит", "заголовок итога «Флот разбит»")
	ok(card.stats_label.text.contains("Бой длился") and card.stats_label.text.contains("потери:"), "время боя и потери по видам")
	ok(p.brief.contains("Итог: Флот разбит") and p.brief.contains("Первое попадание") and card.brief_label.text == p.brief, "выжимка отчёта на карточке: «%s»" % p.brief.get_slice("\n", 1))
	ok(p.report_file != "" and FileAccess.file_exists(p.report_file), "строка отчёта JSON записана рядом (%s)" % p.report_file.get_file())
	ok(p.replay_file != "" and FileAccess.file_exists(p.replay_file), "рядом — запись боя (её проигрывает --replay)")
	var j := JSON.new()
	ok(j.parse(FileAccess.get_file_as_string(p.report_file)) == OK and typeof(j.data) == TYPE_DICTIONARY, "отчёт — одна строка JSON")
	if typeof(j.data) == TYPE_DICTIONARY:
		var d: Dictionary = j.data
		ok(d.has("m7") and d.has("first_hit") and d.has("outcome") and str(d.get("result")) == "defeat", "в отчёте — замеры, итог и уцелевшие (как у стенда)")
	ok(not p.leave_btn.visible, "кнопка «В меню» в углу при карточке спрятана — на карточке своя")
	# все четыре кнопки карточки — под своей серединой
	for k: String in ["again", "menu", "copy", "open"]:
		var b: Button = card.buttons[k]
		ok(await hooks.hovered_at(b.get_global_rect().get_center()) == b, "кнопка карточки «%s» не закрыта ничем" % b.text)
	card.dry = true
	ok(await _press(card.buttons["copy"]), "«Скопировать» нажимается")
	ok(await _press(card.buttons["open"]), "«Открыть папку» нажимается")
	eq(card.presses.get("copy", 0), 1, "«Скопировать» — одно нажатие")
	# под карточкой бой стоит насовсем: вид не шагает (05, ловушка 31; C65)
	var st := p.battle.steps
	p.view.paused = false
	p.view.advance(1.0)
	p.view.advance(1.0)
	eq(p.battle.steps, st, "после итога вид не шагает модель (%d)" % p.battle.steps)
	BattleView.rollback_step_after_over = true
	p.view.advance(0.5)
	BattleView.rollback_step_after_over = false
	ok(p.battle.steps > st, "откат «шагает после итога»: шагов стало %d — проверка краснеет" % p.battle.steps)
	# «Ещё раз» — тот же состав, новое зерно
	var cfg0: Dictionary = main.get("last_cfg")
	MainScript.seed_override = 5151
	ok(await _press(card.buttons["again"]), "«Ещё раз» нажимается")
	await hooks.frames(3)
	var p2: Polygon = main.get("polygon")
	ok(p2 != p and not p2.battle.over, "«Ещё раз» — новый бой")
	for k: String in ["attacker", "defender", "size", "difficulty"]:
		eq(str(p2.battle.setup.get(k)), str(cfg0.get(k)), "«Ещё раз»: %s тот же" % k)
	ok(p2.battle.battle_seed == 5151, "«Ещё раз»: зерно новое")
	p2.battle.finish(Ship.ATTACKER)
	await hooks.frames(3)
	eq(p2.card.title_label.text, "Орбита за нами", "победа — «Орбита за нами»")
	ok(await _press(p2.card.buttons["menu"]), "«В меню» на карточке нажимается")
	await hooks.frames(2)
	eq(str(main.get("mode")), "menu", "«В меню» — меню")
	var m: QuickMenu = main.get("menu")
	eq(str(m.cfg["attacker"]), str(cfg0["attacker"]), "меню помнит прошлый выбор")
	await _done(main)


## Отчёт боя человека — тот же, что у стенда (план G5, п. 5): бой с видом и вводом (рамка,
## ПКМ по полю), потом тот же бой из записи без вида — отчёты совпадают всем, кроме времени
## шага и сборки. Откат: запись без последнего приказа — отчёты расходятся.
func test_report_same_as_stand() -> void:
	var main := await _main("quick_report")
	ok(await _press(_menu_btn(main, "go")), "«В бой»")
	await hooks.frames(3)
	var p: Polygon = main.get("polygon")
	p.view.rig.edge_enabled = false
	p.view.speed = 4
	# рамка по всему экрану и ПКМ вперёд — свой флот получает приказ
	var a := Vector2(40, 120)
	var z := Vector2(1320, 640)
	await hooks.move(a)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = a
	down.global_position = a
	Input.parse_input_event(down)
	await hooks.frames(1)
	for i in 8:
		await hooks.move(a.lerp(z, float(i + 1) / 8.0))
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	up.position = z
	up.global_position = z
	Input.parse_input_event(up)
	await hooks.frames(2)
	await hooks.click(Vector2(683, 260), MOUSE_BUTTON_RIGHT)
	for i in 60:
		await hooks.frames(1)
	var b := p.battle
	ok(b.cmds.journal.size() > 0, "приказы ввода — в журнале боя (%d)" % b.cmds.journal.size())
	b.finish(-1, true)
	await hooks.frames(3)
	var rep := p.report
	var rec := b.record()
	var same := _replay_report(rec, b.steps)
	var diff := _diff(rep, same)
	ok(diff.is_empty(), "отчёт боя с видом и вводом совпал с отчётом того же боя без вида: %s" % (", ".join(diff) if not diff.is_empty() else "все поля"))
	var cut := rec.duplicate(true)
	var cmds: Array = cut["cmds"]
	if not cmds.is_empty():
		cmds.pop_back()
	var other := _replay_report(cut, b.steps)
	ok(not _diff(rep, other).is_empty(), "откат «запись без последнего приказа»: отчёты разошлись — сверка различает")
	await _done(main)


func _replay_report(rec: Dictionary, steps: int) -> Dictionary:
	var defs := Defs.load_default() as Defs
	var why := PackedStringArray()
	var r := Battle.from_record(defs, rec, MainScript.release_name(), why) as Battle
	if r == null:
		return {"беда": "; ".join(why)}
	while r.steps < steps:
		r.step()
	r.finish(-1, true)
	var rep := Report.of(r, PackedFloat64Array(), MainScript.release_name(), OS.get_name())
	r.dispose()
	return rep


## Поля, в которых отчёты расходятся (кроме времени шага: его меряют настоящие часы).
static func _diff(a: Dictionary, b: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in a:
		if k == "step_ms":
			continue
		if not b.has(k) or JSON.stringify(a[k]) != JSON.stringify(b[k]):
			out.append(k)
	for k: String in b:
		if not a.has(k):
			out.append(k)
	return out
