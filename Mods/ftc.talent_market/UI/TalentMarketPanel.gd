extends CanvasLayer

const Rules = preload("res://ftc_mods/ftc.talent_market/TalentRules.gd")
const Catalog = preload("res://ftc_mods/ftc.talent_market/Skills/SkillCatalog.gd")
const INK = Color(0.23, 0.14, 0.075)
const MUTED = Color(0.48, 0.38, 0.25)
const PAPER = Color(1.0, 0.963, 0.84)
const LEAF = Color(0.30, 0.53, 0.22)
const SKILL_ICONS = {"stock_basic": 4, "stock_advanced": 4, "trash_basic": 5, "trash_advanced": 5, "godspeed": 6, "athlete": 6, "agile": 6, "clumsy": 7, "slacking_addiction": 7, "slow_tempered": 7, "cashier": 8, "cashier_advanced": 8, "restock_cups": 11, "clean": 12, "repair": 13, "corporate_drone": 14, "craftsmanship": 14, "diligent": 14, "workaholic": 14, "aura": 15, "aura_plus": 15}

class RainbowBorder:
	extends Control
	var clock = 0.0
	var pending = 0.0
	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta):
		if not is_visible_in_tree():
			return
		clock += delta * 0.12
		pending += delta
		if pending >= 0.06:
			pending = 0.0
			update()
	func _draw():
		if rect_size.x < 40 or rect_size.y < 40:
			return
		# The paper already supplies its watercolor border. Only a few small
		# glints travel along that uneven edge; never draw a geometric frame.
		var edge = [Vector2(22, 16), Vector2(rect_size.x - 22, 16), Vector2(rect_size.x - 9, 30), Vector2(rect_size.x - 9, rect_size.y - 22), rect_size - Vector2(22, 9), Vector2(22, rect_size.y - 9), Vector2(9, rect_size.y - 22), Vector2(9, 30)]
		var palette = [Color(1.0, 0.58, 0.65), Color(1.0, 0.85, 0.40), Color(0.58, 0.91, 0.57), Color(0.48, 0.86, 0.98), Color(0.65, 0.61, 1.0), Color(0.97, 0.58, 0.92)]
		for index in range(4):
			var along = fmod(clock * 0.30 + float(index) / 4.0, 1.0) * 8.0
			var first = int(along)
			var point = edge[first].linear_interpolate(edge[(first + 1) % 8], along - first)
			var color = palette[(index * 2) % 6]
			color.a = 0.35 + 0.5 * (0.5 + 0.5 * sin(clock * 9.0 + float(index) * 1.7))
			var glow = color
			glow.a *= 0.15
			draw_circle(point, 6.0, glow)
			draw_circle(point, 1.6, color)
			if index % 2 == 0:
				draw_line(point - Vector2(0, 4), point + Vector2(0, 4), color, 1.2, true)
				draw_line(point - Vector2(3, 0), point + Vector2(3, 0), color, 1.2, true)

var market
var portraits
var panel
var entry_button
var tabs
var candidate_list
var staff_list
var summary
var summary_paper
var info_panel
var day_label
var money_label
# Native image 1898x829, measured dark-outline icon bounds after the complete
# texture is aspect-fitted into 330x145. Text uses the adjacent column.
var day_icon_center = Vector2(62.5053, 48.6802)
var money_icon_center = Vector2(61.4621, 96.5806)
var message
var description
var refresh_button
var refresh_hint
var debug_switch
var debug_overlay
var debug_title
var debug_stars
var debug_slots = []
var debug_ids = []
var debug_person_id = ""
var debug_feedback
var font
var fonts = {}
var progress_rows = {}
var board_texture
var art = preload("res://ftc_mods/ftc.talent_market/UI/ArtAtlas.gd").new()

func _init(owner = null, factory = null):
	market = owner
	portraits = factory

func _ready():
	layer = 155
	pause_mode = Node.PAUSE_MODE_PROCESS
	_build()

