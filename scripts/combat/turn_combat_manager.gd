# turn_combat_manager.gd
# Manages turn-based combat flow with text command input
# Player Turn → Enemy Turn → State Update cycle
extends Node
class_name TurnCombatManager

#region Signals
signal combat_started(enemy_data: EnemyData)
signal combat_ended(victory: bool, enemy_data: EnemyData)
signal turn_changed(turn_owner: TurnOwner)
signal player_turn_started()
signal enemy_turn_started()
signal command_executed(result: CommandParser.CommandResult, effect: CombatEffect)
signal damage_dealt(target: String, amount: int, is_critical: bool)
signal status_applied(target: String, status: String)
signal message_logged(message: String, type: MessageType)
signal awaiting_input()
## Emitted when timing minigame should be shown (command parsed successfully)
signal timing_minigame_requested(command: CommandParser.CommandResult, difficulty: float)
## Emitted when timing result is applied
signal timing_result_applied(zone: int, multiplier: float)
#endregion

#region Enums
enum TurnOwner { PLAYER, ENEMY, SYSTEM }
enum CombatState { IDLE, ACTIVE, PLAYER_INPUT, ENEMY_ACTING, RESOLVING, ENDED }
enum MessageType { INFO, SUCCESS, WARNING, ERROR, DAMAGE, HEAL, STATUS }
#endregion

#region Combat Data Classes

## Represents an enemy in combat
class EnemyData:
	var id: String = ""
	var display_name: String = "Unknown Entity"
	var max_hp: int = 100
	var current_hp: int = 100
	var attack_power: int = 10
	var defense: int = 5
	var speed: int = 5
	var weakness: String = ""  # Command type that deals extra damage
	var resistance: String = ""  # Command type that deals less damage
	var abilities: Array[String] = []
	var status_effects: Array[String] = []
	var scan_revealed: bool = false
	var description: String = ""
	var defeat_reward: Dictionary = {}
	
	func is_alive() -> bool:
		return current_hp > 0
	
	func take_damage(amount: int) -> int:
		var actual := maxi(0, amount - defense)
		current_hp = maxi(0, current_hp - actual)
		return actual
	
	func heal(amount: int) -> int:
		var before := current_hp
		current_hp = mini(max_hp, current_hp + amount)
		return current_hp - before

## Represents player combat state
class PlayerCombatState:
	var max_integrity: int = 100  # "HP" themed as system integrity
	var current_integrity: int = 100
	var attack_power: int = 15
	var defense: int = 3
	var is_defending: bool = false
	var defend_quality: int = 0  # 0 = none, 1 = normal guard, 2 = perfect guard
	var status_effects: Array[String] = []
	var command_history: Array[String] = []
	var combo_counter: int = 0
	var last_command_type: int = -1  # CommandParser.CommandType
	
	func is_alive() -> bool:
		return current_integrity > 0
	
	func take_damage(amount: int) -> int:
		var reduction := defense
		if is_defending:
			if defend_quality >= 2:
				current_integrity = maxi(0, current_integrity)
				return 0
			if defend_quality == 1:
				reduction += 16
			else:
				reduction += 10  # Extra defense when blocking
		var actual := maxi(1, amount - reduction)
		current_integrity = maxi(0, current_integrity - actual)
		return actual
	
	func heal(amount: int) -> int:
		var before := current_integrity
		current_integrity = mini(max_integrity, current_integrity + amount)
		return current_integrity - before
	
	func reset_turn_state():
		is_defending = false
		defend_quality = 0

## Combat effect result from a command
class CombatEffect:
	var success: bool = true
	var damage_dealt: int = 0
	var damage_taken: int = 0
	var healing_done: int = 0
	var status_applied: String = ""
	var status_removed: String = ""
	var special_effect: String = ""
	var message: String = ""
	var is_critical: bool = false
	var is_weakness: bool = false
	var ends_combat: bool = false
	var victory: bool = false
#endregion

#region State Variables
var combat_state: CombatState = CombatState.IDLE
var current_turn: TurnOwner = TurnOwner.SYSTEM
var turn_number: int = 0

var player_state: PlayerCombatState
var current_enemy: EnemyData

var combat_log: Array[String] = []
var pending_command: CommandParser.CommandResult = null

