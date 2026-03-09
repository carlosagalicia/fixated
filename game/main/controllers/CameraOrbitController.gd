class_name CameraOrbitController
extends RefCounted

const FRONT_PITCH := PI / 10.0
const TOP_PITCH := -PI / 2.0

var pivot: Node3D
var camera: Camera3D
var yaw_speed: float
var pitch_speed: float
var zoom_speed: float
var min_distance: float
var max_distance: float
var zoom_time: float
var yaw := 0.0
var pitch := 0.0
var distance := 0.0
var zoom_tween: Tween
var focus_min_distance := 2.0
var focus_max_distance := 10.0
var use_focus_limits := false

"""
Set up the camera controller with the given pivot and camera nodes, and configuration parameters.
@type: void
@param: the pivot node to rotate (Node3D),
	camera node to zoom (Camera3D),
	dictionary of configuration parameters (Dictionary)
"""
func setup(pivot_node: Node3D, camera_node: Camera3D, config: Dictionary) -> void:
	pivot = pivot_node
	camera = camera_node

	yaw_speed = config.get("yaw_speed", 2.5)
	pitch_speed = config.get("pitch_speed", 2.0)
	zoom_speed = config.get("zoom_speed", 0.5)
	min_distance = config.get("min_distance", 2.0)
	max_distance = config.get("max_distance", 3.0)
	zoom_time = config.get("zoom_time", 0.15)

"""
Initialize the camera's position and rotation based on the current scene setup.
Set the camera's position to be at a distance along the z-axis, 
and initialize yaw and pitch from the pivot's rotation.
@type: void
@param: none
"""
func initialize_from_scene() -> void:
	if camera == null or pivot == null:
		return

	camera.position.x = 0.0
	camera.position.y = 0.0
	camera.position.z = abs(camera.position.z)
	distance = camera.position.z

	var r := pivot.rotation
	yaw = r.y
	pitch = clamp(r.x, TOP_PITCH, FRONT_PITCH)
	pivot.rotation = Vector3(pitch, yaw, 0.0)

"""
Update the camera's rotation based on input actions. 
Yaw and pitch are updated according to the configured speeds and clamped to prevent flipping.
@type: void
@param: delta time since the last frame (float)
"""
func update_rotation(delta: float) -> void:
	if pivot == null:
		return

	var yaw_input := 0.0
	var pitch_input := 0.0

	if Input.is_action_pressed("cam_left"):
		yaw_input -= 1.0
	if Input.is_action_pressed("cam_right"):
		yaw_input += 1.0
	if Input.is_action_pressed("cam_up"):
		pitch_input -= 1.0
	if Input.is_action_pressed("cam_down"):
		pitch_input += 1.0

	yaw += yaw_input * yaw_speed * delta
	pitch += pitch_input * pitch_speed * delta
	pitch = clamp(pitch, TOP_PITCH, FRONT_PITCH)

	pivot.rotation = Vector3(pitch, yaw, 0.0)

"""
Zoom the camera in by decreasing the distance, clamped to the minimum distance.
@type: void
@param: none
"""
func zoom_in() -> void:
	zoom_to(distance - zoom_speed)

"""
Zoom the camera in by increasing the distance, clamped to the maximum distance.
@type: void
@param: none
"""
func zoom_out() -> void:
	zoom_to(distance + zoom_speed)

"""
Set the camera distance to the object
@type: void
@param: new distance (float)
"""
func zoom_to(new_distance: float) -> void:
	if camera == null:
		return

	var min_d := min_distance
	var max_d := max_distance

	if use_focus_limits:
		min_d = focus_min_distance
		max_d = focus_max_distance

	var target: float = clampf(new_distance, min_d, max_d)
	distance = target

	if zoom_tween and zoom_tween.is_running():
		zoom_tween.kill()

	zoom_tween = pivot.create_tween()
	zoom_tween.tween_property(
		camera,
		"position:z",
		distance,
		zoom_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

"""
Focus the camera on a part by tweening the pivot's global position to 
the part's focus position and zooming to a suitable distance.
@type: void
@param: the part to focus on (Node3D), whether the part is a ghost or not (bool)
"""
func focus_on_part(part: Node3D, is_ghost: bool) -> void:
	if part == null or pivot == null:
		return

	var focus_node := _get_focus_target_node(part, is_ghost)
	var aabb := _get_global_aabb(focus_node)
	var target_pos := aabb.get_center()

	var t := pivot.create_tween()
	t.tween_property(pivot, "global_position", target_pos, 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var radius: Variant = max(aabb.get_longest_axis_size() * 0.5, 0.03)
	focus_min_distance = max(1.0, radius * 0.8)
	focus_max_distance = max(1.0, radius * 12.0)
	use_focus_limits = true

	var desired := _compute_distance_for_aabb(aabb)
	zoom_to(desired)

"""
Compute the global AABB of a part by merging the AABBs of 
all its visible VisualInstance3D children.
If there are no visible VisualInstance3D children, return a 
small AABB centered on the part's global position.
@type: AABB
@param: the part to compute the AABB for (Node3D)
"""
func _get_global_aabb(root: Node3D) -> AABB:
	var has_any := false
	var merged := AABB()

	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()

		for c in n.get_children():
			stack.append(c)

		if n is VisualInstance3D:
			var vi := n as VisualInstance3D

			if not vi.is_visible_in_tree():
				continue

			var local := vi.get_aabb()
			var global := _aabb_transform(local, vi.global_transform)

			if not has_any:
				merged = global
				has_any = true
			else:
				merged = merged.merge(global)

	if not has_any:
		return AABB(root.global_position, Vector3.ONE * 0.1)

	return merged

"""
Apply a global transform to an AABB by transforming all 8 
corners and computing a new AABB that contains them.
@type: AABB
@param: the AABB to transform (AABB), the global transform to apply (Transform3D)
"""
func _aabb_transform(aabb: AABB, t: Transform3D) -> AABB:
	var pts := [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0, 0),
		aabb.position + Vector3(0, aabb.size.y, 0),
		aabb.position + Vector3(0, 0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
		aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
		aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size
	]

	var p0: Vector3 = t * pts[0]
	var out := AABB(p0, Vector3.ZERO)

	for i in range(1, pts.size()):
		out = out.expand(t * pts[i])

	return out

"""
Get the appropriate node to focus on for a part. If it's a ghost part, try to find a child 
node named "GhostHit" or "Ghost" to focus on. Otherwise, use the "Meshes" child or the part itself.
@type: Node3D
@param: the part to get the focus target for (Node3D), whether the part is a ghost or not (bool)
"""
func _get_focus_target_node(part: Node3D, is_ghost: bool) -> Node3D:
	if is_ghost:
		var g := part.get_node_or_null("Body/Ghost")
		if g and g is Node3D:
			return g as Node3D

		var gh := part.get_node_or_null("Body/GhostHit")
		if gh and gh is Node3D:
			return gh as Node3D

	var meshes := part.get_node_or_null("Meshes")
	if meshes and meshes is Node3D:
		return meshes as Node3D

	return part

"""
Compute a suitable camera distance to frame a part based on 
its AABB size and the camera's field of view.
@type: float
@param: the AABB of the part to compute the distance for (AABB)
"""
func _compute_distance_for_aabb(aabb: AABB) -> float:
	var extents := aabb.size * 0.5
	var radius := extents.length()
	radius = max(radius, 0.05)

	var fov_rad := deg_to_rad(camera.fov)
	var margin := 1.15
	var d := (radius / tan(fov_rad * 0.5)) * margin
	return d
