extends Node3D

const BLACK_TEXT_CUTSCENE_SCENE := preload("res://Scenes/ui/black_text_cutscene.tscn")
const EVIL_TUX_DIALOGUE_PATH := "res://dialogues/EvilTuxBoss.dialogue"
const EVIL_TUX_BOSS_SCENE_PATH := "res://Scenes/Levels/evilTuxBoss.tscn"
const FALLBACK_HAMLET_SCENE_PATH := "res://Scenes/Levels/fallback_hamlet.tscn"
const PROPRIETARY_CITADEL_SCENE_PATH := "res://Scenes/Levels/proprietary_citadel.tscn"
const PROPRIETARY_CITADEL_SPAWN := "Spawn_BVTPC"
const EVIL_TUX_RETRY_SKIP_META := "evil_tux_retry_skip_intro"
const EVIL_TUX_BOSS_CLEARED_META_KEY := "evil_tux_boss_cleared"
const EVIL_TUX_ENDGAME_META_KEY := "post_evil_tux_endgame"
const EVIL_TUX_HIDE_NPCS_META_KEY := "hide_all_npcs_post_evil_tux"
const EVIL_TUX_RETURN_SCENE_META_KEY := "evil_tux_return_scene_path"
const EVIL_TUX_RETURN_SPAWN_META_KEY := "evil_tux_return_spawn_name"
const TITLE_MENU_SCENE_PATH := "res://Scenes/ui/title_menu.tscn"
const FINAL_CREDIT_LINES := [
	"LEARNIX",
	"",
	"Proposed as a CAPSTONE PROJECT",
	"for Computer Communication Development Institute",
	"",
	"Proponents:",
	"Analyst and Programmer:",
	"John Kenneth L. Belano",
	"",
	"Documentarian:",
	"Marielle Gaviño",
	"",
	"Story and design:",
	"John Kenneth L. Belano",
	"",
	"Programming:",
	"John Kenneth L. Belano",
	"",
	"Visuals:",
	"Claykit - 3D Assets",
	"Miwabun - 2D Assets",
	"",
	"Music and sound",
	"Pixverses",
    "",
    "Genocide Route",
	"",
	"Thank you for playing!",
]

var _boss_camera: Camera3D = null
var _player_node: Node3D = null
var _boss_started: bool = false
var _ending_started: bool = false
var _defeat_prompt_started: bool = false
var _dialogue_resource: Resource = null
var _encounter_controller: EncounterController = null
var _retry_overlay: CanvasLayer = null
var _retry_panel: Control = null

func _ready() -> void:
	_boss_camera = get_node_or_null("Camera3D") as Camera3D
	if EVIL_TUX_DIALOGUE_PATH != "" and ResourceLoader.exists(EVIL_TUX_DIALOGUE_PATH):
		_dialogue_resource = ResourceLoader.load(EVIL_TUX_DIALOGUE_PATH)
	call_deferred("_start_boss_intro")

func _start_boss_intro() -> void:
	if _boss_started:
		return
	_boss_started = true

	if SceneManager:
		SceneManager.input_locked = true

	_player_node = get_tree().get_first_node_in_group("player") as Node3D
	if _player_node:
		_player_node.visible = false
		_player_node.set_process(false)
		_player_node.set_physics_process(false)
		var player_camera := _player_node.get_node_or_null("Camera3D") as Camera3D
		if player_camera:
			player_camera.current = false

	if _boss_camera:
		_boss_camera.current = true

	await get_tree().process_frame
	var skip_intro := SceneManager and SceneManager.has_meta(EVIL_TUX_RETRY_SKIP_META) and bool(SceneManager.get_meta(EVIL_TUX_RETRY_SKIP_META))
	if skip_intro:
		SceneManager.set_meta(EVIL_TUX_RETRY_SKIP_META, false)
	else:
		await _show_intro_dialogue()
	_start_boss_encounter()

