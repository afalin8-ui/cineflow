# ui/polygon_hud.gd — экран боя (план GИ: интерфейс на экране, а не только горячие клавиши;
# 07, 1.1). Раскладка:
#   шапка (ui/hud_header.gd)      — силы сторон, название и часы, орудие планеты, пауза и скорость,
#                                   подкрепление в трёх режимах, «Отход» с вопросом, «В меню»;
#   полоски по центру под шапкой  — ответы на приказы (журнал модели, игровые часы) и свои;
#   лента слева над ростером      — что случилось само (только быстрый бой);
#   ростер (ui/roster.gd)          — свои корабли и звенья по классу тремя группами;
#   нижняя панель                 — что выбрано и чем занято + СЕТКА КОМАНД (ui/command_grid.gd):
#                                   каждая команда клавиши — кнопкой с подписью и буквой;
#   столбик справа внизу          — быстрый выбор «Весь флот», «Тяжёлые», «Лёгкие» и «Знаки».
# Кнопка и клавиша — ОДНА дверь: кнопка зовёт input/battle_input.gd → command(id), как клавиша.
# - Полоски о приказах берутся из ЖУРНАЛА модели (toast_log, с игровым временем:
#   02, ловушка 30; 05, ловушка 38): интерфейс их только показывает и гасит по
#   игровым часам — на паузе полоска стоит. Свои полоски интерфейса («Сначала
#   выбери свои корабли») — по настоящему времени: боя они не касаются.
# - Мышь (ui/builder.gd): ловят только кнопки и нижняя панель (STOP целиком, как настоящая
#   панель); шапка — градиент, щелчок мимо её кнопок уходит в поле (C135). Жест, начатый на
#   поле и кончившийся над панелью, дослушивается в _input (архитектура, 6.5).
# - «ИИ против ИИ»: сетки команд нет (смотреть, а не командовать), ростера и быстрого выбора
#   нет, панель и шапка называют стороны кланами (State.clan_voice — одна дверь с лентой).
# - Числа в текст — форматом, а не str() (07, 5.2).
extends CanvasLayer

const Ship := preload("res://sim/ship.gd")
const State := preload("res://sim/state.gd")
const Weapons := preload("res://sim/weapons.gd")
const Defs := preload("res://sim/defs.gd")
const FrameBench := preload("res://ui/frame_bench.gd")
const Squad := preload("res://sim/squad.gd")
const Craft := preload("res://sim/craft.gd")
const Body := preload("res://sim/body.gd")
const Air := preload("res://sim/air.gd")
const HeavyDoctrine := preload("res://sim/heavy_doctrine.gd")
const Picking := preload("res://input/picking.gd")
const Builder := preload("res://ui/builder.gd")
const Texts := preload("res://ui/texts.gd")
const HudHeader := preload("res://ui/hud_header.gd")
const HudTooltip := preload("res://ui/hud_tooltip.gd")
const ConfirmBox := preload("res://ui/confirm_box.gd")
const CommandGrid := preload("res://ui/command_grid.gd")
const Roster := preload("res://ui/roster.gd")

## Сколько игровых секунд живёт полоска модели и сколько настоящих — своя.
const TOAST_GAME_S := 4.5
const TOAST_REAL_MS := 4000
const TOASTS_MAX := 3
## Подсказок ввода — не больше двух: третья строка остаётся полоске модели.
const HINTS_MAX := 2
## Шапка и подсказка клавиш под ней (две строки, ui/fps_counter.gd → set_hint_top).
const HEADER_H := HudHeader.HEIGHT
const HINT_TOP := HEADER_H + 4.0           # прежнее место (до первого кадра раскладки)
## Полоски — ниже подсказки клавиш, по середине экрана.
const TOAST_Y := HEADER_H + 48.0
## Полоски «как будто шапки нет» — у самого верха экрана; только откат проверки.
const TOAST_Y_OLD := 10.0
const TOAST_GAP := 16.0
## Поля экрана и зазоры (07, 2.2): нижняя панель — слева 10, снизу 10.
const EDGE := 10.0
const PANEL_GAP := 16.0
## Столбик быстрого выбора: ширина и высота кнопки.
const COL_W := 132.0
const COL_BTN_H := 34.0

## ТОЛЬКО для проверок отката (замечания к G2–G4 и план GИ), в игре всегда false:
## полоски у самого верха экрана, как будто шапки нет, — ложатся на её кнопки и часы;
static var rollback_toast_old_y := false
## строка «чем занят» молчит о цели фокуса вне пояса (приказ выглядел невыполненным);
static var rollback_focus_unnamed := false
## «враг вплотную — … · бьёт батарея» без проверки, может ли батарея стрелять.
static var rollback_bat_claim := false
## Хвосты G2 (замечания проверяющих), в игре всегда false:
## подсказки ввода («A — щёлкните точку или врага», «Сначала выбери…») — ПОСЛЕ полосок
## модели, как было: три полоски приказов вытесняли подсказку целиком;
static var rollback_hints_last := false
## тяжёлый со своей целью вне пояса пишет «охота · целей не видно», а лёгкий под
## помехами дальше lockRange — «бьёт X», хотя выстрел невозможен.
static var rollback_doing_g2 := false
## нижняя панель без переноса строк, как было: на 1366 строка занятий всего флота делала
## её шире окна, и панель уходила за оба края (вторая проверка G3).
static var rollback_panel_nowrap := false
## ТОЛЬКО для проверки отката: строка «чем занят» у тяжёлого — как в G2–G3 (без состояний
## пояса доктрины): «… — стоит», когда он идёт к цели.
static var rollback_doing_g3 := false
## ТОЛЬКО для проверки отката (замечание к G4): «держит дистанцию · 148 до «Исса»», хотя 148 —
## в мёртвой зоне и главный калибр молчит.
static var rollback_belt_dead_text := false
## ТОЛЬКО для проверки отката (второе замечание к G4): тяжёлый, идущий за охраняемым по
## приказу, — «идёт на участок», как будто охрану забыли (строку «идёт за «…»» не охраняла
## ни одна проверка).
static var rollback_escort_text := false
## ТОЛЬКО для проверки отката (план GИ): у чужого корабля в «ИИ против ИИ» панель пишет
## «Противник», а не клан (хвост G5, п. 1) — как в 0.6.1. Откат той же двери, что у ленты,
## — State.rollback_watch_voice; этот флажок — ТОЛЬКО для панели.
static var rollback_panel_foe_word := false
## ТОЛЬКО для проверок отката (план GИ), в игре всегда false / пусто:
## подсказка клавиш — на прежнем месте под шапкой, поверх чужой линии на старте;
static var rollback_hint_top := false
## раскладка не смотрит на ширину окна — столбик быстрого выбора стоит там, где он на 1920,
## и на 1366 уходит за край;
static var rollback_fixed_layout := false
## этой команды нет на кнопках — её клавиша «потеряна»;
static var rollback_drop_cmd := &""
## кнопка сетки ходит своей дверью, а не командой клавиши: тактика уходит ВСЕМ своим кораблям,
## а не выбранным;
static var rollback_button_own_door := false
## «Отход» без вопроса — одним щелчком.
static var rollback_retreat_no_ask := false

