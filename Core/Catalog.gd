extends Reference

static func read():
	var file = File.new()
	if file.open("res://ftc_loader/active_mods.json", File.READ) != OK:
		return {"mods": []}
	var json = JSON.parse(file.get_as_text())
	file.close()
	return json.result if json.error == OK else {"mods": []}

static func apply_levels(config):
	for mod in read().get("mods", []):
		for spec in mod.get("levels", []):
			var data = config.get(spec.get("base", ""), {}).duplicate(true)
			for key in spec.get("values", {}):
				data[key] = spec.values[key]
			config[spec.name] = data
