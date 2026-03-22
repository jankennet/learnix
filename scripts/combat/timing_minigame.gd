# timing_minigame.gd
# Undertale-style timing minigame for combat and puzzles
# Three zones: Critical (center), Normal (sides of critical), Miss (edges)
# Player must press action button when indicator is in desired zone
extends Control
class_name TimingMinigame

#region Signals
signal timing_completed(result: TimingResult)
signal timing_cancelled()
#endregion

#region Enums
enum ZoneType { MISS, NORMAL, CRITICAL }
enum TimingContext { COMBAT, PUZZLE }
#endregion

#region Result Class
class TimingResult:
	var zone: ZoneType = ZoneType.MISS
	var position_percent: float = 0.0  # Where on the bar (0.0 - 1.0)
	var context: TimingContext = TimingContext.COMBAT
	var damage_multiplier: float = 0.0  # For combat
	var success_chance: float = 0.0     # For puzzles
	
	func is_critical() -> bool:
		return zone == ZoneType.CRITICAL
	
	func is_hit() -> bool:
		return zone != ZoneType.MISS
	
	func is_miss() -> bool:
		return zone == ZoneType.MISS
#endregion

#region Configuration
@export_group("Bar Settings")
@export var bar_width: float = 400.0
@export var bar_height: float = 40.0
@export var bar_color: Color = Color(0.2, 0.2, 0.3, 0.9)
@export var bar_border_color: Color = Color(0.4, 0.9, 0.4, 1.0)

@export_group("Zone Settings")
## Critical zone size as percentage of total bar
@export_range(0.05, 0.3) var critical_zone_percent: float = 0.15
## Normal zone size as percentage on each side of critical
@export_range(0.1, 0.4) var normal_zone_percent: float = 0.25
@export var critical_color: Color = Color(1.0, 0.85, 0.0, 1.0)  # Gold - fully opaque
@export var normal_color: Color = Color(0.3, 0.8, 0.3, 1.0)     # Green - fully opaque
@export var miss_color: Color = Color(0.6, 0.2, 0.2, 1.0)        # Dark red - fully opaque

## Random zone center position (0.0-1.0 range within safe bounds)
var zone_center_position: float = 0.5  # Will be randomized on start

@export_group("Indicator Settings")
@export var indicator_width: float = 8.0
@export var indicator_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var indicator_speed: float = 400.0  # Pixels per second (fast but readable)
@export var oscillate: bool = true  # Move back and forth vs one direction

@export_group("Timing")
@export var max_time: float = 4.0  # Seconds before auto-miss (default, will be overridden)
@export var combat_max_time: float = 3.0  # Combat timing window
@export var puzzle_max_time: float = 4.0  # Puzzle timing window (more forgiving)
@export var input_action: String = "ui_accept"  # Or custom action

# Context-specific zone sizes
var combat_critical_percent: float = 0.12  # Decent size for combat
var combat_normal_percent: float = 0.22
var puzzle_critical_percent: float = 0.18  # More forgiving for puzzles  
var puzzle_normal_percent: float = 0.28
#endregion

#region Runtime State
var is_active: bool = false
var indicator_position: float = 0.0  # 0.0 to 1.0
var indicator_direction: int = 1     # 1 = right, -1 = left
var current_context: TimingContext = TimingContext.COMBAT
var time_remaining: float = 0.0
var difficulty_modifier: float = 1.0  # Affects speed and zone sizes
var input_delay: float = 0.0  # Delay before accepting input (prevents Enter key from command)
var _current_ui_scale: float = 1.0
var _current_bar_width: float = 0.0
var _current_bar_height: float = 0.0
var _current_indicator_width: float = 0.0
var _last_viewport_size: Vector2 = Vector2.ZERO

# Stored zone boundaries (normalized 0.0-1.0) - set when UI is built
var _zone_crit_start: float = 0.0
var _zone_crit_end: float = 0.0
var _zone_norm_left_start: float = 0.0
var _zone_norm_right_end: float = 0.0

# Stored bar position for debug
var _bar_container_x: float = 0.0
#endregion

#region Node References
var bar_rect: ColorRect
var critical_zone_rect: ColorRect
var normal_zone_left: ColorRect
var normal_zone_right: ColorRect
var indicator_rect: ColorRect
var instruction_label: Label
var timer_label: Label
#endregion

func _ready() -> void:
	# Start hidden
	hide()
	set_process(false)

	var viewport := get_viewport()
	if viewport and not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)
	
	# Ensure we're on top of other UI elements
	z_index = 100
	
	# Don't build UI here - it will be built in start_timing() with correct zone positions

