# InputController.gd
# User input handling: LineEdit, Tab autocomplete, suggestions
# DATA FLOW: User types → InputController → command_submitted signal → Coordinator
# NEVER calls CombatManager directly. Only emits signals.
extends Control
class_name InputController

## Emitted when user submits a command (presses Enter)
signal command_submitted(text: String)

## Path to the LineEdit for command input
@export var input_path: NodePath

## Path to the turn indicator Label
@export var turn_label_path: NodePath

## Path to the suggestion Label
@export var suggestion_label_path: NodePath

## Resolved node references
var _input: LineEdit = null
var _turn_label: Label = null
var _suggest_label: Label = null

#region Initialization

func _ready() -> void:
	_resolve_nodes()
	_connect_signals()

func _resolve_nodes() -> void:
	# Resolve LineEdit
	if input_path and has_node(input_path):
		_input = get_node(input_path)
	else:
		_input = _find_child_of_type("LineEdit")
	
	# Resolve turn label
	if turn_label_path and has_node(turn_label_path):
		_turn_label = get_node(turn_label_path)
	
	# Resolve suggestion label
	if suggestion_label_path and has_node(suggestion_label_path):
		_suggest_label = get_node(suggestion_label_path)
	
	# Warn if critical nodes missing
	if not _input:
		push_warning("InputController: No LineEdit found. Input disabled.")

func _find_child_of_type(type_name: String) -> Node:
	for child in get_children():
		if child.get_class() == type_name:
			return child
	return null

func _connect_signals() -> void:
	if _input:
		_input.text_submitted.connect(_on_text_submitted)
		_input.text_changed.connect(_on_text_changed)

#endregion

#region Public API

## Enable or disable input field.
## @param enabled: Whether input should be editable
func set_enabled(enabled: bool) -> void:
	if _input:
		_input.editable = enabled
		if enabled:
			_input.grab_focus()

## Set the turn indicator text.
## @param text: Text to display (e.g. "<< YOUR TURN >>")
func set_turn_text(text: String) -> void:
	if _turn_label:
		_turn_label.text = text

## Clear the input field.
func clear_input() -> void:
	if _input:
		_input.text = ""
		_update_suggestion("")

## Focus the input field.
func focus_input() -> void:
	if _input:
		_input.grab_focus()

## Get current input text.
func get_input_text() -> String:
	return _input.text if _input else ""

#endregion

#region Input Handlers

func _on_text_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	
	# Emit signal - coordinator handles routing
	command_submitted.emit(trimmed)
	
	# Clear input after submission
	if _input:
		_input.text = ""
		_update_suggestion("")

func _on_text_changed(new_text: String) -> void:
	_update_suggestion(new_text)

func _update_suggestion(prefix: String) -> void:
	if not _suggest_label:
		return
	
	var suggestion := CommandSuggestions.suggest_first(prefix)
	_suggest_label.text = suggestion

#endregion

#region Tab Autocomplete

func _unhandled_input(event: InputEvent) -> void:
	if not _input:
		return
	
	# Handle Tab key for autocomplete
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_handle_tab_complete()
		get_viewport().set_input_as_handled()

func _handle_tab_complete() -> void:
	if not _input:
		return
	
	var prefix := _input.text.strip_edges()
	var suggestions := CommandSuggestions.suggest(prefix)
	
	if suggestions.size() == 0:
		return
	
	var first_suggestion: String = suggestions[0]
	
	# If already matches first suggestion, add space
	if prefix == first_suggestion:
		_input.text = first_suggestion + " "
	else:
		_input.text = first_suggestion
	
	# Move caret to end
	_input.caret_column = _input.text.length()
	
	# Show next suggestion if available
	if _suggest_label:
		_suggest_label.text = suggestions[1] if suggestions.size() > 1 else ""

#endregion
