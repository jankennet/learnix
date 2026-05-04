extends Control

# --- Constants & Config ---
const WORLD_MAIN_SCENE := "res://Scenes/Levels/tutorial - Copy.tscn"


const MENU_ITEMS_WITH_SAVE: Array[String] = ["CONTINUE", "NEW GAME", "SETTINGS", "QUIT GAME"]
const MENU_ITEMS_NO_SAVE: Array[String] = ["NEW GAME", "SETTINGS", "QUIT GAME"]

const WINDOW_MODE_OPTIONS := ["WINDOWED", "BORDERLESS", "FULLSCREEN"]
const RESOLUTION_OPTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const QUALITY_OPTIONS := ["LOW", "MEDIUM", "HIGH"]
const QUALITY_SCALES: Array[float] = [0.67, 0.85, 1.0]
const MENU_SELECTED_COLOR := Color(0.98, 0.92, 0.78, 1.0)
const MENU_UNSELECTED_COLOR := Color(0.82, 0.85, 0.9, 1.0)

# --- UI References ---
@onready var logo_label: Label = $CenterContainer/MainColumn/LogoLabel
@onready var subtitle_label: Label = $CenterContainer/MainColumn/SubtitleLabel
@onready var menu_vbox: VBoxContainer = $CenterContainer/MainColumn/MenuPanel/MenuVBox
@onready var menu_labels: Array = $CenterContainer/MainColumn/MenuPanel/MenuVBox.get_children()
@onready var background_anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")

@onready var settings_overlay: Control = $SettingsOverlay
@onready var settings_list: ItemList = $SettingsOverlay/MainMargin/MainVBox/SettingsList
@onready var graphics_panel: PanelContainer = $SettingsOverlay/MainMargin/MainVBox/GraphicsPanel
@onready var graphics_list: ItemList = $SettingsOverlay/MainMargin/MainVBox/GraphicsPanel/GraphicsMargin/GraphicsVBox/GraphicsList

# Sound Sliders (Make sure these paths match your node tree!)
@onready var master_slider: HSlider = get_node_or_null("SettingsOverlay/MainMargin/MainVBox/SoundPanel/SoundMargin/SoundVBox/SoundGrid/MasterRow/MasterSlider")
@onready var music_slider: HSlider = get_node_or_null("SettingsOverlay/MainMargin/MainVBox/SoundPanel/SoundMargin/SoundVBox/SoundGrid/MusicRow/MusicSlider")
@onready var sfx_slider: HSlider = get_node_or_null("SettingsOverlay/MainMargin/MainVBox/SoundPanel/SoundMargin/SoundVBox/SoundGrid/SFXRow/SFXSlider")

@onready var panels: Array[Control] = [
	$SettingsOverlay/MainMargin/MainVBox/ControlsPanel,
	$SettingsOverlay/MainMargin/MainVBox/SoundPanel,
	graphics_panel
]

# --- State ---
enum MenuState { MAIN, SETTINGS, GRAPHICS, OTHER_PANEL }
var current_state := MenuState.MAIN
var selected_index := 0
var graphics_indices := {"mode": 0, "res": 2, "qual": 2}
var hover_index := -1
var quit_confirm_dialog: ConfirmationDialog = null

# --- Initialization ---
func _ready() -> void:
	# Set custom cursor for the entire game
	var cursor_texture := load("res://Assets/icons8-cursor-48.png") as Texture2D
	if cursor_texture:
		Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_POINTING_HAND)
	
	_set_global_ui_visibility(false)
	_cleanup_gameplay_ui_artifacts()
	if background_anim:
		background_anim.play("default")
		_fit_background_to_viewport()
		var viewport: Viewport = get_viewport()
		if viewport and not viewport.size_changed.is_connected(_on_viewport_size_changed):
			viewport.size_changed.connect(_on_viewport_size_changed)
	subtitle_label.text = "A LINUX BUILDER RPG"
	
	_setup_lists()
	_setup_sound_sliders()
	_sync_graphics_state_from_system()
	
	settings_overlay.hide()

	# Wire mouse interactions
	if settings_list:
		if not settings_list.item_selected.is_connected(_on_settings_item_selected):
			settings_list.item_selected.connect(_on_settings_item_selected)
		if not settings_list.item_activated.is_connected(_on_settings_item_activated):
			settings_list.item_activated.connect(_on_settings_item_activated)

	if graphics_list:
		if not graphics_list.item_selected.is_connected(_on_graphics_item_selected):
			graphics_list.item_selected.connect(_on_graphics_item_selected)
		if not graphics_list.item_activated.is_connected(_on_graphics_item_activated):
			graphics_list.item_activated.connect(_on_graphics_item_activated)

	# Make main menu labels clickable
	for i in range(menu_labels.size()):
		var lbl = menu_labels[i]
		if lbl and not lbl.gui_input.is_connected(_on_main_label_gui_input):
			lbl.gui_input.connect(_on_main_label_gui_input.bind(i))
		# Enable mouse hover + click visual feedback on labels
		if lbl and lbl is Control:
			lbl.mouse_filter = Control.MOUSE_FILTER_STOP
			lbl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			if not lbl.mouse_entered.is_connected(_on_main_label_mouse_entered):
				lbl.mouse_entered.connect(_on_main_label_mouse_entered.bind(i))
			if not lbl.mouse_exited.is_connected(_on_main_label_mouse_exited):
				lbl.mouse_exited.connect(_on_main_label_mouse_exited.bind(i))

	_update_menu_visuals()
	_setup_quit_confirmation_dialog()

