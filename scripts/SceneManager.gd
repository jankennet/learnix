extends Node

const SAVE_FILE_PATH := "user://savegame.json"
const SAVE_FORMAT_VERSION := 1
const WORLD_MAIN_SCENE_PATH := "res://Scenes/world_main.tscn"
const MAIN_HUD_SCENE_PATH := "res://Scenes/ui/MainHUD.tscn"
const QUEST_LIST_SCENE_PATH := "res://Scenes/ui/QuestList.tscn"
const TERMINAL_EXPLORED_META_KEY := "terminal_explored_locations"
const BIOS_VAULT_SAGE_META_KEY := "bios_vault_sage_quiz_passed"
const PENDING_REWARD_META_KEY := "pending_reward_popup_key"
const LEVEL_DEFAULT_SPAWNS := {
	"res://Scenes/Levels/fallback_hamlet.tscn": "Fallback_Hamlet_Final/Spawn_FTFM",
	"res://Scenes/Levels/file_system_forest.tscn": "Forest/Spawn_FSF",
	"res://Scenes/Levels/deamon_depths.tscn": "Dungeon/Spawn_DD",
	"res://Scenes/Levels/bios_vault.tscn": "Spawn_BV",
	"res://Scenes/Levels/bios_vault_.tscn": "Spawn_BV",
}
const PERSISTED_STATE_KEYS := [
	"player_karma",
	"npc_states",
	"interacted_npcs",
	"met_messy_directory",
	"met_elder_shell",
	"met_broken_installer",
	"met_lost_file",
	"helped_lost_file",
	"deleted_lost_file",
	"met_gate_keeper",
	"proficiency_key_forest",
	"proficiency_key_printer",
	"broken_link_fragmented_key",
	"gatekeeper_pass_granted",
	"met_hardware_ghost",
	"met_driver_remnant",
	"met_printer_boss",
	"driver_remnant_defeated",
	"printer_beast_defeated",
	"sudo_token_driver_remnant",
	"deamon_depths_boss_door_unlocked",
	"deamon_depths_printer_intro_played",
	"sage_has_many_quests",
	"sage_boss_only_progress",
	"sage_quiz_tier",
	"sage_quiz_fail_count",
	"sage_force_combat",
]

# Player info
@export var player_scene_path: String = "res://Scenes/Player/player.tscn"
var player: CharacterBody3D

# Global data
var player_karma: String = "neutral" # "good", "bad", etc.
var npc_states: Dictionary = {} # { "Elder Shell": "helped", "Broken Installer": "hostile" }
var interacted_npcs: Dictionary = {} # { "Elder Shell": true }
var input_locked: bool = false

# Dialogue state tracking (used by DialogueManager)
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

# Quest system
var quest_manager: QuestManager
var quest_definitions = preload("res://scripts/QuestDefinitions.gd")
var lost_file_spawner_class = preload("res://scripts/LostFileSpawner.gd")
var lost_file_spawner: Node
var _load_in_progress := false

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
	print("Quest system initialized")
	
	# Initialize Lost File spawner
	lost_file_spawner = lost_file_spawner_class.new()
	add_child(lost_file_spawner)
	print("Lost File spawner initialized")

	_reset_runtime_state()

	# Player is resolved from the active scene when needed.

func has_save_game() -> bool:
	return FileAccess.file_exists(SAVE_FILE_PATH)

func quick_save() -> bool:
	return save_game()

func save_settings() -> bool:
	return save_game()

func save_game() -> bool:
	var save_data := _build_save_data()
	if save_data.is_empty():
		return false

	var save_file := FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if save_file == null:
		push_error("Failed to open save file for writing: " + SAVE_FILE_PATH)
		return false

	save_file.store_string(JSON.stringify(save_data, "\t"))
	return true

func quick_load() -> bool:
	return load_game()

func load_game() -> bool:
	if _load_in_progress or not has_save_game():
		return false

	var save_data := _read_save_data()
	if save_data.is_empty():
		return false

	_load_in_progress = true
	call_deferred("_begin_load_game", save_data)
	return true

func _begin_load_game(save_data: Dictionary) -> void:
	await _load_game_from_data(save_data)
	_load_in_progress = false

