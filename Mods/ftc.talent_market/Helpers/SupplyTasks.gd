extends Reference

var manager
var worker
var stock = preload("res://ftc_mods/ftc.talent_market/Helpers/SupplyStock.gd").new()
var steps = []
var current = {}
var status = "待命"
var elapsed = 0.0
var started = false
var cooldown = 0.0
var busy = false
var cleaning_mop = null
var cleaning_stain = null
var cancelled = false
var washing_pool = null
var action_elapsed = 0.0
var total_steps = 0
var wash_interval = 0.0

func _init(owner, actor):
	manager = owner
	worker = actor

func submit(label, resources, actions):
	if busy or actions.empty():
		return false
	for step in actions:
		if not _permitted_step(step):
			return false
	for resource in resources:
		if not manager.lock(resource, worker):
			manager.unlock_all(worker)
			return false
	steps = actions.duplicate(true)
	total_steps = steps.size()
	status = label
	busy = true
	cancelled = false
	_next()
	return true

func tick(delta):
	if not busy:
		return false
	if not manager.active():
		return true
	elapsed += delta
	cooldown = max(0.0, cooldown - delta)
	if stock.valid(washing_pool):
		var wash_timer = washing_pool.get_node_or_null("CleanTimer")
		if stock.prop(washing_pool, "CLEANPLAYER") == worker.body and wash_timer != null:
			if wash_interval <= 0:
				wash_interval = wash_timer.wait_time
			wash_timer.wait_time = wash_interval * worker.work_duration(1.0, "clean")
		elif wash_interval > 0:
			if wash_timer != null:
				wash_timer.wait_time = wash_interval
			wash_interval = 0.0
	if elapsed > float(current.get("timeout", 45.0)):
		cancel()
		status = "目标不可用，重新安排"
		return false
	var action = str(current.get("kind", "interact"))
	var target = current.get("target")
	if not _permitted_step(current):
		cancel()
		return false
	if action == "clean" and started and not stock.valid(target):
		_finish_clean()
		_next()
		return busy
	if action != "wait" and not stock.valid(target):
		cancel()
		return false
	if action == "wait":
		if elapsed >= float(current.get("duration", 0.3)):
			_next()
		return busy
	if action == "put_package_ground":
		var point = current.get("point")
		if worker.held() != target or point == null or not stock.ground_clear(manager, worker, target, point):
			cancel()
			return false
		if not worker.move_to(current.stand):
			if worker.path_blocked:
				cancel()
				status = "通路关闭，重新安排"
				return false
			return true
		action_elapsed += delta
		if action_elapsed >= _work_delay():
			var dropped = worker.drop_held(point)
			if dropped == target and not stock.valid(worker.held()):
				_next()
			else:
				cancel()
		return busy
	var target_is_held = stock.valid(worker.held()) and (target == worker.held() or worker.body.is_a_parent_of(target))
	if not target_is_held and not worker.move_to_device(target):
		if worker.path_blocked:
			cancel()
			status = "通路关闭，重新安排"
			return false
		return true
	if action == "waitprop":
		if _property_ready(target):
			_next()
		return busy
	if action == "clean":
		_clean(target)
		return busy
	if action in ["elec", "repair"]:
		if not worker.has_skill("repair"):
			cancel()
			return false
		action_elapsed += delta
		if action_elapsed < _work_delay("repair"):
			return true
		if action == "repair":
			var warning = target.get_node_or_null("WarningNode")
			if not stock.valid(warning) or not stock.prop(warning, "NeedFix", false):
				_next()
			elif cooldown <= 0:
				warning.return_Fixing(worker.body)
				cooldown = _work_delay("repair")
			return busy
		if not stock.prop(target, "CanUse", false):
			_next()
		elif cooldown <= 0:
			target.call_home_device(0, 1, 0, worker.body)
			cooldown = _work_delay("repair")
		return busy
	if action in ["interact", "flatten_package", "dispose_package", "dispose_wrapper", "restock_cups"]:
		action_elapsed += delta
		if action_elapsed < _work_delay():
			return true
	if cooldown > 0:
		return true
	started = true
	if action == "flatten_package":
		_flatten_package(target)
		return busy
	if action in ["dispose_package", "dispose_wrapper"]:
		_dispose_packaging(target, action == "dispose_package")
		return busy
	if action == "restock_cups":
		_restock_cups(target)
		return busy
	var before = worker.held()
	var expected = str(current.get("expect", "any"))
	if expected == "held":
		if stock.valid(before):
			if current.get("item") == null or before == current.get("item"):
				_next()
			else:
				cancel()
			return busy
		if not _source_unchanged(target):
			cancel()
			return false
	if expected == "empty" and not stock.valid(before):
		_next()
		return busy
	if expected == "empty" and not _destination_ready(target, before):
		cancel()
		return false
	if stock.kind(target) == "MopPool":
		target.call_pick(int(current.get("button", 0)), worker.body)
		if stock.prop(target, "CLEANPLAYER") == worker.body:
			washing_pool = target
	elif stock.kind(target) == "Trashbin":
		var button = int(current.get("button", 0))
		if stock.valid(before):
			target.call_DevLogic_DropTrash(button, worker.body, before, target)
		else:
			target.call_DevLogic_Trashbin(button, worker.body, target)
	else:
		worker.interact(target, int(current.get("button", 0)))
	if _interaction_ready(target, before):
		var after = worker.held()
		if stock.valid(after) and after.get_parent().name == "Weapon_note":
			after.set("Holding", true)
			after.set("Holder", worker.body)
		if stock.valid(before) and not stock.valid(worker.held()):
			_normalize_put(before)
		_next()
	elif expected == "held" and stock.valid(worker.held()):
		# Another actor may change a shelf between approach and interaction. Keep
		# the actual object safe and re-plan instead of pressing its next button.
		cancel()
	else:
		cooldown = 0.4
	return busy

