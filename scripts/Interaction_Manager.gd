extends Node

var current_interactable: Node = null

# Camera zoom settings for NPC dialogue focus
@export var default_fov: float = 75.0
@export var dialogue_fov: float = 50.0  # Lower FOV = more zoomed in
@export var zoom_speed: float = 4.0

var _target_fov: float = 75.0
var _current_camera: Camera3D = null

func _ready() -> void:
	# Connect to DialogueManager signals for zoom effect
	call_deferred("_connect_dialogue_manager")

func _connect_dialogue_manager() -> void:
	# DialogueManager is an autoload - access via scene tree
	var dm = get_tree().root.get_node_or_null("DialogueManager")
	
	if dm:
		if dm.has_signal("dialogue_started") and not dm.dialogue_started.is_connected(_on_dialogue_started):
			dm.dialogue_started.connect(_on_dialogue_started)
			print("[InteractionManager] Connected to dialogue_started signal")
		if dm.has_signal("dialogue_ended") and not dm.dialogue_ended.is_connected(_on_dialogue_ended):
			dm.dialogue_ended.connect(_on_dialogue_ended)
			print("[InteractionManager] Connected to dialogue_ended signal")
	else:
		push_warning("[InteractionManager] DialogueManager not found at /root/DialogueManager - zoom effect won't work")

func _get_current_camera() -> Camera3D:
	# Get the current active camera in the viewport
	var viewport = get_viewport()
	if viewport:
		return viewport.get_camera_3d()
	return null

func _on_dialogue_started(_resource) -> void:
	_current_camera = _get_current_camera()
	if _current_camera:
		default_fov = _current_camera.fov  # Store current FOV as default
		_target_fov = dialogue_fov

func _on_dialogue_ended(_resource) -> void:
	_target_fov = default_fov

func _process(delta: float) -> void:
	# Smoothly interpolate FOV for zoom effect
	if _current_camera and is_instance_valid(_current_camera):
		if abs(_current_camera.fov - _target_fov) > 0.1:
			_current_camera.fov = lerp(_current_camera.fov, _target_fov, delta * zoom_speed)

func request_interaction():
	# Block interactions when input is locked (e.g., during combat)
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.input_locked:
		return
	
	if current_interactable and current_interactable.has_method("on_interact"):
		current_interactable.on_interact()
