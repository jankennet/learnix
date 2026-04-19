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
const SKILL_UNLOCK_RECEIPTS_META_KEY := "skill_unlock_receipts"
const SKILL_UNLOCK_FLAGS := {
	"cli_history": "cli_history_unlocked",
	"teleport": "teleport_unlocked",
	"file_explorer": "file_explorer_unlocked",
	"mkdir_construct": "mkdir_construct_unlocked",
	"taskkill": "taskkill_unlocked",
	"sudo_privilege": "sudo_privilege_unlocked",
	"potion_patch": "potion_patch_unlocked",
	"potion_overclock": "potion_overclock_unlocked",
	"potion_hardening": "potion_hardening_unlocked",
}
const SKILL_UNLOCK_COSTS := {
	"taskkill": 120,
	"potion_patch": 150,
	"potion_overclock": 220,
	"potion_hardening": 260,
	"sudo_privilege": 320,
}

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

var terminal_panel: TerminalPanel = null
var terminal_output: RichTextLabel = null
var terminal_input: LineEdit = null
var run_command_button: Button = null
var terminal_header: Control = null
var fullscreen_terminal_button: Button = null
var close_terminal_button: Button = null

var _terminal_is_open := false
var _current_terminal_path := ""
var _owned_input_lock := false
var _previous_input_locked := false
var _terminal_is_fullscreen := false
var _is_dragging_terminal := false
var _terminal_drag_offset := Vector2.ZERO
var _terminal_saved_window_rect := Rect2(300.0, 120.0, 680.0, 360.0)
var _last_recorded_location := ""
var _cached_quest_list: CanvasItem = null
var _terminal_history: Array[String] = []
var _terminal_history_index := -1
var _terminal_history_draft := ""
var _tutorial_terminal_progress := {
	"pwd": false,
	"ls": false,
	"cat": false,
}
var _shop_panel: Control = null
var _shutdown_confirm_dialog: ConfirmationDialog = null
var _shutdown_main_menu_button: Button = null

func _ready() -> void:
	# Instantiate TerminalPanel scene
	var TerminalPanelScene := preload("res://Scenes/ui/TerminalPanel.tscn")
	terminal_panel = TerminalPanelScene.instantiate() as TerminalPanel
	get_tree().get_root().add_child(terminal_panel)
	
	# Get references to terminal UI elements
	terminal_output = terminal_panel.get_output()
	terminal_input = terminal_panel.get_input()
	run_command_button = terminal_panel.get_run_button()
	terminal_header = terminal_panel.get_header()
	fullscreen_terminal_button = terminal_panel.fullscreen_button
	close_terminal_button = terminal_panel.close_button
	
	# Connect button callbacks
	terminal_panel.set_button_callbacks(
		Callable(self, "_close_terminal"),
		Callable(self, "_toggle_terminal_fullscreen"),
		Callable(self, "_close_terminal")  # Minimize also closes for now
	)
	
	# Connect input signals
	if file_item and not file_item.gui_input.is_connected(_on_file_item_gui_input):
		file_item.gui_input.connect(_on_file_item_gui_input)
	if term_item and not term_item.gui_input.is_connected(_on_term_item_gui_input):
		term_item.gui_input.connect(_on_term_item_gui_input)
	if quest_item and not quest_item.gui_input.is_connected(_on_quest_item_gui_input):
		quest_item.gui_input.connect(_on_quest_item_gui_input)
	if run_command_button and not run_command_button.pressed.is_connected(_on_run_command_pressed):
		run_command_button.pressed.connect(_on_run_command_pressed)
	if terminal_input and not terminal_input.text_submitted.is_connected(_on_terminal_text_submitted):
		terminal_input.text_submitted.connect(_on_terminal_text_submitted)
	if terminal_input and not terminal_input.focus_exited.is_connected(_on_terminal_input_focus_exited):
		terminal_input.focus_exited.connect(_on_terminal_input_focus_exited)
	if terminal_header and not terminal_header.gui_input.is_connected(_on_terminal_header_gui_input):
		terminal_header.gui_input.connect(_on_terminal_header_gui_input)
	if terminal_input:
		terminal_input.placeholder_text = "Type command (help, ls, cat, save, quit)"
	
	_record_current_location_explored()
	randomize()
	_update_visibility()
	_setup_shutdown_confirm_dialog()

	# Ensure a side quest button exists (exclamation on screen edge)
	if get_tree().get_root().find_child("QuestSideButton", true, false) == null:
		var QuestSideScene := preload("res://Scenes/ui/QuestSideButton.tscn")
		if QuestSideScene:
			var side_btn: QuestSideButton = QuestSideScene.instantiate() as QuestSideButton
			get_tree().get_root().add_child(side_btn)

