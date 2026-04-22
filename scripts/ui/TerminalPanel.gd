extends Control
class_name TerminalPanel

@onready var terminal_output: RichTextLabel = $PanelBg/MarginContainer/VBox/TerminalOutput
@onready var terminal_input: LineEdit = $PanelBg/MarginContainer/VBox/TerminalInputRow/TerminalInput
@onready var run_command_button: Button = $PanelBg/MarginContainer/VBox/TerminalInputRow/RunCommandButton
@onready var terminal_header: Control = $PanelBg/MarginContainer/VBox/TerminalHeader
@onready var fullscreen_button: Button = $PanelBg/MarginContainer/VBox/TerminalHeader/ButtonRow/FullscreenButton
@onready var close_button: Button = $PanelBg/MarginContainer/VBox/TerminalHeader/ButtonRow/CloseButton
@onready var minimize_button: Button = $PanelBg/MarginContainer/VBox/TerminalHeader/ButtonRow/MinimizeButton
@onready var panel_bg: PanelContainer = $PanelBg

const TERMINAL_BG = Color(0.02, 0.08, 0.02, 0.98)  # Almost black with green tint
const TERMINAL_TEXT = Color(0.4, 0.95, 0.45, 1.0)  # Bright phosphor green
const TERMINAL_BORDER = Color(0.4, 0.95, 0.45, 1.0)  # Match text color
const TERMINAL_FONT: FontFile = preload("res://Assets/fonts/PressStart2P-Regular.ttf")
const TERMINAL_FONT_SIZE := 12

func _ready() -> void:
	visible = false
	
	# Hide the run button - real terminals don't show it (but keep reference valid)
	if run_command_button:
		run_command_button.visible = true
		run_command_button.focus_mode = Control.FOCUS_NONE
	
	# Style the panel background with authentic CRT terminal colors
	var sb_main := StyleBoxFlat.new()
	sb_main.bg_color = TERMINAL_BG
	sb_main.border_width_left = 2
	sb_main.border_width_top = 2
	sb_main.border_width_right = 2
	sb_main.border_width_bottom = 2
	sb_main.border_color = TERMINAL_BORDER
	panel_bg.add_theme_stylebox_override("panel", sb_main)
	
	# Style terminal output with CRT phosphor green text
	terminal_output.add_theme_color_override("default_color", TERMINAL_TEXT)
	terminal_output.add_theme_font_override("normal_font", TERMINAL_FONT)
	terminal_output.add_theme_font_size_override("normal_font_size", TERMINAL_FONT_SIZE)
	terminal_output.autowrap_mode = TextServer.AUTOWRAP_OFF
	
	# Style header and buttons with CRT theme
	var header_label = terminal_header.get_node("HeaderLabel")
	header_label.add_theme_color_override("font_color", TERMINAL_TEXT)

	# Prevent chrome buttons from stealing keyboard focus from the command line.
	for button in [run_command_button, close_button, fullscreen_button, minimize_button]:
		if button:
			button.focus_mode = Control.FOCUS_NONE
	
	# Style buttons with minimal CRT theme - make them look like real terminal buttons
	for button in [close_button, fullscreen_button, minimize_button]:
		button.add_theme_color_override("font_color", TERMINAL_TEXT)
		button.add_theme_font_size_override("font_size", 12)  # Smaller font
		
		# Create button style - nearly invisible, just text
		var btn_sb := StyleBoxFlat.new()
		btn_sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent
		btn_sb.border_width_left = 0
		btn_sb.border_width_top = 0
		btn_sb.border_width_right = 0
		btn_sb.border_width_bottom = 0
		button.add_theme_stylebox_override("normal", btn_sb)
		button.add_theme_stylebox_override("hover", btn_sb)
		button.add_theme_stylebox_override("pressed", btn_sb)
		button.add_theme_stylebox_override("focus", btn_sb)
	
	# Style input field with CRT theme
	terminal_input.add_theme_color_override("font_color", TERMINAL_TEXT)
	terminal_input.add_theme_color_override("caret_color", TERMINAL_TEXT)
	terminal_input.add_theme_font_override("font", TERMINAL_FONT)
	terminal_input.add_theme_font_size_override("font_size", TERMINAL_FONT_SIZE)
	var input_sb := StyleBoxFlat.new()
	input_sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent
	input_sb.border_width_left = 0
	input_sb.border_width_top = 0
	input_sb.border_width_right = 0
	input_sb.border_width_bottom = 0
	terminal_input.add_theme_stylebox_override("normal", input_sb)
	terminal_input.add_theme_stylebox_override("focus", input_sb)

func set_button_callbacks(
	on_close: Callable = Callable(),
	on_fullscreen: Callable = Callable(),
	on_minimize: Callable = Callable()
) -> void:
	if close_button and on_close:
		close_button.pressed.connect(on_close)
	if fullscreen_button and on_fullscreen:
		fullscreen_button.pressed.connect(on_fullscreen)
	if minimize_button and on_minimize:
		minimize_button.pressed.connect(on_minimize)

func get_header() -> Control:
	return terminal_header

func get_output() -> RichTextLabel:
	return terminal_output

func get_input() -> LineEdit:
	return terminal_input

func get_run_button() -> Button:
	return run_command_button
