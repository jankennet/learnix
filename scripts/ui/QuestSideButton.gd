extends PanelContainer
class_name QuestSideButton

@onready var label: Label = get_node_or_null("Label") as Label
var _last_viewport_size := Vector2.ZERO

func _ready() -> void:
	name = "QuestSideButton"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(56, 56)
	if not gui_input.is_connected(Callable(self, "_on_gui_input")):
		gui_input.connect(Callable(self, "_on_gui_input"))
	_reposition()

func _process(_delta: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	if vs != _last_viewport_size:
		_reposition()
		_last_viewport_size = vs

func _reposition() -> void:
	var vs := get_viewport().get_visible_rect().size
	var ctrl_size := get_size()
	if ctrl_size == Vector2.ZERO:
		ctrl_size = custom_minimum_size if custom_minimum_size != Vector2.ZERO else Vector2(56, 56)
	position = Vector2(vs.x - ctrl_size.x - 24, vs.y * 0.5 - ctrl_size.y * 0.5)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var be := event as InputEventMouseButton
		if be.button_index == MOUSE_BUTTON_LEFT and be.pressed:
			_open_first_active_quest()

func _open_first_active_quest() -> void:
	if has_node("/root/SceneManager") and SceneManager and SceneManager.quest_manager:
		var qm := SceneManager.quest_manager
		var act := qm.get_active_quests()
		if act.size() > 0:
			var qid := act[0]
			var q := qm.get_quest(qid)
			if q:
				var QuestWindowScene := preload("res://Scenes/ui/QuestWindow.tscn")
				var w: QuestWindow = QuestWindowScene.instantiate() as QuestWindow
				get_tree().get_root().add_child(w)
				w.set_quest(q)
				return

	# fallback: toggle quest list UI
	var root := get_tree().root
	if root:
		var quest_list := root.find_child("QuestList", true, false)
		if quest_list and quest_list is CanvasItem:
			(quest_list as CanvasItem).visible = not (quest_list as CanvasItem).visible
