extends Node3D
## Handles proprietary citadel level setup based on player karma

const BLACK_TEXT_CUTSCENE_SCENE := preload("res://Scenes/ui/black_text_cutscene.tscn")
const EVIL_TUX_BOSS_SCENE_PATH := "res://Scenes/Levels/evilTuxBoss.tscn"
const TUX_REWARD_POPUP_SCRIPT_PATH := "res://scripts/ui/digital_reward_popup.gd"
const TUX_REWARD_TEXTURE_PATH := "res://Assets/characterSpriteSheets/ss_Tux/bossTux_idle.png"
const SPECIAL_END_CREDITS_VIDEO_PATH := "res://Assets/secret/SpecialEndCreds.ogv"
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
	"Miwabun - Character Designer / 2D Artist",
	"",
	"Music and sound",
	"Pixverses",
	"",
	"Pacifist Route, not True ending tho",
	"",
	"Thank you for playing!",
]

@export var good_karma_sky_color: Color = Color(0.1, 0.5, 1.0, 1.0)  # Bright blue
@export var bad_karma_env_color: Color = Color(0.3, 0.3, 0.4, 1.0)   # Dark gray/slate
@export var good_pass_reward_label: String = "Tux Desktop Reward Placeholder"

var world_environment: WorldEnvironment
var environment: Environment
var directional_light: DirectionalLight3D
var _base_light_color: Color = Color.WHITE
var _base_light_energy: float = 1.0
var _ending_sequence_started: bool = false
var _tux_node: Node3D = null

func _ready() -> void:
	world_environment = get_node_or_null("WorldEnvironment")
	if world_environment:
		environment = world_environment.environment

	directional_light = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if directional_light:
		_base_light_color = directional_light.light_color
		_base_light_energy = directional_light.light_energy

	_tux_node = get_node_or_null("NPCs/Tux") as Node3D
	
	_apply_karma_sky()

func _apply_karma_sky() -> void:
	if not environment:
		return
	
	var karma = SceneManager.player_karma if SceneManager else "neutral"

	# Proprietary Citadel has two intended moods in this arc:
	# high karma => sunny; anything else => dark/genocide tone.
	if karma == "good":
		_set_bright_blue_sky()
	else:
		_set_dark_sky()

func _set_bright_blue_sky() -> void:
	"""Set a bright blue sky for good karma"""
	if not environment:
		return
	
	# Change background to a solid color
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = good_karma_sky_color
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 1.0
	if directional_light:
		directional_light.light_color = _base_light_color
		directional_light.light_energy = _base_light_energy

func _set_dark_sky() -> void:
	"""Set a dark sky with reduced lighting for bad karma"""
	if not environment:
		return
	
	# Change background to a solid dark color
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = bad_karma_env_color
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	environment.ambient_light_energy = 0.6
	if directional_light:
		directional_light.light_color = Color(0.5, 0.54, 0.65, 1.0)
		directional_light.light_energy = maxf(0.15, _base_light_energy * 0.35)

func has_good_karma() -> bool:
	return SceneManager and String(SceneManager.player_karma) == "good"

func has_passed_sage() -> bool:
	return SceneManager and bool(SceneManager.bios_vault_sage_quiz_passed)

func has_defeated_sage() -> bool:
	return SceneManager and bool(SceneManager.bios_vault_sage_defeated)

func start_good_pass_ending() -> void:
	if _ending_sequence_started:
		return
	_ending_sequence_started = true
	call_deferred("_run_good_pass_ending_sequence")

func start_good_kill_ending() -> void:
	if _ending_sequence_started:
		return
	_ending_sequence_started = true
	call_deferred("_run_good_kill_ending_sequence")

func start_bad_kill_ending() -> void:
	if _ending_sequence_started:
		return
	_ending_sequence_started = true
	call_deferred("_run_bad_kill_to_boss_sequence")

func start_evil_tux_boss_fight() -> void:
	# Play the ominous evil tux music
	if SceneManager:
		SceneManager.play_music_for_key("ominous_secret_evil_tux")
	
	if _ending_sequence_started:
		return
	_ending_sequence_started = true
	call_deferred("_run_bad_kill_to_boss_sequence")

func _hide_tux_npc() -> void:
	if _tux_node == null or not is_instance_valid(_tux_node):
		_tux_node = get_node_or_null("NPCs/Tux") as Node3D
	if _tux_node == null:
		return
	if _tux_node.has_method("_hide_self"):
		_tux_node.call("_hide_self", true)
	else:
		_tux_node.visible = false
		_tux_node.set_process(false)
		_tux_node.set_physics_process(false)

func _show_reward_popup_placeholder() -> void:
	var popup_script := load(TUX_REWARD_POPUP_SCRIPT_PATH)
	if popup_script == null:
		return
	var popup = popup_script.new()
	if popup == null:
		return
	get_tree().root.add_child(popup)
	var reward_texture: Texture2D = null
	if ResourceLoader.exists(TUX_REWARD_TEXTURE_PATH):
		reward_texture = load(TUX_REWARD_TEXTURE_PATH)
	if popup.has_method("show_key_reward"):
		popup.call("show_key_reward", good_pass_reward_label, reward_texture)

