extends SceneTree

const AgentGridScript := preload("res://scripts/shared/grid.gd")
const AgentSetScript := preload("res://scripts/shared/agent_set.gd")
const SharedFieldScript := preload("res://scripts/shared/shared_field.gd")

const ARTICLE_SLUG := "moving-10000-agents-in-godot"
const OUTPUT_PATH := "res://dist/%s-benchmark.json" % ARTICLE_SLUG
const QUICK_OUTPUT_PATH := "res://dist/%s-benchmark-quick.json" % ARTICLE_SLUG
const MEASUREMENT_SCOPE_TEMPLATE := "%d moving agents, shared goal, naive vs scheduled. Deterministic native benchmark run, no input. Not a product-wide claim."
const MODE_NAIVE := "naive"
const MODE_SCHEDULED := "scheduled"
const FRAME_BUDGET_MS := 16.6
const PHYSICS_FPS := 60
const DELTA := 1.0 / float(PHYSICS_FPS)

# Scenario knobs (agent_count / grid / seed / goal_interval) are SHARED by both
# modes -- they define the comparison and must match for naive vs scheduled to be
# apples-to-apples. Only measurement knobs (runs / warmup / sample) may differ per
# mode, and naive may use lighter sampling because its per-frame cost is
# near-stationary per goal position. The naive per-frame WORK is never changed.
var _config := {
	"agent_count": 500,
	"grid_size": Vector2i(256, 256),
	"cell_size_px": 16.0,
	"warmup_frames": 120,
	"sample_frames": 1000,
	"runs": 5,
	"seed": 1234,
	"goal_interval_frames": 180,
	"field_step_budget": 1536,
	"output_path": OUTPUT_PATH,
	"mode": "both",
	"naive_runs": 0,
	"naive_warmup": -1,
	"naive_sample": 0,
	"merge_naive_path": "",
}
var _run_profile := "full"
var _output_overridden := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_apply_user_args()
	print("Running %s benchmark (%s)" % [ARTICLE_SLUG, _config_summary()])

	var mode_filter: String = _config["mode"]
	var modes: Array = []

	if mode_filter == MODE_NAIVE or mode_filter == "both":
		modes.append(_run_mode(MODE_NAIVE))
	if mode_filter == MODE_SCHEDULED or mode_filter == "both":
		modes.append(_run_mode(MODE_SCHEDULED))

	# Freeze-and-iterate workflow: re-run only the (cheap) scheduled mode while
	# merging the previously measured, locked naive mode into a complete dataset.
	if mode_filter == MODE_SCHEDULED and str(_config["merge_naive_path"]) != "":
		var frozen := _load_frozen_naive(str(_config["merge_naive_path"]))
		if not frozen.is_empty():
			modes.push_front(frozen)

	var payload := _build_payload(modes)
	_write_json(payload)
	quit(0)


