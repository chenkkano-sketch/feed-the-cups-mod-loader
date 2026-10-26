extends Reference

const Navigator = preload("res://ftc_mods/ftc.talent_market/Navigation/Navigator.gd")
const BodyScript = preload("res://ftc_mods/ftc.talent_market/Actors/StaffBody.gd")
const ControlScript = preload("res://ftc_mods/ftc.talent_market/Actors/StaffControl.gd")
const AppearanceRules = preload("res://ftc_mods/ftc.talent_market/TalentRules.gd")
const SkillCatalog = preload("res://ftc_mods/ftc.talent_market/Skills/SkillCatalog.gd")

var body
var profile = {}
var level
var navigation
var route = []
var destination = Vector2.ZERO
var target_device
var device_destination_valid = false
var arrived = false
var last_error = ""
var repath_time = 0.0
var stuck_time = 0.0
var last_position = Vector2.ZERO
var suspended = false
var path_blocked = false

func _init(data = {}, room = null):
	if room != null:
		spawn(data, room)

func spawn(data, room):
	if is_instance_valid(body):
		return false
	if not is_instance_valid(room) or not room.is_inside_tree() or SdkManager.is_multiplay or SdkManager.lobby_player_num > 1:
		return false
	profile = data.duplicate(true)
	AppearanceRules.apply_appearance(profile)
	level = room
	navigation = Navigator.new(room)
	var packed = load("res://TscnAndGd/Main/Player/NewPlayer.tscn")
	if packed == null:
		last_error = "无法读取店员场景"
		return false
	body = packed.instance()
	body.set_script(BodyScript)
	body.get_node("LogicNode/Control").set_script(ControlScript)
	body.name = "Talent_" + str(profile.get("id", body.get_instance_id()))
	body.cur_Player = -1000 - int(body.get_instance_id() % 1000000)
	body.talent_profile = profile
	body.talent_role = "employee"
	body.IsStaff = true
	body.mode = RigidBody2D.MODE_CHARACTER
	body.gravity_scale = 0
	body.can_sleep = false
	body.add_to_group("FTC_TALENT_STAFF")
	var parent = room.get_node_or_null("YSort/Players")
	if parent == null:
		parent = room.get_node_or_null("YSort")
	if parent == null:
		body.free()
		body = null
		return false
	var start = Vector2.ZERO
	if is_instance_valid(GameLogic.player_1P):
		start = GameLogic.player_1P.global_position
	var point = navigation.nearest(start, 250.0)
	if point == null:
		body.free()
		body = null
		last_error = "店内导航尚未就绪"
		return false
	# Spread new employees over reachable nearby tiles instead of stacking
	# every label/body on the human player's spawn point.
	var directions = [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN, Vector2.UP]
	var offset = int(abs(int(str(profile.get("id", "0")).hash()))) % 4
	for step in range(4):
		var candidate = navigation.nearest(point + directions[(offset + step) % 4] * 100.0, 35.0)
		if candidate != null and not navigation.path(point, candidate).empty():
			point = candidate
			break
	body.position = parent.to_local(point)
	parent.add_child(body)
	navigation.set_actor(body)
	if is_instance_valid(GameLogic.player_1P):
		body.add_collision_exception_with(GameLogic.player_1P)
		GameLogic.player_1P.add_collision_exception_with(body)
	for other in body.get_tree().get_nodes_in_group("FTC_TALENT_STAFF"):
		if other != body and other is PhysicsBody2D:
			body.add_collision_exception_with(other)
			other.add_collision_exception_with(body)
	last_position = body.global_position
	destination = last_position
	arrived = true
	return is_instance_valid(body.AVATAR)

func held():
	if not is_instance_valid(body) or not body.Con.IsHold:
		return null
	var item = instance_from_id(body.Con.HoldInsId)
	if is_instance_valid(item) and not item.is_queued_for_deletion():
		return item
	body.Con.IsHold = false
	body.Con.HoldInsId = 0
	body.Con.HoldObj = null
	return null

func move_to(point):
	target_device = null
	device_destination_valid = false
	return _move_to_point(point)

