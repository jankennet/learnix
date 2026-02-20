# hardware_ghost_enemy.gd
# The "Hardware Ghost" enemy - a regretful driver phantom
extends Node
class_name HardwareGhostEnemy

#region Signals
signal encounter_started()
signal encounter_ended(method: String)
signal dialogue_requested(lines: Array)
signal mode_changed(mode: EncounterMode)
#endregion

#region Enums
enum EncounterMode {
	DIALOGUE,
	COMBAT,
	PUZZLE,
	RESOLVED,
}
#endregion

#region Configuration
@export_group("Hardware Ghost Stats")
@export var enemy_name: String = "Hardware Ghost"
@export var max_hp: int = 85
@export var attack_power: int = 11
@export var defense: int = 5
@export var speed: int = 8

@export_group("Encounter Settings")
@export var allow_puzzle_solution: bool = true
@export var puzzle_unlocks_at_hp_percent: float = 70.0
@export var hostile_start: bool = false

@export_group("Dialogue")
@export var dialogue_json_path: String = "res://dialogues/enemies/hardware_ghost.json"
@export var dialogue_resource: Resource = null

var intro_lines: Array = []
var puzzle_offer_lines: Array = []
var defeat_lines: Array = []
var puzzle_success_lines: Array = []
#endregion

#region Dialogue Loading
func _load_dialogue_files() -> void:
	if dialogue_resource:
		if typeof(dialogue_resource) == TYPE_DICTIONARY:
			var rd_dict = dialogue_resource
			intro_lines = rd_dict["intro"] if rd_dict.has("intro") else []
			puzzle_offer_lines = rd_dict["offer"] if rd_dict.has("offer") else []
			defeat_lines = rd_dict["defeat"] if rd_dict.has("defeat") else []
			puzzle_success_lines = rd_dict["success"] if rd_dict.has("success") else []
			return
		elif dialogue_resource.has_method("to_dict"):
			var rd2 = dialogue_resource.to_dict()
			if typeof(rd2) == TYPE_DICTIONARY:
				var rd2_dict = rd2
				intro_lines = rd2_dict["intro"] if rd2_dict.has("intro") else []
				puzzle_offer_lines = rd2_dict["offer"] if rd2_dict.has("offer") else []
				defeat_lines = rd2_dict["defeat"] if rd2_dict.has("defeat") else []
				puzzle_success_lines = rd2_dict["success"] if rd2_dict.has("success") else []
				return

	if FileAccess.file_exists(dialogue_json_path):
		var f := FileAccess.open(dialogue_json_path, FileAccess.READ)
		if f:
			var text := f.get_as_text()
			f.close()
			var j := JSON.new()
			var parsed = j.parse(text)
			if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY:
				var dd := parsed.result as Dictionary
				intro_lines = dd["intro"] if dd.has("intro") else []
				puzzle_offer_lines = dd["offer"] if dd.has("offer") else []
				defeat_lines = dd["defeat"] if dd.has("defeat") else []
				puzzle_success_lines = dd["success"] if dd.has("success") else []
				return

	intro_lines = [
		"[whisper] Legacy device... no longer recognized.",
		"I am a driver from a machine long gone.",
		"The logs repeat. The bus never settles.",
		"Will you quiet the echoes... or sever them?",
	]

	puzzle_offer_lines = [
		"Listen to the logs. Follow the repair sequence.",
		"Trace the legacy driver table and calm the echo.",
		"[TYPE 'puzzle' to stabilize the ghost, or continue fighting]",
	]

	defeat_lines = [
		"[static fades] The bus... goes silent...",
		"A driver finally ends its loop.",
	]

	puzzle_success_lines = [
		"[soft tone] The logs settle.",
		"The legacy driver can finally rest.",
	]
#endregion

#region State
var current_mode: EncounterMode = EncounterMode.DIALOGUE
var enemy_data: TurnCombatManager.EnemyData
var puzzle_data: PuzzleStateHandler.PuzzleData
var combat_manager: TurnCombatManager
var dialogue_index: int = 0
var puzzle_offered: bool = false
var encounter_result: String = ""
var has_attacked: bool = false
#endregion

#region Initialization
func _ready() -> void:
	_load_dialogue_files()
	_initialize_enemy_data()
	_initialize_puzzle_data()

func _initialize_enemy_data() -> void:
	enemy_data = TurnCombatManager.EnemyData.new()
	enemy_data.id = "hardware_ghost"
	enemy_data.display_name = enemy_name
	enemy_data.max_hp = max_hp
	enemy_data.current_hp = max_hp
	enemy_data.attack_power = attack_power
	enemy_data.defense = defense
	enemy_data.speed = speed
	enemy_data.weakness = "debug"
	enemy_data.resistance = "delete"
	enemy_data.abilities = ["echo", "interrupt", "whisper"]
	enemy_data.description = "A regretful phantom of legacy drivers. It whispers logs and lashes out if threatened."
	enemy_data.defeat_reward = {
		"npc_name": "Hardware Ghost",
		"npc_state": "defeated",
		"karma_change": "neutral",
	}