## Timing minigame settings
var timing_minigame_enabled: bool = true
var pending_timing_command: CommandParser.CommandResult = null
var timing_damage_multiplier: float = 1.0
var timing_was_critical: bool = false
var timing_was_miss: bool = false
var _heal_uses_remaining: int = 1
var _heal_uses_max: int = 1
var _overclock_used_this_battle: bool = false
var _taskkill_used_this_battle: bool = false
var _pending_timing_profile: Dictionary = {}
var _skip_enemy_turn_after_command: bool = false
var _combat_start_modifiers_applied: bool = false
const TASKKILL_DATA_BITS_COST := 100
const OVERCLOCK_SKIP_CHANCE := 0.35
#endregion

#region Initialization

func _ready():
	player_state = PlayerCombatState.new()

## Start combat with an enemy
func start_combat(enemy: EnemyData) -> void:
	if combat_state != CombatState.IDLE:
		push_warning("Combat already in progress!")
		return
	
	current_enemy = enemy
	turn_number = 0
	combat_log.clear()
	player_state = PlayerCombatState.new()
	_heal_uses_max = 3 if _is_skill_unlocked("potion_patch") else 1
	_heal_uses_remaining = 1
	_overclock_used_this_battle = false
	_taskkill_used_this_battle = false
	_pending_timing_profile = {}
	_skip_enemy_turn_after_command = false
	_combat_start_modifiers_applied = false
	_apply_sudo_privilege_modifiers()
	
	combat_state = CombatState.ACTIVE
	_log_message("=== COMBAT INITIATED ===", MessageType.INFO)
	_log_message("Encountered: %s" % enemy.display_name, MessageType.WARNING)
	_log_message("Type commands to fight. Type 'help' for command list.", MessageType.INFO)
	
	combat_started.emit(enemy)
	
	# Start first turn
	_start_player_turn()

## End combat
func end_combat(victory: bool) -> void:
	combat_state = CombatState.ENDED
	
	if victory:
		_log_message("=== VICTORY ===", MessageType.SUCCESS)
		_log_message("%s has been defeated!" % current_enemy.display_name, MessageType.SUCCESS)
		# Apply rewards
		if current_enemy.defeat_reward.has("karma"):
			SceneManager.player_karma = current_enemy.defeat_reward.karma
		if current_enemy.defeat_reward.has("npc_state"):
			var npc_name: String = current_enemy.defeat_reward.get("npc_name", current_enemy.id)
			SceneManager.npc_states[npc_name] = current_enemy.defeat_reward.npc_state
	else:
		_log_message("=== SYSTEM FAILURE ===", MessageType.ERROR)
		_log_message("Integrity compromised. Rebooting...", MessageType.ERROR)
	
	combat_ended.emit(victory, current_enemy)
	
	# Reset state
	await get_tree().create_timer(2.0).timeout
	combat_state = CombatState.IDLE
	current_enemy = null
#endregion

#region Turn Flow

func _start_player_turn() -> void:
	if combat_state == CombatState.ENDED:
		return
	
	turn_number += 1
	current_turn = TurnOwner.PLAYER
	combat_state = CombatState.PLAYER_INPUT
	player_state.reset_turn_state()
	
	_log_message("\n--- TURN %d: YOUR INPUT ---" % turn_number, MessageType.INFO)
	_log_message("Integrity: %d/%d | Enemy: %d/%d" % [
		player_state.current_integrity,
		player_state.max_integrity,
		current_enemy.current_hp,
		current_enemy.max_hp
	], MessageType.INFO)
	
	turn_changed.emit(TurnOwner.PLAYER)
	player_turn_started.emit()
	awaiting_input.emit()

func _start_enemy_turn() -> void:
	if combat_state == CombatState.ENDED:
		return
	
	current_turn = TurnOwner.ENEMY
	combat_state = CombatState.ENEMY_ACTING
	
	_log_message("\n--- ENEMY TURN ---", MessageType.WARNING)
	
	turn_changed.emit(TurnOwner.ENEMY)
	enemy_turn_started.emit()
	
	# Process enemy action after brief delay
	await get_tree().create_timer(0.8).timeout
	_execute_enemy_action()