func _move_to_point(point):
	if not is_instance_valid(body):
		return false
	if body.global_position.distance_to(point) <= 14.0:
		path_blocked = false
		_stop_motion()
		arrived = true
		return true
	if destination.distance_to(point) > 8.0 or (route.empty() and (repath_time <= 0.0 or path_blocked)):
		destination = point
		_repath()
	arrived = false
	return false

func move_to_device(device):
	if not is_instance_valid(body) or not is_instance_valid(device) or not device.is_inside_tree() or device.is_queued_for_deletion():
		last_error = "设备已不存在"
		return false
	if target_device != device or repath_time <= 0.0 or path_blocked:
		target_device = device
		device_destination_valid = false
		var point = navigation.approach(device, body.global_position)
		if point == null:
			path_blocked = true
			last_error = navigation.last_error
			route.clear()
			_stop_motion()
			repath_time = 0.8
			return false
		device_destination_valid = true
		path_blocked = false
		if destination.distance_to(point) > 8.0 or route.empty():
			destination = point
			_repath()
		else:
			repath_time = 0.8
	if not device_destination_valid:
		return false
	var result = _move_to_point(destination)
	if result:
		var fixture = navigation.anchor(device)
		body.cur_RayObj = fixture
		body.cur_TouchObj = fixture
		body.face_position(device.global_position)
	return result

func is_arrived():
	return arrived

func update(delta):
	if not is_instance_valid(body):
		return
	if suspended:
		body.talent_aura_active = false
		_stop_motion()
		return
	body.talent_aura_active = bool(profile.get("enabled", true))
	body.talent_work_duration = work_duration()
	body.tick_actions(delta)
	repath_time = max(0.0, repath_time - delta)
	if body.talent_busy_time > 0.0 or route.empty():
		_stop_motion()
		return
	while not route.empty() and body.global_position.distance_to(route[0]) <= 14.0:
		route.pop_front()
	if route.empty():
		arrived = body.global_position.distance_to(destination) <= 22.0
		_stop_motion()
		return
	var distance = body.global_position.distance_to(last_position)
	if distance < 1.0:
		stuck_time += delta
	else:
		stuck_time = 0.0
	last_position = body.global_position
	if stuck_time > 1.2:
		stuck_time = 0.0
		_repath()
		if route.empty():
			_stop_motion()
			return
	var direction = body.global_position.direction_to(route[0])
	# Check the remaining segment every physics frame. A door may close after
	# planning, and the off-grid first segment must not bypass the door check.
	if not navigation.segment_clear(body.global_position, route[0]):
		_repath()
		if route.empty() or not navigation.segment_clear(body.global_position, route[0]):
			_stop_motion()
			return
		direction = body.global_position.direction_to(route[0])
	var speed = 210.0 * float(SkillCatalog.modifiers(profile).move_speed)
	if held() != null:
		speed *= clamp(float(body.Stat.Ins_CarryMult), 0.5, 1.0)
	body.set_motion(direction, min(speed, body.global_position.distance_to(route[0]) / max(delta, 0.005)))

func _repath():
	route = navigation.path(body.global_position, destination)
	path_blocked = route.empty()
	repath_time = 0.8
	last_error = navigation.last_error
	arrived = false

func _stop_motion():
	if is_instance_valid(body):
		if body.is_inside_tree():
			body.set_motion(Vector2.ZERO, 0.0)
		else:
			body.talent_velocity = Vector2.ZERO

func interact(device, button = 0):
	if not is_instance_valid(device) or not device.is_inside_tree() or device.is_queued_for_deletion() or not is_instance_valid(body) or suspended:
		return null
	var fixture = navigation.anchor(device)
	if fixture == null or body.global_position.distance_to(fixture.global_position) > 165.0:
		last_error = "尚未走到设备旁"
		return null
	if str(device.get("FuncType")) == "Box" and device.get("IsOpen") != true and not has_skill("stock_advanced"):
		var entries = device.get("ItemOBJ_Array")
		var waste_only = has_skill("trash_advanced") and entries is Array and entries.empty() and device.get("HasItem") != true
		if button == 2 or not waste_only:
			return null
	body.cur_RayObj = fixture
	body.cur_TouchObj = fixture
	body.face_position(device.global_position)
	return GameLogic.Device.Call_CheckLogic(button, body, device)

