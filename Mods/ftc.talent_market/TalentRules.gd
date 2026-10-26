extends Reference

const Catalog = preload("res://ftc_mods/ftc.talent_market/Skills/SkillCatalog.gd")
const VERSION = 2
const MAX_STAFF = 4
const CANDIDATE_COUNT = 5
const MAX_REFRESH_PRICE = 1000000000
const ROLES = ["employee"]
const NAMES = {"employee": "店员"}
const DUTIES = {"employee": "根据已拥有的主动技能安排工作"}
const LEGACY_ROLES = ["cashier", "drink", "logistics", "chef"]
const STAR_WEIGHTS = [750, 200, 30, 10, 8, 2]
const STAR_DURATIONS = [2.5, 2.0, 1.75, 1.5, 1.25, 0.5]
const STAR_COLOR_NAMES = ["白", "蓝", "粉", "紫", "金", "彩"]
const STAR_COLORS = [Color(0.94, 0.94, 0.94), Color(0.35, 0.65, 1.0), Color(1.0, 0.55, 0.75), Color(0.72, 0.42, 1.0), Color(1.0, 0.8, 0.25), Color(0.55, 1.0, 0.8)]
const FASHION_PARTS = ["Head", "Body", "Face", "Foot", "Hand", "Accessory_1", "Accessory_2", "Accessory_3"]
const OUTFIT_ANIMATION_NAMES = ["DecoHatType", "ApronType", "MaskType", "ShoeType", "CloveType", "NeckType", "PackbagType", "ScarfType", "CardType", "EffectType", "WatchType"]

static func appearance(person):
	var fashion = {}
	var saved = person.get("fashion", {})
	if not saved is Dictionary:
		saved = {}
	for part in FASHION_PARTS:
		fashion[part] = max(0, int(saved.get(part, 0)))
	return {"avatar": max(0, int(person.get("avatar", 0))), "skin": int(clamp(int(person.get("skin", 1)), 1, 4)), "fashion": fashion}

static func apply_appearance(person):
	var outfit = appearance(person)
	for key in outfit:
		person[key] = outfit[key]
	return person

static func appearance_key(person):
	var outfit = appearance(person)
	var fields = [str(outfit.avatar), str(outfit.skin)]
	for part in FASHION_PARTS:
		fields.append(str(outfit.fashion[part]))
	return PoolStringArray(fields).join(":")

static func duration_star(stars):
	return STAR_DURATIONS[int(clamp(int(stars), 1, 6)) - 1]

static func star_color(stars):
	return STAR_COLORS[int(clamp(int(stars), 1, 6)) - 1]

static func star_color_name(stars):
	return STAR_COLOR_NAMES[int(clamp(int(stars), 1, 6)) - 1]

static func star_name(stars):
	return star_color_name(stars) + "色"

static func star_text(stars):
	var result = ""
	for _index in range(int(clamp(int(stars), 1, 6))):
		result += "★"
	return result

static func star_from_roll(roll):
	var value = int(clamp(int(roll), 0, 999))
	for index in range(STAR_WEIGHTS.size()):
		if value < STAR_WEIGHTS[index]:
			return index + 1
		value -= STAR_WEIGHTS[index]
	return 6

static func capabilities(person):
	return Catalog.capabilities(person)

static func modifiers(person):
	return Catalog.modifiers(person)

static func wage(person_or_stars, slots = []):
	var stars = int(person_or_stars.get("stars", 1)) if person_or_stars is Dictionary else int(person_or_stars)
	var selected = Catalog.slots(person_or_stars) if person_or_stars is Dictionary else Catalog.slots(slots)
	var amount = [40, 65, 95, 140, 205, 300][int(clamp(stars, 1, 6)) - 1]
	var counted = {}
	for id in selected:
		if id.empty() or counted.has(id):
			continue
		counted[id] = true
		var info = Catalog.get_skill(id)
		if info.kind == "debuff":
			amount -= 8
		elif info.tier == "advanced":
			amount += 35
		else:
			amount += 18 if info.kind == "active" else 12
	return max(20, amount)

static func refresh_cost(refresh_index):
	var amount = 100
	for _index in range(int(clamp(int(refresh_index), 0, 24))):
		amount = min(MAX_REFRESH_PRICE, amount * 2)
	return int(amount)

static func refresh_price(refresh_index):
	return refresh_cost(refresh_index)

static func empty_state():
	return {"version": VERSION, "run_id": str(OS.get_unix_time()) + ":" + str(OS.get_ticks_usec()) + ":" + str(randi()), "seed": int(randi() % 1000000000), "day": 0, "refresh_index": 0, "candidates": [], "staff": [], "staff_archive": [], "shift": {}, "paid_day": 0, "paid_amount": 0}