func _process(delta: float) -> void:
	_restore_terminal_focus_if_needed()
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = VISIBILITY_CHECK_INTERVAL
	_record_current_location_explored()
	_update_visibility()

func _input(event: InputEvent) -> void:
	if not visible or get_tree().paused:
		return
	if file_item == null and term_item == null and quest_item == null:
		return

	if _terminal_is_open and event.is_action_pressed("ui_cancel"):
		_close_terminal()
		get_viewport().set_input_as_handled()
		return

	if _terminal_is_open and event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if terminal_input and not terminal_input.has_focus() and not _is_terminal_modal_active():
			if _route_key_to_terminal_input(key_event):
				get_viewport().set_input_as_handled()
				return
			_claim_terminal_input_focus()
			# Swallow this key so it doesn't trigger unrelated focused controls.
			get_viewport().set_input_as_handled()
			return
		# Handle Enter key when input HAS focus - intercept before LineEdit processes it
		if terminal_input and terminal_input.has_focus() and (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER):
			_process_terminal_command(terminal_input.text)
			_claim_terminal_input_focus()
			get_viewport().set_input_as_handled()
			return
		if key_event.keycode == KEY_UP or key_event.keycode == KEY_DOWN:
			if terminal_input and terminal_input.has_focus():
				# Never allow any history navigation path unless CLI history is unlocked.
				if not _is_cli_history_unlocked():
					get_viewport().set_input_as_handled()
					return
				if key_event.keycode == KEY_UP:
					_navigate_terminal_history_previous()
				else:
					_navigate_terminal_history_next()
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
			return
		if quest_item and quest_item.get_global_rect().has_point(click.position):
			_open_tux_helper_from_hud()

func _unhandled_input(_event: InputEvent) -> void:
	if not _terminal_is_open:
		return

func _update_visibility() -> void:
	var should_show := not _is_combat_ui_visible()
	visible = should_show
	_set_quest_list_visible(should_show)
	# Hide file item until file explorer is unlocked.
	if file_item:
		file_item.visible = should_show and _is_file_explorer_unlocked()
	if not should_show and _terminal_is_open:
		_close_terminal()

func _set_quest_list_visible(should_show: bool) -> void:
	var quest_list := _get_quest_list_node()
	if quest_list:
		quest_list.visible = should_show

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

func _is_file_explorer_unlocked() -> bool:
	return _is_skill_unlocked("file_explorer")

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
		_open_tux_helper_from_hud()

func _open_tux_helper_from_hud() -> void:
	if _terminal_is_open:
		_close_terminal()

	if has_node("/root/SceneManager") and SceneManager:
		var tux_ctrl := SceneManager.get_node_or_null("TuxDialogueController")
		if tux_ctrl and tux_ctrl.has_method("show_world_hint_from_hud"):
			tux_ctrl.call("show_world_hint_from_hud")
			return
		if tux_ctrl and tux_ctrl.has_method("_show_tux_line"):
			tux_ctrl.call("_show_tux_line", "I am online. Explore Linuxia and check your active quests for your next move.")
			return

	_open_quest_window_or_toggle_list()

func _open_quest_window_or_toggle_list() -> void:
	# Fallback behavior when Tux dialogue controller is unavailable.
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

	var quest_list := _get_quest_list_node()
	if quest_list:
		quest_list.visible = not quest_list.visible

func _get_quest_list_node() -> CanvasItem:
	if _cached_quest_list and is_instance_valid(_cached_quest_list):
		return _cached_quest_list

	var root := get_tree().root
	if root == null:
		return null

	var found := root.find_child(QUEST_LIST_NODE_NAME, true, false)
	if found is CanvasItem:
		_cached_quest_list = found as CanvasItem
		return _cached_quest_list

	return null

func _open_file_explorer_from_hud() -> void:
	if not _is_file_explorer_unlocked():
		return
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
	if _is_tutorial_terminal_guided_mode():
		if _is_tutorial_terminal_progress_empty():
			_reset_tutorial_terminal_progress()
		_print_terminal_line("Tutorial mode: we only need 3 commands for now -> pwd, ls, cat <file-name>")
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

