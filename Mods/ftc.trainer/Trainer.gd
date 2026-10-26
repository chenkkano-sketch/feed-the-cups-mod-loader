extends Node

# Feed The Cups 1.0.1.2 / Godot 3.6.1. Loose autoload; original resources stay intact.
var SETTINGS = "user://ftc_mods/ftc.trainer/settings.cfg"
var mod_api
const SPEEDS = [1.0, 1.5, 2.0, 3.0, 4.0]
const MOVEMENT_SPEEDS = [1.0, 1.5, 2.0, 3.0, 4.0]
const PREP = 1
const CUP = 2
const ORDER_ASSISTANT = preload("res://ftc_mods/ftc.trainer/OrderAssistant.gd")
const PREP_PATHS = {
	"WorkBoard": ["MixNode/MixAni"],
	"Fruit": ["MixNode/MixAni"],
	"TeaPort": ["MixNode/MixAni", "AniNode/TeaColorAni"],
	"MilkPot": ["AniNode/CookAni"],
	"BigPot": ["Cook/AnimationPlayer"],
	"BobaMachine": ["AniNode/CookerAni", "AniNode/BobaAni"],
	"ChopMachine": ["AniNode/MachineAni"],
	"SkinMachine": ["AniNode/MachineAni"],
	"JuiceMachine": ["AniNode/MachineAni"],
	"BreakMachine": ["AniNode/UseAni"],
	"FruitCore": ["AniNode/UseAni"],
	"CreamMachine": ["AniNode/MixAni"],
	"MixerMachine": ["AniNode/Use"]
}
const CUP_PATHS = {
	"DrinkCup": ["MixNode/MixAni", "TexNode/Tex/Extra/Smash/SmashAni"],
	"ShakeCup_L": ["MixNode/MixAni"],
	"CupHolder": ["Logic/CupAni", "AniNode/Use"],
	"SugarMachine": ["AniNode/Use"],
	"BeerMachine": ["AniNode/Use"],
	"PopMachine": ["AniNode/Use"],
	"IceCreamMachine": ["AniNode/Use"],
	"CoffeeMachine": ["UI/Record/Process_1/AnimationPlayer", "UI/Record/Process_2/AnimationPlayer", "UI/Record/Process_3/AnimationPlayer", "UI/Record/Process_4/AnimationPlayer", "AniNode/Use"]
}

var speed_index = 0
var fast_prep = false
var fast_cup = false
var prep_factor = 10.0
var cup_factor = 10.0
var panel_visible = true
var animations = {}
var pour_timers = {}
var cup_holders = {}
var owned_scale = false
var previous_scale = 1.0
var is_offline = false
var sdk = null
var panel = null
var status_label = null
var speed_button = null
var prep_button = null
var cup_button = null
var refresh_at = 0
var auto_order = false
var auto_fill = false
var auto_fill_button = null
var auto_fill_key = ""
var auto_fill_at = 0
var order_assistant = ORDER_ASSISTANT.new()
var auto_order_at = 0
var action_message = "I 键装填当前杯；F7 开启自动配料"
var message_label = null
var movement_speed_index = 0
var movement_button = null
var movement_stats = null
var movement_base = 1.0
var movement_written = 1.0

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	_load_settings()
	_build_panel()
	get_tree().connect("node_added", self, "_node_added")
	_scan(get_tree().root)
	print("[FTC Trainer v2.2] loaded: I fill held cup / F5 movement / F6 game speed / F7 auto fill / F8 auto order + pickup / F9 panel / F10 reset")

func _load_settings():
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return
	speed_index = int(clamp(int(cfg.get_value("trainer", "speed_index", 0)), 0, SPEEDS.size() - 1))
	movement_speed_index = int(clamp(int(cfg.get_value("trainer", "movement_speed_index", 0)), 0, MOVEMENT_SPEEDS.size() - 1))
	# Retire the old interpretation of quick preparation as animation speed.
	fast_prep = false
	fast_cup = false
	auto_order = bool(cfg.get_value("trainer", "auto_order", false))
	auto_fill = bool(cfg.get_value("trainer", "auto_fill", false))
	prep_factor = clamp(float(cfg.get_value("trainer", "prep_factor", 10.0)), 1.0, 20.0)
	cup_factor = clamp(float(cfg.get_value("trainer", "cup_factor", 10.0)), 1.0, 20.0)
	panel_visible = bool(cfg.get_value("trainer", "panel_visible", true))

