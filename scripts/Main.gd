extends Node3D

enum Mode {MOUNT, DISMOUNT}

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D # obtains camera

@export var yaw_speed: float = 2.5 # left/right rotation
@export var pitch_speed: float = 2 # up/down rotation

const FRONT_PITCH := PI / 10.0
const TOP_PITCH := -PI / 2.0

var yaw := 0.0
var pitch := 0.0
var mode: Mode = Mode.DISMOUNT
var hovered_part: Node3D = null

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

"""
Select the current item
@type: void
@param: index (int)
"""
func _on_mode_selector_item_selected(index: int) -> void:
	# index 0 = Mount, index 1 = Dismount
	mode = Mode.MOUNT if index == 0 else Mode.DISMOUNT
	print("Mode:", "MOUNT" if mode == Mode.MOUNT else "DISMOUNT")

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
		hovered_part = new_hover

		if hovered_part:
			hovered_part.set_hovered(true) # turn on new one

# Called every frame. 'delta' is the elapsed time since the previous frame.
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
