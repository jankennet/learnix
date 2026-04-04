extends CanvasLayer

const TITLE_SCENE := "res://Scenes/ui/title_menu.tscn"
const MENU_ITEMS : Array[String] = ["QUICK SAVE", "LOAD", "FILE EXPLORER", "TITLE SCREEN", "SETTINGS", "QUIT GAME"]
const SETTINGS_ITEMS : Array[String] = ["CONTROLS", "GRAPHICS", "SOUND", "SAVE", "GO BACK"]
const WINDOW_MODE_OPTIONS := ["WINDOWED", "BORDERLESS", "FULLSCREEN"]
const RESOLUTION_OPTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const QUALITY_OPTIONS := ["LOW", "MEDIUM", "HIGH"]
const QUALITY_SCALES := [0.67, 0.85, 1.0]
const BASE_EXPLORER_FOLDERS := ["Desktop", "Filesystem_Forest", "Deamon_Depths"]
const BIOS_VAULT_FOLDER := "Bios_Vault"
const CITADEL_FOLDER := "Proprietary_Citadel"
const NPC_EXPLORER_ENTRIES := {
	"Messy Directory": [
		{
			"folder": "Desktop",
			"filename": "messy_directory.txt",
			"title": "Messy Directory",
			"content": "Guardian of scattered folders. Lesson: organize directories and keep backups before destructive commands.",
		},
	],
	"Elder Shell": [
		{
			"folder": "Desktop",
			"filename": "elder_shell.txt",
			"title": "Elder Shell",
			"content": "A patient mentor process. Lesson: understand commands before executing them.",
		},
	],
	"Broken Installer": [
		{
			"folder": "Desktop",
			"filename": "broken_installer.txt",
			"title": "Broken Installer",
			"content": "Dependency panic personified. Lesson: keep package indexes updated and verify missing dependencies.",
		},
	],
	"Lost File": [
		{
			"folder": "Desktop",
			"filename": "lost_file.txt",
			"title": "Lost File",
			"content": "A fragmented document searching for identity. Lesson: accidental deletes hurt; recovery and empathy matter.",
		},
		{
			"folder": "Filesystem_Forest",
			"filename": "lost_file_forest.txt",
			"title": "Lost File (Forest)",
			"content": "Recovered from unstable sectors in the forest. Lesson: locate, restore, decrypt, and verify data integrity.",
		},
	],
	"Gate Keeper": [
		{
			"folder": "Desktop",
			"filename": "gate_keeper.txt",
			"title": "Gate Keeper",
			"content": "Policy-aware gate service. Lesson: access is earned through demonstrated system proficiency.",
		},
	],
	"Mount Whisperer": [
		{
			"folder": "Desktop",
			"filename": "mount_whisperer.txt",
			"title": "Mount Whisperer",
			"content": "Sees ghosts in mounted drives. Lesson: mount cleanly, unmount before removal, and read logs like they remember everything.",
		},
	],
	"Broken Link": [
		{
			"folder": "Filesystem_Forest",
			"filename": "broken_link.txt",
			"title": "Broken Link",
			"content": "A corrupted shortcut node. Lesson: troubleshoot paths methodically and patch references safely.",
		},
	],
	"Hardware Ghost": [
		{
			"folder": "Deamon_Depths",
			"filename": "hardware_ghost.txt",
			"title": "Hardware Ghost",
			"content": "Echoes of legacy hardware layers. Lesson: old systems still shape modern runtime behavior.",
		},
	],
	"Driver Remnant": [
		{
			"folder": "Deamon_Depths",
			"filename": "driver_remnant.txt",
			"title": "Driver Remnant",
			"content": "An unstable leftover driver process. Lesson: remove stale drivers and isolate failing components.",
		},
	],
	"Printer Boss": [
		{
			"folder": "Deamon_Depths",
			"filename": "printer_beast.txt",
			"title": "Printer Beast",
			"content": "A queue-jamming daemon boss. Lesson: monitor services, permissions, and error logs under pressure.",
		},
	],
}
const HINT_MESSAGES := {
	"quick_save": "Quick save is not available yet.",
	"load": "Load is not available yet.",
	"file_explorer": "No discoverable files yet. Talk to NPCs first.",
	"controls": "Controls settings are not available yet.",
	"sound": "Sound settings are not available yet.",
	"save": "Settings save is not available yet.",
	"graphics_apply": "Graphics settings applied."
}

