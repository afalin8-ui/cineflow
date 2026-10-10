# Ввод без окна (ярус ui): помощники hooks.gd доходят до интерфейса, окно-заглушка
# отвечает на F3, худший кадр счётчика — по настоящему времени. Архитектура, 8.3.
# Размер окна — tests/test_ui_window.gd.
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


## Слушает delta каждого кадра — чтобы увидеть, что Godot его урезает.
class DeltaProbe extends Node:
	var max_delta_ms := 0.0

	func _process(delta: float) -> void:
		max_delta_ms = maxf(max_delta_ms, delta * 1000.0)


## Худший кадр за 0,5 с — по настоящему времени (замечание к G0b): Godot урезает
## delta до 8 шагов физики (≈133 мс), и счётчик по delta показал бы рывок в 300 мс
## как 133. Откат «по delta» краснеет — канарейка ниже показывает, что delta этого
## кадра и правда урезан, то есть проверка различает два способа счёта.
func test_f3_worst_frame_real_time() -> void:
	var fps := FpsCounter.new()
	tree.root.add_child(fps)
	var probe := DeltaProbe.new()
	tree.root.add_child(probe)
	await hooks.frames(5)
	ok(fps.worst_ms() < 250.0, "в покое худший кадр короче 250 мс (%.1f)" % fps.worst_ms())
	probe.max_delta_ms = 0.0
	OS.delay_msec(300)              # кадр с паузой 300 мс — как сборка шейдера посреди игры
	await hooks.frames(2)
	var w := fps.worst_ms()
	ok(w >= 290.0, "кадр с паузой 300 мс: худший кадр %.1f мс (ждали не меньше 290)" % w)
	var line := fps.summary().get_slice("\n", 1)
	ok(line.begins_with("худший кадр за 0,5 с: 3"), "в строке счётчика — те же 300 с лишним мс: «%s»" % line)
	ok(probe.max_delta_ms < 290.0, "delta кадра с паузой урезан до %.1f мс — счёт по delta показал бы его, а не 300" % probe.max_delta_ms)
	note("кадр с паузой 300 мс: счётчик %.1f мс, delta %.1f мс" % [w, probe.max_delta_ms])
	# окно — 0,5 с настоящего времени: через 0,7 с рывок из окна ушёл
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 700:
		await hooks.frames(1)
	ok(fps.worst_ms() < 250.0, "через 0,7 с рывок ушёл из окна 0,5 с (%.1f мс)" % fps.worst_ms())
	fps.queue_free()
	probe.queue_free()
	await hooks.frames(1)
