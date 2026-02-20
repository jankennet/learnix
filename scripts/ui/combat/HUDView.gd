# HUDView.gd
# Pure HUD rendering: Player and Enemy HP bars
# DATA FLOW: CombatUIController → HUDView.update_player() / update_enemy()
# NO signals emitted. NO game logic. Just visual display.
extends Control
class_name HUDView

## Path to the player HP ProgressBar
@export var player_bar_path: NodePath

## Path to the enemy HP ProgressBar
@export var enemy_bar_path: NodePath

## Path to optional commands list RichTextLabel
@export var commands_list_path: NodePath

## Resolved node references
var _player_bar: ProgressBar = null
var _enemy_bar: ProgressBar = null
var _commands_list: RichTextLabel = null

#region Initialization

func _ready() -> void:
	_resolve_nodes()
	_setup_commands_list()

func _resolve_nodes() -> void:
	# Resolve player HP bar
	if player_bar_path and has_node(player_bar_path):
		_player_bar = get_node(player_bar_path)
	else:
		push_warning("HUDView: No player HP bar found at path.")
	
	# Resolve enemy HP bar
	if enemy_bar_path and has_node(enemy_bar_path):
		_enemy_bar = get_node(enemy_bar_path)
	else:
		push_warning("HUDView: No enemy HP bar found at path.")
	
	# Resolve commands list (optional)
	if commands_list_path and has_node(commands_list_path):
		_commands_list = get_node(commands_list_path)

func _setup_commands_list() -> void:
	if _commands_list:
		_commands_list.bbcode_enabled = true
		_commands_list.clear()
		_commands_list.append_text("[color=#66f266]AVAILABLE COMMANDS:[/color]\n[color=#80f280]attack, delete, restore, scan,\ndefend, heal, find, escape, help[/color]")

#endregion

#region Public API

## Update player HP bar display.
## @param hp: Current HP value
## @param max_hp: Maximum HP value
func update_player(hp: int, max_hp: int) -> void:
	if _player_bar:
		_player_bar.max_value = max_hp
		_player_bar.value = hp

## Update enemy HP bar display.
## @param hp: Current HP value
## @param max_hp: Maximum HP value
func update_enemy(hp: int, max_hp: int) -> void:
	if _enemy_bar:
		_enemy_bar.max_value = max_hp
		_enemy_bar.value = hp

## Update both HP bars from combat manager state.
## Convenience method for coordinator use.
## @param player_hp: Current player HP
## @param player_max: Max player HP
## @param enemy_hp: Current enemy HP
## @param enemy_max: Max enemy HP
func update_all(player_hp: int, player_max: int, enemy_hp: int, enemy_max: int) -> void:
	update_player(player_hp, player_max)
	update_enemy(enemy_hp, enemy_max)

## Set commands list text (if available).
## @param text: BBCode formatted text
func set_commands_text(text: String) -> void:
	if _commands_list:
		_commands_list.clear()
		_commands_list.append_text(text)

#endregion