func _apply_user_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--quick":
			_run_profile = "quick"
			_config["warmup_frames"] = 30
			_config["sample_frames"] = 120
			_config["runs"] = 1
		elif arg.begins_with("--runs="):
			_config["runs"] = maxi(1, arg.get_slice("=", 1).to_int())
		elif arg.begins_with("--warmup="):
			_config["warmup_frames"] = maxi(0, arg.get_slice("=", 1).to_int())
		elif arg.begins_with("--sample="):
			_config["sample_frames"] = maxi(1, arg.get_slice("=", 1).to_int())
		elif arg.begins_with("--agents="):
			_config["agent_count"] = maxi(1, arg.get_slice("=", 1).to_int())
		elif arg.begins_with("--field-budget="):
			_config["field_step_budget"] = maxi(1, arg.get_slice("=", 1).to_int())
		elif arg.begins_with("--goal-interval="):
			_config["goal_interval_frames"] = maxi(1, arg.get_slice("=", 1).to_int())
		elif arg.begins_with("--grid="):
			_config["grid_size"] = _parse_grid_size(arg.get_slice("=", 1), _config["grid_size"])
		elif arg.begins_with("--mode="):
			var requested := arg.get_slice("=", 1).to_lower()
			if requested == MODE_NAIVE or requested == MODE_SCHEDULED or requested == "both":
				_config["mode"] = requested
		elif arg.begins_with("--naive-runs="):
			_config["naive_runs"] = maxi(1, arg.get_slice("=", 1).to_int())
		elif arg.begins_with("--naive-warmup="):
			_config["naive_warmup"] = maxi(0, arg.get_slice("=", 1).to_int())
		elif arg.begins_with("--naive-sample="):
			_config["naive_sample"] = maxi(1, arg.get_slice("=", 1).to_int())
		elif arg.begins_with("--merge-naive="):
			_config["merge_naive_path"] = arg.get_slice("=", 1)
		elif arg.begins_with("--output="):
			_config["output_path"] = arg.get_slice("=", 1)
			_output_overridden = true

	if _output_overridden:
		return
	if _run_profile == "quick":
		_config["output_path"] = QUICK_OUTPUT_PATH
	elif _config["mode"] != "both":
		# Single-mode iteration writes to a mode-suffixed file so it never
		# clobbers the canonical two-mode dataset by accident.
		_config["output_path"] = "res://dist/%s-benchmark-%s.json" % [ARTICLE_SLUG, _config["mode"]]


func _parse_grid_size(value: String, fallback: Vector2i) -> Vector2i:
	var parts := value.to_lower().split("x")
	if parts.size() != 2:
		return fallback
	var width := parts[0].to_int()
	var height := parts[1].to_int()
	if width < 8 or height < 8:
		return fallback
	return Vector2i(width, height)


func _effective_runs(mode_name: String) -> int:
	if mode_name == MODE_NAIVE and int(_config["naive_runs"]) > 0:
		return int(_config["naive_runs"])
	return int(_config["runs"])


func _effective_warmup(mode_name: String) -> int:
	if mode_name == MODE_NAIVE and int(_config["naive_warmup"]) >= 0:
		return int(_config["naive_warmup"])
	return int(_config["warmup_frames"])


func _effective_sample(mode_name: String) -> int:
	if mode_name == MODE_NAIVE and int(_config["naive_sample"]) > 0:
		return int(_config["naive_sample"])
	return int(_config["sample_frames"])


func _run_mode(mode_name: String) -> Dictionary:
	var runs := _effective_runs(mode_name)
	var warmup := _effective_warmup(mode_name)
	var sample := _effective_sample(mode_name)
	var run_results: Array[Dictionary] = []
	for run_index in range(runs):
		var result := _run_mode_once(mode_name, run_index, warmup, sample)
		run_results.append(result)
		print(
			"%s run %d/%d: median %.3f ms, p99 %.3f ms, max %.3f ms, queries/frame %.1f" % [
				mode_name,
				run_index + 1,
				runs,
				result["frame_time_ms"]["median"],
				result["frame_time_ms"]["p99"],
				result["frame_time_ms"]["max"],
				result["queries_per_frame_avg"],
			]
		)

	return _aggregate_mode(mode_name, run_results, warmup, sample)


