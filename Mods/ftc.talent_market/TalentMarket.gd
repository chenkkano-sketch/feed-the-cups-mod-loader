extends Node

const Rules = preload("res://ftc_mods/ftc.talent_market/TalentRules.gd")
const Actor = preload("res://ftc_mods/ftc.talent_market/Actors/StaffActor.gd")
const Scheduler = preload("res://ftc_mods/ftc.talent_market/AI/SkillScheduler.gd")
const SAVE_KEY = "ftc_talent_market"
const OUTFIT_ANIMATORS = preload("res://ftc_mods/ftc.talent_market/Visuals/PortraitFactory.gd").OUTFIT_ANIMATORS
var api
var game
var state = {}
var workers = {}
var locks = {}
var room = null
var day_started = false
var suspended = true
var tick = 0.0
var refresh_at = 0
var cache_at = 0
var crowd_at = 0
var crowd_pairs = {}
var cached_devices = []
var cached_items = []
var panel
var entry_button
var tabs
var candidate_list
var staff_list
var summary
var message
var font
var was_paused = false
var controls_were_enabled = false
var controls_owned = false
var appearance_catalog = []
var portrait_cache = {}
var portrait_order = []
var portrait_ink_cache = {}
var portraits
var ui
var debug_mode = false

func _ready():
	game = api.native_game()
	pause_mode = Node.PAUSE_MODE_PROCESS
	game.connect("DayStart", self, "_day_start")
	game.connect("OpenStore", self, "_opened")
	game.connect("CloseLight", self, "_closed")
	_build_ui()
	var debug_config = ConfigFile.new()
	if debug_config.load(api.config_path("debug.cfg")) == OK:
		debug_mode = bool(debug_config.get_value("debug", "enabled", false))

func is_run():
	var level = api.current_level()
	return api.offline() and game.LoadingUI.IsLevel and not game.LoadingUI.Is_Loading and is_instance_valid(level) and level.has_node("YSort/Devices") and level.has_node("MapNode/Floor") and is_instance_valid(game.player_1P)

func active():
	if not is_run() or not day_started or get_tree().paused or game.GameUI.DayEnd or game._DayOver_Bool:
		return false
	var furniture = api.service("ftc.furniture_carry", "mode")
	return furniture == null or not furniture.carry.enabled

func can_manage():
	return is_run() and not game.GameUI.Is_Open and not game.GameUI.DayEnd and not game._DayOver_Bool

func is_modal_open():
	return is_instance_valid(panel) and panel.visible

func _ensure_state():
	var saved = game.Save.levelData.get(SAVE_KEY, {})
	if not saved is Dictionary or str(saved.get("run_id", "")).empty():
		_despawn()
		state = Rules.empty_state()
		game.Save.levelData[SAVE_KEY] = state.duplicate(true)
	elif state.empty() or state.get("run_id", "") != saved.get("run_id", ""):
		_despawn()
		state = Rules.normalize(saved)
	if int(state.get("version", 0)) != Rules.VERSION:
		state = Rules.normalize(state)
	if int(state.get("day", 0)) != int(game.cur_Day):
		state = Rules.for_day(state, game.cur_Day, _appearance_catalog())
		state.refresh_spent = 0
		state.severance_spent = 0
	for person in state.get("staff", []) + state.get("candidates", []):
		_validate_appearance(person)

func restore_state():
	_despawn()
	state = Rules.normalize(game.Save.levelData.get(SAVE_KEY, {}))
	for person in state.get("staff", []) + state.get("candidates", []):
		_validate_appearance(person)
	game.Save.levelData[SAVE_KEY] = state.duplicate(true)

func new_run():
	_despawn()
	day_started = false
	state = Rules.empty_state()
	game.Save.levelData[SAVE_KEY] = state.duplicate(true)

func store_state():
	if game == null or not api.offline():
		return
	if game.cur_level == "" and not game.Save.levelData.has(SAVE_KEY):
		return
	_ensure_state()
	game.Save.levelData[SAVE_KEY] = state.duplicate(true)

