extends Node

var api
var carry
var session
var player_carries = {}
var preparing = false
var navigation_pending = false
var navigation_revision = 0
var panel
var carry_button
var notice
var tick = 0.0
var notice_until = 0

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	carry = preload("res://ftc_mods/ftc.furniture_carry/FurnitureCarry.gd").new(self)
	session = preload("res://ftc_mods/ftc.furniture_carry/FurnitureSession.gd").new(self)
	GameLogic.connect("DayStart", self, "_day_start")
	GameLogic.connect("OpenStore", self, "_opened")
	SdkManager.connect("DelNetPlayer", self, "_player_departed")
	_build_ui()

func _player_departed(id):
	if SdkManager.is_multiplay:
		session.departed(int(id))

func _offline():
	return api.offline()

func is_run():
	return GameLogic.LoadingUI.IsLevel and is_instance_valid(carry.level) and carry.level == get_tree().root.get_node_or_null("Level") and is_instance_valid(GameLogic.player_1P)

func coop_session():
	return session if SdkManager.is_multiplay else null

func is_preparing():
	return preparing and is_run() and not GameLogic.GameUI.DayEnd and not GameLogic.GameUI.Is_Open and not GameLogic._DayOver_Bool

func _day_start():
	preparing = true
	if is_run():
		_refresh_navigation(carry.level)

func _opened():
	preparing = false
	panel.hide()
	notice.text = ""

func toggle():
	if SdkManager.is_multiplay:
		session.request_toggle()
		return
	carry.set_enabled(not carry.enabled)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_F2 and is_run():
		toggle()
		get_tree().set_input_as_handled()

func _process(delta):
	session.tick(delta)
	if notice_until > 0 and OS.get_ticks_msec() > notice_until:
		notice.text = ""
		notice_until = 0
	tick += delta
	if tick < 0.2:
		return
	tick = 0.0
	panel.hide()
	if not is_run():
		if carry.enabled:
			carry.set_enabled(false)
		notice.text = ""
		return
	if not is_preparing():
		if carry.enabled:
			carry.set_enabled(false)
		return
	if get_tree().paused:
		return
	# Purchasing and animations continue independently of the frozen business clock.
	if not SdkManager.is_multiplay or session.authority():
		GameLogic.Buy.call_check(GameLogic.GameUI.CurTime + 1.0)
	var rent = api.service("ftc.rent_mode", "mode")
	carry_button.set_active(carry.enabled)
	carry_button.hint_tooltip = "F2 开关自己的搬运模式；联机玩家可同时搬运。"
	_sync_hud(rent)

func _build_ui():
	var font = DynamicFont.new()
	font.font_data = load("res://Language/Fonts/simhei.ttf")
	font.size = 20
	panel = VBoxContainer.new()
	panel.name = "FurnitureCarryHUD"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_constant_override("separation", 5)
	GameLogic.GameUI.get_node("RightUp").add_child(panel)
	carry_button = preload("res://ftc_mods/ftc.furniture_carry/CarryIcon.gd").new()
	carry_button.connect("pressed", self, "toggle")
	panel.add_child(carry_button)
	panel.hide()
	var canvas = CanvasLayer.new()
	canvas.layer = 130
	add_child(canvas)
	notice = Label.new()
	notice.add_font_override("font", font)
	notice.add_color_override("font_color", Color(1, 0.87, 0.4))
	notice.rect_position = Vector2(460, 165)
	notice.rect_size = Vector2(1100, 110)
	notice.autowrap = true
	canvas.add_child(notice)

func _sync_hud(rent):
	var ui = GameLogic.GameUI
	var right = ui.get_node("RightUp")
	var money = right.get_node("InfoNode/money")
	var bottom = money.rect_global_position.y
	for row in money.get_children():
		if row is Control and row.visible:
			bottom = max(bottom, row.get_global_rect().end.y)
	if rent != null and rent.is_run():
		if not rent.bar.visible:
			return
		bottom = max(bottom, rent.bar.get_global_rect().end.y)
	panel.rect_size = panel.get_combined_minimum_size()
	panel.rect_position = Vector2(-34 - panel.rect_size.x, bottom - right.rect_global_position.y + 10)
	panel.visible = right.is_visible_in_tree() and not ui.OrderNode.cur_used

func _start_business():
	if not is_preparing() or get_tree().paused:
		return
	if not can_open():
		return
	# Keep the campaign's native early-opening rewards and duration.
	GameLogic.GameUI.call_Open()

