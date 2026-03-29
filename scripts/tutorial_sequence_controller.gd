extends Node

const DIALOGUE_PATH := "res://dialogues/TutorialFlow.dialogue"
const FALLBACK_HAMLET_SCENE_PATH := "res://Scenes/Levels/fallback_hamlet.tscn"
const FALLBACK_HAMLET_SPAWN_PATH := "Fallback_Hamlet_Final/first_spawn"
const HUD_NODE_PATH := "UI/MainHUD"
const MOVE_ACTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]
const REQUIRED_TERMINAL_COMMANDS := ["pwd", "ls", "cd"]
const TUTORIAL_CAMERA_DISTANCE := 4.6
const TUTORIAL_CAMERA_HEIGHT := 2.4
const TUTORIAL_CAMERA_FOV := 70.0
const MAIN_CAMERA_DISTANCE := 3.0
const MAIN_CAMERA_HEIGHT := 2.0
const MAIN_CAMERA_FOV := 75.0
const TUTORIAL_TUX_NODE_NAME := "Tux_tutorial"
const PLAYER_FOLLOW_TUX_NODE_NAME := "Tux"
const TUTORIAL_TUX_ACTOR_SCRIPT_PATH := "res://scripts/tutorial_tux_actor.gd"

var _player: CharacterBody3D = null
var _dialogue_resource: Resource = null
var _dialogue_manager: Node = null
var _hud: Control = null
var _tutorial_canvas: CanvasLayer = null
var _tutorial_panel: PanelContainer = null
var _tutorial_title: Label = null
var _tutorial_body: Label = null
var _tutorial_footer: Label = null
var _hint_dismissible: bool = false
var _tux: Node3D = null
var _using_tutorial_tux_actor: bool = false
var _beacon_root: Node3D = null
var _beacon_position: Vector3 = Vector3.ZERO
var _seen_move_actions: Dictionary = {}
var _required_terminal_commands: Dictionary = {}
var _tutorial_running: bool = false
var _last_response_text: String = ""
var _last_viewport_size: Vector2 = Vector2.ZERO
var _last_terminal_visible: bool = false
var _force_hide_hud: bool = false

func setup(active_player: CharacterBody3D) -> void:
	_player = active_player

func _ready() -> void:
	call_deferred("_run_tutorial")

func _process(_delta: float) -> void:
	if _force_hide_hud:
		_resolve_hud()
		if _hud != null and is_instance_valid(_hud):
			_hud.visible = false

	if _tutorial_panel == null or not is_instance_valid(_tutorial_panel):
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var terminal_visible := _is_terminal_open()
	if viewport_size.is_equal_approx(_last_viewport_size) and terminal_visible == _last_terminal_visible:
		return

	_last_viewport_size = viewport_size
	_last_terminal_visible = terminal_visible
	_apply_responsive_tutorial_layout()

func _run_tutorial() -> void:
	if _tutorial_running:
		return
	_tutorial_running = true

	_dialogue_resource = load(DIALOGUE_PATH)
	_dialogue_manager = get_tree().root.get_node_or_null("DialogueManager")
	_resolve_hud()
	_ensure_tutorial_canvas()
	if _dialogue_resource == null:
		push_warning("Tutorial dialogue not found: " + DIALOGUE_PATH)
		_tutorial_running = false
		return

	if _player == null:
		_player = _find_player()
	if _player == null:
		push_warning("Tutorial controller could not find player.")
		_tutorial_running = false
		return
	_reset_camera_for_tutorial()
	_hide_player_companion_tux()
	_resolve_existing_tux()

	_force_hide_hud = true
	_hide_hud()
	_lock_input(true)
	_show_hint_card(
		"Tux Boot Sequence",
		"Welcome to Linuxia onboarding.\nFollow each checkpoint and keep your eyes on prompts.",
		"Press [E] to continue in dialogue"
	)
	await _show_dialogue("wake_up", [self])
	await _section_pause(0.2)

	_lock_input(false)
	_show_wasd_canvas()
	await _movement_checkpoint()
	_hide_hint_card()

	_lock_input(true)
	_enable_tux_follow(true)
	await _show_dialogue("movement_success", [self])
	await _section_pause(0.2)

	_lock_input(false)
	_spawn_interact_beacon()
	_show_interact_canvas()
	await _show_dialogue("interact_prompt", [self])
	await _interact_checkpoint()
	_hide_hint_card()
	_cleanup_beacon()

	_lock_input(true)
	_show_hud_guide_canvas()
	_show_hud()
	await _show_dialogue("hud_unlock", [self])
	await _section_pause(0.25)
	_hide_hint_card()

	_lock_input(false)
	await _terminal_checkpoint()

	_lock_input(true)
	var ready_response := await _show_dialogue("linuxia_ready", [self], true)
	var should_teleport := _response_indicates_ready(ready_response)
	_lock_input(false)
	if should_teleport:
		_start_main_gameplay()
	else:
		await _roam_until_player_ready()
		_start_main_gameplay()
	_tutorial_running = false

