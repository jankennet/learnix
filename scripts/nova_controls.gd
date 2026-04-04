extends CharacterBody3D

@export var speed: float = 3.0
@export var gravity: float = 9.8
@export var run_speed: float = 5.0
@export var size_scale: float = 0.9  # Change this to resize Nova + hitbox
@export var auto_step_height: float = 0.35
@export var auto_step_min_speed: float = 0.1

@onready var sprite: AnimatedSprite3D = $Nova
@onready var collision: CollisionShape3D = $Nova_CollisionBox

var last_animation = ""
var last_facing = "left"  # tracks left or right for idle flipping
var _footstep_playing: bool = false
var _current_footstep_path: String = ""

func _ready():
	# Scale Nova visually
	scale = Vector3(size_scale, size_scale, size_scale)
	
	# Move sprite up so feet stay on the ground
	sprite.position.y = sprite.position.y + (1.0 - size_scale) * 0.5

	# Adjust collision shape
	if collision.shape is BoxShape3D:
		var box := collision.shape as BoxShape3D
		box.size *= size_scale

func _physics_process(delta: float) -> void:
	# Respect global input lock (set by UI or other modal systems)
	if SceneManager and SceneManager.input_locked:
		# Stop all movement when locked
		velocity = Vector3.ZERO
		return

	var input_direction = Vector3.ZERO
	var new_animation = ""

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# Handle input
	var pressing_left = Input.is_action_pressed("ui_left")
	var pressing_right = Input.is_action_pressed("ui_right")
	var pressing_up = Input.is_action_pressed("ui_up")
	var pressing_down = Input.is_action_pressed("ui_down")
	var pressing_shift = Input.is_action_pressed("ui_shift")

	if pressing_left:
		input_direction.x -= 1
		sprite.flip_h = true
		last_facing = "left"
	if pressing_right:
		input_direction.x += 1
		sprite.flip_h = false
		last_facing = "right"
	if pressing_up:
		input_direction.z -= 1
	if pressing_down:
		input_direction.z += 1

	# Determine movement and animation
	if input_direction != Vector3.ZERO:
		input_direction = input_direction.normalized()

		var current_speed = run_speed if pressing_shift else speed
		velocity.x = input_direction.x * current_speed
		velocity.z = input_direction.z * current_speed

		# Animation logic
		if pressing_up and !pressing_left and !pressing_right:
			new_animation = "run_anim_up" if pressing_shift else "walk_anim_up"
		elif pressing_down and !pressing_left and !pressing_right:
			new_animation = "run_anim_down" if pressing_shift else "walk_anim_down"
		else:
			new_animation = "run_anim_left" if pressing_shift else "walk_anim_left"

		# Footstep loop handling (looped ambient for walk/run)
		var step_sound := "res://album/sfx/run.mp3" if pressing_shift else "res://album/sfx/walk.mp3"
		if not _footstep_playing or _current_footstep_path != step_sound:
			if _footstep_playing and _current_footstep_path != "":
				if SceneManager:
					SceneManager.stop_sfx(_current_footstep_path)
			if SceneManager:
				SceneManager.play_sfx(step_sound, true)
				_footstep_playing = true
				_current_footstep_path = step_sound
	else:
		# Stop smoothly
		velocity.x = 0
		velocity.z = 0
		new_animation = "nova_idle"
		sprite.flip_h = (last_facing == "left")

		# Stop footstep loop when player stops
		if _footstep_playing and _current_footstep_path != "":
			if SceneManager:
				SceneManager.stop_sfx(_current_footstep_path)
			_footstep_playing = false
			_current_footstep_path = ""

	var stepped := _try_auto_step(delta)
	if stepped:
		# Prevent double horizontal movement in this frame after manual step-up.
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()

	# Play animation if changed
	if new_animation != "" and new_animation != last_animation:
		sprite.play(new_animation)
		last_animation = new_animation
		

func _input(_event):
	# Respect global input lock
	if SceneManager and SceneManager.input_locked:
		return

	# Use frame-based query for the interact action to make key presses (E) reliable
	if Input.is_action_just_pressed("interact"):
		InteractionManager.request_interaction()

func _try_auto_step(delta: float) -> bool:
	if auto_step_height <= 0.0:
		return false
	if not is_on_floor():
		return false

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length() < auto_step_min_speed:
		return false

	var horizontal_motion := horizontal_velocity * delta
	if horizontal_motion.length() <= 0.0:
		return false

	# Only attempt a step when forward movement is blocked at current height.
	if not test_move(global_transform, horizontal_motion):
		return false

	var up_motion := Vector3.UP * auto_step_height
	if test_move(global_transform, up_motion):
		return false

	var raised_transform := global_transform.translated(up_motion)
	if test_move(raised_transform, horizontal_motion):
		return false

	global_transform = raised_transform.translated(horizontal_motion)

	# Settle down onto the floor smoothly after stepping up.
	var settle_distance := auto_step_height + 0.2
	var settle_step := 0.05
	while settle_distance > 0.0 and not test_move(global_transform, Vector3.DOWN * settle_step):
		global_position.y -= settle_step
		settle_distance -= settle_step

	velocity.y = 0.0
	return true
