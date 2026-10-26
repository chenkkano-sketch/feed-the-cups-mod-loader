extends TextureRect

var viewport
var scene
var map_id = ""
var bounds = Rect2()

func _ready():
	expand = true
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = Viewport.new()
	viewport.size = Vector2(1120, 800)
	viewport.disable_3d = true
	viewport.usage = Viewport.USAGE_2D
	viewport.world_2d = World2D.new()
	viewport.render_target_v_flip = true
	viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
	add_child(viewport)
	texture = viewport.get_texture()

func show_map(id):
	if id == map_id:
		return
	map_id = id
	if is_instance_valid(scene):
		viewport.remove_child(scene)
		scene.free()
	# Preview a separate, inert copy of the real map. No native gameplay
	# scripts, camera, sounds or physics can interact with the current run.
	var room = preload("res://ftc_mods/ftc.rent_mode/RentMaps.gd").room(id)
	scene = load(room.get("preview", "res://TscnAndGd/Main/Level/" + id + ".tscn")).instance()
	_make_inert(scene)
	viewport.add_child(scene)
	var floor_map = scene.get_node_or_null("MapNode/Floor")
	if floor_map == null:
		viewport.render_target_update_mode = Viewport.UPDATE_ONCE
		return
	var cells = floor_map.get_used_rect()
	bounds = Rect2(floor_map.map_to_world(cells.position), cells.size * floor_map.cell_size)
	var devices = scene.get_node_or_null("YSort/Devices")
	if devices != null:
		for fixture in devices.get_children():
			if fixture is Node2D:
				bounds = bounds.expand(fixture.global_position)
	# Leave enough margin to show walls, the serving counter and the street.
	bounds = bounds.grow(300)
	var scale = min(viewport.size.x / bounds.size.x, viewport.size.y / bounds.size.y)
	viewport.canvas_transform = Transform2D(Vector2(scale, 0), Vector2(0, scale), (viewport.size - bounds.size * scale) / 2.0 - bounds.position * scale)
	viewport.render_target_update_mode = Viewport.UPDATE_ONCE

func _make_inert(node):
	for child in node.get_children():
		_make_inert(child)
	# Apply the saved table skin without running native gameplay initialization.
	if node.get("Tex") != null and node.has_node("TexNode/TypeAni"):
		var skin = node.get_node("TexNode/TypeAni")
		if skin.has_animation(str(node.Tex)):
			skin.play(str(node.Tex))
			skin.seek(0.0, true)
			skin.stop(false)
	if node is CanvasItem:
		node.material = null
	if node is Control or (node is CanvasItem and (node.name.begins_with("Warning") or node.name in ["Control_Info", "GuideNode", "But", "TakeNode", "PayNode"])):
		node.hide()
	if node is Sprite and node.texture != null and "/UI/" in node.texture.resource_path:
		node.hide()
	if node is Camera2D:
		node.current = false
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
		node.autoplay = false
		node.stop()
	if node is AnimationPlayer:
		node.autoplay = ""
		node.stop()
	if node is Timer:
		node.autostart = false
	if node is CanvasModulate:
		node.color = Color.white
	if node is Light2D:
		node.enabled = false
	if node is CollisionObject2D:
		node.collision_layer = 0
		node.collision_mask = 0
	node.set_script(null)
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
