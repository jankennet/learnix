extends Node

# 🧍 Player info
@export var player_scene_path: String = "res://Scenes/Player/player.tscn"
var player: CharacterBody3D

# 🧠 Global data
var player_karma: String = "neutral" # "good", "bad", etc.
var npc_states: Dictionary = {} # { "Elder Shell": "helped", "Broken Installer": "hostile" }
var interacted_npcs: Dictionary = {} # { "Elder Shell": true }
var input_locked: bool = false

# 📝 Dialogue state tracking (used by DialogueManager)
var met_messy_directory: bool = false
var met_elder_shell: bool = false
var met_broken_installer: bool = false
var met_lost_file: bool = false
var helped_lost_file: bool = false
var deleted_lost_file: bool = false
var met_gate_keeper: bool = false
var proficiency_key_forest: bool = false
var proficiency_key_printer: bool = false
var broken_link_fragmented_key: bool = false
var gatekeeper_pass_granted: bool = false
var met_hardware_ghost: bool = false
var met_driver_remnant: bool = false
var met_printer_boss: bool = false
var driver_remnant_defeated: bool = false
var printer_beast_defeated: bool = false
var sudo_token_driver_remnant: bool = false
var deamon_depths_boss_door_unlocked: bool = false
var deamon_depths_printer_intro_played: bool = false
var sage_has_many_quests: bool = false
var sage_boss_only_progress: bool = false
var sage_quiz_tier: String = "intermediate"
var sage_quiz_fail_count: int = 0
var sage_force_combat: bool = false

# ✅ Quest system
var quest_manager: QuestManager
var quest_definitions = preload("res://scripts/QuestDefinitions.gd")
var lost_file_spawner_class = preload("res://scripts/LostFileSpawner.gd")
var lost_file_spawner: Node

func _instantiate_player_from_scene() -> CharacterBody3D:
	var player_scene = load(player_scene_path)
	if not player_scene:
		push_error("Failed to load player scene: " + player_scene_path)
		return null

	var instance = player_scene.instantiate()
	if instance is CharacterBody3D:
		return instance as CharacterBody3D

	var nested_player = instance.get_node_or_null("CharacterBody3D")
	if nested_player and nested_player is CharacterBody3D:
		instance.remove_child(nested_player)
		instance.queue_free()
		return nested_player as CharacterBody3D

	instance.queue_free()
	push_error("Player scene does not contain a CharacterBody3D root or child")
	return null

func _ready():
	# Initialize quest system
	quest_manager = QuestManager.new()
	add_child(quest_manager)
	quest_definitions.register_all_quests(quest_manager)
	print("✅ Quest system initialized")
	
	# Initialize Lost File spawner
	lost_file_spawner = lost_file_spawner_class.new()
	add_child(lost_file_spawner)
	print("✅ Lost File spawner initialized")
	
	# Fallback Hamlet NPC states
	npc_states["Elder Shell"] = "neutral"
	npc_states["Broken Installer"] = "neutral"
	npc_states["Messy Directory"] = "hostile"
	# Filesystem Forest NPC states
	npc_states["Lost File"] = "hostile"
	npc_states["Broken Link"] = "hostile"
	# Deamon Depths NPC states
	npc_states["Hardware Ghost"] = "neutral"
	npc_states["Driver Remnant"] = "hostile"
	npc_states["Printer Boss"] = "hostile"
	
	# Player is resolved from the active scene when needed.

func mark_npc_interacted(npc_name: String) -> void:
	if npc_name == "":
		return
	interacted_npcs[npc_name] = true

	# Bridge older per-NPC flags with the new interaction registry.
	match npc_name:
		"Broken Installer":
			met_broken_installer = true
		"Lost File":
			met_lost_file = true
		_:
			pass

func has_interacted_with_npc(npc_name: String) -> bool:
	return bool(interacted_npcs.get(npc_name, false))

func _ensure_player() -> CharacterBody3D:
	var player_in_group = get_tree().get_first_node_in_group("player")
	if player_in_group and player_in_group is CharacterBody3D:
		player = player_in_group as CharacterBody3D
		return player

	if is_instance_valid(player) and player.is_inside_tree():
		return player

	push_error("Failed to resolve player instance for teleport")
	return null

func _apply_spawn_transform(transfer_node: Node, active_player: CharacterBody3D, spawn_transform: Transform3D) -> void:
	var yaw := spawn_transform.basis.get_euler().y
	var target_player_transform := Transform3D(Basis(Vector3.UP, yaw), spawn_transform.origin)

	if transfer_node == active_player:
		active_player.global_transform = target_player_transform
		return

	var transfer_node_3d := transfer_node as Node3D
	if transfer_node_3d:
		var player_local_transform := active_player.transform
		transfer_node_3d.global_transform = target_player_transform * player_local_transform.affine_inverse()
		active_player.global_transform = target_player_transform
		return

	active_player.global_transform = target_player_transform

