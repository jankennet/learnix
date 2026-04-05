extends CanvasLayer

signal finished

@export var message: String = ""
@export var hold_duration: float = 2.8
@export var start_black_immediately: bool = true
@export var fade_in_duration: float = 0.2
@export var fade_out_duration: float = 0.2

@onready var _background: ColorRect = get_node_or_null("Background") as ColorRect
@onready var _message_label: Label = get_node_or_null("Message") as Label
@onready var _video_player: VideoStreamPlayer = get_node_or_null("VideoStreamPlayer") as VideoStreamPlayer

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _background:
		_background.modulate.a = 1.0 if start_black_immediately else 0.0
	if _message_label:
		_message_label.modulate.a = 1.0 if start_black_immediately else 0.0
	if _video_player:
		_video_player.visible = false
		_video_player.paused = true
		_fit_video_player_to_viewport()

func _fit_video_player_to_viewport() -> void:
	if _video_player == null:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	# Keep 16:9 and letterbox to avoid any stretch.
	var target_aspect := 16.0 / 9.0
	var viewport_aspect := viewport_size.x / viewport_size.y
	var fitted_size := Vector2.ZERO

	if viewport_aspect >= target_aspect:
		fitted_size.y = viewport_size.y
		fitted_size.x = fitted_size.y * target_aspect
	else:
		fitted_size.x = viewport_size.x
		fitted_size.y = fitted_size.x / target_aspect

	_video_player.anchor_left = 0.0
	_video_player.anchor_top = 0.0
	_video_player.anchor_right = 0.0
	_video_player.anchor_bottom = 0.0
	_video_player.position = (viewport_size - fitted_size) * 0.5
	_video_player.size = fitted_size

func play_embedded_video(hold_after: float = 0.5, fade_duration: float = 0.8) -> void:
	if _video_player == null:
		await _run_timeline()
		finished.emit()
		return

	_fit_video_player_to_viewport()

	if _background:
		_background.modulate.a = 1.0
	if _message_label:
		_message_label.visible = false

	_video_player.visible = true
	_video_player.modulate.a = 0.0
	_video_player.paused = false
	_video_player.play()

	var intro_fade := create_tween()
	intro_fade.tween_property(_video_player, "modulate:a", 1.0, max(fade_duration * 0.6, 0.12))
	await intro_fade.finished

	while _video_player.is_playing():
		await get_tree().process_frame

	await get_tree().create_timer(max(hold_after, 0.0)).timeout

	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(_video_player, "modulate:a", 0.0, max(fade_duration, 0.01))
	if _background:
		fade.tween_property(_background, "modulate:a", 1.0, max(fade_duration, 0.01))
	await fade.finished

	finished.emit()

func play(message_override: String = "", duration_override: float = -1.0) -> void:
	if message_override != "":
		message = message_override
	if duration_override > 0.0:
		hold_duration = duration_override
	if _message_label:
		_message_label.text = message

	await _run_timeline()
	finished.emit()

func play_lines(lines: Array[String], per_line_duration: float = 1.4) -> void:
	if lines.is_empty():
		await _run_timeline()
		finished.emit()
		return

	if _background == null or _message_label == null:
		await get_tree().create_timer(max(per_line_duration * float(lines.size()), 0.1)).timeout
		finished.emit()
		return

	_background.modulate.a = 0.0
	_message_label.modulate.a = 0.0

	var intro_fade := create_tween()
	intro_fade.tween_property(_background, "modulate:a", 1.0, max(fade_in_duration, 0.01))
	intro_fade.parallel().tween_property(_message_label, "modulate:a", 1.0, max(fade_in_duration, 0.01))
	await intro_fade.finished

	for i in range(lines.size()):
		var line_text := lines[i]
		if i > 0:
			var text_fade_out := create_tween()
			text_fade_out.tween_property(_message_label, "modulate:a", 0.0, 0.08)
			await text_fade_out.finished
		_message_label.text = line_text
		var text_fade_in := create_tween()
		text_fade_in.tween_property(_message_label, "modulate:a", 1.0, 0.08)
		await text_fade_in.finished
		await get_tree().create_timer(max(per_line_duration, 0.1)).timeout

	var outro_fade := create_tween()
	outro_fade.tween_property(_message_label, "modulate:a", 0.0, max(fade_out_duration, 0.01))
	outro_fade.parallel().tween_property(_background, "modulate:a", 0.0, max(fade_out_duration, 0.01))
	await outro_fade.finished
	finished.emit()

func fade_in_and_hold(message_override: String = "", duration_override: float = -1.0) -> void:
	if message_override != "":
		message = message_override
	if duration_override > 0.0:
		hold_duration = duration_override
	if _message_label:
		_message_label.text = message

	if _background == null or _message_label == null:
		await get_tree().create_timer(max(hold_duration, 0.1)).timeout
		return

	# Force a visible fade-in for scene transitions.
	_background.modulate.a = 0.0
	_message_label.modulate.a = 0.0

	var fade_in := create_tween()
	fade_in.tween_property(_background, "modulate:a", 1.0, max(fade_in_duration, 0.01))
	fade_in.parallel().tween_property(_message_label, "modulate:a", 1.0, max(fade_in_duration, 0.01))
	await fade_in.finished

	await get_tree().create_timer(max(hold_duration, 0.1)).timeout

func fade_out_only() -> void:
	if _background == null or _message_label == null:
		return

	var fade_out := create_tween()
	fade_out.tween_property(_message_label, "modulate:a", 0.0, max(fade_out_duration, 0.01))
	fade_out.parallel().tween_property(_background, "modulate:a", 0.0, max(fade_out_duration, 0.01))
	await fade_out.finished

func play_teleport_transition(scene_path: String, spawn_name: String, message_override: String = "", duration_override: float = -1.0, teleport_delay: float = 0.5) -> void:
	await fade_in_and_hold(message_override, duration_override)

	var scene_manager := get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("teleport_to_scene"):
		await scene_manager.teleport_to_scene(scene_path, spawn_name, teleport_delay)

	await fade_out_only()
	finished.emit()
	queue_free()

func _run_timeline() -> void:
	if _background == null or _message_label == null:
		await get_tree().create_timer(max(hold_duration, 0.1)).timeout
		return

	if start_black_immediately:
		_background.modulate.a = 1.0
		_message_label.modulate.a = 1.0
	else:
		var tween := create_tween()
		tween.tween_property(_background, "modulate:a", 1.0, max(fade_in_duration, 0.01))
		tween.parallel().tween_property(_message_label, "modulate:a", 1.0, max(fade_in_duration, 0.01))
		await tween.finished

	await get_tree().create_timer(max(hold_duration, 0.1)).timeout

	var fade_out := create_tween()
	fade_out.tween_property(_message_label, "modulate:a", 0.0, max(fade_out_duration, 0.01))
	fade_out.parallel().tween_property(_background, "modulate:a", 0.0, max(fade_out_duration, 0.01))
	await fade_out.finished
