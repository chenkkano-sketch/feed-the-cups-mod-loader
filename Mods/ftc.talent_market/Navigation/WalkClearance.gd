extends Reference

# Door bodies commonly have collision_layer=0: physics queries cannot see
# them, although their collision_mask still blocks the real employee body.
var level
var revision = 0
var records = []
var blockers = []
var cells = {}
var global_blockers = []
var exclude = []
var scan_after = 0
var checked_frame = -1
var capsule = CapsuleShape2D.new()
var circle = CircleShape2D.new()
var hand_segment = SegmentShape2D.new()
const RADIUS = 20.0

func _init(room):
	level = room
	circle.radius = RADIUS
	capsule.radius = RADIUS

func refresh():
	var frame = Engine.get_physics_frames()
	if checked_frame == frame:
		return
	checked_frame = frame
	var changed = false
	if OS.get_ticks_msec() >= scan_after:
		scan_after = OS.get_ticks_msec() + 600
		var found = []
		exclude = []
		var pending = [level]
		while not pending.empty():
			var node = pending.pop_back()
			if node is PhysicsBody2D and not node is StaticBody2D:
				exclude.append(node.get_rid())
			elif node is StaticBody2D:
				var represented = true
				for owner in node.get_shape_owners():
					if not node.shape_owner_get_owner(owner) is CollisionShape2D:
						represented = false
				if represented:
					exclude.append(node.get_rid())
			if node is CollisionShape2D and node.get_parent() is StaticBody2D:
				found.append(node)
			pending += node.get_children()
		if found.size() != records.size():
			changed = true
		else:
			for i in range(found.size()):
				if found[i] != records[i].node:
					changed = true
		if changed:
			records.clear()
			for node in found:
				records.append({"node": node, "state": []})
	for record in records:
		var node = record.node
		var state = []
		if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion():
			var body = node.get_parent()
			state = [node.disabled, node.shape, node.global_transform, body.collision_layer, body.collision_mask, _bounds(node.shape) if node.shape != null else Rect2()]
		if record.state != state:
			record.state = state
			changed = true
	if not changed:
		return
	revision += 1
	blockers.clear()
	cells.clear()
	global_blockers.clear()
	for record in records:
		if record.state.empty() or record.state[0] or record.state[1] == null:
			continue
		var shape = record.state[1]
		var transform = record.state[2]
		var local = record.state[5]
		var bounds = Rect2(transform.xform(local.position), Vector2.ZERO)
		for point in [local.end, Vector2(local.position.x, local.end.y), Vector2(local.end.x, local.position.y)]:
			bounds = bounds.expand(transform.xform(point))
		blockers.append({"shape": shape, "transform": transform, "bounds": bounds, "layer": record.state[3], "mask": record.state[4], "body": record.node.get_parent()})
		var low = (bounds.position / 100.0).floor()
		var high = (bounds.end / 100.0).floor()
		var index = blockers.size() - 1
		if (high.x - low.x + 1) * (high.y - low.y + 1) > 256:
			global_blockers.append(index)
			continue
		for x in range(int(low.x), int(high.x) + 1):
			for y in range(int(low.y), int(high.y) + 1):
				var cell = Vector2(x, y)
				if not cells.has(cell):
					cells[cell] = []
				cells[cell].append(index)

func _nearby(bounds):
	var result = {}
	for index in global_blockers:
		result[index] = true
	var low = (bounds.position / 100.0).floor()
	var high = (bounds.end / 100.0).floor()
	for x in range(int(low.x), int(high.x) + 1):
		for y in range(int(low.y), int(high.y) + 1):
			for index in cells.get(Vector2(x, y), []):
				result[index] = true
	return result.keys()