func _setup_lists() -> void:
	# Populate Settings
	if settings_list:
		settings_list.clear()
		settings_list.add_item("CONTROLS")
		settings_list.add_item("GRAPHICS")
		settings_list.add_item("SOUND")
		settings_list.add_item("GO BACK")
	
	# Initial Graphics List population
	_update_graphics_list()

func _setup_sound_sliders() -> void:
	# If no sliders exist, nothing to do
	if not master_slider and not music_slider and not sfx_slider:
		return

	# Find master once for fallback
	var master_idx := _find_bus_index("Master")

	# Master
	if master_slider:
		if master_idx != -1:
			master_slider.value = db_to_linear(AudioServer.get_bus_volume_db(master_idx))
		else:
			master_slider.value = 1.0
		master_slider.value_changed.connect(_on_volume_changed.bind("Master"))

	# Music (fallback to Master if Music bus not present)
	if music_slider:
		var music_idx := _find_bus_index("Music")
		var src_idx := music_idx if music_idx != -1 else master_idx
		if src_idx != -1:
			music_slider.value = db_to_linear(AudioServer.get_bus_volume_db(src_idx))
		else:
			music_slider.value = 1.0
		music_slider.value_changed.connect(_on_volume_changed.bind("Music"))

	# SFX (fallback to Master if SFX bus not present)
	if sfx_slider:
		var sfx_idx := _find_bus_index("SFX")
		var sfx_src := sfx_idx if sfx_idx != -1 else master_idx
		if sfx_src != -1:
			sfx_slider.value = db_to_linear(AudioServer.get_bus_volume_db(sfx_src))
		else:
			sfx_slider.value = 1.0
		sfx_slider.value_changed.connect(_on_volume_changed.bind("SFX"))

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

# --- Input Handling ---
func _unhandled_input(event: InputEvent) -> void:
	match current_state:
		MenuState.MAIN: _handle_main_menu_input(event)
		MenuState.SETTINGS: _handle_settings_input(event)
		MenuState.GRAPHICS: _handle_graphics_input(event)
		MenuState.OTHER_PANEL: 
			# If a slider is focused, let it handle left/right input automatically
			var focused = get_viewport().gui_get_focus_owner()
			if focused is Slider:
				if event.is_action_pressed("ui_cancel"):
					_switch_to_settings()
				return # Let the slider handle the arrow keys natively

			if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
				_switch_to_settings()

func _handle_main_menu_input(event: InputEvent) -> void:
	var items = _get_active_menu_items()
	if event.is_action_pressed("ui_up"):
		selected_index = wrapi(selected_index - 1, 0, items.size())
		_update_menu_visuals()
	elif event.is_action_pressed("ui_down"):
		selected_index = wrapi(selected_index + 1, 0, items.size())
		_update_menu_visuals()
	elif event.is_action_pressed("ui_accept"):
		var idx = selected_index
		if hover_index != -1:
			idx = hover_index
		_execute_main_selection(items[idx])

func _handle_settings_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_switch_to_main()
	elif event.is_action_pressed("ui_accept"):
		_execute_settings_selection()

func _handle_graphics_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_switch_to_settings()
	elif event.is_action_pressed("ui_left"):
		_cycle_graphics(-1)
	elif event.is_action_pressed("ui_right"):
		_cycle_graphics(1)
	elif event.is_action_pressed("ui_accept"):
		var selected = graphics_list.get_selected_items()
		if selected.is_empty(): return
		
		var text = graphics_list.get_item_text(selected[0])
		if text == "APPLY": _apply_graphics_settings()
		elif text == "GO BACK": _switch_to_settings()

# --- Transitions ---
func _switch_to_settings() -> void:
	current_state = MenuState.SETTINGS
	menu_vbox.hide()
	settings_overlay.show()
	settings_list.show()
	for p in panels: p.hide()
	# Ensure the global controls help overlay is hidden when showing settings list
	var ch = get_node_or_null("/root/ControlsHelp")
	if ch:
		ch.hide()

	if settings_list.get_item_count() > 0:
		settings_list.grab_focus()
		settings_list.select(0)

