extends PanelContainer
class_name QuestWindow

@onready var tab_container: TabContainer = $MarginContainer/VBox/TabContainer
@onready var close_button: Button = $MarginContainer/VBox/CloseRow/CloseButton
@onready var close_row: HBoxContainer = $MarginContainer/VBox/CloseRow

var _quest_tab_map: Dictionary = {}
var _is_dragging_window := false
var _window_drag_offset := Vector2.ZERO

func _ready() -> void:
	visible = false
	if close_button and not close_button.pressed.is_connected(Callable(self, "_on_close_pressed")):
		close_button.pressed.connect(Callable(self, "_on_close_pressed"))

	if has_node("/root/SceneManager") and SceneManager and SceneManager.quest_manager:
		var qm = SceneManager.quest_manager
		if qm.has_signal("quest_started"):
			qm.quest_started.connect(Callable(self, "_on_quest_started"))
		if qm.has_signal("quest_completed"):
			qm.quest_completed.connect(Callable(self, "_on_quest_completed"))
		if qm.has_signal("quest_updated"):
			qm.quest_updated.connect(Callable(self, "_on_quest_updated"))

	_refresh_tabs()

	# Allow dragging the window by the tab/header area
	if tab_container and not tab_container.gui_input.is_connected(Callable(self, "_on_window_gui_input")):
		tab_container.gui_input.connect(Callable(self, "_on_window_gui_input"))
	if close_row and not close_row.gui_input.is_connected(Callable(self, "_on_window_gui_input")):
		close_row.gui_input.connect(Callable(self, "_on_window_gui_input"))

	# Style the close button to be more visible
	if close_button:
		var sb_close := StyleBoxFlat.new()
		sb_close.bg_color = Color(0.12, 0.12, 0.12, 0.8)
		sb_close.border_color = Color(0, 0, 0, 0)
		close_button.add_theme_stylebox_override("normal", sb_close)
		var sb_close_h := StyleBoxFlat.new()
		sb_close_h.bg_color = Color(0.18, 0.18, 0.18, 0.9)
		close_button.add_theme_stylebox_override("hover", sb_close_h)
		close_button.add_theme_color_override("font_color", Color(1, 1, 1))

func _refresh_tabs() -> void:
	# Remove existing tabs (queue_free on snapshot to avoid deferred-child loop)
	for c in tab_container.get_children():
		var node_c: Node = c
		node_c.queue_free()
	_quest_tab_map.clear()

	if not has_node("/root/SceneManager") or not SceneManager or not SceneManager.quest_manager:
		return

	var quests_dict: Dictionary = SceneManager.quest_manager.quests
	var quests: Array = []
	for id in quests_dict.keys():
		var q: Quest = quests_dict.get(id) as Quest
		if q != null:
			quests.append(q)

	# Sort by display name for consistent tab order
	quests.sort_custom(Callable(self, "_compare_quests"))

	for q in quests:
		# Create a styled panel per tab to resemble a notepad page
		var tab := PanelContainer.new()
		tab.name = q.quest_id

		var sb_tab := StyleBoxFlat.new()
		sb_tab.bg_color = Color(0.97, 0.97, 0.97, 0.98)
		sb_tab.border_width_left = 1
		sb_tab.border_width_top = 1
		sb_tab.border_width_right = 1
		sb_tab.border_width_bottom = 1
		sb_tab.border_color = Color(0.75, 0.75, 0.75, 1)
		tab.add_theme_stylebox_override("panel", sb_tab)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_bottom", 12)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 10)

		var title := Label.new()
		title.name = "QuestTitle"
		title.add_theme_font_size_override("font_size", 30)
		title.text = q.quest_name
		title.add_theme_color_override("font_color", Color(0.06, 0.06, 0.06))
		vbox.add_child(title)

		var desc := RichTextLabel.new()
		desc.name = "QuestDescription"
		desc.bbcode_enabled = true
		desc.custom_minimum_size = Vector2(0, 180)
		# Force a readable text color via BBCode wrapper
		desc.bbcode_text = "[color=#222222]" + q.description + "[/color]"
		desc.add_theme_font_size_override("font_size", 14)
		vbox.add_child(desc)

		var progress_row := HBoxContainer.new()
		progress_row.name = "ProgressRow"
		progress_row.add_theme_constant_override("separation", 8)

		var progress_label := Label.new()
		progress_label.name = "ProgressLabel"
		progress_label.text = "Progress"
		progress_label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08))
		progress_row.add_child(progress_label)

		var progress_overlay := Control.new()
		progress_overlay.name = "ProgressOverlay"
		progress_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress_overlay.custom_minimum_size = Vector2(0, 26)

		var progress_bar := ProgressBar.new()
		progress_bar.name = "ProgressBar"
		progress_bar.min_value = 0
		progress_bar.max_value = 100
		progress_bar.value = 0
		progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress_overlay.add_child(progress_bar)

		var progress_percent := Label.new()
		progress_percent.name = "ProgressPercent"
		progress_percent.text = "0%"
		progress_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		progress_percent.set_anchors_preset(Control.PRESET_FULL_RECT)
		progress_percent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		progress_percent.add_theme_font_size_override("font_size", 13)
		progress_percent.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
		progress_overlay.add_child(progress_percent)

		progress_row.add_child(progress_overlay)

		vbox.add_child(progress_row)

		margin.add_child(vbox)
		tab.add_child(margin)

		tab_container.add_child(tab)
		var idx: int = tab_container.get_child_count() - 1
		tab_container.set_tab_title(idx, q.quest_name)
		_quest_tab_map[q.quest_id] = idx
		_update_tab_for_quest(q.quest_id)

