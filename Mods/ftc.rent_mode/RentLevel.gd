extends "res://TscnAndGd/Main/Level/NewLevel.gd"

func _enter_tree():
	if not filename.ends_with("/ftc.rent_mode.tutorial.tscn"):
		return
	# Replace the layout before children's ready/onready. The cloned ordinary
	# level keeps the composed native/furniture/talent lifecycle and save hooks.
	var layout = preload("res://ftc_mods/ftc.rent_mode/Maps/TutorialShop.tscn").instance()
	for child in layout.get_children():
		var old = get_node_or_null(NodePath(child.name))
		if old != null:
			remove_child(old)
			old.free()
		layout.remove_child(child)
		add_child(child)
	layout.free()

func _LoadGame():
	var rent = get_node("/root/RentMode")
	if rent.authority() and rent.seed_room:
		# Capture the native basic machines, shelves and counters before _LoadGame.
		_dev_save()
		_item_save()
		rent.seed_room = false
		GameLogic.new_bool = false
		GameLogic.Save.levelData["cur_Menu"] = GameLogic.cur_Menu.duplicate()
		rent.state.seed_pending = false
		rent._store_state()
		rent.coop.notify("layout", {"level": GameLogic.Save.levelData})
	_tutorial_repair_saved_layout()
	._LoadGame()
	rent.room_loaded()
	if filename.ends_with("/ftc.rent_mode.tutorial.tscn"):
		call_deferred("_tutorial_navigation_ready")

func _tutorial_repair_saved_layout():
	if not filename.ends_with("/ftc.rent_mode.tutorial.tscn"):
		return
	# Only repair the old shipped overlap; never reset a customized layout or
	# replace a machine's contents/upgrades. The native loader restores the rest.
	var devices = GameLogic.Save.levelData.get("Devices", [])
	for record in devices:
		if typeof(record) != TYPE_DICTIONARY or record.get("TSCN", "") != "FreezerBig" or record.get("pos") != Vector2(850, 525):
			continue
		var overlap = false
		var free = true
		for other in devices:
			if other == record or typeof(other) != TYPE_DICTIONARY:
				continue
			var position = other.get("pos", Vector2(-10000, -10000))
			overlap = overlap or position == Vector2(750, 525)
			free = free and not position in [Vector2(850, 525), Vector2(950, 525), Vector2(1050, 525)]
		if overlap and free:
			record.pos = Vector2(950, 525)

func _tutorial_navigation_ready():
	# The layout is installed during enter_tree and equipment is recreated by
	# _LoadGame. Wait for Physics2D to register both before testing wall edges.
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	if not is_inside_tree() or get_tree().current_scene != self or GameLogic.GameUI.Is_Open:
		return
	var graph = GameLogic.Astar
	graph.call_Path2D_init()
	graph.AStar_NPC_Wait.clear()
	graph.call_TMap_init(TMap_Floor)
	graph.call_TMap_init_NPC(TMap_NPCFloor)
	graph.call_TMap_Street_init(TMap_StreetMain, TMap_Street)
	graph.connect_init()
	_tutorial_order_points(Ysort_Dev)
	if is_instance_valid(GameLogic.Staff.OrderTab_OBJ):
		GameLogic.Staff.call_OrderTab_init(GameLogic.Staff.OrderTab_OBJ)

func _tutorial_order_points(node):
	if node.has_method("call_OrderPoint"):
		node.call_OrderPoint()
	for child in node.get_children():
		_tutorial_order_points(child)

func _tutorial_refine_customer_graph():
	if not filename.ends_with("/ftc.rent_mode.tutorial.tscn"):
		return
	# Native NPC paths jitter by up to 25px and bodies have width. A centre-line
	# ray alone permits routes that clip the tutorial's walls and dining tables.
	var astar = GameLogic.Astar
	var graph = astar.AStar_NPC
	var space = get_world_2d().direct_space_state
	var circle = CircleShape2D.new()
	circle.radius = 44.0
	var query = Physics2DShapeQueryParameters.new()
	query.set_shape(circle)
	query.collision_layer = 128
	query.collide_with_areas = false
	for id in graph.get_points():
		var point = graph.get_point_position(id)
		query.transform = Transform2D(0, point)
		if not space.intersect_shape(query, 1).empty():
			graph.remove_point(id)
			astar._Point_NPC_Dir.erase(point)
			if astar.AStar_NPC_Wait.has_point(id):
				astar.AStar_NPC_Wait.remove_point(id)
	for first in graph.get_points():
		var start = graph.get_point_position(first)
		for last in graph.get_point_connections(first):
			if last < first:
				continue
			var end = graph.get_point_position(last)
			var direction = (end - start).normalized()
			var offset = Vector2(-direction.y, direction.x) * 44.0
			if not space.intersect_ray(start + offset, end + offset, [], 128).empty() or not space.intersect_ray(start - offset, end - offset, [], 128).empty():
				graph.disconnect_points(first, last)

func _LEVELSTAT_LOGIC(state):
	var rent = get_node("/root/RentMode")
	if state == 0 and not rent.authority() and rent.coop.waiting_layout:
		rent.coop.pending_level = weakref(self)
		return
	if state == 0 and rent.authority() and rent.seed_room:
		_dev_save()
		_item_save()
		rent.seed_room = false
		GameLogic.new_bool = false
		GameLogic.Save.levelData["cur_Menu"] = GameLogic.cur_Menu.duplicate()
		rent.state.seed_pending = false
		rent._store_state()
		rent.coop.notify("layout", {"level": GameLogic.Save.levelData})
	if state == 0 and not rent.authority() and rent.state.get("phase", "prep") in ["product", "reward"]:
		_Level_Init()
		get_tree().paused = true
		return
	if state == 0 and not rent.pending_reward and (rent.state.get("phase", "prep") == "product" or rent.product_due()):
		_Level_Init()
		get_tree().paused = true
		rent.call_deferred("resume_product")
		return
	if state == 0 and get_node("/root/RentMode").pending_reward:
		_Level_Init()
		get_tree().paused = true
		get_node("/root/RentMode").call_deferred("resume_reward")
		return
	._LEVELSTAT_LOGIC(state)

func TMap_AStarLogic():
	# New furniture positions require a fresh graph every morning.
	GameLogic.Astar.AStar_NPC_Wait.clear()
	GameLogic.Astar.call_clear()
	.TMap_AStarLogic()


