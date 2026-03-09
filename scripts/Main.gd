extends Node3D

enum Mode {MOUNT, DISMOUNT}

const FRONT_PITCH := PI / 10.0
const TOP_PITCH := -PI / 2.0
const LAYER_SOLID := 1 << 0
const LAYER_GHOST := 1 << 1

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D # obtains camera
@onready var parts: Array[Node] = [] # obtains all parts
@onready var radial: ColorRect = $UI/Crosshair/Radial
@onready var crosshair: Control = $UI/Crosshair

@export var crosshair_offset := Vector2.ZERO # crisshair offset from the mouse
@export var yaw_speed: float = 2.5 # left/right rotation
@export var pitch_speed: float = 2 # up/down rotation
@export var zoom_speed: float = 0.5
@export var min_distance: float = 2.0
@export var max_distance: float = 3.0
@export var zoom_time: float = 0.15
@export var hold_time_to_act: float = 0.5
@export var click_move_tolerance_px := 8.0

var _hold_part: Node3D = null # part that is being held
var _hold_timer: float = 0.0
var _holding := false # if we are currently holding a part
var hovered_part: Node3D = null
var yaw := 0.0
var pitch := 0.0
var mode: Mode = Mode.DISMOUNT
var distance: float = 0.0
var zoom_tween: Tween
var highlighted_children: Array[Node3D] = []
var _press_pos: Vector2 = Vector2.ZERO
var _press_is_ghost := false
var _press_part: Node3D = null
var _hold_fired := false
var focus_min_distance := 2.0
var focus_max_distance := 10.0
var use_focus_limits := false

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
Focus the camera on a part by tweening the pivot's global position to 
the part's focus position and zooming to a suitable distance.
@type: void
@param: the part to focus on (Node3D), whether the part is a ghost or not (bool)
"""
func _focus_on_part(part: Node3D, is_ghost: bool) -> void:
	if part == null:
		return

	var focus_node := _get_focus_target_node(part, is_ghost)
	var aabb := _get_global_aabb(focus_node)
	var target_pos := aabb.get_center()

	var t := create_tween()
	t.tween_property(pivot, "global_position", target_pos, 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var radius: Variant = max(aabb.get_longest_axis_size() * 0.5, 0.03)
	focus_min_distance = max(1.0, radius * 0.8)
	focus_max_distance = max(1.0, radius * 12.0)
	use_focus_limits = true

	var desired := _compute_distance_for_aabb(aabb)
	_zoom_to(desired)


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
Raycast into the scene from the given screen position. 
First check for ghost parts, then solid parts.
@type: Dictionary
@param: screen position to raycast from (Vector2)
"""
func _raycast_from_screen(screen_pos: Vector2) -> Dictionary:
	var space := get_world_3d().direct_space_state
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

	if mode == Mode.DISMOUNT:
		if rs and rs.collider:
			return _get_part_and_is_ghost(rs.collider)

		return {"part": null, "is_ghost": false}

	if rg and rg.collider:
		return _get_part_and_is_ghost(rg.collider)

	if rs and rs.collider:
		return _get_part_and_is_ghost(rs.collider)

	return {"part": null, "is_ghost": false}

"""
Set the radial progress shader parameter to show hold-to-dismount progress.
@type: void
@param: progress value between 0.0 and 1.0 (float)
"""
func _set_hold_progress(p: float) -> void:
	var mat := radial.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("progress", clampf(p, 0.0, 1.0))


"""
Return the part under the mouse cursor by raycasting into the scene.
@type: Node3D
@param: screen position of the mouse (Vector2)
"""
func _get_part_under_mouse(screen_pos: Vector2) -> Node3D:
	var info := _raycast_from_screen(screen_pos)
	return info["part"] as Node3D

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

		var is_ghost := (hit is Area3D)
		return {"part": part, "is_ghost": is_ghost}

	return {"part": null, "is_ghost": false}

