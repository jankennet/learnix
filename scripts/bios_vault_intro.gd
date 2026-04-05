extends Node3D

@export var intro_dialogue_path: String = "res://dialogues/BiosVaultIntro.dialogue"
@export var camera_pan_duration: float = 2.0
@export var sage_reveal_duration: float = 2.2
@export var sage_combat_encounter_id: String = "sage"
@export var bios_vault_camera_path: NodePath = "Camera3D"
@export var pre_citadel_cutscene_duration: float = 4.0

const PROPRIETARY_CITADEL_SCENE_PATH := "res://Scenes/Levels/proprietary_citadel.tscn"
const PROPRIETARY_CITADEL_SPAWN := "Spawn_BVTPC"
const BLACK_TEXT_CUTSCENE_SCENE := preload("res://Scenes/ui/black_text_cutscene.tscn")

var _intro_playing: bool = false
var _sage_combat_started: bool = false
var _dialogue_resource: Resource = null
var _sage_sprite: AnimatedSprite3D = null
var _sage_start_pos: Vector3 = Vector3.ZERO
var _player_camera: Camera3D = null
var _vault_camera: Camera3D = null
var _sage_area_intro: Area3D = null
var _sage_area_triggered: bool = false
var _sage_encounter_controller: Node = null
var _citadel_transition_started: bool = false

var _quiz_question_order: Array = []
var _quiz_current_index: int = 0
var _quiz_questions: Dictionary = {
	1: "q1", 2: "q2", 3: "q3", 4: "q4", 5: "q5",
	6: "q6", 7: "q7", 8: "q8", 9: "q9", 10: "q10",
	11: "q11", 12: "q12", 13: "q13", 14: "q14", 15: "q15"
}

func _ready() -> void:
	if intro_dialogue_path != "" and ResourceLoader.exists(intro_dialogue_path):
		_dialogue_resource = ResourceLoader.load(intro_dialogue_path)

	_sage_sprite = get_node_or_null("Sage/AnimatedSprite3D") as AnimatedSprite3D
	if _sage_sprite:
		_sage_start_pos = _sage_sprite.position
		_sage_sprite.modulate.a = 0.0
		_sage_sprite.position = _sage_start_pos + Vector3(0.0, -0.45, 0.9)

	_vault_camera = get_node_or_null(bios_vault_camera_path) as Camera3D

	_sage_area_intro = get_node_or_null("BiosVault/SageArea-Intro") as Area3D
	if _sage_area_intro:
		_sage_area_intro.body_entered.connect(_on_sage_area_entered)

func _play_intro_sequence() -> void:
	if _intro_playing:
		return
	_intro_playing = true

	if SceneManager:
		SceneManager.input_locked = true

	await get_tree().process_frame
	await get_tree().process_frame

	var player: CharacterBody3D = _find_player()
	if player:
		player.velocity = Vector3.ZERO

	if player:
		_player_camera = player.get_node_or_null("Camera3D") as Camera3D

	_compute_sage_assessment()

	var cam: Camera3D = null
	if _vault_camera and player:
		await _shake_camera(_vault_camera, 0.4, 0.15)
		_position_vault_camera_for_sage(player)
		_vault_camera.current = true
		cam = _vault_camera
	elif _player_camera:
		cam = _player_camera
	else:
		cam = get_viewport().get_camera_3d()

	var nova_context: Object = self
	if player:
		nova_context = player

	await _show_intro_dialogue("sage_rules", [nova_context])
	await _pan_camera_left_to_right(cam)
	await _show_intro_dialogue("sage_intro", [self])
	await _reveal_sage_from_screens()
	await _show_intro_dialogue("sage_skill_check", [self])

	if _player_camera:
		_player_camera.current = true

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
	var left_target := start_pos + Vector3(-1.2, 0.25, 0.0)
	var right_target := start_pos + Vector3(1.6, 0.25, 0.0)

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

func _position_vault_camera_for_sage(player: CharacterBody3D) -> void:
	if _vault_camera == null:
		return

	var sage_node := get_node_or_null("Sage") as Node3D
	if sage_node == null:
		return

	var midpoint := (player.global_position + sage_node.global_position) * 0.5
	var camera_pos := midpoint + Vector3(0.0, 2.6, 6.2)
	_vault_camera.global_position = camera_pos
	_vault_camera.look_at(sage_node.global_position + Vector3(0.0, 1.8, 0.0), Vector3.UP)

func _compute_sage_assessment() -> void:
	if not SceneManager:
		return

	var completed_quests := 0
	if SceneManager.quest_manager:
		for quest_id in SceneManager.quest_manager.quests.keys():
			var quest = SceneManager.quest_manager.quests[quest_id]
			if quest != null and str(quest.status) == "completed":
				completed_quests += 1

	var boss_or_miniboss_progress := (
		SceneManager.proficiency_key_forest
		or SceneManager.proficiency_key_printer
		or SceneManager.driver_remnant_defeated
		or SceneManager.printer_beast_defeated
	)

	var narrative_progress := (
		SceneManager.helped_lost_file
		or SceneManager.met_messy_directory
		or SceneManager.met_elder_shell
		or SceneManager.met_broken_installer
		or SceneManager.met_gate_keeper
	)

	SceneManager.sage_boss_only_progress = boss_or_miniboss_progress and not narrative_progress and completed_quests <= 1
	SceneManager.sage_has_many_quests = completed_quests >= 2 or (boss_or_miniboss_progress and narrative_progress)

	if SceneManager.sage_boss_only_progress:
		SceneManager.sage_quiz_tier = "hard"
	elif SceneManager.sage_has_many_quests:
		SceneManager.sage_quiz_tier = "easy_intermediate"
	else:
		SceneManager.sage_quiz_tier = "intermediate"

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