func _build_ui() -> void:
	# Clear existing children IMMEDIATELY (not queue_free which delays)
	for child in get_children():
		child.free()

	# Get the viewport size for proper scaling
	var viewport_size := get_viewport_rect().size
	_last_viewport_size = viewport_size

	# Calculate scale factor based on reference resolution (e.g., 1280x720)
	var ref_width: float = 1280.0
	var ref_height: float = 720.0
	var scale_x: float = viewport_size.x / ref_width
	var scale_y: float = viewport_size.y / ref_height
	var ui_scale: float = min(scale_x, scale_y)
	_current_ui_scale = ui_scale

	# Dynamically scale bar and panel sizes
	var scaled_bar_width: float = clamp(bar_width * ui_scale, 320.0, viewport_size.x * 0.9)
	var scaled_bar_height: float = clamp(bar_height * ui_scale, 28.0, viewport_size.y * 0.08)
	_current_bar_width = scaled_bar_width
	_current_bar_height = scaled_bar_height
	var panel_width: float = scaled_bar_width + 100.0 * ui_scale
	var panel_height: float = scaled_bar_height + 180.0 * ui_scale
	var panel_x: float = (viewport_size.x - panel_width) / 2.0
	var panel_y: float = (viewport_size.y - panel_height) / 2.0

	# Set ourselves to full viewport size
	set_anchors_preset(Control.PRESET_FULL_RECT)
	position = Vector2.ZERO

	# Dark overlay background - covers entire screen
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.75)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# Panel background (centered)
	var panel_bg := ColorRect.new()
	panel_bg.name = "PanelBg"
	panel_bg.color = Color(0.08, 0.1, 0.12, 0.98)
	panel_bg.position = Vector2(panel_x, panel_y)
	panel_bg.size = Vector2(panel_width, panel_height)
	add_child(panel_bg)

	# Panel border
	var panel_border := ReferenceRect.new()
	panel_border.name = "PanelBorder"
	panel_border.position = Vector2(panel_x, panel_y)
	panel_border.size = Vector2(panel_width, panel_height)
	panel_border.border_color = bar_border_color
	panel_border.border_width = 3.0 * ui_scale
	panel_border.editor_only = false
	add_child(panel_border)

	# Content offset from panel top-left
	var content_y: float = panel_y + 25.0 * ui_scale

	# Instruction label
	instruction_label = Label.new()
	instruction_label.name = "InstructionLabel"
	instruction_label.text = "Press SPACE at the right moment!"
	instruction_label.position = Vector2(panel_x + 10.0 * ui_scale, content_y)
	instruction_label.size = Vector2(panel_width - 20.0 * ui_scale, 30.0 * ui_scale)
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	instruction_label.add_theme_font_size_override("font_size", int(18 * ui_scale))
	add_child(instruction_label)

	content_y += 45.0 * ui_scale

	# Bar position (centered in panel)
	var bar_x: float = panel_x + (panel_width - scaled_bar_width) / 2.0
	var bar_y: float = content_y
	_bar_container_x = bar_x  # Store for debug

	# Create a container for the bar and zones (so zones use relative positioning)
	var bar_container := Control.new()
	bar_container.name = "BarContainer"
	bar_container.position = Vector2(bar_x, bar_y)
	bar_container.size = Vector2(scaled_bar_width, scaled_bar_height)
	add_child(bar_container)

	# Background bar (miss zone color) - fills entire container
	bar_rect = ColorRect.new()
	bar_rect.name = "BarBackground"
	bar_rect.color = miss_color
	bar_rect.position = Vector2.ZERO
	bar_rect.size = Vector2(scaled_bar_width, scaled_bar_height)
	bar_container.add_child(bar_rect)

	# Calculate zone sizes (apply difficulty modifier for visual match with hit detection)
	var adjusted_crit: float = critical_zone_percent / difficulty_modifier
	var adjusted_norm: float = normal_zone_percent / difficulty_modifier
	adjusted_crit = clampf(adjusted_crit, 0.03, 0.3)
	adjusted_norm = clampf(adjusted_norm, 0.05, 0.35)

	var crit_width: float = scaled_bar_width * adjusted_crit
	var norm_width: float = scaled_bar_width * adjusted_norm

	# Use randomized zone center position (set in start_timing)
	var zone_center_x: float = scaled_bar_width * zone_center_position
	var crit_start: float = zone_center_x - (crit_width / 2.0)
	var crit_end: float = zone_center_x + (crit_width / 2.0)

	# Clamp zones to stay within bar bounds and update zone_center_position
	if crit_start - norm_width < 0:
		crit_start = norm_width
		crit_end = crit_start + crit_width
		zone_center_x = crit_start + (crit_width / 2.0)
		zone_center_position = zone_center_x / scaled_bar_width  # Update normalized position
	if crit_end + norm_width > scaled_bar_width:
		crit_end = scaled_bar_width - norm_width
		crit_start = crit_end - crit_width
		zone_center_x = crit_start + (crit_width / 2.0)
		zone_center_position = zone_center_x / scaled_bar_width  # Update normalized position

	# STORE zone boundaries as normalized values (0.0-1.0) for hit detection
	# These must match exactly what's visually drawn
	var norm_left_visual_start: float = crit_start - norm_width
	var norm_right_visual_end: float = crit_end + norm_width

	# Convert to normalized, clamping visual positions to bar bounds (0 to bar_width)
	# This matches what's actually visible
	var norm_left_clamped: float = maxf(0.0, norm_left_visual_start)
	var norm_right_clamped: float = minf(scaled_bar_width, norm_right_visual_end)

	_zone_norm_left_start = norm_left_clamped / scaled_bar_width
	_zone_crit_start = crit_start / scaled_bar_width
	_zone_crit_end = crit_end / scaled_bar_width
	_zone_norm_right_end = norm_right_clamped / scaled_bar_width

	# Normal zone left (to the left of critical) - relative to bar
	normal_zone_left = ColorRect.new()
	normal_zone_left.name = "NormalLeft"
	normal_zone_left.color = normal_color
	normal_zone_left.position = Vector2(crit_start - norm_width, 0)
	normal_zone_left.size = Vector2(norm_width, scaled_bar_height)
	bar_container.add_child(normal_zone_left)

	# Normal zone right (to the right of critical) - relative to bar
	normal_zone_right = ColorRect.new()
	normal_zone_right.name = "NormalRight"
	normal_zone_right.color = normal_color
	normal_zone_right.position = Vector2(crit_end, 0)
	normal_zone_right.size = Vector2(norm_width, scaled_bar_height)
	bar_container.add_child(normal_zone_right)

	# Critical zone (center of bar) - relative to bar
	critical_zone_rect = ColorRect.new()
	critical_zone_rect.name = "CriticalZone"
	critical_zone_rect.color = critical_color
	critical_zone_rect.position = Vector2(crit_start, 0)
	critical_zone_rect.size = Vector2(crit_width, scaled_bar_height)
	bar_container.add_child(critical_zone_rect)

	# Indicator (moving line) - relative to bar, starts at left edge
	var scaled_indicator_width: float = max(indicator_width * ui_scale, 4.0)
	_current_indicator_width = scaled_indicator_width
	indicator_rect = ColorRect.new()
	indicator_rect.name = "Indicator"
	indicator_rect.color = indicator_color
	indicator_rect.size = Vector2(scaled_indicator_width, scaled_bar_height + 16.0 * ui_scale)
	indicator_rect.position = Vector2(-scaled_indicator_width / 2.0, -8.0 * ui_scale)
	bar_container.add_child(indicator_rect)

	# Store bar container for indicator updates (no need for bar_x offset anymore)
	set_meta("bar_x", 0.0)  # Indicator is now relative to bar_container
	set_meta("bar_container", bar_container)

	content_y += scaled_bar_height + 20.0 * ui_scale

	# Timer label
	timer_label = Label.new()
	timer_label.name = "TimerLabel"
	timer_label.text = "4.0"
	timer_label.position = Vector2(panel_x + 10.0 * ui_scale, content_y)
	timer_label.size = Vector2(panel_width - 20.0 * ui_scale, 25.0 * ui_scale)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	timer_label.add_theme_font_size_override("font_size", int(16 * ui_scale))
	add_child(timer_label)

	# No zone labels (zones are random)

