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

const NODE_SIZE := Vector2(88, 52)
const PANIC_CONFLICT_THRESHOLD := 4
const CURSOR_STEP := 56.0
const FLOW_SPEED := 132.0
const APP_VISUAL_REFRESH_INTERVAL := 0.12
const RESET_TRY_MAX := 3
const ANTI_REPEAT_VARIATION_HISTORY := 6
const ANTI_REPEAT_SOLUTION_HISTORY := 4

const OBJECTIVE_PATH_TO_APP := "path_to_app"
const OBJECTIVE_STABLE_NODES := "stable_nodes"
const OBJECTIVE_STABLE_LINKS := "stable_links"

const MUTATOR_NONE := "none"
const MUTATOR_NO_DIRECT_KERNEL := "no_direct_kernel"
const MUTATOR_MAX_LINKS := "max_links"
const MUTATOR_ARM_UNSTABLE := "arm_unstable"

const RULE_EFFICIENCY := "efficiency"
const RULE_REDUNDANCY := "redundancy"
const RULE_RESTRICTED_ACCESS := "restricted_access"

const SIGNAL_APP_MIN := 70.0
const SIGNAL_APP_MAX := 90.0
const SIGNAL_KERNEL_BASE := 78.0

const MEMORY_LIMIT_PERCENT := 100.0
const VOLATILE_TIMEOUT_SECONDS := 5.0

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
var _build_help_label: Label

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
var _metadata_tooltip: PanelContainer
var _metadata_tooltip_label: Label
var _mono_font: Font
var _breadcrumb_label: Label
var _preflight_label: Label
var _flow_phase := 0.0
var _app_visual_refresh_accum := 0.0
var _hovered_node_id := -1
var _preflight_progress := 0.0
var _reset_tries_left := RESET_TRY_MAX

var _objective_type: String = OBJECTIVE_PATH_TO_APP
var _objective_target := 0
var _mutator_type: String = MUTATOR_NONE
var _mutator_link_cap := 6
var _last_objective_type: String = ""
var _last_mutator_type: String = ""
var _encounter_profile: String = "default"
var _recent_variation_signatures: PackedStringArray = PackedStringArray()
var _recent_solution_signatures: PackedStringArray = PackedStringArray()
var _current_app_requirements: PackedStringArray = PackedStringArray(["runtime_shell", "net_daemon"])
var _current_app_exact_inputs := 2
var _current_app_variant_label := "runtime+net"
var _rule_set_type: String = RULE_EFFICIENCY
var _rule_blacklist_template: String = "net_daemon"
var _rule_efficiency_max_nodes := 6

var _memory_usage_percent := 0.0
var _memory_failed := false
var _app_signal_strength := 0.0
var _volatile_timers: Dictionary = {}
var _watchdog_enabled := true
var _watchdog_position := Vector2.ZERO
var _watchdog_patrol_points: Array[Vector2] = []
var _watchdog_patrol_index := 0
var _watchdog_speed := 130.0
var _watchdog_cut_cooldown := 0.0
var _watchdog_clash_count := 0

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

	_update_reset_help_text()
	_reset_puzzle()
	_open_input_grace = 0.35
	_app_visual_refresh_accum = 0.0
	show()
	move_to_front()
	_is_active = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	# Clear custom cursor for dependency minigame
	Input.set_custom_mouse_cursor(null)

func close_minigame() -> void:
	hide()
	_is_active = false
	_open_input_grace = 0.0
	_app_visual_refresh_accum = 0.0
	_hovered_node_id = -1
	if _metadata_tooltip:
		_metadata_tooltip.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Restore custom cursor when closing minigame
	var cursor_texture := load("res://Assets/icons8-cursor-48.png") as Texture2D
	if cursor_texture:
		Input.set_custom_mouse_cursor(cursor_texture)
	resolver_closed.emit()

func configure_for_encounter(profile: String) -> void:
	var normalized := profile.strip_edges().to_lower()
	if normalized == "":
		normalized = "default"
	_encounter_profile = normalized
	_watchdog_enabled = _is_watchdog_profile(normalized)

func _is_watchdog_profile(profile: String) -> bool:
	# Moving watchdog cutter (red line) is reserved for miniboss/boss encounters.
	return profile == "driver_remnant" or profile == "printer_beast"

