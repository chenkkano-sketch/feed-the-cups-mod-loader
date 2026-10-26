extends Reference

const BEERS = ["拉格", "艾尔", "皮尔森", "IPA", "小麦", "世涛"]
const TEMPERATURES = {"Normal": 25, "Hot": 85, "Cold": 5, "去冰": 15, "粗冰": -10, "细冰": -5, "碎冰": -30, "圆冰": -40, "长冰": -50}

func held_cup(player):
	if not is_instance_valid(player):
		return null
	var control = player.get("Con")
	if not is_instance_valid(control) or control.get("IsHold") != true:
		return null
	var cup = control.get("HoldObj")
	if not is_instance_valid(cup) and int(control.get("HoldInsId")) > 0:
		cup = instance_from_id(int(control.get("HoldInsId")))
	if not is_instance_valid(cup) or not cup.has_method("return_EmptyCheck"):
		return null
	return cup

func prepare_held_cup(game, player):
	var cup = held_cup(player)
	if not is_instance_valid(cup):
		return "请先拿起一个已绑定订单的空杯"
	var order_id = int(cup.get("cur_ID"))
	var order_logic = game.get("Order")
	if order_id <= 0 or not order_logic.cur_OrderList.has(order_id):
		return "手上杯子的订单已失效，请重新取杯"
	if not cup.return_EmptyCheck():
		return "请使用空杯，已有内容的杯子不会被覆盖"
	var order = order_logic.cur_OrderList[order_id]
	if not is_instance_valid(order.get("NPC")):
		return "该订单顾客已离开，请重新取杯"
	var result = prepare_cup(game, cup, order)
	if not result.get("ok", false):
		return result.get("message", "此订单暂时无法自动配料")
	return "已配好 #" + str(order_id) + " " + str(result.recipe) + "，请自行出餐"

func prepare_cup(game, cup, order):
	var configs = game.Config.FormulaConfig
	var recipe_name = str(order.get("Name", ""))
	var candidates = [recipe_name]
	if recipe_name == "GOBLET":
		candidates = game.cur_Menu.duplicate()
	var original = {}
	var last_check = {}
	for candidate in candidates:
		if not configs.has(candidate):
			continue
		var state = recipe_state(configs[candidate], order, cup)
		if state.empty():
			continue
		if original.empty():
			for key in state:
				original[key] = _copy(cup.get(key))
		_apply(cup, state)
		var customer = order.get("NPC")
		var special = ["Pop"] if is_instance_valid(customer) and int(customer.get("SpecialType")) == 7 else []
		var check = game.Order.return_CanPickCheck_Bool(cup, special)
		last_check = check
		if perfect_check(check):
			_refresh_cup(cup, state)
			# Visual refresh functions may update mixing counters; retain recipe values.
			_apply(cup, state)
			return {"ok": true, "check": check, "recipe": candidate}
		_apply(cup, original)
	return {"ok": false, "message": "杯型不匹配或订单配方校验未通过，空杯已保留", "check": last_check}

func perfect_check(check):
	if not check is Dictionary or int(check.get("WrongType", 0)) != 1:
		return false
	# Match the game's rating calculation rather than overriding the rating.
	var points = 0
	for key in check:
		if not key in ["WrongType", "Stress", "_EXTRACHECKNUM"] and typeof(check[key]) == TYPE_INT:
			points += check[key]
	points -= int(check.get("Total", 0)) + int(check.get("ExtraMax", 0))
	return points >= int(check.get("Total", 0))

