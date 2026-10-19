# Экран боя (план GИ): кнопки вместо одних клавиш, шапка, ростер, сетка команд, тактические
# знаки над кораблями, тонкие кольца. Всё — настоящими событиями ввода (hooks.gd) и вопросом
# «что под точкой» (hovered_at — аналог elementFromPoint), а не «кнопка есть в дереве». Без окна
# (ярус ui): раскладка, попадание мышью и раскладка знаков считаются и так; ЦВЕТ на экране —
# в tests/test_hud_*.gd (ярус hud, с окном). Каждая проверка — с откатом, который её краснит.
extends "res://tests/case.gd"

const MainScene := preload("res://main.tscn")
const MainScript := preload("res://main.gd")
const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Squad := preload("res://sim/squad.gd")
const State := preload("res://sim/state.gd")
const Weapons := preload("res://sim/weapons.gd")
const HeavyDoctrine := preload("res://sim/heavy_doctrine.gd")
const Polygon := preload("res://tools/polygon.gd")
const QuickMenu := preload("res://ui/quick_menu.gd")
const PolygonHud := preload("res://ui/polygon_hud.gd")
const BattleInput := preload("res://input/battle_input.gd")
const BattleView := preload("res://view/battle_view.gd")
const BattleFx := preload("res://view/battle_fx.gd")
const CameraRig := preload("res://view/camera_rig.gd")
const Builder := preload("res://ui/builder.gd")
const Texts := preload("res://ui/texts.gd")
const CommandGrid := preload("res://ui/command_grid.gd")
const HudHeader := preload("res://ui/hud_header.gd")
const HudTooltip := preload("res://ui/hud_tooltip.gd")
const Roster := preload("res://ui/roster.gd")
const Markers := preload("res://view/markers.gd")
const Picking := preload("res://input/picking.gd")
const Settings := preload("res://view/settings.gd")

## Клавиша (по месту) каждой команды, у которой она есть: проверка «кнопка = клавиша».
const KEY_OF := {&"amove": KEY_A, &"hold": KEY_H, &"guard": KEY_Y, &"hunt": KEY_T, &"drift": KEY_D,
	&"hyper": KEY_G, &"launch_interceptor": KEY_Z, &"launch_fighter": KEY_X, &"launch_bomber": KEY_C,
	&"recall": KEY_V, &"ecm_jam": KEY_J, &"ecm_shield": KEY_K, &"ecm_off": KEY_L}

var _main: Node


# ───────────────────────── общее ─────────────────────────

## Быстрый бой по выбору меню (Тройден × Плэктор, «Сражение»), зерно 4242, на паузе, без края
## экрана. Знаки — по умолчанию (включены): настройки — в своём файле прогона.
func _open(size: Vector2i, watch: bool = false, mirror: bool = false, dir: String = "hud") -> Polygon:
	await hooks.set_window_size(size)
	Settings.path = tmp(dir + "_settings.cfg")
	if FileAccess.file_exists(Settings.path):
		DirAccess.remove_absolute(Settings.path)
	MainScript.out_override = tmp(dir)
	MainScript.seed_override = 4242
	_main = MainScene.instantiate()
	tree.root.add_child(_main)
	await hooks.frames(3)
	var defs: Defs = _main.get("defs")
	var cfg := QuickMenu.default_cfg(defs, watch)
	if mirror:
		cfg["defender"] = cfg["attacker"]
	_main.call("open_battle", cfg)
	await hooks.frames(4)
	var p: Polygon = _main.get("polygon")
	p.view.paused = true
	p.view.rig.edge_enabled = false
	await hooks.frames(3)
	return p


## Как у игрока: главная сцена открывает меню «Быстрый бой», бой выбирается кнопкой меню
## НАСТОЯЩИМ щелчком («go» — «В бой», «watch» — «Смотреть: ИИ против ИИ»). null — кнопка
## не нажалась или бой не открылся.
func _open_by_menu(size: Vector2i, key: String) -> Polygon:
	await hooks.set_window_size(size)
	Settings.path = tmp("hud_menu_settings.cfg")
	if FileAccess.file_exists(Settings.path):
		DirAccess.remove_absolute(Settings.path)
	MainScript.out_override = tmp("hud_menu")
	MainScript.seed_override = 4242
	_main = MainScene.instantiate()
	tree.root.add_child(_main)
	await hooks.frames(4)
	var m: QuickMenu = _main.get("menu")
	var mb: Button = m.buttons.get(key) if m != null else null
	if not await _press(mb):
		return null
	await hooks.frames(4)
	var p: Polygon = _main.get("polygon")
	if p == null:
		return null
	p.view.paused = true
	p.view.rig.edge_enabled = false
	await hooks.frames(3)
	return p


func _close() -> void:
	MainScript.out_override = ""
	MainScript.seed_override = -1
	Settings.path = Settings.DEFAULT_PATH
	if _main != null:
		var p: Polygon = _main.get("polygon")
		var b: Battle = p.battle if p != null else null
		_main.queue_free()
		_main = null
		await hooks.frames(2)
		if b != null:
			b.dispose()


func _own(p: Polygon) -> Array[Ship]:
	var out: Array[Ship] = []
	for s in p.battle.side_ships(p.view.my_side):
		if not s.dead and not s.station:
			out.append(s)
	return out


func _first(p: Polygon, pred: Callable) -> Ship:
	for s in _own(p):
		if pred.call(s):
			return s
	return null


## Шаги боя без ожидания кадров (вид разбирает события — прибывших, гибель): пауза снимается
## только на время цикла.
func _steps(p: Polygon, n: int) -> void:
	p.view.paused = false
	for i in n:
		p.view.advance(Battle.STEP)
	p.view.paused = true