func _build_templates() -> void:
	_templates.clear()
	_templates["libcore_legacy"] = {
		"label": "Core Block",
		"version": 1.8,
		"arch": "x64",
		"requires_kernel": true,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray(),
		"max_in_ports": 3,
		"max_out_ports": 3,
		"signal_delta": 0.0,
		"is_diode": false,
		"is_volatile": false,
		"secure_socket_only_arm": false
	}
	_templates["thread_glue"] = {
		"label": "Thread Link",
		"version": 1.6,
		"arch": "x64",
		"requires_kernel": true,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray(),
		"max_in_ports": 2,
		"max_out_ports": 2,
		"signal_delta": 0.0,
		"is_diode": false,
		"is_volatile": false,
		"secure_socket_only_arm": false
	}
	_templates["runtime_shell"] = {
		"label": "Runtime Box",
		"version": 1.9,
		"arch": "x64",
		"requires_kernel": false,
		"exact_inputs": 2,
		"max_input_version": 99.0,
		"requires": PackedStringArray(["libcore_legacy", "thread_glue"]),
		"max_in_ports": 3,
		"max_out_ports": 2,
		"signal_delta": 0.0,
		"is_diode": false,
		"is_volatile": false,
		"secure_socket_only_arm": false
	}
	_templates["net_daemon"] = {
		"label": "Net Block",
		"version": 2.0,
		"arch": "x64",
		"requires_kernel": false,
		"exact_inputs": 1,
		"max_input_version": 1.9,
		"requires": PackedStringArray(["libcore_legacy"]),
		"max_in_ports": 2,
		"max_out_ports": 2,
		"signal_delta": 0.0,
		"is_diode": false,
		"is_volatile": false,
		"secure_socket_only_arm": false
	}
	_templates["arm_shim"] = {
		"label": "ARM Block",
		"version": 1.7,
		"arch": "arm",
		"requires_kernel": true,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray(),
		"max_in_ports": 2,
		"max_out_ports": 2,
		"signal_delta": 0.0,
		"is_diode": false,
		"is_volatile": false,
		"secure_socket_only_arm": false
	}
	_templates["ssl_old"] = {
		"label": "Secure Pack",
		"version": 2.3,
		"arch": "x64",
		"requires_kernel": false,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray(["thread_glue"]),
		"max_in_ports": 2,
		"max_out_ports": 1,
		"signal_delta": 0.0,
		"is_diode": false,
		"is_volatile": false,
		"secure_socket_only_arm": true
	}
	_templates["diode_valve"] = {
		"label": "Diode Node",
		"version": 1.4,
		"arch": "x64",
		"requires_kernel": false,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray(),
		"max_in_ports": 1,
		"max_out_ports": 1,
		"signal_delta": 0.0,
		"is_diode": true,
		"is_volatile": false,
		"secure_socket_only_arm": false
	}
	_templates["signal_amp"] = {
		"label": "Amplifier",
		"version": 1.3,
		"arch": "x64",
		"requires_kernel": false,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray(),
		"max_in_ports": 2,
		"max_out_ports": 2,
		"signal_delta": 15.0,
		"is_diode": false,
		"is_volatile": false,
		"secure_socket_only_arm": false
	}
	_templates["signal_damp"] = {
		"label": "Dampener",
		"version": 1.3,
		"arch": "x64",
		"requires_kernel": false,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray(),
		"max_in_ports": 2,
		"max_out_ports": 2,
		"signal_delta": -20.0,
		"is_diode": false,
		"is_volatile": false,
		"secure_socket_only_arm": false
	}
	_templates["volatile_cache"] = {
		"label": "Volatile Node",
		"version": 1.5,
		"arch": "x64",
		"requires_kernel": false,
		"exact_inputs": 0,
		"max_input_version": 99.0,
		"requires": PackedStringArray(),
		"max_in_ports": 2,
		"max_out_ports": 1,
		"signal_delta": 0.0,
		"is_diode": false,
		"is_volatile": true,
		"secure_socket_only_arm": false
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
	_status_label.text = "GOOD: 0 | CLASH: 0 | GREEN: 0"
	_status_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status_label.offset_left = 0
	_status_label.offset_top = 0
	_status_label.offset_right = 0
	_status_label.offset_bottom = 24
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(0.68, 1.0, 0.82))
	root.add_child(_status_label)

	_hint_label = Label.new()
	_hint_label.text = "Goal: Kernel -> App | Rule: Normal"
	_hint_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hint_label.offset_left = 0
	_hint_label.offset_top = 22
	_hint_label.offset_right = 0
	_hint_label.offset_bottom = 44
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Color(0.8, 0.95, 0.98))
	root.add_child(_hint_label)

	_preflight_label = Label.new()
	_preflight_label.text = "PRE-FLIGHT [..........] 0%"
	_preflight_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_preflight_label.offset_left = 0
	_preflight_label.offset_top = 44
	_preflight_label.offset_right = 0
	_preflight_label.offset_bottom = 66
	_preflight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preflight_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.35))
	root.add_child(_preflight_label)

	_selected_lib_label = Label.new()
	_selected_lib_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_selected_lib_label.offset_left = 0
	_selected_lib_label.offset_top = 44
	_selected_lib_label.offset_right = 0
	_selected_lib_label.offset_bottom = 66
	_selected_lib_label.visible = false
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
	build_help.text = ""
	build_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_help.add_theme_color_override("font_color", Color(0.7, 0.94, 0.9))
	build_v.add_child(build_help)
	_build_help_label = build_help
	_update_reset_help_text()

	_breadcrumb_label = Label.new()
	_breadcrumb_label.visible = false
	_breadcrumb_label.text = "[WARNING] Dependencies satisfied, but binary path to 'App Goal' is undefined."
	_breadcrumb_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_breadcrumb_label.offset_left = -330
	_breadcrumb_label.offset_top = -148
	_breadcrumb_label.offset_right = 330
	_breadcrumb_label.offset_bottom = -126
	_breadcrumb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_breadcrumb_label.add_theme_color_override("font_color", Color(0.96, 0.82, 0.32))
	root.add_child(_breadcrumb_label)

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

	_mono_font = SystemFont.new()
	(_mono_font as SystemFont).font_names = PackedStringArray([
		"Cascadia Mono",
		"Cascadia Code",
		"Consolas",
		"Courier New",
		"monospace"
	])

	_metadata_tooltip = PanelContainer.new()
	_metadata_tooltip.visible = false
	_metadata_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_metadata_tooltip.custom_minimum_size = Vector2.ZERO
	var tooltip_style := StyleBoxFlat.new()
	tooltip_style.bg_color = Color(0.02, 0.1, 0.09, 0.78)
	tooltip_style.border_width_left = 1
	tooltip_style.border_width_top = 1
	tooltip_style.border_width_right = 1
	tooltip_style.border_width_bottom = 1
	tooltip_style.border_color = Color(0.45, 1.0, 0.88, 0.75)
	_metadata_tooltip.add_theme_stylebox_override("panel", tooltip_style)
	add_child(_metadata_tooltip)

	_metadata_tooltip_label = Label.new()
	_metadata_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_metadata_tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_metadata_tooltip_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_metadata_tooltip_label.add_theme_font_size_override("font_size", 11)
	_metadata_tooltip_label.add_theme_font_override("font", _mono_font)
	_metadata_tooltip_label.add_theme_color_override("font_color", Color(0.62, 1.0, 0.88, 0.95))
	_metadata_tooltip_label.add_theme_color_override("font_shadow_color", Color(0.26, 1.0, 0.86, 0.42))
	_metadata_tooltip_label.add_theme_constant_override("shadow_offset_x", 0)
	_metadata_tooltip_label.add_theme_constant_override("shadow_offset_y", 0)
	_metadata_tooltip_label.add_theme_constant_override("shadow_outline_size", 2)
	_metadata_tooltip.add_child(_metadata_tooltip_label)

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
	if not _is_active:
		return

	_flow_phase = fposmod(_flow_phase + delta * FLOW_SPEED, 10000.0)
	_app_visual_refresh_accum += delta

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
	_tick_volatile_nodes(delta)
	_watchdog_process_loop(delta)

	if _dragging_node_id >= 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var node_ctrl := _node_controls.get(_dragging_node_id) as Control
		if node_ctrl:
			var local_mouse := _workspace.get_local_mouse_position()
			node_ctrl.position = local_mouse - _drag_offset
			if _draw_overlay:
				_draw_overlay.queue_redraw()

	if _workspace:
		_build_cursor = get_local_mouse_position()
		_build_cursor.x = clampf(_build_cursor.x, 8.0, size.x - 8.0)
		_build_cursor.y = clampf(_build_cursor.y, 8.0, size.y - 8.0)

	if _metadata_tooltip and _metadata_tooltip.visible and _hovered_node_id >= 0:
		_update_metadata_tooltip_position(_hovered_node_id)

	if _app_visual_refresh_accum >= APP_VISUAL_REFRESH_INTERVAL and _application_node_id >= 0 and _node_controls.has(_application_node_id):
		_app_visual_refresh_accum = 0.0
		_update_node_visual(_application_node_id)

	# Always redraw while active so the build cursor does not appear frozen in move mode.
	if _draw_overlay and _is_active:
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
			_try_manual_reset()
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
	var cursor := _build_cursor
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
		_draw_pipe_connection(o, preview_start, cursor, LINK_STABLE, true)

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
		if _is_resolved and link_state != LINK_STABLE:
			continue
		_draw_pipe_connection(o, start, end, link_state, false)

	# Draw connection ports on each node so link origins are obvious
	for node_id in _node_controls.keys():
		var ctrl := _node_controls[node_id] as Control
		if not ctrl:
			continue
		var center: Vector2 = ctrl.global_position + ctrl.size * 0.5 - overlay_origin
		o.draw_circle(center, 8.0, Color(0.1, 0.96, 0.95, 0.56))
		o.draw_arc(center, 9.5, 0.0, TAU, 20, Color(0.95, 1.0, 1.0, 0.98), 1.8)

	if _watchdog_enabled and _watchdog_patrol_points.size() > 0:
		var dog_pos := ws_pos + _watchdog_position
		o.draw_circle(dog_pos, 9.0, Color(0.98, 0.16, 0.2, 0.88))
		o.draw_arc(dog_pos, 13.0, 0.0, TAU, 20, Color(1.0, 0.68, 0.7, 0.95), 2.2)
		var next_target := ws_pos + _watchdog_patrol_points[_watchdog_patrol_index]
		o.draw_line(dog_pos, next_target, Color(0.96, 0.38, 0.44, 0.45), 1.5)

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

func _draw_pipe_connection(canvas: CanvasItem, start: Vector2, end: Vector2, link_state: int, is_preview: bool) -> void:
	var vec := end - start
	var length := vec.length()
	if length < 2.0:
		return

	var dir := vec / length
	var perp := Vector2(-dir.y, dir.x)

	var base_color := Color(0.9, 0.2, 0.25)
	if link_state == LINK_CONFLICT:
		base_color = Color(0.96, 0.8, 0.24)
	elif link_state == LINK_STABLE:
		base_color = Color(0.38, 1.0, 0.72)

	var usable_end := end
	var failure_point := end
	if not is_preview and link_state != LINK_STABLE:
		var fail_ratio := 0.5
		if link_state == LINK_BROKEN:
			fail_ratio = 0.34 + 0.1 * sin(Time.get_ticks_msec() * 0.013)
		failure_point = start.lerp(end, fail_ratio)
		usable_end = failure_point

	var segment_len := 11.0
	var gap := 5.0
	var d := 0.0
	var usable_len := (usable_end - start).length()
	while d < usable_len:
		var seg_start := start + dir * d
		var seg_end := start + dir * minf(d + segment_len, usable_len)
		canvas.draw_line(seg_start, seg_end, Color(base_color.r, base_color.g, base_color.b, 0.46), 7.0, true)
		canvas.draw_line(seg_start, seg_end, Color(0.92, 1.0, 0.95, 0.9), 3.1, true)
		canvas.draw_line(seg_start, seg_end, Color(base_color.r, base_color.g, base_color.b, 0.94), 1.8, true)
		d += segment_len + gap

	var rib_spacing := 18.0
	var rib_offset := fposmod(_flow_phase * 0.35, rib_spacing)
	var r := rib_offset
	while r < usable_len:
		var rp := start + dir * r
		canvas.draw_line(rp - perp * 4.0, rp + perp * 4.0, Color(0.96, 1.0, 0.98, 0.82), 1.3, true)
		r += rib_spacing

	var ch_spacing := 72.0
	var c := 26.0
	while c < usable_len - 18.0:
		var cp := start + dir * c
		_draw_chevron(canvas, cp, dir, base_color)
		_draw_chevron(canvas, cp + dir * 8.0, dir, base_color)
		c += ch_spacing

	if link_state == LINK_STABLE or is_preview:
		var bit_count := maxi(2, int(usable_len / 70.0))
		for i in range(bit_count):
			var phase := fposmod(_flow_phase + float(i) * (usable_len / float(bit_count)), usable_len)
			var bp := start + dir * phase
			canvas.draw_rect(Rect2(bp - Vector2(2.5, 2.5), Vector2(5.0, 5.0)), Color(0.46, 1.0, 0.55, 0.95), true)

	if not is_preview and link_state != LINK_STABLE:
		var static_color := Color(0.66, 0.72, 0.76, 0.25)
		var sd := (failure_point - start).length() + 6.0
		while sd < length:
			var sp := start + dir * sd
			var jitter := perp * randf_range(-2.0, 2.0)
			canvas.draw_rect(Rect2(sp + jitter - Vector2(1.2, 1.2), Vector2(2.4, 2.4)), static_color, true)
			sd += 4.0

		for j in range(8):
			var noise := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
			canvas.draw_rect(Rect2(failure_point + noise, Vector2(2.0, 2.0)), Color(0.95, 0.98, 1.0, 0.44), true)

		canvas.draw_circle(failure_point, 4.0 + abs(sin(Time.get_ticks_msec() * 0.03)) * 2.5, Color(1.0, 0.95, 0.95, 0.38))

	var tip := usable_end
	var tip_back := tip - dir * 10.0
	var side := perp * 5.5
	canvas.draw_colored_polygon(PackedVector2Array([tip, tip_back + side, tip_back - side]), Color(base_color.r, base_color.g, base_color.b, 0.95))

