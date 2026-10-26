extends "res://TscnAndGd/Main/Player/Player.gd"

# A separate native Player body provides the complete device ABI. Its identity
# is outside the human player slots; native cup/selection logic therefore never
# changes player 1's held cup or selected order.
enum BEHAVIOR { IDLE, MOVE, STUDY, REST, EAT, DRINK, ORDER, CARRY, BREW, MAKE, PICK, CLEAN, WORK, WORK_ON, WORK_OFF_READY, WORK_OFF, CALL, SAMPLE, INTERVIEW, IDLE_MOVE, READY, WC, WASH, FOLLOW }
var behavior = BEHAVIOR.IDLE
var Lv_Order = 1
var talent_velocity = Vector2.ZERO
var talent_profile = {}
var talent_jobs = []
var talent_busy_time = 0.0
var talent_role = ""
var talent_label
var talent_work_duration = 1.0
var talent_aura_active = false

func _ready():
	# Godot also runs the native base readiness. Disable inherited human input,
	# camera, timers and HUD behavior here, then configure this NPC's own stats.
	IsStaff = true
	IsCourier = false
	NoPress = false
	HighPress = false
	cur_Pressure = 0
	cur_PressureMax = 100
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	_stop_scene_timers(self)
	CameraNode.current = false
	CameraNode.set_process(false)
	FaceRay.enabled = false
	if has_node("Player/QTE"):
		get_node("Player/QTE").hide()
	if has_node("Player/PressureNode"):
		get_node("Player/PressureNode").hide()
	if has_node("Player/NameLabel/LatencyLabel"):
		get_node("Player/NameLabel/LatencyLabel").hide()
	var avatar = str(talent_profile.get("avatar", "0"))
	if not GameLogic.Config.PlayerConfig.has(avatar):
		var keys = GameLogic.Config.PlayerConfig.keys()
		if keys.empty():
			return
		keys.sort()
		avatar = str(keys[0])
	talent_profile.avatar = int(avatar)
	# Negative player identity and all eight explicit outfit fields prevent
	# native equipment initialization from reading or writing a human's outfit.
	var outfit = preload("res://ftc_mods/ftc.talent_market/TalentRules.gd").appearance(talent_profile)
	call_new_Avatar(int(avatar), outfit.fashion)
	configure_stats()
	if is_instance_valid(AVATAR):
		_settle_outfit(AVATAR)
		var skin = str(outfit.skin)
		var head_type = AVATAR.get_node_or_null("HeadType")
		if head_type != null and not head_type.has_animation(skin):
			skin = "1"
		talent_profile.skin = int(skin)
		AVATAR.call_HeadType(skin)
		if head_type != null and head_type.has_animation(skin):
			head_type.seek(0.0, true)
	NameLabel.text = str(talent_profile.get("name", "店员"))
	NameLabel.visible = false
	NameLabel.modulate = Color(1, 1, 1, 1)
	if NameLabel.has_node("Ani"):
		NameLabel.get_node("Ani").stop()
	talent_label = Label.new()
	talent_label.name = "TalentStatus"
	talent_label.rect_position = Vector2(-155, -228)
	talent_label.rect_size = Vector2(310, 68)
	talent_label.align = Label.ALIGN_CENTER
	talent_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	talent_label.add_font_override("font", load("res://Language/Fonts/Base_s_outline.tres"))
	talent_label.add_color_override("font_color", Color(0.65, 0.94, 1.0))
	AvatarNode.add_child(talent_label)
	call_StatChange()

func _settle_outfit(node):
	# Hiring is allowed while the market pauses the room. Commit only native
	# costume visual tracks now, so a new NPC already matches its portrait.
	if node is AnimationPlayer and node.name in preload("res://ftc_mods/ftc.talent_market/TalentRules.gd").OUTFIT_ANIMATION_NAMES:
		var selected = str(node.assigned_animation)
		if selected != "" and node.has_animation(selected):
			node.seek(0.0, true)
	for child in node.get_children():
		_settle_outfit(child)

func _stop_scene_timers(node):
	for child in node.get_children():
		if child is Timer:
			child.stop()
		_stop_scene_timers(child)

