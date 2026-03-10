extends CanvasLayer

const TITLE_SCENE := "res://Scenes/ui/title_menu.tscn"
const MENU_ITEMS : Array[String] = ["QUICK SAVE", "LOAD", "FILE EXPLORER", "TITLE SCREEN", "SETTINGS", "QUIT GAME"]
const SETTINGS_ITEMS : Array[String] = ["CONTROLS", "GRAPHICS", "SOUND", "SAVE", "GO BACK"]
const GRAPHICS_ITEMS := ["WINDOW MODE", "RESOLUTION", "QUALITY", "APPLY", "GO BACK"]
const WINDOW_MODE_OPTIONS := ["WINDOWED", "BORDERLESS", "FULLSCREEN"]
const RESOLUTION_OPTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const QUALITY_OPTIONS := ["LOW", "MEDIUM", "HIGH"]
const QUALITY_SCALES := [0.67, 0.85, 1.0]
const HINT_MESSAGES := {
	"quick_save": "Quick save is not available yet.",
	"load": "Load is not available yet.",
	"file_explorer": "File explorer (inventory) is not available yet.",
	"controls": "Controls settings are not available yet.",
	"sound": "Sound settings are not available yet.",
	"save": "Settings save is not available yet.",
	"graphics_apply": "Graphics settings applied."
}

@onready var menu_root: Control = $MenuRoot
@onready var captured_frame: TextureRect = get_node_or_null("MenuRoot/CapturedFrame") as TextureRect
@onready var menu_vbox: VBoxContainer = $MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox
@onready var menu_labels: Array[Label] = [
	$MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox/QuickSaveLabel,
	$MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox/LoadLabel,
	$MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox/FileExplorerLabel,
	$MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox/TitleScreenLabel,
	$MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox/SettingsLabel,
	$MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox/QuitGameLabel,
]
@onready var status_label: Label = $MenuRoot/StatusLabel

var selected_index := 0
var pause_pending := false
var shader_time := 0.0
var status_time_left := 0.0
var in_settings_menu := false
var in_graphics_menu := false

var graphics_window_mode_index := 0
var graphics_resolution_index := 2
var graphics_quality_index := 2

func _process(delta: float) -> void:
	if status_time_left > 0.0:
		status_time_left = max(0.0, status_time_left - delta)
		if status_time_left == 0.0:
			status_label.visible = false

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
	status_label.visible = false
	if captured_frame:
		captured_frame.visible = false
	_update_menu_visuals()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _handle_letter_hotkey(event as InputEventKey):
			get_viewport().set_input_as_handled()
			return

	if not event.is_action_pressed("ui_cancel") and not event.is_action_pressed("ui_up") and not event.is_action_pressed("ui_down") and not event.is_action_pressed("ui_left") and not event.is_action_pressed("ui_right") and not event.is_action_pressed("ui_accept"):
		return

	if _is_title_scene_active():
		return

	if event.is_action_pressed("ui_cancel"):
		if in_graphics_menu:
			_close_graphics_menu()
			return
		if in_settings_menu:
			_close_settings_menu()
			return
		_toggle_pause()
		return

	if not get_tree().paused:
		return

	if in_graphics_menu and event.is_action_pressed("ui_left"):
		_adjust_graphics_option(-1)
		_update_menu_visuals()
		return

	if in_graphics_menu and event.is_action_pressed("ui_right"):
		_adjust_graphics_option(1)
		_update_menu_visuals()
		return

	if event.is_action_pressed("ui_up"):
		selected_index = wrapi(selected_index - 1, 0, _active_menu_items().size())
		_update_menu_visuals()
		return

	if event.is_action_pressed("ui_down"):
		selected_index = wrapi(selected_index + 1, 0, _active_menu_items().size())
		_update_menu_visuals()
		return

	if event.is_action_pressed("ui_accept"):
		_activate_selection()

func _handle_letter_hotkey(event: InputEventKey) -> bool:
	if _is_title_scene_active() or not get_tree().paused:
		return false
	if in_settings_menu:
		return false

	match event.keycode:
		KEY_S:
			_activate_menu_index(0)
			return true
		KEY_L:
			_activate_menu_index(1)
			return true
		KEY_E:
			_activate_menu_index(2)
			return true
		KEY_T:
			_activate_menu_index(3)
			return true
		KEY_C:
			_activate_menu_index(4)
			return true
		KEY_Q:
			_activate_menu_index(5)
			return true
		_:
			return false

func _activate_menu_index(index: int) -> void:
	selected_index = clampi(index, 0, _active_menu_items().size() - 1)
	_update_menu_visuals()
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
	in_settings_menu = false
	in_graphics_menu = false
	_sync_graphics_state_from_system()
	selected_index = 0
	status_label.visible = false
	status_time_left = 0.0
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
	in_settings_menu = false
	in_graphics_menu = false
	status_label.visible = false
	status_time_left = 0.0
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
	if in_graphics_menu:
		_activate_graphics_selection()
		return

	if in_settings_menu:
		_activate_settings_selection()
		return

	match selected_index:
		0:
			if _invoke_scene_manager_method("quick_save"):
				_show_status("Quick save complete.")
			else:
				_show_status(HINT_MESSAGES.quick_save)
		1:
			if _invoke_scene_manager_method("load_game") or _invoke_scene_manager_method("quick_load"):
				_show_status("Load requested.")
			else:
				_show_status(HINT_MESSAGES.load)
		2:
			_open_in_game_file_explorer()
		3:
			_resume_game()
			get_tree().change_scene_to_file(TITLE_SCENE)
		4:
			_open_settings_menu()
		5:
			get_tree().quit()