@onready var menu_root: Control = $MenuRoot
@onready var captured_frame: TextureRect = get_node_or_null("MenuRoot/CapturedFrame") as TextureRect
@onready var darken_overlay: CanvasItem = get_node_or_null("MenuRoot/DarkenOverlay") as CanvasItem
@onready var pause_content_margin: CanvasItem = get_node_or_null("MenuRoot/ContentMargin") as CanvasItem
@onready var menu_vbox: VBoxContainer = $MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox
@onready var key_hint_vbox: CanvasItem = get_node_or_null("MenuRoot/ContentMargin/MainColumn/MenuRow/KeyHintVBox") as CanvasItem
@onready var menu_labels: Array[Label] = [
	$MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox/QuickSaveLabel,
	$MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox/LoadLabel,
	$MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox/FileExplorerLabel,
	$MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox/TitleScreenLabel,
	$MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox/SettingsLabel,
	$MenuRoot/ContentMargin/MainColumn/MenuRow/MenuVBox/QuitGameLabel,
]
@onready var status_label: Label = $MenuRoot/StatusLabel
@onready var file_explorer_window: Control = $MenuRoot/FileExplorerWindow
@onready var explorer_address_label: Label = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/TopBar/AddressLabel
@onready var explorer_folder_label: Label = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/Body/ContentPanel/ContentMargin/ContentVBox/FolderLabel
@onready var explorer_sidebar_list: ItemList = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/Body/SidebarPanel/SidebarMargin/SidebarList
@onready var explorer_file_list: ItemList = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/Body/ContentPanel/ContentMargin/ContentVBox/FileList
@onready var explorer_preview_label: RichTextLabel = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/Body/ContentPanel/ContentMargin/ContentVBox/PreviewLabel
@onready var explorer_close_button: Button = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/TopBar/CloseButton
@onready var explorer_top_bar: Control = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/TopBar

var selected_index := 0
var pause_pending := false
var shader_time := 0.0
var status_time_left := 0.0
var in_settings_menu := false
var in_graphics_menu := false
var in_file_explorer := false
var explorer_opened_from_main_ui := false
var explorer_selected_folder := "Desktop"
var explorer_dragging := false
var explorer_last_mouse_global := Vector2.ZERO
var hovered_index := -1

var confirmation_dialog: ConfirmationDialog = null
var confirmation_mode := ""
var quit_main_menu_button: Button = null
var controls_dialog: AcceptDialog = null
var sound_dialog: AcceptDialog = null
var sound_master_slider: HSlider = null
var sound_music_slider: HSlider = null
var sound_sfx_slider: HSlider = null

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
	if file_explorer_window:
		file_explorer_window.visible = false
	if explorer_close_button and not explorer_close_button.pressed.is_connected(_close_file_explorer):
		explorer_close_button.pressed.connect(_close_file_explorer)
	if explorer_top_bar and not explorer_top_bar.gui_input.is_connected(_on_explorer_top_bar_gui_input):
		explorer_top_bar.gui_input.connect(_on_explorer_top_bar_gui_input)
	if explorer_sidebar_list and not explorer_sidebar_list.item_selected.is_connected(_on_explorer_folder_selected):
		explorer_sidebar_list.item_selected.connect(_on_explorer_folder_selected)
	if explorer_file_list and not explorer_file_list.item_selected.is_connected(_on_explorer_item_selected):
		explorer_file_list.item_selected.connect(_on_explorer_item_selected)
	if explorer_file_list and not explorer_file_list.item_activated.is_connected(_on_explorer_item_activated):
		explorer_file_list.item_activated.connect(_on_explorer_item_activated)
	if explorer_top_bar:
		explorer_top_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	if key_hint_vbox:
		key_hint_vbox.visible = false
	_setup_menu_label_mouse()
	_setup_confirmation_dialog()
	_setup_controls_dialog()
	_setup_sound_dialog()
	_update_menu_visuals()

