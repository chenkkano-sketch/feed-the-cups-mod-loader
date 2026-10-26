extends Reference

# Only the shared home snapshot crosses save directories. The native campaign,
# rent run, inventory and statistics remain in their original ConfigFile.
const Rules = preload("res://ftc_mods/ftc.rent_mode/Sync/HomeSyncRules.gd")
const SECTION = "FtcHomeSync"
const PASSWORD = " "
var last_error = ""
var backup_session = ""
var backed_up = {}
var sequence = 0

func _id():
	sequence += 1
	return "%s-%s-%s" % [OS.get_unix_time(), OS.get_ticks_usec(), sequence]

func _hash(path):
	return File.new().get_sha256(path) if File.new().file_exists(path) else ""

func _read(path):
	var file = File.new()
	if file.open(path, File.READ) != OK:
		last_error = "找不到正常模式存档，继续使用独立的房租之家。"
		return null
	if file.get_len() < 8:
		file.close()
		last_error = "正常模式存档不完整，已保留两边原文件。"
		return null
	var magic = file.get_32()
	file.seek(0)
	var plain_header = file.get_buffer(min(512, file.get_len())).get_string_from_utf8().strip_edges() if magic != 0x43454447 else ""
	file.close()
	var config = ConfigFile.new()
	var error = ERR_FILE_CORRUPT
	if magic == 0x43454447:
		error = config.load_encrypted_pass(path, PASSWORD)
	elif plain_header.begins_with("[Game]") or plain_header.begins_with("[Statistics]") or plain_header.begins_with("[Level]"):
		error = config.load(path)
	if error != OK or not config.has_section("Game"):
		last_error = "正常模式存档读取失败，已保留两边原文件。"
		return null
	if not config.get_value("Game", "VERSION", "") in ["1.0.1.2", "1.0.2.0"] or not config.has_section_key("Game", "HomeUpdate") or not config.has_section_key("Game", "HomeDevList"):
		last_error = "正常模式存档缺少受支持的之家数据，已保留两边原文件。"
		return null
	var snapshot = Rules.snapshot(config)
	if not snapshot.valid:
		last_error = "正常模式的家数据异常：" + str(snapshot.get("error", ""))
		return null
	return config

func _write(config, path, expected_hash = ""):
	var directory = Directory.new()
	var error = directory.make_dir_recursive(path.get_base_dir())
	if error != OK:
		return error
	var temporary = path + ".ftcsync-tmp"
	error = config.save_encrypted_pass(temporary, PASSWORD)
	if error != OK:
		return error
	# Re-read what we wrote before replacing a valid save.
	var verify = ConfigFile.new()
	error = verify.load_encrypted_pass(temporary, PASSWORD)
	if error != OK:
		directory.remove(temporary)
		return error
	if expected_hash != "" and _hash(path) != expected_hash:
		directory.remove(temporary)
		last_error = "正常存档正在被其他程序修改，本次共享稍后重试。"
		return ERR_BUSY
	error = directory.rename(temporary, path)
	if error != OK:
		directory.remove(temporary)
	return error

func _backup(rent_path, official_path, backup_dir):
	var pair = rent_path + "|" + official_path
	if backed_up.has(pair):
		return OK
	if backup_session == "":
		backup_session = _id()
	var directory = Directory.new()
	var folder = backup_dir.plus_file(backup_session)
	var error = directory.make_dir_recursive(folder)
	if error != OK:
		return error
	for item in [[official_path, "normal.sav"], [rent_path, "rent.sav"]]:
		var destination = folder.plus_file(item[1])
		if File.new().file_exists(item[0]) and not File.new().file_exists(destination):
			error = directory.copy(item[0], destination)
			if error != OK:
				return error
	backed_up[pair] = true
	return OK

func _set_base(config, snapshot):
	config.set_value(SECTION, "baseline", snapshot.duplicate(true))
	config.set_value(SECTION, "pending", "")
	if config.has_section_key(SECTION, "target"):
		config.erase_section_key(SECTION, "target")

