extends Camera3D

@export var player: CharacterBody3D
@export var smooth_speed: float = 10.0
@export var collision_offset: float = 0.2 

# --- NEW CONTROLS ---
@export var use_editor_offsets_on_start: bool = true
@export var side_offset: float = 0.0
@export var height_offset: float = 2.0      # How high the camera sits
@export var distance_horizontal: float = 3.0 # How far back the camera sits
# --------------------

var _fixed_rotation: Vector3  # Rotation locked at startup

func _ready() -> void:
	set_as_top_level(true)
	_fixed_rotation = global_rotation  # Lock the angle set in the editor
	if not player:
		player = get_node("../CharacterBody3D")
	_capture_editor_offsets_if_enabled()
	call_deferred("_reassert_active_camera")

func _enter_tree() -> void:
	call_deferred("_reassert_active_camera")

func _reassert_active_camera() -> void:
	if player == null:
		player = get_node_or_null("../CharacterBody3D")
	current = true
	force_sync_to_player()

func _physics_process(delta: float) -> void:
	if not player: return

	_sync_camera_to_player(delta)

func force_sync_to_player() -> void:
	if not player:
		return
	_sync_camera_to_player(1.0)

func _sync_camera_to_player(delta: float) -> void:
	var target_pivot = player.global_position
	var desired_pos = target_pivot + Vector3(side_offset, height_offset, distance_horizontal)

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

func _capture_editor_offsets_if_enabled() -> void:
	if not use_editor_offsets_on_start:
		return
	if player == null:
		return

	# Read the camera placement from the editor and convert it to runtime offsets.
	var editor_delta := global_position - player.global_position
	side_offset = editor_delta.x
	height_offset = editor_delta.y
	distance_horizontal = editor_delta.z
