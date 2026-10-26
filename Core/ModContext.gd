extends Reference

var host
var manifest
var id

func _init(loader, definition):
	host = loader
	manifest = definition
	id = definition.id

func has_capability(capability):
	return capability in manifest.get("capabilities", [])

func offline():
	return host.offline()

func native_game():
	return host.get_node_or_null("/root/GameLogic")

func player():
	var game = native_game()
	return game.player_1P if game != null and is_instance_valid(game.player_1P) else null

func current_level():
	return host.get_tree().root.get_node_or_null("Level")

func config_path(filename = "settings.cfg"):
	if not has_capability("config") or not host.safe_filename(filename):
		return ""
	var directory = "user://ftc_mods/" + id
	Directory.new().make_dir_recursive(directory)
	return directory + "/" + filename

func save_data(data, filename = "data.json"):
	if not has_capability("save") or not host.safe_filename(filename):
		return false
	var path = config_path(filename)
	if path == "":
		return false
	var file = File.new()
	if file.open(path + ".tmp", File.WRITE) != OK:
		return false
	file.store_string(JSON.print(data))
	file.close()
	return Directory.new().rename(path + ".tmp", path) == OK

func load_data(fallback = {}, filename = "data.json"):
	var path = config_path(filename)
	var file = File.new()
	if path == "" or file.open(path, File.READ) != OK:
		return fallback
	var result = JSON.parse(file.get_as_text())
	file.close()
	return result.result if result.error == OK else fallback

func add_root(name, node):
	if not has_capability("gameplay") and not has_capability("ui"):
		return null
	return host.add_owned_root(id, name, node)

func provide_service(name, object):
	return host.provide_service(id + ":" + name, object)

func service(mod_id, name):
	return host.services.get(mod_id + ":" + name)

func subscribe(event, target, method):
	return host.subscribe(id, event, target, method)

func publish(event, data = {}):
	host.publish(id + ":" + event, data)

func set_game_speed(factor):
	if has_capability("gameplay"):
		host.time_factors[id] = clamp(float(factor), 0.1, 8.0)

func set_movement_multiplier(factor):
	if has_capability("gameplay"):
		host.movement_factors[id] = clamp(float(factor), 0.1, 8.0)

func register_movement_provider(target, method):
	if has_capability("gameplay"):
		host.movement_providers.append({"owner": id, "target": weakref(target), "method": method})

func register_control_hook(target, method, priority = 0, network = false):
	if has_capability("input"):
		host.control_hooks.append({"owner": id, "target": weakref(target), "method": method, "priority": priority, "network": network})
		host.control_hooks.sort_custom(host, "_hook_order")

func recipe(name):
	return native_game().Config.FormulaConfig.get(name, {}).duplicate(true)

func register_recipe(name, base_recipe, values):
	if not has_capability("recipes"):
		return false
	return host.register_recipe(id, name, base_recipe, values)

func register_level(name, base_level, values):
	if not has_capability("levels"):
		return false
	return host.register_level(id, name, base_level, values)

func add_money(amount):
	if not has_capability("gameplay") or not offline():
		return false
	var game = native_game()
	game.call_MoneyChange(int(amount), game.HomeMoneyKey)
	return true

func log(message):
	host.log_line(id, str(message))
