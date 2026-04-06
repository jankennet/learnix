# combat_terminal_ui.gd
# Bridge script for combat UI - delegates to CombatUIController
# Provides setup_combat(), open_combat_ui(), close_combat_ui() methods
# for encounter_controller.gd compatibility
extends Control
class_name CombatTerminalUI

signal tutorial_popup_closed

#region Node References

@onready var terminal_output: RichTextLabel = $TerminalContainer/TerminalOutput
@onready var command_input: LineEdit = $TerminalContainer/InputContainer/CommandInput
@onready var terminal_container: VBoxContainer = $TerminalContainer
@onready var input_container: HBoxContainer = $TerminalContainer/InputContainer
@onready var prompt_label: Label = $TerminalContainer/InputContainer/PromptLabel
@onready var submit_button: Button = $TerminalContainer/InputContainer/SubmitButton
@onready var exit_button: Button = $TerminalContainer/InputContainer/ExitButton
@onready var status_panel: Panel = $StatusPanel
@onready var status_vbox: VBoxContainer = $StatusPanel/VBox
@onready var status_title_label: Label = $StatusPanel/VBox/StatusTitle
@onready var player_title_label: Label = $StatusPanel/VBox/PlayerTitle
@onready var enemy_title_label: Label = $StatusPanel/VBox/EnemyTitle
@onready var player_hp_bar: ProgressBar = $StatusPanel/VBox/PlayerStatus/HPBar
@onready var player_hp_label: Label = $StatusPanel/VBox/PlayerStatus/HPLabel
@onready var enemy_hp_bar: ProgressBar = $StatusPanel/VBox/EnemyStatus/HPBar
@onready var enemy_hp_label: Label = $StatusPanel/VBox/EnemyStatus/HPLabel
@onready var enemy_name_label: Label = $StatusPanel/VBox/EnemyStatus/NameLabel
@onready var turn_indicator: Label = $StatusPanel/VBox/TurnIndicator
@onready var npc_visual_panel: PanelContainer = $StatusPanel/VBox/NpcVisualPanel
@onready var npc_visual_host: Control = $StatusPanel/VBox/NpcVisualPanel/NpcVisualHost
@onready var npc_bad_texture: TextureRect = $StatusPanel/VBox/NpcVisualPanel/NpcVisualHost/NpcBadTexture
@onready var npc_good_texture: TextureRect = $StatusPanel/VBox/NpcVisualPanel/NpcVisualHost/NpcGoodTexture
@onready var npc_turn_flash: ColorRect = $StatusPanel/VBox/NpcVisualPanel/NpcVisualHost/NpcTurnFlash
@onready var objective_frame: PanelContainer = $StatusPanel/VBox/ObjectiveFrame
@onready var objective_broken_texture: TextureRect = $StatusPanel/VBox/ObjectiveFrame/ObjectiveBrokenTexture
@onready var objective_crack_sprite: Sprite2D = get_node_or_null("StatusPanel/VBox/ObjectiveFrame/Sprite2D") as Sprite2D
@onready var objective_crack_hole: TextureRect = get_node_or_null("ObjectiveCrackHole") as TextureRect
@onready var objective_content: VBoxContainer = $StatusPanel/VBox/ObjectiveFrame/ObjectiveContent
@onready var mode_label: Label = $StatusPanel/VBox/ModeLabel
@onready var objective_title_label: Label = $StatusPanel/VBox/ObjectiveFrame/ObjectiveContent/ObjectiveTitle
@onready var tux_help_button: Button = $StatusPanel/VBox/ObjectiveFrame/ObjectiveContent/TuxHelpButton
@onready var help_label: Label = $StatusPanel/VBox/ObjectiveFrame/ObjectiveContent/HelpLabel
#endregion

#region Runtime State
var combat_manager: Node = null
var enemy_controller: Node = null
var is_open: bool = false
var timing_minigame: TimingMinigame = null
var dependency_minigame: DependencyResolverMinigame = null
var _puzzle_minigame_pending: bool = false
var _dependency_fail_count: int = 0

const DEPENDENCY_FAIL_DAMAGE := 10
const DEPENDENCY_FAIL_LIMIT := 3
const INTEGRITY_SEGMENTS := 10
const UI_BASE_RESOLUTION := Vector2(1280.0, 720.0)
const UI_MIN_SCALE := 1.0
const UI_MAX_SCALE := 1.7
const TUTORIAL_META_TERMINAL_INTRO := "combat_terminal_intro_seen_v2"
const TUTORIAL_META_TIMING_INTRO := "combat_timing_intro_seen_v2"
const TUTORIAL_META_DEPENDENCY_INTRO := "combat_dependency_intro_seen_v2"
const TUTORIAL_POPUP_SCENE_PATH := "res://Scenes/combat/combat_tutorial_popup.tscn"
const TUX_HELPER_POPUP_SCENE_PATH := "res://Scenes/combat/tux_terminal_helper_popup.tscn"
const SKILL_UNLOCK_RECEIPTS_META_KEY := "skill_unlock_receipts"
const NPC_REVEAL_SHADER_PATH := "res://shaders/ui/npc_reveal_wipe.gdshader"
const CRACKED_GLASS_SHADER_PATH := "res://Scenes/combat/cracked_glass.gdshader"
const CRACKED_GLASS_TEXTURE_PATH := "res://Assets/Glass-Cracks-PNG-HD.png"
const BROKEN_SCREEN_TEXTURE_PATH := "res://Assets/shaders/gliitch.jpg"
const NPC_VISUAL_TEXTURE_PATHS := {
	"lost_file": {
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_bad_lost_file.png",
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_good_lost_file.png"
	},
	"broken_link": {
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_bad_broken_link.png",
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_good_broken_link.png"
	},
	"driver_remnant": {
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_bad_driver_remnant.png",
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_good_driver_remnant.png"
	},
	"hardware_ghost": {
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_bad_hardware_ghost.png",
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_good_hardware_ghost.png"
	},
	"messy_directory": {
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_bad_messy_directory.png",
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_good_messy_directory.png"
	},
	"sage": {
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_Sage.png",
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_Sage.png"
	},
	"printer_beast": {
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_PrinterBoss.png",
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_PrinterBoss.png"
	},
	"evil_tux": {
		"bad": "res://Assets/characterSpriteSheets/ss_Tux/bossTux_idle.png",
		"good": "res://Assets/characterSpriteSheets/ss_Tux/bossTux_idle.png"
	},
	"default": {
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_bad_lost_file.png",
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_good_lost_file.png"
	}
}
#endregion

var _dependency_objective_active := false
var _tutorial_popup_ui: CombatTutorialPopup = null
var _tutorial_popup_visible := false
var _tux_helper_popup: TuxTerminalHelperPopup = null
var _tux_helper_visible := false
var _player_attacked_this_encounter := false
var _npc_visual_progress := 0.0
var _npc_visual_tween: Tween = null
var _npc_player_turn := false
var _npc_visual_material: ShaderMaterial = null
var _objective_crack_material: ShaderMaterial = null
var _objective_crack_hole_texture: Texture2D = null
var _npc_texture_cache: Dictionary = {}
var _command_history: Array[String] = []
var _history_index := -1
var _history_draft := ""

func _ready() -> void:
	if not get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.connect(_on_viewport_resized)
	call_deferred("_apply_responsive_ui")

	# Connect input signals
	if command_input:
		command_input.text_submitted.connect(_on_command_submitted)
	
	if submit_button:
		submit_button.pressed.connect(_on_submit_pressed)
	
	if exit_button:
		exit_button.pressed.connect(_on_exit_pressed)
	
	# Setup timing minigame
	_setup_timing_minigame()
	_setup_dependency_minigame()
	_setup_terminal_visuals()
	_ensure_tutorial_popup_ui()
	if help_label:
		help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if tux_help_button:
		if not tux_help_button.pressed.is_connected(_on_tux_help_button_pressed):
			tux_help_button.pressed.connect(_on_tux_help_button_pressed)
		if tux_help_button.icon == null:
			var tux_icon := load("res://Assets/mainHUD_Icons_Tux.png")
			if tux_icon:
				tux_help_button.icon = tux_icon
		if tux_help_button.text.is_empty():
			tux_help_button.text = "ASK TUX"

func _on_viewport_resized() -> void:
	_apply_responsive_ui()

func _get_ui_scale_factor() -> float:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 1.0
	var width_ratio := viewport_size.x / UI_BASE_RESOLUTION.x
	var height_ratio := viewport_size.y / UI_BASE_RESOLUTION.y
	return clamp(min(width_ratio, height_ratio), UI_MIN_SCALE, UI_MAX_SCALE)

func _apply_responsive_ui() -> void:
	var scale_factor := _get_ui_scale_factor()

	terminal_container.offset_left = 20.0 * scale_factor
	terminal_container.offset_top = 20.0 * scale_factor
	terminal_container.offset_right = -270.0 * scale_factor
	terminal_container.offset_bottom = -20.0 * scale_factor

	status_panel.offset_left = -250.0 * scale_factor
	status_panel.offset_top = 20.0 * scale_factor
	status_panel.offset_right = -20.0 * scale_factor
	status_panel.offset_bottom = -20.0 * scale_factor
	status_panel.custom_minimum_size = Vector2(220.0, 0.0) * scale_factor

	status_vbox.offset_left = 10.0 * scale_factor
	status_vbox.offset_top = 10.0 * scale_factor
	status_vbox.offset_right = -10.0 * scale_factor
	status_vbox.offset_bottom = -10.0 * scale_factor
	status_vbox.add_theme_constant_override("separation", roundi(4.0 * scale_factor))
	input_container.add_theme_constant_override("separation", roundi(8.0 * scale_factor))
	if npc_visual_panel:
		npc_visual_panel.custom_minimum_size = Vector2(0.0, 218.0 * scale_factor)
	if objective_frame:
		objective_frame.custom_minimum_size = Vector2(0.0, 112.0 * scale_factor)
	if objective_content:
		objective_content.add_theme_constant_override("separation", roundi(7.0 * scale_factor))
	_update_crack_sprite_transform(scale_factor)

	terminal_output.add_theme_font_size_override("normal_font_size", roundi(12.0 * scale_factor))
	prompt_label.add_theme_font_size_override("font_size", roundi(16.0 * scale_factor))
	command_input.add_theme_font_size_override("font_size", roundi(16.0 * scale_factor))
	command_input.custom_minimum_size = Vector2(0.0, 34.0 * scale_factor)
	submit_button.add_theme_font_size_override("font_size", roundi(12.0 * scale_factor))
	exit_button.add_theme_font_size_override("font_size", roundi(12.0 * scale_factor))

	status_title_label.add_theme_font_size_override("font_size", roundi(8.0 * scale_factor))
	mode_label.add_theme_font_size_override("font_size", roundi(8.0 * scale_factor))
	player_title_label.add_theme_font_size_override("font_size", roundi(8.0 * scale_factor))
	player_hp_label.add_theme_font_size_override("font_size", roundi(8.0 * scale_factor))
	enemy_title_label.add_theme_font_size_override("font_size", roundi(8.0 * scale_factor))
	enemy_name_label.add_theme_font_size_override("font_size", roundi(8.0 * scale_factor))
	enemy_hp_label.add_theme_font_size_override("font_size", roundi(8.0 * scale_factor))
	turn_indicator.add_theme_font_size_override("font_size", roundi(8.0 * scale_factor))
	if objective_title_label:
		objective_title_label.add_theme_font_size_override("font_size", roundi(12.0 * scale_factor))
	if tux_help_button:
		tux_help_button.add_theme_font_size_override("font_size", roundi(8.0 * scale_factor))
		tux_help_button.custom_minimum_size = Vector2(0.0, 28.0 * scale_factor)
	help_label.add_theme_font_size_override("font_size", roundi(10.0 * scale_factor))
	help_label.add_theme_constant_override("line_spacing", roundi(3.0 * scale_factor))
	help_label.custom_minimum_size = Vector2(0.0, 82.0 * scale_factor)
	player_hp_bar.custom_minimum_size = Vector2(0.0, 14.0 * scale_factor)
	enemy_hp_bar.custom_minimum_size = Vector2(0.0, 14.0 * scale_factor)