func _draw_chevron(canvas: CanvasItem, center: Vector2, dir: Vector2, color: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var p1 := center - dir * 4.0 - perp * 4.0
	var p2 := center + dir * 4.0
	var p3 := center - dir * 4.0 + perp * 4.0
	canvas.draw_line(p1, p2, Color(color.r, color.g, color.b, 0.8), 1.6, true)
	canvas.draw_line(p2, p3, Color(color.r, color.g, color.b, 0.8), 1.6, true)

func _on_node_hover_entered(node_id: int) -> void:
	_hovered_node_id = node_id
	_show_metadata_tooltip(node_id)

func _on_node_hover_exited(node_id: int) -> void:
	if _hovered_node_id != node_id:
		return
	_hovered_node_id = -1
	if _metadata_tooltip:
		_metadata_tooltip.visible = false

func _show_metadata_tooltip(node_id: int) -> void:
	if not _metadata_tooltip or not _metadata_tooltip_label:
		return
	if not _nodes.has(node_id):
		_metadata_tooltip.visible = false
		return

	_metadata_tooltip_label.text = _build_metadata_text(_nodes[node_id])
	_metadata_tooltip_label.reset_size()
	_metadata_tooltip.reset_size()
	_metadata_tooltip.visible = true
	_update_metadata_tooltip_position(node_id)

func _update_metadata_tooltip_position(node_id: int) -> void:
	if not _metadata_tooltip or not _node_controls.has(node_id):
		return
	var ctrl := _node_controls[node_id] as Control
	if ctrl == null:
		return

	var pos := ctrl.global_position - global_position
	var tooltip_size := _metadata_tooltip.size
	if tooltip_size.x <= 0.0 or tooltip_size.y <= 0.0:
		tooltip_size = _metadata_tooltip.get_combined_minimum_size()
	var tooltip_pos := pos + Vector2(ctrl.size.x + 12.0, -6.0)
	var max_x := maxf(0.0, self.size.x - tooltip_size.x - 8.0)
	var max_y := maxf(0.0, self.size.y - tooltip_size.y - 8.0)
	tooltip_pos.x = clampf(tooltip_pos.x, 8.0, max_x)
	tooltip_pos.y = clampf(tooltip_pos.y, 8.0, max_y)
	_metadata_tooltip.position = tooltip_pos

func _build_metadata_text(node: Dictionary) -> String:
	var template_id := str(node.get("template_id", ""))
	match template_id:
		"kernel":
			return "KERNEL START\nSource node\nSend links outward"
		"libcore_legacy":
			return "CORE BLOCK\nBase dependency\nFeeds runtime/net"
		"thread_glue":
			return "THREAD LINK\nConcurrency helper\nPairs with Runtime"
		"net_daemon":
			return "NET BLOCK\nRoutes network data\nNeed: Core Block"
		"runtime_shell":
			return "RUNTIME BOX\nRuns app code\nNeed: Core + Thread"
		"arm_shim":
			return "ARM BLOCK\nARM compatibility\nMay be unstable"
		"ssl_old":
			return "SECURE PACK\nSocket: ARM input only\nSecurity helper"
		"diode_valve":
			return "DIODE NODE\nOne-way flow toward App\nBlocks back-trace"
		"signal_amp":
			return "AMPLIFIER\nSignal +15\nTune final strength"
		"signal_damp":
			return "DAMPENER\nSignal -20\nTune final strength"
		"volatile_cache":
			return "VOLATILE NODE\n5s decay after activation\nDownstream resets on timeout"
		"application":
			return "APP GOAL\nNeed: %s\nSignal: %.0f-%.0f%%\nRule: %s" % [_objective_tip_text(), SIGNAL_APP_MIN, SIGNAL_APP_MAX, _rule_set_short_text()]
		_:
			return "%s\nStatus: %s\nTip: add incoming links" % [
				str(node.get("label", "NODE")).to_upper(),
				str(node.get("reason", "pending"))
			]

func _objective_tip_text() -> String:
	match _objective_type:
		OBJECTIVE_STABLE_NODES:
			return "%d READY nodes" % _objective_target
		OBJECTIVE_STABLE_LINKS:
			return "%d GREEN links" % _objective_target
		_:
			return "Green path (%s)" % _current_app_variant_label

func _mutator_tip_text() -> String:
	match _mutator_type:
		MUTATOR_NO_DIRECT_KERNEL:
			return "No direct Kernel->App"
		MUTATOR_MAX_LINKS:
			return "Max %d links" % _mutator_link_cap
		MUTATOR_ARM_UNSTABLE:
			return "ARM nodes always CLASH"
		_:
			return "Normal"

func _build_node_hint(node: Dictionary) -> String:
	var template_id := str(node.get("template_id", ""))
	match template_id:
		"kernel":
			return "Start here"
		"application":
			return "End goal"
		"runtime_shell":
			return "Run app"
		"net_daemon":
			return "Net path"
		"thread_glue":
			return "Link lib"
		"libcore_legacy":
			return "Core lib"
		"arm_shim":
			return "ARM lib"
		"ssl_old":
			return "Secure lib"
		"diode_valve":
			return "One-way"
		"signal_amp":
			return "+Signal"
		"signal_damp":
			return "-Signal"
		"volatile_cache":
			return "Decay 5s"
		_:
			return "Dependency"

func _on_workspace_gui_input(event: InputEvent) -> void:
	if not _is_active:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_build_cursor = get_local_mouse_position()
		if _selected_template_id != "":
			_spawn_library(_selected_template_id, _workspace.get_local_mouse_position() - NODE_SIZE * 0.5)
			_hint_label.text = "Placed. Connect nodes."
			get_viewport().set_input_as_handled()

func _toggle_link_mode() -> void:
	_link_mode = not _link_mode
	_link_start_node_id = -1
	if _link_mode:
		_hint_label.text = "Connect: pick start, then end."
	else:
		_hint_label.text = "Move mode: drag nodes."

func _try_manual_reset() -> void:
	if _reset_tries_left <= 0:
		_hint_label.text = "Reset locked: no tries left."
		return

	_reset_tries_left -= 1
	_update_reset_help_text()
	_reset_puzzle()
	_hint_label.text = "Reset used (%d left)." % _reset_tries_left

func _update_reset_help_text() -> void:
	if _build_help_label == null:
		return
	_build_help_label.text = "[L] Connect mode  [RMB] Delete  [C] Reset (%d/%d)" % [_reset_tries_left, RESET_TRY_MAX]
	if _reset_tries_left <= 0:
		_build_help_label.add_theme_color_override("font_color", Color(0.96, 0.62, 0.46))
	else:
		_build_help_label.add_theme_color_override("font_color", Color(0.7, 0.94, 0.9))

func _on_repository_item_pressed(template_id: String) -> void:
	_selected_template_id = template_id
	var t: Dictionary = _templates[template_id]
	if _template_order.size() > 0:
		_template_cursor_index = maxi(0, _template_order.find(template_id))
	if _selected_lib_label:
		_selected_lib_label.text = "Selected: %s" % t["label"]
	_hint_label.text = "Selected: %s" % t["label"]

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
				_spawn_library(_selected_template_id, _cursor_workspace_position() - NODE_SIZE * 0.5)
				_hint_label.text = "Placed: %s" % _templates[_selected_template_id]["label"]
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
		"requires": PackedStringArray(),
		"max_in_ports": 0,
		"max_out_ports": 4,
		"signal_delta": 0.0,
		"is_diode": false,
		"is_volatile": false,
		"secure_socket_only_arm": false
	}, Vector2(maxf(90.0, ws_size.x * 0.12), ws_size.y * 0.68))

	_application_node_id = _create_node({
		"template_id": "application",
		"label": "App Goal",
		"version": 2.0,
		"arch": "x64",
		"is_core": false,
		"is_application": true,
		"requires_kernel": false,
		"exact_inputs": _current_app_exact_inputs,
		"max_input_version": 99.0,
		"requires": _current_app_requirements,
		"max_in_ports": 3,
		"max_out_ports": 0,
		"signal_delta": 0.0,
		"is_diode": false,
		"is_volatile": false,
		"secure_socket_only_arm": false
	}, Vector2(ws_size.x * 0.72, ws_size.y * 0.18))
	_setup_watchdog_patrol()

