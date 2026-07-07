extends SceneTree

const AgentGridScript := preload("res://scripts/shared/grid.gd")
const AgentSetScript := preload("res://scripts/shared/agent_set.gd")
const SharedFieldScript := preload("res://scripts/shared/shared_field.gd")

const GRID_SIZE := Vector2i(80, 45)
const CELL_SIZE := 16.0
const SEED := 1234
const SMOKE_SCHEDULED_AGENTS := 1000
const SMOKE_NAIVE_AGENTS := 50


func _init() -> void:
	var grid = AgentGridScript.new(GRID_SIZE, CELL_SIZE, Vector2.ZERO)
	var field = SharedFieldScript.new()
	var agents = AgentSetScript.new()

	field.call("configure", grid)
	field.call("set_goal_world", grid.call("cell_to_world_center", Vector2i(40, 22)))
	field.call("rebuild")

	agents.call("reset", SMOKE_SCHEDULED_AGENTS, grid, SEED)
	for frame in range(3):
		agents.call("advance_scheduled", field, 1.0 / 60.0, float(frame) / 60.0)

	agents.call("reset", SMOKE_NAIVE_AGENTS, grid, SEED)
	var naive_queries := 0
	for _frame in range(1):
		naive_queries = agents.call("advance_naive", field.get("goal_world"), grid, 1.0 / 60.0)

	print("M1 smoke ok: scheduled_agents=%d naive_agents=%d naive_queries=%d" % [
		SMOKE_SCHEDULED_AGENTS,
		SMOKE_NAIVE_AGENTS,
		naive_queries,
	])
	quit(0)
