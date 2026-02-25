extends Control
class_name DependencyResolverMinigame

signal resolver_completed(success: bool)
signal resolver_closed()

const STATUS_BROKEN := 0
const STATUS_CONFLICT := 1
const STATUS_STABLE := 2
const STATUS_CORE := 3

const LINK_BROKEN := 0
const LINK_CONFLICT := 1
const LINK_STABLE := 2

const NODE_SIZE := Vector2(106, 56)
const PANIC_CONFLICT_THRESHOLD := 4
const CURSOR_STEP := 56.0

var _workspace: Control
var _repo_panel: VBoxContainer
var _status_label: Label
var _hint_label: Label
var _log_label: RichTextLabel
var _selected_lib_label: Label
var _terminal_overlay: PanelContainer
var _terminal_output: RichTextLabel
var _terminal_exit_button: Button
var _panic_overlay: ColorRect
var _build_btn_left: Button
var _build_btn_up: Button
var _build_btn_down: Button
var _build_btn_right: Button

var _templates: Dictionary = {}
var _nodes: Dictionary = {}
var _node_controls: Dictionary = {}
var _connections: Array[Dictionary] = []

var _next_node_id := 1
var _selected_template_id := ""
var _template_order: PackedStringArray = PackedStringArray()
var _template_cursor_index := 0
var _link_mode := false
var _link_start_node_id := -1
var _dragging_node_id := -1
var _drag_offset := Vector2.ZERO
var _build_cursor := Vector2.ZERO
var _is_active := false
var _is_resolved := false
var _panic_mode := false
var _open_input_grace := 0.0
var _layout_ready := false
var _draw_overlay: Control
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _mouse_mode_saved := false

var _kernel_node_id := -1
var _application_node_id := -1

var _system_log_lines: PackedStringArray = [
	"systemd[1]: Reached target Basic System.",
	"apt[928]: Reading package lists...",
	"pacman[411]: synchronizing package databases",
	"kernel: udevd started for virtual bus",
	"dnf[531]: Last metadata expiration check: 0:00:08 ago",
	"systemd[1]: Started Journal Service.",
	"resolverd[222]: scanning dependency graph",
	"loader: probing hooks for libthread.so"
]

