extends Reference

const Policy = preload("res://ftc_mods/ftc.rent_mode/Coop/Rules.gd")
const GAME_FIELDS = ["cur_Menu", "cur_Extra", "cur_Rewards", "cur_Challenge", "cur_Event", "cur_Gift", "cur_StoreStar", "GameOverType", "cur_DayType", "Can_Formula", "cur_MenuNum", "cur_ExtraNum"]
var owner
var peers = {}
var elapsed = 0.0
var revision = 0
var received_revision = -1
var run = ""
var waiting_layout = false
var pending_level = null
var applying = false
var last_host = 0
var result_acks = {}
var last_sent = {}

func _init(mode):
	owner = mode

func online():
	return SdkManager.is_multiplay

func authority():
	return not online() or SdkManager.lobby_is_master

func versions():
	var result = {}
	for id in owner.api.host.loaded:
		result[id] = str(owner.api.host.loaded[id].manifest.version)
	return result

func members():
	var result = []
	for member in SdkManager.lobby_members:
		var id = int(member.get("user_id", 0))
		if id > 0:
			result.append(id)
	return result

func ready():
	if not online():
		return true
	var local = versions()
	if not Policy.compatible(local, local):
		return false
	for id in members():
		if id != SdkManager.user_id and not Policy.compatible(local, peers.get(id, {})):
			return false
	return true

func begin_run():
	if not online() or not authority():
		return
	var id = str(owner.state.get("run_id", owner.state.get("final_result", {}).get("id", "")))
	if id.empty():
		return
	owner.state.run_id = id
	if run != id:
		revision = 0
		result_acks.clear()
		last_sent.clear()
	run = id
	last_host = int(SdkManager.lobby_master_id)
	owner.state.coop_run = run

func send(id, packet):
	if not online():
		return
	packet = packet.duplicate(true)
	packet.protocol = Policy.PROTOCOL
	SdkManager.call_one_sync(id, "FTC_RENT_COOP", [packet])

func tick(delta):
	if not online():
		if last_host != 0:
			reset()
		return
	if last_host != int(SdkManager.lobby_master_id):
		reset()
		last_host = int(SdkManager.lobby_master_id)
	elapsed += delta
	if elapsed < (5.0 if ready() else 1.0):
		return
	elapsed = 0.0
	var present = members()
	for id in peers.keys():
		if not id in present:
			peers.erase(id)
	send(0 if authority() else SdkManager.lobby_master_id, {"kind": "hello", "versions": versions()})
	if authority() and owner.is_run():
		broadcast_state()
	_finish_if_claimed()

func reset():
	peers.clear()
	run = ""
	received_revision = -1
	revision = 0
	waiting_layout = false
	pending_level = null
	last_host = 0
	result_acks.clear()
	last_sent.clear()

