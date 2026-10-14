# ui/result_card.gd — простая карточка итога (часть 05, 1.6 и 2.13; план G5, пп. 3 и 5; полная —
# G7): заголовок и слова исхода, длина боя, потери по видам у обеих сторон, кто ушёл в гипер
# и резерв, выжимка отчёта (исход, длина, первое попадание, М1–М4, доли урона, шаг модели)
# и кнопки «Ещё раз», «В меню», «Скопировать» (выжимку — в буфер, её вставляют в чат) и
# «Открыть папку» (там строка отчёта JSON и запись боя). Под карточкой бой стоит насовсем
# (05, ловушка 31): её показывают, когда battle.over.
# Правила интерфейса (00, 6.2–6.4): раскладочные узлы — IGNORE, кнопки — FOCUS_NONE, окно —
# STOP целиком.
extends CanvasLayer

signal again
signal to_menu

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")

## Порядок видов в потерях (space.js:3857 endStats).
const ORDER: Array[StringName] = [&"capital", &"sinho", &"cruiser", &"carrier", &"ecm", &"frigate", &"corvette", &"station"]

var panel: PanelContainer
var title_label: Label
var text_label: Label
var stats_label: Label
var brief_label: Label
var file_label: Label
var buttons: Dictionary[String, Button] = {}
## Поля карточки до краёв окна.
const FIT_GAP := 24.0
var _last_vs := Vector2.ZERO
var presses: Dictionary[String, int] = {}
var brief := ""
var file := ""
## Тесты: кнопки нажимаются, но папка не открывается и буфер не трогается (под xvfb буфер
## настоящий — проверка читает его сама, когда dry выключен).
var dry := false


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "ResultCard"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.95)
	sb.border_color = Color(0.35, 0.55, 0.8, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	title_label = _text(28, Color(1.0, 0.92, 0.7))
	box.add_child(title_label)
	text_label = _text(17, Color(0.85, 0.92, 1.0))
	box.add_child(text_label)
	stats_label = _text(16, Color(0.85, 0.92, 1.0))
	box.add_child(stats_label)
	var head := _text(15, Color(0.75, 0.82, 0.9))
	head.text = "Выжимка отчёта — её можно прислать в чат кнопкой «Скопировать»:"
	box.add_child(head)
	brief_label = _text(14, Color(0.7, 0.78, 0.86))
	box.add_child(brief_label)
	file_label = _text(13, Color(0.55, 0.62, 0.7))
	box.add_child(file_label)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for k: String in ["again", "menu", "copy", "open"]:
		var b := Button.new()
		b.name = k
		b.text = {"again": "Ещё раз", "menu": "В меню", "copy": "Скопировать", "open": "Открыть папку"}[k]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150.0, 38.0)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_press.bind(k))
		row.add_child(b)
		buttons[k] = b


