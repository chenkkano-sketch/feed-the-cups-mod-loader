extends Reference

var market

func on_load(context):
	for definition in preload("res://ftc_loader/Catalog.gd").read().get("mods", []):
		if definition.id == "ftc.rent_mode" and not "ftc.talent_market" in definition.get("load_after", []):
			context.log("人才市场需要房租模式 0.8.1 或更新版本的兼容补丁；请同时导入新版房租模块。")
			return false
	market = preload("res://ftc_mods/ftc.talent_market/TalentMarket.gd").new()
	market.api = context
	if context.add_root("TalentMarket", market) == null:
		return false
	context.provide_service("market", market)
	return true
