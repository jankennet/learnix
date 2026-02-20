extends Area3D

@export var level_name: String = "Fallback Hamlet"
@export var npc_scenes: Array[PackedScene] = []  # Assign your NPC scenes here
@export var npc_positions: Array[Vector3] = []   # Positions for each NPC
@export var npc_rotations: Array[Vector3] = []   # Optional: rotations for each NPC

var npc_instances: Array = []
var player_in_area: bool = false

func _ready():
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Spawn NPCs when level loads
	spawn_npcs()

func _on_body_entered(body: Node3D):
	if body.is_in_group("player"):
		player_in_area = true
		print("Player entered: ", level_name)
		activate_npcs()

func _on_body_exited(body: Node3D):
	if body.is_in_group("player"):
		player_in_area = false
		print("Player left: ", level_name)
		deactivate_npcs()

func spawn_npcs():
	for i in range(npc_scenes.size()):
		if i < npc_positions.size() and npc_scenes[i]:
			var npc_instance = npc_scenes[i].instantiate()
			get_parent().add_child(npc_instance)  # Add to level, not area
			
			# Set position
			npc_instance.global_position = global_position + npc_positions[i]
			
			# Set rotation if provided
			if i < npc_rotations.size():
				npc_instance.rotation_degrees = npc_rotations[i]
			
			npc_instances.append(npc_instance)

func activate_npcs():
	for npc in npc_instances:
		if npc.has_method("set_active"):
			npc.set_active(true)

func deactivate_npcs():
	for npc in npc_instances:
		if npc.has_method("set_active"):
			npc.set_active(false)