func _on_terminal_input_focus_exited() -> void:
	if not _terminal_is_open or _is_terminal_modal_active():
		return
	_claim_terminal_input_focus()

func _process_terminal_command(raw_command: String) -> void:
	if not _terminal_is_open:
		return

	var text := raw_command.strip_edges()
	if terminal_input:
		terminal_input.clear()
		terminal_input.call_deferred("grab_focus")

	if text.is_empty():
		return

	_push_terminal_history(text)
	_terminal_history_index = -1
	_terminal_history_draft = ""

	_print_terminal_line("$ %s" % text)

	var parts := text.split(" ", false)
	var command := parts[0].to_lower()
	var args := parts.slice(1)
	_track_tutorial_terminal_progress(command, args)
	emit_signal("terminal_command_executed", command, args)

	match command:
		"help", "?":
			if _is_tutorial_terminal_guided_mode():
				_print_tutorial_help_guidance()
			else:
				var help_text = "Commands: help, map, pwd, ls, cat <file>, explorer, history, shop, save, quit, clear"
				if _is_cd_command_unlocked():
					help_text += ", cd <location>, cd .."
				help_text += ", echo <text>, whoami, date, uname, touch <file>, mkdir <dir>, rm <file>, sudo shutdown, wget <url>"
				_print_terminal_line(help_text)
				if _is_cli_history_unlocked():
					_print_terminal_line("Tip: use [Up Key] / [Down Key] for command history.")
				else:
					_print_terminal_line("Tip: unlock CLI history with wget learnix://skills/cli_history.unlock")
				var help_locations := _help_location_labels()
				if not help_locations.is_empty():
					_print_terminal_line("Locations: %s" % ", ".join(help_locations))
		"map":
			_print_location_map()
		"pwd":
			_print_terminal_line(_terminal_pwd())
		"ls", "dir":
			_handle_ls_command()
		"cat":
			_handle_cat_command(args)
		"cd":
			if not _is_cd_command_unlocked():
				_print_terminal_line("cd: command not found (defeat PrinterBoss to unlock)")
			else:
				_handle_cd_command(args)
		"echo":
			if args.is_empty():
				_print_terminal_line("")
			else:
				_print_terminal_line(" ".join(args))
		"history":
			_handle_history_command()
		"shop":
			_print_terminal_line("Opening skill shop...")
			_open_shop_from_terminal()
		"wget":
			_handle_wget_command(args)
		"whoami":
			_print_terminal_line("nova")
		"date":
			_print_terminal_line(Time.get_datetime_string_from_system())
		"uname":
			_print_terminal_line("Linuxia 5.15.0 #1 SMP x86_64 GNU/Linux")
		"touch":
			if args.is_empty():
				_print_terminal_line("touch: missing file operand")
			else:
				_print_terminal_line("touch: created %s" % args[0])
		"mkdir":
			if args.is_empty():
				_print_terminal_line("mkdir: missing directory operand")
			else:
				_print_terminal_line("mkdir: created directory '%s'" % args[0])
		"rm":
			if args.is_empty():
				_print_terminal_line("rm: missing file operand")
			else:
				_print_terminal_line("rm: removed '%s'" % args[0])
		"explorer", "files", "open":
			if not _is_file_explorer_unlocked():
				_print_terminal_line("explorer: command not available (unlock with wget learnix://skills/file_explorer.unlock)")
			else:
				_print_terminal_line("Opening file explorer...")
				_open_file_explorer_from_hud()
		"save":
			_handle_save_command()
		"quit", "exit":
			_print_terminal_line("Closing terminal...")
			_close_terminal()
		"sudo":
			if args.size() > 0 and String(args[0]).to_lower() == "shutdown":
				_request_shutdown_confirmation()
			else:
				_print_terminal_line("sudo: supported command is `sudo shutdown`")
		"clear", "cls":
			if terminal_output:
				terminal_output.clear()
		_:
			if _is_tutorial_terminal_guided_mode():
				_print_terminal_line("Let's keep it simple for tutorial: try pwd, ls, or cat <file-name>.")
				_print_tutorial_help_guidance()
			else:
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

	# Check if teleport skill is unlocked before allowing any teleportation
	if not _is_skill_unlocked("teleport"):
		_print_terminal_line("cd: teleport skill not unlocked (unlock with wget learnix://skills/teleport.unlock)")
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
			if SceneManager and bool(SceneManager.get_meta("evil_tux_boss_cleared", false)):
				return false
			return SceneManager.gatekeeper_pass_granted or SceneManager.deamon_depths_boss_door_unlocked or SceneManager.get_meta("bios_vault_sage_quiz_passed", false) == true
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

