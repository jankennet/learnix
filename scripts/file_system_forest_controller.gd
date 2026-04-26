extends Node3D

@export var tutorial_arrow_bob_amplitude: float = 0.22
@export var tutorial_arrow_bob_speed: float = 2.9

const FOREST_ARROW_DONE_KEY := "forest_lost_file_arrow_tutorial_done"
const BAG_HINT_PENDING_KEY := "forest_bag_item_hint_pending"
const BAG_HINT_DONE_KEY := "forest_bag_item_hint_done"

enum ForestArrowState {
	DISABLED,
	GO_TO_LOST_FILE,
	TALK_TO_LOST_FILE,
	DONE,
}

var _arrow_to_lf: Sprite3D = null
var _arrow_talk_to_lf: Sprite3D = null
var _arrow_to_lf_area: Area3D = null
var _base_positions: Dictionary = {}
var _entered_lost_file_area: bool = false
var _state: int = ForestArrowState.DISABLED

func _ready() -> void:
	_arrow_to_lf = get_node_or_null("Forest/ArrowtoLF") as Sprite3D
	_arrow_talk_to_lf = get_node_or_null("NPC/Lost File/ArrowtalktoLF") as Sprite3D
	if _arrow_to_lf:
		_arrow_to_lf_area = _arrow_to_lf.get_node_or_null("Area3D") as Area3D

	_register_arrow(_arrow_to_lf)
	_register_arrow(_arrow_talk_to_lf)
	_hide_all_arrows()

	if _arrow_to_lf_area and not _arrow_to_lf_area.body_entered.is_connected(_on_lost_file_area_body_entered):
		_arrow_to_lf_area.body_entered.connect(_on_lost_file_area_body_entered)

	if _is_tutorial_done():
		_state = ForestArrowState.DONE
		return

	if _has_resolved_lost_file_arc():
		_set_done_and_request_bag_hint()
		return

	if _has_interacted_with_lost_file() or _is_player_inside_area(_arrow_to_lf_area):
		_set_state(ForestArrowState.TALK_TO_LOST_FILE)
	else:
		_set_state(ForestArrowState.GO_TO_LOST_FILE)

func _process(_delta: float) -> void:
	_update_arrow_bobbing()
	_update_tutorial_progress()

func _update_tutorial_progress() -> void:
	if _state == ForestArrowState.DISABLED or _state == ForestArrowState.DONE:
		return

	if _has_resolved_lost_file_arc():
		_set_done_and_request_bag_hint()
		return

	if _state == ForestArrowState.GO_TO_LOST_FILE:
		if _entered_lost_file_area or _is_player_inside_area(_arrow_to_lf_area):
			_set_state(ForestArrowState.TALK_TO_LOST_FILE)

func _set_state(new_state: int) -> void:
	if _state == new_state:
		return
	_state = new_state

	match _state:
		ForestArrowState.GO_TO_LOST_FILE:
			_show_only_arrow(_arrow_to_lf)
		ForestArrowState.TALK_TO_LOST_FILE:
			_show_only_arrow(_arrow_talk_to_lf)
		ForestArrowState.DONE, ForestArrowState.DISABLED:
			_hide_all_arrows()

func _set_done_and_request_bag_hint() -> void:
	_state = ForestArrowState.DONE
	_hide_all_arrows()
	if SceneManager:
		SceneManager.set_meta(FOREST_ARROW_DONE_KEY, true)
		if not bool(SceneManager.get_meta(BAG_HINT_DONE_KEY, false)):
			SceneManager.set_meta(BAG_HINT_PENDING_KEY, true)

func _register_arrow(arrow: Sprite3D) -> void:
	if arrow == null:
		return
	_base_positions[arrow] = arrow.position

func _show_only_arrow(target_arrow: Sprite3D) -> void:
	if _arrow_to_lf:
		_arrow_to_lf.visible = (_arrow_to_lf == target_arrow)
	if _arrow_talk_to_lf:
		_arrow_talk_to_lf.visible = (_arrow_talk_to_lf == target_arrow)

func _hide_all_arrows() -> void:
	if _arrow_to_lf:
		_arrow_to_lf.visible = false
	if _arrow_talk_to_lf:
		_arrow_talk_to_lf.visible = false

func _update_arrow_bobbing() -> void:
	if _base_positions.is_empty():
		return

	var bob_offset := sin(Time.get_ticks_msec() * 0.001 * tutorial_arrow_bob_speed) * tutorial_arrow_bob_amplitude
	for arrow_variant in _base_positions.keys():
		if not (arrow_variant is Sprite3D):
			continue
		var arrow := arrow_variant as Sprite3D
		if arrow == null or not is_instance_valid(arrow):
			continue
		var base_position: Variant = _base_positions.get(arrow)
		if not (base_position is Vector3):
			continue
		var base_vector := base_position as Vector3
		arrow.position = Vector3(base_vector.x, base_vector.y + bob_offset, base_vector.z)

func _on_lost_file_area_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_entered_lost_file_area = true
		if _state == ForestArrowState.GO_TO_LOST_FILE:
			_set_state(ForestArrowState.TALK_TO_LOST_FILE)

func _is_tutorial_done() -> bool:
	if SceneManager == null:
		return false
	return bool(SceneManager.get_meta(FOREST_ARROW_DONE_KEY, false))

func _has_interacted_with_lost_file() -> bool:
	if SceneManager == null:
		return false
	if SceneManager.has_method("has_interacted_with_npc"):
		return bool(SceneManager.call("has_interacted_with_npc", "Lost File"))
	return bool(SceneManager.get("met_lost_file"))

func _has_resolved_lost_file_arc() -> bool:
	if SceneManager == null:
		return false
	return bool(SceneManager.get("helped_lost_file")) or bool(SceneManager.get("deleted_lost_file"))

func _is_player_inside_area(area: Area3D) -> bool:
	if area == null:
		return false
	for body in area.get_overlapping_bodies():
		if body is Node and (body as Node).is_in_group("player"):
			return true
	return false
