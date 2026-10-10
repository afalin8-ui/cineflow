extends Node
## Аналог tests/game-e2e.js для интерфейса: НАСТОЯЩИЕ события ввода через
## Input.parse_input_event, «кто под точкой» — gui_get_hovered_control()
## (аналог elementFromPoint), журнал нажатий — у самого интерфейса.
const HUD = preload("res://ui/hud_probe.gd")
const FIELD = preload("res://ui/field_probe.gd")
var hud; var field
var fails := 0; var passes := 0
var mask := 0

func ok(cond: bool, what: String) -> void:
	if cond: passes += 1; print("  ПРОШЛО  ", what)
	else: fails += 1; print("  ПРОВАЛ  ", what)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new(); ev.position = p; ev.global_position = p; ev.button_mask = mask
	Input.parse_input_event(ev); await frames(2)
func mbtn(p: Vector2, idx: int, down: bool) -> void:
	var bit := 1 << (idx - 1)
	mask = (mask | bit) if down else (mask & ~bit)
	var ev := InputEventMouseButton.new(); ev.position = p; ev.global_position = p
	ev.button_index = idx; ev.pressed = down; ev.button_mask = mask
	Input.parse_input_event(ev); await frames(2)
func click(p: Vector2, idx := MOUSE_BUTTON_LEFT) -> void:
	await move(p); await mbtn(p, idx, true); await mbtn(p, idx, false)
func key(phys: Key, code: Key, uni: int, down := true, echo := false) -> void:
	var ev := InputEventKey.new(); ev.physical_keycode = phys; ev.keycode = code; ev.unicode = uni
	ev.pressed = down; ev.echo = echo
	Input.parse_input_event(ev); await frames(2)
func under(p: Vector2) -> Control:
	await move(p); return get_viewport().gui_get_hovered_control()
func center(c: Control) -> Vector2: return c.get_global_rect().get_center()

func _ready() -> void:
	# В --headless окно 64×64 и ключ --resolution не действует: размер — кодом
	var res := Vector2i(1920, 1080)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("res="): res = Vector2i(int(arg.split("=")[1].split("x")[0]), int(arg.split("=")[1].split("x")[1]))
	get_window().size = res
	var a := InputEventKey.new(); a.physical_keycode = KEY_A
	InputMap.add_action("cmd_amove"); InputMap.action_add_event("cmd_amove", a)
	var a2 := InputEventKey.new(); a2.keycode = KEY_A
	InputMap.add_action("cmd_amove_by_keycode"); InputMap.action_add_event("cmd_amove_by_keycode", a2)
	field = FIELD.new(); add_child(field)
	hud = HUD.new(); add_child(hud)
	await frames(5)
	print("окно: ", get_viewport().get_visible_rect().size, "  драйвер: ", DisplayServer.get_name(), " / ", RenderingServer.get_current_rendering_driver_name())
	await t_scanner()
	await t_roster_gap()
	await t_panel_default_stop()
	await t_slow_click()
	await t_focus()
	await t_gesture()
	await t_keys()
	await t_dialog_escape()
	await t_pause()
	print("ИТОГ: прошло %d, провалов %d" % [passes, fails])
	get_tree().quit(1 if fails else 0)

# 07, 4.2 п.1: сканер мёртвых кнопок — нажатие в центр получает ИМЕННО кнопка
func t_scanner() -> void:
	print("сканер кнопок:")
	var n := 0; var dead := []
	for b: Button in hud.find_children("*", "Button", true, false):
		if not b.is_visible_in_tree() or b.get_viewport() != get_viewport(): continue
		n += 1
		var c := center(b)
		var u := await under(c)
		var before: int = hud.pressed_count.get(_id(b), 0)
		await click(c)
		if u != b or hud.pressed_count.get(_id(b), 0) != before + 1: dead.append(b.name)
	ok(dead.is_empty() and n >= 15, "все %d видимых кнопок нажимаются настоящим щелчком в центр (мёртвых: %s)" % [n, dead])

func _id(b: Button) -> String: return b.get_meta("id", "")