func _bounds(shape):
	if shape is RectangleShape2D:
		return Rect2(-shape.extents, shape.extents * 2.0)
	if shape is CircleShape2D:
		return Rect2(Vector2.ONE * -shape.radius, Vector2.ONE * shape.radius * 2.0)
	if shape is CapsuleShape2D:
		var half = Vector2(shape.radius, max(shape.radius, shape.height * 0.5))
		return Rect2(-half, half * 2.0)
	if shape is ConvexPolygonShape2D or shape is ConcavePolygonShape2D:
		var points = shape.points if shape is ConvexPolygonShape2D else shape.segments
		if not points.empty():
			var result = Rect2(points[0], Vector2.ZERO)
			for point in points:
				result = result.expand(point)
			return result
	if shape is SegmentShape2D:
		return Rect2(shape.a, Vector2.ZERO).expand(shape.b)
	return Rect2(Vector2(-1000000, -1000000), Vector2(2000000, 2000000))

func clear(first, last, actor_layer = 4610, actor_mask = 25730, ignored_root = null):
	refresh()
	var motion = last - first
	var swept = circle
	var transform = Transform2D(0.0, first)
	if motion.length_squared() > 0.001:
		capsule.height = motion.length() + RADIUS * 2.0
		swept = capsule
		transform = Transform2D(motion.angle() - PI * 0.5, (first + last) * 0.5)
	var bounds = Rect2(first, Vector2.ZERO).expand(last).grow(RADIUS + 0.1)
	for index in _nearby(bounds):
		var blocker = blockers[index]
		if ignored_root != null and (blocker.body == ignored_root or ignored_root.is_a_parent_of(blocker.body)):
			continue
		if (int(blocker.layer) & actor_mask) == 0 and (int(blocker.mask) & actor_layer) == 0:
			continue
		if not bounds.intersects(blocker.bounds):
			continue
		if swept.collide(transform, blocker.shape, blocker.transform):
			# Let an employee already pressed against a door retreat onto a clear
			# tile, but never use initial overlap as permission to cross the door.
			if motion.dot(first - blocker.transform.origin) > 0.0 and circle.collide(Transform2D(0.0, first), blocker.shape, blocker.transform) and not circle.collide(Transform2D(0.0, last), blocker.shape, blocker.transform):
				continue
			return false
	# Also cover TileMap/static geometry without CollisionShape2D scene nodes.
	var query = Physics2DShapeQueryParameters.new()
	query.set_shape(swept)
	query.transform = transform
	query.collision_layer = actor_mask
	query.exclude = exclude
	query.collide_with_areas = false
	for hit in level.get_world_2d().direct_space_state.intersect_shape(query, 128):
		if hit.collider is PhysicsBody2D and not hit.collider is StaticBody2D:
			continue
		return false
	return true

func interaction_clear(first, centre, fixture, actor_layer = 4610, actor_mask = 25730):
	refresh()
	# Interaction reaches a fixture's accessible face. The employee remains at
	# the operation point; their full body must not be swept into the counter.
	var last = centre
	var distance = first.distance_squared_to(centre)
	for blocker in blockers:
		if blocker.body != fixture and not fixture.is_a_parent_of(blocker.body):
			continue
		var bounds = blocker.bounds
		var surface = Vector2(clamp(first.x, bounds.position.x, bounds.end.x), clamp(first.y, bounds.position.y, bounds.end.y))
		if first.distance_squared_to(surface) < distance:
			last = surface
			distance = first.distance_squared_to(surface)
	if distance < 0.001:
		return true
	hand_segment.a = first
	hand_segment.b = last
	var bounds = Rect2(first, Vector2.ZERO).expand(last).grow(0.1)
	for index in _nearby(bounds):
		var blocker = blockers[index]
		if blocker.body == fixture or fixture.is_a_parent_of(blocker.body):
			continue
		if (int(blocker.layer) & actor_mask) == 0 and (int(blocker.mask) & actor_layer) == 0:
			continue
		if bounds.intersects(blocker.bounds) and hand_segment.collide(Transform2D(), blocker.shape, blocker.transform):
			return false
	var query = Physics2DShapeQueryParameters.new()
	query.set_shape(hand_segment)
	query.collision_layer = actor_mask
	query.exclude = exclude
	query.collide_with_areas = false
	for hit in level.get_world_2d().direct_space_state.intersect_shape(query, 128):
		if hit.collider is PhysicsBody2D and not hit.collider is StaticBody2D:
			continue
		if hit.collider == fixture or fixture.is_a_parent_of(hit.collider):
			continue
		return false
	return true
