extends Reference
var api
var rent
func on_load(context):
    api = context
    rent = preload("res://ftc_mods/ftc.rent_mode/RentMode.gd").new()
    rent.api = api
    if api.add_root("RentMode", rent) == null:
        return false
    api.provide_service("mode", rent)
    api.register_control_hook(self, "_control", 100)
    api.register_movement_provider(rent.sprint, "factor_for")
    return true
func _control(actor, button, value, type):
    if rent.sprint.reserves_shift(actor, button, type):
        return true
    return false