func _execute_enemy_action() -> void:
	if not current_enemy or not current_enemy.is_alive():
		return
	
	# Simple enemy AI - choose action based on state
	var action := _choose_enemy_action()
	var effect := _resolve_enemy_action(action)
	
	_log_message("%s uses %s!" % [current_enemy.display_name, action], MessageType.WARNING)
	
	if effect.damage_dealt > 0:
		var actual := player_state.take_damage(effect.damage_dealt)
		_log_message("You take %d damage!" % actual, MessageType.DAMAGE)
		damage_dealt.emit("player", actual, effect.is_critical)
	
	if not effect.status_applied.is_empty():
		player_state.status_effects.append(effect.status_applied)
		_log_message("Status applied: %s" % effect.status_applied, MessageType.STATUS)
		status_applied.emit("player", effect.status_applied)
	
	# Check for player defeat
	if not player_state.is_alive():
		end_combat(false)
		return
	
	# Proceed to next player turn
	await get_tree().create_timer(0.5).timeout
	_start_player_turn()

func _choose_enemy_action() -> String:
	# Override in enemy-specific scripts for unique behavior
	if current_enemy.abilities.is_empty():
		return "attack"
	
	# Weighted random selection
	var rand := randf()
	if rand < 0.6:
		return "attack"
	elif rand < 0.85 and current_enemy.abilities.size() > 0:
		return current_enemy.abilities.pick_random()
	else:
		return "attack"

func _resolve_enemy_action(action: String) -> CombatEffect:
	var effect := CombatEffect.new()
	
	match action:
		"attack":
			effect.damage_dealt = current_enemy.attack_power
			if randf() < 0.1:  # 10% crit chance
				effect.damage_dealt *= 2
				effect.is_critical = true
		"corrupt":
			effect.damage_dealt = int(current_enemy.attack_power / 2.0)
			effect.status_applied = "corrupted"
		"fragment":
			effect.damage_dealt = current_enemy.attack_power + 5
			effect.status_applied = "fragmented"
		"scatter":
			effect.damage_dealt = int(current_enemy.attack_power * 0.75)
			effect.message = "Data scattered across sectors!"
		_:
			effect.damage_dealt = current_enemy.attack_power
	
	return effect
#endregion

#region Command Processing

## Process player text input
func process_input(raw_input: String) -> void:
	if combat_state != CombatState.PLAYER_INPUT:
		_log_message("Not your turn!", MessageType.ERROR)
		return
	
	# Handle special inputs
	if raw_input.strip_edges().to_lower() == "help":
		_log_message(CommandParser.get_help_text("combat"), MessageType.INFO)
		awaiting_input.emit()
		return
	
	# Parse the command
	var result := CommandParser.parse(raw_input)
	
	if not result.success:
		_log_message(result.error_message, MessageType.ERROR)
		awaiting_input.emit()  # Let player try again
		return
	
	# Warn about typos but accept
	if result.partial_match:
		_log_message("Did you mean '%s'? Executing..." % result.suggested_command, MessageType.WARNING)

	# Hard-lock taskkill command until the related skill is unlocked.
	if result.command_type == CommandParser.CommandType.KILL and not _is_skill_unlocked("taskkill"):
		_log_message("Command unavailable: unlock taskkill in the skill shop first.", MessageType.ERROR)
		awaiting_input.emit()
		return
	
	# Store in history
	player_state.command_history.append(result.raw_input)

	# Enforce resource-gated skills before timing starts so spam attempts still cost the turn.
	if result.command_type == CommandParser.CommandType.HEAL and not _can_use_heal():
		_log_message("Heal failed: patch reserves are exhausted.", MessageType.ERROR)
		_after_command_resolved(CombatEffect.new())
		return

	if result.command_type == CommandParser.CommandType.KILL:
		if not _consume_taskkill():
			_log_message("taskkill failed: not enough data bits or already used this battle.", MessageType.ERROR)
			_after_command_resolved(CombatEffect.new())
			return
		_skip_enemy_turn_after_command = true
	
	# Check if timing minigame is enabled and command should use it
	if timing_minigame_enabled and _command_uses_timing(result.command_type):
		_pending_timing_profile = _build_timing_profile(result)
		if bool(_pending_timing_profile.get("skip_timing", false)):
			_log_message("Overclock burst skips the timing window!", MessageType.SUCCESS)
			_execute_command_after_timing(result)
			return

		# Store the command and request timing minigame
		pending_timing_command = result
		combat_state = CombatState.RESOLVING
		var difficulty := float(_pending_timing_profile.get("difficulty", _get_timing_difficulty()))
		timing_minigame_requested.emit(result, difficulty)
		return
	
	# If timing disabled or command doesn't use timing, resolve immediately
	_execute_command_after_timing(result)

