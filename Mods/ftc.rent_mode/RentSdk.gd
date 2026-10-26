extends "res://TscnAndGd/SdkManager/Logic/SdkManager.gd"

func read_logic(packet):
	if packet.get("message", "") == "FTC_RENT_COOP":
		var mode = get_node_or_null("/root/RentMode")
		var args = packet.get("args", [])
		if mode != null and mode.coop != null and args is Array and args.size() == 1:
			mode.coop.receive(int(packet.get("from", 0)), args[0])
		return
	.read_logic(packet)
