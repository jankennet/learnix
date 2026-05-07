# puzzle_state_handler.gd
# Manages puzzle mechanics solved through typed commands
# Handles state transitions, validation, and solution checking
extends RefCounted
class_name PuzzleStateHandler

#region Signals (for use when instanced as Node)
# These are defined but puzzles should connect via callback patterns
#endregion

#region Enums
enum PuzzleType {
	NONE,
	FILE_RECOVERY,      # Restore fragmented/deleted files
	PATH_FINDING,       # Navigate directory structure
	PERMISSION_FIX,     # Correct file permissions
	DATA_SORTING,       # Sort data in correct order
	LINK_REPAIR,        # Fix broken symlinks
	ENCRYPTION,         # Decrypt encoded data
	SEQUENCE,           # Execute commands in order
	PATTERN_MATCH,      # Match regex/glob patterns
	DEPENDENCY,         # Resolve dependency chains
	COMPILATION,        # Fix and compile code
}

enum PuzzleState {
	NOT_STARTED,
	IN_PROGRESS,
	SOLVED,
	FAILED,
}
#endregion

#region Puzzle Data Classes

## Base puzzle definition
class PuzzleData:
	var id: String = ""
	var puzzle_type: PuzzleType = PuzzleType.NONE
	var title: String = ""
	var description: String = ""
	var hints: Array[String] = []
	var hint_index: int = 0
	var max_attempts: int = -1  # -1 = unlimited
	var current_attempts: int = 0
	var time_limit: float = -1.0  # -1 = no limit
	var state: PuzzleState = PuzzleState.NOT_STARTED
	var solution_commands: Array[String] = []  # Valid solution patterns
	var current_progress: Array[String] = []  # Commands executed so far
	var custom_data: Dictionary = {}  # Puzzle-specific data
	var reward: Dictionary = {}
	
	func get_next_hint() -> String:
		if hints.is_empty():
			return "No hints available."
		var hint := hints[hint_index]
		hint_index = mini(hint_index + 1, hints.size() - 1)
		return hint
	
	func reset():
		state = PuzzleState.NOT_STARTED
		current_attempts = 0
		current_progress.clear()
		hint_index = 0

## Result of a puzzle command
class PuzzleResult:
	var success: bool = false
	var progress_made: bool = false
	var puzzle_complete: bool = false
	var puzzle_failed: bool = false
	var message: String = ""
	var progress_percent: float = 0.0
	var revealed_data: String = ""
	var state_change: Dictionary = {}
	## Whether this command should trigger timing minigame
	var requires_timing: bool = false
	## Difficulty for timing (0.5 = easy, 2.0 = hard)
	var timing_difficulty: float = 1.0
	## Called by timing system - affects success based on timing result
	var timing_success_chance: float = 1.0
#endregion

#region File Recovery Puzzle (Lost File Theme)

## Creates a file recovery puzzle for the "Lost File" encounter
static func create_lost_file_puzzle() -> PuzzleData:
	var puzzle := PuzzleData.new()
	puzzle.id = "lost_file_recovery"
	puzzle.puzzle_type = PuzzleType.FILE_RECOVERY
	puzzle.title = "Recover the Lost File"
	puzzle.description = """
A fragmented file has been scattered across the current directory.
The pieces are corrupted and need to be recovered in the correct order.

Fragments detected:
  .fragment_001  (corrupted)
  .fragment_002  (scattered)
  .fragment_003  (encrypted)

Use local directory clues to locate, recover, and reconstruct the file.
"""
	
	puzzle.hints = [
		"Discovery: check which orphaned blocks are visible in the current directory.",
		"Analysis: read the fragment clues, then focus on the encrypted piece.",
		"Execution: recover each fragment, combine the pieces, and verify the file.",
	]
	
	# Unlimited attempts (-1) - we want new Linux users to learn, not get frustrated
	puzzle.max_attempts = -1
	
	# Solution requires these steps (flexible order for some)
	puzzle.solution_commands = [
		"find .fragment",
		"restore .fragment_001",
		"decrypt .fragment_003",
		"restore .fragment_002",
		"restore .fragment_003",
		"cat fragments",
		"compile recovered_file",
	]
	
	# Track which fragments have been found/recovered
	puzzle.custom_data = {
		"fragments_found": [],
		"fragments_restored": [],
		"fragments_decrypted": [],
		"file_assembled": false,
		"file_compiled": false,
		"timing_critical_hits": 0,
		"fragment_locations": {
			".fragment_001": "fragment_slot_a",
			".fragment_002": "fragment_slot_b",
			".fragment_003": "fragment_slot_c"
		},
		"required_fragments": [".fragment_001", ".fragment_002", ".fragment_003"],
	}
	
	puzzle.reward = {
		"npc_state": "helped",
		"npc_name": "Lost File",
		"karma_change": "good",
		"unlock": "filesystem_forest_path_2",
		"data_bits": 45,
		"data_bits_per_critical": 8,
	}
	
	return puzzle

