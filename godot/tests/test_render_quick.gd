# Картинка меню «Быстрый бой» и карточки итога (план G5, пп. 3, 5) — в обоих отрисовщиках:
# - на 1920 и 1366 меню и карточка целиком в окне, кнопки не наезжают друг на друга и на
#   подсказку клавиш слева сверху (прямоугольники, а не «на глаз»);
# - «Скопировать» кладёт выжимку отчёта в буфер обмена (под xvfb буфер настоящий); откат —
#   карточка «всухую» (dry): буфер не меняется;
# - лента «ИИ против ИИ» (последние строки feed_log) — над нижней панелью, не на ней;
# - снимки — в $CAPELLA_SHOTS (смотреть глазами).
extends "res://tests/case.gd"

const MainScene := preload("res://main.tscn")
const MainScript := preload("res://main.gd")
const Ship := preload("res://sim/ship.gd")
const Polygon := preload("res://tools/polygon.gd")
const QuickMenu := preload("res://ui/quick_menu.gd")
const ResultCard := preload("res://ui/result_card.gd")
const FpsCounter := preload("res://ui/fps_counter.gd")


func _shots_dir() -> String:
	var d := OS.get_environment("CAPELLA_SHOTS")
	if d == "":
		d = tmp("shots")
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _shot(name: String) -> void:
	await hooks.frames(2)
	var img := tree.root.get_viewport().get_texture().get_image()
	var path := _shots_dir().path_join("%s_%s.png" % [name, RenderingServer.get_current_rendering_method()])
	img.save_png(path)
	note("снимок %s" % path.get_file())


func _main(size: Vector2i, dir_name: String) -> Node:
	await hooks.set_window_size(size)
	MainScript.out_override = tmp(dir_name)
	MainScript.seed_override = 7070
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	await hooks.frames(6)
	return main


func _done(main: Node) -> void:
	MainScript.out_override = ""
	MainScript.seed_override = -1
	main.queue_free()
	await hooks.frames(2)


## Пары кнопок, чьи прямоугольники пересекаются, и кнопки за краем окна.
static func _overlaps(btns: Array[Button], vs: Vector2) -> PackedStringArray:
	var out := PackedStringArray()
	var view := Rect2(Vector2.ZERO, vs)
	for i in btns.size():
		var a := btns[i].get_global_rect()
		if not view.encloses(a):
			out.append("«%s» за краем окна" % btns[i].text)
		for j in range(i + 1, btns.size()):
			if a.intersects(btns[j].get_global_rect()):
				out.append("«%s» на «%s»" % [btns[i].text, btns[j].text])
	return out


## Кнопки, чья надпись не влезает в кнопку хоть в одном виде (обычный, выбранный): текст шириной
## по шрифту кнопки плюс поля её стиля. Найдено снимком: выбранный клан «Клан Тройде» — рамка
## выбранного стиля шире полей обычного, а ширину кнопке давал обычный.
static func _clipped(btns: Array[Button]) -> PackedStringArray:
	var out := PackedStringArray()
	for b in btns:
		var font := b.get_theme_font("font")
		var fs := b.get_theme_font_size("font_size")
		var w := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		for st: String in ["normal", "pressed"]:
			var sb := b.get_theme_stylebox(st)
			var need := w + sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
			if need > b.size.x + 0.5:
				out.append("«%s» (%s: %.0f > %.0f)" % [b.text, st, need, b.size.x])
	return out


func test_menu_and_card_layout() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		var main := await _main(size, "render_quick_%d" % size.x)
		var vs := Vector2(size)
		var m: QuickMenu = main.get("menu")
		if not ok(m != null, "%d: меню открыто" % size.x):
			await _done(main)
			continue
		await hooks.frames(2)
		var pr := m.panel.get_global_rect()
		ok(Rect2(Vector2.ZERO, vs).encloses(pr), "%d: меню целиком в окне (%s)" % [size.x, str(pr)])
		var fps: FpsCounter = main.get("fps")
		ok(fps == null or not fps.hint.get_global_rect().intersects(pr), "%d: подсказка клавиш слева сверху не на меню" % size.x)
		var btns: Array[Button] = []
		for k: String in m.buttons:
			btns.append(m.buttons[k])
		var bad := _overlaps(btns, vs)
		ok(bad.is_empty(), "%d: кнопки меню не наезжают друг на друга: %s" % [size.x, ", ".join(bad)])
		var cut := _clipped(btns)
		ok(cut.is_empty(), "%d: надпись кнопки меню целиком — и у выбранной (рамкой), и у обычной: %s" % [size.x, ", ".join(cut)])
		await _shot("quick_menu_%d" % size.x)
		# «Смотреть: ИИ против ИИ» — до первых строк ленты, потом итог
		var w: Button = m.buttons["watch"]
		await hooks.click(w.get_global_rect().get_center())
		await hooks.frames(3)
		var p: Polygon = main.get("polygon")
		p.view.speed = 4
		var t0 := Time.get_ticks_msec()
		while p.battle.feed_log.is_empty() and Time.get_ticks_msec() - t0 < 60000:
			await hooks.frames(10)
		await hooks.frames(4)
		var fb := p.hud.feed_box.get_global_rect()
		ok(not p.battle.feed_log.is_empty() and p.hud.feed_box.visible, "%d: в «ИИ против ИИ» видна лента (%d строк)" % [size.x, p.battle.feed_log.size()])
		ok(not fb.intersects(p.hud.panel.get_global_rect()) and Rect2(Vector2.ZERO, vs).encloses(fb), "%d: лента над нижней панелью и в окне (%s)" % [size.x, str(fb)])
		await _shot("quick_watch_%d" % size.x)
		p.battle.finish(Ship.DEFENDER)
		await hooks.frames(4)
		var card: ResultCard = p.card
		var cr := card.panel.get_global_rect()
		ok(card.is_open() and Rect2(Vector2.ZERO, vs).encloses(cr), "%d: карточка итога целиком в окне (%s)" % [size.x, str(cr)])
		var cb: Array[Button] = []
		for k: String in card.buttons:
			cb.append(card.buttons[k])
		var cbad := _overlaps(cb, vs)
		ok(cbad.is_empty(), "%d: кнопки карточки не наезжают: %s" % [size.x, ", ".join(cbad)])
		await _shot("quick_card_%d" % size.x)
		# «Скопировать» — выжимка в буфер обмена; откат «всухую» — буфер прежний
		DisplayServer.clipboard_set("пусто")
		card.dry = true
		await hooks.click(card.buttons["copy"].get_global_rect().get_center())
		ok(DisplayServer.clipboard_get() == "пусто", "%d: откат «всухую»: буфер не тронут — проверка различает" % size.x)
		card.dry = false
		await hooks.click(card.buttons["copy"].get_global_rect().get_center())
		var got := DisplayServer.clipboard_get()
		ok(got == p.brief and got.contains("Итог:"), "%d: «Скопировать» положил в буфер выжимку отчёта (%d знаков)" % [size.x, got.length()])
		await _done(main)