## Хвост журнала команд с номера from — без шага (кнопка и клавиша жмутся в разные кадры).
func _tail(p: Polygon, from: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var j: Array[Dictionary] = p.battle.cmds.journal
	for i in range(from, j.size()):
		var d := j[i].duplicate()
		d.erase("step")
		out.append(d)
	return out


## Нажать кнопку настоящим щелчком; false — под её серединой не она (закрыта или за краем).
func _press(b: Button) -> bool:
	if b == null or not b.is_visible_in_tree():
		return false
	var c := b.get_global_rect().get_center()
	var under := await hooks.hovered_at(c)
	if under != b:
		return false
	await hooks.click(c)
	return true


## Видимые кнопки экрана боя (шапка, сетка, ростер, быстрый выбор).
func _buttons(p: Polygon) -> Array[Button]:
	var out: Array[Button] = []
	var stack: Array[Node] = [p.hud]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == p.hud.tooltip or n == p.hud.confirm:
			continue
		var b := n as Button
		if b != null and b.is_visible_in_tree():
			out.append(b)
		stack.append_array(n.get_children())
	return out


## Полный набор команд сетки: тяжёлый, носитель, РЭБ и своё звено (звено поднимается с носителя
## и успевает выйти за 40 шагов).
func _rich_selection(p: Polygon) -> Array[int]:
	var heavy := _first(p, func(s: Ship) -> bool: return s.heavy() and s.hangar == null)
	var car := _first(p, func(s: Ship) -> bool: return s.hangar != null)
	var ecm := _first(p, func(s: Ship) -> bool: return s.def.ecm)
	var sel: Array[int] = []
	if heavy == null or car == null or ecm == null:
		return sel
	p.battle.queue({"op": &"launch", "ids": PackedInt32Array([car.uid]), "role": &"interceptor"})
	_steps(p, 40)
	var q: Squad = null
	for o in p.battle.squads:
		if not o.dead and o.side == p.view.my_side and not o.craft.is_empty():
			q = o
			break
	if q == null:
		return sel
	sel = [heavy.uid, car.uid, ecm.uid, q.uid]
	return sel


# ───────────────────────── кнопки: сканер ─────────────────────────

## Каждая видимая кнопка — целиком в окне, под её серединой — она сама (не закрыта соседом),
## надпись влезает (шрифтом кнопки, с полями 4 + 4), кнопки не наезжают друг на друга.
func _scan_buttons(p: Polygon, vs: Vector2) -> Dictionary:
	var bad := PackedStringArray()
	var list := _buttons(p)
	for b in list:
		var r := b.get_global_rect()
		if r.position.x < 0.0 or r.position.y < 0.0 or r.end.x > vs.x + 0.5 or r.end.y > vs.y + 0.5:
			bad.append("«%s» за краем окна %s" % [_btn_name(b), r])
			continue
		var under := await hooks.hovered_at(r.get_center())
		if under != b:
			bad.append("«%s» закрыта: под серединой %s" % [_btn_name(b), under.name if under != null else "поле"])
		if b.text != "":
			var fs := b.get_theme_font_size("font_size")
			var tw := Builder.text_w(b, b.text, fs)
			if tw + 8.0 > b.size.x + 0.5:
				bad.append("«%s» не влезает: %.0f > %.0f" % [b.text, tw + 8.0, b.size.x])
		# слово и мелкая строка кнопки сетки: Label растёт под текст, а кнопка режет лишнее
		# (clip_contents) — мерить надо против места НА КНОПКЕ: слово — ширина без полей 4 + 4,
		# мелкая строка — без буквы клавиши справа (26)
		for lname: String in ["word", "top"]:
			var l := b.get_node_or_null(lname) as Label
			if l == null or l.text == "":
				continue
			var lfs := l.get_theme_font_size("font_size")
			var lw := Builder.text_w(l, l.text, lfs)
			var room := b.size.x - (8.0 if lname == "word" else 30.0)
			if lw > room + 0.5:
				bad.append("«%s» на кнопке %s не влезает: %.0f > %.0f" % [l.text, b.name, lw, room])
	for i in list.size():
		for j in range(i + 1, list.size()):
			if list[i].get_global_rect().intersects(list[j].get_global_rect()):
				bad.append("«%s» наезжает на «%s»" % [_btn_name(list[i]), _btn_name(list[j])])
	return {"n": list.size(), "bad": bad}


static func _btn_name(b: Button) -> String:
	if b.text != "":
		return b.text
	var w := b.get_node_or_null("word") as Label
	return w.text if w != null else str(b.name)


## Обратный сканер: точки окна через 12 точек — под каждой либо никого (щелчок уходит в поле),
## либо кнопка, либо панель, которая ловит мышь нарочно (Builder.stop). Раскладочный узел,
## поймавший мышь, — это пустое место, которое глотает щелчок по полю (C135).
func _scan_empty(vs: Vector2) -> PackedStringArray:
	var bad := PackedStringArray()
	var seen: Dictionary[String, int] = {}
	var y := 6.0
	while y < vs.y:
		var x := 6.0
		while x < vs.x:
			var mv := InputEventMouseMotion.new()
			mv.position = Vector2(x, y)
			mv.global_position = mv.position
			tree.root.push_input(mv)
			var c := tree.root.gui_get_hovered_control()
			if c != null and not (c is BaseButton) and not c.has_meta(Builder.STOP_META):
				var k := "%s (%s)" % [c.name, c.get_class()]
				if not seen.has(k):
					seen[k] = 0
					bad.append("%s в (%d, %d)" % [k, roundi(x), roundi(y)])
				seen[k] += 1
			x += 12.0
		y += 12.0
	return bad


func _scan_at(size: Vector2i, rich: bool, busy: bool = false) -> Dictionary:
	var p := await _open(size)
	var vs := Vector2(size)
	if rich:
		p.view.selection = _rich_selection(p)
	else:
		await hooks.key(KEY_F2)
	if busy:
		_busy_fleet(p)
	await hooks.frames(4)
	var got := await _scan_buttons(p, vs)
	got["empty"] = _scan_empty(vs)
	got["grid"] = p.hud.grid.buttons.size()
	# текст «что выбрано» — целиком: строк не больше, чем видно в панели постоянной высоты
	var sl := p.hud.sel_label
	got["lines"] = "%d из %d" % [sl.get_line_count(), sl.max_lines_visible]
	got["cut"] = sl.get_line_count() > sl.max_lines_visible
	got["text"] = sl.text.replace("\n", " | ")
	await _close()
	return got


## Занятие тяжёлых — длинное и НЕ от того, сколько шагов боя успело пройти до паузы: оба
## выходят на дистанцию к чужому тяжёлому («выходит на дистанцию · 1068 до «Исса» III»). Так
## текст панели заведомо не влезает целиком в четыре строки. На медленной машине до паузы
## успевает пройти больше шагов, и флагман сам начинал выходить на дистанцию, а в CI — нет:
## проверка отката «режется по высоте» зеленела там на коротком «стоит».
func _busy_fleet(p: Polygon) -> void:
	var foe: Ship = null
	for s in p.battle.side_ships(1 - p.view.my_side):
		if not s.dead and s.heavy():
			foe = s
			break
	for s in _own(p):
		if s.heavy() and not s.legacy and foe != null:
			s.belt = HeavyDoctrine.APPROACH
			s.forced = foe


func test_buttons_on_screen_and_reachable() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		for rich: bool in [false, true]:
			var got := await _scan_at(size, rich)
			var bad: PackedStringArray = got["bad"]
			var n: int = got["n"]
			var what := "весь флот (F2)" if not rich else "тяжёлый + носитель + РЭБ + звено (сетка %d)" % whole(got["grid"])
			note("%d×%d, %s: кнопок %d, бед %d %s" % [size.x, size.y, what, n, bad.size(), "; ".join(bad.slice(0, 4))])
			ok(n >= 15 and bad.is_empty(), "%d×%d, %s: все %d кнопок в окне, нажимаются и надписи целиком" % [size.x, size.y, what, n])
			note("%d×%d, %s: панель — строк %s: «%s»" % [size.x, size.y, what, got["lines"], got["text"]])
			ok(not flag(got["cut"]), "%d×%d, %s: текст панели целиком, ни одной обрезанной строки" % [size.x, size.y, what])
			var empty: PackedStringArray = got["empty"]
			ok(empty.is_empty(), "%d×%d, %s: пустые места экрана щелчок не глотают (%s)" % [size.x, size.y, what, "; ".join(empty)])
	# откат «раскладка как на 1920»: на 1366 столбик быстрого выбора за краем окна
	PolygonHud.rollback_fixed_layout = true
	var r := await _scan_at(Vector2i(1366, 768), false)
	PolygonHud.rollback_fixed_layout = false
	var rb: PackedStringArray = r["bad"]
	ok(not rb.is_empty(), "откат «раскладка не смотрит на ширину окна» краснеет: %s" % "; ".join(rb.slice(0, 3)))
	# длинные занятия: текст не режется, а короче — уходит строка мыши, лишние занятия (_fit_sel);
	# откат «текст панели целиком, лишнее срезается по высоте» — режется
	var bz := await _scan_at(Vector2i(1366, 768), false, true)
	note("1366, весь флот, тяжёлые выходят на дистанцию: панель — строк %s: «%s»" % [bz["lines"], bz["text"]])
	ok(not flag(bz["cut"]), "1366, весь флот, у тяжёлых длинное занятие: текст панели целиком (строк %s)" % bz["lines"])
	PolygonHud.rollback_panel_cut = true
	var rc := await _scan_at(Vector2i(1366, 768), false, true)
	PolygonHud.rollback_panel_cut = false
	ok(flag(rc["cut"]), "откат «текст режется по высоте панели» краснеет: строк %s" % rc["lines"])
	# откат «строитель не ставит IGNORE»: промежутки столбика и полоски шапки ловят мышь
	Builder.rollback_no_ignore = true
	var r2 := await _scan_at(Vector2i(1366, 768), false)
	Builder.rollback_no_ignore = false
	var re: PackedStringArray = r2["empty"]
	ok(not re.is_empty(), "откат «без IGNORE» краснеет обратным сканером: %s" % "; ".join(re.slice(0, 3)))


## Длинное слово («Бомбардировщик») на узкой кнопке 1366 — мельче, а не обрезано.
func test_grid_words_fit() -> void:
	for roll: bool in [false, true]:
		CommandGrid.rollback_word_14 = roll
		var p := await _open(Vector2i(1366, 768))
		p.view.selection = _rich_selection(p)
		await hooks.frames(4)
		var bad := PackedStringArray()
		for id: StringName in p.hud.grid.buttons:
			var wl := p.hud.grid.buttons[id].get_node("word") as Label
			var w := Builder.text_w(wl, wl.text, wl.get_theme_font_size("font_size"))
			var room := p.hud.grid.buttons[id].size.x - 8.0
			if w > room + 0.5:
				bad.append("%s %.0f > %.0f" % [wl.text, w, room])
			if id == &"launch_bomber":
				note("«%s»: кегль %d, %.0f точек из %.0f%s" % [wl.text, wl.get_theme_font_size("font_size"), w, room, " (откат)" if roll else ""])
		var bomb: Button = p.hud.grid.buttons.get(&"launch_bomber")
		var fs := (bomb.get_node("word") as Label).get_theme_font_size("font_size") if bomb != null else 0
		CommandGrid.rollback_word_14 = false
		if not roll:
			ok(bomb != null and bad.is_empty(), "все слова сетки на 1366 влезают («Бомбардировщик» кеглем %d)" % fs)
		else:
			ok(not bad.is_empty(), "откат «всегда кегль 14» краснеет: %s" % "; ".join(bad))
		await _close()


# ───────────────────────── кнопка = клавиша ─────────────────────────

## Одна команда клавишей и кнопкой при одном выборе: в журнал боя ложится одно и то же,
## счётчик двери command() растёт у обоих.
func _key_vs_button(p: Polygon, id: StringName, sel: Array[int]) -> Dictionary:
	p.view.selection = sel.duplicate()
	await hooks.frames(2)
	var b: Button = p.hud.grid.buttons.get(id)
	if b == null:
		return {"bad": "кнопки нет"}
	var done0: int = p.input.commands_done.get(id, 0)
	var n0 := p.battle.cmds.journal.size()
	var kk: Key = KEY_OF[id]
	await hooks.key(kk)
	await hooks.frames(1)
	var by_key := _tail(p, n0)
	var armed_key := p.input.amove_armed
	await hooks.key(KEY_ESCAPE)                 # снять ожидание A (выбор цел)
	p.view.selection = sel.duplicate()
	await hooks.frames(2)
	var done1: int = p.input.commands_done.get(id, 0)
	var n1 := p.battle.cmds.journal.size()
	var gb: Button = p.hud.grid.buttons.get(id)
	var pressed := await _press(gb)
	await hooks.frames(1)
	var by_btn := _tail(p, n1)
	var armed_btn := p.input.amove_armed
	await hooks.key(KEY_ESCAPE)
	var done2: int = p.input.commands_done.get(id, 0)
	var same := by_key == by_btn and armed_key == armed_btn
	var bad := ""
	if not pressed:
		bad = "кнопка не нажалась"
	elif not same:
		bad = "клавиша %s, кнопка %s" % [str(by_key), str(by_btn)]
	elif done1 - done0 != 1 or done2 - done1 != 1:
		bad = "дверь command(): клавиша +%d, кнопка +%d" % [done1 - done0, done2 - done1]
	elif by_key.is_empty() and not armed_key:
		bad = "ни команды, ни ожидания"
	return {"bad": bad, "key": by_key}


func _grid_equals_keys(rollback: bool) -> PackedStringArray:
	PolygonHud.rollback_button_own_door = rollback
	var p := await _open(Vector2i(1366, 768))
	var sel := _rich_selection(p)
	var bad := PackedStringArray()
	if sel.is_empty():
		bad.append("нет тяжёлого, носителя, РЭБ или звена")
	else:
		await hooks.frames(3)
		for id: StringName in Texts.GRID_ORDER:
			var r := await _key_vs_button(p, id, sel)
			var why: String = r["bad"]
			if why != "":
				bad.append("%s: %s" % [id, why])
	PolygonHud.rollback_button_own_door = false
	await _close()
	return bad


func test_grid_button_is_its_key() -> void:
	var bad := await _grid_equals_keys(false)
	ok(bad.is_empty(), "13 кнопок сетки — каждая делает ровно то, что её клавиша (журнал боя): %s" % "; ".join(bad))
	var rb := await _grid_equals_keys(true)
	ok(rb.size() >= 3, "откат «кнопка тактики своей дверью — всему флоту» краснеет: %s" % "; ".join(rb))


## Шапка и столбик: пауза, скорость, «Весь флот», «Знаки» — кнопкой и клавишей одинаково.
func test_header_and_column_are_their_keys() -> void:
	var p := await _open(Vector2i(1366, 768))
	var h := p.hud.header
	# скорость: 2 и кнопка «2×», 4 и «4×», 1 и «1×»
	for pair: Array in [[KEY_2, &"speed2", 2], [KEY_4, &"speed4", 4], [KEY_1, &"speed1", 1]]:
		var pk: Key = pair[0]
		var pid: StringName = pair[1]
		var want: int = pair[2]
		p.view.speed = 3
		await hooks.key(pk)
		var by_key := p.view.speed
		p.view.speed = 3
		await _press(h.buttons[pid])
		ok(by_key == want and p.view.speed == want, "%s: клавиша — %d, кнопка — %d" % [pid, by_key, p.view.speed])
	# пауза: Пробел и кнопка переключают одинаково
	p.view.paused = true
	await hooks.key(KEY_SPACE)
	var k1 := p.view.paused
	await _press(h.buttons[&"pause"])
	var b1 := p.view.paused
	p.view.paused = true
	ok(k1 == false and b1 == true, "Пробел снял паузу, кнопка «Пауза» вернула (%s, %s)" % [k1, b1])
	# весь флот: F2 и кнопка — одна и та же выборка
	p.view.selection = []
	await hooks.key(KEY_F2)
	var f2: Array[int] = p.view.selection.duplicate()
	p.view.selection = []
	await _press(p.hud.quick_buttons[&"all"])
	ok(not f2.is_empty() and p.view.selection == f2, "«Весь флот» = F2: %d кораблей" % f2.size())
	# знаки: I и кнопка
	var m0 := p.view.markers.on
	await hooks.key(KEY_I)
	var m1 := p.view.markers.on
	await _press(p.hud.quick_buttons[&"markers"])
	var m2 := p.view.markers.on
	ok(m1 != m0 and m2 == m0, "I и кнопка «Знаки» переключают знаки (%s → %s → %s)" % [m0, m1, m2])
	await _close()


## Вид кнопки сетки: «горит» / «часть» / обычная / недоступна (ui/builder.gd → Look) и мелкая
## строка над словом.
static func _grid_look(p: Polygon, id: StringName) -> String:
	var b: Button = p.hud.grid.buttons.get(id)
	if b == null or not b.is_visible_in_tree():
		return "нет кнопки"
	var how: int = b.get_meta(&"cf_look", -1)
	var names := {Builder.Look.NORMAL: "обычная", Builder.Look.ON: "горит", Builder.Look.PART: "часть", Builder.Look.OFF: "недоступна"}
	var top := (b.get_node("top") as Label).text
	var word := (b.get_node("word") as Label).text
	return "%s «%s» [%s]%s" % [names.get(how, "?"), word, top, " выкл" if b.disabled else ""]


## Подсветка сетки из выбора (план GИ, п. 5; 07, 1.8 — C26, C136): тактика и дрифт «горят», когда
## они у ВСЕХ выбранных, и стоят «частью» с мелкой строкой «1 из 2», когда у некоторых; гипер
## копится — кнопка «Отменить гипер» горит; пуск — «ангар N» и недоступен без свободных мест;
## купол — горит нынешний режим РЭБ. Состояние ставится прямо в модели (бой на паузе): проверяется,
## что экран его ЧИТАЕТ. До доработки GИ у этого правила не было ни одной проверки — порча
## `_part_look` («горит» при любом k > 0) оставляла все ярусы зелёными; откат — порчей кода
## (godot/CLAUDE.md, 22).
func test_grid_lights_from_selection() -> void:
	var p := await _open(Vector2i(1366, 768))
	var cs: Array[Ship] = []
	for s in _own(p):
		if s.def.id == &"corvette" and cs.size() < 2:
			cs.append(s)
	var car := _first(p, func(s: Ship) -> bool: return s.hangar != null)
	var ecm := _first(p, func(s: Ship) -> bool: return s.def.ecm)
	if not ok(cs.size() == 2 and car != null and ecm != null, "в составе есть два корвета, носитель и РЭБ"):
		await _close()
		return
	for s in cs:
		s.stance = &"guard"
		s.drift = false
	p.view.selection = [cs[0].uid, cs[1].uid]
	await hooks.frames(3)
	ok(_grid_look(p, &"guard") == "горит «Охрана» [тактика]" and _grid_look(p, &"hunt") == "обычная «Охота» [тактика]",
		"оба на «Охране» — «Охрана» горит, «Охота» обычная: %s · %s" % [_grid_look(p, &"guard"), _grid_look(p, &"hunt")])
	cs[0].stance = &"hunt"
	await hooks.frames(2)
	ok(_grid_look(p, &"hunt") == "часть «Охота» [1 из 2]" and _grid_look(p, &"guard") == "часть «Охрана» [1 из 2]" and _grid_look(p, &"hold") == "обычная «Держать» [тактика]",
		"тактики разные — «часть» и «1 из 2» у обеих, «Держать» обычная: %s · %s · %s" % [_grid_look(p, &"hunt"), _grid_look(p, &"guard"), _grid_look(p, &"hold")])
	cs[0].drift = true
	await hooks.frames(2)
	var d1 := _grid_look(p, &"drift")
	cs[1].drift = true
	await hooks.frames(2)
	var d2 := _grid_look(p, &"drift")
	ok(d1 == "часть «Дрифт» [1 из 2]" and d2 == "горит «Дрифт» [ход]", "дрифт у одного — «часть», у обоих — горит: %s → %s" % [d1, d2])
	p.battle.queue({"op": &"hyper", "ids": PackedInt32Array([cs[0].uid])})
	_steps(p, 2)
	await hooks.frames(2)
	ok(cs[0].charging() and _grid_look(p, &"hyper") == "горит «Отменить гипер» [гипер]", "копит гипер — кнопка «Отменить гипер» горит: %s" % _grid_look(p, &"hyper"))
	p.view.selection = [car.uid]
	await hooks.frames(3)
	var l1 := _grid_look(p, &"launch_interceptor")
	var free0 := car.hangar.free
	car.hangar.free = 0
	await hooks.frames(2)
	var l2 := _grid_look(p, &"launch_interceptor")
	car.hangar.free = free0
	ok(free0 > 0 and l1 == "обычная «Перехватчик» [ангар %d]" % free0 and l2 == "недоступна «Перехватчик» [ангар 0] выкл",
		"пуск — «ангар %d», без мест недоступен: %s → %s" % [free0, l1, l2])
	p.view.selection = [ecm.uid]
	ecm.ecm_mode = &"jam"
	await hooks.frames(3)
	var e1 := "%s · %s" % [_grid_look(p, &"ecm_jam"), _grid_look(p, &"ecm_shield")]
	ecm.ecm_mode = &"shield"
	await hooks.frames(2)
	var e2 := "%s · %s" % [_grid_look(p, &"ecm_jam"), _grid_look(p, &"ecm_shield")]
	ok(e1 == "горит «Глушение» [купол] · обычная «Прикрытие» [купол]" and e2 == "обычная «Глушение» [купол] · горит «Прикрытие» [купол]",
		"купол — горит нынешний режим: %s → %s" % [e1, e2])
	await _close()


## Часы орудия планеты в шапке (план GИ, п. 2; 07, 2.4): «<орудие> N с» по игровым часам, за секунду
## до залпа — «залп», в окне предупреждения кнопка горит, подсказка называет орудие; орудия нет —
## нет и плашки (07, ловушка 52). Откат — порчей кода (godot/CLAUDE.md, 22).
func test_header_gun_clock() -> void:
	var p := await _open(Vector2i(1366, 768))
	var h := p.hud.header
	var gun := p.battle.gun
	if not ok(gun != null, "в быстром бою у защитника есть орудие планеты"):
		await _close()
		return
	await hooks.frames(2)
	var left := gun.next - p.battle.time
	var t1 := h.gun_btn.text
	var lk1: int = h.gun_btn.get_meta(&"cf_look", -1)
	var tip: String = h.gun_btn.get_meta(&"cf_tip", "")
	ok(h.gun_btn.is_visible_in_tree() and t1 == "%s %d с" % [gun.def.short, ceili(left)] and lk1 == Builder.Look.NORMAL and tip.contains(gun.def.name),
		"часы орудия: «%s» (до залпа %.1f с), подсказка называет «%s»" % [t1, left, gun.def.name])
	# к залпу: остаётся меньше секунды — «залп», кнопка горит (окно предупреждения)
	_steps(p, maxi(0, ceili((left - 0.5) / Battle.STEP)))
	await hooks.frames(2)
	var left2 := gun.next - p.battle.time
	var t2 := h.gun_btn.text
	var lk2: int = h.gun_btn.get_meta(&"cf_look", -1)
	ok(left2 > 0.0 and left2 < 1.0 and t2 == "%s залп" % gun.def.short and lk2 == Builder.Look.ON,
		"за %.2f с до залпа — «%s», кнопка горит" % [left2, t2])
	# орудия нет — плашки нет, шапка без пустого места
	p.battle.gun = null
	await hooks.frames(2)
	ok(not h.gun_btn.is_visible_in_tree() and not h.shown_buttons().has(h.gun_btn), "орудия нет — плашки часов нет")
	await _close()


## Ни одна клавиша не потеряна: у каждой команды клавиш (KEY_CMD) есть кнопка — в сетке при
## полном выборе, в шапке или в столбике.
func _lost_keys(drop: StringName) -> PackedStringArray:
	PolygonHud.rollback_drop_cmd = drop
	var p := await _open(Vector2i(1366, 768))
	p.view.selection = _rich_selection(p)
	await hooks.frames(4)
	var have: Dictionary[StringName, bool] = {}
	for id: StringName in p.hud.grid.buttons:
		if p.hud.grid.buttons[id].is_visible_in_tree():
			have[id] = true
	for id: StringName in p.hud.header.buttons:
		if p.hud.header.buttons[id].is_visible_in_tree():
			have[id] = true
	for id: StringName in p.hud.quick_buttons:
		if p.hud.quick_buttons[id].is_visible_in_tree():
			have[id] = true
	have[&"arrived"] = have.has(&"reinforce")          # та же кнопка в режиме «Прибывшие (N)»
	var lost := PackedStringArray()
	for k: Key in BattleInput.KEY_CMD:
		var id: StringName = BattleInput.KEY_CMD[k]
		if not have.has(id):
			lost.append("%s (%s)" % [id, OS.get_keycode_string(k)])
	PolygonHud.rollback_drop_cmd = &""
	await _close()
	return lost


func test_no_key_lost() -> void:
	var lost := await _lost_keys(&"")
	ok(lost.is_empty(), "у всех %d клавиш команд есть кнопка: потеряны %s" % [BattleInput.KEY_CMD.size(), ", ".join(lost)])
	var rl := await _lost_keys(&"drift")
	ok(rl.size() == 1 and rl[0].begins_with("drift"), "откат «нет кнопки Дрифта» краснеет: %s" % ", ".join(rl))


# ───────────────────────── медленный щелчок, подсказка, гибель выбранного ─────────────────────────

## C30: кнопку «Перехватчик» держат 150 мс и 9 кадров — щелчок не теряется (сетка не
## пересоздаётся), звено поднимается.
func _slow_click(rollback: bool) -> Dictionary:
	CommandGrid.rollback_rebuild = rollback
	var p := await _open(Vector2i(1366, 768))
	var car := _first(p, func(s: Ship) -> bool: return s.hangar != null)
	p.view.selection = [car.uid]
	await hooks.frames(3)
	var b: Button = p.hud.grid.buttons.get(&"launch_interceptor")
	var r0 := p.hud.grid.rebuilds
	var n0 := p.battle.cmds.journal.size()
	var c := b.get_global_rect().get_center()
	await hooks.move(c)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = c
	ev.global_position = c
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)
	await hooks.frames(9)
	await tree.create_timer(0.15).timeout
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	up.button_mask = 0
	Input.parse_input_event(up)
	await hooks.frames(3)
	var got := _tail(p, n0)
	var rebuilt := p.hud.grid.rebuilds - r0
	_steps(p, 40)
	var nq := 0
	for q in p.battle.squads:
		if not q.dead and q.side == p.view.my_side:
			nq += 1
	CommandGrid.rollback_rebuild = false
	await _close()
	var launched: bool = got.size() == 1 and got[0].get("op") == &"launch"
	return {"hunt": launched and nq == 1, "rebuilt": rebuilt, "up": nq}