func _save():
	if can_manage():
		# Contracts and the inventory they just released must share one checkpoint.
		# Native call_level_save also deletes live items, so use its snapshot hooks.
		var carry = api.service("ftc.furniture_carry", "carry")
		if carry != null:
			carry.cancel()
		var level = api.current_level()
		level._dev_save()
		level._item_save()
		_snapshot_player_item(level)
	store_state()
	game.call_save()

func _snapshot_player_item(level):
	# Native snapshots only visit world items. Keep the human's held object in
	# their hands now, but restore it on the floor if this checkpoint is loaded.
	var player = game.player_1P
	if not is_instance_valid(player) or not player.Con.IsHold:
		return
	var item = instance_from_id(player.Con.HoldInsId)
	if not is_instance_valid(item) or item.is_queued_for_deletion() or not in_hands(item):
		return
	var data = game.Save.return_savedata(item)
	if not data is Dictionary or data.empty():
		return
	data = data.duplicate(true)
	data.pos = level.get_node("YSort/Items").to_local(player.global_position)
	for record in game.Save.levelData.get("Items", []):
		if record is Dictionary and str(record.get("NAME", "")) == str(data.get("NAME", "")):
			return
	game.Save.levelData["Items"].append(data)

func _day_start():
	_ensure_state()
	day_started = true
	cache_at = 0
	crowd_at = 0
	crowd_pairs.clear()
	_spawn_missing()
	store_state()

func _opened():
	_ensure_state()
	if int(state.get("shift", {}).get("day", 0)) == int(game.cur_Day):
		return
	var ids = []
	var amount = 0
	var wages = {}
	for person in state.staff:
		if person.get("enabled", true):
			ids.append(person.id)
			var wage = daily_wage(person)
			wages[str(person.id)] = wage
			amount += wage
	state.shift = {"day": int(game.cur_Day), "ids": ids, "wages": wages, "amount": amount}
	_save()

func _closed():
	_quiesce()

func daily_wage(person):
	var day = max(1, int(game.cur_Day))
	var shift = state.get("shift", {})
	var locked = shift.get("wages", {})
	if int(shift.get("day", 0)) == day and locked.has(str(person.get("id", ""))):
		return int(locked[str(person.id)])
	# A contract retains its original base wage. Every quote starts from that
	# base, never from yesterday's raised wage or a discounted rent payment.
	var multiplier = 1.0 + 0.5 * float(day - 1)
	var rent = api.service("ftc.rent_mode", "mode")
	if rent != null and rent.is_run():
		if rent.has_method("wage_multiplier"):
			multiplier = rent.wage_multiplier(day)
		else:
			# Compatibility with rent-mode releases before the pressure rebalance.
			var initial_rent = max(1, int(rent.Rules.rent_for_day(rent.settings, 1)))
			var current_rent = max(0, int(rent.Rules.rent_for_day(rent.settings, day)))
			multiplier = float(current_rent) / float(initial_rent)
	return int(ceil(float(max(0, int(person.get("wage", 0)))) * multiplier))

func wage_total():
	var shift = state.get("shift", {})
	if int(shift.get("day", 0)) == int(game.cur_Day):
		return int(shift.get("amount", 0))
	var total = 0
	for person in state.get("staff", []):
		if person.get("enabled", true):
			total += daily_wage(person)
	return total

func charge_wages():
	_ensure_state()
	_quiesce()
	if int(state.get("paid_day", 0)) >= int(game.cur_Day):
		return 0
	var shift = state.get("shift", {})
	var amount = int(shift.get("amount", 0)) if int(shift.get("day", 0)) == int(game.cur_Day) else 0
	if game.cur_Event in ["免工资", "大免单"]:
		amount = 0
	state.paid_day = int(game.cur_Day)
	state.paid_amount = amount
	if amount > 0:
		game.call_MoneyChange(-amount, game.HomeMoneyKey)
		game.level_MoneyCostTotal += amount
		game.level_ProfitTotal -= amount
		game.call_MC(-amount, game.HomeMoneyKey)
	store_state()
	return amount

