extends Control

const COMBAT_UI_NODE_NAME := "CombatTerminalUI"
const QUEST_LIST_NODE_NAME := "QuestList"
const VISIBILITY_CHECK_INTERVAL := 0.15
const TERMINAL_ROOT_PATH := "/home/nova"
const DEFAULT_HUB_LOCATION := "fallback_hamlet"
const TERMINAL_EXPLORED_META_KEY := "terminal_explored_locations"
const HUB_DEFAULT_SPAWN := "Fallback_Hamlet_Final/Spawn_FTFM"
const HUB_FOREST_RETURN_SPAWN := "Fallback_Hamlet_Final/Spawn_FTFM"
const HUB_DEPTHS_RETURN_SPAWN := "Fallback_Hamlet_Final/Spawn_DDTFM"
const HUB_BIOS_RETURN_SPAWN := "Fallback_Hamlet_Final/Spawn_BVTFM"

const TERMINAL_TELEPORT_TARGETS := {
	"fallback_hamlet": {
		"scene": "res://Scenes/Levels/fallback_hamlet.tscn",
		"spawn": HUB_DEFAULT_SPAWN,
	},
	"filesystem_forest": {
		"scene": "res://Scenes/Levels/file_system_forest.tscn",
		"spawn": "Forest/Spawn_FSF",
	},
	"deamon_depths": {
		"scene": "res://Scenes/Levels/deamon_depths.tscn",
		"spawn": "Dungeon/Spawn_DD",
	},
	"bios_vault": {
		"scene": "res://Scenes/Levels/bios_vault.tscn",
		"spawn": "Spawn_BV",
	},
}

const TERMINAL_LOCATION_ALIASES := {
	"hamlet": "fallback_hamlet",
	"home": "fallback_hamlet",
	"fallback_hamlet": "fallback_hamlet",
	"filesystem_forest": "filesystem_forest",
	"forest": "filesystem_forest",
	"deamon_depths": "deamon_depths",
	"depths": "deamon_depths",
	"bios_vault": "bios_vault",
	"vault": "bios_vault",
}

const TERMINAL_DIRECTORIES := {
	"": ["fallback_hamlet", "filesystem_forest", "deamon_depths", "bios_vault"],
	"desktop": ["welcome.txt", "npc_notes.log", "quests.todo"],
	"filesystem_forest": ["symlink_map.md", "lost_file.fragment", "roots/"],
	"deamon_depths": ["driver_remnant.log", "printer_queue.dat", "bossdoor.keyhint"],
	"fallback_hamlet": ["market.square", "well.archive", "home.instance"],
	"bios_vault": ["firmware_records.bin", "sage_protocol.md", "locked_segment/"],
}

const TERMINAL_FUN_FACTS := [
	"Linux fact: `pwd` prints your current working directory.",
	"Linux fact: `cd ..` moves to the parent directory.",
	"Linux fact: `ls -a` can show hidden dotfiles.",
	"Linux fact: everything is treated as a file in Unix-like systems.",
	"Linux fact: commands are case-sensitive, so `LS` is different from `ls`.",
]

var _check_timer := 0.0
@onready var file_item: Control = $TopRight/MenuStack/BagItem
@onready var term_item: Control = $TopRight/MenuStack/MessagesItem
@onready var terminal_panel: Control = $TerminalPanel
@onready var terminal_output: RichTextLabel = $TerminalPanel/TerminalMargin/TerminalVBox/TerminalOutput
@onready var terminal_input: LineEdit = $TerminalPanel/TerminalMargin/TerminalVBox/TerminalInputRow/TerminalInput
@onready var run_command_button: Button = $TerminalPanel/TerminalMargin/TerminalVBox/TerminalInputRow/RunCommandButton
@onready var terminal_header: Control = $TerminalPanel/TerminalMargin/TerminalVBox/TerminalHeader
@onready var fullscreen_terminal_button: Button = $TerminalPanel/TerminalMargin/TerminalVBox/TerminalHeader/FullscreenTerminalButton
@onready var close_terminal_button: Button = $TerminalPanel/TerminalMargin/TerminalVBox/TerminalHeader/CloseTerminalButton