## Check if a command type should trigger the timing minigame
func _command_uses_timing(cmd_type: int) -> bool:
	# Commands that require timing (offensive/active commands)
	return cmd_type in [
		CommandParser.CommandType.ATTACK,
		CommandParser.CommandType.DEFEND,
		CommandParser.CommandType.DELETE,
		CommandParser.CommandType.KILL,
		CommandParser.CommandType.HEAL,
		CommandParser.CommandType.RESTORE,
	]

## Get difficulty based on enemy and turn state
func _get_timing_difficulty() -> float:
	var difficulty := 1.0
	
	# Increase difficulty based on enemy speed
	if current_enemy:
		difficulty += (current_enemy.speed - 5) * 0.1
	
	# Slightly harder as combat goes on
	difficulty += turn_number * 0.02
	
	return clampf(difficulty, 0.5, 2.5)

## Called when timing minigame completes (from external UI)
func apply_timing_result(zone: int, damage_multiplier: float, is_miss: bool) -> void:
	timing_damage_multiplier = damage_multiplier
	timing_was_critical = (zone == 2)  # ZoneType.CRITICAL
	timing_was_miss = is_miss
	
	timing_result_applied.emit(zone, damage_multiplier)
	
	# Now execute the pending command with timing applied
	if pending_timing_command:
		var cmd := pending_timing_command
		pending_timing_command = null
		
		if timing_was_miss:
			_log_message("MISS! The command failed to execute!", MessageType.ERROR)
			# Still end turn on miss
			_after_command_resolved(CombatEffect.new())
		else:
			_execute_command_after_timing(cmd)

## Execute command after timing (or immediately if timing disabled)
func _execute_command_after_timing(result: CommandParser.CommandResult) -> void:
	# Resolve the command
	combat_state = CombatState.RESOLVING
	var effect := _resolve_player_command(result)
	
	command_executed.emit(result, effect)
	
	_after_command_resolved(effect)

## Handle post-command logic
func _after_command_resolved(effect: CombatEffect) -> void:
	# Reset timing state
	timing_damage_multiplier = 1.0
	timing_was_critical = false
	timing_was_miss = false
	_skip_enemy_turn_after_command = false
	_pending_timing_profile.clear()
	
	# Check for combat end
	if effect.ends_combat:
		end_combat(effect.victory)
		return
	
	# Check if enemy defeated
	if not current_enemy.is_alive():
		end_combat(true)
		return
	
	# Proceed to enemy turn
	if effect.special_effect == "skip_enemy_turn":
		_log_message("Enemy turn skipped.", MessageType.SUCCESS)
		_skip_enemy_turn_after_command = false
		await get_tree().create_timer(0.35).timeout
		_start_player_turn()
		return

	await get_tree().create_timer(0.5).timeout
	_start_enemy_turn()

## Resolve a player command into combat effects
func _resolve_player_command(result: CommandParser.CommandResult) -> CombatEffect:
	var effect := CombatEffect.new()
	var cmd := result.command_type
	
	# Update combo tracking
	if cmd == player_state.last_command_type:
		player_state.combo_counter += 1
	else:
		player_state.combo_counter = 0
	player_state.last_command_type = cmd
	
	match cmd:
		CommandParser.CommandType.ATTACK:
			effect = _resolve_attack(result)
		
		CommandParser.CommandType.DEFEND:
			effect = _resolve_defend(result)
		
		CommandParser.CommandType.SCAN:
			effect = _resolve_scan(result)
		
		CommandParser.CommandType.HEAL:
			effect = _resolve_heal(result)
		
		CommandParser.CommandType.ESCAPE:
			effect = _resolve_escape(result)
		
		CommandParser.CommandType.DELETE, CommandParser.CommandType.KILL:
			effect = _resolve_delete(result)
		
		CommandParser.CommandType.FIND:
			effect = _resolve_find(result)
		
		CommandParser.CommandType.RESTORE:
			effect = _resolve_restore(result)
		
		_:
			_log_message("Command '%s' has no effect in combat." % result.raw_input, MessageType.WARNING)
			effect.success = false
	
	return effect

