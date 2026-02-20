extends CanvasLayer

@onready var panel = $"Panel"
var teleporter_ref: Node = null

func show_popup(teleporter: Node):
	teleporter_ref = teleporter
	# panel.visible = true
	panel.modulate.a = 1.0
	panel.get_node("LocationLabel").text = teleporter.location_name

func _on_yes_pressed():
	panel.visible = false
	if teleporter_ref:
		teleporter_ref.execute_teleport()

func _on_no_pressed():
	panel.visible = false
	teleporter_ref = null
