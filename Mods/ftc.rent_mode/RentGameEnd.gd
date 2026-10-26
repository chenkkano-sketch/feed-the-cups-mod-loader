extends "res://TscnAndGd/UI/InGame/GameEndUI.gd"

var rent_result = false
var rent_claimed = false
var rent_mode
var original_caption = ""
var original_caption_visible = true
var original_day_visible = true
var original_day_modulate = Color(1, 1, 1, 1)
var original_base_label = ""
var original_first_visible = true

func _GameOver_Logic(complete, reward):
	var mode = get_node_or_null("/root/RentMode")
	if mode != null and mode.is_run():
		mode.state.failed = true
		mode._show_result()
		return
	._GameOver_Logic(complete, reward)

func call_rent_result(mode):
	if rent_result:
		return true
	if _INIT_BOOL:
		return false
	rent_mode = mode
	rent_result = true
	rent_claimed = false
	var caption = RateLabel.get_node("Label")
	var day_control = get_node("Control/DayControl")
	var base_label = get_node("Control/BG/InfoControl/Reward/StoreBaseValueLabel")
	var first = get_node("Control/BG/InfoControl/Reward/StoreValueLabel/First")
	original_caption = caption.text
	original_caption_visible = caption.visible
	original_day_visible = day_control.visible
	original_day_modulate = day_control.modulate
	original_base_label = base_label.text
	original_first_visible = first.visible
	_INIT_BOOL = true
	_ShowEND = false
	FirstPassReward = 0
	# Reuse the native payout animation; the reward ledger owns the actual award.
	get_tree().paused = true
	call_ResetGift()
	TypeAni.play("1" if int(mode.state.final_result.cash) < 0 else "0")
	call_init()
	call_UI_But()
	Ani.playback_speed = 1
	Ani.play("play")
	get_node("DemoEnd/Ani").play("init")
	GameLogic.Can_ESC = false
	call_Can_Move(false)
	EndAccountNode = EndAccount_TSCN.instance()
	EndAccountNode.ICONNUM = max(0, int(mode.state.final_result.get("peak_cash", mode.state.final_result.cash)))
	EndAccountNode.CUPNUM = GameLogic.level_SellTotal
	call_control()
	add_child(EndAccountNode)
	EndAccountNode.connect("Finished", self, "Show_End")
	EndAccountNode.call_show()
	day_control.hide()
	day_control.modulate = Color(original_day_modulate.r, original_day_modulate.g, original_day_modulate.b, 0)
	get_tree().paused = true
	return true

func call_init():
	if not rent_result:
		.call_init()
		return
	Mult_Logic()
	for pair in [["Perfect", GameLogic.level_Perfect], ["Good", GameLogic.level_Good], ["Bad", GameLogic.level_Bad]]:
		get_node("Control/BG/InfoControl/Review/" + pair[0] + "/Label").text = str(pair[1])
	get_node("Control/DayControl").call_init()
	get_node("Control/DayControl").hide()
	get_node("Control/DayControl").modulate = Color(original_day_modulate.r, original_day_modulate.g, original_day_modulate.b, 0)
	CurChoose.hide()

func Mult_Logic():
	if not rent_result:
		.Mult_Logic()
		return
	var result = rent_mode.state.final_result
	StoreValue = max(0, int(result.get("peak_cash", result.cash)))
	_MAXNUM = rent_mode.Rules.failure_reward_cap(result)
	FINAL_VALUE = rent_mode.Rules.failure_reward(StoreValue, result)
	RateLabel.text = "5%"
	var caption = RateLabel.get_node("Label")
	caption.text = ""
	caption.hide()
	get_node("Control/BG/InfoControl/Reward/StoreBaseValueLabel").text = "最高杯币"
	StoreBaseValueLabel.text = str(StoreValue)
	TotalHomeMoneyLabel.text = str(FINAL_VALUE)
	HomeMoneyValueLabel.text = str(FINAL_VALUE)
	HomeMoneyLabel.text = str(GameLogic.return_FullHMK())
	get_node("Control/BG/InfoControl/Reward/StoreValueLabel/First").hide()
	get_node("Control/BG/InfoControl/Reward/StoreValueLabel/Label/Icon/MaxLabel").visible = FINAL_VALUE >= _MAXNUM

func call_CurCard_init():
	if not rent_result:
		.call_CurCard_init()

func Show_End():
	.Show_End()
	if rent_result:
		get_node("Control/DayControl").hide()
		get_node("Control/DayControl").modulate = Color(original_day_modulate.r, original_day_modulate.g, original_day_modulate.b, 0)

func _on_Button_pressed():
	if not rent_result:
		._on_Button_pressed()
		return
	if not cur_show or rent_claimed:
		return
	if rent_mode.claim_result():
		rent_claimed = true
		get_node("Button").disabled = true
	else:
		var caption = RateLabel.get_node("Label")
		caption.text = rent_mode.reward_ledger.error
		caption.show()

func close_rent_result():
	if not rent_result:
		return
	Ani.play("init")
	get_node("Button").disabled = false
	cur_show = false
	if GameLogic.Con.is_connected("P1_Control", self, "_control_logic"):
		GameLogic.Con.disconnect("P1_Control", self, "_control_logic")
	if GameLogic.Con.is_connected("P2_Control", self, "_control_logic"):
		GameLogic.Con.disconnect("P2_Control", self, "_control_logic")
	if is_instance_valid(EndAccountNode):
		EndAccountNode.queue_free()
	EndAccountNode = null
	RateLabel.get_node("Label").text = original_caption
	RateLabel.get_node("Label").visible = original_caption_visible
	get_node("Control/DayControl").visible = original_day_visible
	get_node("Control/DayControl").modulate = original_day_modulate
	get_node("Control/BG/InfoControl/Reward/StoreBaseValueLabel").text = original_base_label
	get_node("Control/BG/InfoControl/Reward/StoreValueLabel/First").visible = original_first_visible
	_INIT_BOOL = false
	rent_result = false
	rent_mode = null
	GameLogic.Can_ESC = true
	call_Can_Move(true)