var _terminal_is_open := false
var _current_terminal_path := ""
var _owned_input_lock := false
var _previous_input_locked := false
var _terminal_is_fullscreen := false
var _is_dragging_terminal := false
var _terminal_drag_offset := Vector2.ZERO
var _terminal_saved_window_rect := Rect2(300.0, 120.0, 680.0, 360.0)
var _last_recorded_location := ""

func _ready() -> void:
	if file_item and not file_item.gui_input.is_connected(_on_file_item_gui_input):
		file_item.gui_input.connect(_on_file_item_gui_input)
	if term_item and not term_item.gui_input.is_connected(_on_term_item_gui_input):
		term_item.gui_input.connect(_on_term_item_gui_input)
	if run_command_button and not run_command_button.pressed.is_connected(_on_run_command_pressed):
		run_command_button.pressed.connect(_on_run_command_pressed)
	if fullscreen_terminal_button and not fullscreen_terminal_button.pressed.is_connected(_toggle_terminal_fullscreen):
		fullscreen_terminal_button.pressed.connect(_toggle_terminal_fullscreen)
	if close_terminal_button and not close_terminal_button.pressed.is_connected(_close_terminal):
		close_terminal_button.pressed.connect(_close_terminal)
	if terminal_input and not terminal_input.text_submitted.is_connected(_on_terminal_text_submitted):
		terminal_input.text_submitted.connect(_on_terminal_text_submitted)
	if terminal_header and not terminal_header.gui_input.is_connected(_on_terminal_header_gui_input):
		terminal_header.gui_input.connect(_on_terminal_header_gui_input)
	if run_command_button:
		run_command_button.text = "[ENTER]"
	if fullscreen_terminal_button:
		fullscreen_terminal_button.text = "[MAX]"
	if close_terminal_button:
		close_terminal_button.text = "[EXIT]"
	if terminal_input:
		terminal_input.placeholder_text = "type command here..."
	_record_current_location_explored()
	randomize()
	_update_visibility()

func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = VISIBILITY_CHECK_INTERVAL
	_record_current_location_explored()
	_update_visibility()