func _input(event: InputEvent) -> void:
	if not in_file_explorer or not file_explorer_window or not file_explorer_window.visible:
		return

	if explorer_dragging and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_update_explorer_drag(motion.global_position)
		get_viewport().set_input_as_handled()
		return

	if explorer_dragging and event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed:
			explorer_dragging = false
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _is_title_scene_active():
		return

	if not event.is_action_pressed("ui_cancel") and not event.is_action_pressed("ui_up") and not event.is_action_pressed("ui_down") and not event.is_action_pressed("ui_left") and not event.is_action_pressed("ui_right") and not event.is_action_pressed("ui_accept"):
		return

	if event.is_action_pressed("ui_cancel"):
		if in_file_explorer:
			_close_file_explorer()
			return
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

	if in_file_explorer:
		if event.is_action_pressed("ui_accept"):
			_activate_explorer_selected_item()
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
	in_file_explorer = false
	_sync_graphics_state_from_system()
	selected_index = 0
	status_label.visible = false
	status_time_left = 0.0
	if file_explorer_window:
		file_explorer_window.visible = false
	_set_pause_chrome_visible(true)
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
	in_file_explorer = false
	explorer_opened_from_main_ui = false
	status_label.visible = false
	status_time_left = 0.0
	if file_explorer_window:
		file_explorer_window.visible = false
	_set_pause_chrome_visible(true)
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

	var active_items := _active_menu_items()
	if selected_index < 0 or selected_index >= active_items.size():
		return
	var selected_item := active_items[selected_index]

	match selected_item:
		"QUICK SAVE":
			if _invoke_scene_manager_method("quick_save"):
				_show_status("Quick save complete.")
			else:
				_show_status(HINT_MESSAGES.quick_save)
		"LOAD":
			_request_load_confirmation()
		"FILE EXPLORER":
			_open_in_game_file_explorer()
		"TITLE SCREEN":
			_resume_game()
			get_tree().change_scene_to_file(TITLE_SCENE)
		"SETTINGS":
			_open_settings_menu()
		"QUIT GAME":
			_request_quit_confirmation()
		_:
			pass

func _activate_settings_selection() -> void:
	match selected_index:
		0:
			_open_controls_dialog()
		1:
			_open_graphics_menu()
		2:
			_open_sound_dialog()
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
	var active_items := _active_menu_items()
	selected_index = active_items.find("SETTINGS")
	if selected_index < 0:
		selected_index = 0
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
	if in_settings_menu:
		return SETTINGS_ITEMS
	
	# Filter menu items based on unlock status
	var active_items := MENU_ITEMS.duplicate()
	if not _is_file_explorer_unlocked():
		active_items.erase("FILE EXPLORER")
	return active_items

func _build_graphics_menu_items() -> Array[String]:
	var resolution :Vector2i = RESOLUTION_OPTIONS[graphics_resolution_index]
	return [
		"WINDOW MODE: %s" % WINDOW_MODE_OPTIONS[graphics_window_mode_index],
		"RESOLUTION: %dx%d" % [resolution.x, resolution.y],
		"QUALITY: %s" % QUALITY_OPTIONS[graphics_quality_index],
		"APPLY",
		"GO BACK"
	]

func _is_file_explorer_unlocked() -> bool:
	if not has_node("/root/SceneManager") or not SceneManager:
		return false
	return SceneManager.get("file_explorer_unlocked") == true

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
	var display_index := selected_index
	if hovered_index >= 0 and hovered_index < active_items.size():
		display_index = hovered_index
	for i in menu_labels.size():
		var option_label := menu_labels[i]
		if i >= active_items.size():
			option_label.visible = false
			continue

		option_label.visible = true
		if i == display_index:
			option_label.text = "# " + active_items[i]
			option_label.modulate = Color(0.95, 0.97, 1.0)
		else:
			option_label.text = "  " + active_items[i]
			option_label.modulate = Color(0.53, 0.68, 0.88)

func _setup_menu_label_mouse() -> void:
	for i in menu_labels.size():
		var label := menu_labels[i]
		if label == null:
			continue
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if not label.gui_input.is_connected(_on_menu_label_gui_input):
			label.gui_input.connect(_on_menu_label_gui_input.bind(i))
		if not label.mouse_entered.is_connected(_on_menu_label_mouse_entered):
			label.mouse_entered.connect(_on_menu_label_mouse_entered.bind(i))
		if not label.mouse_exited.is_connected(_on_menu_label_mouse_exited):
			label.mouse_exited.connect(_on_menu_label_mouse_exited.bind(i))

func _on_menu_label_gui_input(event: InputEvent, index: int) -> void:
	if not get_tree().paused or in_file_explorer:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var active_count := _active_menu_items().size()
		if index < 0 or index >= active_count:
			return
		hovered_index = index
		selected_index = index
		_update_menu_visuals()
		_activate_selection()
		get_viewport().set_input_as_handled()

func _on_menu_label_mouse_entered(index: int) -> void:
	if not get_tree().paused or in_file_explorer:
		return
	var active_count := _active_menu_items().size()
	if index < 0 or index >= active_count:
		return
	hovered_index = index
	selected_index = index
	_update_menu_visuals()

func _on_menu_label_mouse_exited(_index: int) -> void:
	hovered_index = -1
	_update_menu_visuals()

