extends CharacterBody3D

@export var follow_speed: float = 7.5
@export var acceleration: float = 12.0
@export var follow_distance: float = 0.9
@export var follow_distance_behind: float = -1.4
@export var max_distance_before_snap: float = 8.0
@export var afk_threshold_seconds: float = 3.0
@export var hint_interval_seconds: float = 10.0
@export var stuck_hint_delay_seconds: float = 10.0
@export var vertical_follow_speed: float = 16.0
@export var show_floating_hints: bool = true
@export var min_vertical_offset: float = 0.35
@export var facts_file_path: String = "res://data/tux_afk_facts.txt"
@export var speech_chars_per_second: float = 30.0
@export var speech_max_line_chars: int = 36
@export var speech_visible_seconds: float = 2.8
@export var hint_interval_jitter_seconds: float = 4.0
@export var bubble_world_height: float = 0.82
@export var bubble_screen_offset: Vector2 = Vector2(0.0, 36.0)
@export var stuck_hint_probability: float = 0.2
@export var speech_max_lines: int = 2
@export var page_advance_delay_seconds: float = 1.4
@export var bubble_fixed_height: float = 106.0

@export var mentor_lines: Array[String] = []

@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D

var _player: CharacterBody3D
var _hint_timer: float = 0.0
var _next_hint_interval: float = 0.0
var _still_time: float = 0.0
var _last_player_position: Vector3
var _bubble_layer: CanvasLayer
var _bubble_root: PanelContainer
var _bubble_label: Label
var _speech_hide_timer: SceneTreeTimer
var _current_side_offset: Vector3 = Vector3.ZERO
var _vertical_offset: float = 0.0
var _fun_facts: Array[String] = []
var _last_fact_index: int = -1
var _typing_source_text: String = ""
var _typing_elapsed: float = 0.0
var _typing_active: bool = false
var _typing_speed_factor: float = 1.0
var _typing_chars_shown: int = 0
var _message_pages: Array[String] = []
var _active_page_index: int = -1
var _boot_hint_shown: bool = false


func _ready() -> void:
	randomize()
	_try_resolve_player()

	if _player:
		_last_player_position = _player.global_position
		_vertical_offset = maxf(min_vertical_offset, global_position.y - _player.global_position.y)

	collision_layer = 0
	collision_mask = 0
	_load_fun_facts()
	_schedule_next_hint_interval()
	if show_floating_hints:
		_create_speech_bubble()


func _exit_tree() -> void:
	if _bubble_layer and is_instance_valid(_bubble_layer):
		_bubble_layer.queue_free()


func _physics_process(delta: float) -> void:
	if _player == null:
		_try_resolve_player()
	if _player == null:
		return

	_follow_player(delta)
	_sync_vertical_position(delta)
	_update_animation()
	_update_guidance(delta)
	_update_typing(delta)
	_update_bubble_position()


func _sync_vertical_position(delta: float) -> void:
	if _player == null:
		return

	var target_y := _player.global_position.y + _vertical_offset
	global_position.y = lerpf(global_position.y, target_y, clampf(delta * vertical_follow_speed, 0.0, 1.0))


func _follow_player(delta: float) -> void:
	var player_pos := _player.global_position
	var player_velocity := _player.velocity
	player_velocity.y = 0.0
	
	# Calculate desired offset based on player handling
	var desired_offset := Vector3(0, 0, -1.2)  # Default: well behind
	
	if player_velocity.length() > 0.1:
		# Player is moving: offset to right side relative to movement direction
		var forward := player_velocity.normalized()
		var right := Vector3(-forward.z, 0, forward.x)  # Perpendicular to forward
		desired_offset = right * 0.5 + forward * -1.5  # Right side and far behind
	
	# Smoothly interpolate the offset for natural transitions
	_current_side_offset = _current_side_offset.lerp(desired_offset, clampf(delta * 3.0, 0.0, 1.0))
	
	var target_pos := player_pos + _current_side_offset
	
	var to_target := target_pos - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	if distance > max_distance_before_snap:
		global_position = target_pos
		velocity = Vector3.ZERO
		return

	if distance > follow_distance:
		var desired_direction := to_target.normalized()
		var desired_velocity := desired_direction * follow_speed
		velocity = velocity.lerp(desired_velocity, clampf(acceleration * delta, 0.0, 1.0))
	else:
		velocity = velocity.lerp(Vector3.ZERO, clampf(acceleration * delta, 0.0, 1.0))

	velocity.y = 0.0
	move_and_slide()


