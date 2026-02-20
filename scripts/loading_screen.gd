extends CanvasLayer

signal animation_finished

@onready var rect = $ColorRect
@onready var label = $Label

func fade_in():
	show()
	rect.modulate.a = 0.0
	label.text = "Lodeng..."
	create_tween().tween_property(rect, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(0.5).timeout
	emit_signal("animation_finished")

func fade_out():
	create_tween().tween_property(rect, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(0.5).timeout
	hide()
	emit_signal("animation_finished")
