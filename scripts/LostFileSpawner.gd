## Lost File spawning manager
## Handles showing Lost File in Fallback Hamlet after quest completion
## and hiding it from Filesystem Forest

extends Node

const LOST_FILE_IN_FOREST = "res://Scenes/Levels/file_system_forest.tscn"
const LOST_FILE_IN_HAMLET = "res://Scenes/Levels/fallback_hamlet.tscn"
const QUEST_ID = "find_lost_file"
const VISIBILITY_POLL_INTERVAL := 0.25

var _visibility_poll_timer := 0.0
var _last_scene_path := ""
var _last_should_hide := {}

func _ready():
	if SceneManager and SceneManager.quest_manager:
		SceneManager.quest_manager.quest_completed.connect(_on_quest_completed)
		SceneManager.quest_manager.quest_failed.connect(_on_quest_failed)
	
	# Check on startup if Lost File should be visible/hidden
	call_deferred("_check_initial_state")

## Check initial state on startup
func _check_initial_state() -> void:
	_last_scene_path = ""
	_last_should_hide.clear()
	_visibility_poll_timer = 0.0
	# Always start with Lost File hidden in both locations
	var current_scene = get_tree().current_scene
	if not current_scene:
		return
	
	var quest = SceneManager.quest_manager.get_quest(QUEST_ID)
	
	# In Forest: hide Lost File by default
	if LOST_FILE_IN_FOREST in current_scene.scene_file_path:
		if quest and quest.status in ["completed", "failed"]:
			_hide_npc_completely(current_scene, "NPC/Lost File", true)
		else:
			# Make sure it's visible if quest is still active/incomplete
			_hide_npc_completely(current_scene, "NPC/Lost File", false)
	
	# In Hamlet: only show Lost File if quest is completed
	if LOST_FILE_IN_HAMLET in current_scene.scene_file_path:
		if quest and quest.status == "completed":
			_hide_npc_completely(current_scene, "NPC/Lost File", false)
		else:
			# Hide Lost File by default in Hamlet
			_hide_npc_completely(current_scene, "NPC/Lost File", true)

## Called when quest is completed - show Lost File in Hamlet, hide in Forest
func _on_quest_completed(quest_id: String) -> void:
	if quest_id != QUEST_ID:
		return
	
	print("✅ Lost File quest completed - Lost File should appear in Hamlet")
	_update_lost_file_visibility()

## Called when quest is failed - hide Lost File from Forest
func _on_quest_failed(quest_id: String) -> void:
	if quest_id != QUEST_ID:
		return
	
	print("❌ Lost File quest failed - hiding from forest")
	_update_lost_file_visibility()

## Update Lost File visibility based on quest status and current scene
func _update_lost_file_visibility() -> void:
	var current_scene = get_tree().current_scene
	if not current_scene:
		return

	_last_scene_path = current_scene.scene_file_path
	
	var quest = SceneManager.quest_manager.get_quest(QUEST_ID)
	if not quest:
		return
	
	# In Forest: hide Lost File if quest is completed or failed
	if LOST_FILE_IN_FOREST in current_scene.scene_file_path:
		var hide_forest: bool = quest.status in ["completed", "failed"]
		_set_npc_hidden_if_changed(current_scene, "NPC/Lost File", hide_forest)
	
	# In Hamlet: show Lost File if quest is completed (helped)
	if LOST_FILE_IN_HAMLET in current_scene.scene_file_path:
		var hide_hamlet: bool = quest.status != "completed"
		_set_npc_hidden_if_changed(current_scene, "NPC/Lost File", hide_hamlet)

func _set_npc_hidden_if_changed(scene: Node, npc_path: String, should_hide: bool) -> void:
	if _last_should_hide.get(npc_path, null) == should_hide:
		return
	_last_should_hide[npc_path] = should_hide
	_hide_npc_completely(scene, npc_path, should_hide)

## Hide or show an NPC completely (visibility + collision + interact area)
func _hide_npc_completely(scene: Node, npc_path: String, should_hide: bool) -> void:
	var npc = scene.get_node_or_null(npc_path)
	if not npc:
		return
	
	# Hide the NPC and all children
	npc.visible = not should_hide
	
	# Also hide children recursively to ensure sprite is hidden
	for child in npc.get_children():
		if child is CanvasItem:
			child.visible = not should_hide
	
	# Disable collision on the character body itself
	if npc is CharacterBody3D:
		npc.set_collision_layer_value(1, not should_hide)
		npc.set_collision_mask_value(1, not should_hide)
	
	# Disable the interact area
	var interact_area = npc.get_node_or_null("InteractArea")
	if interact_area:
		interact_area.monitoring = not should_hide
		interact_area.monitorable = not should_hide
	
	if should_hide:
		print("🙈 NPC hidden: %s" % npc_path)
	else:
		print("✨ NPC shown: %s" % npc_path)

## Process every frame to ensure visibility persists during scene transitions
func _process(_delta: float) -> void:
	_visibility_poll_timer -= _delta
	if _visibility_poll_timer > 0.0:
		return
	_visibility_poll_timer = VISIBILITY_POLL_INTERVAL

	var current_scene = get_tree().current_scene
	if not current_scene:
		return

	if current_scene.scene_file_path != _last_scene_path:
		_last_scene_path = current_scene.scene_file_path
		_last_should_hide.clear()
	
	# In Forest: hide Lost File if quest was completed/failed
	if LOST_FILE_IN_FOREST in current_scene.scene_file_path:
		var lost_file_forest = current_scene.get_node_or_null("NPC/Lost File")
		if lost_file_forest and (SceneManager.helped_lost_file or SceneManager.deleted_lost_file):
			if lost_file_forest.visible:
				_set_npc_hidden_if_changed(current_scene, "NPC/Lost File", true)
	
	# In Hamlet: show Lost File if quest was completed and helped
	if LOST_FILE_IN_HAMLET in current_scene.scene_file_path:
		var lost_file_hamlet = current_scene.get_node_or_null("NPC/Lost File")
		if lost_file_hamlet:
			if SceneManager.helped_lost_file:
				if not lost_file_hamlet.visible:
					_set_npc_hidden_if_changed(current_scene, "NPC/Lost File", false)
			else:
				if lost_file_hamlet.visible:
					_set_npc_hidden_if_changed(current_scene, "NPC/Lost File", true)