func _update_animation() -> void:
	if sprite == null:
		return

	var move := velocity
	move.y = 0.0

	if move.length() < 0.05:
		sprite.play("tux_idle")
		return

	if absf(move.z) > absf(move.x):
		if move.z < 0.0:
			sprite.play("tux_idle_back")
		else:
			sprite.play("tux_idle")
	else:
		sprite.play("tux_idle_side")
		sprite.flip_h = move.x < 0.0


func _update_guidance(delta: float) -> void:
	if not show_floating_hints:
		return
	if _is_ui_overlay_blocking_bubble():
		_hide_bubble_temporarily()
		return
	if _typing_active or _is_bubble_busy():
		return

	_hint_timer += delta

	var planar_speed := _player.velocity
	planar_speed.y = 0.0
	var is_player_moving := planar_speed.length() >= 0.05
	if not is_player_moving:
		_still_time += delta
	else:
		_still_time = 0.0

	_last_player_position = _player.global_position

	if _hint_timer < _next_hint_interval:
		return

	if _still_time < afk_threshold_seconds:
		return

	_hint_timer = 0.0
	_schedule_next_hint_interval()
	var line := _choose_guidance_line()
	_show_line(line)


func _choose_guidance_line() -> String:
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.input_locked:
		return "Hold, young admin. Let the system breathe before the next move."

	if _fun_facts.is_empty() and mentor_lines.is_empty():
		return "Linux fact mode is online."

	if not _fun_facts.is_empty():
		# Prefer facts; only occasionally replace with a stuck hint.
		if _still_time >= stuck_hint_delay_seconds and randf() < clampf(stuck_hint_probability, 0.0, 1.0):
			return "Stuck? Try exploring a different path, or talk to someone nearby for clues."
		var idx := _pick_random_fact_index()
		return "Linux fact: %s" % _fun_facts[idx]

	return mentor_lines[randi() % mentor_lines.size()]


