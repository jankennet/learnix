extends Control

signal terminal_command_executed(command: String, args: Array)

const COMBAT_UI_NODE_NAME := "CombatTerminalUI"
const QUEST_LIST_NODE_NAME := "QuestList"
const VISIBILITY_CHECK_INTERVAL := 0.15
const TERMINAL_ROOT_PATH := "/home/nova"
const TUTORIAL_LOCATION := "tutorial_boot"
const DEFAULT_HUB_LOCATION := "fallback_hamlet"
const TERMINAL_EXPLORED_META_KEY := "terminal_explored_locations"
const HUB_DEFAULT_SPAWN := "Fallback_Hamlet_Final/first_spawn"
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
	"tutorial": TUTORIAL_LOCATION,
	"tutorial_boot": TUTORIAL_LOCATION,
	"linuxia_intro": TUTORIAL_LOCATION,
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
	TUTORIAL_LOCATION: ["onboarding_notes.txt", "controls.cheatsheet", "welcome_terminal.log"],
	"desktop": ["welcome.txt", "npc_notes.log", "quests.todo"],
	"filesystem_forest": ["symlink_map.md", "lost_file.fragment", "roots/"],
	"deamon_depths": ["driver_remnant.log", "printer_queue.dat", "bossdoor.keyhint"],
	"fallback_hamlet": ["market.square", "well.archive", "home.instance"],
	"bios_vault": ["firmware_records.bin", "sage_protocol.md", "locked_segment/"],
}

