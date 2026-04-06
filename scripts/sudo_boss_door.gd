extends Area3D

const DIALOGUE_CANCEL_LOCK_META_KEY := "dialogue_cancel_locked"

@export var required_command: String = "sudo unlock bossroom"
@export var token_flag: String = "sudo_token_driver_remnant"
@export var unlocked_flag: String = "deamon_depths_boss_door_unlocked"
@export var dialogue_resource_path: String = "res://dialogues/BossDoor.dialogue"
@export var terminal_ui_scene_path: String = "res://Scenes/combat/combat_terminal_ui.tscn"
@export var printer_boss_node_path: NodePath = NodePath("../../NPCS/Printer Boss")
@export var printer_intro_dialogue_path: String = "res://dialogues/PrinterBossIntro.dialogue"
@export var printer_intro_played_flag: String = "deamon_depths_printer_intro_played"
@export var nova_target_marker_path: NodePath = NodePath("Marker3D")
@export var nova_move_distance_x: float = 4.0
@export var nova_move_duration: float = 1.1

var _player_inside: bool = false
var _input_open: bool = false
var _dialog_open: bool = false
var _door_collision: CollisionShape3D = null

var _ui_layer: CanvasLayer = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _hint_label: Label = null
var _line_edit: LineEdit = null
var _dialogue_resource: Resource = null
var _printer_intro_dialogue_resource: Resource = null
var _terminal_layer: CanvasLayer = null
var _terminal_ui: Control = null
var _terminal_command_input: LineEdit = null
var _cutscene_running: bool = false

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_door_collision = get_node_or_null("BossRoomDoor") as CollisionShape3D
	if dialogue_resource_path != "" and ResourceLoader.exists(dialogue_resource_path):
		_dialogue_resource = ResourceLoader.load(dialogue_resource_path)
	if printer_intro_dialogue_path != "" and ResourceLoader.exists(printer_intro_dialogue_path):
		_printer_intro_dialogue_resource = ResourceLoader.load(printer_intro_dialogue_path)

	if _is_printer_intro_played():
		_set_printer_boss_visible(true)
	else:
		_set_printer_boss_visible(false)

	if _is_unlocked():
		_unlock_door_visuals()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		if InteractionManager.current_interactable == null or InteractionManager.current_interactable == self:
			InteractionManager.current_interactable = self

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		if InteractionManager.current_interactable == self:
			InteractionManager.current_interactable = null
		_close_command_prompt()

func get_interact_prompt() -> String:
	if _is_unlocked():
		return "Boss Door Open"
	if not _has_sudo_token():
		return "Inspect Door"
	if _input_open:
		return "Enter sudo command"
	return "Use sudo token"

func on_interact() -> void:
	if not _player_inside:
		return

	if _is_unlocked():
		if not _show_door_dialogue("already_open"):
			_open_info_dialog("ACCESS GRANTED", "The boss room door is already unlocked.")
		return

	if not _has_sudo_token():
		if not _show_door_dialogue("needs_sudo_token"):
			_open_info_dialog("ACCESS DENIED", "This door requires a sudo token from Driver Remnant.")
		return

	_open_command_prompt()

func _unhandled_input(event: InputEvent) -> void:
	if not _input_open and not _dialog_open:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_close_ui()
		get_viewport().set_input_as_handled()

func _open_command_prompt() -> void:
	if _input_open:
		return

	if _open_terminal_prompt():
		return

	_ensure_ui()
	if _ui_layer == null:
		return

	_input_open = true
	_dialog_open = true
	_ui_layer.visible = true
	if SceneManager:
		SceneManager.input_locked = true

	_title_label.text = "SUDO AUTH REQUIRED"
	_hint_label.text = "Type command: %s" % required_command
	_line_edit.editable = true
	_line_edit.visible = true
	_line_edit.text = ""
	_line_edit.grab_focus()

func _close_command_prompt() -> void:
	if not _input_open:
		return
	_close_ui()