func record_wages(amount):
	var records = game.Save.levelData.get("DAYINFO", {})
	if not records is Dictionary:
		return
	var key = "Day_" + str(game.cur_Day)
	if records.has(key) and records[key] is Dictionary:
		var row = records[key]
		if not row.get("TalentWagesRecorded", false):
			var staff_paid = int(amount) + int(state.get("severance_spent", 0))
			row["Cost_Staff"] = int(row.get("Cost_Staff", 0)) - staff_paid
			row["TODAY"] = int(row.get("TODAY", 0)) - staff_paid
			row["TalentWagesRecorded"] = true
			records[key] = row
			records["Cost_Staff"] = int(records.get("Cost_Staff", 0)) - staff_paid
			game.Save.levelData["DAYINFO"] = records
		if not row.get("TalentRefreshRecorded", false):
			# Native settlement has already finished. This is presentation of the
			# fee paid before opening, never another deduction from the wallet.
			var refresh_paid = int(state.get("refresh_spent", 0))
			row["Cost_Items"] = int(row.get("Cost_Items", 0)) - refresh_paid
			row["TODAY"] = int(row.get("TODAY", 0)) - refresh_paid
			row["TalentRefreshRecorded"] = true
			records[key] = row
			records["Cost_Items"] = int(records.get("Cost_Items", 0)) - refresh_paid
			game.Save.levelData["DAYINFO"] = records
	store_state()

func hire(id):
	if not can_manage():
		return _say("请在开店前招聘；营业期间合同锁定。")
	_ensure_state()
	if state.staff.size() >= Rules.MAX_STAFF:
		return _say("当前最多聘用 %d 位店员。" % Rules.MAX_STAFF)
	for person in state.candidates:
		if person.id != id:
			continue
		if game.cur_money < daily_wage(person):
			return _say("当前现金不足一天日薪，请先准备工资。")
		state.staff.append(person.duplicate(true))
		state.candidates.erase(person)
		_save()
		_spawn_missing()
		_render_lists()
		return _say("已聘用 %s，今日日薪 %d 元；本日开店后计薪。" % [person.name, daily_wage(person)], true)
	return false

func refresh_candidates():
	if not can_manage():
		return _say("请在开店前刷新人才；营业期间招聘名单锁定。")
	_ensure_state()
	var index = int(state.get("refresh_index", 0))
	var price = Rules.refresh_cost(index)
	if int(game.cur_money) < price:
		return _say("现金不足，刷新人才需要 %d 元。" % price)
	var next = Rules.candidates(state.seed, game.cur_Day, _appearance_catalog(), index + 1)
	if next.size() != Rules.CANDIDATE_COUNT:
		return _say("暂时无法更新人才名单。")
	# Refresh is paid now. Keep it outside native deferred material purchases,
	# which would otherwise charge the same fee again in evening settlement.
	game.call_MoneyChange(-price, game.HomeMoneyKey)
	game.call_MC(-price, game.HomeMoneyKey)
	game.level_MoneyCostTotal += price
	game.level_ProfitTotal -= price
	state.refresh_index = index + 1
	state.refresh_spent = int(state.get("refresh_spent", 0)) + price
	state.candidates = next
	_save()
	_render_lists()
	return _say("已刷新 5 位人才；下次刷新 %d 元。" % Rules.refresh_cost(index + 1), true)

func fire(id):
	if not can_manage():
		return _say("请在开店前解除合同；营业期间不能免除当日工资。")
	_ensure_state()
	for person in state.get("staff", []):
		if person.id == id:
			var severance = daily_wage(person)
			if int(game.cur_money) < severance:
				return _say("现金不足，遣散 %s 需要 %d 元离职金。" % [person.name, severance])
			game.call_MoneyChange(-severance, game.HomeMoneyKey)
			game.call_MC(-severance, game.HomeMoneyKey)
			game.level_MoneyCostTotal += severance
			game.level_ProfitTotal -= severance
			state.severance_spent = int(state.get("severance_spent", 0)) + severance
			_remove_worker(id)
			state.staff.erase(person)
			_save()
			_render_lists()
			return _say("已遣散 %s，支付离职金 %d 元。" % [person.name, severance], true)
	return false

