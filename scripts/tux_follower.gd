extends CharacterBody3D

@export var follow_speed: float = 7.5
@export var acceleration: float = 12.0
@export var follow_distance: float = 0.9
@export var follow_distance_behind: float = -1.4
@export var max_distance_before_snap: float = 8.0
@export var afk_threshold_seconds: float = 3.0
@export var hint_interval_seconds: float = 18.0
@export var stuck_hint_delay_seconds: float = 10.0
@export var vertical_follow_speed: float = 16.0
@export var show_floating_hints: bool = false
@export var min_vertical_offset: float = 0.35

@export var mentor_lines: Array[String] = [
	"One step at a time, Nova. Even root starts with a prompt.",
	"Steady now. Wisdom compiles best without rushing.",
	"If all else fails, breathe... then read the error message.",
	"I am with you. Think of me as your very determined paperclip.",
	"Curiosity is your strongest command. Keep using it.",
	"A playful guess is fine—just verify your assumptions after."
]

@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D

var _player: CharacterBody3D
var _hint_timer: float = 0.0
var _still_time: float = 0.0
var _last_player_position: Vector3
var _speech_label: Label3D
var _speech_hide_timer: SceneTreeTimer
var _current_side_offset: Vector3 = Vector3.ZERO
var _vertical_offset: float = 0.0


func _ready() -> void:
	_player = get_parent().get_node_or_null("CharacterBody3D")
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D

	if _player:
		_last_player_position = _player.global_position
		_vertical_offset = maxf(min_vertical_offset, global_position.y - _player.global_position.y)

	collision_layer = 0
	collision_mask = 0
	if show_floating_hints:
		_create_speech_label()


func _physics_process(delta: float) -> void:
	if _player == null:
		return

	_follow_player(delta)
	_sync_vertical_position(delta)
	_update_animation()
	_update_guidance(delta)


func _sync_vertical_position(delta: float) -> void:
	if _player == null:
		return

	var target_y := _player.global_position.y + _vertical_offset
	global_position.y = lerpf(global_position.y, target_y, clampf(delta * vertical_follow_speed, 0.0, 1.0))


func _follow_player(delta: float) -> void:
	var player_pos := _player.global_position
	var player_velocity := _player.velocity
	player_velocity.y = 0.0
	
	# Calculate desired offset based on player handling
	var desired_offset := Vector3(0, 0, -1.2)  # Default: well behind
	
	if player_velocity.length() > 0.1:
		# Player is moving: offset to right side relative to movement direction
		var forward := player_velocity.normalized()
		var right := Vector3(-forward.z, 0, forward.x)  # Perpendicular to forward
		desired_offset = right * 0.5 + forward * -1.5  # Right side and far behind
	
	# Smoothly interpolate the offset for natural transitions
	_current_side_offset = _current_side_offset.lerp(desired_offset, clampf(delta * 3.0, 0.0, 1.0))
	
	var target_pos := player_pos + _current_side_offset
	
	var to_target := target_pos - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	if distance > max_distance_before_snap:
		global_position = target_pos
		velocity = Vector3.ZERO
		return

	if distance > follow_distance:
		var desired_direction := to_target.normalized()
		var desired_velocity := desired_direction * follow_speed
		velocity = velocity.lerp(desired_velocity, clampf(acceleration * delta, 0.0, 1.0))
	else:
		velocity = velocity.lerp(Vector3.ZERO, clampf(acceleration * delta, 0.0, 1.0))

	velocity.y = 0.0
	move_and_slide()


func _update_animation() -> void:
	if sprite == null:
		return

	var move := velocity
	move.y = 0.0

	if move.length() < 0.05:
		sprite.play("tux_idle")
		return

	if absf(move.z) > absf(move.x):
		if move.z < 0.0:
			sprite.play("tux_idle_back")
		else:
			sprite.play("tux_idle")
	else:
		sprite.play("tux_idle_side")
		sprite.flip_h = move.x < 0.0


func _update_guidance(delta: float) -> void:
	if not show_floating_hints:
		return

	_hint_timer += delta

	if _player.global_position.distance_to(_last_player_position) < 0.06:
		_still_time += delta
	else:
		_still_time = 0.0
		_last_player_position = _player.global_position

	if _hint_timer < hint_interval_seconds:
		return

	if _still_time < afk_threshold_seconds:
		return

	_hint_timer = 0.0
	var line := _choose_guidance_line()
	_show_line(line)


func _choose_guidance_line() -> String:
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.input_locked:
		return "Hold, young admin. Let the system breathe before the next move."

	if _still_time >= stuck_hint_delay_seconds:
		return "Stuck? Try exploring a different path—or talk to someone nearby for clues."

	if mentor_lines.is_empty():
		return "You're doing well, Nova."

	return mentor_lines[randi() % mentor_lines.size()]


func _create_speech_label() -> void:
	_speech_label = Label3D.new()
	_speech_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech_label.font_size = 24
	_speech_label.modulate = Color(0.9, 0.96, 1.0, 0.0)
	_speech_label.outline_size = 8
	_speech_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.75)
	_speech_label.position = Vector3(0.0, 1.6, 0.0)
	_speech_label.text = ""
	add_child(_speech_label)


func _show_line(line: String) -> void:
	if not show_floating_hints:
		return

	if _speech_label == null:
		return

	_speech_label.text = line
	_speech_label.modulate = Color(0.9, 0.96, 1.0, 1.0)

	if _speech_hide_timer and _speech_hide_timer.time_left > 0.0:
		# Timer will be replaced below.
		pass

	_speech_hide_timer = get_tree().create_timer(5.0)
	_speech_hide_timer.timeout.connect(_hide_speech_label)


func _hide_speech_label() -> void:
	if _speech_label:
		_speech_label.modulate = Color(0.9, 0.96, 1.0, 0.0)
