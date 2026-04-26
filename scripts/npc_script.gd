extends Node3D

const DIALOGUE_CANCEL_LOCK_META_KEY := "dialogue_cancel_locked"
const BIOS_VAULT_GATEKEEPER_ARRIVAL_META_KEY := "bios_vault_gatekeeper_arrival"
const BLACK_TEXT_CUTSCENE_SCENE := preload("res://Scenes/ui/black_text_cutscene.tscn")
const BIOS_VAULT_TRANSFER_LINES_GOOD: Array[String] = ["You've done well.", "You'll handle the next task properly...", "I hope."]
const BIOS_VAULT_TRANSFER_LINES_BAD: Array[String] = ["There's nothing for you here.", "Be gone."]
const BIOS_VAULT_TRANSFER_CUTSCENE_DURATION := 6.0
const BIOS_VAULT_TRANSFER_PAN_DURATION := 2.0

@export var idle_animation: String = "idle"
@export var good_idle_anim: String = "good_idle"
@export var bad_idle_anim: String = "bad_idle"
@export var neutral_idle_anim: String = "idle"
@export var dialog: String = "Hello, traveler!"
@export var interact_radius: float = 1.2
@export var dialogue_resource_path: String = "res://dialogues/untitled.dialogue"
@export var dialogue_start_title: String = ""
@export var encounter_id: String = ""  # optional encounter mapping (e.g. "lost_file")

var _interact_area: Area3D = null
var npc_name: String
var root_node: Node = null
var sprite: AnimatedSprite3D = null
var _last_scene_state: String = ""
var _gatekeeper_transfer_running: bool = false
var _interaction_enabled: bool = true
var _status_bubble_layer: CanvasLayer = null
var _status_bubble_root: PanelContainer = null
var _status_bubble_label: Label = null
var _status_bubble_timer: SceneTreeTimer = null

