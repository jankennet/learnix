# CombatFX.gd
# Visual feedback: shake and flash animations
# DATA FLOW: CombatUIController → CombatFX.hit_player() / hit_enemy()
# Lazily creates animations. No game logic.
extends Node
class_name CombatFX

## Path to the AnimationPlayer for effects
@export var animation_player_path: NodePath

## Path to the player sprite/visual node
@export var player_sprite_path: NodePath

## Path to the enemy sprite/visual node
@export var enemy_sprite_path: NodePath

## Shake intensity in pixels
@export var shake_intensity: float = 5.0

## Shake duration in seconds
@export var shake_duration: float = 0.3

## Flash duration in seconds
@export var flash_duration: float = 0.2

## Flash color for player hit
@export var player_hit_color: Color = Color(1.0, 0.6, 0.2)

## Flash color for enemy hit
@export var enemy_hit_color: Color = Color(1.0, 0.3, 0.3)

## Resolved node references
var _anim: AnimationPlayer = null
var _player_sprite: CanvasItem = null
var _enemy_sprite: CanvasItem = null

## Track created animations to avoid duplicates
var _created_animations: Dictionary = {}

#region Initialization

func _ready() -> void:
	_resolve_nodes()

func _resolve_nodes() -> void:
	# Resolve AnimationPlayer
	if animation_player_path and has_node(animation_player_path):
		_anim = get_node(animation_player_path)
	else:
		push_warning("CombatFX: No AnimationPlayer found. Animations disabled.")
	
	# Resolve player sprite
	if player_sprite_path and has_node(player_sprite_path):
		_player_sprite = get_node(player_sprite_path)
	else:
		push_warning("CombatFX: No player sprite found.")
	
	# Resolve enemy sprite
	if enemy_sprite_path and has_node(enemy_sprite_path):
		_enemy_sprite = get_node(enemy_sprite_path)
	else:
		push_warning("CombatFX: No enemy sprite found.")

#endregion

#region Public API

## Play hit effect on player (shake + flash).
func hit_player() -> void:
	if _player_sprite:
		_shake(_player_sprite)
		_flash(_player_sprite, player_hit_color)

## Play hit effect on enemy (shake + flash).
func hit_enemy() -> void:
	if _enemy_sprite:
		_shake(_enemy_sprite)
		_flash(_enemy_sprite, enemy_hit_color)

## Play hit effect on target by name.
## @param target: "player" or "enemy"
func hit_target(target: String) -> void:
	if target == "enemy":
		hit_enemy()
	else:
		hit_player()

#endregion

#region Animation Implementation

func _shake(node: Node) -> void:
	if not _anim:
		return
	
	if not node is Control:
		push_warning("CombatFX: Shake requires Control node.")
		return
	
	var control_node: Control = node as Control
	var anim_name := "shake_" + str(node.get_instance_id())
	
	# Create animation if not exists
	if not _created_animations.has(anim_name):
		_create_shake_animation(control_node, anim_name)
	
	_anim.play(anim_name)

func _create_shake_animation(node: Control, anim_name: String) -> void:
	if not _anim:
		return
	
	var a := Animation.new()
	a.length = shake_duration
	
	var track_idx := a.add_track(Animation.TYPE_VALUE)
	var node_path := str(get_path_to(node)) + ":position"
	a.track_set_path(track_idx, node_path)
	
	var orig_pos: Vector2 = node.position
	var intensity := shake_intensity
	
	# Keyframes: shake left-right pattern
	a.track_insert_key(track_idx, 0.0, orig_pos)
	a.track_insert_key(track_idx, shake_duration * 0.167, orig_pos + Vector2(intensity, 0))
	a.track_insert_key(track_idx, shake_duration * 0.333, orig_pos + Vector2(-intensity, 0))
	a.track_insert_key(track_idx, shake_duration * 0.5, orig_pos + Vector2(intensity * 0.6, 0))
	a.track_insert_key(track_idx, shake_duration * 0.667, orig_pos + Vector2(-intensity * 0.6, 0))
	a.track_insert_key(track_idx, shake_duration * 0.833, orig_pos)
	
	# Add to animation library
	_ensure_animation_library()
	var lib := _anim.get_animation_library("")
	if lib:
		lib.add_animation(anim_name, a)
		_created_animations[anim_name] = true

func _ensure_animation_library() -> void:
	if not _anim:
		return
	
	if not _anim.has_animation_library(""):
		var lib := AnimationLibrary.new()
		_anim.add_animation_library("", lib)

func _flash(node: CanvasItem, col: Color) -> void:
	if not node:
		return
	
	var orig := node.modulate
	node.modulate = col
	
	# Use tween for smooth flash
	var tween := create_tween()
	tween.tween_property(node, "modulate", orig, flash_duration)

#endregion
