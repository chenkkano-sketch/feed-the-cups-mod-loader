extends Reference

# Household data is deliberately represented separately from native run data.
# This module never loads paths, invokes Steam, or saves a ConfigFile.
const GAME_FIELDS = ["HomeUpdate", "HomeDevList", "EquipDic", "player_1P_ID", "player_2P_ID", "JoinPlayer", "cur_EquipList", "AchievementReward_Array", "Achievement_Array"]
const STRING_ARRAY_FIELDS = ["HomeDevList", "cur_EquipList", "AchievementReward_Array", "Achievement_Array"]
const FASHION_PARTS = ["Head", "Body", "Hand", "Face", "Foot", "Accessory_1", "Accessory_2", "Accessory_3"]
const DEFAULT_MONEY_KEY = 1000000
const MAX_CASH = 9999999
const MAX_CHARACTER_EXP = 18000

static func invalid(reason):
	return {"valid": false, "error": str(reason)}

static func _number(value):
	return typeof(value) in [TYPE_INT, TYPE_REAL] and not is_nan(float(value)) and not is_inf(float(value))

static func _integer(value, minimum, maximum):
	return _number(value) and float(value) >= minimum and float(value) <= maximum and floor(float(value)) == float(value)

static func _copy(value):
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value

static func equivalent(left, right):
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not equivalent(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not equivalent(left[index], right[index]):
				return false
		return true
	return left == right

static func _string_array(value):
	if not value is Array or value.size() > 4096:
		return false
	for item in value:
		if not item is String or item.empty() or item.length() > 256:
			return false
	return true

static func _equipment(value):
	if not value is Dictionary or value.size() > 2:
		return false
	for player in value:
		if typeof(player) != TYPE_INT or not player in [1, 2] or not value[player] is Dictionary or value[player].size() > 10:
			return false
		for avatar in value[player]:
			if typeof(avatar) != TYPE_INT or not _integer(avatar, 0, 9) or not value[player][avatar] is Dictionary:
				return false
			for part in value[player][avatar]:
				if not part in FASHION_PARTS or not _integer(value[player][avatar][part], 0, 1000000000):
					return false
	return true

static func _game_error(game):
	if not game is Dictionary:
		return "共享家居字段不是字典"
	for key in game:
		if not key in GAME_FIELDS:
			return "共享数据包含经营字段：" + str(key)
		if key in STRING_ARRAY_FIELDS:
			if not _string_array(game[key]):
				return "家居或成就列表无效：" + key
		elif key == "EquipDic":
			if not _equipment(game[key]):
				return "角色穿搭数据无效"
		elif not _integer(game[key], 0, 9):
			return "角色或房屋编号无效：" + key
	return ""

static func _exp_error(character_exp):
	if not character_exp is Dictionary or character_exp.size() > 10:
		return "角色经验字典无效"
	for id in character_exp:
		if typeof(id) != TYPE_INT or not _integer(id, 0, 9) or not _integer(character_exp[id], 0, MAX_CHARACTER_EXP):
			return "角色经验值无效"
	return ""

static func _snapshot_error(value):
	if not value is Dictionary or typeof(value.get("valid")) != TYPE_BOOL or not value.get("valid"):
		return "共享数据尚未有效载入"
	if not value.has("game") or not value.has("character_exp") or not value.has("cash") or not value.has("money_key"):
		return "共享数据缺少字段"
	var problem = _game_error(value.game)
	if not problem.empty():
		return problem
	problem = _exp_error(value.character_exp)
	if not problem.empty():
		return problem
	if not _integer(value.cash, 0, MAX_CASH):
		return "共享绿钞余额无效"
	if not _integer(value.money_key, 1, 1000000000):
		return "共享绿钞编码无效"
	return ""

static func snapshot(config):
	if not config is ConfigFile or not config.has_section("Game"):
		return invalid("存档缺少 Game 数据，不能共享家居")
	var result = {"valid": true, "error": "", "game": {}, "character_exp": {}, "cash": 0, "money_key": DEFAULT_MONEY_KEY}
	# Missing native Character data means a fresh character, not permission to
	# retain an older isolated rent save's experience and export it afterward.
	for id in range(10):
		result.character_exp[id] = 0
	for key in GAME_FIELDS:
		if config.has_section_key("Game", key):
			result.game[key] = _copy(config.get_value("Game", key))
	var problem = _game_error(result.game)
	if not problem.empty():
		return invalid(problem)
	var has_key = config.has_section_key("Game", "HMK")
	var use_legacy = not has_key
	if has_key:
		var key = config.get_value("Game", "HMK")
		if not _integer(key, 1, 1000000000):
			return invalid("绿钞 HMK 无效")
		result.money_key = int(key)
	if config.has_section_key("Game", "cur_HOMEMONEY"):
		var encoded = config.get_value("Game", "cur_HOMEMONEY")
		if not encoded is Vector2 or not _number(encoded.x) or not _number(encoded.y):
			return invalid("绿钞向量无效")
		use_legacy = not has_key and encoded == Vector2.ZERO
		# Native subtraction can leave a negative low digit; validate the total,
		# not the signs of the separate vector components.
		var high = float(encoded.x) * result.money_key
		var low = float(encoded.y) * result.money_key
		if abs(high) > 1000000000 or abs(low) > 1000000000:
			return invalid("绿钞向量超出有效范围")
		result.cash = int(round(high)) * 10000 + int(round(low))
	if use_legacy and config.has_section_key("Game", "cur_money_home"):
		var legacy = config.get_value("Game", "cur_money_home")
		if not _number(legacy) or float(legacy) < 0 or float(legacy) > float(MAX_CASH) / 1000000.0:
			return invalid("旧版绿钞余额无效")
		result.cash = int(round(float(legacy) * 1000000.0))
	if config.has_section_key("Statistics", "Character"):
		var characters = config.get_value("Statistics", "Character")
		if not characters is Dictionary or characters.size() > 10:
			return invalid("角色培养数据无效")
		for id in characters:
			if typeof(id) != TYPE_INT or not _integer(id, 0, 9) or not characters[id] is Dictionary:
				return invalid("角色培养编号无效")
			if characters[id].has("EXP"):
				result.character_exp[id] = characters[id].EXP
	problem = _snapshot_error(result)
	return result if problem.empty() else invalid(problem)

static func _union(canonical, local):
	var result = canonical.duplicate(true)
	for item in local:
		if not result.has(item):
			result.append(item)
	return result

static func _merge_leaves(base, local, canonical):
	# Native outfit changes replace individual parts with zero to unequip.
	# A missing key is not a user-requested deletion, so preserve canonical data.
	var result = canonical.duplicate(true)
	for key in local:
		if base.has(key) and equivalent(local[key], base[key]):
			continue
		if local[key] is Dictionary and canonical.get(key) is Dictionary:
			var base_branch = base.get(key, {})
			if not base_branch is Dictionary:
				base_branch = {}
			result[key] = _merge_leaves(base_branch, local[key], canonical[key])
		else:
			result[key] = _copy(local[key])
	return result

static func merge(base, local, canonical):
	for value in [base, local, canonical]:
		var problem = _snapshot_error(value)
		if not problem.empty():
			return invalid(problem)
	var result = canonical.duplicate(true)
	result.error = ""
	var cash = int(canonical.cash) + int(local.cash) - int(base.cash)
	if cash < 0:
		return invalid("共享绿钞不足，已保留本地记录，未覆盖正常存档")
	if cash > MAX_CASH:
		return invalid("共享绿钞超过游戏余额上限")
	result.cash = cash
	# Always retain the newest canonical encoding key, even after a rotation.
	result.money_key = int(canonical.money_key)
	for key in GAME_FIELDS:
		if not local.game.has(key):
			continue
		var unchanged = base.game.has(key) and equivalent(local.game[key], base.game[key])
		if key in ["AchievementReward_Array", "Achievement_Array"]:
			result.game[key] = _union(canonical.game.get(key, []), local.game[key])
		elif key == "HomeDevList":
			var added = []
			for item in local.game[key]:
				if not base.game.get(key, []).has(item):
					added.append(item)
			result.game[key] = _union(canonical.game.get(key, []), added)
		elif key == "HomeUpdate":
			if not unchanged:
				result.game[key] = max(int(canonical.game.get(key, 0)), int(local.game[key]))
		elif key == "EquipDic":
			result.game[key] = _merge_leaves(base.game.get(key, {}), local.game[key], canonical.game.get(key, {}))
		elif not unchanged:
			result.game[key] = _copy(local.game[key])
	for id in local.character_exp:
		result.character_exp[id] = max(int(canonical.character_exp.get(id, 0)), int(local.character_exp[id]))
	return result

static func apply(config, value):
	var problem = _snapshot_error(value)
	if not config is ConfigFile or not problem.empty():
		return false
	for key in GAME_FIELDS:
		if value.game.has(key):
			config.set_value("Game", key, _copy(value.game[key]))
		elif config.has_section_key("Game", key):
			config.erase_section_key("Game", key)
	var key = int(value.money_key)
	var cash = int(value.cash)
	config.set_value("Game", "HMK", key)
	config.set_value("Game", "cur_HOMEMONEY", Vector2(float(int(cash / 10000)) / key, float(cash % 10000) / key))
	config.set_value("Game", "cur_money_home", float(cash) / 1000000.0)
	var characters = config.get_value("Statistics", "Character", {})
	if not characters is Dictionary:
		characters = {}
	else:
		characters = characters.duplicate(true)
	# Native Save only initializes the entire Character dictionary when it is
	# absent, so a newly created shared save must not contain partial records.
	for id in range(10):
		var character = characters.get(id, {})
		if not character is Dictionary:
			character = {}
		else:
			character = character.duplicate(true)
		for counter in ["EXP", "UseCount", "MultplayCount", "FeedCups", "HomeMoneyCount", "CupCoinCount"]:
			if not character.has(counter):
				character[counter] = 0
		character.EXP = int(value.character_exp.get(id, 0))
		characters[id] = character
	config.set_value("Statistics", "Character", characters)
	return true
