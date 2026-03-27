extends CanvasLayer

@onready var move_value: Label = $MarginContainer/PanelContainer/VBoxContainer/GridContainer/MoveValue
@onready var run_value: Label = $MarginContainer/PanelContainer/VBoxContainer/GridContainer/RunValue
@onready var interact_value: Label = $MarginContainer/PanelContainer/VBoxContainer/GridContainer/InteractValue
@onready var dialogue_value: Label = $MarginContainer/PanelContainer/VBoxContainer/GridContainer/DialogueValue
@onready var confirm_value: Label = $MarginContainer/PanelContainer/VBoxContainer/GridContainer/ConfirmValue

func _ready() -> void:
	move_value.text = _build_move_text()
	run_value.text = _first_binding_text("ui_shift")
	interact_value.text = _first_binding_text("interact")
	dialogue_value.text = _joined_binding_text("interact")
	confirm_value.text = _first_binding_text("ui_accept")

func _build_move_text() -> String:
	var up_key := _first_binding_text("ui_up")
	var left_key := _first_binding_text("ui_left")
	var down_key := _first_binding_text("ui_down")
	var right_key := _first_binding_text("ui_right")

	if up_key == "-" and left_key == "-" and down_key == "-" and right_key == "-":
		return "-"

	return "%s %s %s %s" % [up_key, left_key, down_key, right_key]

func _first_binding_text(action_name: String) -> String:
	if not InputMap.has_action(action_name):
		return "-"

	for event in InputMap.action_get_events(action_name):
		var text := _event_to_text(event)
		if text != "":
			return text

	return "-"

func _joined_binding_text(action_name: String) -> String:
	if not InputMap.has_action(action_name):
		return "-"

	var labels: PackedStringArray = []
	for event in InputMap.action_get_events(action_name):
		var text := _event_to_text(event)
		if text == "":
			continue
		if labels.has(text):
			continue
		labels.append(text)

	if labels.is_empty():
		return "-"

	return " / ".join(labels)

func _event_to_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var physical_code := key_event.physical_keycode
		if physical_code != 0:
			return OS.get_keycode_string(physical_code)
		if key_event.keycode != 0:
			return OS.get_keycode_string(key_event.keycode)
		return ""

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			_:
				return "Mouse %d" % mouse_event.button_index

	if event is InputEventJoypadButton:
		var joy_button := event as InputEventJoypadButton
		return "Pad %d" % joy_button.button_index

	if event is InputEventJoypadMotion:
		var joy_axis := event as InputEventJoypadMotion
		if joy_axis.axis_value < 0:
			return "Axis %d-" % joy_axis.axis
		return "Axis %d+" % joy_axis.axis

	return ""