func _setup_timing_minigame() -> void:
	# Create timing minigame instance
	timing_minigame = TimingMinigame.new()
	timing_minigame.name = "TimingMinigame"
	add_child(timing_minigame)
	
	# Connect timing signals
	timing_minigame.timing_completed.connect(_on_timing_completed)
	timing_minigame.timing_cancelled.connect(_on_timing_cancelled)

func _setup_dependency_minigame() -> void:
	# Create dependency resolver minigame instance for puzzle mode
	dependency_minigame = DependencyResolverMinigame.new()
	dependency_minigame.name = "DependencyResolverMinigame"
	add_child(dependency_minigame)

	# Connect resolver signals
	dependency_minigame.resolver_completed.connect(_on_dependency_resolver_completed)
	dependency_minigame.resolver_closed.connect(_on_dependency_resolver_closed)

#region Public API

## Setup combat with manager and enemy references
func setup_combat(manager: Node, enemy: Node) -> void:
	combat_manager = manager
	enemy_controller = enemy
	
	# Connect to combat manager signals
	if combat_manager:
		if combat_manager.has_signal("message_logged"):
			if not combat_manager.is_connected("message_logged", _on_message_logged):
				combat_manager.connect("message_logged", _on_message_logged)
		
		if combat_manager.has_signal("awaiting_input"):
			if not combat_manager.is_connected("awaiting_input", _on_awaiting_input):
				combat_manager.connect("awaiting_input", _on_awaiting_input)
		
		if combat_manager.has_signal("turn_changed"):
			if not combat_manager.is_connected("turn_changed", _on_turn_changed):
				combat_manager.connect("turn_changed", _on_turn_changed)
		
		# Connect to combat_ended signal to close UI after victory/defeat
		if combat_manager.has_signal("combat_ended"):
			if not combat_manager.is_connected("combat_ended", _on_combat_ended):
				combat_manager.connect("combat_ended", _on_combat_ended)
		
		# Connect to timing minigame signal
		if combat_manager.has_signal("timing_minigame_requested"):
			if not combat_manager.is_connected("timing_minigame_requested", _on_timing_minigame_requested):
				combat_manager.connect("timing_minigame_requested", _on_timing_minigame_requested)
	
	# Set enemy name if available
	if enemy_controller and enemy_name_label:
		if "enemy_name" in enemy_controller:
			enemy_name_label.text = enemy_controller.enemy_name
		elif "display_name" in enemy_controller:
			enemy_name_label.text = enemy_controller.display_name
	
	# Update mode label
	if mode_label:
		mode_label.text = "[COMBAT MODE]"
	
	# Initial HP update
	_update_hp_displays()
	_update_side_help_for_mode()
	_refresh_terminal_visuals(true)

## Show the combat UI
func open_combat_ui() -> void:
	is_open = true
	_dependency_fail_count = 0
	_dependency_objective_active = false
	_player_attacked_this_encounter = _has_player_attacked_current_npc()
	show()
	_set_terminal_for_dependency_mode(false)
	
	# Close any active dialogue balloon FIRST (before locking input)
	# This prevents dialogue_balloon from unlocking input when it's freed
	_close_active_dialogue()
	
	# Wait a frame to ensure dialogue is fully closed
	await get_tree().process_frame
	
	# THEN lock player input - this ensures dialogue's unlock doesn't override us
	if SceneManager:
		SceneManager.input_locked = true
	else:
		push_error("[CombatUI] SceneManager autoload not found!")
	
	# Hide the static terminal header (saves space)
	var header = get_node_or_null("TerminalContainer/TerminalHeader")
	if header:
		header.visible = false
	
	# Get enemy name for display
	var enemy_name := "unknown_process"
	if enemy_controller:
		if "enemy_name" in enemy_controller:
			enemy_name = enemy_controller.enemy_name
		elif "display_name" in enemy_controller:
			enemy_name = enemy_controller.display_name
	
	# Clear terminal and show man-page style intro
	if terminal_output:
		terminal_output.clear()
		_print_terminal("[color=#66f266]ENCOUNTER(1)                      LEARNIX                      ENCOUNTER(1)[/color]\n\n")
		_print_terminal("[color=#66f266]NAME[/color]\n")
		_print_terminal("       %s - A corrupted entity seeking resolution\n\n" % enemy_name)
		_print_terminal("[color=#66f266]SYNOPSIS[/color]\n")
		_print_terminal("       continue      - Listen to what they have to say\n")
		_print_terminal("       fight         - Initiate combat\n")
		_print_terminal("       help [topic]  - Show available commands\n\n")
		_print_terminal("[color=#66f266]DESCRIPTION[/color]\n")
		_print_terminal("       You have encountered a %s. They appear distressed.\n" % enemy_name)
		_print_terminal("       You can choose to fight or try to help them.\n\n")
		_print_terminal("[color=#f2e066]Type a command to proceed...[/color]\n")
	
	# Focus input (deferred so UI is fully shown first)
	if command_input:
		command_input.call_deferred("grab_focus")
	
	# Update turn indicator
	if turn_indicator:
		turn_indicator.text = "[ AWAITING INPUT ]"
	_update_side_help_for_mode()
	_refresh_terminal_visuals(true)
	await _show_terminal_intro_tutorial_if_needed()
	if command_input:
		command_input.editable = true
		command_input.grab_focus()
	_update_tux_helper_popup()

## Hide the combat UI
func close_combat_ui() -> void:
	is_open = false
	_dependency_fail_count = 0
	_dependency_objective_active = false
	_player_attacked_this_encounter = false
	hide()
	_set_terminal_for_dependency_mode(false)
	_hide_tutorial_popup()
	_hide_tux_helper_popup()
	_show_queued_reward_popup()
	
	# Cancel any active timing minigame
	if timing_minigame and timing_minigame.is_active:
		timing_minigame.cancel_timing()

	# Ensure dependency resolver is closed if active
	if dependency_minigame and dependency_minigame.visible:
		dependency_minigame.close_minigame()

	_puzzle_minigame_pending = false
	
	# Unlock player input
	if SceneManager:
		SceneManager.input_locked = false
		SceneManager.play_music_for_current_scene()
	
	# Disconnect signals
	if combat_manager:
		if combat_manager.has_signal("message_logged") and combat_manager.is_connected("message_logged", _on_message_logged):
			combat_manager.disconnect("message_logged", _on_message_logged)
		if combat_manager.has_signal("awaiting_input") and combat_manager.is_connected("awaiting_input", _on_awaiting_input):
			combat_manager.disconnect("awaiting_input", _on_awaiting_input)
		if combat_manager.has_signal("turn_changed") and combat_manager.is_connected("turn_changed", _on_turn_changed):
			combat_manager.disconnect("turn_changed", _on_turn_changed)
		if combat_manager.has_signal("combat_ended") and combat_manager.is_connected("combat_ended", _on_combat_ended):
			combat_manager.disconnect("combat_ended", _on_combat_ended)
		if combat_manager.has_signal("timing_minigame_requested") and combat_manager.is_connected("timing_minigame_requested", _on_timing_minigame_requested):
			combat_manager.disconnect("timing_minigame_requested", _on_timing_minigame_requested)
	
	combat_manager = null
	enemy_controller = null
	_refresh_terminal_visuals(true)

func _show_queued_reward_popup() -> void:
	if not SceneManager:
		return
	if not SceneManager.has_meta("pending_reward_popup_key"):
		return

	var key_name = str(SceneManager.get_meta("pending_reward_popup_key"))
	SceneManager.remove_meta("pending_reward_popup_key")
	if key_name.strip_edges() == "":
		return

	var popup_script := load("res://scripts/ui/digital_reward_popup.gd")
	if popup_script == null:
		return
	var popup = popup_script.new()
	if popup == null:
		return
	get_tree().root.add_child(popup)
	if popup.has_method("show_key_reward"):
		popup.call("show_key_reward", key_name)

#endregion

#region Signal Handlers

# Use _unhandled_input instead of _input so GUI controls (LineEdit) process events first
func _input(event: InputEvent) -> void:
	if not is_open or not command_input or not command_input.has_focus():
		return
	
	# Intercept UP/DOWN keys for history navigation before LineEdit processes them
	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_UP or key_event.keycode == KEY_DOWN:
			# Never allow command history navigation unless cli_history was unlocked via wget.
			if not _is_cli_history_unlocked():
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_UP:
				_navigate_command_history_previous()
			else:
				_navigate_command_history_next()
			get_viewport().set_input_as_handled()
			return

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	
	# Consume any unhandled keyboard/mouse events while the combat terminal is open
	# This prevents player movement and interaction
	# The LineEdit already handled text input via GUI processing before this runs
	if event is InputEventKey or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
		
		# If a key was pressed but LineEdit doesn't have focus, grab it
		if command_input and event is InputEventKey and event.pressed:
			if not command_input.has_focus():
				command_input.grab_focus()

func _on_command_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return

	_track_player_attack_intent(text)
	_push_command_history(text)
	
	# Echo command to terminal
	_print_terminal("[color=#80f280]$ %s[/color]\n" % text)
	
	# Clear input and re-focus
	if command_input:
		command_input.clear()
		command_input.grab_focus()
	
	_history_index = -1
	_history_draft = ""
	
	# Handle help command locally before routing to enemy
	if text.strip_edges().to_lower() == "help" or text.strip_edges().to_lower() == "?":
		_show_contextual_help()
		return
	
	# Handle quit/exit commands - becomes escape attempt if in combat
	var lower_text = text.strip_edges().to_lower()
	if lower_text == "quit" or lower_text == "exit" or lower_text == "q" or lower_text == "close" or lower_text == "escape" or lower_text == "flee" or lower_text == "run":
		_attempt_escape()
		return
	
	# Route to enemy controller FIRST - it handles mode transitions
	# Enemy controller will delegate to combat manager when in combat mode
	if enemy_controller and enemy_controller.has_method("process_input"):
		var result = enemy_controller.process_input(text)
		if result is Dictionary:
			# Display message from enemy controller
			if result.get("message", "") != "":
				var message_text := str(result.message)
				var should_simplify := bool(result.get("requires_timing", false))
				should_simplify = should_simplify or message_text.find("TIMING REQUIRED") != -1
				if enemy_controller and "current_mode" in enemy_controller:
					should_simplify = should_simplify or int(enemy_controller.current_mode) == 2
				if should_simplify:
					message_text = _simplify_puzzle_message(message_text)
				_print_terminal("[color=#66f266]%s[/color]\n" % message_text)
			
			# Check if timing minigame is required (for puzzles)
			if result.get("requires_timing", false):
				var timing_difficulty := float(result.get("timing_difficulty", 1.0))
				var pending_command = result.get("pending_command", null)
				var is_compile_step := false
				if pending_command and "command_type" in pending_command:
					is_compile_step = int(pending_command.command_type) == CommandParser.CommandType.COMPILE

				# Node-connect is reserved for the final compile stage.
				if is_compile_step:
					await _start_puzzle_minigame(timing_difficulty)
				else:
					await _start_puzzle_timing_minigame(timing_difficulty)
				return
			
			# Update mode label if mode changed
			if result.get("mode_changed", false):
				_update_mode_display()
			# Check if encounter ended
			if result.get("encounter_ended", false):
				# Close UI after delay
				await get_tree().create_timer(2.0).timeout
				_force_close_and_cleanup()
		_update_hp_displays()
		_update_side_help_for_mode()
	elif combat_manager and combat_manager.has_method("process_input"):
		# Fallback: direct combat manager input
		combat_manager.process_input(text)

