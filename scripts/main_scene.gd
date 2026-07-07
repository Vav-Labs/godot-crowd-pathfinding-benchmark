extends Node2D

const AgentGridScript := preload("res://scripts/shared/grid.gd")
const AgentSetScript := preload("res://scripts/shared/agent_set.gd")
const SharedFieldScript := preload("res://scripts/shared/shared_field.gd")
const SchedulerScript := preload("res://scripts/shared/scheduler.gd")

const DEFAULT_AGENT_COUNT := 500
const MIN_AGENT_COUNT := 100
# Web slider ceiling capped at 1000: the honest naive vs scheduled contrast stays
# legible and browser-safe in this range. The 5000 stress case is a native
# capture (video + dataset), not the interactive web demo.
const MAX_AGENT_COUNT := 1000
const PATH_SAMPLE_COUNT := 16
# Web UX safety net: above this many agents, in-app Naive caps how many full
# path queries run per frame so the browser never freezes. Disclosed in the
# Debug panel. Headless/native measurement always runs uncapped (query_cap = 0).
const NAIVE_DEMO_GUARD_THRESHOLD := 1000
const NAIVE_DEMO_QUERY_CAP := 128
const PATH_REFRESH_INTERVAL := 0.1
const HUD_REFRESH_INTERVAL := 0.15
const FIELD_REBUILD_INTERVAL := 1.0 / 15.0
const FIELD_REBUILD_WORK_BUDGET := 1536
const AGENT_COLOR_REFRESH_INTERVAL := 1.0 / 12.0
# Above this count, dots keep a fixed colour (no per-instance colour refresh), so
# there is no periodic full-buffer write spike. The density glow carries the
# crowd story instead.
const AGENT_COLOR_MAX_COUNT := 2000
const AGENT_RENDER_SCALE := 4.4
const AGENT_RENDER_SCALE_DENSE := 2.2
# Above this count we add a density flow-field glow underlay and shrink the dots,
# so thousands of overlapping additive sprites stop blowing out web fillrate.
const DENSITY_THRESHOLD := 3000
const DENSITY_REFRESH_INTERVAL := 1.0 / 24.0
const DENSITY_MAX_ALPHA := 0.85
const COLOR_DENSITY_LOW := Color(0.20, 0.62, 0.92)
const COLOR_DENSITY_MID := Color(1.0, 0.74, 0.32)
const COLOR_DENSITY_HIGH := Color(1.0, 0.96, 0.88)
const GOAL_ANIMATION_REFRESH_INTERVAL := 1.0 / 30.0
const GOAL_PULSE_DURATION := 1.2
const GRID_SIZE := Vector2i(80, 45)
const CELL_SIZE := 16.0
const SEED := 1234
const HUD_MARGIN := 12.0
const DEBUG_PANEL_SIZE := Vector2(342.0, 216.0)

const COLOR_VOID := Color(0.02, 0.03, 0.05, 1.0)
const COLOR_FLOOR := Color(0.04, 0.07, 0.11, 1.0)
const COLOR_GRID := Color(0.16, 0.21, 0.27, 0.22)
const COLOR_GRID_MAJOR := Color(0.18, 0.26, 0.34, 0.34)
const COLOR_WORLD_RIM := Color(0.27, 0.34, 0.42, 0.72)
const COLOR_WALL := Color(0.19, 0.25, 0.30, 0.82)
const COLOR_WALL_RIM := Color(0.27, 0.34, 0.42, 0.70)
const COLOR_CLEARANCE := Color(0.36, 0.91, 0.78, 0.18)
const COLOR_FIELD_ARROW := Color(0.62, 0.85, 1.0, 0.20)
const COLOR_PATH := Color(0.62, 0.85, 1.0, 0.26)
const COLOR_GOAL_CORE := Color(1.0, 0.18, 0.42, 0.96)
const COLOR_GOAL_HOT := Color(1.0, 1.0, 1.0, 0.92)
const COLOR_GOAL_RING := Color(1.0, 0.62, 0.77, 0.70)
const COLOR_UI_BASE := Color(0.04, 0.06, 0.09, 0.90)
const COLOR_UI_BASE_HOVER := Color(0.07, 0.10, 0.15, 0.94)
const COLOR_UI_MUTED := Color(0.36, 0.44, 0.53, 0.72)
const COLOR_UI_ICE := Color(0.62, 0.85, 1.0, 0.95)
const COLOR_UI_GOLD := Color(1.0, 0.76, 0.29, 0.95)
const COLOR_UI_MINT := Color(0.36, 0.91, 0.78, 0.95)
const COLOR_UI_PINK := Color(1.0, 0.18, 0.42, 0.95)