func _open_terminal_prompt() -> bool:
	if terminal_ui_scene_path == "" or not ResourceLoader.exists(terminal_ui_scene_path):
		return false

	if not _ensure_terminal_ui():
		return false

	_input_open = true
	_dialog_open = true

	if _terminal_ui.has_method("open_combat_ui"):
		_terminal_ui.open_combat_ui()
	else:
		_terminal_ui.show()
		if SceneManager:
			SceneManager.input_locked = true

	_configure_boss_door_terminal_layout()

	var terminal_output: RichTextLabel = _terminal_ui.get_node_or_null("TerminalContainer/TerminalOutput") as RichTextLabel
	if terminal_output:
		terminal_output.clear()

	_print_terminal_line("[color=#66f266]DOOR-AUTH(1)                    LEARNIX                    DOOR-AUTH(1)[/color]\n\n")
	_print_terminal_line("[color=#66f266]NAME[/color]\n")
	_print_terminal_line("       boss_door_auth - elevated access terminal\n\n")
	_print_terminal_line("[color=#66f266]SYNOPSIS[/color]\n")
	_print_terminal_line("       sudo unlock bossroom\n")
	_print_terminal_line("       help\n")
	_print_terminal_line("       exit\n\n")
	_print_terminal_line("[color=#66f266]DESCRIPTION[/color]\n")
	_print_terminal_line("       Sudo token detected. Enter privileged command to disengage lock.\n\n")
	_print_terminal_line("[color=#f2e066]Type the sudo command to unlock the boss room door.[/color]\n")

	var mode_label: Label = _terminal_ui.get_node_or_null("StatusPanel/VBox/ModeLabel") as Label
	if mode_label:
		mode_label.text = "[DOOR AUTH]"

	var name_label: Label = _terminal_ui.get_node_or_null("StatusPanel/VBox/EnemyStatus/NameLabel") as Label
	if name_label:
		name_label.text = "Boss Room Door"

	if _terminal_command_input:
		_terminal_command_input.clear()
		_terminal_command_input.grab_focus()

	return true

func _ensure_terminal_ui() -> bool:
	if _terminal_ui and is_instance_valid(_terminal_ui):
		return true

	var packed := load(terminal_ui_scene_path) as PackedScene
	if packed == null:
		return false

	_terminal_layer = CanvasLayer.new()
	_terminal_layer.name = "BossDoorTerminalLayer"
	add_child(_terminal_layer)

	_terminal_ui = packed.instantiate() as Control
	if _terminal_ui == null:
		_terminal_layer.queue_free()
		_terminal_layer = null
		return false

	_terminal_layer.add_child(_terminal_ui)

	var command_input := _terminal_ui.get_node_or_null("TerminalContainer/InputContainer/CommandInput") as LineEdit
	var submit_btn := _terminal_ui.get_node_or_null("TerminalContainer/InputContainer/SubmitButton") as Button
	var exit_btn := _terminal_ui.get_node_or_null("TerminalContainer/InputContainer/ExitButton") as Button

	if command_input and command_input.text_submitted.is_connected(Callable(_terminal_ui, "_on_command_submitted")):
		command_input.text_submitted.disconnect(Callable(_terminal_ui, "_on_command_submitted"))
	if submit_btn and submit_btn.pressed.is_connected(Callable(_terminal_ui, "_on_submit_pressed")):
		submit_btn.pressed.disconnect(Callable(_terminal_ui, "_on_submit_pressed"))
	if exit_btn and exit_btn.pressed.is_connected(Callable(_terminal_ui, "_on_exit_pressed")):
		exit_btn.pressed.disconnect(Callable(_terminal_ui, "_on_exit_pressed"))

	if command_input:
		command_input.text_submitted.connect(_on_terminal_command_submitted)
	if submit_btn:
		submit_btn.pressed.connect(_on_terminal_submit_pressed)
	if exit_btn:
		exit_btn.pressed.connect(_on_terminal_exit_pressed)

	_terminal_command_input = command_input

	# Hide combat-specific status details to keep this focused on door auth.
	_configure_boss_door_terminal_layout()

	return true