func set_duty(value, id):
	if not can_manage():
		_render_lists()
		return false
	for person in state.staff:
		if person.id == id:
			person.enabled = value
			_remove_worker(id)
			_save()
			_spawn_missing()
			_render_lists()
			return true
	return false

func set_debug_mode(value):
	debug_mode = bool(value)
	var config = ConfigFile.new()
	config.set_value("debug", "enabled", debug_mode)
	config.save(api.config_path("debug.cfg"))
	if not debug_mode:
		ui.close_debug_editor()
	_render_lists()
	return _say("调试模式已开启，可在已聘店员卡片调整技能和星级。" if debug_mode else "调试模式已关闭。", true)

func debug_edit_employee(id, stars, selected):
	if not debug_mode or not is_run() or not panel.visible:
		return _say("请先打开人才市场并开启调试模式。")
	if not (typeof(stars) in [TYPE_INT, TYPE_REAL]) or int(stars) < 1 or int(stars) > 6 or not selected is Array or selected.size() != 4:
		return _say("星级需为1～6，技能槽需为4个。")
	var seen = {}
	for skill in selected:
		if not Rules.Catalog.valid_id(skill) or (skill != "" and seen.has(skill)):
			return _say("技能无效，或同一员工出现了重复技能。")
		if skill != "":
			seen[skill] = true
	selected = Rules.Catalog.stored_slots(selected)
	_ensure_state()
	for index in range(state.staff.size()):
		var person = state.staff[index].duplicate(true)
		if str(person.id) != str(id):
			continue
		# Save released inventory and contract edits in one checkpoint. Keep the
		# body/position, identity, appearance and already committed payroll intact.
		_quiesce()
		person.stars = int(stars)
		person.skill_slots = selected.duplicate()
		person.speed = Rules.modifiers(person).move_speed
		# Commit to the authoritative contract before native save hooks can
		# normalize/rebuild state. Cards and live actors use this same contract.
		state.staff[index] = person
		game.Save.levelData[SAVE_KEY] = state.duplicate(true)
		if workers.has(person.id):
			var worker = workers[person.id]
			worker.actor.profile = person.duplicate(true)
			worker.actor.body.talent_profile = worker.actor.profile
			worker.actor.body.configure_stats()
			worker.actor.body.talent_work_duration = worker.actor.work_duration()
			worker.role = Scheduler.new(self, worker.actor)
		var level = api.current_level()
		level._dev_save()
		level._item_save()
		_snapshot_player_item(level)
		store_state()
		game.call_save()
		api.log("debug employee updated: " + str(person.id) + " stars=" + str(person.stars) + " slots=" + str(person.skill_slots))
		_render_lists()
		return _say("已更新 %s，高级技能已替换同系低级技能，合同工资保留。" % person.name, true)
	return _say("该员工已不在当前合同中。")

func open_debug_editor(id):
	return ui.open_debug_editor(id)

func close_debug_editor():
	ui.close_debug_editor()

func apply_debug_editor():
	ui.apply_debug_editor()

func _spawn_missing():
	if not is_run() or not day_started:
		return
	var level = api.current_level()
	if room != level:
		_despawn()
		room = level
	for person in state.get("staff", []):
		if not person.get("enabled", true):
			continue
		if workers.has(person.id) and is_instance_valid(workers[person.id].actor.body):
			continue
		_remove_worker(person.id)
		var actor = Actor.new()
		if not actor.spawn(person.duplicate(true), room):
			api.log("spawn postponed: " + str(actor.last_error))
			actor.cleanup()
			continue
		var role = Scheduler.new(self, actor)
		workers[person.id] = {"actor": actor, "role": role}