func _font(size):
	if not fonts.has(size):
		var value = DynamicFont.new()
		value.font_data = load("res://Language/Fonts/simhei.ttf")
		value.size = size
		fonts[size] = value
	return fonts[size]

func _style(fill, border, width = 2, margin = 10):
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 8
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	style.shadow_color = Color(0.19, 0.11, 0.04, 0.21)
	style.shadow_size = 3
	style.shadow_offset = Vector2(1, 3)
	return style

func _label(text, parent, size = 20, color = INK):
	var label = Label.new()
	label.text = text
	label.add_font_override("font", _font(size))
	label.add_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(text, parent, method, binds = [], green = true):
	var button = Button.new()
	button.text = text
	button.add_font_override("font", _font(22))
	var fill = LEAF if green else Color(0.71, 0.54, 0.35)
	button.add_stylebox_override("normal", _style(fill, Color(0.22, 0.32, 0.10) if green else INK, 2, 7))
	button.add_stylebox_override("hover", _style(fill.lightened(0.12), Color(0.35, 0.39, 0.12), 2, 7))
	button.add_stylebox_override("pressed", _style(fill.darkened(0.13), INK, 2, 7))
	button.add_stylebox_override("disabled", _style(Color(0.72, 0.70, 0.57), Color(0.54, 0.48, 0.35), 1, 7))
	var normal = art.cell("widgets.png", 2, 4, 0, 0 if green else 1, true, 64)
	var pressed = art.cell("widgets.png", 2, 4, 1 if green else 0, 0 if green else 1, true, 64)
	var disabled = art.cell("widgets.png", 2, 4, 1, 1, true, 64)
	if normal != null:
		button.add_stylebox_override("normal", art.style(normal, 18.0, 7.0))
		var hover = art.style(normal, 18.0, 7.0)
		hover.modulate_color = Color(1.10, 1.08, 0.98)
		button.add_stylebox_override("hover", hover)
		button.add_stylebox_override("pressed", art.style(pressed if pressed != null else normal, 18.0, 7.0))
	if disabled != null:
		button.add_stylebox_override("disabled", art.style(disabled, 18.0, 7.0))
	button.add_color_override("font_color", PAPER)
	button.add_color_override("font_color_hover", Color(1, 1, 0.93))
	button.add_color_override("font_color_disabled", Color(0.46, 0.43, 0.34))
	button.rect_min_size.y = 40
	button.connect("pressed", market, method, binds)
	parent.add_child(button)
	return button

func _icon(index, dimensions):
	return art.icon(art.cell("icons.png", 4, 4, index % 4, int(index / 4), true, 64), dimensions)

func _paper(parent, position, dimensions, column, row):
	var texture = art.cell("widgets.png", 2, 4, column, row, true, 72)
	if texture == null:
		return null
	var paper = Panel.new()
	paper.rect_position = position
	paper.rect_size = dimensions
	paper.add_stylebox_override("panel", art.style(texture, 22.0, 0.0))
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(paper)
	return paper

