extends "res://TscnAndGd/Logics/GameLogic/AStarLogic.gd"

func connect_init():
	.connect_init()
	var level = get_tree().root.get_node_or_null("Level")
	if is_instance_valid(level) and level.has_method("_tutorial_refine_customer_graph"):
		level._tutorial_refine_customer_graph()
