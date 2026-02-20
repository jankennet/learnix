# CombatUIController.gd
# Root coordinator for combat UI - wires signals between combat manager and UI views
# DATA FLOW:
#   TurnCombatManager signals → CombatUIController → TerminalView/HUDView/CombatFX
#   InputController.command_submitted → CombatUIController → TurnCombatManager.process_input()
#
# NEVER touches UI nodes directly. Delegates to sub-controllers.
# Single responsibility: Signal routing and coordination.
extends Control
class_name CombatUIController

#region Exports - Node Paths for Dependency Injection

## Path to the TurnCombatManager node
@export var combat_manager_path: NodePath

## Path to the enemy node (for LostFile encounters)
@export var enemy_node_path: NodePath

## Path to TerminalView controller
@export var terminal_view_path: NodePath

## Path to InputController
@export var input_controller_path: NodePath

## Path to HUDView controller
@export var hud_view_path: NodePath

## Path to CombatFX controller
@export var combat_fx_path: NodePath

#endregion

#region Resolved References

var _combat_manager: Node = null
var _enemy_node: Node = null
var _terminal: TerminalView = null
var _input: InputController = null
var _hud: HUDView = null
var _fx: CombatFX = null

#endregion

#region Initialization

func _ready() -> void:
	_resolve_dependencies()
	_connect_combat_signals()
	_connect_input_signals()
	_initialize_ui()

func _resolve_dependencies() -> void:
	# Resolve TurnCombatManager
	if combat_manager_path and has_node(combat_manager_path):
		_combat_manager = get_node(combat_manager_path)
	else:
		# Fallback: search scene tree
		_combat_manager = get_tree().get_root().find_child("TurnCombatManager", true, false)
	
	if not _combat_manager:
		push_warning("CombatUIController: No TurnCombatManager found. Combat signals disabled.")
	
	# Resolve enemy node (for LostFile encounters)
	if enemy_node_path and has_node(enemy_node_path):
		_enemy_node = get_node(enemy_node_path)
	
	# Resolve TerminalView
	if terminal_view_path and has_node(terminal_view_path):
		_terminal = get_node(terminal_view_path)
	else:
		_terminal = _find_child_of_class("TerminalView")
	
	if not _terminal:
		push_warning("CombatUIController: No TerminalView found. Terminal output disabled.")
	
	# Resolve InputController
	if input_controller_path and has_node(input_controller_path):
		_input = get_node(input_controller_path)
	else:
		_input = _find_child_of_class("InputController")
	
	if not _input:
		push_warning("CombatUIController: No InputController found. Input disabled.")
	
	# Resolve HUDView
	if hud_view_path and has_node(hud_view_path):
		_hud = get_node(hud_view_path)
	else:
		_hud = _find_child_of_class("HUDView")
	
	if not _hud:
		push_warning("CombatUIController: No HUDView found. HUD disabled.")
	
	# Resolve CombatFX
	if combat_fx_path and has_node(combat_fx_path):
		_fx = get_node(combat_fx_path)
	else:
		_fx = _find_child_of_class("CombatFX")
	
	if not _fx:
		push_warning("CombatUIController: No CombatFX found. Effects disabled.")

func _find_child_of_class(class_name_str: String) -> Node:
	for child in get_children():
		if child.get_script() and child.get_script().get_global_name() == class_name_str:
			return child
	return null

func _connect_combat_signals() -> void:
	if not _combat_manager:
		return
	
	# Connect to all combat manager signals
	if _combat_manager.has_signal("message_logged"):
		_combat_manager.connect("message_logged", _on_message_logged)
	
	if _combat_manager.has_signal("awaiting_input"):
		_combat_manager.connect("awaiting_input", _on_awaiting_input)
	
	if _combat_manager.has_signal("turn_changed"):
		_combat_manager.connect("turn_changed", _on_turn_changed)
	
	if _combat_manager.has_signal("damage_dealt"):
		_combat_manager.connect("damage_dealt", _on_damage_dealt)
	
	if _combat_manager.has_signal("player_turn_started"):
		_combat_manager.connect("player_turn_started", _on_player_turn)
	
	if _combat_manager.has_signal("enemy_turn_started"):
		_combat_manager.connect("enemy_turn_started", _on_enemy_turn)

func _connect_input_signals() -> void:
	if _input:
		_input.command_submitted.connect(_on_command_submitted)

