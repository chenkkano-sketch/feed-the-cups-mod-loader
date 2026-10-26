extends Node

const Rules = preload("res://ftc_mods/ftc.rent_mode/RentRules.gd")
const BEST_DAYS = "ftc_rent_best_days"
var api
var settings = Rules.defaults()
var seed_room = false
var preparing = false
var state = {}
var layer
var setup_panel
var setup_menu_info
var map_buttons = []
var map_preview
var map_description
var selected_map = Rules.Maps.DEFAULT
var curve_select
var rent_preview
var fields = {}
var bar
var entry_button
var notice
var setup_paused = false
var tick = 0.0
var opened = false
var pending_reward = false
var restoring = false
var awaiting_bus = false
var font
var sprint
var controls_blocked = false
var controls_were_enabled = true
var coop
var result_open = false
var reward_ledger
var archive_ui
var remote_result_record = {}

func _ready():
	coop = preload("res://ftc_mods/ftc.rent_mode/Coop/Session.gd").new(self)
	SdkManager.connect("LeaveLobby", self, "_coop_left")
	sprint = load("res://ftc_mods/ftc.rent_mode/RentSprint.gd").new(self)
	pause_mode = Node.PAUSE_MODE_PROCESS
	font = DynamicFont.new()
	font.font_data = load("res://Language/Fonts/simhei.ttf")
	font.size = 23
	_build_ui()
	GameLogic.connect("DayStart", self, "begin_prep")
	GameLogic.connect("OpenStore", self, "_opened")
	var config = ConfigFile.new()
	if config.load("user://rent_setup.cfg") == OK:
		var saved = config.get_value("setup", "settings", settings)
		if Rules.validate(saved) == "":
			settings = Rules.for_new_run(saved)

func is_run():
	return GameLogic.cur_level == "房租模式" and GameLogic.LoadingUI.IsLevel

func _offline():
	return not SdkManager.is_multiplay and SdkManager.lobby_player_num <= 1

func authority():
	return not SdkManager.is_multiplay or SdkManager.lobby_is_master

func _coop_left():
	coop.reset()

func can_enter_from_home():
	var loading = GameLogic.LoadingUI
	if not authority() or loading.Is_Loading or not loading.IsHome or loading.IsLevel or loading.IsMain:
		return false
	var home = get_tree().current_scene
	if not is_instance_valid(home) or not home.is_inside_tree():
		return false
	# Upgraded homes share the native map_home script and loading path.
	if not home.filename.begins_with("res://TscnAndGd/Main/Homes/map_home_") or not home.filename.ends_with(".tscn") or not home.has_method("_PlayerCreate"):
		return false
	var player = GameLogic.player_1P
	return GameLogic.Save.gameData.has("HomeDevList") and is_instance_valid(player) and home.is_a_parent_of(player)

func _home_entry_available():
	return can_enter_from_home() and not get_tree().paused and GameLogic.Con.is_processing_input() and GameLogic.player_1P.Con.CanControl

func _physics_process(delta):
	if sprint != null:
		sprint.update(delta, Input.is_key_pressed(KEY_SHIFT), OS.is_window_focused())

func _process(delta):
	coop.tick(delta)
	tick += delta
	if tick < 0.2:
		return
	tick = 0.0
	entry_button.visible = _home_entry_available() and not setup_panel.visible
	if setup_panel.visible and not can_enter_from_home():
		_hide_setup()
	bar.visible = false
	if not is_run():
		return
	if state.empty():
		_restore_state()
	if state.get("failed", false):
		return
	if authority() and opened:
		_record_daily_income()
	var lost = GameLogic.cur_NoOrderNum + GameLogic.cur_NoSellNum
	bar.update_values(current_rent(), lost, int(settings.lost_limit))
	_sync_hud()
	if authority() and preparing and not GameLogic.GameUI.DayEnd and not get_tree().paused and get_node_or_null("/root/FurnitureCarryMode") == null:
		# Deliveries must continue while the business clock is frozen.
		GameLogic.Buy.call_check(GameLogic.GameUI.CurTime + 1.0)
	if authority() and not preparing and GameLogic.GameOverType == -1 and not GameLogic._DayOver_Bool and lost >= int(settings.lost_limit):
		state.reason = "今天流失顾客达到上限，经营结束。"
		GameLogic.GameOverType = 1
		GameLogic.call_dayover()

func _input(event):
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.scancode == KEY_F4 and _home_entry_available():
		_show_setup()
		get_tree().set_input_as_handled()

