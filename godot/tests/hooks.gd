# tests/hooks.gd — ввод настоящими событиями и вопросы «что под точкой»
# (архитектура, 8.3). Работает и без окна (--headless): проверено судьёй.
# ЛОВУШКИ:
# - размер окна задавать ПОСЛЕ первого кадра: в _initialize root.size 100×100,
#   а заданное там после первого кадра откатывается к 64×64; --resolution не помогает.
#   set_window_size сам дожидается кадра — его можно звать хоть из _initialize
#   (канарейка tests/probe_window.gd, проверка tests/test_ui_window.gd);
# - Input.use_accumulated_input сливает движения мыши одного кадра — для протяжки
#   слать по одному движению на кадр;
# - клавиши — по physical_keycode (русская раскладка: keycode 1088 «р» на месте H).
extends RefCounted

var tree: SceneTree


func _init(t: SceneTree) -> void:
	tree = t


func frames(n: int = 1) -> void:
	for i in n:
		await tree.process_frame


## Размер окна — после первого кадра (первый await НЕ убирать: без него размер,
## заданный до первого кадра, откатывается к 64×64), и вернуть, что удержалось.
func set_window_size(size: Vector2i) -> Vector2i:
	await tree.process_frame
	tree.root.size = size
	await tree.process_frame
	await tree.process_frame
	return tree.root.size


func move(pos: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	Input.parse_input_event(mv)
	await tree.process_frame


func click(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await move(pos)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(ev)
	await tree.process_frame                 # события разбираются в следующем кадре
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	up.button_mask = 0
	Input.parse_input_event(up)
	await tree.process_frame
	await tree.process_frame


## Кто под точкой экрана — аналог elementFromPoint.
func hovered_at(pos: Vector2) -> Control:
	await move(pos)
	return tree.root.gui_get_hovered_control()


## Нажать и отпустить клавишу по месту. keycode — буква раскладки (по умолчанию та же).
func key(physical: Key, keycode: Key = KEY_NONE, echo: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.keycode = keycode if keycode != KEY_NONE else physical
	ev.pressed = true
	ev.echo = echo
	Input.parse_input_event(ev)
	await tree.process_frame
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	up.echo = false
	Input.parse_input_event(up)
	await tree.process_frame
