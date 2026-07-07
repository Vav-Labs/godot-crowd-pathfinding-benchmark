class_name AgentGrid
extends RefCounted

var size: Vector2i
var cell_size: float
var origin: Vector2
var blocked := PackedByteArray()
var navigation_blocked := PackedByteArray()
var astar := AStarGrid2D.new()
var walkable_neighbor_indices: Array[PackedInt32Array] = []
var walkable_neighbor_costs: Array[PackedFloat32Array] = []
var agent_clearance_radius: float = 2.6

const MIN_CLEARANCE_CELLS := 1

const CARDINAL_NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

const ALL_NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]


func _init(
		p_size: Vector2i = Vector2i(80, 45),
		p_cell_size: float = 16.0,
		p_origin: Vector2 = Vector2.ZERO,
		p_agent_clearance_radius: float = 2.6) -> void:
	size = p_size
	cell_size = p_cell_size
	origin = p_origin
	agent_clearance_radius = p_agent_clearance_radius
	_configure_blockers()
	_configure_navigation_blockers()
	_configure_astar()
	_configure_neighbor_indices()


func get_world_rect() -> Rect2:
	return Rect2(origin, Vector2(size) * cell_size)


func is_cell_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func clamp_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(cell.x, 0, size.x - 1),
		clampi(cell.y, 0, size.y - 1)
	)


func cell_index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x


func index_to_cell(index: int) -> Vector2i:
	return Vector2i(index % size.x, index / size.x)


func cell_center_from_index(index: int) -> Vector2:
	return cell_to_world_center(index_to_cell(index))


func is_cell_walkable(cell: Vector2i) -> bool:
	if not is_cell_inside(cell):
		return false
	return navigation_blocked[cell_index(cell)] == 0


func is_cell_index_walkable(index: int) -> bool:
	return index >= 0 and index < navigation_blocked.size() and navigation_blocked[index] == 0


func is_navigation_clearance_cell(cell: Vector2i) -> bool:
	if not is_cell_inside(cell):
		return false

	var index := cell_index(cell)
	return blocked[index] == 0 and navigation_blocked[index] != 0


func is_navigation_clearance_index(index: int) -> bool:
	return (
		index >= 0 and
		index < blocked.size() and
		blocked[index] == 0 and
		navigation_blocked[index] != 0
	)


func is_cell_blocked(cell: Vector2i) -> bool:
	if not is_cell_inside(cell):
		return true
	return blocked[cell_index(cell)] != 0


func is_cell_index_blocked(index: int) -> bool:
	return index < 0 or index >= blocked.size() or blocked[index] != 0


func nearest_walkable_cell(cell: Vector2i) -> Vector2i:
	var clamped := clamp_cell(cell)
	if is_cell_walkable(clamped):
		return clamped

	for radius in range(1, max(size.x, size.y)):
		for y in range(clamped.y - radius, clamped.y + radius + 1):
			for x in range(clamped.x - radius, clamped.x + radius + 1):
				var candidate := Vector2i(x, y)
				if is_cell_walkable(candidate):
					return candidate

	return Vector2i.ONE


func world_to_cell(world_position: Vector2) -> Vector2i:
	var local_position := world_position - origin
	return clamp_cell(Vector2i(
		floori(local_position.x / cell_size),
		floori(local_position.y / cell_size)
	))


func world_to_cell_fast(world_position: Vector2) -> Vector2i:
	var local_position := world_position - origin
	return Vector2i(
		clampi(floori(local_position.x / cell_size), 0, size.x - 1),
		clampi(floori(local_position.y / cell_size), 0, size.y - 1)
	)


func cell_to_world_center(cell: Vector2i) -> Vector2:
	var clamped := clamp_cell(cell)
	return origin + (Vector2(clamped) + Vector2(0.5, 0.5)) * cell_size


func clamp_world_position(world_position: Vector2) -> Vector2:
	var rect := get_world_rect()
	return Vector2(
		clampf(world_position.x, rect.position.x, rect.end.x),
		clampf(world_position.y, rect.position.y, rect.end.y)
	)