func _switch_to_main() -> void:
	current_state = MenuState.MAIN
	settings_overlay.hide()
	menu_vbox.show()
	_update_menu_visuals()

# --- Logic & Execution ---
func _execute_main_selection(choice: String) -> void:
	match choice:
		"NEW GAME": 
			_set_global_ui_visibility(true)
			if SceneManager and SceneManager.has_method("start_new_game"):
				SceneManager.start_new_game(WORLD_MAIN_SCENE)
			else:
				get_tree().change_scene_to_file(WORLD_MAIN_SCENE)
		"SETTINGS": _switch_to_settings()
		"QUIT GAME": _request_desktop_quit_confirmation()
		"CONTINUE": 
			_set_global_ui_visibility(true)
			if SceneManager and SceneManager.has_method("load_game"): 
				SceneManager.load_game()

func _setup_quit_confirmation_dialog() -> void:
	quit_confirm_dialog = ConfirmationDialog.new()
	quit_confirm_dialog.name = "TitleQuitConfirmDialog"
	quit_confirm_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	quit_confirm_dialog.exclusive = true
	add_child(quit_confirm_dialog)
	if not quit_confirm_dialog.confirmed.is_connected(_on_title_quit_confirmed):
		quit_confirm_dialog.confirmed.connect(_on_title_quit_confirmed)

func _request_desktop_quit_confirmation() -> void:
	if quit_confirm_dialog == null:
		return
	quit_confirm_dialog.title = "Quit Game"
	quit_confirm_dialog.dialog_text = "Quit to desktop?"
	quit_confirm_dialog.ok_button_text = "Quit to Desktop"
	quit_confirm_dialog.popup_centered(Vector2i(520, 160))

func _on_title_quit_confirmed() -> void:
	if quit_confirm_dialog:
		quit_confirm_dialog.hide()
	get_tree().quit()

func _cleanup_gameplay_ui_artifacts() -> void:
	for node_path in ["/root/QuestSideButton", "/root/QuestWindow", "/root/TerminalPanel", "/root/ControlsHelp", "/root/InteractionPrompt"]:
		var node := get_node_or_null(node_path)
		if node and node is CanvasItem:
			(node as CanvasItem).visible = false

	# PauseMenu is autoloaded; ensure it is visually dismissed when title opens.
	var pause_menu := get_node_or_null("/root/PauseMenu")
	if pause_menu and pause_menu.has_method("_resume_game"):
		pause_menu.call("_resume_game")

func _execute_settings_selection() -> void:
	var selected = settings_list.get_selected_items()
	if selected.is_empty(): return
	
	var choice = settings_list.get_item_text(selected[0])
	
	match choice:
		"GO BACK": _switch_to_main()
		"GRAPHICS":
			current_state = MenuState.GRAPHICS
			settings_list.hide()
			graphics_panel.show()
			_update_graphics_list()
			graphics_list.grab_focus()
		"CONTROLS":
			current_state = MenuState.OTHER_PANEL
			settings_list.hide()
			panels[0].show()
		"SOUND":
			current_state = MenuState.OTHER_PANEL
			settings_list.hide()
			panels[1].show()
			if master_slider: master_slider.grab_focus()

func _cycle_graphics(dir: int) -> void:
	var selected = graphics_list.get_selected_items()
	if selected.is_empty(): return
	var idx = selected[0]
	
	match idx:
		0: graphics_indices.mode = wrapi(graphics_indices.mode + dir, 0, 3)
		1: graphics_indices.res = wrapi(graphics_indices.res + dir, 0, RESOLUTION_OPTIONS.size())
		2: graphics_indices.qual = wrapi(graphics_indices.qual + dir, 0, 3)
	_update_graphics_list()

func _update_graphics_list() -> void:
	if not graphics_list: return
	
	graphics_list.clear()
	graphics_list.add_item("WINDOW: " + WINDOW_MODE_OPTIONS[graphics_indices.mode])
	var res = RESOLUTION_OPTIONS[graphics_indices.res]
	graphics_list.add_item("RES: %dx%d" % [res.x, res.y])
	graphics_list.add_item("QUALITY: " + QUALITY_OPTIONS[graphics_indices.qual])
	graphics_list.add_item("APPLY")
	graphics_list.add_item("GO BACK")
	graphics_list.select(graphics_indices.mode if current_state == MenuState.GRAPHICS else 0)

