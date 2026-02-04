extends Node3D

@onready var camera := $Camera3D # obtains camera

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
			var part: Node3D = body.get_parent() # ← (part that was collided e.g engine)
			if part.has_method("toggle"):
				part.toggle() # toggle function of engine's "Part.gd" script

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