func _build_ui():
	layer = CanvasLayer.new()
	layer.layer = 130
	add_child(layer)
	entry_button = _button("房租模式  [F4]", layer, "_show_setup")
	entry_button.rect_position = Vector2(1350, 30)
	entry_button.rect_size = Vector2(280, 55)
	entry_button.hide()
	bar = preload("res://ftc_mods/ftc.rent_mode/HudRows.gd").new(GameLogic.GameUI.get_node("RightUp/InfoNode/money/MoneyLabel"))
	GameLogic.GameUI.get_node("RightUp").add_child(bar)
	bar.hide()
	notice = _label("", layer)
	notice.rect_position = Vector2(460, 165)
	notice.rect_size = Vector2(1100, 110)
	notice.autowrap = true
	notice.add_color_override("font_color", Color(1, 0.87, 0.4))
	setup_panel = _panel(Vector2(80, 55), Vector2(1760, 970))
	var setup_content = VBoxContainer.new()
	setup_content.add_constant_override("separation", 12)
	setup_panel.add_child(setup_content)
	_label("房租模式  ·  选择地图", setup_content)
	_label("从家里出发，沿用当前角色、装扮与家居加成。准备阶段不限时，手动开店。", setup_content)
	var columns = HBoxContainer.new()
	columns.add_constant_override("separation", 30)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setup_content.add_child(columns)
	var content = VBoxContainer.new()
	content.rect_min_size.x = 850
	content.add_constant_override("separation", 8)
	columns.add_child(content)
	_label("地图专属菜谱与升级路线", content)
	setup_menu_info = _wrap_label("", content)
	setup_menu_info.rect_min_size.y = 80
	var curve_row = HBoxContainer.new()
	content.add_child(curve_row)
	_label("租金曲线", curve_row)
	curve_select = OptionButton.new()
	curve_select.add_font_override("font", font)
	curve_select.add_item("递增租金挑战（推荐）")
	curve_select.add_item("固定金额涨租（自定义）")
	curve_select.rect_min_size = Vector2(400, 45)
	curve_select.connect("item_selected", self, "_refresh_rent_preview")
	curve_row.add_child(curve_select)
	var params = GridContainer.new()
	params.columns = 4
	content.add_child(params)
	for spec in [["funds", "初始资金", 300, 5000, 100], ["rent", "首日房租", 1, 500, 5], ["pressure", "租金压力 0～100%", 0, 100, 1], ["growth", "固定每日增额", 1, 200, 1], ["lost_limit", "每日顾客流失上限", 1, 10, 1]]:
		_label(spec[1], params)
		var field = SpinBox.new()
		field.min_value = spec[2]
		field.max_value = spec[3]
		field.step = spec[4]
		if spec[0] == "pressure":
			field.suffix = "%"
		field.get_line_edit().add_font_override("font", font)
		field.rect_min_size = Vector2(160, 45)
		params.add_child(field)
		fields[spec[0]] = field
		if spec[0] in ["rent", "growth", "pressure"]:
			field.connect("value_changed", self, "_refresh_rent_preview")
	rent_preview = _label("", content)
	_wrap_label("租金压力：0% 为平缓线性增长，50% 为标准压力；高压力在第 7 天起进一步加速，95% 每天额外乘 1.7。开局后固定，联机由房主设置。", content)
	_wrap_label("初始菜谱由地图决定，后续新品、配料、设备和杯型升级沿用该地图原版规则。\n初始设备数量和位置见右侧预览。", content)
	_wrap_label("采购与升级使用原商店；初始原料不足时请先采购，准备阶段配送照常到货。", content)
	_wrap_label("本模式与正常模式共用存档；新开局会替换当前房租经营记录，不影响正常关卡进度。", content)
	var buttons = HBoxContainer.new()
	content.add_child(buttons)
	_button("创建新经营", buttons, "_create_run")
	_button("继续房租经营", buttons, "_continue_from_home")
	_button("关闭", buttons, "_hide_setup")
	var maps = VBoxContainer.new()
	maps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	maps.add_constant_override("separation", 14)
	columns.add_child(maps)
	_label("开局地图  ·  点击切换实景预览", maps)
	var map_choices = GridContainer.new()
	map_choices.columns = 3
	map_choices.add_constant_override("hseparation", 10)
	map_choices.add_constant_override("vseparation", 8)
	maps.add_child(map_choices)
	var group = ButtonGroup.new()
	for room in Rules.Maps.ROOMS:
		if map_buttons.size() >= 7:
			break
		var button = Button.new()
		button.text = room.name
		button.toggle_mode = true
		button.group = group
		button.rect_min_size = Vector2(0, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_font_override("font", font)
		button.set_meta("map", room.id)
		button.connect("pressed", self, "_select_map", [room.id])
		map_choices.add_child(button)
		map_buttons.append(button)
	var preview_frame = PanelContainer.new()
	var preview_style = StyleBoxFlat.new()
	preview_style.bg_color = Color(0.035, 0.045, 0.06)
	preview_style.border_color = Color(0.4, 0.65, 0.7)
	preview_style.set_border_width_all(2)
	preview_style.content_margin_left = 8
	preview_style.content_margin_right = 8
	preview_style.content_margin_top = 8
	preview_style.content_margin_bottom = 8
	preview_frame.add_stylebox_override("panel", preview_style)
	maps.add_child(preview_frame)
	map_preview = load("res://ftc_mods/ftc.rent_mode/RentMapPreview.gd").new()
	map_preview.rect_min_size = Vector2(740, 400)
	preview_frame.add_child(map_preview)
	map_description = _wrap_label("", maps)
	map_description.rect_min_size.y = 100
	_wrap_label("预览展示实际墙体、通道与初始设备。进入店铺后，可在不限时准备阶段继续搬运调整布局。", maps)
	_wrap_label("地图只在创建新经营时选择；继续经营会恢复该存档原有的地图和摆设。", maps)
	setup_panel.hide()

func _panel(pos, size):
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.13, 0.98)
	style.border_color = Color(0.4, 0.65, 0.7)
	style.set_border_width_all(2)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_stylebox_override("panel", style)
	layer.add_child(panel)
	panel.rect_position = pos
	panel.rect_min_size = size
	return panel

func _sync_hud():
	var ui = GameLogic.GameUI
	var right = ui.get_node("RightUp")
	# Share the native HUD's anchor and follow its changing currency/mail rows.
	# Keep the right edge aligned without resizing any native widgets.
	var money = right.get_node("InfoNode/money")
	var bottom = money.rect_global_position.y
	for row in money.get_children():
		if row is Control and row.visible:
			bottom = max(bottom, row.get_global_rect().end.y)
	bar.rect_size = bar.get_combined_minimum_size()
	bar.rect_position = Vector2(-34 - bar.rect_size.x, bottom - right.rect_global_position.y + 6)
	bar.visible = is_run() and right.is_visible_in_tree() and not ui.DayEnd and not get_tree().paused and not setup_panel.visible and not ui.OrderNode.cur_used and not state.get("failed", false)

