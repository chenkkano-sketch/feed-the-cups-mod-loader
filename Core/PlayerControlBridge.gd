extends "res://TscnAndGd/Main/Player/Control.gd"

func _control_logic(button, value, type):
	var api = get_node_or_null("/root/FtcModAPI")
	if api != null and api.consume_control(playerNode, button, value, type):
		return
	._control_logic(button, value, type)

func call_velocity():
	.call_velocity()
	var api = get_node_or_null("/root/FtcModAPI")
	if api != null:
		velocity *= api.movement_factor(playerNode)
