extends Node3D

enum State {MOUNTED, DISMOUNTED} # different part states

@export var part_name := "Part" # Current part name
"""Dependencies part lists"""
# List of pieces that must be DISMOUNTED to dismount this piece
@export var dismount_requires_dismounted: Array[NodePath] = []
# List of pieces that must be MOUNTED to mount this piece
@export var mount_requires_mounted: Array[NodePath] = []

"""Exploded view"""
@export var exploded_offset: Vector3 = Vector3(0, 1, 0) # separation direction
@export var exploded_distance: float = 1.0 # separation distance
@export var move_time: float = 0.18 # animation duration

var state := State.MOUNTED # part begins mounted
var mounted_pos: Vector3
var exploded_pos: Vector3

"""
Called when the node enters the scene tree for the first time. Saves the original position
@type: void
@param: none
"""
func _ready() -> void:
	mounted_pos = position
	exploded_pos = mounted_pos + exploded_offset.normalized() * exploded_distance

"""
Check if the dependent parts are mounted to allow object mount based on the 
mounted/dismounted state of the pieces on which this piece depends on
@type: bool
@param: none
"""
func can_mount() -> bool:
	for path in mount_requires_mounted:
		var other := get_node_or_null(path)
		if other == null:
			continue
		if other.is_dismounted():
			return false
	return true

"""
Check if the dependent parts are dismounted to allow object dismount based on the 
mounted/dismounted state of the pieces on which this piece depends on
@type: bool
@param: none
"""
func can_dismount() -> bool:
	for path in dismount_requires_dismounted:
		var other := get_node_or_null(path)
		if other == null:
			continue
		if other.is_mounted():
			return false
	return true

"""
Check if the part is dismounted
@type: bool
@param: none
"""
func is_dismounted() -> bool:
	return state == State.DISMOUNTED

"""
Check if the part is mounted
@type: bool
@param: none
"""
func is_mounted() -> bool:
	return state == State.MOUNTED

"""
Display message of dismount attempt denial
@type: void
@param: none
"""
func deny_dismount_feedback():
	# Feedback to debug TODO: make it UI
	print("Cannot dismount ", part_name, " because dependencies are not dismounted.")
	_update_color(Color.YELLOW)

"""
Display message of mount attempt denial
@type: void
@param: none
"""
func deny_mount_feedback():
	# Feedback to debug TODO: make it UI
	print("Cannot mount ", part_name, " because dependencies are not mounted.")
	_update_color(Color.ORANGE)

"""
Attempts to mount a part based on its current state and the state
of the pieces on which this piece depends on
@type: void
@param: none
"""
func try_mount():
	if is_dismounted():
		if can_mount():
			mount()
		else:
			deny_mount_feedback()

"""
Attempts to dismount a part based on its current state and the state
of the pieces on which this piece depends on
@type: void
@param: none
"""
func try_dismount():
	if is_mounted():
		if can_dismount():
			dismount()
		else:
			deny_dismount_feedback()

"""
Dismount piece by changing its state to DISMOUNTED, its position and color to red
@type: void
@param: none
"""
func dismount():
	state = State.DISMOUNTED
	_update_color(Color.RED)
	_move_to(exploded_pos)

"""
Mount piece by changing its state to MOUNTED, its position and color to green
@type: void
@param: none
"""
func mount():
	state = State.MOUNTED
	_update_color(Color.GREEN)
	_move_to(mounted_pos)


"""
Move the part to the specified position
@type: void
@param: target position (Vector3)
"""
var move_tween: Tween
func _move_to(target_pos: Vector3) -> void:
	# Avoid old tweens from being kept running (if clicked fast)
	if move_tween and move_tween.is_running():
		move_tween.kill()
	move_tween = create_tween()
	move_tween.tween_property(self , "position", target_pos, move_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

"""
Update color of the object (mesh) by overriding its material with the chosen 
color
@type: void
@param: chosen color of the object (Color)
"""
func _update_color(color: Color): # function that changes the mesh color
	var mesh: MeshInstance3D = $Body/Mesh # mesh class in the body
	if mesh.material_override == null: # if mesh doesn't have a overrided material, create a new one
		var mat := StandardMaterial3D.new()
		mesh.material_override = mat
	mesh.material_override.albedo_color = color
	
"""
Set the selection outline visible if the part is being hovered
@type: void
@param: if the object is hovered or not (bool)
"""
func set_hovered(is_hovered: bool) -> void:
	var outline := $Body/Outline
	if outline:
		outline.visible = is_hovered

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
