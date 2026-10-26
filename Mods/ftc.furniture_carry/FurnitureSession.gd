extends Reference

const PROTOCOL = 2
const CHANNEL = "FTC_FURNITURE"
var owner
var peers = {}
var modes = {}
var epoch = 0
var sequence = 0
var received_sequences = {}
var applying = false
var scene_marker = ""
var elapsed = 0.0
var last_host = 0
var pending_snapshot = null
var pending_dirty = false
var resync_needed = false
var last_snapshot_request = 0

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
	message.version = version()
	SdkManager.call_one_sync(id, CHANNEL, [message])

func send_all(packet):
	var host = int(SdkManager.lobby_master_id)
	if not authority() and host != local_id() and host in members():
		send(host, packet)
	for id in members():
		if id != local_id() and (authority() or id != host):
			send(id, packet)

func reset():
	applying = true
	owner.reset_carries()
	applying = false
	peers.clear()
	modes.clear()
	epoch = 0
	sequence = 0
	received_sequences.clear()
	pending_snapshot = null
	pending_dirty = false
	resync_needed = false
	last_snapshot_request = 0
	scene_marker = ""
	elapsed = 0.0
	last_host = 0

func departed(id):
	peers.erase(id)
	if modes.has(id):
		apply_mode(id, false)
		if authority():
			publish("departed", {"player": id})
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
		received_sequences.clear()
		sequence = 0
		epoch = 0
		pending_snapshot = null
		pending_dirty = false
		resync_needed = false
		scene_marker = marker
		if marker != "" and authority():
			epoch = int(OS.get_ticks_usec() % 2147483647) + 1
			elapsed = 1.0
	if pending_snapshot is Dictionary:
		applying = true
		if owner.apply_snapshot(pending_snapshot.get("layout", {})):
			pending_snapshot = null
			if pending_dirty:
				pending_dirty = false
				request_snapshot()
		applying = false
	if resync_needed and not pending_snapshot is Dictionary:
		request_snapshot()
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
				departed(id)
		for id in peers.keys():
			if not id in present:
				peers.erase(id)
		send_all({"kind": "hello", "epoch": epoch})
	else:
		send(host, {"kind": "hello", "epoch": epoch})

func _seen(sequences, id):
	return int(sequences.get(id, sequences.get(str(id), 0)))

func snapshot(id):
	if not authority() or not ready():
		return
	var seen = received_sequences.duplicate(true)
	seen[local_id()] = sequence
	var packet = {"kind": "snapshot", "epoch": epoch, "day": int(GameLogic.cur_Day), "scene": scene_marker, "modes": modes.duplicate(true), "layout": owner.layout_snapshot(), "sequences": seen}
	if id == 0:
		send_all(packet)
	else:
		send(id, packet)

func request_snapshot():
	if SdkManager.is_multiplay and not authority() and scene_marker != "":
		resync_needed = true
		var now = OS.get_ticks_msec()
		if now - last_snapshot_request < 250:
			return
		last_snapshot_request = now
		resync_needed = false
		send(int(SdkManager.lobby_master_id), {"kind": "snapshot_request", "epoch": epoch})

func publish(kind, content):
	if not ready():
		return
	sequence += 1
	var packet = content.duplicate(true)
	packet.kind = kind
	packet.seq = sequence
	packet.epoch = epoch
	packet.day = int(GameLogic.cur_Day)
	packet.scene = scene_marker
	received_sequences[local_id()] = sequence
	# The acting player already changed their own scene. Other players receive
	# the transition directly, without a host relay or approval round trip.
	send_all(packet)

func relay(origin, event):
	if not authority():
		return
	for id in members():
		if id != local_id() and id != origin:
			send(id, {"kind": "relay", "origin": origin, "event": event})

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
	publish("mode", {"player": id, "enabled": value})
	if authority() and not value:
		owner._save_now()

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
	publish("action", {"action": action})

