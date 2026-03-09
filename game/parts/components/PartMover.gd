class_name PartMover
extends RefCounted

var part: Node3D
var move_time: float
var move_tween: Tween

"""
Set up the PartMover component by initializing it with a 
reference to the owner part and the configured move time.
@type: void
@param: owner part (Node3D), 
	move time (float)
"""
func setup(owner: Node3D, time: float) -> void:
	part = owner
	move_time = time

"""
Move the part to the specified position
@type: void
@param: target position (Vector3)
"""
func move_to(target_pos: Vector3) -> Tween:
	if part == null:
		return null

	if move_tween and move_tween.is_running():
		move_tween.kill()

	move_tween = part.create_tween()
	move_tween.tween_property(part, "position", target_pos, move_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	return move_tween
