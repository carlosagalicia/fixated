extends Node3D

enum Mode {MOUNT, DISMOUNT}

const FRONT_PITCH := PI / 10.0
const TOP_PITCH := -PI / 2.0

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D # obtains camera

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
		var result := space.intersect_ray(query) # execute ray returning collision info
		
		if result and result.collider: # if there is a collision:
			var body: CollisionObject3D = result.collider # object that was collided
			var part: Node3D = body.get_parent() # ← (part that was collided e.g block)
			if mode == Mode.MOUNT:
					part.try_mount()
			else:
					part.try_dismount()
	
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
Select the current item
@type: void
@param: index (int)
"""
func _on_mode_selector_item_selected(index: int) -> void:
	# index 0 = Mount, index 1 = Dismount
	mode = Mode.MOUNT if index == 0 else Mode.DISMOUNT

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
	var result := space.intersect_ray(query)

	var new_hover: Node3D = null
	if result and result.collider: # if collided get collided object
		var body: CollisionObject3D = result.collider
		new_hover = body.get_parent()

	# If hovered object changed, turn off the old one and turn on the new one
	if new_hover != hovered_part:
		if hovered_part:
			hovered_part.set_hovered(false) # turn off old one
		
		_clear_highlighted_children() # clear its highligted children
		
		hovered_part = new_hover
		
		if hovered_part:
			hovered_part.set_hovered(true) # turn on new one
			
			if mode == Mode.DISMOUNT:
				var blockersList: Array = hovered_part.get_blocking_dismount_children()
				for b in blockersList:
					if b:
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