func _ready():
	root_node = self
	set_process(true)

	# Try find a child AnimatedSprite3D on this node first
	if has_node("AnimatedSprite3D"):
		sprite = get_node("AnimatedSprite3D")
	else:
		for c in get_children():
			if c is AnimatedSprite3D:
				sprite = c
				break

	# try climb to a CharacterBody3D parent to be the logical root
	var p2 = get_parent()
	while p2 and not (p2 is CharacterBody3D):
		p2 = p2.get_parent()
	if p2:
		root_node = p2

	# If we didn't find a sprite above, try searching under the resolved root_node
	if sprite == null and root_node:
		# if the resolved root_node is itself an AnimatedSprite3D, use it
		if root_node is AnimatedSprite3D:
			sprite = root_node
		# prefer direct child named AnimatedSprite3D
		elif root_node.has_node("AnimatedSprite3D"):
			sprite = root_node.get_node("AnimatedSprite3D")
		else:
			# shallow search of children for AnimatedSprite3D
			for c in root_node.get_children():
				if c is AnimatedSprite3D:
					sprite = c
					break

	npc_name = root_node.name if root_node else name
	if root_node:
		root_node.add_to_group("npcs")

	# Check if this NPC should be hidden on startup (for quest-related NPCs)
	call_deferred("_check_should_hide_on_startup")
	
	# Connect to quest signals if this is Lost File
	if npc_name == "Lost File":
		call_deferred("_connect_quest_signals")

	# Auto-assign dialogue resource by npc name if not explicitly set
	if dialogue_resource_path == "" or dialogue_resource_path.ends_with("untitled.dialogue"):
		var key = (npc_name if npc_name else "").strip_edges().to_lower().replace(" ", "").replace("_", "")
		match key:
			"brokeninstaller":
				var path_b = "res://dialogues/BrokenInstaller.dialogue"
				if ResourceLoader.exists(path_b):
					dialogue_resource_path = path_b
			"brokenlink":
				var path_bl = "res://dialogues/BrokenLink.dialogue"
				if ResourceLoader.exists(path_bl):
					dialogue_resource_path = path_bl
			"eldershell":
				var path_e = "res://dialogues/ElderShell.dialogue"
				if ResourceLoader.exists(path_e):
					dialogue_resource_path = path_e
			"gatekeeper":
				var path_g = "res://dialogues/GateKeeper.dialogue"
				if ResourceLoader.exists(path_g):
					dialogue_resource_path = path_g
			"lostfile":
				var path_l = "res://dialogues/LostFile.dialogue"
				if ResourceLoader.exists(path_l):
					dialogue_resource_path = path_l
			"messydirectory":
				var path_m = "res://dialogues/MessyDirectory.dialogue"
				if ResourceLoader.exists(path_m):
					dialogue_resource_path = path_m
			"mountwhisperer":
				var path_mw = "res://dialogues/MountWhisperer.dialogue"
				if ResourceLoader.exists(path_mw):
					dialogue_resource_path = path_mw
			"hardwareghost":
				var path_h = "res://dialogues/HardwareGhost.dialogue"
				if ResourceLoader.exists(path_h):
					dialogue_resource_path = path_h
			"driverremnant":
				var path_d = "res://dialogues/DriverRemnant.dialogue"
				if ResourceLoader.exists(path_d):
					dialogue_resource_path = path_d
			"printerboss", "printerbeast":
				var path_p = "res://dialogues/PrinterBeast.dialogue"
				if ResourceLoader.exists(path_p):
					dialogue_resource_path = path_p
			"tux":
				var path_tux = "res://dialogues/ProprietaryCitadelTux.dialogue"
				if ResourceLoader.exists(path_tux):
					dialogue_resource_path = path_tux
			"cmo":
				var path_cmo = "res://dialogues/CMO.dialogue"
				if ResourceLoader.exists(path_cmo):
					dialogue_resource_path = path_cmo

	play_idle_animation()
	_apply_state_visuals_from_scene_state(true)

	# Ensure there's an Area3D for detecting player proximity for interaction
	if root_node.has_node("InteractArea"):
		_interact_area = root_node.get_node("InteractArea")
	else:
		_interact_area = Area3D.new()
		_interact_area.name = "InteractArea"
		root_node.add_child(_interact_area)
		if root_node.has_method("owner"):
			_interact_area.owner = root_node.owner

	# Add or update a CollisionShape3D
	# Try reuse an existing CollisionShape3D from the CharacterBody3D if present
	var existing_cs: CollisionShape3D = null
	for c in root_node.get_children():
		if c is CollisionShape3D:
			existing_cs = c
			break

	var cs: CollisionShape3D = _interact_area.get_node_or_null("CollisionShape3D")
	if cs == null:
		cs = CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		_interact_area.add_child(cs)
		if root_node.has_method("owner"):
			cs.owner = root_node.owner

	# If the CharacterBody3D already had a CollisionShape3D (e.g. a sphere),
	# duplicate its shape and copy its transform so the interaction area
	# matches the NPC's collision footprint. Disable the original physics
	# CollisionShape3D so the NPC won't block the player.
	if existing_cs != null and existing_cs.shape != null:
		cs.shape = existing_cs.shape.duplicate()
		cs.transform = existing_cs.transform
		# Disable the original physics collision shape so the NPC doesn't block movement
		# Only disable if it's the NPC's physics shape (parented to the CharacterBody3D)
		if root_node is CharacterBody3D and existing_cs.get_parent() == root_node:
			existing_cs.disabled = true
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = interact_radius
		cs.shape = sphere

	# Ensure Area3D can detect bodies
	_interact_area.monitoring = true
	_interact_area.body_entered.connect(_on_interact_area_entered)
	_interact_area.body_exited.connect(_on_interact_area_exited)
	_set_interaction_enabled(true)

func _process(_delta: float) -> void:
	_apply_state_visuals_from_scene_state()
	_update_status_bubble_position()
	if npc_name == "Driver Remnant" and SceneManager and npc_name in SceneManager.npc_states:
		if str(SceneManager.npc_states[npc_name]) == "defeated":
			if _interaction_enabled:
				_set_interaction_enabled(false)
			if root_node and root_node.visible:
				_hide_self(true)

func _exit_tree() -> void:
	_clear_status_bubble()

func _is_encounter_npc() -> bool:
	if encounter_id.strip_edges() != "":
		return true

	var key = (npc_name if npc_name else "").strip_edges().to_lower().replace(" ", "")
	return key in [
		"messydirectory",
		"lostfile",
		"brokenlink",
		"hardwareghost",
		"driverremnant",
		"printerboss",
		"printerbeast",
	]

func _should_disable_interaction_for_state(state: String) -> bool:
	return state == "defeated"