func _remove_worker(id):
	if not workers.has(id):
		return
	var worker = workers[id]
	if is_instance_valid(worker.actor.body) and worker.actor.body.is_inside_tree():
		worker.role.cancel()
	unlock_all(worker.actor)
	worker.actor.cleanup()
	workers.erase(id)

func _despawn():
	for id in workers.keys():
		_remove_worker(id)
	locks.clear()
	room = null
	cache_at = 0
	crowd_pairs.clear()

func _quiesce():
	for worker in workers.values():
		worker.actor.suspended = true
		if is_instance_valid(worker.actor.body) and worker.actor.body.is_inside_tree():
			worker.role.cancel()
			worker.actor.cancel_action()
			worker.actor.drop_held()
		unlock_all(worker.actor)
	suspended = true

func _suspend_workers():
	# Pausing a menu preserves jobs and held objects; layout/save/close explicitly
	# quiesce them instead, where a stable world inventory is required.
	for worker in workers.values():
		worker.actor.suspended = true
		if is_instance_valid(worker.actor.body) and worker.actor.body.is_inside_tree():
			worker.actor.body.set_motion(Vector2.ZERO, 0.0)
	suspended = true

func before_layout_save(level):
	if room == level:
		_quiesce()

func _resource_key(resource):
	return "object:" + str(resource.get_instance_id()) if resource is Object and is_instance_valid(resource) else str(resource)

func lock(resource, worker):
	if resource == null or worker == null:
		return false
	var key = _resource_key(resource)
	var id = str(worker.profile.id)
	if locks.has(key) and locks[key] != id:
		return false
	locks[key] = id
	return true

func unlock(resource, worker):
	var key = _resource_key(resource)
	if worker != null and locks.get(key, "") == str(worker.profile.id):
		locks.erase(key)

func unlock_all(worker):
	if worker == null:
		return
	for key in locks.keys():
		if locks[key] == str(worker.profile.id):
			locks.erase(key)

func _collect(node, result):
	if not is_instance_valid(node):
		return
	if node.get("TypeStr") != null or node.get("FuncType") != null or node.has_method("call_home_device"):
		result.append(node)
	for child in node.get_children():
		_collect(child, result)

func _refresh_cache():
	if OS.get_ticks_msec() < cache_at:
		return
	cache_at = OS.get_ticks_msec() + 400
	cached_devices = []
	cached_items = []
	var level = api.current_level()
	if not is_instance_valid(level):
		return
	for path in ["YSort/Devices", "YSort/Other", "YSort/Outdoor"]:
		var branch = level.get_node_or_null(path)
		if branch != null:
			_collect(branch, cached_devices)
	var items_node = level.get_node_or_null("YSort/Items")
	if items_node != null:
		_collect(items_node, cached_items)
	for item in cached_items:
		if not item in cached_devices:
			cached_devices.append(item)

func devices():
	_refresh_cache()
	var result = []
	for device in cached_devices:
		if is_instance_valid(device) and not device.is_queued_for_deletion() and not in_hands(device):
			result.append(device)
	return result

func items():
	_refresh_cache()
	var result = []
	for item in cached_items:
		if is_instance_valid(item) and not item.is_queued_for_deletion() and not in_hands(item):
			result.append(item)
	return result

func in_hands(item):
	var node = item
	while is_instance_valid(node):
		if node.name == "Weapon_note":
			return true
		node = node.get_parent()
	return false

func _physics_process(delta):
	if not active():
		# The native RigidBody keeps its last velocity until explicitly stopped.
		# Do this in physics too, including quick menu-to-layout transitions.
		for worker in workers.values():
			worker.actor.suspended = true
			if is_instance_valid(worker.actor.body) and worker.actor.body.is_inside_tree():
				worker.actor.body.set_motion(Vector2.ZERO, 0.0)
		return
	suspended = false
	for worker in workers.values():
		if is_instance_valid(worker.actor.body):
			worker.actor.suspended = false
			worker.actor.update(delta)