func _create_speech_bubble() -> void:
	if _bubble_layer and is_instance_valid(_bubble_layer):
		return

	_bubble_layer = CanvasLayer.new()
	# Keep bubble visible in gameplay; overlay suppression is handled by explicit blockers.
	_bubble_layer.layer = 15
	get_tree().root.add_child(_bubble_layer)

	_bubble_root = PanelContainer.new()
	_bubble_root.visible = false
	_bubble_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.95)
	style.border_color = Color(0.08, 0.08, 0.08, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	_bubble_root.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	_bubble_root.add_child(margin)

	_bubble_label = Label.new()
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_bubble_label.modulate = Color(0.07, 0.07, 0.07, 1.0)
	_bubble_label.add_theme_font_size_override("font_size", 20)
	_bubble_label.custom_minimum_size = Vector2(420.0, 0.0)
	margin.add_child(_bubble_label)

	_bubble_layer.add_child(_bubble_root)
	_bubble_root.custom_minimum_size = Vector2(440.0, bubble_fixed_height)


func _show_line(line: String) -> void:
	if not show_floating_hints:
		return
	if _is_ui_overlay_blocking_bubble():
		return
	if _typing_active or _is_bubble_busy():
		return

	if _bubble_root == null or _bubble_label == null:
		_create_speech_bubble()
	if _bubble_root == null or _bubble_label == null:
		return

	if _speech_hide_timer and _speech_hide_timer.time_left > 0.0:
		_speech_hide_timer = null

	_message_pages = _paginate_text(line, maxi(16, speech_max_line_chars), maxi(1, speech_max_lines))
	if _message_pages.is_empty():
		return
	_active_page_index = 0
	_begin_page_typing(_active_page_index)
	_bubble_root.visible = true
	_update_bubble_position()


func _schedule_boot_hint() -> void:
	if _boot_hint_shown:
		return
	_boot_hint_shown = true
	var t := get_tree().create_timer(1.2)
	t.timeout.connect(_show_boot_hint)


func _show_boot_hint() -> void:
	if not show_floating_hints:
		return
	if _typing_active or _is_bubble_busy():
		return
	_show_line(_choose_guidance_line())


func _hide_speech_label() -> void:
	if _bubble_root:
		_bubble_root.visible = false
	_typing_active = false
	_typing_source_text = ""
	_typing_elapsed = 0.0
	_typing_chars_shown = 0
	_message_pages.clear()
	_active_page_index = -1
	_hint_timer = 0.0
	_schedule_next_hint_interval()


func _update_typing(delta: float) -> void:
	if not _typing_active:
		return
	if _is_ui_overlay_blocking_bubble():
		_hide_bubble_temporarily()
		return
	if _bubble_label == null:
		_typing_active = false
		return

	_typing_elapsed += delta
	var target_chars := int(_typing_elapsed * maxf(1.0, speech_chars_per_second) * _typing_speed_factor)
	var full_len := _typing_source_text.length()
	target_chars = mini(target_chars, full_len)
	if target_chars < _typing_chars_shown:
		target_chars = _typing_chars_shown
	_typing_chars_shown = target_chars
	_bubble_label.text = _typing_source_text.substr(0, target_chars)
	_update_bubble_position()

	if target_chars >= full_len:
		_typing_active = false
		if _active_page_index >= 0 and _active_page_index < _message_pages.size() - 1:
			_speech_hide_timer = get_tree().create_timer(maxf(0.25, page_advance_delay_seconds))
			_speech_hide_timer.timeout.connect(_advance_to_next_page)
		else:
			_speech_hide_timer = get_tree().create_timer(maxf(1.5, speech_visible_seconds))
			_speech_hide_timer.timeout.connect(_hide_speech_label)


func _begin_page_typing(page_index: int) -> void:
	if page_index < 0 or page_index >= _message_pages.size():
		return
	_typing_source_text = _message_pages[page_index]
	_typing_elapsed = 0.0
	_typing_chars_shown = 0
	_typing_speed_factor = 1.0
	_typing_active = true
	if _bubble_label:
		_bubble_label.text = ""


func _advance_to_next_page() -> void:
	if _message_pages.is_empty():
		_hide_speech_label()
		return
	_active_page_index += 1
	if _active_page_index >= _message_pages.size():
		_hide_speech_label()
		return
	_begin_page_typing(_active_page_index)


func _update_bubble_position() -> void:
	if _bubble_root == null:
		return
	if _is_ui_overlay_blocking_bubble():
		_hide_bubble_temporarily()
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var anchor_world := global_position + Vector3(0.0, bubble_world_height, 0.0)
	if camera.is_position_behind(anchor_world):
		if _bubble_root.visible:
			_bubble_root.visible = false
		return

	if _typing_active or _is_bubble_busy():
		_bubble_root.visible = true

	var screen_pos := camera.unproject_position(anchor_world) + bubble_screen_offset
	var bubble_size := _bubble_root.get_combined_minimum_size()
	bubble_size.y = maxf(bubble_size.y, bubble_fixed_height)
	var viewport_size := get_viewport().get_visible_rect().size
	var x := clampf(screen_pos.x - bubble_size.x * 0.5, 12.0, viewport_size.x - bubble_size.x - 12.0)
	var y := clampf(screen_pos.y - bubble_size.y - 6.0, 12.0, viewport_size.y - bubble_size.y - 12.0)
	_bubble_root.position = Vector2(x, y)


func _hide_bubble_temporarily() -> void:
	if _bubble_root:
		_bubble_root.visible = false


func _is_ui_overlay_blocking_bubble() -> bool:
	var sm := get_node_or_null("/root/SceneManager")
	if sm and bool(sm.get("input_locked")):
		return true
	if get_tree().paused:
		return true

	var root := get_tree().root
	if root == null:
		return false

	for node_name in ["TerminalPanel", "TerminalShop", "QuestList", "QuestWindow", "FileExplorerWindow"]:
		var node := root.find_child(node_name, true, false)
		if node is CanvasItem and (node as CanvasItem).visible:
			return true

	return false


func _schedule_next_hint_interval() -> void:
	var jitter := randf_range(-hint_interval_jitter_seconds, hint_interval_jitter_seconds)
	_next_hint_interval = maxf(2.5, hint_interval_seconds + jitter)


func _pick_random_fact_index() -> int:
	if _fun_facts.size() <= 1:
		_last_fact_index = 0
		return _last_fact_index

	var idx := randi() % _fun_facts.size()
	while idx == _last_fact_index:
		idx = randi() % _fun_facts.size()
	_last_fact_index = idx
	return idx


func _is_bubble_busy() -> bool:
	if _speech_hide_timer and _speech_hide_timer.time_left > 0.0:
		return true
	return _bubble_root != null and _bubble_root.visible


func _load_fun_facts() -> void:
	_fun_facts.clear()
	if facts_file_path == "":
		return
	if not FileAccess.file_exists(facts_file_path):
		return

	var file := FileAccess.open(facts_file_path, FileAccess.READ)
	if file == null:
		return

	var raw_text := file.get_as_text().replace("\r", "")
	file.close()

	# Facts are separated by one or more empty lines.
	var lines := raw_text.split("\n", true)
	var current := ""
	for line in lines:
		var trimmed := line.strip_edges()
		if trimmed == "":
			if current.strip_edges() != "":
				_fun_facts.append(current.strip_edges())
				current = ""
			continue
		current = trimmed if current == "" else "%s %s" % [current, trimmed]

	if current.strip_edges() != "":
		_fun_facts.append(current.strip_edges())


func _try_resolve_player() -> void:
	if _player != null:
		return
	_player = get_parent().get_node_or_null("CharacterBody3D") as CharacterBody3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player and _last_player_position == Vector3.ZERO:
		_last_player_position = _player.global_position


func _paginate_text(text: String, max_chars_per_line: int, max_lines_per_page: int) -> Array[String]:
	var normalized := text.strip_edges().replace("\r", "")
	if normalized == "":
		return []

	var words := normalized.split(" ", false)
	if words.is_empty():
		return [normalized]

	var wrapped_lines: Array[String] = []
	var current := ""

	for word in words:
		var candidate := word if current == "" else "%s %s" % [current, word]
		if candidate.length() <= max_chars_per_line:
			current = candidate
			continue

		if current != "":
			wrapped_lines.append(current)
			current = word
		else:
			# Hard split very long tokens.
			var remaining := word
			while remaining.length() > max_chars_per_line:
				wrapped_lines.append(remaining.substr(0, max_chars_per_line))
				remaining = remaining.substr(max_chars_per_line)
			current = remaining

	if current != "":
		wrapped_lines.append(current)

	# Rebalance adjacent lines to avoid awkward single-word or tiny trailing lines.
	for i in range(wrapped_lines.size() - 1):
		var left := wrapped_lines[i]
		var right := wrapped_lines[i + 1]
		if right == "":
			continue
		var right_words := right.split(" ", false)
		if right_words.size() <= 1 and left.split(" ", false).size() > 2:
			var left_words := left.split(" ", false)
			var moved := left_words[left_words.size() - 1]
			left_words.remove_at(left_words.size() - 1)
			var new_left := " ".join(left_words)
			var new_right := (moved + " " + right).strip_edges()
			if new_left.length() > 0 and new_left.length() <= max_chars_per_line and new_right.length() <= max_chars_per_line:
				wrapped_lines[i] = new_left
				wrapped_lines[i + 1] = new_right

	var pages: Array[String] = []
	var clamped_lines: int = maxi(1, max_lines_per_page)

	# Avoid a dangling single-line last page when we can merge safely.
	if clamped_lines == 2 and wrapped_lines.size() >= 3 and wrapped_lines.size() % 2 == 1:
		var prev_idx := wrapped_lines.size() - 2
		var last_idx := wrapped_lines.size() - 1
		var merged := "%s %s" % [wrapped_lines[prev_idx], wrapped_lines[last_idx]]
		if merged.length() <= max_chars_per_line:
			wrapped_lines[prev_idx] = merged
			wrapped_lines.remove_at(last_idx)

	for i in range(0, wrapped_lines.size(), clamped_lines):
		var page_lines: Array[String] = []
		for j in range(clamped_lines):
			var idx := i + j
			if idx >= wrapped_lines.size():
				break
			page_lines.append(wrapped_lines[idx])
		pages.append("\n".join(page_lines))

	return pages