## Строки ленты (feed_log модели: «Противник отходит…», «… копит гипер», «нечем бить») —
## сколько и сколько игровых секунд живут. Лента — у быстрого боя (show_feed): в лаборатории
## её строки о помехах и огне по станции закрывали бы поле, а читать там нечего.
const FEED_MAX := 4
const FEED_GAME_S := 7.0
const FEED_COLORS := {&"good": Color(0.6, 1.0, 0.7), &"warn": Color(1.0, 0.86, 0.45), &"bad": Color(1.0, 0.55, 0.5)}

## Вид боя (view/battle_view.gd): модель, выбор, скорость.
var view: Node3D
## «ИИ против ИИ»: человек только смотрит — сетки команд, ростера и быстрого выбора нет.
var watch := false
## Быстрый бой: лента видна, итог — карточкой (ui/result_card.gd), а не баннером «F8».
var show_feed := false
var quick := false
var feed_box: VBoxContainer
var _feed: Array[Label] = []
var _last_feed := ""
## Ввод (input/battle_input.gd): дверь команд, ожидание A.
var input: Node
var title := ""
## «В меню» (кнопка шапки): что делать — решает экран боя (tools/polygon.gd).
var on_menu: Callable

var header: HudHeader
## Название и часы в шапке (меряют проверки снимков).
var status: Label
var toasts: Label
var panel: PanelContainer
var info: VBoxContainer
var sel_label: Label
var hp_bg: ColorRect
var hp_bar: ColorRect
var grid: CommandGrid
var roster: Roster
var column: VBoxContainer
var quick_buttons: Dictionary[StringName, Button] = {}
var tooltip: HudTooltip
var confirm: ConfirmBox
var box: Panel
var banner: Label
## Свои полоски интерфейса: [текст, мс настоящего времени, когда гаснет].
var _local: Array[Array] = []
var _last_sel := ""
var _last_toasts := ""
var _roster_at := 0
var _roster_sel := ""
var _last_vw := -1.0
var _fit_pending := false
## F4 — строка-отладка пояса над тяжёлыми (09, 6.7; только разработчику): состояние
## доктрины, расстояния, часы «не оторваться». dbg_lines — что нарисовано (uid → текст).
var belt_debug := false
var dbg_lines: Dictionary[int, String] = {}
var _dbg: Array[Label] = []


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	tooltip = HudTooltip.new()
	tooltip.name = "Tooltip"
	add_child(tooltip)
	confirm = ConfirmBox.new()
	confirm.name = "Confirm"
	confirm.view = view
	add_child(confirm)
	header = HudHeader.new()
	header.tooltip = tooltip
	header.watch = watch
	header.quick = quick
	header.on_press = _header_pressed
	add_child(header)
	status = header.status
	toasts = _label(17, Color(1.0, 0.93, 0.7))
	toasts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toasts)
	# нижняя панель: что выбрано (слева) и сетка команд (справа)
	panel = Builder.panel("SelPanel", 8.0)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	sel_label = _label(13, Color(0.85, 0.92, 1.0))
	sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sel_label.max_lines_visible = 4
	info.add_child(sel_label)
	var hp_row := Control.new()
	hp_row.custom_minimum_size = Vector2(0.0, 5.0)
	info.add_child(hp_row)
	hp_bg = ColorRect.new()
	hp_bg.color = Color(0.0, 0.0, 0.0, 0.6)
	hp_row.add_child(hp_bg)
	hp_bar = ColorRect.new()
	hp_row.add_child(hp_bar)
	grid = CommandGrid.new()
	grid.name = "Grid"
	grid.tooltip = tooltip
	grid.on_press = _grid_pressed
	row.add_child(grid)
	roster = Roster.new()
	roster.name = "Roster"
	roster.tooltip = tooltip
	roster.on_click = _roster_clicked
	add_child(roster)
	column = VBoxContainer.new()
	column.name = "QuickSelect"
	column.add_theme_constant_override("separation", 5)
	add_child(column)
	for id: StringName in [&"all", &"heavy", &"light", &"markers"]:
		var k := Texts.cmd(id, "key")
		var b := Builder.button(str(id), Texts.cmd(id, "word") + (" · " + k if k != "" else ""), Vector2(COL_W, COL_BTN_H), 15)
		b.pressed.connect(_command.bind(id))
		b.set_meta(&"cf_tip", Texts.tip(id, Texts.cmd(id, "word"), false))
		tooltip.attach(b)
		column.add_child(b)
		quick_buttons[id] = b
	box = Panel.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.56, 1.0, 0.78, 0.08)
	bs.border_color = Color(0.56, 1.0, 0.78, 0.85)
	bs.set_border_width_all(1)
	box.add_theme_stylebox_override("panel", bs)
	box.visible = false
	add_child(box)
	feed_box = VBoxContainer.new()
	feed_box.name = "Feed"
	feed_box.add_theme_constant_override("separation", 2)
	add_child(feed_box)
	for i in FEED_MAX:
		var fl := _label(16, Color.WHITE)
		fl.visible = false
		feed_box.add_child(fl)
		_feed.append(fl)
	banner = _label(24, Color(1.0, 0.9, 0.6))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.visible = false
	add_child(banner)
	Builder.finish(self)
	Builder.stop(panel)


static func _label(size: int, color: Color) -> Label:
	return Builder.label(size, color)


## Своя полоска интерфейса (не о приказе): «Сначала выбери свои корабли».
func say(text: String) -> void:
	_local.append([text, Time.get_ticks_msec() + TOAST_REAL_MS])


## Рамка выбора: пустая — спрятать.
func show_box(r: Rect2) -> void:
	box.visible = r.has_area()
	if box.visible:
		box.position = r.position
		box.size = r.size