func can_open():
	if not is_run():
		return true
	if SdkManager.is_multiplay and not session.modes.empty():
		_message("请所有搬运中的玩家按 F2 退出后，再开始营业。")
		return false
	if carry.enabled:
		_message("请先按 F2 退出搬运模式，再开始营业。")
		return false
	if navigation_pending:
		_message("正在更新布局寻路，请稍候再开店。")
		return false
	if is_preparing() and GameLogic.player_1P.Con.IsHold:
		_message("请先放下手上的物品，再开始营业。")
		return false
	return true

func _save_now():
	if not is_preparing() or get_tree().paused:
		return
	if SdkManager.is_multiplay and not session.authority():
		return
	for worker in player_carries.values():
		if is_instance_valid(worker.held):
			return
	if is_instance_valid(carry.held):
		return
	if GameLogic.player_1P.Con.IsHold:
		return
	var rent = api.service("ftc.rent_mode", "mode")
	if rent != null and rent.is_run():
		rent._save_now()
		return
	carry.level._dev_save()
	carry.level._item_save()
	GameLogic.call_save()

func can_control(actor):
	return actor == GameLogic.player_1P

func coop_control(actor, button, value):
	if not session.modes.has(int(actor.get("cur_Player"))):
		return false
	if actor != GameLogic.player_1P:
		# Network button mirroring must not perform a second local pickup.
		return button in ["A", "B", "X", "Y", "L1", "L2", "L3", "R1", "R2", "R3", "BACK"]
	return carry.handle_control(actor, button, value)

func find_player(id):
	if not is_instance_valid(carry.level):
		return null
	for actor in carry.level.get_node("YSort/Players").get_children():
		if int(actor.get("cur_Player")) == id:
			return actor
	return null

func carry_for(id):
	if not SdkManager.is_multiplay or id == int(SdkManager.user_id):
		return carry
	if not player_carries.has(id):
		var worker = preload("res://ftc_mods/ftc.furniture_carry/FurnitureCarry.gd").new(self)
		worker.level = carry.level
		worker.original_slots = carry.original_slots
		worker.npc_cells = carry.npc_cells
		player_carries[id] = worker
	return player_carries[id]

func set_player_enabled(id, value):
	var worker = carry_for(id)
	if value:
		if worker == carry and not worker.enabled:
			if not worker.set_enabled(true):
				return false
		else:
			worker.enabled = true
		return true
	if is_instance_valid(worker.held):
		worker.cancel(false)
	worker.enabled = false
	worker.pressed = false
	if is_instance_valid(worker.guide):
		worker.guide.queue_free()
		worker.guide = null
	return true

func reset_carries():
	for id in player_carries.keys():
		set_player_enabled(id, false)
	player_carries.clear()
	if is_instance_valid(carry.held):
		carry.cancel(false)
	carry.enabled = false
	carry.pressed = false
	if is_instance_valid(carry.guide):
		carry.guide.queue_free()
		carry.guide = null

func layout_snapshot():
	var positions = {}
	var holds = []
	for fixture in carry.level.get_node("YSort/Devices").get_children():
		if fixture is Node2D:
			positions[fixture.name] = fixture.position
	if is_instance_valid(carry.held):
		holds.append({"player": int(carry.player.cur_Player), "object": carry.held.name, "origin": carry.original_transform.origin})
	for worker in player_carries.values():
		if is_instance_valid(worker.held) and is_instance_valid(worker.player):
			holds.append({"player": int(worker.player.cur_Player), "object": worker.held.name, "origin": worker.original_transform.origin})
	return {"positions": positions, "holds": holds}

func apply_snapshot(layout):
	if not layout is Dictionary or not layout.get("positions") is Dictionary or not layout.get("holds") is Array or not is_run():
		return false
	if not layout.holds.empty() and not is_preparing():
		return false
	for record in layout.holds:
		if not record is Dictionary or not is_instance_valid(find_player(int(record.get("player", 0)))):
			return false
	reset_carries()
	var devices = carry.level.get_node("YSort/Devices")
	for name in layout.positions:
		var fixture = devices.get_node_or_null(str(name))
		if is_instance_valid(fixture) and layout.positions[name] is Vector2:
			fixture.position = layout.positions[name]
	for id in session.modes.keys():
		if not set_player_enabled(int(id), true):
			return false
	for record in layout.holds:
		var actor = find_player(int(record.player))
		var fixture = devices.get_node_or_null(str(record.object))
		var worker = carry_for(int(record.player))
		worker.enabled = true
		if is_instance_valid(fixture) and record.get("origin") is Vector2:
			fixture.position = record.origin
		if not is_instance_valid(fixture) or not worker.pick(actor, fixture, false, true):
			return false
	_refresh_navigation(carry.level)
	return true