func _label(text, parent):
	var label = Label.new()
	label.text = text
	label.add_font_override("font", font)
	parent.add_child(label)
	return label

func _wrap_label(text, parent):
	var label = _label(text, parent)
	label.autowrap = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.rect_min_size.y = 55
	return label

func _select_map(id):
	selected_map = Rules.Maps.starting_room(id).id
	for button in map_buttons:
		button.pressed = button.get_meta("map") == selected_map
	var room = Rules.Maps.room(selected_map)
	setup_menu_info.text = "初始菜谱：%s\n配方路线：%s\n沿用原版「%s」的配方、配料、机器与杯型解锁规则。" % [PoolStringArray(room.menu).join("、"), room.route, room.level]
	map_description.text = "%s · 室内面积 %d\n%s" % [room.name, room.area, room.info]
	map_preview.show_map(selected_map)

func _button(text, parent, callback):
	var button = Button.new()
	button.text = text
	button.add_font_override("font", font)
	button.rect_min_size.y = 48
	button.connect("pressed", self, callback)
	parent.add_child(button)
	return button

func _message(text):
	notice.text = text
	print("RENT_MODE: " + text)

func _show_setup():
	if not can_enter_from_home() or (not setup_panel.visible and not _home_entry_available()):
		return false
	var market = api.service("ftc.talent_market", "market")
	if market != null and market.is_modal_open():
		return false
	var setup = Rules.for_new_run(settings)
	_select_map(setup.map)
	for key in fields:
		fields[key].value = setup[key]
	curve_select.select(0 if setup.get("curve", "staged") == "staged" else 1)
	_refresh_rent_preview()
	if not setup_panel.visible:
		setup_paused = get_tree().paused
	get_tree().paused = true
	_block_controls(true)
	setup_panel.show()
	return true

func _hide_setup():
	setup_panel.hide()
	get_tree().paused = setup_paused
	_block_controls(false)

func _create_run():
	if not can_enter_from_home():
		return false
	var chosen = settings.duplicate(true)
	chosen.version = Rules.VERSION
	chosen.map = selected_map
	chosen.curve = "staged" if curve_select.selected == 0 else "linear"
	chosen = Rules.for_new_run(chosen)
	for key in fields:
		chosen[key] = int(fields[key].value)
	var source_level = Rules.Maps.room(chosen.map).level
	if GameLogic.Config.SceneConfig.has(source_level):
		chosen.native_devil = max(0, int(GameLogic.Config.SceneConfig[source_level].DevilMax) - 1)
	var error = Rules.validate(chosen)
	if error != "":
		_message(error)
		return false
	return start_run(chosen)

func start_from_selection(level, difficulty):
	if not can_enter_from_home():
		return false
	if level == "新手引导第一关":
		level = "社区店1"
	var room = Rules.Maps.room_for_level(level)
	if room.empty() or not GameLogic.Config.SceneConfig.has(level):
		_message("该店铺暂时无法开启房租经营。")
		return false
	var chosen = Rules.defaults()
	chosen.map = room.id
	chosen.menu = room.menu.duplicate()
	chosen.funds = clamp(int(GameLogic.Config.SceneConfig[level].Funds), 300, 5000)
	chosen.pressure = 35 + 30 * clamp(int(difficulty), 0, 2)
	chosen.store_difficulty_multiplier = 1 + 2 * clamp(int(difficulty), 0, 2)
	chosen.native_devil = max(0, int(GameLogic.Config.SceneConfig[level].DevilMax) - 1)
	return start_run(chosen)

func _best_key(chosen):
	var tier = clamp(int((int(chosen.get("store_difficulty_multiplier", 1)) - 1) / 2), 0, 2)
	return "%s:%d" % [str(chosen.get("map", "")), tier]

func best_days_for(level, tier):
	var room = Rules.Maps.room_for_level(level)
	if room.empty():
		return 0
	var key = "%s:%d" % [room.id, clamp(int(tier), 0, 2)]
	var records = GameLogic.Save.gameData.get(BEST_DAYS, {})
	var best = max(0, int(records.get(key, 0))) if records is Dictionary else 0
	# Recover the latest completed run from saves made before this counter existed.
	var checkpoint = GameLogic.Save.Config.get_value("FtcRentRun", "checkpoint", {})
	if checkpoint is Dictionary and checkpoint.get("level", {}) is Dictionary:
		var previous = checkpoint.level.get("rent_mode", {})
		if previous is Dictionary and previous.has("settings") and previous.settings is Dictionary and _best_key(previous.settings) == key:
			best = max(best, int(previous.get("paid_day", 0)))
			if previous.has("final_result") and previous.final_result is Dictionary:
				best = max(best, int(previous.final_result.get("day", 0)))
	return best

func _remember_best_days(day):
	if not authority() or int(day) < 1:
		return
	var records = GameLogic.Save.gameData.get(BEST_DAYS, {})
	if not records is Dictionary:
		records = {}
	records = records.duplicate(true)
	var key = _best_key(settings)
	if int(day) <= int(records.get(key, 0)):
		return
	records[key] = int(day)
	GameLogic.Save.gameData[BEST_DAYS] = records
	GameLogic.Save.Config.set_value("Game", BEST_DAYS, records.duplicate(true))