func _process(delta: float) -> void:
	if not is_active:
		return

	var runtime_bar_width: float = _current_bar_width if _current_bar_width > 0.0 else bar_width
	var runtime_indicator_width: float = _current_indicator_width if _current_indicator_width > 0.0 else indicator_width
	
	# Handle input delay (prevents Enter from command triggering immediately)
	if input_delay > 0:
		input_delay -= delta
		return
	
	# Update indicator position - move across bar over time
	var speed: float = (indicator_speed / runtime_bar_width) * difficulty_modifier
	indicator_position += delta * speed * indicator_direction
	
	# Handle oscillation or wrap-around
	if oscillate:
		if indicator_position >= 1.0:
			indicator_position = 1.0
			indicator_direction = -1
		elif indicator_position <= 0.0:
			indicator_position = 0.0
			indicator_direction = 1
	else:
		if indicator_position >= 1.0:
			indicator_position = 0.0
		elif indicator_position <= 0.0:
			indicator_position = 1.0
	
	# Update indicator visual position (relative to bar_container, so 0 to bar_width)
	if indicator_rect and is_instance_valid(indicator_rect):
		var new_x: float = (indicator_position * runtime_bar_width) - (runtime_indicator_width / 2.0)
		indicator_rect.position.x = new_x
		# Debug: show visual position vs logical position
		# print("[Indicator] logical=%.4f, visual_x=%.1f, green_starts=%.1f" % [indicator_position, new_x, _zone_norm_left_start * bar_width])
	
	# Update timer display
	time_remaining -= delta
	if timer_label:
		timer_label.text = "%.1f" % maxf(0, time_remaining)
	
	# Check for timeout
	if time_remaining <= 0:
		_complete_timing(true)  # Force miss on timeout
		return
	
	# Check for SPACE input only (not Enter, not ui_accept)
	if Input.is_action_just_pressed("ui_accept"):
		# Only accept if it's actually spacebar
		pass