func _cursor_workspace_position() -> Vector2:
	if _workspace == null:
		return _build_cursor

	var ws_origin := _workspace.global_position - global_position
	var workspace_cursor := _build_cursor - ws_origin
	workspace_cursor.x = clampf(workspace_cursor.x, 16.0, _workspace.size.x - 16.0)
	workspace_cursor.y = clampf(workspace_cursor.y, 16.0, _workspace.size.y - 16.0)
	return workspace_cursor

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
		"requires": template["requires"],
		"max_in_ports": template.get("max_in_ports", 2),
		"max_out_ports": template.get("max_out_ports", 2),
		"signal_delta": template.get("signal_delta", 0.0),
		"is_diode": template.get("is_diode", false),
		"is_volatile": template.get("is_volatile", false),
		"secure_socket_only_arm": template.get("secure_socket_only_arm", false)
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
	title.add_theme_font_size_override("font_size", 10)
	vbox.add_child(title)

	var meta := Label.new()
	meta.name = "Meta"
	meta.text = ""
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_theme_font_size_override("font_size", 8)
	vbox.add_child(meta)

	var state := Label.new()
	state.name = "State"
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 7)
	vbox.add_child(state)

	panel.gui_input.connect(_on_node_gui_input.bind(node_id))
	panel.mouse_entered.connect(_on_node_hover_entered.bind(node_id))
	panel.mouse_exited.connect(_on_node_hover_exited.bind(node_id))
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
	if _hovered_node_id == node_id:
		_hovered_node_id = -1
		if _metadata_tooltip:
			_metadata_tooltip.visible = false

	var kept: Array[Dictionary] = []
	for link in _connections:
		if int(link["from"]) == node_id or int(link["to"]) == node_id:
			continue
		kept.append(link)
	_connections = kept
	_recompute_graph_state()

func _recompute_graph_state() -> void:
	_run_validation_pass()
	_run_signal_propagation_pass()

	for node_id in _nodes.keys():
		_update_node_visual(int(node_id))

	_update_state_labels()
	_check_fail_or_win()
	if _draw_overlay:
		_draw_overlay.queue_redraw()

func _run_validation_pass() -> void:
	var incoming_counts: Dictionary = {}
	var outgoing_counts: Dictionary = {}
	var incoming_sources: Dictionary = {}
	_memory_usage_percent = 0.0

	for link in _connections:
		var from_id := int(link.get("from", -1))
		var to_id := int(link.get("to", -1))
		incoming_counts[to_id] = int(incoming_counts.get(to_id, 0)) + 1
		outgoing_counts[from_id] = int(outgoing_counts.get(from_id, 0)) + 1
		if not incoming_sources.has(to_id):
			incoming_sources[to_id] = []
		(incoming_sources[to_id] as Array).append(from_id)
		_memory_usage_percent += _compute_edge_memory_cost(from_id, to_id)

	_memory_usage_percent = clampf(_memory_usage_percent, 0.0, 300.0)
	_memory_failed = _memory_usage_percent >= MEMORY_LIMIT_PERCENT

	for node_id in _nodes.keys():
		var node: Dictionary = _nodes[node_id]
		if bool(node.get("is_core", false)):
			node["status"] = STATUS_CORE
			node["reason"] = "Start"
			node["signal"] = SIGNAL_KERNEL_BASE
			_nodes[node_id] = node
			continue

		var incoming: Array[int] = []
		if incoming_sources.has(node_id):
			var raw_incoming: Array = incoming_sources[node_id]
			for source_variant in raw_incoming:
				incoming.append(int(source_variant))

		var source_templates: PackedStringArray = PackedStringArray()
		var source_arches: PackedStringArray = PackedStringArray()
		var version_ok := true
		var has_direct_kernel := false
		var secure_socket_ok := true
		var has_arm_input := false

		for source_id in incoming:
			if not _nodes.has(source_id):
				continue
			var src: Dictionary = _nodes[source_id]
			source_templates.append(str(src.get("template_id", "")))
			var src_arch := str(src.get("arch", ""))
			if not source_arches.has(src_arch):
				source_arches.append(src_arch)
			if str(src.get("template_id", "")) == "arm_shim":
				has_arm_input = true
			if bool(src.get("is_core", false)):
				has_direct_kernel = true
			if float(src.get("version", 0.0)) > float(node.get("max_input_version", 99.0)):
				version_ok = false

		# Secure nodes need at least one ARM source, but may also require non-ARM deps.
		if bool(node.get("secure_socket_only_arm", false)) and not has_arm_input:
			secure_socket_ok = false

		var required: PackedStringArray = node.get("requires", PackedStringArray())
		var missing_required := false
		for req in required:
			if not source_templates.has(req):
				missing_required = true
				break

		var exact_inputs: int = int(node.get("exact_inputs", 0))
		var exact_ok := exact_inputs <= 0 or incoming.size() == exact_inputs
		var kernel_ok := (not bool(node.get("requires_kernel", false))) or has_direct_kernel
		var is_application := bool(node.get("is_application", false))
		var arch_conflict := source_arches.size() > 1 and not is_application
		var arm_unstable := _mutator_type == MUTATOR_ARM_UNSTABLE and str(node.get("arch", "")) == "arm"
		var in_ports := int(incoming_counts.get(node_id, 0))
		var in_limit := int(node.get("max_in_ports", 2))
		var ports_ok := in_limit <= 0 or in_ports <= in_limit

		if arm_unstable:
			node["status"] = STATUS_CONFLICT
			node["reason"] = "ARM noisy"
		elif arch_conflict:
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
		elif not missing_required and not secure_socket_ok:
			node["status"] = STATUS_BROKEN
			node["reason"] = "ARM socket only"
		elif missing_required:
			node["status"] = STATUS_BROKEN
			node["reason"] = "Missing part"
		elif not ports_ok:
			node["status"] = STATUS_BROKEN
			node["reason"] = "Port limit"
		elif incoming.is_empty() and not bool(node.get("is_application", false)):
			node["status"] = STATUS_BROKEN
			node["reason"] = "No input"
		else:
			node["status"] = STATUS_STABLE
			node["reason"] = "Good"

		_nodes[node_id] = node

	for idx in range(_connections.size()):
		var link := _connections[idx]
		var from_id: int = int(link.get("from", -1))
		var to_id: int = int(link.get("to", -1))
		if not _nodes.has(from_id) or not _nodes.has(to_id):
			continue
		var src: Dictionary = _nodes[from_id] as Dictionary
		var dst: Dictionary = _nodes[to_id] as Dictionary
		var out_count := int(outgoing_counts.get(from_id, 0))
		var in_count := int(incoming_counts.get(to_id, 0))
		var out_limit := int(src.get("max_out_ports", 2))
		var in_limit := int(dst.get("max_in_ports", 2))
		var link_cost := _compute_edge_memory_cost(from_id, to_id)
		link["memory_cost"] = link_cost

		if _mutator_type == MUTATOR_MAX_LINKS and idx >= _mutator_link_cap:
			link["state"] = LINK_BROKEN
			link["reason"] = "overload"
		elif _mutator_type == MUTATOR_NO_DIRECT_KERNEL and bool(src.get("is_core", false)) and bool(dst.get("is_application", false)):
			link["state"] = LINK_BROKEN
			link["reason"] = "kernel-lock"
		elif out_limit > 0 and out_count > out_limit:
			link["state"] = LINK_BROKEN
			link["reason"] = "port-out"
		elif in_limit > 0 and in_count > in_limit:
			link["state"] = LINK_BROKEN
			link["reason"] = "port-in"
		elif not _is_diode_direction_valid(from_id, to_id):
			link["state"] = LINK_BROKEN
			link["reason"] = "diode"
		elif float(src.get("version", 0.0)) > float(dst.get("max_input_version", 99.0)):
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

	_update_volatile_tracking()