func _configure_boss_door_terminal_layout() -> void:
	if _terminal_ui == null or not is_instance_valid(_terminal_ui):
		return

	var status_title := _terminal_ui.get_node_or_null("StatusPanel/VBox/StatusTitle") as Label
	if status_title:
		status_title.text = "═══ DOOR STATUS ═══"

	for node_path in [
		"StatusPanel/VBox/PlayerTitle",
		"StatusPanel/VBox/PlayerStatus",
		"StatusPanel/VBox/EnemyTitle",
		"StatusPanel/VBox/EnemyStatus",
		"StatusPanel/VBox/NpcVisualPanel",
		"StatusPanel/VBox/Spacer",
		"StatusPanel/VBox/Separator2",
		"StatusPanel/VBox/Separator3"
	]:
		var node := _terminal_ui.get_node_or_null(node_path)
		if node and node is CanvasItem:
			node.visible = false

func _on_terminal_submit_pressed() -> void:
	if _terminal_command_input:
		_on_terminal_command_submitted(_terminal_command_input.text)

func _on_terminal_exit_pressed() -> void:
	_close_ui()

func _on_terminal_command_submitted(raw_text: String) -> void:
	var original := raw_text.strip_edges()
	if original == "":
		return

	_print_terminal_line("[color=#80f280]$ %s[/color]\n" % original)

	var normalized := original.to_lower().replace("\t", " ")
	while normalized.find("  ") != -1:
		normalized = normalized.replace("  ", " ")

	if normalized == "help" or normalized == "?":
		_print_terminal_line("[color=#66f266]Valid command:[/color] sudo unlock bossroom\n")
		_print_terminal_line("[color=#aaaaaa]Type 'exit' to close terminal.[/color]\n")
	elif normalized == "exit" or normalized == "quit" or normalized == "close":
		_close_ui()
		return
	elif normalized == required_command:
		if SceneManager:
			SceneManager.set(unlocked_flag, true)
		_unlock_door_visuals()
		_print_terminal_line("[color=#66f266]AUTHENTICATION ACCEPTED. Door unlocked.[/color]\n")
		_close_ui()
		call_deferred("_play_printer_intro_sequence")
		return
	else:
		_print_terminal_line("[color=#e65959]Access denied. Unknown command.[/color]\n")
		_print_terminal_line("[color=#f2e066]Hint: type 'help'[/color]\n")

	if _terminal_command_input:
		_terminal_command_input.clear()
		_terminal_command_input.grab_focus()

func _print_terminal_line(text: String) -> void:
	if _terminal_ui and _terminal_ui.has_method("_print_terminal"):
		_terminal_ui._print_terminal(text)

func _open_info_dialog(title: String, message: String) -> void:
	_ensure_ui()
	if _ui_layer == null:
		return

	_dialog_open = true
	_input_open = false
	_ui_layer.visible = true
	if SceneManager:
		SceneManager.input_locked = true

	_title_label.text = title
	_hint_label.text = "%s\n(Press Esc to close)" % message
	_line_edit.text = ""
	_line_edit.visible = false
	_line_edit.editable = false

func _close_ui() -> void:
	if not _dialog_open and not _input_open:
		return

	_dialog_open = false
	_input_open = false

	if _terminal_ui and is_instance_valid(_terminal_ui):
		if _terminal_ui.has_method("close_combat_ui"):
			_terminal_ui.close_combat_ui()
		else:
			_terminal_ui.hide()
	if _terminal_layer and is_instance_valid(_terminal_layer):
		_terminal_layer.visible = false

	if _ui_layer:
		_ui_layer.visible = false

	if SceneManager:
		SceneManager.input_locked = false

func _ensure_ui() -> void:
	if _ui_layer and is_instance_valid(_ui_layer):
		return

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "BossDoorPrompt"
	add_child(_ui_layer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(520, 140)
	center.add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_hint_label)

	_line_edit = LineEdit.new()
	_line_edit.placeholder_text = "sudo ..."
	_line_edit.text_submitted.connect(_on_command_submitted)
	vb.add_child(_line_edit)