func _compare_quests(a, b) -> int:
	if a.quest_name < b.quest_name:
		return -1
	elif a.quest_name > b.quest_name:
		return 1
	return 0

func _update_tab_for_quest(quest_id: String) -> void:
	if not _quest_tab_map.has(quest_id):
		return
	var idx: int = int(_quest_tab_map[quest_id])
	if idx < 0 or idx >= tab_container.get_child_count():
		return
	var tab: Node = tab_container.get_child(idx)
	var prog_bar: ProgressBar = null
	# Try a few common paths depending on how the tab was created
	if tab.has_node("ProgressRow/ProgressBar"):
		prog_bar = tab.get_node("ProgressRow/ProgressBar") as ProgressBar
	elif tab.has_node("MarginContainer/VBox/ProgressRow/ProgressBar"):
		prog_bar = tab.get_node("MarginContainer/VBox/ProgressRow/ProgressBar") as ProgressBar
	else:
		prog_bar = _find_progress_bar_in(tab)
	if not prog_bar:
		return
	var q := SceneManager.quest_manager.get_quest(quest_id)
	if not q:
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

	# Update percent label if present
	var percent_label: Label = null
	if prog_bar and prog_bar.get_parent() and prog_bar.get_parent().has_node("ProgressPercent"):
		percent_label = prog_bar.get_parent().get_node("ProgressPercent") as Label
	if percent_label:
		percent_label.text = "%d%%" % int(prog_bar.value)

func set_quest(q: Quest) -> void:
	_refresh_tabs()
	if not q:
		# Center and show an empty quest window
		_center_and_show()
		return
	if _quest_tab_map.has(q.quest_id):
		tab_container.current_tab = _quest_tab_map[q.quest_id]
	# Center like an app window and grab focus
	_center_and_show()

func _on_close_pressed() -> void:
	hide()


func _on_window_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var click := event as InputEventMouseButton
		if click.pressed:
			_is_dragging_window = true
			_window_drag_offset = click.global_position - global_position
		else:
			_is_dragging_window = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _is_dragging_window:
		var motion := event as InputEventMouseMotion
		_update_window_drag_position(motion.global_position)
		get_viewport().set_input_as_handled()


func _update_window_drag_position(mouse_global_pos: Vector2) -> void:
	var new_pos := mouse_global_pos - _window_drag_offset
	position = new_pos
	_clamp_window_to_viewport()


func _clamp_window_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	var window_size := size
	var clamped_x := clampf(position.x, 0.0, max(0.0, viewport_size.x - window_size.x))
	var clamped_y := clampf(position.y, 0.0, max(0.0, viewport_size.y - window_size.y))
	position = Vector2(clamped_x, clamped_y)


func _center_and_show() -> void:
	visible = true
	var vp := get_viewport_rect().size
	var win_size := size
	position = (vp - win_size) / 2.0
	if get_parent() != null:
		get_parent().move_child(self, get_parent().get_child_count() - 1)
	grab_focus()
	_clamp_window_to_viewport()

func _on_quest_started(quest_id: String) -> void:
	_refresh_tabs()
	if _quest_tab_map.has(quest_id):
		tab_container.current_tab = _quest_tab_map[quest_id]

func _on_quest_completed(quest_id: String) -> void:
	_update_tab_for_quest(quest_id)
	# If the completed quest is currently visible, close window
	if visible and _quest_tab_map.has(quest_id) and tab_container.current_tab == _quest_tab_map[quest_id]:
		visible = false

func _on_quest_updated(quest_id: String) -> void:
	_update_tab_for_quest(quest_id)


func _find_progress_bar_in(root: Node) -> ProgressBar:
	for child in root.get_children():
		if child is ProgressBar:
			return child as ProgressBar
		if child is Node:
			var found := _find_progress_bar_in(child)
			if found:
				return found
	return null