func _normalize_put(item):
	if stock.valid(item) and item.get_parent().name != "Weapon_note":
		item.set("Holding", false)
		item.set("Holder", null)

func _removed(item):
	return not is_instance_valid(item) or item.is_queued_for_deletion() or not item.is_inside_tree()

func _flatten_package(box):
	# Native dismantling has two outcomes: a real five-unit waste box, or the
	# player's existing cardboard-sale reward. Never replace either with spawn.
	if worker.held() != box or not stock.empty_package(box):
		cancel()
		return
	if stock.prop(box, "IsTrash", false):
		_next()
		return
	if not stock.prop(box, "IsOpen", false):
		box.call_OpenBox()
		cooldown = 0.4
		return
	var result = box.call_PickItem(worker.body)
	if result != "拆箱":
		cancel()
	elif _removed(box):
		# Native sale deletes a held box without releasing its former carrier.
		worker.body.Stat.call_carry_off()
		steps.clear()
		_next()
	elif stock.prop(box, "IsTrash", false) and stock.empty_package(box):
		_next()
	else:
		cancel()

func _dispose_packaging(bin, is_box):
	var item = current.get("item")
	if not stock.valid(item) or worker.held() != item:
		cancel()
		return
	if is_box:
		if not stock.empty_package(item) or not stock.prop(item, "IsTrash", false):
			cancel()
			return
	elif not stock.exhausted_packaging(item):
		cancel()
		return
	var amount = float(stock.prop(item, "Weight", 1))
	if item.has_method("return_DropCount"):
		amount = float(item.return_DropCount())
	if not stock.disposal_space(bin, amount):
		cancel()
		return
	# HasTable generic dispatch does not mean "throw away". This native entry
	# accounts for real waste weight, statistics, rewards and item deletion.
	var result = bin.call_DevLogic_DropTrash(0, worker.body, item, bin)
	if result == "入垃圾桶" and not stock.valid(worker.held()) and _removed(item):
		_next()
	else:
		cancel()

func _restock_cups(holder):
	var item = current.get("item")
	var size = str(current.get("size", ""))
	if not stock.valid(item) or worker.held() != item or stock.cup_group_size(item) != size or not stock.cup_low(holder, size):
		cancel()
		return
	var before = int(stock.prop(holder, size + "_Num", -1))
	var result = holder.call_PutOn(0, worker.body)
	if result == "放入杯组" and int(stock.prop(holder, size + "_Num", -1)) == before + 10 and not stock.valid(worker.held()) and _removed(item):
		_next()
	else:
		cancel()