func _on_command_submitted(raw_text: String) -> void:
	var normalized := raw_text.strip_edges().to_lower().replace("\t", " ")
	while normalized.find("  ") != -1:
		normalized = normalized.replace("  ", " ")

	if normalized == required_command:
		if SceneManager:
			SceneManager.set(unlocked_flag, true)
		_unlock_door_visuals()
		print("[BossDoor] Sudo command accepted. Door unlocked.")
		_close_command_prompt()
		call_deferred("_play_printer_intro_sequence")
	else:
		_hint_label.text = "Access denied. Expected: %s" % required_command
		_line_edit.text = ""
		_line_edit.grab_focus()

func _play_printer_intro_sequence() -> void:
	if _cutscene_running:
		return
	_cutscene_running = true

	if _is_printer_intro_played():
		_set_printer_boss_visible(true)
		_start_printer_boss_puzzle()
		_cutscene_running = false
		return

	if SceneManager:
		SceneManager.input_locked = true

	await get_tree().create_timer(0.15).timeout
	await _move_nova_into_boss_room()

	_set_printer_boss_visible(true)

	if _show_printer_intro_dialogue():
		var dm = get_tree().root.get_node_or_null("DialogueManager")
		if dm:
			await dm.dialogue_ended
		if SceneManager and SceneManager.has_meta(DIALOGUE_CANCEL_LOCK_META_KEY):
			SceneManager.set_meta(DIALOGUE_CANCEL_LOCK_META_KEY, false)

	if SceneManager:
		SceneManager.set(printer_intro_played_flag, true)
		SceneManager.input_locked = false

	_start_printer_boss_puzzle()
	_cutscene_running = false

func _move_nova_into_boss_room() -> void:
	var player = _get_player_node()
	if player == null:
		return

	var start_pos: Vector3 = player.global_position
	var marker := get_node_or_null(nova_target_marker_path) as Marker3D
	var target_pos := start_pos + Vector3(nova_move_distance_x, 0, 0)
	if marker:
		# Preserve the player's Y so they don't sink into the floor
		target_pos = Vector3(marker.global_position.x, start_pos.y, marker.global_position.z)

	var tween := create_tween()
	tween.tween_property(player, "global_position", target_pos, nova_move_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

func _show_printer_intro_dialogue() -> bool:
	if _printer_intro_dialogue_resource == null:
		return false
	var dm = get_tree().root.get_node_or_null("DialogueManager")
	if dm == null:
		return false
	if SceneManager:
		SceneManager.set_meta(DIALOGUE_CANCEL_LOCK_META_KEY, true)
	dm.show_dialogue_balloon(_printer_intro_dialogue_resource, "start", [self])
	return true

func _start_printer_boss_puzzle() -> void:
	var printer_boss = _get_printer_boss_node()
	if printer_boss and printer_boss.has_method("start_puzzle"):
		printer_boss.start_puzzle()

func _get_printer_boss_node() -> Node:
	if printer_boss_node_path != NodePath():
		return get_node_or_null(printer_boss_node_path)
	return get_node_or_null("../../NPCS/Printer Boss")

func _set_printer_boss_visible(should_show: bool) -> void:
	var printer_boss = _get_printer_boss_node()
	if printer_boss == null:
		return
	if printer_boss is Node3D:
		printer_boss.visible = should_show

	var interact_area: Area3D = printer_boss.get_node_or_null("InteractArea") as Area3D
	if interact_area:
		interact_area.monitoring = should_show
		interact_area.monitorable = should_show

func _get_player_node() -> CharacterBody3D:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is CharacterBody3D:
		return players[0] as CharacterBody3D
	return null

func _is_printer_intro_played() -> bool:
	if not SceneManager:
		return false
	return bool(SceneManager.get(printer_intro_played_flag))

func _show_door_dialogue(start_title: String) -> bool:
	if _dialogue_resource == null:
		return false
	var dm = get_tree().root.get_node_or_null("DialogueManager")
	if dm == null:
		return false
	dm.show_dialogue_balloon(_dialogue_resource, start_title, [self])
	return true

func _unlock_door_visuals() -> void:
	if _door_collision:
		_door_collision.disabled = true

func _has_sudo_token() -> bool:
	if not SceneManager:
		return false
	return bool(SceneManager.get(token_flag))

func _is_unlocked() -> bool:
	if not SceneManager:
		return false
	return bool(SceneManager.get(unlocked_flag))
