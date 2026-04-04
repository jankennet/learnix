extends Node

const SAVE_FILE_PATH := "user://savegame.json"
const SAVE_FORMAT_VERSION := 1
const TUTORIAL_SCENE_PATH := "res://Scenes/Levels/tutorial - Copy.tscn"
const FALLBACK_HAMLET_SCENE_PATH := "res://Scenes/Levels/fallback_hamlet.tscn"
const TUTORIAL_CONTROLLER_SCRIPT_PATH := "res://scripts/tutorial_sequence_controller.gd"
const TUTORIAL_DIALOGUE_PATH := "res://dialogues/TutorialFlow.dialogue"
const TUTORIAL_POST_TELEPORT_LABEL := "linuxia_arrival_intro"
const PLAYER_FOLLOW_TUX_NODE_NAME := "Tux"
const WORLD_MAIN_SCENE_PATH := "res://Scenes/world_main.tscn"
const MAIN_HUD_SCENE_PATH := "res://Scenes/ui/MainHUD.tscn"
const QUEST_LIST_SCENE_PATH := "res://Scenes/ui/QuestList.tscn"
const BIOS_VAULT_SCENE_PATH := "res://Scenes/Levels/bios_vault.tscn"
const BIOS_VAULT_ALT_SCENE_PATH := "res://Scenes/Levels/bios_vault_.tscn"
const TERMINAL_EXPLORED_META_KEY := "terminal_explored_locations"
const BIOS_VAULT_SAGE_META_KEY := "bios_vault_sage_quiz_passed"
const PENDING_REWARD_META_KEY := "pending_reward_popup_key"
const SKILL_UNLOCK_RECEIPTS_META_KEY := "skill_unlock_receipts"

const LEVEL_DEFAULT_SPAWNS := {
	"res://Scenes/Levels/tutorial - Copy.tscn": "Spawn_player",
	"res://Scenes/Levels/fallback_hamlet.tscn": "Fallback_Hamlet_Final/first_spawn",
	"res://Scenes/Levels/file_system_forest.tscn": "Forest/Spawn_FSF",
	"res://Scenes/Levels/deamon_depths.tscn": "Dungeon/Spawn_DD",
	"res://Scenes/Levels/bios_vault.tscn": "Spawn_BV",
	"res://Scenes/Levels/bios_vault_.tscn": "Spawn_BV",
	"res://Scenes/Levels/proprietary_citadel.tscn": "Spawn_BVTPC",
}
 
# Audio/music config
const MUSIC_FOLDER := "res://album/backgroundMusic/"
const MUSIC_FILES := {
	"title_screen": "3023 Mars Wars.mp3",
	"tutorial": "The Search.mp3",
	"fallback_hamlet": "Ooh! a Fly, wait... It isn't.mp3",
	"file_system_forest": "Ocean Monsters.mp3",
	"deamon_depths": "Rose Garden.mp3",
	"bios_vault": "A Green Pig.mp3",
	"proprietary_citadel": "Poisonous Bite.mp3",
	"ominous_secret_evil_tux": "An Ancient King.mp3",
	"combat_terminal": "Lava monsters.mp3",
	"puzzle_terminal": "Hello, it's Me!.mp3",
}

const SCENE_MUSIC_MAP := {
	"res://Scenes/Levels/tutorial - Copy.tscn": "tutorial",
	"res://Scenes/Levels/fallback_hamlet.tscn": "fallback_hamlet",
	"res://Scenes/Levels/file_system_forest.tscn": "file_system_forest",
	"res://Scenes/Levels/deamon_depths.tscn": "deamon_depths",
	"res://Scenes/Levels/bios_vault.tscn": "bios_vault",
	"res://Scenes/Levels/bios_vault_.tscn": "bios_vault",
	"res://Scenes/Levels/proprietary_citadel.tscn": "proprietary_citadel",
	"res://Scenes/ui/title_menu.tscn": "title_screen",
}

