extends Reference

const Rules = preload("res://ftc_mods/ftc.talent_market/TalentRules.gd")
const AVATAR_ALL = "SpriteTex/Top_note/All_note/"
const AVATAR_BODY = AVATAR_ALL + "Body_note/BodyPose/"
const OUTFIT_ANIMATORS = {
	"Head": [AVATAR_BODY + "Body/HeadPose/Head/Staffhat/DecoHatType"],
	"Body": [AVATAR_BODY + "Body/StaffApron/ApronType"],
	"Face": [AVATAR_BODY + "Body/HeadPose/Head/StaffMask/MaskType"],
	"Foot": [AVATAR_ALL + "Leg_L/Shoe/ShoeType", AVATAR_ALL + "Leg_R/Shoe/ShoeType"],
	"Hand": [AVATAR_BODY + "Arm/Pose/StaffClove/CloveType", AVATAR_BODY + "Arm_Hold/Pose_Hold/StaffClove/CloveType"]
}

var manager
var game
var appearance_catalog = []
var portrait_cache = {}
var portrait_order = []
var portrait_ink_cache = {}

func _init(owner):
	manager = owner
	game = owner.game

func _appearance_catalog():
	if not appearance_catalog.empty():
		return appearance_catalog
	var ids = game.Config.PlayerConfig.keys()
	ids.sort()
	var costumes = game.Config.CostumeConfig.keys()
	costumes.sort()
	for id in ids:
		var config = game.Config.PlayerConfig[id]
		if not config is Dictionary or not config.has("TSCN"):
			continue
		var packed = game.TSCNLoad.return_character(config.TSCN)
		if not packed is PackedScene:
			continue
		# Inspection stays outside the tree: no player, NPC, input or autoload
		# subscriptions are created while enumerating the native visual assets.
		var avatar = packed.instance()
		var head = avatar.get_node_or_null("HeadType")
		if not avatar.has_method("call_EquipInit") or not avatar.has_node(AVATAR_BODY + "Arm_Hold/Pose_Hold/Weapon_note") or not head is AnimationPlayer:
			avatar.free()
			continue
		var skins = []
		for skin in range(1, 5):
			if head.has_animation(str(skin)):
				skins.append(skin)
		if skins.empty():
			avatar.free()
			continue
		var fashion = {}
		for part in Rules.FASHION_PARTS:
			fashion[part] = [0]
			if not OUTFIT_ANIMATORS.has(part):
				continue
			for costume_id in costumes:
				var costume = game.Config.CostumeConfig[costume_id]
				if not costume is Dictionary or str(costume.get("class", "")) != "Costume" or str(costume.get("part", "")) != part:
					continue
				var supported = true
				for path in OUTFIT_ANIMATORS[part]:
					var animator = avatar.get_node_or_null(path)
					if not animator is AnimationPlayer or not animator.has_animation(str(costume.get("ANI", ""))):
						supported = false
						break
				if supported:
					fashion[part].append(int(costume_id))
		appearance_catalog.append({"avatar": int(id), "skins": skins, "fashion": fashion})
		avatar.free()
	return appearance_catalog

func _validate_appearance(person):
	Rules.apply_appearance(person)
	var catalog = _appearance_catalog()
	if catalog.empty():
		return
	var selected = catalog[0]
	for item in catalog:
		if int(item.avatar) == int(person.avatar):
			selected = item
			break
	person.avatar = int(selected.avatar)
	if not int(person.skin) in selected.skins:
		person.skin = int(selected.skins[0])
	for part in Rules.FASHION_PARTS:
		if not int(person.fashion[part]) in selected.fashion[part]:
			person.fashion[part] = 0

func _pose_animation(node, name, depth = 0):
	if not node is AnimationPlayer or not node.has_animation(name) or depth > 8:
		return
	# Detached AnimationPlayers may retain unapplied or conflicting scene poses.
	# Follow only explicitly selected visual clips. Native HeadType delegates to
	# SpriteTex/Character/C_Head; ignoring that animation track loses the skin.
	# Methods, sounds and unrelated default animations remain unexecuted.
	var animation = node.get_animation(name)
	var root = node.get_node_or_null(node.root_node)
	if root == null:
		return
	node.stop(false)
	node.assigned_animation = name
	for track in range(animation.get_track_count()):
		var kind = animation.track_get_type(track)
		if not kind in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER, Animation.TYPE_ANIMATION] or not animation.track_is_enabled(track) or animation.track_get_key_count(track) < 1:
			continue
		var path = animation.track_get_path(track)
		var names = []
		for component in range(path.get_name_count()):
			names.append(str(path.get_name(component)))
		names = PoolStringArray(names).join("/")
		var target = root if names in ["", "."] else root.get_node_or_null(NodePath(names))
		if target == null:
			continue
		var index = 0
		for key in range(1, animation.track_get_key_count(track)):
			if animation.track_get_key_time(track, key) > 0.0:
				break
			index = key
		if kind == Animation.TYPE_ANIMATION:
			var clip = str(animation.track_get_key_value(track, index))
			if clip != "" and clip != "[stop]":
				_pose_animation(target, clip, depth + 1)
			continue
		if path.get_subname_count() < 1:
			continue
		var value = animation.track_get_key_value(track, index) if kind == Animation.TYPE_VALUE else animation.bezier_track_interpolate(track, 0.0)
		if value is Material:
			value = value.duplicate(true)
		var properties = []
		for component in range(path.get_subname_count()):
			properties.append(str(path.get_subname(component)))
		target.set_indexed(NodePath(PoolStringArray(properties).join(":")), value)