func _is_cd_command_unlocked() -> bool:
	if SceneManager == null:
		return false
	return SceneManager.printer_beast_defeated

func _is_cli_history_unlocked() -> bool:
	return _is_skill_unlocked("cli_history")

func _is_skill_unlocked(skill_name: String) -> bool:
	if SceneManager == null:
		return false
	var flag_name := String(SKILL_UNLOCK_FLAGS.get(skill_name, ""))
	if flag_name == "":
		return false
	if SceneManager.get(flag_name) != true:
		return false
	return _has_skill_unlock_receipt(skill_name)

func _get_skill_unlock_receipts() -> Dictionary:
	if SceneManager == null:
		return {}
	var stored: Variant = SceneManager.get_meta(SKILL_UNLOCK_RECEIPTS_META_KEY, {})
	if stored is Dictionary:
		return (stored as Dictionary).duplicate(true)
	return {}

func _has_skill_unlock_receipt(skill_name: String) -> bool:
	var receipts := _get_skill_unlock_receipts()
	return receipts.get(skill_name, false) == true

func _mark_skill_unlock_receipt(skill_name: String) -> void:
	if SceneManager == null:
		return
	var receipts := _get_skill_unlock_receipts()
	receipts[skill_name] = true
	SceneManager.set_meta(SKILL_UNLOCK_RECEIPTS_META_KEY, receipts)

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
		
		# Get the taskbar/HUD height to avoid covering it (taskbar is at bottom)
		var hud_height = 80.0  # Taskbar height with margin
		if term_item:
			# Calculate bottom position from taskbar location
			var taskbar_pos = term_item.get_global_rect().position.y
			var viewport_size = get_viewport_rect().size.y
			hud_height = viewport_size - taskbar_pos + 10  # Extra padding
		
		terminal_panel.anchor_left = 0.0
		terminal_panel.anchor_top = 0.0
		terminal_panel.anchor_right = 1.0
		terminal_panel.anchor_bottom = 1.0
		terminal_panel.offset_left = 0.0
		terminal_panel.offset_top = 0.0  # Full height from top
		terminal_panel.offset_right = 0.0
		terminal_panel.offset_bottom = -hud_height  # Leave room for bottom taskbar
		if fullscreen_terminal_button:
			fullscreen_terminal_button.text = "[-]"
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
		fullscreen_terminal_button.text = "[]"
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
	terminal_panel.position = mouse_global_pos - _terminal_drag_offset
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

func _setup_shutdown_confirm_dialog() -> void:
	_shutdown_confirm_dialog = ConfirmationDialog.new()
	_shutdown_confirm_dialog.name = "TerminalShutdownConfirmDialog"
	_shutdown_confirm_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_shutdown_confirm_dialog.exclusive = true
	add_child(_shutdown_confirm_dialog)
	_shutdown_main_menu_button = _shutdown_confirm_dialog.add_button("Main Menu", true, "to_main_menu")
	if not _shutdown_confirm_dialog.confirmed.is_connected(_on_shutdown_confirmed):
		_shutdown_confirm_dialog.confirmed.connect(_on_shutdown_confirmed)
	if not _shutdown_confirm_dialog.custom_action.is_connected(_on_shutdown_custom_action):
		_shutdown_confirm_dialog.custom_action.connect(_on_shutdown_custom_action)

func _request_shutdown_confirmation() -> void:
	if _shutdown_confirm_dialog == null:
		return
	_print_terminal_line("sudo: choose shutdown target...")
	_shutdown_confirm_dialog.title = "Sudo Shutdown"
	_shutdown_confirm_dialog.dialog_text = "Exit to main menu or quit to desktop?"
	_shutdown_confirm_dialog.ok_button_text = "Quit to Desktop"
	if _shutdown_main_menu_button and is_instance_valid(_shutdown_main_menu_button):
		_shutdown_main_menu_button.visible = true
	_shutdown_confirm_dialog.popup_centered(Vector2i(560, 180))

