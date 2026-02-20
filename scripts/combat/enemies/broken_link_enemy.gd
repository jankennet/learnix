# broken_link_enemy.gd
# The "Broken Link" enemy - a glitchy stub that can be repaired or defeated
# Theme: A missing path that loops in the Filesystem Forest with 404 pings
extends Node
class_name BrokenLinkEnemy

#region Signals
signal encounter_started()
signal encounter_ended(method: String)  # "combat_victory", "puzzle_solved", "fled"
signal dialogue_requested(lines: Array)
signal mode_changed(mode: EncounterMode)
#endregion

#region Enums
enum EncounterMode {
	DIALOGUE,    # Initial conversation
	COMBAT,      # Turn-based fighting
	PUZZLE,      # Link repair puzzle
	RESOLVED,    # Encounter complete
}
#endregion

#region Configuration
@export_group("Broken Link Stats")
@export var enemy_name: String = "Broken Link"
@export var max_hp: int = 90
@export var attack_power: int = 14
@export var defense: int = 6
@export var speed: int = 9

@export_group("Encounter Settings")
@export var allow_puzzle_solution: bool = true
@export var puzzle_unlocks_at_hp_percent: float = 45.0
@export var hostile_start: bool = true

@export_group("Dialogue")
@export var dialogue_json_path: String = "res://dialogues/enemies/broken_link.json"
@export var dialogue_resource: Resource = null

var intro_lines: Array = []
var puzzle_offer_lines: Array = []
var defeat_lines: Array = []
var puzzle_success_lines: Array = []
#endregion

#region Dialogue Loading
func _load_dialogue_files() -> void:
	# 1) Try a DialogueManager singleton
	if Engine.has_singleton("DialogueManager"):
		var dm = Engine.get_singleton("DialogueManager")
		if dm and dm.has_method("get_dialogue"):
			var d = dm.get_dialogue("broken_link")
			if typeof(d) == TYPE_DICTIONARY:
				intro_lines = d["intro"] if d.has("intro") else []
				puzzle_offer_lines = d["offer"] if d.has("offer") else []
				defeat_lines = d["defeat"] if d.has("defeat") else []
				puzzle_success_lines = d["success"] if d.has("success") else []
				return

	# 2) Try an exported Resource (dictionary-like)
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

	# 3) Try loading a JSON file
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

	# 4) Try parsing the project's .dialogue format
	var dlg_path := "res://dialogues/BrokenLink.dialogue"
	if ResourceLoader.exists(dlg_path):
		var fh := FileAccess.open(dlg_path, FileAccess.READ)
		if fh:
			var txt := fh.get_as_text()
			fh.close()
			var sections := _parse_simple_dialogue_format(txt)
			if sections.has("start"):
				intro_lines = sections.get("start", [])
			if sections.has("offer_puzzle"):
				puzzle_offer_lines = sections.get("offer_puzzle", [])
			if sections.has("puzzle_complete"):
				puzzle_success_lines = sections.get("puzzle_complete", [])
			if sections.has("combat_victory"):
				defeat_lines = sections.get("combat_victory", [])
			return

	# 5) Fallback to embedded defaults
	intro_lines = [
		"[404 ping] ...link... not found...",
		"I am a stub. A path to nowhere.",
		"Targets missing. Pointers corrupted.",
		"Do you repair... or sever?",
	]

	puzzle_offer_lines = [
		"You can fix the link... maybe.",
		"Scan me. Find the missing target.",
		"Reconnect the stub and patch the table.",
		"[TYPE 'puzzle' to attempt repair, or continue fighting]",
	]

	defeat_lines = [
		"[404 ping] signal lost...",
		"Fragmented key... only shards remain...",
		"The link collapses into dead pointers.",
	]

	puzzle_success_lines = [
		"[200 OK] link resolved.",
		"Pointers stabilized. Target restored.",
		"Take the Proficiency key...",
	]

