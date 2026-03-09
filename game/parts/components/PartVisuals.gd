class_name PartVisuals
extends RefCounted

var meshes_container: Node3D
var outline: Node3D
var _allow_real_outline := true

"""
Initializes the PartVisuals with the given meshes container and outline nodes.
@type: void
@param: the node that contains the meshes (Node3D),
	node that represents the outline (Node3D)
"""
func setup(meshes_node: Node3D, outline_node: Node3D) -> void:
	meshes_container = meshes_node
	outline = outline_node

"""
Set the visibility of the real outline, if it exists, based on 
the given value and whether real outlines are allowed.
@type: void
@param: whether the real outline should be visible (bool)
"""
func set_real_outline(v: bool) -> void:
	if outline:
		outline.visible = v and _allow_real_outline

"""
Set the visibility of all meshes in the meshes_container based on the given value.
@type: void
@param: whether the meshes should be visible (bool)
"""
func set_meshes_visible(v: bool) -> void:
	if meshes_container:
		meshes_container.visible = v

"""
Set whether the real outline is enabled.
@type: void
@param: whether the real outline is enabled (bool)
"""
func set_real_outline_enabled(v: bool) -> void:
	_allow_real_outline = v
	if not v:
		set_real_outline(false)