## Creates a sequence puzzle for the "Broken Link" encounter
static func create_broken_link_puzzle() -> PuzzleData:
	var puzzle := PuzzleData.new()
	puzzle.id = "broken_link_repair"
	puzzle.puzzle_type = PuzzleType.SEQUENCE
	puzzle.title = "Repair the Broken Link"
	puzzle.description = """
A corrupted link stub is looping in the current directory.
The target reference is missing, and the stub keeps emitting 404 signals.

Repair the link by scanning, locating the target note, unlinking the stub,
reconnecting it to the correct local target, fixing permissions, and patching the link table.
"""

	puzzle.hints = [
		"Discovery: inspect the stub and identify which reference is missing.",
		"Analysis: read the target note, then clear the broken connection.",
		"Execution: rebuild the link and verify the repaired route.",
	]

	# Unlimited attempts - this is a learning encounter
	puzzle.max_attempts = -1

	puzzle.custom_data = {
		"expected_sequence": [
			"ls -l stub",
			"find target_note",
			"unlink stub",
			"ln -s target_note stub",
			"chmod link_table 644",
			"cat link_table",
			"make link_map",
		],
		"clue_files": ["stub", "target_note", "link_table", "link_map.plan"],
		"current_index": 0,
		"reset_on_fail": false,
		"timing_critical_hits": 0,
		"timing_steps": [3, 5],
		"timing_difficulty_map": {
			3: 1.35,
			5: 1.5,
		},
	}

	puzzle.reward = {
		"npc_state": "helped",
		"npc_name": "Broken Link",
		"karma_change": "good",
		"unlock": "proficiency_key_forest",
		"data_bits": 40,
		"data_bits_per_critical": 8,
	}

	return puzzle

## Creates a sequence puzzle for the Hardware Ghost encounter
static func create_hardware_ghost_puzzle() -> PuzzleData:
	var puzzle := PuzzleData.new()
	puzzle.id = "hardware_ghost_logs"
	puzzle.puzzle_type = PuzzleType.SEQUENCE
	puzzle.title = "Calm the Legacy Logs"
	puzzle.description = """
The Hardware Ghost is trapped in a loop of legacy driver logs.
Follow a calming repair sequence to quiet the phantom and stabilize the bus.
"""

	puzzle.hints = [
		"Discovery: read the first fault log and identify the repeating pattern.",
		"Analysis: inspect the driver table and isolate the echo source.",
		"Execution: normalize the table and rebuild the map.",
	]

	puzzle.max_attempts = -1

	puzzle.custom_data = {
		"expected_sequence": [
			"cat legacy_bus.log",
			"find driver_table",
			"cat ghost_echo.log",
			"chmod driver_table 644",
			"make driver_map",
		],
		"clue_files": ["legacy_bus.log", "ghost_echo.log", "driver_table", "driver_map.plan"],
		"current_index": 0,
		"reset_on_fail": false,
		"timing_critical_hits": 0,
		"timing_steps": [2],
		"timing_difficulty_map": {
			2: 1.2,
		},
	}

	puzzle.reward = {
		"npc_state": "helped",
		"npc_name": "Hardware Ghost",
		"karma_change": "good",
		"data_bits": 38,
		"data_bits_per_critical": 6,
	}

	return puzzle

## Creates a sequence puzzle for the Driver Remnant encounter
static func create_driver_remnant_puzzle() -> PuzzleData:
	var puzzle := PuzzleData.new()
	puzzle.id = "driver_remnant_isolation"
	puzzle.puzzle_type = PuzzleType.SEQUENCE
	puzzle.title = "Isolate the Remnant"
	puzzle.description = """
The Driver Remnant is an aggressive leftover thread.
Isolate it by tracing the interrupt line, terminating the rogue driver,
and restoring stability to the interrupt table.
"""

	puzzle.hints = [
		"Discovery: read the remnant signature in the current directory.",
		"Analysis: trace the interrupt line and isolate the unstable route.",
		"Execution: terminate the remnant, clear the line, and stabilize the table.",
	]

	puzzle.max_attempts = -1

	puzzle.custom_data = {
		"expected_sequence": [
			"cat remnant.sig",
			"find irq_line",
			"kill driver_remnant",
			"unlink irq_line",
			"chmod interrupt_table 644",
			"make stability_map",
		],
		"clue_files": ["remnant.sig", "irq_line", "interrupt_table", "stability_map.plan"],
		"current_index": 0,
		"reset_on_fail": false,
		"timing_critical_hits": 0,
		"timing_steps": [2, 4],
		"timing_difficulty_map": {
			2: 1.3,
			4: 1.5,
		},
	}

	puzzle.reward = {
		"npc_state": "defeated",
		"npc_name": "Driver Remnant",
		"karma_change": "neutral",
		"data_bits": 50,
		"data_bits_per_critical": 8,
	}

	return puzzle

