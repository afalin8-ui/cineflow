# Ввод без окна (ярус ui): помощники hooks.gd доходят до интерфейса, окно-заглушка
# отвечает на F3. Архитектура, 8.3. Размер окна — tests/test_ui_window.gd.
extends "res://tests/case.gd"

const MainScene := preload("res://main.tscn")
const FpsCounter := preload("res://ui/fps_counter.gd")


func test_click_reaches_button() -> void:
	await hooks.set_window_size(Vector2i(1920, 1080))
	var b := Button.new()
	b.text = "проба"
	b.position = Vector2(300, 200)
	b.size = Vector2(200, 60)
	tree.root.add_child(b)
	var presses := [0]
	b.pressed.connect(func() -> void: presses[0] += 1)
	await hooks.frames(1)
	var center := b.get_global_rect().get_center()
	var under := await hooks.hovered_at(center)
	ok(under == b, "под центром кнопки — она сама (%s)" % [under])
	await hooks.click(center)
	eq(presses[0], 1, "щелчок в центр нажал кнопку один раз")
	await hooks.click(center + Vector2(0, 200))
	eq(presses[0], 1, "щелчок мимо кнопку не нажал (откат проверки)")
	b.queue_free()
	await hooks.frames(1)


func test_f3_toggles_counter() -> void:
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	await hooks.frames(2)
	var fps: FpsCounter = null
	for c in main.get_children():
		if c is FpsCounter:
			fps = c
	if not ok(fps != null, "счётчик кадров заведён"):
		main.queue_free()
		return
	ok(not fps.panel.visible, "в покое счётчик скрыт")
	await hooks.key(KEY_F3)
	ok(fps.panel.visible, "F3 открыл счётчик")
	await hooks.key(KEY_F3, KEY_NONE, true)
	ok(fps.panel.visible, "повтор F3 (echo) — не нажатие: счётчик не закрылся")
	await hooks.key(KEY_F3)
	ok(not fps.panel.visible, "F3 закрыл счётчик")
	ok(fps.summary().contains("вызовов отрисовки за кадр"), "в сводке есть вызовы отрисовки")
	main.queue_free()
	await hooks.frames(1)