## Вопрос перед отходом (ввод зовёт его через input.ask).
func ask(msg: String, yes: String, no: String, on_yes: Callable) -> void:
	if rollback_retreat_no_ask:
		on_yes.call()
		return
	confirm.view = view
	confirm.ask(msg, yes, no, on_yes)


func _command(id: StringName) -> void:
	if input != null:
		input.call("command", id)


func _grid_pressed(id: StringName) -> void:
	if rollback_button_own_door and id in [&"hold", &"guard", &"hunt"]:
		var all := PackedInt32Array()
		var b: Object = view.get("battle")
		var my_side: int = view.get("my_side")
		var ships: Array = b.get("ships")
		for o: Object in ships:
			var s := o as Ship
			if not s.dead and s.side == my_side and not s.station:
				all.append(s.uid)
		b.call("queue", {"op": &"stance", "ids": all, "stance": id})
		return
	_command(id)


func _header_pressed(id: StringName) -> void:
	if id == &"menu":
		if on_menu.is_valid():
			on_menu.call()
		return
	if id == &"reinforce":
		var mode: StringName = header.buttons[&"reinforce"].get_meta(&"mode", &"reinforce")
		_command(mode)
		return
	_command(id)


func _roster_clicked(uids: Array, shift: bool) -> void:
	if input != null:
		input.call("roster_click", uids, shift)


## Все кнопки экрана боя, видимые сейчас (сканер кнопок и проверки «кнопка = клавиша»).
func shown_buttons() -> Array[Button]:
	var out: Array[Button] = header.shown_buttons()
	for id: StringName in grid.buttons:
		if grid.buttons[id].is_visible_in_tree():
			out.append(grid.buttons[id])
	for k: String in roster.cells:
		if roster.cells[k].is_visible_in_tree():
			out.append(roster.cells[k])
	for id: StringName in quick_buttons:
		if quick_buttons[id].is_visible_in_tree():
			out.append(quick_buttons[id])
	return out


## Подсказка клавиш (её ставит main.gd): пока видна — знакам туда нельзя, текст поверх рамки
## не читается ни то, ни другое. Пусто — спрятана.
var hint_rect := Rect2()


## Панели, на которых знаков над кораблями нет (view/markers.gd → avoid): нижняя панель,
## ростер, столбик быстрого выбора. Шапка — отдельно (её низ — top).
func panel_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c: Control in [panel, roster, column]:
		if c.is_visible_in_tree() and c.size.x > 0.0:
			out.append(c.get_global_rect())
	return out


func _process(_delta: float) -> void:
	if view == null:
		return
	var b: Object = view.get("battle")
	if b == null:
		return
	var vs := get_viewport().get_visible_rect().size
	header.watch = watch
	header.quick = quick
	header.refresh(b, view, input if is_instance_valid(input) else null, title)
	header.place(vs)
	var over: bool = b.get("over")
	# бой кончился — часы стоят, и полоски модели висели бы вечно; итог говорит баннер
	var tt := "" if over else _toast_text(b)
	if tt != _last_toasts:
		_last_toasts = tt
		toasts.text = tt
	_place_toasts(vs)
	_refresh_panel(b, vs)
	_place_bottom(vs)
	_draw_belt_debug(b)
	_show_feed(b, vs)
	var mk: Object = view.get("markers")
	if mk != null:
		mk.set("top", HEADER_H)
		var av := panel_rects()
		if hint_rect.has_area():
			av.append(hint_rect)
		mk.set("avoid", av)
	tooltip.refresh()
	banner.visible = over and not quick
	if over:
		var w: int = b.get("winner")
		var my_side: int = view.get("my_side")
		banner.text = "Бой окончен: %s.\nF8 — начать заново" % ("ничья" if w < 0 else ("наша сторона держит орбиту" if w == my_side else "орбиту держит противник"))
		banner.reset_size()
		banner.position = ((vs - banner.size) * 0.5).floor() - Vector2(0.0, vs.y * 0.18)


## Узкое окно (меньше 1600) — кнопки сетки и колонка «что выбрано» уже. Ширина кнопки — под
## самое длинное слово сетки: «Бомбардировщик» кеглем 11 (101 точка) на 1366 и 12 (110) на 1920;
## на прежних 92 точках оно не влезало и кеглем 10 (92 > 84) — край слова срезался.
static func compact(vs: Vector2) -> bool:
	return vs.x < 1600.0 and not rollback_fixed_layout


static func grid_btn(vs: Vector2) -> Vector2:
	return Vector2(112.0, 42.0) if compact(vs) else Vector2(124.0, 46.0)


static func info_w(vs: Vector2) -> float:
	return 330.0 if compact(vs) else 420.0


## Высота нижней панели постоянная (ростер над ней не прыгает при смене выделения, 07, 1.7):
## два ряда кнопок сетки и поля.
static func panel_h(vs: Vector2) -> float:
	return grid_btn(vs).y * 2.0 + 4.0 + 16.0


## Что выбрано, сетка команд, полоска прочности — по выбору и бою.
func _refresh_panel(b: Object, vs: Vector2) -> void:
	var sl := _sel_text(b)
	var vw := info_w(vs)
	if sl != _last_sel or vw != _last_vw:
		_last_sel = sl
		_last_vw = vw
		_fit_pending = true
	var ids := commands_now(b)
	grid.visible = not ids.is_empty()
	grid.set_commands(ids, grid_btn(vs))
	_update_grid(b)
	# прочность — одной функцией корабля (hp_frac, задел на «что выбито», 07, 7.2 п. 11)
	var one := _single(b)
	hp_bg.visible = one >= 0.0
	hp_bar.visible = one >= 0.0
	var w := info_w(vs)
	if one >= 0.0:
		hp_bg.size = Vector2(w, 4.0)
		hp_bar.size = Vector2(maxf(w * clampf(one, 0.0, 1.0), 1.0), 4.0)
		hp_bar.color = Builder.OWN if _single_own(b) else Builder.FOE
	if rollback_panel_nowrap:
		sel_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		sel_label.custom_minimum_size = Vector2.ZERO
	else:
		sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sel_label.custom_minimum_size = Vector2(w, 0.0)
	# нижняя панель — постоянной высоты; строки «что выбрано» сверх неё не показываются
	var lines := floori((panel_h(vs) - 16.0 - 9.0) / maxf(sel_label.get_line_height(), 1.0))
	sel_label.max_lines_visible = maxi(lines, 2)
	if _fit_pending:
		_fit_pending = false
		_fit_sel()
	panel.custom_minimum_size = Vector2(0.0, panel_h(vs))
	panel.reset_size()