func _on_submit_pressed() -> void:
	if command_input:
		_on_command_submitted(command_input.text)

func _on_combat_ended(victory: bool, _enemy_data) -> void:
	# Combat has ended (victory or defeat) - close UI after displaying result
	if victory:
		_print_terminal("\n[color=#66f266]═══ VICTORY ═══[/color]\n")
		_print_terminal("[color=#66f266]The enemy has been defeated.[/color]\n")
	else:
		_print_terminal("\n[color=#f26666]═══ DEFEAT ═══[/color]\n")
		_print_terminal("[color=#f26666]System integrity compromised.[/color]\n")
	
	_print_terminal("\n[color=#f2e066]Terminal closing in 3 seconds...[/color]\n")
	_print_terminal("[color=#aaaaaa](Type 'quit' or press the Exit button to close immediately)[/color]\n")
	
	# Close after delay
	await get_tree().create_timer(3.0).timeout
	if is_open:  # Only close if still open (user might have quit early)
		_force_close_and_cleanup()

func _on_exit_pressed() -> void:
	_attempt_escape()

## Attempt to escape/exit the encounter
## In dialogue mode: always succeeds
## In combat mode: chance-based, counts as a turn (enemy may attack)
## In puzzle mode: always succeeds
func _attempt_escape() -> void:
	var current_mode := 0  # 0=dialogue, 1=combat, 2=puzzle
	if enemy_controller and "current_mode" in enemy_controller:
		current_mode = enemy_controller.current_mode

	if _is_boss_encounter_locked_exit():
		_print_terminal("[color=#f26666]Boss battle happening, can't do that.[/color]\n")
		if current_mode == 1:
			_consume_turn_for_blocked_boss_exit()
		return
	
	# In combat mode, escape is chance-based and counts as a turn
	if current_mode == 1:  # COMBAT
		_print_terminal("[color=#f2e066]Attempting to escape...[/color]\n")
		await get_tree().create_timer(0.5).timeout
		
		# 60% base escape chance
		var escape_chance := 0.6
		var roll := randf()
		
		if roll < escape_chance:
			# Escape successful
			_print_terminal("[color=#66f266]Escape successful! You got away.[/color]\n")
			_print_terminal("[color=#aaaaaa](The enemy will be hostile when you return)[/color]\n")
			
			# Mark that player fled (enemy stays hostile, combat resumes on next interaction)
			if enemy_controller and "enemy_name" in enemy_controller:
				var npc_name = enemy_controller.enemy_name
				SceneManager.npc_states[npc_name] = "fled_combat"
				# Also store that player has attacked (for resuming combat)
				if "has_attacked" in enemy_controller and enemy_controller.has_attacked:
					SceneManager.set_meta(_combat_state_meta_key(npc_name), {"has_attacked": true})
			
			await get_tree().create_timer(1.0).timeout
			_force_close_and_cleanup()
		else:
			# Escape failed - enemy gets a free attack
			_print_terminal("[color=#f26666]Escape failed![/color]\n")
			_print_terminal("[color=#f2e066]The enemy attacks while you're distracted![/color]\n")
			
			# Enemy takes their turn
			if combat_manager and combat_manager.has_method("_start_enemy_turn"):
				await get_tree().create_timer(0.5).timeout
				combat_manager._start_enemy_turn()
				# Wait for enemy turn to complete
				await get_tree().create_timer(1.0).timeout
				_update_hp_displays()
			
			# Check if player died from the attack
			if combat_manager and "player_state" in combat_manager:
				if combat_manager.player_state.current_integrity <= 0:
					_print_terminal("[color=#f26666]System integrity compromised during escape attempt![/color]\n")
					await get_tree().create_timer(1.5).timeout
					_force_close_and_cleanup()
	else:
		# Dialogue or Puzzle mode - can always exit freely
		_print_terminal("[color=#f2e066]Exiting terminal...[/color]\n")
		await get_tree().create_timer(0.5).timeout
		_force_close_and_cleanup()

func _is_boss_encounter_locked_exit() -> bool:
	if enemy_controller == null:
		return false

	if "enemy_data" in enemy_controller and enemy_controller.enemy_data:
		if "id" in enemy_controller.enemy_data:
			var enemy_id := str(enemy_controller.enemy_data.id).strip_edges().to_lower()
			if enemy_id == "printer_beast" or enemy_id == "evil_tux":
				return true

	if "encounter_id" in enemy_controller:
		var encounter_id := str(enemy_controller.encounter_id).strip_edges().to_lower()
		if encounter_id == "printer_beast" or encounter_id == "evil_tux":
			return true

	if "puzzle_data" in enemy_controller and enemy_controller.puzzle_data and "custom_data" in enemy_controller.puzzle_data:
		var custom_data: Variant = enemy_controller.puzzle_data.custom_data
		if custom_data is Dictionary and bool((custom_data as Dictionary).get("boss_mode", false)):
			return true

	return false

func _consume_turn_for_blocked_boss_exit() -> void:
	if combat_manager == null:
		return
	if not ("combat_state" in combat_manager):
		return
	if int(combat_manager.combat_state) != int(TurnCombatManager.CombatState.PLAYER_INPUT):
		return

	if command_input:
		command_input.editable = false
	await get_tree().create_timer(0.25).timeout
	if combat_manager and combat_manager.has_method("_start_enemy_turn"):
		combat_manager._start_enemy_turn()

## Force close and clean up the encounter controller
func _force_close_and_cleanup() -> void:
	close_combat_ui()
	
	# Find and clean up the encounter controller to restore NPC interaction
	var ec = get_parent()
	while ec and not (ec is EncounterController):
		ec = ec.get_parent()
	
	if ec and ec is EncounterController:
		ec.queue_free()

func _on_message_logged(message: String, type = 0) -> void:
	var color := _get_color_for_type(type)
	_print_terminal("[color=%s]%s[/color]\n" % [color, message])
	_update_hp_displays()

func _on_awaiting_input() -> void:
	if turn_indicator:
		turn_indicator.text = "[ AWAITING INPUT ]"
	if command_input:
		command_input.editable = true
		command_input.grab_focus()

func _on_turn_changed(turn_owner) -> void:
	if not turn_indicator:
		return
	
	# Check turn owner (0 = player, 1 = enemy typically)
	if turn_owner == 0:
		turn_indicator.text = "[ YOUR TURN ]"
		_npc_player_turn = true
	else:
		turn_indicator.text = "[ ENEMY TURN ]"
		_npc_player_turn = false
	_refresh_terminal_visuals()

#endregion

#region Helper Functions

func _print_terminal(bbcode_text: String) -> void:
	if terminal_output:
		terminal_output.append_text(bbcode_text)

func _show_contextual_help() -> void:
	# Get current mode from enemy controller
	var current_mode := 0  # Default to dialogue
	if enemy_controller and "current_mode" in enemy_controller:
		current_mode = enemy_controller.current_mode
	
	_print_terminal("\n")
	
	match current_mode:
		0:  # DIALOGUE
			_print_terminal("[color=#66f266]HELP - DIALOGUE MODE[/color]\n\n")
			_print_terminal("  continue   - Proceed with dialogue\n")
			_print_terminal("  attack     - Start fighting\n")
			_print_terminal("  puzzle     - Try to help them instead\n")
			_print_terminal("\n[color=#f2e066]Tip: Type 'help combat' or 'help puzzle' for more.[/color]\n")
		
		1:  # COMBAT
			_print_terminal("[color=#66f266]HELP - COMBAT MODE[/color]\n\n")
			_print_terminal("  attack, hit   - Strike the enemy\n")
			_print_terminal("  defend, block - Reduce incoming damage\n")
			_print_terminal("  heal, repair  - Restore your integrity\n")
			_print_terminal("  kill <target> - Taskkill finisher (skill required)\n")
			_print_terminal("  restore       - Enemy-specific interaction\n")
			_print_terminal("  escape, flee  - Attempt to flee\n")
		
		2:  # PUZZLE
			var enemy_label := ""
			if enemy_controller and "enemy_name" in enemy_controller:
				enemy_label = str(enemy_controller.enemy_name).to_lower()
			elif enemy_controller and "enemy_data" in enemy_controller and enemy_controller.enemy_data and "id" in enemy_controller.enemy_data:
				enemy_label = str(enemy_controller.enemy_data.id).to_lower()
			if enemy_label.find("broken") != -1 and enemy_label.find("link") != -1:
				_print_terminal("[color=#66f266]HELP - PUZZLE MODE (Broken Link Repair)[/color]\n\n")
				_print_terminal("  ls -l stub - Inspect the broken symlink\n")
				_print_terminal("  find       - Locate the missing target path\n")
				_print_terminal("  unlink     - Remove the broken stub\n")
				_print_terminal("  ln -s      - Reattach stub to /forest/target\n")
				_print_terminal("  chmod      - Fix permissions on link_table\n")
				_print_terminal("  cat        - Rebuild or verify link_table\n")
				_print_terminal("  make       - Finalize link_map\n")
				_print_terminal("  fight      - Return to combat\n")
			elif enemy_label.find("ghost") != -1:
				_print_terminal("[color=#66f266]HELP - PUZZLE MODE (Hardware Ghost Logs)[/color]\n\n")
				_print_terminal("  cat        - Read legacy bus and ghost logs\n")
				_print_terminal("  find       - Locate the legacy driver table\n")
				_print_terminal("  chmod      - Calm/fix driver table permissions\n")
				_print_terminal("  make       - Finalize the driver map\n")
				_print_terminal("  fight      - Return to combat\n")
			elif enemy_label.find("remnant") != -1:
				_print_terminal("[color=#66f266]HELP - PUZZLE MODE (Driver Remnant Isolation)[/color]\n\n")
				_print_terminal("  cat        - Capture the rogue signature\n")
				_print_terminal("  find       - Trace the interrupt line\n")
				_print_terminal("  kill       - Terminate the remnant\n")
				_print_terminal("  unlink     - Isolate the irq line\n")
				_print_terminal("  chmod      - Stabilize interrupt table permissions\n")
				_print_terminal("  make       - Rebuild the stability map\n")
				_print_terminal("  fight      - Return to combat\n")
			elif enemy_label.find("printer") != -1:
				_print_terminal("[color=#66f266]HELP - PUZZLE MODE (Printer Beast Reset)[/color]\n\n")
				_print_terminal("  ls         - Read spool queue status\n")
				_print_terminal("  find       - Locate the jam in /var/spool/print\n")
				_print_terminal("  rm         - Remove jammed pages\n")
				_print_terminal("  chmod      - Fix spool permissions\n")
				_print_terminal("  cat        - Rebuild spool index\n")
				_print_terminal("  make       - Rebuild the print queue\n")
				_print_terminal("  fight      - Return to combat\n")
			else:
				_print_terminal("[color=#66f266]HELP - PUZZLE MODE (Lost File Recovery)[/color]\n\n")
				_print_terminal("  find       - Search for file fragments\n")
				_print_terminal("  restore    - Recover a found fragment\n")
				_print_terminal("  decrypt    - Decode encrypted data\n")
				_print_terminal("  cat        - Read fragment contents\n")
				_print_terminal("  compile    - Reassemble all fragments\n")
				_print_terminal("  fight      - Return to combat\n")
		
		_:  # RESOLVED or unknown
			_print_terminal("[color=#66f266]Encounter resolved.[/color]\n")
	
	_print_terminal("\n")