func _run_signal_propagation_pass() -> void:
	for node_id in _nodes.keys():
		var node: Dictionary = _nodes[node_id]
		node["signal"] = -1.0
		_nodes[node_id] = node

	if _nodes.has(_kernel_node_id):
		var kernel := _nodes[_kernel_node_id] as Dictionary
		kernel["signal"] = SIGNAL_KERNEL_BASE
		_nodes[_kernel_node_id] = kernel

	for _iter in range(_nodes.size() + 1):
		var changed := false
		for link in _connections:
			if int(link.get("state", LINK_BROKEN)) != LINK_STABLE:
				continue
			var from_id := int(link.get("from", -1))
			var to_id := int(link.get("to", -1))
			if not _nodes.has(from_id) or not _nodes.has(to_id):
				continue
			var src : Dictionary = _nodes[from_id]
			var dst : Dictionary = _nodes[to_id]
			var src_signal := float(src.get("signal", -1.0))
			if src_signal < 0.0:
				continue
			var candidate := clampf(src_signal + float(dst.get("signal_delta", 0.0)), 0.0, 100.0)
			if candidate > float(dst.get("signal", -1.0)):
				dst["signal"] = candidate
				_nodes[to_id] = dst
				changed = true
		if not changed:
			break

	_app_signal_strength = 0.0
	if _nodes.has(_application_node_id):
		var app_node: Dictionary = _nodes[_application_node_id]
		_app_signal_strength = float(app_node.get("signal", -1.0))
		if _app_signal_strength < SIGNAL_APP_MIN or _app_signal_strength > SIGNAL_APP_MAX:
			if int(app_node.get("status", STATUS_BROKEN)) == STATUS_STABLE:
				app_node["status"] = STATUS_BROKEN
				app_node["reason"] = "Signal %.0f%%" % _app_signal_strength
				_nodes[_application_node_id] = app_node

func _compute_edge_memory_cost(from_id: int, to_id: int) -> float:
	if not _node_controls.has(from_id) or not _node_controls.has(to_id):
		return 8.0
	var from_ctrl := _node_controls[from_id] as Control
	var to_ctrl := _node_controls[to_id] as Control
	var a := from_ctrl.position + from_ctrl.size * 0.5
	var b := to_ctrl.position + to_ctrl.size * 0.5
	var dist := a.distance_to(b)
	var jump_penalty := 6.0 if abs(a.x - b.x) > 320.0 else 0.0
	return 8.0 + floor(dist / 120.0) + jump_penalty

func _is_diode_direction_valid(from_id: int, to_id: int) -> bool:
	if not _nodes.has(from_id) or not _nodes.has(to_id) or not _node_controls.has(_application_node_id):
		return true
	var src : Dictionary = _nodes[from_id]
	var dst : Dictionary = _nodes[to_id]
	var app_ctrl := _node_controls[_application_node_id] as Control
	var app_center := app_ctrl.position + app_ctrl.size * 0.5

	if bool(dst.get("is_diode", false)):
		var src_ctrl := _node_controls.get(from_id) as Control
		var dst_ctrl := _node_controls.get(to_id) as Control
		if src_ctrl == null or dst_ctrl == null:
			return false
		var src_d := (src_ctrl.position + src_ctrl.size * 0.5).distance_to(app_center)
		var dst_d := (dst_ctrl.position + dst_ctrl.size * 0.5).distance_to(app_center)
		return src_d > dst_d

	if bool(src.get("is_diode", false)):
		var src_ctrl2 := _node_controls.get(from_id) as Control
		var dst_ctrl2 := _node_controls.get(to_id) as Control
		if src_ctrl2 == null or dst_ctrl2 == null:
			return false
		var src_d2 := (src_ctrl2.position + src_ctrl2.size * 0.5).distance_to(app_center)
		var dst_d2 := (dst_ctrl2.position + dst_ctrl2.size * 0.5).distance_to(app_center)
		return dst_d2 < src_d2

	return true

func _update_volatile_tracking() -> void:
	for node_id in _nodes.keys():
		var node : Dictionary = _nodes[node_id]
		if not bool(node.get("is_volatile", false)):
			_volatile_timers.erase(int(node_id))
			continue
		if int(node.get("status", STATUS_BROKEN)) == STATUS_STABLE:
			if not _volatile_timers.has(int(node_id)):
				_volatile_timers[int(node_id)] = VOLATILE_TIMEOUT_SECONDS
		else:
			_volatile_timers.erase(int(node_id))

func _tick_volatile_nodes(delta: float) -> void:
	if _volatile_timers.is_empty() or not _is_active or _is_resolved:
		return
	var expired: Array[int] = []
	for key in _volatile_timers.keys():
		var node_id := int(key)
		var t := float(_volatile_timers[key]) - delta
		_volatile_timers[key] = t
		if t <= 0.0:
			expired.append(node_id)
	for node_id in expired:
		_volatile_timers.erase(node_id)
		_trigger_volatile_timeout(node_id)

func _trigger_volatile_timeout(node_id: int) -> void:
	var kept: Array[Dictionary] = []
	for link in _connections:
		if int(link.get("from", -1)) == node_id:
			continue
		kept.append(link)
	_connections = kept
	if _nodes.has(node_id):
		var node :Dictionary = _nodes[node_id]
		node["status"] = STATUS_BROKEN
		node["reason"] = "Timed out"
		_nodes[node_id] = node
	_recompute_graph_state()

func _setup_watchdog_patrol() -> void:
	if _workspace == null:
		return
	var ws := _workspace.size
	_watchdog_patrol_points = [
		Vector2(ws.x * 0.25, ws.y * 0.24),
		Vector2(ws.x * 0.72, ws.y * 0.26),
		Vector2(ws.x * 0.78, ws.y * 0.68),
		Vector2(ws.x * 0.28, ws.y * 0.72),
	]
	_watchdog_patrol_index = 0
	_watchdog_position = _watchdog_patrol_points[0]

func _watchdog_process_loop(delta: float) -> void:
	if not _watchdog_enabled or not _is_active or _is_resolved or _watchdog_patrol_points.is_empty():
		return
	_watchdog_cut_cooldown = maxf(0.0, _watchdog_cut_cooldown - delta)
	var target := _watchdog_patrol_points[_watchdog_patrol_index]
	var to_target := target - _watchdog_position
	var step := _watchdog_speed * delta
	if to_target.length() <= maxf(1.0, step):
		_watchdog_position = target
		_watchdog_patrol_index = (_watchdog_patrol_index + 1) % _watchdog_patrol_points.size()
	else:
		_watchdog_position += to_target.normalized() * step

	if _watchdog_cut_cooldown > 0.0:
		return

	for idx in range(_connections.size()):
		var link := _connections[idx]
		if int(link.get("state", LINK_BROKEN)) != LINK_STABLE:
			continue
		var from_id := int(link.get("from", -1))
		var to_id := int(link.get("to", -1))
		if not _node_controls.has(from_id) or not _node_controls.has(to_id):
			continue
		var from_ctrl := _node_controls[from_id] as Control
		var to_ctrl := _node_controls[to_id] as Control
		var a := from_ctrl.position + from_ctrl.size * 0.5
		var b := to_ctrl.position + to_ctrl.size * 0.5
		if _distance_point_to_segment(_watchdog_position, a, b) <= 16.0:
			_connections.remove_at(idx)
			_watchdog_clash_count += 1
			_watchdog_cut_cooldown = 0.6
			_recompute_graph_state()
			return

func _distance_point_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	var closest := a + ab * t
	return point.distance_to(closest)

func _update_node_visual(node_id: int) -> void:
	if not _nodes.has(node_id) or not _node_controls.has(node_id):
		return

	var node: Dictionary = _nodes[node_id]
	var panel := _node_controls[node_id] as PanelContainer
	var title := panel.get_node_or_null("VBoxContainer/Title") as Label
	var meta := panel.get_node_or_null("VBoxContainer/Meta") as Label
	var state := panel.get_node_or_null("VBoxContainer/State") as Label

	var color := Color(0.95, 0.2, 0.28)
	var state_text := "LINK"
	if bool(node.get("is_application", false)):
		var app_payload := _get_app_goal_status_payload()
		color = app_payload["color"]
		state_text = app_payload["state_text"]
		if title:
			title.text = "App Goal"
			title.add_theme_color_override("font_color", Color(0.88, 1.0, 0.98))
		if meta:
			meta.text = app_payload["meta_text"]
			meta.add_theme_color_override("font_color", Color(0.78, 0.95, 0.96))
		if state:
			state.text = state_text
			state.add_theme_color_override("font_color", color)
		var app_style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		if app_style:
			var app_override := app_style.duplicate() as StyleBoxFlat
			app_override.border_color = color
			app_override.bg_color = Color(color.r * 0.16, color.g * 0.16, color.b * 0.2, 0.82)
			panel.add_theme_stylebox_override("panel", app_override)
		return

	match int(node.get("status", STATUS_BROKEN)):
		STATUS_CORE:
			color = Color(0.35, 0.65, 1.0)
			state_text = "START"
		STATUS_CONFLICT:
			color = Color(0.96, 0.78, 0.24)
			state_text = "FIX"
		STATUS_STABLE:
			color = Color(0.32, 1.0, 0.55)
			state_text = "READY"

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
		meta.text = _build_node_hint(node)
		meta.add_theme_color_override("font_color", Color(0.78, 0.95, 0.96))
	if state:
		state.text = "%s" % state_text
		state.add_theme_color_override("font_color", color)