func _movement_checkpoint() -> void:
	_seen_move_actions.clear()
	for action_name in MOVE_ACTIONS:
		_seen_move_actions[action_name] = false

	while not _all_move_actions_seen():
		for action_name in MOVE_ACTIONS:
			if Input.is_action_just_pressed(action_name):
				_seen_move_actions[action_name] = true
		await get_tree().process_frame

func _all_move_actions_seen() -> bool:
	for action_name in MOVE_ACTIONS:
		if not bool(_seen_move_actions.get(action_name, false)):
			return false
	return true

func _spawn_interact_beacon() -> void:
	if _beacon_root != null and is_instance_valid(_beacon_root):
		return

	_beacon_root = Node3D.new()
	_beacon_root.name = "TutorialInteractBeacon"
	add_child(_beacon_root)

	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.28
	mesh.bottom_radius = 0.35
	mesh.height = 0.8
	mesh_instance.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.98, 0.72, 0.12, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.6, 0.1, 1.0)
	mat.emission_energy_multiplier = 1.2
	mesh_instance.material_override = mat
	_beacon_root.add_child(mesh_instance)

	var label := Label3D.new()
	label.text = "Press E"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 1.1, 0.0)
	_beacon_root.add_child(label)

	var base_pos := _player.global_position
	if _using_tutorial_tux_actor and _tux != null and is_instance_valid(_tux):
		base_pos = _tux.global_position
	_beacon_position = Vector3(base_pos.x + 1.0, base_pos.y, base_pos.z)
	_beacon_root.global_position = _beacon_position
	_place_tux_for_interaction()

func _interact_checkpoint() -> void:
	while true:
		if _player == null:
			_player = _find_player()
		if _player == null:
			await get_tree().process_frame
			continue

		var close_enough := _player.global_position.distance_to(_beacon_position) <= 2.4
		if close_enough and Input.is_action_just_pressed("interact"):
			break
		await get_tree().process_frame

	await _show_dialogue("interact_success", [self])

func _terminal_checkpoint() -> void:
	_required_terminal_commands.clear()
	for command_name in REQUIRED_TERMINAL_COMMANDS:
		_required_terminal_commands[command_name] = false

	await _show_dialogue("terminal_objective", [self])
	_show_terminal_objective_canvas()

	while _hud == null or not _hud.has_signal("terminal_command_executed"):
		_resolve_hud()
		await get_tree().process_frame

	var callback := Callable(self, "_on_terminal_command_executed")
	if not _hud.is_connected("terminal_command_executed", callback):
		_hud.connect("terminal_command_executed", callback)

	while not _all_terminal_commands_seen():
		await get_tree().process_frame

	if _hud.is_connected("terminal_command_executed", callback):
		_hud.disconnect("terminal_command_executed", callback)

	await _show_dialogue("terminal_complete", [self])
	await _section_pause(0.2)
	_hide_hint_card()

func _on_terminal_command_executed(command: String, args: Array) -> void:
	var normalized := command.to_lower()
	match normalized:
		"pwd":
			_required_terminal_commands["pwd"] = true
		"ls", "dir":
			_required_terminal_commands["ls"] = true
		"cat":
			if args.size() > 0:
				_required_terminal_commands["cat"] = true
	_update_terminal_objective_canvas()

func _all_terminal_commands_seen() -> bool:
	for command_name in REQUIRED_TERMINAL_COMMANDS:
		if not bool(_required_terminal_commands.get(command_name, false)):
			return false
	return true