func _commit(config, rent_path, official_path, backup_dir):
	var transaction = str(config.get_value(SECTION, "pending", ""))
	var remote_hash = _hash(official_path)
	var remote_config = _read(official_path)
	if remote_config == null:
		return null
	var shared = Rules.snapshot(remote_config)
	var receipts = remote_config.get_value(SECTION, "receipts", [])
	if not receipts is Array:
		last_error = "共享存档的同步标记异常，已保留原文件。"
		return null
	if not transaction in receipts:
		var base = config.get_value(SECTION, "baseline", {})
		var target = config.get_value(SECTION, "target", {})
		shared = Rules.merge(base, target, shared)
		if not shared.get("valid", false):
			last_error = "共享之家暂未写回：" + str(shared.get("error", "数据异常"))
			return null
		if _backup(rent_path, official_path, backup_dir) != OK:
			last_error = "之家存档备份失败，本次共享稍后重试。"
			return null
		Rules.apply(remote_config, shared)
		receipts.append(transaction)
		while receipts.size() > 256:
			receipts.pop_front()
		remote_config.set_value(SECTION, "receipts", receipts)
		if _write(remote_config, official_path, remote_hash) != OK:
			if last_error == "":
				last_error = "正常模式存档写回失败，本次共享稍后重试。"
			return null
	# A crash after the official write is harmless: the durable receipt keeps
	# the same transaction from charging/rewarding green cash twice.
	var target = config.get_value(SECTION, "target", {})
	var current = Rules.snapshot(config)
	var rebased = Rules.merge(target, current, shared)
	if not rebased.get("valid", false):
		last_error = "之家同步恢复失败，已保留待同步记录。"
		return null
	Rules.apply(config, rebased)
	_set_base(config, shared)
	return shared

func pull(config, rent_path, official_path, backup_dir):
	last_error = ""
	if official_path == "":
		return false
	var canonical = _read(official_path)
	if canonical == null:
		return false
	if _backup(rent_path, official_path, backup_dir) != OK:
		last_error = "之家存档备份失败，已保留独立存档。"
		return false
	if str(config.get_value(SECTION, "pending", "")) != "":
		if _commit(config, rent_path, official_path, backup_dir) == null:
			return false
		# Persist the receipt locally before any further transactions.
		if _write(config, rent_path) != OK:
			last_error = "房租存档同步标记保存失败。"
			return false
		return save(config, rent_path, official_path, backup_dir) == OK and str(config.get_value(SECTION, "pending", "")) == ""
	# First launch deliberately imports the official balance as-is. Old rent
	# balances are backed up, never added to or subtracted from that balance.
	var shared = Rules.snapshot(canonical)
	Rules.apply(config, shared)
	_set_base(config, shared)
	return true

func save(config, rent_path, official_path, backup_dir):
	last_error = ""
	if official_path == "":
		return _write(config, rent_path)
	var prior_base = config.get_value(SECTION, "baseline", {})
	var prior_current = Rules.snapshot(config)
	if str(config.get_value(SECTION, "pending", "")) == "" and prior_base is Dictionary and prior_base.get("valid", false) and prior_current.get("valid", false) and not Rules.equivalent(prior_base, prior_current):
		config.set_value(SECTION, "pending", _id())
		config.set_value(SECTION, "target", prior_current.duplicate(true))
	if str(config.get_value(SECTION, "pending", "")) != "":
		var staged = _write(config, rent_path)
		if staged != OK:
			return staged
	var canonical = _read(official_path)
	if canonical == null:
		# Keep an existing outbox intact so a later retry can recover expenses.
		return _write(config, rent_path)
	if _backup(rent_path, official_path, backup_dir) != OK:
		last_error = "之家存档备份失败，本次共享稍后重试。"
		return _write(config, rent_path)
	if str(config.get_value(SECTION, "pending", "")) != "":
		if _commit(config, rent_path, official_path, backup_dir) == null:
			return _write(config, rent_path)
		var recovered = _write(config, rent_path)
		if recovered != OK:
			return recovered
		canonical = _read(official_path)
		if canonical == null:
			return OK
	var shared = Rules.snapshot(canonical)
	var base = config.get_value(SECTION, "baseline", {})
	if not base.get("valid", false):
		Rules.apply(config, shared)
		_set_base(config, shared)
		return _write(config, rent_path)
	var current = Rules.snapshot(config)
	if not current.get("valid", false):
		last_error = "房租之家数据异常，已保留正常模式存档。"
		return _write(config, rent_path)
	if Rules.equivalent(base, current):
		Rules.apply(config, shared)
		_set_base(config, shared)
		return _write(config, rent_path)
	config.set_value(SECTION, "pending", _id())
	config.set_value(SECTION, "target", current.duplicate(true))
	# Write the outbox before changing the official save. Failed official
	# writes can be retried after restart without losing purchases or payouts.
	var error = _write(config, rent_path)
	if error != OK:
		return error
	if _commit(config, rent_path, official_path, backup_dir) == null:
		return OK
	return _write(config, rent_path)
