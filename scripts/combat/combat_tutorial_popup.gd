extends Control
class_name CombatTutorialPopup

signal closed

@export var terminal_reference_image: Texture2D
@export var timing_reference_image: Texture2D
@export var nodes_reference_image: Texture2D

@onready var overlay: ColorRect = $Overlay
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var body_label: Label = $Panel/Margin/VBox/Body
@onready var reference_image: TextureRect = $Panel/Margin/VBox/ReferenceFrame/ReferenceImage
@onready var marker_layer: Control = get_node_or_null("Panel/Margin/VBox/ReferenceFrame/MarkerLayer") as Control
@onready var footer_label: Label = $Panel/Margin/VBox/Footer
@onready var continue_button: Button = $Panel/Margin/VBox/ContinueButton

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_ensure_marker_layer()
	if reference_image:
		reference_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		reference_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if continue_button and not continue_button.pressed.is_connected(_on_continue_pressed):
		continue_button.pressed.connect(_on_continue_pressed)

func show_popup(title: String, body: String, footer: String, visual_kind: String) -> void:
	title_label.text = title
	body_label.text = body
	footer_label.text = footer
	reference_image.texture = _texture_for_kind(visual_kind)
	visible = true
	call_deferred("_populate_visual_cues", visual_kind)
	continue_button.call_deferred("grab_focus")

func hide_popup() -> void:
	visible = false

func _texture_for_kind(kind: String) -> Texture2D:
	match kind:
		"timing":
			return timing_reference_image
		"nodes":
			return nodes_reference_image
		_:
			return terminal_reference_image

func _populate_visual_cues(kind: String) -> void:
	_ensure_marker_layer()
	if marker_layer == null:
		return
	marker_layer.move_to_front()

	for child in marker_layer.get_children():
		child.queue_free()

	match kind:
		"timing":
			_add_cue("YELLOW: hit (can fail)", Vector2(0.20, 0.70), Vector2(-70, -42), Color(0.95, 0.78, 0.2, 0.95))
			_add_cue("GREEN: critical", Vector2(0.50, 0.70), Vector2(-62, -42), Color(0.24, 0.72, 0.24, 0.95))
			_add_cue("RED: miss", Vector2(0.84, 0.70), Vector2(-44, -42), Color(0.7, 0.22, 0.22, 0.95))
		"nodes":
			_add_cue("Find nodes here", Vector2(0.13, 0.22), Vector2(-56, -42), Color(0.25, 0.84, 0.66, 0.95))
			_add_cue("Place nodes here", Vector2(0.47, 0.53), Vector2(-66, -42), Color(0.2, 0.78, 0.94, 0.95))
			_add_cue("Kernel start", Vector2(0.18, 0.74), Vector2(-52, -42), Color(0.26, 0.56, 0.7, 0.95))
			_add_cue("App goal", Vector2(0.78, 0.18), Vector2(-42, -42), Color(0.56, 0.7, 0.26, 0.95))
			_add_cue("Build controls", Vector2(0.64, 0.87), Vector2(-56, -42), Color(0.96, 0.74, 0.22, 0.95))
		_:
			_add_cue("Terminal Output", Vector2(0.33, 0.40), Vector2(-64, -42), Color(0.16, 0.42, 0.2, 0.95))
			_add_cue("Input", Vector2(0.33, 0.92), Vector2(-28, -42), Color(0.16, 0.3, 0.48, 0.95))
			_add_cue("Objectives", Vector2(0.89, 0.42), Vector2(-46, -42), Color(0.48, 0.38, 0.16, 0.95))

func _add_cue(text: String, normalized_anchor: Vector2, offset: Vector2, cue_color: Color) -> void:
	if marker_layer == null:
		return

	var layer_size := marker_layer.get_rect().size
	if layer_size.x <= 1.0 or layer_size.y <= 1.0:
		return

	var anchor := Vector2(layer_size.x * normalized_anchor.x, layer_size.y * normalized_anchor.y)

	var dot := ColorRect.new()
	dot.color = cue_color
	dot.custom_minimum_size = Vector2(8, 8)
	dot.position = anchor - Vector2(4, 4)
	marker_layer.add_child(dot)

	var card := PanelContainer.new()
	var card_size := Vector2(148, 32)
	var card_position := anchor + offset
	card_position.x = clampf(card_position.x, 0.0, layer_size.x - card_size.x)
	card_position.y = clampf(card_position.y, 0.0, layer_size.y - card_size.y)
	card.position = card_position
	card.custom_minimum_size = Vector2(148, 32)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.12, 0.95)
	style.border_color = cue_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	card.add_theme_stylebox_override("panel", style)
	marker_layer.add_child(card)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.95, 0.98, 0.95, 1.0))
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(label)

func _ensure_marker_layer() -> void:
	if marker_layer != null and is_instance_valid(marker_layer):
		return

	var frame := get_node_or_null("Panel/Margin/VBox/ReferenceFrame") as Control
	if frame == null:
		return

	var existing := frame.get_node_or_null("MarkerLayer")
	if existing is Control:
		marker_layer = existing as Control
		return

	var created := Control.new()
	created.name = "MarkerLayer"
	created.set_anchors_preset(Control.PRESET_FULL_RECT)
	created.mouse_filter = Control.MOUSE_FILTER_IGNORE
	created.z_index = 50
	frame.add_child(created)
	marker_layer = created

func _on_continue_pressed() -> void:
	hide_popup()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_on_continue_pressed()
		get_viewport().set_input_as_handled()