func _apply_state_visuals_from_scene_state(force: bool = false) -> void:
	if SceneManager and bool(SceneManager.get_meta("hide_all_npcs_post_evil_tux", false)):
		_hide_self(true)
		return

	# Special handling for Lost File in Fallback Hamlet: only show if player has helped it
	if npc_name == "Lost File":
		var current_scene = get_tree().current_scene
		if current_scene and "fallback_hamlet" in current_scene.scene_file_path.to_lower():
			# In Fallback Hamlet: only show if helped
			if not SceneManager.helped_lost_file:
				_hide_self(true)
				return
			else:
				_hide_self(false)
				_set_interaction_enabled(true)
				play_idle_animation()
				return
		if current_scene and "file_system_forest" in current_scene.scene_file_path.to_lower():
			# After resolution, Lost File should not remain in the forest variant.
			if SceneManager.helped_lost_file or SceneManager.deleted_lost_file:
				_hide_self(true)
				return
		# In other scenes, proceed with normal state logic

	var state := ""
	if npc_name in SceneManager.npc_states:
		state = str(SceneManager.npc_states[npc_name])

	if not force and state == _last_scene_state:
		return
	_last_scene_state = state

	match state:
		"defeated":
			_set_interaction_enabled(false)
			_hide_self(true)
		"helped", "solved":
			_hide_self(false)
			_set_interaction_enabled(not _should_disable_interaction_for_state(state))
			if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(good_idle_anim):
				sprite.play(good_idle_anim)
			else:
				play_idle_animation()
		"puzzle_ejected", "hostile", "fled_combat":
			_hide_self(false)
			_set_interaction_enabled(true)
			if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(bad_idle_anim):
				sprite.play(bad_idle_anim)
			else:
				play_idle_animation()
		_:
			_hide_self(false)
			_set_interaction_enabled(true)
			play_idle_animation()

func set_active(active: bool):
	if active:
		play_idle_animation()
	else:
		if sprite:
			sprite.stop()

func play_idle_animation():
	if not sprite:
		return

	var anim_to_play = neutral_idle_anim
	var fallback_candidates: Array[String] = [neutral_idle_anim, idle_animation, bad_idle_anim, good_idle_anim]

	# Check stored state from SceneManager if available
	if "SceneManager" in ProjectSettings.get_setting("autoload/singletons", {}):
		pass

	if npc_name in SceneManager.npc_states:
		var state = SceneManager.npc_states[npc_name]
		if state == "helped":
			anim_to_play = good_idle_anim
			fallback_candidates = [good_idle_anim, neutral_idle_anim, idle_animation, bad_idle_anim]
		elif state == "hostile" or state == "fled_combat" or state == "puzzle_ejected":
			anim_to_play = bad_idle_anim
			fallback_candidates = [bad_idle_anim, neutral_idle_anim, idle_animation, good_idle_anim]
	else:
		match SceneManager.player_karma:
			"good":
				anim_to_play = good_idle_anim
				fallback_candidates = [good_idle_anim, neutral_idle_anim, idle_animation, bad_idle_anim]
			"bad":
				anim_to_play = bad_idle_anim
				fallback_candidates = [bad_idle_anim, neutral_idle_anim, idle_animation, good_idle_anim]

	# Safety: make sure animation exists before playing
	if not sprite.sprite_frames.has_animation(anim_to_play):
		var resolved := ""
		for candidate in fallback_candidates:
			if candidate != "" and sprite.sprite_frames.has_animation(candidate):
				resolved = candidate
				break
		if resolved == "":
			push_warning("%s has no matching animation!" % npc_name)
			return
		anim_to_play = resolved

	sprite.play(anim_to_play)

func on_scene_activated():
	# Called by scene manager / teleporter when level becomes active
	_apply_state_visuals_from_scene_state(true)
	play_idle_animation()