# 🌀 Universal teleport (with loading screen + NPC refresh)
func teleport_to_scene(scene_path: String, spawn_name: String, delay: float = 1.0):
	print("🌍 Teleporting to:", scene_path)
	input_locked = true

	var active_player := _ensure_player()
	if not active_player:
		input_locked = false
		return

	var transfer_node: Node = _get_player_transfer_root(active_player)
	var persistent_ui: Node = _extract_persistent_ui(get_tree().current_scene)

	# Show loading screen
	var loading_ui = await _show_loading_screen(scene_path, spawn_name)

	# Load target scene with threaded streaming
	var new_scene_res := await _load_scene_threaded(scene_path, loading_ui)
	if not new_scene_res:
		push_error("Failed to load scene: " + scene_path)
		await _hide_loading_screen()
		return

	var new_scene = new_scene_res.instantiate()
	var root = get_tree().root

	var previous_parent = transfer_node.get_parent()
	if previous_parent:
		previous_parent.remove_child(transfer_node)

	if persistent_ui and persistent_ui.get_parent():
		persistent_ui.get_parent().remove_child(persistent_ui)

	# Remove current scene
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()

	root.add_child(new_scene)
	get_tree().current_scene = new_scene

	new_scene.add_child(transfer_node)
	if persistent_ui and not new_scene.has_node("UI"):
		new_scene.add_child(persistent_ui)
	elif persistent_ui and new_scene.has_node("UI"):
		# Keep migrated UI alive even if target scene already has a UI node.
		root.add_child(persistent_ui)
	player = active_player

	# Find spawn point
	var spawn = new_scene.get_node_or_null(spawn_name)
	if spawn:
		_apply_spawn_transform(transfer_node, active_player, spawn.global_transform)
	else:
		push_warning("Spawn point not found: " + spawn_name)

	await get_tree().create_timer(delay).timeout

	# 🎥 Reactivate camera
	var cam = active_player.get_node_or_null("Camera3D")
	if cam:
		cam.current = true

	# 🧠 Notify all NPCs to "wake up"
	_activate_scene_npcs(new_scene)

	# 🔓 Hard recovery: always restore player input after transfer
	active_player.process_mode = Node.PROCESS_MODE_INHERIT
	active_player.set_physics_process(true)
	active_player.set_process_input(true)
	active_player.set_process_unhandled_input(true)

	await _hide_loading_screen()

func _get_player_transfer_root(active_player: CharacterBody3D) -> Node:
	var cursor: Node = active_player
	while cursor and cursor.get_parent() and cursor.get_parent() != get_tree().current_scene:
		cursor = cursor.get_parent()

	if cursor and cursor.name == "Player":
		return cursor

	var active_player_parent := active_player.get_parent()
	if active_player_parent and active_player_parent.name == "Player":
		return active_player_parent

	return active_player

func _extract_persistent_ui(scene: Node) -> Node:
	if not scene:
		return null
	var ui_node := scene.get_node_or_null("UI")
	if ui_node and ui_node is CanvasLayer:
		return ui_node
	return null

func start_new_game(scene_path: String) -> void:
	input_locked = true
	var loading_ui = await _show_loading_screen(scene_path)
	var packed_scene := await _load_scene_threaded(scene_path, loading_ui)
	if not packed_scene:
		push_error("Failed to load startup scene: " + scene_path)
		await _hide_loading_screen()
		return

	var change_error := get_tree().change_scene_to_packed(packed_scene)
	if change_error != OK:
		push_error("Failed to switch to startup scene: " + scene_path)
		await _hide_loading_screen()
		return

	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	await _hide_loading_screen()

func _load_scene_threaded(scene_path: String, loading_ui: Node = null) -> PackedScene:
	var request_error := ResourceLoader.load_threaded_request(scene_path)
	if request_error != OK:
		push_warning("Threaded load request failed, using sync load: " + scene_path)
		var fallback_resource := load(scene_path)
		if fallback_resource and fallback_resource is PackedScene:
			if loading_ui and loading_ui.has_method("set_loading_progress"):
				loading_ui.set_loading_progress(1.0)
			return fallback_resource as PackedScene
		return null

	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if loading_ui and loading_ui.has_method("set_loading_progress"):
			if progress.size() > 0:
				loading_ui.set_loading_progress(progress[0])
			else:
				loading_ui.set_loading_progress(0.0)
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(scene_path, progress)

	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_error("Threaded load failed for scene: " + scene_path)
		return null

	var loaded_resource := ResourceLoader.load_threaded_get(scene_path)
	if not loaded_resource or not (loaded_resource is PackedScene):
		push_error("Loaded resource is not a PackedScene: " + scene_path)
		return null

	if loading_ui and loading_ui.has_method("set_loading_progress"):
		loading_ui.set_loading_progress(1.0)

	return loaded_resource as PackedScene

# 🧩 Internal helper: Notify all NPCs in a scene
func _activate_scene_npcs(scene: Node):
	if scene.has_node("NPC"):
		var npc_root = scene.get_node("NPC")
		for npc in npc_root.get_children():
			if npc.has_method("on_scene_activated"):
				npc.call_deferred("on_scene_activated")
				print("💬 Activated NPC:", npc.name)

# Loading screen controls
func _show_loading_screen(scene_path: String = "", spawn_name: String = ""):
	var ui = get_node_or_null("/root/LoadingScreen")
	if ui:
		ui.fade_in(scene_path, spawn_name)
		await ui.animation_finished
	return ui

func _hide_loading_screen():
	var ui = get_node_or_null("/root/LoadingScreen")
	if ui:
		ui.fade_out()
		await ui.animation_finished
	input_locked = false
	return