func start_run(chosen):
	# Core API also serves other modules; only the player-facing entry is Home-only.
	if typeof(chosen) != TYPE_DICTIONARY:
		return false
	chosen = Rules.for_new_run(chosen)
	if not authority() or Rules.validate(chosen) != "" or GameLogic.LoadingUI.Is_Loading:
		return false
	if not coop.ready():
		_message("请所有玩家安装同版房租与搬运 Mod，使用 rent_coop 配置；正在等待房间成员确认版本。")
		return false
	settings = chosen.duplicate(true)
	GameLogic.Save.capture_normal_checkpoint()
	state = {"settings": settings.duplicate(true), "run_id": _new_run_id(), "paid_day": 0, "failed": false, "reason": "", "phase": "prep", "reward_remaining": 0, "peak_money": 0, "seed_pending": true, "rent_floor": 0, "rent_floor_day": 0, "pending_rent_floor": 0, "income_day": 0, "daily_income_peak": 0}
	coop.begin_run()
	result_open = false
	remote_result_record = {}
	pending_reward = false
	GameLogic.SPECIALLEVEL_Int = 0
	# Use the native ChooseShop initialization. HomeDevList, EquipDic and the
	# selected player IDs stay intact, so native day/player initialization applies
	# their bonuses and appearance once, just as in an ordinary shop.
	GameLogic.call_NewLevel_Init()
	GameLogic.cur_Devil = int(settings.get("native_devil", 0))
	GameLogic.cur_level = "房租模式"
	GameLogic.new_bool = true
	GameLogic.call_SceneConfig_load()
	GameLogic.call_MoneyChange(int(settings.funds), GameLogic.HomeMoneyKey)
	record_peak_money(GameLogic.cur_money)
	GameLogic.cur_StoreStar = int(GameLogic.cur_levelInfo.Popular)
	GameLogic.Card.call_Event_init()
	GameLogic.Can_Card = true
	GameLogic.Order.call_Formula_init()
	GameLogic.cur_Menu = settings.menu.duplicate()
	GameLogic.cur_MenuNum = settings.menu.size()
	GameLogic.Can_Formula = false
	GameLogic.cur_Gift = 0
	seed_room = true
	preparing = true
	_store_state()
	var config = ConfigFile.new()
	config.set_value("setup", "settings", settings)
	config.save("user://rent_setup.cfg")
	GameLogic.call_save()
	awaiting_bus = true
	setup_panel.hide()
	get_tree().paused = false
	_block_controls(false)
	GameLogic.call_start_check()
	return true

func _continue_from_home():
	if not can_enter_from_home():
		return false
	return _continue_run()

func _continue_run():
	if not authority() or GameLogic.LoadingUI.Is_Loading:
		return false
	if not coop.ready():
		_message("等待所有玩家确认同版房租与搬运 Mod，请使用 rent_coop 配置。")
		return false
	var checkpoint = GameLogic.Save.Config.get_value("FtcRentRun", "checkpoint", {})
	if not checkpoint is Dictionary or not checkpoint.get("level", {}) is Dictionary or checkpoint.level.get("cur_level", "") != "房租模式":
		_message("没有可继续的房租经营存档。")
		return false
	state = checkpoint.level.get("rent_mode", {}).duplicate(true)
	remote_result_record = {}
	settings = state.get("settings", Rules.defaults()).duplicate(true)
	if state.get("failed", false):
		if state.has("final_result"):
			coop.begin_run()
			setup_panel.hide()
			_show_result()
		else:
			_message("本次经营已经结束，请创建新经营。")
		return false
	setup_panel.hide()
	get_tree().paused = false
	_block_controls(false)
	restoring = true
	GameLogic.Save.load_rent_checkpoint = true
	GameLogic.call_load()
	GameLogic.Save.load_rent_checkpoint = false
	restoring = false
	_restore_state()
	coop.begin_run()
	_store_state()
	GameLogic.call_save()
	GameLogic.MissionComplete_bool = false
	pending_reward = state.get("phase", "prep") == "reward"
	if pending_reward:
		GameLogic.cur_Day = int(state.get("paid_day", 0)) + 1
	awaiting_bus = true
	GameLogic.call_start_check()
	return true

func _restore_state():
	if not authority():
		coop.restore_lobby()
		return
	state = GameLogic.Save.levelData.get("rent_mode", {}).duplicate(true)
	var restored = state.get("settings", Rules.defaults())
	if Rules.validate(restored) == "":
		settings = restored.duplicate(true)

func _store_state():
	if not authority():
		return
	state.settings = settings.duplicate(true)
	GameLogic.Save.levelData["rent_mode"] = state.duplicate(true)
	if coop != null:
		coop.broadcast_state()

func room_loaded():
	if GameLogic.Save.levelData.has("rent_mode"):
		_restore_state()
	OS.set_window_title("Feed The Cups · 房租模式 v0.14.17 · 联机")

func begin_prep():
	if not is_run():
		return
	preparing = true
	opened = false
	GameLogic.cur_Rent = 0
	if not authority():
		return
	state.phase = "prep"
	if int(state.get("income_day", 0)) != int(GameLogic.cur_Day):
		state.income_day = int(GameLogic.cur_Day)
		state.daily_income_peak = 0
		state.pending_rent_floor = int(state.get("rent_floor", 0))
	if GameLogic.cur_Menu.empty():
		GameLogic.cur_Menu = settings.menu.duplicate()
	notice.text = ""
	_store_state()
	GameLogic.call_save()

func _start_business():
	if not is_run() or not preparing or GameLogic.GameUI.DayEnd or get_tree().paused:
		return
	var furniture = api.service("ftc.furniture_carry", "mode")
	if furniture != null and not furniture.can_open():
		return
	if GameLogic.player_1P.Con.IsHold:
		_message("请先放下手上的物品，再开始营业。")
		return
	GameLogic.GameUI.CurTime = float(GameLogic.cur_OpenTime)
	GameLogic.GameUI.set_Pointer()
	GameLogic.GameUI.call_Open()

func _opened():
	if is_run():
		preparing = false
		opened = true
		notice.text = ""
		if authority():
			_record_daily_income()