func _input(event: InputEvent) -> void:
	if not is_active:
		return
	
	# Don't accept input during delay period
	if input_delay > 0:
		return
	
	# Only accept SPACE key (not Enter - that would trigger from command submission)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_complete_timing(false)
			get_viewport().set_input_as_handled()

#region Public API

## Start the timing minigame
## context: COMBAT or PUZZLE
## difficulty: 0.5 (easy) to 2.0 (hard) - affects speed
## custom_instruction: Optional custom text to show
func start_timing(context: TimingContext = TimingContext.COMBAT, difficulty: float = 1.0, custom_instruction: String = "") -> void:
	current_context = context
	# Clamp difficulty - higher makes it faster and zones smaller
	difficulty_modifier = clampf(difficulty, 0.5, 2.0)
	
	# Set context-specific settings
	if context == TimingContext.PUZZLE:
		max_time = puzzle_max_time
		critical_zone_percent = puzzle_critical_percent
		normal_zone_percent = puzzle_normal_percent
	else:
		max_time = combat_max_time
		critical_zone_percent = combat_critical_percent
		normal_zone_percent = combat_normal_percent
	
	# Randomize zone center position (keep within safe bounds so zones fit)
	# For puzzle: center can move 20-80% of bar
	# For combat: center can move 25-75% of bar
	var min_center: float = 0.25 if context == TimingContext.COMBAT else 0.20
	var max_center: float = 0.75 if context == TimingContext.COMBAT else 0.80
	zone_center_position = randf_range(min_center, max_center)
	
	# Reset state
	indicator_position = 0.0
	indicator_direction = 1
	time_remaining = max_time
	input_delay = 0.3  # Wait 0.3 seconds before accepting input (prevents Enter from triggering)
	is_active = true
	
	# Rebuild UI to ensure fresh state
	_build_ui()
	
	# Update instruction text
	if instruction_label:
		if custom_instruction.is_empty():
			match context:
				TimingContext.COMBAT:
					instruction_label.text = "⚔️ Press SPACE to execute attack!"
				TimingContext.PUZZLE:
					instruction_label.text = "🔧 Press SPACE to run command!"
		else:
			instruction_label.text = custom_instruction
	
	# Show and start processing
	show()
	set_process(true)
	
	# Ensure we're on top and visible
	z_index = 100
	move_to_front()
	
	# Set anchors to cover full parent
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# Set focus mode and grab focus for input
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	
	print("[TimingMinigame] Started - is_active: %s, indicator_rect: %s" % [is_active, indicator_rect != null])

## Cancel the timing minigame without completing
func cancel_timing() -> void:
	is_active = false
	set_process(false)
	hide()
	timing_cancelled.emit()

## Set the zone sizes (useful for different difficulty levels)
func set_zone_sizes(critical_percent: float, normal_percent: float) -> void:
	critical_zone_percent = clampf(critical_percent, 0.03, 0.4)
	normal_zone_percent = clampf(normal_percent, 0.05, 0.4)
	if is_active:
		_update_zone_sizes()