func receive(sender, packet):
	if not online() or not sender in members() or not packet is Dictionary or int(packet.get("protocol", -1)) != Policy.PROTOCOL:
		return
	var kind = str(packet.get("kind", ""))
	if kind == "hello":
		var peer_versions = packet.get("versions", {}).duplicate(true) if packet.get("versions") is Dictionary else {}
		var changed = peers.get(sender, {}) != peer_versions
		peers[sender] = peer_versions
		if changed and authority() and owner.is_run() and Policy.compatible(versions(), peer_versions):
			broadcast_state(true)
		return
	if authority():
		if not Policy.compatible(versions(), peers.get(sender, {})):
			return
		if kind == "result_claimed" and packet.get("run") == run and packet.get("id") == owner.state.get("final_result", {}).get("id", "") and owner.state.get("failed", false):
			result_acks[sender] = true
			_finish_if_claimed()
		return
	if sender != int(SdkManager.lobby_master_id) or not Policy.compatible(versions(), peers.get(sender, {})):
		return
	match kind:
		"layout":
			if packet.get("run") != run or not packet.get("level") is Dictionary:
				return
			SdkManager.lobby_level_data = packet.level.duplicate(true)
			waiting_layout = false
			owner.state.seed_pending = false
			var level = pending_level.get_ref() if pending_level != null else null
			pending_level = null
			if is_instance_valid(level):
				level.call_deferred("_LEVELSTAT_LOGIC", 0)
		"state":
			if not Policy.accept_snapshot(packet, run, received_revision):
				return
			received_revision = int(packet.revision)
			owner.state = packet.state.duplicate(true)
			owner.settings = owner.state.settings.duplicate(true)
			SdkManager.lobby_level_data.rent_mode = owner.state.duplicate(true)
			for key in GAME_FIELDS:
				if packet.game.has(key):
					GameLogic.set(key, packet.game[key])
			owner.preparing = bool(packet.get("preparing", false))
			owner.opened = bool(packet.get("opened", false))
			GameLogic.cur_NoOrderNum = int(packet.get("lost_order", 0))
			GameLogic.cur_NoSellNum = int(packet.get("lost_sell", 0))
		"notice":
			if packet.get("run") == run:
				owner._message(str(packet.get("text", "")))
		"product_wait":
			if packet.get("run") == run:
				GameLogic.GameUI.get_node("RewardUI").call_clean()
				owner._message("房主正在选择本阶段新品，请稍候。")
		"failed":
			if not preload("res://ftc_mods/ftc.rent_mode/RewardLedger.gd").valid(packet.get("result")):
				return
			if packet.get("run") != run:
				if run != "" or not GameLogic.LoadingUI.IsHome or not packet.get("settings") is Dictionary or owner.Rules.validate(packet.settings) != "":
					return
				run = str(packet.run)
				last_host = int(SdkManager.lobby_master_id)
				owner.settings = packet.settings.duplicate(true)
				owner.state = {"settings": owner.settings.duplicate(true), "run_id": run, "coop_run": run, "failed": true}
			if packet.get("run") == run:
				owner.state.final_result = packet.result.duplicate(true)
				owner.state.failed = true
				if packet.get("record") is Dictionary and int(packet.record.get("ProfitTotal", -1)) == max(0, int(packet.result.get("peak_cash", packet.result.cash))):
					owner.remote_result_record = packet.record.duplicate(true)
				owner._show_result()
		"result_closed":
			if packet.get("run") == run:
				owner.close_result()

func result_claimed(id):
	if not online():
		owner._return_to_setup()
		return
	if not authority():
		send(SdkManager.lobby_master_id, {"kind": "result_claimed", "run": run, "id": id})
		return
	result_acks[SdkManager.user_id] = true
	_finish_if_claimed()

func _finish_if_claimed():
	if not authority() or not result_acks.has(SdkManager.user_id):
		return
	for id in members():
		if not result_acks.has(id):
			return
	notify("result_closed")
	result_acks.clear()
	owner._return_to_setup()

func restore_lobby():
	if authority():
		return
	var saved = SdkManager.lobby_level_data.get("rent_mode", {})
	if saved is Dictionary and owner.Rules.validate(saved.get("settings", {})) == "":
		owner.state = saved.duplicate(true)
		owner.settings = saved.settings.duplicate(true)
		var id = str(saved.get("run_id", saved.get("coop_run", "")))
		if id != run:
			received_revision = -1
		run = id
		last_host = int(SdkManager.lobby_master_id)
		owner.state.coop_run = run
		waiting_layout = bool(saved.get("seed_pending", false))

func broadcast_state(force = false):
	if not online() or not authority() or run == "":
		return
	var game = {}
	for key in GAME_FIELDS:
		game[key] = GameLogic.get(key)
	var snapshot = {"state": owner.state, "game": game, "preparing": owner.preparing, "opened": owner.opened, "lost_order": GameLogic.cur_NoOrderNum, "lost_sell": GameLogic.cur_NoSellNum}
	if not force and snapshot == last_sent:
		return
	last_sent = snapshot.duplicate(true)
	revision += 1
	send(0, {"kind": "state", "revision": revision, "state": owner.state, "game": game, "preparing": owner.preparing, "opened": owner.opened, "lost_order": GameLogic.cur_NoOrderNum, "lost_sell": GameLogic.cur_NoSellNum})

func notify(kind, values = {}):
	if not authority():
		return
	var packet = values.duplicate(true)
	packet.kind = kind
	packet.run = run
	packet.day = int(GameLogic.cur_Day)
	send(0, packet)