func _record_daily_income():
	if not authority() or not is_run() or not opened or state.get("phase", "prep") != "prep" or int(state.get("paid_day", 0)) >= int(GameLogic.cur_Day):
		return
	if int(state.get("income_day", 0)) != int(GameLogic.cur_Day):
		state.income_day = int(GameLogic.cur_Day)
		state.daily_income_peak = 0
		state.pending_rent_floor = int(state.get("rent_floor", 0))
	var income = max(0, int(GameLogic.Money_Sell) + int(GameLogic.Money_Tip))
	state.daily_income_peak = max(int(state.get("daily_income_peak", 0)), income)
	# Keep calculating the next-day floor as cups are sold. Today's bill is fixed.
	state.pending_rent_floor = max(int(state.get("pending_rent_floor", 0)), Rules.income_rent_floor(settings, state.daily_income_peak))

func _settled_daily_income(day):
	var income = int(state.get("daily_income_peak", 0)) if int(state.get("income_day", 0)) == int(day) else 0
	var records = GameLogic.Save.levelData.get("DAYINFO", {})
	if records is Dictionary:
		var row = records.get("Day_" + str(day), {})
		if row is Dictionary:
			income = max(income, int(row.get("Money_Sell", 0)) + int(row.get("Money_Tip", 0)))
	return max(0, income)

func settle_day(day_ui):
	if not authority():
		return
	if int(state.get("paid_day", 0)) >= GameLogic.cur_Day:
		return
	_record_daily_income()
	var daily_income = _settled_daily_income(GameLogic.cur_Day)
	var rent = current_rent()
	var settlement = Rules.settle(GameLogic.cur_money, rent)
	GameLogic.call_MoneyChange(-rent, GameLogic.HomeMoneyKey)
	GameLogic.level_MoneyCostTotal += rent
	GameLogic.level_ProfitTotal -= rent
	GameLogic.call_MC(-rent, GameLogic.HomeMoneyKey)
	state.paid_day = GameLogic.cur_Day
	state.rent_floor = max(int(state.get("rent_floor", 0)), max(int(state.get("pending_rent_floor", 0)), Rules.income_rent_floor(settings, daily_income)))
	state.rent_floor_day = int(GameLogic.cur_Day) + 1
	state.daily_income_peak = daily_income
	_remember_best_days(state.paid_day)
	state.phase = "reward"
	if (settlement.failed or GameLogic.cur_money < 0) and GameLogic.GameOverType == -1:
		GameLogic.GameOverType = 2
		state.reason = "现金不足以支付今日房租和经营支出。"
	state.failed = GameLogic.GameOverType != -1
	if state.failed and state.reason == "":
		state.reason = "主动放弃经营。" if GameLogic.GameOverType == 3 else "压力过高，无法继续接待顾客。"
	if state.failed:
		_freeze_result()
	# Keep the gifts earned by the native popularity system (including its
	# furniture bonuses); every successful day still guarantees one choice.
	state.reward_remaining = 0 if state.failed else max(1, GameLogic.cur_Gift)
	GameLogic.cur_Gift = int(state.reward_remaining)
	# Keep the original settlement screen and its totals consistent with actual cash.
	apply_settlement_ui(day_ui, rent)
	_record_settled_rent(rent)
	_snapshot_settlement_inventory()
	_store_state()
	GameLogic.call_save()
	SdkManager.call_puppet_node_sync(day_ui, "call_rent_settlement", [GameLogic.cur_money, GameLogic.level_ProfitTotal, GameLogic.level_MoneyCostTotal, rent, GameLogic.GameOverType])
	notice.text = ""

func apply_settlement_ui(day_ui, rent):
	if not is_instance_valid(day_ui):
		return
	var numbers = day_ui.get_node("BG/DayInfoBG/VBox")
	numbers.get_node("Minus/Rent/Num").text = str(-rent)
	if int(day_ui.get_meta("ftc_rent_paid_day") if day_ui.has_meta("ftc_rent_paid_day") else -1) != int(GameLogic.cur_Day):
		for path in ["Last/Total/Num", "Last/Profit/Num"]:
			var label = numbers.get_node(path)
			label.text = str(int(label.text) - rent)
		day_ui.set_meta("ftc_rent_paid_day", int(GameLogic.cur_Day))
	numbers.get_node("Last/CurMoney/Num").text = str(GameLogic.cur_money)
	day_ui.call_TotalNum_set(GameLogic.level_ProfitTotal)

func _record_settled_rent(rent):
	# Native DayEnd records zero rent for this mode before RentMode settles it.
	# Amend that same ledger so historical screens match the paid cash and UI.
	var records = GameLogic.Save.levelData.get("DAYINFO", {})
	if not records is Dictionary:
		return
	var key = "Day_" + str(GameLogic.cur_Day)
	if not records.has(key) or not records[key] is Dictionary:
		return
	var row = records[key]
	if row.get("RentModeRentRecorded", false):
		return
	row["Cost_Rent"] = int(row.get("Cost_Rent", 0)) - int(rent)
	row["TODAY"] = int(row.get("TODAY", 0)) - int(rent)
	row["RentModeRentRecorded"] = true
	records[key] = row
	records["Cost_Rent"] = int(records.get("Cost_Rent", 0)) - int(rent)
	GameLogic.Save.levelData["DAYINFO"] = records

