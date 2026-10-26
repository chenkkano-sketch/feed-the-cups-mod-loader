extends "res://TscnAndGd/UI/InGame/RewardUI.gd"

func call_select(button):
	var was_used = cur_used
	.call_select(button)
	if GameLogic.cur_level == "房租模式" and was_used and not cur_used:
		get_node("/root/RentMode").reward_selected()

func call_end():
	var rent = get_node_or_null("/root/RentMode")
	if rent != null and rent.is_run() and not rent.authority():
		return
	if rent != null and rent.is_run() and rent.remaining_rewards() == 0 and rent.open_product_selection():
		Ani.play("init")
		cur_used = false
		call_disconnect()
		return
	.call_end()

func finish_rent_day():
	.call_end()
