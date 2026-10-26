extends Reference

const Home = preload("res://ftc_mods/ftc.rent_mode/Sync/HomeSync.gd")
const SECTION = "FtcHomeSync"
const MARKER = "startup_profile_version"
const TUTORIAL = "新手引导第一关"
var last_error = ""

func ensure(rent_path, official_path, backup_dir):
	last_error = ""
	if official_path == "" or rent_path == official_path:
		return false
	var io = Home.new()
	var original = io._read(official_path)
	if original == null:
		return false
	var progress = original.get_value("Game", "Level_Data", {})
	if not progress is Dictionary or progress.empty() or not original.has_section("Statistics"):
		# A genuinely new account still uses the game's own tutorial.
		return false
	for key in progress:
		if not key is String or not progress[key] is Dictionary:
			return false
	var exists = File.new().file_exists(rent_path)
	var expected_hash = io._hash(rent_path)
	var config = io._read(rent_path) if exists else ConfigFile.new()
	if config == null:
		# A damaged existing save must use native recovery, never replacement.
		last_error = "房租存档读取异常，未覆盖原文件。"
		return false
	if int(config.get_value(SECTION, MARKER, 0)) >= 1:
		return false
	var current = config.get_value("Game", "Level_Data", {})
	if not current is Dictionary:
		return false
	for key in current:
		if key != TUTORIAL:
			# Existing independent campaign progress remains independent.
			return false
	if not exists:
		# Seed the same account's personal profile before native _loadLogic can
		# create a fresh player. Do not copy its active campaign shop or inventory.
		for section in ["Game", "Statistics"]:
			for key in original.get_section_keys(section):
				config.set_value(section, key, original.get_value(section, key))
		_reset_active_tutorial(config)
	elif config.get_value("Level", "cur_level", "") == TUTORIAL and not config.has_section_key("Level", "rent_mode"):
		# Repair the tutorial checkpoint created by 0.12.0 on first launch.
		# An existing rent run, personal money and rewards are preserved.
		_reset_active_tutorial(config)
	config.set_value("Game", "Level_Data", progress.duplicate(true))
	# Old fresh profiles already have default unlock arrays. Preserve any local
	# unlocks while importing the same account's legitimate character/menu list.
	for key in ["Array_UnlockPlayer", "Array_UnlockMenu"]:
		var incoming = original.get_value("Statistics", key, [])
		var unlocked = config.get_value("Statistics", key, [])
		if incoming is Array and unlocked is Array:
			unlocked = unlocked.duplicate(true)
			for item in incoming:
				if not item in unlocked:
					unlocked.append(item)
			config.set_value("Statistics", key, unlocked)
	config.set_value(SECTION, MARKER, 1)
	if io._backup(rent_path, official_path, backup_dir) != OK:
		last_error = "首次存档初始化备份失败，已保留原文件。"
		return false
	if not exists and File.new().file_exists(rent_path):
		return false
	if io._write(config, rent_path, expected_hash) != OK:
		last_error = "首次存档初始化保存失败，已保留原文件。"
		return false
	return true

func _reset_active_tutorial(config):
	if config.has_section("Level"):
		config.erase_section("Level")
	config.set_value("Level", "cur_level", "")
	config.set_value("Level", "Level_bool", false)
	config.set_value("Level", "cur_Day", 1)
	config.set_value("Level", "GameOverType", -1)
	config.set_value("Game", "Bool_InLevel", false)
	config.set_value("Game", "IsJoin", false)
	config.set_value("Game", "LevelDic", {})
	config.set_value("Game", "cur_money", 0)
	config.set_value("Game", "_MC", Vector2.ZERO)
	config.set_value("Game", "_MONEYCHECK", 0)