const SCENE_DISPLAY_NAMES := {
	"res://Scenes/Levels/tutorial - Copy.tscn": "Tutorial Boot",
	"res://Scenes/Levels/fallback_hamlet.tscn": "Fallback Hamlet",
	"res://Scenes/Levels/file_system_forest.tscn": "Filesystem Forest",
	"res://Scenes/Levels/deamon_depths.tscn": "Deamon Depths",
	"res://Scenes/Levels/bios_vault.tscn": "Bios Vault",
	"res://Scenes/Levels/bios_vault_.tscn": "Bios Vault",
	"res://Scenes/Levels/proprietary_citadel.tscn": "Proprietary Citadel",
	"res://Scenes/ui/title_menu.tscn": "Title Screen",
}

# Grouped to prevent typos when saving/loading
const PERSISTED_STATE_KEYS := [
	"data_bits",
	"player_karma", "npc_states", "interacted_npcs", "met_messy_directory", 
	"met_elder_shell", "met_broken_installer", "met_lost_file", "helped_lost_file", 
	"deleted_lost_file", "met_gate_keeper", "proficiency_key_forest", "proficiency_key_printer", 
	"broken_link_fragmented_key", "gatekeeper_pass_granted", "met_hardware_ghost", 
	"met_driver_remnant", "met_printer_boss", "driver_remnant_defeated", "printer_beast_defeated", 
	"sudo_token_driver_remnant", "deamon_depths_boss_door_unlocked", "deamon_depths_printer_intro_played", 
	"sage_has_many_quests", "sage_boss_only_progress", "sage_quiz_tier", "sage_quiz_fail_count", "sage_force_combat",
	"cli_history_unlocked", "teleport_unlocked", "file_explorer_unlocked", "mkdir_construct_unlocked",
	"taskkill_unlocked", "sudo_privilege_unlocked", "potion_patch_unlocked", "potion_overclock_unlocked", "potion_hardening_unlocked"
]

@export var player_scene_path: String = "res://Scenes/Player/player.tscn"
var player: CharacterBody3D
var _bg_music_player: AudioStreamPlayer = null
var _current_music_key: String = ""

# --- Game State ---
var data_bits: int = 0
var player_karma: String = "neutral"
var npc_states: Dictionary = {}
var interacted_npcs: Dictionary = {}
var input_locked: bool = false

signal data_bits_changed(total: int, delta: int, source: String)

# Dialogue flags
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
var broken_link_defeated: bool = false
var hardware_ghost_defeated: bool = false
var sudo_token_driver_remnant: bool = false
var deamon_depths_boss_door_unlocked: bool = false
var deamon_depths_printer_intro_played: bool = false
var sage_has_many_quests: bool = false
var sage_boss_only_progress: bool = false
var sage_quiz_tier: String = "intermediate"
var sage_quiz_fail_count: int = 0
var sage_force_combat: bool = false

# Terminal skill unlock flags
var cli_history_unlocked: bool = false
var teleport_unlocked: bool = false
var file_explorer_unlocked: bool = false
var mkdir_construct_unlocked: bool = false
var taskkill_unlocked: bool = false
var sudo_privilege_unlocked: bool = false
var potion_patch_unlocked: bool = false
var potion_overclock_unlocked: bool = false
var potion_hardening_unlocked: bool = false

# Systems
var quest_manager: QuestManager
var quest_definitions = preload("res://scripts/QuestDefinitions.gd")
var lost_file_spawner_class = preload("res://scripts/LostFileSpawner.gd")
var lost_file_spawner: Node
var _load_in_progress := false

func _ready() -> void:
	quest_manager = QuestManager.new()
	add_child(quest_manager)
	quest_definitions.register_all_quests(quest_manager)
	
	lost_file_spawner = lost_file_spawner_class.new()
	add_child(lost_file_spawner)

	_reset_runtime_state()

	# Instantiate the Tux dialogue controller to react to NPC events
	var tux_ctrl_script = load("res://scripts/tux_dialogue_controller.gd")
	if tux_ctrl_script:
		var tux_ctrl = tux_ctrl_script.new()
		tux_ctrl.name = "TuxDialogueController"
		add_child(tux_ctrl)
	# Background music player
	_bg_music_player = AudioStreamPlayer.new()
	_bg_music_player.name = "BackgroundMusicPlayer"
	add_child(_bg_music_player)
	# Autoplay music for the current scene once ready (deferred)
	call_deferred("play_music_for_key", SCENE_MUSIC_MAP.get(get_tree().current_scene.scene_file_path if get_tree().current_scene else "", ""))