func _setup_confirmation_dialog() -> void:
	confirmation_dialog = ConfirmationDialog.new()
	confirmation_dialog.name = "PauseConfirmationDialog"
	confirmation_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	confirmation_dialog.exclusive = true
	add_child(confirmation_dialog)
	if not confirmation_dialog.confirmed.is_connected(_on_confirmation_dialog_confirmed):
		confirmation_dialog.confirmed.connect(_on_confirmation_dialog_confirmed)
	if not confirmation_dialog.custom_action.is_connected(_on_confirmation_dialog_custom_action):
		confirmation_dialog.custom_action.connect(_on_confirmation_dialog_custom_action)

func _request_load_confirmation() -> void:
	var summary := _get_load_summary_text()
	confirmation_mode = "load"
	if quit_main_menu_button and is_instance_valid(quit_main_menu_button):
		quit_main_menu_button.visible = false
	confirmation_dialog.title = "Load Save"
	confirmation_dialog.dialog_text = "Want to load %s?" % summary
	confirmation_dialog.ok_button_text = "Load"
	confirmation_dialog.popup_centered(Vector2i(560, 180))

func _request_quit_confirmation() -> void:
	confirmation_mode = "quit"
	if quit_main_menu_button == null or not is_instance_valid(quit_main_menu_button):
		quit_main_menu_button = confirmation_dialog.add_button("Main Menu", true, "to_main_menu")
	quit_main_menu_button.visible = true
	confirmation_dialog.title = "Quit Game"
	confirmation_dialog.dialog_text = "Where do you want to go?"
	confirmation_dialog.ok_button_text = "Quit to Desktop"
	confirmation_dialog.popup_centered(Vector2i(560, 180))

func _on_confirmation_dialog_confirmed() -> void:
	if confirmation_dialog:
		confirmation_dialog.hide()
	match confirmation_mode:
		"load":
			if _invoke_scene_manager_method("load_game") or _invoke_scene_manager_method("quick_load"):
				_show_status("Load requested.")
			else:
				_show_status(HINT_MESSAGES.load)
		"quit":
			get_tree().quit()
		_:
			pass
	confirmation_mode = ""

func _on_confirmation_dialog_custom_action(action: StringName) -> void:
	if confirmation_dialog:
		confirmation_dialog.hide()
	if confirmation_mode == "quit" and String(action) == "to_main_menu":
		_resume_game()
		get_tree().change_scene_to_file(TITLE_SCENE)
	confirmation_mode = ""

func _get_load_summary_text() -> String:
	if SceneManager and SceneManager.has_method("get_save_summary"):
		var summary: Dictionary = SceneManager.get_save_summary()
		if not summary.is_empty():
			var saved_time := String(summary.get("saved_at_text", "Unknown time"))
			var location := String(summary.get("location", "Unknown Area"))
			return "%s at %s" % [location, saved_time]
	return "the latest save"

func _setup_controls_dialog() -> void:
	controls_dialog = AcceptDialog.new()
	controls_dialog.name = "PauseControlsDialog"
	controls_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	controls_dialog.exclusive = true
	controls_dialog.title = "Controls"
	controls_dialog.ok_button_text = "Close"
	controls_dialog.dialog_text = "Move: WASD\nRun: Shift\nInteract: E\nConfirm: Enter\nCancel/Pause: Esc"
	add_child(controls_dialog)

func _open_controls_dialog() -> void:
	if controls_dialog == null:
		return
	controls_dialog.popup_centered(Vector2i(520, 260))

