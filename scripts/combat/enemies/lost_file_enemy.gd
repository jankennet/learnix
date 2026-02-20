# lost_file_enemy.gd
# The "Lost File" enemy - a fragmented file spirit that attacks with corruption
# Can be defeated through combat OR solved through puzzle mechanics
# Theme: A file that was accidentally deleted and became corrupted/hostile
extends Node
class_name LostFileEnemy

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
	PUZZLE,      # File recovery puzzle
	RESOLVED,    # Encounter complete
}
#endregion

#region Configuration
@export_group("Lost File Stats")
@export var enemy_name: String = "Lost File"
@export var max_hp: int = 80
@export var attack_power: int = 12
@export var defense: int = 3
@export var speed: int = 7

@export_group("Encounter Settings")
@export var allow_puzzle_solution: bool = true
@export var puzzle_unlocks_at_hp_percent: float = 50.0  # Can start puzzle when HP below this
@export var hostile_start: bool = true  # Starts aggressive

@export_group("Dialogue")
@export var dialogue_json_path: String = "res://dialogues/enemies/lost_file.json"
@export var dialogue_resource: Resource = null  # optional dialogue resource (Dictionary-like)

var intro_lines: Array = []
var puzzle_offer_lines: Array = []
var defeat_lines: Array = []
var puzzle_success_lines: Array = []

## Dialogues will be loaded at runtime in _ready()

func _load_dialogue_files() -> void:
	# 1) Try a DialogueManager singleton (if your project provides one)
	if Engine.has_singleton("DialogueManager"):
		var dm = Engine.get_singleton("DialogueManager")
		if dm and dm.has_method("get_dialogue"):
			var d = dm.get_dialogue("lost_file")
			if typeof(d) == TYPE_DICTIONARY:
				intro_lines = d["intro"] if d.has("intro") else []
				puzzle_offer_lines = d["offer"] if d.has("offer") else []
				defeat_lines = d["defeat"] if d.has("defeat") else []
				puzzle_success_lines = d["success"] if d.has("success") else []
				return

	# 2) Try an exported Resource (dictionary-like)
	if dialogue_resource:
		# dialogue_resource might be a raw Dictionary or a Resource that can be converted to one.
		if typeof(dialogue_resource) == TYPE_DICTIONARY:
			# treat it directly as a Dictionary (avoid casting Resource -> Dictionary)
			var rd_dict = dialogue_resource
			# Use safe Dictionary lookups because Dictionary.get(key, default) signature differs in this Godot version
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

	# 3) Try loading a JSON file at dialogue_json_path
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

	# 4) Try parsing the project's .dialogue format used in /dialogues
	var dlg_path := "res://dialogues/LostFile.dialogue"
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

	# 5) Fallback to embedded defaults (kept for safety)
	intro_lines = [
		"[static crackle] ...who... who deleted me?",
		"I was... important once. A document. A memory.",
		"Now I'm scattered. Fragmented. LOST.",
		"You... you look like the one who did this!",
		"[The Lost File's data fragments swirl aggressively]",
	]

	puzzle_offer_lines = [
		"Wait... you're not the one who deleted me?",
		"Maybe... maybe you can help restore me?",
		"My fragments are scattered across the filesystem.",
		"[TYPE 'puzzle' to attempt recovery, or continue fighting]",
	]

	defeat_lines = [
		"My... my data... it's corrupting further...",
		"I just wanted... to be remembered...",
		"[The Lost File's fragments scatter and fade]",
	]

	puzzle_success_lines = [
		"[data stabilizing]",
		"I... I remember now. I remember what I was.",
		"Thank you, user. You've restored what was lost.",
		"I will return to where I belong.",
		"[The Lost File peacefully returns to the filesystem]",
	]

