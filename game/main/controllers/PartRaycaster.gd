class_name PartRaycaster
extends RefCounted

const LAYER_SOLID := 1 << 0
const LAYER_GHOST := 1 << 1
const MODE_MOUNT := 0
const MODE_DISMOUNT := 1

var world_owner: Node3D
var camera: Camera3D
var mode_getter: Callable

"""
Set up the raycaster with the necessary references.
@type: void
@param: the node that owns the world (Node3D),
	camera to raycast from (Camera3D),
	callable to get the current mode (Callable)
"""
func setup(owner: Node3D, cam: Camera3D, get_mode: Callable) -> void:
	world_owner = owner
	camera = cam
	mode_getter = get_mode

"""
Find the nearest ancestor of a node that is a part (has try_mount and try_dismount methods).
@type: Node3D
@param: the node to start searching from (Node)
"""
func _find_part_ancestor(n: Node) -> Node3D:
	var cur: Node = n

	while cur != null:
		if cur.has_method("try_mount") and cur.has_method("try_dismount"):
			return cur as Node3D

		cur = cur.get_parent()

	return null

"""
Return the part that was hit by the ray and whether it is a ghost part or not
@type: Dictionary
@param: the object that was hit by the ray (Object)
"""
func _get_part_and_is_ghost(hit: Object) -> Dictionary:
	if hit is Node:
		var part := _find_part_ancestor(hit as Node)

		if part == null:
			return {"part": null, "is_ghost": false}

		var is_ghost := hit is Area3D
		return {"part": part, "is_ghost": is_ghost}

	return {"part": null, "is_ghost": false}

"""
Raycast into the scene from the given screen position. 
First check for ghost parts, then solid parts.
@type: Dictionary
@param: screen position to raycast from (Vector2)
"""
func _raycast_from_screen(screen_pos: Vector2) -> Dictionary:
	if world_owner == null or camera == null:
		return {"part": null, "is_ghost": false}

	var space := world_owner.get_world_3d().direct_space_state
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 100.0

	# Query ghost
	var qg := PhysicsRayQueryParameters3D.create(from, to)
	qg.collide_with_areas = true
	qg.collide_with_bodies = false
	qg.collision_mask = LAYER_GHOST
	var rg := space.intersect_ray(qg)

	# Query solid
	var qs := PhysicsRayQueryParameters3D.create(from, to)
	qs.collide_with_areas = false
	qs.collide_with_bodies = true
	qs.collision_mask = LAYER_SOLID
	var rs := space.intersect_ray(qs)

	var mode: Variant = mode_getter.call()

	if mode == MODE_DISMOUNT:
		if not rs.is_empty() and rs.collider:
			return _get_part_and_is_ghost(rs.collider)

		return {"part": null, "is_ghost": false}

	if not rg.is_empty() and rg.collider:
		return _get_part_and_is_ghost(rg.collider)

	if not rs.is_empty() and rs.collider:
		return _get_part_and_is_ghost(rs.collider)

	return {"part": null, "is_ghost": false}

"""
Return the part under the mouse cursor by raycasting into the scene.
@type: Node3D
@param: screen position of the mouse (Vector2)
"""
func get_part_under_mouse(screen_pos: Vector2) -> Node3D:
	var info := _raycast_from_screen(screen_pos)
	return info["part"] as Node3D
