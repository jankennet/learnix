# driver_remnant_enemy.gd
# The "Driver Remnant" enemy - aggressive, unstable driver shard
extends Node
class_name DriverRemnantEnemy

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
@export_group("Driver Remnant Stats")
@export var enemy_name: String = "Driver Remnant"
@export var max_hp: int = 95
@export var attack_power: int = 15
@export var defense: int = 6
@export var speed: int = 10

@export_group("Encounter Settings")
@export var allow_puzzle_solution: bool = true
@export var puzzle_unlocks_at_hp_percent: float = 55.0
@export var hostile_start: bool = true

@export_group("Dialogue")
@export var dialogue_json_path: String = "res://dialogues/enemies/driver_remnant.json"
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
		"[volatile burst] INVALID! INVALID!",
		"Unmapped calls. Unstable memory.",
		"You do not belong in this address space.",
	]

	puzzle_offer_lines = [
		"The remnant spikes. It can be isolated.",
		"Trace the interrupt line and terminate the rogue thread.",
		"[TYPE 'puzzle' to isolate it, or continue fighting]",
	]

	defeat_lines = [
		"[screech] Access revoked...",
		"The rogue thread collapses.",
	]

	puzzle_success_lines = [
		"[stabilized] The remnant is contained.",
		"The interrupt table settles.",
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
	enemy_data.id = "driver_remnant"
	enemy_data.display_name = enemy_name
	enemy_data.max_hp = max_hp
	enemy_data.current_hp = max_hp
	enemy_data.attack_power = attack_power
	enemy_data.defense = defense
	enemy_data.speed = speed
	enemy_data.weakness = "kill"
	enemy_data.resistance = "restore"
	enemy_data.abilities = ["spike", "overrun", "panic"]
	enemy_data.description = "A rare, hostile remnant of old drivers. Aggressive and unpredictable."
	enemy_data.defeat_reward = {
		"npc_name": "Driver Remnant",
		"npc_state": "defeated",
		"karma_change": "neutral",
	}

func _initialize_puzzle_data() -> void:
	puzzle_data = PuzzleStateHandler.create_driver_remnant_puzzle()
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
			result.message = "[The Driver Remnant crackles, awaiting your decision...]\n"
			result.message += "[Type 'attack' to fight, or 'puzzle' to isolate it]"
		else:
			result.message = intro_lines[dialogue_index]
			if dialogue_index < intro_lines.size() - 1:
				result.message += "\n[Type 'continue' to proceed, 'attack' to fight, or 'puzzle' to isolate it]"
			else:
				result.message += "\n[Type 'attack' to fight, or 'puzzle' to isolate it]"
	elif input == "attack" or input == "fight":
		has_attacked = true
		_transition_to_combat()
		result.mode_changed = true
		result.message = "[Combat initiated - the remnant lashes out]"
	elif input == "puzzle" or input == "help" or input == "isolate":
		if allow_puzzle_solution:
			_transition_to_puzzle()
			result.mode_changed = true
			result.message = "[Puzzle mode initiated - you attempt to isolate the remnant]"
		else:
			result.message = "The remnant is too unstable to isolate right now..."
	else:
		result.message = intro_lines[mini(dialogue_index, intro_lines.size() - 1)]
		result.message += "\n[Type 'continue' to proceed, 'attack' to fight, or 'puzzle' to isolate it]"

	return result

func _handle_combat_input(input: String) -> Dictionary:
	var result := {"handled": true, "message": "", "mode_changed": false, "encounter_ended": false}

	if input == "puzzle" or input == "help" or input == "isolate" or input == "restore":
		if has_attacked:
			result.message = "[You've already chosen to fight. The remnant resists isolation.]"
			return result
		if allow_puzzle_solution and _can_offer_puzzle():
			_transition_to_puzzle()
			result.mode_changed = true
			result.message = "[Puzzle mode initiated - you attempt to isolate the remnant]"
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

	if cmd.command_type == CommandParser.CommandType.RESTORE:
		if has_attacked:
			result.message = "[You've already chosen to fight. The remnant resists isolation.]"
			return result
		if allow_puzzle_solution and _can_offer_puzzle():
			_transition_to_puzzle()
			result.mode_changed = true
			result.message = "[Puzzle mode initiated - you attempt to isolate the remnant]"
			return result
		result.message = "[Puzzle mode not available yet. Continue the encounter.]"
		return result

	if cmd.command_type == CommandParser.CommandType.KILL:
		has_attacked = true
		result.message = _handle_kill_in_combat()
		return result

	if not puzzle_offered and not has_attacked and _should_offer_puzzle():
		puzzle_offered = true
		result.message = "[The remnant's spikes waver...]\n"
		for line in puzzle_offer_lines:
			result.message += line + "\n"
		result.message += "\n[Type 'puzzle' to isolate it, or continue fighting]"
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

func _handle_kill_in_combat() -> String:
	var damage := 28
	enemy_data.current_hp -= damage

	var msg := "[KILL command destabilizes the remnant!]\n"
	msg += "The rogue thread buckles, taking %d integrity damage!\n" % damage

	if enemy_data.current_hp <= 0:
		_resolve_encounter("combat_victory")
		msg += "\n"
		for line in defeat_lines:
			msg += line + "\n"
	else:
		msg += "Driver Remnant HP: %d/%d" % [enemy_data.current_hp, enemy_data.max_hp]

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
			SceneManager.npc_states["Driver Remnant"] = "helped"
			SceneManager.driver_remnant_defeated = true
			SceneManager.met_driver_remnant = true
			# Driver Remnant grants a sudo token (not a proficiency key)
			if not SceneManager.sudo_token_driver_remnant:
				SceneManager.sudo_token_driver_remnant = true
				print("Driver Remnant: Granted sudo token")
			_maybe_complete_drivers_den_quest()
		"combat_victory":
			SceneManager.npc_states["Driver Remnant"] = "defeated"
			SceneManager.driver_remnant_defeated = true
			SceneManager.met_driver_remnant = true
			# Driver Remnant grants a sudo token (not a proficiency key)
			if not SceneManager.sudo_token_driver_remnant:
				SceneManager.sudo_token_driver_remnant = true
				print("Driver Remnant: Granted sudo token")
			_trigger_tux_defeat_dialogue("Driver Remnant")
			_hide_npc_after_defeat("Driver Remnant")
			_maybe_complete_drivers_den_quest()
		"fled":
			pass

	encounter_ended.emit(method)
	mode_changed.emit(EncounterMode.RESOLVED)

## Trigger Tux dialogue for NPC defeat
func _trigger_tux_defeat_dialogue(npc_name: String) -> void:
	var tux_ctrl = SceneManager.get_node_or_null("TuxDialogueController")
	if tux_ctrl and tux_ctrl.has_method("_handle_npc_defeated"):
		var defeat_flag_map := {
			"Driver Remnant": "driver_remnant_defeated",
		}
		var flag = defeat_flag_map.get(npc_name, "unknown")
		print("[DriverRemnant] Triggering Tux defeat dialogue for: %s" % npc_name)
		tux_ctrl.call("_handle_npc_defeated", flag)

## Hide NPC after being defeated
func _hide_npc_after_defeat(npc_name: String) -> void:
	var npc: Node = null
	for candidate in get_tree().get_nodes_in_group("npcs"):
		if candidate.name == npc_name or candidate.name.contains(npc_name.replace(" ", "")):
			npc = candidate
			break
	if npc and npc.has_method("_hide_self"):
		npc.call("_hide_self", true)
		print("[DriverRemnant] Hidden %s after defeat" % npc_name)

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