func has_save_game() -> bool:
	return FileAccess.file_exists(SAVE_FILE_PATH)

func get_save_summary() -> Dictionary:
	if not has_save_game():
		return {}

	var save_data := _read_save_data()
	if save_data.is_empty():
		return {}

	var scene_path := String(save_data.get("scene_path", ""))
	var saved_at_unix := int(save_data.get("saved_at_unix", 0))
	if saved_at_unix <= 0:
		saved_at_unix = int(FileAccess.get_modified_time(SAVE_FILE_PATH))
	return {
		"scene_path": scene_path,
		"location": _describe_scene_path(scene_path),
		"saved_at_unix": saved_at_unix,
		"saved_at_text": _format_unix_timestamp(saved_at_unix),
	}

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
	if SCENE_MUSIC_MAP.has(scene_path):
		play_music_for_key(SCENE_MUSIC_MAP[scene_path])

	var active_player := _ensure_player_in_loaded_scene(new_scene)
	if active_player:
		if _is_bios_vault_scene(scene_path):
			_hide_player_companion_tux(active_player)
		active_player.global_transform = _deserialize_transform(save_data.get("player_transform", {}))
		player = active_player
		var cam = active_player.get_node_or_null("Camera3D")
		if cam:
			cam.current = true
			_bind_terrain_camera_for_scene(new_scene, cam)
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
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"player_transform": _serialize_transform(active_player.global_transform),
		"state": _serialize_runtime_state(),
		"quests": _serialize_quest_state(),
		"meta": _serialize_persistent_meta(),
	}

func _describe_scene_path(scene_path: String) -> String:
	if SCENE_DISPLAY_NAMES.has(scene_path):
		return String(SCENE_DISPLAY_NAMES[scene_path])
	if scene_path == "":
		return "Unknown Area"
	return scene_path.get_file().get_basename().replace("_", " ").capitalize()

func _format_unix_timestamp(unix_ts: int) -> String:
	if unix_ts <= 0:
		return "Unknown time"
	var dt := Time.get_datetime_dict_from_unix_time(unix_ts)
	if dt.is_empty():
		return "Unknown time"
	return "%04d-%02d-%02d %02d:%02d" % [
		int(dt.get("year", 0)),
		int(dt.get("month", 0)),
		int(dt.get("day", 0)),
		int(dt.get("hour", 0)),
		int(dt.get("minute", 0)),
	]

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
		"pending_check": quest_manager.pending_completion.keys() if quest_manager else [],
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

	quest_manager.pending_completion.clear()
	var pending_list = quest_data.get("pending_check", []) if quest_data.has("pending_check") else []
	if pending_list is Array:
		for quest_id in pending_list:
			var quest_id_string := String(quest_id)
			if quest_manager.quests.has(quest_id_string):
				quest_manager.pending_completion[quest_id_string] = true

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
		SKILL_UNLOCK_RECEIPTS_META_KEY,
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
	data_bits = 0
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
	broken_link_defeated = false
	hardware_ghost_defeated = false
	sudo_token_driver_remnant = false
	deamon_depths_boss_door_unlocked = false
	deamon_depths_printer_intro_played = false
	sage_has_many_quests = false
	sage_boss_only_progress = false
	sage_quiz_tier = "intermediate"
	sage_quiz_fail_count = 0
	sage_force_combat = false
	cli_history_unlocked = false
	teleport_unlocked = false
	file_explorer_unlocked = false
	mkdir_construct_unlocked = false
	taskkill_unlocked = false
	sudo_privilege_unlocked = false
	potion_patch_unlocked = false
	potion_overclock_unlocked = false
	potion_hardening_unlocked = false

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