func _ready() -> void:
	hide()
	set_process(true)
	set_process_input(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 120
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_templates()
	_build_ui()
	call_deferred("_finalize_initial_layout")

func _finalize_initial_layout() -> void:
	await get_tree().process_frame
	_layout_ready = true
	_reset_puzzle()

func open_minigame() -> void:
	if not _layout_ready:
		await get_tree().process_frame
		_layout_ready = true

	# Ensure full-screen overlay sizing before spawning nodes.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0

	_reset_puzzle()
	_open_input_grace = 0.35
	show()
	move_to_front()
	_is_active = true
	if not _mouse_mode_saved:
		_saved_mouse_mode = Input.mouse_mode
		_mouse_mode_saved = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func close_minigame() -> void:
	hide()
	_is_active = false
	_open_input_grace = 0.0
	if _mouse_mode_saved:
		Input.mouse_mode = _saved_mouse_mode as Input.MouseMode
		_mouse_mode_saved = false
	resolver_closed.emit()

func _build_templates() -> void:
	_templates.clear()
	_templates["libcore_legacy"] = {
		"label": "Core Block",
		"version": 1.8,
		"arch": "x64",
		"requires_kernel": true,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray()
	}
	_templates["thread_glue"] = {
		"label": "Thread Link",
		"version": 1.6,
		"arch": "x64",
		"requires_kernel": true,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray()
	}
	_templates["runtime_shell"] = {
		"label": "Runtime Box",
		"version": 1.9,
		"arch": "x64",
		"requires_kernel": false,
		"exact_inputs": 2,
		"max_input_version": 99.0,
		"requires": PackedStringArray(["libcore_legacy", "thread_glue"])
	}
	_templates["net_daemon"] = {
		"label": "Net Block",
		"version": 2.0,
		"arch": "x64",
		"requires_kernel": false,
		"exact_inputs": 1,
		"max_input_version": 1.9,
		"requires": PackedStringArray(["libcore_legacy"])
	}
	_templates["arm_shim"] = {
		"label": "ARM Block",
		"version": 1.7,
		"arch": "arm",
		"requires_kernel": true,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray()
	}
	_templates["ssl_old"] = {
		"label": "Secure Pack",
		"version": 2.3,
		"arch": "x64",
		"requires_kernel": false,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray(["thread_glue"])
	}

func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	# Background fill (first child, renders behind everything else).
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.05, 0.08, 0.985)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = false
	_log_label.scroll_active = false
	_log_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_log_label.offset_left = 30
	_log_label.offset_top = 18
	_log_label.offset_right = -30
	_log_label.offset_bottom = 132
	_log_label.modulate = Color(0.45, 0.95, 0.9, 0.2)
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log_label)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 18
	frame.offset_top = 18
	frame.offset_right = -18
	frame.offset_bottom = -18
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.01, 0.09, 0.13, 0.12)
	frame_style.border_width_left = 3
	frame_style.border_width_top = 3
	frame_style.border_width_right = 3
	frame_style.border_width_bottom = 3
	frame_style.border_color = Color(0.1, 0.95, 0.95, 0.95)
	frame_style.corner_radius_top_left = 14
	frame_style.corner_radius_top_right = 14
	frame_style.corner_radius_bottom_left = 14
	frame_style.corner_radius_bottom_right = 14
	frame.add_theme_stylebox_override("panel", frame_style)
	add_child(frame)

	var shell := Control.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.offset_left = 18
	shell.offset_top = 18
	shell.offset_right = -18
	shell.offset_bottom = -18
	add_child(shell)

	_repo_panel = VBoxContainer.new()
	_repo_panel.custom_minimum_size = Vector2(270, 0)
	_repo_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_repo_panel.offset_left = 10
	_repo_panel.offset_top = 30
	_repo_panel.offset_right = 280
	_repo_panel.offset_bottom = -220
	shell.add_child(_repo_panel)

	var repo_bg := PanelContainer.new()
	repo_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	repo_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var repo_style := StyleBoxFlat.new()
	repo_style.bg_color = Color(0.0, 0.09, 0.08, 0.7)
	repo_style.border_width_left = 1
	repo_style.border_width_top = 1
	repo_style.border_width_right = 1
	repo_style.border_width_bottom = 1
	repo_style.border_color = Color(0.2, 0.95, 0.72, 0.65)
	repo_bg.add_theme_stylebox_override("panel", repo_style)
	_repo_panel.add_child(repo_bg)
	_repo_panel.move_child(repo_bg, 0)

	var repo_title := Label.new()
	repo_title.text = "REPOSITORY"
	repo_title.add_theme_color_override("font_color", Color(0.35, 1.0, 0.86))
	_repo_panel.add_child(repo_title)

	var repo_hint := Label.new()
	repo_hint.text = "Select library, then click graph to place"
	repo_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	repo_hint.add_theme_color_override("font_color", Color(0.76, 0.95, 0.92, 0.9))
	_repo_panel.add_child(repo_hint)

	_template_order = PackedStringArray()
	for template_id in _templates.keys():
		_template_order.append(template_id)
		var template: Dictionary = _templates[template_id]
		var btn := Button.new()
		btn.text = "%s" % [template["label"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_repository_item_pressed.bind(template_id))
		_repo_panel.add_child(btn)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 300
	root.offset_top = 22
	root.offset_right = -8
	root.offset_bottom = -22
	shell.add_child(root)

	_status_label = Label.new()
	_status_label.text = "Good Nodes: 0 | Clashes: 0 | Links: 0"
	_status_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status_label.offset_left = 0
	_status_label.offset_top = 0
	_status_label.offset_right = 0
	_status_label.offset_bottom = 24
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(0.68, 1.0, 0.82))
	root.add_child(_status_label)

	_hint_label = Label.new()
	_hint_label.text = "Goal: connect Kernel to App with all green links."
	_hint_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hint_label.offset_left = 0
	_hint_label.offset_top = 22
	_hint_label.offset_right = 0
	_hint_label.offset_bottom = 44
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Color(0.8, 0.95, 0.98))
	root.add_child(_hint_label)

	_selected_lib_label = Label.new()
	_selected_lib_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_selected_lib_label.offset_left = 0
	_selected_lib_label.offset_top = 44
	_selected_lib_label.offset_right = 0
	_selected_lib_label.offset_bottom = 66
	_selected_lib_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selected_lib_label.add_theme_color_override("font_color", Color(0.42, 0.88, 1.0))
	root.add_child(_selected_lib_label)

	_workspace = Control.new()
	_workspace.set_anchors_preset(Control.PRESET_FULL_RECT)
	_workspace.offset_left = 8
	_workspace.offset_top = 76
	_workspace.offset_right = -8
	_workspace.offset_bottom = -160
	_workspace.mouse_filter = Control.MOUSE_FILTER_PASS
	_workspace.gui_input.connect(_on_workspace_gui_input)
	root.add_child(_workspace)
	_build_cursor = _workspace.size * 0.5

	var build_panel := PanelContainer.new()
	build_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	build_panel.offset_left = -170
	build_panel.offset_top = -120
	build_panel.offset_right = 170
	build_panel.offset_bottom = -24
	var build_style := StyleBoxFlat.new()
	build_style.bg_color = Color(0.05, 0.2, 0.23, 0.85)
	build_style.border_width_left = 2
	build_style.border_width_top = 2
	build_style.border_width_right = 2
	build_style.border_width_bottom = 2
	build_style.border_color = Color(0.4, 1.0, 0.98, 0.86)
	build_panel.add_theme_stylebox_override("panel", build_style)
	root.add_child(build_panel)

	var build_v := VBoxContainer.new()
	build_v.add_theme_constant_override("separation", 8)
	build_panel.add_child(build_v)

	var build_title := Label.new()
	build_title.text = "BUILD PATH"
	build_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_title.add_theme_color_override("font_color", Color(0.72, 1.0, 0.94))
	build_v.add_child(build_title)

	var arrows := HBoxContainer.new()
	arrows.alignment = BoxContainer.ALIGNMENT_CENTER
	arrows.add_theme_constant_override("separation", 8)
	build_v.add_child(arrows)

	var left_btn := Button.new()
	left_btn.text = "◀"
	left_btn.custom_minimum_size = Vector2(46, 34)
	left_btn.pressed.connect(_on_build_arrow_pressed.bind("left"))
	arrows.add_child(left_btn)
	_build_btn_left = left_btn

	var up_btn := Button.new()
	up_btn.text = "▲"
	up_btn.custom_minimum_size = Vector2(46, 34)
	up_btn.pressed.connect(_on_build_arrow_pressed.bind("up"))
	arrows.add_child(up_btn)
	_build_btn_up = up_btn

	var down_btn := Button.new()
	down_btn.text = "▼"
	down_btn.custom_minimum_size = Vector2(46, 34)
	down_btn.pressed.connect(_on_build_arrow_pressed.bind("down"))
	arrows.add_child(down_btn)
	_build_btn_down = down_btn

	var right_btn := Button.new()
	right_btn.text = "▶"
	right_btn.custom_minimum_size = Vector2(46, 34)
	right_btn.pressed.connect(_on_build_arrow_pressed.bind("right"))
	arrows.add_child(right_btn)
	_build_btn_right = right_btn

	var build_help := Label.new()
	build_help.text = "[L] Connect mode  [RMB] Delete  [C] Reset"
	build_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_help.add_theme_color_override("font_color", Color(0.7, 0.94, 0.9))
	build_v.add_child(build_help)

	var exit_panel := PanelContainer.new()
	exit_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	exit_panel.offset_left = -54
	exit_panel.offset_top = -20
	exit_panel.offset_right = 54
	exit_panel.offset_bottom = 6
	var exit_style := StyleBoxFlat.new()
	exit_style.bg_color = Color(0.07, 0.18, 0.2, 0.88)
	exit_style.border_width_left = 1
	exit_style.border_width_top = 1
	exit_style.border_width_right = 1
	exit_style.border_width_bottom = 1
	exit_style.border_color = Color(0.74, 1.0, 0.96, 0.72)
	exit_panel.add_theme_stylebox_override("panel", exit_style)
	root.add_child(exit_panel)

	var exit_lbl := Label.new()
	exit_lbl.text = "[E] EXIT"
	exit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exit_lbl.add_theme_color_override("font_color", Color(0.84, 1.0, 0.98))
	exit_panel.add_child(exit_lbl)

	# Drawing overlay: renders grid, lines, ports ON TOP of workspace/nodes.
	_draw_overlay = Control.new()
	_draw_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_overlay.draw.connect(_on_overlay_redraw)
	add_child(_draw_overlay)

	_terminal_overlay = PanelContainer.new()
	_terminal_overlay.visible = false
	_terminal_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_terminal_overlay.custom_minimum_size = Vector2(720, 360)
	_terminal_overlay.position = Vector2(-360, -180)
	add_child(_terminal_overlay)

	var terminal_vbox := VBoxContainer.new()
	terminal_vbox.custom_minimum_size = Vector2(700, 340)
	_terminal_overlay.add_child(terminal_vbox)

	_terminal_output = RichTextLabel.new()
	_terminal_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_terminal_output.bbcode_enabled = false
	_terminal_output.scroll_following = true
	terminal_vbox.add_child(_terminal_output)

	_terminal_exit_button = Button.new()
	_terminal_exit_button.text = "[E] Continue"
	_terminal_exit_button.disabled = true
	_terminal_exit_button.pressed.connect(_on_terminal_continue_pressed)
	terminal_vbox.add_child(_terminal_exit_button)

	_panic_overlay = ColorRect.new()
	_panic_overlay.visible = false
	_panic_overlay.color = Color(0.5, 0.06, 0.08, 0.36)
	_panic_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panic_overlay)

	var panic_label := Label.new()
	panic_label.text = "SYSTEM ERROR: TOO MANY BAD LINKS"
	panic_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panic_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panic_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	panic_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.72))
	_panic_overlay.add_child(panic_label)

	# Match main terminal CRT curvature by reusing the combat CRT shader.
	var crt_shader := load("res://Scenes/combat/crt_effect.gdshader") as Shader
	if crt_shader:
		var crt_material := ShaderMaterial.new()
		crt_material.shader = crt_shader
		crt_material.set_shader_parameter("scanline_intensity", 0.06)
		crt_material.set_shader_parameter("scanline_frequency", 2.5)
		crt_material.set_shader_parameter("vignette_intensity", 0.12)
		crt_material.set_shader_parameter("curvature", 0.018)
		crt_material.set_shader_parameter("flicker_intensity", 0.008)
		crt_material.set_shader_parameter("glow_intensity", 0.1)
		crt_material.set_shader_parameter("chromatic_aberration", 0.0004)
		crt_material.set_shader_parameter("phosphor_color", Vector3(0.35, 0.95, 0.4))
		crt_material.set_shader_parameter("bezel_color", Vector3(0.65, 0.68, 0.62))
		crt_material.set_shader_parameter("bezel_glow", 0.15)

		var crt_overlay := ColorRect.new()
		crt_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		crt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crt_overlay.material = crt_material
		crt_overlay.color = Color(1.0, 1.0, 1.0, 1.0)
		add_child(crt_overlay)

	if _template_order.size() > 0:
		_template_cursor_index = clampi(_template_cursor_index, 0, _template_order.size() - 1)
		_on_repository_item_pressed(_template_order[_template_cursor_index])