func clamp_world_to_walkable(world_position: Vector2) -> Vector2:
	return cell_to_world_center(nearest_walkable_cell(world_to_cell(world_position)))


func default_benchmark_goal_cells() -> Array[Vector2i]:
	if size == Vector2i(80, 45):
		return [
			Vector2i(12, 10),
			Vector2i(67, 10),
			Vector2i(67, 34),
			Vector2i(12, 34),
			Vector2i(40, 22),
		]

	return [
		_fraction_cell(0.15, 0.22),
		_fraction_cell(0.84, 0.22),
		_fraction_cell(0.84, 0.76),
		_fraction_cell(0.15, 0.76),
		Vector2i(size.x / 2, size.y / 2),
	]


func get_walkable_neighbors(cell: Vector2i, include_diagonals: bool = true) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var directions := ALL_NEIGHBORS if include_diagonals else CARDINAL_NEIGHBORS

	for direction in directions:
		var next_cell: Vector2i = cell + direction
		if can_travel_between_cells(cell, next_cell):
			result.append(next_cell)

	return result


func can_travel_between_cells(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if not is_cell_walkable(from_cell) or not is_cell_walkable(to_cell):
		return false

	var delta := to_cell - from_cell
	if abs(delta.x) > 1 or abs(delta.y) > 1:
		return false

	if delta.x == 0 or delta.y == 0:
		return true

	# No corner cutting: a diagonal step is valid only when both adjacent
	# orthogonal cells are also open in the inflated navigation mask.
	return (
		is_cell_walkable(from_cell + Vector2i(delta.x, 0)) and
		is_cell_walkable(from_cell + Vector2i(0, delta.y))
	)


func has_corner_cut_blocked_diagonal(cell: Vector2i) -> bool:
	if not is_cell_walkable(cell):
		return false

	for direction in ALL_NEIGHBORS:
		if abs(direction.x) + abs(direction.y) != 2:
			continue

		var next_cell := cell + direction
		if not is_cell_walkable(next_cell):
			continue

		if not can_travel_between_cells(cell, next_cell):
			return true

	return false


func get_walkable_neighbor_indices(index: int) -> PackedInt32Array:
	return walkable_neighbor_indices[index]


func get_walkable_neighbor_costs(index: int) -> PackedFloat32Array:
	return walkable_neighbor_costs[index]


func find_path_cells(start_cell: Vector2i, end_cell: Vector2i) -> Array:
	var start := nearest_walkable_cell(start_cell)
	var end := nearest_walkable_cell(end_cell)
	return find_path_cells_walkable(start, end)


func find_path_cells_walkable(start_cell: Vector2i, end_cell: Vector2i) -> Array:
	var start := start_cell
	var end := end_cell
	if start == end:
		return [start]

	return astar.get_id_path(start, end, false)


func _configure_blockers() -> void:
	blocked = PackedByteArray()
	blocked.resize(size.x * size.y)
	blocked.fill(0)

	for x in range(size.x):
		_set_blocked(Vector2i(x, 0), true)
		_set_blocked(Vector2i(x, size.y - 1), true)

	for y in range(size.y):
		_set_blocked(Vector2i(0, y), true)
		_set_blocked(Vector2i(size.x - 1, y), true)

	var rooms := _blocker_rooms()

	for rect in rooms:
		_fill_blocked_rect(rect)

	for safe_cell in default_benchmark_goal_cells():
		for y in range(safe_cell.y - 1, safe_cell.y + 2):
			for x in range(safe_cell.x - 1, safe_cell.x + 2):
				var cell := Vector2i(x, y)
				if is_cell_inside(cell):
					_set_blocked(cell, false)


func _blocker_rooms() -> Array[Rect2i]:
	if size == Vector2i(80, 45):
		return [
			Rect2i(15, 6, 5, 15),
			Rect2i(15, 28, 5, 10),
			Rect2i(31, 3, 6, 14),
			Rect2i(31, 26, 6, 15),
			Rect2i(48, 8, 7, 23),
			Rect2i(63, 4, 5, 13),
			Rect2i(63, 27, 5, 13),
			Rect2i(24, 20, 9, 3),
			Rect2i(56, 20, 12, 3),
		]

	return [
		_fraction_rect(0.19, 0.10, 0.07, 0.34),
		_fraction_rect(0.19, 0.62, 0.07, 0.25),
		_fraction_rect(0.39, 0.06, 0.08, 0.30),
		_fraction_rect(0.39, 0.58, 0.08, 0.32),
		_fraction_rect(0.60, 0.18, 0.09, 0.46),
		_fraction_rect(0.79, 0.09, 0.07, 0.28),
		_fraction_rect(0.79, 0.60, 0.07, 0.28),
		_fraction_rect(0.30, 0.45, 0.12, 0.07),
		_fraction_rect(0.70, 0.45, 0.15, 0.07),
	]


func _fraction_cell(x_ratio: float, y_ratio: float) -> Vector2i:
	return Vector2i(
		clampi(roundi(float(size.x - 1) * x_ratio), 1, size.x - 2),
		clampi(roundi(float(size.y - 1) * y_ratio), 1, size.y - 2)
	)


func _fraction_rect(x_ratio: float, y_ratio: float, width_ratio: float, height_ratio: float) -> Rect2i:
	var position := Vector2i(
		clampi(roundi(float(size.x) * x_ratio), 1, size.x - 3),
		clampi(roundi(float(size.y) * y_ratio), 1, size.y - 3)
	)
	var rect_size := Vector2i(
		clampi(roundi(float(size.x) * width_ratio), 2, size.x - position.x - 1),
		clampi(roundi(float(size.y) * height_ratio), 2, size.y - position.y - 1)
	)
	return Rect2i(position, rect_size)


func _configure_astar() -> void:
	astar.region = Rect2i(0, 0, size.x, size.y)
	astar.cell_size = Vector2(cell_size, cell_size)
	astar.offset = origin + Vector2(cell_size * 0.5, cell_size * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()

	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			if not is_cell_walkable(cell):
				astar.set_point_solid(cell, true)


func _configure_neighbor_indices() -> void:
	walkable_neighbor_indices.clear()
	walkable_neighbor_costs.clear()
	walkable_neighbor_indices.resize(size.x * size.y)
	walkable_neighbor_costs.resize(size.x * size.y)

	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			var index := cell_index(cell)
			var indices := PackedInt32Array()
			var costs := PackedFloat32Array()

			if is_cell_walkable(cell):
				for direction in ALL_NEIGHBORS:
					var next_cell: Vector2i = cell + direction
					if not can_travel_between_cells(cell, next_cell):
						continue

					indices.append(cell_index(next_cell))
					costs.append(1.4142 if abs(direction.x) + abs(direction.y) == 2 else 1.0)

			walkable_neighbor_indices[index] = indices
			walkable_neighbor_costs[index] = costs


func _fill_blocked_rect(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			if is_cell_inside(cell):
				_set_blocked(cell, true)


func _configure_navigation_blockers() -> void:
	navigation_blocked = PackedByteArray()
	navigation_blocked.resize(blocked.size())
	navigation_blocked.fill(0)

	var clearance_cells := maxi(MIN_CLEARANCE_CELLS, ceili(agent_clearance_radius / cell_size))
	for y in range(size.y):
		for x in range(size.x):
			var source_cell := Vector2i(x, y)
			if not is_cell_blocked(source_cell):
				continue

			for offset_y in range(-clearance_cells, clearance_cells + 1):
				for offset_x in range(-clearance_cells, clearance_cells + 1):
					var target_cell := source_cell + Vector2i(offset_x, offset_y)
					if is_cell_inside(target_cell):
						navigation_blocked[cell_index(target_cell)] = 1


func _set_blocked(cell: Vector2i, solid: bool) -> void:
	if not is_cell_inside(cell):
		return
	blocked[cell_index(cell)] = 1 if solid else 0