func _parse_simple_dialogue_format(text: String) -> Dictionary:
	# Parses a simple custom .dialogue format used in the project's dialogues folder.
	# Returns a dictionary of cleaned sections: start, offer_puzzle, puzzle_complete, combat_victory
	var lines := text.split("\n", false)
	var current_section := ""
	var sections := {}
	for raw_line in lines:
		var line := raw_line.strip_edges()
		if line.begins_with("~ "):
			# Section header like: ~ start or ~ offer_puzzle
			var parts := line.substr(2).strip_edges()
			current_section = parts
			sections[current_section] = []
			continue
		if current_section == "":
			continue
		# Only capture NPC lines prefixed by 'Lost File:' (or generic text lines)
		if line.find(":") != -1:
			var tokens := line.split(":", false)
			var speaker := tokens[0].strip_edges()
			var tail := tokens.slice(1, tokens.size())
			var rest := ""
			if tail.size() > 0:
				# Build the tail string manually to avoid using Array.join (not available)
				for i in range(tail.size()):
					if i > 0:
						rest += ":"
					rest += str(tail[i]).strip_edges()
			else:
				rest = ""
			if speaker.to_lower().find("lost file") != -1 or speaker == "":
				sections[current_section].append(rest)
		else:
			# non-prefixed lines (plain text) — include
			if line != "" and not line.begins_with("-") and not line.begins_with("do "):
				sections[current_section].append(line)

	# Normalize section keys to expected names
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
	if sections.has("puzzle_complete") and not out.has("puzzle_complete"):
		out["puzzle_complete"] = sections["puzzle_complete"]

	return out

#region State
var current_mode: EncounterMode = EncounterMode.DIALOGUE
var enemy_data: TurnCombatManager.EnemyData
var puzzle_data: PuzzleStateHandler.PuzzleData
var combat_manager: TurnCombatManager
var dialogue_index: int = 0
var puzzle_offered: bool = false
var encounter_result: String = ""
var has_attacked: bool = false  # Once player attacks, puzzle mode is locked
#endregion

#region Initialization

func _ready() -> void:
	# Load dialogues first so intro/puzzle lines are ready when encounter starts
	_load_dialogue_files()

	_initialize_enemy_data()
	_initialize_puzzle_data()

func _initialize_enemy_data() -> void:
	enemy_data = TurnCombatManager.EnemyData.new()
	enemy_data.id = "lost_file"
	enemy_data.display_name = enemy_name
	enemy_data.max_hp = max_hp
	enemy_data.current_hp = max_hp
	enemy_data.attack_power = attack_power
	enemy_data.defense = defense
	enemy_data.speed = speed
	enemy_data.weakness = "restore"  # Restore command is super effective
	enemy_data.resistance = "delete"  # Delete actually heals (ironic)
	enemy_data.abilities = ["corrupt", "fragment", "scatter"]
	enemy_data.description = "A file that was deleted and became corrupted. It lashes out in confusion, scattering data and corrupting memory. Perhaps it can be restored instead of destroyed?"
	enemy_data.defeat_reward = {
		"npc_name": "Lost File",
		"npc_state": "hostile",  # Combat victory = hostile resolution
		"karma_change": "neutral",
	}

func _initialize_puzzle_data() -> void:
	puzzle_data = PuzzleStateHandler.create_lost_file_puzzle()
#endregion

#region Encounter Flow

## Start the encounter (called when player interacts)
func start_encounter(cm: TurnCombatManager) -> void:
	combat_manager = cm
	current_mode = EncounterMode.DIALOGUE
	dialogue_index = 0
	puzzle_offered = false
	
	encounter_started.emit()
	_show_intro_dialogue()

## Process player input during the encounter
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
	
	# Any input during dialogue advances or starts combat
	if input == "continue" or input == "next" or input == "":
		dialogue_index += 1
		if dialogue_index >= intro_lines.size():
			# Dialogue complete, offer choice
			result.message = "[The Lost File awaits your decision...]\n"
			result.message += "[Type 'attack' to fight, or 'help'/'puzzle' to try restoring it]"
		else:
			# Show the next dialogue line
			result.message = intro_lines[dialogue_index]
			if dialogue_index < intro_lines.size() - 1:
				result.message += "\n[Type 'continue' to proceed, 'attack' to fight, or 'help' to assist]"
			else:
				result.message += "\n[Type 'attack' to fight, or 'help'/'puzzle' to try restoring it]"
	elif input == "attack" or input == "fight":
		has_attacked = true  # Lock out puzzle mode
		_transition_to_combat()
		result.mode_changed = true
		result.message = "[Combat initiated - puzzle mode is now locked]"
	elif input == "puzzle" or input == "restore" or input == "find" or input == "help":
		# Allow entering puzzle mode directly from dialogue
		if allow_puzzle_solution:
			_transition_to_puzzle()
			result.mode_changed = true
			result.message = "[Puzzle mode initiated - you can try to help restore the Lost File]"
		else:
			result.message = "The Lost File isn't ready to accept help yet..."
	elif input == "talk":
		result.message = intro_lines[mini(dialogue_index, intro_lines.size() - 1)]
		result.message += "\n[Type 'continue' to proceed, 'attack' to fight, or 'help' to assist]"
	else:
		# Unknown input, show current dialogue
		result.message = intro_lines[mini(dialogue_index, intro_lines.size() - 1)]
		result.message += "\n[Type 'continue' to proceed, 'attack' to fight, or 'help' to assist]"
	
	return result

