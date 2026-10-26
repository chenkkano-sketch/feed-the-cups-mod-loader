extends Reference

const SLOT_COUNT = 4
# All retained skills are available; pools also define generation rarity.
const NORMAL = ["cashier", "restock_cups", "clean", "repair", "stock_basic", "trash_basic", "corporate_drone", "diligent", "athlete", "agile", "slacking_addiction", "slow_tempered", "aura", "clumsy"]
const ADVANCED = ["cashier_advanced", "stock_advanced", "trash_advanced", "craftsmanship", "workaholic", "godspeed", "aura_plus"]
const ENABLED = NORMAL + ADVANCED
const UPGRADED = {"cashier": "cashier_advanced", "stock_basic": "stock_advanced", "trash_basic": "trash_advanced", "aura": "aura_plus"}
const DEFINITIONS = {
	"cashier": {"name": "点单", "kind": "active", "tier": "normal", "description": "走到点单机前，为排队顾客完成点单。", "capabilities": ["cashier", "take_orders"]},
	"cashier_advanced": {"name": "高级点单", "kind": "active", "tier": "advanced", "description": "包含点单机点单；也会走到堂食桌旁为等候顾客点单。", "capabilities": ["cashier", "cashier_advanced", "take_orders", "take_table_orders"]},
	"restock_cups": {"name": "补充空杯", "kind": "active", "tier": "normal", "description": "从库存取对应尺寸杯组，在杯架剩余不超过4个时补充10个空杯。", "capabilities": ["restock_cups", "refill_cups"]},
	"clean": {"name": "清洁", "kind": "active", "tier": "normal", "description": "清扫垃圾、拖净污渍，保持店面整洁。", "capabilities": ["clean", "clean_floor"]},
	"repair": {"name": "设备维修", "kind": "active", "tier": "normal", "description": "优先修复电箱恢复供电，并维修出现故障的设备。", "capabilities": ["repair", "repair_power"]},
	"stock_basic": {"name": "货架整理", "kind": "active", "tier": "normal", "description": "仅从已经开封的箱子逐件取货上架，不搬运或拆开新包裹。", "capabilities": ["stock_basic", "stock_open_boxes"]},
	"stock_advanced": {"name": "高级货架整理", "kind": "active", "tier": "advanced", "description": "包含货架整理；还会搬运包裹、开箱，再逐件上架。", "capabilities": ["stock_basic", "stock_advanced", "stock_open_boxes", "move_packages", "open_packages"]},
	"trash_basic": {"name": "丢垃圾", "kind": "active", "tier": "normal", "description": "室内垃圾桶达到50%容量后，打包并清运到户外。", "capabilities": ["trash_basic", "empty_bins"], "modifiers": {"trash_fill_ratio": 0.5}},
	"trash_advanced": {"name": "高级丢垃圾", "kind": "active", "tier": "advanced", "description": "包含丢垃圾；空闲时也清运不足50%的垃圾桶，并清理废道具、拆平空箱投入垃圾桶。", "capabilities": ["trash_basic", "trash_advanced", "empty_bins", "clear_waste", "flatten_empty_packages"], "modifiers": {"trash_fill_ratio": 0.5}},
	"corporate_drone": {"name": "社畜", "kind": "passive", "tier": "normal", "description": "工作速度提高30%，可与其他工作速度被动相加叠加。", "modifiers": {"work_speed_bonus": 0.3}},
	"craftsmanship": {"name": "工匠精神", "kind": "passive", "tier": "advanced", "description": "工作速度提高50%，可与其他工作速度被动相加叠加。", "modifiers": {"work_speed_bonus": 0.5}},
	"diligent": {"name": "认真", "kind": "passive", "tier": "normal", "description": "工作速度提高15%，可与其他工作速度被动相加叠加。", "modifiers": {"work_speed_bonus": 0.15}},
	"workaholic": {"name": "工作狂", "kind": "passive", "tier": "advanced", "description": "工作速度提高50%，可与工匠精神及其他工作速度被动相加叠加。", "modifiers": {"work_speed_bonus": 0.5}},
	"godspeed": {"name": "神速", "kind": "passive", "tier": "advanced", "description": "移动速度提高30%，可与其他移动速度被动相加叠加。", "modifiers": {"move_speed_bonus": 0.3}},
	"athlete": {"name": "运动健将", "kind": "passive", "tier": "normal", "description": "移动速度提高20%，可与其他移动速度被动相加叠加。", "modifiers": {"move_speed_bonus": 0.2}},
	"agile": {"name": "灵活", "kind": "passive", "tier": "normal", "description": "移动速度提高10%，可与其他移动速度被动相加叠加。", "modifiers": {"move_speed_bonus": 0.1}},
	"slacking_addiction": {"name": "偷懒成瘾", "kind": "debuff", "tier": "normal", "description": "工作速度降低30%，可与慢性子并存，与其他工作速度加成相加抵消。", "modifiers": {"work_speed_bonus": -0.3}},
	"slow_tempered": {"name": "慢性子", "kind": "debuff", "tier": "normal", "description": "工作速度降低15%，可与偷懒成瘾并存，与其他工作速度加成相加抵消。", "modifiers": {"work_speed_bonus": -0.15}},
	"aura": {"name": "协作光环", "kind": "passive", "tier": "normal", "description": "180像素内其他店员动作耗时减少8%；同类光环取最强效果。", "modifiers": {"aura_radius": 180.0, "aura_work_duration": 0.92}},
	"aura_plus": {"name": "团队核心", "kind": "passive", "tier": "advanced", "description": "240像素内其他店员动作耗时减少15%，覆盖协作光环。", "modifiers": {"aura_radius": 240.0, "aura_work_duration": 0.85}},
	"clumsy": {"name": "笨手笨脚", "kind": "debuff", "tier": "normal", "description": "自身动作耗时增加30%，移动速度降低10%。", "modifiers": {"work_duration": 1.3, "move_speed": 0.9}}
}