func _show_dialogue(start_title: String, context_args: Array = [], track_response: bool = false) -> String:
	if _dialogue_manager == null or _dialogue_resource == null:
		return ""
	if not _dialogue_manager.has_method("show_dialogue_balloon"):
		return ""

	_close_terminal_if_open()
	_last_response_text = ""
	var balloon : Variant = _dialogue_manager.show_dialogue_balloon(_dialogue_resource, start_title, context_args)
	_adjust_dialogue_balloon_layout(balloon)
	var responses_menu := _find_response_menu(balloon)
	if track_response and responses_menu != null and responses_menu.has_signal("response_selected"):
		var response_callback := Callable(self, "_on_dialogue_response_selected")
		if not responses_menu.is_connected("response_selected", response_callback):
			responses_menu.connect("response_selected", response_callback)

	if _dialogue_manager.has_signal("dialogue_ended"):
		await _dialogue_manager.dialogue_ended

	if track_response and responses_menu != null:
		var response_callback := Callable(self, "_on_dialogue_response_selected")
		if responses_menu.is_connected("response_selected", response_callback):
			responses_menu.disconnect("response_selected", response_callback)

	return _last_response_text

func _on_dialogue_response_selected(response: Variant) -> void:
	if response == null:
		return
	if response is Dictionary:
		_last_response_text = String((response as Dictionary).get("text", ""))
		return
	if response is Object:
		_last_response_text = String((response as Object).get("text"))
		return
	_last_response_text = str(response)

func _find_response_menu(balloon: Node) -> Control:
	if balloon == null or not is_instance_valid(balloon):
		return null
	var menu := balloon.find_child("ResponsesMenu", true, false)
	if menu is Control:
		return menu as Control
	return null

func _response_indicates_ready(response_text: String) -> bool:
	var normalized := response_text.to_lower()
	if normalized.contains("not yet"):
		return false
	if normalized.contains("still need"):
		return false
	if normalized.contains("ready"):
		return true
	if normalized.contains("let's go") or normalized.contains("lets go"):
		return true
	return false

func _wait_for_tux_ready_interact() -> void:
	while true:
		if _player == null:
			_player = _find_player()
		if _tux == null or not is_instance_valid(_tux):
			_resolve_existing_tux()
		if _player != null and _tux != null and is_instance_valid(_tux):
			var close_to_tux := _player.global_position.distance_to(_tux.global_position) <= 2.6
			if close_to_tux and Input.is_action_just_pressed("interact"):
				_hide_hint_card()
				return
		await get_tree().process_frame

func _roam_until_player_ready() -> void:
	while true:
		_show_hint_card(
			"Roam Mode Enabled",
			"Explore first. You will not be teleported automatically.\nReturn to Tux and press [E] to confirm when ready.",
			"Click this card to hide it while exploring",
			true
		)
		await _wait_for_tux_ready_interact()
		_lock_input(true)
		var response := await _show_dialogue("linuxia_ready", [self], true)
		_lock_input(false)
		if _response_indicates_ready(response):
			return

func _adjust_dialogue_balloon_layout(balloon: Variant) -> void:
	if not (balloon is Node):
		return
	var balloon_node := balloon as Node
	var root_control := balloon_node.find_child("Balloon", true, false)
	if not (root_control is Control):
		return
	var margin := (root_control as Control).get_node_or_null("MarginContainer")
	if margin is MarginContainer:
		var container := margin as MarginContainer
		container.offset_top = -286.0

func _close_terminal_if_open() -> void:
	_resolve_hud()
	if _hud == null:
		return
	if _hud.has_method("_close_terminal"):
		_hud.call("_close_terminal")
		return
	var terminal_panel := _hud.get_node_or_null("TerminalPanel")
	if terminal_panel is Control:
		(terminal_panel as Control).visible = false