static func candidates(seed_value, day, catalog = [], refresh_index = 0):
	var rng = RandomNumberGenerator.new()
	rng.seed = int(seed_value) + int(day) * 7919 + int(refresh_index) * 65497
	var looks = RandomNumberGenerator.new()
	looks.seed = int(seed_value) + int(day) * 104729 + int(refresh_index) * 130363 + 48371
	if catalog.empty():
		catalog = [{"avatar": 0, "skins": [1], "fashion": {}}]
	var result = []
	var family = ["林", "陈", "周", "许", "方", "苏", "叶", "顾", "陆", "江", "孟", "唐"]
	var given = ["小满", "青禾", "南星", "知夏", "晓雨", "可可", "阿麦", "小澄", "木木", "小葵", "子宁", "小乔"]
	for _index in range(CANDIDATE_COUNT):
		var person = {"id": "tm_%d_%d_%d_%d" % [int(seed_value), int(day), int(refresh_index), result.size()], "name": family[rng.randi_range(0, family.size()-1)] + given[rng.randi_range(0, given.size()-1)], "role": "employee", "stars": star_from_roll(rng.randi_range(0, 999)), "skill_slots": [], "enabled": true}
		for _slot in range(Catalog.SLOT_COUNT):
			person.skill_slots.append(Catalog.roll_slot(rng, person.skill_slots))
		person.skill_slots = Catalog.stored_slots(person)
		var look = catalog[looks.randi_range(0, catalog.size() - 1)]
		person.avatar = int(look.get("avatar", 0))
		var skins = look.get("skins", [1])
		if not skins is Array or skins.empty():
			skins = [1]
		person.skin = int(skins[looks.randi_range(0, skins.size() - 1)])
		person.fashion = {}
		for part in FASHION_PARTS:
			var options = look.get("fashion", {}).get(part, [0])
			if not options is Array or options.empty():
				options = [0]
			person.fashion[part] = int(options[looks.randi_range(0, options.size() - 1)])
		person.wage = wage(person)
		person.speed = modifiers(person).move_speed
		result.append(person)
	return result

static func valid_person(person):
	if not person is Dictionary or not person.get("id", "") is String or str(person.get("id", "")).empty() or person.get("role", "") != "employee":
		return false
	if int(person.get("stars", 0)) < 1 or int(person.get("stars", 0)) > 6:
		return false
	if not person.get("skill_slots", null) is Array or person.skill_slots.size() != Catalog.SLOT_COUNT:
		return false
	var seen = {}
	for id in person.skill_slots:
		if not Catalog.valid_id(id) or (id != "" and seen.has(id)):
			return false
		if id != "":
			seen[id] = true
	for basic in Catalog.UPGRADED:
		if basic in person.skill_slots and Catalog.UPGRADED[basic] in person.skill_slots:
			return false
	# A signed contract keeps its base wage; Market applies the day's multiplier.
	return int(person.get("wage", 0)) > 0

static func migrate_person(person):
	if not person is Dictionary:
		return {}
	var result = person.duplicate(true)
	var old_role = str(result.get("role", "employee"))
	var old_skills = result.get("skills", {})
	if not old_skills is Dictionary:
		old_skills = {}
	if not result.has("stars"):
		result.stars = int(clamp(int(old_skills.get(old_role, 1)), 1, 5))
	result.stars = int(clamp(int(result.stars), 1, 6))
	if not result.has("skill_slots"):
		var mapping = {"cashier": ["cashier"], "drink": [], "logistics": ["stock_advanced", "trash_advanced", "clean", "repair"], "chef": ["stock_basic"]}
		result.skill_slots = mapping.get(old_role, [])
		if old_role in LEGACY_ROLES:
			result.legacy_role = old_role
			result.legacy_skills = old_skills.duplicate(true)
	result.skill_slots = Catalog.stored_slots(result)
	result.role = "employee"
	# Preserve legacy fields for save compatibility; all behavior uses slots.
	result.enabled = bool(result.get("enabled", true))
	if int(result.get("wage", 0)) <= 0:
		result.wage = wage(result)
	result.speed = modifiers(result).move_speed
	return apply_appearance(result)

static func normalize(data):
	if not data is Dictionary or not int(data.get("version", 0)) in [1, VERSION]:
		return empty_state()
	var result = data.duplicate(true)
	result.version = VERSION
	if str(result.get("run_id", "")).empty():
		result.run_id = empty_state().run_id
	result.day = max(0, int(result.get("day", 0)))
	result.seed = int(result.get("seed", 0))
	result.refresh_index = max(0, int(result.get("refresh_index", 0)))
	var people = []
	var archive = []
	var seen = {}
	var saved_staff = result.get("staff", [])
	if not saved_staff is Array:
		saved_staff = []
	for saved in saved_staff:
		var person = migrate_person(saved)
		if valid_person(person) and not seen.has(person.id):
			seen[person.id] = true
			if people.size() < MAX_STAFF:
				people.append(person)
			else:
				archive.append(person)
	# Overflow is preserved as contracts, never silently fired or automatically
	# promoted. The current shift remains intact, including its locked payroll.
	var saved_archive = result.get("staff_archive", [])
	if not saved_archive is Array:
		saved_archive = []
	for saved in saved_archive:
		var person = migrate_person(saved)
		if valid_person(person) and not seen.has(person.id):
			seen[person.id] = true
			archive.append(person)
	result.staff = people
	result.staff_archive = archive
	var candidates = []
	var saved_candidates = result.get("candidates", [])
	if not saved_candidates is Array:
		saved_candidates = []
	for saved in saved_candidates:
		var person = migrate_person(saved)
		if valid_person(person) and not seen.has(person.id) and candidates.size() < CANDIDATE_COUNT:
			seen[person.id] = true
			candidates.append(person)
	result.candidates = candidates
	return result

static func skill_text(person):
	var text = []
	for id in Catalog.slots(person):
		text.append("空槽" if id.empty() else Catalog.get_skill(id).name)
	return PoolStringArray(text).join("  ·  ")

static func for_day(data, day, catalog = []):
	var result = normalize(data)
	if int(result.day) != int(day):
		result.day = int(day)
		result.refresh_index = 0
		result.candidates = candidates(result.seed, day, catalog, 0)
	return result