func _update_state_labels() -> void:
	var stable_count := 0
	var conflict_count := 0
	var stable_link_count := 0
	for node in _nodes.values():
		match int(node.get("status", STATUS_BROKEN)):
			STATUS_STABLE, STATUS_CORE:
				stable_count += 1
			STATUS_CONFLICT:
				conflict_count += 1
	for link in _connections:
		if int(link.get("state", LINK_BROKEN)) == LINK_STABLE:
			stable_link_count += 1

	var goal_text := _objective_short_text()
	var rule_text := _rule_set_short_text()
	var mod_text := _mutator_short_text()
	var sub_progress := _get_subobjective_progress()
	var sub_met: bool = sub_progress["met"]
	var has_physical_path := _has_any_path(_kernel_node_id, _application_node_id)
	var is_fully_ready := _is_objective_complete(0)
	_preflight_progress = _compute_preflight_progress()

	_status_label.text = "GOOD:%d | CLASH:%d | GREEN:%d | MEM:%d%% | SIG:%d%% | GOAL:%d/%d" % [
		stable_count,
		conflict_count + _watchdog_clash_count,
		stable_link_count,
		int(round(_memory_usage_percent)),
		int(round(_app_signal_strength)),
		int(sub_progress["current"]),
		int(sub_progress["target"])
	]
	if _status_label:
		if is_fully_ready:
			_status_label.add_theme_color_override("font_color", Color(0.38, 1.0, 0.62))
		else:
			_status_label.add_theme_color_override("font_color", Color(0.96, 0.82, 0.35))
	_hint_label.text = "Goal: %s | Rule: %s | Mod: %s" % [goal_text, rule_text, mod_text]

	if _breadcrumb_label:
		_breadcrumb_label.visible = sub_met and not has_physical_path

	if _preflight_label:
		_preflight_label.text = "PRE-FLIGHT %s %d%%" % [_build_preflight_bar(_preflight_progress), int(round(_preflight_progress * 100.0))]
		if is_fully_ready:
			_preflight_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.66))
		elif has_physical_path:
			_preflight_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.35))
		else:
			_preflight_label.add_theme_color_override("font_color", Color(0.94, 0.64, 0.34))

func _check_fail_or_win() -> void:
	if _is_resolved:
		return

	if _memory_failed:
		_panic_mode = true
		_panic_overlay.visible = true
		_hint_label.text = "Install failed: Memory overload. Press C to reset."
		return

	var conflict_count := 0
	for node in _nodes.values():
		if int(node.get("status", STATUS_BROKEN)) == STATUS_CONFLICT:
			conflict_count += 1
	for link in _connections:
		if int(link.get("state", LINK_BROKEN)) == LINK_CONFLICT:
			conflict_count += 1
	conflict_count += _watchdog_clash_count

	if conflict_count >= PANIC_CONFLICT_THRESHOLD:
		_panic_mode = true
		_panic_overlay.visible = true
		_hint_label.text = "Too many clashes. Press C to reset."
		return

	_panic_mode = false
	_panic_overlay.visible = false

	if not _is_objective_complete(conflict_count):
		return

	if _is_repeated_solution_pattern():
		_hint_label.text = "Pattern reused. Build a different route."
		return

	_remember_solution_signature()

	_is_resolved = true
	_hint_label.text = "All good. Install is ready."
	_show_success_terminal()

func _has_green_path(start_id: int, target_id: int) -> bool:
	if start_id < 0 or target_id < 0:
		return false
	if not _nodes.has(start_id) or not _nodes.has(target_id):
		return false

	var adjacency := _build_adjacency_from_links(_connections, true)
	var visited: Dictionary = {}
	var stack: Array[int] = [start_id]

	while not stack.is_empty():
		var current := int(stack.pop_back())
		if current == target_id:
			return true
		if visited.has(current):
			continue
		visited[current] = true

		for next_id_variant in adjacency.get(current, []):
			var next_id := int(next_id_variant)
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
	_hovered_node_id = -1
	_memory_usage_percent = 0.0
	_memory_failed = false
	_app_signal_strength = 0.0
	_volatile_timers.clear()
	_watchdog_clash_count = 0
	_watchdog_cut_cooldown = 0.0

	if _panic_overlay:
		_panic_overlay.visible = false
	if _terminal_overlay:
		_terminal_overlay.visible = false
	if _terminal_exit_button:
		_terminal_exit_button.disabled = true
	if _metadata_tooltip:
		_metadata_tooltip.visible = false

	_select_run_variation()

	_spawn_core_nodes()
	_recompute_graph_state()
	_hint_label.text = "Goal: %s | Rule: %s | Mod: %s" % [_objective_short_text(), _rule_set_short_text(), _mutator_short_text()]
	if _template_order.size() > 0:
		_template_cursor_index = clampi(_template_cursor_index, 0, _template_order.size() - 1)
		_on_repository_item_pressed(_template_order[_template_cursor_index])

func _select_run_variation() -> void:
	var app_variants: Array[Dictionary] = [
		{
			"label": "runtime+net",
			"requires": PackedStringArray(["runtime_shell", "net_daemon"]),
			"exact_inputs": 2
		},
		{
			"label": "runtime+secure",
			"requires": PackedStringArray(["runtime_shell", "ssl_old"]),
			"exact_inputs": 2
		},
		{
			"label": "arm+secure",
			"requires": PackedStringArray(["arm_shim", "ssl_old"]),
			"exact_inputs": 2
		},
		{
			"label": "runtime+arm",
			"requires": PackedStringArray(["runtime_shell", "arm_shim"]),
			"exact_inputs": 2
		}
	]

	var objectives := PackedStringArray([
		OBJECTIVE_PATH_TO_APP,
		OBJECTIVE_STABLE_NODES,
		OBJECTIVE_STABLE_LINKS,
	])
	var mutators := PackedStringArray([
		MUTATOR_NONE,
		MUTATOR_NO_DIRECT_KERNEL,
		MUTATOR_MAX_LINKS,
		MUTATOR_ARM_UNSTABLE,
	])
	var rules := PackedStringArray([
		RULE_EFFICIENCY,
		RULE_REDUNDANCY,
		RULE_RESTRICTED_ACCESS,
	])
	var restricted_pool := PackedStringArray(["net_daemon", "runtime_shell", "ssl_old"])

	var objective_weights := PackedInt32Array([3, 3, 3])
	var mutator_weights := PackedInt32Array([4, 2, 2, 2])
	var app_weights := PackedInt32Array([4, 3, 2, 2])
	var rule_weights := PackedInt32Array([4, 3, 3])

	match _encounter_profile:
		"driver_remnant":
			objective_weights = PackedInt32Array([2, 2, 6])
			mutator_weights = PackedInt32Array([2, 3, 5, 1])
			app_weights = PackedInt32Array([5, 2, 1, 2])
			rule_weights = PackedInt32Array([5, 2, 3])
		"hardware_ghost":
			objective_weights = PackedInt32Array([2, 6, 2])
			mutator_weights = PackedInt32Array([2, 2, 1, 5])
			app_weights = PackedInt32Array([2, 3, 4, 3])
			rule_weights = PackedInt32Array([3, 4, 3])
		"printer_beast":
			objective_weights = PackedInt32Array([5, 2, 3])
			mutator_weights = PackedInt32Array([2, 1, 6, 1])
			app_weights = PackedInt32Array([4, 2, 2, 3])
			rule_weights = PackedInt32Array([4, 3, 3])
		"broken_link":
			objective_weights = PackedInt32Array([3, 1, 6])
			mutator_weights = PackedInt32Array([1, 6, 2, 1])
			app_weights = PackedInt32Array([3, 4, 2, 2])
			rule_weights = PackedInt32Array([3, 4, 3])
		"lost_file":
			objective_weights = PackedInt32Array([6, 3, 1])
			mutator_weights = PackedInt32Array([6, 1, 1, 1])
			app_weights = PackedInt32Array([5, 2, 1, 2])
			rule_weights = PackedInt32Array([5, 2, 3])

	var selected_objective := _pick_weighted_index(objective_weights)
	var selected_mutator := _pick_weighted_index(mutator_weights)
	var selected_app := _pick_weighted_index(app_weights)
	var selected_rule := _pick_weighted_index(rule_weights)

	for _i in range(20):
		var candidate_objective := _pick_weighted_index(objective_weights)
		var candidate_mutator := _pick_weighted_index(mutator_weights)
		var candidate_app := _pick_weighted_index(app_weights)
		var candidate_rule := _pick_weighted_index(rule_weights)
		var candidate_sig := "%s|%s|%s|%s" % [
			objectives[candidate_objective],
			mutators[candidate_mutator],
			str((app_variants[candidate_app] as Dictionary).get("label", "runtime+net")),
			rules[candidate_rule]
		]
		var same_as_last := objectives[candidate_objective] == _last_objective_type and mutators[candidate_mutator] == _last_mutator_type
		if same_as_last:
			continue
		if _recent_variation_signatures.has(candidate_sig):
			continue
		selected_objective = candidate_objective
		selected_mutator = candidate_mutator
		selected_app = candidate_app
		selected_rule = candidate_rule
		break

	_objective_type = objectives[selected_objective]
	_mutator_type = mutators[selected_mutator]
	var app_variant := app_variants[selected_app] as Dictionary
	_current_app_variant_label = str(app_variant.get("label", "runtime+net"))
	_current_app_requirements = app_variant.get("requires", PackedStringArray(["runtime_shell", "net_daemon"]))
	_current_app_exact_inputs = int(app_variant.get("exact_inputs", 2))
	_rule_set_type = rules[selected_rule]
	_rule_blacklist_template = restricted_pool[randi_range(0, restricted_pool.size() - 1)]
	if _rule_set_type == RULE_RESTRICTED_ACCESS:
		var valid_blocked: PackedStringArray = PackedStringArray()
		for blocked in restricted_pool:
			if not _current_app_requirements.has(blocked):
				valid_blocked.append(blocked)
		if not valid_blocked.is_empty():
			_rule_blacklist_template = valid_blocked[randi_range(0, valid_blocked.size() - 1)]
	_rule_efficiency_max_nodes = 5 + randi_range(0, 2)
	_remember_variation_signature("%s|%s|%s|%s" % [_objective_type, _mutator_type, _current_app_variant_label, _rule_set_type])

	match _objective_type:
		OBJECTIVE_STABLE_NODES:
			_objective_target = 5
		OBJECTIVE_STABLE_LINKS:
			_objective_target = 4
		_:
			_objective_target = 0

	if _mutator_type == MUTATOR_MAX_LINKS:
		_mutator_link_cap = 6

	_last_objective_type = _objective_type
	_last_mutator_type = _mutator_type

