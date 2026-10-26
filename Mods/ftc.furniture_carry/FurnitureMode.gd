extends Node

var api
var carry
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
	GameLogic.connect("DayStart", self, "_day_start")
	GameLogic.connect("OpenStore", self, "_opened")
	_build_ui()

func _offline():
	return api.offline()

func is_run():
	return (_offline() or coop_session() != null) and GameLogic.LoadingUI.IsLevel and is_instance_valid(carry.level) and carry.level == get_tree().root.get_node_or_null("Level") and is_instance_valid(GameLogic.player_1P)

func coop_session():
	var rent = api.service("ftc.rent_mode", "mode")
	return rent.coop if SdkManager.is_multiplay and rent != null and rent.is_run() else null

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
	var session = coop_session()
	if session != null:
		session.request_editor()
		return
	carry.set_enabled(not carry.enabled)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_F2 and is_run():
		toggle()
		get_tree().set_input_as_handled()

func _process(delta):
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
	var session = coop_session()
	if session == null or session.authority():
		GameLogic.Buy.call_check(GameLogic.GameUI.CurTime + 1.0)
	var rent = api.service("ftc.rent_mode", "mode")
	carry_button.set_active(carry.enabled and (session == null or session.editor == int(SdkManager.user_id)))
	if session != null and session.editor != 0 and session.editor != int(SdkManager.user_id):
		carry_button.hint_tooltip = "其他玩家正在实时搬运，等待其按 F2 退出。"
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
	var session = coop_session()
	if session != null and session.editor != 0:
		_message("请搬运中的玩家按 F2 退出后，再开始营业。")
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
	var session = coop_session()
	if session != null and not session.authority():
		return
	carry.cancel()
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
	var session = coop_session()
	return actor == GameLogic.player_1P if session == null else session.authority() and int(actor.get("cur_Player")) == session.editor

func coop_control(actor, button, value):
	var session = coop_session()
	if session == null or session.editor == 0 or int(actor.get("cur_Player")) != session.editor:
		return false
	if not session.authority():
		# Remote button mirroring must never execute the same action twice.
		return button in ["A", "B", "X", "Y", "L1", "L2", "L3", "R1", "R2", "R3", "BACK"]
	return carry.handle_control(actor, button, value)

func coop_editor(id):
	carry.cancel()
	carry.enabled = id != 0
	carry.pressed = false
	if is_instance_valid(carry.guide):
		carry.guide.queue_free()
		carry.guide = null
	if id == int(SdkManager.user_id) and id != 0:
		carry.guide = load("res://ftc_mods/ftc.furniture_carry/LayoutGuide.gd").new()
		carry.guide.z_index = -1
		carry.guide.cells = carry.level.get_node("MapNode/Floor").get_used_cells()
		for cell in carry.original_slots:
			if not cell in carry.guide.cells:
				carry.guide.cells.append(cell)
		for cell in carry.npc_cells:
			if not cell in carry.guide.cells:
				carry.guide.cells.append(cell)
		carry.level.add_child(carry.guide)
		_message("实时搬运已开启：交互拿起、放下或交换家具，F2 退出；房主保存布局。")

func coop_action(packet):
	var action = str(packet.get("action", ""))
	var session = coop_session()
	if session == null:
		return
	if action == "pick":
		var actor = session.find_player(int(packet.player))
		var fixture = get_node_or_null(NodePath(packet.path))
		if is_instance_valid(actor) and is_instance_valid(fixture):
			carry.pick(actor, fixture)
	elif action == "swap" and is_instance_valid(carry.held):
		var actor = session.find_player(int(packet.player))
		var fixture = get_node_or_null(NodePath(packet.path))
		if is_instance_valid(actor) and is_instance_valid(fixture) and packet.get("position") is Vector2 and packet.get("vacant") is Vector2:
			carry.swap(actor, fixture, true, packet.position, packet.vacant)
	elif action == "release" and is_instance_valid(carry.held):
		var fixture = carry.held
		carry._release(carry.level.get_node("YSort/Devices"), packet.position, false)
		_refresh_order_points(fixture)
		_refresh_navigation(carry.level)

func coop_picked(path, actor):
	var session = coop_session()
	if session != null and session.authority() and not session.applying:
		session.notify("carry", {"action": "pick", "path": str(path), "player": int(actor.cur_Player)})

func coop_released(position):
	var session = coop_session()
	if session != null and session.authority() and not session.applying:
		session.notify("carry", {"action": "release", "position": position})

func coop_swapped(path, actor, position, vacant):
	var session = coop_session()
	if session != null and session.authority() and not session.applying:
		session.notify("carry", {"action": "swap", "path": path, "player": int(actor.cur_Player), "position": position, "vacant": vacant})

func _refresh_order_points(node):
	if node.has_method("call_OrderPoint"):
		node.call_OrderPoint()
	for child in node.get_children():
		_refresh_order_points(child)

func _refresh_navigation(level):
	navigation_revision += 1
	var revision = navigation_revision
	navigation_pending = true
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	if revision != navigation_revision:
		return
	if not is_instance_valid(level) or level != carry.level or not is_preparing():
		navigation_pending = false
		return
	var astar = GameLogic.Astar
	carry.apply_navigation()
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
