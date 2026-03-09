class_name PartNodes
extends RefCounted

var part: Node3D

"""
Initialize the PartNodes with the owning part node.
@type: void
@param: owner node that this PartNodes instance will reference (Node3D)
"""
func setup(owner: Node3D) -> void:
	part = owner

"""
Find a child Node3D by name, or return null if not found or wrong type.
@type: Node3D or null
@param: name of the child node to find (String)
"""
func find_node3d(name_: String) -> Node3D:
	if part == null:
		return null

	var n := part.get_node_or_null(name_)
	if n is Node3D:
		return n as Node3D

	return null

"""
Find a StaticBody3D child, preferring one named "Body", or return null if not found.
@type: StaticBody3D or null
@param: none
"""
func find_body() -> StaticBody3D:
	if part == null:
		return null

	var b := part.get_node_or_null("Body")
	if b is StaticBody3D:
		return b as StaticBody3D

	for c in part.get_children():
		if c is StaticBody3D:
			return c as StaticBody3D

	return null

"""
Find a child node by name under a given root, or return null if not found.
@type: Node or null
@param: root node to search under (Node), name of the child node to find (String)
"""
func find_under(root: Node, child_name: String) -> Node:
	if root == null:
		return null

	return root.get_node_or_null(child_name)

"""
Helper to get all MeshInstance3D nodes under a given container, or an empty array if none.
@type: Array[MeshInstance3D]
@param: container node to search under (Node3D)
"""
func get_meshes_from(container: Node3D) -> Array[MeshInstance3D]:
	var arr: Array[MeshInstance3D] = []

	if container == null:
		return arr

	for c in container.get_children():
		if c is MeshInstance3D:
			arr.append(c as MeshInstance3D)

	return arr

"""
Get all MeshInstance3D nodes under the meshes_container, or an empty array if none.
@type: Array[MeshInstance3D]
@param: none
"""
func get_meshes(meshes_container: Node3D) -> Array[MeshInstance3D]:
	return get_meshes_from(meshes_container)

"""
Get all MeshInstance3D nodes under the ghost_container, or an empty array if none.
@type: Array[MeshInstance3D]
@param: none
"""
func get_ghost_meshes(ghost_container: Node3D) -> Array[MeshInstance3D]:
	return get_meshes_from(ghost_container)