## Прочность единственного выбранного (корабль — hp_frac, звено — среднее по машинам); −1 — нет.
func _single(b: Object) -> float:
	var sel: Array[int] = view.get("selection")
	if sel.size() != 1:
		return -1.0
	var s: Ship = b.call("ship_by_uid", sel[0])
	if s != null and not s.dead:
		return s.hp_frac()
	var q: Squad = b.call("squad_by_uid", sel[0])
	if q != null and not q.dead and not q.craft.is_empty():
		var sum := 0.0
		for c in q.craft:
			sum += c.hp_frac()
		return sum / float(q.craft.size())
	return -1.0


func _single_own(b: Object) -> bool:
	var sel: Array[int] = view.get("selection")
	var my_side: int = view.get("my_side")
	var s: Ship = b.call("ship_by_uid", sel[0])
	if s != null:
		return s.side == my_side
	var q: Squad = b.call("squad_by_uid", sel[0])
	return q != null and q.side == my_side


## Какие команды есть у выбранного (07, 2.10): атака с ходу — у кораблей и звеньев; тактики,
## дрифт, гипер — у кораблей; пуск — у носителей (и станции); посадка — у звеньев; купол — у РЭБ.
## «ИИ против ИИ» и повтор записи — сетки нет.
func commands_now(_b: Object) -> Array[StringName]:
	var out: Array[StringName] = []
	if input == null or watch:
		return out
	var enabled: bool = input.get("orders_enabled")
	if not enabled:
		return out
	var ships: PackedInt32Array = input.call("own_selected")
	var squads: PackedInt32Array = input.call("own_squads")
	var carriers: PackedInt32Array = input.call("own_carriers")
	var ecms: PackedInt32Array = input.call("own_ecms")
	for id in Texts.GRID_ORDER:
		var has := false
		match id:
			&"amove":
				has = not ships.is_empty() or not squads.is_empty()
			&"hold", &"guard", &"hunt", &"drift", &"hyper":
				has = not ships.is_empty()
			&"launch_interceptor", &"launch_fighter", &"launch_bomber":
				has = not carriers.is_empty()
			&"recall":
				has = not squads.is_empty()
			&"ecm_jam", &"ecm_shield", &"ecm_off":
				has = not ecms.is_empty()
		if has and id != rollback_drop_cmd:
			out.append(id)
	return out


## Слова и вид кнопок сетки на месте: «горит» — у всех выбранных, «часть» — у некоторых
## (C26, C136; 07, 1.8), пуск — «ангар N» и недоступен без свободных мест.
func _update_grid(b: Object) -> void:
	if grid.buttons.is_empty():
		return
	var own: Array[Ship] = []
	var own_ids: PackedInt32Array = input.call("own_selected")
	var car_ids: PackedInt32Array = input.call("own_carriers")
	var ecm_ids: PackedInt32Array = input.call("own_ecms")
	for u in own_ids:
		var s: Ship = b.call("ship_by_uid", u)
		if s != null:
			own.append(s)
	var n := own.size()
	var armed: bool = input.get("amove_armed")
	for id: StringName in grid.buttons:
		var word := Texts.cmd(id, "word")
		var top := Texts.cmd(id, "top")
		var how := Builder.Look.NORMAL
		match id:
			&"amove":
				how = Builder.Look.ON if armed else Builder.Look.NORMAL
			&"hold", &"guard", &"hunt":
				var k := 0
				for s in own:
					if s.stance == id:
						k += 1
				how = _part_look(k, n)
				if k > 0 and k < n:
					top = "%d из %d" % [k, n]
			&"drift":
				var kd := 0
				for s in own:
					if s.drift:
						kd += 1
				how = _part_look(kd, n)
				if kd > 0 and kd < n:
					top = "%d из %d" % [kd, n]
			&"hyper":
				var kh := 0
				for s in own:
					if s.charging():
						kh += 1
				if kh > 0:
					word = Texts.cmd(&"unhyper", "word")
					top = Texts.cmd(&"unhyper", "top")
					how = Builder.Look.ON
			&"launch_interceptor", &"launch_fighter", &"launch_bomber":
				var free := 0
				for u in car_ids:
					var c: Ship = b.call("ship_by_uid", u)
					if c != null and c.hangar != null:
						free += c.hangar.free
				top = "ангар %d" % free
				how = Builder.Look.OFF if free <= 0 else Builder.Look.NORMAL
			&"ecm_jam", &"ecm_shield", &"ecm_off":
				var first: Ship = null
				for u in ecm_ids:
					first = b.call("ship_by_uid", u)
					break
				var mode: StringName = {&"ecm_jam": &"jam", &"ecm_shield": &"shield", &"ecm_off": &"off"}[id]
				how = Builder.Look.ON if first != null and first.ecm_mode == mode else Builder.Look.NORMAL
		grid.update_cmd(id, word, top, how)
	if not grid.buttons.has(&"hyper"):
		return
	var hb := grid.buttons[&"hyper"]
	var tip_id := &"unhyper" if hb.get_meta(&"cf_look", -1) == Builder.Look.ON else &"hyper"
	hb.set_meta(&"cf_tip", Texts.tip(tip_id, Texts.cmd(tip_id, "word"), false))


static func _part_look(k: int, n: int) -> Builder.Look:
	if k <= 0 or n <= 0:
		return Builder.Look.NORMAL
	return Builder.Look.ON if k == n else Builder.Look.PART


## Низ экрана: нижняя панель (слева), ростер над ней на постоянной высоте, столбик быстрого
## выбора справа; лента — над ростером.
func _place_bottom(vs: Vector2) -> void:
	var ph := panel_h(vs)
	panel.position = Vector2(EDGE, vs.y - EDGE - ph)
	var my_side: int = view.get("my_side")
	var now := Time.get_ticks_msec()
	var sel: Array[int] = view.get("selection")
	var sk := str(sel)
	roster.visible = not watch
	if roster.visible and (now >= _roster_at or sk != _roster_sel):
		_roster_at = now + 250
		_roster_sel = sk
		var bt: Object = view.get("battle")
		roster.refresh(bt, my_side, sel)
	roster.reset_size()
	roster.position = Vector2(EDGE, panel.position.y - 6.0 - Roster.CELL.y)
	for id: StringName in quick_buttons:
		quick_buttons[id].visible = id == &"markers" or not watch
	var mk: Object = view.get("markers")
	if mk != null:
		var on: bool = mk.get("on")
		var mb := quick_buttons[&"markers"]
		var how := Builder.Look.ON if on else Builder.Look.NORMAL
		var was: int = mb.get_meta(&"cf_look", -1)
		if was != how:
			Builder.look(mb, how)
	column.reset_size()
	var w := 1920.0 if rollback_fixed_layout else vs.x
	column.position = Vector2(w - EDGE - COL_W, vs.y - EDGE - column.size.y)


