class_name AgentSet
extends RefCounted

const AGENT_DEFINITION := "Agent = moving unit with its own position, advanced every physics frame, following a path/field toward a shared goal. This is not a sprite-only visualization."

var count: int = 0
var positions := PackedVector2Array()
var velocities := PackedVector2Array()
var phases := PackedFloat32Array()
var naive_targets := PackedVector2Array()
var naive_target_valid := PackedByteArray()
var radius: float = DEFAULT_RADIUS
var speed: float = 54.0
var naive_cursor: int = 0
var last_queries: int = 0

const SWAY_AGENT_LIMIT := 1000
const TARGET_REACHED_DISTANCE_SQ := 4.0
const DEFAULT_RADIUS := 2.6
const AGENT_SLOW_COLOR := Color(1.00, 0.76, 0.29, 0.66)
const AGENT_CRUISE_COLOR := Color(1.00, 0.57, 0.25, 0.84)
const AGENT_FAST_COLOR := Color(1.00, 0.42, 0.24, 0.98)


func reset(agent_count: int, grid, seed: int) -> void:
	count = agent_count
	positions = PackedVector2Array()
	velocities = PackedVector2Array()
	phases = PackedFloat32Array()
	positions.resize(count)
	velocities.resize(count)
	phases.resize(count)
	naive_targets.resize(count)
	naive_target_valid.resize(count)
	naive_target_valid.fill(0)
	naive_cursor = 0
	last_queries = 0

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	for i in range(count):
		var cell := _random_walkable_cell(grid, rng)
		var jitter: Vector2 = Vector2(
			rng.randf_range(-0.35, 0.35),
			rng.randf_range(-0.35, 0.35)
		) * grid.cell_size
		positions[i] = grid.cell_to_world_center(cell) + jitter
		velocities[i] = Vector2.ZERO
		phases[i] = rng.randf() * TAU


func clear_naive_targets() -> void:
	naive_target_valid.fill(0)


# Naive baseline: every agent runs a full path query toward the goal every
# physics frame. This is the thesis "before" -- the frame spike we measure.
#
# query_cap <= 0  -> LOCKED honest baseline (headless/native measurement). Every
#                    agent queries every frame, so queries/frame == count. No
#                    budget, cache or fallback -- the measured spike stays honest.
# query_cap  > 0  -> DEMO web stress guard only. Still naive (full per-agent A*),
#                    but only `query_cap` agents re-query per frame on a rotating
#                    cursor; the rest follow their last naive target. Disclosed in
#                    the Debug panel and never used for measurement.
func advance_naive(goal_world: Vector2, grid: AgentGrid, delta: float, query_cap: int = 0) -> int:
	var goal_cell: Vector2i = grid.nearest_walkable_cell(grid.world_to_cell_fast(goal_world))
	last_queries = 0

	if query_cap <= 0:
		for i in range(count):
			_advance_toward(i, _naive_query_target(i, goal_world, goal_cell, grid), delta)
		return last_queries

	var budget := mini(query_cap, count)
	for step_index in range(count):
		var agent_index := (naive_cursor + step_index) % count
		var target_world: Vector2
		if step_index < budget:
			target_world = _naive_query_target(agent_index, goal_world, goal_cell, grid)
			naive_targets[agent_index] = target_world
			naive_target_valid[agent_index] = 1
		elif naive_target_valid[agent_index] == 1:
			target_world = naive_targets[agent_index]
		else:
			target_world = positions[agent_index]

		_advance_toward(agent_index, target_world, delta)

	naive_cursor = (naive_cursor + budget) % maxi(count, 1)
	return last_queries


func _naive_query_target(index: int, goal_world: Vector2, goal_cell: Vector2i, grid: AgentGrid) -> Vector2:
	var position := positions[index]
	var start_cell: Vector2i = grid.world_to_cell_fast(position)
	if not grid.is_cell_walkable(start_cell):
		start_cell = grid.nearest_walkable_cell(start_cell)

	var path: Array = grid.find_path_cells_walkable(start_cell, goal_cell)
	last_queries += 1

	if path.size() > 1:
		return grid.cell_to_world_center(path[1])
	return goal_world


