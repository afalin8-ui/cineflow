## Стенд интерфейса без окна: godot --headless --path proj -s res://tests/ui_test.gd -- inject=parse|push
extends SceneTree

var hud: ProbeHud
var field_clicks: Array = []
var inject := "parse"
var fails := 0
var checks := 0

class Field extends Node:
	var log: Array
	func _unhandled_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			log.append(e.position)

func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
	print(("  ok   " if cond else "  FAIL ") + what)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv[0] == "inject": inject = kv[1]
	_run()

func send(e: InputEvent) -> void:
	if inject == "push":
		root.push_input(e, true)
	else:
		Input.parse_input_event(e)
		Input.flush_buffered_events()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func mouse(pos: Vector2, button := MOUSE_BUTTON_LEFT, pressed := true) -> void:
	var b := InputEventMouseButton.new()
	b.position = pos
	b.global_position = pos
	b.button_index = button
	b.pressed = pressed
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	send(b)

func move(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	send(m)

## аналог elementFromPoint: что под точкой получит нажатие
func under(pos: Vector2) -> Control:
	move(pos)
	await frames(1)
	return root.gui_get_hovered_control()

func click(pos: Vector2, hold := 0, between := Callable()) -> void:
	move(pos)
	await frames(1)
	mouse(pos, MOUSE_BUTTON_LEFT, true)
	await frames(1)
	if between.is_valid():
		between.call()
	await frames(hold)
	mouse(pos, MOUSE_BUTTON_LEFT, false)
	await frames(1)

func key(physical: Key, keycode: Key, unicode := 0, echo := false) -> void:
	var k := InputEventKey.new()
	k.physical_keycode = physical
	k.keycode = keycode
	k.unicode = unicode
	k.pressed = true
	k.echo = echo
	send(k)
	var u := k.duplicate()
	u.pressed = false
	u.echo = false
	send(u)

func all_buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button and c.is_visible_in_tree():
			out.append(c)
		all_buttons(c, out)

func _run() -> void:
	var f := Field.new()
	f.log = field_clicks
	root.add_child(f)
	hud = ProbeHud.new()
	root.add_child(hud)
	print("inject=", inject, " display=", DisplayServer.get_name())
	await frames(1)   # в --headless размер, заданный до первого кадра, откатывается к 64×64
	for sz in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		root.size = sz
		await frames(3)
		ok(root.get_visible_rect().size == Vector2(sz), "окно стенда %s" % [sz])
		print("== size ", sz)
		# 1. Сканер: каждая видимая кнопка нажимается настоящим щелчком в центр
		var btns: Array = []
		all_buttons(hud, btns)
		var good := 0
		var bad: Array = []
		var vis := root.get_visible_rect()
		var off: Array = []
		for b in btns:
			if not vis.encloses(b.get_global_rect()):
				off.append(b.name)
		ok(off.is_empty(), "все кнопки целиком на экране %s (за краем: %s)" % [vis.size, off])
		for b in btns:
			var c: Vector2 = b.get_global_rect().get_center()
			var h := await under(c)
			var n0: int = hud.pressed_log.size()
			await click(c)
			if h == b and hud.pressed_log.size() == n0 + 1:
				good += 1
			else:
				bad.append("%s(under=%s)" % [b.name, h.name if h else "null"])
		ok(bad.is_empty(), "все %d видимых кнопок нажимаются щелчком в центр (плохие: %s)" % [btns.size(), bad])
		# 2. Пустая полоса ростера — поле (C135)
		var r: Rect2 = hud.roster.get_global_rect()
		var empty := Vector2(r.end.x - 40, r.get_center().y)
		var n1 := field_clicks.size()
		var h2 := await under(empty)
		await click(empty)
		ok(h2 == null and field_clicks.size() == n1 + 1, "пустое место ростера (%s) уходит в поле, под точкой: %s" % [empty, h2])
		# 3. Пустое место шапки справа — поле? (шапка во всю ширину со STOP его глотает)
		var tr: Rect2 = hud.top.get_global_rect()
		var tp := Vector2(tr.end.x - 30, tr.get_center().y)
		var h3 := await under(tp)
		var n3 := field_clicks.size()
		await click(tp)
		print("  info шапка во всю ширину, mouse_filter=STOP: под точкой %s, поле получило щелчок: %s" % [h3.name if h3 else "null", field_clicks.size() == n3 + 1])
	# 4. Контейнер IGNORE не делает прозрачными детей (C2 в Godot закрыт устройством)
	hud.top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await frames(1)
	var pb: Button = hud.buttons["x2"]
	var hb := await under(pb.get_global_rect().get_center())
	ok(hb == pb, "кнопка внутри шапки с IGNORE по-прежнему ловит мышь (C2 не повторяется)")
	var tr2: Rect2 = hud.top.get_global_rect()
	var tp2 := Vector2(tr2.end.x - 30, tr2.get_center().y)
	var n4 := field_clicks.size()
	await click(tp2)
	ok(field_clicks.size() == n4 + 1, "шапка с IGNORE: пустое место шапки уходит в поле (C135)")
	# 5. C30: медленный щелчок, панель обновляется между нажатием и отпусканием
	var hold_btn: Button = hud.buttons["hold"]
	var pos: Vector2 = hold_btn.get_global_rect().get_center()
	var n5: int = hud.pressed_log.size()
	await click(pos, 5, hud.refresh)
	ok(hud.pressed_log.size() == n5 + 1, "C30: медленный щелчок при обновлении НА МЕСТЕ засчитан")
	hud.rebuild_each_refresh = true
	var n6: int = hud.pressed_log.size()
	await click(pos, 5, hud.refresh)
	ok(hud.pressed_log.size() == n6, "C30-ловушка воспроизводится: при пересборке панели щелчок теряется (откат обязан проваливаться)")
	hud.rebuild_each_refresh = false
	hud.refresh()
	await frames(2)
	# 6. Пробел не нажимает кнопку снова (focus_mode = NONE) — и нажимает у кнопки по умолчанию
	var stop_btn: Button = hud.buttons["stop"]
	await click(stop_btn.get_global_rect().get_center())
	var n7: int = hud.pressed_log.size()
	key(KEY_SPACE, KEY_SPACE, 32)
	await frames(2)
	ok(hud.pressed_log.size() == n7, "Пробел после щелчка по кнопке HUD (FOCUS_NONE) её не нажимает")
	var def := Button.new()
	def.text = "по умолчанию"
	def.position = Vector2(700, 300)
	def.size = Vector2(160, 40)
	var cnt := [0]
	def.pressed.connect(func(): cnt[0] += 1)
	hud.root.add_child(def)
	await frames(1)
	await click(def.get_global_rect().get_center())
	key(KEY_SPACE, KEY_SPACE, 32)
	await frames(2)
	ok(cnt[0] == 2, "ловушка 30 воспроизводится: кнопка с фокусом по умолчанию жмётся Пробелом второй раз (нажатий %d)" % cnt[0])
	def.queue_free()
	# 7. Клавиши по физическому месту: русская раскладка, клавиша H
	InputMap.add_action("cmd_hold_phys")
	var ep := InputEventKey.new(); ep.physical_keycode = KEY_H
	InputMap.action_add_event("cmd_hold_phys", ep)
	InputMap.add_action("cmd_hold_key")
	var ek := InputEventKey.new(); ek.keycode = KEY_H
	InputMap.action_add_event("cmd_hold_key", ek)
	var ru := InputEventKey.new()
	ru.physical_keycode = KEY_H
	ru.keycode = 1088 as Key    # «р» в русской раскладке
	ru.unicode = 1088
	ru.pressed = true
	ok(ru.is_action_pressed("cmd_hold_phys"), "H в русской раскладке: действие по физическому коду срабатывает")
	ok(not ru.is_action_pressed("cmd_hold_key"), "H в русской раскладке: действие по keycode молчит (ловушка 2.9)")
	var echo := ru.duplicate()
	echo.echo = true
	ok(not echo.is_action_pressed("cmd_hold_phys"), "повтор клавиши (echo) is_action_pressed не засчитывает")
	# 8. Окно вопроса: повтор Esc его не закрывает, первое Esc закрывает
	hud.confirm.popup_centered()
	await frames(2)
	key(KEY_ESCAPE, KEY_ESCAPE, 0, true)
	await frames(2)
	ok(hud.confirm.visible, "повтор Esc (echo) окно вопроса не закрывает")
	key(KEY_ESCAPE, KEY_ESCAPE)
	await frames(2)
	ok(not hud.confirm.visible, "первое Esc закрывает окно вопроса (ConfirmationDialog сам)")
	# 9. Пауза: меню поверх глотает мышь; кнопки меню живут на паузе
	hud.show_pause(true)
	await frames(2)
	var hs := await under(stop_btn.get_global_rect().get_center())
	ok(hs == hud.pause_panel, "на паузе щелчок по месту «Стоп» берёт затемнение меню, а не кнопку (под точкой: %s)" % (hs.name if hs else "null"))
	var rb: Button = hud.buttons["resume"]
	var n9: int = hud.pressed_log.size()
	await click(rb.get_global_rect().get_center())
	ok(hud.pressed_log.size() == n9 + 1 and hud.pressed_log[-1] == "resume", "на паузе кнопка «Продолжить» нажимается (PROCESS_MODE_ALWAYS)")
	hud.show_pause(false)
	# 10. Снимок экрана без окна
	var img := root.get_texture().get_image() if root.get_texture() else null
	print("  info снимок в --headless: ", "нет картинки" if img == null or img.is_empty() else "%dx%d" % [img.get_width(), img.get_height()])
	print("RESULT checks=%d fails=%d" % [checks, fails])
	quit(1 if fails > 0 else 0)