func apply_action(action, synchronized):
	if not is_preparing() or not action is Dictionary:
		return false
	var id = int(action.get("player", 0))
	var actor = find_player(id)
	if not is_instance_valid(actor):
		return false
	var worker = carry_for(id)
	if not worker.enabled:
		return false
	var kind = str(action.get("kind", ""))
	if kind == "pick":
		var fixture = carry.level.get_node("YSort/Devices").get_node_or_null(str(action.get("object", "")))
		if not is_instance_valid(fixture):
			return false
		if not synchronized and actor.global_position.distance_to(fixture.global_position) > 240:
			return false
		return worker.pick(actor, fixture, false, true)
	if not is_instance_valid(worker.held) or worker.held.name != str(action.get("held", action.get("object", ""))):
		return false
	if kind == "release" and action.get("position") is Vector2:
		var cell = worker.cell_at(action.position)
		if worker.fixture_at(cell) != null:
			return false
		return worker.place(cell, false, synchronized, action.position)
	if kind == "swap":
		var target = carry.level.get_node("YSort/Devices").get_node_or_null(str(action.get("object", "")))
		if not is_instance_valid(target):
			return false
		if not synchronized and actor.global_position.distance_to(target.global_position) > 240:
			return false
		return worker.swap(actor, target, synchronized, action.get("position"), action.get("vacant"))
	return false

func completed_action(action):
	var result = action.duplicate(true)
	var worker = carry_for(int(action.player))
	if action.kind == "release":
		var fixture = carry.level.get_node("YSort/Devices").get_node_or_null(str(action.object))
		if is_instance_valid(fixture):
			result.position = fixture.position
	elif action.kind == "swap" and is_instance_valid(worker.held):
		result.vacant = worker.original_transform.origin
		var fixture = carry.level.get_node("YSort/Devices").get_node_or_null(str(action.get("held", "")))
		if is_instance_valid(fixture):
			result.position = fixture.position
	return result

func coop_picked(path, actor):
	if SdkManager.is_multiplay:
		session.local_action({"kind": "pick", "object": str(path).get_file()})

func coop_released(name, actor, position):
	if SdkManager.is_multiplay and is_instance_valid(actor):
		session.local_action({"kind": "release", "object": str(name), "held": str(name), "position": position})

func coop_swapped(name, actor, position, vacant, previous):
	if SdkManager.is_multiplay:
		session.local_action({"kind": "swap", "object": str(name), "held": previous, "position": position, "vacant": vacant})

func _refresh_order_points(node):
	if node.has_method("call_OrderPoint"):
		node.call_OrderPoint()
	for child in node.get_children():
		_refresh_order_points(child)

func _refresh_navigation(level):
	navigation_revision += 1
	var revision = navigation_revision
	navigation_pending = true
	yield(get_tree().create_timer(0.18), "timeout")
	if revision != navigation_revision:
		return
	if not is_instance_valid(level) or level != carry.level or not is_preparing():
		navigation_pending = false
		return
	var astar = GameLogic.Astar
	carry.apply_navigation()
	if SdkManager.is_multiplay and not session.authority():
		navigation_pending = false
		return
	astar.call_Path2D_init()
	astar.AStar_NPC_Wait.clear()
	astar.call_TMap_init(level.get_node("MapNode/Floor"))
	astar.call_TMap_init_NPC(level.get_node("MapNode/NPCFloor"))
	astar.call_TMap_Street_init(level.get_node("MapNode/StreetMain"), level.get_node("MapNode/Street"))
	if level.has_node("MapNode/Leave"):
		astar.call_Leave_Init(level.get_node("MapNode/Leave"))
	astar.connect_init()
	for device in level.get_node("YSort/Devices").get_children():
		_refresh_order_points(device)
		if device.has_method("call_connect_check"):
			device.call_connect_check()
	if is_instance_valid(GameLogic.Staff.OrderTab_OBJ):
		GameLogic.Staff.call_OrderTab_init(GameLogic.Staff.OrderTab_OBJ)
	navigation_pending = false

func _message(text):
	var rent = api.service("ftc.rent_mode", "mode")
	if rent != null and rent.is_run():
		notice.text = ""
		rent._message(text)
		return
	notice.text = text
	notice_until = OS.get_ticks_msec() + 6500
