extends "res://TscnAndGd/UI/InGame/DayEndUI.gd"

func call_DayEnd():
	if GameLogic.cur_level != "房租模式":
		.call_DayEnd()
		return
	if ENDCHECK:
		return
	# Original water, electricity, ingredients, staff and fines are still charged.
	GameLogic.cur_Rent = 0
	var rent = get_node("/root/RentMode")
	rent.api.log("day_end.native.begin tick=%s" % OS.get_ticks_msec())
	.call_DayEnd()
	rent.api.log("day_end.rent.begin tick=%s" % OS.get_ticks_msec())
	rent.settle_day(self)
	rent.api.log("day_end.rent.done tick=%s" % OS.get_ticks_msec())

func call_rent_settlement(cash, profit, cost, rent_amount, over):
	if GameLogic.cur_level != "房租模式" or not SdkManager.return_ismember():
		return
	GameLogic.cur_money = int(cash)
	GameLogic.level_ProfitTotal = int(profit)
	GameLogic.level_MoneyCostTotal = int(cost)
	GameLogic.GameOverType = int(over)
	get_node("/root/RentMode").apply_settlement_ui(self, int(rent_amount))

func _Back_Logic():
	if GameLogic.cur_level != "房租模式":
		._Back_Logic()
		return
	if not get_node("/root/RentMode").authority():
		return
	if not cur_show:
		return
	if TYPE == 0:
		get_tree().root.get_node("Level").call_level_save()
		if Ani.assigned_animation != "0":
			return
		SdkManager.call_puppet_node_sync(Self, "call_Back_puppet", [0, GameLogic.GameOverType, GameLogic.SPECIAL_NUM])
		cur_show = false
		GameLogic.Audio.But_Apply.play(0)
		Ani.playback_speed = 1
		Ani.play("1")
		TYPE = 1
	elif TYPE == 1:
		SdkManager.call_puppet_node_sync(Self, "call_Back_puppet", [1, GameLogic.GameOverType, GameLogic.SPECIAL_NUM])
		cur_show = false
		GameLogic.Audio.But_Apply.play(0)
		GameLogic.GameUI.DayEnd = true
		Ani.play("init")
		ENDCHECK = false
		TYPE = 2
		get_node("/root/RentMode").advance_day()
