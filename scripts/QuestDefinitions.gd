## Quest definitions for the game
## Register all quests here and they'll be available in the quest system

extends Node

## Initialize all quests
## Call this once at game start (e.g., in SceneManager._ready())
static func register_all_quests(quest_manager: QuestManager) -> void:
	quest_manager.register_quest(_create_find_lost_file_quest())
	quest_manager.register_quest(_create_broken_link_quest())
	quest_manager.register_quest(_create_gatekeeper_proficiency_quest())
	quest_manager.register_quest(_create_drivers_den_cleanup_quest())

## Quest: Find Lost File
## - Messy Directory asks player to find her lost file
## - Player must locate Lost File and decide to help or fight
## - If helped: Restore Lost File's fragments
## - If fought: Lost File becomes hostile
static func _create_find_lost_file_quest() -> Quest:
	var quest = Quest.new()
	quest.quest_id = "find_lost_file"
	quest.quest_name = "Find the Lost File"
	quest.description = "Messy Directory is desperately searching for her lost child, a file that was deleted by an rm command. She asks you to find it in the Filesystem Forest and decide its fate."
	quest.npc_involved = ["Messy Directory", "Lost File"] as Array[String]
	quest.status = "inactive"
	return quest

## Quest: Gate Keeper Proficiency
## - Gate Keeper blocks access to the next zone
## - Player must collect two Proficiency keys
## - Keys are earned from Broken Link (Filesystem Forest mini boss) and Printer boss (Deamon Depths)
static func _create_gatekeeper_proficiency_quest() -> Quest:
	var quest = Quest.new()
	quest.quest_id = "gatekeeper_proficiency"
	quest.quest_name = "Prove Proficiency"
	quest.description = "The Gate Keeper requires two Proficiency keys: one from Broken Link in the Filesystem Forest (helped, not killed) and one from the Printer boss in the Deamon Depths."
	quest.npc_involved = ["Gate Keeper", "Broken Link", "Printer"] as Array[String]
	quest.status = "inactive"
	return quest

## Quest: Broken Link Puzzle/Fight
## - Broken Link resides in the Filesystem Forest
## - Role: Glitchy stub
## - Personality: Lost, corrupted, emits 404 sounds
## - Outcome: Helped grants Proficiency key; killed yields a fragmented key
static func _create_broken_link_quest() -> Quest:
	var quest = Quest.new()
	quest.quest_id = "broken_link_puzzle"
	quest.quest_name = "Broken Link: Glitchy Stub"
	quest.description = "In the Filesystem Forest, a glitchy stub called Broken Link flickers between puzzle and fight. Lost and corrupted, it emits 404 sounds. Help it to earn a Proficiency key; kill it and you only get a fragmented key."
	quest.npc_involved = ["Broken Link"] as Array[String]
	quest.status = "inactive"
	return quest

## Quest: Drivers Den Cleanup
## - Hardware Ghost asks for help quieting legacy echoes
## - Driver Remnant is an aggressive leftover that must be purged
## - Printer Beast holds the Deamon Depths proficiency key
static func _create_drivers_den_cleanup_quest() -> Quest:
	var quest = Quest.new()
	quest.quest_id = "drivers_den_cleanup"
	quest.quest_name = "Drivers Den: Echoes and Errors"
	quest.description = "In the Deamon Depths, Hardware Ghost pleads for help. Silence the Driver Remnant and stop the Printer Beast to recover the printer proficiency key."
	quest.npc_involved = ["Hardware Ghost", "Driver Remnant", "Printer Boss"] as Array[String]
	quest.status = "inactive"
	return quest

## TODO: Add more quests here as needed
## Example template:
# static func _create_new_quest() -> Quest:
#     var quest = Quest.new()
#     quest.quest_id = "unique_id"
#     quest.quest_name = "Quest Name"
#     quest.description = "Description"
#     quest.npc_involved = ["NPC1", "NPC2"]
#     return quest