func _save_settings():
	var cfg = ConfigFile.new()
	cfg.set_value("trainer", "speed_index", speed_index)
	cfg.set_value("trainer", "fast_prep", fast_prep)
	cfg.set_value("trainer", "fast_cup", fast_cup)
	cfg.set_value("trainer", "prep_factor", prep_factor)
	cfg.set_value("trainer", "cup_factor", cup_factor)
	cfg.set_value("trainer", "panel_visible", panel_visible)
	cfg.set_value("trainer", "auto_order", auto_order)
	cfg.set_value("trainer", "auto_fill", auto_fill)
	cfg.set_value("trainer", "movement_speed_index", movement_speed_index)
	var err = cfg.save(SETTINGS)
	if err != OK:
		push_warning("FTC Trainer: settings save failed: " + str(err))

func _build_panel():
	var layer = CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	panel = PanelContainer.new()
	panel.rect_position = Vector2(18, 18)
	panel.rect_min_size = Vector2(335, 245)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.06, 0.08, 0.94)
	style.border_color = Color(0.25, 0.8, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_stylebox_override("panel", style)
	var font_path = "res://Language/Fonts/simhei.ttf"
	if ResourceLoader.exists(font_path):
		var theme = Theme.new()
		var font = DynamicFont.new()
		font.font_data = load(font_path)
		font.size = 18
		theme.default_font = font
		panel.theme = theme
	layer.add_child(panel)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 7)
	panel.add_child(box)
	var title = Label.new()
	title.text = "杯杯倒满 · 单机修改器 v2.2"
	title.add_color_override("font_color", Color(0.4, 1, 0.85))
	box.add_child(title)
	status_label = Label.new()
	box.add_child(status_label)
	movement_button = _button(box, "", "cycle_movement_speed")
	speed_button = _button(box, "", "cycle_speed")
	prep_button = _button(box, "", "prepare_held_cup")
	auto_fill_button = _button(box, "", "toggle_auto_fill")
	cup_button = _button(box, "", "toggle_auto_order")
	message_label = Label.new()
	message_label.autowrap = true
	message_label.rect_min_size = Vector2(310, 48)
	box.add_child(message_label)
	_button(box, "F10  全部恢复正常", "reset_all")
	var help = Label.new()
	help.text = "F9 显示 / 隐藏面板\n全局加速也会加快顾客与营业时间"
	box.add_child(help)
	panel.visible = panel_visible
	_refresh_ui()

func _button(box, text, method):
	var button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.connect("pressed", self, method)
	box.add_child(button)
	return button

func _input(event):
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.scancode:
		KEY_I:
			if event.control or event.alt or event.meta:
				return
			prepare_held_cup()
		KEY_F5:
			cycle_movement_speed()
		KEY_F6:
			cycle_speed()
		KEY_F7:
			toggle_auto_fill()
		KEY_F8:
			toggle_auto_order()
		KEY_F9:
			panel_visible = not panel_visible
			panel.visible = panel_visible
			_save_settings()
		KEY_F10:
			reset_all()
		_:
			return
	get_tree().set_input_as_handled()

func cycle_speed():
	speed_index = (speed_index + 1) % SPEEDS.size()
	_changed()

func cycle_movement_speed():
	movement_speed_index = (movement_speed_index + 1) % MOVEMENT_SPEEDS.size()
	if movement_speed_index == 0:
		_restore_movement()
	_changed()

func _movement_tick():
	var context = _game_and_player()
	mod_api.set_movement_multiplier(MOVEMENT_SPEEDS[movement_speed_index] if not context.empty() else 1.0)

func _restore_movement():
	if mod_api != null:
		mod_api.set_movement_multiplier(1.0)

func toggle_prep():
	fast_prep = not fast_prep
	_changed()

func toggle_cup():
	fast_cup = not fast_cup
	_changed()

func toggle_auto_order():
	auto_order = not auto_order
	action_message = "自动点单已开启；空手时自动取杯" if auto_order else "自动点单与自动取杯已关闭"
	_changed()

