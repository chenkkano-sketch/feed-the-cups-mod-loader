extends "res://TscnAndGd/Logics/GameLogic/GameLogic.gd"

func call_SceneConfig_load(reload = false):
	.call_SceneConfig_load(reload)
	if cur_level != "房租模式":
		return
	var rent = get_node_or_null("/root/RentMode")
	if rent == null or not cur_levelInfo is Dictionary or not Config.SceneConfig.has("房租模式"):
		return
	if SdkManager.return_ismember():
		# The native lobby packet already contains the host's final shop profile.
		# Reapplying rent difficulty here would multiply Popular a second time.
		cur_PV = clamp(int(cur_levelInfo.get("PV", 6)), 1, 10)
		return
	var multiplier = int(rent.settings.get("store_difficulty_multiplier", 1))
	var base_star = int(Config.SceneConfig["房租模式"].Popular)
	var devil_bonus = max(0, int(cur_levelInfo.Popular) - base_star)
	cur_levelInfo.Popular = min(10, max(1, base_star) * multiplier + devil_bonus)
	cur_levelInfo.StarMax = max(int(cur_levelInfo.get("StarMax", 10)), int(cur_levelInfo.Popular))
	# Native traffic level 5 is "络绎不绝". Rent's "火爆" uses level 6.
	cur_levelInfo.PV = "6"
	cur_PV = 6

func call_MoneyChange(value, key = 0):
	.call_MoneyChange(value, key)
	var rent = get_node_or_null("/root/RentMode")
	if rent != null and rent.authority() and rent.is_run():
		rent.record_peak_money(cur_money)
		rent._record_daily_income()

func call_dayover():
	var rent = get_node_or_null("/root/RentMode")
	if rent != null:
		rent.api.log("day_end.begin tick=%s day=%s map=%s orders=%s already_ending=%s" % [OS.get_ticks_msec(), cur_Day, rent.settings.get("map", ""), Order.cur_OrderList.size(), _DayOver_Bool])
	.call_dayover()
	if rent != null:
		rent.api.log("day_end.return tick=%s paused=%s end=%s" % [OS.get_ticks_msec(), get_tree().paused, GameUI.DayEnd])

func call_LevelLoad(level, type = 0):
	var rent = get_node_or_null("/root/RentMode")
	if rent != null and rent.authority() and level == "房租模式" and rent.awaiting_bus and LoadingUI.IsHome:
		rent.awaiting_bus = false
		# HomeBusStation already broadcast the native LoadingLevel packet.
		rent.coop.begin_run()
		.call_LevelLoad(level, type)
		return
	if rent != null and rent.authority() and level == "房租模式" and LoadingUI.IsHome:
		# A legacy saved rent contract can also be boarded directly. Restore its
		# checkpoint and use this same bus departure to enter the shop.
		if rent._continue_from_home():
			rent.awaiting_bus = false
			rent.coop.begin_run()
			.call_LevelLoad(level, type)
		return
	.call_LevelLoad(level, type)

func call_LevelData_Load():
	var rent = get_node_or_null("/root/RentMode")
	if SdkManager.return_ismember():
		if rent != null:
			rent.coop.restore_lobby()
		.call_LevelData_Load()
		return
	if rent != null and Save.levelData.get("cur_level", "") == "房租模式":
		if rent.restoring:
			_DATALOAD(Save.levelData)
			Order.call_Formula_init()
			MissionComplete_bool = false
		else:
			# The saved rent checkpoint belongs in its own slot. Leaving it in
			# the live normal campaign state makes the bus reload Home.
			Save.restore_normal_home_state()
			_DATALOAD(Save.levelData)
			Order.call_Formula_init()
			GameOverType = -1
			call_HomeLoad()
		return
	.call_LevelData_Load()

func call_LobbyData_Load():
	var rent = get_node_or_null("/root/RentMode")
	if rent != null:
		rent.coop.restore_lobby()
	.call_LobbyData_Load()
	if rent != null and SdkManager.return_ismember() and SdkManager.lobby_level_data.get("cur_level", "") == "房租模式":
		# Native LoadingLevel resolves the scene immediately after this call.
		# The native lobby load sets the day first, so the endless day list also
		# covers late joins beyond the first 32 days.
		Config._SceneConfig()
		cur_PV = clamp(int(cur_levelInfo.get("PV", 6)), 1, 10)