const TERMINAL_FILE_CONTENTS := {
	"onboarding_notes.txt": "Welcome to Linuxia onboarding.\nTry commands: pwd, ls, cat <file>.",
	"controls.cheatsheet": "WASD: move\nE: interact\nUse terminal to learn more.",
	"welcome_terminal.log": "[log] Welcome to Nova Shell.\nSystem initialized.",
	"welcome.txt": "Welcome home, traveler.",
	"npc_notes.log": "NPC: Tux may help you during onboarding.",
	"quests.todo": "- Visit the market\n- Talk to Tux\n- Learn the terminal",
	"symlink_map.md": "# Symlink Map\n- /roots -> roots/",
	"lost_file.fragment": "<fragment> corrupted data...",
	"driver_remnant.log": "driver remnant diagnostics...",
	"printer_queue.dat": "printer queue: empty",
	"market.square": "Market square index file.",
	"well.archive": "Old well archive entries.",
	"home.instance": "Home instance descriptor.",
	"firmware_records.bin": "<binary>",
	"sage_protocol.md": "Sage protocol notes.",
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
@onready var quest_item: Control = $TopRight/MenuStack/QuestItem
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
	if quest_item and not quest_item.gui_input.is_connected(_on_quest_item_gui_input):
		quest_item.gui_input.connect(_on_quest_item_gui_input)
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
		terminal_input.placeholder_text = "Type command (help, ls, cat, save, quit)"
	_record_current_location_explored()
	randomize()
	_update_visibility()

	# Ensure a side quest button exists (exclamation on screen edge)
	if get_tree().get_root().find_child("QuestSideButton", true, false) == null:
		var QuestSideScene := preload("res://Scenes/ui/QuestSideButton.tscn")
		if QuestSideScene:
			var side_btn: QuestSideButton = QuestSideScene.instantiate() as QuestSideButton
			get_tree().get_root().add_child(side_btn)

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


func _on_quest_item_gui_input(event: InputEvent) -> void:
	if not visible or get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Open QuestWindow for the first active quest in the QuestManager
		if has_node("/root/SceneManager") and SceneManager and SceneManager.quest_manager:
			var qm := SceneManager.quest_manager
			var act := qm.get_active_quests()
			if act.size() > 0:
				var qid := act[0]
				var q := qm.get_quest(qid)
				if q:
					var QuestWindowScene := preload("res://Scenes/ui/QuestWindow.tscn")
					var w: QuestWindow = QuestWindowScene.instantiate() as QuestWindow
					get_tree().get_root().add_child(w)
					w.set_quest(q)
					return
		# Fallback: toggle small quest list UI if it exists
		var root := get_tree().root
		if root:
			var quest_list := root.find_child(QUEST_LIST_NODE_NAME, true, false)
			if quest_list and quest_list is CanvasItem:
				(quest_list as CanvasItem).visible = not (quest_list as CanvasItem).visible

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
		_current_terminal_path = _terminal_home_location()
	_acquire_terminal_input_lock()
	_terminal_is_open = true
	terminal_panel.visible = true
	if SceneManager:
		SceneManager.play_sfx("res://album/sfx/open-terminal.mp3")
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
	emit_signal("terminal_command_executed", command, args)

	match command:
		"help", "?":
			_print_terminal_line("Commands: help, map, pwd, ls, cat <file>, cd <location>, cd .., explorer, save, quit, clear, sudo shutdown")
			if _is_tutorial_scene_active():
				_print_terminal_line("Locations: tutorial")
			else:
				_print_terminal_line("Locations: hamlet, filesystem_forest, deamon_depths, bios_vault")
		"map":
			_print_location_map()
		"pwd":
			_print_terminal_line(_terminal_pwd())
		"ls", "dir":
			_handle_ls_command()
		"cat":
			_handle_cat_command(args)
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
	if _is_tutorial_scene_active() and _current_terminal_path == "":
		_print_terminal_line(TUTORIAL_LOCATION)
		return
	var entries: Array = TERMINAL_DIRECTORIES.get(_current_terminal_path, [])
	if entries.is_empty():
		_print_terminal_line("(empty)")
		return
	for entry in entries:
		_print_terminal_line(str(entry))

func _handle_cat_command(args: Array) -> void:
	if args.is_empty():
		_print_terminal_line("Usage: cat <file>")
		return

	var target := String(args[0]).strip_edges()
	# If user provided a path-like arg, collapse to basename for our simple lookup
	var basename := target.get_file()

	# Check current directory entries first
	var entries: Array = TERMINAL_DIRECTORIES.get(_current_terminal_path, [])
	if entries.has(target) or entries.has(basename):
		var content: String = String(TERMINAL_FILE_CONTENTS.get(target, TERMINAL_FILE_CONTENTS.get(basename, "(no readable content)")))
		for line in content.split("\n", false):
			_print_terminal_line(str(line))
		return

	# Try global lookup
	if TERMINAL_FILE_CONTENTS.has(target) or TERMINAL_FILE_CONTENTS.has(basename):
		var content2: String = String(TERMINAL_FILE_CONTENTS.get(target, TERMINAL_FILE_CONTENTS.get(basename, "")))
		for line in content2.split("\n", false):
			_print_terminal_line(str(line))
		return

	_print_terminal_line("cat: file not found: %s" % target)

func _handle_cd_command(args: Array) -> void:
	if args.is_empty():
		_current_terminal_path = _terminal_home_location()
		_print_terminal_line(_terminal_pwd())
		return

	var target := String(args[0]).strip_edges().to_lower()
	if target == "..":
		var source_location := _get_current_location_key()
		if source_location == "":
			source_location = _current_terminal_path
		var home := _terminal_home_location()
		_current_terminal_path = home
		if home == TUTORIAL_LOCATION:
			_print_terminal_line(_terminal_pwd())
			return
		_print_terminal_line("Teleporting to %s..." % home)
		_teleport_to_terminal_location(home, _hub_return_spawn_for_location(source_location))
		return

	if target == "/" or target == "~":
		_current_terminal_path = _terminal_home_location()
		_print_terminal_line(_terminal_pwd())
		return

	var location_key := String(TERMINAL_LOCATION_ALIASES.get(target, ""))
	if location_key == "":
		if _is_tutorial_scene_active() and target == "home":
			location_key = TUTORIAL_LOCATION
		else:
			_print_terminal_line("cd: no such location: %s" % target)
			return

	if _is_tutorial_scene_active() and location_key != TUTORIAL_LOCATION:
		_print_terminal_line("cd: access denied during onboarding.")
		return

	if location_key == TUTORIAL_LOCATION:
		_current_terminal_path = TUTORIAL_LOCATION
		_print_terminal_line(_terminal_pwd())
		return

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
		TUTORIAL_LOCATION:
			return true
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
		return [_terminal_home_location()]
	var home_location := _terminal_home_location()
	var meta_value = SceneManager.get_meta(TERMINAL_EXPLORED_META_KEY, [home_location])
	var explored: Array[String] = []
	if meta_value is Array:
		for entry in meta_value:
			explored.append(String(entry))
	if not explored.has(home_location):
		explored.append(home_location)
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
		"res://Scenes/Levels/tutorial - Copy.tscn":
			return TUTORIAL_LOCATION
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
	for location_key in _visible_terminal_locations():
		var unlocked := _is_terminal_location_unlocked(location_key)
		var explored := _has_explored_location(location_key)
		var status := "[available]"
		if not unlocked:
			status = "[locked]"
		elif not explored:
			status = "[undiscovered]"
		_print_terminal_line("- %s %s" % [location_key, status])

func _visible_terminal_locations() -> Array:
	if _is_tutorial_scene_active():
		return [TUTORIAL_LOCATION]
	return TERMINAL_DIRECTORIES.get("", [])

func _terminal_home_location() -> String:
	if _is_tutorial_scene_active():
		return TUTORIAL_LOCATION
	return DEFAULT_HUB_LOCATION

func _is_tutorial_scene_active() -> bool:
	return _get_current_location_key() == TUTORIAL_LOCATION

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