@onready var agent_mm: MultiMeshInstance2D = $Agents
@onready var density_sprite: Sprite2D = $AgentDensity
@onready var heatmap_mm: MultiMeshInstance2D = $HeatmapCells
@onready var clearance_mm: MultiMeshInstance2D = $ClearanceCells
@onready var blocked_rim_mm: MultiMeshInstance2D = $BlockedCellRims
@onready var blocked_mm: MultiMeshInstance2D = $BlockedCells
@onready var dynamic_layer: Node2D = $DynamicLayer
@onready var control_panel: PanelContainer = $Hud/ControlPanel
@onready var debug_panel: PanelContainer = $Hud/DebugPanel
@onready var debug_title_label: Label = $Hud/DebugPanel/DebugMargin/VBox/DebugTitleLabel
@onready var debug_status_label: Label = $Hud/DebugPanel/DebugMargin/VBox/DebugStatusLabel
@onready var debug_agents_label: Label = $Hud/DebugPanel/DebugMargin/VBox/DebugAgentsLabel
@onready var debug_grid_label: Label = $Hud/DebugPanel/DebugMargin/VBox/DebugGridLabel
@onready var debug_goal_label: Label = $Hud/DebugPanel/DebugMargin/VBox/DebugGoalLabel
@onready var debug_nav_label: Label = $Hud/DebugPanel/DebugMargin/VBox/DebugNavLabel
@onready var title_label: Label = $Hud/ControlPanel/PanelMargin/VBox/TitleLabel
@onready var agent_label: Label = $Hud/ControlPanel/PanelMargin/VBox/AgentLabel
@onready var agent_slider: HSlider = $Hud/ControlPanel/PanelMargin/VBox/AgentSlider
@onready var naive_button: Button = $Hud/ControlPanel/PanelMargin/VBox/WorkModeRow/NaiveButton
@onready var scheduled_button: Button = $Hud/ControlPanel/PanelMargin/VBox/WorkModeRow/ScheduledButton
@onready var demo_mode_button: Button = $Hud/ControlPanel/PanelMargin/VBox/ScenarioRow/DemoModeButton
@onready var benchmark_mode_button: Button = $Hud/ControlPanel/PanelMargin/VBox/ScenarioRow/BenchmarkModeButton
@onready var reset_button: Button = $Hud/ControlPanel/PanelMargin/VBox/ScenarioRow/ResetButton
@onready var field_button: CheckButton = $Hud/ControlPanel/PanelMargin/VBox/OverlayRow/FieldButton
@onready var paths_button: CheckButton = $Hud/ControlPanel/PanelMargin/VBox/OverlayRow/PathsButton
@onready var blocks_button: CheckButton = $Hud/ControlPanel/PanelMargin/VBox/OverlayRow/BlocksButton
@onready var clearance_button: CheckButton = $Hud/ControlPanel/PanelMargin/VBox/DiagnosticRow/ClearanceButton

var agent_mesh: QuadMesh
var grid: AgentGrid
var agents: AgentSet
var field: SharedField
var scheduler: AgentScheduler
var goal_world := Vector2.ZERO
var agent_count := DEFAULT_AGENT_COUNT
var elapsed_seconds := 0.0
var frame_time_ms := 0.0
var smoothed_frame_time_ms := 0.0
var queries_this_frame := 0
var naive_guard_active := false
var show_field := true
var show_paths := true
var show_blocks := true
var show_clearance := true
var path_refresh_elapsed := PATH_REFRESH_INTERVAL
var hud_refresh_elapsed := HUD_REFRESH_INTERVAL
var field_rebuild_elapsed := FIELD_REBUILD_INTERVAL
var agent_color_refresh_elapsed := AGENT_COLOR_REFRESH_INTERVAL
var density_refresh_elapsed := DENSITY_REFRESH_INTERVAL
var density_active := false
var density_image: Image
var density_texture: ImageTexture
var density_counts := PackedFloat32Array()
var goal_animation_refresh_elapsed := GOAL_ANIMATION_REFRESH_INTERVAL
var goal_pulse_age := GOAL_PULSE_DURATION
var last_pointer_position := Vector2.ZERO
var last_goal_clamp_text := ""
var hovered_cell := Vector2i(-1, -1)
var cached_path_segments := PackedVector2Array()
var heatmap_cell_indices := PackedInt32Array()
var clearance_cell_indices := PackedInt32Array()
var capture_hide_debug := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and is_node_ready():
		_layout_hud_panels()


func _ready() -> void:
	RenderingServer.set_default_clear_color(COLOR_VOID)

	grid = AgentGridScript.new(GRID_SIZE, CELL_SIZE, Vector2.ZERO, AgentSetScript.DEFAULT_RADIUS)
	agents = AgentSetScript.new()
	field = SharedFieldScript.new()
	scheduler = SchedulerScript.new()
	_apply_capture_args()

	_style_hud()
	_connect_hud()
	_layout_hud_panels()
	debug_panel.visible = not capture_hide_debug
	_setup_agent_multimesh()
	_setup_heatmap_multimesh()
	_setup_clearance_multimesh()
	_setup_blocked_multimesh()
	_setup_density_field()
	clearance_mm.visible = show_clearance
	blocked_rim_mm.visible = show_blocks
	blocked_mm.visible = show_blocks
	dynamic_layer.main = self

	_update_title_label()
	agents.reset(agent_count, grid, SEED)
	field.configure(grid)
	goal_world = grid.cell_to_world_center(Vector2i(GRID_SIZE.x / 2, GRID_SIZE.y / 2))
	field.set_goal_world(goal_world)

	_update_density_state()
	agents.sync_to_multimesh(agent_mm.multimesh, true)
	_refresh_density_field()
	_refresh_heatmap_colors()
	_trigger_goal_pulse()
	_rebuild_path_preview_segments()
	_update_status_label()
	_update_nav_diagnostic(goal_world)
	_refresh_static()
	_refresh_dynamic()


