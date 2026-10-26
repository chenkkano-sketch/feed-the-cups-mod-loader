extends "res://TscnAndGd/UI/InGame/ChooseShop.gd"

const Rules = preload("res://ftc_mods/ftc.rent_mode/RentRules.gd")
var rent_tier = 0

func _rent_entry():
	return get_parent().get_parent().has_meta("ftc_rent_entry")

func _Level_Check():
	if not _rent_entry():
		._Level_Check()
		return
	var ranks = [Level_Rank1, Level_Rank2, Level_Rank3, Level_Rank4]
	for index in range(4):
		var button = DifficultyNode.get_node(str(index + 1))
		button.call_unlock(ranks[index] != "" and ranks[index] != "新手引导第一关")
	var rank = 4
	while rank > 1 and ranks[rank - 1] == "":
		rank -= 1
	DifficultyNode.get_node(str(rank)).pressed = true
	cur_Press = str(rank)
	call_cur_level(cur_Press)

func call_show(type, player_id):
	.call_show(type, player_id)
	if not _rent_entry():
		return
	get_node("Control/BG/LevelName/TitleLabel").text = "房租模式 选择店铺"
	# The last original shop in a category is the default rent shop.
	DifficultyNode.get_node(cur_Press).pressed = true
	rent_tier = 0
	_on_Difficulty_pressed()

func call_Devil_Set(type):
	if not _rent_entry():
		.call_Devil_Set(type)
		return
	if type == "+":
		rent_tier = min(2, rent_tier + 1)
	elif type == "-":
		rent_tier = max(0, rent_tier - 1)
	GameLogic.Audio.But_EasyClick.play(0)
	_refresh_rent_caption()

func _on_Difficulty_pressed():
	._on_Difficulty_pressed()
	if _rent_entry():
		_lock_native_devil()
		_refresh_rent_caption()

func call_new_info():
	.call_new_info()
	if _rent_entry():
		_refresh_best_days()
	else:
		_restore_normal_best_caption()

func _best_money_icon(best):
	var icon = best.get_node_or_null("Label/MoneyIcon")
	return icon if icon != null else best.get_node_or_null("MoneyIcon")

func _restore_normal_best_caption():
	var best = get_node("Control/通关信息/BaseInfo1/HighMoney")
	best.text = "最高收入"
	var icon = _best_money_icon(best)
	if icon != null:
		icon.show()

func _refresh_best_days():
	if not _rent_entry() or not GameLogic.Config.SceneConfig.has(cur_Select):
		return
	var record = get_node("Control/通关信息")
	record.show()
	var best = record.get_node("BaseInfo1/HighMoney")
	best.text = "最高坚持天数"
	best.get_node("Label").text = "%d天" % get_node("/root/RentMode").best_days_for(cur_Select, rent_tier)
	var money_icon = _best_money_icon(best)
	if money_icon != null:
		money_icon.hide()
	if not GameLogic.Level_Data.has(cur_Select):
		record.get_node("BaseInfo2/SellTotal/Label").text = "0"

func _lock_native_devil():
	if not GameLogic.Config.SceneConfig.has(cur_Select):
		return
	var source = GameLogic.Config.SceneConfig[cur_Select]
	Devil_Max = max(1, int(source.DevilMax))
	cur_Devil = Devil_Max - 1
	Devil_Finished = cur_Devil
	var choose = get_node("Control/Choose")
	choose.show()
	var icons = choose.get_node("HBox")
	for old_icon in icons.get_children():
		icons.remove_child(old_icon)
		old_icon.queue_free()
	for index in range(Devil_Max):
		var icon = GameLogic.TSCNLoad.DevilIcon_TSCN.instance()
		icon.name = str(index)
		icons.add_child(icon)
		icons.move_child(icon, 0)
		icon.call_type(index)
		if index > 0 and source.DevilList.size() >= index:
			icon.call_Str(source.DevilList[index - 1])
		icon.get_node("Ani").play("select")
	change_logic()

func call_Traffic_set():
	.call_Traffic_set()
	if _rent_entry():
		_show_rent_traffic()

func _show_rent_traffic():
	TrafficLabel.get_node("AnimationPlayer").stop()
	TrafficLabel.text = "火爆"
	TrafficLabel.add_color_override("font_color", Color(1, 0.12, 0.08))

