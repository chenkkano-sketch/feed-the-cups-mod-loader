extends "res://TscnAndGd/SdkManager/Logic/SdkManager.gd"

func read_logic(packet):
	if packet.get("message", "") == "FTC_FURNITURE":
		var mode = get_node_or_null("/root/FurnitureCarryMode")
		var args = packet.get("args", [])
		if mode != null and mode.session != null and args is Array and args.size() == 1:
			mode.session.receive(int(packet.get("from", 0)), args[0])
		return
	.read_logic(packet)