func _activate_settings_selection() -> void:
	match selected_index:
		0:
			_show_status(HINT_MESSAGES.controls)
		1:
			_open_graphics_menu()
		2:
			_show_status(HINT_MESSAGES.sound)
		3:
			if _invoke_scene_manager_method("save_settings") or _invoke_scene_manager_method("save_game"):
				_show_status("Save requested.")
			else:
				_show_status(HINT_MESSAGES.save)
		4:
			_close_settings_menu()

func _activate_graphics_selection() -> void:
	match selected_index:
		0:
			_adjust_graphics_option(1)
			_update_menu_visuals()
		1:
			_adjust_graphics_option(1)
			_update_menu_visuals()
		2:
			_adjust_graphics_option(1)
			_update_menu_visuals()
		3:
			_apply_graphics_settings()
		4:
			_close_graphics_menu()

func _open_settings_menu() -> void:
	in_settings_menu = true
	in_graphics_menu = false
	selected_index = 0
	_update_menu_visuals()

func _close_settings_menu() -> void:
	in_settings_menu = false
	in_graphics_menu = false
	selected_index = 4
	_update_menu_visuals()

func _open_graphics_menu() -> void:
	in_graphics_menu = true
	selected_index = 0
	_update_menu_visuals()

func _close_graphics_menu() -> void:
	in_graphics_menu = false
	selected_index = 1
	_update_menu_visuals()

func _active_menu_items() -> Array[String]:
	if in_graphics_menu:
		return _build_graphics_menu_items()
	return SETTINGS_ITEMS if in_settings_menu else MENU_ITEMS

func _build_graphics_menu_items() -> Array[String]:
	var resolution :Vector2i = RESOLUTION_OPTIONS[graphics_resolution_index]
	return [
		"WINDOW MODE: %s" % WINDOW_MODE_OPTIONS[graphics_window_mode_index],
		"RESOLUTION: %dx%d" % [resolution.x, resolution.y],
		"QUALITY: %s" % QUALITY_OPTIONS[graphics_quality_index],
		"APPLY",
		"GO BACK"
	]

func _adjust_graphics_option(direction: int) -> void:
	match selected_index:
		0:
			graphics_window_mode_index = wrapi(graphics_window_mode_index + direction, 0, WINDOW_MODE_OPTIONS.size())
		1:
			graphics_resolution_index = wrapi(graphics_resolution_index + direction, 0, RESOLUTION_OPTIONS.size())
		2:
			graphics_quality_index = wrapi(graphics_quality_index + direction, 0, QUALITY_OPTIONS.size())
		_:
			return

func _sync_graphics_state_from_system() -> void:
	var mode := DisplayServer.window_get_mode()
	var borderless := DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		graphics_window_mode_index = 2
	elif borderless:
		graphics_window_mode_index = 1
	else:
		graphics_window_mode_index = 0

	var current_size := DisplayServer.window_get_size()
	graphics_resolution_index = _nearest_resolution_index(current_size)

func _nearest_resolution_index(size: Vector2i) -> int:
	var nearest_index := 0
	var nearest_distance := INF
	for i in RESOLUTION_OPTIONS.size():
		var option_size :Vector2i = RESOLUTION_OPTIONS[i]
		var dx := float(option_size.x - size.x)
		var dy := float(option_size.y - size.y)
		var distance := dx * dx + dy * dy
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = i
	return nearest_index

func _apply_graphics_settings() -> void:
	match graphics_window_mode_index:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	if graphics_window_mode_index != 2:
		DisplayServer.window_set_size(RESOLUTION_OPTIONS[graphics_resolution_index])

	_apply_quality_preset()
	_show_status(HINT_MESSAGES.graphics_apply)

func _apply_quality_preset() -> void:
	var viewport := get_viewport()
	if not viewport:
		return

	match graphics_quality_index:
		0:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
		1:
			viewport.msaa_3d = Viewport.MSAA_2X
		2:
			viewport.msaa_3d = Viewport.MSAA_4X

	for property_info in viewport.get_property_list():
		if str(property_info.name) == "scaling_3d_scale":
			viewport.set("scaling_3d_scale", QUALITY_SCALES[graphics_quality_index])
			break

func _update_menu_visuals() -> void:
	var active_items := _active_menu_items()
	for i in menu_labels.size():
		var option_label := menu_labels[i]
		if i >= active_items.size():
			option_label.visible = false
			continue

		option_label.visible = true
		if i == selected_index:
			option_label.text = "# " + active_items[i]
			option_label.modulate = Color(0.95, 0.97, 1.0)
		else:
			option_label.text = "  " + active_items[i]
			option_label.modulate = Color(0.53, 0.68, 0.88)

func _show_status(message: String) -> void:
	status_label.text = message
	status_label.visible = true
	status_time_left = 2.0

func _invoke_scene_manager_method(method_name: String) -> bool:
	if SceneManager and SceneManager.has_method(method_name):
		SceneManager.call(method_name)
		return true
	return false

func _open_in_game_file_explorer() -> void:
	var method_candidates := ["open_file_explorer", "open_inventory", "toggle_inventory"]
	for method_name in method_candidates:
		if SceneManager and SceneManager.has_method(method_name):
			_resume_game()
			SceneManager.call_deferred(method_name)
			return

	var current_scene := get_tree().current_scene
	if current_scene:
		for method_name in method_candidates:
			if current_scene.has_method(method_name):
				_resume_game()
				current_scene.call_deferred(method_name)
				return

	_show_status(HINT_MESSAGES.file_explorer)

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
