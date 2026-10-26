extends "res://TscnAndGd/Logics/GameLogic/AStarLogic.gd"

func connect_init():
	# Native graph construction rays include dynamic characters. An employee
	# standing in an aisle must not permanently cut that edge after F2 layout.
	# No physics frame runs between these synchronous calls.
	var bodies = []
	for actor in get_tree().get_nodes_in_group("FTC_TALENT_STAFF"):
		if is_instance_valid(actor) and actor is PhysicsBody2D and actor.is_inside_tree():
			bodies.append([actor, actor.collision_layer])
			actor.collision_layer = 0
	.connect_init()
	for record in bodies:
		if is_instance_valid(record[0]) and record[0].is_inside_tree():
			record[0].collision_layer = record[1]