func test_slow_click_not_lost() -> void:
	var r := await _slow_click(false)
	ok(flag(r["hunt"]) and whole(r["rebuilt"]) == 0, "медленный щелчок по «Перехватчику» (150 мс, 9 кадров) — звено поднялось, сетка не пересобиралась (%d)" % whole(r["rebuilt"]))
	var o := await _slow_click(true)
	ok(not flag(o["hunt"]) and whole(o["up"]) == 0, "откат «сетка пересобирается каждый кадр» краснеет: пересборок %d, звеньев %d" % [whole(o["rebuilt"]), whole(o["up"])])


## Подсказка — СРАЗУ при наведении (штатная ждёт полсекунды), со словом и буквой.
func _tip_after_hover(rollback: bool) -> String:
	HudTooltip.rollback_delay = rollback
	var p := await _open(Vector2i(1366, 768))
	var h := _first(p, func(s: Ship) -> bool: return s.heavy())
	p.view.selection = [h.uid]
	await hooks.frames(3)
	var b: Button = p.hud.grid.buttons.get(&"guard")
	await hooks.move(b.get_global_rect().get_center())
	await hooks.frames(1)
	var t := p.hud.tooltip.label.text if p.hud.tooltip.panel.visible else ""
	var inside := p.hud.tooltip.panel.get_global_rect()
	var vs := Vector2(1366, 768)
	var fits := inside.position.x >= 0.0 and inside.end.x <= vs.x and inside.position.y >= 0.0
	HudTooltip.rollback_delay = false
	await _close()
	return t if fits or t == "" else "ЗА КРАЕМ " + t