func _handle_combat_input(input: String) -> Dictionary:
	var result := {"handled": true, "message": "", "mode_changed": false, "encounter_ended": false}
	
	# Check for puzzle mode trigger - only if player hasn't attacked yet
	if input == "puzzle" or input == "restore" or input == "recover" or input == "help":
		if has_attacked:
			result.message = "[You've already chosen to fight. The Lost File no longer trusts your help.]"
			return result
		if allow_puzzle_solution and _can_offer_puzzle():
			_transition_to_puzzle()
			result.mode_changed = true
			result.message = "[Puzzle mode initiated - you can try to help restore the Lost File]"
			return result
		else:
			result.message = "[Puzzle mode not available yet. Continue the encounter.]"
			return result
	
	# Parse and process combat command
	var cmd := CommandParser.parse(input)
	
	if not cmd.success:
		result.message = cmd.error_message
		return result
	
	# Track if this is an attack command - locks out puzzle mode
	if cmd.command_type == CommandParser.CommandType.ATTACK or cmd.command_type == CommandParser.CommandType.DELETE:
		has_attacked = true
	
	# Special handling for Lost File's weakness/resistance
	if cmd.command_type == CommandParser.CommandType.RESTORE:
		# Restore deals massive damage to Lost File
		result.message = _handle_restore_in_combat()
		return result
	
	# Check for puzzle offer threshold (only if hasn't attacked)
	if not puzzle_offered and not has_attacked and _should_offer_puzzle():
		puzzle_offered = true
		result.message = "[The Lost File's aggression falters...]\n"
		for line in puzzle_offer_lines:
			result.message += line + "\n"
		result.message += "\n[Type 'puzzle' or 'help' to try helping, or continue fighting]"
		return result
	
	# Normal combat processing through combat manager
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
	
	# Allow returning to combat
	if input == "fight" or input == "combat" or input == "attack":
		_transition_to_combat()
		result.mode_changed = true
		result.message = "[Returning to combat]"
		return result
	
	# Parse command
	var cmd := CommandParser.parse(input)
	
	if not cmd.success:
		result.message = cmd.error_message
		return result
	
	# Process puzzle command
	var puzzle_result := PuzzleStateHandler.process_puzzle_command(puzzle_data, cmd)
	result.message = puzzle_result.message
	
	# Check if timing is required
	if puzzle_result.requires_timing:
		result.requires_timing = true
		result.timing_difficulty = puzzle_result.timing_difficulty
		result.pending_puzzle_result = puzzle_result
		result.pending_command = cmd
		# Store for later application after timing
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
		# Puzzle failed, return to combat
		result.message += "\n[Puzzle failed - returning to combat]"
		_transition_to_combat()
		result.mode_changed = true
	
	return result

## Store pending timing data
var _pending_puzzle_timing: Dictionary = {}

## Apply timing result to pending puzzle action
func apply_puzzle_timing_result(zone: int, success_chance: float) -> Dictionary:
	var result := {"message": "", "encounter_ended": false, "mode_changed": false}
	
	if _pending_puzzle_timing.is_empty():
		result.message = "No pending puzzle action."
		return result
	
	var pending_result: PuzzleStateHandler.PuzzleResult = _pending_puzzle_timing.get("puzzle_result")
	
	if pending_result:
		# Apply timing to puzzle
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