## Creates a sequence puzzle for the Printer Beast encounter
static func create_printer_beast_puzzle() -> PuzzleData:
	var puzzle := PuzzleData.new()
	puzzle.id = "printer_beast_reset"
	puzzle.puzzle_type = PuzzleType.SEQUENCE
	puzzle.title = "Clear the Printer Daemon"
	puzzle.description = """
The Printer Beast is locked in a paper-jam loop.
Clear the spool, fix permissions, and restart the queue to quiet the daemon.
"""

	puzzle.hints = [
		"Discovery: inspect the spool state in the current directory.",
		"Analysis: identify the jammed page and the queue index.",
		"Execution: clear the jam, repair the spool, and rebuild the queue.",
	]

	puzzle.max_attempts = -1

	puzzle.custom_data = {
		"expected_sequence": [
			"ls spool",
			"find jam_page",
			"rm jam_page",
			"chmod spool 644",
			"cat spool_index",
			"make print_queue",
		],
		"clue_files": ["spool", "jam_page", "spool_index", "print_queue.plan"],
		"current_index": 0,
		"reset_on_fail": false,
		"timing_critical_hits": 0,
		"timing_steps": [2, 4],
		"timing_difficulty_map": {
			2: 1.25,
			4: 1.4,
		},
	}

	puzzle.reward = {
		"npc_state": "helped",
		"npc_name": "Printer Boss",
		"karma_change": "neutral",
		"data_bits": 60,
		"data_bits_per_critical": 10,
	}

	return puzzle

## Process a command for the Lost File puzzle
static func process_lost_file_command(puzzle: PuzzleData, command: CommandParser.CommandResult) -> PuzzleResult:
	var result := PuzzleResult.new()
	var _data: Dictionary = puzzle.custom_data
	
	# Don't count helpful/informational commands as attempts
	var informational_commands := [
		CommandParser.CommandType.LIST,
		CommandParser.CommandType.SCAN,
		CommandParser.CommandType.HELP,
	]
	if command.command_type not in informational_commands:
		puzzle.current_attempts += 1
	
	puzzle.state = PuzzleState.IN_PROGRESS
	
	match command.command_type:
		CommandParser.CommandType.FIND:
			result = _handle_find_fragment(puzzle, command)
		
		CommandParser.CommandType.RESTORE:
			result = _handle_restore_fragment(puzzle, command)
		
		CommandParser.CommandType.DECRYPT:
			result = _handle_decrypt_fragment(puzzle, command)
		
		CommandParser.CommandType.READ:  # cat
			result = _handle_cat_fragments(puzzle, command)
		
		CommandParser.CommandType.COMPILE:
			result = _handle_compile_file(puzzle, command)
		
		CommandParser.CommandType.LIST:  # ls
			result = _handle_list_fragments(puzzle, command)
		
		CommandParser.CommandType.SCAN:
			result = _handle_scan_puzzle(puzzle, command)
		
		_:
			result.message = "Command '%s' has no effect on this puzzle." % command.raw_input
	
	# Update progress percentage
	result.progress_percent = _calculate_progress(puzzle)
	
	# Check for puzzle failure (only if max_attempts is positive)
	if puzzle.max_attempts > 0 and puzzle.current_attempts >= puzzle.max_attempts:
		result.puzzle_failed = true
		puzzle.state = PuzzleState.FAILED
		result.message += "\n[WARNING] Too many failed attempts. Don't worry - you can try again!"
		result.message += "\nTip: Use 'hint' for help, or 'ls' to check your progress."
	
	return result

static func _handle_find_fragment(puzzle: PuzzleData, command: CommandParser.CommandResult) -> PuzzleResult:
	var result := PuzzleResult.new()
	var data: Dictionary = puzzle.custom_data
	var target := command.target.to_lower() if not command.target.is_empty() else ""
	
	if target.is_empty():
		result.message = "find: missing search pattern\nUsage: find <pattern>"
		return result
	
	var found_any := false
	var locations: Dictionary = data.get("fragment_locations", {})
	var already_found: Array = data.get("fragments_found", [])
	
	for fragment_name in locations.keys():
		if target in fragment_name or fragment_name in target or target == ".fragment":
			if fragment_name not in already_found:
				already_found.append(fragment_name)
				found_any = true
				result.revealed_data += "Found: %s at %s\n" % [fragment_name, locations[fragment_name]]
	
	data["fragments_found"] = already_found
	
	if found_any:
		result.success = true
		result.progress_made = true
		result.message = "Search complete.\n" + result.revealed_data
	else:
		if already_found.size() == locations.size():
			result.message = "All fragments already located."
		else:
			result.message = "find: no matches for '%s'" % target
	
	return result

