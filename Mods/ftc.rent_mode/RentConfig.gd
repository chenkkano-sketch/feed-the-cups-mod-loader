extends "res://TscnAndGd/Logics/SystemLogic/ConfigLogic.gd"

func _SceneConfig():
	._SceneConfig()
	if SceneConfig.has("房租模式"):
		var mode = get_node_or_null("/root/RentMode")
		var settings = mode.settings if mode != null else {}
		var room = preload("res://ftc_mods/ftc.rent_mode/RentMaps.gd").selected(settings)
		if settings.get("progression", "legacy") == "native":
			var source = SceneConfig[room.level]
			for key in preload("res://ftc_mods/ftc.rent_mode/RentMaps.gd").PROFILE_FIELDS:
				var value = source[key]
				SceneConfig["房租模式"][key] = value.duplicate(true) if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY] else value
		SceneConfig["房租模式"].TSCN = room.get("scene", "RentRoom_" + room.id)
		SceneConfig["房租模式"].IndoorArea = str(room.area)
		# Native progression widgets expect future days in this list.
		# DayControl renders only the current day, so this never creates a huge UI.
		var days = []
		for _i in range(max(32, int(get_parent().cur_Day) + 2)):
			days.append("无")
		SceneConfig["房租模式"].Difficult = days
