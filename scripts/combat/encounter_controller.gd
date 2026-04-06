# encounter_controller.gd
# Main controller that orchestrates combat, puzzle, and dialogue systems
# Attach to NPCs or trigger zones to start encounters
extends Node
class_name EncounterController

#region Signals
signal encounter_started(encounter_type: String)
signal encounter_ended(result: String)
signal state_changed(new_state: String)
#endregion

#region Configuration
@export_group("Encounter Setup")
@export var encounter_id: String = "lost_file"
@export var auto_start: bool = false
@export var combat_ui_scene: PackedScene

@export_group("Enemy Configuration")
@export var enemy_script: Script  # LostFileEnemy or similar
#endregion

#region Runtime References
var combat_manager: TurnCombatManager
var combat_ui: Control  # CombatTerminalUI - type not available at compile time
var enemy_controller: Node
var is_active: bool = false
var _encounter_resolved: bool = false
#endregion

func _ready() -> void:
	# Create combat manager
	combat_manager = TurnCombatManager.new()
	add_child(combat_manager)
	if combat_manager.has_signal("combat_ended") and not combat_manager.combat_ended.is_connected(_on_combat_manager_ended):
		combat_manager.combat_ended.connect(_on_combat_manager_ended)
	
	# Load combat UI
	if combat_ui_scene:
		combat_ui = combat_ui_scene.instantiate() as Control
	else:
		# Try loading default
		var default_path := "res://Scenes/combat/combat_terminal_ui.tscn"
		if ResourceLoader.exists(default_path):
			var scene := load(default_path) as PackedScene
			combat_ui = scene.instantiate() as Control
	
	if combat_ui:
		# Add to CanvasLayer for UI
		var canvas := CanvasLayer.new()
		canvas.layer = 10
		add_child(canvas)
		canvas.add_child(combat_ui)
		combat_ui.hide()
	
	# Create enemy controller based on encounter_id
	_create_enemy_controller()
	
	if auto_start:
		start_encounter()

func _create_enemy_controller() -> void:
	match encounter_id:
		"evil_tux":
			enemy_controller = EvilTuxEnemy.new()
			add_child(enemy_controller)
			enemy_controller.encounter_ended.connect(_on_encounter_ended)
		"sage":
			enemy_controller = SageEnemy.new()
			add_child(enemy_controller)
			enemy_controller.encounter_ended.connect(_on_encounter_ended)
		"lost_file":
			enemy_controller = LostFileEnemy.new()
			add_child(enemy_controller)
			
			# Connect signals
			enemy_controller.encounter_ended.connect(_on_encounter_ended)
		"broken_link":
			enemy_controller = BrokenLinkEnemy.new()
			add_child(enemy_controller)
			
			# Connect signals
			enemy_controller.encounter_ended.connect(_on_encounter_ended)
		"hardware_ghost":
			enemy_controller = HardwareGhostEnemy.new()
			add_child(enemy_controller)
			enemy_controller.encounter_ended.connect(_on_encounter_ended)
		"driver_remnant":
			enemy_controller = DriverRemnantEnemy.new()
			add_child(enemy_controller)
			enemy_controller.encounter_ended.connect(_on_encounter_ended)
		"printer_beast":
			enemy_controller = PrinterBeastEnemy.new()
			add_child(enemy_controller)
			enemy_controller.encounter_ended.connect(_on_encounter_ended)

## Start the encounter
func start_encounter() -> void:
	if is_active:
		return
	
	is_active = true
	_encounter_resolved = false
	encounter_started.emit(encounter_id)
	
	# Check if we should start in puzzle mode or combat mode
	var start_in_puzzle: bool = has_meta("start_in_puzzle") and get_meta("start_in_puzzle") == true
	var start_in_combat: bool = has_meta("start_in_combat") and get_meta("start_in_combat") == true
	
	# Check if player previously fled combat with this enemy - restore has_attacked state
	if enemy_controller and "enemy_name" in enemy_controller:
		var npc_name = enemy_controller.enemy_name
		var combat_state_key := _combat_state_meta_key(npc_name)
		var saved_state = SceneManager.get_meta(combat_state_key) if SceneManager.has_meta(combat_state_key) else null
		if saved_state and saved_state is Dictionary:
			if saved_state.get("has_attacked", false):
				enemy_controller.has_attacked = true
				start_in_combat = true  # Force combat mode since they attacked before
	
	# Setup and show UI
	if combat_ui and enemy_controller:
		combat_ui.setup_combat(combat_manager, enemy_controller)
		combat_ui.open_combat_ui()
		enemy_controller.start_encounter(combat_manager)
		
		# If starting in puzzle mode, transition immediately
		if start_in_puzzle and enemy_controller.has_method("_transition_to_puzzle"):
			# Wait a frame for everything to initialize
			await get_tree().process_frame
			enemy_controller._transition_to_puzzle()
			# Update the UI mode display
			if combat_ui.has_method("_update_mode_display"):
				combat_ui._update_mode_display()
			# Play puzzle terminal music
			if SceneManager:
				SceneManager.play_music_for_key("puzzle_terminal")
		# If starting in combat mode (player fled before), transition immediately
		elif start_in_combat and enemy_controller.has_method("_transition_to_combat"):
			await get_tree().process_frame
			enemy_controller._transition_to_combat()
			if combat_ui.has_method("_update_mode_display"):
				combat_ui._update_mode_display()
			# Play combat terminal music
			if SceneManager:
				SceneManager.play_music_for_key("combat_terminal")
			# Show resumption message
			if combat_ui and combat_ui.has_method("_print_terminal"):
				combat_ui._print_terminal("\n[color=#f2e066]The enemy recognizes you from before![/color]\n")
				combat_ui._print_terminal("[color=#f2e066]Combat resumes immediately.[/color]\n\n")
	
	state_changed.emit("started")

