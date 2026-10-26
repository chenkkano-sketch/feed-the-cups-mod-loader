extends TextureButton

var active = false

func _init():
	name = "CarryIcon"
	texture_normal = load("res://Resources/UI/GameUI/ui_pack.sprites/Icon_fuction_13.tres")
	expand = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	rect_min_size = Vector2(68, 68)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	focus_mode = Control.FOCUS_NONE
	hint_tooltip = "搬运模式 [F2]：点击或按 F2 开关"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_active(false)

func set_active(value):
	active = value
	hint_tooltip = "搬运模式：已开启 [F2]，交互可拿起、放下或交换" if value else "搬运模式：已关闭 [F2]，点击开启"
	update()

func _draw():
	if not active:
		return
	draw_circle(Vector2(54, 53), 14, Color.black)
	draw_circle(Vector2(54, 53), 11, Color(0.2, 0.8, 0.2))
	var tick = PoolVector2Array([Vector2(47, 53), Vector2(52, 58), Vector2(62, 47)])
	draw_polyline(tick, Color.black, 6, true)
	draw_polyline(tick, Color.white, 3, true)