static func get_skill(id):
	if not DEFINITIONS.has(str(id)):
		return {}
	var result = DEFINITIONS[str(id)].duplicate(true)
	result.id = str(id)
	if not result.has("capabilities"):
		result.capabilities = []
	if not result.has("modifiers"):
		result.modifiers = {}
	return result

static func valid_id(id):
	return id is String and (id == "" or DEFINITIONS.has(id))

static func stored_slots(person):
	var source = person.get("skill_slots", []) if person is Dictionary else person
	if not source is Array:
		source = []
	var result = []
	var seen = {}
	for index in range(SLOT_COUNT):
		var id = str(source[index]) if index < source.size() else ""
		if not valid_id(id) or (id != "" and seen.has(id)):
			id = ""
		result.append(id)
		if id != "":
			seen[id] = true
	for basic in UPGRADED:
		if basic in result and UPGRADED[basic] in result:
			result[result.find(basic)] = ""
	return result

static func slots(person):
	return stored_slots(person)

static func has_skill(person, id):
	var selected = slots(person)
	if str(id) in selected:
		return str(id) != ""
	return UPGRADED.has(str(id)) and UPGRADED[str(id)] in selected

static func capabilities(person):
	var result = {}
	for id in slots(person):
		for capability in get_skill(id).get("capabilities", []):
			result[capability] = true
	return result

static func modifiers(person):
	var selected = slots(person)
	var result = {"work_duration": 1.0, "move_speed": 1.0, "aura_radius": 0.0, "aura_work_duration": 1.0, "trash_fill_ratio": 0.5}
	var applied = {}
	var work_speed_bonus = 0.0
	var move_speed_bonus = 0.0
	for id in selected:
		if id.empty() or applied.has(id) or (UPGRADED.has(id) and UPGRADED[id] in selected):
			continue
		applied[id] = true
		var effect = get_skill(id).modifiers
		work_speed_bonus += float(effect.get("work_speed_bonus", 0.0))
		move_speed_bonus += float(effect.get("move_speed_bonus", 0.0))
		result.work_duration *= float(effect.get("work_duration", 1.0))
		result.move_speed *= float(effect.get("move_speed", 1.0))
		result.aura_radius = max(result.aura_radius, float(effect.get("aura_radius", 0.0)))
		result.aura_work_duration = min(result.aura_work_duration, float(effect.get("aura_work_duration", 1.0)))
		result.trash_fill_ratio = min(result.trash_fill_ratio, float(effect.get("trash_fill_ratio", 0.5)))
	# Speed bonuses add; duration is the reciprocal, never a subtraction that
	# reaches zero when several work passives share the four slots. Penalties
	# subtract from speed using the same baseline, rather than from duration.
	result.work_duration /= 1.0 + work_speed_bonus
	result.move_speed *= 1.0 + move_speed_bonus
	return result

static func slot_tier_from_roll(roll):
	var value = int(clamp(int(roll), 0, 99))
	return "empty" if value < 50 else ("normal" if value < 95 else "advanced")

static func roll_slot(rng, selected = []):
	var tier = slot_tier_from_roll(rng.randi_range(0, 99))
	if tier == "empty":
		return ""
	var pool = []
	for id in (NORMAL if tier == "normal" else ADVANCED):
		if id in ENABLED and not id in selected and not (UPGRADED.has(id) and UPGRADED[id] in selected):
			pool.append(id)
	if pool.empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]
