extends Reference

# Native workflows share one employee's hands, navigation and resource locks.
# Exactly one engine owns this employee's hands, navigation and locks at a time.
const Cashier = preload("res://ftc_mods/ftc.talent_market/Roles/Cashier.gd")
const Logistics = preload("res://ftc_mods/ftc.talent_market/Roles/Logistics.gd")
const ORDER = ["cashier", "logistics"]

var manager
var worker
var tasks = {}
var current_task = ""
var status = "等待可执行任务"
var cursor = 0
var idle_time = 0.0
var completed_tasks = 0
var recovery_task = ""
var recovery_item_id = 0

func _init(owner, employee):
	manager = owner
	worker = employee
	tasks = {"cashier": Cashier.new(owner, employee), "logistics": Logistics.new(owner, employee)}

func task(id):
	return tasks.get(str(id))

func _permitted(id):
	match str(id):
		"cashier":
			return worker.has_skill("cashier")
		"logistics":
			for skill in ["stock_basic", "trash_basic", "restock_cups", "clean", "repair"]:
				if worker.has_skill(skill):
					return true
	return false

func tick(delta):
	if not manager.active() or not is_instance_valid(worker.body):
		cancel()
		status = "工作已暂停"
		return
	worker.body.talent_aura_active = bool(worker.profile.get("enabled", true))
	if current_task != "":
		if not _permitted(current_task):
			cancel()
			# Contract edits or migrations may remove a permission mid-action.
			# Preserve any real inventory on the floor before changing workflows.
			worker.drop_held()
			return
		var active_task = tasks[current_task]
		active_task.tick(delta)
		status = active_task.status
		if not active_task.is_busy():
			cursor = (ORDER.find(current_task) + 1) % ORDER.size()
			active_task.cancel()
			worker.cancel_action()
			_remember_recovery(current_task)
			current_task = ""
			completed_tasks += 1
		return
	idle_time = max(0.0, idle_time - delta)
	if idle_time > 0:
		return
	idle_time = 0.25
	var held = worker.held()
	if is_instance_valid(held):
		var recovery = _recovery_engine(held)
		if recovery != "":
			# A busy counter or storage vessel is temporary. Keep the physical
			# item in hand and retry its owner instead of dropping it on the floor.
			if tasks[recovery].try_start():
				current_task = recovery
			_remember_recovery(recovery)
			status = tasks[recovery].status
		else:
			worker.drop_held()
			_clear_recovery()
			status = "已放下待接手物品"
		return
	_clear_recovery()
	# Completed jobs rotate to the next workflow. A constant queue therefore
	# lets this employee return to taking orders between maintenance jobs.
	for offset in range(ORDER.size()):
		var id = ORDER[(cursor + offset) % ORDER.size()]
		if _permitted(id) and tasks[id].try_start():
			current_task = id
			_remember_recovery(id)
			status = tasks[id].status
			return
	# Partial-bin trips are background work. Every regular skill gets a chance
	# before idle waste disposal starts.
	if _permitted("logistics") and tasks.logistics.try_idle():
		current_task = "logistics"
		_remember_recovery(current_task)
		status = tasks.logistics.status
		return
	status = "等待技能对应的任务" if _has_active_skill() else "没有主动技能，正在待命"
	if _permitted("logistics") and worker.has_skill("restock_cups") and tasks.logistics.restock_wait_reason != "":
		status = tasks.logistics.restock_wait_reason

func _clear_recovery():
	recovery_task = ""
	recovery_item_id = 0

func _remember_recovery(id):
	var held = worker.held()
	if is_instance_valid(held):
		recovery_task = str(id)
		recovery_item_id = held.get_instance_id()
	else:
		_clear_recovery()

func _recovery_engine(held):
	# Ownership is tied to the actual object, so a later pickup cannot inherit
	# the workflow of an unrelated bottle, cup or pot previously held here.
	if recovery_item_id == held.get_instance_id() and _permitted(recovery_task):
		return recovery_task
	return "logistics" if _permitted("logistics") else ""

func _has_active_skill():
	for id in ORDER:
		if _permitted(id):
			return true
	return false

func get_progress():
	if current_task != "" and tasks.has(current_task):
		var progress = tasks[current_task].get_progress()
		progress["task"] = current_task
		return progress
	return {"label": status, "elapsed": 0.0, "duration": 1.0, "ratio": 0.0, "task": ""}

func cancel():
	var previous_task = current_task
	for engine in tasks.values():
		engine.cancel()
	manager.unlock_all(worker)
	worker.cancel_action()
	# Inspect inventory after each engine has released its resources.
	if previous_task != "":
		_remember_recovery(previous_task)
	elif not is_instance_valid(worker.held()):
		_clear_recovery()
	current_task = ""
	idle_time = 0.0
	status = "工作已暂停"