func on_interact() -> void:
	if not _interaction_enabled:
		return

	# Block interaction if input is locked (e.g., during combat)
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.input_locked:
		return

	if npc_name in SceneManager.npc_states:
		var state_label := str(SceneManager.npc_states[npc_name])
		if _should_disable_interaction_for_state(state_label):
			_set_interaction_enabled(false)
			return

	if SceneManager and SceneManager.has_method("mark_npc_interacted"):
		SceneManager.mark_npc_interacted(npc_name)
	
	# Check if player fled from combat with this NPC - resume combat directly
	if npc_name in SceneManager.npc_states:
		var state = SceneManager.npc_states[npc_name]
		if state == "fled_combat":
			# Only resume if a matching combat state marker exists.
			# This avoids stale fled_combat flags forcing first-contact combat.
			var combat_state_key := _combat_state_meta_key(npc_name)
			var has_saved_combat_state := SceneManager.has_meta(combat_state_key)
			if has_saved_combat_state:
				# Player fled before, resume combat directly (skip dialogue)
				_start_encounter_with_mode("combat")
				return
			else:
				# Stale flag cleanup: fall back to normal dialogue flow.
				SceneManager.npc_states[npc_name] = "neutral"
	
	# Show NPC dialog
	# If a dialogue resource path is configured and DialogueManager exists, show the balloon
	if dialogue_resource_path != "":
		var resource = null
		if ResourceLoader.exists(dialogue_resource_path):
			resource = ResourceLoader.load(dialogue_resource_path)
		if resource != null:
			# DialogueManager is an autoload - access via scene tree
			var dm = get_node_or_null("/root/DialogueManager")
			if dm:
				if _should_lock_dialogue_cancel_for_npc():
					SceneManager.set_meta(DIALOGUE_CANCEL_LOCK_META_KEY, true)
				var start_title = dialogue_start_title if dialogue_start_title != "" else ""
				dm.show_dialogue_balloon(resource, start_title, [self, root_node])
				return
	# Fallback: simple interaction without dialogue
	pass

func _should_lock_dialogue_cancel_for_npc() -> bool:
	if SceneManager == null:
		return false

	var normalized_name: String = (npc_name if npc_name != "" else String(name)).strip_edges().to_lower().replace("_", " ")
	while normalized_name.find("  ") != -1:
		normalized_name = normalized_name.replace("  ", " ")

	if normalized_name == "broken link" or normalized_name == "printer boss" or normalized_name == "printer beast" or normalized_name == "sage" or normalized_name == "evil tux":
		return true

	var normalized_encounter := encounter_id.strip_edges().to_lower()
	return normalized_encounter == "broken_link" or normalized_encounter == "printer_beast" or normalized_encounter == "sage" or normalized_encounter == "evil_tux"

## Handlers callable from DialogueManager via `do start_combat()` or `do start_puzzle()`
func start_combat() -> void:
	_start_encounter_with_mode("combat")

func start_puzzle() -> void:
	_start_encounter_with_mode("puzzle")

func mark_sage_quiz_passed() -> void:
	var scene_controller = get_tree().current_scene
	if scene_controller and scene_controller.has_method("mark_sage_quiz_passed"):
		scene_controller.call("mark_sage_quiz_passed")
		return

	if SceneManager:
		SceneManager.set_meta("bios_vault_sage_quiz_passed", true)
		var tux_ctrl = SceneManager.get_node_or_null("TuxDialogueController")
		if tux_ctrl and tux_ctrl.has_method("on_sage_quiz_passed"):
			tux_ctrl.call("on_sage_quiz_passed")

func reset_sage_quiz_attempts() -> void:
	var scene_controller = get_tree().current_scene
	if scene_controller and scene_controller.has_method("reset_sage_quiz_attempts"):
		scene_controller.call("reset_sage_quiz_attempts")
		return

	if SceneManager:
		SceneManager.sage_quiz_fail_count = 0
		SceneManager.sage_force_combat = false

func register_sage_quiz_fail() -> void:
	var scene_controller = get_tree().current_scene
	if scene_controller and scene_controller.has_method("register_sage_quiz_fail"):
		scene_controller.call("register_sage_quiz_fail")
		return

	if SceneManager:
		SceneManager.sage_quiz_fail_count += 1
		if SceneManager.sage_quiz_fail_count >= 3:
			SceneManager.sage_force_combat = true

func start_sage_combat() -> void:
	var scene_controller = get_tree().current_scene
	if scene_controller and scene_controller.has_method("start_sage_combat"):
		scene_controller.call("start_sage_combat")
		return

	_start_encounter_with_mode("combat")

func start_bios_vault_transfer() -> void:
	if _gatekeeper_transfer_running:
		return
	_gatekeeper_transfer_running = true
	call_deferred("_run_bios_vault_transfer")

