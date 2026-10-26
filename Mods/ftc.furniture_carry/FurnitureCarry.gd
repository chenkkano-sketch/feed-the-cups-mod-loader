extends Reference

const ROOT_TYPES = ["Trashbin", "Shelf", "WorkBench", "WorkBench_Immovable"]
var owner
var enabled = false
var held = null
var player = null
var original_parent = null
var original_transform = Transform2D()
var original_player_pos = Vector2.ZERO
var original_z_index = 0
var original_z_relative = true
var collision_states = []
var level = null
var original_slots = {}
var npc_cells = {}
var guide = null
var pressed = false
var attached_visuals = []

func _init(mode):
	owner = mode

func capture_slots(room):
	if level != room:
		level = room
		original_slots.clear()
		npc_cells.clear()
		attached_visuals.clear()
		var npc_floor = room.get_node("MapNode/NPCFloor")
		for cell in npc_floor.get_used_cells():
			npc_cells[cell] = npc_floor.get_cellv(cell)
		# Scene-owned fittings and floor signs belong to their complete stations.
		for binding in [["YSort/Decorate/Decorate_Clean", "WaterTank"], ["YSort/Other/Tabletext_order", "OrderTab"]]:
			var fittings = room.get_node_or_null(binding[0])
			if fittings == null:
				continue
			for fixture in room.get_node("YSort/Devices").get_children():
				if contains_type(fixture, binding[1]):
					attached_visuals.append([fittings, fittings.global_position - fixture.global_position, binding[1], fittings.get_parent()])
					break
		enabled = false
		held = null
	# Keep scene fittings alive if the native loader replaces devices in-place.
	for record in attached_visuals:
		var fitting = record[0]
		var decor = record[3]
		if is_instance_valid(fitting) and fitting.get_parent() != decor:
			var world_pos = fitting.global_position
			fitting.get_parent().remove_child(fitting)
			decor.add_child(fitting)
			fitting.global_position = world_pos
	for object in room.get_node("YSort/Devices").get_children():
		if object is Node2D:
			original_slots[cell_at(object.position)] = object.position

func attach_visuals():
	# Rebind scene-owned fittings after native saved devices are reconstructed.
	# Native device saves retain equipment; scene fittings are rebuilt each load.
	for record in attached_visuals:
		if not is_instance_valid(record[0]):
			continue
		for fixture in level.get_node("YSort/Devices").get_children():
			if contains_type(fixture, record[2]):
				var fitting = record[0]
				if fitting.get_parent() != fixture:
					fitting.get_parent().remove_child(fitting)
					fixture.add_child(fitting)
				fitting.position = record[1]
				break

func set_enabled(value):
	if not value:
		cancel()
		enabled = false
		pressed = false
		if is_instance_valid(guide):
			guide.queue_free()
		if owner.is_run() and owner.preparing and not owner.get_tree().paused:
			owner._save_now()
		return true
	if not owner.is_preparing() or owner.get_tree().paused:
		owner._message("只能在开店前、非暂停状态进入搬运模式。")
		return false
	player = GameLogic.player_1P
	if not is_instance_valid(player) or player.Con.IsHold:
		owner._message("请先放下手上的物品。")
		return false
	enabled = true
	pressed = false
	guide = load("res://ftc_mods/ftc.furniture_carry/LayoutGuide.gd").new()
	guide.z_index = -1
	guide.cells = level.get_node("MapNode/Floor").get_used_cells()
	for cell in original_slots:
		if not cell in guide.cells:
			guide.cells.append(cell)
	for cell in npc_cells:
		if not cell in guide.cells:
			guide.cells.append(cell)
	level.add_child(guide)
	owner._message("搬运模式：交互键拿起、放下或与面前家具交换。F2 退出；手持时会放到腾出的空位。点单机正面需顾客可达。")
	return true

