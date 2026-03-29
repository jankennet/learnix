extends CharacterBody3D

@export var speed: float = 3.0
@export var gravity: float = 9.8
@export var run_speed: float = 5.0
@export var size_scale: float = 0.9  # Change this to resize Nova + hitbox

@onready var sprite: AnimatedSprite3D = $Nova
@onready var collision: CollisionShape3D = $Nova_CollisionBox

var last_animation = ""
var last_facing = "left"  # tracks left or right for idle flipping

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
	else:
		# Stop smoothly
		velocity.x = 0
		velocity.z = 0
		new_animation = "nova_idle"
		sprite.flip_h = (last_facing == "left")

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