## Лента: последние строки feed_log моложе FEED_GAME_S игровых секунд — слева над ростером,
## цветом по виду (хорошо · внимание · плохо). Часы игровые: на паузе строка стоит.
func _show_feed(b: Object, vs: Vector2) -> void:
	var lines: Array[Dictionary] = []
	if show_feed:
		var log: Array[Dictionary] = b.get("feed_log")
		var t: float = b.get("time")
		var i := log.size() - 1
		while i >= 0 and lines.size() < FEED_MAX:
			var e: Dictionary = log[i]
			var et: float = e["t"]
			if t - et > FEED_GAME_S:
				break
			lines.push_front(e)
			i -= 1
	var key := ""
	for e in lines:
		key += str(e["step"]) + str(e["text"]) + "|"
	if key != _last_feed:
		_last_feed = key
		for j in FEED_MAX:
			var fl := _feed[j]
			fl.visible = j < lines.size()
			if fl.visible:
				fl.text = str(lines[j]["text"])
				var col: Color = FEED_COLORS.get(lines[j]["kind"], Color(0.85, 0.92, 1.0))
				fl.add_theme_color_override("font_color", col)
		feed_box.reset_size()
	var above := roster.position.y if roster.visible else panel.position.y
	if not hint_gone() and hint_h > 0.0:
		above -= hint_h + 8.0              # подсказка клавиш стоит над ростером, лента — над ней
	feed_box.position = Vector2(PANEL_GAP, above - feed_box.size.y - 8.0)


## Полоски — по середине экрана под шапкой и подсказкой клавиш; длинная — переносится по
## словам в пределах окна (с полями TOAST_GAP).
func _place_toasts(vs: Vector2) -> void:
	toasts.autowrap_mode = TextServer.AUTOWRAP_OFF
	toasts.custom_minimum_size = Vector2.ZERO
	toasts.reset_size()
	var band := vs.x - 2.0 * TOAST_GAP
	if toasts.size.x > band:
		toasts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		toasts.custom_minimum_size = Vector2(band, 0.0)
		toasts.size = Vector2(band, 0.0)
		toasts.reset_size()
	toasts.position = Vector2(((vs.x - toasts.size.x) * 0.5), TOAST_Y_OLD if rollback_toast_old_y else TOAST_Y).floor()


## Подсказка ввода, которая держится, пока ввод в этом состоянии (A ждёт щелчка).
func input_hint() -> String:
	if input == null:
		return ""
	var armed: bool = input.get("amove_armed")
	return "A — щёлкните точку или врага · Esc — отмена" if armed else ""


func _toast_text(b: Object) -> String:
	# подсказки ввода — ПЕРВЫМИ и всегда (хвост G2): полоски модели о приказах шли
	# первыми, и три приказа подряд вытесняли «A — щёлкните точку или врага» целиком
	var hints := PackedStringArray()
	var ih := input_hint()
	if ih != "":
		hints.append(ih)
	var now := Time.get_ticks_msec()
	var keep: Array[Array] = []
	for l in _local:
		var until: int = l[1]
		if until > now:
			keep.append(l)
	_local = keep
	for j in range(_local.size() - 1, -1, -1):
		if hints.size() >= HINTS_MAX:
			break
		hints.append(str(_local[j][0]))
	var room := TOASTS_MAX if rollback_hints_last else TOASTS_MAX - hints.size()
	var out := PackedStringArray()
	var log: Array[Dictionary] = b.get("toast_log")
	var t: float = b.get("time")
	var i := log.size() - 1
	while i >= 0 and out.size() < room:
		var e: Dictionary = log[i]
		var et: float = e["t"]
		if t - et > TOAST_GAME_S:
			break
		out.append(str(e["text"]))
		i -= 1
	if rollback_hints_last:
		for h in hints:
			if out.size() >= TOASTS_MAX:
				break
			out.append(h)
		return "\n".join(out)
	hints.append_array(out)
	return "\n".join(hints)


## Состав выбора словами: «Флагман · Фрегат ×2 · Корвет ×4 · Перехватчик».
func _composition(b: Object, sel: Array[int]) -> String:
	var order: Array[String] = []
	var cnt: Dictionary[String, int] = {}
	for u in sel:
		var s: Ship = b.call("ship_by_uid", u)
		var w := ""
		if s != null and not s.dead:
			w = Roster.word_of(s)
		else:
			var q: Squad = b.call("squad_by_uid", u)
			if q == null or q.dead:
				continue
			var st := b as State
			var rd: Defs.StrikeRoleDef = st.defs.strike_roles.get(q.role)
			w = rd.label if rd != null else str(q.role)
		if not cnt.has(w):
			order.append(w)
			cnt[w] = 0
		cnt[w] += 1
	var parts := PackedStringArray()
	for w in order:
		parts.append(w if cnt[w] == 1 else "%s ×%d" % [w, cnt[w]])
	return " · ".join(parts)


## Подсказка клавиш боя (ui/fps_counter.gd, её ведёт main.gd): слева над ростером, как в JS
## (07, 1.11), а не под шапкой — там на старте стоит чужая линия, и строки ложились на её
## знаки. Гаснет через 16 игровых секунд (07, 2.13): клавиши приказов теперь на кнопках.
const HINT_GONE_S := 16.0
var hint_h := 0.0


func hint_top(h: float) -> float:
	hint_h = h
	if rollback_hint_top:
		return HINT_TOP
	var above := roster.position.y if roster.visible else panel.position.y
	return above - 8.0 - h


func hint_gone() -> bool:
	if view == null:
		return false
	var b: Object = view.get("battle")
	var t: float = b.get("time") if b != null else 0.0
	return t > HINT_GONE_S


## Чья это сторона словами: в «ИИ против ИИ» — клан (State.clan_voice — одна дверь с лентой),
## в бою с приказами — «Противник» (свои — «Выбрано: N»).
func _side_word(b: Object, side: int) -> String:
	var voice: bool = b.call("clan_voice")
	if voice and not rollback_panel_foe_word:
		var st := b as State
		return st.clan_tag(side)
	return Texts.FOE


