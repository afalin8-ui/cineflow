extends SceneTree
func _init():
	var B = load("res://sim/battle.gd")
	print("loaded: ", B != null)
	quit()
