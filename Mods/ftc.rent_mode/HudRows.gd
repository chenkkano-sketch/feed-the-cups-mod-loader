extends VBoxContainer

const ICONS = "res://Resources/UI/GameUI/ui_pack.sprites/"
var rent_label
var lost_label
var rent_row
var lost_row

func _init(native_money):
	name = "RentHUD"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_constant_override("separation", 0)
	var digits = native_money.get_font("font").duplicate()
	if digits is DynamicFont:
		digits.outline_size = 4
		digits.outline_color = Color.black
	rent_row = _row(digits, "Ui_icon_coin.tres")
	rent_label = rent_row.get_child(0)
	lost_row = _row(digits, "Icon_moodstar_3.tres")
	lost_label = lost_row.get_child(0)
	update_values(150, 0, 3)

func _row(digits, icon_path):
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGN_END
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_constant_override("separation", 6)
	add_child(row)
	var label = Label.new()
	label.align = Label.ALIGN_RIGHT
	label.valign = Label.VALIGN_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_font_override("font", digits)
	label.add_color_override("font_color", Color(1, 0.08, 0.08))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var icon = TextureRect.new()
	icon.texture = load(ICONS + icon_path)
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.rect_min_size = Vector2(34, 48)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	return row

func update_values(rent, lost, limit):
	rent_label.text = "-%d" % rent if rent > 0 else "0"
	rent_row.hint_tooltip = "今日房租：%d 杯币" % rent
	lost_label.text = "%d/%d" % [lost, limit]
	lost_row.hint_tooltip = "今日流失顾客：%d/%d" % [lost, limit]