func test_tooltip_immediate() -> void:
	var t := await _tip_after_hover(false)
	ok(t.begins_with("Охрана · Y") and t.contains("участок"), "подсказка «Охраны» через кадр после наведения, в окне: «%s»" % t.replace("\n", " | "))
	var o := await _tip_after_hover(true)
	ok(o == "", "откат «подсказка через 0,5 с» краснеет: через кадр «%s»" % o)


## Выбранный погиб — панель пишет «Ничего не выбрано» в тот же или следующий кадр.
func _dead_selected(rollback: bool) -> Array[String]:
	BattleView.rollback_keep_dead = rollback
	var p := await _open(Vector2i(1366, 768))
	var s := _first(p, func(x: Ship) -> bool: return x.def.id == &"corvette")
	p.view.selection = [s.uid]
	await hooks.frames(2)
	var before := p.hud.sel_label.text
	Weapons.damage(p.battle, s, s.hp * 4.0 + 1000.0, &"main", null, Vector2.ZERO)
	var after: Array[String] = [before]
	for i in 2:
		await hooks.frames(1)
		after.append(p.hud.sel_label.text)
	BattleView.rollback_keep_dead = false
	await _close()
	return after


func test_selected_dies_nothing_selected() -> void:
	var t := await _dead_selected(false)
	ok(not t[0].begins_with(Texts.NOTHING), "до гибели панель про корвет: «%s»" % t[0].get_slice("\n", 0))
	ok(t[1].begins_with(Texts.NOTHING) or t[2].begins_with(Texts.NOTHING), "погиб — «Ничего не выбрано» в тот же или следующий кадр («%s»)" % t[2].get_slice("\n", 0))
	var o := await _dead_selected(true)
	ok(not o[2].begins_with(Texts.NOTHING), "откат «выбор не чистится» краснеет: «%s»" % o[2].get_slice("\n", 0))


# ───────────────────────── подкрепление, отход, быстрый выбор, ростер ─────────────────────────

## Кнопка подкрепления — три режима: «Подкрепление (N) · B» → «Гипер N с» (недоступна) →
## «Прибывшие (N) · N»; нажатие в третьем и N выбирают прибывших.
func _reinforce(rollback: bool) -> Dictionary:
	HudHeader.rollback_no_arrived = rollback
	var p := await _open(Vector2i(1366, 768))
	var rb := p.hud.header.buttons[&"reinforce"]
	var out := {}
	out["call"] = rb.text
	var n0 := p.battle.cmds.journal.size()
	out["pressed"] = await _press(rb)
	var t := _tail(p, n0)
	out["op"] = t.size() == 1 and t[0].get("op") == &"reinforce"
	_steps(p, 2)                                # команда исполняется на следующем шаге
	await hooks.frames(2)
	out["fly"] = rb.text
	out["fly_off"] = rb.disabled
	_steps(p, roundi(40.0 / Battle.STEP))
	await hooks.frames(3)
	out["arrived"] = rb.text
	var want: Array[int] = []
	for u in p.view.arrived:
		var s := p.battle.ship_by_uid(u)
		if s != null and not s.dead:
			want.append(u)
	out["n"] = want.size()
	p.view.selection = []
	out["pressed2"] = await _press(rb)
	var by_btn: Array[int] = p.view.selection.duplicate()
	p.view.selection = []
	await hooks.key(KEY_N)
	var by_key: Array[int] = p.view.selection.duplicate()
	out["sel_ok"] = not want.is_empty() and by_btn == want and by_key == want
	HudHeader.rollback_no_arrived = false
	await _close()
	return out


func test_reinforce_three_modes() -> void:
	var r := await _reinforce(false)
	var call: String = r["call"]
	var fly: String = r["fly"]
	var arr: String = r["arrived"]
	note("подкрепление: «%s» → «%s» → «%s»" % [call, fly, arr])
	ok(call.begins_with("Подкрепление (") and call.ends_with("· B") and flag(r["pressed"]) and flag(r["op"]), "«Подкрепление (N) · B» нажимается и зовёт резерв (команда reinforce)")
	ok(fly.begins_with("Гипер ") and flag(r["fly_off"]), "в пути — «Гипер N с», кнопка недоступна")
	ok(arr == "Прибывшие (%d) · N" % whole(r["n"]) and whole(r["n"]) > 0, "вышли — «Прибывшие (%d) · N»" % whole(r["n"]))
	ok(flag(r["pressed2"]) and flag(r["sel_ok"]), "нажатие «Прибывшие» и клавиша N выбирают тех же %d" % whole(r["n"]))
	var o := await _reinforce(true)
	var oa: String = o["arrived"]
	ok(not oa.begins_with("Прибывшие"), "откат «нет режима Прибывшие» краснеет: «%s»" % oa)


## «Отход» спрашивает: «Остаться» — ничего, «Отступить» — команда retreat.
func _retreat(rollback: bool) -> Dictionary:
	PolygonHud.rollback_retreat_no_ask = rollback
	var p := await _open(Vector2i(1366, 768))
	var tb := p.hud.header.buttons[&"retreat"]
	var n0 := p.battle.cmds.journal.size()
	var out := {}
	out["pressed"] = await _press(tb)
	out["asked"] = p.hud.confirm.is_open()
	out["after_ask"] = _tail(p, n0).size()
	if p.hud.confirm.is_open():
		await _press(p.hud.confirm.find_child("no", true, false) as Button)
	out["after_no"] = _tail(p, n0).size()
	out["closed"] = not p.hud.confirm.is_open()
	await _press(tb)
	if p.hud.confirm.is_open():
		await _press(p.hud.confirm.find_child("yes", true, false) as Button)
	var t := _tail(p, n0)
	out["yes"] = not t.is_empty() and t[t.size() - 1].get("op") == &"retreat"
	PolygonHud.rollback_retreat_no_ask = false
	await _close()
	return out


func test_retreat_asks_first() -> void:
	var r := await _retreat(false)
	ok(flag(r["pressed"]) and flag(r["asked"]) and whole(r["after_ask"]) == 0, "«Отход» — сначала вопрос, команды нет")
	ok(flag(r["closed"]) and whole(r["after_no"]) == 0, "«Остаться» — вопрос закрыт, отхода нет")
	ok(flag(r["yes"]), "«Отступить» — команда отхода")
	var o := await _retreat(true)
	ok(not flag(o["asked"]) and whole(o["after_ask"]) > 0, "откат «отход без вопроса» краснеет: команда ушла сразу (%d)" % whole(o["after_ask"]))


## «Лёгкие» — корветы, фрегаты И корабли РЭБ (09, 6.8: РЭБ стоит с лёгкими).
func _light(rollback: bool) -> Dictionary:
	BattleInput.rollback_ecm_not_light = rollback
	var p := await _open(Vector2i(1366, 768))
	await _press(p.hud.quick_buttons[&"light"])
	var ecm := 0
	var heavy := 0
	for u in p.view.selection:
		var s := p.battle.ship_by_uid(u)
		if s.def.ecm:
			ecm += 1
		if s.heavy():
			heavy += 1
	var n := p.view.selection.size()
	await _press(p.hud.quick_buttons[&"heavy"])
	var hv := 0
	for u in p.view.selection:
		if p.battle.ship_by_uid(u).heavy():
			hv += 1
	var hn := p.view.selection.size()
	BattleInput.rollback_ecm_not_light = false
	await _close()
	return {"n": n, "ecm": ecm, "heavy": heavy, "hn": hn, "hv": hv}


func test_light_includes_ecm() -> void:
	var r := await _light(false)
	ok(whole(r["ecm"]) > 0 and whole(r["heavy"]) == 0, "«Лёгкие»: %d кораблей, РЭБ %d, тяжёлых 0" % [whole(r["n"]), whole(r["ecm"])])
	ok(whole(r["hn"]) > 0 and whole(r["hv"]) == whole(r["hn"]), "«Тяжёлые»: %d, все тяжёлые" % whole(r["hn"]))
	var o := await _light(true)
	ok(whole(o["ecm"]) == 0, "откат «Лёгкие без РЭБ» краснеет")


