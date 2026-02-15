extends Node3D

enum Mode {MOUNT, DISMOUNT}

const FRONT_PITCH := PI / 10.0
const TOP_PITCH := -PI / 2.0

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D # obtains camera
@onready var parts: Array[Node] = [] # obtains all parts

@export var yaw_speed: float = 2.5 # left/right rotation
@export var pitch_speed: float = 2 # up/down rotation
@export var zoom_speed: float = 0.5
@export var min_distance: float = 1.25
@export var max_distance: float = 3.0
@export var zoom_time: float = 0.15

var hovered_part: Node3D = null
var yaw := 0.0
var pitch := 0.0
var mode: Mode = Mode.DISMOUNT
var distance: float = 0.0
var zoom_tween: Tween
var camera_z_sign := 1.0
var highlighted_children: Array[Node3D] = []

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
mode by default
@type: void
@param: none
"""
func _ready() -> void:
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

"""
Handle left-click events on parts to mount/dismount them.
Handle mouse hover on parts to outline them in green
@type: void
@param: left-click event (InputEvent)
"""
func _unhandled_input(event: InputEvent) -> void: # called when an InputEvent happens
	# mouse hover
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	
	# left click on object
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_update_hover(event.position) # update hover
		var space := get_world_3d().direct_space_state # current 3D world state
		var from: Vector3 = camera.project_ray_origin(event.position) # ray from camera(click on screen)
		var to: Vector3 = from + camera.project_ray_normal(event.position) * 100.0 # final point of ray
		
		var query := PhysicsRayQueryParameters3D.create(from, to) # define total ray
		query.collide_with_bodies = true
		query.collide_with_areas = true
		var result := space.intersect_ray(query) # execute ray returning collision info
		
		if result and result.collider: # if there is a collision:
			var info := _get_part_and_is_ghost(result.collider)
			var part: Node3D = info["part"]
			if part:
				if mode == Mode.MOUNT:
					if part.has_method("try_mount"):
						part.try_mount()
				else:
					if part.has_method("try_dismount"):
						part.try_dismount()
			_refresh_mount_ghosts()
	
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
Select the current item, updates the ghost view of all parts
@type: void
@param: index (int)
"""
func _on_mode_selector_item_selected(index: int) -> void:
	# index 0 = Mount, index 1 = Dismount
	mode = Mode.MOUNT if index == 0 else Mode.DISMOUNT
	# Update ghost preview
	_refresh_mount_ghosts()

"""
Update the hover 
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
		if hovered_part and hovered_part.has_method("set_hovered"):
			hovered_part.set_hovered(false)

		_clear_highlighted_children()

		hovered_part = new_hover

		if hovered_part and hovered_part.has_method("set_hovered"):
			hovered_part.set_hovered(true, new_is_ghost)

			if mode == Mode.DISMOUNT and hovered_part.has_method("get_blocking_dismount_children"):
				var blockers_list: Array[Node3D] = hovered_part.get_blocking_dismount_children()
				for b in blockers_list:
					if b and b.has_method("set_temp_color"):
						b.set_temp_color(Color.RED)
						highlighted_children.append(b)


"""
Update the rotation
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
