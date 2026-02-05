extends Node3D

enum Mode {MOUNT, DISMOUNT}
var mode: Mode = Mode.DISMOUNT

@onready var camera := $Camera3D # obtains camera

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
Handle left-click events on parts to mount/dismount them
@type: void
@param: left-click event (InputEvent)
"""
func _unhandled_input(event: InputEvent) -> void: # called when an InputEvent happens
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
