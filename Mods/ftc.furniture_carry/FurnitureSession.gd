extends Reference

const PROTOCOL = 1
const CHANNEL = "FTC_FURNITURE"
var owner
var peers = {}
var modes = {}
var epoch = 0
var revision = 0
var received_revision = -1
var sequence = 0
var received_sequences = {}
var pending = {}
var applying = false
var scene_marker = ""
var elapsed = 0.0
var last_host = 0
var pending_snapshot = null

func _init(mode):
	owner = mode

func authority():
	return SdkManager.lobby_is_master

func local_id():
	return int(SdkManager.user_id)

func members():
	var result = []
	for member in SdkManager.lobby_members:
		var id = int(member.get("user_id", 0))
		if id > 0:
			result.append(id)
	return result

func version():
	return str(owner.api.host.loaded["ftc.furniture_carry"].manifest.version)

func ready():
	return epoch != 0 and owner.is_run()

func send(id, packet):
	if not SdkManager.is_multiplay:
		return
	var message = packet.duplicate(true)
	message.protocol = PROTOCOL
	SdkManager.call_one_sync(id, CHANNEL, [message])

func reset():
	applying = true
	owner.reset_carries()
	applying = false
	peers.clear()
	modes.clear()
	epoch = 0
	revision = 0
	received_revision = -1
	sequence = 0
	received_sequences.clear()
	pending.clear()
	pending_snapshot = null
	scene_marker = ""
	elapsed = 0.0
	last_host = 0

func departed(id):
	peers.erase(id)
	received_sequences.erase(id)
	if authority() and modes.has(id):
		apply_mode(id, false)
		broadcast("mode", {"player": id, "enabled": false})
		owner._save_now()

func tick(delta):
	if not SdkManager.is_multiplay:
		if epoch != 0 or last_host != 0:
			reset()
		return
	var host = int(SdkManager.lobby_master_id)
	if last_host != 0 and last_host != host:
		reset()
	last_host = host
	var marker = ""
	if owner.is_run():
		marker = str(owner.carry.level.get_path()) + ":" + str(GameLogic.cur_Day)
	if marker != scene_marker:
		applying = true
		owner.reset_carries()
		applying = false
		modes.clear()
		pending.clear()
		received_sequences.clear()
		revision = 0
		received_revision = -1
		epoch = 0
		scene_marker = marker
		if marker != "" and authority():
			epoch = int(OS.get_ticks_usec() % 2147483647) + 1
		elapsed = 1.0
	if pending_snapshot is Dictionary:
		applying = true
		if owner.apply_snapshot(pending_snapshot):
			pending_snapshot = null
		applying = false
	elapsed += delta
	if elapsed < (1.0 if epoch == 0 else 4.0):
		return
	elapsed = 0.0
	if marker == "":
		return
	var present = members()
	if authority():
		for id in modes.keys():
			if not id in present:
				apply_mode(id, false)
				broadcast("mode", {"player": id, "enabled": false})
		for id in peers.keys():
			if not id in present:
				peers.erase(id)
		send(0, {"kind": "hello", "version": version(), "epoch": epoch})
	else:
		send(host, {"kind": "hello", "version": version()})

func snapshot(id):
	if not authority() or not ready():
		return
	send(id, {"kind": "snapshot", "version": version(), "epoch": epoch, "revision": revision, "day": int(GameLogic.cur_Day), "scene": scene_marker, "modes": modes.duplicate(true), "layout": owner.layout_snapshot()})

func broadcast(kind, content):
	if not authority() or not ready():
		return
	revision += 1
	var packet = content.duplicate(true)
	packet.kind = kind
	packet.epoch = epoch
	packet.revision = revision
	packet.day = int(GameLogic.cur_Day)
	packet.scene = scene_marker
	send(0, packet)

func request_toggle():
	if not ready():
		owner._message("正在同步联机店铺，请稍候。")
		return
	var id = local_id()
	var value = not bool(modes.get(id, false))
	var actor = owner.find_player(id)
	if value and (not owner.is_preparing() or not is_instance_valid(actor) or actor.Con.IsHold or owner.get_tree().paused):
		owner._message("只能在开店前且双手空闲时进入搬运模式。")
		return
	if not apply_mode(id, value):
		return
	if authority():
		broadcast("mode", {"player": id, "enabled": value})
		if not value:
			owner._save_now()
	else:
		sequence += 1
		send(SdkManager.lobby_master_id, {"kind": "mode_request", "epoch": epoch, "enabled": value, "seq": sequence})

