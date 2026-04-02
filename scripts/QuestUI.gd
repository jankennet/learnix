class_name QuestUI
extends Control

## Quest list UI - shows active and completed/failed quests

@onready var quest_container: VBoxContainer = $VBoxContainer

func _ready():
	# Connect to quest signals
	if SceneManager and SceneManager.quest_manager:
		SceneManager.quest_manager.quest_started.connect(_on_quest_started)
		SceneManager.quest_manager.quest_completed.connect(_on_quest_completed)
		SceneManager.quest_manager.quest_failed.connect(_on_quest_failed)
		SceneManager.quest_manager.quest_updated.connect(_on_quest_updated)
	
	# Populate existing quest entries
	_refresh_quest_list()
	print("Quest UI initialized")

## Refresh the entire quest list (show active/completed/failed)
func _refresh_quest_list() -> void:
	if not SceneManager or not SceneManager.quest_manager:
		return
	
	# Clear existing items
	for child in quest_container.get_children():
		child.queue_free()
	
	var visible_quests: Array[Quest] = []
	for quest in SceneManager.quest_manager.quests.values():
		if not (quest is Quest):
			continue
		if String(quest.status) in ["active", "completed", "failed"]:
			visible_quests.append(quest)

	visible_quests.sort_custom(func(a: Quest, b: Quest) -> bool:
		return a.quest_name < b.quest_name
	)

	for quest in visible_quests:
		_add_quest_label(quest)

## Add a simple label for the quest
func _add_quest_label(quest: Quest) -> void:
	var label = Label.new()
	label.name = quest.quest_id
	var status_text := "In progress"
	match String(quest.status):
		"completed":
			status_text = "Completed"
		"failed":
			status_text = "Failed"
		_:
			status_text = "In progress"
	label.text = "• %s [%s]" % [quest.quest_name, status_text]
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

func _on_quest_updated(_quest_id: String) -> void:
	_refresh_quest_list()
