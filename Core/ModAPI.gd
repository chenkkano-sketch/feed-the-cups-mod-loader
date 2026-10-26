extends Node

const API_VERSION = "1.0"
const Context = preload("res://ftc_loader/ModContext.gd")
var loaded = {}
var failed = {}
var services = {}
var owned_roots = {}
var subscribers = {}
var time_factors = {}
var movement_factors = {}
var movement_providers = []
var control_hooks = []
var recipes = {}
var levels = {}
var scale_owned = false
var base_scale = 1.0
var last_level = null
var watch_at = 0
var initialized = false

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	for binding in [["DayStart", "day_start"], ["NewDay", "new_day"], ["OpenStore", "store_opened"], ["CallFormula", "menu_changed"], ["RewardUI", "reward_opened"]]:
		var game = get_node("/root/GameLogic")
		if game.has_signal(binding[0]):
			game.connect(binding[0], self, "_game_event", [binding[1]])
	call_deferred("_load_mods")

func _load_mods():
	for definition in preload("res://ftc_loader/Catalog.gd").read().get("mods", []):
		var dependency_failed = false
		for dependency in definition.get("dependencies", {}):
			if not loaded.has(dependency):
				dependency_failed = true
		if dependency_failed:
			failed[definition.id] = "dependency failed"
			continue
		var script = load(definition.entry)
		if script == null or not script.can_instance():
			failed[definition.id] = "invalid entry"
			log_line(definition.id, "ERROR: entry could not be loaded")
			continue
		var instance = script.new()
		var context = Context.new(self, definition)
		if not instance.has_method("on_load") or instance.on_load(context) != true:
			failed[definition.id] = "on_load failed"
			_cleanup(definition.id)
			log_line(definition.id, "ERROR: on_load did not succeed")
			continue
		loaded[definition.id] = {"instance": instance, "context": context, "manifest": definition}
		log_line(definition.id, "loaded " + definition.version)
	initialized = true
	publish("loader_ready", {"mods": loaded.keys(), "failed": failed.keys()})
	if not failed.empty():
		OS.alert("以下 Mod 未成功加载：\n" + PoolStringArray(failed.keys()).join("\n") + "\n详情见 FTCModLoader/Logs/runtime.log。", "杯杯倒满 Mod 加载器")

func offline():
	var sdk = get_node_or_null("/root/SdkManager")
	return sdk != null and sdk.get("is_multiplay") == false and int(sdk.get("lobby_player_num")) <= 1

func safe_filename(name):
	var pattern = RegEx.new()
	pattern.compile("^[A-Za-z0-9][A-Za-z0-9_.-]{0,100}$")
	var stem = name.split(".")[0].to_upper()
	return pattern.search(name) != null and not name.ends_with(".") and not stem in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]

func add_owned_root(owner, name, node):
	if not safe_filename(name) or get_tree().root.has_node(name):
		return null
	node.name = name
	if not owned_roots.has(owner):
		owned_roots[owner] = []
	owned_roots[owner].append(weakref(node))
	get_tree().root.add_child(node)
	return node

func provide_service(key, object):
	if services.has(key):
		return false
	services[key] = object
	return true

func subscribe(owner, event, target, method):
	if not target.has_method(method):
		return false
	if not subscribers.has(event):
		subscribers[event] = []
	subscribers[event].append({"owner": owner, "target": weakref(target), "method": method})
	return true

func publish(event, data = {}):
	for subscription in subscribers.get(event, []).duplicate():
		var target = subscription.target.get_ref()
		if is_instance_valid(target):
			target.call(subscription.method, data)

func _game_event(event):
	publish(event, {})

func _hook_order(a, b):
	return int(a.priority) > int(b.priority)

func consume_control(actor, button, value, type):
	for hook in control_hooks:
		if not offline() and not hook.get("network", false):
			continue
		var target = hook.target.get_ref()
		if is_instance_valid(target) and target.call(hook.method, actor, button, value, type) == true:
			return true
	return false

func movement_factor(actor):
	if not offline() or actor != get_node("/root/GameLogic").player_1P:
		return 1.0
	var factor = 1.0
	for value in movement_factors.values():
		factor *= value
	for provider in movement_providers:
		var target = provider.target.get_ref()
		if is_instance_valid(target):
			factor *= float(target.call(provider.method, actor))
	return clamp(factor, 0.01, 64.0)

func _process(_delta):
	var factor = 1.0
	if offline():
		for value in time_factors.values():
			factor *= value
	if not is_equal_approx(factor, 1.0):
		if not scale_owned:
			base_scale = Engine.time_scale
			scale_owned = true
		Engine.time_scale = base_scale * clamp(factor, 0.1, 8.0)
	elif scale_owned:
		Engine.time_scale = base_scale
		scale_owned = false
	if OS.get_ticks_msec() >= watch_at:
		watch_at = OS.get_ticks_msec() + 250
		var level = get_tree().root.get_node_or_null("Level")
		if level != last_level:
			last_level = level
			publish("scene_loaded", {"node": level, "level": get_node("/root/GameLogic").cur_level})

func register_recipe(owner, name, base, values):
	var config = get_node("/root/GameLogic").Config.FormulaConfig
	if not name.begins_with(owner + ".") or not config.has(base) or config.has(name) or recipes.has(name):
		return false
	recipes[name] = {"owner": owner, "base": base, "values": values.duplicate(true)}
	apply_recipes(config)
	return true

func apply_recipes(config):
	for name in recipes:
		var spec = recipes[name]
		if config.has(spec.base):
			var data = config[spec.base].duplicate(true)
			for key in spec.values:
				data[key] = spec.values[key]
			config[name] = data

func register_level(owner, name, base, values):
	var config = get_node("/root/GameLogic").Config.SceneConfig
	if not name.begins_with(owner + ".") or config.has(name) or levels.has(name) or not config.has(base):
		return false
	levels[name] = {"owner": owner, "base": base, "values": values.duplicate(true)}
	apply_levels(config)
	return true

func apply_levels(config):
	for name in levels:
		var spec = levels[name]
		if config.has(spec.base):
			var data = config[spec.base].duplicate(true)
			for key in spec.values:
				data[key] = spec.values[key]
			config[name] = data

func _cleanup(owner):
	time_factors.erase(owner)
	movement_factors.erase(owner)
	for collection in [control_hooks, movement_providers]:
		for item in collection.duplicate():
			if item.owner == owner:
				collection.erase(item)
	for event in subscribers:
		for item in subscribers[event].duplicate():
			if item.owner == owner:
				subscribers[event].erase(item)
	for key in services.keys():
		if key.begins_with(owner + ":"):
			services.erase(key)
	for reference in owned_roots.get(owner, []):
		var node = reference.get_ref()
		if is_instance_valid(node):
			node.queue_free()
	owned_roots.erase(owner)
	for catalog in [recipes, levels]:
		for key in catalog.keys():
			if catalog[key].owner == owner:
				catalog.erase(key)

func log_line(owner, message):
	var directory = OS.get_executable_path().get_base_dir().plus_file("FTCModLoader/Logs")
	Directory.new().make_dir_recursive(directory)
	var path = directory.plus_file("runtime.log")
	var file = File.new()
	if file.open(path, File.READ_WRITE if file.file_exists(path) else File.WRITE) == OK:
		file.seek_end()
		file.store_line("[%s] %s" % [owner, message])
		file.close()
	print("[FTC ModLoader] ", owner, ": ", message)

func _exit_tree():
	for id in loaded:
		var instance = loaded[id].instance
		if instance.has_method("on_unload"):
			instance.on_unload()
	if scale_owned:
		Engine.time_scale = base_scale
