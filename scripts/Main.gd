extends Node3D

enum Mode {MOUNT, DISMOUNT}

const FRONT_PITCH := PI / 10.0
const TOP_PITCH := -PI / 2.0

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D # obtains camera
@onready var parts: Array[Node] = [] # obtains all parts
@onready var radial: ColorRect = $UI/Crosshair/Radial
@onready var crosshair: Control = $UI/Crosshair

@export var crosshair_offset := Vector2.ZERO # crisshair offset from the mouse
@export var yaw_speed: float = 2.5 # left/right rotation
@export var pitch_speed: float = 2 # up/down rotation
@export var zoom_speed: float = 0.5
@export var min_distance: float = 1.25
@export var max_distance: float = 3.0
@export var zoom_time: float = 0.15
@export var hold_time_to_dismount: float = 0.5

var _hold_part: Node3D = null # part that is being held
var _hold_timer: float = 0.0
var _holding := false # if we are currently holding a part
var hovered_part: Node3D = null
var yaw := 0.0
var pitch := 0.0
var mode: Mode = Mode.DISMOUNT
var distance: float = 0.0
var zoom_tween: Tween
var camera_z_sign := 1.0
var highlighted_children: Array[Node3D] = []

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
	var space := get_world_3d().direct_space_state
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 100.0

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collide_with_areas = true

	var result := space.intersect_ray(query)
	if result and result.collider:
		var info := _get_part_and_is_ghost(result.collider)
		return info["part"] as Node3D

	return null

"""
Return the part that was hit by the ray and whether it is a ghost part or not
@type: Dictionary
@param: the object that was hit by the ray (Object)
"""
func _get_part_and_is_ghost(hit: Object) -> Dictionary:
	if hit is Area3D:
		var body := (hit as Node).get_parent()
		var part := body.get_parent() as Node3D
		return {"part": part, "is_ghost": true}

	if hit is CollisionObject3D:
		var part := (hit as Node).get_parent() as Node3D
		return {"part": part, "is_ghost": false}

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
	# hide mouse
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	
	# initialize pivot rotation
	var r := pivot.rotation
	yaw = r.y
	pitch = clamp(r.x, TOP_PITCH, FRONT_PITCH)
	pivot.rotation = Vector3(pitch, yaw, 0.0)
	
	# initialize with dismount mode
	var selector := $UI/ModeSelector # current selector (e.g. optionButton)
	if selector is OptionButton:
		selector.select(1) # default dismount mode
	mode = Mode.DISMOUNT
	
	# initialize camera distance from object
	camera_z_sign = sign(camera.position.z)
	if camera_z_sign == 0:
		camera_z_sign = 1.0
	distance = abs(camera.position.z)
	
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
	
	# left click / hold logic
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_update_hover(event.position) # update hover
		
		if mode == Mode.MOUNT:
			# Regular mount click
			if event.pressed:
				var part := _get_part_under_mouse(event.position)
				if part:
					part.try_mount()
					_refresh_mount_ghosts()
		else:
			# DISMOUNT: HOLD to dismount
			if event.pressed:
				_holding = true
				_hold_timer = 0.0
				_hold_part = _get_part_under_mouse(event.position)
				# show radial if pressing on a part
				radial.visible = _hold_part != null
				_set_hold_progress(0.0)
			else:
				# if let go before then cancel
				_holding = false
				_hold_timer = 0.0
				_hold_part = null
				radial.visible = false
				_set_hold_progress(0.0)

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
	var target: float = clampf(new_distance, min_distance, max_distance)
	distance = target

	if zoom_tween and zoom_tween.is_running():
		zoom_tween.kill()

	zoom_tween = create_tween()
	zoom_tween.tween_property(
		camera,
		"position:z",
		camera_z_sign * distance,
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
	_holding = false
	_hold_timer = 0.0
	_hold_part = null
	radial.visible = false
	_set_hold_progress(0.0)

"""
Update the hovered part based on the current mouse position. 
Outline the hovered part in green, and if in DISMOUNT mode, 
also show red blockers for parts that would prevent dismounting.
@type: void
@param: current mouse position (Vector2)
"""
func _update_hover(mouse_pos: Vector2) -> void:
	var space := get_world_3d().direct_space_state
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var to: Vector3 = from + camera.project_ray_normal(mouse_pos) * 100.0

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collide_with_areas = true

	var result := space.intersect_ray(query)

	var new_hover: Node3D = null
	var new_is_ghost := false
	if result and result.collider:
		var info := _get_part_and_is_ghost(result.collider)
		new_hover = info["part"]
		new_is_ghost = info["is_ghost"]

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
	
	# Hold-to-dismount
	if mode == Mode.DISMOUNT and _holding:
		if _hold_part == null:
			_holding = false
			_hold_timer = 0.0
			radial.visible = false
			_set_hold_progress(0.0)
			return

		_hold_timer += delta
		var progress := _hold_timer / hold_time_to_dismount
		radial.visible = true
		_set_hold_progress(progress)

		# if mouse changes to another piece, restart
		var current := _get_part_under_mouse(get_viewport().get_mouse_position())
		if current != _hold_part:
			_hold_part = current
			_hold_timer = 0.0
			radial.visible = _hold_part != null
			_set_hold_progress(0.0)

		# dismount when time is due
		if _hold_part != null and _hold_timer >= hold_time_to_dismount:
			_hold_part.try_dismount()
			_refresh_mount_ghosts()

			_holding = false
			_hold_timer = 0.0
			_hold_part = null
			radial.visible = false
			_set_hold_progress(0.0)
			
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