signal npc_first_interacted(npc_name: String)

func mark_npc_interacted(npc_name: String) -> bool:
	if npc_name == "":
		return false

	var first_time := false
	if not bool(interacted_npcs.get(npc_name, false)):
		first_time = true

	interacted_npcs[npc_name] = true

	# Bridge older per-NPC flags with the new interaction registry.
	match npc_name:
		"Broken Installer":
			met_broken_installer = true
		"Lost File":
			met_lost_file = true
		_:
			pass

	if first_time:
		emit_signal("npc_first_interacted", npc_name)

	return first_time

func award_data_bits(amount: int, source: String = "") -> int:
	if amount <= 0:
		return data_bits
	data_bits += amount
	emit_signal("data_bits_changed", data_bits, amount, source)
	return data_bits

func spend_data_bits(amount: int, source: String = "") -> bool:
	if amount <= 0:
		return true
	if data_bits < amount:
		return false
	data_bits -= amount
	emit_signal("data_bits_changed", data_bits, -amount, source)
	return true

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
	target_player_transform = _resolve_safe_spawn_transform(active_player, target_player_transform)

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

func _resolve_safe_spawn_transform(active_player: CharacterBody3D, desired_transform: Transform3D) -> Transform3D:
	if active_player == null:
		return desired_transform

	var resolved := desired_transform
	var space_state := active_player.get_world_3d().direct_space_state
	if space_state == null:
		return resolved

	var floor_clearance := _player_floor_clearance(active_player)
	var ray_start := desired_transform.origin + Vector3.UP * 8.0
	var ray_end := desired_transform.origin - Vector3.UP * 40.0
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [active_player]
	var hit := space_state.intersect_ray(query)
	if not hit.is_empty() and hit.has("position"):
		resolved.origin.y = (hit.position as Vector3).y + floor_clearance + 0.05

	# If still overlapping after floor snap, nudge upward until clear.
	var attempts := 0
	while attempts < 10 and active_player.test_move(resolved, Vector3.ZERO):
		resolved.origin.y += 0.1
		attempts += 1

	return resolved

func _player_floor_clearance(active_player: CharacterBody3D) -> float:
	var min_bottom := 0.0
	var found_shape := false

	for child in active_player.get_children():
		if not (child is CollisionShape3D):
			continue
		var collision := child as CollisionShape3D
		if collision.shape == null:
			continue

		var half_height := 0.5
		if collision.shape is CapsuleShape3D:
			var capsule := collision.shape as CapsuleShape3D
			half_height = capsule.radius + (capsule.height * 0.5)
		elif collision.shape is BoxShape3D:
			var box := collision.shape as BoxShape3D
			half_height = box.size.y * 0.5
		elif collision.shape is CylinderShape3D:
			var cylinder := collision.shape as CylinderShape3D
			half_height = cylinder.height * 0.5
		elif collision.shape is SphereShape3D:
			var sphere := collision.shape as SphereShape3D
			half_height = sphere.radius

		var local_bottom := collision.transform.origin.y - half_height
		if not found_shape or local_bottom < min_bottom:
			min_bottom = local_bottom
			found_shape = true

	if not found_shape:
		return 0.6

	return max(0.2, -min_bottom)

