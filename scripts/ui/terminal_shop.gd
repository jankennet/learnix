class_name TerminalShop
extends Control

@onready var data_bits_label: Label = $Backdrop/ShopWindow/Margin/VRoot/HeaderRow/DataBitsLabel
@onready var close_button: Button = $Backdrop/ShopWindow/Margin/VRoot/HeaderRow/CloseButton
@onready var body_row: HSplitContainer = $Backdrop/ShopWindow/Margin/VRoot/BodyRow
@onready var skills_network: Control = $Backdrop/ShopWindow/Margin/VRoot/BodyRow/SkillsMenu/SkillsNetwork
@onready var skills_list: VBoxContainer = get_node_or_null("Backdrop/ShopWindow/Margin/VRoot/BodyRow/SkillsMenu/SkillsScroll/SkillsList")
@onready var core_hub: PanelContainer = $Backdrop/ShopWindow/Margin/VRoot/BodyRow/SkillsMenu/SkillsNetwork/CoreHub
@onready var cli_history_card: PanelContainer = $Backdrop/ShopWindow/Margin/VRoot/BodyRow/SkillsMenu/SkillsNetwork/CLI_HISTORY
@onready var teleport_card: PanelContainer = $Backdrop/ShopWindow/Margin/VRoot/BodyRow/SkillsMenu/SkillsNetwork/TELEPORT
@onready var file_explorer_card: PanelContainer = $Backdrop/ShopWindow/Margin/VRoot/BodyRow/SkillsMenu/SkillsNetwork/FILE_EXPLORER
@onready var connection_a: Line2D = $Backdrop/ShopWindow/Margin/VRoot/BodyRow/SkillsMenu/SkillsNetwork/ConnectionA
@onready var connection_b: Line2D = $Backdrop/ShopWindow/Margin/VRoot/BodyRow/SkillsMenu/SkillsNetwork/ConnectionB
@onready var connection_c: Line2D = $Backdrop/ShopWindow/Margin/VRoot/BodyRow/SkillsMenu/SkillsNetwork/ConnectionC
@onready var cli_history_status: Label = get_node_or_null("Backdrop/ShopWindow/Margin/VRoot/BodyRow/SkillsMenu/SkillsNetwork/CLI_HISTORY/Content/Status")
@onready var teleport_status: Label = get_node_or_null("Backdrop/ShopWindow/Margin/VRoot/BodyRow/SkillsMenu/SkillsNetwork/TELEPORT/Content/Status")
@onready var file_explorer_status: Label = get_node_or_null("Backdrop/ShopWindow/Margin/VRoot/BodyRow/SkillsMenu/SkillsNetwork/FILE_EXPLORER/Content/Status")
@onready var lesson_core: VBoxContainer = $Backdrop/ShopWindow/Margin/VRoot/BodyRow/LessonRepository/LessonRepositoryContainers/LessonRepositoryCore/Wrap/List
@onready var lesson_network: VBoxContainer = $Backdrop/ShopWindow/Margin/VRoot/BodyRow/LessonRepository/LessonRepositoryContainers/LessonRepositoryNetwork/Wrap/List
@onready var lesson_ops: VBoxContainer = $Backdrop/ShopWindow/Margin/VRoot/BodyRow/LessonRepository/LessonRepositoryContainers/LessonRepositoryOps/Wrap/List
@onready var preview_name: Label = get_node_or_null("Backdrop/ShopWindow/Margin/VRoot/BodyRow/LessonRepository/SkillPreviewPanel/Margin/Wrap/SkillName")
@onready var preview_summary: Label = get_node_or_null("Backdrop/ShopWindow/Margin/VRoot/BodyRow/LessonRepository/SkillPreviewPanel/Margin/Wrap/SkillSummary")
@onready var preview_requirement: Label = get_node_or_null("Backdrop/ShopWindow/Margin/VRoot/BodyRow/LessonRepository/SkillPreviewPanel/Margin/Wrap/SkillRequirement")
@onready var preview_command: Label = get_node_or_null("Backdrop/ShopWindow/Margin/VRoot/BodyRow/LessonRepository/SkillPreviewPanel/Margin/Wrap/SkillCommand")
@onready var preview_action_hint: Label = get_node_or_null("Backdrop/ShopWindow/Margin/VRoot/BodyRow/LessonRepository/SkillPreviewPanel/Margin/Wrap/SkillActionHint")
@onready var copy_feedback_dialog: AcceptDialog = get_node_or_null("CopyFeedbackDialog")

