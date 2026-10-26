extends "res://TscnAndGd/UI/InGame/DayEndUI.gd"

var market_salary = 0
var market_refresh = 0
var market_severance = 0
var live_adjustment = false

func call_DayEnd():
	var market = get_node_or_null("/root/TalentMarket")
	if market == null or not market.api.offline() or ENDCHECK:
		.call_DayEnd()
		return
	market.api.log("day_end.payroll.begin tick=%s" % OS.get_ticks_msec())
	market_salary = market.charge_wages()
	market.api.log("day_end.payroll.done tick=%s salary=%s" % [OS.get_ticks_msec(), market_salary])
	market_refresh = int(market.state.get("refresh_spent", 0))
	market_severance = int(market.state.get("severance_spent", 0))
	live_adjustment = true
	.call_DayEnd()
	market.api.log("day_end.native.done tick=%s" % OS.get_ticks_msec())
	live_adjustment = false
	market.record_wages(market_salary)

func _Num_set(sell, tip, other, items, rent, water, electricity, staff, fine, count, buy_count, profit):
	var refresh_display = market_refresh if live_adjustment else 0
	._Num_set(sell, tip, other, int(items) - refresh_display, rent, water, electricity, staff, fine, count, buy_count, profit)
	var box = get_node("BG/DayInfoBG/VBox")
	var row = box.get_node_or_null("Minus/Staff")
	var staff_cost = int(staff) - (market_salary + market_severance if live_adjustment else 0)
	if row != null:
		row.show()
		row.get_node("Num").text = str(staff_cost)
	for path in ["Last/Total/Num", "Last/Profit/Num"]:
		var label = box.get_node(path)
		label.text = str(int(label.text) + staff_cost)