func _setup_sound_dialog() -> void:
	sound_dialog = AcceptDialog.new()
	sound_dialog.name = "PauseSoundDialog"
	sound_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	sound_dialog.exclusive = true
	sound_dialog.title = "Sound"
	sound_dialog.ok_button_text = "Close"
	sound_dialog.dialog_text = ""
	add_child(sound_dialog)

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(420, 140)
	content.add_theme_constant_override("separation", 8)
	sound_dialog.add_child(content)

	var master_row := HBoxContainer.new()
	content.add_child(master_row)
	var master_label := Label.new()
	master_label.text = "Master"
	master_label.custom_minimum_size = Vector2(90, 0)
	master_row.add_child(master_label)
	sound_master_slider = HSlider.new()
	sound_master_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_master_slider.min_value = 0.0
	sound_master_slider.max_value = 1.0
	sound_master_slider.step = 0.01
	sound_master_slider.value_changed.connect(_on_sound_slider_changed.bind("Master"))
	master_row.add_child(sound_master_slider)

	var music_row := HBoxContainer.new()
	content.add_child(music_row)
	var music_label := Label.new()
	music_label.text = "Music"
	music_label.custom_minimum_size = Vector2(90, 0)
	music_row.add_child(music_label)
	sound_music_slider = HSlider.new()
	sound_music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_music_slider.min_value = 0.0
	sound_music_slider.max_value = 1.0
	sound_music_slider.step = 0.01
	sound_music_slider.value_changed.connect(_on_sound_slider_changed.bind("Music"))
	music_row.add_child(sound_music_slider)

	var sfx_row := HBoxContainer.new()
	content.add_child(sfx_row)
	var sfx_label := Label.new()
	sfx_label.text = "SFX"
	sfx_label.custom_minimum_size = Vector2(90, 0)
	sfx_row.add_child(sfx_label)
	sound_sfx_slider = HSlider.new()
	sound_sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_sfx_slider.min_value = 0.0
	sound_sfx_slider.max_value = 1.0
	sound_sfx_slider.step = 0.01
	sound_sfx_slider.value_changed.connect(_on_sound_slider_changed.bind("SFX"))
	sfx_row.add_child(sound_sfx_slider)

func _open_sound_dialog() -> void:
	if sound_dialog == null:
		return
	_sync_sound_dialog_from_audio()
	sound_dialog.popup_centered(Vector2i(560, 260))

func _find_bus_index(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		return idx
	var target := bus_name.to_lower()
	for i in range(AudioServer.get_bus_count()):
		var n := AudioServer.get_bus_name(i)
		if n and n.to_lower() == target:
			return i
	return -1

func _sync_sound_dialog_from_audio() -> void:
	if sound_master_slider:
		var master_idx := _find_bus_index("Master")
		sound_master_slider.value = db_to_linear(AudioServer.get_bus_volume_db(master_idx)) if master_idx != -1 else 1.0
	if sound_music_slider:
		var music_idx := _find_bus_index("Music")
		if music_idx == -1:
			music_idx = _find_bus_index("Master")
		sound_music_slider.value = db_to_linear(AudioServer.get_bus_volume_db(music_idx)) if music_idx != -1 else 1.0
	if sound_sfx_slider:
		var sfx_idx := _find_bus_index("SFX")
		if sfx_idx == -1:
			sfx_idx = _find_bus_index("Master")
		sound_sfx_slider.value = db_to_linear(AudioServer.get_bus_volume_db(sfx_idx)) if sfx_idx != -1 else 1.0

func _on_sound_slider_changed(value: float, bus_name: String) -> void:
	var bus_index := _find_bus_index(bus_name)
	if bus_index == -1:
		bus_index = _find_bus_index("Master")
	if bus_index == -1:
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))
	AudioServer.set_bus_mute(bus_index, value <= 0.001)

func _show_status(message: String) -> void:
	status_label.text = message
	status_label.visible = true
	status_time_left = 2.0

func _invoke_scene_manager_method(method_name: String) -> bool:
	if SceneManager and SceneManager.has_method(method_name):
		return bool(SceneManager.call(method_name))
	return false

func _open_in_game_file_explorer() -> void:
	if not get_tree().paused:
		_pause_game()
		return

	if not _has_any_discoverable_file():
		_show_status(HINT_MESSAGES.file_explorer)
		return

	_open_file_explorer()

func open_file_explorer_from_main_ui() -> void:
	if _is_title_scene_active():
		return
	if not _is_file_explorer_unlocked():
		return

	visible = true
	menu_root.visible = true
	explorer_opened_from_main_ui = true
	in_settings_menu = false
	in_graphics_menu = false
	selected_index = 2
	_set_pause_chrome_visible(false)

	if captured_frame:
		captured_frame.visible = false
		captured_frame.texture = null

	_open_file_explorer()

func _open_file_explorer() -> void:
	in_file_explorer = true
	explorer_dragging = false
	status_label.visible = false
	status_time_left = 0.0
	if file_explorer_window:
		file_explorer_window.visible = true
	_refresh_explorer_sidebar(explorer_selected_folder)

func _close_file_explorer() -> void:
	in_file_explorer = false
	explorer_dragging = false
	if file_explorer_window:
		file_explorer_window.visible = false

	if explorer_opened_from_main_ui and not get_tree().paused:
		explorer_opened_from_main_ui = false
		_set_pause_chrome_visible(true)
		visible = false
		menu_root.visible = false
		return

	_update_menu_visuals()