func _objective_short_text() -> String:
	match _objective_type:
		OBJECTIVE_STABLE_NODES:
			return "Make %d GOOD nodes" % _objective_target
		OBJECTIVE_STABLE_LINKS:
			return "Make %d GOOD links" % _objective_target
		_:
			return "Kernel -> App (%s)" % _current_app_variant_label

func _mutator_short_text() -> String:
	match _mutator_type:
		MUTATOR_NO_DIRECT_KERNEL:
			return "No Kernel -> App shortcut"
		MUTATOR_MAX_LINKS:
			return "Max %d links" % _mutator_link_cap
		MUTATOR_ARM_UNSTABLE:
			return "ARM nodes always CLASH"
		_:
			return "Normal"

func _rule_set_short_text() -> String:
	match _rule_set_type:
		RULE_REDUNDANCY:
			return "Redundancy: 2 paths"
		RULE_RESTRICTED_ACCESS:
			var blocked: String = str(_templates.get(_rule_blacklist_template, {}).get("label", _rule_blacklist_template))
			return "Restricted: no %s" % blocked
		_:
			return "Efficiency: <= %d nodes" % _rule_efficiency_max_nodes

func _evaluate_rule_set() -> Dictionary:
	match _rule_set_type:
		RULE_REDUNDANCY:
			var paths := _count_edge_disjoint_green_paths(2)
			return {
				"met": paths >= 2,
				"current": paths,
				"target": 2,
				"label": "Redundancy"
			}
		RULE_RESTRICTED_ACCESS:
			var blocked_count := 0
			for node in _nodes.values():
				if bool(node.get("is_core", false)) or bool(node.get("is_application", false)):
					continue
				if str(node.get("template_id", "")) == _rule_blacklist_template:
					blocked_count += 1
			return {
				"met": blocked_count == 0,
				"current": blocked_count,
				"target": 0,
				"label": "Restricted"
			}
		_:
			var path_nodes := _find_any_shortest_path_nodes(_kernel_node_id, _application_node_id)
			var used_nodes := path_nodes.size()
			if used_nodes <= 0:
				used_nodes = 999
			return {
				"met": used_nodes <= _rule_efficiency_max_nodes,
				"current": used_nodes,
				"target": _rule_efficiency_max_nodes,
				"label": "Efficiency"
			}

func _count_edge_disjoint_green_paths(max_needed: int) -> int:
	var remaining: Array[Dictionary] = []
	for link in _connections:
		if int(link.get("state", LINK_BROKEN)) == LINK_STABLE:
			remaining.append(link.duplicate())

	var found := 0
	while found < max_needed:
		var path := _find_path_in_link_set(_kernel_node_id, _application_node_id, remaining)
		if path.is_empty():
			break
		found += 1
		var reduced: Array[Dictionary] = []
		for link in remaining:
			var from_id := int(link.get("from", -1))
			var to_id := int(link.get("to", -1))
			var consumed := false
			for i in range(path.size() - 1):
				if from_id == int(path[i]) and to_id == int(path[i + 1]):
					consumed = true
					break
			if not consumed:
				reduced.append(link)
		remaining = reduced

	return found

func _find_path_in_link_set(start_id: int, target_id: int, link_set: Array[Dictionary]) -> Array[int]:
	if start_id < 0 or target_id < 0:
		return []
	var adjacency := _build_adjacency_from_links(link_set, false)
	var queue: Array[int] = [start_id]
	var visited: Dictionary = {start_id: true}
	var parent: Dictionary = {}

	while not queue.is_empty():
		var current := int(queue.pop_front())
		if current == target_id:
			break
		for next_id_variant in adjacency.get(current, []):
			var next_id := int(next_id_variant)
			if visited.has(next_id):
				continue
			visited[next_id] = true
			parent[next_id] = current
			queue.append(next_id)

	if not visited.has(target_id):
		return []

	var path: Array[int] = [target_id]
	var cursor := target_id
	while cursor != start_id:
		cursor = int(parent.get(cursor, start_id))
		path.push_front(cursor)
	return path

func _is_objective_complete(_conflict_count: int) -> bool:
	var sub_progress := _get_subobjective_progress()
	if not bool(sub_progress.get("met", false)):
		return false

	if not bool(_evaluate_rule_set().get("met", false)):
		return false

	# Only path objective requires full Kernel -> App green route and preflight.
	if _objective_type == OBJECTIVE_PATH_TO_APP:
		if not _has_any_path(_kernel_node_id, _application_node_id):
			return false
		if not _is_app_connected_green():
			return false
		if _compute_preflight_progress() < 1.0:
			return false

	return true

func _has_any_path(start_id: int, target_id: int) -> bool:
	if start_id < 0 or target_id < 0:
		return false
	if not _nodes.has(start_id) or not _nodes.has(target_id):
		return false

	var adjacency := _build_adjacency_from_links(_connections, false)
	var visited: Dictionary = {}
	var stack: Array[int] = [start_id]

	while not stack.is_empty():
		var current := int(stack.pop_back())
		if current == target_id:
			return true
		if visited.has(current):
			continue
		visited[current] = true

		for next_id_variant in adjacency.get(current, []):
			var next_id := int(next_id_variant)
			if _nodes.has(next_id):
				stack.append(next_id)

	return false

func _find_any_shortest_path_nodes(start_id: int, target_id: int) -> Array[int]:
	if start_id < 0 or target_id < 0:
		return []
	if not _nodes.has(start_id) or not _nodes.has(target_id):
		return []

	var adjacency := _build_adjacency_from_links(_connections, false)
	var queue: Array[int] = [start_id]
	var visited: Dictionary = {start_id: true}
	var parent: Dictionary = {}

	while not queue.is_empty():
		var current := int(queue.pop_front())
		if current == target_id:
			break
		for next_id_variant in adjacency.get(current, []):
			var next_id := int(next_id_variant)
			if not _nodes.has(next_id) or visited.has(next_id):
				continue
			visited[next_id] = true
			parent[next_id] = current
			queue.append(next_id)

	if not visited.has(target_id):
		return []

	var path: Array[int] = [target_id]
	var cursor := target_id
	while cursor != start_id:
		cursor = int(parent.get(cursor, start_id))
		path.push_front(cursor)
	return path

