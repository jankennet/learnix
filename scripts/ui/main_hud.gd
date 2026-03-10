extends Control

const COMBAT_UI_NODE_NAME := "CombatTerminalUI"
const QUEST_LIST_NODE_NAME := "QuestList"
const VISIBILITY_CHECK_INTERVAL := 0.15

var _check_timer := 0.0

func _ready() -> void:
	_update_visibility()

func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = VISIBILITY_CHECK_INTERVAL
	_update_visibility()

func _update_visibility() -> void:
	var should_show := not _is_combat_ui_visible()
	visible = should_show
	_set_quest_list_visible(should_show)

func _set_quest_list_visible(should_show: bool) -> void:
	var root := get_tree().root
	if root == null:
		return

	var quest_list := root.find_child(QUEST_LIST_NODE_NAME, true, false)
	if quest_list == null:
		return

	if quest_list is CanvasItem:
		(quest_list as CanvasItem).visible = should_show

func _is_combat_ui_visible() -> bool:
	var root := get_tree().root
	if root == null:
		return false

	var combat_ui := root.find_child(COMBAT_UI_NODE_NAME, true, false)
	if combat_ui == null:
		return false

	if combat_ui is CanvasItem:
		var canvas_item := combat_ui as CanvasItem
		return canvas_item.visible and canvas_item.is_visible_in_tree()

	return false