func _maybe_show_npc_dialogue(index: int) -> void:
	if not explorer_file_list:
		return
	var entry = explorer_file_list.get_item_metadata(index)
	if typeof(entry) != TYPE_DICTIONARY:
		return
		
	var title := String(entry.get("title", ""))

	# Check if title is an NPC name
	var tux_ctrl = get_node_or_null("/root/SceneManager/TuxDialogueController")
	if tux_ctrl and tux_ctrl.has_method("show_npc_file_dialogue"):
		tux_ctrl.call("show_npc_file_dialogue", title)

func _on_explorer_top_bar_gui_input(event: InputEvent) -> void:
	if not in_file_explorer or not file_explorer_window or not file_explorer_window.visible:
		return

	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			if button_event.pressed:
				explorer_dragging = true
				explorer_last_mouse_global = button_event.global_position
			else:
				explorer_dragging = false
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and explorer_dragging:
		var motion_event := event as InputEventMouseMotion
		_update_explorer_drag(motion_event.global_position)
		get_viewport().set_input_as_handled()

func _update_explorer_drag(mouse_global_position: Vector2) -> void:
	if file_explorer_window == null:
		return
	var delta := mouse_global_position - explorer_last_mouse_global
	explorer_last_mouse_global = mouse_global_position
	file_explorer_window.offset_left += delta.x
	file_explorer_window.offset_right += delta.x
	file_explorer_window.offset_top += delta.y
	file_explorer_window.offset_bottom += delta.y
	_clamp_file_explorer_window_to_viewport()

func _clamp_file_explorer_window_to_viewport() -> void:
	if file_explorer_window == null:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := file_explorer_window.size
	var current_pos := file_explorer_window.global_position
	var clamped_pos := current_pos
	clamped_pos.x = clampf(current_pos.x, 0.0, max(0.0, viewport_size.x - panel_size.x))
	clamped_pos.y = clampf(current_pos.y, 0.0, max(0.0, viewport_size.y - panel_size.y))
	var correction := clamped_pos - current_pos
	if correction == Vector2.ZERO:
		return
	file_explorer_window.offset_left += correction.x
	file_explorer_window.offset_right += correction.x
	file_explorer_window.offset_top += correction.y
	file_explorer_window.offset_bottom += correction.y

func _set_pause_chrome_visible(visible_state: bool) -> void:
	if darken_overlay:
		darken_overlay.visible = visible_state
	if pause_content_margin:
		pause_content_margin.visible = visible_state
	if status_label:
		status_label.visible = visible_state and status_time_left > 0.0

func _refresh_explorer_sidebar(select_folder: String = "") -> void:
	if not explorer_sidebar_list:
		return

	var folders := _build_explorer_folders()
	explorer_sidebar_list.clear()
	for folder_name in folders:
		explorer_sidebar_list.add_item(folder_name)

	if folders.is_empty():
		explorer_selected_folder = ""
		_refresh_explorer_files()
		return

	var target_folder := select_folder
	if target_folder == "" or not folders.has(target_folder):
		target_folder = folders[0]
	explorer_selected_folder = target_folder

	for i in folders.size():
		if folders[i] == target_folder:
			explorer_sidebar_list.select(i)
			break

	_refresh_explorer_files()

func _refresh_explorer_files() -> void:
	if not explorer_file_list or not explorer_preview_label:
		return

	explorer_file_list.clear()
	var entries := _build_folder_entries(explorer_selected_folder)
	for entry in entries:
		var label_prefix := "[TXT] " if entry.get("type", "doc") == "doc" else "[DIR] "
		var item_text := "%s%s" % [label_prefix, entry.get("filename", "unknown")]
		var item_index := explorer_file_list.add_item(item_text)
		explorer_file_list.set_item_metadata(item_index, entry)

	if explorer_folder_label:
		explorer_folder_label.text = explorer_selected_folder

	if explorer_address_label:
		explorer_address_label.text = "/home/nova/%s" % explorer_selected_folder

	explorer_preview_label.text = "Select a file to preview its notes."
	if entries.size() > 0:
		explorer_file_list.select(0)
		_show_explorer_preview_for_index(0)

func _on_explorer_folder_selected(index: int) -> void:
	var folders := _build_explorer_folders()
	if index < 0 or index >= folders.size():
		return
	explorer_selected_folder = folders[index]
	_refresh_explorer_files()

func _on_explorer_item_selected(index: int) -> void:
	_show_explorer_preview_for_index(index)

func _on_explorer_item_activated(index: int) -> void:
	_activate_explorer_item(index)
	# Check if this is an NPC file and show Tux dialogue
	_maybe_show_npc_dialogue(index)