func begin_work(device, duration = 1.0):
	if is_instance_valid(body):
		body.talent_work_duration = work_duration()
		body.call_DeviceAni(device, duration)

func end_work():
	if is_instance_valid(body):
		body.finish_actions()

func has_skill(id):
	return SkillCatalog.has_skill(profile, str(id))

func can_take_source(source):
	var target = source.get("target")
	# Only advanced stocking opens shipping packages; refilling cups alone
	# never grants permission to open sealed deliveries.
	return not is_instance_valid(target) or str(target.get("FuncType")) != "Box" or target.get("IsOpen") == true or has_skill("stock_advanced")

func native_work_duration(category = "hand"):
	var fields = {"hand": "HandWorkLV", "order": "OrderLV", "clean": "CleanLV", "repair": "FixLV", "machine": "MachineWorkLV"}
	var human = GameLogic.player_1P
	if not is_instance_valid(human) or human.get("Stat") == null:
		return 1.0
	var value = human.Stat.get(fields.get(str(category), "HandWorkLV"))
	# Native player work statistics use 3 as their normal baseline. Read the
	# current effective value every time; no previous profession level survives.
	return 3.0 / max(0.1, float(value)) if typeof(value) in [TYPE_INT, TYPE_REAL] else 1.0

func work_duration(base = 1.0, category = "hand"):
	var duration = native_work_duration(category) * float(AppearanceRules.duration_star(profile.get("stars", 1))) * float(SkillCatalog.modifiers(profile).work_duration)
	var strongest = 1.0
	if is_instance_valid(body) and body.is_inside_tree() and not suspended:
		var market = body.get_node_or_null("/root/TalentMarket")
		if market != null and market.active():
			for colleague in body.get_tree().get_nodes_in_group("FTC_TALENT_STAFF"):
				if colleague == body or not is_instance_valid(colleague) or colleague.is_queued_for_deletion() or not colleague.is_inside_tree() or colleague.get("talent_aura_active") != true:
					continue
				var other = colleague.get("talent_profile")
				if not other is Dictionary or not bool(other.get("enabled", true)):
					continue
				var effect = SkillCatalog.modifiers(other)
				var radius = float(effect.aura_radius)
				if radius > 0 and body.global_position.distance_squared_to(colleague.global_position) <= radius * radius:
					strongest = min(strongest, float(effect.aura_work_duration))
	# Each neighbour contributes its own intrinsic modifier only. This cannot
	# recursively amplify an aura or accumulate stale effects after departure.
	return max(0.1, float(base) * duration * strongest)

func cancel_action():
	route.clear()
	target_device = null
	device_destination_valid = false
	arrived = false
	_stop_motion()
	if not is_instance_valid(body):
		return
	body.talent_aura_active = false
	if not body.is_inside_tree():
		body.talent_jobs.clear()
		body.talent_busy_time = 0.0
		return
	var item = held()
	if is_instance_valid(item):
		for method in ["call_WORKING_end", "call_STIR_end", "call_SHAKE_end", "call_SQUEEZE_end", "call_Shovel_end"]:
			if item.has_method(method):
				item.call(method, body)
	body.finish_actions()

func drop_held(ground_point = null):
	# Native call_PutOnGround defers add_child until the next frame. The save
	# bridge needs a synchronous reparent so native _item_save sees the object.
	if not is_instance_valid(body) or not body.is_inside_tree():
		return null
	var item = held()
	if not is_instance_valid(item):
		return null
	if not is_instance_valid(level) or not level.is_inside_tree() or not level.has_node("YSort/Items"):
		return null
	var items = level.get_node("YSort/Items")
	var point = body.global_position if ground_point == null else ground_point
	if is_instance_valid(item.get_parent()):
		item.get_parent().remove_child(item)
	items.add_child(item)
	item.position = items.to_local(point)
	item.Holding = false
	item.Holder = null
	if item.has_method("call_Collision_Switch"):
		item.call_deferred("call_Collision_Switch", true)
	body.Stat.call_carry_off()
	return item

func cleanup():
	cancel_action()
	if not is_instance_valid(body):
		return
	drop_held()
	body.queue_free()
	body = null
	route.clear()