func _handle_restore_in_combat() -> String:
	# Restore is super effective against Lost File
	var damage := 30  # Big damage
	enemy_data.current_hp -= damage
	
	var msg := "[RESTORE command resonates with the Lost File!]\n"
	msg += "The fragments briefly stabilize... dealing %d integrity damage!\n" % damage
	
	if enemy_data.current_hp <= 0:
		_resolve_encounter("combat_victory")
		msg += "\n"
		for line in defeat_lines:
			msg += line + "\n"
	else:
		msg += "Lost File HP: %d/%d" % [enemy_data.current_hp, enemy_data.max_hp]
	
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
	
	# Show puzzle intro
	var intro := puzzle_data.description
	dialogue_requested.emit([intro])

func _can_offer_puzzle() -> bool:
	# Can't offer puzzle if player has already attacked
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

func _resolve_encounter(method: String) -> void:
	encounter_result = method
	current_mode = EncounterMode.RESOLVED
	
	# Update NPC state based on resolution method
	match method:
		"puzzle_solved":
			SceneManager.npc_states["Lost File"] = "helped"
			SceneManager.npc_states["Messy Directory"] = "helped"
			SceneManager.helped_lost_file = true
			if puzzle_data.reward.has("karma_change"):
				SceneManager.player_karma = puzzle_data.reward.karma_change
			
			# Trigger good ending: move both NPCs to Fallback Hamlet
			_trigger_good_ending()
		
		"combat_victory":
			SceneManager.npc_states["Lost File"] = "hostile"
			SceneManager.deleted_lost_file = true
		
		"fled":
			# No state change
			pass
	
	encounter_ended.emit(method)
	mode_changed.emit(EncounterMode.RESOLVED)

## Trigger the good ending: Lost File and Messy Directory go to Fallback Hamlet
func _trigger_good_ending() -> void:
	print("[LostFile] Triggering good ending - moving to Fallback Hamlet")
	
	# Find Lost File NPC and switch to good_idle
	var lost_file_npc = _find_npc_by_name("Lost File")
	if lost_file_npc:
		_set_npc_good_idle(lost_file_npc)
	
	# Find Messy Directory NPC and switch to good_idle
	var messy_dir_npc = _find_npc_by_name("Messy Directory")
	if messy_dir_npc:
		_set_npc_good_idle(messy_dir_npc)
	
	# After a short delay, teleport both to Fallback Hamlet
	await get_tree().create_timer(2.0).timeout
	_move_npcs_to_fallback_hamlet(lost_file_npc, messy_dir_npc)

## Find an NPC node by name in the scene
func _find_npc_by_name(npc_name: String) -> Node:
	var root = get_tree().root
	
	# Try to find in current scene's NPC group
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if npc.name == npc_name or npc.name.contains(npc_name.replace(" ", "")):
			return npc
	
	# Fallback: search entire tree
	var found = root.find_child(npc_name.replace(" ", ""), true, false)
	if found:
		return found
	
	# Try without spaces
	found = root.find_child(npc_name.replace(" ", "_"), true, false)
	return found

## Set an NPC to play good_idle animation
func _set_npc_good_idle(npc: Node) -> void:
	if not npc:
		return
	
	# Find the AnimatedSprite3D
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
			print("[LostFile] %s now playing good_idle" % npc.name)
		else:
			print("[LostFile] %s has no good_idle animation" % npc.name)

