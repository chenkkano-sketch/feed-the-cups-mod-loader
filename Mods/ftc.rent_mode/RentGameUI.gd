extends "res://TscnAndGd/UI/InGame/GameUI.gd"

const Rules = preload("res://ftc_mods/ftc.rent_mode/RentRules.gd")

func call_curTraffic_set():
	.call_curTraffic_set()
	if GameLogic.cur_level == "房租模式":
		# Native _curTraffic_set applies opening/closing traffic cards after this
		# call and then splits the scaled rate into customers and passers-by.
		PV_Max *= Rules.traffic_multiplier(GameLogic.cur_Day)

func _on_Timer_timeout():
	var rent = get_node_or_null("/root/RentMode")
	if rent != null and rent.is_run() and rent.preparing:
		return
	._on_Timer_timeout()