func _process(delta: float) -> void:
	if _log_label:
		if _log_label.get_line_count() > 26:
			_log_label.clear()
		if randf() < delta * 2.4:
			_log_label.append_text("%s\n" % _system_log_lines[randi_range(0, _system_log_lines.size() - 1)])

	if _panic_mode and _panic_overlay:
		var flicker: float = 0.24 + abs(sin(Time.get_ticks_msec() * 0.03)) * 0.4
		_panic_overlay.color.a = flicker

	if _open_input_grace > 0.0:
		_open_input_grace = maxf(0.0, _open_input_grace - delta)

	if _dragging_node_id >= 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var node_ctrl := _node_controls.get(_dragging_node_id) as Control
		if node_ctrl:
			var local_mouse := _workspace.get_local_mouse_position()
			node_ctrl.position = local_mouse - _drag_offset
			if _draw_overlay:
				_draw_overlay.queue_redraw()

	if _workspace:
		if _is_active and _workspace.get_global_rect().has_point(get_viewport().get_mouse_position()):
			_build_cursor = _workspace.get_local_mouse_position()
		_build_cursor.x = clampf(_build_cursor.x, 16.0, _workspace.size.x - 16.0)
		_build_cursor.y = clampf(_build_cursor.y, 16.0, _workspace.size.y - 16.0)

	if _draw_overlay:
		_draw_overlay.queue_redraw()