## Что выбрано и чем занято (07, 1.8). Один корабль — имя, класс, скорость и прочность, чем
## занят; несколько — «Выбрано: N», имена (до четырёх) и занятия (до трёх видов). Клавиши
## теперь — на кнопках сетки, в панели их нет; мышь — одной строкой.
func _sel_text(b: Object) -> String:
	var sel: Array[int] = view.get("selection")
	var my_side: int = view.get("my_side")
	if sel.is_empty() and watch:
		_sel_alts = PackedStringArray([Texts.WATCH_HINT])
		return Texts.WATCH_HINT
	if sel.is_empty():
		var nt := "%s\n%s" % [Texts.NOTHING, Texts.NOTHING_HINT]
		_sel_alts = PackedStringArray([nt, Texts.NOTHING])
		return nt
	var names := PackedStringArray()
	var own := 0
	var acts: Dictionary[String, int] = {}
	var foe_side := -1
	var single: Ship = null
	for u in sel:
		var s: Ship = b.call("ship_by_uid", u)
		var q: Squad = b.call("squad_by_uid", u) if s == null else null
		if q != null and not q.dead:
			# звено: «Перехватчик «Зонг» ×4/5» (04, 1.1)
			if names.size() < 4:
				names.append(squad_name(q, b as State))
			if q.side == my_side and not watch:
				own += 1
				var qa := squad_doing(q, b as State)
				var qc: int = acts.get(qa, 0)
				acts[qa] = qc + 1
			else:
				foe_side = q.side
				if watch:
					var wa := squad_doing(q, b as State)
					var wc: int = acts.get(wa, 0)
					acts[wa] = wc + 1
			continue
		if s == null or s.dead:
			continue
		if sel.size() == 1:
			single = s
		if names.size() < 4:
			names.append(s.name)
		if s.side == my_side and not watch:
			own += 1
			var a := doing(s, b as State)
			var c: int = acts.get(a, 0)
			acts[a] = c + 1
		else:
			foe_side = s.side
			if watch:
				# «ИИ против ИИ»: смотрят обе стороны — чем занят и корабль противника (подсказка
				# панели это обещает; в бою с приказами чужое занятие не показываем, как в G4)
				var fa := doing(s, b as State)
				var fc: int = acts.get(fa, 0)
				acts[fa] = fc + 1
	var head := ""
	if own > 0:
		head = "Выбрано: %d" % sel.size()
	elif foe_side >= 0:
		head = _side_word(b, foe_side)
	elif watch:
		head = _side_word(b, my_side)
	var more := "" if sel.size() <= names.size() else ", …"
	var line := "%s — %s%s" % [head, ", ".join(names), more]
	if sel.size() > 3:
		# много выбранных — состав по классу («Корвет ×8 · Фрегат ×4»), а не четыре имени (07, 1.8)
		line = "%s — %s" % [head, _composition(b, sel)]
	if single != null:
		line += "\n%s · скорость %d · прочность %d%%" % [single.def.role_text, roundi(single.vel.length()), roundi(single.hp_frac() * 100.0)]
	# панель постоянной высоты: текст, который в неё не лёг, НЕ обрезается на полуслове, а
	# короче — сначала уходит строка мыши, потом лишние занятия (3 → 2 → 1 вида), потом занятия
	# совсем (_fit_sel выбирает первый вариант, который влез)
	var mouse := "\nПКМ — лететь, по врагу — бить его" if own > 0 and not watch else ""
	_sel_alts = PackedStringArray()
	for k: int in [3, 3, 2, 1, 0]:
		var t := line + _acts_text(acts, k)
		if _sel_alts.is_empty():
			t += mouse
		_sel_alts.append(t)
	return _sel_alts[0]


## Занятия выбранных одной строкой: не больше k видов, остальное — «…» (k = 0 — пусто).
static func _acts_text(acts: Dictionary[String, int], k: int) -> String:
	if k <= 0 or acts.is_empty():
		return ""
	var act_list := PackedStringArray()
	for a: String in acts:
		if act_list.size() >= k:
			act_list.append("…")
			break
		# «×N», а не просто число: в строках занятий свои числа («(1068)», «… III»), и «III 1»
		# читалось бы как часть имени
		act_list.append(a if acts.size() == 1 else "%s ×%d" % [a, acts[a]])
	return "\n" + ", ".join(act_list)


## Варианты текста «что выбрано» от полного к короткому (их собирает _sel_text).
var _sel_alts := PackedStringArray()
## ТОЛЬКО для проверки отката (план GИ): текст выбранного ставится целиком, лишнее режется
## по высоте панели — последняя строка обрывается на полуслове. В игре false.
static var rollback_panel_cut := false


## Первый вариант «что выбрано», который целиком влезает в панель (строк не больше видимых).
func _fit_sel() -> void:
	# ширина — та, с которой текст встанет в панель: Label сам свою ширину до кадра раскладки не
	# знает, и на первом кадре мерил бы строки по прежней (на старте — по нулевой)
	sel_label.size = Vector2(sel_label.custom_minimum_size.x, sel_label.size.y)
	for t in _sel_alts:
		sel_label.text = t
		if rollback_panel_cut or sel_label.get_line_count() <= sel_label.max_lines_visible:
			return


## «Перехватчик «Зонг» ×4/5» — роль, имя машины, живых из поднятых (04, 1.1).
static func squad_name(q: Squad, b: State) -> String:
	var rd: Defs.StrikeRoleDef = b.defs.strike_roles.get(q.role)
	return "%s %s ×%d/%d" % [rd.label if rd != null else str(q.role), q.def.name, q.craft.size(), q.size]


## Чем занято своё звено (04, 1.1: «атакует», «идёт к точке», «перезаряжается»,
## «патрулирует»; доктрина 09, 4.2 и 4.4 — обход с фланга и патруль над своей линией).
static func squad_doing(q: Squad, b: State) -> String:
	if q.recall:
		return "на посадку"
	var reloading := 0
	var flank := 0
	var fighting := 0
	var leaving := 0
	for c in q.craft:
		if c.leaving:
			leaving += 1
		elif c.reloading > 0.0:
			reloading += 1
		elif Air.routing(b, c):
			flank += 1
		elif c.target != null:
			fighting += 1
	if leaving > 0:
		return "ракет нет — уходит с поля"
	if reloading * 2 >= q.craft.size():
		return "перезаряжается у носителя"
	if flank * 2 >= q.craft.size():
		return "обходит строй с фланга"
	if fighting > 0:
		var t := q.target as Ship
		return "атакует %s" % Weapons.short_name(t) if t != null and not t.dead else "атакует"
	if q.has_move:
		return "ждёт у точки" if q.pos.distance_to(q.move_to) < Air.LEG_REACH * 2.0 else "идёт к точке"
	if q.role == &"interceptor":
		return "патрулирует над своей линией"
	return "кружит у носителя"


