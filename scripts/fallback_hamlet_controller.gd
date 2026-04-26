extends Node3D

@export var portal_locked_color: Color = Color(0.55, 0.55, 0.55, 1.0)
@export var portal_unlocked_color: Color = Color(1.0, 0.86, 0.25, 1.0)
@export var camera_blend_duration: float = 0.45
@export var tux_render_priority: int = 3

var _portal_mesh: MeshInstance3D = null
var _portal_particles: GPUParticles3D = null
var _last_portal_unlocked_state: bool = false

var _gatekeeper_trigger_camera: Camera3D = null
var _gatekeeper_trigger_area: Area3D = null
var _gatekeeper_target_transform: Transform3D
var _gatekeeper_target_fov: float = 55.0
var _previous_camera: Camera3D = null
var _camera_transition_tween: Tween = null
var _player_inside_gatekeeper_area: bool = false

var _tux_priority_applied: bool = false

func _ready() -> void:
	_setup_portal_nodes()
	_setup_gatekeeper_camera_nodes()
	_setup_gatekeeper_trigger_area()
	_refresh_portal_color(true)
	_ensure_tux_render_priority()

func _process(_delta: float) -> void:
	_refresh_portal_color(false)
	if not _tux_priority_applied:
		_ensure_tux_render_priority()

func _setup_portal_nodes() -> void:
	var portal_root := get_node_or_null("vfxPortal3") as Node3D
	if portal_root == null:
		return

	_portal_mesh = portal_root.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _portal_mesh and _portal_mesh.material_override:
		_portal_mesh.material_override = _portal_mesh.material_override.duplicate(true)

	_portal_particles = portal_root.get_node_or_null("GPUParticles3D") as GPUParticles3D
	if _portal_particles and _portal_particles.material_override:
		_portal_particles.material_override = _portal_particles.material_override.duplicate(true)

func _setup_gatekeeper_camera_nodes() -> void:
	_gatekeeper_trigger_camera = get_node_or_null("Fallback_Hamlet_Final/GatekeeperAngleTrigger") as Camera3D
	if _gatekeeper_trigger_camera == null:
		return

	_gatekeeper_target_transform = _gatekeeper_trigger_camera.global_transform
	_gatekeeper_target_fov = _gatekeeper_trigger_camera.fov
	_gatekeeper_trigger_camera.current = false

func _setup_gatekeeper_trigger_area() -> void:
	var gatekeeper := get_node_or_null("NPC/Gate Keeper") as Node3D
	if gatekeeper == null:
		return

	var collision_src := gatekeeper.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_src == null or collision_src.shape == null:
		return

	_gatekeeper_trigger_area = gatekeeper.get_node_or_null("GatekeeperCameraArea") as Area3D
	if _gatekeeper_trigger_area == null:
		_gatekeeper_trigger_area = Area3D.new()
		_gatekeeper_trigger_area.name = "GatekeeperCameraArea"
		gatekeeper.add_child(_gatekeeper_trigger_area)
		_gatekeeper_trigger_area.owner = owner

	var shape_node := _gatekeeper_trigger_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		_gatekeeper_trigger_area.add_child(shape_node)
		shape_node.owner = owner

	shape_node.shape = collision_src.shape.duplicate(true)
	shape_node.transform = collision_src.transform

	_gatekeeper_trigger_area.monitoring = true
	_gatekeeper_trigger_area.monitorable = true
	if not _gatekeeper_trigger_area.body_entered.is_connected(_on_gatekeeper_area_body_entered):
		_gatekeeper_trigger_area.body_entered.connect(_on_gatekeeper_area_body_entered)
	if not _gatekeeper_trigger_area.body_exited.is_connected(_on_gatekeeper_area_body_exited):
		_gatekeeper_trigger_area.body_exited.connect(_on_gatekeeper_area_body_exited)

func _refresh_portal_color(force: bool) -> void:
	var unlocked := _has_both_gatekeeper_keys()
	if not force and unlocked == _last_portal_unlocked_state:
		return

	_last_portal_unlocked_state = unlocked
	var target_color := portal_unlocked_color if unlocked else portal_locked_color

	if _portal_mesh and _portal_mesh.material_override is ShaderMaterial:
		(_portal_mesh.material_override as ShaderMaterial).set_shader_parameter("portalColor", target_color)

	if _portal_particles and _portal_particles.material_override is StandardMaterial3D:
		(_portal_particles.material_override as StandardMaterial3D).albedo_color = target_color

func _has_both_gatekeeper_keys() -> bool:
	if SceneManager == null:
		return false
	return bool(SceneManager.get("proficiency_key_forest")) and bool(SceneManager.get("proficiency_key_printer"))

func _on_gatekeeper_area_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside_gatekeeper_area = true
	_activate_gatekeeper_camera()

func _on_gatekeeper_area_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside_gatekeeper_area = false
	_restore_player_camera()

func _activate_gatekeeper_camera() -> void:
	if _gatekeeper_trigger_camera == null:
		return

	var active_camera := get_viewport().get_camera_3d()
	if active_camera == null:
		return

	if active_camera == _gatekeeper_trigger_camera:
		return

	_previous_camera = active_camera
	_cancel_camera_transition_tween()

	_gatekeeper_trigger_camera.global_transform = active_camera.global_transform
	_gatekeeper_trigger_camera.fov = active_camera.fov
	_gatekeeper_trigger_camera.current = true

	_camera_transition_tween = create_tween()
	_camera_transition_tween.set_trans(Tween.TRANS_SINE)
	_camera_transition_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_transition_tween.tween_property(_gatekeeper_trigger_camera, "global_transform", _gatekeeper_target_transform, camera_blend_duration)
	_camera_transition_tween.parallel().tween_property(_gatekeeper_trigger_camera, "fov", _gatekeeper_target_fov, camera_blend_duration)

func _restore_player_camera() -> void:
	if _gatekeeper_trigger_camera == null:
		return
	if _previous_camera == null or not is_instance_valid(_previous_camera):
		_gatekeeper_trigger_camera.current = false
		return

	if get_viewport().get_camera_3d() != _gatekeeper_trigger_camera:
		return

	_cancel_camera_transition_tween()

	_camera_transition_tween = create_tween()
	_camera_transition_tween.set_trans(Tween.TRANS_SINE)
	_camera_transition_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_transition_tween.tween_property(_gatekeeper_trigger_camera, "global_transform", _previous_camera.global_transform, camera_blend_duration)
	_camera_transition_tween.parallel().tween_property(_gatekeeper_trigger_camera, "fov", _previous_camera.fov, camera_blend_duration)
	_camera_transition_tween.finished.connect(_finalize_restore_player_camera)

func _finalize_restore_player_camera() -> void:
	if _player_inside_gatekeeper_area:
		return
	if _previous_camera and is_instance_valid(_previous_camera):
		_previous_camera.current = true
	_gatekeeper_trigger_camera.current = false

func _cancel_camera_transition_tween() -> void:
	if _camera_transition_tween and _camera_transition_tween.is_valid():
		_camera_transition_tween.kill()
	_camera_transition_tween = null

func _ensure_tux_render_priority() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node
	if player == null:
		return

	var player_root := player.get_parent() as Node
	if player_root == null:
		return

	var tux_sprite := player_root.get_node_or_null("Tux/Tux/AnimatedSprite3D") as AnimatedSprite3D
	if tux_sprite == null:
		return

	tux_sprite.render_priority = tux_render_priority
	_tux_priority_applied = true
