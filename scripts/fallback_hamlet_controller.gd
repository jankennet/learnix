extends Node3D

@export var portal_locked_color: Color = Color(0.55, 0.55, 0.55, 1.0)
@export var portal_unlocked_color: Color = Color(1.0, 0.86, 0.25, 1.0)
@export var camera_blend_duration: float = 0.45
@export var tux_render_priority: int = 3
@export var tutorial_arrow_bob_amplitude: float = 0.24
@export var tutorial_arrow_bob_speed: float = 2.8

const COMBAT_TUTORIAL_POPUP_SCENE_PATH := "res://Scenes/combat/combat_tutorial_popup.tscn"
const WORLD_TUTORIAL_DONE_KEY := "fallback_hamlet_world_arrow_tutorial_done"
const HAMLET_PHASE_ONE_DONE_KEY := "fallback_hamlet_talk_to_forest_tutorial_done"
const FOREST_BAG_HINT_DONE_KEY := "forest_bag_item_hint_done"
const SHOP_TUTORIAL_PENDING_KEY := "fallback_hamlet_shop_tutorial_pending"
const SHOP_OPENED_ONCE_KEY := "fallback_hamlet_shop_opened_once"

enum WorldTutorialState {
	DISABLED,
	TALK_TO_MESSY,
	GO_TO_FOREST_HINT,
	GO_TO_FOREST_TELEPORT,
	SHOP_PROMPT,
	COMPLETED,
}

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
var _world_tutorial_state: int = WorldTutorialState.DISABLED
var _world_tutorial_flow_running: bool = false
var _arrow_root: Node3D = null
var _arrow_to_use_shop: Sprite3D = null
var _arrow_talk_to_md: Sprite3D = null
var _arrow_to_forest_hint: Sprite3D = null
var _arrow_to_forest_tp: Sprite3D = null
var _forest_hint_area: Area3D = null
var _forest_tp_area: Area3D = null
var _tutorial_arrow_base_positions: Dictionary = {}
var _player_entered_forest_hint_area: bool = false

func _ready() -> void:
	_setup_portal_nodes()
	_setup_gatekeeper_camera_nodes()
	_setup_gatekeeper_trigger_area()
	_setup_world_arrow_tutorial_nodes()
	_refresh_portal_color(true)
	_ensure_tux_render_priority()
	call_deferred("_start_world_arrow_tutorial_if_needed")

func _process(delta: float) -> void:
	_refresh_portal_color(false)
	if not _tux_priority_applied:
		_ensure_tux_render_priority()
	_update_tutorial_arrow_bobbing(delta)
	_update_world_arrow_tutorial_progress()

func _setup_world_arrow_tutorial_nodes() -> void:
	_arrow_root = get_node_or_null("Fallback_Hamlet_Final/VisualCuesArrowsTutorial") as Node3D
	if _arrow_root == null:
		return

	_arrow_to_use_shop = _arrow_root.get_node_or_null("ArrowtoUseshop") as Sprite3D
	_arrow_talk_to_md = _arrow_root.get_node_or_null("ArrowtalktoMD") as Sprite3D
	_arrow_to_forest_tp = _arrow_root.get_node_or_null("ArrowtoForestTP") as Sprite3D
	_arrow_to_forest_hint = _arrow_root.get_node_or_null("ArrowtoForest") as Sprite3D
	if _arrow_to_forest_hint:
		_forest_hint_area = _arrow_to_forest_hint.get_node_or_null("Area3D") as Area3D

	_forest_tp_area = get_node_or_null("Fallback_Hamlet_Final/ForestTP") as Area3D

	var tutorial_arrows: Array[Sprite3D] = [
		_arrow_to_use_shop,
		_arrow_talk_to_md,
		_arrow_to_forest_hint,
		_arrow_to_forest_tp,
	]
	for arrow in tutorial_arrows:
		if arrow == null:
			continue
		_tutorial_arrow_base_positions[arrow] = arrow.position
		arrow.visible = false

	if _forest_hint_area and not _forest_hint_area.body_entered.is_connected(_on_forest_hint_area_body_entered):
		_forest_hint_area.body_entered.connect(_on_forest_hint_area_body_entered)

func _start_world_arrow_tutorial_if_needed() -> void:
	if SceneManager == null:
		return
	if _arrow_root == null:
		return
	if _is_world_arrow_tutorial_complete():
		_hide_all_world_tutorial_arrows()
		_world_tutorial_state = WorldTutorialState.COMPLETED
		return
	if _should_run_return_shop_tutorial():
		if _world_tutorial_flow_running:
			return
		_world_tutorial_flow_running = true
		call_deferred("_run_return_shop_tutorial_intro")
		return
	if _is_hamlet_phase_one_done():
		_hide_all_world_tutorial_arrows()
		_world_tutorial_state = WorldTutorialState.DISABLED
		return
	if _world_tutorial_flow_running:
		return

	_world_tutorial_flow_running = true
	call_deferred("_run_world_arrow_tutorial_intro")

