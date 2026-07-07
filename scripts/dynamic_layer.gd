extends Node2D

# Per-frame layer: path preview + goal marker. Redrawn every physics frame
# because it follows the moving agents. Static geometry (grid, blockers, field
# arrows) lives on the parent and is only redrawn when it actually changes.

var main: Node2D


func _draw() -> void:
	if main != null:
		main.draw_dynamic_layer(self)