func _refresh_rent_caption():
	if not _rent_entry() or not GameLogic.Config.SceneConfig.has(cur_Select):
		return
	var pressure = 35 + 30 * rent_tier
	DailyRentLabel.text = str(Rules.rent_for_day({"curve": "staged", "rent": 150, "pressure": pressure}, 1))
	DayCountLabel.text = "无限"
	get_node("Control/InfoBG/BaseInfo1/DayCount/Label/Icon").hide()
	var reward_row = get_node("Control/InfoBG/BaseInfo1/Reward")
	reward_row.text = "房租压力"
	RewardLabel.text = "%d%%" % pressure
	RewardLabel.get_node("Sprite").hide()
	var popular = get_node("Control/InfoBG/BaseInfo1/Popular")
	popular.text = "初始店铺难度"
	popular.get_node("HBox").hide()
	var difficulty_value = popular.get_node_or_null("RentDifficultyValue")
	if difficulty_value == null:
		difficulty_value = Label.new()
		difficulty_value.name = "RentDifficultyValue"
		difficulty_value.anchor_left = 1.0
		difficulty_value.anchor_right = 1.0
		difficulty_value.margin_left = -110
		difficulty_value.margin_right = 64
		difficulty_value.margin_bottom = 32
		difficulty_value.align = Label.ALIGN_RIGHT
		difficulty_value.valign = Label.VALIGN_CENTER
		difficulty_value.add_font_override("font", RewardLabel.get_font("font"))
		difficulty_value.add_color_override("font_color", Color(1, 0.78, 0))
		popular.add_child(difficulty_value)
	difficulty_value.text = ["简单", "普通", "困难"][rent_tier]
	var reward_max = get_node("Control/InfoBG/BaseInfo2/RewardMax")
	reward_max.text = "绿钞上限"
	RewardMaxLabel.text = str(Rules.failure_reward_cap({"pressure": pressure}))
	RewardGet.text = "初始客流量"
	RewardGetLabel.get_node("AnimationPlayer").stop()
	RewardGetLabel.get_node("Sprite").hide()
	RewardGetLabel.add_color_override("font_color", Color(1, 0.12, 0.08))
	RewardGetLabel.hint_tooltip = "预计首日总客流，包含路过与进店顾客；实际人数会随经营情况变化。"
	RewardGetLabel.text = "约%d人" % _initial_customer_count()
	RewardGet.show()
	_refresh_best_days()
	var tips = get_node("Control/InfoBG/GamePlay")
	tips.get_node("1").text = "【房租模式】在房租模式下，每日开门营业前时间暂停，可以尽情调整布局和备餐。"
	tips.get_node("2").text = ""
	tips.get_node("3").text = ""
	_show_rent_traffic()

func _initial_customer_count():
	var source = GameLogic.Config.SceneConfig[cur_Select]
	var profile = GameLogic.Config.SceneConfig.get("房租模式", {})
	var devil_factor = 0.8 if cur_Devil == 0 else (0.9 if cur_Devil == 1 else 1.0)
	# Native traffic level 6 has a base spawn rate of 27 per hundred ticks.
	# Count both passers and customers; one game hour is 50 seconds.
	var traffic_rate = 0.27 * GameLogic.return_Multiplier() * devil_factor
	var open_time = float(source.OpenTime)
	var close_time = float(source.CloseTime)
	if close_time <= open_time:
		close_time += 24.0
	var expected = 0.0
	for hour in range(int(floor(open_time)), int(ceil(close_time))):
		var duration = max(0.0, min(close_time, float(hour + 1)) - max(open_time, float(hour)))
		var traffic = float(profile.get(str(hour % 24), 50))
		expected += duration * 50.0 * traffic / max(1.0, float(GameLogic.GameUI.TrafficMax)) * traffic_rate
	return max(0, int(round(expected)))

func _Apply_Logic():
	if not _rent_entry():
		._Apply_Logic()
		return
	var mode = get_node_or_null("/root/RentMode")
	if mode == null or not mode.start_from_selection(cur_Select, rent_tier):
		return
	_on_Apply_button_up()
	for signal_name in ["P1_Control", "P2_Control"]:
		if GameLogic.Con.is_connected(signal_name, self, "_control_logic"):
			GameLogic.Con.disconnect(signal_name, self, "_control_logic")
	Ani.play("hide")
	call_UI_hide()
	GameLogic.Can_ESC = true
	show_bool = false
