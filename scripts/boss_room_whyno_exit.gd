extends Area3D

@export var dialogue_resource_path: String = "res://dialogues/PrinterBossRoomExitHint.dialogue"
@export var dialogue_start_title: String = "start"
@export var interact_prompt: String = "Inspect Teleporter"

var _player_inside: bool = false
var _dialogue_resource: Resource = null

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if dialogue_resource_path != "" and ResourceLoader.exists(dialogue_resource_path):
		_dialogue_resource = ResourceLoader.load(dialogue_resource_path)

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

	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.input_locked:
		return

	var dm = get_node_or_null("/root/DialogueManager")
	if dm and dm.has_method("show_dialogue_balloon") and _dialogue_resource != null:
		dm.show_dialogue_balloon(_dialogue_resource, dialogue_start_title, [self])
