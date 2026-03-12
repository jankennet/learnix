extends Control

const WORLD_MAIN_SCENE := "res://Scenes/world_main.tscn"
const ASCII_LOGO := """ /$$       /$$$$$$$$  /$$$$$$  /$$$$$$$  /$$   /$$ /$$$$$$ /$$   /$$
| $$      | $$_____/ /$$__  $$| $$__  $$| $$$ | $$|_  $$_/| $$  / $$
| $$      | $$      | $$  \\ $$| $$  \\ $$| $$$$| $$  | $$  |  $$/ $$/
| $$      | $$$$$   | $$$$$$$$| $$$$$$$/| $$ $$ $$  | $$   \\  $$$$/
| $$      | $$__/   | $$__  $$| $$__  $$| $$  $$$$  | $$    >$$  $$
| $$      | $$      | $$  | $$| $$  \\ $$| $$\\  $$$  | $$   /$$/\\  $$
| $$$$$$$$| $$$$$$$$| $$  | $$| $$  | $$| $$ \\  $$ /$$$$$$| $$  \\ $$
|________/|________/|__/  |__/|__/  |__/|__/  \\__/|______/|__/  |__/"""

const MENU_ITEMS_WITH_SAVE :Array[String]= ["CONTINUE", "NEW GAME", "SETTINGS", "QUIT GAME"]
const MENU_ITEMS_NO_SAVE :Array[String] = ["NEW GAME", "SETTINGS", "QUIT GAME"]

@onready var logo_label: Label = $CenterContainer/MainColumn/LogoLabel
@onready var subtitle_label: Label = $CenterContainer/MainColumn/SubtitleLabel
@onready var menu_vbox: VBoxContainer = $CenterContainer/MainColumn/MenuVBox
@onready var menu_labels: Array[Label] = [
	$CenterContainer/MainColumn/MenuVBox/ContinueLabel,
	$CenterContainer/MainColumn/MenuVBox/NewGameLabel,
	$CenterContainer/MainColumn/MenuVBox/SettingsLabel,
	$CenterContainer/MainColumn/MenuVBox/QuitLabel,
]
@onready var settings_overlay: Label = $SettingsOverlay

var selected_index := 0
var in_settings := false

func _ready() -> void:
	_set_global_ui_visibility(false)
	logo_label.text = ASCII_LOGO
	subtitle_label.text = "A LINUX BUILDER RPG"
	_update_menu_visuals()
	settings_overlay.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if in_settings:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			in_settings = false
			settings_overlay.visible = false
			menu_vbox.visible = true
			selected_index = mini(selected_index, _menu_items().size() - 1)
			_update_menu_visuals()
		return

	if event.is_action_pressed("ui_up"):
		selected_index = wrapi(selected_index - 1, 0, _menu_items().size())
		_update_menu_visuals()
		return

	if event.is_action_pressed("ui_down"):
		selected_index = wrapi(selected_index + 1, 0, _menu_items().size())
		_update_menu_visuals()
		return

	if event.is_action_pressed("ui_accept"):
		_activate_selection()

func _activate_selection() -> void:
	var active_items := _menu_items()
	if selected_index < 0 or selected_index >= active_items.size():
		return

	match active_items[selected_index]:
		"CONTINUE":
			_set_global_ui_visibility(true)
			set_process_unhandled_input(false)
			if SceneManager and SceneManager.has_method("load_game"):
				if not SceneManager.load_game():
					set_process_unhandled_input(true)
					_update_menu_visuals()
			else:
				set_process_unhandled_input(true)
		"NEW GAME":
			_set_global_ui_visibility(true)
			set_process_unhandled_input(false)
			if SceneManager and SceneManager.has_method("start_new_game"):
				SceneManager.start_new_game(WORLD_MAIN_SCENE)
			else:
				get_tree().change_scene_to_file(WORLD_MAIN_SCENE)
		"SETTINGS":
			in_settings = true
			settings_overlay.visible = true
			menu_vbox.visible = false
		"QUIT GAME":
			get_tree().quit()

func _set_global_ui_visibility(visible_state: bool) -> void:
	var controls_help := get_node_or_null("/root/ControlsHelp")
	if controls_help:
		controls_help.visible = visible_state

	var interaction_prompt := get_node_or_null("/root/InteractionPrompt")
	if interaction_prompt:
		interaction_prompt.visible = visible_state

func _update_menu_visuals() -> void:
	var active_items := _menu_items()
	selected_index = clampi(selected_index, 0, active_items.size() - 1)
	for i in menu_labels.size():
		var option_label := menu_labels[i]
		if i >= active_items.size():
			option_label.visible = false
			continue

		option_label.visible = true
		if i == selected_index:
			option_label.text = "# " + active_items[i]
			option_label.modulate = Color(0.92, 0.92, 0.92)
		else:
			option_label.text = "  " + active_items[i]
			option_label.modulate = Color(0.55, 0.55, 0.55)

func _menu_items() -> Array[String]:
	if SceneManager and SceneManager.has_method("has_save_game") and SceneManager.has_save_game():
		return MENU_ITEMS_WITH_SAVE
	return MENU_ITEMS_NO_SAVE