# 🌀 Universal teleport (with loading screen + NPC refresh)
func teleport_to_scene(scene_path: String, spawn_name: String, delay: float = 1.0) -> void:
	print("🌍 Teleporting to: ", scene_path)
	input_locked = true
	# Play teleport SFX
	play_sfx("res://album/sfx/teleport.mp3")
	var current_scene := get_tree().current_scene
	var previous_scene_path := current_scene.scene_file_path if current_scene else ""

	var active_player := _ensure_player()
	if not active_player:
		input_locked = false
		return

	var transfer_node := _get_player_transfer_root(active_player)
	if _is_bios_vault_scene(scene_path):
		_hide_player_companion_tux(active_player)
	var persistent_ui := _extract_persistent_ui(current_scene)

	var loading_ui = await _show_loading_screen(scene_path, spawn_name)
	var new_scene_res := await _load_scene_threaded(scene_path, loading_ui)
	
	if not new_scene_res:
		push_error("Aborting teleport. Scene failed to load: " + scene_path)
		await _hide_loading_screen()
		return

	var new_scene := new_scene_res.instantiate()
	var root := get_tree().root

	# Safely re-parent
	if transfer_node.get_parent():
		transfer_node.get_parent().remove_child(transfer_node)
	if persistent_ui and persistent_ui.get_parent():
		persistent_ui.get_parent().remove_child(persistent_ui)

	if current_scene:
		current_scene.queue_free()

	root.add_child(new_scene)
	get_tree().current_scene = new_scene

	if SCENE_MUSIC_MAP.has(scene_path):
		play_music_for_key(SCENE_MUSIC_MAP[scene_path])

	new_scene.add_child(transfer_node)
	if persistent_ui and not new_scene.has_node("UI"):
		new_scene.add_child(persistent_ui)
	elif persistent_ui:
		root.add_child(persistent_ui)

	player = active_player

	# Spawn Resolution
	var spawn := new_scene.get_node_or_null(spawn_name)
	if spawn:
		_apply_spawn_transform(transfer_node, active_player, spawn.global_transform)
	else:
		push_warning("Spawn point not found: " + spawn_name)

	await get_tree().create_timer(delay).timeout

	var cam := active_player.get_node_or_null("Camera3D")
	if cam:
		cam.current = true
		_bind_terrain_camera_for_scene(new_scene, cam)

	_activate_scene_npcs(new_scene)

	# Clean state restoration
	active_player.process_mode = Node.PROCESS_MODE_INHERIT
	active_player.set_physics_process(true)
	active_player.set_process_input(true)
	active_player.set_process_unhandled_input(true)

	await _hide_loading_screen()
	await _run_post_tutorial_arrival_sequence(previous_scene_path, scene_path, active_player)

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

func _is_bios_vault_scene(scene_path: String) -> bool:
	return scene_path == BIOS_VAULT_SCENE_PATH or scene_path == BIOS_VAULT_ALT_SCENE_PATH

func _hide_player_companion_tux(active_player: CharacterBody3D) -> void:
	if active_player == null:
		return

	var player_root := active_player.get_parent()
	if player_root:
		var sibling_tux := player_root.find_child(PLAYER_FOLLOW_TUX_NODE_NAME, true, false)
		if sibling_tux is Node3D:
			_hide_tux_node(sibling_tux as Node3D)

	for child in active_player.find_children("*", "Node3D", true, false):
		if not (child is Node3D):
			continue
		var node := child as Node3D
		if not node.name.to_lower().contains("tux"):
			continue
		_hide_tux_node(node)

func _hide_tux_node(node: Node3D) -> void:
	node.visible = false
	node.set_process(false)
	node.set_physics_process(false)
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0

func _bind_terrain_camera_for_scene(scene: Node, camera_node: Node) -> void:
	if scene == null:
		return
	if not (camera_node is Camera3D):
		return
	_assign_camera_to_terrain_recursive(scene, camera_node as Camera3D)

func _assign_camera_to_terrain_recursive(node: Node, camera: Camera3D) -> void:
	if node == null:
		return

	if node.get_class() == "Terrain3D" and node.has_method("set_camera"):
		node.call("set_camera", camera)

	for child in node.get_children():
		if child is Node:
			_assign_camera_to_terrain_recursive(child as Node, camera)