func _build():
	font = _font(20)
	entry_button = _button("人才市场 [F3]", self, "open_market")
	entry_button.rect_position = Vector2(1490, 890)
	entry_button.rect_size = Vector2(260, 42)
	entry_button.hide()
	panel = Control.new()
	panel.name = "TalentBoard"
	panel.rect_position = Vector2(80, 32)
	panel.rect_size = Vector2(1760, 1016)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var shade = ColorRect.new()
	shade.color = Color(0.07, 0.09, 0.035, 0.40)
	shade.rect_position = Vector2(-80, -32)
	shade.rect_size = Vector2(1920, 1080)
	panel.add_child(shade)
	var image = Image.new()
	if image.load("res://ftc_mods/ftc.talent_market/UI/Assets/market-board-v2.png") == OK:
		board_texture = ImageTexture.new()
		board_texture.create_from_image(image, Texture.FLAG_FILTER)
		var board = TextureRect.new()
		board.texture = board_texture
		board.expand = true
		board.stretch_mode = TextureRect.STRETCH_SCALE
		board.rect_size = panel.rect_size
		board.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(board)
	else:
		var board = Panel.new()
		board.rect_size = panel.rect_size
		board.add_stylebox_override("panel", _style(Color(0.96, 0.88, 0.68), Color(0.43, 0.24, 0.09), 16, 0))
		panel.add_child(board)
	# Keep each region on the corresponding part of the illustrated board:
	# heading on the upper timber, cards on wood, footer on the cream strip.
	var heading = Control.new()
	heading.rect_position = Vector2(100, 36)
	heading.rect_size = Vector2(1560, 170)
	panel.add_child(heading)
	_paper(heading, Vector2(560, 0), Vector2(440, 84), 0, 2)
	var title = _label("人才市场", heading, 36)
	title.rect_position = Vector2(560, 20)
	title.rect_size = Vector2(440, 48)
	title.align = Label.ALIGN_CENTER
	_build_info_card(heading)
	tabs = TabContainer.new()
	tabs.rect_position = Vector2(100, 150)
	tabs.rect_size = Vector2(1560, 672)
	tabs.tab_align = 0
	tabs.add_font_override("font", _font(23))
	tabs.add_color_override("font_color_fg", INK)
	tabs.add_color_override("font_color_bg", MUTED)
	tabs.add_stylebox_override("tab_fg", _style(Color(1.0, 0.96, 0.77), Color(0.57, 0.38, 0.15), 2, 10))
	tabs.add_stylebox_override("tab_bg", _style(Color(0.77, 0.70, 0.55), Color(0.57, 0.45, 0.29), 1, 10))
	var tab_paper = art.cell("widgets.png", 2, 4, 1, 2, true, 64)
	if tab_paper != null:
		var selected = art.style(tab_paper, 18.0, 10.0)
		selected.content_margin_top = 14
		tabs.add_stylebox_override("tab_fg", selected)
		var resting = selected.duplicate()
		resting.modulate_color = Color(0.80, 0.78, 0.65)
		tabs.add_stylebox_override("tab_bg", resting)
	var tab_body = StyleBoxEmpty.new()
	tab_body.content_margin_left = 4
	tab_body.content_margin_right = 4
	tab_body.content_margin_top = 4
	tab_body.content_margin_bottom = 4
	tabs.add_stylebox_override("panel", tab_body)
	panel.add_child(tabs)
	candidate_list = _grid("今日人才", 5)
	staff_list = _grid("已聘店员", 4)
	tabs.connect("tab_changed", self, "_tab_changed")
	var footer = HBoxContainer.new()
	footer.rect_position = Vector2(100, 868)
	footer.rect_size = Vector2(1560, 100)
	footer.add_constant_override("separation", 20)
	panel.add_child(footer)
	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(info)
	description = _label("全部现存技能已开放；不同速度被动与减益可并存。", info, 19)
	description.autowrap = true
	description.rect_min_size = Vector2(760, 45)
	var legend = HBoxContainer.new()
	legend.add_constant_override("separation", 18)
	info.add_child(legend)
	for star in range(1, 7):
		var mark = HBoxContainer.new()
		mark.add_constant_override("separation", 3)
		legend.add_child(mark)
		mark.add_child(_icon(3 if star == 6 else 0, Vector2(18, 18)))
		_label(str(star) + "星" + Rules.star_color_name(star), mark, 16, INK if star == 1 else Rules.star_color(star).darkened(0.25))
	var actions = VBoxContainer.new()
	actions.add_constant_override("separation", 4)
	footer.add_child(actions)
	var action_row = HBoxContainer.new()
	action_row.add_constant_override("separation", 12)
	actions.add_child(action_row)
	refresh_button = _button("刷新人才 · 100 元", action_row, "refresh_candidates")
	refresh_button.rect_min_size = Vector2(270, 46)
	var close_button = _button("关闭 [F3]", action_row, "close_market", [], false)
	close_button.rect_min_size = Vector2(150, 46)
	refresh_hint = _label("下次 200 元", actions, 16, MUTED)
	refresh_hint.align = Label.ALIGN_CENTER
	debug_switch = CheckBox.new()
	debug_switch.text = "调试模式"
	debug_switch.add_font_override("font", _font(19))
	debug_switch.add_color_override("font_color", INK)
	debug_switch.connect("toggled", market, "set_debug_mode")
	action_row.add_child(debug_switch)
	message = description
	_build_debug_editor()
	panel.hide()