func _on_tux_help_button_pressed() -> void:
	_toggle_tux_helper_popup()

func _toggle_tux_helper_popup() -> void:
	if _tux_helper_visible:
		_hide_tux_helper_popup()
		return
	_show_tux_helper_popup()

func _show_tux_helper_popup() -> void:
	_ensure_tux_helper_popup()
	if _tux_helper_popup == null:
		return

	_tux_helper_visible = true
	_tux_helper_popup.show_helper(_build_tux_helper_context())
	if not _tux_helper_popup.hint_selected.is_connected(_on_tux_helper_hint_selected):
		_tux_helper_popup.hint_selected.connect(_on_tux_helper_hint_selected)
	if not _tux_helper_popup.closed.is_connected(_on_tux_helper_closed):
		_tux_helper_popup.closed.connect(_on_tux_helper_closed)

func _hide_tux_helper_popup() -> void:
	_tux_helper_visible = false
	if _tux_helper_popup != null and is_instance_valid(_tux_helper_popup):
		_tux_helper_popup.hide_helper()

func _on_tux_helper_closed() -> void:
	_tux_helper_visible = false

func _on_tux_helper_hint_selected(message: String) -> void:
	if message.strip_edges().is_empty():
		return
	_print_terminal("[color=#f2e066]Tux:[/color] %s\n" % message)
	if command_input:
		command_input.grab_focus()

func _ensure_tux_helper_popup() -> void:
	if _tux_helper_popup != null and is_instance_valid(_tux_helper_popup):
		return

	var popup_scene := load(TUX_HELPER_POPUP_SCENE_PATH) as PackedScene
	if popup_scene == null:
		push_warning("Tux helper popup scene not found: " + TUX_HELPER_POPUP_SCENE_PATH)
		return

	var popup_instance := popup_scene.instantiate()
	if not (popup_instance is TuxTerminalHelperPopup):
		push_warning("Tux helper popup scene root must be TuxTerminalHelperPopup.")
		if popup_instance:
			popup_instance.queue_free()
		return

	_tux_helper_popup = popup_instance as TuxTerminalHelperPopup
	_tux_helper_popup.name = "TuxTerminalHelperPopup"
	_tux_helper_popup.z_index = 250
	add_child(_tux_helper_popup)

func _update_tux_helper_popup() -> void:
	if _tux_helper_popup == null or not is_instance_valid(_tux_helper_popup):
		return
	if _tux_helper_visible:
		_tux_helper_popup.show_helper(_build_tux_helper_context())

func _build_tux_helper_context() -> Dictionary:
	var npc_name := _get_current_npc_name()
	var current_mode := _get_current_mode()
	var player_attacked_npc := _has_player_attacked_current_npc()
	var title := "TUX HELPER"
	var summary := ""
	var suggestions: Array[Dictionary] = []

	match current_mode:
		0:
			title = "%s // Dialogue Briefing" % npc_name
			summary = _build_dialogue_summary(npc_name)
			suggestions = [
				{"label": "What did they say?", "detail": "Turn the dialogue into a short reminder.", "message": _build_dialogue_hint_message(npc_name, "read the dialogue for the NPC's request")},
				{"label": "What does the NPC want?", "detail": "Focus on the verb or request in the conversation.", "message": _build_dialogue_hint_message(npc_name, "look for the verb or request in the dialogue")},
				{"label": "What should I do next?", "detail": "Ask Tux for the safest next step.", "message": _build_dialogue_hint_message(npc_name, "continue talking before you jump to combat")},
				{"label": "Show the route", "detail": "Summarize the likely choice.", "message": _build_dialogue_hint_message(npc_name, "choose help, puzzle, or fight based on the NPC's tone")},
			]
		1:
			title = "%s // Combat Notes" % npc_name
			if player_attacked_npc:
				summary = "TUX: You attacked first. Before your next command, answer one of these checks."
				suggestions = [
					{"label": "Why did you attack?", "detail": "TUX asks for intent.", "message": "TUX: Why did you attack this NPC instead of trying help or puzzle mode first?"},
					{"label": "Was there another way?", "detail": "TUX asks for alternatives.", "message": "TUX: Could you resolve this through dialogue or puzzle steps with less damage?"},
					{"label": "What harm are you causing?", "detail": "TUX asks about consequences.", "message": "TUX: Every attack escalates this encounter. Is this the outcome you want?"},
					{"label": "Do you want to disengage?", "detail": "TUX suggests de-escalation.", "message": "TUX: If you need a reset, defend now or escape before integrity drops."},
				]
			else:
				summary = "TUX: Stay focused. Pick your next command based on integrity, turn order, and risk."
				suggestions = [
					{"label": "Which commands now?", "detail": "TUX lists combat options.", "message": "TUX: Use attack or defend to manage pressure, heal to recover, or escape to reset."},
					{"label": "How do you survive?", "detail": "TUX gives a survival sequence.", "message": "TUX: Defend when pressured, heal before you drop too low, then attack when stable."},
					{"label": "When should you escape?", "detail": "TUX gives reset timing.", "message": "TUX: Escape when your integrity trend is negative or your next turn is unsafe."},
					{"label": "How do you read target?", "detail": "TUX explains the panel.", "message": "TUX: Watch target integrity, turn indicator, and mode changes before committing."},
				]
		2:
			title = "%s // Puzzle Notes" % npc_name
			summary = _build_puzzle_summary()
			suggestions = _build_puzzle_suggestions(npc_name)
		_:
			title = "TUX HELPER"
			summary = "This encounter is resolved. Use the helper in future encounters when the dialogue is easy to miss."
			suggestions = [
				{"label": "Why is this useful?", "detail": "Tux explains the helper's purpose.", "message": "The helper is here to convert dialogue into a concrete next step."},
			]

	return {
		"title": title,
		"summary": summary,
		"suggestions": suggestions,
		"show_sprite": current_mode != 1,
		"footer": "Tip: many NPCs tell you the solution in dialogue before the terminal asks for it.",
	}

func _track_player_attack_intent(raw_input: String) -> void:
	var normalized := raw_input.strip_edges().to_lower()
	if normalized == "attack" or normalized == "hit" or normalized == "fight":
		_player_attacked_this_encounter = true

func _build_dialogue_summary(npc_name: String) -> String:
	if npc_name.strip_edges().is_empty():
		return "Listen to the NPC before you skip ahead. Dialogue usually reveals whether they want help, combat, or a puzzle fix."
	return "%s is likely giving the clue in dialogue. Read for the key verb: help, continue, puzzle, or fight." % npc_name

func _build_dialogue_hint_message(npc_name: String, default_message: String) -> String:
	if npc_name.strip_edges().is_empty():
		return default_message.capitalize() if default_message != "" else "Read the NPC dialogue carefully."
	return "%s: %s." % [npc_name, default_message.capitalize()]

func _build_puzzle_summary() -> String:
	if dependency_minigame and dependency_minigame.has_method("_objective_short_text"):
		return str(dependency_minigame.call("_objective_short_text"))

	var lines := _build_puzzle_objective_lines()
	return _join_lines(lines)

func _build_puzzle_suggestions(npc_name: String) -> Array[Dictionary]:
	var suggestions: Array[Dictionary] = []
	var puzzle_title := _get_current_puzzle_title()
	var puzzle_hints := _get_current_puzzle_hints()
	var next_hint := puzzle_hints[0] if not puzzle_hints.is_empty() else ""

	suggestions.append({
		"label": "What is the goal?",
		"detail": "Tux turns the puzzle into a short objective.",
		"message": _build_puzzle_goal_message(puzzle_title),
	})
	suggestions.append({
		"label": "What should I do first?",
		"detail": "A first-step reminder based on the puzzle hints.",
		"message": next_hint if next_hint != "" else "Check the objective panel and start with the first listed command.",
	})
	suggestions.append({
		"label": "What am I avoiding?",
		"detail": "A reminder about wrong links or wrong commands.",
		"message": _build_puzzle_avoidance_message(npc_name),
	})
	suggestions.append({
		"label": "Show the next step",
		"detail": "Tux repeats the most useful current hint.",
		"message": next_hint if next_hint != "" else "Look for the next readable step in the objective panel.",
	})

	return suggestions

func _build_puzzle_goal_message(puzzle_title: String) -> String:
	if puzzle_title.strip_edges().is_empty():
		return "Solve the current puzzle by following the objective panel and avoiding bad links."
	return "Current puzzle: %s. Focus on the green path, the restored fragments, or the command sequence shown in the objective panel." % puzzle_title

func _build_puzzle_avoidance_message(npc_name: String) -> String:
	var lower_name := npc_name.to_lower()
	if lower_name.find("link") != -1:
		return "Avoid red links and broken stubs. Build a full green path from Kernel to App."
	if lower_name.find("ghost") != -1:
		return "Avoid skipping the log-reading steps. The ghost puzzle usually wants a calm, ordered sequence."
	if lower_name.find("remnant") != -1:
		return "Avoid leaving the remnant active. Trace it, isolate it, then finish the stability steps."
	if lower_name.find("printer") != -1:
		return "Avoid rushing the reset. Clear the jam, fix permissions, and rebuild the queue in order."
	if lower_name.find("lost") != -1:
		return "Avoid trying to compile too early. Find, restore, decrypt, assemble, then compile."
	return "Avoid random commands. Follow the visible sequence and use Tux if the dialogue gave a clue."

func _get_current_puzzle_title() -> String:
	if not enemy_controller:
		return ""
	if "puzzle_data" in enemy_controller and enemy_controller.puzzle_data and "title" in enemy_controller.puzzle_data:
		return str(enemy_controller.puzzle_data.title)
	return ""

func _get_current_puzzle_hints() -> Array[String]:
	if not enemy_controller:
		return []
	if not ("puzzle_data" in enemy_controller):
		return []
	var puzzle_data = enemy_controller.puzzle_data
	if puzzle_data == null or not ("hints" in puzzle_data):
		return []
	var hints: Array[String] = []
	for hint in puzzle_data.hints:
		var hint_text := str(hint).strip_edges()
		if hint_text != "":
			hints.append(hint_text)
	return hints

func _get_current_npc_name() -> String:
	if enemy_controller == null:
		return "NPC"
	if "enemy_name" in enemy_controller:
		var enemy_name := str(enemy_controller.enemy_name).strip_edges()
		if enemy_name != "":
			return enemy_name
	if "display_name" in enemy_controller:
		var display_name := str(enemy_controller.display_name).strip_edges()
		if display_name != "":
			return display_name
	return "NPC"

