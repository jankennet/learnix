# evil_tux_enemy.gd
# Final boss encounter profile for Evil Tux.
extends PrinterBeastEnemy
class_name EvilTuxEnemy

@export_group("Evil Tux Stats")
@export var evil_tux_name: String = "Evil Tux"
@export var evil_tux_max_hp: int = 200
@export var evil_tux_attack_power: int = 18
@export var evil_tux_defense: int = 10
@export var evil_tux_speed: int = 12

func _load_dialogue_files() -> void:
	intro_lines = []
	puzzle_offer_lines = [
		"The shadow in Tux's shell twitches.",
		"If you can still build a stable path, you might survive this.",
		"[TYPE 'puzzle' to try the dependency challenge, or keep fighting]",
	]
	defeat_lines = [
		"[signal fracture] The voice in the shell cuts loose.",
		"Evil Tux staggers, but the other presence does not leave quietly.",
	]
	puzzle_success_lines = [
		"[system fault] The hostile presence destabilizes.",
		"The shell is still standing, but the grip has loosened.",
	]

func _initialize_enemy_data() -> void:
	enemy_name = evil_tux_name
	enemy_data = TurnCombatManager.EnemyData.new()
	enemy_data.id = "evil_tux"
	enemy_data.display_name = evil_tux_name
	enemy_data.max_hp = evil_tux_max_hp
	enemy_data.current_hp = evil_tux_max_hp
	enemy_data.attack_power = evil_tux_attack_power
	enemy_data.defense = evil_tux_defense
	enemy_data.speed = evil_tux_speed
	enemy_data.weakness = "restore"
	enemy_data.resistance = "delete"
	enemy_data.abilities = ["attack", "corrupt", "scatter"]
	enemy_data.description = "A Tux shell held together by something old, cold, and angry."
	enemy_data.defeat_reward = {
		"npc_name": "Evil Tux",
		"npc_state": "defeated",
		"karma_change": "bad",
	}

func _initialize_puzzle_data() -> void:
	puzzle_data = PuzzleStateHandler.create_printer_beast_puzzle()
	if puzzle_data and "custom_data" in puzzle_data:
		puzzle_data.custom_data["boss_mode"] = true

func _start_quest_if_needed() -> void:
	pass

func _maybe_complete_drivers_den_quest() -> void:
	pass

func _resolve_encounter(method: String) -> void:
	encounter_result = method
	current_mode = EncounterMode.RESOLVED

	match method:
		"puzzle_solved":
			if SceneManager:
				SceneManager.npc_states["Evil Tux"] = "defeated"
		"combat_victory":
			if SceneManager:
				SceneManager.npc_states["Evil Tux"] = "defeated"
		"fled":
			pass

	encounter_ended.emit(method)
	mode_changed.emit(EncounterMode.RESOLVED)
