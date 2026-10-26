extends Reference

# Inventory views contain existing objects only. A source always retains its real
# shelf layer or delivery box so native take/put updates save data and capacity.
const SHELF_BUTTONS = [0, 1, 3, 2]

func valid(node):
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()

func prop(node, key, fallback = null):
	if not valid(node):
		return fallback
	var value = node.get(key)
	return fallback if value == null else value

func usable(item):
	return valid(item) and not prop(item, "Used", false) and not prop(item, "Freshless_bool", false) and not prop(item, "IsBroken", false)

func kind(node):
	return str(prop(node, "FuncType", ""))

func type_name(node):
	return str(prop(node, "TypeStr", ""))

func is_shelf(node):
	return kind(node) in ["Shelf", "Freezer"] and node.has_method("call_PutOn") and node.has_method("call_pick")

func shelf_buttons(shelf):
	# The small native refrigerated shelf swaps the last two layer buttons.
	return [0, 1, 2, 3] if type_name(shelf) == "Shelf_M_Freezer" else SHELF_BUTTONS

func empty_package(box):
	# Equipment crates use BoxWood and a different assembly protocol. Only the
	# native paper/foam delivery-box family may enter this destructive action.
	if not valid(box) or kind(box) != "Box" or not box.has_method("call_PickItem") or not box.has_method("call_ObjTurnTrashbag"):
		return false
	var entries = prop(box, "ItemOBJ_Array", null)
	if not entries is Array or not entries.empty() or prop(box, "HasItem", false):
		return false
	var serialized = prop(box, "_ItemNameDic", {})
	if not serialized is Dictionary or not serialized.empty():
		return false
	var contents = box.get_node_or_null("TexNode/ItemNode")
	if contents != null:
		for child in contents.get_children():
			if valid(child) and child.get("TypeStr") != null:
				return false
	return true

func exhausted_packaging(item):
	if not valid(item) or not prop(item, "IsItem", false):
		return false
	var function = kind(item)
	# A cup bundle also has Num; it is usable stock, never an empty wrapper.
	if function in ["DrinkCup_Group", "DrinkCup", "SuperCup", "SodaCan", "BeerCup", "Box", "BoxWood", "Trashbag", "Mop"]:
		return false
	if function in ["Bottle", "Hang", "Top", "Pop"]:
		var liquid = item.get("Liquid_Count")
		return liquid != null and int(liquid) <= 0
	if function == "Can":
		var portions = item.get("Num")
		return portions != null and int(portions) <= 0
	if function in ["TeaLeaf", "Powder", "CoffeeBean", "Sugar", "Choco", "FreeSugar", "Pot", "Cooker", "TeaBag", "Cake"]:
		if prop(item, "Used", false):
			return true
		return function == "TeaLeaf" and prop(item, "IsOpen", false) and int(prop(item, "CurGram", 1)) <= 0
	return false

func cup_group_size(item):
	if not valid(item) or kind(item) != "DrinkCup_Group" or int(prop(item, "Num", 0)) < 10:
		return ""
	for size in ["S", "M", "L"]:
		if type_name(item) == "DrinkCup_Group_" + size:
			return size
	return ""

func cup_low(holder, size):
	if not valid(holder) or kind(holder) != "CupHolder" or not size in ["S", "M", "L"]:
		return false
	var count = int(prop(holder, size + "_Num", -1))
	return count >= 0 and count <= 4 and count + 10 <= int(prop(holder, "Cup_Max", 0))

func disposal_space(bin, amount):
	if not valid(bin) or kind(bin) != "Trashbin" or bin.get_parent().name == "Weapon_note":
		return false
	var maximum = float(prop(bin, "Trash_Max", 0))
	var count = float(prop(bin, "Trash_Count", 0))
	return amount >= 0 and maximum >= amount and maximum - count >= amount

func indoor_bin(bin):
	# This is the same discriminator used by native Trashbin._ready/load.
	# DeviceID is an instance counter, never a bin category or location.
	return valid(bin) and kind(bin) == "Trashbin" and str(bin.editor_description) == "Dev"

func outdoor_bin(bin):
	return valid(bin) and kind(bin) == "Trashbin" and not indoor_bin(bin)

func disposal_amount(item):
	if not valid(item):
		return 0.0
	return float(item.return_DropCount()) if item.has_method("return_DropCount") else float(prop(item, "Weight", 1))

func sources(manager):
	var result = []
	var seen = {}
	for node in manager.devices() + manager.items():
		if not valid(node):
			continue
		if is_shelf(node):
			for layer in range(1, 5):
				var entries = prop(node, "layer%d_Array" % layer, [])
				if entries is Array and not entries.empty():
					_add_source(result, seen, entries.back(), node, shelf_buttons(node)[layer - 1], layer)
		elif kind(node) == "Box" and prop(node, "ItemOBJ_Array", []) is Array:
			var entries = prop(node, "ItemOBJ_Array", [])
			if not entries.empty():
				_add_source(result, seen, entries.back(), node, 2, 0)
			elif empty_package(node) and node.get_parent().name in ["Items", "Devices", "ObjNode", "SavedNode", "Outdoor", "Update", "UpdateItems"]:
				_add_source(result, seen, node, node, 0, 0)
		elif prop(node, "CanMove", false) or prop(node, "IsItem", false):
			# Objects inside a native shelf/box are represented above, never picked
			# directly; that would leave stale entries in the container inventory.
			var parent = node.get_parent()
			if parent.name in ["Items", "Devices", "ObjNode", "SavedNode"]:
				_add_source(result, seen, node, node, 0, 0)
	return result