func _run_world_arrow_tutorial_intro() -> void:
	await _wait_for_scene_manager_world_guide_popup()

	if _is_world_arrow_tutorial_complete():
		_world_tutorial_flow_running = false
		_world_tutorial_state = WorldTutorialState.COMPLETED
		_hide_all_world_tutorial_arrows()
		return

	_show_only_tutorial_arrow(_arrow_talk_to_md)
	await _wait_for_scene_manager_world_guide_popup()

	_world_tutorial_flow_running = false
	if _is_world_arrow_tutorial_complete():
		_world_tutorial_state = WorldTutorialState.COMPLETED
		_hide_all_world_tutorial_arrows()
		return

	if _has_started_messy_directory_quest():
		_set_world_tutorial_state(WorldTutorialState.GO_TO_FOREST_HINT)
	else:
		_set_world_tutorial_state(WorldTutorialState.TALK_TO_MESSY)

func _wait_for_scene_manager_world_guide_popup() -> void:
	while get_tree().root.find_child("PostTutorialGuideCanvas", true, false) != null:
		await get_tree().process_frame

func _run_return_shop_tutorial_intro() -> void:
	while get_tree().root.find_child("PostTutorialGuideCanvas", true, false) != null:
		await get_tree().process_frame
	await _wait_for_scene_ready_for_tutorial()

	if _is_world_arrow_tutorial_complete():
		_world_tutorial_flow_running = false
		_world_tutorial_state = WorldTutorialState.COMPLETED
		_hide_all_world_tutorial_arrows()
		return

	_set_world_tutorial_state(WorldTutorialState.SHOP_PROMPT)
	await _show_world_tutorial_popup(
		"Spend Data Bits",
		"Now that you're back, spend your Data Bits at the shop, or type 'shop' in terminal.",
		"Follow the arrow to the shop to continue.",
		"map_navigation"
	)

	_world_tutorial_flow_running = false

func _wait_for_scene_ready_for_tutorial() -> void:
	for _i in range(4):
		await get_tree().process_frame

	while true:
		var current_scene := get_tree().current_scene
		var in_hamlet := current_scene != null and String(current_scene.scene_file_path) == "res://Scenes/Levels/fallback_hamlet.tscn"
		var has_player := get_tree().get_first_node_in_group("player") != null
		var unlocked := SceneManager == null or not bool(SceneManager.input_locked)
		if in_hamlet and has_player and unlocked:
			break
		await get_tree().process_frame

func _show_world_tutorial_popup(title: String, body: String, footer: String, visual_kind: String) -> void:
	var popup_scene := load(COMBAT_TUTORIAL_POPUP_SCENE_PATH)
	if not (popup_scene is PackedScene):
		return

	var popup_instance := (popup_scene as PackedScene).instantiate()
	if popup_instance == null:
		return

	var popup_layer := CanvasLayer.new()
	popup_layer.name = "FallbackWorldArrowTutorialPopup"
	popup_layer.layer = 278
	get_tree().root.add_child(popup_layer)
	popup_layer.add_child(popup_instance)

	if not popup_instance.has_method("show_popup") or not popup_instance.has_signal("closed"):
		popup_layer.queue_free()
		return

	popup_instance.call("show_popup", title, body, footer, visual_kind)
	await popup_instance.closed
	popup_layer.queue_free()

func _update_world_arrow_tutorial_progress() -> void:
	if _world_tutorial_flow_running:
		return
	if _world_tutorial_state == WorldTutorialState.DISABLED or _world_tutorial_state == WorldTutorialState.COMPLETED:
		return
	if _is_world_arrow_tutorial_complete():
		_complete_world_arrow_tutorial()
		return

	match _world_tutorial_state:
		WorldTutorialState.TALK_TO_MESSY:
			if _has_started_messy_directory_quest():
				_set_world_tutorial_state(WorldTutorialState.GO_TO_FOREST_HINT)
		WorldTutorialState.GO_TO_FOREST_HINT:
			if _player_entered_forest_hint_area or _is_player_inside_area(_forest_hint_area):
				_set_world_tutorial_state(WorldTutorialState.GO_TO_FOREST_TELEPORT)
		WorldTutorialState.GO_TO_FOREST_TELEPORT:
			if _did_player_confirm_forest_teleport():
				_mark_hamlet_phase_one_done()
				_hide_all_world_tutorial_arrows()
				_world_tutorial_state = WorldTutorialState.DISABLED
		WorldTutorialState.SHOP_PROMPT:
			if _has_opened_shop_once():
				_complete_world_arrow_tutorial()
		_:
			pass

