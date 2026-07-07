class_name SharedField
extends RefCounted

var grid: AgentGrid
var goal_world: Vector2 = Vector2.ZERO
var goal_cell: Vector2i = Vector2i.ZERO
var requested_goal_world: Vector2 = Vector2.ZERO
var requested_goal_cell: Vector2i = Vector2i.ZERO
var dirty: bool = true
var costs := PackedFloat32Array()
var directions := PackedVector2Array()
var max_cost: float = 0.0
var build_in_progress := false
var last_step_work_units := 0
var last_step_completed := false

const INF := 1_000_000.0
const BUILD_PHASE_CLEAR := 0
const BUILD_PHASE_BFS := 1
const BUILD_PHASE_DIRECTIONS := 2
const BUILD_PHASE_CLEARANCE := 3

var _build_costs := PackedFloat32Array()
var _build_directions := PackedVector2Array()
var _build_goal_world := Vector2.ZERO
var _build_goal_cell := Vector2i.ZERO
var _build_max_cost := 0.0
var _build_queue := PackedInt32Array()
var _build_head := 0
var _build_scan_index := 0
var _build_phase := BUILD_PHASE_CLEAR


func configure(p_grid: AgentGrid) -> void:
	grid = p_grid
	costs = PackedFloat32Array()
	directions = PackedVector2Array()
	costs.resize(grid.size.x * grid.size.y)
	directions.resize(grid.size.x * grid.size.y)
	_build_costs.resize(grid.size.x * grid.size.y)
	_build_directions.resize(grid.size.x * grid.size.y)
	set_goal_world(grid.cell_to_world_center(Vector2i(grid.size.x / 2, grid.size.y / 2)))
	rebuild()


func set_goal_world(p_goal_world: Vector2) -> void:
	if grid == null:
		requested_goal_world = p_goal_world
		requested_goal_cell = Vector2i.ZERO
		dirty = true
		return

	var clamped_world := grid.clamp_world_to_walkable(p_goal_world)
	var next_goal_cell: Vector2i = grid.nearest_walkable_cell(grid.world_to_cell(clamped_world))
	requested_goal_cell = next_goal_cell
	requested_goal_world = grid.cell_to_world_center(requested_goal_cell)

	if requested_goal_cell != goal_cell:
		dirty = true
		if build_in_progress and requested_goal_cell != _build_goal_cell:
			build_in_progress = false


func get_direction_for_world_position(world_position: Vector2) -> Vector2:
	var cell: Vector2i = grid.nearest_walkable_cell(grid.world_to_cell(world_position))
	var direction: Vector2 = directions[grid.cell_index(cell)]
	if direction.length_squared() > 0.001:
		return direction

	var to_goal := goal_world - world_position
	if to_goal.length_squared() <= 0.001:
		return Vector2.ZERO
	return to_goal.normalized()


func get_direction_fast(world_position: Vector2) -> Vector2:
	# directions[] is filled for navigable AND clearance-band cells, so this is a
	# single O(1) lookup -- no nearest-walkable spiral on the per-agent hot path.
	var index: int = grid.cell_index(grid.world_to_cell_fast(world_position))
	var direction: Vector2 = directions[index]
	if direction.length_squared() > 0.001:
		return direction

	var to_goal := goal_world - world_position
	if to_goal.length_squared() <= 0.001:
		return Vector2.ZERO
	return to_goal.normalized()


func build_path_from_world(world_position: Vector2, max_steps: int = 96) -> PackedVector2Array:
	var points := PackedVector2Array()
	var cell: Vector2i = grid.nearest_walkable_cell(grid.world_to_cell(world_position))
	var cell_index: int = grid.cell_index(cell)

	for _step in range(max_steps):
		points.append(grid.cell_center_from_index(cell_index))
		if cell_index == grid.cell_index(goal_cell):
			break

		var next_index := _best_neighbor_toward_goal_index(cell_index)
		if next_index == cell_index:
			break
		cell_index = next_index

	return points


func rebuild() -> void:
	if grid == null:
		return

	_begin_rebuild()
	while dirty:
		step_rebuild(costs.size() * 4)


func step_rebuild(work_budget: int) -> bool:
	last_step_work_units = 0
	last_step_completed = false
	if grid == null or not dirty:
		return false
	if work_budget <= 0:
		return false
	if not build_in_progress:
		_begin_rebuild()

	var budget := work_budget
	while budget > 0 and build_in_progress:
		match _build_phase:
			BUILD_PHASE_CLEAR:
				budget = _step_clear_phase(budget)
			BUILD_PHASE_BFS:
				budget = _step_bfs_phase(budget)
			BUILD_PHASE_DIRECTIONS:
				budget = _step_directions_phase(budget)
			BUILD_PHASE_CLEARANCE:
				budget = _step_clearance_phase(budget)
			_:
				_commit_rebuild()

	return last_step_completed


func _begin_rebuild() -> void:
	if grid == null:
		return

	var total := grid.size.x * grid.size.y
	if costs.size() != total:
		costs.resize(total)
	if directions.size() != total:
		directions.resize(total)
	if _build_costs.size() != total:
		_build_costs.resize(total)
	if _build_directions.size() != total:
		_build_directions.resize(total)

	_build_goal_cell = grid.nearest_walkable_cell(requested_goal_cell)
	_build_goal_world = grid.cell_to_world_center(_build_goal_cell)
	_build_max_cost = 0.0
	_build_queue = PackedInt32Array()
	_build_head = 0
	_build_scan_index = 0
	_build_phase = BUILD_PHASE_CLEAR
	build_in_progress = true
	dirty = true


