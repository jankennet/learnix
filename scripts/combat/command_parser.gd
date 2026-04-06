# command_parser.gd
# Core command parsing system for turn-based text input gameplay
# Validates, tokenizes, and resolves player typed commands
extends RefCounted
class_name CommandParser

#region Command Types
enum CommandType {
	UNKNOWN,
	# Combat Commands
	ATTACK,         # attack, hit, strike
	DEFEND,         # defend, block, guard
	SCAN,           # scan, analyze, inspect
	HEAL,           # heal, restore, repair
	ESCAPE,         # escape, flee, run
	# File System Commands (thematic)
	DELETE,         # rm, del, delete
	MOVE,           # mv, move
	COPY,           # cp, copy
	FIND,           # find, locate, search
	RESTORE,        # restore, recover, undelete
	LIST,           # ls, dir, list
	READ,           # cat, read, open
	WRITE,          # echo, write
	CHMOD,          # chmod, permissions
	KILL,           # kill, terminate
	# Puzzle Commands
	CONNECT,        # connect, link
	DISCONNECT,     # disconnect, unlink
	SORT,           # sort, order
	RENAME,         # rename, mv
	DECRYPT,        # decrypt, decode
	ENCRYPT,        # encrypt, encode
	EXECUTE,        # exec, run, ./
	COMPILE,        # compile, build
	DEBUG,          # debug, trace
	PATCH,          # patch, fix
	HELP,           # help
}
#endregion

#region Command Result
class CommandResult:
	var success: bool = false
	var command_type: CommandType = CommandType.UNKNOWN
	var target: String = ""
	var arguments: Array[String] = []
	var raw_input: String = ""
	var error_message: String = ""
	var partial_match: bool = false  # For typo tolerance
	var suggested_command: String = ""
	
	func _init(raw: String = ""):
		raw_input = raw
	
	func is_valid() -> bool:
		return success and command_type != CommandType.UNKNOWN
#endregion

#region Command Definitions
# Maps input strings to command types with aliases
const COMMAND_ALIASES: Dictionary = {
	# Combat basics
	"attack": CommandType.ATTACK,
	"hit": CommandType.ATTACK,
	"strike": CommandType.ATTACK,
	"atk": CommandType.ATTACK,
	
	"defend": CommandType.DEFEND,
	"block": CommandType.DEFEND,
	"guard": CommandType.DEFEND,
	"def": CommandType.DEFEND,
	
	"scan": CommandType.SCAN,
	"analyze": CommandType.SCAN,
	"inspect": CommandType.SCAN,
	"info": CommandType.SCAN,
	
	"heal": CommandType.HEAL,
	"repair": CommandType.HEAL,
	"mend": CommandType.HEAL,
	
	"escape": CommandType.ESCAPE,
	"flee": CommandType.ESCAPE,
	"run": CommandType.ESCAPE,
	"exit": CommandType.ESCAPE,
	
	# File system themed commands
	"rm": CommandType.DELETE,
	"del": CommandType.DELETE,
	"delete": CommandType.DELETE,
	"remove": CommandType.DELETE,
	
	"mv": CommandType.MOVE,
	"move": CommandType.MOVE,
	
	"cp": CommandType.COPY,
	"copy": CommandType.COPY,
	"duplicate": CommandType.COPY,
	
	"find": CommandType.FIND,
	"locate": CommandType.FIND,
	"search": CommandType.FIND,
	"whereis": CommandType.FIND,
	
	"undelete": CommandType.RESTORE,
	"recover": CommandType.RESTORE,
	"restore": CommandType.RESTORE,
	
	"ls": CommandType.LIST,
	"dir": CommandType.LIST,
	"list": CommandType.LIST,
	
	"cat": CommandType.READ,
	"read": CommandType.READ,
	"open": CommandType.READ,
	"less": CommandType.READ,
	"more": CommandType.READ,
	
	"echo": CommandType.WRITE,
	"write": CommandType.WRITE,
	"printf": CommandType.WRITE,
	
	"chmod": CommandType.CHMOD,
	"chown": CommandType.CHMOD,
	"permissions": CommandType.CHMOD,
	
	"kill": CommandType.KILL,
	"terminate": CommandType.KILL,
	"pkill": CommandType.KILL,
	"killall": CommandType.KILL,
	
	# Puzzle commands
	"connect": CommandType.CONNECT,
	"link": CommandType.CONNECT,
	"ln": CommandType.CONNECT,
	
	"disconnect": CommandType.DISCONNECT,
	"unlink": CommandType.DISCONNECT,
	
	"sort": CommandType.SORT,
	"order": CommandType.SORT,
	
	"rename": CommandType.RENAME,
	
	"decrypt": CommandType.DECRYPT,
	"decode": CommandType.DECRYPT,
	"decipher": CommandType.DECRYPT,
	
	"encrypt": CommandType.ENCRYPT,
	"encode": CommandType.ENCRYPT,
	"cipher": CommandType.ENCRYPT,
	
	"exec": CommandType.EXECUTE,
	"execute": CommandType.EXECUTE,
	"./": CommandType.EXECUTE,
	
	"compile": CommandType.COMPILE,
	"build": CommandType.COMPILE,
	"make": CommandType.COMPILE,
	"gcc": CommandType.COMPILE,
	
	"debug": CommandType.DEBUG,
	"trace": CommandType.DEBUG,
	"gdb": CommandType.DEBUG,
	
	"patch": CommandType.PATCH,
	"fix": CommandType.PATCH,
	"hotfix": CommandType.PATCH,
	
	"help": CommandType.HELP,
	"?": CommandType.HELP,
}

