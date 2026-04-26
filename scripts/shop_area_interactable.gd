extends Area3D

@export var interact_prompt: String = "Open Skill Shop"

var _player_inside: bool = false

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	if InteractionManager.current_interactable == null or InteractionManager.current_interactable == self:
		InteractionManager.current_interactable = self

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = false
	if InteractionManager.current_interactable == self:
		InteractionManager.current_interactable = null

func get_interact_prompt() -> String:
	return interact_prompt

func on_interact() -> void:
	if not _player_inside:
		return

	var sm := get_node_or_null("/root/SceneManager")
	if sm and sm.input_locked:
		return

	var main_hud := get_tree().root.find_child("MainHUD", true, false)
	if main_hud and main_hud.has_method("_open_shop_from_terminal"):
		main_hud.call("_open_shop_from_terminal")