func _on_sage_area_entered(body: Node) -> void:
	if _sage_area_triggered or _intro_playing:
		return

	if body.is_in_group("player"):
		_sage_area_triggered = true
		_play_intro_sequence()

func _shake_camera(cam: Camera3D, duration: float, intensity: float) -> void:
	if cam == null:
		return

	var original_pos := cam.global_position
	var elapsed := 0.0

	while elapsed < duration:
		var offset := Vector3(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		cam.global_position = original_pos + offset
		elapsed += 0.016
		await get_tree().process_frame

	cam.global_position = original_pos


func mark_sage_quiz_passed() -> void:
	if SceneManager:
		SceneManager.sage_quiz_fail_count = 0
		SceneManager.sage_force_combat = false
		SceneManager.set_meta("bios_vault_sage_quiz_passed", true)
		var tux_ctrl = SceneManager.get_node_or_null("TuxDialogueController")
		if tux_ctrl and tux_ctrl.has_method("on_sage_quiz_passed"):
			tux_ctrl.call("on_sage_quiz_passed")

	call_deferred("_begin_post_sage_transition", "puzzle_solved")

func reset_sage_quiz_attempts() -> void:
	if SceneManager:
		SceneManager.sage_quiz_fail_count = 0
		SceneManager.sage_force_combat = false

func register_sage_quiz_fail() -> void:
	if not SceneManager:
		return

	SceneManager.sage_quiz_fail_count += 1
	if SceneManager.sage_quiz_fail_count >= 3:
		SceneManager.sage_force_combat = true

func start_sage_combat() -> void:
	if _sage_combat_started:
		return
	if SceneManager:
		SceneManager.sage_force_combat = true
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
	
	# Store reference and connect to encounter end signal
	_sage_encounter_controller = ec
	if ec.has_signal("encounter_ended"):
		ec.encounter_ended.connect(_on_sage_encounter_ended)
	
	ec.start_encounter()
func shuffle_quiz_questions() -> void:
	_quiz_question_order = []
	for i in range(1, 16):
		_quiz_question_order.append(i)
	_quiz_question_order.shuffle()
	_quiz_current_index = 0

func show_next_question() -> void:
	if _quiz_current_index >= _quiz_question_order.size():
		# All questions answered correctly
		if _dialogue_resource == null:
			return
		var dialogue_manager = get_tree().root.get_node_or_null("DialogueManager")
		if dialogue_manager == null:
			return
		dialogue_manager.show_dialogue_balloon(_dialogue_resource, "quiz_pass", [self])
		if dialogue_manager.has_signal("dialogue_ended"):
			await dialogue_manager.dialogue_ended
		return
	
	var question_num = _quiz_question_order[_quiz_current_index]
	var question_node = _quiz_questions.get(question_num, "")
	
	if question_node == "":
		push_error("Invalid question number: ", question_num)
		return
	
	_quiz_current_index += 1
	
	# Show the question dialogue
	if _dialogue_resource == null:
		return
	
	var dm = get_tree().root.get_node_or_null("DialogueManager")
	if dm == null:
		return
	
	dm.show_dialogue_balloon(_dialogue_resource, question_node, [self])
	if dm.has_signal("dialogue_ended"):
		await dm.dialogue_ended

func _on_sage_encounter_ended(method: String) -> void:
	# Called when sage combat/puzzle ends
	# method can be: "combat_victory", "puzzle_solved", or "fled"
	
	if method in ["combat_victory", "puzzle_solved"]:
		_begin_post_sage_transition(method)

func _begin_post_sage_transition(method: String) -> void:
	if _citadel_transition_started:
		return

	_citadel_transition_started = true

	# Player cleared the sage encounter - transition to proprietary citadel
	if SceneManager:
		SceneManager.input_locked = true

	_start_persistent_citadel_transition(method)

func _start_persistent_citadel_transition(method: String) -> void:
	var cutscene_text := _get_pre_citadel_text(method)
	if cutscene_text.is_empty():
		if SceneManager:
			SceneManager.teleport_to_scene(PROPRIETARY_CITADEL_SCENE_PATH, PROPRIETARY_CITADEL_SPAWN, 0.5)
		return

	var cutscene := BLACK_TEXT_CUTSCENE_SCENE.instantiate()
	if cutscene == null:
		if SceneManager:
			SceneManager.teleport_to_scene(PROPRIETARY_CITADEL_SCENE_PATH, PROPRIETARY_CITADEL_SPAWN, 0.5)
		return

	get_tree().root.add_child(cutscene)

	if cutscene.has_method("play_teleport_transition"):
		cutscene.call_deferred(
			"play_teleport_transition",
			PROPRIETARY_CITADEL_SCENE_PATH,
			PROPRIETARY_CITADEL_SPAWN,
			cutscene_text,
			max(pre_citadel_cutscene_duration, 8.0),
			0.5
		)
	else:
		if SceneManager:
			SceneManager.teleport_to_scene(PROPRIETARY_CITADEL_SCENE_PATH, PROPRIETARY_CITADEL_SPAWN, 0.5)

func _get_pre_citadel_text(method: String) -> String:
	var high_karma := SceneManager and String(SceneManager.player_karma) == "good"
	var killed_sage := method == "combat_victory"

	if high_karma and not killed_sage:
		return "You pass. Tux is waiting for you."
	if high_karma and killed_sage:
		return "I won... so why does it feel like I lost something?"
	if not high_karma and killed_sage:
		return "Tux is waiting for you."

	# Fallback for any unhandled karma/outcome combination.
	return "The path opens ahead. Tux is waiting for you."
