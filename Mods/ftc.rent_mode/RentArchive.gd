extends "res://TscnAndGd/Objects/Home/RecordUI.gd"

var rent_mode
var claimed = false
var peak_label
var claim_button

func open_rent(mode, record):
	rent_mode = mode
	_RecordData = record.duplicate(true)
	UIBool = true
	cur_Used = true
	GameLogic.Can_ESC = false
	get_node("Control/ButControl/DelBut").hide()
	get_node("Control/Info/L").hide()
	get_node("Control/Info/R").hide()
	get_node("Control/FileLabel").hide()
	_info_set("")
	# Keep the native archive art, card grid and revenue details. The main
	# coin number is this run's peak instead of the campaign's total revenue.
	get_node("Control/Info/Main/TotalIncome/Coin/Label").text = str(record.ProfitTotal)
	UIANI.play("play")
	_add_peak_label(record.ProfitTotal)
	_add_claim_button()
	if not UIANI.is_connected("animation_finished", self, "_archive_animation_finished"):
		UIANI.connect("animation_finished", self, "_archive_animation_finished")

func _add_peak_label(value):
	var original = get_node("Control/Info/Main/TotalIncome/Coin/Label")
	peak_label = Label.new()
	peak_label.name = "RentPeakCoins"
	peak_label.anchor_left = original.anchor_left
	peak_label.anchor_right = original.anchor_right
	peak_label.anchor_top = original.anchor_top
	peak_label.anchor_bottom = original.anchor_bottom
	peak_label.margin_left = original.margin_left
	peak_label.margin_right = original.margin_right
	peak_label.margin_top = original.margin_top
	peak_label.margin_bottom = original.margin_bottom
	peak_label.align = original.align
	peak_label.valign = original.valign
	peak_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	peak_label.add_font_override("font", original.get_font("font"))
	peak_label.add_color_override("font_color", Color(1, 0.78, 0.04))
	peak_label.add_color_override("font_color_shadow", Color(0, 0, 0))
	peak_label.add_constant_override("shadow_offset_x", 2)
	peak_label.add_constant_override("shadow_offset_y", 2)
	peak_label.text = str(value)
	original.get_parent().add_child(peak_label)

func _add_claim_button():
	claim_button = Button.new()
	claim_button.name = "RentClaimButton"
	claim_button.text = "查看绿钞结算  [Enter / 空格]"
	claim_button.anchor_left = 0.5
	claim_button.anchor_right = 0.5
	claim_button.anchor_top = 1.0
	claim_button.anchor_bottom = 1.0
	claim_button.margin_left = -250
	claim_button.margin_right = 250
	claim_button.margin_top = -70
	claim_button.margin_bottom = -15
	claim_button.focus_mode = Control.FOCUS_NONE
	claim_button.add_font_override("font", rent_mode.font)
	claim_button.connect("pressed", self, "call_closed")
	get_node("Control").add_child(claim_button)

func _archive_animation_finished(_name):
	if is_instance_valid(peak_label):
		peak_label.text = str(_RecordData.ProfitTotal)
		peak_label.show()
	if is_instance_valid(claim_button) and not claimed:
		claim_button.show()

func _on_BackBut_pressed():
	call_closed()

func call_closed():
	if claimed or not is_instance_valid(rent_mode):
		return
	claimed = true
	rent_mode.call_deferred("show_payout")

func _on_DelBut_pressed():
	pass

func _input(event):
	if not cur_Used or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.scancode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		call_closed()
		get_tree().set_input_as_handled()

func close_rent():
	cur_Used = false
	GameLogic.Can_ESC = true
	queue_free()