func _load_game_from_data(save_data: Dictionary) -> void:
	_dismiss_pause_menu()
	get_tree().paused = false
	input_locked = true

	var scene_path := String(save_data.get("scene_path", ""))
	if scene_path == "":
		push_error("Save data is missing a scene path.")
		input_locked = false
		return

	var loading_ui = await _show_loading_screen(scene_path)
	var packed_scene := await _load_scene_threaded(scene_path, loading_ui)
	if not packed_scene:
		push_error("Failed to load saved scene: " + scene_path)
		await _hide_loading_screen()
		return

	_apply_runtime_state(save_data)

	var root := get_tree().root
	var previous_scene := get_tree().current_scene
	var persistent_ui: Node = _extract_persistent_ui(previous_scene)
	if persistent_ui and persistent_ui.get_parent():
		persistent_ui.get_parent().remove_child(persistent_ui)

	if previous_scene:
		previous_scene.queue_free()

	var new_scene := packed_scene.instantiate()
	root.add_child(new_scene)
	get_tree().current_scene = new_scene

	if persistent_ui and not new_scene.has_node("UI"):
		new_scene.add_child(persistent_ui)
	elif persistent_ui and new_scene.has_node("UI"):
		root.add_child(persistent_ui)

	_ensure_gameplay_ui(new_scene)

	var active_player := _ensure_player_in_loaded_scene(new_scene)
	if active_player:
		active_player.global_transform = _deserialize_transform(save_data.get("player_transform", {}))
		player = active_player
		var cam = active_player.get_node_or_null("Camera3D")
		if cam:
			cam.current = true
	else:
		push_warning("Loaded save without a valid player instance.")

	_activate_scene_npcs(new_scene)
	await get_tree().process_frame
	await _hide_loading_screen()

func _build_save_data() -> Dictionary:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return {}

	var scene_path := String(current_scene.scene_file_path)
	if scene_path == "":
		return {}

	var active_player := _ensure_player()
	if active_player == null:
		return {}

	return {
		"version": SAVE_FORMAT_VERSION,
		"scene_path": scene_path,
		"player_transform": _serialize_transform(active_player.global_transform),
		"state": _serialize_runtime_state(),
		"quests": _serialize_quest_state(),
		"meta": _serialize_persistent_meta(),
	}

func _read_save_data() -> Dictionary:
	var save_file := FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if save_file == null:
		push_error("Failed to open save file for reading: " + SAVE_FILE_PATH)
		return {}

	var raw_text := save_file.get_as_text()
	var parsed = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		push_error("Save file is invalid JSON.")
		return {}

	return parsed as Dictionary

func _serialize_runtime_state() -> Dictionary:
	var state := {}
	for key in PERSISTED_STATE_KEYS:
		state[key] = get(key)
	return state

func _apply_runtime_state(save_data: Dictionary) -> void:
	_reset_runtime_state()

	var state: Dictionary = save_data.get("state", {}) if save_data.has("state") else {}
	for key in PERSISTED_STATE_KEYS:
		if state.has(key):
			set(key, state[key])

	_apply_quest_state(save_data.get("quests", {}))
	_apply_persistent_meta(save_data.get("meta", {}))

func _serialize_quest_state() -> Dictionary:
	var quest_statuses := {}
	if quest_manager:
		for quest_id in quest_manager.quests.keys():
			var quest: Quest = quest_manager.quests[quest_id] as Quest
			if quest == null:
				continue
			quest_statuses[String(quest_id)] = String(quest.status)

	return {
		"statuses": quest_statuses,
		"active": quest_manager.active_quests.duplicate(true) if quest_manager else [],
	}

func _apply_quest_state(quest_data: Dictionary) -> void:
	if quest_manager == null:
		return

	quest_manager.active_quests.clear()
	for quest in quest_manager.quests.values():
		if not (quest is Quest):
			continue
		quest.status = "inactive"

	var statuses: Dictionary = quest_data.get("statuses", {}) if quest_data.has("statuses") else {}
	for quest_id in statuses.keys():
		var quest := quest_manager.get_quest(String(quest_id))
		if quest:
			quest.status = String(statuses[quest_id])

	var active_list = quest_data.get("active", []) if quest_data.has("active") else []
	if active_list is Array:
		for quest_id in active_list:
			var quest_id_string := String(quest_id)
			if quest_manager.quests.has(quest_id_string):
				quest_manager.active_quests.append(quest_id_string)

func _serialize_persistent_meta() -> Dictionary:
	var meta_state := {}
	for meta_key in _persistent_meta_keys():
		if has_meta(meta_key):
			meta_state[meta_key] = get_meta(meta_key)
	return meta_state

func _apply_persistent_meta(meta_state: Dictionary) -> void:
	for meta_key in _persistent_meta_keys():
		if has_meta(meta_key):
			remove_meta(meta_key)

	for meta_key in meta_state.keys():
		set_meta(String(meta_key), meta_state[meta_key])

func _persistent_meta_keys() -> Array[String]:
	var keys: Array[String] = [
		TERMINAL_EXPLORED_META_KEY,
		BIOS_VAULT_SAGE_META_KEY,
		PENDING_REWARD_META_KEY,
	]
	for npc_name in npc_states.keys():
		var combat_key := _combat_state_meta_key(String(npc_name))
		if not keys.has(combat_key):
			keys.append(combat_key)
	return keys

func _serialize_transform(transform: Transform3D) -> Dictionary:
	return {
		"origin": [transform.origin.x, transform.origin.y, transform.origin.z],
		"basis": [
			transform.basis.x.x, transform.basis.x.y, transform.basis.x.z,
			transform.basis.y.x, transform.basis.y.y, transform.basis.y.z,
			transform.basis.z.x, transform.basis.z.y, transform.basis.z.z,
		],
	}