func _resolve_attack(_result: CommandParser.CommandResult) -> CombatEffect:
	var effect := CombatEffect.new()
	var base_damage := player_state.attack_power
	
	# Apply timing minigame multiplier
	base_damage = int(base_damage * timing_damage_multiplier)
	
	# Timing critical overrides/stacks with random critical
	if timing_was_critical:
		effect.is_critical = true
		_log_message("⭐ PERFECT TIMING! Critical strike!", MessageType.SUCCESS)
	
	# Combo bonus
	if player_state.combo_counter > 0:
		base_damage += player_state.combo_counter * 2
		_log_message("Combo x%d!" % (player_state.combo_counter + 1), MessageType.SUCCESS)
	
	# Additional critical hit chance (only if not already critical from timing)
	if not effect.is_critical and randf() < 0.10:
		base_damage *= 2
		effect.is_critical = true
		_log_message("CRITICAL HIT!", MessageType.SUCCESS)
	
	# Check weakness
	if current_enemy.weakness == "attack":
		base_damage = int(base_damage * 1.5)
		effect.is_weakness = true
		_log_message("It's super effective!", MessageType.SUCCESS)
	
	var actual := current_enemy.take_damage(base_damage)
	effect.damage_dealt = actual
	
	_log_message("You attack for %d damage!" % actual, MessageType.DAMAGE)
	damage_dealt.emit("enemy", actual, effect.is_critical)
	
	return effect

func _resolve_defend(_result: CommandParser.CommandResult) -> CombatEffect:
	var effect := CombatEffect.new()
	player_state.is_defending = true
	player_state.defend_quality = 2 if timing_was_critical else 1
	
	if timing_was_critical:
		_log_message("Perfect guard! The next hit will be fully blocked.", MessageType.SUCCESS)
	else:
		_log_message("You brace for impact. The next hit will be heavily reduced.", MessageType.INFO)
	effect.message = "Defending"
	
	return effect

func _resolve_scan(_result: CommandParser.CommandResult) -> CombatEffect:
	var effect := CombatEffect.new()
	
	if current_enemy.scan_revealed:
		_log_message("Already scanned. Data cached.", MessageType.INFO)
	else:
		current_enemy.scan_revealed = true
		_log_message("=== SCAN RESULTS ===", MessageType.SUCCESS)
		_log_message("Name: %s" % current_enemy.display_name, MessageType.INFO)
		_log_message("HP: %d/%d" % [current_enemy.current_hp, current_enemy.max_hp], MessageType.INFO)
		_log_message("Attack: %d | Defense: %d" % [current_enemy.attack_power, current_enemy.defense], MessageType.INFO)
		if not current_enemy.weakness.is_empty():
			_log_message("Weakness: %s" % current_enemy.weakness, MessageType.SUCCESS)
		if not current_enemy.resistance.is_empty():
			_log_message("Resistance: %s" % current_enemy.resistance, MessageType.WARNING)
		_log_message("Info: %s" % current_enemy.description, MessageType.INFO)
	
	return effect

func _resolve_heal(_result: CommandParser.CommandResult) -> CombatEffect:
	var effect := CombatEffect.new()
	if _heal_uses_remaining <= 0:
		_log_message("No patch reserves left.", MessageType.ERROR)
		effect.success = false
		return effect

	_heal_uses_remaining -= 1
	var heal_amount := 25
	
	# Apply timing multiplier to healing
	heal_amount = int(heal_amount * timing_damage_multiplier)
	
	if timing_was_critical:
		_log_message("⭐ PERFECT TIMING! Maximum restoration!", MessageType.SUCCESS)
		heal_amount = int(heal_amount * 1.5)  # Extra bonus for critical
	
	var actual := player_state.heal(heal_amount)
	effect.healing_done = actual
	
	_log_message("Restored %d integrity." % actual, MessageType.HEAL)
	
	return effect

func get_timing_profile() -> Dictionary:
	return _pending_timing_profile.duplicate(true)

