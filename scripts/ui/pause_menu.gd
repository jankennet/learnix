extends CanvasLayer

const TITLE_SCENE := "res://Scenes/ui/title_menu.tscn"
const MENU_ITEMS := ["RESUME", "SETTINGS", "QUIT TO TITLE", "QUIT GAME"]

@onready var menu_root: Control = $MenuRoot
@onready var captured_frame: TextureRect = get_node_or_null("MenuRoot/CapturedFrame") as TextureRect
@onready var menu_vbox: VBoxContainer = $MenuRoot/CenterContainer/PanelContainer/VBoxContainer
@onready var menu_labels: Array[Label] = [
	$MenuRoot/CenterContainer/PanelContainer/VBoxContainer/ResumeLabel,
	$MenuRoot/CenterContainer/PanelContainer/VBoxContainer/SettingsLabel,
	$MenuRoot/CenterContainer/PanelContainer/VBoxContainer/QuitTitleLabel,
	$MenuRoot/CenterContainer/PanelContainer/VBoxContainer/QuitGameLabel,
]
@onready var settings_label: Label = $MenuRoot/CenterContainer/PanelContainer/VBoxContainer/SettingsOverlay

var selected_index := 0
var in_settings := false
var pause_pending := false
var shader_time := 0.0

func _process(delta: float) -> void:
	if not visible or not get_tree().paused:
		return
	if not captured_frame or not captured_frame.visible:
		return
	shader_time += delta
	var shader_material := captured_frame.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("custom_time", shader_time)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	menu_root.visible = false
	settings_label.visible = false
	if captured_frame:
		captured_frame.visible = false
	_update_menu_visuals()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") and not event.is_action_pressed("ui_up") and not event.is_action_pressed("ui_down") and not event.is_action_pressed("ui_accept"):
		return

	if _is_title_scene_active():
		return

	if event.is_action_pressed("ui_cancel"):
		if in_settings:
			in_settings = false
			settings_label.visible = false
			menu_vbox.visible = true
			return
		_toggle_pause()
		return

	if not get_tree().paused:
		return

	if in_settings and event.is_action_pressed("ui_accept"):
		in_settings = false
		settings_label.visible = false
		menu_vbox.visible = true
		return

	if in_settings:
		return

	if event.is_action_pressed("ui_up"):
		selected_index = wrapi(selected_index - 1, 0, MENU_ITEMS.size())
		_update_menu_visuals()
		return

	if event.is_action_pressed("ui_down"):
		selected_index = wrapi(selected_index + 1, 0, MENU_ITEMS.size())
		_update_menu_visuals()
		return

	if event.is_action_pressed("ui_accept"):
		_activate_selection()

func _toggle_pause() -> void:
	if get_tree().paused:
		_resume_game()
	else:
		_pause_game()

func _pause_game() -> void:
	if pause_pending:
		return
	pause_pending = true
	shader_time = 0.0
	_set_global_ui_visibility(false)
	call_deferred("_complete_pause")

func _complete_pause() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture_current_frame()
	visible = true
	menu_root.visible = true
	in_settings = false
	settings_label.visible = false
	menu_vbox.visible = true
	_update_menu_visuals()
	get_tree().paused = true
	pause_pending = false

func _resume_game() -> void:
	pause_pending = false
	get_tree().paused = false
	visible = false
	menu_root.visible = false
	if captured_frame:
		captured_frame.visible = false
		captured_frame.texture = null
	in_settings = false
	settings_label.visible = false
	menu_vbox.visible = true
	_set_global_ui_visibility(true)

func _capture_current_frame() -> void:
	var viewport := get_viewport()
	if not viewport:
		return

	var viewport_texture := viewport.get_texture()
	if not viewport_texture:
		return

	var image := viewport_texture.get_image()
	if image.is_empty():
		return

	if captured_frame:
		captured_frame.texture = ImageTexture.create_from_image(image)
		captured_frame.visible = true

func _activate_selection() -> void:
	match selected_index:
		0:
			_resume_game()
		1:
			in_settings = true
			settings_label.visible = true
			menu_vbox.visible = false
		2:
			_resume_game()
			get_tree().change_scene_to_file(TITLE_SCENE)
		3:
			get_tree().quit()

func _update_menu_visuals() -> void:
	for i in menu_labels.size():
		var option_label := menu_labels[i]
		if i == selected_index:
			option_label.text = "# " + MENU_ITEMS[i]
			option_label.modulate = Color(0.92, 0.92, 0.92)
		else:
			option_label.text = "  " + MENU_ITEMS[i]
			option_label.modulate = Color(0.55, 0.55, 0.55)

func _set_global_ui_visibility(visible_state: bool) -> void:
	var controls_help := get_node_or_null("/root/ControlsHelp")
	if controls_help:
		controls_help.visible = visible_state
		var controls_container := controls_help.get_node_or_null("MarginContainer")
		if controls_container:
			controls_container.visible = visible_state

	var interaction_prompt := get_node_or_null("/root/InteractionPrompt")
	if interaction_prompt:
		interaction_prompt.visible = visible_state

func _is_title_scene_active() -> bool:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return false
	return current_scene.scene_file_path == TITLE_SCENE