var _scene_manager: Node = null
var _owned_input_lock := false
var _previous_input_locked := false
var _skill_buttons: Dictionary = {}
var _selected_skill_id := ""

const _SKILL_ORDER := [
	"cli_history",
	"teleport",
	"file_explorer",
	"kill_taskkill",
	"sudo_privilege",
	"potion_patch",
	"potion_overclock",
	"potion_hardening"
]

const _SKILL_META := {
	"cli_history": {
		"title": "CLI HISTORY",
		"summary": "Recall previous terminal commands with [Up Key] for faster retries.",
		"command": "wget learnix://skills/cli_history.unlock"
	},
	"teleport": {
		"title": "TELEPORT",
		"summary": "Enable terminal route switching with cd destination aliases.",
		"command": "wget learnix://skills/teleport.unlock"
	},
	"file_explorer": {
		"title": "FILE EXPLORER",
		"summary": "Unlock repository indexing and lesson file browsing tools.",
		"command": "wget learnix://skills/file_explorer.unlock"
	},
	"kill_taskkill": {
		"title": "KILL / TASKKILL",
		"summary": "Interrupt enemy attack animations instantly or freeze an active hazard process for a short duration.",
		"command": "wget learnix://skills/taskkill.unlock"
	},
	"sudo_privilege": {
		"title": "SUDO (PRIVILEGE ESCALATION)",
		"summary": "High-tier admin mode: temporary Administrator Rights for invincibility windows, bonus damage, or security bypass.",
		"command": "wget learnix://skills/sudo_privilege.unlock"
	},
	"potion_patch": {
		"title": "POTION: PATCH TONIC",
		"summary": "Consumable patch tonic that restores integrity (healing) during combat.",
		"command": "wget learnix://skills/potion_patch.unlock"
	},
	"potion_overclock": {
		"title": "POTION: OVERCLOCK MIX",
		"summary": "Temporary attack-speed and damage boost for aggressive pushes.",
		"command": "wget learnix://skills/potion_overclock.unlock"
	},
	"potion_hardening": {
		"title": "POTION: HARDENING GEL",
		"summary": "Short-term defense buff to reduce incoming damage while repositioning.",
		"command": "wget learnix://skills/potion_hardening.unlock"
	}
}

func _ready() -> void:
	visible = false
	_scene_manager = get_node_or_null("/root/SceneManager")
	if close_button and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	_build_skill_list()
	call_deferred("_refresh_layout")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh_layout()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_shop()
		get_viewport().set_input_as_handled()

func open_shop() -> void:
	_acquire_input_lock()
	_refresh_view()
	_refresh_layout()
	visible = true
	if close_button:
		close_button.grab_focus()

func close_shop() -> void:
	visible = false
	_release_input_lock()

func _on_close_pressed() -> void:
	close_shop()

func _refresh_view() -> void:
	_refresh_data_bits()
	_refresh_skill_nodes()
	_refresh_repositories()

func _refresh_layout() -> void:
	if body_row and body_row.size.x > 0.0:
		body_row.split_offset = int(body_row.size.x * 0.67)
	_layout_network_nodes()

func _layout_network_nodes() -> void:
	if skills_network == null:
		return
	skills_network.visible = false

	var width := skills_network.size.x
	var height := skills_network.size.y
	if width <= 100.0 or height <= 100.0:
		return

	if core_hub:
		core_hub.visible = false
	if cli_history_card:
		cli_history_card.visible = false
	if teleport_card:
		teleport_card.visible = false
	if file_explorer_card:
		file_explorer_card.visible = false
	if connection_a:
		connection_a.visible = false
	if connection_b:
		connection_b.visible = false
	if connection_c:
		connection_c.visible = false

func _set_rect(target: Control, pos: Vector2, size_value: Vector2) -> void:
	if target == null:
		return
	target.set_anchors_preset(Control.PRESET_TOP_LEFT)
	target.offset_left = int(pos.x)
	target.offset_top = int(pos.y)
	target.size = size_value

func _rect_center(target: Control) -> Vector2:
	if target == null:
		return Vector2.ZERO
	return target.position + (target.size * 0.5)

