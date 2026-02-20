# interaction_prompt.gd
# Shows "Press E to Interact" prompt when player is near interactable objects
# Listens to InteractionManager.current_interactable changes
extends CanvasLayer

@onready var prompt_container: CenterContainer = $PromptContainer
@onready var key_label: Label = $PromptContainer/PromptPanel/HBox/KeyLabel
@onready var action_label: Label = $PromptContainer/PromptPanel/HBox/ActionLabel

var _last_interactable: Node = null

func _ready() -> void:
	# Start hidden
	prompt_container.visible = false

func _process(_delta: float) -> void:
	# Check InteractionManager for current interactable
	var im = _get_interaction_manager()
	if not im:
		prompt_container.visible = false
		return
	
	# Don't show prompt if input is locked (during combat, dialogue, etc.)
	if SceneManager and SceneManager.input_locked:
		prompt_container.visible = false
		return
	
	var interactable = im.current_interactable
	
	if interactable and is_instance_valid(interactable):
		# Show prompt
		prompt_container.visible = true
		
		# Update text based on interactable type
		if interactable != _last_interactable:
			_update_prompt_text(interactable)
			_last_interactable = interactable
	else:
		# Hide prompt
		prompt_container.visible = false
		_last_interactable = null

func _update_prompt_text(interactable: Node) -> void:
	# Determine action text based on the interactable
	var action_text := "Interact"
	
	# Check if it's a teleporter
	if interactable.has_method("_do_teleport") or "target_scene" in interactable:
		action_text = "Travel"
		if "location_name" in interactable and interactable.location_name != "":
			action_text = "Travel to: " + interactable.location_name + "?"
		elif "spawn_name" in interactable:
			action_text = "Travel to: " + interactable.spawn_name + "?"
	# Check if it's an NPC
	elif interactable.is_in_group("npcs"):
		action_text = "Talk"
		# Try to get NPC name
		if "npc_name" in interactable:
			action_text = "Talk to " + interactable.npc_name
		elif "name" in interactable:
			action_text = "Talk to " + interactable.name
	
	# Check for custom interaction text
	if interactable.has_method("get_interact_prompt"):
		action_text = interactable.get_interact_prompt()
	elif "interact_prompt" in interactable:
		action_text = interactable.interact_prompt
	
	action_label.text = action_text

func _get_interaction_manager() -> Node:
	if Engine.has_singleton("InteractionManager"):
		return Engine.get_singleton("InteractionManager")
	return get_tree().root.get_node_or_null("InteractionManager")