func _build_timing_profile(result: CommandParser.CommandResult) -> Dictionary:
	var profile := {
		"skip_timing": false,
		"force_critical_only": false,
		"difficulty": _get_timing_difficulty(),
		"critical_zone_percent": 0.12,
		"normal_zone_percent": 0.22,
		"instruction": "Press SPACE at the right moment!",
	}

	match result.command_type:
		CommandParser.CommandType.ATTACK, CommandParser.CommandType.DELETE:
			if _should_trigger_overclock_skip():
				profile.skip_timing = true
				profile.difficulty = 1.0
				profile.instruction = "Overclock surge: timing skipped"
		CommandParser.CommandType.DEFEND:
			profile.difficulty = _get_defend_timing_difficulty()
			profile.critical_zone_percent = 0.08 if not _is_skill_unlocked("potion_hardening") else 0.11
			profile.normal_zone_percent = 0.12 if not _is_skill_unlocked("potion_hardening") else 0.16
			profile.instruction = "Press SPACE for a perfect guard!"
		CommandParser.CommandType.HEAL:
			profile.difficulty = clampf(_get_timing_difficulty() - 0.15, 0.5, 2.0)
			profile.critical_zone_percent = 0.14
			profile.normal_zone_percent = 0.24
			profile.instruction = "Press SPACE to restore integrity!"
		CommandParser.CommandType.KILL:
			profile.force_critical_only = true
			profile.difficulty = clampf(_get_timing_difficulty(), 0.8, 2.0)
			profile.critical_zone_percent = 1.0
			profile.normal_zone_percent = 0.0
			profile.instruction = "Critical-only taskkill"
		CommandParser.CommandType.RESTORE:
			profile.difficulty = clampf(_get_timing_difficulty() - 0.05, 0.5, 2.0)

	return profile

func _should_trigger_overclock_skip() -> bool:
	if _overclock_used_this_battle:
		return false
	if not _is_skill_unlocked("potion_overclock"):
		return false
	if randf() > OVERCLOCK_SKIP_CHANCE:
		return false
	_overclock_used_this_battle = true
	return true

func _can_use_heal() -> bool:
	return _heal_uses_remaining > 0

func _can_use_taskkill() -> bool:
	if _taskkill_used_this_battle:
		return false
	if not _is_skill_unlocked("taskkill"):
		return false
	if SceneManager == null:
		return false
	return int(SceneManager.get("data_bits")) >= TASKKILL_DATA_BITS_COST

func _consume_taskkill() -> bool:
	if not _can_use_taskkill():
		return false
	if not SceneManager.spend_data_bits(TASKKILL_DATA_BITS_COST, "combat_taskkill"):
		return false
	_taskkill_used_this_battle = true
	return true

func _get_defend_timing_difficulty() -> float:
	var difficulty := minf(2.0, _get_timing_difficulty() + 0.6)
	if _is_skill_unlocked("potion_hardening"):
		difficulty = maxf(1.55, difficulty - 0.25)
	return clampf(difficulty, 1.4, 2.0)

func _is_skill_unlocked(skill_id: String) -> bool:
	if SceneManager == null:
		return false
	return SceneManager.get("%s_unlocked" % skill_id) == true

func _apply_sudo_privilege_modifiers() -> void:
	if _combat_start_modifiers_applied:
		return
	_combat_start_modifiers_applied = true
	if not _is_skill_unlocked("sudo_privilege"):
		return

	player_state.max_integrity += 25
	player_state.current_integrity += 25
	player_state.attack_power += 5

	if current_enemy:
		current_enemy.max_hp = maxi(1, int(round(current_enemy.max_hp * 1.25)))
		current_enemy.current_hp = current_enemy.max_hp
		current_enemy.attack_power += 4
		current_enemy.defense += 2
		current_enemy.speed += 1

	_log_message("sudo privilege activated: your power rises, but enemies harden too.", MessageType.WARNING)

func _resolve_escape(_result: CommandParser.CommandResult) -> CombatEffect:
	var effect := CombatEffect.new()
	
	# Escape chance based on speed difference
	var escape_chance := 0.3 + (0.1 * (10 - current_enemy.speed))
	
	if randf() < escape_chance:
		_log_message("Escaped successfully!", MessageType.SUCCESS)
		effect.ends_combat = true
		effect.victory = false
	else:
		_log_message("Escape failed!", MessageType.ERROR)
	
	return effect