func _input(event: InputEvent) -> void:
	if not visible or get_tree().paused:
		return
	if file_item == null and term_item == null:
		return

	if _terminal_is_open and event.is_action_pressed("ui_cancel"):
		_close_terminal()
		get_viewport().set_input_as_handled()
		return

	if _terminal_is_open and _is_dragging_terminal and event is InputEventMouseMotion:
		_update_terminal_drag_position((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var click := event as InputEventMouseButton
		if file_item and file_item.get_global_rect().has_point(click.position):
			_open_file_explorer_from_hud()
			return
		if term_item and term_item.get_global_rect().has_point(click.position):
			_open_terminal()

func _unhandled_input(event: InputEvent) -> void:
	if not _terminal_is_open:
		return
	if event is InputEventKey and event.pressed:
		get_viewport().set_input_as_handled()

func _update_visibility() -> void:
	var should_show := not _is_combat_ui_visible()
	visible = should_show
	_set_quest_list_visible(should_show)
	if not should_show and _terminal_is_open:
		_close_terminal()

func _set_quest_list_visible(should_show: bool) -> void:
	var root := get_tree().root
	if root == null:
		return

	var quest_list := root.find_child(QUEST_LIST_NODE_NAME, true, false)
	if quest_list == null:
		return

	if quest_list is CanvasItem:
		(quest_list as CanvasItem).visible = should_show

func _is_combat_ui_visible() -> bool:
	var root := get_tree().root
	if root == null:
		return false

	# Use find_children (array) so a hidden boss-door terminal instance
	# doesn't shadow the active encounter terminal.
	var nodes := root.find_children(COMBAT_UI_NODE_NAME, "", true, false)
	for node in nodes:
		if node is CanvasItem:
			var ci := node as CanvasItem
			if ci.visible and ci.is_visible_in_tree():
				return true

	return false

func _on_file_item_gui_input(event: InputEvent) -> void:
	if not visible or get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_file_explorer_from_hud()

func _on_term_item_gui_input(event: InputEvent) -> void:
	if not visible or get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_terminal()

func _open_file_explorer_from_hud() -> void:
	if _terminal_is_open:
		_close_terminal()
	var pause_menu := get_node_or_null("/root/PauseMenu")
	if pause_menu and pause_menu.has_method("open_file_explorer_from_main_ui"):
		pause_menu.call("open_file_explorer_from_main_ui")

func _open_terminal() -> void:
	if terminal_panel == null:
		return
	_record_current_location_explored()
	_current_terminal_path = _get_current_location_key()
	if _current_terminal_path == "":
		_current_terminal_path = DEFAULT_HUB_LOCATION
	_acquire_terminal_input_lock()
	_terminal_is_open = true
	terminal_panel.visible = true
	if terminal_output and terminal_output.get_parsed_text().is_empty():
		_print_terminal_line("NOVA SHELL ready. Type help to list commands.")
		_print_terminal_line("Current directory: %s" % _terminal_pwd())
	if terminal_input:
		terminal_input.call_deferred("grab_focus")

func _close_terminal() -> void:
	_terminal_is_open = false
	_is_dragging_terminal = false
	_release_terminal_input_lock()
	if terminal_panel:
		terminal_panel.visible = false

func _on_run_command_pressed() -> void:
	if terminal_input:
		_process_terminal_command(terminal_input.text)

func _on_terminal_text_submitted(text: String) -> void:
	_process_terminal_command(text)

func _process_terminal_command(raw_command: String) -> void:
	if not _terminal_is_open:
		return

	var text := raw_command.strip_edges()
	if terminal_input:
		terminal_input.clear()
		terminal_input.grab_focus()

	if text.is_empty():
		return

	_print_terminal_line("$ %s" % text)

	var parts := text.split(" ", false)
	var command := parts[0].to_lower()
	var args := parts.slice(1)

	match command:
		"help", "?":
			_print_terminal_line("Commands: help, map, pwd, ls, cd <location>, cd .., explorer, save, quit, clear, sudo shutdown")
			_print_terminal_line("Locations: hamlet, filesystem_forest, deamon_depths, bios_vault")
		"map":
			_print_location_map()
		"pwd":
			_print_terminal_line(_terminal_pwd())
		"ls", "dir":
			_handle_ls_command()
		"cd":
			_handle_cd_command(args)
		"explorer", "files", "open":
			_print_terminal_line("Opening file explorer...")
			_open_file_explorer_from_hud()
		"save":
			_handle_save_command()
		"quit", "exit":
			_print_terminal_line("Closing terminal...")
			_close_terminal()
		"sudo":
			if args.size() > 0 and String(args[0]).to_lower() == "shutdown":
				_print_terminal_line("Shutting down Learnix...")
				get_tree().quit()
			else:
				_print_terminal_line("sudo: supported command is `sudo shutdown`")
		"clear", "cls":
			if terminal_output:
				terminal_output.clear()
		_:
			_print_terminal_line("Unknown command: %s" % command)
			_print_terminal_line("Try `help`.")

	_maybe_print_fun_fact()

func _terminal_pwd() -> String:
	if _current_terminal_path == "":
		return TERMINAL_ROOT_PATH
	return "%s/%s" % [TERMINAL_ROOT_PATH, _current_terminal_path]

func _handle_ls_command() -> void:
	var entries: Array = TERMINAL_DIRECTORIES.get(_current_terminal_path, [])
	if entries.is_empty():
		_print_terminal_line("(empty)")
		return
	for entry in entries:
		_print_terminal_line(str(entry))

func _handle_cd_command(args: Array) -> void:
	if args.is_empty():
		_current_terminal_path = DEFAULT_HUB_LOCATION
		_print_terminal_line(_terminal_pwd())
		return

	var target := String(args[0]).strip_edges().to_lower()
	if target == "..":
		var source_location := _get_current_location_key()
		if source_location == "":
			source_location = _current_terminal_path
		_current_terminal_path = DEFAULT_HUB_LOCATION
		_print_terminal_line("Teleporting to %s..." % DEFAULT_HUB_LOCATION)
		_teleport_to_terminal_location(DEFAULT_HUB_LOCATION, _hub_return_spawn_for_location(source_location))
		return

	if target == "/" or target == "~":
		_current_terminal_path = DEFAULT_HUB_LOCATION
		_print_terminal_line(_terminal_pwd())
		return

	var location_key := String(TERMINAL_LOCATION_ALIASES.get(target, ""))
	if location_key == "":
		_print_terminal_line("cd: no such location: %s" % target)
		return

	if location_key != DEFAULT_HUB_LOCATION:
		if not _is_terminal_location_unlocked(location_key):
			_print_terminal_line("cd: access denied (%s is still locked)." % location_key)
			return
		if not _has_explored_location(location_key):
			_print_terminal_line("cd: access denied (%s not discovered yet)." % location_key)
			return

	_current_terminal_path = location_key
	_print_terminal_line("Teleporting to %s..." % location_key)
	_teleport_to_terminal_location(location_key, "")

func _teleport_to_terminal_location(location_key: String, spawn_override: String = "") -> void:
	if SceneManager == null:
		_print_terminal_line("Teleport unavailable: SceneManager not found.")
		return

	var target_data: Dictionary = TERMINAL_TELEPORT_TARGETS.get(location_key, {})
	if target_data.is_empty():
		_print_terminal_line("Teleport unavailable for: %s" % location_key)
		return

	var scene_path := String(target_data.get("scene", ""))
	var spawn_path := String(target_data.get("spawn", "")) if spawn_override == "" else spawn_override
	if scene_path == "" or spawn_path == "":
		_print_terminal_line("Teleport target is misconfigured.")
		return

	_close_terminal()
	SceneManager.teleport_to_scene(scene_path, spawn_path, 0.1)

func _hub_return_spawn_for_location(location_key: String) -> String:
	match location_key:
		"bios_vault":
			return HUB_BIOS_RETURN_SPAWN
		"deamon_depths":
			return HUB_DEPTHS_RETURN_SPAWN
		"filesystem_forest":
			return HUB_FOREST_RETURN_SPAWN
		_:
			return HUB_DEFAULT_SPAWN

func _is_terminal_location_unlocked(location_key: String) -> bool:
	if SceneManager == null:
		return location_key == DEFAULT_HUB_LOCATION

	match location_key:
		"bios_vault":
			return SceneManager.gatekeeper_pass_granted or SceneManager.deamon_depths_boss_door_unlocked or bool(SceneManager.get_meta("bios_vault_sage_quiz_passed", false))
		"deamon_depths":
			return SceneManager.proficiency_key_forest or SceneManager.broken_link_fragmented_key or _has_explored_location("deamon_depths")
		"filesystem_forest":
			return true
		"fallback_hamlet":
			return true
		_:
			return false

func _record_current_location_explored() -> void:
	if SceneManager == null:
		return
	var current_location := _get_current_location_key()
	if current_location == "":
		return
	if current_location == _last_recorded_location:
		return
	var explored := _get_explored_locations()
	if explored.has(current_location):
		_last_recorded_location = current_location
		return
	explored.append(current_location)
	SceneManager.set_meta(TERMINAL_EXPLORED_META_KEY, explored)
	_last_recorded_location = current_location

func _get_explored_locations() -> Array[String]:
	if SceneManager == null:
		return [DEFAULT_HUB_LOCATION]
	var meta_value = SceneManager.get_meta(TERMINAL_EXPLORED_META_KEY, [DEFAULT_HUB_LOCATION])
	var explored: Array[String] = []
	if meta_value is Array:
		for entry in meta_value:
			explored.append(String(entry))
	if not explored.has(DEFAULT_HUB_LOCATION):
		explored.append(DEFAULT_HUB_LOCATION)
	return explored

func _has_explored_location(location_key: String) -> bool:
	return _get_explored_locations().has(location_key)

func _get_current_location_key() -> String:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return ""
	return _location_key_from_scene_path(current_scene.scene_file_path)

func _location_key_from_scene_path(scene_path: String) -> String:
	match scene_path:
		"res://Scenes/Levels/fallback_hamlet.tscn":
			return "fallback_hamlet"
		"res://Scenes/Levels/file_system_forest.tscn":
			return "filesystem_forest"
		"res://Scenes/Levels/deamon_depths.tscn":
			return "deamon_depths"
		"res://Scenes/Levels/bios_vault.tscn", "res://Scenes/Levels/bios_vault_.tscn":
			return "bios_vault"
		_:
			return ""

func _toggle_terminal_fullscreen() -> void:
	_set_terminal_fullscreen(not _terminal_is_fullscreen)

func _set_terminal_fullscreen(fullscreen_enabled: bool) -> void:
	if terminal_panel == null:
		return
	if _terminal_is_fullscreen == fullscreen_enabled:
		return

	if fullscreen_enabled:
		_terminal_saved_window_rect = Rect2(terminal_panel.position, terminal_panel.size)
		terminal_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		terminal_panel.offset_left = 0.0
		terminal_panel.offset_top = 0.0
		terminal_panel.offset_right = 0.0
		terminal_panel.offset_bottom = 0.0
		if fullscreen_terminal_button:
			fullscreen_terminal_button.text = "[WIN]"
		_terminal_is_fullscreen = true
		return

	terminal_panel.anchor_left = 0.0
	terminal_panel.anchor_top = 0.0
	terminal_panel.anchor_right = 0.0
	terminal_panel.anchor_bottom = 0.0
	terminal_panel.offset_left = _terminal_saved_window_rect.position.x
	terminal_panel.offset_top = _terminal_saved_window_rect.position.y
	terminal_panel.offset_right = _terminal_saved_window_rect.position.x + _terminal_saved_window_rect.size.x
	terminal_panel.offset_bottom = _terminal_saved_window_rect.position.y + _terminal_saved_window_rect.size.y
	_clamp_terminal_to_viewport()
	if fullscreen_terminal_button:
		fullscreen_terminal_button.text = "[MAX]"
	_terminal_is_fullscreen = false

func _on_terminal_header_gui_input(event: InputEvent) -> void:
	if _terminal_is_fullscreen:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var click := event as InputEventMouseButton
		if click.pressed:
			_is_dragging_terminal = true
			_terminal_drag_offset = click.global_position - terminal_panel.global_position
		else:
			_is_dragging_terminal = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _is_dragging_terminal:
		var motion := event as InputEventMouseMotion
		_update_terminal_drag_position(motion.global_position)
		get_viewport().set_input_as_handled()

func _update_terminal_drag_position(mouse_global_pos: Vector2) -> void:
	if terminal_panel == null:
		return
	var new_pos := mouse_global_pos - _terminal_drag_offset
	terminal_panel.position = new_pos
	_clamp_terminal_to_viewport()

func _clamp_terminal_to_viewport() -> void:
	if terminal_panel == null or _terminal_is_fullscreen:
		return
	var viewport_size := get_viewport_rect().size
	var panel_size := terminal_panel.size
	var clamped_x := clampf(terminal_panel.position.x, 0.0, max(0.0, viewport_size.x - panel_size.x))
	var clamped_y := clampf(terminal_panel.position.y, 0.0, max(0.0, viewport_size.y - panel_size.y))
	terminal_panel.position = Vector2(clamped_x, clamped_y)

func _handle_save_command() -> void:
	if _invoke_scene_manager_method("quick_save"):
		_print_terminal_line("Quick save complete.")
		return
	if _invoke_scene_manager_method("save_game"):
		_print_terminal_line("Save requested.")
		return
	_print_terminal_line("Save is not available yet.")

func _print_location_map() -> void:
	_print_terminal_line("Location map:")
	for location_key in TERMINAL_DIRECTORIES.get("", []):
		var unlocked := _is_terminal_location_unlocked(location_key)
		var explored := _has_explored_location(location_key)
		var status := "[available]"
		if not unlocked:
			status = "[locked]"
		elif not explored:
			status = "[undiscovered]"
		_print_terminal_line("- %s %s" % [location_key, status])

func _invoke_scene_manager_method(method_name: String) -> bool:
	if SceneManager and SceneManager.has_method(method_name):
		return bool(SceneManager.call(method_name))
	return false

func _maybe_print_fun_fact() -> void:
	if TERMINAL_FUN_FACTS.is_empty():
		return
	if randf() > 0.25:
		return
	var fact :String = TERMINAL_FUN_FACTS[randi() % TERMINAL_FUN_FACTS.size()]
	_print_terminal_line("[fun] %s" % fact)

func _print_terminal_line(text: String) -> void:
	if terminal_output == null:
		return
	terminal_output.append_text("%s\n" % text)

func _acquire_terminal_input_lock() -> void:
	if SceneManager == null:
		return
	if _owned_input_lock:
		return
	_previous_input_locked = SceneManager.input_locked
	SceneManager.input_locked = true
	_owned_input_lock = true

func _release_terminal_input_lock() -> void:
	if SceneManager == null:
		return
	if not _owned_input_lock:
		return
	SceneManager.input_locked = _previous_input_locked
	_owned_input_lock = false