func _destination_ready(target, item):
	if not stock.valid(item):
		return false
	if stock.type_name(target) in ["WorkBench", "WorkBench_Immovable"]:
		return not stock.valid(stock.prop(target, "OnTableObj"))
	if stock.is_shelf(target):
		var layer = stock.shelf_buttons(target).find(int(current.get("button", 0))) + 1
		if layer < 1:
			return false
		var entries = stock.prop(target, "layer%d_Array" % layer, [])
		var row_type = str(stock.prop(target, "Layer%d_Item" % layer, ""))
		return entries is Array and entries.size() < int(8.0 / max(0.01, float(stock.prop(item, "Weight", 1)))) and (entries.empty() or row_type == stock.type_name(item))
	if stock.kind(target) == "MopPool":
		return not stock.prop(target, "HasMop", false) and stock.kind(item) == "Mop"
	if stock.kind(target) == "Trashbin":
		if stock.kind(item) == "Trashbag" and item.get("IsPick") == null:
			if not stock.outdoor_bin(target) or current.get("source_bin") == target:
				return false
		return stock.disposal_space(target, stock.disposal_amount(item))
	return true

func _interaction_ready(target, before):
	var expected = str(current.get("expect", "any"))
	var held = worker.held()
	match expected:
		"held":
			var item = current.get("item")
			return stock.valid(held) and (item == null or held == item)
		"empty":
			return not stock.valid(held)
		"open":
			return stock.prop(target, "IsOpen", false)
		"changed":
			return held != before
		_:
			return true

func _source_unchanged(target):
	var item = current.get("item")
	if item == null:
		return true
	if not stock.valid(item):
		return false
	if item.get_parent().name == "Weapon_note":
		return false
	if current.get("require_empty_package", false) and not stock.empty_package(item):
		return false
	if current.get("require_exhausted", false) and not stock.exhausted_packaging(item):
		return false
	if stock.is_shelf(target):
		var index = stock.shelf_buttons(target).find(int(current.get("button", 0)))
		if index < 0:
			return false
		var entries = stock.prop(target, "layer%d_Array" % (index + 1), [])
		return entries is Array and not entries.empty() and entries.back() == item
	if stock.kind(target) == "Box":
		if target == item:
			return stock.empty_package(item) or (current.get("allow_full_package", false) and worker.has_skill("stock_advanced"))
		if not stock.prop(target, "IsOpen", false) and not worker.has_skill("stock_advanced"):
			return false
		var entries = stock.prop(target, "ItemOBJ_Array", [])
		return entries is Array and not entries.empty() and entries.back() == item
	if stock.kind(target) == "MopPool":
		return stock.prop(target, "OnTableObj") == item and stock.prop(target, "HasMop", false)
	return target == item

func _property_ready(target):
	var property = str(current.get("property", ""))
	var value = stock.prop(target, property)
	# Native washing removes dirt in chunks of ten and can finish below zero.
	# Preserve the native wash/timer while restoring the mop's valid bounds.
	if property == "StainCount" and value != null and int(value) < 0:
		target.StainCount = 0
		if target.has_method("_Stain_Logic"):
			target._Stain_Logic()
		value = 0
	if current.has("minimum"):
		return value != null and float(value) >= float(current.minimum)
	if current.has("maximum"):
		return value != null and float(value) <= float(current.maximum)
	return value == current.get("value", true)

func _clean(target):
	var mop = worker.held()
	if not stock.valid(mop) or stock.type_name(mop) != "Mop":
		cancel()
		return
	if not started:
		if int(stock.prop(mop, "StainCount", 0)) >= int(stock.prop(mop, "StainMax", 30)):
			_next()
			return
		var cleaner = stock.prop(target, "_MOPNODE")
		if stock.valid(cleaner) and cleaner != mop:
			_next()
			return
		cleaning_mop = mop
		cleaning_stain = target
		mop.return_WORK_start(worker.body, 1.0)
		worker.begin_work(mop, 5.0)
		target.call_clean(true, mop, worker.work_duration(1.0, "clean"))
		started = true
	# Native WaterStain resets its timer to 0.3 after each dose. Reapply only
	# while this mop still owns the stain, so every dose keeps star/passive timing.
	var timer = target.get_node_or_null("CleanTimer")
	if timer != null and stock.prop(target, "_MOPNODE") == mop:
		timer.wait_time = 0.3 * worker.work_duration(1.0, "clean")
	if float(stock.prop(target, "Num", 0)) <= 0 or int(stock.prop(mop, "StainCount", 0)) >= int(stock.prop(mop, "StainMax", 30)):
		_finish_clean()
		_next()

