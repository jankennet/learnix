extends Area3D

@export var target_scene: String
@export var spawn_name: String
@export var location_name: String = "Unknown Location"
@export var delay: float = 1.0

var can_teleport := true
var player: CharacterBody3D
var player_inside := false

func _ready():
	monitoring = true
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)
	print("[Teleporter] ready - signals connected")
	set_process(true)

func _on_enter(body):
	if body.is_in_group("player"):
		player = body
		player_inside = true
		print("Player in teleporter area:", target_scene)
		# register as current interactable so global interact works
		InteractionManager.current_interactable = self

func _on_exit(body):
	if body.is_in_group("player"):
		player_inside = false
		print("Player exited teleporter area")
		if InteractionManager.current_interactable == self:
			InteractionManager.current_interactable = null


func _process(_delta):
	# Block interaction if input is locked (e.g., during combat)
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.input_locked:
		return
	
	if player_inside and Input.is_action_just_pressed("interact") and can_teleport:
		print("Pressed E → Teleporting to:", target_scene)
		can_teleport = false
		call_deferred("_do_teleport")


func on_interact() -> void:
	# Called by InteractionManager when the player presses the global interact key
	# Block if input is locked
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.input_locked:
		return
	
	if player_inside and can_teleport:
		can_teleport = false
		call_deferred("_do_teleport")


func _do_teleport():
	if not is_instance_valid(player):
		push_error("Player reference lost!")
		can_teleport = true
		return

	print("Teleporting to:", target_scene)

	var transfer_node: Node = player
	var player_parent_for_transfer := player.get_parent()
	if player_parent_for_transfer and player_parent_for_transfer != get_tree().current_scene and player_parent_for_transfer.name == "Player":
		transfer_node = player_parent_for_transfer

	var player_parent = transfer_node.get_parent()
	if player_parent:
		player_parent.remove_child(transfer_node)

	await get_tree().create_timer(delay).timeout

	var new_scene_res = load(target_scene)
	if not new_scene_res:
		push_error("Failed to load scene: " + target_scene)
		can_teleport = true
		return

	var new_scene = new_scene_res.instantiate()
	var root = get_tree().root

	if get_tree().current_scene:
		get_tree().current_scene.queue_free()

	root.add_child(new_scene)
	get_tree().current_scene = new_scene

	new_scene.add_child(transfer_node)

	# ✅ Spawn search
	var spawn: Node3D = new_scene.get_node_or_null(spawn_name)
	if spawn == null:
		spawn = _find_node_recursive(new_scene, spawn_name)
	if spawn == null:
		var spawns = get_tree().get_nodes_in_group("spawn_point")
		if spawns.size() > 0:
			spawn = spawns[0]
			print("⚠️ Fallback spawn used:", spawn.name)

	if spawn:
		_apply_spawn_transform(transfer_node, player, spawn.global_transform)
	else:
		push_warning("No spawn found! Player at default pos")

	# ✅ ✅ NPC animation restore
	if new_scene.has_node("NPC"):
		var npc_root = new_scene.get_node("NPC")
		for npc in npc_root.get_children():
			if npc.has_method("on_scene_activated"):
				npc.call_deferred("on_scene_activated")

	# ✅ Restore camera
	await get_tree().create_timer(0.1).timeout
	var cam = player.get_node_or_null("Camera3D")
	if cam:
		cam.current = true

	can_teleport = true


func _apply_spawn_transform(transfer_node: Node, active_player: CharacterBody3D, spawn_transform: Transform3D) -> void:
	var yaw := spawn_transform.basis.get_euler().y
	var target_player_transform := Transform3D(Basis(Vector3.UP, yaw), spawn_transform.origin)

	if transfer_node == active_player:
		active_player.global_transform = target_player_transform
		return

	var transfer_node_3d := transfer_node as Node3D
	if transfer_node_3d:
		var player_local_transform := active_player.transform
		transfer_node_3d.global_transform = target_player_transform * player_local_transform.affine_inverse()
		active_player.global_transform = target_player_transform
		return

	active_player.global_transform = target_player_transform


func _find_node_recursive(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found = _find_node_recursive(child, node_name)
		if found:
			return found
	return null
