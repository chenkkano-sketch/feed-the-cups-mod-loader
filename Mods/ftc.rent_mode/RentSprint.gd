extends Reference

const MULTIPLIER = 1.8
const INTERVAL = 0.065
const LIFETIME = 0.30
const MAX_GHOSTS = 5
const MIN_DISTANCE = 8.0

var owner
var actor = null
var active = false
var ghosts = []
var elapsed = 0.0
var last_position = Vector2.ZERO

func _init(mode):
	owner = mode

func can_sprint(target):
	if not owner.is_run() or not owner._offline() or owner.get_tree().paused or owner.controls_blocked:
		return false
	if GameLogic.LoadingUI.Is_Loading or GameLogic.GameUI.DayEnd or owner.state.get("failed", false):
		return false
	if not is_instance_valid(target) or target != GameLogic.player_1P or target.IsDead:
		return false
	var control = target.Con
	return control.CanControl and control.CanMove and not control.IsPause and not control.IsRoll and control.state in [GameLogic.NPC.STATE.IDLE_EMPTY, GameLogic.NPC.STATE.IDLE_ACT, GameLogic.NPC.STATE.MOVE]

func factor_for(target):
	return MULTIPLIER if active and target == actor and can_sprint(target) else 1.0

func reserves_shift(target, button, type):
	if not owner.is_run() or not owner._offline() or owner.get_tree().paused or target != GameLogic.player_1P:
		return false
	var binding = target.Con.KEYCONTROL.get(button, {})
	return type == GameLogic.Con.TYPE.KEY and binding is Dictionary and binding.get("BUT", -1) == KEY_SHIFT

func update(delta, pressed, focused = true):
	_age_ghosts(delta)
	var target = GameLogic.player_1P if owner.is_run() else null
	var allowed = focused and can_sprint(target)
	var wanted = allowed and pressed
	if target != actor or active != wanted:
		var previous = actor
		actor = target
		active = wanted
		elapsed = 0.0
		if is_instance_valid(actor):
			last_position = actor.global_position
		if is_instance_valid(previous):
			previous.Con.call_velocity()
		if is_instance_valid(actor) and previous != actor:
			actor.Con.call_velocity()
	if not allowed:
		clear_ghosts()
		return
	if not active:
		return
	elapsed += delta
	var distance = actor.global_position.distance_to(last_position)
	if actor.Con.input_vector == Vector2.ZERO or distance > 200.0:
		last_position = actor.global_position
		elapsed = 0.0
		return
	if elapsed >= INTERVAL and distance >= MIN_DISTANCE:
		_emit_ghost(actor)
		last_position = actor.global_position
		elapsed = 0.0

func _collect_sprites(node, result, inherited_color = Color.white, inherited_z = 0):
	# Snapshot only character artwork, excluding held machines, labels and UI.
	if not node is CanvasItem or not node.is_visible_in_tree() or node.name in ["Weapon_note", "StaffMop"] or node is Control:
		return
	var color = inherited_color * node.modulate
	var order = inherited_z + node.z_index if node.z_as_relative else node.z_index
	if node is Sprite and node.texture != null and color.a * node.self_modulate.a > 0.01:
		result.append([order, result.size(), node, color * node.self_modulate])
	for child in node.get_children():
		_collect_sprites(child, result, color, order)

func _sprite_before(a, b):
	return a[0] < b[0] if a[0] != b[0] else a[1] < b[1]

func _emit_ghost(target):
	if not is_instance_valid(target.AVATAR):
		return
	var artwork = target.AVATAR.get_node_or_null("SpriteTex")
	var room = owner.get_tree().root.get_node_or_null("Level")
	if artwork == null or room == null:
		return
	var sprites = []
	_collect_sprites(artwork, sprites)
	if sprites.empty():
		return
	sprites.sort_custom(self, "_sprite_before")
	var ghost = Node2D.new()
	ghost.name = "RentSprintAfterimage"
	ghost.z_index = -1
	room.get_node("YSort").add_child(ghost)
	ghost.global_position = target.AVATAR.global_position
	for record in sprites:
		var source = record[2]
		var copy = Sprite.new()
		copy.texture = source.texture
		copy.hframes = source.hframes
		copy.vframes = source.vframes
		copy.frame = source.frame
		copy.region_enabled = source.region_enabled
		copy.region_rect = source.region_rect
		copy.region_filter_clip = source.region_filter_clip
		copy.centered = source.centered
		copy.offset = source.offset
		copy.flip_h = source.flip_h
		copy.flip_v = source.flip_v
		copy.modulate = record[3]
		ghost.add_child(copy)
		copy.global_transform = source.global_transform
	ghost.modulate = Color(0.45, 0.85, 1.0, 0.38)
	ghosts.append([ghost, 0.0])
	while ghosts.size() > MAX_GHOSTS:
		var oldest = ghosts.pop_front()
		if is_instance_valid(oldest[0]):
			oldest[0].queue_free()

func _age_ghosts(delta):
	for index in range(ghosts.size() - 1, -1, -1):
		var record = ghosts[index]
		if not is_instance_valid(record[0]):
			ghosts.remove(index)
			continue
		record[1] += delta
		if record[1] >= LIFETIME:
			record[0].queue_free()
			ghosts.remove(index)
		else:
			record[0].modulate.a = 0.38 * (1.0 - record[1] / LIFETIME)

func clear_ghosts():
	for record in ghosts:
		if is_instance_valid(record[0]):
			record[0].queue_free()
	ghosts.clear()
