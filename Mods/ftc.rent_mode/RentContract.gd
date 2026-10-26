extends "res://TscnAndGd/Objects/Home/ChooseShopScroll.gd"

var color_clock = 0.0

func _ready():
	._ready()
	if has_meta("ftc_rent_entry"):
		var title = Label.new()
		title.text = "房租合同"
		title.rect_position = Vector2(-50, -126)
		var font = DynamicFont.new()
		font.font_data = load("res://Language/Fonts/simhei.ttf")
		font.size = 22
		title.add_font_override("font", font)
		title.add_color_override("font_color", Color(1, 1, 1))
		add_child(title)
	else:
		call_deferred("_spawn_rent_entry")

func _spawn_rent_entry():
	if not is_inside_tree() or not filename.ends_with("/ChooseShopScroll.tscn"):
		return
	var parent = get_parent()
	if parent.has_node("FtcRentContract"):
		return
	var other = load(filename).instance()
	other.name = "FtcRentContract"
	other.set_meta("ftc_rent_entry", true)
	parent.add_child(other)
	other.position = position + Vector2(126, 0)

func _process(delta):
	if not has_meta("ftc_rent_entry"):
		return
	color_clock += delta
	var glow = 0.5 + 0.5 * sin(color_clock * 2.1)
	modulate = Color(0.6 + 0.4 * glow, 0.65 + 0.28 * (1.0 - glow), 0.9 + 0.1 * glow)