"""
Show all ghost parts that can be mounted in the MOUNT mode
mode by default
@type: void
@param: none
"""
func _refresh_mount_ghosts() -> void:
	# Turn off all ghosts first
	for p in parts:
		if p:
			p.set_ghost_visible(false)
			
	if mode != Mode.MOUNT:
		return

	# Mountable candidates (dismounted + can_mount)
	var mountables: Array[Node3D] = []

	for p in parts:
		if p and p.is_dismounted() and p.can_mount():
			mountables.append(p)

	# If no candidates, show roots (dismounted + without requirements)
	if mountables.is_empty():
		for p in parts:
			if p and p.is_dismounted() and p.is_mount_root():
				p.set_ghost_visible(true)
		return

	# Otherwise, show candidates
	for p in mountables:
		p.set_ghost_visible(true)

"""
Called when the node enters the scene tree for the first time. Set to dismount
mode by default. Initialize camera rotation and distance. Get all parts in the scene.
@type: void
@param: none
"""
func _ready() -> void:
	# Camera distance
	camera.position.x = 0.0
	camera.position.y = 0.0
	camera.position.z = abs(camera.position.z)
	distance = camera.position.z
	
	# hide mouse
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	
	# initialize pivot rotation
	var r := pivot.rotation
	yaw = r.y
	pitch = clamp(r.x, TOP_PITCH, FRONT_PITCH)
	pivot.rotation = Vector3(pitch, yaw, 0.0)
	
	# initialize with dismount mode
	var selector := $UI/ModeSelector # current selector

	if selector is OptionButton:
		selector.select(1) # default dismount mode
	
	parts = get_tree().get_nodes_in_group("parts") # get all parts
	_refresh_mount_ghosts()
	
	radial.visible = false
	_set_hold_progress(0.0)

"""
Handle player input for hovering, clicking, and zooming. 
Left-click behavior depends on the current mode (MOUNT or DISMOUNT).
@type: void
@param: left-click event (InputEvent)
"""
func _unhandled_input(event: InputEvent) -> void: # called when an InputEvent happens
	# mouse hover
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	
	# left click / hold logic (BOTH MODES)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_update_hover(event.position)

		if event.pressed:
			_press_pos = event.position
			_hold_fired = false
			
			var info := _raycast_from_screen(event.position)
			var part: Node3D = info["part"]
			var is_ghost: bool = info["is_ghost"]
			
			_press_part = part
			_press_is_ghost = is_ghost

			var valid_hold := false
			if mode == Mode.MOUNT:
				valid_hold = part != null and is_ghost
			else:
				valid_hold = part != null and not is_ghost

			if valid_hold:
				_start_hold(part)
			else:
				_reset_hold_state()

		else:
			# Click is released, hold is canceled and event is click
			var moved := _press_pos.distance_to(event.position) > click_move_tolerance_px
			
			if not _hold_fired and not moved and _press_part != null:
				# regular click
				_focus_on_part(_press_part, _press_is_ghost)
				
			_reset_hold_state()
			
			_press_part = null

	# zoom
	if event.is_action_pressed("zoom_in"):
		_zoom_to(distance - zoom_speed)

	elif event.is_action_pressed("zoom_out"):
		_zoom_to(distance + zoom_speed)

