extends Control

signal intro_finished

const INTRO_VIDEO_PATH := "res://Assets/secret/LearnixIntro.ogv"
const INTRO_SKIP_HOLD_SECONDS := 0.8
const SKIP_HINT_SHOW_SECONDS := 1.25

@onready var video_player: VideoStreamPlayer = $VideoStreamPlayer
@onready var skip_hint_label: Label = $SkipHintLabel

var _hold_time := 0.0
var _is_done := false
var _hint_time_left := 0.0

func _ready() -> void:
	var stream := load(INTRO_VIDEO_PATH) as VideoStream
	if stream == null:
		_finish_intro()
		return

	video_player.stream = stream
	video_player.expand = true
	video_player.autoplay = false
	video_player.play()

	if video_player.has_signal("finished") and not video_player.finished.is_connected(_on_video_finished):
		video_player.finished.connect(_on_video_finished)

func _process(delta: float) -> void:
	if _is_done:
		return

	if _hint_time_left > 0.0:
		_hint_time_left = maxf(0.0, _hint_time_left - delta)
		skip_hint_label.visible = _hint_time_left > 0.0

	if Input.is_physical_key_pressed(KEY_SPACE):
		_hold_time += delta
		if _hold_time >= INTRO_SKIP_HOLD_SECONDS:
			_finish_intro()
	else:
		_hold_time = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if _is_done:
		return
	if event is InputEventMouseButton and event.pressed:
		_hint_time_left = SKIP_HINT_SHOW_SECONDS
		skip_hint_label.visible = true

func _on_video_finished() -> void:
	_finish_intro()

func _finish_intro() -> void:
	if _is_done:
		return
	_is_done = true
	if video_player and video_player.is_playing():
		video_player.stop()
	skip_hint_label.visible = false
	emit_signal("intro_finished")