func recipe_state(formula, order, cup):
	var capacity = int(cup.get("Liquid_Max"))
	var layers = []
	for i in range(1, int(formula.get("FormulaNum", 0)) + 1):
		var ingredient = str(formula.get("For_" + str(i), ""))
		for _unit in range(max(0, int(formula.get("For_" + str(i) + "_Num", 0)))):
			if not ingredient.empty():
				layers.append(ingredient)
	if layers.empty() or capacity <= 0 or layers.size() > capacity:
		return {}
	var foam = max(0, int(order.get("BeerPop", 0)))
	var remaining_foam = foam
	for i in range(layers.size() - 1, -1, -1):
		if remaining_foam > 0 and layers[i] in BEERS:
			layers[i] = "啤酒泡"
			remaining_foam -= 1
	if remaining_foam > 0:
		return {}
	var liquids = {}
	for ingredient in layers:
		liquids[ingredient] = int(liquids.get(ingredient, 0)) + 1
	if int(formula.get("MakeType", 0)) == 3 and not liquids.has("啤酒泡"):
		liquids["啤酒泡"] = 0
	var sugar = int(order.get("Sugar", 1))
	var sugar_type = 1 if sugar == 2 else (2 if sugar == 3 else 0)
	var celcius = str(order.get("Celcius", "Normal"))
	var mix = int(formula.get("Mixd", 0))
	var state = {
		"LIQUID_DIR": liquids, "LIQUID_ARRAY": layers, "Liquid_Count": layers.size(),
		"SugarType": sugar_type, "Celcius": celcius,
		"WaterCelcius": int(TEMPERATURES.get(celcius, 25)),
		"HasHot": celcius == "Hot", "HasIce": not celcius in ["Normal", "Hot", "去冰"],
		"Is_Mix": mix in [1, 3, 4], "Can_Mix": false,
		"MixInt": capacity - 1 if mix == 3 else (capacity - 2 if mix == 4 else (layers.size() if mix == 1 else 0)),
		"Pop": max(0, int(order.get("Pop", 0))), "BeerPop": foam,
		"Top": str(formula.get("Top", "")), "Hang": str(formula.get("Hang", "")),
		"IsPassDay": false, "IsStale": false, "IsPack": str(cup.get("FuncType")) == "SodaCan"
	}
	var extras = order.get("ExtraArray", [])
	if extras.size() > 5:
		return {}
	for i in range(1, 6):
		state["Extra_" + str(i)] = str(extras[i - 1]) if i <= extras.size() else ""
	for i in range(1, 4):
		state["Condiment_" + str(i)] = str(formula.get("Condiment_" + str(i), ""))
	return state

func _copy(value):
	return value.duplicate(true) if value is Array or value is Dictionary else value

func _apply(cup, state):
	for key in state:
		cup.set(key, _copy(state[key]))

func _refresh_cup(cup, state):
	if cup.has_method("call_Liquid_Array"):
		cup.call_Liquid_Array(state.LIQUID_ARRAY)
	if state.Is_Mix and cup.has_method("call_mix"):
		cup.call_mix()
	if cup.has_method("_WaterCelcius_Show"):
		cup._WaterCelcius_Show()
	if state.SugarType > 0 and cup.has_method("call_Sugar_In"):
		cup.call_Sugar_In(state.SugarType)
	if cup.has_method("call_add_extra"):
		cup.call_add_extra()
	for i in range(1, 4):
		var condiment = state["Condiment_" + str(i)]
		if not condiment.empty() and cup.has_method("call_Condiment_play"):
			cup.call_Condiment_play(condiment, i)
	if cup.has_method("call_Pop_Logic"):
		cup.call_Pop_Logic()
	if state.BeerPop > 0 and cup.has_method("call_BeerTop"):
		cup.call_BeerTop(state.BeerPop)
	if state.IsPack and cup.has_method("_IsPack_Logic"):
		cup._IsPack_Logic()
	for property in ["Top", "Hang"]:
		var node_name = "Top" if property == "Top" else "HangCup"
		var decoration = str(state[property])
		for prefix in ["AniNode/", "CupInfo/bg/DrinkCup/AniNode/"]:
			var animation = cup.get_node_or_null(prefix + node_name)
			if animation is AnimationPlayer and animation.has_animation(decoration):
				animation.play(decoration)
				animation.advance(0)
	# Complete the fill-level visuals on both the cup and its held-cup preview.
	for path in ["AniNode/CupAni", "CupInfo/bg/DrinkCup/AniNode/CupAni"]:
		var animation = cup.get_node_or_null(path)
		var name = "ball" + str(int(ceil(state.Liquid_Count / 2.0))) if str(cup.get("FuncType")) == "EggRollCup" else "Layer" + str(state.Liquid_Count)
		if animation is AnimationPlayer and animation.has_animation(name):
			animation.play(name)
			animation.advance(0)