"""
Set the camera distance to the object
@type: void
@param: new distance (float)
"""
func _zoom_to(new_distance: float) -> void:
	var min_d := min_distance
	var max_d := max_distance

	if use_focus_limits:
		min_d = focus_min_distance
		max_d = focus_max_distance

	var target: float = clampf(new_distance, min_d, max_d)
	distance = target

	if zoom_tween and zoom_tween.is_running():
		zoom_tween.kill()

	zoom_tween = create_tween()
	zoom_tween.tween_property(
		camera,
		"position:z",
		distance,
		zoom_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

"""
Handle mode switching between MOUNT and DISMOUNT when the player selects an option from the UI.
@type: void
@param: index (int)
"""
func _on_mode_selector_item_selected(index: int) -> void:
	# index 0 = Mount, index 1 = Dismount
	mode = Mode.MOUNT if index == 0 else Mode.DISMOUNT
	# Update ghost preview
	_refresh_mount_ghosts()
	_reset_hold_state()
	
	var enable_real_outline := (mode == Mode.DISMOUNT)
	for p in parts:
		if p:
			p.set_real_outline_enabled(enable_real_outline)

"""
Update the hovered part based on the current mouse position. 
Outline the hovered part in green, and if in DISMOUNT mode, 
also show red blockers for parts that would prevent dismounting.
@type: void
@param: current mouse position (Vector2)
"""
func _update_hover(mouse_pos: Vector2) -> void:
	var info := _raycast_from_screen(mouse_pos)
	var new_hover := info["part"] as Node3D
	var new_is_ghost := bool(info["is_ghost"])

	if new_hover != hovered_part:
		if hovered_part:
			hovered_part.set_hovered(false)

		_clear_highlighted_children()

		hovered_part = new_hover

		if hovered_part:
			hovered_part.set_hovered(true, new_is_ghost)

			if mode == Mode.DISMOUNT:
				var blockers_list: Array[Node3D] = hovered_part.get_blocking_dismount_children()
				for b in blockers_list:
					if b:
						b.set_temp_color(Color.RED)
						highlighted_children.append(b)

"""
Update the camera rotation based on player input. Handle hold-to-dismount logic in DISMOUNT mode.
@type: void
@param: current time elapsed (float)
"""
func _process(delta: float) -> void:
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

	# Relative pitches from initial pose
	pitch = clamp(pitch, TOP_PITCH, FRONT_PITCH)

	pivot.rotation = Vector3(pitch, yaw, 0.0)
	
	# Hold-to-do-action
	if _holding:
		# If we started holding but not on a part, stop immediately
		if _hold_part == null:
			_reset_hold_state()

		else:
			_hold_timer += delta
			var progress := _hold_timer / hold_time_to_act
			radial.visible = true
			_set_hold_progress(progress)

			# If mouse moved to another part, restart hold on the new one
			var current := _get_part_under_mouse(get_viewport().get_mouse_position())

			if current != _hold_part:
				_hold_part = current
				_hold_timer = 0.0
				radial.visible = _hold_part != null
				_set_hold_progress(0.0)

			# Trigger action when time is due
			if _hold_part != null and _hold_timer >= hold_time_to_act:
				if mode == Mode.MOUNT:
					_hold_part.try_mount()

				else:
					_hold_part.try_dismount()

				_refresh_mount_ghosts()
				_hold_fired = true
				_reset_hold_state()
			
	# Follow mouse
	var m := get_viewport().get_mouse_position() + crosshair_offset
	crosshair.position = m - crosshair.size * 0.5

"""
Clear the parts that were highlighted
@type: void
@param: none
"""
func _clear_highlighted_children() -> void:
	for p in highlighted_children:
		if p:
			p.clear_temp_color()
	highlighted_children.clear()

"""
Reset the hold state when the player releases the mouse button 
or moves the cursor away from the part.
@type: void
@param: none
"""
func _reset_hold_state() -> void:
	_holding = false
	_hold_timer = 0.0
	_hold_part = null
	radial.visible = false
	_set_hold_progress(0.0)

"""
Start the hold process when the player clicks on a valid part.
@type: void
@param: the part that is being held (Node3D)
"""
func _start_hold(part: Node3D) -> void:
	_holding = true
	_hold_timer = 0.0
	_hold_part = part
	radial.visible = true
	_set_hold_progress(0.0)

"""
Get the appropriate node to focus on for a part. If it's a ghost part, try to find a child 
node named "GhostHit" or "Ghost" to focus on. Otherwise, use the "Meshes" child or the part itself.
@type: Node3D
@param: the part to get the focus target for (Node3D), whether the part is a ghost or not (bool)
"""
func _get_focus_target_node(part: Node3D, is_ghost: bool) -> Node3D:
	if is_ghost:
		var gh := part.get_node_or_null("Body/GhostHit")
		if gh and gh is Node3D:
			return gh as Node3D

		var g := part.get_node_or_null("Body/Ghost")
		if g and g is Node3D:
			return g as Node3D

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
