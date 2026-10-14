# ui/quick_menu.gd — меню «Быстрый бой» (часть 01, 1.1; 07, 2.16; план G5, п. 3): твой клан
# и противник (Тройден, Плэктор; зеркальный бой можно; Рииз и Девиан видны, но выключены —
# «в следующих сборках»), масштаб, сложность — все четыре, под выбором её описание, по
# умолчанию «Офицер». Игрок — атакующий, как в JS. Две двери: «В бой» и «Смотреть: ИИ против
# ИИ» (человек только смотрит). Выбор — кнопками в ряд, а не выпадающими списками: щёлкнуть
# проще, и проверка нажимает ровно то, что увидит человек.
# Правила интерфейса (00, 6.2–6.4): раскладочные узлы — IGNORE, кнопки — FOCUS_NONE, окно —
# STOP целиком.
extends CanvasLayer

signal start(cfg: Dictionary)

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const FrameBench := preload("res://ui/frame_bench.gd")
const Ai := preload("res://sim/ai.gd")

## Кланы, которые срез уже умеет (модели, проверки): остальные видны, но выключены.
const READY: Array[StringName] = [&"troyden", &"plektor"]
const LATER_TEXT := "в следующих сборках"

var defs: Defs
var build := ""
var cfg := {}
var panel: PanelContainer
var desc_label: Label
var lineup_label: Label
var later_label: Label
## Кнопки по ключу «ряд:значение» (mine:troyden, foe:plektor, size:mid, dif:normal) и «go», «watch».
var buttons: Dictionary[String, Button] = {}
## Сколько раз нажата каждая кнопка — проверки.
var presses: Dictionary[String, int] = {}


func setup(p_defs: Defs, p_build: String) -> void:
	defs = p_defs
	build = p_build
	cfg = default_cfg(defs)


## Выбор по умолчанию (данные быстрого боя: Тройден × Плэктор, «Сражение», «Офицер»).
static func default_cfg(p_defs: Defs, watch: bool = false) -> Dictionary:
	var q := p_defs.quick
	return {"attacker": str(q.default_mine), "defender": str(q.default_foe), "size": str(q.default_size),
		"difficulty": str(q.default_difficulty), "watch": watch}


## Что сложность меняет В ЭТОМ бою — из её чисел (03, 2.18; 05, 2.8): как часто думает ИИ,
## множитель урона его оружия (aim, space.js:309 aiMul) и сколько его тяжёлых бьют общую цель. Описание из данных
## («добывает вполсилы», «вдвое больше денег») — про кампанию, в быстром бою его нет.
static func difficulty_text(dd: Defs.DifficultyDef) -> String:
	var lo := String.num(Ai.THINK_MIN * dd.tempo, 1).replace(".", ",")
	var hi := String.num(Ai.THINK_MAX * dd.tempo, 1).replace(".", ",")
	var focus := "огонь в одну цель не сводит"
	if dd.focus >= 1.0:
		focus = "общую цель бьют все его тяжёлые"
	elif dd.focus > 0.0:
		focus = "общую цель бьют %d из 10 его тяжёлых" % roundi(dd.focus * 10.0)
	var pct := roundi(dd.aim * 100.0)
	var force := "в полную силу, как твои"
	if pct < 100:
		force = "слабее твоих: %d%% урона" % pct
	elif pct > 100:
		force = "сильнее твоих: %d%% урона" % pct
	return "Противник решает раз в %s–%s с, его орудия бьют %s, %s." % [lo, hi, force, focus]


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var back := ColorRect.new()
	back.color = Color(0.0, 0.0, 0.02, 0.55)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	panel = PanelContainer.new()
	panel.name = "QuickMenu"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.95)
	sb.border_color = Color(0.35, 0.55, 0.8, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_text("Капелла · быстрый бой на орбите", 26, Color(1.0, 0.92, 0.7)))
	box.add_child(_text("Ты — атакующий. У планеты противника орудие, оно бьёт по твоему флоту.", 16, Color(0.75, 0.82, 0.9)))
	box.add_child(_gap())
	box.add_child(_text("Твой клан", 17, Color(0.85, 0.92, 1.0)))
	box.add_child(_clan_row("mine"))
	box.add_child(_text("Противник", 17, Color(0.85, 0.92, 1.0)))
	box.add_child(_clan_row("foe"))
	later_label = _text("", 14, Color(0.6, 0.66, 0.74))
	box.add_child(later_label)
	box.add_child(_gap())
	box.add_child(_text("Масштаб", 17, Color(0.85, 0.92, 1.0)))
	var srow := _row()
	var sg := ButtonGroup.new()
	for id in defs.quick.size_ids:
		var sn: String = defs.quick.size_names.get(id, str(id))
		srow.add_child(_choice("size:%s" % id, sn, sg))
	box.add_child(srow)
	lineup_label = _text("", 15, Color(0.75, 0.82, 0.9))
	box.add_child(lineup_label)
	box.add_child(_gap())
	box.add_child(_text("Сложность", 17, Color(0.85, 0.92, 1.0)))
	var drow := _row()
	var dg := ButtonGroup.new()
	for id in defs.difficulty_ids:
		var dd: Defs.DifficultyDef = defs.difficulty[id]
		drow.add_child(_choice("dif:%s" % id, dd.name, dg))
	box.add_child(drow)
	desc_label = _text("", 15, Color(0.75, 0.82, 0.9))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(560.0, 0.0)
	box.add_child(desc_label)
	box.add_child(_gap())
	var act := _row()
	act.add_child(_action("go", "В бой"))
	act.add_child(_action("watch", "Смотреть: ИИ против ИИ"))
	box.add_child(act)
	box.add_child(_text("%s · F3 — счётчик кадров · F11 — полный экран" % build, 13, Color(0.5, 0.56, 0.64)))
	_sync()