## F4: строки-отладки над каждым видимым тяжёлым (обеих сторон) — где он на экране.
func _draw_belt_debug(b: Object) -> void:
	dbg_lines.clear()
	var cam: Camera3D = null
	var rig: Object = view.get("rig")
	if rig != null:
		cam = rig.get("camera")
	var n := 0
	if belt_debug and cam != null:
		var bt := b as State
		var my_side: int = view.get("my_side")
		for s in bt.ships:
			if s.dead or not s.heavy() or s.station or not Picking.shown(s, my_side):
				continue
			var pt: Vector3 = view.call("ship_point", s)
			if cam.is_position_behind(pt):
				continue
			var txt := belt_line(s, bt)
			dbg_lines[s.uid] = txt
			while _dbg.size() <= n:
				var l := _label(13, Color(1.0, 0.85, 0.45))
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				add_child(l)
				_dbg.append(l)
			var lb := _dbg[n]
			lb.text = txt
			lb.visible = true
			lb.reset_size()
			lb.position = (cam.unproject_position(pt) - Vector2(lb.size.x * 0.5, 46.0)).floor()
			n += 1
	for i in range(n, _dbg.size()):
		_dbg[i].visible = false


## Строка-отладка пояса (F4): состояние доктрины, до цели движения и до ближайшего чужого,
## часы и выигрыш окна «не оторваться», сколько врагов «не повод отходить».
static func belt_line(s: Ship, b: State) -> String:
	var parts := PackedStringArray([HeavyDoctrine.NAMES[s.belt] if not s.legacy else "по-старому"])
	var t := s.forced as Ship
	if t == null or t.dead:
		t = s.target as Ship
	if t != null and not t.dead:
		parts.append("цель %d" % roundi(s.pos.distance_to(t.pos)))
	var nd := INF
	for o in b.ships:
		if not o.dead and o.side != s.side:
			nd = minf(nd, s.pos.distance_to(o.pos))
	if nd < INF:
		parts.append("ближ. %d / D %d" % [roundi(nd), roundi(s.def.main.dead)])
	if s.ret_foe != null:
		parts.append("окно %.1f с +%d" % [s.ret_clock, roundi(s.ret_gain)])
	if not s.futile.is_empty():
		parts.append("не повод: %d" % s.futile.size())
	return " · ".join(parts)


## Чем занят свой корабль — одной строкой (07, 7.2 п. 2; 09, 6.7: слово «бьёт» — только
## когда выстрел возможен). b — бой: докуда батарея бьёт сейчас (под помехами —
## lockRange).
static func doing(s: Ship, b: State) -> String:
	if s.charging():
		return "копит гипер %d с" % ceili(s.hyper_left)
	if s.drift:
		return "дрейф"
	if s.has_move:
		return "идёт в точку"
	var t := s.target as Ship
	var sec := s.sec_target as Ship
	var fz := s.forced as Ship
	var jam := ""
	if s.jam != null and s.heavy():
		var jp: Defs.EcmDef = s.jam
		jam = " · под помехами — главный калибр %s" % Weapons.slower(jp.main_slow)
	if s.heavy() and not s.legacy and not s.station and not rollback_doing_g3:
		return _doing_belt(s, b, jam)
	if s.heavy():
		# «батареей по …» — только если батарея по ней СЕЙЧАС достаёт (под помехами —
		# ближе lockRange, 09, 1.3): иначе это обещание выстрела, которого нет
		var bat := ""
		if sec != null and not sec.dead and s.pos.distance_to(sec.pos) <= Weapons.sec_reach(b, s):
			bat = " · батареей по %s" % Weapons.short_name(sec)
		# цель фокуса вне пояса, а главный калибр бьёт свою цель в поясе (09, 6.3): приказ
		# не потерян — строка называет, почему по цели фокуса не бьёт
		var off := ""
		if fz != null and not fz.dead and fz != t and not rollback_focus_unnamed:
			off = " · %s вне пояса (%d)" % [Weapons.short_name(fz), roundi(s.pos.distance_to(fz.pos))]
		if s.idle_reason == &"dead_zone":
			if rollback_bat_claim and bat == "":
				bat = " · бьёт батарея"
			return "враг вплотную — главный калибр не бьёт%s%s%s" % [bat, off, jam]
		if t != null and not t.dead and Weapons.main_reach(s, s.pos.distance_to(t.pos)) == 0:
			return "главным по %s (%d)%s%s%s" % [Weapons.short_name(t), roundi(s.pos.distance_to(t.pos)), bat, off, jam]
		if fz != null and not fz.dead and not rollback_focus_unnamed:
			return "цель %s вне пояса (%d) — стоит%s%s" % [Weapons.short_name(fz), roundi(s.pos.distance_to(fz.pos)), bat, jam]
		# своя цель вне пояса (на «Охоте» — до 1,8 R): пока тяжёлый в пояс не ходит (G4),
		# он стоит, и строка обязана это сказать, а не «целей не видно» (хвост G2)
		if t != null and not t.dead and not s.has_amove and not rollback_doing_g2:
			var dt_ := s.pos.distance_to(t.pos)
			return "цель %s %s (%d) — стоит%s%s" % [Weapons.short_name(t), "вне пояса" if Weapons.main_reach(s, dt_) > 0 else "в мёртвой зоне", roundi(dt_), bat, jam]
		if s.has_amove:
			return "идёт с боем%s" % jam
		if bat != "":
			return "держит позицию%s%s%s" % [bat, off, jam]
	elif s.target != null:
		var tb := s.target as Body
		if tb != null and not tb.dead:
			var d := s.pos.distance_to(tb.pos)
			var tn := Weapons.short_name(t) if t != null else "машины звена"
			# под помехами лёгкое бьёт только ближе lockRange: «бьёт X» дальше — обещание
			# выстрела, которого нет (хвост G2; 09, 6.7)
			if s.def.light != null and d <= s.def.light.rng and d > Weapons.light_reach(b, s) and not rollback_doing_g2:
				return "под помехами — бьёт только вблизи (%s в %d)" % [tn, roundi(d)]
			if s.has_amove or s.forced != null or s.stance == &"hunt":
				return ("бьёт %s" if s.def.light != null and d <= s.def.light.rng else "идёт на %s") % tn
			return ("бьёт %s" if s.def.light != null and d <= s.def.light.rng else "охрана · видит %s") % tn
	if s.has_amove:
		return "идёт с боем"
	if s.vel.length() > 3.0:
		return "тормозит" if s.stance == &"hold" else "идёт на участок"
	match s.stance:
		&"hunt":
			return "охота · целей не видно"
		&"hold":
			return "стоит%s" % jam
	return "стоит%s" % jam