func _isolate_preview(node):
	# Never remove a Container's internal child-layout connections. The native
	# avatar remains detached, and the final sprite-only copy carries no signals.
	for group in node.get_groups():
		node.remove_from_group(group)
	if node is CanvasItem and node.material != null:
		node.material = node.material.duplicate(true)
	for child in node.get_children():
		_isolate_preview(child)

func _pose_outfit(node):
	if node is AnimationPlayer and node.name in Rules.OUTFIT_ANIMATION_NAMES:
		var selected = str(node.assigned_animation)
		if selected != "":
			_pose_animation(node, selected)
	for child in node.get_children():
		_pose_outfit(child)

func _pose_scene_defaults(node):
	# Match only the packed scene's actual startup clips, before applying the
	# employee's choices. SpeakerType.init, for example, hides an unused headset.
	# Detached nodes never receive the engine's enter-tree autoplay initialization.
	if node is AnimationPlayer:
		var startup = str(node.get("autoplay"))
		if startup != "" and node.has_animation(startup):
			_pose_animation(node, startup)
	for child in node.get_children():
		_pose_scene_defaults(child)

func _copy_visual(node):
	if not node is Node2D or node is CollisionObject2D or node is RayCast2D or node is CollisionShape2D or not node.visible or node.modulate.a <= 0.001:
		return null
	if node.name in ["Texturenode", "Effect_StaffHead", "EffectNode"]:
		return null
	var copy = Sprite.new() if node is Sprite else Node2D.new()
	copy.name = node.name
	copy.transform = node.transform
	copy.modulate = node.modulate
	copy.self_modulate = node.self_modulate
	copy.z_index = node.z_index
	copy.z_as_relative = node.z_as_relative
	copy.show_behind_parent = node.show_behind_parent
	copy.material = node.material
	copy.use_parent_material = node.use_parent_material
	copy.light_mask = node.light_mask
	if node is Sprite:
		copy.texture = node.texture
		copy.centered = node.centered
		copy.offset = node.offset
		copy.hframes = node.hframes
		copy.vframes = node.vframes
		copy.frame = node.frame
		copy.flip_h = node.flip_h
		copy.flip_v = node.flip_v
		copy.region_enabled = node.region_enabled
		copy.region_rect = node.region_rect
		copy.region_filter_clip = node.region_filter_clip
	for child in node.get_children():
		var visual = _copy_visual(child)
		if visual != null:
			copy.add_child(visual)
	return copy

func _sprite_ink_rect(sprite):
	# Some native species use large transparent sheets. Fit actual opaque art,
	# not the empty padding or a transparent effect's rectangle.
	var rect = sprite.get_rect()
	if sprite.texture == null or sprite.self_modulate.a <= 0.001:
		return Rect2()
	var key = "%s:%s:%s:%s:%s:%s" % [sprite.texture.get_instance_id(), sprite.hframes, sprite.vframes, sprite.frame, sprite.region_enabled, sprite.region_rect]
	var ink
	if portrait_ink_cache.has(key):
		ink = portrait_ink_cache[key]
	else:
		var image = sprite.texture.get_data()
		ink = Rect2(Vector2.ZERO, rect.size)
		if image != null and image.get_width() > 0 and image.get_height() > 0:
			if image.is_compressed():
				image.decompress()
			var region = sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, sprite.texture.get_size())
			var cell_size = region.size / Vector2(sprite.hframes, sprite.vframes)
			var origin = region.position + Vector2(int(sprite.frame) % sprite.hframes, int(sprite.frame) / sprite.hframes) * cell_size
			var cell = Rect2(origin, cell_size).clip(Rect2(Vector2.ZERO, Vector2(image.get_width(), image.get_height())))
			if cell.size.x > 0 and cell.size.y > 0:
				ink = image.get_rect(cell).get_used_rect()
				ink.position += cell.position - origin
			else:
				ink = Rect2()
		if portrait_ink_cache.size() >= 512:
			portrait_ink_cache.clear()
		portrait_ink_cache[key] = ink
	if sprite.flip_h:
		ink.position.x = rect.size.x - ink.end.x
	if sprite.flip_v:
		ink.position.y = rect.size.y - ink.end.y
	ink.position += rect.position
	return ink