func _set_link(line: Line2D, start_pos: Vector2, end_pos: Vector2) -> void:
	if line == null:
		return
	line.points = PackedVector2Array([start_pos, end_pos])

func _refresh_data_bits() -> void:
	var total := 0
	if _scene_manager:
		total = int(_scene_manager.get("data_bits"))
	if data_bits_label:
		data_bits_label.text = "Data Bits: %d" % total

func _refresh_skill_nodes() -> void:
	if _skill_buttons.is_empty():
		_build_skill_list()

	for skill_id in _SKILL_ORDER:
		if not _skill_buttons.has(skill_id):
			continue
		var button := _skill_buttons[skill_id] as Button
		if button == null:
			continue
		var skill := _SKILL_META.get(skill_id, {}) as Dictionary
		var unlocked := _is_skill_unlocked(skill_id)
		var requirements_met := _is_skill_requirements_met(skill_id)
		if unlocked:
			button.text = ">> %s  |  UNLOCKED" % String(skill.get("title", skill_id.to_upper()))
		elif requirements_met:
			button.text = ">> %s  |  REQUIREMENTS MET" % String(skill.get("title", skill_id.to_upper()))
		else:
			button.text = ">> %s" % String(skill.get("title", skill_id.to_upper()))
		_apply_skill_button_style(button, unlocked, skill_id == _selected_skill_id)

	if _selected_skill_id == "" and not _SKILL_ORDER.is_empty():
		_select_skill(_SKILL_ORDER[0])
	else:
		_update_skill_preview(_selected_skill_id)

func _set_skill_status(status_label: Label, unlocked: bool, unlocked_detail: String, locked_detail: String = "") -> void:
	if status_label == null:
		return
	if unlocked:
		status_label.text = "UNLOCKED  |  %s" % unlocked_detail
		status_label.modulate = Color(0.58, 1.0, 0.73, 1.0)
		return
	var detail := locked_detail if locked_detail != "" else "Not unlocked yet"
	status_label.text = "LOCKED  |  %s" % detail
	status_label.modulate = Color(1.0, 0.56, 0.56, 1.0)

func _refresh_repositories() -> void:
	if lesson_core:
		lesson_core.get_parent().get_parent().get_parent().visible = false
	_update_skill_preview(_selected_skill_id)

func _build_skill_list() -> void:
	if skills_list == null:
		return
	for child in skills_list.get_children():
		child.queue_free()
	_skill_buttons.clear()

	for skill_id in _SKILL_ORDER:
		var skill := _SKILL_META.get(skill_id, {}) as Dictionary
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, 58)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.focus_mode = Control.FOCUS_NONE
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.text = ">> %s" % String(skill.get("title", skill_id.to_upper()))
		row.mouse_entered.connect(_on_skill_row_hovered.bind(skill_id))
		row.pressed.connect(_on_skill_row_pressed.bind(skill_id))
		skills_list.add_child(row)
		_skill_buttons[skill_id] = row

func _on_skill_row_hovered(skill_id: String) -> void:
	_select_skill(skill_id)

func _on_skill_row_pressed(skill_id: String) -> void:
	_select_skill(skill_id)
	_copy_skill_command(skill_id)

func _select_skill(skill_id: String) -> void:
	_selected_skill_id = skill_id
	_refresh_skill_nodes()

func _update_skill_preview(skill_id: String) -> void:
	if skill_id == "":
		return
	var skill := _SKILL_META.get(skill_id, {}) as Dictionary
	if skill.is_empty():
		return
	var unlocked := _is_skill_unlocked(skill_id)
	var requirements_met := _is_skill_requirements_met(skill_id)
	if preview_name:
		preview_name.text = String(skill.get("title", skill_id.to_upper()))
	if preview_summary:
		preview_summary.text = String(skill.get("summary", ""))
	if preview_requirement:
		if unlocked:
			preview_requirement.text = "Status: UNLOCKED"
			preview_requirement.modulate = Color(0.58, 1.0, 0.73, 1.0)
		elif requirements_met:
			preview_requirement.text = "Status: REQUIREMENTS MET"
			preview_requirement.modulate = Color(0.88, 0.95, 1.0, 1.0)
		else:
			preview_requirement.text = "Status: Locked"
			preview_requirement.modulate = Color(1.0, 0.76, 0.76, 1.0)
	if preview_command:
		preview_command.text = "Command: %s" % String(skill.get("command", "wget learnix://skills/%s.unlock" % skill_id))
	if preview_action_hint:
		preview_action_hint.text = "Click to copy unlock command"