func _build_debug_editor():
	debug_overlay = ColorRect.new()
	debug_overlay.name = "EmployeeDebugEditor"
	debug_overlay.color = Color(0, 0, 0, 0.68)
	debug_overlay.rect_size = panel.rect_size
	debug_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(debug_overlay)
	var paper = PanelContainer.new()
	paper.rect_position = Vector2(440, 140)
	paper.rect_min_size = Vector2(880, 600)
	paper.add_stylebox_override("panel", _style(PAPER, Color(0.48, 0.32, 0.13), 3, 26))
	debug_overlay.add_child(paper)
	var content = VBoxContainer.new()
	content.add_constant_override("separation", 18)
	paper.add_child(content)
	debug_title = _label("员工调试", content, 30)
	var help = _label("自由修改4个技能槽与星级，重复技能不可选，同系高级自动替换低级。\n全部现存技能已开放，速度被动与减益可并存叠加。", content, 20)
	help.autowrap = true
	help.rect_min_size.y = 65
	var star_row = HBoxContainer.new()
	content.add_child(star_row)
	_label("星级", star_row, 23)
	debug_stars = SpinBox.new()
	debug_stars.min_value = 1
	debug_stars.max_value = 6
	debug_stars.step = 1
	debug_stars.rect_min_size = Vector2(180, 46)
	debug_stars.get_line_edit().add_font_override("font", _font(23))
	star_row.add_child(debug_stars)
	debug_ids = [""] + Catalog.DEFINITIONS.keys()
	for index in range(4):
		var row = HBoxContainer.new()
		content.add_child(row)
		_label("技能槽 %d" % (index + 1), row, 22)
		var select = OptionButton.new()
		select.rect_min_size = Vector2(650, 46)
		select.add_font_override("font", _font(22))
		for id in debug_ids:
			select.add_item("空技能槽" if id == "" else Catalog.get_skill(id).name)
		select.connect("item_selected", self, "_debug_selection_changed")
		row.add_child(select)
		debug_slots.append(select)
	debug_feedback = _label("", content, 19)
	debug_feedback.autowrap = true
	debug_feedback.rect_min_size.y = 46
	var buttons = HBoxContainer.new()
	content.add_child(buttons)
	_button("应用并保存", buttons, "apply_debug_editor")
	_button("取消", buttons, "close_debug_editor", [], false)
	debug_overlay.hide()

func open_debug_editor(id):
	if not market.debug_mode or not market.panel.visible or not market.is_run():
		return false
	for person in market.state.staff:
		if str(person.id) != str(id):
			continue
		debug_person_id = str(id)
		debug_title.text = "调试员工 · " + person.name
		debug_stars.value = person.stars
		var selected = Catalog.stored_slots(person)
		for index in range(4):
			debug_slots[index].select(debug_ids.find(selected[index]))
		debug_feedback.text = "修改后即时生效；原合同工资、外观和已记工资保留。"
		_debug_selection_changed(0)
		debug_overlay.show()
		return true
	return false

func _debug_selection_changed(_item):
	var chosen = []
	for select in debug_slots:
		chosen.append(debug_ids[select.selected])
	for basic in Catalog.UPGRADED:
		if basic in chosen and Catalog.UPGRADED[basic] in chosen:
			debug_slots[chosen.find(basic)].select(0)
	for select in debug_slots:
		var others = []
		for other in debug_slots:
			if other != select:
				others.append(debug_ids[other.selected])
		for index in range(debug_ids.size()):
			var id = debug_ids[index]
			select.set_item_disabled(index, id != "" and (id in others or (Catalog.UPGRADED.has(id) and Catalog.UPGRADED[id] in others)))