func apply_mode(id, value):
	applying = true
	var accepted = owner.set_player_enabled(id, value)
	applying = false
	if not accepted:
		return false
	if value:
		modes[id] = true
	else:
		modes.erase(id)
	return true

func local_action(packet):
	if not ready() or applying:
		return
	var action = packet.duplicate(true)
	action.player = local_id()
	if authority():
		broadcast("action", {"action": action, "origin_seq": 0})
	else:
		sequence += 1
		pending[sequence] = action
		send(SdkManager.lobby_master_id, {"kind": "action_request", "epoch": epoch, "seq": sequence, "action": action})

func _valid_request(sender, packet):
	if not ready() or int(packet.get("epoch", 0)) != epoch or peers.get(sender, "") != version():
		return false
	var seq = int(packet.get("seq", 0))
	if seq <= int(received_sequences.get(sender, 0)):
		return false
	received_sequences[sender] = seq
	return true

func receive(sender, packet):
	if not SdkManager.is_multiplay or sender == local_id() or not sender in members() or not packet is Dictionary or int(packet.get("protocol", -1)) != PROTOCOL:
		return
	var kind = str(packet.get("kind", ""))
	if authority():
		if kind == "hello":
			var peer_version = str(packet.get("version", ""))
			var changed = peers.get(sender, "") != peer_version
			peers[sender] = peer_version
			if changed and peer_version == version():
				snapshot(sender)
			return
		if not _valid_request(sender, packet):
			return
		if kind == "snapshot_request":
			snapshot(sender)
		elif kind == "mode_request":
			var value = bool(packet.get("enabled", false))
			var actor = owner.find_player(sender)
			if (not value or (owner.is_preparing() and is_instance_valid(actor) and not actor.Con.IsHold and not owner.get_tree().paused)) and bool(modes.get(sender, false)) != value:
				if apply_mode(sender, value):
					broadcast("mode", {"player": sender, "enabled": value})
					if not value:
						owner._save_now()
				else:
					snapshot(sender)
			else:
				snapshot(sender)
		elif kind == "action_request" and modes.has(sender) and packet.get("action") is Dictionary:
			var action = packet.action.duplicate(true)
			action.player = sender
			applying = true
			var accepted = owner.apply_action(action, false)
			applying = false
			if accepted:
				broadcast("action", {"action": owner.completed_action(action), "origin_seq": int(packet.seq)})
			else:
				snapshot(sender)
		elif kind == "action_request":
			snapshot(sender)
		return
	if sender != int(SdkManager.lobby_master_id) or str(packet.get("version", version())) != version():
		return
	if kind == "hello":
		if epoch != int(packet.get("epoch", 0)):
			send(sender, {"kind": "snapshot_request", "epoch": int(packet.get("epoch", 0)), "seq": _next_seq()})
		return
	if kind == "snapshot":
		if str(packet.get("scene", "")) != scene_marker or int(packet.get("day", -1)) != int(GameLogic.cur_Day):
			return
		epoch = int(packet.get("epoch", 0))
		received_revision = int(packet.get("revision", 0))
		pending.clear()
		modes = packet.get("modes", {}).duplicate(true)
		applying = true
		if not owner.apply_snapshot(packet.get("layout", {})):
			pending_snapshot = packet.get("layout", {}).duplicate(true)
		applying = false
		return
	if not ready() or int(packet.get("epoch", 0)) != epoch or str(packet.get("scene", "")) != scene_marker or int(packet.get("day", -1)) != int(GameLogic.cur_Day):
		return
	var next_revision = int(packet.get("revision", -1))
	if next_revision <= received_revision:
		return
	if next_revision != received_revision + 1:
		send(sender, {"kind": "snapshot_request", "epoch": epoch, "seq": _next_seq()})
		return
	received_revision = next_revision
	if kind == "mode":
		if not apply_mode(int(packet.get("player", 0)), bool(packet.get("enabled", false))):
			send(sender, {"kind": "snapshot_request", "epoch": epoch, "seq": _next_seq()})
	elif kind == "action" and packet.get("action") is Dictionary:
		var action = packet.action
		var origin = int(packet.get("origin_seq", 0))
		if int(action.get("player", 0)) == local_id() and pending.has(origin):
			var same_action = pending[origin] == action
			pending.erase(origin)
			if not same_action:
				send(sender, {"kind": "snapshot_request", "epoch": epoch, "seq": _next_seq()})
			return
		applying = true
		var success = owner.apply_action(action, true)
		applying = false
		if not success:
			send(sender, {"kind": "snapshot_request", "epoch": epoch, "seq": _next_seq()})

func _next_seq():
	sequence += 1
	return sequence