static func _handle_restore_fragment(puzzle: PuzzleData, command: CommandParser.CommandResult) -> PuzzleResult:
	var result := PuzzleResult.new()
	var data: Dictionary = puzzle.custom_data
	var target := command.target.to_lower() if not command.target.is_empty() else ""
	
	if target.is_empty():
		result.message = "restore: missing target\nUsage: restore <fragment>"
		return result
	
	var found: Array = data.get("fragments_found", [])
	var restored: Array = data.get("fragments_restored", [])
	var decrypted: Array = data.get("fragments_decrypted", [])
	var required: Array = data.get("required_fragments", [])
	
	# Find matching fragment
	var matched_fragment := ""
	for frag in required:
		if target in frag or frag in target:
			matched_fragment = frag
			break
	
	if matched_fragment.is_empty():
		result.message = "restore: '%s' is not a valid fragment" % target
		return result
	
	# Check if found first
	if matched_fragment not in found:
		result.message = "restore: fragment '%s' not located yet. Use 'find' first." % matched_fragment
		return result
	
	# Check if already restored
	if matched_fragment in restored:
		result.message = "restore: '%s' already recovered" % matched_fragment
		return result
	
	# Fragment 003 needs decryption first
	if matched_fragment == ".fragment_003" and matched_fragment not in decrypted:
		result.message = "restore: '%s' is encrypted. Decrypt it first." % matched_fragment
		return result
	
	# Restore the fragment - requires timing minigame!
	result.requires_timing = true
	result.timing_difficulty = 1.0
	result.timing_success_chance = 1.0  # Will be modified by timing result
	
	# Store pending restore info for after timing completes
	result.state_change["pending_restore"] = matched_fragment
	result.state_change["restored_array"] = restored
	result.state_change["required_size"] = required.size()
	
	# DO NOT update state yet - timing must succeed first!
	# Only mark that timing is required
	result.message = "Initiating recovery of %s... [TIMING REQUIRED]" % matched_fragment
	
	return result

static func _handle_decrypt_fragment(puzzle: PuzzleData, command: CommandParser.CommandResult) -> PuzzleResult:
	var result := PuzzleResult.new()
	var data: Dictionary = puzzle.custom_data
	var target := command.target.to_lower() if not command.target.is_empty() else ""
	
	if target.is_empty():
		result.message = "decrypt: missing target\nUsage: decrypt <file>"
		return result
	
	var found: Array = data.get("fragments_found", [])
	var decrypted: Array = data.get("fragments_decrypted", [])
	
	# Only fragment_003 is encrypted
	if ".fragment_003" in target or target in ".fragment_003":
		if ".fragment_003" not in found:
			result.message = "decrypt: fragment_003 not located yet. Use 'find' first."
			return result
		
		if ".fragment_003" in decrypted:
			result.message = "decrypt: fragment_003 already decrypted"
			return result
		
		# DO NOT update state yet - timing must succeed first!
		result.state_change["pending_decrypt"] = ".fragment_003"
		result.state_change["decrypted_array"] = decrypted
		
		result.requires_timing = true
		result.timing_difficulty = 1.2  # Slightly harder
		result.message = "Decrypting .fragment_003... [TIMING REQUIRED]"
	else:
		result.message = "decrypt: '%s' is not encrypted" % target
	
	return result

static func _handle_cat_fragments(puzzle: PuzzleData, _command: CommandParser.CommandResult) -> PuzzleResult:
	var result := PuzzleResult.new()
	var data: Dictionary = puzzle.custom_data
	
	var restored: Array = data.get("fragments_restored", [])
	var required: Array = data.get("required_fragments", [])
	
	if restored.size() < required.size():
		result.message = "cat: cannot assemble - missing fragments\nRestored: %d/%d" % [restored.size(), required.size()]
		return result
	
	if data.get("file_assembled", false):
		result.message = "cat: file already assembled as 'recovered_file'"
		return result
	
	# Assemble the file
	data["file_assembled"] = true
	
	result.success = true
	result.progress_made = true
	result.message = """Concatenating fragments...
.fragment_001 + .fragment_002 + .fragment_003
[========================================] 100%

File assembled as 'recovered_file'
Note: File may be corrupted. Run 'compile' to verify integrity."""
	
	return result

