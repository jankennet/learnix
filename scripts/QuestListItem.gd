class_name QuestListItem
extends Button
signal quest_toggled(quest)

## Individual quest item in the quest list UI

@onready var quest_name_label = $MarginContainer/VBoxContainer/QuestName
@onready var quest_status_label = $MarginContainer/VBoxContainer/QuestStatus
@onready var quest_description_label = $MarginContainer/VBoxContainer/QuestDescription

var quest: Quest

func _ready():
	# Verify nodes exist
	if not quest_name_label or not quest_status_label or not quest_description_label:
		push_error("QuestListItem: Missing required label nodes. Ensure node paths are correct.")
	# Connect the pressed signal so clicking toggles quest completion
	connect("pressed", Callable(self, "_on_pressed"))

## Set the quest data and update the display
func set_quest(q: Quest) -> void:
	quest = q
	_update_display()

## Update the display based on quest status
func _update_display() -> void:
	if not quest:
		return
	
	# Update name
	if quest_name_label:
		quest_name_label.text = quest.quest_name
	
	# Update status with color coding
	if quest_status_label:
		var status_text = ""
		var status_color = Color.WHITE
		
		match quest.status:
			"inactive":
				status_text = "[Not Started]"
				status_color = Color.GRAY
			"active":
				status_text = "[Active]"
				status_color = Color.YELLOW
			"completed":
				status_text = "[✓ Completed]"
				status_color = Color.GREEN
			"failed":
				status_text = "[✗ Failed]"
				status_color = Color.RED
		
		quest_status_label.text = status_text
		quest_status_label.modulate = status_color
	
	# Update description
	if quest_description_label:
		quest_description_label.text = quest.description


func _on_pressed() -> void:
	if not quest:
		return
	# Prefer using the QuestManager API so active_quests stays in sync
	if has_node("/root/SceneManager") and SceneManager and SceneManager.quest_manager:
		var qm = SceneManager.quest_manager
		if quest.status != "completed":
			if qm.has_method("complete_quest"):
				qm.complete_quest(quest.quest_id)
			else:
				quest.status = "completed"
		else:
			if qm.has_method("start_quest"):
				qm.start_quest(quest.quest_id)
			else:
				quest.status = "active"
	else:
		# Fallback: modify the resource directly
		if quest.status != "completed":
			quest.status = "completed"
		else:
			quest.status = "active"

	_update_display()
	emit_signal("quest_toggled", quest)