## Ростер: щелчок — весь класс, следующий — по одному, после последнего — снова весь; Shift —
## добавить. Ростер и панель стоят на месте, что бы ни выбрали.
func _roster(rollback: bool) -> Dictionary:
	BattleInput.rollback_roster_whole = rollback
	var p := await _open(Vector2i(1366, 768))
	var cell: Button = null
	var key := ""
	for k: String in p.hud.roster.cells:
		if k == "s:corvette":
			cell = p.hud.roster.cells[k]
			key = k
	var members: Array = p.hud.roster.members.get(key, [])
	var seq: Array[String] = []
	var y0 := p.hud.roster.position.y
	var py0 := p.hud.panel.position.y
	var ys := PackedFloat64Array()
	for i in members.size() + 2:
		await _press(cell)
		await hooks.frames(1)
		seq.append("%d" % p.view.selection.size() if p.view.selection.size() != 1 else "#%d" % members.find(p.view.selection[0]))
		ys.append(p.hud.roster.position.y)
		ys.append(p.hud.panel.position.y)
	var fr: Button = p.hud.roster.cells.get("s:frigate")
	var before := p.view.selection.size()
	var sh := InputEventKey.new()
	sh.physical_keycode = KEY_SHIFT
	sh.keycode = KEY_SHIFT
	sh.pressed = true
	Input.parse_input_event(sh)
	await hooks.frames(1)
	await _press(fr)
	var up := sh.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await hooks.frames(1)
	var nfr: Array = p.hud.roster.members.get("s:frigate", [])
	var added := p.view.selection.size() - before
	var still := true
	for y in ys:
		still = still and (absf(y - y0) < 0.5 or absf(y - py0) < 0.5)
	BattleInput.rollback_roster_whole = false
	await _close()
	return {"n": members.size(), "seq": " → ".join(seq), "added": added, "nfr": nfr.size(), "still": still}


func test_roster_cycles_and_stays() -> void:
	var r := await _roster(false)
	var n := whole(r["n"])
	var want := PackedStringArray(["%d" % n])
	for i in n:
		want.append("#%d" % i)
	want.append("%d" % n)
	var seq: String = r["seq"]
	note("ростер «Корвет ×%d»: %s" % [n, seq])
	ok(n > 1 and seq == " → ".join(want), "щелчок — весь класс, дальше по одному, после последнего — снова весь")
	ok(whole(r["added"]) == whole(r["nfr"]) and whole(r["nfr"]) > 0, "Shift + щелчок по «Фрегат» добавил %d" % whole(r["added"]))
	ok(flag(r["still"]), "ростер и нижняя панель стоят на месте при любом выборе")
	var o := await _roster(true)
	var os: String = o["seq"]
	ok(not os.contains("#"), "откат «всегда весь класс» краснеет: %s" % os)


# ───────────────────────── «ИИ против ИИ» ─────────────────────────

func _watch(voice_rb: bool, panel_rb: bool) -> Dictionary:
	State.rollback_watch_voice = voice_rb
	PolygonHud.rollback_panel_foe_word = panel_rb
	var p := await _open(Vector2i(1366, 768), true)
	var h := p.hud
	var out := {}
	out["grid"] = h.grid.visible and not h.grid.buttons.is_empty()
	out["roster"] = h.roster.visible
	var qs := PackedStringArray()
	for id: StringName in h.quick_buttons:
		if h.quick_buttons[id].is_visible_in_tree():
			qs.append(str(id))
	out["quick"] = ",".join(qs)
	out["words"] = "%s / %s" % [h.header.word[0].text, h.header.word[1].text]
	out["reserve"] = h.header.reserve_label.text if h.header.reserve_label.visible else ""
	out["att"] = p.battle.clan_tag(p.view.my_side)
	var foe: Ship = null
	for s in p.battle.ships:
		if s.side != p.view.my_side and not s.dead and not s.station:
			foe = s
			break
	p.view.selection = [foe.uid]
	await hooks.frames(3)
	out["panel"] = h.sel_label.text.get_slice("\n", 0)
	out["clan"] = p.battle.clan_tag(foe.side)
	State.rollback_watch_voice = false
	PolygonHud.rollback_panel_foe_word = false
	await _close()
	return out


func test_watch_no_grid_and_clans() -> void:
	var w := await _watch(false, false)
	note("«ИИ против ИИ»: шапка «%s», панель «%s»" % [w["words"], w["panel"]])
	ok(not flag(w["grid"]) and not flag(w["roster"]) and str(w["quick"]) == "markers", "сетки команд, ростера и быстрого выбора нет — только «Знаки» (%s)" % w["quick"])
	var words: String = w["words"]
	ok(not words.contains(Texts.WE) and not words.contains(Texts.FOE), "шапка — кланами, без «Мы» и «Противник»")
	var res: String = w["reserve"]
	ok(res.begins_with(str(w["att"]) + ": "), "резерв в шапке (бывшая строка статуса) — с кланом: «%s» (хвост G5, п. 1)" % res)
	var panel: String = w["panel"]
	ok(panel.begins_with(str(w["clan"])) and not panel.contains(Texts.FOE), "панель у корабля защитника называет клан")
	var o := await _watch(true, false)
	ok(str(o["words"]).contains(Texts.WE) and not str(o["reserve"]).contains(":"), "откат «с места атакующего» краснеет: шапка «%s», резерв «%s»" % [o["words"], o["reserve"]])
	var o2 := await _watch(false, true)
	ok(str(o2["panel"]).begins_with(Texts.FOE), "откат «панель — Противник» краснеет: «%s»" % o2["panel"])


# ───────────────────────── знаки ─────────────────────────

## Что нарисовано знаками сейчас: наложения, выше шапки, под панелями, имя на чужом значке.
func _audit(p: Polygon) -> Dictionary:
	var mk := p.view.markers
	var d := mk.drawn
	var over := 0
	var name_hit := 0
	for i in d.size():
		for j in d.size():
			if i == j:
				continue
			if j > i and d[i].unit.intersects(d[j].unit):
				over += 1
			if d[i].name != "" and (d[i].name_r.intersects(d[j].frame) or d[i].name_r.intersects(d[j].bar)):
				name_hit += 1
	var top := 0
	var under := 0
	for m in d:
		if m.unit.position.y < mk.top - 0.5:
			top += 1
		for a in mk.avoid:
			if a.intersects(m.unit):
				under += 1
	var names := 0
	for m in d:
		if m.name != "":
			names += 1
	return {"drawn": d.size(), "folded": mk.folded.size(), "over": over, "name_hit": name_hit, "top": top, "under": under, "names": names}


static func _say(a: Dictionary) -> String:
	return "знаков %d, сложено %d, имён %d · наложений %d, имя на значке %d, выше шапки %d, под панелью %d" % [whole(a["drawn"]), whole(a["folded"]), whole(a["names"]), whole(a["over"]), whole(a["name_hit"]), whole(a["top"]), whole(a["under"])]


