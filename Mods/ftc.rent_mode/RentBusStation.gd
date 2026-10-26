extends "res://TscnAndGd/Objects/Home/HomeBusStation.gd"

func _on_Timer_timeout():
	var rent = get_node_or_null("/root/RentMode")
	if rent != null and rent.authority() and GameLogic.LoadingUI.IsHome and GameLogic.cur_level == "房租模式" and not rent.awaiting_bus:
		# The native bus sends LoadingLevel before it calls GameLogic.call_LevelLoad.
		# Restore an older rent checkpoint first so that native packet contains
		# the correct shop, save data and multiplayer player slots.
		if not SdkManager.is_multiplay or _CurNum == SdkManager.lobby_members.size():
			if not rent._continue_from_home():
				return
	._on_Timer_timeout()
