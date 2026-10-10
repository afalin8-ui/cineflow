extends Node
## «Поле»: щелчки, не пойманные интерфейсом, — в _unhandled_input. Начатый
## на поле жест дослушивается в _input (раньше интерфейса), где бы он ни
## кончился (ловушка 50). Флажок listen_in_input=false — откат.
var listen_in_input := true
var gesture := ""          # "", "maybe-rotate", "rotate"
var log: Array = []

func _ready() -> void: process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		log.append(["unhandled", ev.button_index, ev.pressed, ev.position])
		if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed: gesture = "maybe-rotate"
		elif ev.button_index == MOUSE_BUTTON_RIGHT and not ev.pressed and gesture != "": _end(ev)
	elif ev is InputEventMouseMotion and gesture != "":
		gesture = "rotate"; log.append(["unhandled_motion", ev.position])
	if ev is InputEventKey and ev.pressed:
		log.append(["key", ev.physical_keycode, ev.keycode, ev.echo,
			InputMap.event_is_action(ev, "cmd_amove"), InputMap.event_is_action(ev, "cmd_amove_by_keycode")])

func _input(ev: InputEvent) -> void:
	if not listen_in_input or gesture == "": return
	if ev is InputEventMouseMotion: gesture = "rotate"
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and not ev.pressed:
		_end(ev); get_viewport().set_input_as_handled()

func _end(ev) -> void:
	log.append(["gesture_end", gesture, ev.position]); gesture = ""