## Три кадра: старт, «Весь флот» (у всех имена), предел камеры 5000 с «Весь флот».
func _three_frames(size: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p := await _open(size)
	await hooks.frames(2)
	out.append(_audit(p))
	await hooks.key(KEY_F2)
	await hooks.frames(3)
	out.append(_audit(p))
	p.view.rig.set_view(p.view.rig.look, p.view.rig.yaw, 5000.0, true)
	await hooks.frames(3)
	out.append(_audit(p))
	await _close()
	return out


func test_markers_no_overlap() -> void:
	var names := ["старт", "весь флот", "предел 5000"]
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		var fr := await _three_frames(size)
		for i in 3:
			var a := fr[i]
			note("%d×%d, %s: %s" % [size.x, size.y, names[i], _say(a)])
			ok(whole(a["drawn"]) > 10 and whole(a["over"]) == 0 and whole(a["name_hit"]) == 0 and whole(a["top"]) == 0 and whole(a["under"]) == 0,
				"%d×%d, %s: знаки не наезжают, имя не на значке, не выше шапки и не под панелью" % [size.x, size.y, names[i]])
		ok(whole(fr[1]["names"]) > 0, "%d×%d: у выбранных имена есть" % [size.x, size.y])
	Markers.rollback_no_layout = true
	var o := await _three_frames(Vector2i(1366, 768))
	Markers.rollback_no_layout = false
	ok(whole(o[2]["over"]) > 0, "откат «без раскладки» краснеет на пределе 5000: %s" % _say(o[2]))
	Markers.rollback_names_free = true
	var o2 := await _three_frames(Vector2i(1366, 768))
	Markers.rollback_names_free = false
	ok(whole(o2[1]["name_hit"]) > 0 or whole(o2[2]["name_hit"]) > 0, "откат «имя не в месте знака» краснеет: %s / %s" % [_say(o2[1]), _say(o2[2])])


## Знак корабля, стоящего у самой шапки: не выше её (отходит вниз или прячется). Корабль
## ставится на экране в y = 60 перемещением камеры (взгляд по оси экрана).
func _near_header(rollback: bool) -> Dictionary:
	Markers.rollback_no_top = rollback
	var p := await _open(Vector2i(1366, 768))
	var rig := p.view.rig
	var s := _first(p, func(x: Ship) -> bool: return x.heavy())
	var fwd := -rig.camera.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var base := rig.look
	var lo := -6000.0
	var hi := 6000.0
	for it in 30:
		var mid := (lo + hi) * 0.5
		rig.set_view(base + fwd * mid, rig.yaw, rig.dist, true)
		var y := rig.camera.unproject_position(p.view.ship_point(s)).y
		if y < 60.0:
			lo = mid
		else:
			hi = mid
	await hooks.frames(3)
	var y2 := rig.camera.unproject_position(p.view.ship_point(s)).y
	var a := _audit(p)
	var m := p.view.markers.mark_of(s.uid)
	a["ship_y"] = y2
	a["mark_y"] = m.unit.position.y if m != null else -1.0
	Markers.rollback_no_top = false
	await _close()
	return a


func test_markers_not_above_header() -> void:
	var a := await _near_header(false)
	note("корабль у шапки (y %.0f): %s, его знак y %.0f" % [num(a["ship_y"]), _say(a), num(a["mark_y"])])
	ok(absf(num(a["ship_y"]) - 60.0) < 3.0 and whole(a["top"]) == 0, "корабль под самой шапкой — знаков выше шапки нет")
	var o := await _near_header(true)
	ok(whole(o["top"]) > 0, "откат «знаки и под шапкой» краснеет: %s" % _say(o))


## На пределе камеры 5000 знак есть у КАЖДОГО видимого корабля (свой или сложенный в соседа),
## кроме тех, что под панелями.
func _far_missing(rollback: bool) -> Dictionary:
	Markers.rollback_fade_far = rollback
	var p := await _open(Vector2i(1366, 768))
	p.view.rig.set_view(p.view.rig.look, p.view.rig.yaw, 5000.0, true)
	await hooks.frames(4)
	var mk := p.view.markers
	var cam := p.view.rig.camera
	var have: Dictionary[int, bool] = {}
	for m in mk.drawn:
		have[m.uid] = true
	for u in mk.folded:
		have[u] = true
	var n := 0
	var miss := 0
	var tiny := 0
	for s in p.battle.ships:
		if s.dead or not Picking.shown(s, p.view.my_side):
			continue
		var sp := cam.unproject_position(p.view.ship_point(s))
		var room := Rect2(Vector2(40.0, mk.top + 50.0), Vector2(1366.0 - 80.0, 768.0 - mk.top - 90.0))
		var clear := room.has_point(sp)
		for a in mk.avoid:
			if a.grow(50.0).has_point(sp):
				clear = false
		if not clear:
			continue
		n += 1
		var len_px := cam.unproject_position(p.view.ship_point(s) + cam.global_transform.basis.x * s.def.radius).distance_to(sp)
		if len_px < 4.0:
			tiny += 1
		if not have.has(s.uid):
			miss += 1
	Markers.rollback_fade_far = false
	await _close()
	return {"n": n, "miss": miss, "tiny": tiny}


func test_markers_visible_at_5000() -> void:
	var r := await _far_missing(false)
	ok(whole(r["n"]) > 20 and whole(r["miss"]) == 0, "предел 5000: у всех %d кораблей на поле есть знак (меньше 4 точек на экране — %d)" % [whole(r["n"]), whole(r["tiny"])])
	var o := await _far_missing(true)
	ok(whole(o["miss"]) > 0, "откат «знак только у крупных» краснеет: без знака %d из %d" % [whole(o["miss"]), whole(o["n"])])


## Щелчок по знаку, отошедшему от своего корабля, выбирает этот корабль; рамка по одному знаку —
## тоже (корабль вне рамки).
func _moved_mark(p: Polygon) -> Markers.Mark:
	var cam := p.view.rig.camera
	for m in p.view.markers.drawn:
		if m.squad or m.side != p.view.my_side or not m.moved:
			continue
		var c := m.frame.get_center()
		if c.distance_to(m.p) < 45.0:
			continue
		# под серединой знака не должно быть ни другого корабля в 35 точках, ни корпуса
		var clash := false
		for s in p.battle.ships:
			if s.dead or s.uid == m.uid:
				continue
			if cam.unproject_position(p.view.ship_point(s)).distance_to(c) < 35.0:
				clash = true
		if not clash and Picking.pick_hull(p.view, c) == null:
			return m
	return null


func _marker_click(rollback: bool, jumps: bool = false) -> Dictionary:
	Picking.rollback_no_markers = rollback
	Markers.rollback_hover_jumps = jumps
	var p := await _open(Vector2i(1366, 768))
	await hooks.key(KEY_F2)
	p.view.rig.set_view(p.view.rig.look, p.view.rig.yaw, 5000.0, true)
	await hooks.frames(3)
	var m := _moved_mark(p)
	var out := {"found": m != null}
	if m != null:
		var uid := m.uid
		var c := m.frame.get_center()
		await hooks.click(c)
		var one: Array[int] = [uid]
		out["click"] = p.view.selection == one
		await hooks.frames(2)
		var m2 := p.view.markers.mark_of(uid)
		var r := m2.frame.grow(3.0) if m2 != null else Rect2()
		out["box_ok"] = not r.has_point(m2.p) if m2 != null else false
		await _drag(r.position, r.end)
		out["box"] = uid in p.view.selection
	Picking.rollback_no_markers = false
	Markers.rollback_hover_jumps = false
	await _close()
	return out


func _drag(a: Vector2, b: Vector2) -> void:
	await hooks.move(a)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = a
	ev.global_position = a
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)
	await hooks.frames(1)
	for i in range(1, 9):
		var mv := InputEventMouseMotion.new()
		mv.position = a.lerp(b, float(i) / 8.0)
		mv.global_position = mv.position
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mv)
		await hooks.frames(1)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	up.button_mask = 0
	up.position = b
	up.global_position = b
	Input.parse_input_event(up)
	await hooks.frames(2)


func test_marker_click_and_box() -> void:
	var r := await _marker_click(false)
	if not ok(flag(r["found"]), "на пределе 5000 есть свой знак, отошедший от корабля дальше 45 точек"):
		return
	ok(flag(r["click"]), "щелчок по знаку, отошедшему от корабля, выбирает этот корабль")
	ok(flag(r["box_ok"]) and flag(r["box"]), "рамка вокруг одного знака (корабль вне рамки) берёт корабль")
	var o := await _marker_click(true)
	ok(not flag(o.get("click", true)) and not flag(o.get("box", true)), "откат «выбор не знает знаков» краснеет: щелчок и рамка мимо")
	# наведение поднимает знак в важности; без памяти о прошлом месте он уезжает из-под курсора
	var j := await _marker_click(false, true)
	ok(not flag(j.get("click", true)), "откат «знак под курсором встаёт заново» краснеет: щелчок пришёлся в пустоту")


## Имя корабля — под курсором (и у выбранных), а не у всех: наводим мышь на знак своего корабля
## без имени — имя появляется, уводим — пропадает.
func _hover_name(rollback: bool) -> Array[String]:
	Markers.rollback_hover_no_name = rollback
	var p := await _open(Vector2i(1366, 768))
	var got: Array[String] = ["", "", ""]
	var m: Markers.Mark = null
	for d in p.view.markers.drawn:
		if not d.squad and d.side == p.view.my_side and d.name == "" and d.frame.position.y > 120.0:
			m = d
			break
	if m != null:
		var uid := m.uid
		got[0] = m.name
		await hooks.move(m.frame.get_center())
		await hooks.frames(2)
		var m2 := p.view.markers.mark_of(uid)
		got[1] = m2.name if m2 != null else "?"
		await hooks.move(Vector2(30.0, 400.0))
		await hooks.frames(2)
		var m3 := p.view.markers.mark_of(uid)
		got[2] = m3.name if m3 != null else "?"
	Markers.rollback_hover_no_name = false
	await _close()
	return got


func test_marker_name_on_hover() -> void:
	var r := await _hover_name(false)
	ok(r[0] == "" and r[1] != "" and r[2] == "", "имя под курсором: до наведения «%s», под курсором «%s», после «%s»" % [r[0], r[1], r[2]])
	var o := await _hover_name(true)
	ok(o[1] == "", "откат «имя только у выбранных» краснеет: под курсором «%s»" % o[1])


## Знак не главнее корпуса, который БЛИЖЕ по лучу: по ближнему тяжёлому, на корпус которого
## лёг знак дальнего корабля, щелчок берёт ближний.
func _behind(rollback: bool) -> Dictionary:
	Picking.rollback_marker_first = rollback
	var p := await _open(Vector2i(1366, 768))
	var cap := _first(p, func(s: Ship) -> bool: return s.def.id == &"capital")
	var cor := _first(p, func(s: Ship) -> bool: return s.def.id == &"corvette")
	var rig := p.view.rig
	var cam := rig.camera
	var found := {}
	# камера близко у флагмана; свой корвет ставим ЗА флагманом по лучу камеры — его знак ложится
	# на корпус флагмана, а сам корвет дальше по лучу
	var cp0 := p.view.ship_point(cap)
	rig.set_view(Vector3(cp0.x, 0.0, cp0.z), rig.yaw, 700.0, true)
	await hooks.frames(3)
	# по лучу за флагманом луч уходит вниз: корвет ставится НИЖЕ флагмана (высота-картинка вида)
	# и туда, где луч камеры через середину флагмана пересекает его высоту
	for drop: float in [60.0, 120.0, 200.0]:
		var cp := p.view.ship_point(cap)
		var dir := (cp - cam.global_position).normalized()
		var h := cp.y - drop
		p.view._height[cor.uid] = h
		var t0 := (h - cam.global_position.y) / dir.y
		var q := cam.global_position + dir * t0
		hooks.place_ship(cor, Vector2(q.x, q.z))
		p.view._prev[cor.uid] = Vector3(q.x, q.z, cor.yaw)
		await hooks.frames(3)
		var capsule: Array = p.view.capsule(cap)
		var ca: Vector3 = capsule[0]
		var cb: Vector3 = capsule[1]
		var cr: float = capsule[2]
		for m in p.view.markers.drawn:
			if m.uid == cap.uid or m.squad:
				continue
			for k in 9:
				var pt := m.frame.position + m.frame.size * Vector2(0.25 + 0.25 * float(k % 3), 0.25 + 0.25 * float(k / 3))
				var t := Picking.ray_capsule(cam.project_ray_origin(pt), cam.project_ray_normal(pt), ca, cb, cr)
				if t >= 0.0 and t < m.depth - 20.0:
					found = {"pt": pt, "far": m.uid}
					break
			if not found.is_empty():
				break
		if not found.is_empty():
			break
	var out := {"found": not found.is_empty()}
	if not found.is_empty():
		var fpt: Vector2 = found["pt"]
		var hit := Picking.pick_any(p.view, fpt)
		var hs := hit as Ship
		out["near"] = hs != null and hs.uid == cap.uid
	Picking.rollback_marker_first = false
	await _close()
	return out


func test_marker_not_over_nearer_hull() -> void:
	var r := await _behind(false)
	if not ok(flag(r["found"]), "нашлось место, где знак дальнего корабля лёг на корпус ближнего флагмана"):
		return
	ok(flag(r["near"]), "по такому месту щелчок берёт ближний флагман (знак не дальше своего корабля по лучу)")
	var o := await _behind(true)
	ok(not flag(o.get("near", true)), "откат «знак главнее всегда» краснеет — взят дальний")


## Цвет и форма знака — по СТОРОНЕ: своя — мятный прямоугольник, чужая — красный
## шестиугольник; в зеркальном бою (Тройден × Тройден) так же. Пара цветов различима и при
## цветовой слепоте (симуляция Machado 2009: протанопия, дейтеранопия, тританопия).
func _sides(mirror: bool, clan_rb: bool, shape_rb: bool, dot_rb: bool = false, watch: bool = false) -> Dictionary:
	Markers.rollback_clan_color = clan_rb
	Markers.rollback_one_shape = shape_rb
	HudHeader.rollback_dot_clan = dot_rb
	var p := await _open(Vector2i(1366, 768), watch, mirror)
	var mk := p.view.markers
	var my := p.view.my_side
	var foe := 1 - my
	var out := {}
	out["c_my"] = mk.side_color(my, p.battle.sides[my].clan)
	out["c_foe"] = mk.side_color(foe, p.battle.sides[foe].clan)
	out["s_my"] = mk.side_shape(my)
	out["s_foe"] = mk.side_shape(foe)
	# квадратики шапки — легенда знаков: тот же цвет стороны
	await hooks.frames(2)
	out["d_my"] = p.hud.header.dot[my].color
	out["d_foe"] = p.hud.header.dot[foe].color
	Markers.rollback_clan_color = false
	Markers.rollback_one_shape = false
	HudHeader.rollback_dot_clan = false
	await _close()
	return out