func handle_control(actor, button, value):
	if not enabled or not owner.is_run() or not owner.can_control(actor):
		return false
	if button == "START":
		if is_instance_valid(held):
			cancel()
		return false
	if owner.get_tree().paused:
		return false
	if button == "A":
		if value == 0:
			pressed = false
		elif not pressed and actor.Con.CanControl and not actor.Con.IsPause:
			pressed = true
			if is_instance_valid(held):
				place(front_cell(actor))
			else:
				pick_from_player(actor)
		return true
	# Keep furniture out of native discard, consume, dismantle and skill actions.
	return button in ["B", "X", "Y", "L1", "L2", "L3", "R1", "R2", "R3", "BACK"]

func cell_at(pos):
	return Vector2(floor(pos.x / 100.0), floor(pos.y / 100.0))

func facing(actor):
	var direction = actor.FaceRay.global_transform.basis_xform(actor.FaceRay.cast_to).normalized()
	if abs(direction.x) > abs(direction.y):
		return Vector2(sign(direction.x), 0)
	return Vector2(0, sign(direction.y))

func front_cell(actor):
	return cell_at(actor.global_position + facing(actor) * 100)

func root_fixture(object):
	var devices = level.get_node("YSort/Devices")
	var node = object
	while is_instance_valid(node) and node.get_parent() != devices:
		node = node.get_parent()
	if is_instance_valid(node) and node.get_parent() == devices:
		return node
	return null

func movable(object):
	if not is_instance_valid(object):
		return false
	if object.get("SelfDev") in ["OrderTab", "CupHolder", "WaterTank", "MopPool", "CleanMachine"]:
		return true
	if not object.get("TypeStr") in ROOT_TYPES:
		return false
	if object.get("TypeStr") == "WorkBench_Immovable" and object.get("CanPutDev") == false:
		return false
	return true

func contains_type(object, type):
	if object.get("FuncType") == type or object.get("TypeStr") == type or object.get("SelfDev") == type:
		return true
	for child in object.get_children():
		if contains_type(child, type):
			return true
	return false

func candidate(object):
	var fixture = root_fixture(object)
	if not is_instance_valid(fixture):
		return null
	return fixture if movable(fixture) else null

func pick_from_player(actor):
	var object = candidate(actor.cur_RayObj) if is_instance_valid(actor.cur_RayObj) else null
	if object == null:
		# Collision-free original counters can still be targeted from their front.
		for fixture in level.get_node("YSort/Devices").get_children():
			if cell_at(fixture.position) == front_cell(actor):
				object = candidate(fixture)
				break
	if object == null:
		owner._message("面向垃圾桶、货架、桌子、点单机或出杯机再交互；固定出餐台和场景装饰不可搬运。")
		return false
	return pick(actor, object)

func pick(actor, object, broadcast = true):
	# Never detach just the tabletop from a multi-part station.
	var fixture = root_fixture(object)
	if fixture != null:
		object = fixture
	if not enabled or not owner.preparing or owner.get_tree().paused or actor.Con.IsHold or not movable(object):
		return false
	if fixture == null or actor.global_position.distance_to(fixture.global_position) > 180:
		return false
	var object_path = object.get_path()
	player = actor
	held = object
	original_parent = object.get_parent()
	original_transform = object.transform
	original_player_pos = actor.global_position
	original_z_index = object.z_index
	original_z_relative = object.z_as_relative
	collision_states.clear()
	_capture_collisions(object)
	var old_speed = object.CarrySpeed
	object.CarrySpeed = 0.75
	GameLogic.Device.call_Pick_Logic(actor, object)
	# Native shelves use the pushing pose, whose weapon node is hidden.
	actor.Con.NeedPush = false
	actor.call_StatChange()
	object.CarrySpeed = old_speed
	object.scale = original_transform.get_scale() * 0.55
	# Furniture scenes use absolute draw order; show carried furniture above the player.
	object.z_as_relative = true
	object.z_index = 10
	owner._refresh_navigation(level)
	owner._message("已拿起。面向空地放下，或面向另一件家具交换；F2 可放到腾出的空位并退出。")
	var success = actor.Con.HoldObj == object and object.get_parent() == actor.WeaponNode
	if success and broadcast:
		owner.coop_picked(object_path, actor)
	return success

