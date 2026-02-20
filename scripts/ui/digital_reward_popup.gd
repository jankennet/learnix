extends CanvasLayer
class_name DigitalRewardPopup

const FONT_PATH := "res://Assets/fonts/PressStart2P-Regular.ttf"

var _backdrop: ColorRect
var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _key_text: Label
var _hint_text: Label
var _icon: ProficiencyKeyIcon
var _dismiss_ready: bool = false

func show_key_reward(key_name: String) -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui(key_name)
	await _play_animation()
	_dismiss_ready = true

func _build_ui(key_name: String) -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0, 0.02, 0.06, 0)
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(680, 220)
	_panel.modulate = Color(1, 1, 1, 0)
	_panel.scale = Vector2(0.85, 0.85)
	center.add_child(_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.08, 0.16, 0.96)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.23, 0.95, 1.0, 1.0)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var root_hbox := HBoxContainer.new()
	root_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	root_hbox.add_theme_constant_override("separation", 22)
	margin.add_child(root_hbox)

	var icon_holder := CenterContainer.new()
	icon_holder.custom_minimum_size = Vector2(150, 150)
	root_hbox.add_child(icon_holder)

	_icon = ProficiencyKeyIcon.new()
	_icon.scale = Vector2(1.2, 1.2)
	icon_holder.add_child(_icon)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_theme_constant_override("separation", 10)
	root_hbox.add_child(text_box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.text = "KEY ACQUIRED"
	_title.add_theme_color_override("font_color", Color(0.34, 0.95, 1.0, 1.0))
	_title.add_theme_font_size_override("font_size", 30)
	text_box.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_subtitle.text = "<< DIGITAL REWARD UNLOCKED >>"
	_subtitle.add_theme_color_override("font_color", Color(0.72, 0.84, 1.0, 1.0))
	_subtitle.add_theme_font_size_override("font_size", 16)
	text_box.add_child(_subtitle)

	_key_text = Label.new()
	_key_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_key_text.text = key_name
	_key_text.add_theme_color_override("font_color", Color(1.0, 0.96, 0.55, 1.0))
	_key_text.add_theme_font_size_override("font_size", 20)
	text_box.add_child(_key_text)

	_hint_text = Label.new()
	_hint_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint_text.text = "[ CLICK ANYWHERE TO CONTINUE ]"
	_hint_text.add_theme_color_override("font_color", Color(0.58, 1.0, 0.92, 0.85))
	_hint_text.add_theme_font_size_override("font_size", 12)
	_hint_text.modulate = Color(1, 1, 1, 0)
	text_box.add_child(_hint_text)

	if ResourceLoader.exists(FONT_PATH):
		var font := load(FONT_PATH)
		_title.add_theme_font_override("font", font)
		_subtitle.add_theme_font_override("font", font)
		_key_text.add_theme_font_override("font", font)
		_hint_text.add_theme_font_override("font", font)

func _play_animation() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_backdrop, "color:a", 0.62, 0.18)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.18)
	tween.tween_property(_panel, "scale", Vector2(1.02, 1.02), 0.20)
	await tween.finished

	var settle := create_tween()
	settle.tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.12)
	await settle.finished

	for i in range(3):
		_key_text.modulate = Color(0.4, 1.0, 1.0, 1.0)
		await get_tree().create_timer(0.08).timeout
		_key_text.modulate = Color(1.0, 0.96, 0.55, 1.0)
		await get_tree().create_timer(0.08).timeout

	var hint_fade := create_tween()
	hint_fade.tween_property(_hint_text, "modulate:a", 1.0, 0.2)

func _unhandled_input(event: InputEvent) -> void:
	if not _dismiss_ready:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		await _dismiss()

func _dismiss() -> void:
	_dismiss_ready = false
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(_panel, "modulate:a", 0.0, 0.18)
	fade.tween_property(_backdrop, "color:a", 0.0, 0.18)
	await fade.finished
	queue_free()