## Различие двух цветов глазом с данной матрицей зрения (ΔE CIE76 в Lab, 0 — не различить).
static func _de(a: Color, b: Color, m: Basis) -> float:
	return _lab(_sim(a, m)).distance_to(_lab(_sim(b, m)))


static func _sim(c: Color, m: Basis) -> Color:
	var v := Vector3(c.srgb_to_linear().r, c.srgb_to_linear().g, c.srgb_to_linear().b)
	var r := Vector3(m.x.dot(v), m.y.dot(v), m.z.dot(v))
	return Color(clampf(r.x, 0.0, 1.0), clampf(r.y, 0.0, 1.0), clampf(r.z, 0.0, 1.0))


static func _lab(lin: Color) -> Vector3:
	var x := (0.4124 * lin.r + 0.3576 * lin.g + 0.1805 * lin.b) / 0.95047
	var y := 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b
	var z := (0.0193 * lin.r + 0.1192 * lin.g + 0.9505 * lin.b) / 1.08883
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var fx: float = f.call(x)
	var fy: float = f.call(y)
	var fz: float = f.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


## Значок класса (план GИ, п. 6): у каждого корабля на экране — значок ЕГО класса (флагман,
## крейсер, носитель, РЭБ, фрегат, корвет, «Синхо», станция — по id корабля), а не «тяжёлый или
## лёгкий». До доработки GИ это не охраняла ни одна проверка — порча `kind_of` («класс по cls»:
## флагман и крейсер одним ромбом, всё лёгкое — шевроном) оставляла ярусы зелёными; откат —
## порчей кода (godot/CLAUDE.md, 22). Рисунок самих значков — на снимках яруса hud (глазами).
func test_marker_kind_by_class() -> void:
	var p := await _open(Vector2i(1920, 1080))
	await hooks.key(KEY_F2)
	await hooks.frames(3)
	var bad := PackedStringArray()
	var kinds: Dictionary[StringName, int] = {}
	var n := 0
	for m in p.view.markers.drawn:
		if m.squad:
			continue
		var s := p.battle.ship_by_uid(m.uid)
		var want: StringName = &"station" if s.station else s.def.id
		n += 1
		kinds[m.kind] = kinds.get(m.kind, 0) + 1
		if m.kind != want or not Markers.RANK.has(m.kind):
			bad.append("%s: значок %s, класс %s" % [s.name, m.kind, want])
	var ks := PackedStringArray()
	for k: StringName in kinds:
		ks.append("%s ×%d" % [k, kinds[k]])
	note("значки на старте: %s" % ", ".join(ks))
	ok(n > 10 and bad.is_empty() and kinds.size() >= 6, "у %d знаков значок своего класса, классов %d (%s): %s" % [n, kinds.size(), ", ".join(ks), "; ".join(bad)])
	# станция есть только в «Генеральном» (quick.station_on), в «Сражении» её нет — значок
	# спрашивается напрямую у корабля с её данными
	var st := Ship.new()
	st.def = p.battle.defs.station
	st.station = true
	ok(Markers.kind_of(st) == &"station", "у станции — значок станции (%s)" % Markers.kind_of(st))
	await _close()


