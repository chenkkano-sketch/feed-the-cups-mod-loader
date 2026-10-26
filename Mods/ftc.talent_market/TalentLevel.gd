extends "res://TscnAndGd/Main/Level/NewLevel.gd"

func _dev_save():
	var market = get_node_or_null("/root/TalentMarket")
	if market != null:
		market.before_layout_save(self)
	._dev_save()

func _item_save():
	var market = get_node_or_null("/root/TalentMarket")
	if market != null:
		market.before_layout_save(self)
	._item_save()