func _on_shutdown_confirmed() -> void:
	if _shutdown_confirm_dialog:
		_shutdown_confirm_dialog.hide()
	_print_terminal_line("Shutting down Learnix to desktop...")
	get_tree().quit()

func _on_shutdown_custom_action(action: StringName) -> void:
	if String(action) != "to_main_menu":
		return
	if _shutdown_confirm_dialog:
		_shutdown_confirm_dialog.hide()
	_print_terminal_line("Returning to main menu...")
	_close_terminal()
	if get_tree():
		get_tree().change_scene_to_file("res://Scenes/ui/title_menu.tscn")

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

	var all_locations: Array = TERMINAL_DIRECTORIES.get("", [])
	var visible_locations: Array = []
	for location_entry in all_locations:
		var location_key := String(location_entry)
		if location_key == DEFAULT_HUB_LOCATION:
			visible_locations.append(location_key)
			continue
		if _is_terminal_location_unlocked(location_key) and _has_explored_location(location_key):
			visible_locations.append(location_key)
	return visible_locations

func _help_location_labels() -> Array[String]:
	var labels: Array[String] = []
	for location_entry in _visible_terminal_locations():
		var location_key := String(location_entry)
		if location_key == DEFAULT_HUB_LOCATION:
			labels.append("hamlet")
		else:
			labels.append(location_key)
	return labels

func _terminal_home_location() -> String:
	if _is_tutorial_scene_active():
		return TUTORIAL_LOCATION
	return DEFAULT_HUB_LOCATION

func _is_tutorial_scene_active() -> bool:
	return _get_current_location_key() == TUTORIAL_LOCATION

func _is_tutorial_terminal_guided_mode() -> bool:
	if _is_tutorial_scene_active():
		return true
	return _current_terminal_path == TUTORIAL_LOCATION

func _reset_tutorial_terminal_progress() -> void:
	_tutorial_terminal_progress["pwd"] = false
	_tutorial_terminal_progress["ls"] = false
	_tutorial_terminal_progress["cat"] = false

func _track_tutorial_terminal_progress(command: String, args: Array) -> void:
	if not _is_tutorial_terminal_guided_mode():
		return
	match command:
		"pwd":
			_tutorial_terminal_progress["pwd"] = true
		"ls", "dir":
			_tutorial_terminal_progress["ls"] = true
		"cat":
			if not args.is_empty():
				_tutorial_terminal_progress["cat"] = true

func _print_tutorial_help_guidance() -> void:
	if not bool(_tutorial_terminal_progress.get("pwd", false)):
		_print_terminal_line("Try typing pwd")
		return
	if not bool(_tutorial_terminal_progress.get("ls", false)):
		_print_terminal_line("Great. Now try typing ls")
		return
	if not bool(_tutorial_terminal_progress.get("cat", false)):
		_print_terminal_line("Nice. Now try: cat onboarding_notes.txt")
		return
	_print_terminal_line("Great job. Tutorial commands: pwd, ls, cat <file-name>")

func _is_tutorial_terminal_progress_empty() -> bool:
	if bool(_tutorial_terminal_progress.get("pwd", false)):
		return false
	if bool(_tutorial_terminal_progress.get("ls", false)):
		return false
	if bool(_tutorial_terminal_progress.get("cat", false)):
		return false
	return true

func _invoke_scene_manager_method(method_name: String) -> bool:
	if SceneManager and SceneManager.has_method(method_name):
		return SceneManager.call(method_name) == true
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

func _push_terminal_history(command_text: String) -> void:
	var normalized := command_text.strip_edges()
	if normalized == "":
		return
	if not _terminal_history.is_empty() and _terminal_history[_terminal_history.size() - 1] == normalized:
		return
	_terminal_history.append(normalized)

func _navigate_terminal_history_previous() -> void:
	if terminal_input == null or _terminal_history.is_empty():
		return
	
	# CLI_HISTORY skill must be unlocked to use history navigation
	if not _is_cli_history_unlocked():
		return

	if _terminal_history_index == -1:
		_terminal_history_draft = terminal_input.text
		_terminal_history_index = _terminal_history.size() - 1
	elif _terminal_history_index > 0:
		_terminal_history_index -= 1

	terminal_input.text = _terminal_history[_terminal_history_index]
	terminal_input.caret_column = terminal_input.text.length()