func elder_shell_show_sysinfo_status() -> void:
	if SceneManager and SceneManager.has_method("mark_npc_interacted"):
		SceneManager.mark_npc_interacted(npc_name)

	_close_active_dialogue_balloon()

	var mode := _elder_shell_mode_label()
	var line := _elder_shell_status_line(mode)
	_show_status_bubble(line)

func start_proprietary_citadel_good_pass_ending() -> void:
	_call_scene_controller("start_good_pass_ending")

func start_proprietary_citadel_good_kill_ending() -> void:
	_call_scene_controller("start_good_kill_ending")

func start_proprietary_citadel_bad_kill_ending() -> void:
	_call_scene_controller("start_bad_kill_ending")

func start_evil_tux_boss_fight() -> void:
	_call_scene_controller("start_evil_tux_boss_fight")

func _call_scene_controller(method_name: String) -> void:
	var scene_controller = get_tree().current_scene
	if scene_controller and scene_controller.has_method(method_name):
		scene_controller.call(method_name)
		return

	if SceneManager and SceneManager.has_method(method_name):
		SceneManager.call(method_name)

func _run_bios_vault_transfer() -> void:
	var target_scene_path := "res://Scenes/Levels/bios_vault.tscn"
	var spawn_name := "Spawn_BV"

	if SceneManager and bool(SceneManager.get_meta("evil_tux_boss_cleared", false)):
		_gatekeeper_transfer_running = false
		return

	if SceneManager:
		SceneManager.input_locked = true
		SceneManager.set_meta(BIOS_VAULT_GATEKEEPER_ARRIVAL_META_KEY, true)

	_close_active_dialogue_balloon()

	await get_tree().process_frame
	await _pan_camera_to_gatekeeper(BIOS_VAULT_TRANSFER_PAN_DURATION)

	if SceneManager:
		var transitioned := await _play_gatekeeper_transfer_cutscene(target_scene_path, spawn_name)
		if not transitioned:
			await SceneManager.teleport_to_scene(target_scene_path, spawn_name, 0.1)
		await get_tree().process_frame

		SceneManager.input_locked = false
	else:
		if SceneManager and SceneManager.has_method("transition_to_scene"):
			await SceneManager.transition_to_scene(target_scene_path, 0.1)
		else:
			get_tree().change_scene_to_file(target_scene_path)

	_gatekeeper_transfer_running = false

func _close_active_dialogue_balloon() -> void:
	var balloon_script: Script = load("res://Scenes/dialogue_balloon.gd")
	if balloon_script == null:
		return

	for child in get_tree().root.get_children():
		if child != null and child.get_script() == balloon_script:
			child.queue_free()

func _elder_shell_mode_label() -> String:
	if SceneManager == null:
		return "balanced"

	var helpful_score := 0
	var destructive_score := 0

	if SceneManager.get("helped_lost_file") == true:
		helpful_score += 2
	if SceneManager.get("deleted_lost_file") == true:
		destructive_score += 2

	if SceneManager.get("hardware_ghost_defeated") == true:
		destructive_score += 1
	if SceneManager.get("broken_link_defeated") == true:
		destructive_score += 1
	if SceneManager.get("driver_remnant_defeated") == true:
		destructive_score += 1
	if SceneManager.get("printer_beast_defeated") == true:
		destructive_score += 1

	var karma := String(SceneManager.get("player_karma")).strip_edges().to_lower()
	if karma == "good":
		helpful_score += 1
	elif karma == "bad":
		destructive_score += 1

	if helpful_score > destructive_score:
		return "helpful"
	if destructive_score > helpful_score:
		return "destructive"
	return "balanced"

func _elder_shell_status_line(mode: String) -> String:
	match mode:
		"helpful":
			return "sysinfo: You are walking a helpful path. Your choices are repairing more than they are breaking."
		"destructive":
			return "sysinfo: You are trending destructive. Slow down and verify before you execute."
		_:
			return "sysinfo: You are balanced between helpful and destructive choices."

