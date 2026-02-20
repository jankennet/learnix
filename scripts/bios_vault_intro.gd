extends Node3D

@export var intro_dialogue_path: String = "res://dialogues/BiosVaultIntro.dialogue"
@export var camera_pan_duration: float = 2.0
@export var sage_reveal_duration: float = 2.2
@export var sage_combat_encounter_id: String = "printer_beast"

var _intro_playing: bool = false
var _sage_combat_started: bool = false
var _dialogue_resource: Resource = null
var _sage_sprite: AnimatedSprite3D = null
var _sage_start_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	if intro_dialogue_path != "" and ResourceLoader.exists(intro_dialogue_path):
		_dialogue_resource = ResourceLoader.load(intro_dialogue_path)

	_sage_sprite = get_node_or_null("CharacterBody3D/AnimatedSprite3D") as AnimatedSprite3D
	if _sage_sprite:
		_sage_start_pos = _sage_sprite.position
		_sage_sprite.modulate.a = 0.0
		_sage_sprite.position = _sage_start_pos + Vector3(0.0, -0.45, 0.9)

	call_deferred("_play_intro_sequence")

func _play_intro_sequence() -> void:
	if _intro_playing:
		return
	_intro_playing = true

	if SceneManager:
		SceneManager.input_locked = true

	await get_tree().process_frame
	await get_tree().process_frame

	var player: CharacterBody3D = _find_player()
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null and player:
		cam = player.get_node_or_null("Camera3D") as Camera3D

	var nova_context: Object = self
	if player:
		nova_context = player

	await _show_intro_dialogue("nova_where", [nova_context])
	await _pan_camera_left_to_right(cam)
	await _show_intro_dialogue("sage_intro", [self])
	await _reveal_sage_from_screens()
	await _show_intro_dialogue("sage_skill_check", [self])

	if SceneManager:
		SceneManager.input_locked = false

	_intro_playing = false

func _show_intro_dialogue(start_title: String, context_args: Array) -> void:
	if _dialogue_resource == null:
		return
	var dm = get_tree().root.get_node_or_null("DialogueManager")
	if dm == null:
		return
	dm.show_dialogue_balloon(_dialogue_resource, start_title, context_args)
	if dm.has_signal("dialogue_ended"):
		await dm.dialogue_ended

func _pan_camera_left_to_right(cam: Camera3D) -> void:
	if cam == null:
		return

	var start_pos := cam.global_position
	var left_target := start_pos + Vector3(-1.5, 0.0, 0.0)
	var right_target := start_pos + Vector3(1.8, 0.0, 0.0)

	var rig := cam.get_parent()
	var had_processing := false
	if rig:
		had_processing = rig.is_processing()
		rig.set_process(false)

	var target_look := global_position + Vector3(0.0, 1.6, -1.0)

	cam.global_position = left_target
	cam.look_at(target_look, Vector3.UP)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cam, "global_position", right_target, camera_pan_duration)
	await tween.finished

	cam.look_at(target_look, Vector3.UP)

	if rig:
		rig.set_process(had_processing)

func _reveal_sage_from_screens() -> void:
	if _sage_sprite == null:
		return

	_sage_sprite.show()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_sage_sprite, "modulate:a", 1.0, sage_reveal_duration)
	tween.tween_property(_sage_sprite, "position", _sage_start_pos, sage_reveal_duration)
	await tween.finished

func _find_player() -> CharacterBody3D:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is CharacterBody3D:
		return players[0] as CharacterBody3D
	return null

func mark_sage_quiz_passed() -> void:
	if SceneManager:
		SceneManager.set_meta("bios_vault_sage_quiz_passed", true)

func start_sage_combat() -> void:
	if _sage_combat_started:
		return
	_sage_combat_started = true
	call_deferred("_start_sage_combat_deferred")

func _start_sage_combat_deferred() -> void:
	if SceneManager:
		SceneManager.input_locked = false

	var EncounterControllerScript = load("res://scripts/combat/encounter_controller.gd")
	if EncounterControllerScript == null:
		push_error("[BiosVaultIntro] EncounterController not found")
		_sage_combat_started = false
		return

	var ec = EncounterControllerScript.new()
	ec.encounter_id = sage_combat_encounter_id
	ec.set_meta("start_in_combat", true)
	get_tree().current_scene.add_child(ec)
	ec.start_encounter()