# C135: пустое место ростера во всю ширину — это поле
func t_roster_gap() -> void:
	var r: HBoxContainer = hud.roster
	var b0: Control = r.get_child(0); var b1: Control = r.get_child(1)
	var gap := Vector2((b0.get_global_rect().end.x + b1.get_global_rect().position.x) / 2.0, b0.get_global_rect().get_center().y)
	var u := await under(gap)
	field.log.clear()
	await click(gap)
	var got: bool = field.log.any(func(x): return x[0] == "unhandled" and x[1] == MOUSE_BUTTON_LEFT and x[2])
	ok(u == null and got, "щелчок в щель ростера уходит в поле (под точкой: %s)" % [u])
	var far := Vector2(get_viewport().get_visible_rect().size.x - 30, b0.get_global_rect().get_center().y)
	field.log.clear(); await click(far)
	ok(field.log.size() > 0, "правее ростера (растянутая полоса) — тоже поле")

# Godot-версия C135/C2: у PanelContainer по умолчанию STOP — растянутая
# подложка глотает щелчки, пока ей не поставить IGNORE
func t_panel_default_stop() -> void:
	var pc := PanelContainer.new(); pc.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	pc.offset_top = -120; pc.offset_bottom = -100
	hud.get_node("Root").add_child(pc); await frames(3)
	var p := Vector2(100, get_viewport().get_visible_rect().size.y - 110)
	field.log.clear(); await click(p)
	var eaten: bool = field.log.is_empty()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE; await frames(2)
	field.log.clear(); await click(p)
	ok(eaten and not field.log.is_empty(), "PanelContainer по умолчанию глотает щелчок (STOP), с IGNORE — пропускает в поле")
	pc.queue_free()
	# C2 наоборот: у Godot IGNORE родителя НЕ наследуется детьми
	ok(hud.roster.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud.pressed_count.get("roster_Крейсер", 0) >= 1,
		"кнопка внутри контейнера с IGNORE нажимается (в браузере прозрачность наследовалась — C2)")

# C30: медленный щелчок (держать 0,5 с, панель обновляется каждые 0,34 с)
func t_slow_click() -> void:
	for rebuild in [false, true]:
		hud.rebuild_each_refresh = rebuild
		await frames(2)
		var b: Button = hud.grid.get_node("cmd_Перехватчик")
		var c := center(b)
		var before: int = hud.pressed_count.get("cmd_Перехватчик", 0)
		await move(c); await mbtn(c, MOUSE_BUTTON_LEFT, true)
		await get_tree().create_timer(0.5).timeout
		await mbtn(c, MOUSE_BUTTON_LEFT, false)
		var fired: bool = hud.pressed_count.get("cmd_Перехватчик", 0) == before + 1
		if rebuild: ok(not fired, "ОТКАТ C30: при пересборке панели медленный щелчок теряется (проверка обязана краснеть)")
		else: ok(fired, "медленный щелчок (0,5 с) по кнопке, обновляемой на месте, срабатывает (C30)")
	hud.rebuild_each_refresh = false
	await frames(3)

# Ловушка 30 (C28): кнопка с фокусом нажимается Пробелом ещё раз
func t_focus() -> void:
	var fb: Button = hud.focus_btn
	await click(center(fb))
	var n1: int = hud.pressed_count.get("focus_default", 0)
	await key(KEY_SPACE, KEY_SPACE, 32); await key(KEY_SPACE, KEY_SPACE, 32, false)
	var n2: int = hud.pressed_count.get("focus_default", 0)
	var sb: Button = hud.grid.get_node("cmd_Стоп")
	await click(center(sb))
	var s1: int = hud.pressed_count.get("cmd_Стоп", 0)
	await key(KEY_SPACE, KEY_SPACE, 32); await key(KEY_SPACE, KEY_SPACE, 32, false)
	ok(n2 == n1 + 1 and hud.pressed_count.get("cmd_Стоп", 0) == s1,
		"FOCUS_ALL (по умолчанию): Пробел жмёт кнопку повторно (%d→%d); FOCUS_NONE — нет" % [n1, n2])

