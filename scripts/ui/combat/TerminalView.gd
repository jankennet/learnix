# TerminalView.gd
# Output-only terminal display with typewriter effect
# DATA FLOW: CombatUIController → TerminalView.print_message()
# NO input handling. NO game logic. Just text display.
extends Control
class_name TerminalView

## Emitted when typewriter finishes (can be used for sequencing)
signal typewriter_finished()

## Path to the RichTextLabel node for terminal output
@export var terminal_path: NodePath

## Typing speed in seconds per character (0 = instant)
@export var typing_speed: float = 0.01

## Reference to the terminal label (resolved from path or child)
var _terminal: RichTextLabel = null

## Flag to skip typewriter animation
var _typing_skip: bool = false

## Lock to prevent overlapping typewriter calls
var _typing_active: bool = false

#region Initialization

func _ready() -> void:
	_resolve_terminal()
	if _terminal:
		_terminal.bbcode_enabled = true
	else:
		push_warning("TerminalView: No RichTextLabel found. Terminal output disabled.")

func _resolve_terminal() -> void:
	if terminal_path and has_node(terminal_path):
		_terminal = get_node(terminal_path)
	else:
		# Fallback: find first RichTextLabel child
		for child in get_children():
			if child is RichTextLabel:
				_terminal = child
				break

#endregion

#region Public API

## Print a message to the terminal with typewriter effect.
## @param text: The message to display
## @param color: The text color
func print_message(text: String, color: Color = Color.WHITE) -> void:
	if not _terminal:
		push_warning("TerminalView: Cannot print, terminal not available.")
		return
	await _typewriter_append(text + "\n", color)

## Print a message instantly without typewriter effect.
## @param text: The message to display
## @param color: The text color
func print_instant(text: String, color: Color = Color.WHITE) -> void:
	if not _terminal:
		return
	var hex := color.to_html(false)
	_terminal.append_text("[color=#%s]%s\n[/color]" % [hex, text])
	_scroll_to_bottom()

## Clear all terminal content.
func clear() -> void:
	if _terminal:
		_terminal.clear()

## Skip any ongoing typewriter animation.
func skip_typewriter() -> void:
	_typing_skip = true

## Check if typewriter is currently animating.
func is_typing() -> bool:
	return _typing_active

#endregion

#region Color Mapping

## Map message type enum to display color.
## This accepts the MessageType from TurnCombatManager.
## CRT Terminal Color Palette - classic phosphor green with accent colors
## @param type: The message type value
## @param manager_ref: Optional reference to get enum values
static func get_message_color(type: int, _manager_ref = null) -> Color:
	# Classic CRT terminal color palette
	# INFO=0, SUCCESS=1, WARNING=2, ERROR=3, DAMAGE=4, HEAL=5, STATUS=6
	match type:
		1:  # SUCCESS - Bright phosphor green
			return Color(0.3, 0.95, 0.3)
		2:  # WARNING - Amber/yellow (secondary CRT color)
			return Color(0.9, 0.8, 0.2)
		3:  # ERROR - Muted red (for readability on dark bg)
			return Color(0.9, 0.35, 0.3)
		4:  # DAMAGE - Orange-amber
			return Color(0.9, 0.55, 0.2)
		5:  # HEAL - Bright cyan-green
			return Color(0.3, 0.9, 0.7)
		6:  # STATUS - Gold/amber
			return Color(0.85, 0.75, 0.25)
		_:  # INFO or unknown - Standard phosphor green
			return Color(0.3, 0.9, 0.3)

#endregion

#region Typewriter Implementation

func _typewriter_append(text: String, color: Color) -> void:
	if not _terminal:
		return
	
	var hex := color.to_html(false)
	
	# Very short text: just append
	if text.length() < 2 or typing_speed <= 0:
		_terminal.append_text("[color=#%s]%s[/color]" % [hex, text])
		_scroll_to_bottom()
		typewriter_finished.emit()
		return
	
	_typing_active = true
	_typing_skip = false
	
	for i in range(text.length()):
		_terminal.append_text("[color=#%s]%s[/color]" % [hex, text[i]])
		_scroll_to_bottom()
		
		if _typing_skip:
			# Complete remaining text instantly
			_terminal.append_text("[color=#%s]%s[/color]" % [hex, text.substr(i + 1)])
			break
		
		await get_tree().create_timer(typing_speed).timeout
	
	_scroll_to_bottom()
	_typing_active = false
	typewriter_finished.emit()

func _scroll_to_bottom() -> void:
	if _terminal:
		_terminal.scroll_to_line(_terminal.get_line_count())

#endregion

#region Input Handling (Skip Typewriter)

func _unhandled_input(event: InputEvent) -> void:
	# Allow any key press to skip typewriter when active
	if _typing_active and event is InputEventKey and event.pressed:
		skip_typewriter()

#endregion