func _input(event: InputEvent) -> void:
	if not _is_active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if _open_input_grace > 0.0:
			return
		if event.keycode == KEY_ESCAPE:
			close_minigame()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_C:
			_reset_puzzle()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_LEFT:
			_on_build_arrow_pressed("left")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_RIGHT:
			_on_build_arrow_pressed("right")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_UP:
			_on_build_arrow_pressed("up")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_DOWN:
			_on_build_arrow_pressed("down")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_L:
			_toggle_link_mode()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_E:
			if _is_resolved and _terminal_overlay and _terminal_overlay.visible:
				_on_terminal_continue_pressed()
			else:
				close_minigame()
			get_viewport().set_input_as_handled()

func _on_overlay_redraw() -> void:
	if _workspace == null or _draw_overlay == null:
		return

	var o := _draw_overlay
	var overlay_origin := o.global_position
	var ws_pos : Vector2= _workspace.global_position - overlay_origin
	var ws_size := _workspace.size

	# Dispatch-like graph grid
	var grid_step := 26.0
	var grid_color := Color(0.22, 0.95, 0.95, 0.11)
	var x : float = ws_pos.x
	while x <= ws_pos.x + ws_size.x:
		o.draw_line(Vector2(x, ws_pos.y), Vector2(x, ws_pos.y + ws_size.y), grid_color, 1.0)
		x += grid_step
	var y : float = ws_pos.y
	while y <= ws_pos.y + ws_size.y:
		o.draw_line(Vector2(ws_pos.x, y), Vector2(ws_pos.x + ws_size.x, y), grid_color, 1.0)
		y += grid_step

	# Cursor reticle
	var cursor := ws_pos + _build_cursor
	o.draw_circle(cursor, 8.5, Color(0.38, 1.0, 0.95, 0.2))
	o.draw_arc(cursor, 12.0, 0, TAU, 28, Color(0.5, 1.0, 0.95, 0.85), 2.0)
	o.draw_line(cursor + Vector2(-16, 0), cursor + Vector2(-8, 0), Color(0.5, 1.0, 0.95, 0.8), 2)
	o.draw_line(cursor + Vector2(16, 0), cursor + Vector2(8, 0), Color(0.5, 1.0, 0.95, 0.8), 2)
	o.draw_line(cursor + Vector2(0, -16), cursor + Vector2(0, -8), Color(0.5, 1.0, 0.95, 0.8), 2)
	o.draw_line(cursor + Vector2(0, 16), cursor + Vector2(0, 8), Color(0.5, 1.0, 0.95, 0.8), 2)

	# Preview line from link-start to cursor while in connect mode
	if _link_mode and _link_start_node_id >= 0 and _node_controls.has(_link_start_node_id):
		var start_ctrl := _node_controls[_link_start_node_id] as Control
		var preview_start: Vector2 = start_ctrl.global_position + start_ctrl.size * 0.5 - overlay_origin
		o.draw_line(preview_start, cursor, Color(0.5, 1.0, 0.95, 0.45), 2.5, true)

	for link in _connections:
		var from_id: int = int(link.get("from", -1))
		var to_id: int = int(link.get("to", -1))
		if not _node_controls.has(from_id) or not _node_controls.has(to_id):
			continue

		var from_ctrl := _node_controls[from_id] as Control
		var to_ctrl := _node_controls[to_id] as Control
		var start: Vector2 = from_ctrl.global_position + from_ctrl.size * 0.5 - overlay_origin
		var end: Vector2 = to_ctrl.global_position + to_ctrl.size * 0.5 - overlay_origin

		var link_state: int = int(link.get("state", LINK_BROKEN))
		var color := Color(0.9, 0.18, 0.22)
		match link_state:
			LINK_CONFLICT:
				color = Color(0.96, 0.82, 0.24)
			LINK_STABLE:
				color = Color(0.5, 1.0, 0.88)

		# High-contrast pipes so they stay visible on all backgrounds.
		o.draw_line(start, end, Color(color.r, color.g, color.b, 0.58), 10.0, true)
		o.draw_line(start, end, Color(0.97, 1.0, 1.0, 0.95), 4.2, true)
		o.draw_line(start, end, color, 2.4, true)
		var dir: Vector2 = (end - start).normalized()
		var tip: Vector2 = end - dir * 14.0
		var side := Vector2(-dir.y, dir.x) * 9.0
		o.draw_colored_polygon(PackedVector2Array([end, tip + side, tip - side]), color)

	# Draw connection ports on each node so link origins are obvious
	for node_id in _node_controls.keys():
		var ctrl := _node_controls[node_id] as Control
		if not ctrl:
			continue
		var center: Vector2 = ctrl.global_position + ctrl.size * 0.5 - overlay_origin
		o.draw_circle(center, 8.0, Color(0.1, 0.96, 0.95, 0.56))
		o.draw_arc(center, 9.5, 0.0, TAU, 20, Color(0.95, 1.0, 1.0, 0.98), 1.8)

	# CRT TV pass: scanlines, flicker, rolling refresh band, and vignette.
	var screen_size := o.size
	var crt_t := Time.get_ticks_msec() * 0.001

	# Fine scanlines across the whole overlay.
	var scan_step := 2.0
	var sy := 0.0
	while sy < screen_size.y:
		var scan_alpha := 0.05 + 0.018 * (0.5 + 0.5 * sin(crt_t * 22.0 + sy * 0.21))
		o.draw_line(Vector2(0.0, sy), Vector2(screen_size.x, sy), Color(0.0, 0.08, 0.06, scan_alpha), 1.0)
		sy += scan_step

	# Subtle moving refresh band.
	var band_h := 110.0
	var band_y := fposmod(crt_t * 120.0, screen_size.y + band_h) - band_h
	o.draw_rect(Rect2(Vector2(0.0, band_y), Vector2(screen_size.x, band_h)), Color(0.08, 0.24, 0.2, 0.08), true)

	# Global phosphor tint and flicker.
	o.draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0.0, 0.18, 0.13, 0.045), true)
	var flicker_alpha: float = 0.018 + 0.022 * abs(sin(crt_t * 37.0))
	o.draw_rect(Rect2(Vector2.ZERO, screen_size), Color(0.0, 0.0, 0.0, flicker_alpha), true)

	# Edge vignette to mimic curved CRT falloff.
	for i in range(8):
		var inset := float(i) * 11.0
		var rect_size := screen_size - Vector2(inset * 2.0, inset * 2.0)
		if rect_size.x <= 0.0 or rect_size.y <= 0.0:
			break
		var edge_alpha := 0.018 + float(i) * 0.01
		o.draw_rect(Rect2(Vector2(inset, inset), rect_size), Color(0.0, 0.0, 0.0, edge_alpha), false, 2.0)

	# Stronger tube curvature illusion: darkened corners + bowed edge shading.
	var corner_radius := minf(screen_size.x, screen_size.y) * 0.24
	var corners := [
		Vector2(0.0, 0.0),
		Vector2(screen_size.x, 0.0),
		Vector2(0.0, screen_size.y),
		Vector2(screen_size.x, screen_size.y)
	]
	for c in corners:
		for j in range(11):
			var jr := float(j)
			var r := corner_radius + jr * 22.0
			var a := maxf(0.0, 0.08 - jr * 0.0065)
			o.draw_circle(c, r, Color(0.0, 0.0, 0.0, a))

	# Bowed top and bottom glass shading.
	var top_center := Vector2(screen_size.x * 0.5, -screen_size.y * 0.82)
	var bottom_center := Vector2(screen_size.x * 0.5, screen_size.y * 1.82)
	for b in range(9):
		var bf := float(b)
		var radius := screen_size.y * 1.02 + bf * 32.0
		var shade_alpha := maxf(0.0, 0.06 - bf * 0.006)
		o.draw_arc(top_center, radius, 0.18, PI - 0.18, 80, Color(0.0, 0.0, 0.0, shade_alpha), 2.2)
		o.draw_arc(bottom_center, radius, PI + 0.18, TAU - 0.18, 80, Color(0.0, 0.0, 0.0, shade_alpha), 2.2)

	# Subtle curved glass highlight.
	o.draw_arc(top_center, screen_size.y * 1.08, 0.42, PI - 0.42, 72, Color(0.72, 1.0, 0.94, 0.045), 1.6)