func _run_mode_once(mode_name: String, run_index: int, warmup_frames: int, sample_frames: int) -> Dictionary:
	var grid = AgentGridScript.new(
		_config["grid_size"],
		float(_config["cell_size_px"]),
		Vector2.ZERO,
		AgentSetScript.DEFAULT_RADIUS
	)
	var agents = AgentSetScript.new()
	var field = SharedFieldScript.new()
	var seed: int = int(_config["seed"]) + run_index
	agents.call("reset", int(_config["agent_count"]), grid, seed)

	var scheduled := mode_name == MODE_SCHEDULED
	var last_goal_cell := Vector2i(-1, -1)
	var field_rebuilds := 0
	if scheduled:
		field.call("configure", grid)

	var frame_times: Array[float] = []
	var steady_times: Array[float] = []
	var rebuild_times: Array[float] = []
	var build_latency_frames: Array[int] = []
	var build_latency_ms: Array[float] = []
	var query_counts: Array[int] = []
	var frames_over_budget := 0
	var steady_over_budget := 0
	var total_queries := 0
	var total_frames := warmup_frames + sample_frames
	var pending_build_start_frame := -1
	var pending_build_counted := false

	for frame_index in range(total_frames):
		var goal_cell := _goal_cell_for_frame(grid, frame_index)
		var goal_world: Vector2 = grid.call("cell_to_world_center", goal_cell)
		var did_rebuild := false
		var start_usec := Time.get_ticks_usec()
		var queries := 0

		if scheduled:
			if goal_cell != last_goal_cell:
				field.call("set_goal_world", goal_world)
				field_rebuilds += 1
				last_goal_cell = goal_cell
				pending_build_start_frame = frame_index
				pending_build_counted = frame_index >= warmup_frames
			if bool(field.get("dirty")):
				field.call("step_rebuild", int(_config["field_step_budget"]))
				did_rebuild = int(field.get("last_step_work_units")) > 0
				if bool(field.get("last_step_completed")):
					_record_build_latency(
						build_latency_frames,
						build_latency_ms,
						pending_build_start_frame,
						frame_index,
						pending_build_counted
					)
					pending_build_start_frame = -1
					pending_build_counted = false
			queries = agents.call("advance_scheduled", field, DELTA, float(frame_index) * DELTA)
		else:
			queries = agents.call("advance_naive", goal_world, grid, DELTA)

		var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
		if frame_index >= warmup_frames:
			frame_times.append(elapsed_ms)
			query_counts.append(queries)
			total_queries += queries
			if elapsed_ms > FRAME_BUDGET_MS:
				frames_over_budget += 1
			# Localize spikes: separate the goal-change (field rebuild) frames from
			# the steady frames so the dataset honestly shows whether the
			# steady-state is flat and where the over-budget frames live.
			if did_rebuild:
				rebuild_times.append(elapsed_ms)
			else:
				steady_times.append(elapsed_ms)
				if elapsed_ms > FRAME_BUDGET_MS:
					steady_over_budget += 1

	if scheduled and bool(field.get("dirty")) and pending_build_counted:
		var tail_frame := total_frames
		while bool(field.get("dirty")):
			field.call("step_rebuild", int(_config["field_step_budget"]))
			agents.call("advance_scheduled", field, DELTA, float(tail_frame) * DELTA)
			if bool(field.get("last_step_completed")):
				_record_build_latency(
					build_latency_frames,
					build_latency_ms,
					pending_build_start_frame,
					tail_frame,
					true
				)
				break
			tail_frame += 1

	var measured := frame_times.size()
	var steady_measured := maxi(steady_times.size(), 1)
	return {
		"run_index": run_index,
		"seed": seed,
		"frame_time_ms": _frame_stats(frame_times),
		"steady_frame_time_ms": _frame_stats(steady_times) if steady_times.size() > 0 else {},
		"frames_over_budget_pct": 100.0 * float(frames_over_budget) / float(measured),
		"steady_frames_over_budget_pct": 100.0 * float(steady_over_budget) / float(steady_measured),
		"rebuild_frames": rebuild_times.size(),
		"rebuild_cost_ms": _rebuild_cost(rebuild_times),
		"build_completion_latency_frames": _int_stats(build_latency_frames),
		"build_completion_latency_ms": _frame_stats(build_latency_ms) if not build_latency_ms.is_empty() else {},
		"build_completion_samples": build_latency_frames.size(),
		"queries_per_frame_avg": float(total_queries) / float(measured),
		"total_queries": total_queries,
		"field_rebuilds": field_rebuilds if scheduled else 0,
		"sample_frames": measured,
		"query_samples": _query_stats(query_counts),
	}


