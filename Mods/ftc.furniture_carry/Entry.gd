extends Reference

var mode

func on_load(context):
	mode = preload("res://ftc_mods/ftc.furniture_carry/FurnitureMode.gd").new()
	mode.api = context
	if context.add_root("FurnitureCarryMode", mode) == null:
		return false
	context.provide_service("mode", mode)
	context.provide_service("carry", mode.carry)
	context.register_control_hook(self, "_control", 200, true)
	return true

func _control(actor, button, value, _type):
	if SdkManager.is_multiplay:
		return mode.coop_control(actor, button, value)
	return mode.carry.handle_control(actor, button, value)