## Called when encounter ends
func _on_encounter_ended(method: String) -> void:
	if _encounter_resolved:
		return
	_encounter_resolved = true
	is_active = false
	if method == "puzzle_solved":
		_award_puzzle_data_bits()
	
	# Clear the fled_combat state since encounter is now properly resolved
	if enemy_controller and "enemy_name" in enemy_controller:
		var npc_name = enemy_controller.enemy_name
		# Only clear if it was "fled_combat", don't overwrite other states
		if SceneManager.npc_states.get(npc_name, "") == "fled_combat":
			# Set appropriate state based on how encounter ended
			if method == "puzzle_solved":
				SceneManager.npc_states[npc_name] = "helped"
			elif method == "combat_victory":
				SceneManager.npc_states[npc_name] = "defeated"
			else:
				SceneManager.npc_states[npc_name] = "neutral"
		# Clear saved combat state
		var combat_state_key := _combat_state_meta_key(npc_name)
		if SceneManager.has_meta(combat_state_key):
			SceneManager.remove_meta(combat_state_key)
	
	# Close UI after delay
	await get_tree().create_timer(2.0).timeout
	
	if combat_ui:
		combat_ui.close_combat_ui()
	
	encounter_ended.emit(method)
	state_changed.emit("ended")
	
	# Clean up the encounter controller itself
	queue_free()

func _award_puzzle_data_bits() -> void:
	if SceneManager == null or enemy_controller == null:
		return

	var puzzle_data: Variant = enemy_controller.get("puzzle_data")
	if puzzle_data == null:
		return

	var reward: Dictionary = {}
	if puzzle_data is Object and "reward" in puzzle_data:
		reward = puzzle_data.reward
	elif puzzle_data is Dictionary:
		reward = puzzle_data.get("reward", {})
	if reward.is_empty():
		return

	var base_bits := maxi(0, int(reward.get("data_bits", 0)))
	var bonus_per_critical := maxi(0, int(reward.get("data_bits_per_critical", 0)))
	var critical_hits := 0
	if puzzle_data is Object and "custom_data" in puzzle_data and puzzle_data.custom_data is Dictionary:
		critical_hits = int(puzzle_data.custom_data.get("timing_critical_hits", 0))
	elif puzzle_data is Dictionary:
		var custom_data: Dictionary = puzzle_data.get("custom_data", {})
		critical_hits = int(custom_data.get("timing_critical_hits", 0))

	var total_bits := base_bits + (critical_hits * bonus_per_critical)
	if total_bits <= 0:
		return

	var enemy_name := "the puzzle"
	if enemy_controller and "enemy_name" in enemy_controller:
		enemy_name = str(enemy_controller.enemy_name)
	SceneManager.award_data_bits(total_bits, "puzzle:%s" % enemy_name.to_lower().replace(" ", "_"))
	if combat_ui and combat_ui.has_method("_print_terminal"):
		if critical_hits > 0 and bonus_per_critical > 0:
			combat_ui._print_terminal("[color=#66f266]Recovered %d Data Bits from %s (%d base + %d from %d critical timing hit%s).[/color]\n" % [total_bits, enemy_name, base_bits, critical_hits * bonus_per_critical, critical_hits, "s" if critical_hits != 1 else ""])
		else:
			combat_ui._print_terminal("[color=#66f266]Recovered %d Data Bits from %s.[/color]\n" % [total_bits, enemy_name])

func _on_combat_manager_ended(victory: bool, _enemy_data) -> void:
	if _encounter_resolved or not victory:
		return

	if enemy_controller and enemy_controller.has_method("_resolve_encounter"):
		enemy_controller.call("_resolve_encounter", "combat_victory")
	elif enemy_controller and enemy_controller.has_signal("encounter_ended"):
		enemy_controller.encounter_ended.emit("combat_victory")

## Reset encounter for replay
func reset_encounter() -> void:
	is_active = false
	if enemy_controller:
		enemy_controller.queue_free()
	_create_enemy_controller()

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