func advance_scheduled(field: SharedField, delta: float, elapsed_seconds: float) -> int:
	last_queries = 0
	var step_distance := speed * delta
	var use_sway := count <= SWAY_AGENT_LIMIT
	var grid: AgentGrid = field.grid
	var directions := field.directions
	var width := grid.size.x
	var height := grid.size.y
	var inv_cell_size := 1.0 / grid.cell_size
	var origin := grid.origin
	var goal_world := field.goal_world

	for i in range(count):
		var position := positions[i]
		var cell_x := clampi(floori((position.x - origin.x) * inv_cell_size), 0, width - 1)
		var cell_y := clampi(floori((position.y - origin.y) * inv_cell_size), 0, height - 1)
		var direction: Vector2 = directions[cell_y * width + cell_x]
		if direction.length_squared() <= 0.001:
			var to_goal := goal_world - position
			if to_goal.length_squared() > 0.001:
				direction = to_goal.normalized()
			else:
				velocities[i] = Vector2.ZERO
				continue

		if direction.length_squared() <= 0.001:
			velocities[i] = Vector2.ZERO
			continue

		if use_sway:
			var side := Vector2(-direction.y, direction.x) * sin(elapsed_seconds * 1.6 + phases[i]) * 0.16
			direction = (direction + side).normalized()

		velocities[i] = direction * speed
		positions[i] = position + direction * step_distance

	return last_queries


func get_position(index: int) -> Vector2:
	return positions[index]


func get_sample_indices(sample_count: int) -> Array[int]:
	var result: Array[int] = []
	if count == 0:
		return result

	var stride := maxi(count / sample_count, 1)
	for i in range(0, count, stride):
		result.append(i)
		if result.size() >= sample_count:
			break

	return result


# Writes every agent into a MultiMesh as a single batched draw call (one draw
# call for the whole crowd). True positions only -- no settled spread.
func sync_to_multimesh(mm: MultiMesh, update_colors: bool = false) -> void:
	var initialize := mm.instance_count != count
	if initialize:
		mm.instance_count = count

	if update_colors or initialize:
		var inv_speed := 1.0 / speed if speed > 0.0 else 0.0
		for i in range(count):
			mm.set_instance_transform_2d(i, Transform2D(0.0, positions[i]))
			var velocity_factor := clampf(velocities[i].length() * inv_speed, 0.0, 1.0)
			mm.set_instance_color(i, _agent_color_for_velocity(velocity_factor))
	else:
		for i in range(count):
			mm.set_instance_transform_2d(i, Transform2D(0.0, positions[i]))


# Bins agent positions into a coarse density grid for the glow underlay used at
# high counts. Caller clears out_counts first; returns the peak cell count.
func accumulate_density(grid: AgentGrid, out_counts: PackedFloat32Array) -> float:
	var max_count := 0.0
	for i in range(count):
		var index := grid.cell_index(grid.world_to_cell_fast(positions[i]))
		var value := out_counts[index] + 1.0
		out_counts[index] = value
		if value > max_count:
			max_count = value

	return max_count


func _advance_toward(index: int, target_world: Vector2, delta: float) -> void:
	var to_target := target_world - positions[index]
	var distance_sq := to_target.length_squared()

	if distance_sq <= TARGET_REACHED_DISTANCE_SQ:
		velocities[index] = Vector2.ZERO
		return

	var step := minf(speed * delta, sqrt(distance_sq))
	var direction := to_target.normalized()
	velocities[index] = direction * speed
	positions[index] += direction * step


func _agent_color_for_velocity(velocity_factor: float) -> Color:
	if velocity_factor < 0.45:
		return AGENT_SLOW_COLOR.lerp(AGENT_CRUISE_COLOR, velocity_factor / 0.45)

	return AGENT_CRUISE_COLOR.lerp(AGENT_FAST_COLOR, (velocity_factor - 0.45) / 0.55)


func _random_walkable_cell(grid, rng: RandomNumberGenerator) -> Vector2i:
	for _attempt in range(128):
		var cell := Vector2i(
			rng.randi_range(2, grid.size.x - 3),
			rng.randi_range(2, grid.size.y - 3)
		)
		if grid.is_cell_walkable(cell):
			return cell

	return Vector2i(2, 2)