func _on_workspace_gui_input(event: InputEvent) -> void:
	if not _is_active:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_build_cursor = _workspace.get_local_mouse_position()
		if _selected_template_id != "":
			_spawn_library(_selected_template_id, _workspace.get_local_mouse_position() - NODE_SIZE * 0.5)
			_hint_label.text = "Library placed. Connect nodes to satisfy dependencies."
			get_viewport().set_input_as_handled()

func _toggle_link_mode() -> void:
	_link_mode = not _link_mode
	_link_start_node_id = -1
	if _link_mode:
		_hint_label.text = "Connect mode ON: click start node, then end node."
	else:
		_hint_label.text = "Connect mode OFF: drag nodes to move them."

func _on_repository_item_pressed(template_id: String) -> void:
	_selected_template_id = template_id
	var t: Dictionary = _templates[template_id]
	if _template_order.size() > 0:
		_template_cursor_index = maxi(0, _template_order.find(template_id))
	if _selected_lib_label:
		_selected_lib_label.text = "Selected: %s" % t["label"]
	_hint_label.text = "Selected %s. Click graph (or ▲) to place." % t["label"]

func _on_build_arrow_pressed(direction: String) -> void:
	_flash_build_button(direction)
	if _template_order.is_empty():
		return

	match direction:
		"left":
			_template_cursor_index = posmod(_template_cursor_index - 1, _template_order.size())
			_on_repository_item_pressed(_template_order[_template_cursor_index])
		"right":
			_template_cursor_index = posmod(_template_cursor_index + 1, _template_order.size())
			_on_repository_item_pressed(_template_order[_template_cursor_index])
		"up":
			if _selected_template_id != "":
				_spawn_library(_selected_template_id, _build_cursor - NODE_SIZE * 0.5)
				_hint_label.text = "Placed %s." % _templates[_selected_template_id]["label"]
		"down":
			_toggle_link_mode()