func _get_current_mode() -> int:
	if enemy_controller and "current_mode" in enemy_controller:
		return int(enemy_controller.current_mode)
	return 0

func _has_player_attacked_current_npc() -> bool:
	if _player_attacked_this_encounter:
		return true

	if enemy_controller and "has_attacked" in enemy_controller:
		return bool(enemy_controller.has_attacked)

	if not SceneManager:
		return false

	var npc_name := _get_current_npc_name()
	if npc_name.strip_edges().is_empty():
		return false

	var meta_key := _combat_state_meta_key(npc_name)
	if not SceneManager.has_meta(meta_key):
		return false

	var combat_state = SceneManager.get_meta(meta_key)
	if combat_state is Dictionary:
		return bool(combat_state.get("has_attacked", false))

	return false

func _update_mode_display() -> void:
	if not mode_label or not enemy_controller:
		return
	
	# Get current mode from enemy controller
	if "current_mode" in enemy_controller:
		match enemy_controller.current_mode:
			0:  # DIALOGUE
				mode_label.text = "[DIALOGUE]"
			1:  # COMBAT
				mode_label.text = "[COMBAT MODE]"
				# Play combat terminal music when transitioning to combat
				if SceneManager:
					SceneManager.play_music_for_key("combat_terminal")
			2:  # PUZZLE
				mode_label.text = "[PUZZLE MODE]"
				# Play puzzle terminal music when transitioning to puzzle
				if SceneManager:
					SceneManager.play_music_for_key("puzzle_terminal")
			3:  # RESOLVED
				mode_label.text = "[RESOLVED]"
			_:
				mode_label.text = "[UNKNOWN]"
	_update_side_help_for_mode()
	_refresh_terminal_visuals()

func _update_hp_displays() -> void:
	# Update player HP
	if combat_manager and "player_state" in combat_manager:
		var ps = combat_manager.player_state
		if ps and "current_integrity" in ps and "max_integrity" in ps:
			if player_hp_bar:
				player_hp_bar.max_value = ps.max_integrity
				player_hp_bar.value = ps.current_integrity
				player_hp_bar.step = maxf(1.0, float(ps.max_integrity) / float(INTEGRITY_SEGMENTS))
			if player_hp_label:
				player_hp_label.text = "%s %d / %d" % [_build_integrity_segments(ps.current_integrity, ps.max_integrity), ps.current_integrity, ps.max_integrity]
	
	# Update enemy HP
	if enemy_controller:
		var hp := 0
		var max_hp_val := 100
		
		# Try enemy_data first (LostFileEnemy stores HP there)
		if "enemy_data" in enemy_controller and enemy_controller.enemy_data:
			var ed = enemy_controller.enemy_data
			if "current_hp" in ed:
				hp = ed.current_hp
			if "max_hp" in ed:
				max_hp_val = ed.max_hp
		# Fallback to direct properties
		elif "current_hp" in enemy_controller:
			hp = enemy_controller.current_hp
			if "max_hp" in enemy_controller:
				max_hp_val = enemy_controller.max_hp
		
		if enemy_hp_bar:
			enemy_hp_bar.max_value = max_hp_val
			enemy_hp_bar.value = hp
			enemy_hp_bar.step = maxf(1.0, float(max_hp_val) / float(INTEGRITY_SEGMENTS))
		if enemy_hp_label:
			enemy_hp_label.text = "%s %d / %d" % [_build_integrity_segments(hp, max_hp_val), hp, max_hp_val]

func _get_color_for_type(type) -> String:
	# CRT Terminal color palette
	# INFO=0, SUCCESS=1, WARNING=2, ERROR=3, DAMAGE=4, HEAL=5, STATUS=6
	match type:
		1:  # SUCCESS
			return "#4df24d"
		2:  # WARNING
			return "#e6cc33"
		3:  # ERROR
			return "#e65959"
		4:  # DAMAGE
			return "#e68c33"
		5:  # HEAL
			return "#4de6b3"
		6:  # STATUS
			return "#d9bf40"
		_:  # INFO
			return "#4de64d"

func _combat_state_meta_key(npc_name: String) -> String:
	var sanitized_name := ""
	for i in npc_name.length():
		var ch := npc_name[i]
		var code := ch.unicode_at(0)
		var is_ascii_letter := (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var is_ascii_digit := code >= 48 and code <= 57
		if is_ascii_letter or is_ascii_digit or ch == "_":
			sanitized_name += ch.to_lower()
		else:
			sanitized_name += "_"

	if sanitized_name.is_empty():
		sanitized_name = "npc"
	elif sanitized_name[0].unicode_at(0) >= 48 and sanitized_name[0].unicode_at(0) <= 57:
		sanitized_name = "_" + sanitized_name

	return "combat_state_" + sanitized_name

func _close_active_dialogue() -> void:
	# Find and close any active dialogue balloon
	var root = get_tree().root
	var balloons_to_remove: Array[Node] = []
	
	for child in root.get_children():
		# IMPORTANT: Don't remove the DialogueManager autoload!
		if child.name == "DialogueManager":
			continue
		
		# Check if it's a dialogue balloon (CanvasLayer with specific structure)
		# Balloon names typically contain "Balloon" not just "Dialogue"
		if child.name.contains("Balloon"):
			balloons_to_remove.append(child)
			continue
		
		# Check if it's a CanvasLayer with a Balloon child (dialogue balloon structure)
		if child is CanvasLayer:
			var balloon = child.get_node_or_null("Balloon")
			if balloon == null:
				balloon = child.get_node_or_null("%Balloon")
			if balloon:
				balloons_to_remove.append(child)
				continue
	
	# Remove all found balloons
	for balloon in balloons_to_remove:
		balloon.queue_free()
	
	# Also try ending dialogue via DialogueManager
	var dm = get_node_or_null("/root/DialogueManager")
	if dm:
		# Try various methods to end dialogue
		if dm.has_method("end_dialogue"):
			dm.end_dialogue()
		elif dm.has_method("stop"):
			dm.stop()

func _show_terminal_intro_tutorial_if_needed() -> void:
	if _is_tutorial_seen(TUTORIAL_META_TERMINAL_INTRO):
		return

	await _show_tutorial_popup(
		"Combat Terminal Overview",
		"This terminal is your command console during encounters.\nType commands in the input row, then press [ENTER] to run them.\nOutput appears in the large console area above.",
		"Tip: watch the right-side objective panel for the next command goals.",
		"terminal"
	)
	_mark_tutorial_seen(TUTORIAL_META_TERMINAL_INTRO)

func _show_timing_intro_tutorial_if_needed() -> void:
	if _is_tutorial_seen(TUTORIAL_META_TIMING_INTRO):
		return

	await _show_tutorial_popup(
		"Timing Challenge",
		"Press SPACE while the marker moves across the bar.\nGreen = hit but can still fail.\nRed = complete miss.\nYellow = critical success.",
		"Better timing gives stronger command results.",
		"timing"
	)
	_mark_tutorial_seen(TUTORIAL_META_TIMING_INTRO)

func _show_dependency_intro_tutorial_if_needed() -> void:
	if _is_tutorial_seen(TUTORIAL_META_DEPENDENCY_INTRO):
		return

	await _show_tutorial_popup(
		"Connecting Nodes Puzzle",
		"Place nodes and connect links until you build a clean path from Kernel to App.\nGreen links are stable, red links are broken/conflicting.\nWin by producing one valid green route.",
		"Build carefully: every bad reset risks terminal integrity.",
		"nodes"
	)
	_mark_tutorial_seen(TUTORIAL_META_DEPENDENCY_INTRO)

func _is_tutorial_seen(meta_key: String) -> bool:
	var host := _get_tutorial_meta_host()
	if host == null:
		return false
	if not host.has_meta(meta_key):
		return false
	return bool(host.get_meta(meta_key))

func _mark_tutorial_seen(meta_key: String) -> void:
	var host := _get_tutorial_meta_host()
	if host == null:
		return
	host.set_meta(meta_key, true)

func _get_tutorial_meta_host() -> Node:
	if SceneManager:
		return SceneManager
	return get_tree().root

func _ensure_tutorial_popup_ui() -> void:
	if _tutorial_popup_ui != null and is_instance_valid(_tutorial_popup_ui):
		return

	var popup_scene := load(TUTORIAL_POPUP_SCENE_PATH) as PackedScene
	if popup_scene == null:
		push_warning("Tutorial popup scene not found: " + TUTORIAL_POPUP_SCENE_PATH)
		return

	var popup_instance := popup_scene.instantiate()
	if not (popup_instance is CombatTutorialPopup):
		push_warning("Tutorial popup scene root must be CombatTutorialPopup.")
		if popup_instance:
			popup_instance.queue_free()
		return

	_tutorial_popup_ui = popup_instance as CombatTutorialPopup
	_tutorial_popup_ui.name = "CombatTutorialPopup"
	_tutorial_popup_ui.z_index = 200
	add_child(_tutorial_popup_ui)

func _show_tutorial_popup(title: String, body: String, footer: String, visual_kind: String) -> void:
	_ensure_tutorial_popup_ui()
	if _tutorial_popup_ui == null:
		return

	_tutorial_popup_visible = true
	_tutorial_popup_ui.show_popup(title, body, footer, visual_kind)
	await _tutorial_popup_ui.closed
	_tutorial_popup_visible = false
	tutorial_popup_closed.emit()

func _hide_tutorial_popup() -> void:
	_tutorial_popup_visible = false
	if _tutorial_popup_ui != null and is_instance_valid(_tutorial_popup_ui):
		_tutorial_popup_ui.hide_popup()

func _make_visual_chip(text: String, color: Color, chip_size: Vector2 = Vector2(170, 54)) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = chip_size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.95, 0.98, 0.95, 0.65)
	chip.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.96, 0.98, 0.96, 1.0))
	label.add_theme_font_size_override("font_size", 13)
	chip.add_child(label)

	return chip

#endregion
#region Timing Minigame

## Called when combat manager requests the timing minigame
func _on_timing_minigame_requested(command: CommandParser.CommandResult, difficulty: float) -> void:
	if not timing_minigame:
		var fallback_profile: Dictionary = {}
		if combat_manager and combat_manager.has_method("get_timing_profile"):
			fallback_profile = combat_manager.call("get_timing_profile") as Dictionary
		# Fallback: if no minigame, complete with normal hit
		if combat_manager and combat_manager.has_method("apply_timing_result"):
			var fallback_zone := 2 if bool(fallback_profile.get("force_critical_only", false)) else 1
			combat_manager.apply_timing_result(fallback_zone, 1.0, false)
		return

	await _show_timing_intro_tutorial_if_needed()
	
	# Disable input while timing
	if command_input:
		command_input.editable = false
	
	# Update turn indicator
	if turn_indicator:
		turn_indicator.text = "[ TIMING! ]"
	
	# Store that this is combat timing
	_current_timing_context = "combat"
	var timing_profile: Dictionary = {}
	if combat_manager and combat_manager.has_method("get_timing_profile"):
		timing_profile = combat_manager.call("get_timing_profile") as Dictionary
	if timing_profile.is_empty():
		timing_profile = {}

	var prompt_text := "⚔️ TIMING CHALLENGE! Press SPACE at the right moment!"
	if bool(timing_profile.get("force_critical_only", false)):
		prompt_text = "⚔️ TASKKILL! Critical window only."
	elif command.command_type == CommandParser.CommandType.DEFEND:
		prompt_text = "🛡️ DEFEND! Press SPACE for a perfect guard."
	elif command.command_type == CommandParser.CommandType.HEAL:
		prompt_text = "💊 HEAL! Press SPACE to restore integrity."

	if timing_profile.get("force_critical_only", false):
		timing_minigame.set_force_critical_only(true)
	else:
		timing_minigame.set_force_critical_only(false)

	if timing_profile.has("critical_zone_percent") and timing_profile.has("normal_zone_percent"):
		timing_minigame.set_zone_sizes(float(timing_profile.get("critical_zone_percent", 0.12)), float(timing_profile.get("normal_zone_percent", 0.22)))
	
	# Start the timing minigame
	_print_terminal("\n[color=#f2e066]%s[/color]\n" % prompt_text)
	_print_terminal("[color=#aaaaaa]Command: %s[/color]\n" % command.raw_input)
	var custom_instruction := String(timing_profile.get("instruction", ""))
	timing_minigame.start_timing(TimingMinigame.TimingContext.COMBAT, difficulty, custom_instruction)

