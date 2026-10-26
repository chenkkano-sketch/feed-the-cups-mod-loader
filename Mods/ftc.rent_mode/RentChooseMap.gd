extends "res://TscnAndGd/UI/InGame/ChooseMap.gd"

const CATEGORY_NAMES = ["果汁", "奶茶", "咖啡", "公园茶饮", "汽水", "果茶", "游乐园饮品", "酒吧饮品"]

func _rent_entry():
	var scroll = get_parent().get_parent()
	return scroll.has_meta("ftc_rent_entry")

func call_init():
	.call_init()
	if not _rent_entry():
		return
	get_node("Control/BG/LevelName/Label").text = "房租模式 城市"
	for index in range(1, 9):
		var button = MapNode.get_node(str(index))
		button.LockBool = false
		button.call_init()
		button.NameLabel.text = CATEGORY_NAMES[index - 1]
		button.InfoLabel.text = "房租模式 · %s菜谱" % CATEGORY_NAMES[index - 1]
