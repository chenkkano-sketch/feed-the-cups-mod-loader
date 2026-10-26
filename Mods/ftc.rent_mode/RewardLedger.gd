extends Reference

const Rules = preload("res://ftc_mods/ftc.rent_mode/RentRules.gd")
const Home = preload("res://ftc_mods/ftc.rent_mode/Sync/HomeSync.gd")
const RECEIPTS = "ftc_rent_reward_receipts"
const BEST_DAYS = "ftc_rent_best_days"
var error = ""
var storage

static func valid(result):
	if not result is Dictionary or not result.get("id") is String or result.id.empty() or result.id.length() > 160:
		return false
	for key in ["cash", "pressure", "day"]:
		if not typeof(result.get(key)) in [TYPE_INT, TYPE_REAL] or is_nan(float(result[key])) or is_inf(float(result[key])):
			return false
	if result.has("peak_cash") and (not typeof(result.peak_cash) in [TYPE_INT, TYPE_REAL] or is_nan(float(result.peak_cash)) or is_inf(float(result.peak_cash)) or abs(float(result.peak_cash)) > Rules.MAX_RENT):
		return false
	if result.has("map") != result.has("tier"):
		return false
	if result.has("map") and (not result.map is String or not Rules.Maps.has_room(result.map) or typeof(result.tier) != TYPE_INT or result.tier < 0 or result.tier > 2):
		return false
	return abs(float(result.cash)) <= Rules.MAX_RENT and result.pressure >= 0 and result.pressure <= 100 and result.day >= 1

func claim(path, result, game):
	error = ""
	if not valid(result):
		error = "经营结算数据无效。"
		return false
	var io = storage if storage != null else Home.new()
	var expected_hash = io._hash(path)
	var config = _read_reward_save(path)
	if config == null:
		return false
	var receipts = config.get_value("Game", RECEIPTS, {})
	if not receipts is Dictionary:
		error = "奖励领取记录异常，已保留原存档。"
		return false
	var best_days = config.get_value("Game", BEST_DAYS, {})
	if not best_days is Dictionary:
		best_days = {}
	best_days = best_days.duplicate(true)
	var best_changed = false
	if result.has("map"):
		var best_key = "%s:%d" % [result.map, result.tier]
		if int(result.day) > int(best_days.get(best_key, 0)):
			best_days[best_key] = int(result.day)
			best_changed = true
	if receipts.has(result.id):
		# The receipt and encoded money are committed in the same atomic file.
		# Reloading an older run or receiving a repeated packet cannot pay twice.
		if best_changed:
			config.set_value("Game", BEST_DAYS, best_days)
			var best_write_error = io._write(config, path, expected_hash)
			if best_write_error != OK:
				error = "最高天数保存失败（%s），可重试。" % best_write_error
				return false
			game.Save.gameData[BEST_DAYS] = best_days.duplicate(true)
			game.Save.Config.set_value("Game", BEST_DAYS, best_days.duplicate(true))
		game.Save.gameData[RECEIPTS] = receipts.duplicate(true)
		game.Save.Config.set_value("Game", RECEIPTS, receipts.duplicate(true))
		return true
	var amount = Rules.failure_reward(result.get("peak_cash", result.cash), result)
	var before = Home.Rules.snapshot(config)
	if not before.valid:
		error = "自己的绿钞数据无效，奖励尚未领取：" + str(before.get("error", ""))
		return false
	var old_money = game.cur_HOMEMONEY
	var old_key = game.HomeMoneyKey
	var old_data = game.Save.gameData.duplicate(true)
	# Read personal currency, never the host's lobby dictionaries. Use the same
	# native currency API and wallet limit as the campaign result screen.
	game.HomeMoneyKey = int(before.money_key)
	game.cur_HOMEMONEY = Vector2(float(int(before.cash / 10000)) / game.HomeMoneyKey, float(int(before.cash) % 10000) / game.HomeMoneyKey)
	if amount > 0 and not game.call_MoneyHomeChange(amount, game.HomeMoneyKey):
		game.HomeMoneyKey = old_key
		game.cur_HOMEMONEY = old_money
		game.Save.gameData = old_data
		error = "原版绿钞入账失败，奖励尚未领取。"
		return false
	game.return_FullHMK()
	receipts[result.id] = amount
	config.set_value("Game", RECEIPTS, receipts.duplicate(true))
	if best_changed:
		config.set_value("Game", BEST_DAYS, best_days)
	config.set_value("Game", "HMK", game.HomeMoneyKey)
	config.set_value("Game", "cur_HOMEMONEY", game.cur_HOMEMONEY)
	var backup_error = Directory.new().copy(path, path + ".before-rent-reward")
	var write_error = backup_error if backup_error != OK else io._write(config, path, expected_hash)
	if write_error != OK:
		game.HomeMoneyKey = old_key
		game.cur_HOMEMONEY = old_money
		game.Save.gameData = old_data
		game.emit_signal("MoneyHomeChange", 0)
		error = "奖励保存失败（%s），尚未领取，可重试。" % write_error
		return false
	var updated_keys = [RECEIPTS, "HMK", "cur_HOMEMONEY"]
	if best_changed:
		updated_keys.append(BEST_DAYS)
	for key in updated_keys:
		game.Save.gameData[key] = config.get_value("Game", key)
		game.Save.Config.set_value("Game", key, config.get_value("Game", key))
	# Only these personal fields were written: guests keep their own Level and
	# Game dictionaries on disk. Normal offline HomeSync exports the delta later.
	return true

func _read_reward_save(path):
	# Reward payout needs the native wallet, not the optional home-decor fields.
	# Older valid saves can lack HomeUpdate/HomeDevList and still hold a wallet.
	var file = File.new()
	if not file.file_exists(path):
		error = "找不到自己的存档，奖励尚未领取。"
		return null
	var config = ConfigFile.new()
	var read_error = config.load_encrypted_pass(path, " ")
	if read_error != OK:
		read_error = config.load(path)
	if read_error != OK or not config.has_section("Game"):
		error = "自己的存档无法读取，奖励尚未领取。"
		return null
	var version = config.get_value("Game", "VERSION", "")
	if not version is String or version.empty():
		error = "自己的存档缺少游戏版本信息，奖励尚未领取。"
		return null
	return config