## Start timing-bar minigame for puzzle steps before final compile
func _start_puzzle_timing_minigame(difficulty: float) -> void:
	if not timing_minigame:
		_apply_puzzle_timing_result(1, 0.7)
		return

	await _show_timing_intro_tutorial_if_needed()

	_print_terminal("\n[color=#f2e066]⏱️ PUZZLE TIMING WINDOW[/color]\n")
	_print_terminal("[color=#aaaaaa]Tux: lock this step before the final compile.[/color]\n")

	if command_input:
		command_input.editable = false

	if turn_indicator:
		turn_indicator.text = "[ PUZZLE TIMING ]"

	_current_timing_context = "puzzle"
	timing_minigame.start_timing(TimingMinigame.TimingContext.PUZZLE, difficulty)

## Start dependency resolver minigame for puzzle commands
func _start_puzzle_minigame(_difficulty: float) -> void:
	if not dependency_minigame:
		# Fallback: if no minigame, apply with normal success
		_apply_puzzle_timing_result(1, 0.7)
		return

	if dependency_minigame.has_method("configure_for_encounter"):
		dependency_minigame.configure_for_encounter(_get_dependency_profile())

	# Print message in terminal
	_print_terminal("\n[color=#f2e066]🔧 FINAL LINK STAGE[/color]\n")
	_print_terminal("[color=#aaaaaa]Tux: one last step. Build a full green Kernel -> App path.[/color]\n")

	# Disable command input while puzzle minigame is active
	if command_input:
		command_input.editable = false

	# Update turn indicator
	if turn_indicator:
		turn_indicator.text = "[ PUZZLE CHALLENGE ]"

	# Mark pending puzzle resolution and open minigame
	_current_timing_context = "puzzle"
	_puzzle_minigame_pending = true
	_dependency_objective_active = true
	_update_side_help_for_mode()
	_set_terminal_for_dependency_mode(true)
	dependency_minigame.open_minigame()
	await _show_dependency_intro_tutorial_if_needed()

func _update_side_help_for_mode() -> void:
	if not help_label:
		return

	var current_mode := 0
	if enemy_controller and "current_mode" in enemy_controller:
		current_mode = int(enemy_controller.current_mode)

	var objective_title := "TERMINAL OBJECTIVE"
	var lines: Array[String] = []

	match current_mode:
		0:
			objective_title = "GOAL // DIALOGUE"
			lines = [
				"goal: read the NPC before you skip ahead",
				"next: type continue to keep listening",
				"options: attack for combat, help/puzzle for repairs",
			]
		1:
			objective_title = "GOAL // COMBAT"
			lines = [
				"goal: reduce target integrity to 0",
				"next: attack/hit, defend/block, heal/repair, kill, or restore",
				"escape: use flee if you need a reset",
			]
		2:
			objective_title = "GOAL // PUZZLE"
			lines = _build_puzzle_objective_lines()
		_:
			objective_title = "GOAL"
			lines = ["Encounter resolved."]

	if objective_title_label:
		objective_title_label.text = objective_title

	help_label.text = _join_lines(lines)
	_refresh_terminal_visuals()

func _build_puzzle_objective_lines() -> Array[String]:
	if _dependency_objective_active:
		return [
			"goal: build a full green Kernel -> App path",
			"next: place the correct nodes and links",
			"avoid: red links, red nodes, and dead ends",
			"reset: use [EXIT] only if you need to start over",
		]

	if not enemy_controller or not ("puzzle_data" in enemy_controller):
		return ["Type help for puzzle command list"]

	var puzzle_data = enemy_controller.puzzle_data
	if puzzle_data == null or not ("custom_data" in puzzle_data):
		return ["Type help for puzzle command list"]

	var custom: Dictionary = puzzle_data.custom_data
	if custom.has("expected_sequence"):
		var expected_sequence: Array = custom.get("expected_sequence", [])
		var current_index := int(custom.get("current_index", 0))
		var seq_lines: Array[String] = []
		seq_lines.append("goal: follow the command sequence in order")
		var start_index := maxi(0, current_index - 1)
		var end_index := mini(expected_sequence.size(), current_index + 3)
		for i in range(start_index, end_index):
			var command_text := str(expected_sequence[i])
			var prefix := "[ ] "
			if i < current_index:
				prefix = "[X] "
			elif i == current_index:
				prefix = "[>] "
			seq_lines.append(prefix + command_text)
		if seq_lines.is_empty() and expected_sequence.size() > 0:
			seq_lines.append("[X] sequence complete")
		return seq_lines

	if custom.has("required_fragments"):
		var found: Array = custom.get("fragments_found", [])
		var restored: Array = custom.get("fragments_restored", [])
		var decrypted: Array = custom.get("fragments_decrypted", [])
		var required: Array = custom.get("required_fragments", [])
		var fragment_lines: Array[String] = []
		for fragment in required:
			var fragment_name := str(fragment)
			var marker := "[ ]"
			if fragment in restored:
				marker = "[X]"
			elif fragment == ".fragment_003" and fragment in decrypted:
				marker = "[~]"
			fragment_lines.append("%s restore %s" % [marker, fragment_name])
		fragment_lines.insert(0, "goal: recover each fragment before compiling")

		if found.size() < required.size():
			fragment_lines.append("next: find .fragment")
		elif ".fragment_003" in found and ".fragment_003" not in decrypted:
			fragment_lines.append("next: decrypt .fragment_003")
		elif not bool(custom.get("file_assembled", false)):
			fragment_lines.append("next: cat fragments")
		elif not bool(custom.get("file_compiled", false)):
			fragment_lines.append("next: compile recovered_file")

		return fragment_lines

	return ["Type help for puzzle command list"]

func _join_lines(lines: Array[String]) -> String:
	var output := ""
	for i in range(lines.size()):
		if i > 0:
			output += "\n\n"
		output += lines[i]
	return output

func _build_integrity_segments(current_value: int, max_value: int) -> String:
	var safe_max := maxi(1, max_value)
	var ratio := clampf(float(current_value) / float(safe_max), 0.0, 1.0)
	var filled := int(round(ratio * float(INTEGRITY_SEGMENTS)))
	filled = clampi(filled, 0, INTEGRITY_SEGMENTS)
	var output := "["
	for i in range(INTEGRITY_SEGMENTS):
		output += "#" if i < filled else "-"
	output += "]"
	return output

func _get_dependency_profile() -> String:
	if not enemy_controller:
		return "default"

	var enemy_label := ""
	if "enemy_name" in enemy_controller:
		enemy_label = str(enemy_controller.enemy_name).to_lower()
	elif "enemy_data" in enemy_controller and enemy_controller.enemy_data and "id" in enemy_controller.enemy_data:
		enemy_label = str(enemy_controller.enemy_data.id).to_lower()

	if enemy_label.find("remnant") != -1:
		return "driver_remnant"
	if enemy_label.find("ghost") != -1:
		return "hardware_ghost"
	if enemy_label.find("evil") != -1 and enemy_label.find("tux") != -1:
		return "evil_tux"
	if enemy_label.find("printer") != -1:
		return "printer_beast"
	if enemy_label.find("broken") != -1 and enemy_label.find("link") != -1:
		return "broken_link"
	if enemy_label.find("lost") != -1:
		return "lost_file"

	return "default"

func _get_dependency_fail_limit() -> int:
	var enemy_id := ""
	if enemy_controller and "enemy_data" in enemy_controller and enemy_controller.enemy_data and "id" in enemy_controller.enemy_data:
		enemy_id = str(enemy_controller.enemy_data.id).to_lower()
	if enemy_id == "evil_tux":
		return 1
	return DEPENDENCY_FAIL_LIMIT

## Track current timing context
var _current_timing_context: String = "combat"

## Called when timing minigame completes
func _on_timing_completed(result: TimingMinigame.TimingResult) -> void:
	# Log result to terminal
	match result.zone:
		TimingMinigame.ZoneType.CRITICAL:
			_print_terminal("[color=#ffd700]⭐ CRITICAL! Perfect timing![/color]\n")
		TimingMinigame.ZoneType.NORMAL:
			_print_terminal("[color=#66f266]✓ HIT! Good timing![/color]\n")
		TimingMinigame.ZoneType.MISS:
			_print_terminal("[color=#e65959]✗ MISS! Command failed![/color]\n")
	
	# Re-enable input
	if command_input:
		command_input.editable = true
		command_input.grab_focus()
	
	# Route to appropriate handler based on context
	if _current_timing_context == "puzzle":
		_apply_puzzle_timing_result(result.zone, result.success_chance)
	else:
		# Send result to combat manager
		if combat_manager and combat_manager.has_method("apply_timing_result"):
			combat_manager.apply_timing_result(
				result.zone,
				result.damage_multiplier,
				result.is_miss()
			)
	_refresh_terminal_visuals()

## Apply timing result to puzzle
func _apply_puzzle_timing_result(zone: int, success_chance: float) -> void:
	if enemy_controller and enemy_controller.has_method("apply_puzzle_timing_result"):
		var result = enemy_controller.apply_puzzle_timing_result(zone, success_chance)
		if result is Dictionary:
			if result.get("message", "") != "":
				_print_terminal("[color=#66f266]%s[/color]\n" % _simplify_puzzle_message(str(result.message)))
			if result.get("mode_changed", false):
				_update_mode_display()
			# Play SFX for puzzle result: complete vs failed
			if result.get("encounter_ended", false):
				if SceneManager:
					SceneManager.play_sfx("res://album/sfx/puzzle-complete.mp3")
				await get_tree().create_timer(2.0).timeout
				_force_close_and_cleanup()
			elif result.get("mode_changed", false):
				# Mode changes often indicate failure/return to combat
				if SceneManager:
					SceneManager.play_sfx("res://album/sfx/puzzle-error.mp3")
		_update_hp_displays()
		_update_side_help_for_mode()

## Called when timing minigame is cancelled
func _on_timing_cancelled() -> void:
	_print_terminal("[color=#aaaaaa]Timing cancelled.[/color]\n")
	
	# Re-enable input
	if command_input:
		command_input.editable = true
		command_input.grab_focus()
	
	# Treat as miss based on context
	if _current_timing_context == "puzzle":
		_apply_puzzle_timing_result(0, 0.0)
	elif combat_manager and combat_manager.has_method("apply_timing_result"):
		combat_manager.apply_timing_result(0, 0.0, true)

