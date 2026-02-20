extends Control
class_name ProficiencyKeyIcon

@export var frame_color: Color = Color(0.55, 0.58, 0.63, 1.0)
@export var frame_shadow: Color = Color(0.24, 0.26, 0.30, 1.0)
@export var recess_color: Color = Color(0.08, 0.09, 0.14, 1.0)
@export var core_color: Color = Color(0.36, 0.28, 0.78, 1.0)

func _ready() -> void:
	custom_minimum_size = Vector2(92, 118)
	queue_redraw()

func _draw() -> void:
	var body_pos := Vector2(18, 4)
	var body_size := Vector2(56, 56)

	draw_rect(Rect2(body_pos + Vector2(2, 2), body_size), frame_shadow, true)
	draw_rect(Rect2(body_pos, body_size), frame_color, true)
	draw_rect(Rect2(body_pos + Vector2(8, 8), body_size - Vector2(16, 16)), recess_color, true)
	draw_rect(Rect2(body_pos + Vector2(21, 21), Vector2(14, 14)), core_color, true)
	draw_rect(Rect2(body_pos + Vector2(25, 25), Vector2(6, 6)), Color(0.16, 0.14, 0.34, 1.0), true)

	draw_rect(Rect2(Vector2(34, 60), Vector2(8, 40)), frame_color, true)
	draw_rect(Rect2(Vector2(50, 60), Vector2(8, 40)), frame_color, true)
	draw_rect(Rect2(Vector2(33, 99), Vector2(10, 12)), frame_shadow, true)
	draw_rect(Rect2(Vector2(49, 99), Vector2(10, 12)), frame_shadow, true)
