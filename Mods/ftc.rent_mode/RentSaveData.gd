extends "res://TscnAndGd/Logics/SystemLogic/SaveData.gd"

# Park only the rent shop in the game's ordinary encrypted save file.
const SECTION = "FtcRentRun"
const RUN_GAME_FIELDS = ["cur_money", "_MC", "_MONEYCHECK", "LevelDic", "Bool_InLevel", "IsJoin", "Level_Data"]
const Home = preload("res://ftc_mods/ftc.rent_mode/Sync/HomeSync.gd")
var normal_checkpoint = {}
var load_rent_checkpoint = false

func DataLoad(path):
	.DataLoad(path)
	if load_rent_checkpoint:
		restore_rent_checkpoint()

func _home_account():
	return str(SdkManager.user_id) if SdkManager.user_id != 0 else "default"

func _home_rent_path():
	return "user://" + _home_account() + "/saves/" + dataSavedName + save_suffix

func _home_official_path():
	return ""

func _section(config, name):
	var result = {}
	if config.has_section(name):
		for key in config.get_section_keys(name):
			var value = config.get_value(name, key)
			result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

func _put_section(config, name, values):
	if config.has_section(name):
		config.erase_section(name)
	for key in values:
		config.set_value(name, key, values[key])

func _copy_config(source):
	var result = ConfigFile.new()
	for section in source.get_sections():
		for key in source.get_section_keys(section):
			result.set_value(section, key, source.get_value(section, key))
	return result

func capture_normal_checkpoint():
	if levelData.get("cur_level", "") == "房租模式":
		return false
	normal_checkpoint = {"level": _section(Config, "Level"), "game": {}}
	for key in RUN_GAME_FIELDS:
		if Config.has_section_key("Game", key):
			normal_checkpoint.game[key] = Config.get_value("Game", key)
	return true

func restore_rent_checkpoint():
	var checkpoint = Config.get_value(SECTION, "checkpoint", {})
	if not checkpoint is Dictionary or not checkpoint.get("level", {}) is Dictionary or checkpoint.level.get("cur_level", "") != "房租模式":
		return false
	if levelData.get("cur_level", "") != "房租模式" and not capture_normal_checkpoint():
		return false
	levelData = checkpoint.level.duplicate(true)
	for key in RUN_GAME_FIELDS:
		if checkpoint.get("game", {}).has(key):
			gameData[key] = checkpoint.game[key]
		else:
			gameData.erase(key)
	return true

func restore_normal_home_state():
	if normal_checkpoint.empty():
		return false
	levelData = normal_checkpoint.level.duplicate(true)
	for key in RUN_GAME_FIELDS:
		if normal_checkpoint.game.has(key):
			gameData[key] = normal_checkpoint.game[key]
		else:
			gameData.erase(key)
	return true

func dataSYNC():
	.dataSYNC()
	_migrate_legacy_rent()
	if levelData.get("cur_level", "") != "房租模式":
		capture_normal_checkpoint()

func _migrate_legacy_rent():
	if Config.has_section_key(SECTION, "checkpoint"):
		return
	var root = OS.get_user_data_dir().replace("\\", "/").trim_suffix("/")
	if root.get_file() != "Feed The Cups" or not _home_account().is_valid_filename() or not dataSavedName.is_valid_filename():
		return
	var legacy = root.get_base_dir().plus_file("Feed The Cups Rent Mode").plus_file(_home_account()).plus_file("saves").plus_file(dataSavedName + save_suffix)
	if not File.new().file_exists(legacy):
		return
	var old = ConfigFile.new()
	if old.load_encrypted_pass(legacy, " ") != OK or old.get_value("Level", "cur_level", "") != "房租模式" or not old.has_section_key("Level", "rent_mode"):
		return
	var checkpoint = {"level": _section(old, "Level"), "game": {}}
	for key in RUN_GAME_FIELDS:
		if old.has_section_key("Game", key):
			checkpoint.game[key] = old.get_value("Game", key)
	var official = _home_rent_path()
	var backup = official + ".before-unified-rent"
	if File.new().file_exists(official) and not File.new().file_exists(backup):
		if Directory.new().copy(official, backup) != OK:
			print("[Rent Save] 旧房租经营迁移备份失败，已保留原存档。")
			return
	var io = Home.new()
	var expected_hash = io._hash(official)
	Config.set_value(SECTION, "checkpoint", checkpoint)
	var receipts = old.get_value("Game", "ftc_rent_reward_receipts", {})
	if receipts is Dictionary:
		var merged = Config.get_value("Game", "ftc_rent_reward_receipts", {})
		if merged is Dictionary:
			merged = merged.duplicate(true)
			for id in receipts:
				if not merged.has(id):
					merged[id] = receipts[id]
			Config.set_value("Game", "ftc_rent_reward_receipts", merged)
	if io._write(Config, official, expected_hash) != OK:
		Config.erase_section(SECTION)
		print("[Rent Save] 旧房租经营迁移失败，已保留原存档：", io.last_error)
	else:
		print("[Rent Save] 旧房租经营已并入正常存档，旧文件保留为备份。")

func _saveLogic(path):
	if SdkManager.return_ismember() and GameLogic.cur_level == "房租模式":
		return
	if GameLogic.cur_level != "房租模式" or normal_checkpoint.empty():
		._saveLogic(path)
		if GameLogic.cur_level != "房租模式":
			capture_normal_checkpoint()
		return
	var checkpoint = {"level": _section(Config, "Level"), "game": {}}
	for key in RUN_GAME_FIELDS:
		if Config.has_section_key("Game", key):
			checkpoint.game[key] = Config.get_value("Game", key)
	if checkpoint.level.get("cur_level", "") != "房租模式":
		print("[Rent Save] 房租关卡尚未写入存档，本次跳过。")
		return
	var shared = _copy_config(Config)
	shared.set_value(SECTION, "checkpoint", checkpoint)
	_put_section(shared, "Level", normal_checkpoint.level)
	for key in RUN_GAME_FIELDS:
		if normal_checkpoint.game.has(key):
			shared.set_value("Game", key, normal_checkpoint.game[key])
		elif shared.has_section_key("Game", key):
			shared.erase_section_key("Game", key)
	var io = Home.new()
	var backup = path + ".before-unified-rent"
	if File.new().file_exists(path) and not File.new().file_exists(backup):
		var backup_error = Directory.new().copy(path, backup)
		if backup_error != OK:
			print("[Rent Save] 备份失败，未写入：", backup_error)
			return
	var error = io._write(shared, path, io._hash(path))
	if error != OK:
		print("[Rent Save] 共用存档写入失败：", error, " ", io.last_error)
		return
	Config.set_value(SECTION, "checkpoint", checkpoint)