func _section_pause(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _resolve_hud() -> void:
	if _hud != null and is_instance_valid(_hud):
		return

	var scene_root := get_tree().current_scene
	if scene_root != null:
		_hud = scene_root.get_node_or_null(HUD_NODE_PATH) as Control
		if _hud == null:
			var found := scene_root.find_child("MainHUD", true, false)
			if found is Control:
				_hud = found as Control

func _ensure_tutorial_canvas() -> void:
	if _tutorial_canvas != null and is_instance_valid(_tutorial_canvas):
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	_tutorial_canvas = CanvasLayer.new()
	_tutorial_canvas.name = "TutorialCanvas"
	_tutorial_canvas.layer = 30
	scene_root.add_child(_tutorial_canvas)

	_tutorial_panel = PanelContainer.new()
	_tutorial_panel.visible = false
	_tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _tutorial_panel.gui_input.is_connected(_on_tutorial_panel_gui_input):
		_tutorial_panel.gui_input.connect(_on_tutorial_panel_gui_input)
	_tutorial_canvas.add_child(_tutorial_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.13, 0.17, 0.95)
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.94, 0.77, 0.33, 1.0)
	panel_style.shadow_size = 10
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	_tutorial_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 14)
	_tutorial_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_tutorial_title = Label.new()
	_tutorial_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_title.add_theme_font_size_override("font_size", 26)
	_tutorial_title.add_theme_color_override("font_color", Color(0.98, 0.92, 0.76, 1.0))
	vbox.add_child(_tutorial_title)

	_tutorial_body = Label.new()
	_tutorial_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_body.add_theme_font_size_override("font_size", 17)
	_tutorial_body.add_theme_color_override("font_color", Color(0.88, 0.93, 0.97, 1.0))
	vbox.add_child(_tutorial_body)

	_tutorial_footer = Label.new()
	_tutorial_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_footer.add_theme_font_size_override("font_size", 14)
	_tutorial_footer.add_theme_color_override("font_color", Color(0.97, 0.84, 0.45, 1.0))
	vbox.add_child(_tutorial_footer)

	_apply_responsive_tutorial_layout()

func _show_hint_card(title: String, body: String, footer: String = "", dismissible: bool = false) -> void:
	_ensure_tutorial_canvas()
	if _tutorial_panel == null:
		return
	_hint_dismissible = dismissible
	_tutorial_panel.mouse_filter = Control.MOUSE_FILTER_STOP if dismissible else Control.MOUSE_FILTER_IGNORE
	_tutorial_title.text = title
	_tutorial_body.text = body
	_tutorial_footer.text = footer
	_tutorial_panel.visible = true

func _hide_hint_card() -> void:
	if _tutorial_panel != null and is_instance_valid(_tutorial_panel):
		_tutorial_panel.visible = false
	_hint_dismissible = false
	if _tutorial_panel != null:
		_tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_tutorial_panel_gui_input(event: InputEvent) -> void:
	if not _hint_dismissible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_hint_card()
		get_viewport().set_input_as_handled()

func _show_wasd_canvas() -> void:
	_show_hint_card(
		"Movement Checkpoint",
		"Use WASD to move in all four directions.\n\n  [W]\n[A] [S] [D]",
		"Finish all directions to continue"
	)

func _show_interact_canvas() -> void:
	_show_hint_card(
		"Talk To Tux",
		"Move to Tux and the glowing marker, then press [E] to interact.",
		"Action key: E"
	)

func _show_hud_guide_canvas() -> void:
	_show_hint_card(
		"HUD Unlocked",
		"Bottom-right quick menu:\nFILE icon = inventory/docs\nTERMINAL icon = terminal\nTUX icon = mission help",
		"Use these throughout Linuxia"
	)

func _show_terminal_objective_canvas() -> void:
	_update_terminal_objective_canvas()

func _update_terminal_objective_canvas() -> void:
	var pwd_done := "[ ]"
	var ls_done := "[ ]"
	var cat_done := "[ ]"
	if bool(_required_terminal_commands.get("pwd", false)):
		pwd_done = "[x]"
	if bool(_required_terminal_commands.get("ls", false)):
		ls_done = "[x]"
	if bool(_required_terminal_commands.get("cd", false)):
		cat_done = "[x]"

	_show_hint_card(
		"Terminal Objective",
		pwd_done + " pwd\n" + ls_done + " ls\n" + cat_done + " cat <file_name>",
		"Open TERMINAL and complete all commands"
	)