func _show_status_bubble(text: String) -> void:
	if text.strip_edges() == "":
		return

	if _status_bubble_layer == null or not is_instance_valid(_status_bubble_layer):
		_status_bubble_layer = CanvasLayer.new()
		_status_bubble_layer.layer = 95
		get_tree().root.add_child(_status_bubble_layer)

		_status_bubble_root = PanelContainer.new()
		_status_bubble_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.95, 0.98, 1.0, 0.96)
		style.border_color = Color(0.06, 0.12, 0.2, 1.0)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		_status_bubble_root.add_theme_stylebox_override("panel", style)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 9)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 9)
		_status_bubble_root.add_child(margin)

		_status_bubble_label = Label.new()
		_status_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_status_bubble_label.modulate = Color(0.07, 0.09, 0.12, 1.0)
		_status_bubble_label.custom_minimum_size = Vector2(430.0, 0.0)
		margin.add_child(_status_bubble_label)

		_status_bubble_layer.add_child(_status_bubble_root)

	if _status_bubble_label:
		_status_bubble_label.text = text

	if _status_bubble_root:
		_status_bubble_root.visible = true

	_update_status_bubble_position()

	if _status_bubble_timer and _status_bubble_timer.time_left > 0.0:
		_status_bubble_timer = null
	_status_bubble_timer = get_tree().create_timer(4.2)
	_status_bubble_timer.timeout.connect(_hide_status_bubble)

func _update_status_bubble_position() -> void:
	if _status_bubble_root == null or not is_instance_valid(_status_bubble_root):
		return
	if not _status_bubble_root.visible:
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_status_bubble_root.visible = false
		return

	var anchor_source: Node3D = root_node as Node3D if root_node is Node3D else self
	var anchor := anchor_source.global_position + Vector3(0.0, 1.2, 0.0)
	if camera.is_position_behind(anchor):
		_status_bubble_root.visible = false
		return

	var screen_pos := camera.unproject_position(anchor) + Vector2(0.0, 28.0)
	var bubble_size := _status_bubble_root.get_combined_minimum_size()
	var viewport_size := get_viewport().get_visible_rect().size
	var x := clampf(screen_pos.x - (bubble_size.x * 0.5), 12.0, viewport_size.x - bubble_size.x - 12.0)
	var y := clampf(screen_pos.y - (bubble_size.y * 0.5), 12.0, viewport_size.y - bubble_size.y - 12.0)
	_status_bubble_root.position = Vector2(x, y)

func _hide_status_bubble() -> void:
	if _status_bubble_root and is_instance_valid(_status_bubble_root):
		_status_bubble_root.visible = false

func _clear_status_bubble() -> void:
	if _status_bubble_layer and is_instance_valid(_status_bubble_layer):
		_status_bubble_layer.queue_free()
	_status_bubble_layer = null
	_status_bubble_root = null
	_status_bubble_label = null
	_status_bubble_timer = null

func _pan_camera_to_gatekeeper(duration: float = 0.9) -> void:
	var showtime_cam := _get_gatekeeper_showtime_camera()
	if showtime_cam == null:
		return
	showtime_cam.current = true

	# Gatekeeper showtime pan: start from Y=3deg, then rotate to Y=25deg.
	var start_rotation := showtime_cam.rotation
	showtime_cam.rotation = Vector3(start_rotation.x, deg_to_rad(3.0), start_rotation.z)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(showtime_cam, "rotation:y", deg_to_rad(25.0), duration)
	await tween.finished

func _get_gatekeeper_showtime_camera() -> Camera3D:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return null

	var direct := scene_root.get_node_or_null("Fallback_Hamlet_Final/GatekeeperShowtime") as Camera3D
	if direct:
		return direct

	var fallback := scene_root.find_child("GatekeeperShowtime", true, false)
	if fallback is Camera3D:
		return fallback as Camera3D

	return null

func _get_gatekeeper_transfer_lines() -> Array[String]:
	if SceneManager and String(SceneManager.player_karma) == "good":
		return BIOS_VAULT_TRANSFER_LINES_GOOD
	return BIOS_VAULT_TRANSFER_LINES_BAD

