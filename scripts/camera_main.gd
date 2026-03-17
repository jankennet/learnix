extends Camera3D

@export var player: CharacterBody3D
@export var smooth_speed: float = 10.0
@export var collision_offset: float = 0.2 

# --- NEW CONTROLS ---
@export var height_offset: float = 2.0      # How high the camera sits
@export var distance_horizontal: float = 3.0 # How far back the camera sits
# --------------------

var _fixed_rotation: Vector3  # Rotation locked at startup

func _ready() -> void:
	set_as_top_level(true)
	_fixed_rotation = global_rotation  # Lock the angle set in the editor
	if not player:
		player = get_node("../CharacterBody3D")

func _physics_process(delta: float) -> void:
	if not player: return

	var target_pivot = player.global_position
	var back_dir = Vector3(0, 0, 1)
	var desired_pos = target_pivot + (back_dir * distance_horizontal) + (Vector3.UP * height_offset)

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(target_pivot, desired_pos)
	query.exclude = [player]
	var result = space_state.intersect_ray(query)

	var final_pos = desired_pos
	if result:
		var hit_to_player_dir = (target_pivot - result.position).normalized()
		final_pos = result.position + (hit_to_player_dir * collision_offset)
		global_position = final_pos
	else:
		global_position = global_position.lerp(final_pos, delta * smooth_speed)

	# Restore fixed rotation — never rotates with the player
	global_rotation = _fixed_rotation
