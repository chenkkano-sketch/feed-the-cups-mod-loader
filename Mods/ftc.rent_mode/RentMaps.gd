extends Reference

const DEFAULT = "2_2"
const PROFILE_FIELDS = ["Menu", "MenuStart", "MenuMax", "ExtraMax", "MenuList", "Type", "Tag", "Can", "Machine", "DrinkTypeList", "Cold", "Hot", "Normal", "Sugar", "Fresh", "S", "M", "L", "Popular", "StarMax", "DevilList", "DevilMax", "CustomersList", "OpenTime", "CloseTime", "OpeningHours", "PeakTime", "BGMName", "Season"]
const ROOMS = [
	{"id": "2_1", "name": "紧凑店铺", "level": "美食街1", "menu": ["速溶奶茶S"], "route": "奶茶、豆乳 · 椰果配料", "area": 36, "info": "较小的操作区，单套炉台和茶壶。适合集中布置、缩短移动距离。"},
	{"id": "2_2", "name": "标准店铺", "level": "美食街2", "menu": ["抹茶S"], "route": "牛奶、茶饮 · 红豆配料", "area": 42, "info": "双套炉台和茶壶，配备热水机及台式冰箱。"},
	{"id": "2_3", "name": "宽型店铺", "level": "美食街3", "menu": ["脏脏热牛奶S"], "route": "牛奶、奶茶 · 速挂配料", "area": 48, "info": "横向展开的操作区，设备分布更宽，另有落地冰箱与清洁池。"},
	{"id": "4_1", "name": "写字楼1", "level": "写字楼1", "menu": ["双倍浓缩S"], "route": "咖啡、果汁 · 基础咖啡", "area": 46, "scene": "ftc.rent_mode.office_1", "info": "原版办公楼环境，三处取餐台，配备咖啡机和热水机。"},
	{"id": "4_2", "name": "写字楼2", "level": "写字楼2", "menu": ["白咖啡S"], "route": "牛奶、咖啡 · 奶咖", "area": 60, "scene": "ftc.rent_mode.office_2", "info": "原版楼梯大厅，四处取餐台，配备咖啡机、炉台与茶壶。"},
	{"id": "5_1", "name": "体育场1", "level": "体育场1", "menu": ["苏打水S"], "route": "汽水 · 普通汽水", "area": 40, "scene": "ftc.rent_mode.gym_1", "info": "原版球场看台环境，配备汽水机、燃气炉和大锅。"},
	{"id": "3_2", "name": "古街2", "level": "古街2", "menu": ["暴打草莓牛奶S"], "route": "果茶、果汁 · 暴打系列", "area": 70, "scene": "ftc.rent_mode.old_street_2", "info": "原版古街环境，保留堂食座位、大锅、冷藏设备与备料台。"},
	{"id": "1_1", "name": "社区店1", "level": "社区店1", "menu": ["净水S"], "route": "果汁", "area": 40, "scene": "ftc.rent_mode.level_1_1", "info": "原版「社区店1」店铺及设备布局。"},
	{"id": "1_2", "name": "社区店2", "level": "社区店2", "menu": ["鲜柠水S"], "route": "果汁", "area": 64, "scene": "ftc.rent_mode.level_1_2", "info": "原版「社区店2」店铺及设备布局。"},
	{"id": "1_3", "name": "社区店3", "level": "社区店3", "menu": ["纯鲜橙S"], "route": "果汁", "area": 63, "scene": "ftc.rent_mode.level_1_3", "info": "原版「社区店3」店铺及设备布局。"},
	{"id": "2_4", "name": "美食街4", "level": "美食街4", "menu": ["玫瑰西米露S"], "route": "奶茶", "area": 59, "scene": "ftc.rent_mode.level_2_4", "info": "原版「美食街4」店铺及设备布局。"},
	{"id": "4_3", "name": "写字楼3", "level": "写字楼3", "menu": ["康宝蓝S"], "route": "咖啡", "area": 54, "scene": "ftc.rent_mode.level_4_3", "info": "原版「写字楼3」店铺及设备布局。"},
	{"id": "4_4", "name": "写字楼4", "level": "写字楼4", "menu": ["生酪咖啡S"], "route": "咖啡", "area": 85, "scene": "ftc.rent_mode.level_4_4", "info": "原版「写字楼4」店铺及设备布局。"},
	{"id": "6_1", "name": "公园1", "level": "公园1", "menu": ["红茶S"], "route": "公园茶饮", "area": 0, "scene": "ftc.rent_mode.level_6_1", "info": "原版「公园1」店铺及设备布局。"},
	{"id": "6_2", "name": "公园2", "level": "公园2", "menu": ["乌龙茶S"], "route": "公园茶饮", "area": 0, "scene": "ftc.rent_mode.level_6_2", "info": "原版「公园2」店铺及设备布局。"},
	{"id": "6_3", "name": "公园3", "level": "公园3", "menu": ["白茶S"], "route": "公园茶饮", "area": 0, "scene": "ftc.rent_mode.level_6_3", "info": "原版「公园3」店铺及设备布局。"},
	{"id": "6_4", "name": "公园4", "level": "公园4", "menu": ["黑糖牛奶S"], "route": "公园茶饮", "area": 0, "scene": "ftc.rent_mode.level_6_4", "info": "原版「公园4」店铺及设备布局。"},
	{"id": "5_2", "name": "体育场2", "level": "体育场2", "menu": ["杯事可乐S"], "route": "汽水", "area": 0, "scene": "ftc.rent_mode.level_5_2", "info": "原版「体育场2」店铺及设备布局。"},
	{"id": "5_3", "name": "体育场3", "level": "体育场3", "menu": ["青柠蓝柑M"], "route": "汽水", "area": 0, "scene": "ftc.rent_mode.level_5_3", "info": "原版「体育场3」店铺及设备布局。"},
	{"id": "5_4", "name": "体育场4", "level": "体育场4", "menu": ["薄荷可乐S"], "route": "汽水", "area": 80, "scene": "ftc.rent_mode.level_5_4", "info": "原版「体育场4」店铺及设备布局。"},
	{"id": "3_1", "name": "古街1", "level": "古街1", "menu": ["黄瓜汁S"], "route": "果茶", "area": 0, "scene": "ftc.rent_mode.level_3_1", "info": "原版「古街1」店铺及设备布局。"},
	{"id": "3_3", "name": "古街3", "level": "古街3", "menu": ["姜撞奶S"], "route": "果茶", "area": 0, "scene": "ftc.rent_mode.level_3_3", "info": "原版「古街3」店铺及设备布局。"},
	{"id": "3_4", "name": "古街4", "level": "古街4", "menu": ["夏日桂花糖水M", "夏日桂花果捞M"], "route": "果茶", "area": 0, "scene": "ftc.rent_mode.level_3_4", "info": "原版「古街4」店铺及设备布局。"},
	{"id": "7_1", "name": "游乐园1", "level": "游乐园1", "menu": ["酸奶冰S"], "route": "游乐园饮品", "area": 0, "scene": "ftc.rent_mode.level_7_1", "info": "原版「游乐园1」店铺及设备布局。"},
	{"id": "7_2", "name": "游乐园2", "level": "游乐园2", "menu": ["草莓冰S"], "route": "游乐园饮品", "area": 0, "scene": "ftc.rent_mode.level_7_2", "info": "原版「游乐园2」店铺及设备布局。"},
	{"id": "7_3", "name": "游乐园3", "level": "游乐园3", "menu": ["暴风雪1S"], "route": "游乐园饮品", "area": 60, "scene": "ftc.rent_mode.level_7_3", "info": "原版「游乐园3」店铺及设备布局。"},
	{"id": "7_4", "name": "游乐园4", "level": "游乐园4", "menu": ["蛋卷1S"], "route": "游乐园饮品", "area": 80, "scene": "ftc.rent_mode.level_7_4", "info": "原版「游乐园4」店铺及设备布局。"},
	{"id": "8_1", "name": "酒吧1", "level": "酒吧1", "menu": ["原浆1S"], "route": "酒吧饮品", "area": 40, "scene": "ftc.rent_mode.level_8_1", "info": "原版「酒吧1」店铺及设备布局。"},
	{"id": "8_2", "name": "酒吧2", "level": "酒吧2", "menu": ["精酿1M"], "route": "酒吧饮品", "area": 50, "scene": "ftc.rent_mode.level_8_2", "info": "原版「酒吧2」店铺及设备布局。"},
	{"id": "8_3", "name": "酒吧3", "level": "酒吧3", "menu": ["调酒1M", "调酒2M", "调酒3L"], "route": "酒吧饮品", "area": 60, "scene": "ftc.rent_mode.level_8_3", "info": "原版「酒吧3」店铺及设备布局。"},
	{"id": "8_4", "name": "酒吧4", "level": "酒吧4", "menu": ["雪克1S"], "route": "酒吧饮品", "area": 80, "scene": "ftc.rent_mode.level_8_4", "info": "原版「酒吧4」店铺及设备布局。"}
]

# Existing tutorial saves still load their original geometry and equipment.
# This retired map is deliberately excluded from new-run choices.
const LEGACY_ROOMS = [
	{"id": "tutorial", "name": "超大店铺", "area": 92, "scene": "ftc.rent_mode.tutorial", "preview": "res://ftc_mods/ftc.rent_mode/Maps/TutorialShop.tscn"}
]

static func has_room(id):
	for room in ROOMS + LEGACY_ROOMS:
		if room.id == id:
			return true
	return false

static func room(id):
	for item in ROOMS + LEGACY_ROOMS:
		if item.id == id:
			return item
	return ROOMS[1]

static func selected(settings):
	return room(settings.get("map", DEFAULT))

static func starting_room(id):
	for item in ROOMS:
		if item.id == id:
			return item
	return room(DEFAULT)

static func room_for_level(level):
	for item in ROOMS:
		if item.level == level:
			return item
	return {}