func _resolve_delete(result: CommandParser.CommandResult) -> CombatEffect:
	var effect := CombatEffect.new()
	var target := result.target.to_lower()
	
	# Check if target matches enemy
	var enemy_keywords := [
		current_enemy.id.to_lower(),
		current_enemy.display_name.to_lower(),
		"enemy",
		"target"
	]
	
	var valid_target := false
	for keyword in enemy_keywords:
		if target.contains(keyword) or keyword.contains(target):
			valid_target = true
			break
	
	if valid_target:
		var base_damage := player_state.attack_power + 5
		
		# Apply timing multiplier
		base_damage = int(base_damage * timing_damage_multiplier)
		
		if timing_was_critical:
			effect.is_critical = true
			_log_message("⭐ PERFECT TIMING! Critical deletion!", MessageType.SUCCESS)
		
		# DELETE is super effective against file-themed enemies
		if current_enemy.weakness == "delete":
			base_damage = int(base_damage * 2.0)
			effect.is_weakness = true
			_log_message("DELETE command is super effective!", MessageType.SUCCESS)
		
		var actual := current_enemy.take_damage(base_damage)
		effect.damage_dealt = actual
		if result.command_type == CommandParser.CommandType.KILL and _skip_enemy_turn_after_command:
			effect.is_critical = true
			effect.special_effect = "skip_enemy_turn"
			_log_message("taskkill injected a fatal critical strike!", MessageType.SUCCESS)
		
		_log_message("rm -f %s ... Deleted %d bytes!" % [target, actual], MessageType.DAMAGE)
		damage_dealt.emit("enemy", actual, effect.is_critical)
	else:
		_log_message("Target '%s' not found. Delete failed." % target, MessageType.ERROR)
		effect.success = false
	
	return effect

func _resolve_find(_result: CommandParser.CommandResult) -> CombatEffect:
	var effect := CombatEffect.new()
	
	# Find reveals enemy weakness if pattern matches
	_log_message("Searching for patterns...", MessageType.INFO)
	
	if not current_enemy.weakness.is_empty():
		_log_message("Found vulnerability: %s" % current_enemy.weakness, MessageType.SUCCESS)
		current_enemy.scan_revealed = true
	else:
		_log_message("No exploitable patterns found.", MessageType.WARNING)
	
	return effect

func _resolve_restore(_result: CommandParser.CommandResult) -> CombatEffect:
	var effect := CombatEffect.new()
	
	# Restore can heal or remove status effects
	if player_state.status_effects.size() > 0:
		var removed: String = player_state.status_effects.pop_back()
		effect.status_removed = removed
		
		if timing_was_critical:
			_log_message("⭐ PERFECT TIMING! All status effects cleared!", MessageType.SUCCESS)
			# Clear all status effects on critical
			while player_state.status_effects.size() > 0:
				player_state.status_effects.pop_back()
		else:
			_log_message("Restored from '%s' status." % removed, MessageType.SUCCESS)
	else:
		# Small heal if no status to remove
		var heal_amount := int(15 * timing_damage_multiplier)
		if timing_was_critical:
			heal_amount = int(heal_amount * 1.5)
			_log_message("⭐ PERFECT TIMING! Maximum restoration!", MessageType.SUCCESS)
		var actual := player_state.heal(heal_amount)
		effect.healing_done = actual
		_log_message("Restored %d integrity." % actual, MessageType.HEAL)
	
	return effect
#endregion

#region Utility

func _log_message(message: String, type: MessageType) -> void:
	combat_log.append(message)
	message_logged.emit(message, type)
	print("[COMBAT] %s" % message)

## Get current combat state for UI
func get_combat_state_dict() -> Dictionary:
	var enemy_dict: Variant = null
	if current_enemy:
		enemy_dict = {
			"name": current_enemy.display_name,
			"hp": current_enemy.current_hp,
			"max_hp": current_enemy.max_hp,
			"scanned": current_enemy.scan_revealed,
		}
	
	return {
		"state": combat_state,
		"turn": current_turn,
		"turn_number": turn_number,
		"player": {
			"integrity": player_state.current_integrity if player_state else 0,
			"max_integrity": player_state.max_integrity if player_state else 100,
			"is_defending": player_state.is_defending if player_state else false,
			"status_effects": player_state.status_effects if player_state else [],
		},
		"enemy": enemy_dict,
		"log": combat_log,
	}
#endregion
