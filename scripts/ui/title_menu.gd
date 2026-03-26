extends Control

# --- Constants & Config ---
const WORLD_MAIN_SCENE := "res://Scenes/Levels/tutorial - Copy.tscn"
const ASCII_LOGO := """ /$$         /$$$$$$$$  /$$$$$$  /$$$$$$$  /$$   /$$ /$$$$$$ /$$   /$$
| $$        | $$_____/ /$$__  $$| $$__  $$| $$$ | $$|_  $$_/| $$  / $$
| $$        | $$      | $$  \\ $$| $$  \\ $$| $$$$| $$  | $$  |  $$/ $$/
| $$        | $$$$$   | $$$$$$$$| $$$$$$$/| $$ $$ $$  | $$   \\  $$$$/
| $$        | $$__/   | $$__  $$| $$__  $$| $$  $$$$  | $$    >$$  $$
| $$        | $$      | $$  | $$| $$  \\ $$| $$\\  $$$  | $$   /$$/\\  $$
| $$$$$$$$| $$$$$$$$| $$  | $$| $$  | $$| $$ \\  $$ /$$$$$$| $$  \\ $$
|________/|________/|__/  |__/|__/  |__/|__/  \\__/|______/|__/  \\__/"""

const MENU_ITEMS_WITH_SAVE: Array[String] = ["CONTINUE", "NEW GAME", "SETTINGS", "QUIT GAME"]
const MENU_ITEMS_NO_SAVE: Array[String] = ["NEW GAME", "SETTINGS", "QUIT GAME"]

const WINDOW_MODE_OPTIONS := ["WINDOWED", "BORDERLESS", "FULLSCREEN"]
const RESOLUTION_OPTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const QUALITY_OPTIONS := ["LOW", "MEDIUM", "HIGH"]
const QUALITY_SCALES: Array[float] = [0.67, 0.85, 1.0]

# --- UI References ---
@onready var logo_label: Label = $CenterContainer/MainColumn/LogoLabel
@onready var subtitle_label: Label = $CenterContainer/MainColumn/SubtitleLabel
@onready var menu_vbox: VBoxContainer = $CenterContainer/MainColumn/MenuVBox
@onready var menu_labels: Array = $CenterContainer/MainColumn/MenuVBox.get_children()

@onready var settings_overlay: Control = $SettingsOverlay
@onready var settings_list: ItemList = $SettingsOverlay/MainMargin/MainVBox/SettingsList
@onready var graphics_panel: PanelContainer = $SettingsOverlay/MainMargin/MainVBox/GraphicsPanel
@onready var graphics_list: ItemList = $SettingsOverlay/MainMargin/MainVBox/GraphicsPanel/GraphicsMargin/GraphicsVBox/GraphicsList

# Sound Sliders (Make sure these paths match your node tree!)
@onready var master_slider: HSlider = get_node_or_null("SettingsOverlay/MainMargin/MainVBox/SoundPanel/VBox/MasterSlider")
@onready var music_slider: HSlider = get_node_or_null("SettingsOverlay/MainMargin/MainVBox/SoundPanel/VBox/MusicSlider")
@onready var sfx_slider: HSlider = get_node_or_null("SettingsOverlay/MainMargin/MainVBox/SoundPanel/VBox/SFXSlider")

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

# --- Initialization ---
func _ready() -> void:
	_set_global_ui_visibility(false)
	logo_label.text = ASCII_LOGO
	subtitle_label.text = "A LINUX BUILDER RPG"
	
	_setup_lists()
	_setup_sound_sliders()
	
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
	for i in menu_labels.size():
		var lbl = menu_labels[i]
		if lbl and not lbl.gui_input.is_connected(_on_main_label_gui_input):
			lbl.gui_input.connect(_on_main_label_gui_input.bind(i))

	_update_menu_visuals()

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
	if not master_slider: return # Failsafe if nodes aren't built yet
	
	master_slider.value_changed.connect(_on_volume_changed.bind("Master"))
	if music_slider: music_slider.value_changed.connect(_on_volume_changed.bind("Music"))
	if sfx_slider: sfx_slider.value_changed.connect(_on_volume_changed.bind("SFX"))
	
	# Set initial positions based on current bus volumes
	master_slider.value = db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")))
	if music_slider: music_slider.value = db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")))
	if sfx_slider: sfx_slider.value = db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")))

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
		_execute_main_selection(items[selected_index])

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
			get_tree().change_scene_to_file(WORLD_MAIN_SCENE)
		"SETTINGS": _switch_to_settings()
		"QUIT GAME": get_tree().quit()
		"CONTINUE": 
			_set_global_ui_visibility(true)
			if SceneManager and SceneManager.has_method("load_game"): 
				SceneManager.load_game()

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
	
	var viewport = get_viewport()
	if viewport:
		viewport.scaling_3d_scale = QUALITY_SCALES[graphics_indices.qual]
		
		# Optional MSAA setup based on quality
		match graphics_indices.qual:
			0: viewport.msaa_3d = Viewport.MSAA_DISABLED
			1: viewport.msaa_3d = Viewport.MSAA_2X
			2: viewport.msaa_3d = Viewport.MSAA_4X

func _on_volume_changed(value: float, bus_name: String) -> void:
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))
		AudioServer.set_bus_mute(bus_index, value <= 0.001)

# --- UI Helpers ---
func _update_menu_visuals() -> void:
	var items = _get_active_menu_items()
	for i in menu_labels.size():
		var label = menu_labels[i] as Label
		if i >= items.size():
			label.hide()
			continue
		label.show()
		label.text = ("> " if i == selected_index else "  ") + items[i]
		label.modulate = Color(0.92, 0.92, 0.92) if i == selected_index else Color(0.55, 0.55, 0.55)

func _get_active_menu_items() -> Array[String]:
	if SceneManager and SceneManager.has_method("has_save_game") and SceneManager.has_save_game():
		return MENU_ITEMS_WITH_SAVE
	return MENU_ITEMS_NO_SAVE

func _set_global_ui_visibility(state: bool) -> void:
	for node_path in ["/root/ControlsHelp", "/root/InteractionPrompt"]:
		var n = get_node_or_null(node_path)
		if n: n.visible = state


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
			_execute_main_selection(items[index])
