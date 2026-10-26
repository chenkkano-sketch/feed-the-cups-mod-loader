extends Reference

# One native device/customer operation is a finite job, leaving other skills a turn.
var manager
var worker
var status = "等待营业"
var terminal = null
var customer = null
var table_order = false
var prefer_tables = true
var elapsed = 0.0
var travel_elapsed = 0.0
var route_check_in = 0.0
var terminal_key = ""
var customer_key = ""

func _init(market, employee):
	manager = market
	worker = employee

func tick(delta):
	if not worker.has_skill("cashier") or not manager.active() or not _opened():
		cancel()
		status = "等待营业"
		return
	if is_instance_valid(worker.held()) or not _pending():
		cancel()
		status = "等候可点单顾客"
		return
	travel_elapsed += delta
	if travel_elapsed > 45.0:
		cancel()
		status = "通路暂不可用，重新安排"
		return
	route_check_in -= delta
	if route_check_in <= 0:
		route_check_in = 0.6
		if worker.navigation.approach(terminal, worker.body.global_position) == null:
			cancel()
			status = "等待可通行的点单位置"
			return
	if not worker.move_to_device(terminal):
		elapsed = 0.0
		status = "前往堂食桌点单" if table_order else "前往点单机"
		return
	status = "正在为堂食顾客点单" if table_order else "正在点单"
	elapsed += delta
	if elapsed < worker.work_duration(1.0, "order"):
		return
	# Native table/terminal operations consume their own front customer. Check
	# again after walking so a player or another server cannot cause a double order.
	if _pending():
		terminal.call_Order_Logic(worker.body)
	prefer_tables = not table_order
	cancel()
	status = "点单完成"

func is_busy():
	return _valid(terminal) and _valid(customer)

func try_start():
	if not worker.has_skill("cashier") or not manager.active() or not _opened() or is_instance_valid(worker.held()):
		return false
	cancel()
	if worker.has_skill("cashier_advanced") and prefer_tables and _claim(true):
		return true
	if _claim(false):
		return true
	return worker.has_skill("cashier_advanced") and _claim(true)

func _valid(node):
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()

func _needs_order(npc, seated):
	if not _valid(npc):
		return false
	var orders = manager.game.Order
	var id = int(npc.get("PickUpID"))
	if id > 0 and orders.cur_OrderList.has(id):
		return false
	return orders.cur_TableOrderArray.has(npc) if seated else orders.cur_LineUpArray.has(npc)

func _front(device, seated):
	var orders = manager.game.Order
	var queue = device.OrderList if seated else orders.cur_LineUpArray
	while not queue.empty() and not _needs_order(queue.front(), seated):
		queue.pop_front()
	return queue.front() if not queue.empty() else null

func _pending():
	if not is_busy() or not _needs_order(customer, table_order):
		return false
	if table_order and (not worker.has_skill("cashier_advanced") or terminal.get("FuncType") != "GuestSeat"):
		return false
	if not table_order and terminal.get("TurnOn") != true:
		return false
	return _front(terminal, table_order) == customer

func _available(device, seated):
	if not _valid(device) or not device.has_method("call_Order_Logic"):
		return false
	if seated:
		if device.get("FuncType") != "GuestSeat" or not device.get("OrderList") is Array:
			return false
	elif device.get("SelfDev") != "OrderTab" or device.get("TurnOn") != true:
		return false
	var npc = _front(device, seated)
	if not _valid(npc):
		return false
	for resource in [device, npc]:
		if manager.locks.get(manager._resource_key(resource), str(worker.profile.id)) != str(worker.profile.id):
			return false
	if not seated and manager.locks.get("cashier.queue", str(worker.profile.id)) != str(worker.profile.id):
		return false
	return worker.navigation.approach(device, worker.body.global_position) != null

func _claim(seated):
	var nearest = null
	var distance = INF
	for device in manager.devices():
		if not _available(device, seated):
			continue
		var candidate = worker.body.global_position.distance_squared_to(device.global_position)
		if candidate < distance:
			distance = candidate
			nearest = device
	if nearest == null:
		return false
	var npc = _front(nearest, seated)
	if not manager.lock(nearest, worker):
		return false
	if not manager.lock(npc, worker):
		manager.unlock(nearest, worker)
		return false
	if not seated and not manager.lock("cashier.queue", worker):
		manager.unlock(nearest, worker)
		manager.unlock(npc, worker)
		return false
	terminal = nearest
	customer = npc
	terminal_key = manager._resource_key(terminal)
	customer_key = manager._resource_key(customer)
	table_order = seated
	elapsed = 0.0
	travel_elapsed = 0.0
	status = "前往堂食桌点单" if seated else "前往点单机"
	return true

func get_progress():
	var duration = worker.work_duration(1.0, "order")
	return {"label": status, "elapsed": elapsed, "duration": duration, "ratio": clamp(elapsed / duration, 0.0, 1.0)}

func _opened():
	return is_instance_valid(manager.game.GameUI) and manager.game.GameUI.get("Is_Open") == true

func cancel():
	# Keep identity keys even when a customer leaves and is freed mid-walk.
	if terminal_key != "":
		manager.unlock(terminal_key, worker)
	if customer_key != "":
		manager.unlock(customer_key, worker)
	if not table_order:
		manager.unlock("cashier.queue", worker)
	terminal = null
	customer = null
	terminal_key = ""
	customer_key = ""
	route_check_in = 0.0
	table_order = false
	elapsed = 0.0
	travel_elapsed = 0.0