func _hide_hud() -> void:
	_resolve_hud()
	if _hud:
		_hud.visible = false

func _show_hud() -> void:
	_force_hide_hud = false
	_resolve_hud()
	if _hud:
		_hud.visible = true

func _lock_input(locked: bool) -> void:
	if SceneManager:
		SceneManager.input_locked = locked
	if locked and _player:
		_player.velocity = Vector3.ZERO

func _resolve_existing_tux() -> void:
	if _tux != null and is_instance_valid(_tux):
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var tutorial_tux := scene_root.find_child(TUTORIAL_TUX_NODE_NAME, true, false)
	if tutorial_tux is Node3D:
		_tux = tutorial_tux as Node3D
		_using_tutorial_tux_actor = true
		_configure_tutorial_tux_actor(_tux)
		return

	for candidate in scene_root.find_children("*", "Node3D", true, false):
		if not (candidate is Node3D):
			continue
		var node := candidate as Node3D
		if not node.name.to_lower().contains("tux"):
			continue
		if _player != null and _player.is_ancestor_of(node):
			continue
		_tux = node
		_using_tutorial_tux_actor = false
		_enable_tux_follow(false)
		return

	push_warning("Tutorial controller could not find an existing scene Tux.")

func _hide_player_companion_tux() -> void:
	if _player == null:
		return

	var player_root := _player.get_parent()
	if player_root != null:
		var sibling_tux := player_root.find_child(PLAYER_FOLLOW_TUX_NODE_NAME, true, false)
		if sibling_tux is Node3D:
			_hide_tux_node(sibling_tux as Node3D)

	for child in _player.find_children("*", "Node3D", true, false):
		if not (child is Node3D):
			continue
		var node := child as Node3D
		if not node.name.to_lower().contains("tux"):
			continue
		_hide_tux_node(node)

func _hide_tux_node(node: Node3D) -> void:
	node.visible = false
	node.set_process(false)
	node.set_physics_process(false)
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0

func _configure_tutorial_tux_actor(node: Node3D) -> void:
	if node == null:
		return
	_set_non_collidable_recursive(node)

	if node is CharacterBody3D and node.get_script() == null:
		var actor_script := load(TUTORIAL_TUX_ACTOR_SCRIPT_PATH)
		if actor_script is Script:
			(node as CharacterBody3D).set_script(actor_script)

	if node.has_method("set_follow_enabled"):
		node.call("set_follow_enabled", false)

	var sprite_node := node.get_node_or_null("AnimatedSprite3D")
	if not (sprite_node is AnimatedSprite3D):
		var sprite_candidates := node.find_children("*", "AnimatedSprite3D", true, false)
		if not sprite_candidates.is_empty():
			sprite_node = sprite_candidates[0]
	if sprite_node is AnimatedSprite3D:
		var sprite := sprite_node as AnimatedSprite3D
		sprite.visible = true
		sprite.play("default")

func _set_non_collidable_recursive(root: Node) -> void:
	if root == null:
		return

	if root is CollisionObject3D:
		var collision_node := root as CollisionObject3D
		collision_node.collision_layer = 0
		collision_node.collision_mask = 0

	if root is CharacterBody3D:
		var body := root as CharacterBody3D
		body.collision_layer = 0
		body.collision_mask = 0

	for child in root.get_children():
		if child is Node:
			_set_non_collidable_recursive(child as Node)

func _reset_camera_for_tutorial() -> void:
	if _player == null:
		return

	var player_camera := _player.get_node_or_null("Camera3D")
	if not (player_camera is Camera3D):
		return

	var cam := player_camera as Camera3D
	cam.current = true
	cam.fov = TUTORIAL_CAMERA_FOV
	var camera_script : Variant = cam.get_script()
	if camera_script is Script and String((camera_script as Script).resource_path).ends_with("camera_main.gd"):
		cam.set("distance_horizontal", TUTORIAL_CAMERA_DISTANCE)
		cam.set("height_offset", TUTORIAL_CAMERA_HEIGHT)
		cam.set("smooth_speed", maxf(float(cam.get("smooth_speed")), 8.0))
	_sync_dialogue_zoom_baseline(TUTORIAL_CAMERA_FOV)