func close_debug_editor():
	if is_instance_valid(debug_overlay):
		debug_overlay.hide()
	debug_person_id = ""

func apply_debug_editor():
	var selected = []
	for select in debug_slots:
		selected.append(debug_ids[select.selected])
	if market.debug_edit_employee(debug_person_id, int(debug_stars.value), selected):
		close_debug_editor()
	else:
		debug_feedback.text = market.message.text

func _build_info_card(heading):
	info_panel = Control.new()
	info_panel.name = "MarketInfoCard"
	info_panel.rect_position = Vector2(1210, -12)
	info_panel.rect_size = Vector2(330, 145)
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(info_panel)
	var texture = art.sheet("info-plaque.png")
	if texture != null:
		var background = TextureRect.new()
		background.texture = texture
		background.expand = true
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		background.rect_size = info_panel.rect_size
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_panel.add_child(background)
	else:
		var background = Panel.new()
		background.rect_size = info_panel.rect_size
		background.add_stylebox_override("panel", _style(PAPER, MUTED, 2, 16))
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_panel.add_child(background)
	day_label = _label("", info_panel, 26)
	day_label.valign = Label.VALIGN_CENTER
	day_label.rect_position = Vector2(103, day_icon_center.y - 18.0)
	day_label.rect_size = Vector2(164, 36)
	money_label = _label("", info_panel, 28)
	money_label.valign = Label.VALIGN_CENTER
	money_label.rect_position = Vector2(103, money_icon_center.y - 19.5)
	money_label.rect_size = Vector2(164, 39)
	# Keep older integrations' public references while the card exposes its two
	# independent live fields for layout and balance checks.
	summary_paper = info_panel
	summary = money_label

func _grid(title, columns):
	var scroll = ScrollContainer.new()
	scroll.name = title
	tabs.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = columns
	grid.add_constant_override("hseparation", 12)
	grid.add_constant_override("vseparation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	return grid

func _stars(person, parent, size = 22):
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGN_CENTER
	row.add_constant_override("separation", 2)
	parent.add_child(row)
	for index in range(6):
		var icon_id = (3 if int(person.stars) == 6 and index == 5 else 0) if index < int(person.stars) else 1
		row.add_child(_icon(icon_id, Vector2(size, size)))
	return row

func _skill(id, parent, compact = false):
	var info = Catalog.get_skill(id)
	var slot = PanelContainer.new()
	slot.name = "SkillSlot"
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.set_meta("skill_id", id)
	slot.rect_min_size.y = 35 if compact else 36
	var tint = Color(0.94, 0.91, 0.80)
	if not info.empty():
		tint = Color(0.87, 0.94, 0.77) if info.kind == "active" else (Color(0.99, 0.83, 0.78) if info.kind == "debuff" else Color(0.83, 0.91, 0.98))
	slot.add_stylebox_override("panel", _style(tint, Color(0.73, 0.63, 0.43), 1, 5))
	var background = art.cell("widgets.png", 2, 4, 1 if info.empty() else 0, 3, true, 64)
	if background != null:
		slot.add_stylebox_override("panel", art.style(background, 13.0, 5.0))
	parent.add_child(slot)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 5)
	slot.add_child(row)
	if info.empty():
		var empty = _label("－ 空技能槽 －", row, 16 if compact else 18, MUTED)
		empty.align = Label.ALIGN_CENTER
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		row.add_child(_icon(int(SKILL_ICONS.get(id, 14)), Vector2(20, 20) if compact else Vector2(28, 28)))
		var title = str(info.name)
		var label = _label(title, row, 15 if compact else 18)
		label.clip_text = true
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var kind = "主动" if info.kind == "active" else "被动"
		_label(kind, row, 12 if compact else 15, Color(0.24, 0.43, 0.16) if info.kind == "active" else (Color(0.65, 0.25, 0.20) if info.kind == "debuff" else Color(0.21, 0.38, 0.60)))
		slot.hint_tooltip = title + " · " + kind + "\n" + str(info.description)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.connect("mouse_entered", self, "_describe", [id])
		for child in row.get_children():
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot

func _describe(id):
	var info = Catalog.get_skill(id)
	if not info.empty():
		description.text = str(info.name) + "：" + str(info.description)

func _card(person, hired):
	var card = PanelContainer.new()
	card.name = "EmployeeCard"
	card.set_meta("person_id", person.id)
	card.set_meta("stars", person.stars)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.rect_min_size = Vector2(372, 288) if hired else Vector2(294, 600)
	var border = Rules.star_color(person.stars)
	card.add_stylebox_override("panel", _style(PAPER.linear_interpolate(border, 0.07), border, 3, 14))
	var rarity = int(clamp(int(person.stars), 1, 6)) - 1
	var paper = art.cell("employee-cards.png", 3, 2, rarity % 3, int(rarity / 3), true)
	if paper != null:
		var paper_style = art.style(paper, 42.0, 18.0)
		paper_style.content_margin_top = 32
		paper_style.content_margin_bottom = 16
		card.add_stylebox_override("panel", paper_style)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 5)
	card.add_child(box)
	if hired:
		var header = HBoxContainer.new()
		header.add_constant_override("separation", 8)
		box.add_child(header)
		header.add_child(portraits._portrait(person, Vector2(88, 88)))
		var details = VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(details)
		_label(person.name, details, 22)
		_stars(person, details, 18)
		_salary(person, details, 18)
	else:
		_label(person.name, box, 24).align = Label.ALIGN_CENTER
		box.add_child(portraits._portrait(person, Vector2(250, 228)))
		_stars(person, box, 23)
		_salary(person, box, 20)
	var skills = GridContainer.new()
	skills.name = "SkillSlots"
	skills.columns = 2 if hired else 1
	skills.add_constant_override("hseparation", 6)
	skills.add_constant_override("vseparation", 5)
	box.add_child(skills)
	for id in _display_slots(person):
		_skill(id, skills, hired)
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	if hired:
		var progress = ProgressBar.new()
		progress.rect_min_size.y = 17
		progress.percent_visible = false
		progress.add_stylebox_override("bg", _style(Color(0.80, 0.75, 0.60), Color(0.60, 0.51, 0.34), 1, 0))
		progress.add_stylebox_override("fg", _style(Color(0.40, 0.67, 0.28), Color(0.30, 0.46, 0.20), 0, 0))
		box.add_child(progress)
		progress_rows[str(person.id)] = progress
		var controls = HBoxContainer.new()
		controls.add_constant_override("separation", 12)
		box.add_child(controls)
		var duty = CheckBox.new()
		duty.text = "今日出勤"
		duty.pressed = bool(person.get("enabled", true))
		duty.disabled = not market.can_manage()
		duty.add_font_override("font", _font(19))
		duty.add_color_override("font_color", INK)
		duty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		duty.connect("toggled", market, "set_duty", [person.id])
		controls.add_child(duty)
		var severance = market.daily_wage(person)
		var dismiss = _button("遣散 · %d元" % severance, controls, "fire", [person.id], false)
		dismiss.disabled = not market.can_manage() or int(market.game.cur_money) < severance
		dismiss.hint_tooltip = "支付离职金 %d 元后解除合同，金额为当日一整天日薪。" % severance
		if market.debug_mode:
			_button("调试技能 / 星级", box, "open_debug_editor", [person.id], false)
	else:
		_button("聘  用", box, "hire", [person.id]).disabled = not market.can_manage() or market.state.staff.size() >= Rules.MAX_STAFF or int(market.game.cur_money) < market.daily_wage(person)
	if int(person.stars) == 6:
		var rainbow = RainbowBorder.new()
		var overlay = Node2D.new()
		card.add_child(overlay)
		overlay.add_child(rainbow)
		card.connect("resized", self, "_resize_rainbow", [card, rainbow])
		_resize_rainbow(card, rainbow)
	var tween = Tween.new()
	card.add_child(tween)
	card.connect("mouse_entered", self, "_hover", [card, tween, true])
	card.connect("mouse_exited", self, "_hover", [card, tween, false])
	return card

