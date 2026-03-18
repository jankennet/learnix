extends CharacterBody3D

@export var idle_animation: StringName = &"default"

@onready var _sprite: AnimatedSprite3D = _find_sprite()

func _ready() -> void:
	_apply_idle_animation()

func _process(_delta: float) -> void:
	if _sprite == null:
		_sprite = _find_sprite()
	if _sprite == null:
		return
	if not _sprite.is_playing() or _sprite.animation != idle_animation:
		_apply_idle_animation()

func set_follow_enabled(_enabled: bool) -> void:
	# Tutorial tux is intentionally stationary; this exists for controller compatibility.
	pass

func _apply_idle_animation() -> void:
	if _sprite == null:
		return
	_sprite.visible = true
	_sprite.play(idle_animation)

func _find_sprite() -> AnimatedSprite3D:
	var direct := get_node_or_null("AnimatedSprite3D")
	if direct is AnimatedSprite3D:
		return direct as AnimatedSprite3D
	var matches := find_children("*", "AnimatedSprite3D", true, false)
	if not matches.is_empty() and matches[0] is AnimatedSprite3D:
		return matches[0] as AnimatedSprite3D
	return null