func _initialize_puzzle_data() -> void:
	puzzle_data = PuzzleStateHandler.create_hardware_ghost_puzzle()
#endregion

#region Encounter Flow
func start_encounter(cm: TurnCombatManager) -> void:
	combat_manager = cm
	current_mode = EncounterMode.DIALOGUE
	dialogue_index = 0
	puzzle_offered = false
	has_attacked = false
	_start_quest_if_needed()

	encounter_started.emit()
	_show_intro_dialogue()

func process_input(raw_input: String) -> Dictionary:
	var result := {
		"handled": false,
		"message": "",
		"mode_changed": false,
		"encounter_ended": false,
	}

	var input := raw_input.strip_edges().to_lower()

	match current_mode:
		EncounterMode.DIALOGUE:
			result = _handle_dialogue_input(input)
		EncounterMode.COMBAT:
			result = _handle_combat_input(input)
		EncounterMode.PUZZLE:
			result = _handle_puzzle_input(input)
		EncounterMode.RESOLVED:
			result.message = "Encounter already resolved."
			result.handled = true

	return result

func _show_intro_dialogue() -> void:
	dialogue_requested.emit(intro_lines)

func _handle_dialogue_input(input: String) -> Dictionary:
	var result := {"handled": true, "message": "", "mode_changed": false, "encounter_ended": false}

	if input == "continue" or input == "next" or input == "":
		dialogue_index += 1
		if dialogue_index >= intro_lines.size():
			result.message = "[The Hardware Ghost awaits your response...]\n"
			result.message += "[Type 'puzzle' to calm it, or 'attack' to sever it]"
		else:
			result.message = intro_lines[dialogue_index]
			if dialogue_index < intro_lines.size() - 1:
				result.message += "\n[Type 'continue' to proceed, 'puzzle' to calm it, or 'attack' to sever it]"
			else:
				result.message += "\n[Type 'puzzle' to calm it, or 'attack' to sever it]"
	elif input == "attack" or input == "fight" or input == "threaten":
		has_attacked = true
		_transition_to_combat()
		result.mode_changed = true
		result.message = "[Combat initiated - the ghost reacts to your aggression]"
	elif input == "puzzle" or input == "help" or input == "listen" or input == "calm":
		if allow_puzzle_solution:
			_transition_to_puzzle()
			result.mode_changed = true
			result.message = "[Puzzle mode initiated - you try to calm the legacy logs]"
		else:
			result.message = "The ghost cannot settle right now..."
	else:
		result.message = intro_lines[mini(dialogue_index, intro_lines.size() - 1)]
		result.message += "\n[Type 'continue' to proceed, 'puzzle' to calm it, or 'attack' to sever it]"

	return result

func _handle_combat_input(input: String) -> Dictionary:
	var result := {"handled": true, "message": "", "mode_changed": false, "encounter_ended": false}

	if input == "puzzle" or input == "help" or input == "listen":
		if has_attacked:
			result.message = "[You've already threatened it. The ghost refuses to calm down.]"
			return result
		if allow_puzzle_solution and _can_offer_puzzle():
			_transition_to_puzzle()
			result.mode_changed = true
			result.message = "[Puzzle mode initiated - you try to calm the legacy logs]"
			return result
		else:
			result.message = "[Puzzle mode not available yet. Continue the encounter.]"
			return result

	var cmd := CommandParser.parse(input)
	if not cmd.success:
		result.message = cmd.error_message
		return result

	if cmd.command_type == CommandParser.CommandType.ATTACK or cmd.command_type == CommandParser.CommandType.DELETE:
		has_attacked = true

	if cmd.command_type == CommandParser.CommandType.DEBUG:
		result.message = _handle_debug_in_combat()
		return result

	if not puzzle_offered and not has_attacked and _should_offer_puzzle():
		puzzle_offered = true
		result.message = "[The ghost's static softens...]\n"
		for line in puzzle_offer_lines:
			result.message += line + "\n"
		result.message += "\n[Type 'puzzle' to calm it, or continue fighting]"
		return result

	if combat_manager:
		combat_manager.process_input(input)
		result.handled = true

	return result