func _apply_skill_button_style(button: Button, unlocked: bool, selected: bool) -> void:
	if button == null:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.0509804, 0.0941176, 0.14902, 0.92)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.27451, 0.705882, 0.815686, 0.82)
	normal.corner_radius_top_left = 7
	normal.corner_radius_top_right = 7
	normal.corner_radius_bottom_right = 7
	normal.corner_radius_bottom_left = 7

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.0784314, 0.137255, 0.203922, 0.95)
	hover.border_color = Color(0.47451, 0.901961, 0.984314, 0.95)

	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.0901961, 0.164706, 0.239216, 0.98)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", pressed)

	if unlocked:
		button.add_theme_color_override("font_color", Color(0.64, 1.0, 0.82, 1.0))
	else:
		button.add_theme_color_override("font_color", Color(0.86, 0.93, 0.97, 1.0))

	if selected:
		button.add_theme_color_override("font_color", Color(0.76, 0.98, 1.0, 1.0))

func _is_skill_unlocked(skill_id: String) -> bool:
	if _scene_manager == null:
		return false
	match skill_id:
		"kill_taskkill":
			return _as_bool(_scene_manager.get("taskkill_unlocked"))
		_:
			return _as_bool(_scene_manager.get("%s_unlocked" % skill_id))

func _is_skill_requirements_met(skill_id: String) -> bool:
	match skill_id:
		"cli_history":
			return true
		"teleport":
			return _is_teleport_skill_requirements_met()
		"file_explorer":
			return _is_file_explorer_skill_requirements_met()
		_:
			return false

func _copy_skill_command(skill_id: String) -> void:
	if not _is_skill_requirements_met(skill_id):
		_show_copy_feedback("Requirements aren't met")
		return
	
	var skill := _SKILL_META.get(skill_id, {}) as Dictionary
	if skill.is_empty():
		return
	var command := String(skill.get("command", "wget learnix://skills/%s.unlock" % skill_id))
	if command == "":
		return
	DisplayServer.clipboard_set(command)
	_show_copy_feedback("Command copied to clipboard")

func _show_copy_feedback(message: String) -> void:
	if copy_feedback_dialog == null:
		return
	copy_feedback_dialog.dialog_text = message
	copy_feedback_dialog.popup_centered()

func _as_bool(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int:
		return value != 0
	if value is float:
		return value != 0.0
	if value is String:
		var normalized: String = String(value).strip_edges().to_lower()
		return normalized != "" and normalized != "0" and normalized != "false" and normalized != "off" and normalized != "no"
	return value != null

func core_container_or_fallback() -> VBoxContainer:
	if lesson_core:
		return lesson_core
	return lesson_network

func _is_teleport_skill_unlocked() -> bool:
	if _scene_manager == null:
		return false
	return _as_bool(_scene_manager.get("teleport_unlocked"))

func _is_teleport_skill_requirements_met() -> bool:
	if _scene_manager == null:
		return false
	var printer_defeated := _as_bool(_scene_manager.get("printer_beast_defeated"))
	return printer_defeated and _has_interacted_with_npc("CMO")

func _is_file_explorer_skill_requirements_met() -> bool:
	if _scene_manager == null:
		return false
	return _as_bool(_scene_manager.get("helped_lost_file"))

func _has_interacted_with_npc(npc_name: String) -> bool:
	if _scene_manager == null:
		return false
	var interactions = _scene_manager.get("interacted_npcs")
	if interactions is Dictionary:
		return _as_bool(interactions.get(npc_name, false))
	return false

func _append_lesson(container: VBoxContainer, text: String) -> void:
	if container == null:
		return
	var line := Label.new()
	line.text = "- %s" % text
	container.add_child(line)

func _clear_container(container: VBoxContainer) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()

func _acquire_input_lock() -> void:
	if _scene_manager == null or _owned_input_lock:
		return
	_previous_input_locked = _as_bool(_scene_manager.get("input_locked"))
	_scene_manager.set("input_locked", true)
	_owned_input_lock = true

func _release_input_lock() -> void:
	if _scene_manager == null or not _owned_input_lock:
		return
	_scene_manager.set("input_locked", _previous_input_locked)
	_owned_input_lock = false