func take_next_order(game, player):
	if not is_instance_valid(game) or not is_instance_valid(player):
		return false
	var orders = game.get("Order")
	if not is_instance_valid(orders):
		return false
	for customer in orders.cur_LineUpArray.duplicate():
		if not is_instance_valid(customer):
			orders.cur_LineUpArray.erase(customer)
			continue
		var existing_id = int(customer.get("PickUpID"))
		if existing_id > 0 and orders.cur_OrderList.has(existing_id):
			orders.cur_LineUpArray.erase(customer)
			continue
		orders.call_player_order(player)
		return true
	for customer in orders.cur_TableOrderArray.duplicate():
		if not is_instance_valid(customer):
			orders.cur_TableOrderArray.erase(customer)
			continue
		var existing_id = int(customer.get("PickUpID"))
		if existing_id > 0 and orders.cur_OrderList.has(existing_id):
			orders.cur_TableOrderArray.erase(customer)
			continue
		orders.call_TableOrder(player, customer)
		return true
	return false

func take_order_cup(game, player, holders):
	if not is_instance_valid(game) or not is_instance_valid(player):
		return 0
	var control = player.get("Con")
	if not is_instance_valid(control):
		return 0
	# A mop, ingredient box, or an existing cup must never be replaced.
	if control.get("IsHold") == true or is_instance_valid(control.get("HoldObj")):
		return 0
	var orders = game.get("Order")
	if not is_instance_valid(orders) or orders.cur_OrderList.empty():
		return 0
	var pending = orders.cur_OrderArray.duplicate()
	if pending.empty():
		pending = orders.cur_OrderList.keys()
	var staff = game.get("Staff")
	var level = staff.get("LevelNode") if is_instance_valid(staff) else null
	for holder in holders:
		if not is_instance_valid(holder) or not holder.is_inside_tree():
			continue
		if holder is CanvasItem and not holder.is_visible_in_tree():
			continue
		if is_instance_valid(level) and not level.is_ancestor_of(holder):
			continue
		if not holder.has_method("call_NextCup_Logic") or not holder.has_method("call_DevLogic"):
			continue
		var candidates = pending.duplicate()
		var selected = int(holder.get("_Cur_ID"))
		if candidates.has(selected):
			candidates.erase(selected)
			candidates.push_front(selected)
		for order_id in candidates:
			if not orders.cur_OrderList.has(order_id) or orders.cur_CupArray.has(order_id):
				continue
			var order = orders.cur_OrderList[order_id]
			if not is_instance_valid(order.get("NPC")):
				continue
			var recipe = str(order.get("Name", ""))
			if not game.Config.FormulaConfig.has(recipe):
				continue
			var formula = game.Config.FormulaConfig[recipe]
			# This rack dispenses ordinary drink cups. Other container types stay manual.
			if int(formula.get("MakeType", 0)) != 0:
				continue
			var size = str(formula.get("CupType", ""))
			if not size in ["S", "M", "L"] or int(holder.get(size + "_Num")) <= 0:
				continue
			if selected != int(order_id) or holder.get("CanTake_bool") != true or not is_instance_valid(holder.get("Take_DEV")):
				holder.set("_Take_ID", order_id)
				holder.call_NextCup_Logic()
			if holder.get("CanTake_bool") != true or int(holder.get("_Cur_ID")) != int(order_id):
				continue
			# Use the game's existing pickup path for stock, ticket, carry state and UI.
			holder.call_DevLogic(0, player, null)
			var cup = held_cup(player)
			if is_instance_valid(cup) and int(cup.get("cur_ID")) == int(order_id):
				return int(order_id)
			if control.get("IsHold") == true:
				return 0
	return 0