func _visual_points(node, transform, points):
	if node.modulate.a <= 0.001:
		return
	var current = transform * node.transform
	if node is Sprite and node.texture != null:
		var rect = _sprite_ink_rect(node)
		if rect.size.x > 0 and rect.size.y > 0:
			for point in [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]:
				points.append(current.xform(point))
	for child in node.get_children():
		_visual_points(child, current, points)

func _portrait_visual(person):
	var key = Rules.appearance_key(person)
	if portrait_cache.has(key):
		return portrait_cache[key]
	var packed = game.TSCNLoad.return_character(game.Config.PlayerConfig[str(person.avatar)].TSCN)
	var avatar = packed.instance()
	_isolate_preview(avatar)
	# Native explicit equipment initialization also preserves each species'
	# default costume. This plain, off-tree identity has no human player slot.
	var identity = Node.new()
	avatar.body = identity
	avatar.CURPLAYER = -900001
	avatar.CURAVATAR = int(person.avatar)
	_pose_scene_defaults(avatar)
	avatar.call_EquipInit(Rules.appearance(person).fashion)
	_pose_animation(avatar.get_node_or_null("BodyPose"), "StandDown")
	_pose_animation(avatar.get_node_or_null("FaceAni"), "down")
	_pose_animation(avatar.get_node_or_null("ArmAct"), "EmptyDown")
	_pose_outfit(avatar)
	_pose_animation(avatar.get_node_or_null("HeadType"), str(person.skin))
	var visual = _copy_visual(avatar)
	avatar.free()
	identity.free()
	if visual == null:
		visual = Node2D.new()
	visual.set_meta("appearance_key", key)
	var points = []
	_visual_points(visual, Transform2D.IDENTITY, points)
	var bounds = Rect2(Vector2(-60, -160), Vector2(120, 170))
	if not points.empty():
		bounds = Rect2(points[0], Vector2.ZERO)
		for point in points:
			bounds = bounds.expand(point)
	visual.set_meta("bounds", bounds)
	portrait_cache[key] = visual
	portrait_order.append(key)
	while portrait_order.size() > 64:
		var old = portrait_order.pop_front()
		portrait_cache[old].free()
		portrait_cache.erase(old)
	return visual

func _portrait(person, dimensions = Vector2(112, 128)):
	var frame = Control.new()
	frame.name = "Portrait"
	frame.rect_min_size = dimensions
	frame.rect_size = dimensions
	# Godot 3 calls Control.clip_contents rect_clip_content.
	frame.rect_clip_content = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_meta("appearance", Rules.appearance(person))
	var source = _portrait_visual(person)
	var visual = source.duplicate(0)
	var bounds = source.get_meta("bounds")
	# Bounds already include the copied avatar root's native transform. Fit an
	# identity parent so that transform is applied exactly once, including its
	# translation; replacing the root position used to move hats/feet off anchor.
	var anchor = Node2D.new()
	anchor.name = "PortraitFit"
	frame.add_child(anchor)
	anchor.add_child(visual)
	frame.connect("resized", self, "_fit_portrait", [frame, anchor, bounds])
	_fit_portrait(frame, anchor, bounds)
	return frame

func _fit_portrait(frame, anchor, bounds):
	var dimensions = frame.rect_size
	# Leave additional vertical breathing room for native shoe/hat atlas pixels
	# just outside their conservative alpha bounds. All species share this inset.
	var available = Vector2(max(1.0, dimensions.x - 16.0), max(1.0, dimensions.y - 16.0) * 0.87)
	# Equal visible height is the primary fit, preserving each native aspect.
	# The width guard only matters for an unusually broad native accessory.
	var scale = min(available.y / max(1.0, bounds.size.y), available.x / max(1.0, bounds.size.x))
	anchor.scale = Vector2(scale, scale)
	anchor.position = dimensions * 0.5 - (bounds.position + bounds.size * 0.5) * scale
	frame.set_meta("fitted_bounds", Rect2(anchor.position + bounds.position * scale, bounds.size * scale))
	frame.set_meta("fit_scale", scale)


func cleanup():
	for visual in portrait_cache.values():
		visual.free()
	portrait_cache.clear()
	portrait_order.clear()
	portrait_ink_cache.clear()