func _on_dependency_resolver_completed(success: bool) -> void:
	if not _puzzle_minigame_pending:
		return

	_puzzle_minigame_pending = false
	_dependency_objective_active = false
	_update_side_help_for_mode()
	_set_terminal_for_dependency_mode(false)

	if success:
		_dependency_fail_count = 0
		_print_terminal("[color=#66f266]Puzzle solved![/color]\n")
		if SceneManager:
			SceneManager.play_sfx("res://album/sfx/puzzle-complete.mp3")
		_apply_puzzle_timing_result(2, 1.0)
	else:
		if SceneManager:
			SceneManager.play_sfx("res://album/sfx/puzzle-error.mp3")
		_handle_dependency_minigame_failure("Puzzle failed.")

func _on_dependency_resolver_closed() -> void:
	_dependency_objective_active = false
	_update_side_help_for_mode()
	_set_terminal_for_dependency_mode(false)

	# If the puzzle was pending and player closed the minigame, treat as failed attempt.
	if _puzzle_minigame_pending:
		_puzzle_minigame_pending = false
		_handle_dependency_minigame_failure("Puzzle closed.")

	# Ensure terminal input is restored after close.
	if command_input:
		command_input.editable = true
		command_input.grab_focus()
	if turn_indicator:
		turn_indicator.text = "[ AWAITING INPUT ]"

func _handle_dependency_minigame_failure(reason_text: String) -> void:
	_dependency_fail_count += 1
	var damage_taken := _apply_dependency_fail_damage()

	_print_terminal("[color=#e65959]%s[/color]\n" % reason_text)
	_print_terminal("[color=#e68c33]Integrity -%d (%d/%d failures)[/color]\n" % [
		damage_taken,
		_dependency_fail_count,
		_get_dependency_fail_limit()
	])
	_update_hp_displays()
	_update_side_help_for_mode()

	if _is_player_defeated():
		_print_terminal("[color=#f26666]System integrity compromised.[/color]\n")
		_force_close_and_cleanup()
		return

	if _dependency_fail_count >= _get_dependency_fail_limit():
		_mark_dependency_failure_dialogue_state()
		_print_terminal("[color=#f26666]Too many failed puzzle attempts. Terminal access revoked.[/color]\n")
		if turn_indicator:
			turn_indicator.text = "[ TERMINAL EJECTED ]"
		_force_close_and_cleanup()
		return

	_apply_puzzle_timing_result(0, 0.0)

func _apply_dependency_fail_damage() -> int:
	if combat_manager and "player_state" in combat_manager and combat_manager.player_state:
		return combat_manager.player_state.take_damage(DEPENDENCY_FAIL_DAMAGE)
	return DEPENDENCY_FAIL_DAMAGE

func _is_player_defeated() -> bool:
	if combat_manager and "player_state" in combat_manager and combat_manager.player_state:
		return combat_manager.player_state.current_integrity <= 0
	return false

func _mark_dependency_failure_dialogue_state() -> void:
	if not SceneManager:
		return

	var enemy_label := _get_current_enemy_label()
	if enemy_label != "":
		SceneManager.npc_states[enemy_label] = "puzzle_ejected"

func _get_current_enemy_label() -> String:
	if not enemy_controller:
		return ""

	if "enemy_name" in enemy_controller:
		return str(enemy_controller.enemy_name)
	if "enemy_data" in enemy_controller and enemy_controller.enemy_data:
		if "display_name" in enemy_controller.enemy_data:
			return str(enemy_controller.enemy_data.display_name)
		if "id" in enemy_controller.enemy_data:
			return str(enemy_controller.enemy_data.id)

	return ""

func _set_terminal_for_dependency_mode(active: bool) -> void:
	var terminal_container_node := get_node_or_null("TerminalContainer") as CanvasItem
	var status_panel_node := get_node_or_null("StatusPanel") as CanvasItem
	var crt_overlay := get_node_or_null("CRTEffectOverlay") as CanvasItem

	if terminal_container_node:
		terminal_container_node.visible = not active
	if status_panel_node:
		status_panel_node.visible = true
	if crt_overlay:
		crt_overlay.visible = not active
	_refresh_terminal_visuals(true)

func _simplify_puzzle_message(message: String) -> String:
	var out := message
	out = out.replace("[TIMING REQUIRED]", "[PUZZLE STEP]")
	out = out.replace("[ TIMING REQUIRED ]", "[PUZZLE STEP]")
	out = out.replace("[Timing Required]", "[Puzzle Step]")
	out = out.replace("[timing required]", "[puzzle step]")
	out = out.replace("perfect timing", "great solve")
	out = out.replace("PERFECT TIMING", "GREAT SOLVE")
	out = out.replace("timing", "solve")
	out = out.replace("Timing", "Solve")
	out = out.replace("Dependency", "Link")
	out = out.replace("dependency", "link")
	return out

func _setup_terminal_visuals() -> void:
	var crack_sprite := _resolve_objective_crack_sprite()
	var crack_hole := _resolve_objective_crack_hole()
	if npc_bad_texture:
		npc_bad_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if npc_good_texture:
		npc_good_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if npc_turn_flash:
		npc_turn_flash.visible = false
	if objective_broken_texture:
		objective_broken_texture.texture = null
		objective_broken_texture.visible = false
	if crack_sprite:
		crack_sprite.visible = false
		crack_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		crack_sprite.z_index = 220
		crack_sprite.show_behind_parent = false
		if crack_sprite.texture == null:
			crack_sprite.texture = load(CRACKED_GLASS_TEXTURE_PATH)
		if _objective_crack_material == null:
			var cracked_shader := load(CRACKED_GLASS_SHADER_PATH) as Shader
			if cracked_shader:
				_objective_crack_material = ShaderMaterial.new()
				_objective_crack_material.shader = cracked_shader
		if _objective_crack_material:
			_objective_crack_material.set_shader_parameter("refraction_offset", Vector2(34.0, 34.0))
			_objective_crack_material.set_shader_parameter("crack_dark_threshold", 0.22)
			_objective_crack_material.set_shader_parameter("crack_rim_threshold", 0.36)
			_objective_crack_material.set_shader_parameter("crack_alpha_threshold", 0.02)
			_objective_crack_material.set_shader_parameter("crack_core_darkness", 0.68)
			_objective_crack_material.set_shader_parameter("crack_rim_brightness", 0.5)
			crack_sprite.material = _objective_crack_material
	if crack_hole:
		crack_hole.visible = false
		crack_hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crack_hole.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		crack_hole.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crack_hole.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crack_hole.z_index = 221
		crack_hole.top_level = true
		crack_hole.modulate = Color(1.0, 1.0, 1.0, 1.0)
		crack_hole.texture = _get_crack_hole_texture()
	if npc_good_texture and _npc_visual_material == null:
		var reveal_shader := load(NPC_REVEAL_SHADER_PATH) as Shader
		if reveal_shader:
			_npc_visual_material = ShaderMaterial.new()
			_npc_visual_material.shader = reveal_shader
			npc_good_texture.material = _npc_visual_material
	_update_crack_sprite_transform(_get_ui_scale_factor())
	_refresh_terminal_visuals(true)

func _refresh_terminal_visuals(force_immediate: bool = false) -> void:
	var crack_sprite := _resolve_objective_crack_sprite()
	var crack_hole := _resolve_objective_crack_hole()
	var scale_factor := _get_ui_scale_factor()
	if npc_visual_panel:
		npc_visual_panel.visible = true
	var current_mode := _get_current_mode()
	var should_show_attack_glow := current_mode == 1 and _npc_player_turn and _has_player_attacked_current_npc()
	var enemy_key := _get_current_enemy_visual_key()
	var bad_texture := _get_npc_visual_texture(enemy_key, "bad")
	var good_texture := _get_npc_visual_texture(enemy_key, "good")
	if npc_bad_texture:
		npc_bad_texture.texture = bad_texture
		npc_bad_texture.visible = true
		npc_bad_texture.modulate = Color(1.0, 0.35, 0.35, 1.0) if should_show_attack_glow else Color(1.0, 1.0, 1.0, 1.0)
	if npc_good_texture:
		npc_good_texture.texture = good_texture
		npc_good_texture.visible = current_mode == 2 or _get_npc_visual_progress() > 0.0
	_set_npc_reveal_progress(_get_npc_visual_progress(), force_immediate)
	if npc_turn_flash:
		npc_turn_flash.visible = should_show_attack_glow
		npc_turn_flash.color = Color(1.0, 0.1, 0.1, 0.18) if npc_turn_flash.visible else Color(1.0, 0.1, 0.1, 0.0)
	if objective_broken_texture:
		objective_broken_texture.visible = false
	if crack_sprite:
		_update_crack_sprite_transform(scale_factor)
		crack_sprite.visible = current_mode == 1
	if crack_hole:
		_update_crack_hole_transform(scale_factor)
		crack_hole.visible = current_mode == 1 and crack_sprite != null and crack_sprite.visible
	if objective_frame:
		objective_frame.modulate = Color(1.0, 0.82, 0.82, 1.0) if current_mode == 1 else Color(1.0, 1.0, 1.0, 1.0)

func _resolve_objective_crack_sprite() -> Sprite2D:
	if objective_crack_sprite and is_instance_valid(objective_crack_sprite):
		return objective_crack_sprite

	objective_crack_sprite = get_node_or_null("StatusPanel/VBox/ObjectiveFrame/Sprite2D") as Sprite2D
	if objective_crack_sprite:
		return objective_crack_sprite

	objective_crack_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if objective_crack_sprite:
		return objective_crack_sprite

	var fallback := find_child("Sprite2D", true, false)
	if fallback is Sprite2D:
		objective_crack_sprite = fallback as Sprite2D

	return objective_crack_sprite

func _resolve_objective_crack_hole() -> TextureRect:
	if objective_crack_hole and is_instance_valid(objective_crack_hole):
		return objective_crack_hole

	objective_crack_hole = get_node_or_null("ObjectiveCrackHole") as TextureRect
	if objective_crack_hole:
		return objective_crack_hole

	var fallback := find_child("ObjectiveCrackHole", true, false)
	if fallback is TextureRect:
		objective_crack_hole = fallback as TextureRect

	return objective_crack_hole

func _get_crack_hole_texture() -> Texture2D:
	if _objective_crack_hole_texture:
		return _objective_crack_hole_texture

	var texture_size := 256
	var image := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(texture_size * 0.5, texture_size * 0.5)
	var radius := texture_size * 0.5

	for y in range(texture_size):
		for x in range(texture_size):
			var uv := Vector2(float(x), float(y))
			var distance_norm := uv.distance_to(center) / radius
			var alpha := 0.0
			if distance_norm <= 0.7:
				alpha = 1.0
			elif distance_norm <= 0.95:
				alpha = 1.0 - ((distance_norm - 0.7) / 0.25)
			alpha = clampf(alpha, 0.0, 1.0)
			image.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))

	_objective_crack_hole_texture = ImageTexture.create_from_image(image)
	return _objective_crack_hole_texture

