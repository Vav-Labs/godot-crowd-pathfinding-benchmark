extends SceneTree

const AgentGridScript := preload("res://scripts/shared/grid.gd")
const AgentSetScript := preload("res://scripts/shared/agent_set.gd")
const SharedFieldScript := preload("res://scripts/shared/shared_field.gd")

const GRID_SIZE := Vector2i(80, 45)
const CELL_SIZE := 16.0
const SEED := 1234


func _bench(label: String, agent_count: int, scheduled: bool) -> void:
	var grid = AgentGridScript.new(GRID_SIZE, CELL_SIZE, Vector2.ZERO)
	var field = SharedFieldScript.new()
	var agents = AgentSetScript.new()
	field.call("configure", grid)
	field.call("set_goal_world", grid.call("cell_to_world_center", Vector2i(40, 22)))
	field.call("rebuild")
	agents.call("reset", agent_count, grid, SEED)

	var frames := 120
	var t0 := Time.get_ticks_usec()
	for f in range(frames):
		if scheduled:
			agents.call("advance_scheduled", field, 1.0 / 60.0, float(f) / 60.0)
		else:
			agents.call("advance_naive", field.get("goal_world"), grid, 1.0 / 60.0)
	var t1 := Time.get_ticks_usec()
	var per_frame_ms := float(t1 - t0) / float(frames) / 1000.0
	print("%s: %d agents  -> %.3f ms/frame (logic only)" % [label, agent_count, per_frame_ms])


func _init() -> void:
	_bench("scheduled", 500, true)
	_bench("scheduled", 5000, true)
	_bench("naive    ", 500, false)
	quit(0)
