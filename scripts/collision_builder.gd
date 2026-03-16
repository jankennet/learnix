extends Node3D

# Builds trimesh colliders from MeshInstance3D nodes at runtime.
# Reuse this on any level root/instance that should block player movement.
func _ready() -> void:
	_add_trimesh_colliders(self)

func _add_trimesh_colliders(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh and not _has_static_collision(mesh_instance):
			mesh_instance.create_trimesh_collision()

	for child in node.get_children():
		_add_trimesh_colliders(child)

func _has_static_collision(mesh_instance: MeshInstance3D) -> bool:
	for child in mesh_instance.get_children():
		if child is StaticBody3D:
			return true
	return false