func toggle_auto_fill():
	auto_fill = not auto_fill
	auto_fill_key = ""
	auto_fill_at = 0
	action_message = "自动配料已开启：拿起空杯后按绑定订单装填" if auto_fill else "自动配料已关闭；可按 I 单次装填"
	_changed()

func _auto_fill_tick():
	if not auto_fill or get_tree().paused or not _offline_allowed():
		return
	if OS.get_ticks_msec() < auto_fill_at:
		return
	auto_fill_at = OS.get_ticks_msec() + 100
	var context = _game_and_player()
	if context.empty():
		auto_fill_key = ""
		return
	var cup = order_assistant.held_cup(context[1])
	if not is_instance_valid(cup) or not cup.return_EmptyCheck():
		auto_fill_key = ""
		return
	# A newly picked cup can be initialized and ticketed across multiple frames.
	var order_id = int(cup.get("cur_ID"))
	var orders = context[0].get("Order")
	if order_id <= 0 or int(cup.get("Liquid_Max")) <= 0 or not is_instance_valid(orders):
		return
	if not orders.cur_OrderList.has(order_id):
		return
	var key = str(cup.get_instance_id()) + ":" + str(order_id)
	if key == auto_fill_key:
		return
	# Attempt once for this empty cup/ticket. A failed recipe must not retry each frame.
	auto_fill_key = key
	action_message = order_assistant.prepare_held_cup(context[0], context[1])
	_refresh_ui()

func _game_and_player():
	var game = get_node_or_null("/root/GameLogic")
	if not is_instance_valid(game):
		return []
	var loading = game.get("LoadingUI")
	if not is_instance_valid(loading) or loading.get("IsLevel") != true:
		return []
	var player = game.get("player_1P")
	if not is_instance_valid(player) or player.get("IsDead") == true:
		return []
	return [game, player]

func prepare_held_cup():
	if not _offline_allowed():
		action_message = "单机模式下才能装填配料"
	elif get_tree().paused:
		action_message = "请先继续游戏，再装填配料"
	else:
		var context = _game_and_player()
		if context.empty():
			action_message = "请先进入营业关卡并拿起空杯"
		else:
			action_message = order_assistant.prepare_held_cup(context[0], context[1])
	_refresh_ui()

func _auto_order_tick():
	if not auto_order or OS.get_ticks_msec() < auto_order_at:
		return
	auto_order_at = OS.get_ticks_msec() + 350
	var context = _game_and_player()
	if context.empty():
		return
	var ui = context[0].get("GameUI")
	if not is_instance_valid(ui) or ui.get("Is_Open") != true:
		return
	order_assistant.take_next_order(context[0], context[1])
	var holders = []
	for id in cup_holders.keys():
		var holder = cup_holders[id].get_ref()
		if is_instance_valid(holder):
			holders.append(holder)
		else:
			cup_holders.erase(id)
	var order_id = order_assistant.take_order_cup(context[0], context[1], holders)
	if order_id > 0:
		action_message = "已取出 #" + str(order_id) + " 空杯到手上"
		_refresh_ui()
		if auto_fill:
			auto_fill_at = 0
			_auto_fill_tick()

func reset_all():
	speed_index = 0
	fast_prep = false
	fast_cup = false
	auto_order = false
	auto_fill = false
	auto_fill_key = ""
	auto_fill_at = 0
	movement_speed_index = 0
	_restore_movement()
	action_message = "已恢复正常，自动配料与点单已关闭"
	_restore_scale()
	_restore_pours()
	_changed()

func _changed():
	_save_settings()
	_refresh_ui()

func _refresh_ui():
	if not is_instance_valid(status_label):
		return
	status_label.text = "单机可用" if is_offline else "联机 / 初始化：修改功能暂停"
	speed_button.text = "F6  游戏速度：" + str(SPEEDS[speed_index]) + " 倍"
	movement_button.text = "F5  移动速度：" + str(MOVEMENT_SPEEDS[movement_speed_index]) + " 倍"
	prep_button.text = "I  装填配料（手上订单）"
	auto_fill_button.text = "F7  自动配料：" + ("开启" if auto_fill else "关闭")
	cup_button.text = "F8  自动点单 / 取杯：" + ("开启" if auto_order else "关闭")
	message_label.text = action_message

