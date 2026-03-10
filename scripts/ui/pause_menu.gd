extends CanvasLayer

const TITLE_SCENE := "res://Scenes/ui/title_menu.tscn"
const MENU_ITEMS : Array[String] = ["QUICK SAVE", "LOAD", "FILE EXPLORER", "TITLE SCREEN", "SETTINGS", "QUIT GAME"]
const SETTINGS_ITEMS : Array[String] = ["CONTROLS", "GRAPHICS", "SOUND", "SAVE", "GO BACK"]
const GRAPHICS_ITEMS := ["WINDOW MODE", "RESOLUTION", "QUALITY", "APPLY", "GO BACK"]
const WINDOW_MODE_OPTIONS := ["WINDOWED", "BORDERLESS", "FULLSCREEN"]
const RESOLUTION_OPTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const QUALITY_OPTIONS := ["LOW", "MEDIUM", "HIGH"]
const QUALITY_SCALES := [0.67, 0.85, 1.0]
const BASE_EXPLORER_FOLDERS := ["Desktop", "Filesystem_Forest", "Deamon_Depths"]
const BIOS_VAULT_FOLDER := "Bios_Vault"
const CITADEL_FOLDER := "Proprietary_Citadel"
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
@onready var file_explorer_window: Control = $MenuRoot/FileExplorerWindow
@onready var explorer_address_label: Label = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/TopBar/AddressLabel
@onready var explorer_folder_label: Label = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/Body/ContentPanel/ContentMargin/ContentVBox/FolderLabel
@onready var explorer_sidebar_list: ItemList = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/Body/SidebarPanel/SidebarMargin/SidebarList
@onready var explorer_file_list: ItemList = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/Body/ContentPanel/ContentMargin/ContentVBox/FileList
@onready var explorer_preview_label: RichTextLabel = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/Body/ContentPanel/ContentMargin/ContentVBox/PreviewLabel
@onready var explorer_close_button: Button = $MenuRoot/FileExplorerWindow/MainMargin/MainVBox/TopBar/CloseButton

var selected_index := 0
var pause_pending := false
var shader_time := 0.0
var status_time_left := 0.0
var in_settings_menu := false
var in_graphics_menu := false
var in_file_explorer := false
var explorer_selected_folder := "Desktop"

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
	if explorer_sidebar_list and not explorer_sidebar_list.item_selected.is_connected(_on_explorer_folder_selected):
		explorer_sidebar_list.item_selected.connect(_on_explorer_folder_selected)
	if explorer_file_list and not explorer_file_list.item_selected.is_connected(_on_explorer_item_selected):
		explorer_file_list.item_selected.connect(_on_explorer_item_selected)
	if explorer_file_list and not explorer_file_list.item_activated.is_connected(_on_explorer_item_activated):
		explorer_file_list.item_activated.connect(_on_explorer_item_activated)
	_update_menu_visuals()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _handle_letter_hotkey(event as InputEventKey):
			get_viewport().set_input_as_handled()
			return

	if _is_title_scene_active():
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_tree().paused and visible and not in_file_explorer:
			if _handle_pause_menu_click((event as InputEventMouseButton).position):
				get_viewport().set_input_as_handled()
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

func _handle_letter_hotkey(event: InputEventKey) -> bool:
	if _is_title_scene_active() or not get_tree().paused:
		return false
	if in_settings_menu or in_file_explorer:
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
	in_file_explorer = false
	_sync_graphics_state_from_system()
	selected_index = 0
	status_label.visible = false
	status_time_left = 0.0
	if file_explorer_window:
		file_explorer_window.visible = false
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
	status_label.visible = false
	status_time_left = 0.0
	if file_explorer_window:
		file_explorer_window.visible = false
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
	if not get_tree().paused:
		_pause_game()
		return

	if not _has_any_discoverable_file():
		_show_status(HINT_MESSAGES.file_explorer)
		return

	_open_file_explorer()