func _get_link_state(from_id: int, to_id: int) -> int:
	for link in _connections:
		if int(link.get("from", -1)) == from_id and int(link.get("to", -1)) == to_id:
			return int(link.get("state", LINK_BROKEN))
	return LINK_BROKEN

func _compute_preflight_progress() -> float:
	if _kernel_node_id < 0 or _application_node_id < 0:
		return 0.0
	if not _nodes.has(_kernel_node_id) or not _nodes.has(_application_node_id):
		return 0.0

	var app_ctrl := _node_controls.get(_application_node_id) as Control
	var kernel_ctrl := _node_controls.get(_kernel_node_id) as Control
	if app_ctrl == null or kernel_ctrl == null:
		return 0.0

	var path_nodes := _find_any_shortest_path_nodes(_kernel_node_id, _application_node_id)
	if path_nodes.is_empty():
		var app_center := app_ctrl.position + app_ctrl.size * 0.5
		var kernel_center := kernel_ctrl.position + kernel_ctrl.size * 0.5
		var base_dist := maxf(1.0, kernel_center.distance_to(app_center))
		var best_dist := base_dist
		for node_id in _nodes.keys():
			var candidate := int(node_id)
			if not _has_any_path(_kernel_node_id, candidate):
				continue
			var ctrl := _node_controls.get(candidate) as Control
			if ctrl == null:
				continue
			var center := ctrl.position + ctrl.size * 0.5
			best_dist = minf(best_dist, center.distance_to(app_center))
		return clampf(1.0 - best_dist / base_dist, 0.0, 0.84)

	var total_links := path_nodes.size() - 1
	if total_links <= 0:
		return 1.0

	var stable_links := 0
	for i in range(total_links):
		if _get_link_state(path_nodes[i], path_nodes[i + 1]) == LINK_STABLE:
			stable_links += 1

	if stable_links >= total_links and _is_app_connected_green():
		return 1.0

	var ratio := float(stable_links) / float(total_links)
	return 0.85 + ratio * 0.14

func _build_preflight_bar(progress: float) -> String:
	var clamped := clampf(progress, 0.0, 1.0)
	var total_slots := 10
	var filled := int(round(clamped * total_slots))
	var bar := "["
	for i in range(total_slots):
		bar += "#" if i < filled else "."
	bar += "]"
	return bar

func _get_subobjective_progress() -> Dictionary:
	match _objective_type:
		OBJECTIVE_STABLE_NODES:
			var stable_count := 0
			for node in _nodes.values():
				var status := int(node.get("status", STATUS_BROKEN))
				if status == STATUS_STABLE or status == STATUS_CORE:
					stable_count += 1
			return {
				"current": stable_count,
				"target": _objective_target,
				"met": stable_count >= _objective_target
			}
		OBJECTIVE_STABLE_LINKS:
			var stable_links := 0
			for link in _connections:
				if int(link.get("state", LINK_BROKEN)) == LINK_STABLE:
					stable_links += 1
			return {
				"current": stable_links,
				"target": _objective_target,
				"met": stable_links >= _objective_target
			}
		_:
			var has_green := _is_app_connected_green()
			return {
				"current": 1 if has_green else 0,
				"target": 1,
				"met": has_green
			}

func _get_app_goal_status_payload() -> Dictionary:
	var has_physical := _has_any_path(_kernel_node_id, _application_node_id)
	var has_green := _is_app_connected_green()
	var sub_progress := _get_subobjective_progress()
	var rule_progress := _evaluate_rule_set()
	var app_reason := "Pending"
	if _nodes.has(_application_node_id):
		app_reason = str(_nodes[_application_node_id].get("reason", "Pending"))
	var current := int(sub_progress["current"])
	var target := int(sub_progress["target"])
	var sub_met: bool = sub_progress["met"]
	var rule_met: bool = bool(rule_progress.get("met", false))
	var pulse := 0.35 + 0.35 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))
	var signal_ok := _app_signal_strength >= SIGNAL_APP_MIN and _app_signal_strength <= SIGNAL_APP_MAX
	var non_path_objective_met := _objective_type != OBJECTIVE_PATH_TO_APP and sub_met and rule_met

	if non_path_objective_met:
		return {
			"color": Color(0.34, 1.0, 0.55),
			"meta_text": "STATUS: OBJECTIVE MET",
			"state_text": "READY TO INSTALL"
		}

	if _is_resolved or (has_green and sub_met and rule_met and signal_ok):
		return {
			"color": Color(0.34, 1.0, 0.55),
			"meta_text": "STATUS: STABLE %.0f%%" % _app_signal_strength,
			"state_text": "READY TO INSTALL"
		}

	if has_physical:
		var amber := Color(0.96, 0.8, 0.24)
		amber = amber.lerp(Color(0.72, 0.58, 0.14), pulse * 0.45)
		var signal_tag := "OK" if signal_ok else "BAD"
		return {
			"color": amber,
			"meta_text": "STATUS: LINKED %.0f%% (%s)" % [_app_signal_strength, signal_tag],
			"state_text": "%s | DEPS %d/%d | RULE %d/%d" % [app_reason, current, target, int(rule_progress.get("current", 0)), int(rule_progress.get("target", 0))]
		}

	var red := Color(0.9, 0.26, 0.22)
	red = red.lerp(Color(0.6, 0.2, 0.16), pulse * 0.45)
	return {
		"color": red,
		"meta_text": "STATUS: UNMOUNTED",
		"state_text": app_reason if app_reason != "Good" else "MISSING PATH"
	}

func _is_app_connected_green() -> bool:
	if _application_node_id < 0 or _kernel_node_id < 0:
		return false
	if not _nodes.has(_application_node_id):
		return false
	if int(_nodes[_application_node_id].get("status", STATUS_BROKEN)) != STATUS_STABLE:
		return false
	return _has_green_path(_kernel_node_id, _application_node_id)

func _pick_weighted_index(weights: PackedInt32Array) -> int:
	if weights.is_empty():
		return 0

	var total := 0
	for w in weights:
		total += maxi(0, int(w))

	if total <= 0:
		return 0

	var roll := randi_range(1, total)
	var acc := 0
	for i in range(weights.size()):
		acc += maxi(0, int(weights[i]))
		if roll <= acc:
			return i

	return weights.size() - 1

func _build_adjacency_from_links(link_set: Array, stable_only: bool) -> Dictionary:
	var adjacency: Dictionary = {}
	for link_variant in link_set:
		var link := link_variant as Dictionary
		if stable_only and int(link.get("state", LINK_BROKEN)) != LINK_STABLE:
			continue
		var from_id := int(link.get("from", -1))
		var to_id := int(link.get("to", -1))
		if from_id < 0 or to_id < 0:
			continue
		if not adjacency.has(from_id):
			adjacency[from_id] = []
		(adjacency[from_id] as Array).append(to_id)
	return adjacency

func _remember_variation_signature(signature: String) -> void:
	if signature == "":
		return
	_recent_variation_signatures.append(signature)
	while _recent_variation_signatures.size() > ANTI_REPEAT_VARIATION_HISTORY:
		_recent_variation_signatures.remove_at(0)

func _build_solution_signature() -> String:
	if _kernel_node_id < 0 or _application_node_id < 0:
		return ""
	if not _is_app_connected_green():
		return ""

	var path_nodes := _find_any_shortest_path_nodes(_kernel_node_id, _application_node_id)
	if path_nodes.size() < 2:
		return ""

	var chain: PackedStringArray = PackedStringArray()
	for node_id in path_nodes:
		if not _nodes.has(node_id):
			continue
		var node: Dictionary = _nodes[node_id]
		if bool(node.get("is_core", false)):
			chain.append("kernel")
		elif bool(node.get("is_application", false)):
			chain.append("app")
		else:
			chain.append(str(node.get("template_id", "unknown")))

	if chain.size() < 2:
		return ""

	var total_links := maxi(0, chain.size() - 1)
	var stable_links := 0
	for link in _connections:
		if int(link.get("state", LINK_BROKEN)) == LINK_STABLE:
			stable_links += 1

	return "%s|%s|shape:%s|green:%d/%d" % [
		_current_app_variant_label,
		_rule_set_type,
		">".join(chain),
		stable_links,
		total_links
	]

func _is_repeated_solution_pattern() -> bool:
	var signature := _build_solution_signature()
	if signature == "":
		return false
	return _recent_solution_signatures.has(signature)

func _remember_solution_signature() -> void:
	var signature := _build_solution_signature()
	if signature == "":
		return
	_recent_solution_signatures.append(signature)
	while _recent_solution_signatures.size() > ANTI_REPEAT_SOLUTION_HISTORY:
		_recent_solution_signatures.remove_at(0)