func _deserialize_transform(data: Dictionary) -> Transform3D:
	var origin_data = data.get("origin", []) if data.has("origin") else []
	var basis_data = data.get("basis", []) if data.has("basis") else []
	if not (origin_data is Array) or origin_data.size() != 3:
		return Transform3D.IDENTITY
	if not (basis_data is Array) or basis_data.size() != 9:
		return Transform3D.IDENTITY.translated(Vector3(origin_data[0], origin_data[1], origin_data[2]))

	var basis := Basis(
		Vector3(basis_data[0], basis_data[1], basis_data[2]),
		Vector3(basis_data[3], basis_data[4], basis_data[5]),
		Vector3(basis_data[6], basis_data[7], basis_data[8])
	)
	return Transform3D(basis, Vector3(origin_data[0], origin_data[1], origin_data[2]))

func _reset_runtime_state() -> void:
	player = null
	player_karma = "neutral"
	npc_states.clear()
	interacted_npcs.clear()
	input_locked = false

	met_messy_directory = false
	met_elder_shell = false
	met_broken_installer = false
	met_lost_file = false
	helped_lost_file = false
	deleted_lost_file = false
	met_gate_keeper = false
	proficiency_key_forest = false
	proficiency_key_printer = false
	broken_link_fragmented_key = false
	gatekeeper_pass_granted = false
	met_hardware_ghost = false
	met_driver_remnant = false
	met_printer_boss = false
	driver_remnant_defeated = false
	printer_beast_defeated = false
	sudo_token_driver_remnant = false
	deamon_depths_boss_door_unlocked = false
	deamon_depths_printer_intro_played = false
	sage_has_many_quests = false
	sage_boss_only_progress = false
	sage_quiz_tier = "intermediate"
	sage_quiz_fail_count = 0
	sage_force_combat = false

	_reset_quest_progress()
	_clear_persistent_meta()
	_initialize_default_npc_states()

func _reset_quest_progress() -> void:
	if quest_manager == null:
		return
	quest_manager.active_quests.clear()
	for quest in quest_manager.quests.values():
		quest.status = "inactive"

func _clear_persistent_meta() -> void:
	for meta_key in _persistent_meta_keys():
		if has_meta(meta_key):
			remove_meta(meta_key)

func _initialize_default_npc_states() -> void:
	npc_states["Elder Shell"] = "neutral"
	npc_states["Broken Installer"] = "neutral"
	npc_states["Messy Directory"] = "hostile"
	npc_states["Lost File"] = "hostile"
	npc_states["Broken Link"] = "hostile"
	npc_states["Hardware Ghost"] = "neutral"
	npc_states["Driver Remnant"] = "hostile"
	npc_states["Printer Boss"] = "hostile"

func _combat_state_meta_key(npc_name: String) -> String:
	var sanitized_name := npc_name.to_lower().strip_edges().replace(" ", "_")
	return "combat_state_" + sanitized_name

func _ensure_player_in_loaded_scene(scene: Node) -> CharacterBody3D:
	var existing_player := scene.get_tree().get_first_node_in_group("player")
	if existing_player and existing_player is CharacterBody3D:
		return existing_player as CharacterBody3D

	var player_root := _instantiate_player_root()
	if player_root:
		scene.add_child(player_root)
		var loaded_player := player_root.get_node_or_null("CharacterBody3D")
		if loaded_player and loaded_player is CharacterBody3D:
			return loaded_player as CharacterBody3D
		if player_root is CharacterBody3D:
			return player_root as CharacterBody3D

	return _ensure_player()

func _instantiate_player_root() -> Node:
	var player_scene = load(player_scene_path)
	if player_scene == null:
		push_error("Failed to load player root scene: " + player_scene_path)
		return null
	return player_scene.instantiate()

func _ensure_gameplay_ui(scene: Node) -> void:
	if scene == null or scene.has_node("UI"):
		return

	var ui_root := CanvasLayer.new()
	ui_root.name = "UI"
	ui_root.layer = 10
	scene.add_child(ui_root)

	var quest_list_scene := load(QUEST_LIST_SCENE_PATH) as PackedScene
	if quest_list_scene:
		var quest_list := quest_list_scene.instantiate() as Control
		if quest_list:
			quest_list.offset_top = 142.0
			quest_list.offset_bottom = 242.0
			ui_root.add_child(quest_list)

	var main_hud_scene := load(MAIN_HUD_SCENE_PATH) as PackedScene
	if main_hud_scene:
		ui_root.add_child(main_hud_scene.instantiate())

func _dismiss_pause_menu() -> void:
	var pause_menu := get_node_or_null("/root/PauseMenu")
	if pause_menu and pause_menu.has_method("_resume_game"):
		pause_menu.call("_resume_game")

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
	_reset_runtime_state()
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