func _capture_collisions(object):
	if object is CollisionShape2D or object is CollisionPolygon2D:
		collision_states.append([object, "disabled", object.disabled])
		object.set_deferred("disabled", true)
	if object is CollisionObject2D:
		collision_states.append([object, "collision_layer", object.collision_layer])
		collision_states.append([object, "collision_mask", object.collision_mask])
		object.collision_layer = 0
		object.collision_mask = 0
	for child in object.get_children():
		_capture_collisions(child)

func fixture_at(cell):
	for object in level.get_node("YSort/Devices").get_children():
		if object is Node2D and object != held and cell_at(object.position) == cell:
			return object
	return null

func legal_floor(cell):
	return cell in original_slots or npc_cells.has(cell) or level.get_node("MapNode/Floor").get_cellv(cell) != -1

func apply_navigation():
	var map = level.get_node("MapNode/NPCFloor")
	map.clear()
	for cell in npc_cells:
		map.set_cellv(cell, npc_cells[cell])
	for object in level.get_node("YSort/Devices").get_children():
		if object is Node2D and npc_cells.has(cell_at(object.position)):
			map.set_cellv(cell_at(object.position), -1)

func customer_can_reach(cell, extra_blocked = null):
	if not npc_cells.has(cell):
		return false
	var available = npc_cells.duplicate()
	for path in ["MapNode/StreetMain", "MapNode/Street"]:
		for point in level.get_node(path).get_used_cells():
			available[point] = true
	for object in level.get_node("YSort/Devices").get_children():
		if object is Node2D:
			available.erase(cell_at(object.position))
	if extra_blocked != null:
		available.erase(extra_blocked)
	if not available.has(cell):
		return false
	var queue = []
	var visited = {}
	for point in level.get_node("MapNode/StreetMain").get_used_cells():
		if available.has(point):
			visited[point] = true
			queue.append(point)
	var index = 0
	var space = level.get_world_2d().direct_space_state
	while index < queue.size():
		var point = queue[index]
		index += 1
		if point == cell:
			return true
		for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var next = point + direction
			if not available.has(next) or visited.has(next):
				continue
			var ray = space.intersect_ray(point * 100 + Vector2(50, 50), next * 100 + Vector2(50, 50), [player] if is_instance_valid(player) else [])
			if ray.empty():
				visited[next] = true
				queue.append(next)
	return false

func validate_place(cell, replacing = null):
	if not is_instance_valid(held):
		return "手上没有家具。"
	if not legal_floor(cell):
		return "只能放在店内地板或家具原有位置。"
	if fixture_at(cell) != replacing:
		return "这个位置已有家具。"
	if cell_at(player.global_position) == cell:
		return "请放在人物前方，不要放在脚下。"
	if contains_type(held, "OrderTab") and not customer_can_reach(cell + Vector2.DOWN):
		return "顾客无法到达这张桌子的正面，不能放置点单机。"
	if replacing == null and not cell in original_slots:
		var shape = RectangleShape2D.new()
		shape.extents = Vector2(35, 30)
		var query = Physics2DShapeQueryParameters.new()
		query.set_shape(shape)
		query.transform = Transform2D(0, cell * 100 + Vector2(50, 50))
		query.exclude = [player]
		query.collide_with_areas = false
		if not level.get_world_2d().direct_space_state.intersect_shape(query, 1).empty():
			return "这里有墙体或固定设施，不能放置。"
	for fixture in level.get_node("YSort/Devices").get_children():
		if fixture == replacing:
			continue
		if contains_type(fixture, "OrderTab") and not customer_can_reach(cell_at(fixture.position) + Vector2.DOWN, cell):
			return "这里会堵住顾客前往点单机的通道。"
	return ""

