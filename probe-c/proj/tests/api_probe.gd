extends SceneTree
func _init():
	for c in ["Viewport", "Control", "Input", "DisplayServer", "RenderingServer"]:
		var names := []
		for m in ClassDB.class_get_method_list(c, true):
			var n: String = m.name
			if n.findn("gui") >= 0 or n.findn("hover") >= 0 or n.findn("find_control") >= 0 or n.findn("parse_input") >= 0 or n.findn("push_input") >= 0 or n.findn("rendering_info") >= 0 or n.findn("warp") >= 0:
				names.append(n)
		print(c, ": ", names)
	print("Label default mouse_filter: ", Label.new().mouse_filter, "  Panel: ", Panel.new().mouse_filter, "  PanelContainer: ", PanelContainer.new().mouse_filter, "  HBoxContainer: ", HBoxContainer.new().mouse_filter, "  Control: ", Control.new().mouse_filter, " (STOP=0 PASS=1 IGNORE=2)")
	print("Button focus_mode default: ", Button.new().focus_mode, " (NONE=0 CLICK=1 ALL=2)")
	quit()