func _set_world_tutorial_state(new_state: int) -> void:
	if _world_tutorial_state == new_state:
		return
	_world_tutorial_state = new_state

	match _world_tutorial_state:
		WorldTutorialState.TALK_TO_MESSY:
			_show_only_tutorial_arrow(_arrow_talk_to_md)
		WorldTutorialState.GO_TO_FOREST_HINT:
			_show_only_tutorial_arrow(_arrow_to_forest_hint)
		WorldTutorialState.GO_TO_FOREST_TELEPORT:
			_show_only_tutorial_arrow(_arrow_to_forest_tp)
		WorldTutorialState.SHOP_PROMPT:
			_show_only_tutorial_arrow(_arrow_to_use_shop)
		WorldTutorialState.COMPLETED, WorldTutorialState.DISABLED:
			_hide_all_world_tutorial_arrows()

func _show_only_tutorial_arrow(target_arrow: Sprite3D) -> void:
	if _arrow_to_use_shop:
		_arrow_to_use_shop.visible = (_arrow_to_use_shop == target_arrow)
	if _arrow_talk_to_md:
		_arrow_talk_to_md.visible = (_arrow_talk_to_md == target_arrow)
	if _arrow_to_forest_hint:
		_arrow_to_forest_hint.visible = (_arrow_to_forest_hint == target_arrow)
	if _arrow_to_forest_tp:
		_arrow_to_forest_tp.visible = (_arrow_to_forest_tp == target_arrow)

func _hide_all_world_tutorial_arrows() -> void:
	if _arrow_to_use_shop:
		_arrow_to_use_shop.visible = false
	if _arrow_talk_to_md:
		_arrow_talk_to_md.visible = false
	if _arrow_to_forest_hint:
		_arrow_to_forest_hint.visible = false
	if _arrow_to_forest_tp:
		_arrow_to_forest_tp.visible = false

func _update_tutorial_arrow_bobbing(_delta: float) -> void:
	if _tutorial_arrow_base_positions.is_empty():
		return

	var bob_offset := sin(Time.get_ticks_msec() * 0.001 * tutorial_arrow_bob_speed) * tutorial_arrow_bob_amplitude
	for arrow_variant in _tutorial_arrow_base_positions.keys():
		if not (arrow_variant is Sprite3D):
			continue
		var arrow := arrow_variant as Sprite3D
		if arrow == null or not is_instance_valid(arrow):
			continue
		var base_position: Variant = _tutorial_arrow_base_positions.get(arrow)
		if not (base_position is Vector3):
			continue
		var base_vector := base_position as Vector3
		arrow.position = Vector3(base_vector.x, base_vector.y + bob_offset, base_vector.z)

func _is_world_arrow_tutorial_complete() -> bool:
	if SceneManager == null:
		return false
	return bool(SceneManager.get_meta(WORLD_TUTORIAL_DONE_KEY, false))

func _complete_world_arrow_tutorial() -> void:
	if SceneManager:
		SceneManager.set_meta(WORLD_TUTORIAL_DONE_KEY, true)
		SceneManager.set_meta(SHOP_TUTORIAL_PENDING_KEY, false)
	_world_tutorial_state = WorldTutorialState.COMPLETED
	_world_tutorial_flow_running = false
	_hide_all_world_tutorial_arrows()

func _mark_hamlet_phase_one_done() -> void:
	if SceneManager == null:
		return
	SceneManager.set_meta(HAMLET_PHASE_ONE_DONE_KEY, true)

func _is_hamlet_phase_one_done() -> bool:
	if SceneManager == null:
		return false
	return bool(SceneManager.get_meta(HAMLET_PHASE_ONE_DONE_KEY, false))

func _should_run_return_shop_tutorial() -> bool:
	if SceneManager == null:
		return false
	if not bool(SceneManager.get_meta(HAMLET_PHASE_ONE_DONE_KEY, false)):
		return false
	if not bool(SceneManager.get_meta(FOREST_BAG_HINT_DONE_KEY, false)):
		return false
	if not bool(SceneManager.get_meta(SHOP_TUTORIAL_PENDING_KEY, false)):
		return false
	return not _has_opened_shop_once()

func _has_opened_shop_once() -> bool:
	if SceneManager == null:
		return false
	return bool(SceneManager.get_meta(SHOP_OPENED_ONCE_KEY, false))

func _has_started_messy_directory_quest() -> bool:
	if SceneManager == null:
		return false

	if bool(SceneManager.get("met_messy_directory")):
		return true

	if not SceneManager.quest_manager:
		return false
	var quest := SceneManager.quest_manager.get_quest("find_lost_file")
	if quest == null:
		return false

	var quest_status := String(quest.status)
	return quest_status == "active" or quest_status == "completed" or quest_status == "failed"

func _is_player_inside_area(area: Area3D) -> bool:
	if area == null:
		return false
	for body in area.get_overlapping_bodies():
		if body is Node and (body as Node).is_in_group("player"):
			return true
	return false

func _did_player_confirm_forest_teleport() -> bool:
	if _forest_tp_area == null:
		return false
	if not _is_player_inside_area(_forest_tp_area):
		return false
	return Input.is_action_just_pressed("interact")

func _on_forest_hint_area_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_entered_forest_hint_area = true

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