static func _handle_compile_file(puzzle: PuzzleData, _command: CommandParser.CommandResult) -> PuzzleResult:
	var result := PuzzleResult.new()
	var data: Dictionary = puzzle.custom_data
	
	if not data.get("file_assembled", false):
		result.message = "compile: no file to compile. Assemble fragments first with 'cat'."
		return result
	
	if data.get("file_compiled", false):
		result.message = "compile: file already verified"
		return result
	
	# Final compile requires timing! This is the most critical moment
	result.success = true
	result.progress_made = true
	result.requires_timing = true
	result.timing_difficulty = 1.5  # Hardest timing in puzzle
	result.state_change["pending_compile"] = true
	result.message = """Compiling recovered_file... [TIMING REQUIRED]

This is the final step! Time it perfectly to ensure complete recovery."""
	
	return result

static func _handle_list_fragments(puzzle: PuzzleData, _command: CommandParser.CommandResult) -> PuzzleResult:
	var result := PuzzleResult.new()
	var data: Dictionary = puzzle.custom_data
	
	var found: Array = data.get("fragments_found", [])
	var restored: Array = data.get("fragments_restored", [])
	var decrypted: Array = data.get("fragments_decrypted", [])
	
	result.success = true
	result.message = "=== Fragment Status ===\n"
	
	for frag in data.get("required_fragments", []):
		var status := "[ ]"
		if frag in restored:
			status = "[✓] RESTORED"
		elif frag in found:
			if frag == ".fragment_003":
				status = "[~] ENCRYPTED" if frag not in decrypted else "[~] DECRYPTED"
			else:
				status = "[~] LOCATED"
		result.message += "%s %s\n" % [status, frag]
	
	if data.get("file_assembled", false):
		result.message += "\n> recovered_file [ASSEMBLED]"
		if data.get("file_compiled", false):
			result.message += " [VERIFIED]"
	
	return result

static func _handle_scan_puzzle(puzzle: PuzzleData, _command: CommandParser.CommandResult) -> PuzzleResult:
	var result := PuzzleResult.new()
	result.success = true
	result.message = puzzle.description
	result.message += "\n\nCurrent hint: " + puzzle.get_next_hint()
	return result

static func _calculate_progress(puzzle: PuzzleData) -> float:
	var data: Dictionary = puzzle.custom_data
	var total_steps := 7.0  # find + 3 restores + 1 decrypt + cat + compile
	var completed := 0.0
	
	var found: Array = data.get("fragments_found", [])
	var restored: Array = data.get("fragments_restored", [])
	var decrypted: Array = data.get("fragments_decrypted", [])
	
	if found.size() >= 3:
		completed += 1.0
	completed += restored.size()
	completed += decrypted.size()
	if data.get("file_assembled", false):
		completed += 1.0
	if data.get("file_compiled", false):
		completed += 1.0
	
	return (completed / total_steps) * 100.0
#endregion

#region Generic Puzzle Processing

## Process any puzzle type
static func process_puzzle_command(puzzle: PuzzleData, command: CommandParser.CommandResult) -> PuzzleResult:
	match puzzle.puzzle_type:
		PuzzleType.FILE_RECOVERY:
			return process_lost_file_command(puzzle, command)
		PuzzleType.PATH_FINDING:
			return _process_path_finding(puzzle, command)
		PuzzleType.PERMISSION_FIX:
			return _process_permission_fix(puzzle, command)
		PuzzleType.DATA_SORTING:
			return _process_data_sorting(puzzle, command)
		PuzzleType.SEQUENCE:
			return _process_sequence(puzzle, command)
		_:
			var result := PuzzleResult.new()
			result.message = "Puzzle type not implemented."
			return result

static func _process_path_finding(_puzzle: PuzzleData, _command: CommandParser.CommandResult) -> PuzzleResult:
	var result := PuzzleResult.new()
	# TODO: Implement path navigation puzzle
	result.message = "Path finding puzzle processing..."
	return result

static func _process_permission_fix(_puzzle: PuzzleData, _command: CommandParser.CommandResult) -> PuzzleResult:
	var result := PuzzleResult.new()
	# TODO: Implement chmod puzzle
	result.message = "Permission fix puzzle processing..."
	return result

static func _process_data_sorting(_puzzle: PuzzleData, _command: CommandParser.CommandResult) -> PuzzleResult:
	var result := PuzzleResult.new()
	# TODO: Implement sorting puzzle
	result.message = "Data sorting puzzle processing..."
	return result

