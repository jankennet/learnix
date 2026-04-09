## Explorer Command Quiz System
## Handles the educational mini-game for identifying Linux commands
## This module manages quiz state, scoring, and user interactions

class_name ExplorerCommandQuiz
extends RefCounted

## Quiz state variables
var quiz_active: bool = false
var current_file_entry: Dictionary = {}
var current_file_key: String = ""
var current_command_index: int = 0
var answered_correctly: bool = false
var data_bits_earned: int = 0
var wrong_answer_count: int = 0
var option_cache: Array = []
var option_cache_question_index: int = -1
var file_progress: Dictionary = {}

## Initialize a new quiz session
func reset() -> void:
	quiz_active = false
	current_file_entry = {}
	current_file_key = ""
	current_command_index = 0
	answered_correctly = false
	wrong_answer_count = 0
	option_cache = []
	option_cache_question_index = -1
	# Note: data_bits_earned persists across quizzes

## Load a new lesson file for quiz
func load_lesson(file_entry: Dictionary) -> void:
	if not file_entry.has("commands"):
		return

	var next_key := "%s|%s" % [String(file_entry.get("filename", "")), String(file_entry.get("title", ""))]
	if quiz_active and current_file_key == next_key:
		# Keep quiz progress when re-rendering the same file.
		return

	current_file_entry = file_entry
	current_file_key = next_key
	if file_progress.has(current_file_key):
		var saved: Dictionary = file_progress[current_file_key] as Dictionary
		current_command_index = int(saved.get("index", 0))
		wrong_answer_count = int(saved.get("wrong", 0))
	else:
		current_command_index = 0
		wrong_answer_count = 0
		file_progress[current_file_key] = {
			"index": 0,
			"wrong": 0,
		}
	answered_correctly = false
	option_cache = []
	option_cache_question_index = -1
	quiz_active = true

func _save_current_progress() -> void:
	if current_file_key == "":
		return
	file_progress[current_file_key] = {
		"index": current_command_index,
		"wrong": wrong_answer_count,
	}

## Get quiz display text with progress
func get_quiz_display() -> String:
	if current_file_entry.is_empty() or not current_file_entry.has("commands"):
		return ""
	
	var commands: Array = current_file_entry.get("commands", [])
	if commands.is_empty():
		return ""

	var quiz_text := "[b]════════ COMMAND CHALLENGE ════════[/b]"
	quiz_text += "\n[color=ffff99][b]Identify the command from its description[/b][/color]"
	quiz_text += "\n[i]Click one option below to answer.[/i]"
	
	if wrong_answer_count > 0:
		quiz_text += "\n\n[color=ff6666]Wrong answers: %d/3[/color]" % wrong_answer_count
	
	quiz_text += "\n[b]Progress: %d/%d[/b]" % [current_command_index, commands.size()]
	quiz_text += "\n[b]DATA BITS Earned: [color=ffff00]%d[/color][/b]" % data_bits_earned

	if current_command_index < commands.size():
		var current_cmd: Dictionary = commands[current_command_index] as Dictionary
		var prompt_desc := String(current_cmd.get("desc", "Unknown command purpose"))
		quiz_text += "\n\n[b]Question:[/b] Which command matches this description?"
		quiz_text += "\n[color=aad7ff]%s[/color]" % prompt_desc
	else:
		quiz_text += "\n\n[color=99ff99][b]All commands solved for this lesson![/b][/color]"
	
	return quiz_text

func get_command_options() -> Array:
	if current_file_entry.is_empty() or not current_file_entry.has("commands"):
		return []
	var commands: Array = current_file_entry.get("commands", [])
	if commands.is_empty():
		return []
	if current_command_index >= commands.size():
		return commands

	if option_cache_question_index != current_command_index or option_cache.is_empty():
		option_cache = commands.duplicate(true)
		option_cache.shuffle()
		option_cache_question_index = current_command_index

	return option_cache

## Check answer and return result
## Returns: {"correct": bool, "reward": int, "complete": bool, "failed": bool}
func check_answer(command_name: String) -> Dictionary:
	if current_file_entry.is_empty() or not current_file_entry.has("commands"):
		return {"correct": false, "reward": 0, "complete": false, "failed": false}
	
	var commands: Array = current_file_entry.get("commands", [])
	if commands.is_empty() or current_command_index >= commands.size():
		return {"correct": false, "reward": 0, "complete": false, "failed": false}
	
	var current_cmd: Dictionary = commands[current_command_index] as Dictionary
	var correct_cmd: String = current_cmd.get("cmd", "")
	var difficulty: int = current_cmd.get("difficulty", 1)
	var data_bits_reward: int = difficulty * 10  # 10, 20, or 30 bits
	
	if command_name == correct_cmd:
		# Correct answer!
		data_bits_earned += data_bits_reward
		current_command_index += 1
		answered_correctly = true
		option_cache = []
		option_cache_question_index = -1
		_save_current_progress()
		
		var quiz_complete: bool = current_command_index >= commands.size()
		return {
			"correct": true,
			"reward": data_bits_reward,
			"complete": quiz_complete,
			"failed": false
		}
	else:
		# Wrong answer
		wrong_answer_count += 1
		var quiz_failed: bool = wrong_answer_count >= 3

		if quiz_failed:
			# Reset on failure
			wrong_answer_count = 0
			current_command_index = 0
			option_cache = []
			option_cache_question_index = -1
			_save_current_progress()
		else:
			_save_current_progress()
		
		return {
			"correct": false,
			"reward": 0,
			"complete": false,
			"failed": quiz_failed
		}

## Get total data bits earned
func get_total_bits() -> int:
	return data_bits_earned

## Check if quiz is complete
func is_complete() -> bool:
	if current_file_entry.is_empty() or not current_file_entry.has("commands"):
		return false
	var commands: Array = current_file_entry.get("commands", [])
	return current_command_index >= commands.size() and commands.size() > 0
