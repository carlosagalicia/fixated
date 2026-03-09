class_name PartGhost
extends RefCounted

const LAYER_GHOST := 1 << 1

var ghost_container: Node3D
var ghost_hit: Area3D
var nodes: PartNodes
var _ghost_hover_active := false
var _ghost_saved_colors: Dictionary = {}

"""
Initialize the PartGhost with the given ghost container node, ghost hit area, and part nodes helper.
@type: void
@param: ghost container node (Node3D), 
	ghost hit area (Area3D), 
	part nodes helper (PartNodes)
"""
func setup(ghost_node: Node3D, ghost_hit_node: Area3D, nodes_helper: PartNodes) -> void:
	ghost_container = ghost_node
	ghost_hit = ghost_hit_node
	nodes = nodes_helper

"""
Set the visibility and collision properties of the ghost based on 
the given value and whether the part is dismounted.
@type: void
@param: whether the ghost should be visible (bool)
"""
func set_ghost_visible(v: bool, is_dismounted: bool) -> void:
	var showg := v and is_dismounted
	_set_ghost_visible_internal(showg)

	if not showg:
		clear_hover()

"""
Set ghost visibility and collision properties.
@type: void
@param: whether the ghost should be visible (bool)
"""
func _set_ghost_visible_internal(showg: bool) -> void:
	if ghost_container:
		ghost_container.visible = showg

	if ghost_hit:
		ghost_hit.monitorable = showg
		ghost_hit.monitoring = showg
		ghost_hit.collision_layer = LAYER_GHOST if showg else 0
		ghost_hit.collision_mask = LAYER_GHOST if showg else 0

"""
Set the hover state of the part, affecting the real outline and 
ghost hover color based on whether it's a ghost or not.
@type: void
@param: whether the part is hovered (bool), 
		whether the hover is for a ghost (bool, default false)
"""
func set_hovered(is_hovered: bool) -> void:
	if ghost_container and ghost_container.visible and is_hovered:
		_set_hover_color(Color(0.6, 1.0, 0.6, 1.0))
	else:
		clear_hover()

"""
Update the position of the ghost container and ghost hit area to match 
the mounted global position if the ghost is visible.
@type: void
@param: delta time since last frame (float)
"""
func update_position(mounted_global_pos: Vector3) -> void:
	if ghost_container and ghost_container.visible:
		ghost_container.global_position = mounted_global_pos

		if ghost_hit:
			ghost_hit.global_position = mounted_global_pos

"""
Get or create a StandardMaterial3D for the given MeshInstance3D to be used for ghost hover coloring.
If the mesh already has a material override that is a StandardMaterial3D, it will be reused. 
Otherwise, a new material will be created by duplicating the active material or 
creating a new StandardMaterial3D if no active material exists.
@type: StandardMaterial3D
@param: MeshInstance3D for which to get or create the hover ghost material (MeshInstance3D)
"""
func _get_or_make_hover_material(g: MeshInstance3D) -> StandardMaterial3D:
	if g.material_override is StandardMaterial3D:
		return g.material_override as StandardMaterial3D

	var active := g.get_active_material(0)

	if active:
		g.material_override = active.duplicate()
	else:
		g.material_override = StandardMaterial3D.new()

	return g.material_override as StandardMaterial3D

"""
Set a hover color on all ghost meshes by getting or creating a hover 
ghost material and changing its albedo color.
The original colors are saved the first time this is called while hover is active,
and can be restored by calling _ghost_clear_hover_color.
@type: void
@param: color to set on the ghost meshes (Color)
"""
func _set_hover_color(color: Color) -> void:
	if nodes == null:
		return

	if not _ghost_hover_active:
		_ghost_saved_colors.clear()

		for g in nodes.get_ghost_meshes(ghost_container):
			var mat := _get_or_make_hover_material(g)
			_ghost_saved_colors[g] = mat.albedo_color

		_ghost_hover_active = true

	for g in nodes.get_ghost_meshes(ghost_container):
		var mat := _get_or_make_hover_material(g)
		mat.albedo_color = color

"""
Clear the hover color from all ghost meshes by restoring their 
original colors from the _ghost_saved_colors dictionary.
Called when hover is no longer active to revert 
the ghost meshes back to their original appearance.
@type: void
@param: none
"""
func clear_hover() -> void:
	if not _ghost_hover_active or nodes == null:
		return

	for g in nodes.get_ghost_meshes(ghost_container):
		var mat := _get_or_make_hover_material(g)
		if _ghost_saved_colors.has(g):
			mat.albedo_color = _ghost_saved_colors[g]

	_ghost_saved_colors.clear()
	_ghost_hover_active = false

"""
Immediately hide the ghost and clear any hover state without waiting for external conditions,
such as when the part is mounted or when the player cancels the placement.
@type: void
@param: none
"""
func hide_immediately() -> void:
	_set_ghost_visible_internal(false)
	clear_hover()