static func _process_sequence(puzzle: PuzzleData, command: CommandParser.CommandResult) -> PuzzleResult:
	var result := PuzzleResult.new()
	var data: Dictionary = puzzle.custom_data
	var expected_sequence: Array = data.get("expected_sequence", [])
	var current_index: int = data.get("current_index", 0)
	
	if current_index >= expected_sequence.size():
		result.puzzle_complete = true
		result.message = "Sequence already complete!"
		return result
	
	var expected_cmd: String = expected_sequence[current_index]
	var input_cmd := command.raw_input.to_lower().strip_edges()
	var expected_lower := expected_cmd.to_lower().strip_edges()
	var command_matches_expected := expected_cmd in input_cmd or input_cmd in expected_cmd
	var is_final_compile_step := command.command_type == CommandParser.CommandType.COMPILE and current_index == expected_sequence.size() - 1
	is_final_compile_step = is_final_compile_step or expected_lower.begins_with("compile ") or expected_lower.begins_with("make ")

	# If the player's command matches the expected step, resolve progression first,
	# even for commands like LIST that are otherwise treated as informational.
	if command_matches_expected:
		var timing_steps: Array = data.get("timing_steps", [])
		if is_final_compile_step:
			result.requires_timing = true
			result.timing_difficulty = 1.6
			result.state_change["pending_sequence"] = {
				"next_index": current_index + 1,
				"total": expected_sequence.size()
			}
			result.state_change["use_node_connect"] = true
			result.message = "Final build check pending... [NODE CONNECT REQUIRED]"
		elif timing_steps.has(current_index):
			result.requires_timing = true
			result.timing_difficulty = data.get("timing_difficulty_map", {}).get(current_index, 1.0)
			result.state_change["pending_sequence"] = {
				"next_index": current_index + 1,
				"total": expected_sequence.size()
			}
			result.message = "Step %d/%d pending... [TIMING REQUIRED]" % [current_index + 1, expected_sequence.size()]
		else:
			data["current_index"] = current_index + 1
			result.success = true
			result.progress_made = true
			result.message = "Step %d/%d complete." % [current_index + 1, expected_sequence.size()]

			if current_index + 1 >= expected_sequence.size():
				result.puzzle_complete = true
				puzzle.state = PuzzleState.SOLVED
				result.message += "\nSequence complete!"

		result.progress_percent = (float(data.get("current_index", 0)) / float(expected_sequence.size())) * 100.0
		return result

	# Discovery commands should help the player orient, not fail progression.
	if command.command_type == CommandParser.CommandType.LIST:
		result.success = true
		result.progress_made = false
		result.message = _build_sequence_directory_snapshot(puzzle, current_index)
		result.progress_percent = (float(data.get("current_index", 0)) / float(expected_sequence.size())) * 100.0
		return result

	if command.command_type == CommandParser.CommandType.HELP or command.command_type == CommandParser.CommandType.SCAN:
		result.success = true
		result.progress_made = false
		result.message = _build_sequence_guidance_message(puzzle, expected_cmd, current_index, expected_sequence.size())
		result.progress_percent = (float(data.get("current_index", 0)) / float(expected_sequence.size())) * 100.0
		return result
	
	# No match and not an informational command: show guided mismatch feedback.
	result.message = _build_wrong_sequence_command_message(puzzle, expected_cmd, current_index, expected_sequence.size())
	# Optionally reset sequence
	if data.get("reset_on_fail", false):
		data["current_index"] = 0
		result.message += "\nSequence reset."
	
	result.progress_percent = (float(data.get("current_index", 0)) / float(expected_sequence.size())) * 100.0
	return result

static func _build_sequence_directory_snapshot(puzzle: PuzzleData, current_index: int) -> String:
	var clue_files: Array = puzzle.custom_data.get("clue_files", [])
	if clue_files.is_empty():
		return "Directory listing unavailable. Use scan for guidance."

	var lines: Array[String] = ["=== Local Directory Snapshot ==="]
	for i in range(clue_files.size()):
		var clue := str(clue_files[i])
		if i == current_index:
			# Highlight the current clue
			lines.append("* [color=#8CFF8C]%s[/color]  [color=#FFD27F]current clue[/color]" % clue)
		else:
			lines.append("- %s" % clue)
	var expected_sequence: Array = puzzle.custom_data.get("expected_sequence", [])
	if current_index >= 0 and current_index < expected_sequence.size():
		var expected_cmd := str(expected_sequence[current_index]).strip_edges()
		var verbs := _verb_family_for_expected(expected_cmd)
		if not verbs.is_empty():
			lines.append("Verb family now: %s" % ", ".join(verbs))
	lines.append("Tip: read the current clue file first, then use one verb from the family above.")
	return "\n".join(lines)

