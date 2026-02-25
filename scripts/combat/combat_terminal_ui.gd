# combat_terminal_ui.gd
# Bridge script for combat UI - delegates to CombatUIController
# Provides setup_combat(), open_combat_ui(), close_combat_ui() methods
# for encounter_controller.gd compatibility
extends Control
class_name CombatTerminalUI

#region Node References

@onready var terminal_output: RichTextLabel = $TerminalContainer/TerminalOutput
@onready var command_input: LineEdit = $TerminalContainer/InputContainer/CommandInput
@onready var status_panel: Panel = $StatusPanel
@onready var player_hp_bar: ProgressBar = $StatusPanel/VBox/PlayerStatus/HPBar
@onready var player_hp_label: Label = $StatusPanel/VBox/PlayerStatus/HPLabel
@onready var enemy_hp_bar: ProgressBar = $StatusPanel/VBox/EnemyStatus/HPBar
@onready var enemy_hp_label: Label = $StatusPanel/VBox/EnemyStatus/HPLabel
@onready var enemy_name_label: Label = $StatusPanel/VBox/EnemyStatus/NameLabel
@onready var turn_indicator: Label = $StatusPanel/VBox/TurnIndicator
@onready var mode_label: Label = $StatusPanel/VBox/ModeLabel
#endregion

#region Runtime State
var combat_manager: Node = null
var enemy_controller: Node = null
var is_open: bool = false
var timing_minigame: TimingMinigame = null
var dependency_minigame: DependencyResolverMinigame = null
var _puzzle_minigame_pending: bool = false
#endregion

func _ready() -> void:
	# Connect input signals
	if command_input:
		command_input.text_submitted.connect(_on_command_submitted)
	
	var submit_btn = get_node_or_null("TerminalContainer/InputContainer/SubmitButton")
	if submit_btn:
		submit_btn.pressed.connect(_on_submit_pressed)
	
	var exit_btn = get_node_or_null("TerminalContainer/InputContainer/ExitButton")
	if exit_btn:
		exit_btn.pressed.connect(_on_exit_pressed)
	
	# Setup timing minigame
	_setup_timing_minigame()
	_setup_dependency_minigame()

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

## Show the combat UI
func open_combat_ui() -> void:
	is_open = true
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

## Hide the combat UI
func close_combat_ui() -> void:
	is_open = false
	hide()
	_set_terminal_for_dependency_mode(false)
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
	
	# Echo command to terminal
	_print_terminal("[color=#80f280]$ %s[/color]\n" % text)
	
	# Clear input and re-focus
	if command_input:
		command_input.clear()
		command_input.grab_focus()
	
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
				_start_puzzle_minigame(result.get("timing_difficulty", 1.0))
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
	else:
		turn_indicator.text = "[ ENEMY TURN ]"

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
			_print_terminal("  attack     - Strike the enemy\n")
			_print_terminal("  defend     - Reduce incoming damage\n")
			_print_terminal("  scan       - Reveal enemy weakness\n")
			_print_terminal("  heal       - Restore your integrity\n")
			_print_terminal("  escape     - Attempt to flee\n")
		
		2:  # PUZZLE
			var enemy_label := ""
			if enemy_controller and "enemy_name" in enemy_controller:
				enemy_label = str(enemy_controller.enemy_name).to_lower()
			elif enemy_controller and "enemy_data" in enemy_controller and enemy_controller.enemy_data and "id" in enemy_controller.enemy_data:
				enemy_label = str(enemy_controller.enemy_data.id).to_lower()
			if enemy_label.find("broken") != -1 and enemy_label.find("link") != -1:
				_print_terminal("[color=#66f266]HELP - PUZZLE MODE (Broken Link Repair)[/color]\n\n")
				_print_terminal("  scan       - Inspect the stub or verify link_table\n")
				_print_terminal("  find       - Locate the missing target path\n")
				_print_terminal("  disconnect - Unlink the broken stub\n")
				_print_terminal("  connect    - Reattach the stub to /forest/target\n")
				_print_terminal("  chmod      - Fix permissions on link_table\n")
				_print_terminal("  patch      - Stabilize the link table\n")
				_print_terminal("  compile    - Finalize link_map\n")
				_print_terminal("  fight      - Return to combat\n")
			elif enemy_label.find("ghost") != -1:
				_print_terminal("[color=#66f266]HELP - PUZZLE MODE (Hardware Ghost Logs)[/color]\n\n")
				_print_terminal("  scan       - Read the legacy bus logs\n")
				_print_terminal("  find       - Locate the legacy driver table\n")
				_print_terminal("  debug      - Isolate the echo\n")
				_print_terminal("  patch      - Calm the driver table\n")
				_print_terminal("  compile    - Finalize the driver map\n")
				_print_terminal("  fight      - Return to combat\n")
			elif enemy_label.find("remnant") != -1:
				_print_terminal("[color=#66f266]HELP - PUZZLE MODE (Driver Remnant Isolation)[/color]\n\n")
				_print_terminal("  scan       - Capture the rogue signature\n")
				_print_terminal("  find       - Trace the interrupt line\n")
				_print_terminal("  kill       - Terminate the remnant\n")
				_print_terminal("  disconnect - Isolate the irq line\n")
				_print_terminal("  patch      - Stabilize the interrupt table\n")
				_print_terminal("  compile    - Rebuild the stability map\n")
				_print_terminal("  fight      - Return to combat\n")
			elif enemy_label.find("printer") != -1:
				_print_terminal("[color=#66f266]HELP - PUZZLE MODE (Printer Beast Reset)[/color]\n\n")
				_print_terminal("  scan       - Read the spool status\n")
				_print_terminal("  find       - Locate the jam in /var/spool/print\n")
				_print_terminal("  rm         - Remove jammed pages\n")
				_print_terminal("  chmod      - Fix spool permissions\n")
				_print_terminal("  patch      - Reset the spooler\n")
				_print_terminal("  compile    - Rebuild the print queue\n")
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
			2:  # PUZZLE
				mode_label.text = "[PUZZLE MODE]"
			3:  # RESOLVED
				mode_label.text = "[RESOLVED]"
			_:
				mode_label.text = "[UNKNOWN]"