func _valid_scene(packet):
	return ready() and int(packet.get("epoch", 0)) == epoch and str(packet.get("scene", "")) == scene_marker and int(packet.get("day", -1)) == int(GameLogic.cur_Day)

func receive(sender, packet):
	if not SdkManager.is_multiplay or sender == local_id() or not sender in members() or not packet is Dictionary or int(packet.get("protocol", -1)) != PROTOCOL or str(packet.get("version", "")) != version():
		return
	var kind = str(packet.get("kind", ""))
	if kind == "relay":
		if sender == int(SdkManager.lobby_master_id) and packet.get("event") is Dictionary:
			var origin = int(packet.get("origin", 0))
			var event = packet.event
			if origin in members() and int(event.get("protocol", -1)) == PROTOCOL and str(event.get("version", "")) == version():
				_handle_event(origin, event)
		return
	if kind == "hello":
		if authority():
			var changed = peers.get(sender, "") != str(packet.version)
			peers[sender] = str(packet.version)
			if changed or int(packet.get("epoch", 0)) != epoch:
				snapshot(sender)
		elif sender == int(SdkManager.lobby_master_id) and epoch != int(packet.get("epoch", 0)):
			request_snapshot()
		return
	if kind == "snapshot_request":
		if authority():
			snapshot(sender)
		return
	if kind == "snapshot":
		if authority() or sender != int(SdkManager.lobby_master_id) or str(packet.get("scene", "")) != scene_marker or int(packet.get("day", -1)) != int(GameLogic.cur_Day) or not packet.get("sequences") is Dictionary:
			return
		var seen = packet.sequences
		if epoch != 0 and epoch != int(packet.get("epoch", 0)):
			sequence = 0
			received_sequences.clear()
		else:
			if sequence > _seen(seen, local_id()):
				request_snapshot()
				return
			for id in received_sequences.keys():
				if _seen(received_sequences, id) > _seen(seen, id):
					request_snapshot()
					return
		epoch = int(packet.get("epoch", 0))
		resync_needed = false
		modes = packet.get("modes", {}).duplicate(true)
		received_sequences = seen.duplicate(true)
		sequence = max(sequence, _seen(seen, local_id()))
		applying = true
		if not owner.apply_snapshot(packet.get("layout", {})):
			pending_snapshot = packet.duplicate(true)
		else:
			pending_snapshot = null
		applying = false
		return
	_handle_event(sender, packet)

func _handle_event(sender, packet):
	var kind = str(packet.get("kind", ""))
	if not _valid_scene(packet):
		request_snapshot()
		return
	var seq = int(packet.get("seq", 0))
	var previous = _seen(received_sequences, sender)
	if seq <= previous:
		return
	received_sequences[sender] = seq
	if seq != previous + 1:
		if authority():
			snapshot(0)
		else:
			request_snapshot()
		return
	if pending_snapshot is Dictionary:
		pending_dirty = true
		return
	if authority() and ((kind == "mode" and int(packet.get("player", 0)) == sender) or (kind == "action" and packet.get("action") is Dictionary and int(packet.action.get("player", 0)) == sender)):
		relay(sender, packet)
	if kind == "departed" and sender == int(SdkManager.lobby_master_id):
		apply_mode(int(packet.get("player", 0)), false)
		return
	if kind == "mode" and int(packet.get("player", 0)) == sender:
		if apply_mode(sender, bool(packet.get("enabled", false))):
			if authority() and not bool(packet.get("enabled", false)):
				owner._save_now()
			return
	elif kind == "action" and packet.get("action") is Dictionary and int(packet.action.get("player", 0)) == sender and modes.has(sender):
		applying = true
		var success = owner.apply_action(packet.action)
		applying = false
		if success:
			return
	# Rare conflicts recover from the host's current layout. Normal
	# pickups and placements never wait for this path.
	if authority():
		snapshot(0)
	else:
		request_snapshot()