func _show_intro_dialogue() -> void:
	if _dialogue_resource == null:
		return
	var dialogue_manager := get_tree().root.get_node_or_null("DialogueManager")
	if dialogue_manager == null:
		return
	dialogue_manager.show_dialogue_balloon(_dialogue_resource, "start", [self])
	if dialogue_manager.has_signal("dialogue_ended"):
		await dialogue_manager.dialogue_ended

func _start_boss_encounter() -> void:
	if _ending_started:
		return

	_encounter_controller = EncounterController.new()
	if _encounter_controller == null:
		push_error("[EvilTuxBoss] EncounterController not found")
		return

	_encounter_controller.encounter_id = "evil_tux"
	_encounter_controller.auto_start = false
	get_tree().current_scene.add_child(_encounter_controller)
	await get_tree().process_frame
	if _encounter_controller.combat_manager and not _encounter_controller.combat_manager.combat_ended.is_connected(_on_boss_combat_ended):
		_encounter_controller.combat_manager.combat_ended.connect(_on_boss_combat_ended)
	if not _encounter_controller.encounter_ended.is_connected(_on_boss_encounter_ended):
		_encounter_controller.encounter_ended.connect(_on_boss_encounter_ended)
	_encounter_controller.start_encounter()
	_ending_started = true

func _on_boss_encounter_ended(method: String) -> void:
	if method not in ["combat_victory", "puzzle_solved"]:
		return
	call_deferred("_run_final_end_sequence")

func _on_boss_combat_ended(victory: bool, _enemy_data) -> void:
	if victory:
		return
	if _defeat_prompt_started:
		return
	_defeat_prompt_started = true
	call_deferred("_run_defeat_retry_sequence")

func _run_final_end_sequence() -> void:
	if SceneManager:
		SceneManager.input_locked = true
	await _show_credit_roll()
	
	var is_bad_karma := SceneManager and String(SceneManager.player_karma) == "bad"
	var is_good_passed_sage := SceneManager and String(SceneManager.player_karma) == "good" and bool(SceneManager.get_meta("bios_vault_sage_quiz_passed", false))
	var _is_good_killed_sage := SceneManager and String(SceneManager.player_karma) == "good" and bool(SceneManager.get_meta("bios_vault_sage_defeated", false)) and not is_good_passed_sage
	
	if is_good_passed_sage:
		await _show_good_pass_ending_cutscene()
		await _show_final_black_cutscene("You can wake up now.", 2.8)
	else:
		await _show_final_black_cutscene("I\'ll see you again." if is_bad_karma else "You can wake up now.", 2.8)
	
	if SceneManager:
		SceneManager.stop_music()
		SceneManager.set_meta(EVIL_TUX_BOSS_CLEARED_META_KEY, true)
		SceneManager.set_meta(EVIL_TUX_RETURN_SCENE_META_KEY, FALLBACK_HAMLET_SCENE_PATH if is_bad_karma else PROPRIETARY_CITADEL_SCENE_PATH)
		SceneManager.set_meta(EVIL_TUX_RETURN_SPAWN_META_KEY, "first_spawn" if is_bad_karma else PROPRIETARY_CITADEL_SPAWN)
		SceneManager.set_meta(EVIL_TUX_ENDGAME_META_KEY, is_bad_karma)
		if is_good_passed_sage:
			SceneManager.set_meta("good_karma_passed_sage_reward", true)
		if is_bad_karma:
			SceneManager.set_meta(EVIL_TUX_HIDE_NPCS_META_KEY, true)
		else:
			if SceneManager.has_meta(EVIL_TUX_HIDE_NPCS_META_KEY):
				SceneManager.remove_meta(EVIL_TUX_HIDE_NPCS_META_KEY)
		SceneManager.save_game()
	get_tree().change_scene_to_file(TITLE_MENU_SCENE_PATH)

func _run_defeat_retry_sequence() -> void:
	if SceneManager:
		SceneManager.input_locked = true
	await get_tree().create_timer(1.2).timeout
	await _show_final_black_cutscene("You can still get back up.", 1.8)
	_show_retry_overlay()