func _step_clear_phase(budget: int) -> int:
	var total := _build_costs.size()
	while budget > 0 and _build_scan_index < total:
		_build_costs[_build_scan_index] = INF
		_build_directions[_build_scan_index] = Vector2.ZERO
		_build_scan_index += 1
		budget -= 1
		last_step_work_units += 1

	if _build_scan_index >= total:
		var goal_index: int = grid.cell_index(_build_goal_cell)
		_build_queue = PackedInt32Array([goal_index])
		_build_head = 0
		_build_costs[goal_index] = 0.0
		_build_scan_index = 0
		_build_phase = BUILD_PHASE_BFS

	return budget


func _step_bfs_phase(budget: int) -> int:
	while budget > 0 and _build_head < _build_queue.size():
		var current_index: int = _build_queue[_build_head]
		_build_head += 1
		var current_cost: float = _build_costs[current_index]
		var neighbors: PackedInt32Array = grid.get_walkable_neighbor_indices(current_index)
		var neighbor_costs: PackedFloat32Array = grid.get_walkable_neighbor_costs(current_index)

		for neighbor_offset in range(neighbors.size()):
			var next_index: int = neighbors[neighbor_offset]
			var step_cost: float = neighbor_costs[neighbor_offset]
			var next_cost := current_cost + step_cost

			if next_cost < _build_costs[next_index]:
				_build_costs[next_index] = next_cost
				_build_max_cost = maxf(_build_max_cost, next_cost)
				_build_queue.append(next_index)

		budget -= 1
		last_step_work_units += 1

	if _build_head >= _build_queue.size():
		_build_scan_index = 0
		_build_phase = BUILD_PHASE_DIRECTIONS

	return budget


func _step_directions_phase(budget: int) -> int:
	var total := _build_costs.size()
	var goal_index := grid.cell_index(_build_goal_cell)
	while budget > 0 and _build_scan_index < total:
		var index := _build_scan_index
		_build_scan_index += 1
		budget -= 1
		last_step_work_units += 1

		if not grid.is_cell_index_walkable(index) or index == goal_index:
			continue

		var best_index := _best_build_neighbor_toward_goal_index(index)
		if best_index != index:
			var from_world: Vector2 = grid.cell_center_from_index(index)
			var to_world: Vector2 = grid.cell_center_from_index(best_index)
			_build_directions[index] = (to_world - from_world).normalized()

	if _build_scan_index >= total:
		_build_scan_index = 0
		_build_phase = BUILD_PHASE_CLEARANCE

	return budget


# Clearance band = nav-blocked cells that are not visual walls (the inflated
# 1-cell ring around obstacles). Agents drift into it, so give each such cell the
# flow of its lowest-cost navigable neighbour. Lets get_direction_fast() stay O(1)
# instead of running a nearest-walkable spiral for ~20% of agents every frame.
func _step_clearance_phase(budget: int) -> int:
	var total := _build_costs.size()
	while budget > 0 and _build_scan_index < total:
		var index := _build_scan_index
		_build_scan_index += 1
		budget -= 1
		last_step_work_units += 1

		if not grid.is_navigation_clearance_index(index):
			continue

		var cell: Vector2i = grid.index_to_cell(index)
		var best_cost := INF
		var best_dir := Vector2.ZERO
		for offset in AgentGrid.ALL_NEIGHBORS:
			var neighbor: Vector2i = cell + offset
			if not grid.is_cell_inside(neighbor):
				continue
			var neighbor_index: int = grid.cell_index(neighbor)
			if not grid.is_cell_index_walkable(neighbor_index):
				continue
			if _build_costs[neighbor_index] < best_cost:
				best_cost = _build_costs[neighbor_index]
				best_dir = (grid.cell_center_from_index(neighbor_index) - grid.cell_center_from_index(index)).normalized()

		_build_directions[index] = best_dir

	if _build_scan_index >= total:
		_commit_rebuild()

	return budget


func _commit_rebuild() -> void:
	var previous_costs := costs
	var previous_directions := directions
	costs = _build_costs
	directions = _build_directions
	_build_costs = previous_costs
	_build_directions = previous_directions

	goal_cell = _build_goal_cell
	goal_world = _build_goal_world
	max_cost = _build_max_cost
	build_in_progress = false
	dirty = requested_goal_cell != goal_cell
	last_step_completed = true


func _best_neighbor_toward_goal_index(index: int) -> int:
	if not grid.is_cell_index_walkable(index):
		return index

	var best_index := index
	var best_cost: float = costs[index]
	var neighbors: PackedInt32Array = grid.get_walkable_neighbor_indices(index)

	for next_index in neighbors:
		var next_cost: float = costs[next_index]
		if next_cost < best_cost:
			best_cost = next_cost
			best_index = next_index

	return best_index


func _best_build_neighbor_toward_goal_index(index: int) -> int:
	if not grid.is_cell_index_walkable(index):
		return index

	var best_index := index
	var best_cost: float = _build_costs[index]
	var neighbors: PackedInt32Array = grid.get_walkable_neighbor_indices(index)

	for next_index in neighbors:
		var next_cost: float = _build_costs[next_index]
		if next_cost < best_cost:
			best_cost = next_cost
			best_index = next_index

	return best_index
