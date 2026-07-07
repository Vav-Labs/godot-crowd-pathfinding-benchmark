class_name AgentScheduler
extends RefCounted

enum Mode {
	DEMO,
	BENCHMARK,
}

enum WorkMode {
	NAIVE,
	SCHEDULED,
}

var mode: Mode = Mode.DEMO
var work_mode: WorkMode = WorkMode.SCHEDULED
var frame_index: int = 0
var benchmark_goal_interval_frames: int = 180
var scripted_goal_index: int = 0
var scripted_goal_cells: Array[Vector2i] = [
	Vector2i(12, 10),
	Vector2i(67, 10),
	Vector2i(67, 34),
	Vector2i(12, 34),
	Vector2i(40, 22),
]


func set_mode(next_mode: Mode) -> void:
	mode = next_mode
	frame_index = 0
	scripted_goal_index = 0


func toggle_mode() -> void:
	if mode == Mode.DEMO:
		set_mode(Mode.BENCHMARK)
	else:
		set_mode(Mode.DEMO)


func set_work_mode(next_work_mode: WorkMode) -> void:
	work_mode = next_work_mode


func toggle_work_mode() -> void:
	if work_mode == WorkMode.NAIVE:
		set_work_mode(WorkMode.SCHEDULED)
	else:
		set_work_mode(WorkMode.NAIVE)


func mode_label() -> String:
	if mode == Mode.BENCHMARK:
		return "benchmark"
	return "demo"


func work_mode_label() -> String:
	if work_mode == WorkMode.NAIVE:
		return "naive"
	return "scheduled"


func is_benchmark() -> bool:
	return mode == Mode.BENCHMARK


func is_naive() -> bool:
	return work_mode == WorkMode.NAIVE


func current_benchmark_goal(grid) -> Vector2:
	return grid.cell_to_world_center(scripted_goal_cells[scripted_goal_index])


func advance_benchmark_goal(grid) -> Vector2:
	if frame_index > 0 and frame_index % benchmark_goal_interval_frames == 0:
		scripted_goal_index = (scripted_goal_index + 1) % scripted_goal_cells.size()

	frame_index += 1
	return current_benchmark_goal(grid)