func _show_retry_overlay() -> void:
	_cleanup_retry_overlay()
	_retry_overlay = CanvasLayer.new()
	_retry_overlay.layer = 210
	_retry_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_retry_overlay)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.82)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_retry_overlay.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_retry_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 260)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	_retry_panel = panel

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Evil Tux is still shaking."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var body := Label.new()
	body.text = "You can try again now, or leave and come back later."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(640, 80)
	vbox.add_child(body)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 18)
	vbox.add_child(button_row)

	var retry_button := Button.new()
	retry_button.text = "Retry Fight"
	retry_button.custom_minimum_size = Vector2(220, 48)
	retry_button.pressed.connect(retry_evil_tux_boss)
	button_row.add_child(retry_button)

	var leave_button := Button.new()
	leave_button.text = "Leave"
	leave_button.custom_minimum_size = Vector2(220, 48)
	leave_button.pressed.connect(decline_evil_tux_retry)
	button_row.add_child(leave_button)

	retry_button.grab_focus()

func _cleanup_retry_overlay() -> void:
	if _retry_overlay and is_instance_valid(_retry_overlay):
		_retry_overlay.queue_free()
	_retry_overlay = null
	_retry_panel = null

func retry_evil_tux_boss() -> void:
	_cleanup_retry_overlay()
	if SceneManager:
		SceneManager.set_meta(EVIL_TUX_RETRY_SKIP_META, true)
	call_deferred("_restart_boss_scene")

func decline_evil_tux_retry() -> void:
	_cleanup_retry_overlay()
	call_deferred("_return_to_citadel")

func _restart_boss_scene() -> void:
	if SceneManager:
		await SceneManager.teleport_to_scene(EVIL_TUX_BOSS_SCENE_PATH, "", 0.5)

func _return_to_citadel() -> void:
	if SceneManager:
		await SceneManager.teleport_to_scene(PROPRIETARY_CITADEL_SCENE_PATH, PROPRIETARY_CITADEL_SPAWN, 0.5)

func _show_good_pass_ending_cutscene() -> void:
	var cutscene := BLACK_TEXT_CUTSCENE_SCENE.instantiate()
	if cutscene == null:
		return
	get_tree().root.add_child(cutscene)
	if cutscene.has_method("play"):
		await cutscene.play("[PLACEHOLDER: Good Ending Special Cutscene]", 3.0)
	cutscene.queue_free()

func _show_final_black_cutscene(message_text: String, hold_duration: float) -> void:
	var cutscene := BLACK_TEXT_CUTSCENE_SCENE.instantiate()
	if cutscene == null:
		return
	get_tree().root.add_child(cutscene)
	if cutscene.has_method("play"):
		await cutscene.play(message_text, hold_duration)
	cutscene.queue_free()

func _show_credit_roll() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 240
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(overlay)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 1)
	overlay.add_child(backdrop)

	var clip := Control.new()
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(clip)

	var scroll := VBoxContainer.new()
	scroll.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_theme_constant_override("separation", 24)
	scroll.custom_minimum_size = Vector2(1200, 0)
	clip.add_child(scroll)

	for line_text in FINAL_CREDIT_LINES:
		var label := Label.new()
		label.text = line_text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0, 1.0))
		label.add_theme_font_size_override("font_size", 34 if line_text != "" else 18)
		label.custom_minimum_size = Vector2(1200, 56 if line_text != "" else 30)
		scroll.add_child(label)

	await get_tree().process_frame
	var viewport_size := get_viewport().get_visible_rect().size
	var content_height := scroll.get_combined_minimum_size().y
	var start_y := viewport_size.y + 64.0
	var end_y := -content_height - 96.0
	scroll.position = Vector2((viewport_size.x - scroll.custom_minimum_size.x) * 0.5, start_y)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(scroll, "position:y", end_y, 22.0)
	var fade_in := create_tween()
	fade_in.tween_property(backdrop, "modulate:a", 1.0, 1.6)
	await fade_in.finished
	await tween.finished
	await get_tree().create_timer(1.4).timeout
	overlay.queue_free()