func _initialize_ui() -> void:
	# Initial HUD update
	_refresh_hud()
	
	# Focus input
	if _input:
		_input.grab_focus()

#endregion

#region Combat Signal Handlers

func _on_message_logged(message: String, type) -> void:
	if not _terminal:
		return
	
	# Map type to color using TerminalView helper
	var color := _get_message_color(type)
	_terminal.print_message(message, color)

func _on_awaiting_input() -> void:
	if _input:
		_input.set_turn_text("<< YOUR TURN >>")
		_input.set_enabled(true)
		_input.grab_focus()

func _on_turn_changed(turn_owner) -> void:
	if not _input:
		return
	
	if not _combat_manager:
		return
	
	# Access TurnOwner enum from combat manager
	if turn_owner == _combat_manager.TurnOwner.PLAYER:
		_input.set_turn_text("<< YOUR TURN >>")
	elif turn_owner == _combat_manager.TurnOwner.ENEMY:
		_input.set_turn_text("-- ENEMY --")
	else:
		_input.set_turn_text("")

func _on_player_turn() -> void:
	if _input:
		_input.set_turn_text("<< YOUR TURN >>")

func _on_enemy_turn() -> void:
	if _input:
		_input.set_turn_text("-- ENEMY --")

func _on_damage_dealt(target: String, _amount: int, _is_critical: bool) -> void:
	# Visual feedback via CombatFX
	if _fx:
		_fx.hit_target(target)
	
	# Update HUD
	_refresh_hud()

#endregion

#region Input Signal Handlers

func _on_command_submitted(text: String) -> void:
	# Route command to combat manager
	if _combat_manager and _is_player_input_state():
		_combat_manager.process_input(text)
	else:
		# Fallback: try LostFile encounter handler
		_try_lost_file_handler(text)

func _is_player_input_state() -> bool:
	if not _combat_manager:
		return false
	
	# Check if combat_state property exists and equals PLAYER_INPUT
	if "combat_state" in _combat_manager and "CombatState" in _combat_manager:
		return _combat_manager.combat_state == _combat_manager.CombatState.PLAYER_INPUT
	
	return true  # Assume valid if can't check

func _try_lost_file_handler(text: String) -> void:
	# Legacy support for LostFile encounters
	var lost := get_tree().get_root().find_child("LostFileEnemy", true, false)
	if lost and lost.has_method("process_input"):
		lost.process_input(text)

#endregion

#region HUD Updates

func _refresh_hud() -> void:
	if not _hud or not _combat_manager:
		return
	
	# Update player HP
	if "player_state" in _combat_manager and _combat_manager.player_state:
		var ps = _combat_manager.player_state
		if "max_integrity" in ps and "current_integrity" in ps:
			_hud.update_player(ps.current_integrity, ps.max_integrity)
	
	# Update enemy HP
	if "current_enemy" in _combat_manager and _combat_manager.current_enemy:
		var enemy = _combat_manager.current_enemy
		if "max_hp" in enemy and "current_hp" in enemy:
			_hud.update_enemy(enemy.current_hp, enemy.max_hp)

#endregion

#region Message Color Mapping

func _get_message_color(type) -> Color:
	if not _combat_manager:
		return Color(0.8, 0.8, 0.8)
	
	# Map MessageType enum to color
	# MessageType: INFO=0, SUCCESS=1, WARNING=2, ERROR=3, DAMAGE=4, HEAL=5, STATUS=6
	match type:
		_combat_manager.MessageType.SUCCESS:
			return Color(0.4, 1.0, 0.4)  # Green
		_combat_manager.MessageType.ERROR:
			return Color(1.0, 0.3, 0.3)  # Red
		_combat_manager.MessageType.WARNING:
			return Color(1.0, 0.9, 0.3)  # Yellow
		_combat_manager.MessageType.DAMAGE:
			return Color(1.0, 0.5, 0.2)  # Orange
		_combat_manager.MessageType.HEAL:
			return Color(0.5, 1.0, 0.6)  # Light green
		_combat_manager.MessageType.STATUS:
			return Color(1.0, 0.75, 0.2) # Gold
		_combat_manager.MessageType.INFO:
			return Color(0.6, 0.9, 1.0)  # Cyan
		_:
			return Color(0.8, 0.8, 0.8)  # Default gray

#endregion
