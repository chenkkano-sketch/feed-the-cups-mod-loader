extends Reference

var manager
var worker
var stock = preload("res://ftc_mods/ftc.talent_market/Helpers/SupplyStock.gd").new()
var tasks
var status = "等待整理与维护任务"
var scan_in = 0.0
var restock_wait_reason = ""

func _init(owner, actor):
	manager = owner
	worker = actor
	tasks = preload("res://ftc_mods/ftc.talent_market/Helpers/SupplyTasks.gd").new(owner, actor)

func tick(delta):
	if not manager.active():
		return
	if tasks.busy:
		tasks.tick(delta)
		status = tasks.status
		return
	scan_in -= delta
	if scan_in > 0:
		return
	scan_in = 0.8
	var held = worker.held()
	if stock.valid(held):
		_recover_held(held)
		return
	if (worker.has_skill("repair") and (_repair_power() or _repair_devices())) or (worker.has_skill("restock_cups") and _restock_cups()) or (worker.has_skill("trash_basic") and (_collect_trash() or _collect_loose_bags())) or (worker.has_skill("clean") and (_clean_floor() or _clean_loose_trash())) or (worker.has_skill("trash_advanced") and (_clear_wrappers() or _clear_empty_packages())) or (worker.has_skill("stock_advanced") and _bring_package_inside()) or (worker.has_skill("stock_basic") and _stock_delivery()):
		status = tasks.status
	else:
		status = "等待可整理物资或维护任务"

func _submit(label, resources, steps, permission = ""):
	# Do not monopolize the queue with an inaccessible first package or shelf.
	# Closed storefronts and displaced floor deliveries are temporary: rescan
	# from the next object now and try them again after the layout/doors change.
	var visited = {}
	for step in steps:
		var target = step.get("target")
		if not stock.valid(target) or not target is Node2D or target == worker.held() or worker.body.is_a_parent_of(target):
			continue
		if visited.has(target.get_instance_id()):
			continue
		visited[target.get_instance_id()] = true
		if worker.navigation.approach(target, worker.body.global_position) == null:
			return false
	for step in steps:
		if permission != "":
			step["permission"] = permission
	return tasks.submit(label, resources, steps)

func _repair_power():
	if not worker.has_skill("repair"):
		return false
	if not manager.game.IsBlackOut:
		return false
	for node in stock.find_special(manager, "call_home_device"):
		if node.has_node("WarningNode") and stock.prop(node, "CanUse", false) and node.get_node("WarningNode").has_method("call_Fix_ElecBox"):
			if _submit("恢复供电", [node], [{"kind": "elec", "target": node, "timeout": 30.0}], "repair"):
				return true
	return false

func _repair_devices():
	for node in manager.devices():
		var warning = node.get_node_or_null("WarningNode")
		if not stock.valid(warning) or not stock.prop(warning, "NeedFix", false) or not warning.has_method("return_Fixing"):
			continue
		if _submit("修理故障设备", [node], [{"kind": "repair", "target": node, "timeout": 90.0}], "repair"):
			return true
	return false

func _outside_bin(amount = 0.0, source = null):
	var best = null
	var distance = INF
	for node in manager.devices():
		if node == source or not stock.outdoor_bin(node):
			continue
		if not stock.disposal_space(node, amount) or manager.locks.get(manager._resource_key(node), str(worker.profile.id)) != str(worker.profile.id):
			continue
		var approach = worker.navigation.approach(node, worker.body.global_position)
		if approach == null:
			continue
		var candidate_distance = worker.body.global_position.distance_squared_to(approach)
		if candidate_distance < distance:
			best = node
			distance = candidate_distance
	return best

func _bin_for_waste(amount):
	var inside = null
	var outside = null
	var inside_distance = INF
	var outside_distance = INF
	for node in manager.devices():
		if not stock.disposal_space(node, amount):
			continue
		# Choosing a reserved indoor bin would keep retrying that same bin and
		# hide an available outdoor alternative from every following package.
		var key = manager._resource_key(node)
		if manager.locks.has(key) and manager.locks[key] != str(worker.profile.id):
			continue
		var approach = worker.navigation.approach(node, worker.body.global_position)
		if approach == null:
			continue
		var distance = worker.body.global_position.distance_squared_to(approach)
		if stock.indoor_bin(node):
			if distance < inside_distance:
				inside = node
				inside_distance = distance
		elif distance < outside_distance:
			outside = node
			outside_distance = distance
	return inside if stock.valid(inside) else outside

