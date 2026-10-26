extends "res://TscnAndGd/Main/Level/NewLevel.gd"

func _LoadGame():
	var mode = get_node_or_null("/root/FurnitureCarryMode")
	if mode != null:
		mode.carry.cancel()
		mode.carry.capture_slots(self)
	._LoadGame()
	if mode != null:
		mode.carry.attach_visuals()

func TMap_AStarLogic():
	var mode = get_node_or_null("/root/FurnitureCarryMode")
	if mode != null and GameLogic.LoadingUI.IsLevel:
		GameLogic.Astar.AStar_NPC_Wait.clear()
		GameLogic.Astar.call_clear()
		if mode.carry.level == self:
			mode.carry.apply_navigation()
	.TMap_AStarLogic()

func call_level_save():
	var mode = get_node_or_null("/root/FurnitureCarryMode")
	if mode != null and mode.carry.level == self:
		mode.carry.cancel()
	.call_level_save()
