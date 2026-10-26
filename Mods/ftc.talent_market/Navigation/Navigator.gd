extends Reference

# Read-only access to native points, with a private live-door fallback graph.
# Neither fallback connections nor blocked doors change customer paths.
var level
var last_error = ""
var actor = null
const Clearance = preload("res://ftc_mods/ftc.talent_market/Navigation/WalkClearance.gd")

func _init(room = null):
	level = room

func set_actor(body):
	actor = weakref(body)

func _layers():
	var body = actor.get_ref() if actor != null else null
	return [body.collision_layer, body.collision_mask] if is_instance_valid(body) else [4610, 25730]

func graph():
	if not is_instance_valid(level) or not is_instance_valid(GameLogic.Astar):
		return null
	var value = GameLogic.Astar.AStar_Func
	return value if value != null and value.get_point_count() > 0 else null

func nearest(position, maximum_distance = 160.0):
	var native = graph()
	if native == null:
		return null
	var point = native.get_closest_point(position)
	if point < 0:
		return null
	var value = native.get_point_position(point)
	return value if value.distance_to(position) <= maximum_distance else null

func path(start, destination):
	last_error = ""
	var native = graph()
	if native == null:
		last_error = "导航尚未就绪"
		return []
	var environment = _environment()
	var first = _reachable_start(native, start, environment)
	var last = native.get_closest_point(destination)
	if first < 0 or last < 0:
		last_error = "找不到通路"
		return []
	var final_point = native.get_point_position(last)
	if final_point.distance_to(destination) > 45.0:
		last_error = "目标不在通行区域"
		return []
	var result = Array(native.get_point_path(first, last))
	if result.empty() or not _route_clear(result, environment) or not _edge_clear(start, result[0], environment):
		var live = _live_graph(native, environment)
		result = Array(live.get_point_path(first, last))
		if not _route_clear(result, environment) or (not result.empty() and not _edge_clear(start, result[0], environment)):
			result.clear()
	if result.empty():
		last_error = "目标无法到达"
		return []
	# Keep the first point if it is needed to leave an off-centre spawn safely.
	if result.size() > 1 and start.distance_to(result[0]) < 24.0:
		result.pop_front()
	return result

func _reachable_start(native, start, environment):
	var nearest_id = native.get_closest_point(start)
	if nearest_id >= 0 and _edge_clear(start, native.get_point_position(nearest_id), environment):
		return nearest_id
	# A body pressed against a door can be nearer to a point across that door.
	# Try another nearby tile on its actual side instead of crossing or freezing.
	var best = -1
	var distance = 160.0 * 160.0
	for id in native.get_points():
		var point = native.get_point_position(id)
		var candidate_distance = start.distance_squared_to(point)
		if candidate_distance < distance and _edge_clear(start, point, environment):
			best = id
			distance = candidate_distance
	return best

func _environment():
	var cache = level.get_meta("ftc_talent_path_environment") if level.has_meta("ftc_talent_path_environment") else {}
	if not cache.has("clearance"):
		cache = {"clearance": Clearance.new(level)}
		level.set_meta("ftc_talent_path_environment", cache)
	cache.clearance.refresh()
	return cache

func _edge_clear(first, last, environment):
	var layers = _layers()
	return environment.clearance.clear(first, last, int(layers[0]), int(layers[1]))

func _route_clear(points, environment):
	for i in range(1, points.size()):
		if not _edge_clear(points[i - 1], points[i], environment):
			return false
	return true

func segment_clear(first, last):
	return _edge_clear(first, last, _environment())

func _live_graph(native, environment):
	var cached = environment.get("graph")
	var layers = _layers()
	if cached != null and environment.get("source") == native.get_instance_id() and environment.get("count") == native.get_point_count() and environment.get("revision") == environment.clearance.revision and environment.get("layers") == layers:
		return cached
	var live = AStar2D.new()
	var positions = {}
	for id in native.get_points():
		var point = native.get_point_position(id)
		live.add_point(id, point, native.get_point_weight_scale(id))
		positions[point] = id
	var directions = [Vector2(100, 0), Vector2(0, 100)]
	if GameLogic.Astar.ASTAR_MAIN_TYPE == 1:
		directions += [Vector2(100, 100), Vector2(-100, 100)]
	for point in positions:
		for direction in directions:
			var other = point + direction
			if positions.has(other) and _edge_clear(point, other, environment):
				live.connect_points(positions[point], positions[other], true)
	environment.graph = live
	environment.source = native.get_instance_id()
	environment.count = native.get_point_count()
	environment.revision = environment.clearance.revision
	environment.layers = layers
	return live

func anchor(device):
	if not is_instance_valid(device) or not (device is Node2D) or not device.is_inside_tree() or device.is_queued_for_deletion():
		return null
	var current = device
	while is_instance_valid(current.get_parent()) and current != level:
		var parent = current.get_parent()
		if parent.name in ["Devices", "Outdoor", "Items", "Update", "UpdateItems"]:
			return current
		if parent == level or parent.name == "YSort":
			break
		current = parent
	return device

func approach(device, start):
	var fixture = anchor(device)
	if fixture == null:
		return null
	var centre = fixture.global_position
	var candidates = []
	# Ground packages are solid too. Target a neighbouring operation tile rather
	# than the package's centre, where body collision would prevent arrival.
	for direction in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
		candidates.append(centre + direction * 100.0)
	var best = null
	var best_distance = INF
	var visited = {}
	for candidate in candidates:
		# Player-dropped boxes are not grid-aligned. A half-tile offset can be
		# 70.71px from the nearest graph point even on an unobstructed floor.
		var nearby = nearest(candidate, 75.0)
		if nearby == null or visited.has(nearby):
			continue
		visited[nearby] = true
		if nearby.distance_to(centre) > 150.0:
			continue
		# A nearby operation point can lie on the opposite side of a closed
		# entrance. Check the actual hand-to-device segment as well as the route.
		if not _interaction_clear(nearby, centre, fixture):
			continue
		var route = path(start, nearby)
		if route.empty():
			continue
		var length = start.distance_to(route[0])
		for index in range(1, route.size()):
			length += route[index - 1].distance_to(route[index])
		if length < best_distance:
			best_distance = length
			best = nearby
	if best == null:
		last_error = "设备四周没有可达的操作位置"
	return best

func _interaction_clear(first, last, fixture):
	var layers = _layers()
	return _environment().clearance.interaction_clear(first, last, fixture, int(layers[0]), int(layers[1]))