func _activate_explorer_selected_item() -> void:
	if not explorer_file_list:
		return
	var selected_items := explorer_file_list.get_selected_items()
	if selected_items.is_empty():
		return
	_activate_explorer_item(selected_items[0])

func _activate_explorer_item(index: int) -> void:
	if not explorer_file_list:
		return
	var entry = explorer_file_list.get_item_metadata(index)
	if typeof(entry) != TYPE_DICTIONARY:
		return
	if String(entry.get("type", "doc")) == "folder":
		var folder_name := String(entry.get("target", ""))
		if folder_name != "":
			explorer_selected_folder = folder_name
			_refresh_explorer_sidebar(folder_name)
			return
	_show_explorer_preview_for_index(index)
	# If this is a quest entry, open the quest window UI
	if String(entry.get("meta_type", "")) == "quest":
		_open_quest_from_entry(entry)
		return

func _show_explorer_preview_for_index(index: int) -> void:
	if not explorer_file_list or not explorer_preview_label:
		return
	if index < 0 or index >= explorer_file_list.item_count:
		return

	var entry = explorer_file_list.get_item_metadata(index)
	if typeof(entry) != TYPE_DICTIONARY:
		explorer_preview_label.text = "Preview unavailable."
		return

	var title := String(entry.get("title", "File"))
	var filename := String(entry.get("filename", "unknown.txt"))
	var body := String(entry.get("content", "No notes."))
	explorer_preview_label.text = "[b]%s[/b]\n%s\n\n%s" % [title, filename, body]


func _open_quest_from_entry(entry: Dictionary) -> void:
	if typeof(entry) != TYPE_DICTIONARY:
		return
	var quest_id := String(entry.get("quest_id", ""))
	if quest_id == "":
		return
	if not has_node("/root/SceneManager") or not SceneManager or not SceneManager.quest_manager:
		return
	var q := SceneManager.quest_manager.get_quest(quest_id)
	if not q:
		return
	var QuestWindowScene := preload("res://Scenes/ui/QuestWindow.tscn")
	var w: QuestWindow = QuestWindowScene.instantiate() as QuestWindow
	get_tree().get_root().add_child(w)
	w.set_quest(q)

func _build_explorer_folders() -> Array[String]:
	var folders: Array[String] = []
	for folder_name in BASE_EXPLORER_FOLDERS:
		folders.append(folder_name)
	if _is_bios_vault_unlocked():
		folders.append(BIOS_VAULT_FOLDER)
	if _is_proprietary_citadel_unlocked():
		folders.append(CITADEL_FOLDER)
	return folders