func start_new_game(scene_path: String) -> void:
	_reset_runtime_state()
	input_locked = true
	var loading_ui = await _show_loading_screen(scene_path)
	var packed_scene := await _load_scene_threaded(scene_path, loading_ui)
	if not packed_scene:
		push_error("Failed to load startup scene: " + scene_path)
		await _hide_loading_screen()
		return

	var root := get_tree().root
	var previous_scene := get_tree().current_scene
	if previous_scene:
		previous_scene.queue_free()

	var new_scene := packed_scene.instantiate()
	root.add_child(new_scene)
	get_tree().current_scene = new_scene

	_ensure_gameplay_ui(new_scene)
	if SCENE_MUSIC_MAP.has(scene_path):
		play_music_for_key(SCENE_MUSIC_MAP[scene_path])

	var active_player := _ensure_player_in_loaded_scene(new_scene)
	if active_player:
		if _is_bios_vault_scene(scene_path):
			_hide_player_companion_tux(active_player)
		var spawn_path: String = LEVEL_DEFAULT_SPAWNS.get(scene_path, "")
		if spawn_path != "":
			var spawn_point := new_scene.get_node_or_null(spawn_path)
			if spawn_point:
				_apply_spawn_transform(_get_player_transfer_root(active_player), active_player, spawn_point.global_transform)
		player = active_player
		_attach_tutorial_controller(new_scene, active_player, scene_path)
		var cam = active_player.get_node_or_null("Camera3D")
		if cam:
			cam.current = true
			_bind_terrain_camera_for_scene(new_scene, cam)
	else:
		push_warning("Failed to instantiate player for new game.")

	await get_tree().process_frame
	await _hide_loading_screen()

func _attach_tutorial_controller(scene: Node, active_player: CharacterBody3D, scene_path: String) -> void:
	if scene_path != TUTORIAL_SCENE_PATH:
		return
	if scene == null:
		return
	if scene.get_node_or_null("TutorialSequenceController"):
		return

	var controller_script = load(TUTORIAL_CONTROLLER_SCRIPT_PATH)
	if controller_script == null:
		push_warning("Tutorial controller script not found: " + TUTORIAL_CONTROLLER_SCRIPT_PATH)
		return

	var controller_instance = controller_script.new()
	if not (controller_instance is Node):
		push_warning("Tutorial controller script did not instantiate a Node.")
		return

	var controller_node := controller_instance as Node
	controller_node.name = "TutorialSequenceController"
	scene.add_child(controller_node)

	if controller_node.has_method("setup"):
		controller_node.call("setup", active_player)

func _load_scene_threaded(scene_path: String, loading_ui: Node = null) -> PackedScene:
	var request_error := ResourceLoader.load_threaded_request(scene_path)
	
	if request_error != OK:
		push_warning("Threaded request failed natively. Falling back to sync load: " + scene_path)
		return _synchronous_load_fallback(scene_path, loading_ui)

	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
	
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if loading_ui and loading_ui.has_method("set_loading_progress"):
			loading_ui.set_loading_progress(progress[0] if not progress.is_empty() else 0.0)
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(scene_path, progress)

	# MISSING LOGIC ADDED HERE: Actually return the loaded resource!
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		if loading_ui and loading_ui.has_method("set_loading_progress"):
			loading_ui.set_loading_progress(1.0)
		return ResourceLoader.load_threaded_get(scene_path) as PackedScene

	# If it fails (e.g., Wine case-sensitivity mismatch)
	push_error("Threaded load completely failed for scene: " + scene_path)
	return _synchronous_load_fallback(scene_path, loading_ui)

func _synchronous_load_fallback(scene_path: String, loading_ui: Node = null) -> PackedScene:
	push_warning("Attempting synchronous fallback for: " + scene_path)
	var fallback_resource := load(scene_path)
	if fallback_resource is PackedScene:
		if loading_ui and loading_ui.has_method("set_loading_progress"):
			loading_ui.set_loading_progress(1.0)
		return fallback_resource as PackedScene
	return null

# 🧩 Internal helper: Notify all NPCs in a scene
func _activate_scene_npcs(scene: Node):
	if scene.has_node("NPC"):
		var npc_root = scene.get_node("NPC")
		for npc in npc_root.get_children():
			if npc.has_method("on_scene_activated"):
				npc.call_deferred("on_scene_activated")
				print("💬 Activated NPC:", npc.name)

# Background music helpers
# Cache loaded streams to avoid disk hits every time a scene changes
var _music_cache: Dictionary = {} 