func place(cell):
	if not enabled or not owner.preparing or owner.get_tree().paused:
		return false
	var occupant = fixture_at(cell)
	if occupant != null:
		return swap(player, occupant)
	var error = validate_place(cell)
	if error != "":
		owner._message(error)
		return false
	var parent = level.get_node("YSort/Devices")
	var offset = original_transform.origin - cell_at(original_transform.origin) * 100
	var target = cell * 100 + offset
	var object = held
	_release(parent, target, false)
	owner.coop_released(target)
	if parent.name == "ObjNode":
		parent.get_parent().OnTableObj = object
	owner._refresh_order_points(object)
	owner._refresh_navigation(level)
	owner._message("已放下。可以继续走动和搬运，F2 退出搬运模式。")
	return true

func swap(actor, target, synchronized = false, placed_position = null, vacant_position = null):
	if not enabled or not owner.preparing or owner.get_tree().paused or not is_instance_valid(held) or not is_instance_valid(actor):
		return false
	var devices = level.get_node("YSort/Devices")
	if not is_instance_valid(target) or target.get_parent() != devices or not movable(target):
		if not synchronized:
			owner._message("面前的设施不可搬运，不能交换。")
		return false
	var cell = cell_at(target.position)
	if not synchronized:
		if actor.global_position.distance_to(target.global_position) > 180:
			return false
		var error = validate_place(cell, target)
		if error != "":
			owner._message(error)
			return false
	var old_object = held
	var old_parent = original_parent
	var old_transform = original_transform
	var old_player_pos = original_player_pos
	var target_path = str(target.get_path())
	var target_start = target.position
	var held_offset = original_transform.origin - cell_at(original_transform.origin) * 100
	var target_offset = target.position - cell * 100
	var placement = placed_position if placed_position is Vector2 else cell * 100 + held_offset
	var vacancy = vacant_position if vacant_position is Vector2 else cell_at(old_transform.origin) * 100 + target_offset
	_release(devices, placement, false)
	if not pick(actor, target, false):
		# Restore the carried object if the native pickup unexpectedly refuses.
		if held == target and target.get_parent() == actor.WeaponNode:
			_release(devices, target_start, false)
		if not actor.Con.IsHold and pick(actor, old_object, false):
			original_parent = old_parent
			original_transform = old_transform
			original_player_pos = old_player_pos
		if not synchronized:
			owner._message("交换未完成，请再试一次。")
		return false
	original_parent = old_parent
	var fallback_transform = original_transform
	fallback_transform.origin = vacancy
	original_transform = fallback_transform
	original_player_pos = old_player_pos
	owner._refresh_order_points(old_object)
	owner._refresh_navigation(level)
	if not synchronized:
		owner.coop_swapped(target_path, actor, placement, vacancy)
		owner._message("已交换。当前手持面前的家具；再次交互可继续交换或放下。")
	return true

func _release(parent, pos, restoring):
	var object = held
	object.get_parent().remove_child(object)
	parent.add_child(object)
	object.transform = original_transform
	object.position = pos
	object.z_index = original_z_index
	object.z_as_relative = original_z_relative
	object.Holding = false
	object.Holder = null
	for record in collision_states:
		if is_instance_valid(record[0]):
			record[0].set_deferred(record[1], record[2])
	if is_instance_valid(player):
		player.Stat.call_carry_off()
		# The native helper returns early for lobby guests. Keep their mirrored
		# hold state in sync before the next half of an atomic swap.
		player.Con.IsHold = false
		player.Con.NeedPush = false
		player.Con.HoldInsId = 0
		player.Con.HoldObj = null
		player.call_StatChange()
	if restoring and parent.name == "ObjNode":
		parent.get_parent().OnTableObj = object
	held = null
	collision_states.clear()

func cancel():
	if not is_instance_valid(held) or not is_instance_valid(original_parent):
		held = null
		return
	var object = held
	if is_instance_valid(player) and cell_at(player.global_position) == cell_at(original_parent.to_global(original_transform.origin)):
		player.global_position = original_player_pos
	_release(original_parent, original_transform.origin, true)
	owner.coop_released(original_transform.origin)
	owner._refresh_order_points(object)
	owner._refresh_navigation(level)