static func _text(size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _press(k: String) -> void:
	var n: int = presses.get(k, 0)
	presses[k] = n + 1
	match k:
		"again":
			again.emit()
		"menu":
			to_menu.emit()
		"copy":
			if not dry and DisplayServer.get_name() != "headless":
				DisplayServer.clipboard_set(brief)
		"open":
			if not dry and file != "" and DisplayServer.get_name() != "headless":
				OS.shell_open(file.get_base_dir())


func is_open() -> bool:
	return panel != null and panel.visible


## Показать итог боя b: rep — отчёт (sim/report.gd), p_brief — его выжимка, p_file — где лежит
## строка отчёта ("" — записать не удалось).
func show_result(b: Battle, defs: Defs, p_brief: String, p_file: String) -> void:
	brief = p_brief
	file = p_file
	var p := b.player_side
	var res := str(b.result)
	var saved := b.sides[p].jumped.size()
	var spare := 0
	for e in b.sides[p].reserve:
		spare += e.count
	if b.watch:
		if b.winner < 0:
			title_label.text = "Ничья"
			text_label.text = "Обе стороны ушли с орбиты одновременно."
		else:
			var w := b.sides[b.winner]
			var wf: Defs.FactionDef = defs.factions.get(w.clan)
			title_label.text = "Орбиту удержал %s" % (wf.name if wf != null else str(w.clan))
			text_label.text = "%s: его противник уничтожен или ушёл в гипер." % ("Атакующий" if b.winner == Ship.ATTACKER else "Защитник")
	else:
		match res:
			"victory":
				title_label.text = "Орбита за нами"
				text_label.text = "Противник больше не контролирует орбиту: его флот уничтожен или ушёл."
			"retreat":
				title_label.text = "Отход"
				text_label.text = "Флот вышел из боя. Домой вернутся только те, кто успел уйти в гипер."
			_:
				title_label.text = "Флот разбит"
				var back := PackedStringArray()
				if saved > 0:
					back.append("ушедшие в гипер")
				if spare > 0:
					back.append("корабли резерва")
				text_label.text = ("Орбита за противником. Домой вернутся только %s." % " и ".join(back)) if not back.is_empty() else "Корабли потеряны. Орбита остаётся за противником."
	stats_label.text = stats_text(b, defs)
	brief_label.text = brief
	file_label.text = ("Отчёт и запись боя — в папке: %s" % file.get_base_dir()) if file != "" else "Файл отчёта записать не удалось — хватит и выжимки выше."
	buttons["open"].disabled = file == ""
	panel.visible = true
	_fit()


## Карточка по тексту, но не шире окна без FIT_GAP с каждой стороны: длинные строки (потери
## «Генерального», путь к папке) переносятся по словам, а не уводят карточку за края.
func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var labels: Array[Label] = [text_label, stats_label, brief_label, file_label]
	for l in labels:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size = Vector2.ZERO
	panel.reset_size()
	var room := vs.x - 2.0 * FIT_GAP
	if panel.size.x > room:
		var pad := panel.size.x - stats_label.size.x
		for l in labels:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(maxf(room - pad, 200.0), 0.0)
		panel.reset_size()
	_last_vs = vs
	panel.position = ((vs - panel.size) * 0.5).floor()


func hide_result() -> void:
	if panel != null:
		panel.visible = false


## Время, потери по видам у обеих сторон («2 из 6», ушедшие — «⇢1»), ушедшие и резерв.
static func stats_text(b: Battle, defs: Defs) -> String:
	var lines := PackedStringArray()
	lines.append("Бой длился %d:%02d" % [floori(b.time / 60.0), floori(b.time) % 60])
	var p := b.player_side
	var mine := "Атакующий" if b.watch else "Мы"
	var foe := "Защитник" if b.watch else "Противник"
	for side: int in [p, 1 - p]:
		var parts := PackedStringArray()
		for id in ORDER:
			var n := 0
			var lost := 0
			var fled := 0
			var word := ""
			for s in b.ships:
				if s.side != side or s.def.id != id:
					continue
				n += 1
				if s.fled:
					fled += 1
				elif s.dead:
					lost += 1
				if word == "":
					word = _word(s)
			if n == 0:
				continue
			parts.append("%s %d из %d%s" % [word, lost, n, (" ⇢%d" % fled) if fled > 0 else ""])
		var fd: Defs.FactionDef = defs.factions.get(b.sides[side].clan)
		lines.append("%s (%s), потери: %s" % [mine if side == p else foe, fd.name if fd != null else "", ", ".join(parts)])
	var saved := b.sides[p].jumped.size()
	var spare := 0
	for e in b.sides[p].reserve:
		spare += e.count
	var tally := PackedStringArray()
	if saved > 0:
		tally.append("ушли в гипер: %d" % saved)
	if spare > 0:
		tally.append("резерв в бой не вступал: %d" % spare)
	if not tally.is_empty() and not b.watch:
		var t := " · ".join(tally)
		lines.append(t.substr(0, 1).to_upper() + t.substr(1))
	return "\n".join(lines)


## Слово класса: часть роли до « · », у станции — «станция» (space.js:3863 classWord).
static func _word(s: Ship) -> String:
	if s.station:
		return "станция"
	var r := s.def.role_text.get_slice(" · ", 0)
	return r.to_lower() if r != "" else str(s.def.id)


func _process(_delta: float) -> void:
	if panel != null and panel.visible:
		var vs := get_viewport().get_visible_rect().size
		if vs != _last_vs:
			_fit()
		panel.position = ((vs - panel.size) * 0.5).floor()