static func _build_sequence_guidance_message(_puzzle: PuzzleData, expected_cmd: String, current_index: int, total_steps: int) -> String:
	var lower := expected_cmd.to_lower().strip_edges()
	var noun := _extract_expected_noun(expected_cmd)
	var verbs := _verb_family_for_expected(expected_cmd)
	var phase := _phase_from_expected_command(expected_cmd)
	var header := "[color=#7FD7FF]TUX GUIDANCE[/color] // %s PHASE ([color=#FFD27F]%d/%d[/color])" % [phase, current_index + 1, maxi(1, total_steps)]
	var verb_line := "Try verbs: [color=#7FD7FF]%s[/color]" % (", ".join(verbs) if not verbs.is_empty() else "scan, ls, help")
	var noun_line := "Current noun from clues: [color=#8CFF8C]%s[/color]" % noun

	if lower.begins_with("cat"):
		return "%s\n%s\n%s\nUse a read-only command on the clue file to inspect state." % [header, noun_line, verb_line]
	if lower.begins_with("find"):
		return "%s\n%s\n%s\nSearch for the noun/token shown by logs or file text." % [header, noun_line, verb_line]
	if lower.begins_with("kill"):
		return "%s\n%s\n%s\nUse a process-termination verb on the unstable target." % [header, noun_line, verb_line]
	if lower.begins_with("unlink"):
		return "%s\n%s\n%s\nDetach stale links before rebuilding routes." % [header, noun_line, verb_line]
	if lower.begins_with("chmod"):
		return "%s\n%s\n%s\nNormalize permissions before the final rebuild action." % [header, noun_line, verb_line]
	if lower.begins_with("make") or lower.begins_with("compile"):
		return "%s\n%s\n%s\nFinal step: rebuild and validate to finish the encounter." % [header, noun_line, verb_line]
	return "%s\n%s\n%s\nUse SCAN -> ANALYZE -> EXECUTE. If stuck, run ls and read the current clue file." % [header, noun_line, verb_line]

static func _build_wrong_sequence_command_message(puzzle: PuzzleData, expected_cmd: String, current_index: int, total_steps: int) -> String:
	var clue_files: Array = puzzle.custom_data.get("clue_files", [])
	var noun := _extract_expected_noun(expected_cmd)
	if current_index >= 0 and current_index < clue_files.size():
		noun = str(clue_files[current_index])
	var verbs := _verb_family_for_expected(expected_cmd)
	var phase := _phase_from_expected_command(expected_cmd)
	return "[color=#FF7F7F]Wrong command.[/color]\nPhase: %s ([color=#FFD27F]%d/%d[/color])\nNoun: [color=#8CFF8C]%s[/color]\nUse one verb from: [color=#7FD7FF]%s[/color]\nTip: type [color=#FFD27F]ls[/color] to view clue files or [color=#FFD27F]scan[/color] for guidance." % [phase, current_index + 1, maxi(1, total_steps), noun, ", ".join(verbs)]

static func _extract_expected_noun(expected_cmd: String) -> String:
	var tokens := expected_cmd.strip_edges().split(" ", false)
	if tokens.size() >= 2:
		return str(tokens[1]).strip_edges()
	return "current_clue"

static func _phase_from_expected_command(expected_cmd: String) -> String:
	var lower := expected_cmd.to_lower().strip_edges()
	if lower.begins_with("cat") or lower.begins_with("ls"):
		return "SCAN"
	if lower.begins_with("find"):
		return "ANALYZE"
	return "EXECUTE"

static func _verb_family_for_expected(expected_cmd: String) -> Array[String]:
	var lower := expected_cmd.to_lower().strip_edges()
	if lower.begins_with("ls"):
		return ["ls", "dir", "list"]
	if lower.begins_with("cat"):
		return ["cat", "read", "open"]
	if lower.begins_with("find"):
		return ["find", "search", "locate"]
	if lower.begins_with("kill"):
		return ["kill", "terminate"]
	if lower.begins_with("unlink"):
		return ["unlink", "disconnect"]
	if lower.begins_with("ln"):
		return ["ln", "link", "connect"]
	if lower.begins_with("rm"):
		return ["rm", "delete", "remove"]
	if lower.begins_with("chmod"):
		return ["chmod", "permissions"]
	if lower.begins_with("make") or lower.begins_with("compile"):
		return ["make", "build", "compile"]
	return ["scan", "help"]
#endregion
#region Timing Minigame Integration

## Apply timing result to a puzzle command
## zone: 0 = MISS, 1 = NORMAL, 2 = CRITICAL
## Returns updated PuzzleResult based on timing
static func apply_timing_to_puzzle(puzzle: PuzzleData, original_result: PuzzleResult, zone: int, success_chance: float) -> PuzzleResult:
	var result := original_result
	var data: Dictionary = puzzle.custom_data
	
	# Handle timing based on zone
	match zone:
		2:  # CRITICAL - Perfect execution
			data["timing_critical_hits"] = int(data.get("timing_critical_hits", 0)) + 1
			result.message = "PERFECT TIMING!\n"
			_apply_critical_timing(puzzle, result, data)
		1:  # NORMAL - Success with chance
			if randf() < success_chance:
				result.message = "Good timing!\n"
				_apply_normal_timing(puzzle, result, data)
			else:
				result.message = "Timing was off... Command partially failed.\n"
				result.success = false
				result.progress_made = false
		0, _:  # MISS - Command fails
			result.message = "MISS! Command failed to execute.\n"
			result.success = false
			result.progress_made = false
			result.puzzle_complete = false
	
	return result