# Ловушка 50: ПКМ нажат на поле, отпущен над кнопкой — жест кончился
func t_gesture() -> void:
	var tgt: Button = hud.grid.get_node("cmd_Охрана")
	for in_input in [true, false]:
		field.listen_in_input = in_input; field.gesture = ""; field.log.clear()
		var start := Vector2(900, 500)
		await move(start); await mbtn(start, MOUSE_BUTTON_RIGHT, true)
		for i in 8: await move(start.lerp(center(tgt), (i + 1) / 8.0))
		var before: int = hud.pressed_count.get("cmd_Охрана", 0)
		await mbtn(center(tgt), MOUSE_BUTTON_RIGHT, false)
		var ended: bool = field.log.any(func(x): return x[0] == "gesture_end")
		if in_input: ok(ended and field.gesture == "" and hud.pressed_count.get("cmd_Охрана", 0) == before,
			"жест с поля, отпущенный над панелью, дослушан в _input: поворот кончился, кнопка не нажалась")
		else:
			var r: Rect2 = tgt.get_global_rect()
			var over: Array = field.log.filter(func(x): return x[0] == "unhandled_motion" and r.grow(2).has_point(x[1]))
			var outside: Array = field.log.filter(func(x): return x[0] == "unhandled_motion" and not r.grow(2).has_point(x[1]))
			print("    только _unhandled_input: движений над кнопкой дошло %d, вне её %d; отпускание дошло: %s" % [over.size(), outside.size(), ended])
			ok(over.is_empty() and ended, "4.7.2: над кнопкой (STOP) движение поле НЕ получает, а отпускание без захвата — получает (жест не залипает, но поворот замирает над панелью)")
	field.listen_in_input = true; field.gesture = ""

# Ловушка 49: клавиши по МЕСТУ. Русская раскладка: физическая A даёт «ф»
func t_keys() -> void:
	field.log.clear()
	await key(KEY_A, 0x0444 as Key, 0x0444)
	await key(KEY_A, 0x0444 as Key, 0x0444, false)
	var e: Array = field.log.filter(func(x): return x[0] == "key")
	ok(e.size() == 1 and e[0][4] and not e[0][5], "русская раскладка: действие по physical_keycode срабатывает, по keycode — нет")
	field.log.clear()
	await key(KEY_ESCAPE, KEY_ESCAPE, 0, true, true)
	var esc: Array = field.log.filter(func(x): return x[0] == "key")
	ok(esc.size() == 1 and esc[0][3] == true, "повтор Esc приходит с echo = true (его и надо отбрасывать, ловушка 27)")

# Окно вопроса и удержанный Esc
func t_dialog_escape() -> void:
	var d: ConfirmationDialog = hud.confirm
	d.popup_centered(); await frames(3)
	await key(KEY_ESCAPE, KEY_ESCAPE, 0, true, true); await key(KEY_ESCAPE, KEY_ESCAPE, 0, false)
	var after_echo := d.visible
	await key(KEY_ESCAPE, KEY_ESCAPE, 0); await key(KEY_ESCAPE, KEY_ESCAPE, 0, false)
	ok(after_echo and not d.visible and hud.pressed_count.get("ask_no", 0) == 1,
		"окно вопроса: повтор Esc не закрывает (виден=%s), обычный Esc закрывает как «Нет»" % after_echo)
	d.popup_centered(); await frames(3)
	var lbl := d.get_label()
	var lc := lbl.get_global_rect().get_center() + Vector2(d.position)
	await click(lbl.get_global_rect().get_center())
	ok(d.visible, "щелчок по тексту окна его не закрывает (ловушка 34)")
	d.hide(); await frames(2)

# Пауза: бой стоит, интерфейс и камера живут (06, 5.2)
var sim_ticks := 0; var ui_ticks := 0
func t_pause() -> void:
	var sim := Node.new(); sim.set_script(GDScript.new())
	var s := GDScript.new(); s.source_code = "extends Node\nvar n := 0\nfunc _physics_process(_d): n += 1\n"; s.reload()
	sim.set_script(s); add_child(sim)
	var ui := Node.new(); var s2 := GDScript.new(); s2.source_code = "extends Node\nvar n := 0\nfunc _process(_d): n += 1\n"; s2.reload()
	ui.set_script(s2); ui.process_mode = Node.PROCESS_MODE_ALWAYS; add_child(ui)
	await frames(3)
	get_tree().paused = true
	var a0: int = sim.n; var b0: int = ui.n
	await get_tree().create_timer(0.3, true).timeout
	ok(sim.n == a0 and ui.n > b0, "пауза дерева: шаг боя стоит (%d→%d), узел ALWAYS живёт (%d→%d)" % [a0, sim.n, b0, ui.n])
	get_tree().paused = false
