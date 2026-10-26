extends "res://TscnAndGd/UI/InGame/MenuUI.gd"

func _rent_product():
	return has_meta("rent_product") and get_node("/root/RentMode").is_run()

func call_New_Formula_Set():
	if not _rent_product():
		.call_New_Formula_Set()
		return
	var rent = get_node("/root/RentMode")
	var offers = rent.product_offers()
	Can_Re = rent.product_candidates().size() > 3
	for i in range(3):
		var button = NewMenuVBox.get_node(str(i))
		button.visible = i < offers.size()
		button.disabled = i >= offers.size()
		if i < offers.size():
			button.ForName = offers[i]
			button._MenuButton_set()

func _on_Re_pressed():
	if not _rent_product():
		._on_Re_pressed()
		return
	var rent = get_node("/root/RentMode")
	if cur_STATE != STATE.MAIN or rent.product_changed() or not Can_Re or GameLogic.cur_ReDrawCoin <= 0:
		return
	GameLogic.cur_ReDrawCoin -= 1
	rent.product_offers(true)
	call_New_Formula_Set()
	get_node("Re/RandomCoin/Label").text = str(GameLogic.cur_ReDrawCoin)
	GameLogic.call_ReDrawCoinChange()
	GameLogic.call_save()
	But_0_grabfocus()

func _on_NewMenu_pressed():
	if _rent_product():
		var rent = get_node("/root/RentMode")
		if rent.product_changed():
			call_CanCheck()
			return
		GameLogic.cur_Extra = rent.menu_extras()
	._on_NewMenu_pressed()

func call_add_formula():
	if not _rent_product():
		.call_add_formula()

func call_NewFormula_Logic():
	if not _rent_product():
		.call_NewFormula_Logic()
		return
	var rent = get_node("/root/RentMode")
	if rent.product_changed() or not cur_Select_For in rent.product_offers() or cur_Select_For in GameLogic.cur_Menu:
		return
	GameLogic.cur_Extra = rent.menu_extras()
	cur_Extra_Bool = rent.is_extra(cur_Select_For)
	.call_NewFormula_Logic()
	if rent.product_changed():
		GameLogic.cur_Extra = rent.menu_extras()
		GameLogic.call_save()

func _on_BackBut_pressed():
	var rent = get_node_or_null("/root/RentMode")
	if rent != null and rent.is_run() and has_meta("rent_product"):
		if not rent.finish_product_selection():
			AddNewLabel.text = "请先选择一款新品，再确认菜单"
			return
		for signal_name in ["P1_Control", "P2_Control"]:
			if GameLogic.Con.is_connected(signal_name, self, "_control_logic"):
				GameLogic.Con.disconnect(signal_name, self, "_control_logic")
		get_parent().queue_free()
		GameLogic.GameUI.get_node("RewardUI").finish_rent_day()
		return
	._on_BackBut_pressed()
