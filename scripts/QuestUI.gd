class_name QuestUI
extends Control

## Simple Quest list UI - only shows active quests

@onready var quest_container: VBoxContainer = $VBoxContainer

func _ready():
	# Connect to quest signals
	if SceneManager and SceneManager.quest_manager:
		SceneManager.quest_manager.quest_started.connect(_on_quest_started)
		SceneManager.quest_manager.quest_completed.connect(_on_quest_completed)
		SceneManager.quest_manager.quest_failed.connect(_on_quest_failed)
	
	# Check for any already active quests
	_refresh_quest_list()
	print("Quest UI initialized")

## Refresh the entire quest list (only show active quests)
func _refresh_quest_list() -> void:
	if not SceneManager or not SceneManager.quest_manager:
		return
	
	# Clear existing items
	for child in quest_container.get_children():
		child.queue_free()
	
	# Add only active quests
	for quest_id in SceneManager.quest_manager.active_quests:
		var quest = SceneManager.quest_manager.get_quest(quest_id)
		if quest:
			_add_quest_label(quest)

## Add a simple label for the quest
func _add_quest_label(quest: Quest) -> void:
	var label = Label.new()
	label.name = quest.quest_id
	label.text = "• " + quest.quest_name
	label.add_theme_font_size_override("font_size", 14)
	quest_container.add_child(label)

## Called when a quest starts
func _on_quest_started(_quest_id: String) -> void:
	_refresh_quest_list()

## Called when a quest completes
func _on_quest_completed(_quest_id: String) -> void:
	_refresh_quest_list()

## Called when a quest fails
func _on_quest_failed(_quest_id: String) -> void:
	_refresh_quest_list()