func _flash_build_button(direction: String) -> void:
	var btn: Button = null
	match direction:
		"left":
			btn = _build_btn_left
		"up":
			btn = _build_btn_up
		"down":
			btn = _build_btn_down
		"right":
			btn = _build_btn_right

	if btn == null:
		return

	btn.modulate = Color(0.62, 1.35, 1.08, 1.0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)

func _spawn_core_nodes() -> void:
	var ws_size := _workspace.size
	_build_cursor = ws_size * 0.5
	_kernel_node_id = _create_node({
		"template_id": "kernel",
		"label": "Kernel Start",
		"version": 1.0,
		"arch": "x64",
		"is_core": true,
		"is_application": false,
		"requires_kernel": false,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray()
	}, Vector2(maxf(90.0, ws_size.x * 0.12), ws_size.y * 0.68))

	_application_node_id = _create_node({
		"template_id": "application",
		"label": "App Goal",
		"version": 2.0,
		"arch": "x64",
		"is_core": false,
		"is_application": true,
		"requires_kernel": false,
		"exact_inputs": 2,
		"max_input_version": 99.0,
		"requires": PackedStringArray(["runtime_shell", "net_daemon"])
	}, Vector2(ws_size.x * 0.72, ws_size.y * 0.18))

func _spawn_library(template_id: String, pos: Vector2) -> void:
	if not _templates.has(template_id):
		return
	var template: Dictionary = _templates[template_id]
	var payload := {
		"template_id": template_id,
		"label": template["label"],
		"version": template["version"],
		"arch": template["arch"],
		"is_core": false,
		"is_application": false,
		"requires_kernel": template["requires_kernel"],
		"exact_inputs": template["exact_inputs"],
		"max_input_version": template["max_input_version"],
		"requires": template["requires"]
	}
	_create_node(payload, pos)
	_recompute_graph_state()

