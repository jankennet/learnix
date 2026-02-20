class_name QuestManager
extends Node

## Quest system manager - tracks and manages all active quests
## Attach to SceneManager for global access

var quests: Dictionary = {}  # { quest_id: Quest }
var active_quests: Array[String] = []  # array of active quest IDs

signal quest_started(quest_id: String)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String)
signal quest_updated(quest_id: String)

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
	active_quests.append(quest_id)
	print("✅ Quest started: %s" % quest.quest_name)
	quest_started.emit(quest_id)

## Complete a quest
func complete_quest(quest_id: String) -> void:
	if not quest_id in quests:
		push_error("❌ Quest '%s' not found" % quest_id)
		return
	
	var quest = quests[quest_id]
	quest.status = "completed"
	
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