func _snapshot_settlement_inventory():
	# The reward checkpoint is saved before the native first confirmation,
	# which normally snapshots and deletes the live level items. Capture only
	# the snapshot here, so paid income cannot restore morning ingredient stock.
	if not is_run() or GameLogic.LoadingUI.Is_Loading:
		return
	var level = get_tree().root.get_node_or_null("Level")
	if not is_instance_valid(level) or level != get_tree().current_scene or not level.has_method("_dev_save") or not level.has_method("_item_save"):
		return
	if not level.has_node("YSort/Devices") or not level.has_node("YSort/Items"):
		return
	level._dev_save()
	level._item_save()
	var market = api.service("ftc.talent_market", "market")
	if market != null and market.has_method("_snapshot_player_item"):
		market._snapshot_player_item(level)
		return
	# Talent normally owns this compatibility hook. Keep standalone Rent safe
	# too without forcing a drop or changing the human's held object.
	var player = GameLogic.player_1P
	if not is_instance_valid(player) or not player.Con.IsHold:
		return
	var item = instance_from_id(player.Con.HoldInsId)
	if not is_instance_valid(item) or item.is_queued_for_deletion() or not player.is_a_parent_of(item):
		return
	var data = GameLogic.Save.return_savedata(item)
	if not data is Dictionary or data.empty():
		return
	var items = GameLogic.Save.levelData.get("Items", null)
	if not items is Array:
		return
	for record in items:
		if record is Dictionary and str(record.get("NAME", "")) == str(data.get("NAME", "")):
			return
	data = data.duplicate(true)
	data.pos = level.get_node("YSort/Items").to_local(player.global_position)
	items.append(data)
	GameLogic.Save.levelData["Items"] = items

func current_rent():
	var floor_amount = int(state.get("rent_floor", 0)) if int(GameLogic.cur_Day) >= int(state.get("rent_floor_day", 0)) else 0
	var base_rent = max(Rules.rent_for_day(settings, GameLogic.cur_Day), floor_amount)
	return int(base_rent * Rules.rent_multiplier(GameLogic.cur_Rewards, GameLogic.cur_Challenge, GameLogic.cur_Event))

func wage_multiplier(day):
	return Rules.wage_multiplier_for_day(settings, day)

func _refresh_rent_preview(_value = 0):
	if rent_preview == null or not fields.has("growth"):
		return
	var preview = Rules.defaults()
	preview.curve = "staged" if curve_select.selected == 0 else "linear"
	preview.rent = int(fields.rent.value)
	preview.growth = int(fields.growth.value)
	preview.pressure = int(fields.pressure.value)
	fields.growth.editable = preview.curve == "linear"
	fields.growth.modulate.a = 1.0 if preview.curve == "linear" else 0.4
	fields.pressure.editable = preview.curve == "staged"
	fields.pressure.modulate.a = 1.0 if preview.curve == "staged" else 0.4
	var lines = ["前12天租金｜最高杯币÷20折绿钞，上限%d" % Rules.failure_reward_cap(preview)]
	for stage in range(4):
		var day = stage * 3 + 1
		lines.append("第 %d～%d 天：%d / %d / %d" % [day, day + 2, Rules.rent_for_day(preview, day), Rules.rent_for_day(preview, day + 1), Rules.rent_for_day(preview, day + 2)])
	rent_preview.text = PoolStringArray(lines).join("\n")

func resume_reward():
	pending_reward = false
	GameLogic.cur_Gift = remaining_rewards()
	GameLogic.GameUI.DayEnd = true
	coop.broadcast_state()
	GameLogic.emit_signal("RewardUI")

func remaining_rewards():
	if state.get("failed", false):
		return 0
	# Old checkpoints held exactly one daily choice and have no count field.
	return max(0, int(state.get("reward_remaining", 1 if state.get("phase", "prep") == "reward" else 0)))

func reward_selected():
	if not authority():
		return
	# RewardUI consumes cur_Gift when it *shows* an offer. Persist an inclusive
	# count instead, and consume only after native call_select accepted a card.
	state.reward_remaining = max(0, remaining_rewards() - 1)
	if int(state.reward_remaining) == 0:
		state.phase = "product" if product_due() else "prep"
	else:
		state.phase = "reward"
	_store_state()
	GameLogic.call_save()

func product_stage():
	return int(int(state.get("paid_day", 0)) / 3)

func product_candidates():
	var available = []
	GameLogic.call_StoreStar_Logic()
	GameLogic.Order.call_Formula_init()
	for pool in [GameLogic.Order.cur_LevelMenu, GameLogic.Order.cur_ExtraMenu]:
		for recipe in pool:
			if is_extra(recipe) and int(GameLogic.cur_levelInfo.ExtraMax) <= 0:
				continue
			if not recipe in GameLogic.cur_Menu and not recipe in available and int(pool[recipe].Rank) <= GameLogic.cur_StoreStar:
				available.append(recipe)
	return available

func is_extra(recipe):
	for tag in GameLogic.Order.EXTRATAGLIST:
		if tag in GameLogic.Config.FormulaConfig[recipe].Tag:
			return true
	return false

func menu_extras():
	var extras = []
	for recipe in GameLogic.cur_Menu:
		if is_extra(recipe):
			extras.append(recipe)
	return extras

func product_changed():
	var before = state.get("product_before", GameLogic.cur_Menu)
	var added = []
	var removed = []
	for recipe in GameLogic.cur_Menu:
		if not recipe in before:
			added.append(recipe)
	for recipe in before:
		if not recipe in GameLogic.cur_Menu:
			removed.append(recipe)
	var extras = menu_extras().size()
	if added.size() != 1 or removed.size() > 1 or extras > int(GameLogic.cur_levelInfo.ExtraMax) or GameLogic.cur_Menu.size() - extras > int(GameLogic.cur_levelInfo.MenuMax):
		return false
	return removed.empty() or is_extra(added[0]) == is_extra(removed[0])