static func _text(s: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func _gap() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(0.0, 4.0)
	return c


static func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 8)
	return h


func _clan_row(row: String) -> HBoxContainer:
	var h := _row()
	var g := ButtonGroup.new()
	for id in defs.faction_ids:
		var f: Defs.FactionDef = defs.factions[id]
		var b := _choice("%s:%s" % [row, id], f.name, g)
		if not (id in READY):
			b.disabled = true
			b.tooltip_text = "%s — %s" % [f.name, LATER_TEXT]
		h.add_child(b)
	return h


func _choice(key: String, text: String, g: ButtonGroup) -> Button:
	var b := Button.new()
	b.name = key.replace(":", "_")
	b.text = text
	b.toggle_mode = true
	b.button_group = g
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(128.0, 34.0)
	b.add_theme_font_size_override("font_size", 16)
	# выбранное — рамкой и светлым текстом: штатная тёмная заливка «нажатой» кнопки на тёмной
	# панели почти не отличается от обычной (снимок меню). Поля по бокам — как у обычной (4):
	# ширину кнопке даёт обычный стиль, и с полями 6 выбранный клан читался «Клан Тройде»
	# (снимок; test_render_quick меряет надпись в обоих видах)
	var on := StyleBoxFlat.new()
	on.bg_color = Color(0.16, 0.22, 0.32)
	on.border_color = Color(1.0, 0.85, 0.5)
	on.set_border_width_all(2)
	on.set_corner_radius_all(4)
	on.set_content_margin_all(6)
	on.content_margin_left = 4.0
	on.content_margin_right = 4.0
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.8))
	b.add_theme_color_override("font_hover_pressed_color", Color(1.0, 0.95, 0.8))
	b.pressed.connect(_pick.bind(key))
	buttons[key] = b
	return b


func _action(key: String, text: String) -> Button:
	var b := Button.new()
	b.name = key
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(220.0, 42.0)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(_go.bind(key == "watch"))
	buttons[key] = b
	return b


func _pick(key: String) -> void:
	_count_press(key)
	var row := key.get_slice(":", 0)
	var val := key.get_slice(":", 1)
	match row:
		"mine": cfg["attacker"] = val
		"foe": cfg["defender"] = val
		"size": cfg["size"] = val
		"dif": cfg["difficulty"] = val
	_sync()


func _go(watch: bool) -> void:
	_count_press("watch" if watch else "go")
	var out := cfg.duplicate()
	out["watch"] = watch
	start.emit(out)


func _count_press(k: String) -> void:
	var n: int = presses.get(k, 0)
	presses[k] = n + 1


## Кнопки и подписи — по выбору.
func _sync() -> void:
	for key: String in buttons:
		var b := buttons[key]
		if not b.toggle_mode:
			continue
		var row := key.get_slice(":", 0)
		var val := key.get_slice(":", 1)
		var want := ""
		match row:
			"mine": want = str(cfg["attacker"])
			"foe": want = str(cfg["defender"])
			"size": want = str(cfg["size"])
			"dif": want = str(cfg["difficulty"])
		b.set_pressed_no_signal(val == want)
	var later := PackedStringArray()
	for id in defs.faction_ids:
		if not (id in READY):
			var f: Defs.FactionDef = defs.factions[id]
			later.append(f.name)
	later_label.text = "%s — %s" % [" и ".join(later), LATER_TEXT] if not later.is_empty() else ""
	var dd: Defs.DifficultyDef = defs.difficulty.get(StringName(str(cfg["difficulty"])))
	desc_label.text = difficulty_text(dd) if dd != null else ""
	lineup_label.text = lineup_text(defs, cfg)
	_center()


## «У тебя 8 кораблей и резерв из 5, у противника 22 и станция» — что будет в бою.
static func lineup_text(p_defs: Defs, c: Dictionary) -> String:
	var size := StringName(str(c["size"]))
	var mine := _count(Battle.compose(p_defs, size, StringName(str(c["attacker"]))))
	var res := _count(Battle.compose(p_defs, &"small", StringName(str(c["attacker"]))))
	var foe := _count(Battle.compose(p_defs, size, StringName(str(c["defender"]))))
	var st := " и станция" if size in p_defs.quick.station_on else ""
	return "У тебя %d %s и резерв из %d, у противника %d%s" % [mine, FrameBench.plural(mine, "корабль", "корабля", "кораблей"), res, foe, st]


static func _count(list: Array[Defs.FleetEntry]) -> int:
	var n := 0
	for e in list:
		n += e.count
	return n


func _center() -> void:
	if panel == null or not is_inside_tree():
		return
	panel.reset_size()
	var vs := get_viewport().get_visible_rect().size
	panel.position = ((vs - panel.size) * 0.5).floor()


func _process(_delta: float) -> void:
	_center()