func configure_stats():
	# The native ABI still requires numeric fields, but no former profession or
	# hidden four-stat level may alter behaviour. Stars/passives time our actions.
	Stat.Skills = []
	Stat.MoveSpeed = 30.0
	var human = GameLogic.player_1P
	for property in ["OrderLV", "CleanLV", "FixLV", "HandWorkLV", "MachineWorkLV", "KnifeWorkLV"]:
		var value = human.Stat.get(property) if is_instance_valid(human) and human.get("Stat") != null else 3
		Stat.set(property, int(max(1, int(value))))
	Lv_Order = Stat.OrderLV
	Stat.Ins_MAXSPEED = int(210.0 * float(preload("res://ftc_mods/ftc.talent_market/Skills/SkillCatalog.gd").modifiers(talent_profile).move_speed))
	Stat.Ins_SpeedMult = 1.0
	Stat.call_CollisionAni()
	Con.CanControl = true
	Con.CanMove = true
	Con.CanRoll = false

func _integrate_forces(state):
	# Physics performs collision response; no position snapping or teleporting.
	state.linear_velocity = talent_velocity
	state.angular_velocity = 0.0

func set_motion(direction, speed):
	talent_velocity = direction * speed
	Con.velocity = talent_velocity
	var changed = false
	if direction.length_squared() > 0.001:
		behavior = BEHAVIOR.MOVE
		changed = Con.input_vector.distance_squared_to(direction.normalized()) > 0.001
		Con.input_vector = direction.normalized()
		if Con.state != GameLogic.NPC.STATE.MOVE:
			Con.state = GameLogic.NPC.STATE.MOVE
			changed = false
	else:
		if talent_busy_time > 0:
			behavior = BEHAVIOR.WORK
		else:
			behavior = BEHAVIOR.IDLE
		if Con.state != GameLogic.NPC.STATE.IDLE_EMPTY:
			Con.state = GameLogic.NPC.STATE.IDLE_EMPTY
	if changed:
		call_StatChange()

func face_position(point):
	var direction = point - global_position
	if direction.length_squared() > 0.001:
		var facing = direction.normalized()
		if Con.input_vector.distance_squared_to(facing) > 0.001:
			Con.input_vector = facing
			call_FaceRay_Rot()
			call_StatChange()

func tick_actions(delta):
	if talent_busy_time > 0:
		talent_busy_time = max(0.0, talent_busy_time - delta)
		if talent_busy_time <= 0:
			finish_actions()

func call_DeviceAni(device, duration = 1.0, _multiply = true):
	if not is_instance_valid(device):
		return
	if not talent_jobs.has(device):
		talent_jobs.append(device)
	talent_busy_time = max(talent_busy_time, max(0.1, float(duration)) * talent_work_duration)
	behavior = BEHAVIOR.WORK
	Con.ArmState = GameLogic.NPC.STATE.WORK
	talent_velocity = Vector2.ZERO
	call_StatChange()

func finish_actions():
	for device in talent_jobs:
		if not is_instance_valid(device):
			continue
		for key in ["cur_PlayerList", "_PLAYERLIST"]:
			var players = device.get(key)
			if typeof(players) == TYPE_ARRAY:
				players.erase(self)
	talent_jobs.clear()
	talent_busy_time = 0.0
	behavior = BEHAVIOR.IDLE
	if not is_inside_tree():
		return
	Con.IsMixing = false
	Con.ArmState = GameLogic.NPC.STATE.IDLE_EMPTY
	call_StatChange()

func call_control(_type):
	pass

func call_touch():
	# Native carry statistics call this; the NPC must not open human HUD hints.
	pass

func call_Pressure_init():
	cur_PressureMax = 100

func call_pressure_set(_value, _type = 0):
	pass

func _on_Timer_timeout():
	pass

func _on_OrderTimer_timeout():
	finish_actions()

func _on_PlayerNode_body_entered(_other):
	pass

func call_FootPrint_Logic():
	pass

func call_StatChange():
	emit_signal("StatChange")