## Строка тяжёлого доктрины (09, 6.7) — по состоянию пояса (sim/heavy_doctrine.gd): «выходит
## на дистанцию · 940 до «Рэш»», «держит дистанцию · главным по «Рэш» (620)», «враг вплотную
## — отходит · батареей по «Исса»», «не оторваться от «Исса» — бьёт батареей», «прижат —
## главным по «Рэш» · батареей по «Исса»», «держит позицию · враг вплотную — бьёт батареей»,
## «путь к «Рэш» закрыт — «Исса» в 340». «Бьёт» — только когда выстрел возможен.
static func _doing_belt(s: Ship, b: State, jam: String) -> String:
	var t := s.target as Ship
	var sec := s.sec_target as Ship
	var fz := s.forced as Ship
	var mt := fz if fz != null and not fz.dead else t        # против кого встаёт в пояс (2.9)
	if mt != null and mt.dead:
		mt = null
	var bat_ok := sec != null and not sec.dead and s.pos.distance_to(sec.pos) <= Weapons.sec_reach(b, s)
	var bat := " · батареей по %s" % Weapons.short_name(sec) if bat_ok else ""
	# «бьёт батареей по X» — только когда батарея по X СЕЙЧАС достаёт (откат — без проверки)
	var bat_hit := " — бьёт батареей по %s" % Weapons.short_name(sec) if bat_ok else (" — бьёт батареей" if rollback_bat_claim else "")
	var main := ""
	if t != null and not t.dead and Weapons.main_reach(s, s.pos.distance_to(t.pos)) == 0:
		main = "главным по %s (%d)" % [Weapons.short_name(t), roundi(s.pos.distance_to(t.pos))]
	# цель фокуса вне пояса, а главный калибр бьёт свою (6.3) — приказ не потерян
	var off := ""
	if fz != null and not fz.dead and fz != t and not rollback_focus_unnamed:
		off = " · %s вне пояса (%d)" % [Weapons.short_name(fz), roundi(s.pos.distance_to(fz.pos))]
	var close: Ship = null
	var cd := INF
	for o in b.ships:
		if o.dead or o.side == s.side or not Picking.shown(o, s.side):
			continue
		var d := s.pos.distance_to(o.pos)
		if d < cd:
			cd = d
			close = o
	match s.belt:
		HeavyDoctrine.APPROACH:
			var head := "выходит на дистанцию · %d до %s" % [roundi(s.pos.distance_to(mt.pos)), Weapons.short_name(mt)] if mt != null else "выходит на дистанцию"
			return head + (" · " + main if main != "" and t != mt else "") + bat + jam
		HeavyDoctrine.BELT:
			if main != "":
				return "держит дистанцию · %s%s%s%s" % [main, bat, off, jam]
			if mt != null and s.pos.distance_to(mt.pos) < s.def.main.dead and not rollback_belt_dead_text:
				# цель ближе мёртвой зоны — это не «держит дистанцию»: главный калибр по ней молчит
				return "%s в мёртвой зоне (%d)%s%s" % [Weapons.short_name(mt), roundi(s.pos.distance_to(mt.pos)), bat_hit, jam]
			if mt != null:
				return "держит дистанцию · %d до %s%s%s" % [roundi(s.pos.distance_to(mt.pos)), Weapons.short_name(mt), bat, jam]
			return "держит дистанцию%s%s" % [bat, jam]
		HeavyDoctrine.BLOCKED:
			var who := "%s в %d" % [Weapons.short_name(close), roundi(cd)] if close != null else "чужой рядом"
			var tn := Weapons.short_name(mt) if mt != null else "цели"
			return "путь к %s закрыт — %s%s%s%s" % [tn, who, (" · " + main) if main != "" else "", bat_hit.replace(" — ", " · "), jam]
		HeavyDoctrine.LEASH:
			var tn2 := "%s (%d)" % [Weapons.short_name(mt), roundi(s.pos.distance_to(mt.pos))] if mt != null else "цель"
			return "на краю участка · %s дальше поводка%s%s" % [tn2, bat, jam]
		HeavyDoctrine.RETREAT:
			return "враг вплотную — отходит%s%s%s" % [(" · " + main) if main != "" else "", bat, jam]
		HeavyDoctrine.PINNED:
			return "прижат%s%s%s" % [(" — " + main) if main != "" else "", bat, jam]
		HeavyDoctrine.FUTILE:
			var fo: Ship = null
			for u: int in s.futile:
				var o := b.ship_by_uid(u)
				if o != null and not o.dead and (fo == null or s.pos.distance_to(o.pos) < s.pos.distance_to(fo.pos)):
					fo = o
			var fn := Weapons.short_name(fo) if fo != null else "врага"
			return "не оторваться от %s%s%s%s" % [fn, bat_hit, (" · " + main) if main != "" else "", jam]
		HeavyDoctrine.HOLD:
			if close != null and cd < s.def.main.dead:
				return "держит позицию · враг вплотную%s%s%s" % [bat_hit, (" · " + main) if main != "" else "", jam]
			if main != "":
				return "держит позицию · %s%s%s%s" % [main, bat, off, jam]
			return "держит позицию%s%s" % [bat, jam]
		HeavyDoctrine.MOVE:
			if s.has_amove:
				return "идёт с боем%s%s" % [bat, jam]
			if HeavyDoctrine.escorting(b, s) and not rollback_escort_text:
				return "идёт за %s%s%s" % [Weapons.short_name(s.guard_of as Ship), bat, jam]
			return "идёт на участок%s%s" % [bat, jam]
	if main != "":
		return "%s%s%s%s" % [main, bat, off, jam]
	if bat != "":
		return "стоит%s%s" % [bat, jam]
	return "стоит%s" % jam
