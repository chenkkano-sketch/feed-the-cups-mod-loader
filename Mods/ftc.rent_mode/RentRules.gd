extends Reference

const Maps = preload("res://ftc_mods/ftc.rent_mode/RentMaps.gd")
const VERSION = 5
# Default (150 first-day rent) pressure curve; never drops at stage boundaries.
const PRESSURE_RENTS = [150, 350, 700, 1500, 2800, 4000, 5200, 6500, 8000, 9500, 11000, 13000, 15000, 17500, 20000, 23000, 26000, 30000, 34000, 39000, 44000, 50000, 56000, 63000]
# Keep the original curve solely as the payroll baseline. Raising shop rent
# must not multiply every existing employee's daily wage a second time.
const STAGE_BASES = [300, 800, 2000, 5000, 11000, 20000, 35000, 50000]
const DAILY_MULTIPLIERS = [1.0, 1.5, 2.0]
const MAX_RENT = 1000000000000
const LATE_PRESSURE_DAY = 6
const LATE_PRESSURE_95_DAILY = 1.7
const TRAFFIC_GROWTH_PER_DAY = 0.05
const TRAFFIC_MAX_MULTIPLIER = 6.0
const INCOME_RENT_SHARE = 0.5
const STARTERS = ["橙汁S", "净水S", "蜜糖橙汁S", "柠檬橙汁S", "速溶奶茶S", "椰果奶茶S", "抹茶S", "脏脏热牛奶S", "红茶S", "乌龙茶S", "白茶S", "黑糖牛奶S"]

static func defaults():
	return {"version": VERSION, "map": Maps.DEFAULT, "progression": "native", "curve": "staged", "pressure": 35, "menu": Maps.room(Maps.DEFAULT).menu.duplicate(), "funds": 1500, "rent": 150, "growth": 15, "lost_limit": 3}

static func traffic_multiplier(day):
	return min(TRAFFIC_MAX_MULTIPLIER, 1.0 + float(max(0, int(day) - 1)) * TRAFFIC_GROWTH_PER_DAY)

static func failure_reward_cap(settings):
	return int(round(clamp(float(settings.get("pressure", 50)), 0.0, 100.0) * 200.0))

static func failure_reward(cash, settings):
	return int(min(failure_reward_cap(settings), floor(max(0.0, float(cash)) / 20.0)))

static func income_rent_floor(settings, daily_income):
	# A strong trading day can raise later rent, but a weak day never lowers it.
	var pressure = clamp(float(settings.get("pressure", 50)), 0.0, 100.0) / 100.0
	return int(min(float(MAX_RENT), round(max(0.0, float(daily_income)) * pressure * INCOME_RENT_SHARE)))

static func for_new_run(saved):
	var result = saved.duplicate(true)
	result.map = Maps.starting_room(saved.get("map", Maps.DEFAULT)).id
	if int(result.get("version", 1)) < 2:
		result.curve = "staged"
		result.rent = 150
	result.version = VERSION
	result.pressure = saved.get("pressure", 50)
	result.progression = "native"
	result.menu = Maps.room(result.map).menu.duplicate()
	return result

static func validate(settings):
	if typeof(settings) != TYPE_DICTIONARY:
		return "开局设置无效"
	if not Maps.has_room(settings.get("map", Maps.DEFAULT)):
		return "请选择有效的开局地图"
	if not settings.get("curve", "linear") in ["linear", "staged"]:
		return "租金曲线无效"
	if typeof(settings.get("menu")) != TYPE_ARRAY or settings.menu.size() < 1 or settings.menu.size() > 3:
		return "初始菜谱无效"
	var native_route = settings.get("progression", "legacy") == "native"
	if native_route and settings.menu != Maps.starting_room(settings.get("map", Maps.DEFAULT)).menu:
		return "初始菜谱由地图决定"
	var seen = []
	for item in settings.menu:
		if (not native_route and not item in STARTERS) or item in seen:
			return "菜谱无效或重复"
		seen.append(item)
	for key in ["funds", "rent", "growth", "lost_limit"]:
		if not typeof(settings.get(key)) in [TYPE_INT, TYPE_REAL]:
			return "经营参数无效"
	if settings.funds < 300 or settings.funds > 5000:
		return "初始资金需要在 300～5000 之间"
	if settings.rent < 1 or settings.rent > 500 or settings.growth < 1 or settings.growth > 200:
		return "房租需要为 1～500，每日涨租需要为 1～200"
	if settings.lost_limit < 1 or settings.lost_limit > 10:
		return "每日流失上限需要为 1～10"
	var pressure = settings.get("pressure", 50)
	if not typeof(pressure) in [TYPE_INT, TYPE_REAL] or pressure < 0 or pressure > 100:
		return "租金压力需要为 0～100%"
	var native_devil = settings.get("native_devil", 0)
	if not typeof(native_devil) in [TYPE_INT, TYPE_REAL] or native_devil < 0 or native_devil > 8:
		return "原版难度设置无效"
	var difficulty_multiplier = settings.get("store_difficulty_multiplier", 1)
	if not difficulty_multiplier in [1, 3, 5]:
		return "初始店铺难度无效"
	return ""

