extends Control
class_name CombatTutorialPopup

signal closed

@export var terminal_reference_image: Texture2D
@export var timing_reference_image: Texture2D
@export var nodes_reference_image: Texture2D
@export var step1_reference_image: Texture2D
@export var step2_reference_image: Texture2D
@export var step3_1_reference_image: Texture2D
@export var step4_1_reference_image: Texture2D
@export var step5_reference_image: Texture2D
@export var step6_reference_image: Texture2D
@export var map_navigation_reference_image: Texture2D
@export var talking_npc_reference_image: Texture2D
@export var quest_notes_reference_image: Texture2D
@export var shop_overview_reference_image: Texture2D
@export var skill_shop_overview_reference_image: Texture2D
@export var skill_status_reference_image: Texture2D
@export var skill_copy_reference_image: Texture2D
@export var skill_paste_reference_image: Texture2D
@export var selecting_nodes_reference_image: Texture2D
@export var app_goal_reference_image: Texture2D
@export var connect_nodes_reference_image: Texture2D
@export var reference_keys_reference_image: Texture2D
@export var reference_tutorial_done_reference_image: Texture2D

@onready var overlay: ColorRect = $Overlay
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var body_label: Label = $Panel/Margin/VBox/Body
@onready var reference_image: TextureRect = $Panel/Margin/VBox/ReferenceFrame/ReferenceImage
@onready var marker_layer: Control = get_node_or_null("Panel/Margin/VBox/ReferenceFrame/MarkerLayer") as Control
@onready var footer_label: Label = $Panel/Margin/VBox/Footer
@onready var continue_button: Button = $Panel/Margin/VBox/ContinueButton
var _placeholder_texture: Texture2D = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_placeholder_texture = _build_placeholder_texture()
	_ensure_marker_layer()
	if marker_layer:
		marker_layer.visible = false
	if overlay and not overlay.gui_input.is_connected(_on_overlay_gui_input):
		overlay.gui_input.connect(_on_overlay_gui_input)
	if reference_image:
		reference_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		reference_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if continue_button and not continue_button.pressed.is_connected(_on_continue_pressed):
		continue_button.focus_mode = Control.FOCUS_NONE
		continue_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		continue_button.pressed.connect(_on_continue_pressed)
	if continue_button and not continue_button.gui_input.is_connected(_on_continue_gui_input):
		continue_button.gui_input.connect(_on_continue_gui_input)

func show_popup(title: String, body: String, footer: String, visual_kind: String) -> void:
	title_label.text = title
	body_label.text = body
	footer_label.text = footer
	reference_image.texture = _texture_for_kind(visual_kind)
	visible = true
	continue_button.call_deferred("grab_focus")

func hide_popup() -> void:
	visible = false

func _texture_for_kind(kind: String) -> Texture2D:
	var resolved: Texture2D = null
	match kind:
		"step1":
			resolved = step1_reference_image
		"step2":
			resolved = step2_reference_image
		"step3_1":
			resolved = step3_1_reference_image
		"step4_1":
			resolved = step4_1_reference_image
		"step5":
			resolved = step5_reference_image
		"step6":
			resolved = step6_reference_image
		"map_navigation":
			resolved = map_navigation_reference_image
		"talking_npc":
			resolved = talking_npc_reference_image
		"quest_notes":
			resolved = quest_notes_reference_image
		"shop_overview":
			resolved = shop_overview_reference_image
		"skill_shop_overview":
			resolved = skill_shop_overview_reference_image
		"skill_status":
			resolved = skill_status_reference_image
		"skill_copy":
			resolved = skill_copy_reference_image
		"skill_paste":
			resolved = skill_paste_reference_image
		"timing":
			resolved = timing_reference_image
		"nodes":
			resolved = nodes_reference_image
		"selecting_nodes":
			resolved = selecting_nodes_reference_image
		"app_goal":
			resolved = app_goal_reference_image
		"connect_nodes":
			resolved = connect_nodes_reference_image
		"reference_keys":
			resolved = reference_keys_reference_image
		"reference_tutorial_done":
			resolved = reference_tutorial_done_reference_image
		_:
			resolved = terminal_reference_image
	if resolved != null:
		return resolved
	return _placeholder_texture

func _build_placeholder_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.13, 0.16, 0.2, 1.0))
	for x in range(0, 64, 8):
		for y in range(0, 64, 8):
			if int((x + y) / 8) % 2 == 0:
				image.set_pixel(x, y, Color(0.3, 0.36, 0.42, 1.0))
	return ImageTexture.create_from_image(image)

func _populate_visual_cues(_kind: String) -> void:
	_ensure_marker_layer()
	if marker_layer == null:
		return
	marker_layer.visible = false
	for child in marker_layer.get_children():
		child.queue_free()

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
	if not visible:
		return
	hide_popup()
	closed.emit()

func _on_continue_gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_continue_pressed()
		accept_event()

func _on_overlay_gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_continue_pressed()
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_continue_pressed()
		accept_event()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_on_continue_pressed()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_on_continue_pressed()
		get_viewport().set_input_as_handled()