func _display_slots(person):
	# Sort presentation only. Independently rolled slots retain their original
	# order in the contract, save data and scheduler.
	var ordered = []
	for id in Catalog.slots(person):
		if not str(id).empty():
			ordered.append(id)
	while ordered.size() < Catalog.SLOT_COUNT:
		ordered.append("")
	return ordered

func _salary(person, parent, size, compact = false):
	var salary = HBoxContainer.new()
	salary.alignment = BoxContainer.ALIGN_CENTER
	salary.add_constant_override("separation", 5)
	parent.add_child(salary)
	salary.add_child(_icon(2, Vector2(size, size)))
	var wage = market.daily_wage(person)
	_label("%d元/天" % wage if compact else "日薪 %d 元" % wage, salary, size, MUTED)
	salary.hint_tooltip = "今日日薪 %d 元，合同基薪 %d 元。工资随基础房租曲线上涨；开店时锁定当日金额。" % [wage, int(person.wage)]

func _resize_rainbow(card, rainbow):
	rainbow.rect_size = card.rect_size

func _hover(card, tween, entered):
	tween.stop_all()
	card.rect_pivot_offset = card.rect_size * 0.5
	tween.interpolate_property(card, "rect_rotation", card.rect_rotation, -0.35 if entered else 0.0, 0.16, Tween.TRANS_SINE, Tween.EASE_OUT)
	tween.start()

func render():
	debug_switch.set_pressed_no_signal(market.debug_mode)
	progress_rows.clear()
	for list_node in [candidate_list, staff_list]:
		for child in list_node.get_children():
			list_node.remove_child(child)
			child.queue_free()
	for person in market.state.get("candidates", []):
		candidate_list.add_child(_card(person, false))
	for person in market.state.get("staff", []):
		staff_list.add_child(_card(person, true))
	if market.state.get("staff", []).empty():
		_label("还没有店员。先从今日人才中挑选一位搭档。", staff_list, 24, MUTED)
	update_summary()

func update_summary():
	day_label.text = "第 %d 天" % int(market.game.cur_Day)
	money_label.text = str(int(market.game.cur_money))
	tabs.set_tab_title(1, "已聘店员 %d/%d" % [market.state.get("staff", []).size(), Rules.MAX_STAFF])
	var index = int(market.state.get("refresh_index", 0))
	var price = Rules.refresh_cost(index)
	refresh_button.text = "刷新人才 · %d 元" % price
	refresh_button.disabled = not market.can_manage() or int(market.game.cur_money) < price
	refresh_hint.text = "下次 %d 元 · 每日重置" % Rules.refresh_cost(index + 1)
	refresh_button.hint_tooltip = "花费 %d 元，替换当前候选人。已聘店员保留；下次刷新费用 %d 元。" % [price, Rules.refresh_cost(index + 1)]
	refresh_button.visible = tabs.current_tab == 0
	refresh_hint.visible = tabs.current_tab == 0
	for id in progress_rows:
		var bar = progress_rows[id]
		if not is_instance_valid(bar):
			continue
		var worker = market.workers.get(id)
		var progress = worker.role.get_progress() if worker != null and worker.role.has_method("get_progress") else {}
		bar.value = float(progress.get("ratio", 0.0)) * 100.0
		bar.hint_tooltip = str(progress.get("label", "准备待命"))

func _tab_changed(_index):
	update_summary()

func reveal():
	panel.show()
	var tween = Tween.new()
	panel.add_child(tween)
	tween.interpolate_property(panel, "modulate:a", 0.82, 1.0, 0.16, Tween.TRANS_SINE, Tween.EASE_OUT)
	tween.connect("tween_all_completed", tween, "queue_free")
	tween.start()
