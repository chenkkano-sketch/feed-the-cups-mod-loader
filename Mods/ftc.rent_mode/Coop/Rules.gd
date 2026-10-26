extends Reference

const PROTOCOL = 1
const REQUIRED = ["ftc.furniture_carry", "ftc.rent_mode"]

static func compatible(local_versions, peer_versions):
	if not local_versions is Dictionary or not peer_versions is Dictionary or local_versions.size() != peer_versions.size():
		return false
	for id in REQUIRED:
		if str(local_versions.get(id, "")) == "" or local_versions.get(id) != peer_versions.get(id):
			return false
	for id in local_versions:
		if str(local_versions[id]) == "" or not peer_versions.has(id) or local_versions[id] != peer_versions[id]:
			return false
	return true

static func accept_snapshot(packet, run, revision):
	if not packet is Dictionary or not packet.get("state") is Dictionary or not packet.get("game") is Dictionary:
		return false
	if not packet.state.get("settings") is Dictionary or preload("res://ftc_mods/ftc.rent_mode/RentRules.gd").validate(packet.state.settings) != "":
		return false
	var incoming = str(packet.state.get("coop_run", ""))
	return incoming != "" and incoming == run and int(packet.get("revision", -1)) > revision

static func can_edit(editor, requester, preparing, empty_hands):
	return requester > 0 and preparing and empty_hands and (editor == 0 or editor == requester)
