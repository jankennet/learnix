extends Control
class_name TuxTerminalHelperPopup

signal closed
signal hint_selected(message: String)

@export var tux_animation_texture: Texture2D = preload("res://Assets/characterSpriteSheets/ss_Tux/tux_terminal_anim.png")

@onready var overlay: ColorRect = $Overlay
@onready var window_panel: PanelContainer = $Window
@onready var title_icon: TextureRect = $Window/MarginContainer/VBox/Header/TitleIcon
@onready var title_label: Label = $Window/MarginContainer/VBox/Header/TitleStack/TitleLabel
@onready var subtitle_label: Label = $Window/MarginContainer/VBox/Header/TitleStack/SubtitleLabel
@onready var close_button: Button = $Window/MarginContainer/VBox/Header/CloseButton
@onready var body_row: HBoxContainer = $Window/MarginContainer/VBox/Body
@onready var info_column: VBoxContainer = $Window/MarginContainer/VBox/Body/InfoColumn
@onready var suggestion_label: Label = $Window/MarginContainer/VBox/Body/InfoColumn/SuggestionLabel
@onready var animation_panel: PanelContainer = $Window/MarginContainer/VBox/Body/AnimationPanel
@onready var animation_host: Control = $Window/MarginContainer/VBox/Body/AnimationPanel/AnimationHost
@onready var tux_animation: AnimatedSprite2D = $Window/MarginContainer/VBox/Body/AnimationPanel/AnimationHost/TuxAnimation
@onready var summary_label: RichTextLabel = $Window/MarginContainer/VBox/Body/InfoColumn/SummaryLabel
@onready var suggestion_flow: HFlowContainer = $Window/MarginContainer/VBox/Body/InfoColumn/SuggestionFlow
@onready var response_label: RichTextLabel = $Window/MarginContainer/VBox/Body/InfoColumn/ResponseLabel
@onready var footer_label: Label = $Window/MarginContainer/VBox/Footer

var _active_context: Dictionary = {}
var _window_expanded_offsets := Vector4(-390.0, -235.0, 390.0, 235.0)
var _window_compact_offsets := Vector4(-330.0, -180.0, 330.0, 180.0)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	if close_button and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	if title_icon and title_icon.texture == null:
		title_icon.texture = load("res://Assets/mainHUD_Icons_Tux.png")
	if title_label:
		title_label.text = "TUX HELPER"
	if subtitle_label:
		subtitle_label.text = "NPC clue assistant"
	if tux_animation:
		tux_animation.visible = true
		tux_animation.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_ensure_animation_frames()
		var animation_name := _get_preferred_animation_name()
		if animation_name != StringName():
			tux_animation.play(animation_name)

func show_helper(context: Dictionary) -> void:
	_active_context = context.duplicate(true)
	visible = true
	overlay.move_to_front()
	window_panel.move_to_front()
	var show_sprite := bool(context.get("show_sprite", true))
	_apply_layout_mode(show_sprite)
	if title_label:
		title_label.text = str(context.get("title", "TUX HELPER"))
	if subtitle_label:
		subtitle_label.text = str(context.get("subtitle", "NPC clue assistant"))
	if animation_host:
		animation_host.visible = show_sprite
	if tux_animation:
		tux_animation.visible = show_sprite
	if summary_label:
		var summary_text := str(context.get("summary", "")).strip_edges()
		summary_label.text = summary_text
		summary_label.visible = not summary_text.is_empty()
	if footer_label:
		footer_label.text = str(context.get("footer", "Pick a question, then follow terminal output if you need exact commands."))
	if response_label:
		response_label.visible = false
	_build_suggestion_buttons(context.get("suggestions", []))
	if close_button:
		close_button.call_deferred("grab_focus")

func _apply_layout_mode(show_sprite: bool) -> void:
	if window_panel:
		if show_sprite:
			window_panel.offset_left = _window_expanded_offsets.x
			window_panel.offset_top = _window_expanded_offsets.y
			window_panel.offset_right = _window_expanded_offsets.z
			window_panel.offset_bottom = _window_expanded_offsets.w
		else:
			window_panel.offset_left = _window_compact_offsets.x
			window_panel.offset_top = _window_compact_offsets.y
			window_panel.offset_right = _window_compact_offsets.z
			window_panel.offset_bottom = _window_compact_offsets.w

	if animation_panel:
		animation_panel.visible = show_sprite
		animation_panel.custom_minimum_size = Vector2(220.0, 300.0) if show_sprite else Vector2.ZERO

	if body_row:
		body_row.add_theme_constant_override("separation", 10 if show_sprite else 0)

	if info_column:
		info_column.custom_minimum_size = Vector2(0.0, 300.0) if show_sprite else Vector2(0.0, 190.0)

	if summary_label:
		summary_label.custom_minimum_size = Vector2(0.0, 84.0) if show_sprite else Vector2(0.0, 52.0)

	if suggestion_label:
		suggestion_label.text = "SUGGESTIONS" if show_sprite else "TUX ASKS"

func hide_helper() -> void:
	visible = false

func _build_suggestion_buttons(suggestions: Array) -> void:
	for child in suggestion_flow.get_children():
		child.queue_free()

	var count := 0
	for suggestion in suggestions:
		if not (suggestion is Dictionary):
			continue
		if count >= 4:
			break
		var label_text := str(suggestion.get("label", "Hint"))
		if label_text.strip_edges().is_empty():
			continue
		var button := Button.new()
		button.text = label_text
		button.custom_minimum_size = Vector2(0, 32)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_suggestion_pressed.bind(suggestion))
		suggestion_flow.add_child(button)
		count += 1

func _on_suggestion_pressed(suggestion: Dictionary) -> void:
	var detail := str(suggestion.get("detail", ""))
	var message := str(suggestion.get("message", detail))
	hint_selected.emit(message)

func _ensure_animation_frames() -> void:
	if tux_animation == null:
		return
	if tux_animation.sprite_frames != null and not tux_animation.sprite_frames.get_animation_names().is_empty():
		return
	if tux_animation_texture == null:
		return

	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 8.0)
	frames.set_animation_loop("idle", true)

	var frame_width := maxi(1, ceili(float(tux_animation_texture.get_width()) / 12.0))
	var total_width := tux_animation_texture.get_width()
	var frame_height := tux_animation_texture.get_height()
	for index in range(12):
		var start_x := index * frame_width
		if start_x >= total_width:
			break
		var atlas := AtlasTexture.new()
		atlas.atlas = tux_animation_texture
		atlas.region = Rect2(start_x, 0, mini(frame_width, total_width - start_x), frame_height)
		frames.add_frame("idle", atlas)

	tux_animation.sprite_frames = frames

func _get_preferred_animation_name() -> StringName:
	if tux_animation == null or tux_animation.sprite_frames == null:
		return StringName()
	var names := tux_animation.sprite_frames.get_animation_names()
	if names.has("idle"):
		return &"idle"
	if names.has("default"):
		return &"default"
	if not names.is_empty():
		return StringName(names[0])
	return StringName()

func _on_close_pressed() -> void:
	hide_helper()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()
