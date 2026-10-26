extends "res://TscnAndGd/Logics/GameLogic/GameLogic.gd"

func call_NewLevel_Init():
	var market = get_node_or_null("/root/TalentMarket")
	if market != null:
		market.new_run()
	.call_NewLevel_Init()

func _save():
	var market = get_node_or_null("/root/TalentMarket")
	if market != null:
		market.store_state()
	._save()

func _DATALOAD(data):
	._DATALOAD(data)
	var market = get_node_or_null("/root/TalentMarket")
	if market != null:
		market.restore_state()