func _parse_simple_dialogue_format(text: String) -> Dictionary:
	var lines := text.split("\n", false)
	var current_section := ""
	var sections := {}
	for raw_line in lines:
		var line := raw_line.strip_edges()
		if line.begins_with("~ "):
			var parts := line.substr(2).strip_edges()
			current_section = parts
			sections[current_section] = []
			continue
		if current_section == "":
			continue
		if line.find(":") != -1:
			var tokens := line.split(":", false)
			var speaker := tokens[0].strip_edges()
			var tail := tokens.slice(1, tokens.size())
			var rest := ""
			if tail.size() > 0:
				for i in range(tail.size()):
					if i > 0:
						rest += ":"
					rest += str(tail[i]).strip_edges()
			if speaker.to_lower().find("broken link") != -1 or speaker == "":
				sections[current_section].append(rest)
		else:
			if line != "" and not line.begins_with("-") and not line.begins_with("do "):
				sections[current_section].append(line)

	var out := {}
	if sections.has("start"):
		out["start"] = sections["start"]
	if sections.has("offer_puzzle"):
		out["offer_puzzle"] = sections["offer_puzzle"]
	if sections.has("puzzle_complete"):
		out["puzzle_complete"] = sections["puzzle_complete"]
	if sections.has("combat_victory"):
		out["combat_victory"] = sections["combat_victory"]
	if sections.has("offer") and not out.has("offer_puzzle"):
		out["offer_puzzle"] = sections["offer"]

	return out
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
	enemy_data.id = "broken_link"
	enemy_data.display_name = enemy_name
	enemy_data.max_hp = max_hp
	enemy_data.current_hp = max_hp
	enemy_data.attack_power = attack_power
	enemy_data.defense = defense
	enemy_data.speed = speed
	enemy_data.weakness = "connect"
	enemy_data.resistance = "delete"
	enemy_data.abilities = ["unlink", "glitch", "loop"]
	enemy_data.description = "A corrupted link stub looping through the Filesystem Forest. It emits 404 pings and lashes out when severed. It might be repaired instead of destroyed."
	enemy_data.defeat_reward = {
		"npc_name": "Broken Link",
		"npc_state": "defeated",
		"karma_change": "neutral",
	}

func _initialize_puzzle_data() -> void:
	puzzle_data = PuzzleStateHandler.create_broken_link_puzzle()
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
			result.message = "[The Broken Link flickers, awaiting your decision...]\n"
			result.message += "[Type 'attack' to fight, or 'help'/'puzzle' to repair it]"
		else:
			result.message = intro_lines[dialogue_index]
			if dialogue_index < intro_lines.size() - 1:
				result.message += "\n[Type 'continue' to proceed, 'attack' to fight, or 'help' to assist]"
			else:
				result.message += "\n[Type 'attack' to fight, or 'help'/'puzzle' to repair it]"
	elif input == "attack" or input == "fight":
		has_attacked = true
		_transition_to_combat()
		result.mode_changed = true
		result.message = "[Combat initiated - puzzle mode is now locked]"
	elif input == "puzzle" or input == "help" or input == "repair":
		if allow_puzzle_solution:
			_transition_to_puzzle()
			result.mode_changed = true
			result.message = "[Puzzle mode initiated - you can try to repair the Broken Link]"
		else:
			result.message = "The Broken Link is too unstable to repair right now..."
	else:
		result.message = intro_lines[mini(dialogue_index, intro_lines.size() - 1)]
		result.message += "\n[Type 'continue' to proceed, 'attack' to fight, or 'help' to assist]"

	return result

func _handle_combat_input(input: String) -> Dictionary:
	var result := {"handled": true, "message": "", "mode_changed": false, "encounter_ended": false}

	if input == "puzzle" or input == "help" or input == "repair":
		if has_attacked:
			result.message = "[You've already chosen to fight. The Broken Link resists repair.]"
			return result
		if allow_puzzle_solution and _can_offer_puzzle():
			_transition_to_puzzle()
			result.mode_changed = true
			result.message = "[Puzzle mode initiated - you can try to repair the Broken Link]"
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

	if cmd.command_type == CommandParser.CommandType.CONNECT:
		result.message = _handle_connect_in_combat()
		return result

	if not puzzle_offered and not has_attacked and _should_offer_puzzle():
		puzzle_offered = true
		result.message = "[The Broken Link flickers and stutters...]\n"
		for line in puzzle_offer_lines:
			result.message += line + "\n"
		result.message += "\n[Type 'puzzle' or 'help' to try repairing, or continue fighting]"
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