func _physics_process(delta: float) -> void:
	elapsed_seconds += delta
	field_rebuild_elapsed += delta
	agent_color_refresh_elapsed += delta
	goal_animation_refresh_elapsed += delta
	goal_pulse_age += delta
	frame_time_ms = delta * 1000.0
	smoothed_frame_time_ms = lerpf(smoothed_frame_time_ms, frame_time_ms, 0.12)

	if scheduler.is_benchmark():
		goal_world = scheduler.advance_benchmark_goal(grid)
		var field_was_dirty := field.dirty
		field.set_goal_world(goal_world)
		if field.dirty and not field_was_dirty:
			agents.clear_naive_targets()
			_trigger_goal_pulse()

	# Time-slice field rebuilds: agents keep reading the previous complete field
	# while the next one is built into a back buffer, then swapped atomically.
	var field_rebuilt := false
	if field.dirty:
		field_rebuilt = field.step_rebuild(FIELD_REBUILD_WORK_BUDGET)
		if field_rebuilt:
			field_rebuild_elapsed = 0.0

	if scheduler.is_naive():
		# Honest naive everywhere; only cap the in-app run above the guard
		# threshold so the web browser never freezes (disclosed in Debug).
		var query_cap := NAIVE_DEMO_QUERY_CAP if agent_count > NAIVE_DEMO_GUARD_THRESHOLD else 0
		naive_guard_active = query_cap > 0
		queries_this_frame = agents.advance_naive(goal_world, grid, delta, query_cap)
	else:
		naive_guard_active = false
		queries_this_frame = agents.advance_scheduled(field, delta, elapsed_seconds)

	# Above AGENT_COLOR_MAX_COUNT dots keep a fixed colour: the per-instance colour
	# write was a periodic full-buffer spike, and the density glow tells the story.
	var refresh_agent_colors := agent_count <= AGENT_COLOR_MAX_COUNT and agent_color_refresh_elapsed >= AGENT_COLOR_REFRESH_INTERVAL
	if refresh_agent_colors:
		agent_color_refresh_elapsed = 0.0
	agents.sync_to_multimesh(agent_mm.multimesh, refresh_agent_colors)

	if density_active:
		density_refresh_elapsed += delta
		if density_refresh_elapsed >= DENSITY_REFRESH_INTERVAL:
			density_refresh_elapsed = 0.0
			_refresh_density_field()

	# Static layer only changes when the field is rebuilt (goal moved); the
	# dynamic layer follows the agents and is refreshed every frame.
	if field_rebuilt:
		_refresh_heatmap_colors()
		_refresh_static()
		_rebuild_path_preview_segments()
		_refresh_dynamic()
	else:
		_maybe_refresh_path_preview(delta)

	_maybe_refresh_goal_animation()
	_maybe_update_status_label(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_scene_mode()
		elif event.keycode == KEY_R:
			_reset_agents()
		elif event.keycode == KEY_SPACE:
			scheduler.toggle_work_mode()
			agents.clear_naive_targets()
			_sync_hud_buttons()
			_update_status_label()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_update_nav_diagnostic(event.position)
		if not scheduler.is_benchmark():
			_set_goal_from_screen(event.position)

	if event is InputEventMouseMotion:
		_update_nav_diagnostic(event.position)
		if not scheduler.is_benchmark() and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_set_goal_from_screen(event.position)


# Cached static layer (grid + blockers + field arrows). Drawn by the parent
# node, so it renders behind the Agents and DynamicLayer children. Only redrawn
# via _refresh_static() when the layout, overlay toggles or field change.
func _draw() -> void:
	# Blocked cells are a separate batched MultiMesh ($BlockedCells), so the
	# static parent draw is just the grid + field arrows, both batched into a
	# single draw_multiline() call each.
	_draw_grid()
	if show_field:
		_draw_field_preview()


func draw_dynamic_layer(canvas: CanvasItem) -> void:
	if show_paths:
		_draw_cached_path_preview(canvas)
	_draw_vignette(canvas)
	_draw_goal(canvas)


func _refresh_static() -> void:
	queue_redraw()


func _refresh_dynamic() -> void:
	if dynamic_layer != null:
		dynamic_layer.queue_redraw()


func _setup_agent_multimesh() -> void:
	agent_mesh = QuadMesh.new()
	_sync_agent_visual_quality()

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = agent_mesh
	multimesh.instance_count = agent_count
	multimesh.custom_aabb = _world_multimesh_aabb(32.0)

	agent_mm.multimesh = multimesh
	agent_mm.material = _create_agent_glow_material()
	agent_mm.modulate = Color.WHITE


func _sync_agent_visual_quality() -> void:
	if agent_mesh == null:
		return

	var size := agents.radius * _agent_render_scale()
	agent_mesh.size = Vector2(size, size)


func _world_multimesh_aabb(margin: float = 0.0) -> AABB:
	var rect := grid.get_world_rect().grow(margin)
	return AABB(
		Vector3(rect.position.x, rect.position.y, -1.0),
		Vector3(rect.size.x, rect.size.y, 2.0)
	)


func _create_agent_glow_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode blend_add, unshaded;

void fragment() {
	vec4 tint = COLOR;
	vec2 p = UV * 2.0 - vec2(1.0);
	float d = length(p);
	float core = 1.0 - smoothstep(0.0, 0.42, d);
	float halo = 1.0 - smoothstep(0.32, 1.0, d);
	// Tight core, minimal halo spill -> far less additive overdraw when crowds
	// stack, while still reading as a glowing dot.
	float alpha = (core * 0.92 + halo * 0.16) * tint.a;
	vec3 color = tint.rgb * (0.60 + core * 0.70);
	COLOR = vec4(color, alpha);
}
"""

	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _setup_heatmap_multimesh() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(grid.cell_size * 0.92, grid.cell_size * 0.92)

	heatmap_cell_indices = PackedInt32Array()
	for index in range(GRID_SIZE.x * GRID_SIZE.y):
		if grid.is_cell_index_walkable(index):
			heatmap_cell_indices.append(index)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = heatmap_cell_indices.size()
	multimesh.custom_aabb = _world_multimesh_aabb()

	for i in range(heatmap_cell_indices.size()):
		multimesh.set_instance_transform_2d(
			i,
			Transform2D(0.0, grid.cell_center_from_index(heatmap_cell_indices[i]))
		)
		multimesh.set_instance_color(i, Color(0.0, 0.0, 0.0, 0.0))

	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	heatmap_mm.multimesh = multimesh
	heatmap_mm.material = material


func _setup_clearance_multimesh() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(grid.cell_size * 0.88, grid.cell_size * 0.88)

	clearance_cell_indices = PackedInt32Array()
	for index in range(GRID_SIZE.x * GRID_SIZE.y):
		if grid.is_navigation_clearance_index(index):
			clearance_cell_indices.append(index)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.mesh = mesh
	multimesh.instance_count = clearance_cell_indices.size()
	multimesh.custom_aabb = _world_multimesh_aabb()

	for i in range(clearance_cell_indices.size()):
		multimesh.set_instance_transform_2d(
			i,
			Transform2D(0.0, grid.cell_center_from_index(clearance_cell_indices[i]))
		)

	clearance_mm.multimesh = multimesh
	clearance_mm.modulate = COLOR_CLEARANCE


# Blocked cells never change, so bake them into a single MultiMesh once: one
# draw call for the whole wall layout instead of ~1800 per-cell draw_rect()
# calls re-rendered by the GPU every frame.
func _setup_blocked_multimesh() -> void:
	var rim_mesh := QuadMesh.new()
	rim_mesh.size = Vector2(grid.cell_size, grid.cell_size)

	var wall_mesh := QuadMesh.new()
	wall_mesh.size = Vector2(grid.cell_size * 0.84, grid.cell_size * 0.84)

	var centers := PackedVector2Array()
	for y in range(GRID_SIZE.y):
		for x in range(GRID_SIZE.x):
			var cell := Vector2i(x, y)
			if grid.is_cell_blocked(cell):
				centers.append(grid.cell_to_world_center(cell))

	var rim_multimesh := MultiMesh.new()
	rim_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	rim_multimesh.mesh = rim_mesh
	rim_multimesh.instance_count = centers.size()
	rim_multimesh.custom_aabb = _world_multimesh_aabb()

	var wall_multimesh := MultiMesh.new()
	wall_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	wall_multimesh.mesh = wall_mesh
	wall_multimesh.instance_count = centers.size()
	wall_multimesh.custom_aabb = _world_multimesh_aabb()

	for i in range(centers.size()):
		var transform := Transform2D(0.0, centers[i])
		rim_multimesh.set_instance_transform_2d(i, transform)
		wall_multimesh.set_instance_transform_2d(i, transform)

	blocked_rim_mm.multimesh = rim_multimesh
	blocked_rim_mm.modulate = COLOR_WALL_RIM
	blocked_mm.multimesh = wall_multimesh
	blocked_mm.modulate = COLOR_WALL


func _setup_density_field() -> void:
	density_counts = PackedFloat32Array()
	density_counts.resize(GRID_SIZE.x * GRID_SIZE.y)

	density_image = Image.create(GRID_SIZE.x, GRID_SIZE.y, false, Image.FORMAT_RGBA8)
	density_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	density_texture = ImageTexture.create_from_image(density_image)

	var rect := grid.get_world_rect()
	density_sprite.texture = density_texture
	density_sprite.centered = false
	density_sprite.position = rect.position
	density_sprite.scale = Vector2(
		rect.size.x / float(GRID_SIZE.x),
		rect.size.y / float(GRID_SIZE.y)
	)
	density_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	density_sprite.material = material
	density_sprite.visible = false


# Crowd density glow underlay (high counts): bin agent positions into the coarse
# grid, colour by density (cool -> gold -> white-hot), upload as one bilinear
# texture. One textured draw call regardless of agent count -> bounded fillrate.
func _refresh_density_field() -> void:
	if not density_active or density_image == null:
		return

	density_counts.fill(0.0)
	var max_count := agents.accumulate_density(grid, density_counts)
	var inv_max := 1.0 / max_count if max_count > 0.0 else 0.0

	for index in range(density_counts.size()):
		@warning_ignore("integer_division")
		var y := index / GRID_SIZE.x
		var x := index % GRID_SIZE.x
		density_image.set_pixel(x, y, _density_color(density_counts[index] * inv_max))

	density_texture.update(density_image)


func _density_color(normalized: float) -> Color:
	if normalized <= 0.0:
		return Color(0.0, 0.0, 0.0, 0.0)

	# Boost low densities so sparse trails still glow, then ramp to a hot core.
	var t := pow(clampf(normalized, 0.0, 1.0), 0.55)
	var rgb: Color
	if t < 0.5:
		rgb = COLOR_DENSITY_LOW.lerp(COLOR_DENSITY_MID, t / 0.5)
	else:
		rgb = COLOR_DENSITY_MID.lerp(COLOR_DENSITY_HIGH, (t - 0.5) / 0.5)

	return Color(rgb.r, rgb.g, rgb.b, t * DENSITY_MAX_ALPHA)


func _update_density_state() -> void:
	density_active = agent_count > DENSITY_THRESHOLD
	if density_sprite != null:
		density_sprite.visible = density_active
	if not density_active and density_image != null:
		density_image.fill(Color(0.0, 0.0, 0.0, 0.0))
		density_texture.update(density_image)


func _refresh_heatmap_colors() -> void:
	if heatmap_mm == null or heatmap_mm.multimesh == null or field == null:
		return

	var max_cost := maxf(field.max_cost, 1.0)
	var multimesh := heatmap_mm.multimesh
	for i in range(heatmap_cell_indices.size()):
		var index := heatmap_cell_indices[i]
		var cost: float = field.costs[index]
		if cost >= SharedFieldScript.INF * 0.5:
			multimesh.set_instance_color(i, Color(0.0, 0.0, 0.0, 0.0))
			continue

		multimesh.set_instance_color(i, _heatmap_color_for_cost(cost / max_cost))


func _heatmap_color_for_cost(normalized_cost: float) -> Color:
	var t := clampf(normalized_cost, 0.0, 1.0)
	var near_goal := Color(0.36, 0.91, 0.78, 0.24)
	var mid_field := Color(0.17, 0.55, 0.84, 0.16)
	var far_field := Color(0.09, 0.14, 0.37, 0.11)

	if t < 0.38:
		return near_goal.lerp(mid_field, t / 0.38)

	return mid_field.lerp(far_field, (t - 0.38) / 0.62)


func _style_hud() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.03, 0.05, 0.86)
	panel_style.border_color = Color(0.27, 0.34, 0.42, 0.62)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	control_panel.add_theme_stylebox_override("panel", panel_style)

	var debug_style := StyleBoxFlat.new()
	debug_style.bg_color = Color(0.02, 0.03, 0.05, 0.82)
	debug_style.border_color = Color(0.36, 0.44, 0.53, 0.56)
	debug_style.set_border_width_all(1)
	debug_style.set_corner_radius_all(6)
	debug_panel.add_theme_stylebox_override("panel", debug_style)

	debug_title_label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.98, 1.0))
	debug_status_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.77, 0.95))
	debug_agents_label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.29, 0.95))
	debug_grid_label.add_theme_color_override("font_color", Color(0.62, 0.85, 1.0, 0.88))
	debug_goal_label.add_theme_color_override("font_color", Color(0.36, 0.91, 0.78, 0.90))
	debug_nav_label.add_theme_color_override("font_color", Color(0.62, 0.85, 1.0, 0.88))
	agent_label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.29, 0.95))


func _layout_hud_panels() -> void:
	if control_panel == null or debug_panel == null:
		return

	var viewport_size := get_viewport_rect().size
	var debug_position := Vector2(
		viewport_size.x - DEBUG_PANEL_SIZE.x - HUD_MARGIN,
		HUD_MARGIN
	)
	var control_right := control_panel.position.x + control_panel.size.x + HUD_MARGIN
	if debug_position.x < control_right:
		debug_position.x = HUD_MARGIN
		debug_position.y = control_panel.position.y + control_panel.size.y + HUD_MARGIN

	debug_panel.position = debug_position
	debug_panel.size = DEBUG_PANEL_SIZE


func _make_button_style(bg_color: Color, border_color: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _button_color(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _apply_button_style(button: Button, accent: Color, active: bool, action: bool = false) -> void:
	var normal_bg := COLOR_UI_BASE
	var normal_border := COLOR_UI_MUTED
	var font_color := _button_color(COLOR_UI_ICE, 0.74)
	var border_width := 1

	if active:
		normal_bg = _button_color(accent, 0.20)
		normal_border = _button_color(accent, 0.90)
		font_color = _button_color(accent, 1.0)
		border_width = 2
	elif action:
		normal_bg = _button_color(accent, 0.10)
		normal_border = _button_color(accent, 0.62)
		font_color = _button_color(accent, 0.96)

	button.add_theme_stylebox_override("normal", _make_button_style(normal_bg, normal_border, border_width))
	button.add_theme_stylebox_override(
		"hover",
		_make_button_style(COLOR_UI_BASE_HOVER, _button_color(accent, 0.92), border_width)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_button_style(_button_color(accent, 0.27), _button_color(accent, 1.0), 2)
	)
	button.add_theme_stylebox_override(
		"hover_pressed",
		_make_button_style(_button_color(accent, 0.32), _button_color(accent, 1.0), 2)
	)
	button.add_theme_stylebox_override("focus", _make_button_style(Color.TRANSPARENT, _button_color(accent, 0.95), 1))
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", _button_color(accent, 1.0))
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", font_color)
	button.add_theme_color_override("font_disabled_color", _button_color(COLOR_UI_MUTED, 0.45))


func _connect_hud() -> void:
	agent_slider.min_value = MIN_AGENT_COUNT
	agent_slider.max_value = maxi(MAX_AGENT_COUNT, agent_count)
	agent_slider.step = 100
	agent_slider.value = agent_count
	_set_control_tooltips()
	agent_slider.value_changed.connect(_on_agent_slider_value_changed)
	naive_button.pressed.connect(_set_naive_work_mode)
	scheduled_button.pressed.connect(_set_scheduled_work_mode)
	demo_mode_button.pressed.connect(_set_demo_mode)
	benchmark_mode_button.pressed.connect(_set_benchmark_mode)
	reset_button.pressed.connect(_reset_agents)
	field_button.toggled.connect(_on_field_toggled)
	paths_button.toggled.connect(_on_paths_toggled)
	blocks_button.toggled.connect(_on_blocks_toggled)
	clearance_button.toggled.connect(_on_clearance_toggled)
	_sync_hud_buttons()


func _apply_capture_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-agents="):
			agent_count = maxi(1, arg.get_slice("=", 1).to_int())
		elif arg == "--capture-benchmark":
			scheduler.set_mode(SchedulerScript.Mode.BENCHMARK)
		elif arg == "--capture-demo":
			scheduler.set_mode(SchedulerScript.Mode.DEMO)
		elif arg == "--capture-naive":
			scheduler.set_work_mode(SchedulerScript.WorkMode.NAIVE)
		elif arg == "--capture-scheduled":
			scheduler.set_work_mode(SchedulerScript.WorkMode.SCHEDULED)
		elif arg.begins_with("--capture-goal-interval="):
			scheduler.benchmark_goal_interval_frames = maxi(1, arg.get_slice("=", 1).to_int())
		elif arg == "--capture-hide-debug":
			capture_hide_debug = true


func _set_control_tooltips() -> void:
	naive_button.tooltip_text = "Each agent asks for its own path. Useful baseline, expensive when many agents update together."
	scheduled_button.tooltip_text = "Agents follow one shared flow field. Bounded per-frame work, better for crowds."
	demo_mode_button.tooltip_text = "Interactive mode. Click the grid to move the goal."
	benchmark_mode_button.tooltip_text = "Scripted moving goals for repeatable frame-time comparison."
	reset_button.tooltip_text = "Respawn agents and reset the active mode without changing Naive or Scheduled."
	agent_slider.tooltip_text = "Change active agent count. Higher counts make frame-time differences easier to see."
	field_button.tooltip_text = "Show the shared cost field used by scheduled agents."
	paths_button.tooltip_text = "Show sampled preview paths from agents toward the goal."
	blocks_button.tooltip_text = "Show visual obstacle cells."
	clearance_button.tooltip_text = "Show inflated blocked cells used for agent radius and corner safety."


func _update_title_label() -> void:
	title_label.text = "Moving %d Agents" % agent_count


func _reset_agents() -> void:
	var current_mode := SchedulerScript.Mode.BENCHMARK if scheduler.is_benchmark() else SchedulerScript.Mode.DEMO
	scheduler.set_mode(current_mode)
	elapsed_seconds = 0.0
	queries_this_frame = 0
	path_refresh_elapsed = PATH_REFRESH_INTERVAL
	hud_refresh_elapsed = HUD_REFRESH_INTERVAL
	field_rebuild_elapsed = FIELD_REBUILD_INTERVAL
	agent_color_refresh_elapsed = AGENT_COLOR_REFRESH_INTERVAL
	density_refresh_elapsed = DENSITY_REFRESH_INTERVAL
	goal_animation_refresh_elapsed = GOAL_ANIMATION_REFRESH_INTERVAL

	_update_density_state()
	agents.reset(agent_count, grid, SEED)
	if scheduler.is_benchmark():
		goal_world = scheduler.current_benchmark_goal(grid)
	else:
		goal_world = grid.cell_to_world_center(Vector2i(GRID_SIZE.x / 2, GRID_SIZE.y / 2))
	field.set_goal_world(goal_world)
	agents.clear_naive_targets()
	last_goal_clamp_text = ""
	_trigger_goal_pulse()
	_force_field_rebuild()
	agents.sync_to_multimesh(agent_mm.multimesh, true)
	_refresh_density_field()
	_rebuild_path_preview_segments()
	_update_status_label()
	_update_nav_diagnostic(last_pointer_position)
	_sync_hud_buttons()
	_refresh_static()
	_refresh_dynamic()


func _set_goal_from_screen(screen_position: Vector2) -> void:
	var requested_cell := grid.world_to_cell(screen_position)
	var clamped_world := grid.clamp_world_to_walkable(screen_position)
	var clamped_cell := grid.world_to_cell(clamped_world)

	if requested_cell != clamped_cell or not grid.is_cell_walkable(requested_cell):
		last_goal_clamp_text = "goal clamped %s -> %s" % [
			_cell_text(requested_cell),
			_cell_text(clamped_cell),
		]
	else:
		last_goal_clamp_text = ""

	goal_world = clamped_world
	field.set_goal_world(goal_world)
	agents.clear_naive_targets()
	_trigger_goal_pulse()
	path_refresh_elapsed = PATH_REFRESH_INTERVAL
	_update_status_label()
	_update_nav_diagnostic(screen_position)
	# Field rebuild + static refresh happen on the next physics frame (dirty),
	# but refresh the dynamic goal marker immediately for snappy feedback.
	_refresh_dynamic()


func _toggle_scene_mode() -> void:
	if scheduler.is_benchmark():
		_set_scene_mode(SchedulerScript.Mode.DEMO)
	else:
		_set_scene_mode(SchedulerScript.Mode.BENCHMARK)


func _set_demo_mode() -> void:
	_set_scene_mode(SchedulerScript.Mode.DEMO)


func _set_benchmark_mode() -> void:
	_set_scene_mode(SchedulerScript.Mode.BENCHMARK)


func _set_scene_mode(next_mode: int) -> void:
	if scheduler.mode == next_mode:
		_sync_hud_buttons()
		return

	scheduler.set_mode(next_mode)
	agents.clear_naive_targets()
	if scheduler.is_benchmark():
		goal_world = scheduler.current_benchmark_goal(grid)
	else:
		goal_world = grid.cell_to_world_center(Vector2i(GRID_SIZE.x / 2, GRID_SIZE.y / 2))

	field.set_goal_world(goal_world)
	last_goal_clamp_text = ""
	_trigger_goal_pulse()
	_force_field_rebuild()
	_rebuild_path_preview_segments()
	_update_status_label()
	_update_nav_diagnostic(last_pointer_position)
	_sync_hud_buttons()
	_refresh_static()
	_refresh_dynamic()


func _set_naive_work_mode() -> void:
	scheduler.set_work_mode(SchedulerScript.WorkMode.NAIVE)
	agents.clear_naive_targets()
	_sync_hud_buttons()
	_rebuild_path_preview_segments()
	_update_status_label()
	_refresh_dynamic()


func _set_scheduled_work_mode() -> void:
	scheduler.set_work_mode(SchedulerScript.WorkMode.SCHEDULED)
	agents.clear_naive_targets()
	_sync_hud_buttons()
	_rebuild_path_preview_segments()
	_update_status_label()
	_refresh_dynamic()


func _sync_hud_buttons() -> void:
	_sync_work_mode_buttons()
	_sync_scene_mode_buttons()
	_sync_overlay_button_styles()


func _sync_work_mode_buttons() -> void:
	var naive_active := scheduler.is_naive()
	naive_button.button_pressed = naive_active
	scheduled_button.button_pressed = not naive_active
	_apply_button_style(naive_button, COLOR_UI_GOLD, naive_active)
	_apply_button_style(scheduled_button, COLOR_UI_ICE, not naive_active)


func _sync_scene_mode_buttons() -> void:
	var benchmark_active := scheduler.is_benchmark()
	demo_mode_button.button_pressed = not benchmark_active
	benchmark_mode_button.button_pressed = benchmark_active
	reset_button.text = "Reset Bench" if benchmark_active else "Reset Demo"
	reset_button.tooltip_text = (
		"Restart the benchmark route from the first scripted goal."
		if benchmark_active
		else "Respawn agents and reset the demo goal without changing Naive or Scheduled."
	)
	_apply_button_style(demo_mode_button, COLOR_UI_MINT, not benchmark_active)
	_apply_button_style(benchmark_mode_button, COLOR_UI_PINK, benchmark_active)
	_apply_button_style(reset_button, COLOR_UI_ICE if not benchmark_active else COLOR_UI_PINK, false, true)


func _sync_overlay_button_styles() -> void:
	_apply_button_style(field_button, COLOR_UI_ICE, show_field)
	_apply_button_style(paths_button, COLOR_UI_ICE, show_paths)
	_apply_button_style(blocks_button, COLOR_UI_MUTED, show_blocks)
	_apply_button_style(clearance_button, COLOR_UI_MINT, show_clearance)


func _agent_render_scale() -> float:
	# Smaller crisp dots once the density glow is carrying the crowd, so the
	# overlapping additive sprites cost far less fillrate.
	if agent_count > DENSITY_THRESHOLD:
		return AGENT_RENDER_SCALE_DENSE
	return AGENT_RENDER_SCALE


func _on_agent_slider_value_changed(value: float) -> void:
	agent_count = int(value)
	_update_title_label()
	_update_density_state()
	_sync_agent_visual_quality()
	agents.reset(agent_count, grid, SEED)
	agents.sync_to_multimesh(agent_mm.multimesh, true)
	_refresh_density_field()
	_rebuild_path_preview_segments()
	_update_status_label()
	_refresh_dynamic()


func _on_field_toggled(enabled: bool) -> void:
	show_field = enabled
	_sync_overlay_button_styles()
	_refresh_static()


func _on_paths_toggled(enabled: bool) -> void:
	show_paths = enabled
	_sync_overlay_button_styles()
	if enabled:
		_rebuild_path_preview_segments()
	_refresh_dynamic()


func _on_blocks_toggled(enabled: bool) -> void:
	show_blocks = enabled
	blocked_rim_mm.visible = enabled
	blocked_mm.visible = enabled
	_sync_overlay_button_styles()


func _on_clearance_toggled(enabled: bool) -> void:
	show_clearance = enabled
	clearance_mm.visible = enabled
	_sync_overlay_button_styles()
	_update_nav_diagnostic(last_pointer_position)


func _update_nav_diagnostic(screen_position: Vector2) -> void:
	if debug_nav_label == null or grid == null:
		return

	last_pointer_position = screen_position
	if not grid.get_world_rect().has_point(screen_position):
		hovered_cell = Vector2i(-1, -1)
		debug_nav_label.text = "Hover: outside grid%s" % _goal_clamp_suffix()
		return

	var cell := grid.world_to_cell(screen_position)
	hovered_cell = cell

	var visual_wall := grid.is_cell_blocked(cell)
	var nav_clearance := grid.is_navigation_clearance_cell(cell)
	var corner_cut_blocked := grid.has_corner_cut_blocked_diagonal(cell)

	var diagonal_text := "corner cut" if corner_cut_blocked else "no"
	debug_nav_label.text = (
		"Hover %s: %s\n" +
		"visual wall %s | clearance %s\n" +
		"diagonal blocked %s%s"
	) % [
		_cell_text(cell),
		_cell_state_text(cell),
		_bool_text(visual_wall),
		_bool_text(nav_clearance),
		diagonal_text,
		_goal_clamp_suffix(),
	]


func _goal_clamp_suffix() -> String:
	if last_goal_clamp_text.is_empty():
		return ""
	return "\n%s" % last_goal_clamp_text


func _bool_text(value: bool) -> String:
	return "yes" if value else "no"


func _cell_state_text(cell: Vector2i) -> String:
	if grid.is_cell_blocked(cell):
		return "visual wall"
	if grid.is_navigation_clearance_cell(cell):
		return "nav clearance"
	if not grid.is_cell_walkable(cell):
		return "blocked"
	return "walkable"


func _cell_text(cell: Vector2i) -> String:
	return "(%d,%d)" % [cell.x, cell.y]


func _draw_grid() -> void:
	var rect: Rect2 = grid.get_world_rect()
	draw_rect(rect, COLOR_FLOOR, true)
	draw_rect(rect, COLOR_WORLD_RIM, false, 2.0)

	var minor_lines := PackedVector2Array()
	var major_lines := PackedVector2Array()
	for x in range(0, GRID_SIZE.x + 1, 4):
		var x_pos: float = grid.origin.x + float(x) * grid.cell_size
		if x % 8 == 0:
			major_lines.append(Vector2(x_pos, rect.position.y))
			major_lines.append(Vector2(x_pos, rect.end.y))
		else:
			minor_lines.append(Vector2(x_pos, rect.position.y))
			minor_lines.append(Vector2(x_pos, rect.end.y))

	for y in range(0, GRID_SIZE.y + 1, 4):
		var y_pos: float = grid.origin.y + float(y) * grid.cell_size
		if y % 8 == 0:
			major_lines.append(Vector2(rect.position.x, y_pos))
			major_lines.append(Vector2(rect.end.x, y_pos))
		else:
			minor_lines.append(Vector2(rect.position.x, y_pos))
			minor_lines.append(Vector2(rect.end.x, y_pos))

	if minor_lines.size() >= 2:
		draw_multiline(minor_lines, COLOR_GRID, 1.0)
	if major_lines.size() >= 2:
		draw_multiline(major_lines, COLOR_GRID_MAJOR, 1.15)


func _draw_field_preview() -> void:
	# All field arrows batched into one draw_multiline() call.
	var arrows := PackedVector2Array()
	for x in range(4, GRID_SIZE.x, 8):
		for y in range(4, GRID_SIZE.y, 8):
			var cell := Vector2i(x, y)
			if not grid.is_cell_walkable(cell):
				continue

			var start: Vector2 = grid.cell_to_world_center(cell)
			var direction: Vector2 = field.get_direction_for_world_position(start)
			if direction.length_squared() <= 0.001:
				continue

			arrows.append(start)
			arrows.append(start + direction * 7.5)

	if arrows.size() >= 2:
		draw_multiline(arrows, COLOR_FIELD_ARROW, 0.95)


func _draw_cached_path_preview(canvas: CanvasItem) -> void:
	if cached_path_segments.size() >= 2:
		canvas.draw_multiline(cached_path_segments, COLOR_PATH, 1.4)


func _rebuild_path_preview_segments() -> void:
	if not show_paths:
		return
	if scheduler.is_naive() == false and field.dirty:
		return

	var samples: Array[int] = agents.get_sample_indices(PATH_SAMPLE_COUNT)
	var goal_cell: Vector2i = grid.nearest_walkable_cell(grid.world_to_cell(goal_world))

	# Flatten every sample path into one segment list -> one draw_multiline().
	var segments := PackedVector2Array()
	for sample_index in samples:
		var points := PackedVector2Array()
		if scheduler.is_naive():
			var start_cell: Vector2i = grid.nearest_walkable_cell(grid.world_to_cell(agents.get_position(sample_index)))
			var path_cells: Array = grid.find_path_cells(start_cell, goal_cell)
			for cell in path_cells:
				points.append(grid.cell_to_world_center(cell))
				if points.size() >= 22:
					break
		else:
			points = field.build_path_from_world(agents.get_position(sample_index), 64)

		for i in range(points.size() - 1):
			segments.append(points[i])
			segments.append(points[i + 1])

	cached_path_segments = segments


func _maybe_refresh_path_preview(delta: float) -> void:
	if not show_paths:
		return

	path_refresh_elapsed += delta
	if path_refresh_elapsed < PATH_REFRESH_INTERVAL:
		return

	path_refresh_elapsed = 0.0
	_rebuild_path_preview_segments()
	_refresh_dynamic()


func _draw_goal(canvas: CanvasItem) -> void:
	var heartbeat := 0.5 + 0.5 * sin(elapsed_seconds * 4.0)
	var core_radius := 8.0 + heartbeat * 1.6
	var halo_radius := 17.0 + heartbeat * 4.0
	var loop_t := fposmod(elapsed_seconds, GOAL_PULSE_DURATION) / GOAL_PULSE_DURATION
	var loop_radius := lerpf(18.0, 54.0, loop_t)
	var loop_alpha := (1.0 - loop_t) * 0.22

	canvas.draw_circle(goal_world, halo_radius + 7.0, Color(1.0, 0.18, 0.42, 0.10))
	canvas.draw_arc(goal_world, loop_radius, 0.0, TAU, 72, Color(1.0, 0.62, 0.77, loop_alpha), 1.8)
	canvas.draw_circle(goal_world, core_radius + 3.0, COLOR_GOAL_CORE)
	canvas.draw_circle(goal_world, core_radius * 0.46, COLOR_GOAL_HOT)
	canvas.draw_arc(goal_world, halo_radius, 0.0, TAU, 64, COLOR_GOAL_RING, 2.0)
	canvas.draw_arc(goal_world, halo_radius + 7.0, 0.0, TAU, 64, Color(1.0, 0.62, 0.77, 0.30), 1.2)

	if goal_pulse_age < GOAL_PULSE_DURATION:
		var t := clampf(goal_pulse_age / GOAL_PULSE_DURATION, 0.0, 1.0)
		var ripple_radius := lerpf(20.0, 82.0, t)
		var ripple_alpha := (1.0 - t) * 0.46
		canvas.draw_arc(
			goal_world,
			ripple_radius,
			0.0,
			TAU,
			72,
			Color(1.0, 0.62, 0.77, ripple_alpha),
			2.4
		)


func _draw_vignette(canvas: CanvasItem) -> void:
	var rect := grid.get_world_rect()
	var width := 72.0
	var edge_color := Color(0.02, 0.03, 0.05, 0.16)
	canvas.draw_rect(Rect2(rect.position, Vector2(width, rect.size.y)), edge_color, true)
	canvas.draw_rect(Rect2(Vector2(rect.end.x - width, rect.position.y), Vector2(width, rect.size.y)), edge_color, true)
	canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, width)), edge_color, true)
	canvas.draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - width), Vector2(rect.size.x, width)), edge_color, true)


func _maybe_refresh_goal_animation() -> void:
	if goal_animation_refresh_elapsed < GOAL_ANIMATION_REFRESH_INTERVAL:
		return

	goal_animation_refresh_elapsed = 0.0
	_refresh_dynamic()


func _trigger_goal_pulse() -> void:
	goal_pulse_age = 0.0
	goal_animation_refresh_elapsed = GOAL_ANIMATION_REFRESH_INTERVAL


func _update_status_label() -> void:
	if debug_status_label == null:
		return

	var goal_cell := grid.world_to_cell(goal_world)
	agent_label.text = "Agents %d" % agent_count
	debug_status_label.text = (
		"Work: %s / %s | %.2f ms | %d fps\n" +
		"queries/frame %d%s"
	) % [
		scheduler.mode_label(),
		scheduler.work_mode_label(),
		smoothed_frame_time_ms,
		Engine.get_frames_per_second(),
		queries_this_frame,
		_naive_guard_suffix(),
	]
	debug_agents_label.text = "Agents: %d | speed %.0f | radius %.1f | render %.1fx | density %s" % [
		agent_count,
		agents.speed,
		agents.radius,
		_agent_render_scale(),
		"on" if density_active else "off",
	]
	debug_grid_label.text = "Grid: %dx%d | cell %.0f | clearance cells %d" % [
		GRID_SIZE.x,
		GRID_SIZE.y,
		CELL_SIZE,
		clearance_cell_indices.size(),
	]
	debug_goal_label.text = "Goal: %s | %s | field max %.1f" % [
		_cell_text(goal_cell),
		_cell_state_text(goal_cell),
		field.max_cost,
	]


func _maybe_update_status_label(delta: float) -> void:
	hud_refresh_elapsed += delta
	if hud_refresh_elapsed < HUD_REFRESH_INTERVAL:
		return

	hud_refresh_elapsed = 0.0
	_update_status_label()


func _force_field_rebuild() -> void:
	if field.dirty:
		field.rebuild()
	_refresh_heatmap_colors()
	field_rebuild_elapsed = 0.0


func _naive_guard_suffix() -> String:
	if naive_guard_active:
		return "\nNaive stress guard: path queries capped"
	return ""