## Move NPCs to Fallback Hamlet
func _move_npcs_to_fallback_hamlet(lost_file: Node, messy_dir: Node) -> void:
	# Find Fallback Hamlet spawn points
	var hamlet_scene = get_tree().root.find_child("FallbackHamlet", true, false)
	if not hamlet_scene:
		# Try loading/finding the hamlet scene
		print("[LostFile] Fallback Hamlet not found in current scene - NPCs will appear there on next visit")
		return
	
	# Find spawn positions for the NPCs
	var lost_file_spawn = hamlet_scene.find_child("LostFileSpawn", true, false)
	var messy_dir_spawn = hamlet_scene.find_child("MessyDirectorySpawn", true, false)
	
	# If no specific spawns, find generic NPC area
	if not lost_file_spawn:
		lost_file_spawn = hamlet_scene.find_child("NPCSpawn1", true, false)
	if not messy_dir_spawn:
		messy_dir_spawn = hamlet_scene.find_child("NPCSpawn2", true, false)
	
	# Move Lost File
	if lost_file and lost_file_spawn:
		var old_parent = lost_file.get_parent()
		if old_parent:
			old_parent.remove_child(lost_file)
		hamlet_scene.add_child(lost_file)
		lost_file.global_position = lost_file_spawn.global_position
		print("[LostFile] Moved Lost File to Fallback Hamlet")
	
	# Move Messy Directory  
	if messy_dir and messy_dir_spawn:
		var old_parent = messy_dir.get_parent()
		if old_parent:
			old_parent.remove_child(messy_dir)
		hamlet_scene.add_child(messy_dir)
		messy_dir.global_position = messy_dir_spawn.global_position
		print("[LostFile] Moved Messy Directory to Fallback Hamlet")
	
	# If spawns weren't found, just log that they'll appear on next scene load
	if not lost_file_spawn or not messy_dir_spawn:
		print("[LostFile] NPC spawn points not found - they will appear in Hamlet on next visit")
#endregion

#region Enemy AI (Override for TurnCombatManager)

## Custom enemy action selection for Lost File
func choose_action() -> String:
	var hp_percent := (float(enemy_data.current_hp) / float(enemy_data.max_hp)) * 100.0
	
	# More desperate attacks at low HP
	if hp_percent < 25:
		# Desperate fragmentation attack
		return "fragment" if randf() < 0.7 else "attack"
	elif hp_percent < 50:
		# Mix of attacks
		var roll := randf()
		if roll < 0.4:
			return "corrupt"
		elif roll < 0.7:
			return "scatter"
		else:
			return "attack"
	else:
		# Standard attacks
		return "attack" if randf() < 0.6 else "corrupt"

## Custom action resolution for Lost File
func resolve_action(action: String) -> TurnCombatManager.CombatEffect:
	var effect := TurnCombatManager.CombatEffect.new()
	
	match action:
		"attack":
			effect.damage_dealt = enemy_data.attack_power
			effect.message = "The Lost File lashes out with corrupted data!"
		
		"corrupt":
			effect.damage_dealt = int(enemy_data.attack_power * 0.7)
			effect.status_applied = "corrupted"
			effect.message = "The Lost File injects corrupted bytes into your system!"
		
		"fragment":
			effect.damage_dealt = enemy_data.attack_power + 5
			effect.message = "The Lost File explodes into fragments, each one cutting!"
			if randf() < 0.3:
				effect.is_critical = true
				effect.damage_dealt *= 2
				effect.message += " CRITICAL HIT!"
		
		"scatter":
			effect.damage_dealt = int(enemy_data.attack_power * 0.5)
			effect.status_applied = "scattered"
			effect.message = "Data scatters across sectors, disorienting you!"
	
	return effect

## Backwards-compatible wrappers for combat manager
func _choose_enemy_action() -> String:
	return choose_action()

func _resolve_enemy_action(action: String) -> TurnCombatManager.CombatEffect:
	return resolve_action(action)
#endregion

#region Utility

## Get encounter state for saving/loading
func get_state_dict() -> Dictionary:
	return {
		"mode": current_mode,
		"enemy_hp": enemy_data.current_hp,
		"puzzle_state": puzzle_data.state,
		"puzzle_progress": puzzle_data.custom_data,
		"dialogue_index": dialogue_index,
		"puzzle_offered": puzzle_offered,
	}

## Restore encounter state
func load_state_dict(state: Dictionary) -> void:
	current_mode = state.get("mode", EncounterMode.DIALOGUE)
	enemy_data.current_hp = state.get("enemy_hp", max_hp)
	puzzle_data.state = state.get("puzzle_state", PuzzleStateHandler.PuzzleState.NOT_STARTED)
	puzzle_data.custom_data = state.get("puzzle_progress", {})
	dialogue_index = state.get("dialogue_index", 0)
	puzzle_offered = state.get("puzzle_offered", false)
#endregion