func _update_hp_displays() -> void:
	# Update player HP
	if combat_manager and "player_state" in combat_manager:
		var ps = combat_manager.player_state
		if ps and "current_integrity" in ps and "max_integrity" in ps:
			if player_hp_bar:
				player_hp_bar.max_value = ps.max_integrity
				player_hp_bar.value = ps.current_integrity
			if player_hp_label:
				player_hp_label.text = "%d / %d" % [ps.current_integrity, ps.max_integrity]
	
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
		if enemy_hp_label:
			enemy_hp_label.text = "%d / %d" % [hp, max_hp_val]

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

#endregion
#region Timing Minigame

## Called when combat manager requests the timing minigame
func _on_timing_minigame_requested(command: CommandParser.CommandResult, difficulty: float) -> void:
	if not timing_minigame:
		# Fallback: if no minigame, complete with normal hit
		if combat_manager and combat_manager.has_method("apply_timing_result"):
			combat_manager.apply_timing_result(1, 1.0, false)
		return
	
	# Print message in terminal
	_print_terminal("\n[color=#f2e066]⚔️ TIMING CHALLENGE! Press SPACE at the right moment![/color]\n")
	_print_terminal("[color=#aaaaaa]Command: %s[/color]\n" % command.raw_input)
	
	# Disable input while timing
	if command_input:
		command_input.editable = false
	
	# Update turn indicator
	if turn_indicator:
		turn_indicator.text = "[ TIMING! ]"
	
	# Store that this is combat timing
	_current_timing_context = "combat"
	
	# Start the timing minigame
	timing_minigame.start_timing(TimingMinigame.TimingContext.COMBAT, difficulty)

## Start dependency resolver minigame for puzzle commands
func _start_puzzle_minigame(_difficulty: float) -> void:
	if not dependency_minigame:
		# Fallback: if no minigame, apply with normal success
		_apply_puzzle_timing_result(1, 0.7)
		return

	# Print message in terminal
	_print_terminal("\n[color=#f2e066]🔧 LINK PUZZLE STARTED[/color]\n")
	_print_terminal("[color=#aaaaaa]Make a full green path from Kernel to App.[/color]\n")

	# Disable command input while puzzle minigame is active
	if command_input:
		command_input.editable = false

	# Update turn indicator
	if turn_indicator:
		turn_indicator.text = "[ PUZZLE CHALLENGE ]"

	# Mark pending puzzle resolution and open minigame
	_current_timing_context = "puzzle"
	_puzzle_minigame_pending = true
	_set_terminal_for_dependency_mode(true)
	dependency_minigame.open_minigame()

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

## Apply timing result to puzzle
func _apply_puzzle_timing_result(zone: int, success_chance: float) -> void:
	if enemy_controller and enemy_controller.has_method("apply_puzzle_timing_result"):
		var result = enemy_controller.apply_puzzle_timing_result(zone, success_chance)
		if result is Dictionary:
			if result.get("message", "") != "":
				_print_terminal("[color=#66f266]%s[/color]\n" % _simplify_puzzle_message(str(result.message)))
			if result.get("mode_changed", false):
				_update_mode_display()
			if result.get("encounter_ended", false):
				await get_tree().create_timer(2.0).timeout
				_force_close_and_cleanup()
		_update_hp_displays()

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
	_set_terminal_for_dependency_mode(false)

	if success:
		_print_terminal("[color=#66f266]Puzzle solved![/color]\n")
		_apply_puzzle_timing_result(2, 1.0)
	else:
		_print_terminal("[color=#e65959]Puzzle failed.[/color]\n")
		_apply_puzzle_timing_result(0, 0.0)

func _on_dependency_resolver_closed() -> void:
	_set_terminal_for_dependency_mode(false)

	# If the puzzle was pending and player closed the minigame, treat as failed attempt.
	if _puzzle_minigame_pending:
		_puzzle_minigame_pending = false
		_print_terminal("[color=#aaaaaa]Puzzle closed.[/color]\n")
		_apply_puzzle_timing_result(0, 0.0)

	# Ensure terminal input is restored after close.
	if command_input:
		command_input.editable = true
		command_input.grab_focus()
	if turn_indicator:
		turn_indicator.text = "[ AWAITING INPUT ]"

func _set_terminal_for_dependency_mode(active: bool) -> void:
	var terminal_container := get_node_or_null("TerminalContainer") as CanvasItem
	var status_panel_node := get_node_or_null("StatusPanel") as CanvasItem
	var crt_overlay := get_node_or_null("CRTEffectOverlay") as CanvasItem

	if terminal_container:
		terminal_container.visible = not active
	if status_panel_node:
		status_panel_node.visible = not active
	if crt_overlay:
		crt_overlay.visible = not active

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
	
	#endregion