func _spawn_black_cutscene(message_text: String, hold_duration: float = 2.5, start_black_immediately: bool = false) -> CanvasLayer:
	var cutscene := BLACK_TEXT_CUTSCENE_SCENE.instantiate()
	if cutscene == null:
		return null
	if start_black_immediately:
		cutscene.start_black_immediately = true
	get_tree().root.add_child(cutscene)
	if cutscene.has_method("play"):
		cutscene.call_deferred("play", message_text, hold_duration)
	return cutscene

func _spawn_black_cutscene_and_wait(message_text: String, hold_duration: float = 2.5, start_black_immediately: bool = false) -> void:
	var cutscene := _spawn_black_cutscene(message_text, hold_duration, start_black_immediately)
	if cutscene and cutscene.has_signal("finished"):
		await cutscene.finished

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

func _run_good_pass_ending_sequence() -> void:
	if SceneManager:
		SceneManager.input_locked = true
	_hide_tux_npc()
	await _play_special_end_credits_with_fade()
	if SceneManager:
		SceneManager.stop_music()
		SceneManager.set_meta("evil_tux_boss_cleared", true)
		SceneManager.set_meta("evil_tux_return_scene_path", "res://Scenes/Levels/fallback_hamlet.tscn")
		SceneManager.set_meta("evil_tux_return_spawn_name", "first_spawn")
		SceneManager.set_meta("evil_tux_endgame_bad", false)
		SceneManager.set_meta("good_karma_passed_sage_reward", true)
		SceneManager.save_game()
	if SceneManager:
		await SceneManager.teleport_to_scene("res://Scenes/ui/title_menu.tscn", "", 0.5, false)
	else:
		get_tree().change_scene_to_file("res://Scenes/ui/title_menu.tscn")

func _run_good_kill_ending_sequence() -> void:
	if SceneManager:
		SceneManager.input_locked = true
	_hide_tux_npc()
	await _show_credit_roll()
	await _show_final_black_cutscene("You can wake up now.", 3.0)
	if SceneManager:
		SceneManager.stop_music()
		SceneManager.set_meta("evil_tux_boss_cleared", true)
		SceneManager.set_meta("evil_tux_return_scene_path", "res://Scenes/Levels/fallback_hamlet.tscn")
		SceneManager.set_meta("evil_tux_return_spawn_name", "first_spawn")
		SceneManager.set_meta("evil_tux_endgame_bad", false)
		SceneManager.save_game()
	if SceneManager:
		await SceneManager.teleport_to_scene("res://Scenes/ui/title_menu.tscn", "", 0.5, false)
	else:
		get_tree().change_scene_to_file("res://Scenes/ui/title_menu.tscn")

func _run_bad_kill_to_boss_sequence() -> void:
	if SceneManager:
		SceneManager.input_locked = true
	_hide_tux_npc()
	await _run_light_flicker_sequence()
	if SceneManager:
		await SceneManager.teleport_to_scene(EVIL_TUX_BOSS_SCENE_PATH, "", 0.5)

func _run_light_flicker_sequence() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 220
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0, 0, 0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(rect)
	get_tree().root.add_child(overlay)

	for i in range(3):
		var fade_in := create_tween()
		fade_in.tween_property(rect, "color:a", 0.95, 0.12)
		await fade_in.finished
		if i == 2:
			break
		await get_tree().create_timer(0.08).timeout
		var fade_out := create_tween()
		fade_out.tween_property(rect, "color:a", 0.0, 0.12)
		await fade_out.finished
		await get_tree().create_timer(0.07).timeout

	rect.color.a = 0.95
	await get_tree().create_timer(0.12).timeout
	overlay.queue_free()

func _play_special_end_credits_with_fade() -> void:
	if SceneManager:
		SceneManager.stop_music()

	if not ResourceLoader.exists(SPECIAL_END_CREDITS_VIDEO_PATH):
		push_warning("Special end credits video not found: " + SPECIAL_END_CREDITS_VIDEO_PATH)
		push_warning("Falling back to black cutscene.")
		await _show_final_black_cutscene("You can wake up now.", 3.0)
		return

	var cutscene := BLACK_TEXT_CUTSCENE_SCENE.instantiate()
	if cutscene == null:
		await _show_final_black_cutscene("You can wake up now.", 3.0)
		return

	get_tree().root.add_child(cutscene)
	var played_video := false
	if cutscene.has_method("play_embedded_video"):
		await cutscene.play_embedded_video(0.5, 0.8)
		played_video = true
	else:
		await _show_final_black_cutscene("You can wake up now.", 3.0)

	if is_instance_valid(cutscene):
		cutscene.queue_free()

	if played_video:
		await _show_final_black_cutscene("You can wake up now.", 3.0)

	await get_tree().create_timer(0.3).timeout