func _update_crack_sprite_transform(_scale_factor: float) -> void:
	var crack_sprite := _resolve_objective_crack_sprite()
	if crack_sprite == null:
		return

	var scale_factor := maxf(_scale_factor, 1.0)
	var base_scale := Vector2(0.26141405, 0.23132005)
	crack_sprite.scale = base_scale
	crack_sprite.top_level = true

	var frame_rect := Rect2()
	if objective_frame and is_instance_valid(objective_frame):
		frame_rect = objective_frame.get_global_rect()
	if frame_rect.size == Vector2.ZERO:
		frame_rect = Rect2(Vector2.ZERO, get_viewport_rect().size)

	var sprite_size := Vector2(1536.0, 1536.0)
	if crack_sprite.texture:
		sprite_size = crack_sprite.texture.get_size()

	var visual_size := sprite_size * crack_sprite.scale
	var outside_offset := Vector2(24.0, 18.0) * scale_factor
	var pullback := visual_size * Vector2(0.38, 0.34)
	crack_sprite.global_position = frame_rect.position + frame_rect.size + outside_offset - pullback
	_update_crack_hole_transform(scale_factor)

func _update_crack_hole_transform(_scale_factor: float) -> void:
	var crack_sprite := _resolve_objective_crack_sprite()
	var crack_hole := _resolve_objective_crack_hole()
	if crack_sprite == null or crack_hole == null:
		return

	var sprite_size := Vector2(1536.0, 1536.0)
	if crack_sprite.texture:
		sprite_size = crack_sprite.texture.get_size()

	var visual_size := sprite_size * crack_sprite.scale
	var hole_size := visual_size * 0.32
	var hole_center := crack_sprite.global_position

	crack_hole.size = hole_size
	crack_hole.pivot_offset = hole_size * 0.5
	crack_hole.global_position = hole_center - hole_size * 0.5

func _set_npc_reveal_progress(progress: float, immediate: bool = false) -> void:
	var clamped := clampf(progress, 0.0, 1.0)
	var start_progress := _npc_visual_progress
	_npc_visual_progress = clamped
	if _npc_visual_material == null:
		return
	if _npc_visual_tween != null and _npc_visual_tween.is_running():
		_npc_visual_tween.kill()
	if immediate or is_equal_approx(start_progress, clamped):
		_npc_visual_material.set_shader_parameter("progress", clamped)
		return
	_npc_visual_tween = create_tween()
	_npc_visual_tween.tween_method(Callable(self, "_apply_npc_reveal_progress"), start_progress, clamped, 0.28)

func _apply_npc_reveal_progress(progress: float) -> void:
	if _npc_visual_material:
		_npc_visual_material.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))

func _get_npc_visual_progress() -> float:
	var current_mode := _get_current_mode()
	if current_mode == 1:
		return 0.0
	if current_mode == 3:
		return 1.0
	if current_mode != 2 and not _dependency_objective_active:
		return 0.0

	if _dependency_objective_active and dependency_minigame:
		if dependency_minigame.has_method("_compute_preflight_progress"):
			return clampf(float(dependency_minigame.call("_compute_preflight_progress")), 0.0, 1.0)
		if dependency_minigame.has_method("_get_subobjective_progress"):
			var sub_progress = dependency_minigame.call("_get_subobjective_progress")
			if sub_progress is Dictionary:
				var current := float(sub_progress.get("current", 0.0))
				var target := maxf(1.0, float(sub_progress.get("target", 1.0)))
				return clampf(current / target, 0.0, 1.0)

	var puzzle_data = null
	if enemy_controller and "puzzle_data" in enemy_controller:
		puzzle_data = enemy_controller.puzzle_data
	if puzzle_data == null or not ("custom_data" in puzzle_data):
		return 0.0

	var custom: Dictionary = puzzle_data.custom_data
	if custom.has("expected_sequence"):
		var sequence: Array = custom.get("expected_sequence", [])
		if sequence.is_empty():
			return 0.0
		return clampf(float(custom.get("current_index", 0)) / float(sequence.size()), 0.0, 1.0)

	if custom.has("required_fragments"):
		var required: Array = custom.get("required_fragments", [])
		if required.is_empty():
			return 0.0
		var restored: Array = custom.get("fragments_restored", [])
		var decrypted: Array = custom.get("fragments_decrypted", [])
		var completed := 0.0
		for fragment in required:
			if fragment in restored:
				completed += 1.0
			elif fragment == ".fragment_003" and fragment in decrypted:
				completed += 0.5
		return clampf(completed / float(required.size()), 0.0, 1.0)

	return 0.0

func _get_current_enemy_visual_key() -> String:
	if not enemy_controller:
		return "default"

	var candidates: Array[String] = []
	if "enemy_data" in enemy_controller and enemy_controller.enemy_data:
		if "id" in enemy_controller.enemy_data:
			candidates.append(str(enemy_controller.enemy_data.id))
		if "display_name" in enemy_controller.enemy_data:
			candidates.append(str(enemy_controller.enemy_data.display_name))
	if "enemy_name" in enemy_controller:
		candidates.append(str(enemy_controller.enemy_name))

	var label := _get_current_enemy_label()
	if label != "":
		candidates.append(label)

	# Include class/script hints to survive initialization-order races.
	candidates.append(str(enemy_controller.get_class()))
	var enemy_script: Script = enemy_controller.get_script() as Script
	if enemy_script != null:
		var script_path := str(enemy_script.resource_path)
		if script_path != "":
			candidates.append(script_path.get_file().get_basename())

	for raw_hint in candidates:
		var resolved := _resolve_enemy_visual_key_from_hint(raw_hint)
		if resolved != "":
			return resolved

	return "default"


func _resolve_enemy_visual_key_from_hint(hint: String) -> String:
	var key := hint.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	if key == "":
		return ""

	if NPC_VISUAL_TEXTURE_PATHS.has(key):
		return key

	if key.find("sage") != -1:
		return "sage"
	if key.find("evil") != -1 and key.find("tux") != -1:
		return "evil_tux"
	if key.find("printer") != -1:
		return "printer_beast"
	if key.find("lost") != -1 and key.find("file") != -1:
		return "lost_file"
	if key.find("broken") != -1 and key.find("link") != -1:
		return "broken_link"
	if key.find("driver") != -1 and key.find("remnant") != -1:
		return "driver_remnant"
	if key.find("hardware") != -1 and key.find("ghost") != -1:
		return "hardware_ghost"
	if key.find("messy") != -1 or key.find("directory") != -1:
		return "messy_directory"

	return ""

func _get_npc_visual_texture(enemy_key: String, state: String) -> Texture2D:
	var cache_key := "%s:%s" % [enemy_key, state]
	if _npc_texture_cache.has(cache_key):
		return _npc_texture_cache[cache_key]

	var key_data = NPC_VISUAL_TEXTURE_PATHS.get(enemy_key, NPC_VISUAL_TEXTURE_PATHS["default"])
	var texture_path := str(key_data.get(state, ""))
	if texture_path.is_empty():
		return null
	var texture := load(texture_path) as Texture2D
	if texture:
		_npc_texture_cache[cache_key] = texture
	return texture

## History Helper Functions

func _get_combat_history() -> Array:
	"""Returns an array of all combat events for display in history."""
	if not combat_manager:
		return []
	
	var history: Array = []
	# Collect from combat_data if available
	if "combat_history" in combat_manager:
		history = combat_manager.combat_history.duplicate()
	
	return history

func _add_to_history(event_data: Dictionary) -> void:
	"""Adds an event to combat history."""
	if not combat_manager:
		return
	
	if not "combat_history" in combat_manager:
		combat_manager.combat_history = []
	
	# Ensure event_data has timestamp
	if not "timestamp" in event_data:
		event_data["timestamp"] = Time.get_ticks_msec()
	
	combat_manager.combat_history.append(event_data)

func _clear_combat_history() -> void:
	"""Clears the combat history."""
	if not combat_manager:
		return
	
	if "combat_history" in combat_manager:
		combat_manager.combat_history.clear()

func _get_history_entry_text(entry: Dictionary) -> String:
	"""Formats a history entry for display."""
	var event_type: String = entry.get("type", "unknown")
	var text: String = ""
	
	match event_type:
		"attack":
			var attacker = entry.get("attacker", "Unknown")
			var target = entry.get("target", "Unknown")
			var damage = entry.get("damage", 0)
			text = "%s attacked %s for %s damage" % [attacker, target, damage]
		
		"heal":
			var healer = entry.get("healer", "Unknown")
			var amount = entry.get("amount", 0)
			text = "%s healed for %s" % [healer, amount]
		
		"puzzle_solved":
			var puzzle_name = entry.get("puzzle_name", "Unknown Puzzle")
			text = "Puzzle solved: %s" % puzzle_name
		
		"enemy_defeated":
			var enemy_name = entry.get("enemy_name", "Unknown Enemy")
			text = "Defeated: %s" % enemy_name
		
		"turn_started":
			var turn_number = entry.get("turn", 0)
			var current_player = entry.get("player_turn", false)
			text = "Turn %d - %s's turn" % [turn_number, "Player" if current_player else "Enemy"]
		
		"status_applied":
			var status = entry.get("status", "Unknown")
			var target = entry.get("target", "Unknown")
			text = "%s affected by %s" % [target, status]
		
		_:
			text = entry.get("message", "Unknown event")
	
	return text

func _filter_history_by_type(event_type: String) -> Array:
	"""Returns history entries of a specific type."""
	var history := _get_combat_history()
	return history.filter(func(entry): return entry.get("type", "") == event_type)

func _get_recent_history_entries(count: int = 5) -> Array:
	"""Returns the most recent N history entries."""
	var history := _get_combat_history()
	if history.size() <= count:
		return history
	return history.slice(history.size() - count, history.size())

## Command History Navigation

func _push_command_history(command: String) -> void:
	"""Adds a command to the command history."""
	if command.is_empty():
		return
	
	# Avoid duplicate consecutive commands
	if not _command_history.is_empty() and _command_history[-1] == command:
		return
	
	_command_history.append(command)
	_history_index = -1
	_history_draft = ""

func _navigate_command_history_previous() -> void:
	"""Navigate to previous command (Up key)."""
	if _command_history.is_empty() or not command_input:
		return
	if not _is_cli_history_unlocked():
		return
	
	if _history_index == -1:
		_history_draft = command_input.text
		_history_index = _command_history.size() - 1
	elif _history_index > 0:
		_history_index -= 1

	if _history_index == -1:
		command_input.text = _history_draft
	else:
		command_input.text = _command_history[_history_index]

	# Move cursor to end
	command_input.caret_column = command_input.text.length()

func _navigate_command_history_next() -> void:
	"""Navigate to next command (Down key)."""
	if _command_history.is_empty() or not command_input:
		return
	if not _is_cli_history_unlocked():
		return
	if _history_index == -1:
		return

	_history_index += 1
	if _history_index >= _command_history.size():
		_history_index = -1
		command_input.text = _history_draft
	else:
		command_input.text = _command_history[_history_index]
	command_input.caret_column = command_input.text.length()

func _is_cli_history_unlocked() -> bool:
	if not SceneManager:
		return false
	if SceneManager.get("cli_history_unlocked") != true:
		return false
	var receipts: Variant = SceneManager.get_meta(SKILL_UNLOCK_RECEIPTS_META_KEY, {})
	if receipts is Dictionary:
		return receipts.get("cli_history", false) == true
	return false
	
	#endregion