func _record_build_latency(
		latency_frames: Array[int],
		latency_ms: Array[float],
		start_frame: int,
		completed_frame: int,
		count_sample: bool) -> void:
	if not count_sample or start_frame < 0:
		return

	var frame_count := completed_frame - start_frame + 1
	latency_frames.append(frame_count)
	latency_ms.append(float(frame_count) * DELTA * 1000.0)


func _rebuild_cost(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	return {
		"median": _percentile(sorted, 0.50),
		"max": sorted[sorted.size() - 1],
	}


func _goal_cell_for_frame(grid, frame_index: int) -> Vector2i:
	var goals: Array = grid.call("default_benchmark_goal_cells")
	var interval := maxi(1, int(_config["goal_interval_frames"]))
	var goal_index: int = int(floor(float(frame_index) / float(interval))) % goals.size()
	return grid.call("nearest_walkable_cell", goals[goal_index])


func _frame_stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	return {
		"median": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95),
		"p99": _percentile(sorted, 0.99),
		"max": sorted[sorted.size() - 1],
	}


func _query_stats(values: Array[int]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	return {
		"median": _percentile_int(sorted, 0.50),
		"max": sorted[sorted.size() - 1],
	}


func _int_stats(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	return {
		"median": _percentile_int(sorted, 0.50),
		"p95": _percentile_int(sorted, 0.95),
		"p99": _percentile_int(sorted, 0.99),
		"max": sorted[sorted.size() - 1],
	}


func _percentile(sorted_values: Array[float], percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(roundi(float(sorted_values.size() - 1) * percentile), 0, sorted_values.size() - 1)
	return sorted_values[index]


func _percentile_int(sorted_values: Array[int], percentile: float) -> int:
	if sorted_values.is_empty():
		return 0
	var index := clampi(roundi(float(sorted_values.size() - 1) * percentile), 0, sorted_values.size() - 1)
	return sorted_values[index]


func _aggregate_mode(mode_name: String, run_results: Array[Dictionary], warmup_frames: int, sample_frames: int) -> Dictionary:
	return {
		"mode": mode_name,
		"description": _mode_description(mode_name),
		"sampling": {
			"runs": run_results.size(),
			"warmup_frames": warmup_frames,
			"sample_frames": sample_frames,
		},
		"frame_time_ms": {
			"median": _median_run_metric(run_results, "frame_time_ms", "median"),
			"p95": _median_run_metric(run_results, "frame_time_ms", "p95"),
			"p99": _median_run_metric(run_results, "frame_time_ms", "p99"),
			"max": _median_run_metric(run_results, "frame_time_ms", "max"),
		},
		"steady_frame_time_ms": {
			"median": _median_run_metric(run_results, "steady_frame_time_ms", "median"),
			"p95": _median_run_metric(run_results, "steady_frame_time_ms", "p95"),
			"p99": _median_run_metric(run_results, "steady_frame_time_ms", "p99"),
			"max": _median_run_metric(run_results, "steady_frame_time_ms", "max"),
		},
		"frames_over_budget_pct": _median_scalar(run_results, "frames_over_budget_pct"),
		"steady_frames_over_budget_pct": _median_scalar(run_results, "steady_frames_over_budget_pct"),
		"rebuild_frames_median_run": int(round(_median_scalar(run_results, "rebuild_frames"))),
		"rebuild_cost_ms_median_run": _median_rebuild_cost(run_results),
		"build_completion_latency_frames": _median_optional_metric(run_results, "build_completion_latency_frames"),
		"build_completion_latency_ms": _median_optional_metric(run_results, "build_completion_latency_ms"),
		"build_completion_samples_median_run": int(round(_median_scalar(run_results, "build_completion_samples"))),
		"queries_per_frame_avg": _median_scalar(run_results, "queries_per_frame_avg"),
		"total_queries_median_run": int(round(_median_scalar(run_results, "total_queries"))),
		"field_rebuilds_median_run": int(round(_median_scalar(run_results, "field_rebuilds"))),
		"runs": run_results,
	}


func _median_rebuild_cost(run_results: Array[Dictionary]) -> Dictionary:
	var medians: Array[float] = []
	var maxes: Array[float] = []
	for result in run_results:
		var cost: Variant = result.get("rebuild_cost_ms", {})
		if cost is Dictionary and (cost as Dictionary).has("median"):
			medians.append(float(cost["median"]))
			maxes.append(float(cost["max"]))
	if medians.is_empty():
		return {}
	medians.sort()
	maxes.sort()
	return {
		"median": _percentile(medians, 0.50),
		"max": _percentile(maxes, 0.50),
	}


func _mode_description(mode_name: String) -> String:
	if mode_name == MODE_NAIVE:
		return "every agent calls AStarGrid2D.get_id_path() every physics frame"
	return "agents follow one shared flow/Dijkstra field rebuilt only on scripted goal moves"


func _median_run_metric(run_results: Array[Dictionary], group_key: String, metric_key: String) -> float:
	var values: Array[float] = []
	for result in run_results:
		var group: Variant = result.get(group_key, {})
		if group is Dictionary and (group as Dictionary).has(metric_key):
			values.append(float(group[metric_key]))
	values.sort()
	return _percentile(values, 0.50)


func _median_scalar(run_results: Array[Dictionary], key: String) -> float:
	var values: Array[float] = []
	for result in run_results:
		if result.has(key):
			values.append(float(result[key]))
	values.sort()
	return _percentile(values, 0.50)


func _median_optional_metric(run_results: Array[Dictionary], group_key: String) -> Dictionary:
	var keys := ["median", "p95", "p99", "max"]
	var output := {}
	for metric_key in keys:
		var values: Array[float] = []
		for result in run_results:
			var group: Variant = result.get(group_key, {})
			if group is Dictionary and (group as Dictionary).has(metric_key):
				values.append(float(group[metric_key]))
		if not values.is_empty():
			values.sort()
			output[metric_key] = _percentile(values, 0.50)
	return output


# Loads the locked naive mode from a previously generated dataset so scheduled
# iterations can be merged into a complete two-mode dataset without re-measuring
# the slow naive baseline. Records provenance + warns if the frozen naive was
# measured under a different scenario than the current run.
func _load_frozen_naive(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("merge-naive file not found: %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("modes"):
		push_error("merge-naive file is not a valid benchmark dataset: %s" % path)
		return {}

	var naive_mode: Dictionary = {}
	for mode_entry in parsed["modes"]:
		if typeof(mode_entry) == TYPE_DICTIONARY and mode_entry.get("mode", "") == MODE_NAIVE:
			naive_mode = (mode_entry as Dictionary).duplicate(true)
			break

	if naive_mode.is_empty():
		push_error("no naive mode found in %s" % path)
		return {}

	naive_mode["frozen_from"] = {
		"path": ProjectSettings.globalize_path(path),
		"generated_utc": parsed.get("generated_utc", "unknown"),
	}

	# naive never rebuilds the field, so its steady-state == overall. Backfill the
	# split fields when the frozen dataset predates them, so the merged dataset is
	# schema-consistent across both modes.
	if not naive_mode.has("steady_frame_time_ms") and naive_mode.has("frame_time_ms"):
		naive_mode["steady_frame_time_ms"] = (naive_mode["frame_time_ms"] as Dictionary).duplicate(true)
		naive_mode["steady_frames_over_budget_pct"] = naive_mode.get("frames_over_budget_pct", 0.0)
		naive_mode["rebuild_frames_median_run"] = 0
		naive_mode["rebuild_cost_ms_median_run"] = {}
		naive_mode["build_completion_latency_frames"] = {}
		naive_mode["build_completion_latency_ms"] = {}
		naive_mode["build_completion_samples_median_run"] = 0

	var warning := _scenario_mismatch_warning(parsed.get("config", {}))
	if warning != "":
		naive_mode["merge_warning"] = warning
		push_warning(warning)
		print("WARNING: %s" % warning)

	return naive_mode


func _scenario_mismatch_warning(frozen_config: Dictionary) -> String:
	var grid_size: Vector2i = _config["grid_size"]
	var current_grid := "%dx%d" % [grid_size.x, grid_size.y]
	var mismatches: Array[String] = []
	if int(frozen_config.get("agent_count", -1)) != int(_config["agent_count"]):
		mismatches.append("agent_count")
	if str(frozen_config.get("grid_size", "")) != current_grid:
		mismatches.append("grid_size")
	if int(frozen_config.get("seed", -9999)) != int(_config["seed"]):
		mismatches.append("seed")
	if int(frozen_config.get("cell_size_px", -1)) != int(float(_config["cell_size_px"])):
		mismatches.append("cell_size_px")

	if mismatches.is_empty():
		return ""
	return "Frozen naive scenario differs from current run (%s) -- naive vs scheduled may not be comparable; re-measure naive." % ", ".join(mismatches)


func _build_payload(modes: Array) -> Dictionary:
	var grid_size: Vector2i = _config["grid_size"]
	var version_info := Engine.get_version_info()
	return {
		"article_slug": ARTICLE_SLUG,
		"generated_utc": Time.get_datetime_string_from_system(true),
		"godot_version": version_info.string,
		"os_name": OS.get_name(),
		"processor_name": OS.get_processor_name(),
		"measurement_scope": _measurement_scope(),
		"run_profile": _run_profile,
		"mode_filter": _config["mode"],
		"citation_status": _citation_status(),
		"config": {
			"agent_count": int(_config["agent_count"]),
			"grid_size": "%dx%d" % [grid_size.x, grid_size.y],
			"cell_size_px": float(_config["cell_size_px"]),
			"physics_fps": PHYSICS_FPS,
			"frame_budget_ms": FRAME_BUDGET_MS,
			"warmup_frames": int(_config["warmup_frames"]),
			"sample_frames": int(_config["sample_frames"]),
			"runs": int(_config["runs"]),
			"seed": int(_config["seed"]),
			"field_step_budget": int(_config["field_step_budget"]),
			"goal_schedule": "relocates every %d frames, fixed cells from AgentGrid.default_benchmark_goal_cells()" % int(_config["goal_interval_frames"]),
			"sampling_note": "warmup/sample/runs above are shared defaults; the actual per-mode sampling is recorded in modes[].sampling (naive may run lighter -- its per-frame cost is near-stationary per goal position; its per-frame work is unchanged).",
		},
		"modes": modes,
	}


func _write_json(payload: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("res://dist")
	var path: String = _config["output_path"]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write %s" % path)
		quit(1)
		return

	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("Wrote %s" % ProjectSettings.globalize_path(path))


func _config_summary() -> String:
	var grid_size: Vector2i = _config["grid_size"]
	return "mode %s, %d agents, %dx%d grid, warmup %d, sample %d, runs %d, goal interval %d, field budget %d" % [
		_config["mode"],
		int(_config["agent_count"]),
		grid_size.x,
		grid_size.y,
		int(_config["warmup_frames"]),
		int(_config["sample_frames"]),
		int(_config["runs"]),
		int(_config["goal_interval_frames"]),
		int(_config["field_step_budget"]),
	]


func _measurement_scope() -> String:
	return MEASUREMENT_SCOPE_TEMPLATE % int(_config["agent_count"])


func _citation_status() -> String:
	if _run_profile == "quick":
		return "quick validation run; do not cite as the final article dataset"
	return "full benchmark candidate; cite only after reviewing generated JSON and matching article conditions"
