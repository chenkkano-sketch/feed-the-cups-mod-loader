extends "res://TscnAndGd/Objects/Home/Wardrobe.gd"

func _enter_tree():
	# Hatstand reuses Wardrobe's script but only ships the normal A button.
	# Its native _ready only hides these absent debug nodes. Supply invisible,
	# inert placeholders first, then leave native initialization to run once.
	var buttons = get_node_or_null("Button")
	if buttons == null:
		return
	for id in ["1", "2", "3"]:
		if not buttons.has_node(id):
			var placeholder = Control.new()
			placeholder.name = id
			placeholder.visible = false
			placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			placeholder.focus_mode = Control.FOCUS_NONE
			buttons.add_child(placeholder)