func product_offers(redraw = false):
	if not redraw and state.has("product_offers"):
		return state.product_offers
	var drinks = []
	var extras = []
	for recipe in product_candidates():
		if is_extra(recipe):
			extras.append(recipe)
		else:
			drinks.append(recipe)
	drinks.shuffle()
	extras.shuffle()
	var offers = []
	# Keep both native categories available without introducing another menu.
	for _i in range(2):
		if not drinks.empty():
			offers.append(drinks.pop_back())
	if not extras.empty():
		offers.append(extras.pop_back())
	while offers.size() < 3 and (not drinks.empty() or not extras.empty()):
		offers.append(drinks.pop_back() if not drinks.empty() else extras.pop_back())
	state.product_offers = offers
	_store_state()
	GameLogic.call_save()
	return offers

func product_due():
	if not is_run() or state.get("failed", false) or product_stage() <= int(state.get("product_stage", 0)):
		return false
	return not product_candidates().empty()

func resume_product():
	preparing = false
	if not open_product_selection():
		state.phase = "prep"
		_store_state()
		GameLogic.GameUI.get_node("RewardUI").finish_rent_day()

func open_product_selection():
	if not authority():
		_message("房主正在选择本阶段新品，请稍候。")
		return false
	if not product_due() and state.get("phase", "prep") != "product":
		return false
	var room = get_tree().root.get_node_or_null("Level")
	if room == null:
		return false
	if room.has_node("RentProductCanvas"):
		return true
	if not state.has("product_before"):
		state.product_before = GameLogic.cur_Menu.duplicate()
	state.phase = "product"
	preparing = false
	_store_state()
	GameLogic.call_save()
	get_tree().paused = true
	coop.notify("product_wait")
	GameLogic.cur_DayType = "配方"
	GameLogic.cur_MenuNum = int(GameLogic.cur_levelInfo.MenuMax)
	GameLogic.cur_ExtraNum = int(GameLogic.cur_levelInfo.ExtraMax)
	GameLogic.cur_Extra = menu_extras()
	GameLogic.Can_Formula = not product_changed()
	var canvas = CanvasLayer.new()
	canvas.name = "RentProductCanvas"
	canvas.layer = 120
	room.add_child(canvas)
	var menu_ui = load("res://TscnAndGd/UI/InGame/MenuUI.tscn").instance()
	menu_ui.name = "RentProductMenu"
	menu_ui.set_meta("rent_product", true)
	canvas.add_child(menu_ui)
	menu_ui.call_init()
	menu_ui.AddNewLabel.text = "第 %d 天结束 · 选一款新品，满额需替换" % (product_stage() * 3)
	menu_ui.call_show()
	if product_changed():
		# A saved choice resumes at the native confirmation screen, including
		# its visible confirm button, rather than showing another set of cards.
		menu_ui.Ani.advance(0.5)
		menu_ui.Ani.play("select")
		menu_ui.Ani.advance(1.0)
		menu_ui.call_CanCheck()
	return true

func finish_product_selection():
	if state.get("phase", "prep") != "product" or not product_changed():
		return false
	state.product_stage = product_stage()
	state.erase("product_baseline")
	state.erase("product_before")
	state.erase("product_offers")
	state.phase = "prep"
	GameLogic.cur_DayType = "无"
	_store_state()
	GameLogic.call_save()
	return true

func advance_day():
	if not authority():
		return
	if state.get("failed", false) or GameLogic.GameOverType != -1:
		_show_result()
		return
	GameLogic.cur_Day += 1
	GameLogic.cur_Gift = remaining_rewards()
	_store_state()
	GameLogic.call_save()
	coop.broadcast_state()
	GameLogic.emit_signal("RewardUI")

func _show_result():
	if result_open:
		return
	if authority():
		_freeze_result()
		_store_state()
		GameLogic.call_save()
	if not preload("res://ftc_mods/ftc.rent_mode/RewardLedger.gd").valid(state.get("final_result")):
		_message("经营结算数据尚未同步，请等待房主。")
		return
	var record = _result_record()
	if authority():
		coop.notify("failed", {"result": state.final_result, "record": record, "settings": settings})
	result_open = true
	preparing = false
	_block_controls(false)
	GameLogic.GameUI.call_DayEnd_Close()
	notice.text = ""
	layer.layer = 210
	archive_ui = load("res://TscnAndGd/UI/InGame/RecordUI.tscn").instance()
	archive_ui.set_script(preload("res://ftc_mods/ftc.rent_mode/RentArchive.gd"))
	archive_ui.layer = 200
	archive_ui.pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().root.add_child(archive_ui)
	archive_ui.open_rent(self, record)
	get_tree().paused = true

func show_payout():
	if not result_open:
		return
	var game_end = GameLogic.GameUI.GameEndUI
	if not is_instance_valid(game_end) or not game_end.has_method("call_rent_result") or not game_end.call_rent_result(self):
		if is_instance_valid(archive_ui):
			archive_ui.claimed = false
		_message("绿钞结算暂时无法打开，请重试。")
		return
	if is_instance_valid(archive_ui):
		archive_ui.close_rent()
	archive_ui = null
	layer.layer = 130
	notice.text = ""
	GameLogic.Can_ESC = false

