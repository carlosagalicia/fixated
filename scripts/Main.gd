extends Node3D

enum Mode {MOUNT, DISMOUNT}

@onready var camera := $Camera3D # obtains camera

var mode: Mode = Mode.DISMOUNT
var hovered_part: Node3D = null

"""
Called when the node enters the scene tree for the first time. Set to dismount
mode by default
@type: void
@param: none
"""
func _ready() -> void:
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
	pass