func _create_node(payload: Dictionary, pos: Vector2) -> int:
	var node_id := _next_node_id
	_next_node_id += 1

	payload["id"] = node_id
	payload["status"] = STATUS_BROKEN
	payload["reason"] = "Not ready"
	_nodes[node_id] = payload

	var panel := PanelContainer.new()
	panel.custom_minimum_size = NODE_SIZE
	panel.size = NODE_SIZE
	panel.position = pos
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var node_style := StyleBoxFlat.new()
	node_style.bg_color = Color(0.02, 0.16, 0.2, 0.8)
	node_style.border_width_left = 2
	node_style.border_width_top = 2
	node_style.border_width_right = 2
	node_style.border_width_bottom = 2
	node_style.border_color = Color(0.9, 0.2, 0.24)
	node_style.corner_radius_top_left = 4
	node_style.corner_radius_top_right = 4
	node_style.corner_radius_bottom_left = 4
	node_style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", node_style)
	_workspace.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = str(payload["label"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	vbox.add_child(title)

	var meta := Label.new()
	meta.name = "Meta"
	meta.text = ""
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", 10)
	vbox.add_child(meta)

	var state := Label.new()
	state.name = "State"
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 9)
	vbox.add_child(state)

	panel.gui_input.connect(_on_node_gui_input.bind(node_id))
	_node_controls[node_id] = panel
	_update_node_visual(node_id)
	return node_id

func _on_node_gui_input(event: InputEvent, node_id: int) -> void:
	if not _is_active:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if node_id != _kernel_node_id and node_id != _application_node_id:
			_delete_node(node_id)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _link_mode:
				_handle_link_click(node_id)
				get_viewport().set_input_as_handled()
				return
			_dragging_node_id = node_id
			var ctrl := _node_controls[node_id] as Control
			_drag_offset = _workspace.get_local_mouse_position() - ctrl.position
			get_viewport().set_input_as_handled()
		else:
			_dragging_node_id = -1
			_recompute_graph_state()

func _handle_link_click(node_id: int) -> void:
	if _link_start_node_id < 0:
		_link_start_node_id = node_id
		_hint_label.text = "Connect from: %s" % _nodes[node_id]["label"]
		return

	if _link_start_node_id == node_id:
		_link_start_node_id = -1
		_hint_label.text = "Connect start cleared."
		return

	_add_connection(_link_start_node_id, node_id)
	_link_start_node_id = -1
	_recompute_graph_state()

func _add_connection(from_id: int, to_id: int) -> void:
	if from_id == to_id:
		return
	for link in _connections:
		if int(link["from"]) == from_id and int(link["to"]) == to_id:
			return
	_connections.append({"from": from_id, "to": to_id, "state": LINK_BROKEN, "reason": "pending"})

func _delete_node(node_id: int) -> void:
	if not _nodes.has(node_id):
		return
	var ctrl := _node_controls.get(node_id) as Control
	if ctrl:
		ctrl.queue_free()
	_nodes.erase(node_id)
	_node_controls.erase(node_id)

	var kept: Array[Dictionary] = []
	for link in _connections:
		if int(link["from"]) == node_id or int(link["to"]) == node_id:
			continue
		kept.append(link)
	_connections = kept
	_recompute_graph_state()

func _recompute_graph_state() -> void:
	for node_id in _nodes.keys():
		var node: Dictionary = _nodes[node_id]
		if bool(node.get("is_core", false)):
			node["status"] = STATUS_CORE
			node["reason"] = "Start"
			_nodes[node_id] = node
			continue

		var incoming: Array[int] = []
		for link in _connections:
			if int(link["to"]) == int(node_id):
				incoming.append(int(link["from"]))

		var source_templates: PackedStringArray = PackedStringArray()
		var source_arches: PackedStringArray = PackedStringArray()
		var version_ok := true
		var has_direct_kernel := false

		for source_id in incoming:
			if not _nodes.has(source_id):
				continue
			var src: Dictionary = _nodes[source_id]
			source_templates.append(str(src.get("template_id", "")))
			var src_arch := str(src.get("arch", ""))
			if not source_arches.has(src_arch):
				source_arches.append(src_arch)
			if bool(src.get("is_core", false)):
				has_direct_kernel = true
			if float(src.get("version", 0.0)) > float(node.get("max_input_version", 99.0)):
				version_ok = false

		var required: PackedStringArray = node.get("requires", PackedStringArray())
		var missing_required := false
		for req in required:
			if not source_templates.has(req):
				missing_required = true
				break

		var exact_inputs: int = int(node.get("exact_inputs", 0))
		var exact_ok := exact_inputs <= 0 or incoming.size() == exact_inputs
		var kernel_ok := (not bool(node.get("requires_kernel", false))) or has_direct_kernel
		var arch_conflict := source_arches.size() > 1

		if arch_conflict:
			node["status"] = STATUS_CONFLICT
			node["reason"] = "Mixed types"
		elif not version_ok:
			node["status"] = STATUS_BROKEN
			node["reason"] = "Wrong version"
		elif not kernel_ok:
			node["status"] = STATUS_BROKEN
			node["reason"] = "Needs Kernel"
		elif not exact_ok:
			node["status"] = STATUS_BROKEN
			node["reason"] = "Needs %d inputs" % exact_inputs
		elif missing_required:
			node["status"] = STATUS_BROKEN
			node["reason"] = "Missing part"
		elif incoming.is_empty() and not bool(node.get("is_application", false)):
			node["status"] = STATUS_BROKEN
			node["reason"] = "No input"
		else:
			node["status"] = STATUS_STABLE
			node["reason"] = "Good"

		_nodes[node_id] = node

	for idx in range(_connections.size()):
		var link := _connections[idx]
		var from_id: int = int(link["from"])
		var to_id: int = int(link["to"])
		if not _nodes.has(from_id) or not _nodes.has(to_id):
			continue
		var src: Dictionary = _nodes[from_id]
		var dst: Dictionary = _nodes[to_id]

		if float(src.get("version", 0.0)) > float(dst.get("max_input_version", 99.0)):
			link["state"] = LINK_BROKEN
			link["reason"] = "version"
		elif int(dst.get("status", STATUS_BROKEN)) == STATUS_CONFLICT:
			link["state"] = LINK_CONFLICT
			link["reason"] = "arch"
		elif int(src.get("status", STATUS_BROKEN)) in [STATUS_STABLE, STATUS_CORE] and int(dst.get("status", STATUS_BROKEN)) == STATUS_STABLE:
			link["state"] = LINK_STABLE
			link["reason"] = "ok"
		else:
			link["state"] = LINK_BROKEN
			link["reason"] = "unsatisfied"

		_connections[idx] = link

	for node_id in _nodes.keys():
		_update_node_visual(int(node_id))

	_update_state_labels()
	_check_fail_or_win()
	if _draw_overlay:
		_draw_overlay.queue_redraw()

func _update_node_visual(node_id: int) -> void:
	if not _nodes.has(node_id) or not _node_controls.has(node_id):
		return

	var node: Dictionary = _nodes[node_id]
	var panel := _node_controls[node_id] as PanelContainer
	var title := panel.get_node_or_null("VBoxContainer/Title") as Label
	var meta := panel.get_node_or_null("VBoxContainer/Meta") as Label
	var state := panel.get_node_or_null("VBoxContainer/State") as Label

	var color := Color(0.95, 0.2, 0.28)
	var state_text := "BAD"
	match int(node.get("status", STATUS_BROKEN)):
		STATUS_CORE:
			color = Color(0.35, 0.65, 1.0)
			state_text = "START"
		STATUS_CONFLICT:
			color = Color(0.96, 0.78, 0.24)
			state_text = "CLASH"
		STATUS_STABLE:
			color = Color(0.32, 1.0, 0.55)
			state_text = "GOOD"

	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var override_style := style.duplicate() as StyleBoxFlat
		override_style.border_color = color
		override_style.bg_color = Color(color.r * 0.16, color.g * 0.16, color.b * 0.2, 0.82)
		panel.add_theme_stylebox_override("panel", override_style)
	if title:
		title.text = str(node["label"])
		title.add_theme_color_override("font_color", Color(0.88, 1.0, 0.98))
	if meta:
		meta.text = ""
		meta.add_theme_color_override("font_color", Color(0.78, 0.95, 0.96))
	if state:
		state.text = "%s" % state_text
		state.add_theme_color_override("font_color", color)

func _update_state_labels() -> void:
	var stable_count := 0
	var conflict_count := 0
	for node in _nodes.values():
		match int(node.get("status", STATUS_BROKEN)):
			STATUS_STABLE, STATUS_CORE:
				stable_count += 1
			STATUS_CONFLICT:
				conflict_count += 1

	_status_label.text = "Good Nodes: %d | Clashes: %d | Links: %d" % [stable_count, conflict_count, _connections.size()]

func _check_fail_or_win() -> void:
	if _is_resolved:
		return

	var conflict_count := 0
	for node in _nodes.values():
		if int(node.get("status", STATUS_BROKEN)) == STATUS_CONFLICT:
			conflict_count += 1
	for link in _connections:
		if int(link.get("state", LINK_BROKEN)) == LINK_CONFLICT:
			conflict_count += 1

	if conflict_count >= PANIC_CONFLICT_THRESHOLD:
		_panic_mode = true
		_panic_overlay.visible = true
		_hint_label.text = "Too many clashes. Press C to reset."
		return

	_panic_mode = false
	_panic_overlay.visible = false

	if _application_node_id < 0 or _kernel_node_id < 0:
		return
	if not _nodes.has(_application_node_id):
		return
	if int(_nodes[_application_node_id].get("status", STATUS_BROKEN)) != STATUS_STABLE:
		return
	if not _has_green_path(_kernel_node_id, _application_node_id):
		return

	_is_resolved = true
	_hint_label.text = "All good. Install is ready."
	_show_success_terminal()

func _has_green_path(start_id: int, target_id: int) -> bool:
	var visited: Dictionary = {}
	var stack: Array[int] = [start_id]

	while not stack.is_empty():
		var current := int(stack.pop_back())
		if current == target_id:
			return true
		if visited.has(current):
			continue
		visited[current] = true

		for link in _connections:
			if int(link.get("from", -1)) != current:
				continue
			if int(link.get("state", LINK_BROKEN)) != LINK_STABLE:
				continue
			var next_id := int(link.get("to", -1))
			if not _nodes.has(next_id):
				continue
			var node_status := int(_nodes[next_id].get("status", STATUS_BROKEN))
			if node_status in [STATUS_STABLE, STATUS_CORE]:
				stack.append(next_id)

	return false

func _show_success_terminal() -> void:
	_terminal_overlay.visible = true
	_terminal_output.clear()
	_terminal_exit_button.disabled = true

	var lines: PackedStringArray = [
		"$ sudo apt install learnix-app",
		"Reading package lists... Done",
		"Building dependency tree... Done",
		"Resolving version constraints... Done",
		"Selecting previously unselected package runtime-shell (v1.9)",
		"Selecting previously unselected package net-daemon (v2.0)",
		"Unpacking libraries... Done",
		"Setting up runtime-shell... Done",
		"Setting up net-daemon... Done",
		"Setting up learnix-app... Done",
		"Processing triggers for man-db... Done",
		"Install complete. System stable."
	]

	await _print_terminal_lines(lines, 0.33)
	_terminal_exit_button.disabled = false

func _print_terminal_lines(lines: PackedStringArray, interval: float) -> void:
	for line in lines:
		_terminal_output.append_text("%s\n" % line)
		await get_tree().create_timer(interval).timeout

func _on_terminal_continue_pressed() -> void:
	_terminal_overlay.visible = false
	resolver_completed.emit(true)
	close_minigame()

func _reset_puzzle() -> void:
	for ctrl in _node_controls.values():
		if ctrl and ctrl is Control:
			(ctrl as Control).queue_free()

	_nodes.clear()
	_node_controls.clear()
	_connections.clear()
	_next_node_id = 1
	_selected_template_id = ""
	_link_start_node_id = -1
	_dragging_node_id = -1
	_is_resolved = false
	_panic_mode = false

	if _panic_overlay:
		_panic_overlay.visible = false
	if _terminal_overlay:
		_terminal_overlay.visible = false
	if _terminal_exit_button:
		_terminal_exit_button.disabled = true

	_spawn_core_nodes()
	_recompute_graph_state()
	_hint_label.text = "Goal: connect Kernel to App with all green links."
	if _template_order.size() > 0:
		_template_cursor_index = clampi(_template_cursor_index, 0, _template_order.size() - 1)
		_on_repository_item_pressed(_template_order[_template_cursor_index])