func _music_path_for_key(key: String) -> String:
	# Using 'get' with a default is slightly faster than 'has' + '[]'
	var fname: String = MUSIC_FILES.get(key, "")
	return MUSIC_FOLDER + fname if fname != "" else ""

func _play_music_stream(path: String, loop: bool = true) -> void:
	if path.is_empty():
		return

	# 1. Use Cache or Load
	var stream: AudioStream
	if _music_cache.has(path):
		stream = _music_cache[path]
	else:
		stream = load(path) as AudioStream
		if stream:
			_music_cache[path] = stream
	
	if not stream:
		push_warning("Music stream not found or invalid: " + path)
		return

	# 2. Handle Looping
	_setup_looping(stream, loop)

	# 3. Initialize Player
	if not _bg_music_player:
		_bg_music_player = AudioStreamPlayer.new()
		_bg_music_player.name = "BackgroundMusicPlayer"
		# Optional: Ensure it keeps playing if the game pauses
		_bg_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_bg_music_player)

	# 4. Smart Playback (Avoid restarting the same track)
	if _bg_music_player.stream == stream:
		if not _bg_music_player.playing:
			_bg_music_player.play()
		return

	_bg_music_player.stream = stream
	_bg_music_player.play()

func _setup_looping(stream: AudioStream, loop: bool) -> void:
	# Try to set loop properties safely by inspecting available properties on the stream.
	var props := stream.get_property_list()
	for prop in props:
		var pname: String = prop.get("name", "")
		if pname == "loop":
			stream.set("loop", loop)
			return
		elif pname == "loop_mode":
			var mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
			stream.set("loop_mode", mode)
			return

func play_music_for_key(key: String, loop: bool = true) -> void:
	# Optimization: Don't do anything if this key is already playing
	if _current_music_key == key and _bg_music_player and _bg_music_player.playing:
		return

	var path := _music_path_for_key(key)
	if path.is_empty():
		push_warning("No music configured for key: " + key)
		return
	
	_play_music_stream(path, loop)
	_current_music_key = key

func stop_music() -> void:
	if _bg_music_player:
		_bg_music_player.stop()
		_current_music_key = ""

func _fade_out_and_stop(duration: float = 0.6) -> void:
	if not _bg_music_player or not _bg_music_player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_bg_music_player, "volume_db", -80.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished
	_bg_music_player.stop()
	_bg_music_player.volume_db = -80.0