func _add_source(result, seen, item, target, button, layer):
	if not valid(item) or seen.has(item.get_instance_id()):
		return
	seen[item.get_instance_id()] = true
	result.append({"item": item, "target": target, "button": button, "layer": layer})

func shelf_slot(manager, item, prefer_existing = true, exclude = null, worker = null):
	if not valid(item) or (kind(item) == "Box" and (prop(item, "IsTrash", false) or empty_package(item))) or exhausted_packaging(item):
		return {}
	var wanted = type_name(item)
	var weight = max(0.01, float(prop(item, "Weight", 1)))
	var empty = {}
	for shelf in manager.devices():
		if not is_shelf(shelf) or shelf == exclude:
			continue
		if worker != null and (manager.locks.get(manager._resource_key(shelf), str(worker.profile.id)) != str(worker.profile.id) or worker.navigation.approach(shelf, worker.body.global_position) == null):
			continue
		for layer in range(1, 5):
			var entries = prop(shelf, "layer%d_Array" % layer, [])
			if not entries is Array or entries.size() >= int(8.0 / weight):
				continue
			var current_type = prop(shelf, "Layer%d_Item" % layer, "")
			var row = {"target": shelf, "button": shelf_buttons(shelf)[layer - 1], "layer": layer}
			if str(current_type) == wanted:
				return row
			if entries.empty() and empty.empty():
				empty = row
	return empty

func empty_bench(manager):
	for node in manager.devices():
		if type_name(node) == "WorkBench" and not valid(prop(node, "OnTableObj")):
			return node
		if type_name(node) == "WorkBench_Immovable" and prop(node, "CanPutDev", false) and not valid(prop(node, "OnTableObj")):
			return node
	return null

func available(manager, worker, node):
	return valid(node) and manager.locks.get(manager._resource_key(node), str(worker.profile.id)) == str(worker.profile.id) and (node == worker.held() or worker.navigation.approach(node, worker.body.global_position) != null)

func ground_clear(manager, worker, box, point):
	var floor_map = worker.level.get_node_or_null("MapNode/Floor")
	if floor_map == null or floor_map.get_cellv(floor_map.world_to_map(floor_map.to_local(point))) < 0:
		return false
	for item in manager.items() + manager.devices():
		if not valid(item) or item == box or item == worker.body or not item is Node2D or item.get_parent().name == "Weapon_note":
			continue
		if item.global_position.distance_to(point) < 75.0:
			return false
	var shape = RectangleShape2D.new()
	shape.extents = Vector2(36, 28)
	var query = Physics2DShapeQueryParameters.new()
	query.set_shape(shape)
	query.transform = Transform2D(0.0, point)
	query.collide_with_areas = false
	var excluded = []
	var pending = [worker.level]
	while not pending.empty():
		var node = pending.pop_back()
		if node is PhysicsBody2D and (not node is StaticBody2D or node == box or box.is_a_parent_of(node)):
			excluded.append(node.get_rid())
		pending += node.get_children()
	query.exclude = excluded
	return worker.level.get_world_2d().direct_space_state.intersect_shape(query, 1).empty()

func package_ground(manager, worker, box):
	var shelves = []
	var entries = prop(box, "ItemOBJ_Array", [])
	if entries is Array and not entries.empty():
		var preferred = shelf_slot(manager, entries.back(), true, null, worker)
		if not preferred.empty():
			shelves.append(preferred.target)
	for node in manager.devices():
		if is_shelf(node) and not node in shelves and available(manager, worker, node):
			shelves.append(node)
	var floor_map = worker.level.get_node_or_null("MapNode/Floor")
	if floor_map == null:
		return {}
	for shelf in shelves:
		# Prefer corner spaces beside the rack, leaving its front operation tile.
		for offset in [Vector2(-100, 100), Vector2(100, 100), Vector2(-100, -100), Vector2(100, -100), Vector2(-100, 0), Vector2(100, 0), Vector2(0, 100), Vector2(0, -100)]:
			var cell = floor_map.world_to_map(floor_map.to_local(shelf.global_position + offset))
			var point = floor_map.to_global(floor_map.map_to_world(cell) + floor_map.cell_size * 0.5)
			var key = "stock.floor:%d:%d" % [int(point.x), int(point.y)]
			if manager.locks.get(key, str(worker.profile.id)) != str(worker.profile.id) or not ground_clear(manager, worker, box, point):
				continue
			for direction in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
				var stand = worker.navigation.nearest(point + direction * 100.0, 45.0)
				if stand == null or stand.distance_to(point) < 70.0 or stand.distance_to(point) > 150.0:
					continue
				if not worker.navigation.path(worker.body.global_position, stand).empty():
					return {"point": point, "stand": stand, "key": key}
	return {}

func take_steps(source):
	var result = []
	if source.empty():
		return result
	var target = source.target
	if kind(target) == "Box" and target != source.item and not prop(target, "IsOpen", false):
		result.append({"kind": "interact", "target": target, "button": 2, "expect": "open", "timeout": 8.0})
	result.append({"kind": "interact", "target": target, "button": int(source.button), "expect": "held", "item": source.item})
	return result

func find_special(manager, method):
	var level = manager.get_tree().root.get_node_or_null("Level")
	if not valid(level):
		return []
	var result = []
	var pending = [level]
	while not pending.empty():
		var node = pending.pop_back()
		if node.has_method(method):
			result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result