#endregion

#region Internal Methods

func _update_zone_sizes() -> void:
	if not is_active:
		return

	# Rebuild to keep visuals and hit detection in sync at current resolution.
	_build_ui()
	if indicator_rect and is_instance_valid(indicator_rect):
		indicator_rect.position.x = (indicator_position * _current_bar_width) - (_current_indicator_width / 2.0)

func _complete_timing(forced_miss: bool) -> void:
	is_active = false
	set_process(false)
	
	var result := TimingResult.new()
	result.position_percent = indicator_position
	result.context = current_context
	
	# Use the RIGHT EDGE of the indicator for hit detection
	# so that when the indicator visually touches a zone, it counts
	var runtime_bar_width: float = _current_bar_width if _current_bar_width > 0.0 else bar_width
	var runtime_indicator_width: float = _current_indicator_width if _current_indicator_width > 0.0 else indicator_width
	var detection_pos: float = indicator_position + (runtime_indicator_width / 2.0 / runtime_bar_width)
	
	if forced_miss:
		result.zone = ZoneType.MISS
	else:
		result.zone = _get_zone_at_position(detection_pos)
	
	print("[TimingMinigame] Result: %s" % ZoneType.keys()[result.zone])
	
	# Calculate multipliers based on zone
	match result.zone:
		ZoneType.CRITICAL:
			result.damage_multiplier = 2.0  # Double damage / guaranteed success
			result.success_chance = 1.0
		ZoneType.NORMAL:
			result.damage_multiplier = 1.0  # Normal damage
			result.success_chance = 0.7    # 70% chance for puzzle
		ZoneType.MISS:
			result.damage_multiplier = 0.0  # No damage
			result.success_chance = 0.0     # Puzzle fails
	
	# Visual feedback before hiding
	_show_result_feedback(result)

func _get_zone_at_position(pos: float) -> ZoneType:
	# Calculate zone boundaries using the same logic as visual zones
	# pos is normalized 0.0-1.0
	
	# Use the EXACT stored zone boundaries from when the UI was built
	# This guarantees visual and detection match perfectly
	
	# Check critical first (gold zone)
	if pos >= _zone_crit_start and pos <= _zone_crit_end:
		return ZoneType.CRITICAL
	
	# Check normal zones (green - left of critical or right of critical)
	if (pos >= _zone_norm_left_start and pos < _zone_crit_start) or (pos > _zone_crit_end and pos <= _zone_norm_right_end):
		return ZoneType.NORMAL
	
	# Everything else is miss (red zones on the edges)
	return ZoneType.MISS

func _show_result_feedback(result: TimingResult) -> void:
	# Flash the indicator color based on result
	var flash_color: Color
	var result_text: String
	
	match result.zone:
		ZoneType.CRITICAL:
			flash_color = Color(1.0, 0.85, 0.0, 1.0)
			result_text = "⭐ CRITICAL!"
		ZoneType.NORMAL:
			flash_color = Color(0.3, 0.8, 0.3, 1.0)
			result_text = "✓ HIT!"
		ZoneType.MISS:
			flash_color = Color(0.8, 0.2, 0.2, 1.0)
			result_text = "✗ MISS!"
	
	if indicator_rect:
		indicator_rect.color = flash_color
	
	if instruction_label:
		instruction_label.text = result_text
	
	# Brief delay before completing
	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(func():
		hide()
		timing_completed.emit(result)
	)

func _on_viewport_size_changed() -> void:
	if not is_active:
		return

	var viewport_size := get_viewport_rect().size
	if viewport_size == _last_viewport_size:
		return

	var current_instruction: String = instruction_label.text if instruction_label else ""
	var current_timer_text: String = timer_label.text if timer_label else ""

	_build_ui()

	if instruction_label and not current_instruction.is_empty():
		instruction_label.text = current_instruction
	if timer_label and not current_timer_text.is_empty():
		timer_label.text = current_timer_text
	if indicator_rect and is_instance_valid(indicator_rect):
		indicator_rect.position.x = (indicator_position * _current_bar_width) - (_current_indicator_width / 2.0)
#endregion

#region Static Helpers

## Create a configured TimingMinigame instance
static func create_minigame(parent: Node = null) -> TimingMinigame:
	var minigame := TimingMinigame.new()
	minigame.name = "TimingMinigame"
	
	if parent:
		parent.add_child(minigame)
	
	return minigame
#endregion
