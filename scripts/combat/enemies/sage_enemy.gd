# sage_enemy.gd
# Dedicated Sage encounter profile for Bios Vault.
extends PrinterBeastEnemy
class_name SageEnemy

@export_group("Sage Stats")
@export var sage_enemy_name: String = "Sage"
@export var sage_max_hp: int = 140
@export var sage_attack_power: int = 20
@export var sage_defense: int = 9
@export var sage_speed: int = 8

func _load_dialogue_files() -> void:
	intro_lines = [
		"So, you chose force over understanding.",
		"Let your intent be measured in battle.",
		"[Type 'attack' to continue.]",
	]
	puzzle_offer_lines = []
	defeat_lines = [
		"...You prevailed. Walk forward, and own what you chose.",
	]
	puzzle_success_lines = []

func _initialize_enemy_data() -> void:
	enemy_name = sage_enemy_name
	enemy_data = TurnCombatManager.EnemyData.new()
	enemy_data.id = "sage"
	enemy_data.display_name = sage_enemy_name
	enemy_data.max_hp = sage_max_hp
	enemy_data.current_hp = sage_max_hp
	enemy_data.attack_power = sage_attack_power
	enemy_data.defense = sage_defense
	enemy_data.speed = sage_speed
	enemy_data.weakness = "attack"
	enemy_data.resistance = "defend"
	enemy_data.abilities = ["logic_lash", "judgment_burst", "echo_pulse"]
	enemy_data.description = "The Sage manifests pure judgment, forcing intent into action."
	enemy_data.defeat_reward = {
		"npc_name": "Sage",
		"npc_state": "defeated",
		"karma_change": "neutral",
	}

func _initialize_puzzle_data() -> void:
	# Sage fight is combat-only for this story beat.
	puzzle_data = PuzzleStateHandler.create_printer_beast_puzzle()

func _start_quest_if_needed() -> void:
	# No quest side effects for Sage combat.
	pass

func _maybe_complete_drivers_den_quest() -> void:
	# No quest side effects for Sage combat.
	pass

func _handle_dialogue_input(input: String) -> Dictionary:
	var result := {"handled": true, "message": "", "mode_changed": false, "encounter_ended": false}

	if input == "continue" or input == "next" or input == "" or input == "attack" or input == "fight":
		has_attacked = true
		_transition_to_combat()
		result.mode_changed = true
		result.message = "[Combat initiated - Sage closes in.]"
	else:
		result.message = "Type 'attack' to continue."

	return result

func _handle_patch_in_combat() -> String:
	var damage := 30
	enemy_data.current_hp -= damage

	var msg := "[Your command lands cleanly.]\n"
	msg += "Sage takes %d damage!\n" % damage

	if enemy_data.current_hp <= 0:
		_resolve_encounter("combat_victory")
		msg += "\n"
		for line in defeat_lines:
			msg += line + "\n"
	else:
		msg += "Sage HP: %d/%d" % [enemy_data.current_hp, enemy_data.max_hp]

	return msg

func _resolve_encounter(method: String) -> void:
	encounter_result = method
	current_mode = EncounterMode.RESOLVED

	match method:
		"puzzle_solved":
			if SceneManager:
				SceneManager.set_meta("bios_vault_sage_quiz_passed", true)
		"combat_victory":
			if SceneManager:
				SceneManager.npc_states["Sage"] = "defeated"
				SceneManager.set_meta("bios_vault_sage_defeated", true)
			_hide_npc_after_defeat("Sage")
		"fled":
			pass

	encounter_ended.emit(method)
	mode_changed.emit(EncounterMode.RESOLVED)
