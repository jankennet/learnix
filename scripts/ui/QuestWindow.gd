extends PanelContainer
class_name QuestWindow

@onready var tab_container: TabContainer = $MarginContainer/VBox/TabContainer
@onready var close_button: Button = $MarginContainer/VBox/Header/CloseButton
@onready var header: Control = $MarginContainer/VBox/Header
@onready var _scene_manager: Node = get_node_or_null("/root/SceneManager")

var _quest_tab_map: Dictionary = {}
var _is_dragging_window := false
var _window_drag_offset := Vector2.ZERO

const NOTEPAD_BG = Color(0.95, 0.95, 0.9, 1.0)
const NOTEPAD_BORDER = Color(0.18, 0.18, 0.18, 1.0)
const TAB_BG = Color(0.97, 0.97, 0.97, 1.0)
const TAB_BORDER = Color(0.75, 0.75, 0.75, 1.0)
const TEXT_DARK = Color(0.06, 0.06, 0.06)
const TEXT_BODY = Color(0.22, 0.22, 0.22)

func _ready() -> void:
	visible = false
	focus_mode = FOCUS_NONE
	
	# Style main window to opaque notepad
	var sb_main := StyleBoxFlat.new()
	sb_main.bg_color = NOTEPAD_BG
	sb_main.border_width_left = 2
	sb_main.border_width_top = 2
	sb_main.border_width_right = 2
	sb_main.border_width_bottom = 2
	sb_main.border_color = NOTEPAD_BORDER
	add_theme_stylebox_override("panel", sb_main)
	
	# Connect UI signals
	close_button.pressed.connect(Callable(self, "_on_close_pressed"))
	_style_close_button()

	# Connect dragging to the header
	header.gui_input.connect(Callable(self, "_on_header_gui_input"))

	_connect_quest_manager_signals()
	_refresh_tabs()

func _style_close_button() -> void:
	if not close_button:
		return
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.12, 0.12, 0.12, 0.8)
	sb_normal.border_color = Color(0, 0, 0, 0)
	close_button.add_theme_stylebox_override("normal", sb_normal)
	
	var sb_hover := StyleBoxFlat.new()
	sb_hover.bg_color = Color(0.18, 0.18, 0.18, 0.9)
	sb_hover.border_color = Color(0, 0, 0, 0)
	close_button.add_theme_stylebox_override("hover", sb_hover)
	close_button.add_theme_color_override("font_color", Color.WHITE)

func _create_quest_tab(quest: Quest) -> void:
	var tab := PanelContainer.new()
	tab.name = quest.quest_id
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = TAB_BG
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = TAB_BORDER
	tab.add_theme_stylebox_override("panel", sb)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	
	# Title
	var title := Label.new()
	title.name = "QuestTitle"
	title.add_theme_font_size_override("font_size", 30)
	title.text = quest.quest_name
	title.add_theme_color_override("font_color", TEXT_DARK)
	vbox.add_child(title)
	
	# Description
	var desc := RichTextLabel.new()
	desc.name = "QuestDescription"
	desc.bbcode_enabled = true
	desc.custom_minimum_size = Vector2(0, 180)
	desc.bbcode_text = "[color=#%s]%s[/color]" % [TEXT_BODY.to_html(false), quest.description]
	desc.add_theme_font_size_override("font_size", 14)
	vbox.add_child(desc)
	
	# Progress row
	var prog_row := HBoxContainer.new()
	prog_row.add_theme_constant_override("separation", 8)
	
	var prog_label := Label.new()
	prog_label.text = "Progress"
	prog_label.add_theme_color_override("font_color", TEXT_DARK)
	prog_row.add_child(prog_label)
	
	var prog_overlay := Control.new()
	prog_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prog_overlay.custom_minimum_size = Vector2(0, 26)
	
	var prog_bar := ProgressBar.new()
	prog_bar.min_value = 0
	prog_bar.max_value = 100
	prog_bar.value = 0
	prog_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prog_overlay.add_child(prog_bar)
	
	var prog_percent := Label.new()
	prog_percent.text = "0%"
	prog_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prog_percent.set_anchors_preset(Control.PRESET_FULL_RECT)
	prog_percent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prog_percent.add_theme_font_size_override("font_size", 13)
	prog_percent.add_theme_color_override("font_color", TEXT_DARK)
	prog_overlay.add_child(prog_percent)
	
	prog_row.add_child(prog_overlay)
	vbox.add_child(prog_row)
	
	# Assemble
	margin.add_child(vbox)
	tab.add_child(margin)
	tab_container.add_child(tab)
	
	var idx = tab_container.get_child_count() - 1
	tab_container.set_tab_title(idx, quest.quest_name)
	_quest_tab_map[quest.quest_id] = idx
	_update_tab_for_quest(quest.quest_id)

func _create_no_quests_tab() -> void:
	var tab := PanelContainer.new()
	tab.name = "NoQuests"
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = TAB_BG
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = TAB_BORDER
	tab.add_theme_stylebox_override("panel", sb)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 30)
	title.text = "Quests"
	title.add_theme_color_override("font_color", TEXT_DARK)
	vbox.add_child(title)
	
	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.custom_minimum_size = Vector2(0, 180)
	desc.bbcode_text = "[color=#%s]Tux: This panel will show quests you've been offered. Try talking to NPCs to pick up tasks and track them here.[/color]" % TEXT_BODY.to_html(false)
	desc.add_theme_font_size_override("font_size", 14)
	vbox.add_child(desc)
	
	margin.add_child(vbox)
	tab.add_child(margin)
	tab_container.add_child(tab)
	
	var idx = tab_container.get_child_count() - 1
	tab_container.set_tab_title(idx, "Quests")
	_quest_tab_map["NoQuests"] = idx