func _finish_clean():
	if stock.valid(cleaning_stain) and stock.prop(cleaning_stain, "_MOPNODE") == cleaning_mop:
		cleaning_stain.call_clean(false, cleaning_mop, 1.0)
	if stock.valid(cleaning_mop):
		cleaning_mop.call_STIR_end(worker.body)
	cleaning_mop = null
	cleaning_stain = null
	worker.end_work()

func _work_delay(category = "hand"):
	return worker.work_duration(1.0, category)

func _permitted_step(step):
	var required = str(step.get("permission", ""))
	if required != "" and not worker.has_skill(required):
		return false
	var action = str(step.get("kind", "interact"))
	if action in ["dispose_wrapper", "dispose_package", "flatten_package"] and not worker.has_skill("trash_advanced"):
		return false
	if action == "restock_cups" and not worker.has_skill("restock_cups"):
		return false
	if action == "clean" and not worker.has_skill("clean"):
		return false
	if action in ["repair", "elec"] and not worker.has_skill("repair"):
		return false
	var target = step.get("target")
	if stock.kind(target) == "Box":
		if step.get("allow_full_package", false) and not worker.has_skill("stock_advanced"):
			return false
		if str(step.get("expect", "")) == "open" and not worker.has_skill("stock_advanced"):
			return false
		if step.get("item") != target and not stock.prop(target, "IsOpen", false) and not worker.has_skill("stock_advanced"):
			return false
	return true

func get_progress():
	var duration = _work_delay()
	var fraction = clamp(action_elapsed / duration, 0.0, 1.0)
	if str(current.get("kind", "")) in ["waitprop", "clean", "repair", "elec"]:
		fraction = clamp(elapsed / max(1.0, float(current.get("timeout", duration))), 0.0, 0.95)
	var completed = max(0, total_steps - steps.size() - (1 if busy else 0))
	return {"label": status, "elapsed": action_elapsed, "duration": duration, "ratio": (float(completed) + fraction) / max(1.0, float(total_steps)) if busy else 1.0}

func _next():
	current = {}
	elapsed = 0.0
	started = false
	cooldown = 0.0
	action_elapsed = 0.0
	if steps.empty():
		busy = false
		if not stock.valid(washing_pool) or stock.prop(washing_pool, "CLEANPLAYER") != worker.body:
			washing_pool = null
		worker.end_work()
		manager.unlock_all(worker)
		return
	current = steps.pop_front()
	if current.has("label"):
		status = str(current.label)

func cancel():
	_finish_clean()
	# Native pool timers retain CLEANPLAYER when an employee is dismissed
	# mid-wash. Release this operator and leave the real dirt/tool in place so
	# another employee or the player can continue washing normally.
	if stock.valid(washing_pool) and stock.prop(washing_pool, "CLEANPLAYER") == worker.body:
		var timer = washing_pool.get_node_or_null("CleanTimer")
		if timer != null:
			timer.stop()
			if wash_interval > 0:
				timer.wait_time = wash_interval
		var audio = washing_pool.get_node_or_null("AudioStreamPlayer2D")
		if audio != null:
			audio.stop()
		washing_pool.CLEANPLAYER = null
	washing_pool = null
	wash_interval = 0.0
	var held = worker.held()
	_release_native_operator(held)
	steps.clear()
	total_steps = 0
	current = {}
	busy = false
	cancelled = true
	worker.cancel_action()
	manager.unlock_all(worker)

func _release_native_operator(item):
	if not stock.valid(item):
		return
	for key in ["PlayerList", "cur_PlayerList", "_PLAYERLIST"]:
		var operators = item.get(key)
		if operators is Array:
			operators.erase(worker.body)