func _sync_crowd_collisions():
	if OS.get_ticks_msec() < crowd_at:
		return
	crowd_at = OS.get_ticks_msec() + 350
	for group in ["NPC", "Couriers"]:
		for passer in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(passer) or not passer is PhysicsBody2D or not passer.is_inside_tree():
				continue
			for worker in workers.values():
				var body = worker.actor.body
				if not is_instance_valid(body) or not body.is_inside_tree() or body == passer:
					continue
				var key = str(body.get_instance_id()) + ":" + str(passer.get_instance_id())
				if crowd_pairs.has(key):
					continue
				body.add_collision_exception_with(passer)
				passer.add_collision_exception_with(body)
				crowd_pairs[key] = true

func _process(delta):
	tick += delta
	if tick < 0.12:
		return
	var elapsed = tick
	tick = 0.0
	entry_button.visible = is_run() and not game.GameUI.DayEnd and not get_tree().paused
	if not is_run():
		if not workers.empty():
			_despawn()
		return
	_ensure_state()
	_spawn_missing()
	_sync_crowd_collisions()
	if not active():
		if not suspended:
			if get_tree().paused:
				_suspend_workers()
			else:
				_quiesce()
	else:
		suspended = false
		for worker in workers.values():
			if is_instance_valid(worker.actor.body):
				worker.actor.suspended = false
				worker.role.tick(elapsed)
				if is_instance_valid(worker.actor.body.talent_label):
					worker.actor.body.talent_label.text = worker.actor.profile.name + "\n" + str(worker.role.status)
	if panel.visible and OS.get_ticks_msec() >= refresh_at:
		refresh_at = OS.get_ticks_msec() + 1000
		_update_summary()

func _input(event):
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.scancode == KEY_F3 and is_run():
		if panel.visible:
			close_market()
		elif not get_tree().paused:
			open_market()
		get_tree().set_input_as_handled()
	elif event.scancode == KEY_ESCAPE and panel.visible:
		if ui.debug_overlay.visible:
			ui.close_debug_editor()
		else:
			close_market()
		get_tree().set_input_as_handled()

func _build_ui():
	portraits = preload("res://ftc_mods/ftc.talent_market/Visuals/PortraitFactory.gd").new(self)
	portrait_cache = portraits.portrait_cache
	portrait_order = portraits.portrait_order
	ui = preload("res://ftc_mods/ftc.talent_market/UI/TalentMarketPanel.gd").new(self, portraits)
	add_child(ui)
	panel = ui.panel
	entry_button = ui.entry_button
	tabs = ui.tabs
	candidate_list = ui.candidate_list
	staff_list = ui.staff_list
	summary = ui.summary
	message = ui.message
	font = ui.font

func _appearance_catalog():
	return portraits._appearance_catalog()

func _validate_appearance(person):
	portraits._validate_appearance(person)

func _portrait_visual(person):
	return portraits._portrait_visual(person)

func _render_lists():
	ui.render()

func _update_summary():
	ui.update_summary()

func open_market():
	if not is_run() or panel.visible or get_tree().paused:
		return
	_ensure_state()
	was_paused = get_tree().paused
	controls_were_enabled = game.Con.is_processing_input()
	game.Con.set_process_input(false)
	controls_owned = true
	get_tree().paused = true
	_suspend_workers()
	_render_lists()
	ui.reveal()

func close_market():
	if not panel.visible:
		return
	ui.close_debug_editor()
	panel.hide()
	get_tree().paused = was_paused
	if controls_owned:
		game.Con.set_process_input(controls_were_enabled)
		controls_owned = false

func _say(text, success = false):
	message.text = text
	return success

func _exit_tree():
	_despawn()
	if portraits != null:
		portraits.cleanup()
	if controls_owned:
		game.Con.set_process_input(controls_were_enabled)
		get_tree().paused = was_paused