func _open_file_explorer() -> void:
	in_file_explorer = true
	status_label.visible = false
	status_time_left = 0.0
	if file_explorer_window:
		file_explorer_window.visible = true
	_refresh_explorer_sidebar(explorer_selected_folder)

func _close_file_explorer() -> void:
	in_file_explorer = false
	if file_explorer_window:
		file_explorer_window.visible = false
	_update_menu_visuals()

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
	match folder_name:
		"Desktop":
			if _npc_interacted("Messy Directory"):
				entries.append(_doc_entry("messy_directory.txt", "Messy Directory", "Guardian of scattered folders. Lesson: organize directories and keep backups before destructive commands."))
			if _npc_interacted("Elder Shell"):
				entries.append(_doc_entry("elder_shell.txt", "Elder Shell", "A patient mentor process. Lesson: understand commands before executing them."))
			if _npc_interacted("Broken Installer"):
				entries.append(_doc_entry("broken_installer.txt", "Broken Installer", "Dependency panic personified. Lesson: keep package indexes updated and verify missing dependencies."))
			if _npc_interacted("Lost File"):
				entries.append(_doc_entry("lost_file.txt", "Lost File", "A fragmented document searching for identity. Lesson: accidental deletes hurt; recovery and empathy matter."))
			if _npc_interacted("Gate Keeper"):
				entries.append(_doc_entry("gate_keeper.txt", "Gate Keeper", "Policy-aware gate service. Lesson: access is earned through demonstrated system proficiency."))

		"Filesystem_Forest":
			if _npc_interacted("Lost File"):
				entries.append(_doc_entry("lost_file_forest.txt", "Lost File (Forest)", "Recovered from unstable sectors in the forest. Lesson: locate, restore, decrypt, and verify data integrity."))
			if _npc_interacted("Broken Link"):
				entries.append(_doc_entry("broken_link.txt", "Broken Link", "A corrupted shortcut node. Lesson: troubleshoot paths methodically and patch references safely."))
			if SceneManager and SceneManager.proficiency_key_forest:
				entries.append(_doc_entry("proficiency_key_forest.txt", "Forest Proficiency Key", "Reward for repairing systems in the Filesystem Forest. Grants one half of gate access."))

		"Deamon_Depths":
			if _npc_interacted("Hardware Ghost"):
				entries.append(_doc_entry("hardware_ghost.txt", "Hardware Ghost", "Echoes of legacy hardware layers. Lesson: old systems still shape modern runtime behavior."))
			if _npc_interacted("Driver Remnant"):
				entries.append(_doc_entry("driver_remnant.txt", "Driver Remnant", "An unstable leftover driver process. Lesson: remove stale drivers and isolate failing components."))
			if _npc_interacted("Printer Boss"):
				entries.append(_doc_entry("printer_beast.txt", "Printer Beast", "A queue-jamming daemon boss. Lesson: monitor services, permissions, and error logs under pressure."))
			if SceneManager and SceneManager.proficiency_key_printer:
				entries.append(_doc_entry("proficiency_key_printer.txt", "Depths Proficiency Key", "Reward for stabilizing Deamon Depths. Completes the gate key pair with the forest key."))

		"Bios_Vault":
			entries.append(_doc_entry("sage_lessons.txt", "Sage Assessment", "The Sage evaluates command fluency and consistency. Lesson: precise fundamentals beat rushed execution."))
			entries.append(_doc_entry("bios_vault_lore.txt", "Bios Vault Lore", "A pre-boot archive of system memory, policy traces, and protected training records."))

		"Proprietary_Citadel":
			entries.append(_doc_entry("citadel_lore.txt", "Proprietary Citadel", "A sealed stack of closed-source protocols. Lesson: interoperability and transparency prevent lock-in traps."))

	if entries.is_empty():
		entries.append(_doc_entry("readme.txt", "No Files Yet", "Interact with NPCs in this zone to unlock new notes and lesson files."))

	return entries

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