func _navigate_terminal_history_next() -> void:
	if terminal_input == null or _terminal_history.is_empty():
		return

	if not _is_cli_history_unlocked():
		return

	if _terminal_history_index == -1:
		return

	_terminal_history_index += 1
	if _terminal_history_index >= _terminal_history.size():
		_terminal_history_index = -1
		terminal_input.text = _terminal_history_draft
		terminal_input.caret_column = terminal_input.text.length()
		return

	terminal_input.text = _terminal_history[_terminal_history_index]
	terminal_input.caret_column = terminal_input.text.length()

func _handle_history_command() -> void:
	if not _is_cli_history_unlocked():
		_print_terminal_line("history: command not available (unlock with wget learnix://skills/cli_history.unlock)")
		return
	if _terminal_history.is_empty():
		_print_terminal_line("No command history yet.")
		return
	var start_index := maxi(0, _terminal_history.size() - 20)
	for idx in range(start_index, _terminal_history.size()):
		_print_terminal_line("%02d  %s" % [idx + 1, _terminal_history[idx]])

func _handle_wget_command(args: Array) -> void:
	if not _terminal_is_open or terminal_panel == null or not terminal_panel.visible:
		_print_terminal_line("wget: skill unlock is only available in the MainHUD terminal")
		return

	if args.is_empty():
		_print_terminal_line("Usage: wget <url>")
		return
	
	var url := String(args[0]).strip_edges()
	if not url.begins_with("learnix://skills/"):
		_print_terminal_line("wget: unsupported URL scheme or path")
		return
	
	# Parse learnix://skills/<skill_name>.unlock
	var path := url.trim_prefix("learnix://skills/")
	if not path.ends_with(".unlock"):
		_print_terminal_line("wget: invalid skill unlock URL")
		return
	
	var skill_name := path.trim_suffix(".unlock")
	if skill_name.is_empty():
		_print_terminal_line("wget: no skill specified")
		return
	
	_unlock_skill(skill_name)

func _unlock_skill(skill_name: String) -> void:
	if SceneManager == null:
		_print_terminal_line("Error: Cannot unlock skill (SceneManager unavailable)")
		return
	if not SKILL_UNLOCK_FLAGS.has(skill_name):
		_print_terminal_line("Unlock failed: unknown skill '%s'." % skill_name)
		return

	if not _can_unlock_skill(skill_name):
		var unlock_cost := _get_skill_unlock_cost(skill_name)
		if unlock_cost > 0:
			var current_bits := int(SceneManager.get("data_bits"))
			if current_bits < unlock_cost:
				_print_terminal_line("Unlock failed: '%s' requires %d Data Bits (you have %d)." % [skill_name, unlock_cost, current_bits])
				return
		_print_terminal_line("Unlock failed: requirements not met for '%s'." % skill_name)
		return
	
	var flag_name := String(SKILL_UNLOCK_FLAGS.get(skill_name, ""))
	if flag_name == "":
		_print_terminal_line("Unlock failed: invalid unlock mapping for '%s'." % skill_name)
		return
	if SceneManager.get(flag_name) == true:
		if _has_skill_unlock_receipt(skill_name):
			_print_terminal_line("Skill '%s' is already unlocked." % skill_name)
			return
		# Legacy flag-only state can appear from older saves. Require normal purchase flow.
		SceneManager.set(flag_name, false)
		_print_terminal_line("Legacy unlock state detected for '%s'. Purchase required to activate." % skill_name)

	var skill_cost := _get_skill_unlock_cost(skill_name)
	if skill_cost > 0:
		if not SceneManager.spend_data_bits(skill_cost, "skill_unlock_%s" % skill_name):
			_print_terminal_line("Unlock failed: couldn't spend %d Data Bits for '%s'." % [skill_cost, skill_name])
			return
		_print_terminal_line("Spent %d Data Bits to unlock '%s'." % [skill_cost, skill_name])
	SceneManager.set(flag_name, true)
	_mark_skill_unlock_receipt(skill_name)
	if skill_name == "file_explorer":
		_update_visibility()
	
	_print_terminal_line("Skill '%s' unlocked successfully!" % skill_name)

func _get_skill_unlock_cost(skill_name: String) -> int:
	return int(SKILL_UNLOCK_COSTS.get(skill_name, 0))

