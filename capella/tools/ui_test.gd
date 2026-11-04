extends SceneTree
## Проверка управления настоящими событиями мыши и клавиш (под Xvfb).
var main
var fails := 0

func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1

func click(p: Vector2, btn := MOUSE_BUTTON_LEFT) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	Input.parse_input_event(m)
	await process_frame
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = btn
		e.pressed = pressed
		e.position = p
		e.global_position = p
		Input.parse_input_event(e)
		await process_frame
	await process_frame

func key(k: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	main._start(false)
	await frames(10)
	var v = main.battle
	var w: World = v.world
	var hud = v.hud
	# 1. Кнопка постройки
	var b: Button = hud.build_btns["warden" if w.teams[0].fac == "troyden" else "ogr"]
	var ore0: float = w.teams[0].ore
	await click(b.get_global_rect().get_center())
	ok(w.teams[0].station.build_queue.size() == 1, "нажатие по кнопке постройки ставит в очередь")
	ok(w.teams[0].ore < ore0, "руда списана")
	# 2. Выбор корабля щелчком
	var ship = null
	for u in w.units:
		if u.team == 0 and not u.is_station() and not u.is_squad() and u.cls != "harvester":
			ship = u
			break
	v.focus(ship.pos)
	await frames(5)
	var sp: Vector2 = v.screen_of(ship)
	await click(sp)
	ok(v.sel == [ship], "щелчок выбирает корабль")
	await frames(3)
	ok(hud.sel_box.visible, "панель выбранного видна")
	# 3. ПКМ — приказ лететь
	await click(sp + Vector2(200, 0), MOUSE_BUTTON_RIGHT)
	ok(ship.order == "move", "ПКМ по пустому месту — приказ лететь (%s)" % ship.order)
	# 4. Рамка выделения
	var dr := InputEventMouseButton.new()
	dr.button_index = MOUSE_BUTTON_LEFT
	dr.pressed = true
	dr.position = Vector2(5, 5) + Vector2(300, 100)
	Input.parse_input_event(dr)
	await frames(2)
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(1300, 800)
	Input.parse_input_event(mm)
	await frames(2)
	dr = dr.duplicate()
	dr.pressed = false
	dr.position = Vector2(1300, 800)
	Input.parse_input_event(dr)
	await frames(3)
	ok(v.sel.size() >= 1, "рамка выбирает несколько (%d)" % v.sel.size())
	# 5. Атака врага и выбор хардпоинта
	var enemy := w.spawn("howard" if w.teams[1].fac == "troyden" else "whiteshark", 1, ship.pos + Vector2(9000, 0))
	w._update_vis()
	v.sel = [ship]
	v.focus(ship.pos + Vector2(4000, 0))
	await frames(5)
	var ep: Vector2 = v.screen_of(enemy)
	await click(ep, MOUSE_BUTTON_RIGHT)
	ok(ship.order == "attack" and ship.target == enemy, "ПКМ по врагу — атака")
	await frames(15)
	var hp_btn: Button = null
	for c in hud.sel_body.get_children():
		if c is GridContainer:
			for bb in c.get_children():
				if bb is Button and bb.text.begins_with(enemy.hps[0].label):
					hp_btn = bb
	ok(hp_btn != null, "у цели видны кнопки хардпоинтов")
	if hp_btn:
		await click(hp_btn.get_global_rect().get_center())
		ok(ship.target_hp == enemy.hps[0].id, "нажатие по хардпоинту — цель «%s»" % enemy.hps[0].label)
	# 6. Пауза, справка, меню
	await key(KEY_SPACE)
	ok(v.paused, "пробел — пауза")
	await key(KEY_SPACE)
	await key(KEY_F1)
	ok(hud.help_box.visible, "F1 — справка")
	await key(KEY_F1)
	await key(KEY_ESCAPE)
	ok(hud.menu_box.visible and v.paused, "Esc — меню паузы")
	await key(KEY_ESCAPE)
	# 7. Отход
	v.sel = [ship]
	await key(KEY_R)
	ok(ship.charge > 0, "R — зарядка гиперпрыжка")
	# 8. Улучшение станции
	w.teams[0].ore = 5000
	await frames(15)
	var up: Button = hud.st_body.get_node("up")
	await click(up.get_global_rect().get_center())
	ok(w.teams[0].station.upgrading > 0, "кнопка улучшения станции")
	# 9. Мини-карта: щелчок по вражеской станции переносит камеру к ней
	var est: Unit = w.teams[1].station
	var mp: Vector2 = hud.mini.global_position + hud._m2mini(est.pos)
	await click(mp)
	ok(Vector2(v.pivot.x, v.pivot.z).distance_to(est.pos * 0.1) < 150, "мини-карта: камера к вражеской станции")
	ok(hud._m2mini(w.teams[0].station.pos).y > hud.MINI * 0.7, "мини-карта: своя станция внизу")
	root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/ui.png")
	print("ПРОВАЛОВ: %d" % fails)
	quit(fails)
