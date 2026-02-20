# CommandSuggestions.gd
# Isolation layer for command autocomplete
# Wraps CommandParser.get_suggestions() for testability and future extension
# DATA FLOW: InputController → CommandSuggestions → CommandParser (static)
extends RefCounted
class_name CommandSuggestions

## Get autocomplete suggestions for a given prefix.
## Returns an Array of matching command strings.
## This wrapper exists to:
## 1. Make autocomplete testable in isolation
## 2. Allow future replacement with AI/fuzzy search
## 3. Decouple InputController from CommandParser directly
static func suggest(prefix: String) -> Array:
	return CommandParser.get_suggestions(prefix)

## Get the first suggestion, or empty string if none.
static func suggest_first(prefix: String) -> String:
	var suggestions := suggest(prefix)
	return suggestions[0] if suggestions.size() > 0 else ""

## Get all available commands (for help display).
static func get_all_commands() -> Array:
	return CommandParser.get_suggestions("")
