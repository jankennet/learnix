extends Node

# 🧍 Player info
@export var player_scene_path: String = "res://Scenes/Player/player.tscn"
var player: CharacterBody3D

# 🧠 Global data
var player_karma: String = "neutral" # "good", "bad", etc.
var npc_states: Dictionary = {} # { "Elder Shell": "helped", "Broken Installer": "hostile" }
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

# ✅ Quest system
var quest_manager: QuestManager
var quest_definitions = preload("res://scripts/QuestDefinitions.gd")
var lost_file_spawner_class = preload("res://scripts/LostFileSpawner.gd")
var lost_file_spawner: Node

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
	
	# Load the player dynamically
	if not player:
		var player_scene = load(player_scene_path)
		if player_scene:
			player = player_scene.instantiate() as CharacterBody3D
		else:
			push_error("Failed to load player scene: " + player_scene_path)

# 🌀 Universal teleport (with loading screen + NPC refresh)
func teleport_to_scene(scene_path: String, spawn_name: String, delay: float = 1.0):
	print("🌍 Teleporting to:", scene_path)

	# Show loading screen
	await _show_loading_screen()

	# Load target scene
	var new_scene_res = load(scene_path)
	if not new_scene_res:
		push_error("Failed to load scene: " + scene_path)
		await _hide_loading_screen()
		return

	var new_scene = new_scene_res.instantiate()
	var root = get_tree().root

	# Remove current scene
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()

	root.add_child(new_scene)
	get_tree().current_scene = new_scene

	new_scene.add_child(player)

	# Find spawn point
	var spawn = new_scene.get_node_or_null(spawn_name)
	if spawn:
		var spawn_transform = spawn.global_transform
		var yaw = spawn_transform.basis.get_euler().y
		player.global_transform = Transform3D(Basis(Vector3.UP, yaw), spawn_transform.origin)
	else:
		push_warning("Spawn point not found: " + spawn_name)

	await get_tree().create_timer(delay).timeout

	# 🎥 Reactivate camera
	var cam = player.get_node_or_null("Camera3D")
	if cam:
		cam.current = true

	# 🧠 Notify all NPCs to "wake up"
	_activate_scene_npcs(new_scene)

	await _hide_loading_screen()

# 🧩 Internal helper: Notify all NPCs in a scene
func _activate_scene_npcs(scene: Node):
	if scene.has_node("NPC"):
		var npc_root = scene.get_node("NPC")
		for npc in npc_root.get_children():
			if npc.has_method("on_scene_activated"):
				npc.call_deferred("on_scene_activated")
				print("💬 Activated NPC:", npc.name)

# Loading screen controls
func _show_loading_screen():
	var ui = get_node_or_null("/root/LoadingScreen")
	if ui:
		ui.fade_in()
		await ui.animation_finished
	return

func _hide_loading_screen():
	var ui = get_node_or_null("/root/LoadingScreen")
	if ui:
		ui.fade_out()
		await ui.animation_finished
	return
