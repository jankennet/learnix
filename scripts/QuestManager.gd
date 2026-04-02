class_name QuestManager
extends Node

## Quest system manager - tracks and manages all active quests
## Attach to SceneManager for global access

var quests: Dictionary = {}  # { quest_id: Quest }
var active_quests: Array[String] = []  # array of active quest IDs
var pending_completion: Dictionary = {}  # { quest_id: true } when quest is ready to check

signal quest_started(quest_id: String)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String)
signal quest_updated(quest_id: String)
signal quest_ready_to_check(quest_id: String)

## Register a new quest in the system
func register_quest(quest: Quest) -> void:
	if quest.quest_id in quests:
		push_warning("⚠️ Quest '%s' already registered" % quest.quest_id)
		return
	quests[quest.quest_id] = quest
	quest.status = "inactive"

## Start a quest
func start_quest(quest_id: String) -> void:
	if not quest_id in quests:
		push_error("❌ Quest '%s' not found" % quest_id)
		return
	
	var quest = quests[quest_id]
	if quest.status == "active":
		push_warning("⚠️ Quest '%s' already active" % quest_id)
		return
	
	quest.status = "active"
	pending_completion.erase(quest_id)
	if not active_quests.has(quest_id):
		active_quests.append(quest_id)
	print("✅ Quest started: %s" % quest.quest_name)
	quest_started.emit(quest_id)

## Complete a quest
func complete_quest(quest_id: String, force: bool = false) -> void:
	if not quest_id in quests:
		push_error("❌ Quest '%s' not found" % quest_id)
		return
	
	var quest = quests[quest_id]
	if not force and String(quest.status) == "active":
		pending_completion[quest_id] = true
		print("📝 Quest ready to check: %s" % quest.quest_name)
		quest_ready_to_check.emit(quest_id)
		quest_updated.emit(quest_id)
		return

	quest.status = "completed"
	pending_completion.erase(quest_id)
	
	if quest_id in active_quests:
		active_quests.erase(quest_id)
	
	print("✅ Quest completed: %s" % quest.quest_name)
	quest_completed.emit(quest_id)

## Fail a quest
func fail_quest(quest_id: String) -> void:
	if not quest_id in quests:
		push_error("❌ Quest '%s' not found" % quest_id)
		return
	
	var quest = quests[quest_id]
	quest.status = "failed"
	pending_completion.erase(quest_id)
	
	if quest_id in active_quests:
		active_quests.erase(quest_id)
	
	print("⚠️ Quest failed: %s" % quest.quest_name)
	quest_failed.emit(quest_id)

## Get quest by ID
func get_quest(quest_id: String) -> Quest:
	if quest_id in quests:
		return quests[quest_id]
	return null

## Check if a quest is active
func is_quest_active(quest_id: String) -> bool:
	return quest_id in active_quests

## Get all active quests
func get_active_quests() -> Array[String]:
	return active_quests

## Update quest status (generic)
func update_quest(quest_id: String) -> void:
	if quest_id in quests:
		quest_updated.emit(quest_id)

## Return quest progress as a percentage [0..100]
func get_quest_progress(quest_id: String) -> int:
	var quest := get_quest(quest_id)
	if quest == null:
		return 0

	match String(quest.status):
		"inactive":
			return 0
		"completed":
			return 100
		"failed":
			return 0
		"active":
			if pending_completion.has(quest_id):
				return 100
		_:
			return 0

	var sm := get_node_or_null("/root/SceneManager")
	if sm == null:
		return 50

	match quest_id:
		"gatekeeper_proficiency":
			var has_forest_key := bool(sm.get("proficiency_key_forest"))
			var has_printer_key := bool(sm.get("proficiency_key_printer"))
			var has_fragment := bool(sm.get("broken_link_fragmented_key"))
			var key_count := int(has_forest_key) + int(has_printer_key)

			if key_count >= 2:
				return 100
			if key_count == 1:
				return 55
			if has_fragment:
				return 30
			return 0
		"find_lost_file":
			if bool(sm.get("helped_lost_file")) or bool(sm.get("deleted_lost_file")):
				return 100
			if bool(sm.get("met_lost_file")):
				return 65
			if bool(sm.get("met_messy_directory")):
				return 25
			return 0
		"drivers_den_cleanup":
			var remnant_done := bool(sm.get("driver_remnant_defeated"))
			var printer_done := bool(sm.get("printer_beast_defeated"))
			if remnant_done and printer_done:
				return 100
			if remnant_done or printer_done:
				return 60
			if bool(sm.get("met_hardware_ghost")):
				return 20
			return 0
		"broken_link_puzzle":
			if bool(sm.get("proficiency_key_forest")) or bool(sm.get("broken_link_fragmented_key")) or bool(sm.get("broken_link_defeated")):
				return 100
			return 35 if bool(sm.get("met_lost_file")) else 0
		_:
			return 50

func is_quest_ready_to_check(quest_id: String) -> bool:
	var quest := get_quest(quest_id)
	if quest == null:
		return false
	if String(quest.status) != "active":
		return false
	if pending_completion.has(quest_id):
		return true
	return get_quest_progress(quest_id) >= 100

## Active quests can be checked once progress reaches 100%.
func can_check_complete(quest_id: String) -> bool:
	var quest := get_quest(quest_id)
	if quest == null:
		return false
	return is_quest_ready_to_check(quest_id)

func check_complete(quest_id: String) -> bool:
	if not can_check_complete(quest_id):
		return false
	complete_quest(quest_id, true)
	pending_completion.erase(quest_id)
	quest_updated.emit(quest_id)
	return true