func _apply_graphics_settings() -> void:
	var mode = graphics_indices.mode
	if mode == 0: # Windowed
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	elif mode == 1: # Borderless
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	else: # Fullscreen
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	
	if mode != 2:
		DisplayServer.window_set_size(RESOLUTION_OPTIONS[graphics_indices.res])

	var perf_manager := get_node_or_null("/root/PerformanceManager")
	if perf_manager and perf_manager.has_method("set_quality_index"):
		perf_manager.call("set_quality_index", graphics_indices.qual)
	else:
		var viewport := get_viewport()
		if viewport:
			viewport.scaling_3d_scale = QUALITY_SCALES[graphics_indices.qual]
			match graphics_indices.qual:
				0: viewport.msaa_3d = Viewport.MSAA_DISABLED
				1: viewport.msaa_3d = Viewport.MSAA_2X
				2: viewport.msaa_3d = Viewport.MSAA_4X

func _sync_graphics_state_from_system() -> void:
	var mode := DisplayServer.window_get_mode()
	var borderless := DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		graphics_indices.mode = 2
	elif borderless:
		graphics_indices.mode = 1
	else:
		graphics_indices.mode = 0

	var current_size := DisplayServer.window_get_size()
	graphics_indices.res = _nearest_resolution_index(current_size)

	var perf_manager := get_node_or_null("/root/PerformanceManager")
	if perf_manager and perf_manager.has_method("get_quality_index"):
		graphics_indices.qual = int(perf_manager.call("get_quality_index"))

func _nearest_resolution_index(window_size: Vector2i) -> int:
	var nearest_index := 0
	var nearest_distance := INF
	for i in RESOLUTION_OPTIONS.size():
		var option_size: Vector2i = RESOLUTION_OPTIONS[i]
		var dx := float(option_size.x - window_size.x)
		var dy := float(option_size.y - window_size.y)
		var distance := dx * dx + dy * dy
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = i
	return nearest_index

func _on_volume_changed(value: float, bus_name: String) -> void:
	var bus_index := _find_bus_index(bus_name)
	if bus_index == -1:
		# fallback to Master bus if specific bus missing
		bus_index = _find_bus_index("Master")
	if bus_index == -1:
		# no bus available, nothing we can do
		return

	AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))
	AudioServer.set_bus_mute(bus_index, value <= 0.001)

# --- UI Helpers ---
func _update_menu_visuals() -> void:
	var items = _get_active_menu_items()
	var display_index := selected_index
	if current_state == MenuState.MAIN and hover_index != -1:
		display_index = hover_index
	for i in range(menu_labels.size()):
		var label = menu_labels[i] as Label
		if i >= items.size():
			label.hide()
			continue
		label.show()
		label.text = ("> " if i == display_index else "  ") + items[i]
		label.modulate = MENU_SELECTED_COLOR if i == display_index else MENU_UNSELECTED_COLOR

func _get_active_menu_items() -> Array[String]:
	if SceneManager and SceneManager.has_method("has_save_game") and SceneManager.has_save_game():
		return MENU_ITEMS_WITH_SAVE
	return MENU_ITEMS_NO_SAVE

func _set_global_ui_visibility(state: bool) -> void:
	for node_path in ["/root/ControlsHelp", "/root/InteractionPrompt"]:
		var n = get_node_or_null(node_path)
		if n: n.visible = state

func _on_viewport_size_changed() -> void:
	_fit_background_to_viewport()

func _fit_background_to_viewport() -> void:
	if not background_anim or background_anim.sprite_frames == null:
		return

	var frame_texture: Texture2D = background_anim.sprite_frames.get_frame_texture("default", 0)
	if frame_texture == null:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var frame_size: Vector2 = frame_texture.get_size()
	if frame_size.x <= 0.0 or frame_size.y <= 0.0:
		return

	var scale_factor: float = max(viewport_size.x / frame_size.x, viewport_size.y / frame_size.y)
	background_anim.scale = Vector2.ONE * scale_factor
	background_anim.position = viewport_size * 0.5


### Mouse signal handlers ###
func _on_settings_item_selected(index: int) -> void:
	# keep track of selection when clicking
	settings_list.select(index)


func _on_settings_item_activated(index: int) -> void:
	# activate item as if Enter was pressed
	settings_list.select(index)
	_execute_settings_selection()


func _on_graphics_item_selected(index: int) -> void:
	graphics_list.select(index)


func _on_graphics_item_activated(index: int) -> void:
	graphics_list.select(index)
	var text = graphics_list.get_item_text(index)
	if text == "APPLY":
		_apply_graphics_settings()
		_update_graphics_list()
	elif text == "GO BACK":
		_switch_to_settings()


func _on_main_label_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var items = _get_active_menu_items()
		if index >= 0 and index < items.size():
			selected_index = index
			_execute_main_selection(items[index])

func _on_main_label_mouse_entered(index: int) -> void:
	if current_state != MenuState.MAIN:
		return
	hover_index = index
	_update_menu_visuals()

func _on_main_label_mouse_exited(_index: int) -> void:
	if current_state != MenuState.MAIN:
		return
	hover_index = -1
	_update_menu_visuals()