static func _apply_critical_timing(puzzle: PuzzleData, result: PuzzleResult, data: Dictionary) -> void:
	# Handle pending actions with bonus effects
	if result.state_change.has("pending_restore"):
		var fragment: String = result.state_change["pending_restore"]
		var restored: Array = result.state_change.get("restored_array", [])
		var required_size: int = result.state_change.get("required_size", 3)
		
		if fragment not in restored:
			restored.append(fragment)
			data["fragments_restored"] = restored
		
		result.message += "Recovered %s with enhanced integrity! (%d/%d fragments restored)" % [
			fragment,
			restored.size(),
			required_size
		]
		result.progress_made = true
		
	elif result.state_change.has("pending_decrypt"):
		var decrypted: Array = result.state_change.get("decrypted_array", [])
		if ".fragment_003" not in decrypted:
			decrypted.append(".fragment_003")
			data["fragments_decrypted"] = decrypted
		result.message += "Decrypted .fragment_003 with perfect precision!"
		result.progress_made = true
		
	elif result.state_change.has("pending_compile"):
		# Perfect compile!
		data["file_compiled"] = true
		puzzle.state = PuzzleState.SOLVED
		result.puzzle_complete = true
		result.progress_percent = 100.0
		result.message += """Compiling recovered_file...
Checking integrity... PERFECT
Verifying checksums... VERIFIED
Rebuilding index... OPTIMIZED

[PERFECT SUCCESS] File fully recovered with bonus integrity!

The Lost File has been restored to its original state.
It remembers who it once was... and is grateful for your skill."""
	elif result.state_change.has("pending_sequence"):
		var pending: Dictionary = result.state_change.get("pending_sequence", {})
		var next_index: int = pending.get("next_index", 0)
		var total: int = pending.get("total", 0)
		data["current_index"] = next_index
		result.progress_made = true
		result.message += "Step %d/%d locked in with perfect timing." % [next_index, total]
		result.progress_percent = (float(next_index) / float(total)) * 100.0
		if next_index >= total:
			result.puzzle_complete = true
			puzzle.state = PuzzleState.SOLVED
			result.message += "\nSequence complete!"
	else:
		# Generic critical success
		result.message += "Command executed with maximum efficiency!"

static func _apply_normal_timing(puzzle: PuzzleData, result: PuzzleResult, data: Dictionary) -> void:
	# Handle pending actions normally
	if result.state_change.has("pending_restore"):
		var fragment: String = result.state_change["pending_restore"]
		var restored: Array = result.state_change.get("restored_array", [])
		var required_size: int = result.state_change.get("required_size", 3)
		
		if fragment not in restored:
			restored.append(fragment)
			data["fragments_restored"] = restored
		
		result.message += "Recovered %s successfully. (%d/%d fragments restored)" % [
			fragment,
			restored.size(),
			required_size
		]
		result.progress_made = true
		
	elif result.state_change.has("pending_decrypt"):
		var decrypted: Array = result.state_change.get("decrypted_array", [])
		if ".fragment_003" not in decrypted:
			decrypted.append(".fragment_003")
			data["fragments_decrypted"] = decrypted
		result.message += "Decrypted .fragment_003 successfully."
		result.progress_made = true
		
	elif result.state_change.has("pending_compile"):
		# Normal compile
		data["file_compiled"] = true
		puzzle.state = PuzzleState.SOLVED
		result.puzzle_complete = true
		result.progress_percent = 100.0
		result.message += """Compiling recovered_file...
Checking integrity... OK
Verifying checksums... OK
Rebuilding index... OK

[SUCCESS] File fully recovered!

The Lost File has been restored to its original state.
It remembers who it once was..."""
	elif result.state_change.has("pending_sequence"):
		var pending: Dictionary = result.state_change.get("pending_sequence", {})
		var next_index: int = pending.get("next_index", 0)
		var total: int = pending.get("total", 0)
		data["current_index"] = next_index
		result.progress_made = true
		result.message += "Step %d/%d complete." % [next_index, total]
		result.progress_percent = (float(next_index) / float(total)) * 100.0
		if next_index >= total:
			result.puzzle_complete = true
			puzzle.state = PuzzleState.SOLVED
			result.message += "\nSequence complete!"
	else:
		# Generic normal success
		result.message += "Command executed successfully."

#endregion