func _handle_connect_in_combat() -> String:
	var damage := 24
	enemy_data.current_hp -= damage

	var msg := "[CONNECT command stabilizes the Broken Link!]\n"
	msg += "Pointers realign, dealing %d integrity damage!\n" % damage

	if enemy_data.current_hp <= 0:
		_resolve_encounter("combat_victory")
		msg += "\n"
		for line in defeat_lines:
			msg += line + "\n"
	else:
		msg += "Broken Link HP: %d/%d" % [enemy_data.current_hp, enemy_data.max_hp]

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
			var granted_forest_key := not SceneManager.proficiency_key_forest
			SceneManager.npc_states["Broken Link"] = "helped"
			SceneManager.proficiency_key_forest = true
			SceneManager.broken_link_fragmented_key = false
			if granted_forest_key:
				_queue_key_reward_popup("Forest Proficiency Key")
			var broken_link_npc = _find_npc_by_name("Broken Link")
			if broken_link_npc:
				_set_npc_good_idle(broken_link_npc)
			if puzzle_data.reward.has("karma_change"):
				SceneManager.player_karma = puzzle_data.reward.karma_change
			if SceneManager.quest_manager:
				SceneManager.quest_manager.complete_quest("broken_link_puzzle")
		"combat_victory":
			var granted_forest_key_combat := not SceneManager.proficiency_key_forest
			SceneManager.npc_states["Broken Link"] = "defeated"
			SceneManager.broken_link_fragmented_key = false
			SceneManager.proficiency_key_forest = true
			if granted_forest_key_combat:
				_queue_key_reward_popup("Forest Proficiency Key")
			var broken_link_defeated = _find_npc_by_name("Broken Link")
			if broken_link_defeated:
				_hide_npc(broken_link_defeated)
			if SceneManager.quest_manager:
				SceneManager.quest_manager.complete_quest("broken_link_puzzle")
		"fled":
			pass

	encounter_ended.emit(method)
	mode_changed.emit(EncounterMode.RESOLVED)

func _queue_key_reward_popup(key_name: String) -> void:
	if SceneManager:
		SceneManager.set_meta("pending_reward_popup_key", key_name)

func _start_quest_if_needed() -> void:
	if SceneManager and SceneManager.quest_manager:
		var quest = SceneManager.quest_manager.get_quest("broken_link_puzzle")
		if quest and quest.status == "inactive":
			SceneManager.quest_manager.start_quest("broken_link_puzzle")
#endregion

## Find an NPC node by name in the scene
func _find_npc_by_name(npc_name: String) -> Node:
	var root = get_tree().root
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if npc.name == npc_name or npc.name.contains(npc_name.replace(" ", "")):
			return npc

	var found = root.find_child(npc_name.replace(" ", ""), true, false)
	if found:
		return found

	found = root.find_child(npc_name.replace(" ", "_"), true, false)
	return found

## Set an NPC to play good_idle animation
func _set_npc_good_idle(npc: Node) -> void:
	if not npc:
		return

	var sprite: AnimatedSprite3D = null
	if npc.has_node("AnimatedSprite3D"):
		sprite = npc.get_node("AnimatedSprite3D")
	else:
		for child in npc.get_children():
			if child is AnimatedSprite3D:
				sprite = child
				break

	if sprite:
		if sprite.sprite_frames.has_animation("good_idle"):
			sprite.play("good_idle")
			print("[BrokenLink] %s now playing good_idle" % npc.name)
		else:
			print("[BrokenLink] %s has no good_idle animation" % npc.name)

## Hide an NPC node and disable interaction
func _hide_npc(npc: Node) -> void:
	if not npc:
		return

	if npc is Node3D or npc is CanvasItem:
		npc.visible = false

	for child in npc.get_children():
		if child is CanvasItem or child is Node3D:
			child.visible = false

	var interact_area = npc.get_node_or_null("InteractArea")
	if interact_area and interact_area is Area3D:
		interact_area.monitoring = false
		interact_area.monitorable = false

	if npc is CharacterBody3D:
		npc.set_collision_layer_value(1, false)
		npc.set_collision_mask_value(1, false)
#endregion