func _offline_allowed():
	if not is_instance_valid(sdk):
		sdk = get_node_or_null("/root/SdkManager")
	# Fail closed if an update changes the multiplayer interface.
	if not is_instance_valid(sdk):
		return false
	return sdk.get("is_multiplay") == false and sdk.get("lobby_player_num") == 1

func _process(delta):
	var allowed = _offline_allowed()
	if allowed != is_offline:
		is_offline = allowed
		_refresh_ui()
	if not is_offline:
		_restore_scale()
		_restore_movement()
		_restore_pours()
		return
	_apply_scale()
	if get_tree().paused:
		return
	_movement_tick()
	_auto_fill_tick()
	_auto_order_tick()
	# Snapshot keys: animation method tracks may add/delete other registered objects.
	for id in animations.keys():
		var entry = animations[id]
		var animation = entry[0].get_ref()
		if not is_instance_valid(animation):
			animations.erase(id)
			continue
		var factor = prep_factor if entry[1] == PREP and fast_prep else 1.0
		if entry[1] == CUP and fast_cup:
			factor = cup_factor
		if factor > 1.0 and animation.is_playing() and animation.can_process() and animation.is_active():
			# Advance normally so recipe checks, ingredient consumption and completion events run.
			animation.advance(min(delta, 0.1) * (factor - 1.0))
	_update_pours()
	if OS.get_ticks_msec() >= refresh_at:
		refresh_at = OS.get_ticks_msec() + 1000
		_refresh_ui()

func _apply_scale():
	mod_api.set_game_speed(SPEEDS[speed_index])

func _restore_scale():
	if mod_api != null:
		mod_api.set_game_speed(1.0)

func _scan(node):
	_register(node)
	for child in node.get_children():
		_scan(child)

func _node_added(node):
	# The node_added signal precedes some _ready calls; defer discovery until children exist.
	call_deferred("_register", weakref(node))

func _register(value):
	var node = value.get_ref() if value is WeakRef else value
	if not is_instance_valid(node):
		return
	var script = node.get_script()
	if script == null:
		return
	var path = script.resource_path
	if not path.begins_with("res://TscnAndGd/Objects/"):
		return
	var basename = path.get_file().get_basename()
	if basename == "CupHolder":
		cup_holders[node.get_instance_id()] = weakref(node)
	if PREP_PATHS.has(basename):
		_register_paths(node, PREP_PATHS[basename], PREP)
	if CUP_PATHS.has(basename):
		_register_paths(node, CUP_PATHS[basename], CUP)
	# Containers throttle pouring with this timer. Cooling and spoilage timers are excluded.
	if basename in ["TeaPort", "Con_Liquid"]:
		var timer = node.get_node_or_null("Timer")
		if timer is Timer:
			pour_timers[timer.get_instance_id()] = [weakref(timer), timer.wait_time, false]

func _register_paths(node, paths, category):
	for path in paths:
		var animation = node.get_node_or_null(path)
		if animation is AnimationPlayer:
			animations[animation.get_instance_id()] = [weakref(animation), category]

func _update_pours():
	for id in pour_timers.keys():
		var entry = pour_timers[id]
		var timer = entry[0].get_ref()
		if not is_instance_valid(timer):
			pour_timers.erase(id)
			continue
		if fast_cup:
			if not entry[2]:
				entry[1] = timer.wait_time
				entry[2] = true
			timer.wait_time = max(entry[1] / cup_factor, 0.02)
			if not timer.is_stopped() and timer.time_left > timer.wait_time:
				timer.start(timer.wait_time)
		elif entry[2]:
			_restore_timer(entry)

func _restore_timer(entry):
	var timer = entry[0].get_ref()
	if is_instance_valid(timer) and entry[2]:
		timer.wait_time = entry[1]
		if not timer.is_stopped():
			timer.start(entry[1])
	entry[2] = false

func _restore_pours():
	for entry in pour_timers.values():
		_restore_timer(entry)

func _exit_tree():
	_restore_scale()
	_restore_movement()
	_restore_pours()