func _play_gatekeeper_transfer_cutscene(scene_path: String, spawn_name: String) -> bool:
	var cutscene := BLACK_TEXT_CUTSCENE_SCENE.instantiate()
	if cutscene == null:
		return false

	get_tree().root.add_child(cutscene)
	var transfer_lines := _get_gatekeeper_transfer_lines()
	var per_line_duration := BIOS_VAULT_TRANSFER_CUTSCENE_DURATION / maxf(1.0, float(transfer_lines.size()))

	if cutscene.has_method("play_lines_teleport_transition"):
		await cutscene.play_lines_teleport_transition(transfer_lines, per_line_duration, scene_path, spawn_name, 0.1)
		return true

	if cutscene.has_method("play_lines") and cutscene.has_method("fade_out_only"):
		await cutscene.play_lines(transfer_lines, per_line_duration, true)
		if SceneManager:
			await SceneManager.teleport_to_scene(scene_path, spawn_name, 0.1)
		await cutscene.fade_out_only()
		if is_instance_valid(cutscene):
			cutscene.queue_free()
		return true

	if cutscene.has_method("play_teleport_transition"):
		await cutscene.play_teleport_transition(
			scene_path,
			spawn_name,
			"\n".join(transfer_lines),
			BIOS_VAULT_TRANSFER_CUTSCENE_DURATION,
			0.1
		)
		return true

	if cutscene.has_method("play"):
		await cutscene.play("\n".join(transfer_lines), BIOS_VAULT_TRANSFER_CUTSCENE_DURATION)
	if SceneManager:
		await SceneManager.teleport_to_scene(scene_path, spawn_name, 0.1)
	if is_instance_valid(cutscene):
		cutscene.queue_free()
	return true

func _flash_red_light() -> void:
	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 200
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(1.0, 0.1, 0.1, 0.0)
	flash_layer.add_child(rect)
	get_tree().root.add_child(flash_layer)

	var tween := create_tween()
	tween.tween_property(rect, "color:a", 0.8, 0.15)
	tween.tween_property(rect, "color:a", 0.0, 0.25)
	await tween.finished

	flash_layer.queue_free()

func _start_encounter_with_mode(mode: String) -> void:
	var EncounterControllerScript = load("res://scripts/combat/encounter_controller.gd")
	if not EncounterControllerScript:
		push_error("EncounterController not found")
		return
	var ec = EncounterControllerScript.new()
	# If this NPC has an encounter_id configured, use it
	if encounter_id != "":
		ec.encounter_id = encounter_id
	else:
		# Fallback mapping based on npc_name
		var key = (npc_name if npc_name else str(name)).to_lower()
		if key.find("lost") != -1:
			ec.encounter_id = "lost_file"
		elif key.find("broken") != -1 and key.find("link") != -1:
			ec.encounter_id = "broken_link"
		elif key.find("hardware") != -1 and key.find("ghost") != -1:
			ec.encounter_id = "hardware_ghost"
		elif key.find("driver") != -1 and key.find("remnant") != -1:
			ec.encounter_id = "driver_remnant"
		elif key.find("printer") != -1:
			ec.encounter_id = "printer_beast"
	
	# Set the starting mode before adding to scene
	if mode == "puzzle":
		ec.set_meta("start_in_puzzle", true)
	elif mode == "combat":
		ec.set_meta("start_in_combat", true)
	
	get_tree().current_scene.add_child(ec)
	ec.start_encounter()