# Commands that require a target
const REQUIRES_TARGET: Array[CommandType] = [
	CommandType.DELETE,
	CommandType.MOVE,
	CommandType.COPY,
	CommandType.READ,
	CommandType.WRITE,
	CommandType.RENAME,
	CommandType.KILL,
	CommandType.CONNECT,
	CommandType.DISCONNECT,
	CommandType.CHMOD,
]

# Commands that can have optional arguments
const OPTIONAL_ARGS: Array[CommandType] = [
	CommandType.SCAN,
	CommandType.FIND,
	CommandType.LIST,
	CommandType.ATTACK,
]
#endregion

#region Parsing Logic

## Main parsing function - takes raw player input and returns CommandResult
static func parse(input: String) -> CommandResult:
	var result := CommandResult.new(input)
	
	# Sanitize input
	var cleaned := input.strip_edges().to_lower()
	
	if cleaned.is_empty():
		result.error_message = "No command entered. Type 'help' for available commands."
		return result
	
	# Tokenize the input
	var tokens := _tokenize(cleaned)
	
	if tokens.is_empty():
		result.error_message = "Invalid input format."
		return result
	
	# First token is the command
	var cmd_token := tokens[0]
	
	# Check for exact match
	if COMMAND_ALIASES.has(cmd_token):
		result.command_type = COMMAND_ALIASES[cmd_token]
		result.success = true
	else:
		# Try fuzzy matching for typo tolerance
		var fuzzy_result := _fuzzy_match(cmd_token)
		if fuzzy_result.found:
			result.command_type = COMMAND_ALIASES[fuzzy_result.match]
			result.partial_match = true
			result.suggested_command = fuzzy_result.match
			result.success = true
		else:
			result.error_message = "Unknown command: '%s'. Type 'help' for available commands." % cmd_token
			return result
	
	# Extract target and arguments
	if tokens.size() > 1:
		result.target = tokens[1]
		for i in range(2, tokens.size()):
			result.arguments.append(tokens[i])
	
	# Validate required targets
	if result.command_type in REQUIRES_TARGET and result.target.is_empty():
		result.success = false
		result.error_message = "Command '%s' requires a target." % cmd_token
		return result
	
	return result

## Tokenize input string into parts
static func _tokenize(input: String) -> Array[String]:
	var tokens: Array[String] = []
	var parts := input.split(" ", false)  # Split by space, skip empty
	
	for part in parts:
		var cleaned := part.strip_edges()
		if not cleaned.is_empty():
			tokens.append(cleaned)
	
	return tokens

## Fuzzy matching for typo tolerance (Levenshtein distance)
static func _fuzzy_match(input: String) -> Dictionary:
	var best_match := ""
	var best_distance := 999
	var threshold := 2  # Max allowed edit distance
	
	for cmd in COMMAND_ALIASES.keys():
		var distance := _levenshtein_distance(input, cmd)
		if distance < best_distance and distance <= threshold:
			best_distance = distance
			best_match = cmd
	
	return {
		"found": not best_match.is_empty(),
		"match": best_match,
		"distance": best_distance
	}