func _restock_cups():
	restock_wait_reason = ""
	if not worker.has_skill("restock_cups"):
		return false
	# Empty holders take precedence over the native low-stock warning. A real
	# bundle contains ten cups, so a holder above four never needs a refill.
	var sources = stock.sources(manager)
	for empty_only in [true, false]:
		for holder in manager.devices():
			if stock.kind(holder) != "CupHolder":
				continue
			for size in ["S", "M", "L"]:
				if not stock.cup_low(holder, size) or (int(stock.prop(holder, size + "_Num", 0)) == 0) != empty_only:
					continue
				var found_group = false
				for source in sources:
					if stock.cup_group_size(source.item) != size:
						continue
					found_group = true
					if not worker.can_take_source(source):
						restock_wait_reason = "补杯等待：" + size + "号杯组尚未开箱"
						continue
					if worker.navigation.approach(source.target, worker.body.global_position) == null:
						restock_wait_reason = "补杯等待：" + size + "号杯组取用位置不可达"
						continue
					if worker.navigation.approach(holder, worker.body.global_position) == null:
						restock_wait_reason = "补杯等待：杯架操作位置不可达"
						continue
					var steps = stock.take_steps(source)
					steps.append({"kind": "restock_cups", "target": holder, "item": source.item, "size": size})
					if _submit("补充" + size + "号空杯架", [source.target, source.item, holder], steps, "restock_cups"):
						restock_wait_reason = ""
						return true
					restock_wait_reason = "补杯等待：杯组或杯架正被占用"
				if not found_group and restock_wait_reason == "":
					restock_wait_reason = "补杯等待：缺少可取用的" + size + "号杯组"
	return false

func _collect_trash(allow_partial = false):
	if not worker.has_skill("trash_basic"):
		return false
	for node in manager.devices():
		if not stock.indoor_bin(node) or int(stock.prop(node, "Trash_Count", 0)) < 1:
			continue
		if float(node.Trash_Count) < float(stock.prop(node, "Trash_Max", 1)) * 0.5 and not (allow_partial and worker.has_skill("trash_advanced")):
			continue
		var outside = _outside_bin(float(node.Trash_Count), node)
		if not stock.valid(outside):
			continue
		if _submit("打包并运出垃圾", [node, outside], [
			{"target": node, "button": 2, "expect": "held", "label": "打包室内垃圾"},
			{"target": outside, "button": 0, "expect": "empty", "label": "将垃圾袋运至户外", "source_bin": node}
		], "trash_basic"):
			return true
	return false

func _clean_floor():
	if not worker.has_skill("clean"):
		return false
	var pool = null
	for node in manager.devices():
		if stock.kind(node) == "MopPool" and stock.prop(node, "HasMop", false) and stock.valid(stock.prop(node, "OnTableObj")):
			pool = node
			break
	if not stock.valid(pool):
		return false
	var tree = worker.body.get_tree()
	for stain in tree.get_nodes_in_group("WaterStain"):
		if not stock.valid(stain) or float(stock.prop(stain, "Num", 0)) <= 0:
			continue
		var steps = []
		var mop = stock.prop(pool, "OnTableObj")
		if int(stock.prop(mop, "StainCount", 0)) > 0:
			steps.append({"target": pool, "button": 2})
			steps.append({"kind": "waitprop", "target": mop, "property": "StainCount", "maximum": 0, "timeout": 15.0})
		steps.append({"target": pool, "button": 0, "expect": "held", "item": mop})
		steps.append({"kind": "clean", "target": stain, "timeout": 25.0})
		steps.append({"target": pool, "button": 0, "expect": "empty"})
		steps.append({"target": pool, "button": 2})
		steps.append({"kind": "waitprop", "target": mop, "property": "StainCount", "maximum": 0, "timeout": 15.0})
		if _submit("拿拖把清洁并洗净归位", [pool, mop, stain], steps, "clean"):
			return true
	return false