func _fade_in_current(duration: float = 0.6) -> void:
	if _current_music_key == "":
		return
	var path := _music_path_for_key(_current_music_key)
	if path == "":
		return
	if not _bg_music_player:
		_bg_music_player = AudioStreamPlayer.new()
		_bg_music_player.name = "BackgroundMusicPlayer"
		_bg_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_bg_music_player)
	_bg_music_player.volume_db = -80.0
	_play_music_stream(path, true)
	var tween := create_tween()
	tween.tween_property(_bg_music_player, "volume_db", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished

# --------- SFX helpers ---------
var _sfx_cache: Dictionary = {}
var _sfx_players: Dictionary = {} # keyed by path -> AudioStreamPlayer

func _sfx_bus_name() -> String:
	var idx := AudioServer.get_bus_index("SFX")
	return "SFX" if idx != -1 else "Master"

func play_sfx(path: String, loop: bool=false, volume_db: float=0.0) -> void:
	if path == null or path == "":
		return

	var stream: AudioStream = null
	if _sfx_cache.has(path):
		stream = _sfx_cache[path]
	else:
		stream = load(path) as AudioStream
		if stream:
			_sfx_cache[path] = stream

	if not stream:
		push_warning("SFX stream not found or invalid: " + path)
		return

	var bus_name := _sfx_bus_name()

	if loop:
		if _sfx_players.has(path):
			var existing: AudioStreamPlayer = _sfx_players[path] as AudioStreamPlayer
			if existing and existing.playing:
				return
		var sfx_player: AudioStreamPlayer = AudioStreamPlayer.new()
		sfx_player.stream = stream
		sfx_player.bus = bus_name
		sfx_player.volume_db = volume_db
		_setup_looping(stream, true)
		add_child(sfx_player)
		_sfx_players[path] = sfx_player
		sfx_player.play()
	else:
		var one_shot: AudioStreamPlayer = AudioStreamPlayer.new()
		one_shot.stream = stream
		one_shot.bus = bus_name
		one_shot.volume_db = volume_db
		add_child(one_shot)
		one_shot.play()
		if one_shot.has_signal("finished"):
			one_shot.connect("finished", Callable(one_shot, "queue_free"))
		else:
			var t := Timer.new()
			t.one_shot = true
			if stream.has_method("get_length"):
				t.wait_time = stream.get_length()
			else:
				t.wait_time = 2.0
			add_child(t)
			t.connect("timeout", Callable(one_shot, "queue_free"))
			t.connect("timeout", Callable(t, "queue_free"))
			t.start()

func stop_sfx(path: String) -> void:
	if _sfx_players.has(path):
		var pl: AudioStreamPlayer = _sfx_players[path] as AudioStreamPlayer
		if pl:
			pl.stop()
			pl.queue_free()
		_sfx_players.erase(path)


# Loading screen controls
func _show_loading_screen(scene_path: String = "", spawn_name: String = ""):
	var ui = get_node_or_null("/root/LoadingScreen")
	if ui:
		await _fade_out_and_stop(0.6)
		ui.fade_in(scene_path, spawn_name)
		await ui.animation_finished
	return ui

func _hide_loading_screen():
	var ui = get_node_or_null("/root/LoadingScreen")
	if ui:
		ui.fade_out()
		await ui.animation_finished
	input_locked = false
	# Restore music after loading screen is hidden
	await _fade_in_current(0.6)
	return

func _run_post_tutorial_arrival_sequence(previous_scene_path: String, target_scene_path: String, active_player: CharacterBody3D) -> void:
	if previous_scene_path != TUTORIAL_SCENE_PATH:
		return
	if target_scene_path != FALLBACK_HAMLET_SCENE_PATH:
		return

	_restore_player_companion_tux(active_player)
	await get_tree().process_frame
	await _play_dialogue_sequence(TUTORIAL_DIALOGUE_PATH, TUTORIAL_POST_TELEPORT_LABEL, [self])

func _restore_player_companion_tux(active_player: CharacterBody3D) -> void:
	if active_player == null:
		return

	var player_root := active_player.get_parent()
	if player_root == null:
		return

	var companion := player_root.find_child(PLAYER_FOLLOW_TUX_NODE_NAME, true, false)
	if companion == null:
		return

	if companion is Node3D:
		(companion as Node3D).visible = true
	companion.set_process(true)
	companion.set_physics_process(true)
	if companion.has_method("set_follow_enabled"):
		companion.call("set_follow_enabled", true)

	var sprite_node := companion.get_node_or_null("AnimatedSprite3D")
	if not (sprite_node is AnimatedSprite3D):
		var sprite_candidates := companion.find_children("*", "AnimatedSprite3D", true, false)
		if not sprite_candidates.is_empty():
			sprite_node = sprite_candidates[0]
	if sprite_node is AnimatedSprite3D:
		var sprite := sprite_node as AnimatedSprite3D
		sprite.visible = true
		if sprite.sprite_frames and sprite.sprite_frames.has_animation("tux_idle"):
			sprite.play("tux_idle")

func _play_dialogue_sequence(dialogue_path: String, start_label: String, context_args: Array = []) -> void:
	var dialogue_manager := get_tree().root.get_node_or_null("DialogueManager")
	if dialogue_manager == null:
		return
	if not dialogue_manager.has_method("show_dialogue_balloon"):
		return

	var dialogue_resource := load(dialogue_path)
	if dialogue_resource == null:
		push_warning("Dialogue resource missing: " + dialogue_path)
		return

	var previous_input_lock := input_locked
	input_locked = true
	dialogue_manager.show_dialogue_balloon(dialogue_resource, start_label, context_args)
	if dialogue_manager.has_signal("dialogue_ended"):
		await dialogue_manager.dialogue_ended
	input_locked = previous_input_lock