func _can_unlock_skill(skill_name: String) -> bool:
	if SceneManager == null:
		return false
	match skill_name:
		"cli_history":
			return true
		"file_explorer":
			return SceneManager.get("helped_lost_file") == true
		"teleport":
			var interacted_npcs : Variant = SceneManager.get("interacted_npcs")
			var cmo_interacted: bool = false
			if interacted_npcs is Dictionary:
				var npc_map: Dictionary = interacted_npcs as Dictionary
				var cmo_flag: Variant = npc_map.get("CMO", false)
				cmo_interacted = cmo_flag == true
			var printer_progress: bool = SceneManager.get("printer_beast_defeated") == true or SceneManager.get("proficiency_key_printer") == true
			return printer_progress and cmo_interacted
		"taskkill", "sudo_privilege", "potion_patch", "potion_overclock", "potion_hardening":
			return int(SceneManager.get("data_bits")) >= _get_skill_unlock_cost(skill_name)
		_:
			return SKILL_UNLOCK_FLAGS.has(skill_name)

func _open_shop_from_terminal() -> void:
	if _shop_panel == null or not is_instance_valid(_shop_panel):
		var ShopScene := preload("res://Scenes/ui/TerminalShop.tscn")
		_shop_panel = ShopScene.instantiate() as Control
		get_tree().get_root().add_child(_shop_panel)

	_close_terminal()
	if _shop_panel and _shop_panel.has_method("open_shop"):
		_shop_panel.call("open_shop")
	elif _shop_panel:
		_shop_panel.visible = true

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

func _is_terminal_modal_active() -> bool:
	if _shutdown_confirm_dialog and is_instance_valid(_shutdown_confirm_dialog) and _shutdown_confirm_dialog.visible:
		return true
	if _shop_panel and is_instance_valid(_shop_panel) and _shop_panel.visible:
		return true
	return false

func _restore_terminal_focus_if_needed() -> void:
	if not _terminal_is_open:
		return
	if terminal_panel == null or not terminal_panel.visible:
		return
	if terminal_input == null:
		return
	if not terminal_input.editable or not terminal_input.visible:
		return
	if _is_terminal_modal_active():
		return
	if terminal_input.has_focus():
		return
	_claim_terminal_input_focus()

func _claim_terminal_input_focus() -> void:
	if terminal_input == null:
		return
	if not terminal_input.visible or not terminal_input.editable:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner and focus_owner != terminal_input:
		focus_owner.release_focus()
	terminal_input.grab_focus()
	terminal_input.call_deferred("grab_focus")

func _route_key_to_terminal_input(key_event: InputEventKey) -> bool:
	if terminal_input == null:
		return false
	if not _terminal_is_open or not terminal_input.visible or not terminal_input.editable:
		return false
	if key_event.ctrl_pressed or key_event.alt_pressed or key_event.meta_pressed:
		return false

	match key_event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_process_terminal_command(terminal_input.text)
			return true
		KEY_BACKSPACE:
			if terminal_input.caret_column > 0:
				var idx := terminal_input.caret_column - 1
				terminal_input.text = terminal_input.text.substr(0, idx) + terminal_input.text.substr(terminal_input.caret_column)
				terminal_input.caret_column = idx
			return true
		KEY_DELETE:
			if terminal_input.caret_column < terminal_input.text.length():
				terminal_input.text = terminal_input.text.substr(0, terminal_input.caret_column) + terminal_input.text.substr(terminal_input.caret_column + 1)
			return true
		KEY_LEFT:
			terminal_input.caret_column = maxi(0, terminal_input.caret_column - 1)
			return true
		KEY_RIGHT:
			terminal_input.caret_column = mini(terminal_input.text.length(), terminal_input.caret_column + 1)
			return true
		KEY_HOME:
			terminal_input.caret_column = 0
			return true
		KEY_END:
			terminal_input.caret_column = terminal_input.text.length()
			return true
		KEY_TAB:
			# Prevent focus traversal from stealing terminal typing.
			return true

	if key_event.unicode <= 0:
		return false
	var typed := char(key_event.unicode)
	if typed == "":
		return false
	if typed == "\n" or typed == "\r" or typed == "\t":
		return false

	var insert_at := terminal_input.caret_column
	terminal_input.text = terminal_input.text.substr(0, insert_at) + typed + terminal_input.text.substr(insert_at)
	terminal_input.caret_column = insert_at + 1
	return true
