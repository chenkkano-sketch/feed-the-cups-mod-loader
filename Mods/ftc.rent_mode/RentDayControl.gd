extends "res://TscnAndGd/UI/InGame/DayControl.gd"

func call_init():
	if GameLogic.cur_level != "房租模式":
		.call_init()
		return
	call_del()
	cur_TYPE = "无"
	GameLogic.cur_DayType = "无"
	get_node("DAYLabel").text = "DAY " + str(GameLogic.cur_Day)

func call_newday(day, special):
	if GameLogic.cur_level != "房租模式":
		.call_newday(day, special)
	else:
		cur_TYPE = "无"
		GameLogic.cur_DayType = "无"