func _collect_loose_bags():
	# A save, debug edit or interrupted shift can leave an already packed bag
	# on the floor. Continue its real contents instead of forgetting that waste.
	for source in stock.sources(manager):
		var item = source.item
		if stock.kind(item) != "Trashbag" or item.get("IsPick") != null or not worker.can_take_source(source):
			continue
		var outside = _outside_bin(stock.disposal_amount(item))
		if not stock.valid(outside):
			continue
		var steps = stock.take_steps(source)
		steps.append({"target": outside, "button": 0, "expect": "empty"})
		if _submit("继续运出已打包的垃圾", [source.target, item, outside], steps, "trash_basic"):
			return true
	return false

func _clean_loose_trash():
	for source in stock.sources(manager):
		var item = source.item
		# Native loose rubbish shares Trashbag's FuncType, but only TrashItem
		# has IsPick. Do not steal packaged garbage or useful stock to clean it.
		if stock.kind(item) != "Trashbag" or item.get("IsPick") == null or not worker.can_take_source(source):
			continue
		var bin = _bin_for_waste(float(stock.prop(item, "Weight", 1)))
		if stock.valid(bin):
			var steps = stock.take_steps(source)
			steps.append({"target": bin, "button": 0, "expect": "empty"})
			if _submit("捡起散落垃圾并丢入垃圾桶", [source.target, item, bin], steps, "clean"):
				return true
	return false

func _bring_package_inside():
	if not worker.has_skill("stock_advanced"):
		return false
	for box in manager.devices() + manager.items():
		if not stock.valid(box) or stock.kind(box) != "Box" or stock.prop(box, "IsOpen", false) or stock.empty_package(box):
			continue
		if box.get_parent().name == "Weapon_note":
			continue
		var steps = []
		var resources = [box]
		# Carry the real package onto indoor floor beside a rack. No counter is
		# claimed, so the player's work surfaces remain available.
		var spot = stock.package_ground(manager, worker, box)
		if not spot.empty() and box.global_position.distance_to(spot.point) > 75.0:
			resources.append(spot.key)
			steps.append({"target": box, "button": 0, "expect": "held", "item": box, "allow_full_package": true})
			steps.append({"kind": "put_package_ground", "target": box, "point": spot.point, "stand": spot.stand})
		steps.append({"target": box, "button": 2, "expect": "open", "permission": "stock_advanced"})
		if _submit("在货架旁地面放箱并开箱", resources, steps, "stock_advanced"):
			return true
	return false

func _stock_delivery():
	if not worker.has_skill("stock_basic"):
		return false
	for source in stock.sources(manager):
		var item = source.item
		if not stock.usable(item) or stock.exhausted_packaging(item) or stock.kind(item) in ["DrinkCup", "SodaCan", "SuperCup", "Trashbag", "Mop"]:
			continue
		if stock.is_shelf(source.target):
			continue
		if not worker.has_skill("stock_advanced") and stock.kind(source.target) != "Box":
			continue
		if not worker.can_take_source(source):
			continue
		# Delivery boxes and loose stock are unpacked one object at a time.
		# Installed appliances, tea vessels and the player's layout are never moved.
		if stock.kind(source.target) != "Box" and (not stock.prop(item, "IsItem", false) or item.get_parent().name != "Items"):
			continue
		if stock.kind(item) == "Box":
			continue
		var slot = stock.shelf_slot(manager, item, true, null, worker)
		if slot.empty():
			continue
		var steps = stock.take_steps(source)
		steps.append({"target": slot.target, "button": slot.button, "expect": "empty"})
		if _submit("从已开箱物资逐件上架", [source.target, item, slot.target], steps, "stock_basic"):
			return true
	return false

