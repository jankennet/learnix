extends Control

const COMBAT_UI_NODE_NAME := "CombatTerminalUI"
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
	visible = not _is_combat_ui_visible()

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