func _handle_puzzle_input(input: String) -> Dictionary:
	var result := {
		"handled": true,
		"message": "",
		"mode_changed": false,
		"encounter_ended": false,
		"requires_timing": false,
		"timing_difficulty": 1.0,
		"timing_context": "puzzle",
		"pending_puzzle_result": null,
		"pending_command": null
	}

	if input == "fight" or input == "combat" or input == "attack":
		_transition_to_combat()
		result.mode_changed = true
		result.message = "[Returning to combat]"
		return result

	var cmd := CommandParser.parse(input)
	if not cmd.success:
		result.message = cmd.error_message
		return result

	var puzzle_result := PuzzleStateHandler.process_puzzle_command(puzzle_data, cmd)
	result.message = puzzle_result.message

	if puzzle_result.requires_timing:
		result.requires_timing = true
		result.timing_difficulty = puzzle_result.timing_difficulty
		result.pending_puzzle_result = puzzle_result
		result.pending_command = cmd
		_pending_puzzle_timing = {
			"puzzle_result": puzzle_result,
			"command": cmd
		}
		return result

	if puzzle_result.puzzle_complete:
		_resolve_encounter("puzzle_solved")
		result.encounter_ended = true
		result.message += "\n\n"
		for line in puzzle_success_lines:
			result.message += line + "\n"
	elif puzzle_result.puzzle_failed:
		result.message += "\n[Puzzle failed - returning to combat]"
		_transition_to_combat()
		result.mode_changed = true

	return result

var _pending_puzzle_timing: Dictionary = {}

func apply_puzzle_timing_result(zone: int, success_chance: float) -> Dictionary:
	var result := {"message": "", "encounter_ended": false, "mode_changed": false}

	if _pending_puzzle_timing.is_empty():
		result.message = "No pending puzzle action."
		return result

	var pending_result: PuzzleStateHandler.PuzzleResult = _pending_puzzle_timing.get("puzzle_result")
	if pending_result:
		var final_result := PuzzleStateHandler.apply_timing_to_puzzle(
			puzzle_data,
			pending_result,
			zone,
			success_chance
		)
		result.message = final_result.message

		if final_result.puzzle_complete:
			_resolve_encounter("puzzle_solved")
			result.encounter_ended = true
			result.message += "\n\n"
			for line in puzzle_success_lines:
				result.message += line + "\n"
		elif final_result.puzzle_failed:
			result.message += "\n[Puzzle failed - returning to combat]"
			_transition_to_combat()
			result.mode_changed = true

	_pending_puzzle_timing.clear()
	return result

func _handle_debug_in_combat() -> String:
	var damage := 26
	enemy_data.current_hp -= damage

	var msg := "[DEBUG command calms the ghost's loop!]\n"
	msg += "Legacy traces resolve, dealing %d integrity damage!\n" % damage

	if enemy_data.current_hp <= 0:
		_resolve_encounter("combat_victory")
		msg += "\n"
		for line in defeat_lines:
			msg += line + "\n"
	else:
		msg += "Hardware Ghost HP: %d/%d" % [enemy_data.current_hp, enemy_data.max_hp]

	return msg
#endregion

#region Mode Transitions
func _transition_to_combat() -> void:
	current_mode = EncounterMode.COMBAT
	mode_changed.emit(EncounterMode.COMBAT)
	if combat_manager:
		combat_manager.start_combat(enemy_data)

func _transition_to_puzzle() -> void:
	current_mode = EncounterMode.PUZZLE
	mode_changed.emit(EncounterMode.PUZZLE)
	var intro := puzzle_data.description
	dialogue_requested.emit([intro])

func _can_offer_puzzle() -> bool:
	if has_attacked:
		return false
	return allow_puzzle_solution and puzzle_data.state != PuzzleStateHandler.PuzzleState.FAILED

func _should_offer_puzzle() -> bool:
	if not allow_puzzle_solution:
		return false
	if has_attacked:
		return false
	var hp_percent := (float(enemy_data.current_hp) / float(enemy_data.max_hp)) * 100.0
	return hp_percent <= puzzle_unlocks_at_hp_percent
#endregion

#region Resolution and Quest Hooks
func _resolve_encounter(method: String) -> void:
	encounter_result = method
	current_mode = EncounterMode.RESOLVED

	match method:
		"puzzle_solved":
			SceneManager.npc_states["Hardware Ghost"] = "helped"
			SceneManager.met_hardware_ghost = true
			if puzzle_data.reward.has("karma_change"):
				SceneManager.player_karma = puzzle_data.reward.karma_change
			_maybe_complete_drivers_den_quest()
		"combat_victory":
			SceneManager.npc_states["Hardware Ghost"] = "defeated"
			SceneManager.met_hardware_ghost = true
			_maybe_complete_drivers_den_quest()
		"fled":
			pass

	encounter_ended.emit(method)
	mode_changed.emit(EncounterMode.RESOLVED)

func _start_quest_if_needed() -> void:
	if SceneManager and SceneManager.quest_manager:
		var quest = SceneManager.quest_manager.get_quest("drivers_den_cleanup")
		if quest and quest.status == "inactive":
			SceneManager.quest_manager.start_quest("drivers_den_cleanup")

func _maybe_complete_drivers_den_quest() -> void:
	if not SceneManager or not SceneManager.quest_manager:
		return
	if SceneManager.driver_remnant_defeated and SceneManager.proficiency_key_printer:
		var quest = SceneManager.quest_manager.get_quest("drivers_den_cleanup")
		if quest and quest.status == "active":
			SceneManager.quest_manager.complete_quest("drivers_den_cleanup")
#endregion