func _build_folder_entries(folder_name: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	_append_mapped_npc_entries(entries, folder_name)

	match folder_name:
		"Desktop":
			_append_generic_interaction_entries(entries)
			# Append active/completed quests as explorer documents so players can open them from the file manager
			if has_node("/root/SceneManager") and SceneManager and SceneManager.quest_manager:
				for quest_id in SceneManager.quest_manager.quests.keys():
					var q := SceneManager.quest_manager.get_quest(quest_id)
					if not q:
						continue
					# Only show quests that have been started or completed
					if String(q.status) == "inactive":
						continue
					var filename := "%s.quest" % quest_id
					var exists := false
					for e in entries:
						if String(e.get("filename", "")) == filename:
							exists = true
							break
					if not exists:
						entries.append({
							"type": "doc",
							"filename": filename,
							"title": q.quest_name,
							"content": q.description,
							"meta_type": "quest",
							"quest_id": quest_id,
						})

		"Filesystem_Forest":
			if SceneManager and SceneManager.proficiency_key_forest:
				_append_doc_entry_if_missing(entries, "proficiency_key_forest.txt", "Forest Proficiency Key", "Reward for repairing systems in the Filesystem Forest. Grants one half of gate access.")

		"Deamon_Depths":
			if SceneManager and SceneManager.proficiency_key_printer:
				_append_doc_entry_if_missing(entries, "proficiency_key_printer.txt", "Depths Proficiency Key", "Reward for stabilizing Deamon Depths. Completes the gate key pair with the forest key.")

		"Bios_Vault":
			_append_doc_entry_if_missing(entries, "sage_lessons.txt", "Sage Assessment", "The Sage evaluates command fluency and consistency. Lesson: precise fundamentals beat rushed execution.")
			_append_doc_entry_if_missing(entries, "bios_vault_lore.txt", "Bios Vault Lore", "A pre-boot archive of system memory, policy traces, and protected training records.")

		"Proprietary_Citadel":
			_append_doc_entry_if_missing(entries, "citadel_lore.txt", "Proprietary Citadel", "A sealed stack of closed-source protocols. Lesson: interoperability and transparency prevent lock-in traps.")

	if entries.is_empty():
		entries.append(_doc_entry("readme.txt", "No Files Yet", "Interact with NPCs in this zone to unlock new notes and lesson files."))

	return entries

func _append_mapped_npc_entries(entries: Array[Dictionary], folder_name: String) -> void:
	for npc_name in NPC_EXPLORER_ENTRIES.keys():
		if not _npc_interacted(npc_name):
			continue
		var npc_entries: Array = NPC_EXPLORER_ENTRIES[npc_name]
		for npc_entry in npc_entries:
			if String(npc_entry.get("folder", "")) != folder_name:
				continue
			_append_doc_entry_if_missing(
				entries,
				String(npc_entry.get("filename", "interaction_log.txt")),
				String(npc_entry.get("title", npc_name)),
				String(npc_entry.get("content", "Interaction recorded."))
			)

func _append_generic_interaction_entries(entries: Array[Dictionary]) -> void:
	if not SceneManager:
		return
	for npc_name in _get_interacted_npc_names():
		if NPC_EXPLORER_ENTRIES.has(npc_name):
			continue
		var slug := _slugify_filename(npc_name)
		_append_doc_entry_if_missing(
			entries,
			"%s.txt" % slug,
			npc_name,
			"Interaction log recorded for %s. Lesson: every system actor leaves clues once you stop and inspect them." % npc_name
		)

func _append_doc_entry_if_missing(entries: Array[Dictionary], filename: String, title: String, content: String) -> void:
	for entry in entries:
		if String(entry.get("filename", "")) == filename:
			return
	entries.append(_doc_entry(filename, title, content))

func _get_interacted_npc_names() -> Array[String]:
	var names: Array[String] = []
	if not SceneManager:
		return names
	for key in SceneManager.interacted_npcs.keys():
		if bool(SceneManager.interacted_npcs.get(key, false)):
			names.append(String(key))
	names.sort()
	return names

func _slugify_filename(value: String) -> String:
	return value.to_lower().strip_edges().replace(" ", "_").replace("-", "_")

func _doc_entry(filename: String, title: String, content: String) -> Dictionary:
	return {
		"type": "doc",
		"filename": filename,
		"title": title,
		"content": content,
	}

func _npc_interacted(npc_name: String) -> bool:
	if not SceneManager:
		return false
	if SceneManager.has_method("has_interacted_with_npc"):
		return SceneManager.has_interacted_with_npc(npc_name)

	match npc_name:
		"Messy Directory":
			return SceneManager.met_messy_directory
		"Elder Shell":
			return SceneManager.met_elder_shell
		"Broken Installer":
			return SceneManager.met_broken_installer
		"Lost File":
			return SceneManager.met_lost_file or SceneManager.helped_lost_file or SceneManager.deleted_lost_file
		"Gate Keeper":
			return SceneManager.met_gate_keeper
		"Broken Link":
			return SceneManager.proficiency_key_forest or SceneManager.broken_link_fragmented_key
		"Hardware Ghost":
			return SceneManager.met_hardware_ghost
		"Driver Remnant":
			return SceneManager.met_driver_remnant or SceneManager.driver_remnant_defeated
		"Printer Boss":
			return SceneManager.met_printer_boss or SceneManager.printer_beast_defeated
		_:
			return false

func _is_bios_vault_unlocked() -> bool:
	if not SceneManager:
		return false
	return SceneManager.gatekeeper_pass_granted or SceneManager.deamon_depths_boss_door_unlocked or bool(SceneManager.get_meta("bios_vault_sage_quiz_passed", false))

func _is_proprietary_citadel_unlocked() -> bool:
	if not SceneManager:
		return false
	return bool(SceneManager.get_meta("bios_vault_sage_quiz_passed", false))

func _has_any_discoverable_file() -> bool:
	for folder_name in _build_explorer_folders():
		var entries := _build_folder_entries(folder_name)
		if entries.size() > 0 and String(entries[0].get("filename", "")) != "readme.txt":
			return true
	return false

func _handle_pause_menu_click(global_pos: Vector2) -> bool:
	if not get_tree().paused or in_file_explorer:
		return false
	for i in menu_labels.size():
		var label := menu_labels[i]
		if not label.visible:
			continue
		if label.get_global_rect().has_point(global_pos):
			selected_index = i
			_update_menu_visuals()
			_activate_selection()
			return true
	return false

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
