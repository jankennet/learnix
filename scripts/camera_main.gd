extends Node3D

@export var player: CharacterBody3D
@onready var camera_3d: Camera3D = $CharacterBody3D/Main_Camera
@export var smooth_speed: float = 6.0

func _process(delta: float) -> void:
	if player:
		# Keep current rotation (angle) — only follow position
		global_position = global_position.lerp(player.global_position, delta * smooth_speed)
		global_rotation = global_rotation  # keeps rotation fixed