## Матрицы Machado, Oliveira, Fernandes 2009 (полная выраженность), по строкам.
const VISION := {
	"обычное": [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	"протанопия": [Vector3(0.152286, 1.052583, -0.204868), Vector3(0.114503, 0.786281, 0.099216), Vector3(-0.003882, -0.048116, 1.051998)],
	"дейтеранопия": [Vector3(0.367322, 0.860646, -0.227968), Vector3(0.280085, 0.672501, 0.047413), Vector3(-0.011820, 0.042940, 0.968881)],
	"тританопия": [Vector3(1.255528, -0.076749, -0.178779), Vector3(-0.078411, 0.930809, 0.147602), Vector3(0.004733, 0.691367, 0.303900)],
}


static func _worst_de(a: Color, b: Color) -> Dictionary:
	var worst := INF
	var who := ""
	for k: String in VISION:
		var rows: Array = VISION[k]
		var r0: Vector3 = rows[0]
		var r1: Vector3 = rows[1]
		var r2: Vector3 = rows[2]
		var m := Basis(r0, r1, r2)
		var d := _de(a, b, m)
		if d < worst:
			worst = d
			who = k
	return {"de": worst, "who": who}


func test_marker_colors_by_side() -> void:
	var r := await _sides(false, false, false)
	var my: Color = r["c_my"]
	var fo: Color = r["c_foe"]
	ok(my == Markers.SIDE_A and fo == Markers.SIDE_B, "быстрый бой: свои — мятные, чужие — красные")
	ok(str(r["s_my"]) == "rect" and str(r["s_foe"]) == "hex", "свои — прямоугольник, чужие — шестиугольник")
	var w := _worst_de(my, fo)
	note("мятный и красный знаков: худшее различие ΔE %.0f (%s)" % [num(w["de"]), w["who"]])
	ok(num(w["de"]) >= 30.0, "пара цветов различима при любом зрении: худшее — %s, ΔE %.0f" % [w["who"], num(w["de"])])
	# контроль самой мерки: красный и зелёный одной яркости при дейтеранопии сливаются
	var c := _worst_de(Color(0.8, 0.3, 0.2), Color(0.45, 0.5, 0.2))
	ok(num(c["de"]) < 30.0, "контроль мерки: красный и зелёный одной яркости — худшее %s, ΔE %.0f (не различить)" % [c["who"], num(c["de"])])
	var mr := await _sides(true, false, false)
	var mc0: Color = mr["c_my"]
	var mc1: Color = mr["c_foe"]
	ok(mc0 != mc1 and str(mr["s_my"]) != str(mr["s_foe"]), "зеркало Тройден × Тройден: стороны разного цвета и формы")
	var o := await _sides(true, true, false)
	var oc0: Color = o["c_my"]
	var oc1: Color = o["c_foe"]
	ok(oc0 == oc1, "откат «цвет по клану» краснеет на зеркале: стороны одного цвета")
	var o2 := await _sides(false, false, true)
	ok(str(o2["s_my"]) == str(o2["s_foe"]), "откат «одна форма» краснеет: различие только цветом")
	# легенда в шапке: квадратик у полосы силы того же цвета, что знаки его стороны, — и в «ИИ
	# против ИИ», где по нему узнают, какой клан мятный (откат — цвет клана — краснеет)
	for wt: bool in [false, true]:
		var lg := await _sides(false, false, false, false, wt)
		var d0: Color = lg["d_my"]
		var d1: Color = lg["d_foe"]
		ok(d0 == my and d1 == fo, "%s: квадратики шапки — цвет знаков своей стороны (%s / %s)" % ["«ИИ против ИИ»" if wt else "быстрый бой", d0, d1])
	var lo := await _sides(false, false, false, true, true)
	var e0: Color = lo["d_my"]
	var e1: Color = lo["d_foe"]
	ok(not (e0 == my and e1 == fo), "откат «квадратик цветом клана» краснеет: %s / %s" % [e0, e1])
	var lm := await _sides(true, false, false, true)
	var m0: Color = lm["d_my"]
	var m1: Color = lm["d_foe"]
	note("откат в зеркале: квадратики %s / %s — %s" % [m0, m1, "одинаковые" if m0 == m1 else "разные"])


## «Знаки» (I) помнится между запусками (view/settings.gd), файл — свой у прогона.
func _toggle_and_reopen(rollback: bool) -> Array[bool]:
	BattleView.rollback_markers_forget = rollback
	var p := await _open(Vector2i(1366, 768), false, false, "hud_set")
	var a := p.view.markers.on
	await hooks.key(KEY_I)
	var b := p.view.markers.on
	var path := Settings.path
	var defs: Defs = _main.get("defs")
	_main.call("open_battle", QuickMenu.default_cfg(defs, false))
	await hooks.frames(4)
	var p2: Polygon = _main.get("polygon")
	var c := p2.view.markers.on
	Settings.path = path
	BattleView.rollback_markers_forget = false
	await _close()
	return [a, b, c]


func test_markers_toggle_remembered() -> void:
	var r := await _toggle_and_reopen(false)
	ok(r[0] and not r[1] and not r[2], "знаки по умолчанию включены, I выключила, новый бой открылся без них")
	var o := await _toggle_and_reopen(true)
	ok(o[2], "откат «не запоминать» краснеет: новый бой снова со знаками")


# ───────────────────────── кольца и край экрана ─────────────────────────

## Кольцо выделения — тонкая линия (не плоский тор); на большом флоте — не больше двух поясов.
func test_rings_thin_and_few() -> void:
	for roll: bool in [false, true]:
		BattleView.rollback_torus_ring = roll
		var p := await _open(Vector2i(1366, 768))
		var s := _first(p, func(x: Ship) -> bool: return x.heavy())
		p.view.selection = [s.uid]
		await hooks.frames(3)
		var line := p.view.drawn_rings.has(s.uid)
		var torus := 0
		for c in p.view.get_children():
			torus += _visible_rings(c)
		BattleView.rollback_torus_ring = false
		if not roll:
			ok(line and torus == 0, "выделенный — тонкое кольцо линией, плоских торов нет")
		else:
			ok(not line and torus > 0, "откат «прежний тор» краснеет (торов %d)" % torus)
		await _close()
	for roll2: bool in [false, true]:
		BattleFx.rollback_three_on_big = roll2
		var p2 := await _open(Vector2i(1366, 768))
		var own := _own(p2)
		var armed: Array[int] = []
		var foes: Array[Ship] = []
		for s2 in p2.battle.ships:
			if s2.side != p2.view.my_side and s2.heavy() and not s2.dead:
				foes.append(s2)
		for s3 in own:
			if s3.range0() > 0.0 and armed.size() < 6:
				armed.append(s3.uid)
		p2.battle.ship_by_uid(armed[0]).forced = foes[0]
		p2.view.selection = armed
		p2.view.hover_uid = foes[1].uid
		p2.view.draw_state()
		var n := p2.view.bfx.drawn_belts.size()
		BattleFx.rollback_three_on_big = false
		if not roll2:
			ok(n == 2, "большой флот (6 выделенных) + фокус + под курсором — поясов %d, не больше двух" % n)
		else:
			ok(n == 3, "откат «три пояса и на большом флоте» краснеет: %d" % n)
		await _close()


func _visible_rings(n: Node) -> int:
	var k := 0
	var mi := n as MeshInstance3D
	if mi != null and mi.visible and mi.mesh is TorusMesh:
		k += 1
	for c in n.get_children():
		k += _visible_rings(c)
	return k


## Над кнопкой шапки у верхнего края экрана край экрана камеру не тянет.
func _edge_over_button(rollback: bool) -> float:
	CameraRig.rollback_edge_over_buttons = rollback
	var p := await _open(Vector2i(1366, 768))
	var rig := p.view.rig
	var b := p.hud.header.buttons[&"retreat"]
	var at := Vector2(b.get_global_rect().get_center().x, b.get_global_rect().position.y + 2.0)
	await hooks.move(at)
	var under := tree.root.gui_get_hovered_control()
	rig.edge_enabled = true
	var l0 := rig.look
	await hooks.frames(10)
	var moved := rig.look.distance_to(l0)
	rig.edge_enabled = false
	CameraRig.rollback_edge_over_buttons = false
	await _close()
	return moved if under == b else -1.0


func test_edge_silent_over_buttons() -> void:
	var d := await _edge_over_button(false)
	ok(d == 0.0, "мышь на «Отходе» у верхнего края — камера стоит (сдвиг %.1f)" % d)
	var o := await _edge_over_button(true)
	ok(o > 1.0, "откат «край и над кнопками» краснеет: камера уехала на %.0f" % o)


## Подсказка боя в 0.6: две длинные строки под шапкой (откат).
const HINT_06 := "F3 — счётчик кадров · F8 — начать заново · F9 — запись боя · F11 — полный экран\nкамера: колесо — ближе и дальше · Q/E или правая кнопка с протяжкой — повернуть · стрелки и край экрана — сдвинуть"


## Подсказка клавиш — над ростером, а не под шапкой, как раньше: на старте под шапкой стоит
## чужая линия, и строки ложились на её знаки. Не наезжает на ростер, панель и шапку, ни один
## корабль на старте под ней не стоит, гаснет через 16 игровых секунд.
func _hint(size: Vector2i, rollback: bool) -> Dictionary:
	PolygonHud.rollback_hint_top = rollback
	var p := await _open(size)
	await hooks.frames(3)
	var fps: Node = _main.get("fps")
	var hint: Label = fps.get("hint")
	if rollback:
		fps.call("set_hint_text", HINT_06)
		await hooks.frames(3)
	var r := hint.get_global_rect()
	var cam := p.view.rig.camera
	var under := 0
	for s in p.battle.ships:
		if not s.dead and r.grow(6.0).has_point(cam.unproject_position(p.view.ship_point(s))):
			under += 1
	var clash := r.intersects(p.hud.roster.get_global_rect()) or r.intersects(p.hud.panel.get_global_rect()) or r.position.y < HudHeader.HEIGHT or r.end.x > float(size.x)
	var vis0 := hint.is_visible_in_tree()
	_steps(p, roundi(17.0 / Battle.STEP))
	await hooks.frames(3)
	var vis1 := hint.is_visible_in_tree()
	PolygonHud.rollback_hint_top = false
	await _close()
	return {"under": under, "clash": clash, "vis0": vis0, "vis1": vis1, "rect": r}


func test_hint_above_roster() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		var h := await _hint(size, false)
		note("%d×%d: подсказка %s, кораблей под ней %d" % [size.x, size.y, h["rect"], whole(h["under"])])
		ok(flag(h["vis0"]) and not flag(h["clash"]) and whole(h["under"]) == 0, "%d×%d: подсказка видна, над ростером, ни на что не наезжает и не закрывает кораблей" % [size.x, size.y])
		ok(not flag(h["vis1"]), "%d×%d: через 16 игровых секунд подсказки нет — клавиши на кнопках" % [size.x, size.y])
	var o := await _hint(Vector2i(1366, 768), true)
	ok(whole(o["under"]) > 0, "откат «подсказка как в 0.6 — две длинные строки под шапкой» краснеет: под ней %d кораблей чужой линии" % whole(o["under"]))


## Текст выпуска capella-v0.7, «Что попробовать», шаги 1–4 — теми же действиями, что сделает
## человек: щелчки по кнопкам, ячейке ростера и знаку, колесо мыши. Каждое правило под шагами
## проверено своим откатом выше; здесь — что шаги вместе дают обещанное.
func test_release_walkthrough() -> void:
	# как в тексте выпуска: из меню, кнопкой «В бой»
	var p := await _open_by_menu(Vector2i(1366, 768), "go")
	if not ok(p != null, "шаг 1: в меню «В бой» нажимается и открывает бой"):
		await _close()
		return
	var my := p.view.my_side
	p.view.paused = false
	# 1. «Весь флот», потом «Охота» — все корабли на «Охоте»
	ok(await _press(p.hud.quick_buttons[&"all"]), "шаг 1: «Весь флот» нажимается")
	await hooks.frames(2)
	var hb: Button = p.hud.grid.buttons.get(&"hunt")
	ok(await _press(hb), "шаг 1: «Охота» нажимается")
	await hooks.frames(4)
	var all_hunt := true
	for s in _own(p):
		all_hunt = all_hunt and s.stance == &"hunt"
	ok(all_hunt and _own(p).size() > 3, "шаг 1: все %d кораблей на «Охоте»" % _own(p).size())
	# 2. ячейка ростера «Носитель», потом «Перехватчик» — звено взлетело
	var cell: Button = p.hud.roster.cells.get("s:carrier")
	ok(await _press(cell), "шаг 2: ячейка «Носитель» нажимается")
	await hooks.frames(2)
	var sel_ok := p.view.selection.size() == 1 and p.battle.ship_by_uid(p.view.selection[0]).hangar != null
	var ib: Button = p.hud.grid.buttons.get(&"launch_interceptor")
	ok(sel_ok and await _press(ib), "шаг 2: выбран носитель, «Перехватчик» нажимается")
	_steps(p, 40)
	p.view.paused = false
	var nq := 0
	for q in p.battle.squads:
		if not q.dead and q.side == my:
			nq += 1
	ok(nq == 1, "шаг 2: звено взлетело (%d)" % nq)
	await hooks.frames(2)
	var sq_mark := false
	for m in p.view.markers.drawn:
		sq_mark = sq_mark or (m.squad and m.kind == &"interceptor" and m.side == my)
	ok(sq_mark, "шаг 2: над звеном — знак роли (перехватчик)")
	# 3. «Подкрепление», через полминуты — «Прибывшие»: вышедшие выбраны
	var rb := p.hud.header.buttons[&"reinforce"]
	ok(await _press(rb), "шаг 3: «Подкрепление» нажимается")
	_steps(p, roundi(36.0 / Battle.STEP))
	p.view.paused = false
	await hooks.frames(3)
	ok(rb.text.begins_with("Прибывшие") and await _press(rb), "шаг 3: «%s» нажимается" % rb.text)
	var arrived := not p.view.selection.is_empty()
	for u in p.view.selection:
		arrived = arrived and u in p.view.arrived
	ok(arrived, "шаг 3: выбраны вышедшие (%d)" % p.view.selection.size())
	# 4. колесо до упора — знаки на месте; щелчок по знаку выбирает корабль
	p.view.paused = true
	var rig := p.view.rig
	var mid := Vector2(683.0, 380.0)
	await hooks.move(mid)
	for i in 40:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = true
		ev.position = mid
		ev.global_position = mid
		Input.parse_input_event(ev)
		await hooks.frames(1)
	var n := 0
	while absf(rig.s_dist - rig.dist) > 5.0 and n < 900:
		await hooks.frames(1)
		n += 1
	await hooks.key(KEY_ESCAPE)
	await hooks.frames(3)
	ok(rig.dist >= rig.dist_max - 1.0, "шаг 4: колесом камера отъехала до упора (%.0f из %.0f)" % [rig.dist, rig.dist_max])
	var cam := rig.camera
	var shown := 0
	for s in p.battle.ships:
		if not s.dead and Picking.shown(s, my):
			shown += 1
	var mk := p.view.markers
	ok(mk.drawn.size() + mk.folded.size() >= shown - 4, "шаг 4: знаки на месте — %d своих и %d сложенных при %d кораблях" % [mk.drawn.size(), mk.folded.size(), shown])
	var target: Markers.Mark = null
	for m in mk.drawn:
		if m.squad:
			continue
		var c := m.frame.get_center()
		var clash := false
		for s in p.battle.ships:
			if not s.dead and s.uid != m.uid and cam.unproject_position(p.view.ship_point(s)).distance_to(c) < 35.0:
				clash = true
		if not clash:
			target = m
			break
	if ok(target != null, "шаг 4: есть знак, по которому щёлкнуть"):
		var uid := target.uid
		await hooks.click(target.frame.get_center())
		var one: Array[int] = [uid]
		ok(p.view.selection == one, "шаг 4: щелчок по знаку выбрал его корабль")
	await _close()
	# 5. «Смотреть: ИИ против ИИ» — знаки обеих сторон, шапка называет кланы
	var w := await _open_by_menu(Vector2i(1366, 768), "watch")
	if not ok(w != null and w.battle.watch, "шаг 5: в меню «Смотреть: ИИ против ИИ» нажимается и открывает бой ИИ"):
		await _close()
		return
	await hooks.frames(2)
	var per := PackedInt32Array([0, 0])
	var shapes := PackedStringArray(["", ""])
	for m in w.view.markers.drawn:
		if m.squad:
			continue
		per[m.side] += 1
		shapes[m.side] = str(w.view.markers.side_shape(m.side))
	ok(per[0] > 0 and per[1] > 0 and shapes[0] != shapes[1], "шаг 5: знаки у обеих сторон — %d и %d, рамки «%s» и «%s»" % [per[0], per[1], shapes[0], shapes[1]])
	var hw: Array[String] = []
	for i in 2:
		hw.append(w.hud.header.word[i].text)
	ok(hw[0] == "Тройден" and hw[1] == "Плэктор", "шаг 5: шапка называет кланы: «%s» и «%s»" % [hw[0], hw[1]])
	var same := true
	for i in 2:
		var mc := w.view.markers.side_color(i, w.battle.sides[i].clan)
		same = same and w.hud.header.word[i].get_theme_color("font_color") == mc and w.hud.header.dot[i].color == mc
	ok(same, "шаг 5: имя клана в шапке и квадратик у него — того же цвета, что знаки его стороны")
	await _close()
