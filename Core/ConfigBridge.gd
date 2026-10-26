extends "res://TscnAndGd/Logics/SystemLogic/ConfigLogic.gd"

func _SceneConfig():
	._SceneConfig()
	preload("res://ftc_loader/Catalog.gd").apply_levels(SceneConfig)
	var api = get_node_or_null("/root/FtcModAPI")
	if api != null:
		api.apply_levels(SceneConfig)

func _FormulaConfigLoad():
	._FormulaConfigLoad()
	var api = get_node_or_null("/root/FtcModAPI")
	if api != null:
		api.apply_recipes(FormulaConfig)