func _clear_wrappers():
	if not worker.has_skill("trash_advanced"):
		return false
	for source in stock.sources(manager):
		if not stock.exhausted_packaging(source.item) or not worker.can_take_source(source):
			continue
		var bin = _bin_for_waste(float(stock.prop(source.item, "Weight", 1)))
		if not stock.valid(bin):
			continue
		var steps = stock.take_steps(source)
		for step in steps:
			step["require_exhausted"] = true
		steps.append({"kind": "dispose_wrapper", "target": bin, "item": source.item})
		if _submit("清理已用完的原料包装", [source.target, source.item, bin], steps, "trash_advanced"):
			return true
	return false

func _clear_empty_packages():
	if not worker.has_skill("trash_advanced"):
		return false
	for source in stock.sources(manager):
		var box = source.item
		if not stock.empty_package(box):
			continue
		var bin = _bin_for_waste(5.0)
		if not stock.valid(bin):
			continue
		var steps = stock.take_steps(source)
		for step in steps:
			step["require_empty_package"] = true
		steps.append({"kind": "flatten_package", "target": box, "item": box})
		steps.append({"kind": "dispose_package", "target": bin, "item": box})
		if _submit("拆平空箱并投入垃圾桶", [source.target, box, bin], steps, "trash_advanced"):
			return true
	return false

func _recover_held(held):
	if stock.kind(held) == "Box":
		if stock.empty_package(held) and worker.has_skill("trash_advanced"):
			var bin = _bin_for_waste(5.0)
			if stock.valid(bin) and _submit("继续回收空包装箱", [held, bin], [
				{"kind": "flatten_package", "target": held, "item": held},
				{"kind": "dispose_package", "target": bin, "item": held}
			]):
				return
			status = "等待可用垃圾桶回收空箱"
			return
		var spot = stock.package_ground(manager, worker, held)
		if not spot.empty() and _submit("将货箱放在货架旁地面", [held, spot.key], [{"kind": "put_package_ground", "target": held, "point": spot.point, "stand": spot.stand}]):
			return
		status = "等待货架旁可用空地"
		return
	if stock.exhausted_packaging(held) and worker.has_skill("trash_advanced"):
		var bin = _bin_for_waste(float(stock.prop(held, "Weight", 1)))
		if stock.valid(bin) and _submit("继续清理用完的包装", [held, bin], [{"kind": "dispose_wrapper", "target": bin, "item": held}]):
			return
		status = "等待可用垃圾桶清理包装"
		return
	var size = stock.cup_group_size(held)
	if size != "" and worker.has_skill("restock_cups"):
		for holder in manager.devices():
			if stock.cup_low(holder, size) and _submit("继续补充" + size + "号空杯架", [held, holder], [{"kind": "restock_cups", "target": holder, "item": held, "size": size}]):
				return
	if stock.kind(held) == "Mop":
		for pool in manager.devices():
			if stock.kind(pool) == "MopPool" and not stock.prop(pool, "HasMop", false):
				if _submit("拖把归位", [pool, held], [{"target": pool, "button": 0, "expect": "empty"}]):
					return
	if stock.kind(held) == "Trashbag":
		var outside = _outside_bin(stock.disposal_amount(held))
		if stock.valid(outside) and _submit("运出垃圾", [outside, held], [{"target": outside, "button": 0, "expect": "empty"}]):
			return
		status = "等待可用的户外垃圾桶"
		return
	var slot = stock.shelf_slot(manager, held, true, null, worker)
	if not slot.empty() and _submit("继续将手中货物上架", [slot.target, held], [{"target": slot.target, "button": slot.button, "expect": "empty"}]):
		return
	var bench = stock.empty_bench(manager)
	if stock.valid(bench) and _submit("暂存手中货物", [bench, held], [{"target": bench, "button": 0, "expect": "empty"}]):
		return
	status = "等待空货架或空柜台"

func cancel():
	tasks.cancel()
	status = "整理与维护已暂停"

func is_busy():
	return tasks.busy

func try_start():
	if not manager.active():
		return false
	scan_in = 0.0
	tick(0.0)
	return is_busy()

func try_idle():
	if not manager.active() or not worker.has_skill("trash_advanced") or tasks.busy or stock.valid(worker.held()):
		return false
	return _collect_trash(true)

func get_progress():
	return tasks.get_progress()