func _refresh_tabs() -> void:
	# Clear all tabs
	for c in tab_container.get_children():
		c.queue_free()
	_quest_tab_map.clear()

	var qm := _get_quest_manager()
	if qm == null:
		return

	# Filter available quests
	var available := _get_available_quests(qm)
	available.sort_custom(Callable(self, "_compare_quests"))

	# Create tabs for each available quest
	for q in available:
		_create_quest_tab(q)

	# If no quests, show hint
	if available.is_empty():
		_create_no_quests_tab()

func _get_available_quests(qm: QuestManager) -> Array:
	var result: Array = []
	var sm = _scene_manager if _scene_manager else get_node_or_null("/root/SceneManager")

	for quest in qm.quests.values():
		if not quest is Quest:
			continue
		
		# Always show active, completed, or failed quests
		if quest.status in ["active", "completed", "failed"]:
			result.append(quest)
			continue
		
		# For inactive quests: only show if no NPC prereq, or player talked to one of them
		if not quest.npc_involved or quest.npc_involved.is_empty():
			result.append(quest)
		elif sm and sm.has_method("has_interacted_with_npc"):
			for npc_name in quest.npc_involved:
				if sm.has_interacted_with_npc(str(npc_name)):
					result.append(quest)
					break
	
	return result

func _compare_quests(a: Quest, b: Quest) -> int:
	return -1 if a.quest_name < b.quest_name else (1 if a.quest_name > b.quest_name else 0)

func _update_tab_for_quest(quest_id: String) -> void:
	if not _quest_tab_map.has(quest_id):
		return
	
	var idx = int(_quest_tab_map[quest_id])
	if idx < 0 or idx >= tab_container.get_child_count():
		return
	
	var tab = tab_container.get_child(idx)
	var qm = _get_quest_manager()
	var q = qm.get_quest(quest_id) as Quest if qm else null
	
	if not q:
		return
	
	# Find and update progress bar
	var prog_bar = _find_node_by_name(tab, "ProgressBar") as ProgressBar
	if not prog_bar:
		return
	
	match q.status:
		"inactive":
			prog_bar.value = 0
		"active":
			prog_bar.value = 50
		"completed":
			prog_bar.value = 100
		"failed":
			prog_bar.value = 0
	
	# Update progress label
	var prog_percent = _find_node_by_name(tab, "ProgressPercent") as Label
	if prog_percent:
		prog_percent.text = "%d%%" % int(prog_bar.value)

func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found = _find_node_by_name(child, target_name)
		if found:
			return found
	return null

func set_quest(q: Quest) -> void:
	_refresh_tabs()
	if q and _quest_tab_map.has(q.quest_id):
		tab_container.current_tab = _quest_tab_map[q.quest_id]
	_center_and_show()

func _on_close_pressed() -> void:
	hide()

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var click := event as InputEventMouseButton
		if click.pressed:
			_is_dragging_window = true
			_window_drag_offset = click.global_position - position
		else:
			_is_dragging_window = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _is_dragging_window:
		var motion := event as InputEventMouseMotion
		position = motion.global_position - _window_drag_offset
		_clamp_window_to_viewport()
		get_viewport().set_input_as_handled()

func _clamp_window_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	var panel_size := size
	var clamped_x := clampf(position.x, 0.0, max(0.0, viewport_size.x - panel_size.x))
	var clamped_y := clampf(position.y, 0.0, max(0.0, viewport_size.y - panel_size.y))
	position = Vector2(clamped_x, clamped_y)

func _center_and_show() -> void:
	visible = true
	var viewport_size := get_viewport_rect().size
	var panel_size := size
	position = (viewport_size - panel_size) / 2.0
	if get_parent():
		get_parent().move_child(self, get_parent().get_child_count() - 1)
	_clamp_window_to_viewport()

func _on_quest_started(quest_id: String) -> void:
	_refresh_tabs()
	if _quest_tab_map.has(quest_id):
		tab_container.current_tab = _quest_tab_map[quest_id]

func _on_quest_completed(quest_id: String) -> void:
	_update_tab_for_quest(quest_id)
	if visible and _quest_tab_map.has(quest_id) and tab_container.current_tab == _quest_tab_map[quest_id]:
		visible = false

func _on_quest_updated(quest_id: String) -> void:
	_update_tab_for_quest(quest_id)

func _get_quest_manager() -> QuestManager:
	if _scene_manager == null:
		_scene_manager = get_node_or_null("/root/SceneManager")
	return _scene_manager.get("quest_manager") if _scene_manager else null

func _connect_quest_manager_signals() -> void:
	var qm = _get_quest_manager()
	if not qm:
		return

	qm.quest_started.connect(Callable(self, "_on_quest_started"))
	qm.quest_completed.connect(Callable(self, "_on_quest_completed"))
	qm.quest_updated.connect(Callable(self, "_on_quest_updated"))