func _result_record():
	if not authority() and not remote_result_record.empty():
		return remote_result_record.duplicate(true)
	var data = GameLogic.Save.levelData
	if data.get("cur_level", "") != "房租模式":
		var checkpoint = GameLogic.Save.Config.get_value("FtcRentRun", "checkpoint", {})
		if checkpoint is Dictionary and checkpoint.get("level", {}) is Dictionary and checkpoint.level.get("cur_level", "") == "房租模式":
			data = checkpoint.level
	var result = state.final_result
	var saved_rewards = data.get("cur_Rewards", GameLogic.cur_Rewards)
	if not saved_rewards is Array:
		saved_rewards = []
	var saved_challenges = data.get("cur_Challenge", GameLogic.cur_Challenge)
	if saved_challenges is Dictionary:
		saved_challenges = saved_challenges.keys()
	elif not saved_challenges is Array:
		saved_challenges = []
	var saved_menu = data.get("level_menudata", GameLogic.level_menudata)
	if not saved_menu is Dictionary:
		saved_menu = {}
	var record = {
		"StartTime": str(data.get("StartTime", "")),
		"SPECIALLEVEL_Int": 0,
		"GameOverType": int(GameLogic.GameOverType) if GameLogic.GameOverType >= 0 else 2,
		"cur_level": "房租模式",
		"cur_Devil": int(data.get("cur_Devil", GameLogic.cur_Devil)),
		"Day": int(result.day),
		"ProfitTotal": max(0, int(result.get("peak_cash", result.cash))),
		"Total_Rewards": saved_rewards.duplicate(true),
		"Total_Challenge": saved_challenges.duplicate(true),
		"level_menudata": saved_menu.duplicate(true),
		"BuyCount": int(data.get("level_BuyUpdate", GameLogic.level_BuyUpdate))
	}
	if data.get("PlayerIDDic", {}) is Dictionary:
		record.PlayerIDDic = data.get("PlayerIDDic", {}).duplicate(true)
	var history = data.get("DAYINFO", {})
	if history is Dictionary:
		for key in history:
			if not str(key).begins_with("Day_") and not record.has(key):
				var value = history[key]
				record[key] = value.duplicate(true) if value is Dictionary or value is Array else value
		for day in range(1, int(result.day) + 1):
			var key = "Day_" + str(day)
			if history.get(key, {}) is Dictionary and history.has(key):
				record[key] = history[key].duplicate(true)
		if record.Total_Rewards.empty() and history.get("Total_Rewards", []) is Array:
			record.Total_Rewards = history.get("Total_Rewards", []).duplicate(true)
		if record.Total_Challenge.empty():
			var challenges = history.get("Total_Challenge", [])
			if challenges is Array:
				record.Total_Challenge = challenges.duplicate(true)
			elif challenges is Dictionary:
				record.Total_Challenge = challenges.keys()
	for key in ["level_Perfect", "level_Good", "level_Bad", "level_Lose", "level_Quickly", "level_Skipping", "level_Nearly", "level_Cri"]:
		record[key] = int(data.get(key, GameLogic.get(key)))
	return record

func _new_run_id():
	return "%s:%s:%s" % [SdkManager.user_id, OS.get_unix_time(), OS.get_ticks_usec()]

func _freeze_result():
	if state.has("final_result"):
		_remember_best_days(int(state.final_result.get("day", 0)))
		return
	if not state.has("run_id"):
		state.run_id = _new_run_id()
	state.final_result = {"id": str(state.run_id), "cash": int(GameLogic.cur_money), "peak_cash": max(int(state.get("peak_money", GameLogic.cur_money)), int(GameLogic.cur_money)), "pressure": int(settings.get("pressure", 50)), "day": int(GameLogic.cur_Day)}
	_remember_best_days(int(GameLogic.cur_Day))

func record_peak_money(amount):
	if state.empty() or state.get("failed", false):
		return
	state.peak_money = max(int(state.get("peak_money", 0)), int(amount))

func claim_result():
	if not result_open:
		return false
	if reward_ledger == null:
		reward_ledger = preload("res://ftc_mods/ftc.rent_mode/RewardLedger.gd").new()
	var claim_data = state.final_result.duplicate(true)
	claim_data.map = str(settings.get("map", ""))
	claim_data.tier = clamp(int((int(settings.get("store_difficulty_multiplier", 1)) - 1) / 2), 0, 2)
	if not reward_ledger.claim(GameLogic.Save._home_rent_path(), claim_data, GameLogic):
		return false
	if _offline():
		GameLogic.Save._saveLogic(GameLogic.Save._home_rent_path())
	# Let the button callback finish before an offline/all-confirmed result closes.
	coop.call_deferred("result_claimed", str(state.final_result.id))
	return true

func close_result():
	if is_instance_valid(archive_ui):
		archive_ui.close_rent()
	archive_ui = null
	var game_end = GameLogic.GameUI.GameEndUI
	if is_instance_valid(game_end) and game_end.has_method("close_rent_result"):
		game_end.close_rent_result()
	layer.layer = 130
	result_open = false
	get_tree().paused = false
	_block_controls(false)
	GameLogic.GameOverType = -1
	GameLogic.MissionComplete_bool = false

func _return_to_setup():
	if not authority():
		_message("请等待房主返回家里。")
		return
	close_result()
	GameLogic.GameUI.call_DayEnd_Close()
	# This run is already settled by RentMode. Home's native mission check must
	# not settle it a second time as a campaign win/loss.
	GameLogic.GameOverType = -1
	GameLogic.MissionComplete_bool = false
	awaiting_bus = false
	# Reload the normal checkpoint from the shared save so the next bus ride
	# sees the normal level, money and difficulty rather than the finished rent.
	GameLogic.call_load()

func _save_now():
	if not is_run() or not preparing or GameLogic.GameUI.DayEnd or get_tree().paused:
		_message("请在开店前保存；营业结束时也会自动保存。")
		return
	var furniture = api.service("ftc.furniture_carry", "carry")
	if furniture != null:
		furniture.cancel()
	if GameLogic.player_1P.Con.IsHold:
		_message("请先放下手上的物品，再保存家具布局。")
		return
	var level = get_tree().root.get_node("Level")
	level._dev_save()
	level._item_save()
	_store_state()
	GameLogic.call_save()
	_message("已保存经营进度和当前家具布局。")

func _block_controls(block):
	if block and not controls_blocked:
		controls_were_enabled = GameLogic.Con.is_processing_input()
		GameLogic.Con.set_process_input(false)
		controls_blocked = true
	elif not block and controls_blocked:
		GameLogic.Con.set_process_input(controls_were_enabled)
		controls_blocked = false

