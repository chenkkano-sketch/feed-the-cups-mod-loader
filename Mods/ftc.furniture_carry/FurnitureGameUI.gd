extends "res://TscnAndGd/UI/InGame/GameUI.gd"

func _on_Timer_timeout():
	var mode = get_node_or_null("/root/FurnitureCarryMode")
	if mode != null and mode.is_preparing():
		return
	._on_Timer_timeout()

func call_Open():
	var mode = get_node_or_null("/root/FurnitureCarryMode")
	if mode != null and not mode.can_open():
		return
	.call_Open()