func _apply_responsive_tutorial_layout() -> void:
	if _tutorial_panel == null:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var terminal_open := _is_terminal_open()
	var width_ratio := 0.56
	var height_ratio := 0.28
	if terminal_open:
		width_ratio = 0.44
		height_ratio = 0.22

	var panel_width := clampf(viewport_size.x * width_ratio, 380.0, 860.0)
	var panel_height := clampf(viewport_size.y * height_ratio, 150.0, 300.0)
	_tutorial_panel.anchor_left = 0.5
	_tutorial_panel.anchor_right = 0.5
	_tutorial_panel.offset_left = -panel_width * 0.5
	_tutorial_panel.offset_right = panel_width * 0.5
	_tutorial_panel.offset_top = 16.0
	_tutorial_panel.offset_bottom = 16.0 + panel_height

	var title_size := int(clampf(viewport_size.y * 0.042, 20.0, 34.0))
	var body_size := int(clampf(viewport_size.y * 0.028, 14.0, 22.0))
	var footer_size := int(clampf(viewport_size.y * 0.022, 12.0, 18.0))
	_tutorial_title.add_theme_font_size_override("font_size", title_size)
	_tutorial_body.add_theme_font_size_override("font_size", body_size)
	_tutorial_footer.add_theme_font_size_override("font_size", footer_size)

func _is_terminal_open() -> bool:
	_resolve_hud()
	if _hud == null:
		return false
	var terminal_node := _hud.get_node_or_null("TerminalPanel")
	if terminal_node is Control:
		return (terminal_node as Control).visible
	return false

func _place_tux_for_interaction() -> void:
	if _tux == null or _player == null:
		return
	if _using_tutorial_tux_actor:
		return
	_enable_tux_follow(false)
	var target := _beacon_position + Vector3(-1.15, 0.0, 0.9)
	_tux.global_position = target

func _enable_tux_follow(enabled: bool) -> void:
	if _tux == null:
		return
	if _using_tutorial_tux_actor:
		if _tux.has_method("set_follow_enabled"):
			_tux.call("set_follow_enabled", false)
		return
	_tux.set_physics_process(enabled)
	_tux.set_process(enabled)

func _cleanup_beacon() -> void:
	if _beacon_root and is_instance_valid(_beacon_root):
		_beacon_root.queue_free()
	_beacon_root = null
	_enable_tux_follow(true)

func _start_main_gameplay() -> void:
	_hide_hint_card()
	call_deferred("_transition_to_main_gameplay")

func _transition_to_main_gameplay() -> void:
	await get_tree().process_frame
	_reset_camera_after_tutorial()
	if SceneManager and SceneManager.has_method("teleport_to_scene"):
		SceneManager.call_deferred("teleport_to_scene", FALLBACK_HAMLET_SCENE_PATH, FALLBACK_HAMLET_SPAWN_PATH, 0.15)
		return
	get_tree().change_scene_to_file(FALLBACK_HAMLET_SCENE_PATH)

func _reset_camera_after_tutorial() -> void:
	if _player == null:
		return
	var player_camera := _player.get_node_or_null("Camera3D")
	if not (player_camera is Camera3D):
		return
	var cam := player_camera as Camera3D
	cam.current = true
	cam.fov = MAIN_CAMERA_FOV
	var camera_script : Variant = cam.get_script()
	if camera_script is Script and String((camera_script as Script).resource_path).ends_with("camera_main.gd"):
		cam.set("distance_horizontal", MAIN_CAMERA_DISTANCE)
		cam.set("height_offset", MAIN_CAMERA_HEIGHT)
		cam.set("smooth_speed", maxf(float(cam.get("smooth_speed")), 8.0))
	_sync_dialogue_zoom_baseline(MAIN_CAMERA_FOV)

func _sync_dialogue_zoom_baseline(fov_value: float) -> void:
	var interaction_manager := get_tree().root.get_node_or_null("InteractionManager")
	if interaction_manager and interaction_manager.has_method("set_camera_fov_baseline"):
		interaction_manager.call("set_camera_fov_baseline", fov_value)

func _find_player() -> CharacterBody3D:
	var found = get_tree().get_first_node_in_group("player")
	if found and found is CharacterBody3D:
		return found as CharacterBody3D
	return null
