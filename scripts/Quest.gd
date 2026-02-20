class_name Quest
extends Resource

## Quest data class - stores all information about a quest
## Usage: create a new Quest resource with the properties defined below

@export var quest_id: String  # unique identifier (e.g., "find_lost_file")
@export var quest_name: String  # display name
@export var description: String  # long description
@export var npc_involved: Array[String]  # NPCs connected to this quest
@export var status: String = "inactive"  # "inactive", "active", "completed", "failed"

func _to_string() -> String:
	return "Quest(%s): %s [%s]" % [quest_id, quest_name, status]