static func rent_for_day(settings, day):
	if settings.get("curve", "linear") == "linear":
		return _payroll_rent_for_day(settings, day)
	var elapsed = max(0, int(day) - 1)
	var pressure = float(settings.get("pressure", 50))
	# The staged curve's easy endpoint is tied to starting rent, not the
	# unrelated custom-linear increment, so increasing pressure never gets easier.
	var linear = min(float(MAX_RENT), float(settings.rent) * (1.0 + float(elapsed) * 0.1))
	var standard = float(_standard_rent_for_day(settings, day))
	if pressure <= 50.0:
		return int(min(float(MAX_RENT), round(lerp(linear, standard, pressure / 50.0))))
	# Keep the first six days unchanged. The base table slows after day six, so
	# high pressure adds another compound factor from day seven onward.
	# At 95% pressure this factor is 1.7 per extra day; wages stay unchanged.
	var rate = log(1.15) * (pressure - 50.0) / 50.0
	var late_days = max(0, int(day) - LATE_PRESSURE_DAY)
	var late_rate = log(LATE_PRESSURE_95_DAILY) * (pressure - 50.0) / 45.0
	var exponent = float(elapsed) * rate + float(late_days) * late_rate
	if standard >= float(MAX_RENT) or exponent >= log(float(MAX_RENT) / max(1.0, standard)):
		return MAX_RENT
	return int(min(float(MAX_RENT), round(standard * exp(exponent))))

static func _standard_rent_for_day(settings, day):
	var elapsed = max(0, int(day) - 1)
	var scale = float(settings.rent) / 150.0
	if elapsed < PRESSURE_RENTS.size():
		return int(min(float(MAX_RENT), round(float(PRESSURE_RENTS[elapsed]) * scale)))
	var anchor = float(PRESSURE_RENTS.back()) * scale
	var exponent = elapsed - PRESSURE_RENTS.size() + 1
	if float(exponent) >= log(float(MAX_RENT) / anchor) / log(1.1):
		return MAX_RENT
	return int(min(float(MAX_RENT), round(anchor * pow(1.1, exponent))))

static func wage_multiplier_for_day(settings, day):
	var initial = max(1, _payroll_rent_for_day(settings, 1))
	return float(_payroll_rent_for_day(settings, day)) / float(initial)

static func _payroll_rent_for_day(settings, day):
	var elapsed = max(0, int(day) - 1)
	# Missing curve means an existing v0.1 contract; never reinterpret its terms.
	if settings.get("curve", "linear") == "linear":
		return int(min(float(MAX_RENT), float(settings.rent) + float(elapsed) * float(settings.growth)))
	var stage = int(elapsed / 3)
	var within_stage = int(elapsed % 3)
	var scale = float(settings.rent) / 300.0
	var base = 0.0
	if stage < STAGE_BASES.size():
		base = float(STAGE_BASES[stage]) * scale
	else:
		# Continue the staged challenge without copying Balatro's super-exponential
		# score targets: this game's income still depends on serving real customers.
		var anchor = 50000.0 * scale * DAILY_MULTIPLIERS[within_stage]
		var exponent = stage - 7
		if float(exponent) >= log(float(MAX_RENT) / anchor) / log(1.6):
			return MAX_RENT
		return int(min(float(MAX_RENT), round(anchor * pow(1.6, exponent))))
	return int(min(float(MAX_RENT), round(base * DAILY_MULTIPLIERS[within_stage])))

static func settle(cash, rent):
	return {"cash": int(cash) - int(rent), "failed": int(cash) < int(rent)}

static func rent_multiplier(rewards, challenges, event):
	var multiplier = 1.0
	for spec in [["涨租", 0.25], ["涨租+", 0.5], ["涨租++", 1.0]]:
		if spec[0] in challenges:
			multiplier += spec[1]
	if "租金降低" in rewards:
		multiplier -= 0.25
	if "租金降低+" in rewards:
		multiplier -= 0.5
	if event in ["免房租", "大免单"]:
		multiplier = 0.0
	return max(0.0, multiplier)