func _combat_state_meta_key(npc_label: String) -> String:
	var sanitized_name := ""
	for i in npc_label.length():
		var ch := npc_label[i]
		var code := ch.unicode_at(0)
		var is_ascii_letter := (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var is_ascii_digit := code >= 48 and code <= 57
		if is_ascii_letter or is_ascii_digit or ch == "_":
			sanitized_name += ch.to_lower()
		else:
			sanitized_name += "_"

	if sanitized_name.is_empty():
		sanitized_name = "npc"
	elif sanitized_name[0].unicode_at(0) >= 48 and sanitized_name[0].unicode_at(0) <= 57:
		sanitized_name = "_" + sanitized_name

	return "combat_state_" + sanitized_name


func _on_interact_area_entered(body: Node) -> void:
	if not _interaction_enabled:
		return
	if body.is_in_group("player"):
		var im = null
		if Engine.has_singleton("InteractionManager"):
			im = Engine.get_singleton("InteractionManager")
		else:
			im = get_tree().root.get_node_or_null("InteractionManager")

		if im:
			# Use self (the npc_script node) which has the on_interact() method
			im.current_interactable = self


func _on_interact_area_exited(body: Node) -> void:
	if body.is_in_group("player"):
		var im = null
		if Engine.has_singleton("InteractionManager"):
			im = Engine.get_singleton("InteractionManager")
		else:
			im = get_tree().root.get_node_or_null("InteractionManager")

		if im and im.current_interactable == self:
			im.current_interactable = null

## Check if this NPC should be hidden on startup based on quest status
func _check_should_hide_on_startup() -> void:
	print("DEBUG: _check_should_hide_on_startup called for: %s" % npc_name)
	
	# Only check for Lost File NPC
	if npc_name != "Lost File":
		print("DEBUG: Not Lost File, ignoring")
		return
	
	# Find which level scene this NPC is part of by checking node path
	var node_path = get_path()
	print("DEBUG: NPC node path: %s" % node_path)
	
	# Simple check: is "fallback_hamlet" in our parent hierarchy?
	var current = get_parent()
	var found_fallback = false
	while current:
		if "Fallback" in current.name or "fallback" in current.name.to_lower():
			found_fallback = true
			print("DEBUG: Found Fallback Hamlet parent: %s" % current.name)
			break
		current = current.get_parent()
	
	# Also check the current scene
	var current_scene = get_tree().current_scene
	if current_scene:
		print("DEBUG: Current scene name: %s" % current_scene.name)
		if "fallback" in current_scene.name.to_lower():
			found_fallback = true
			print("DEBUG: Current scene is Fallback Hamlet")
	
	if found_fallback or str(node_path).contains("Fallback") or str(node_path).to_lower().contains("fallback"):
		print("DEBUG: In Fallback Hamlet, checking if quest was completed")
		# Lost File should only be visible if helped_lost_file is true (persisted flag)
		print("DEBUG: helped_lost_file: %s, deleted_lost_file: %s" % [SceneManager.helped_lost_file, SceneManager.deleted_lost_file])
		if SceneManager.helped_lost_file:
			print("DEBUG: Quest was completed and helped, showing Lost File")
			_hide_self(false)
			print("✨ Lost File: Visible in Hamlet (quest completed and helped)")
		else:
			print("DEBUG: Quest not completed or failed, hiding Lost File")
			_hide_self(true)
			print("🙈 Lost File: Hidden in Hamlet (quest not completed/helped)")
	else:
		print("DEBUG: Not in Fallback Hamlet")

## Hide or show this NPC completely
func _hide_self(should_hide: bool) -> void:
	if root_node:
		root_node.visible = not should_hide
		
		# Hide all children too
		for child in root_node.get_children():
			if child is CanvasItem or child is Node3D:
				child.visible = not should_hide
		
		# Disable collision
		if root_node is CharacterBody3D:
			root_node.set_collision_layer_value(1, not should_hide)
			root_node.set_collision_mask_value(1, not should_hide)
		
		# Disable interact area
		if should_hide:
			_set_interaction_enabled(false)
		else:
			_set_interaction_enabled(_interaction_enabled)

func _set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	if _interact_area:
		_interact_area.monitoring = enabled
		_interact_area.monitorable = enabled

	if not enabled:
		var im = null
		if Engine.has_singleton("InteractionManager"):
			im = Engine.get_singleton("InteractionManager")
		else:
			im = get_tree().root.get_node_or_null("InteractionManager")
		if im and im.current_interactable == self:
			im.current_interactable = null
## Connect to quest signals for Lost File
func _connect_quest_signals() -> void:
	if SceneManager and SceneManager.quest_manager:
		SceneManager.quest_manager.quest_completed.connect(_on_quest_completed)
		SceneManager.quest_manager.quest_failed.connect(_on_quest_failed)
		print("DEBUG: Lost File connected to quest signals")

## Handle quest completion
func _on_quest_completed(quest_id: String) -> void:
	if quest_id != "find_lost_file" or npc_name != "Lost File":
		return
	
	print("DEBUG: Lost File detected quest completion, checking visibility")
	
	# Check if we're in Fallback Hamlet
	var current = get_parent()
	var in_hamlet = false
	while current:
		if "Fallback" in current.name or "fallback" in current.name.to_lower():
			in_hamlet = true
			break
		current = current.get_parent()
	
	if in_hamlet and SceneManager.helped_lost_file:
		print("DEBUG: Lost File is in Hamlet and quest was helped, showing it")
		_hide_self(false)

## Handle quest failure
func _on_quest_failed(quest_id: String) -> void:
	if quest_id != "find_lost_file" or npc_name != "Lost File":
		return
	
	print("DEBUG: Lost File detected quest failure, hiding")
	_hide_self(true)
