extends Reference
var api
func on_load(context):
	api = context
	api.set_movement_multiplier(1.1)
	api.subscribe("day_start", self, "_day_start")
	api.log("SDK 示例已加载，移动倍率 ×1.1")
	return true
func _day_start(_event):
	api.log("新一天开始")
func on_unload():
	api.set_movement_multiplier(1.0)