## Calculate Levenshtein edit distance between two strings
static func _levenshtein_distance(s1: String, s2: String) -> int:
	var len1 := s1.length()
	var len2 := s2.length()
	
	if len1 == 0:
		return len2
	if len2 == 0:
		return len1
	
	var matrix: Array = []
	for i in range(len1 + 1):
		matrix.append([])
		for j in range(len2 + 1):
			matrix[i].append(0)
	
	for i in range(len1 + 1):
		matrix[i][0] = i
	for j in range(len2 + 1):
		matrix[0][j] = j
	
	for i in range(1, len1 + 1):
		for j in range(1, len2 + 1):
			var cost := 0 if s1[i - 1] == s2[j - 1] else 1
			matrix[i][j] = mini(
				mini(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
				matrix[i - 1][j - 1] + cost
			)
	
	return matrix[len1][len2]

## Get suggestions for autocomplete based on prefix
static func get_suggestions(prefix: String) -> Array:
	var p := prefix.strip_edges().to_lower()
	var out := []
	if p == "":
		return COMMAND_ALIASES.keys()
	for k in COMMAND_ALIASES.keys():
		if k.begins_with(p):
			out.append(k)
	return out
#endregion

#region Command Type Helpers

## Get display name for a command type
static func get_command_name(type: CommandType) -> String:
	match type:
		CommandType.ATTACK: return "Attack"
		CommandType.DEFEND: return "Defend"
		CommandType.SCAN: return "Scan"
		CommandType.HEAL: return "Heal"
		CommandType.ESCAPE: return "Escape"
		CommandType.DELETE: return "Delete"
		CommandType.MOVE: return "Move"
		CommandType.COPY: return "Copy"
		CommandType.FIND: return "Find"
		CommandType.RESTORE: return "Restore"
		CommandType.LIST: return "List"
		CommandType.READ: return "Read"
		CommandType.WRITE: return "Write"
		CommandType.CHMOD: return "Change Permissions"
		CommandType.KILL: return "Kill Process"
		CommandType.CONNECT: return "Connect"
		CommandType.DISCONNECT: return "Disconnect"
		CommandType.SORT: return "Sort"
		CommandType.RENAME: return "Rename"
		CommandType.DECRYPT: return "Decrypt"
		CommandType.ENCRYPT: return "Encrypt"
		CommandType.EXECUTE: return "Execute"
		CommandType.COMPILE: return "Compile"
		CommandType.DEBUG: return "Debug"
		CommandType.PATCH: return "Patch"
		CommandType.HELP: return "Help"
		_: return "Unknown"

## Check if command is combat-related
static func is_combat_command(type: CommandType) -> bool:
	return type in [
		CommandType.ATTACK,
		CommandType.DEFEND,
		CommandType.HEAL,
		CommandType.ESCAPE,
		CommandType.KILL,
		CommandType.RESTORE,
	]

## Check if command is puzzle-related
static func is_puzzle_command(type: CommandType) -> bool:
	return type in [
		CommandType.FIND,
		CommandType.RESTORE,
		CommandType.CONNECT,
		CommandType.DISCONNECT,
		CommandType.SORT,
		CommandType.RENAME,
		CommandType.DECRYPT,
		CommandType.COMPILE,
		CommandType.DEBUG,
		CommandType.PATCH,
	]

## Get help text for available commands
static func get_help_text(context: String = "all") -> String:
	var help := "=== AVAILABLE COMMANDS ===\n\n"
	
	if context == "combat" or context == "all":
		help += "[COMBAT]\n"
		help += "  attack, hit       - Strike the enemy\n"
		help += "  defend, block     - Reduce incoming damage\n"
		help += "  heal, repair      - Restore your integrity\n"
		help += "  kill <target>     - Taskkill finisher (requires taskkill skill)\n"
		help += "  restore           - Enemy-specific interaction (not a standard combat heal)\n"
		help += "  escape, flee      - Attempt to exit combat\n\n"
	
	if context == "puzzle" or context == "all":
		help += "[PUZZLE]\n"
		help += "  find <pattern>     - Search for files/data\n"
		help += "  restore <file>     - Recover deleted data\n"
		help += "  connect <a> <b>    - Link two nodes\n"
		help += "  sort <data>        - Order elements\n"
		help += "  decrypt <file>     - Decode encrypted data\n"
		help += "  compile <source>   - Build from source\n"
		help += "  patch <target>     - Apply fix to target\n"
		help += "  debug <process>    - Trace execution\n"
	
	return help
#endregion
