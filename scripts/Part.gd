extends Node3D

enum State {MOUNTED, DISMOUNTED} # different part states
const LAYER_GHOST := 1 << 1

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
@onready var ghost: MeshInstance3D = $Body/Ghost
@onready var ghost_hit: Area3D = $Body/GhostHit

var _temp_color_active := false # if the part is colored when it is a dependency
var _orig_material_override: Material = null # original material override
var _orig_has_override := false # if material is overriden
var state := State.MOUNTED # part begins mounted
var mounted_pos: Vector3 # part position when mounted
var mounted_global_pos: Vector3 # part global position when mounted
var dismounted_pos: Vector3 # part position when dismounted
var stored := false # if part is stored
var stored_pos: Vector3 # part position when stored
var _orig_layer: int
var _orig_mask: int
var _ghost_hover_active := false
var _ghost_saved_color: Color = Color.WHITE

"""
Get the ghost mesh of this part
@type: MeshInstance3D
@param: none
"""
func _get_ghost_mesh() -> MeshInstance3D:
	return $Body/Ghost

"""
Get the ghost material, if it is not unique, make it unique by duplicating the active 
material or creating a new one if there is no active material
@type: StandardMaterial3D
@param: none
"""
func _get_or_make_unique_ghost_material() -> StandardMaterial3D:
	var g := _get_ghost_mesh()

	if g.material_override is StandardMaterial3D:
		return g.material_override as StandardMaterial3D

	var active := g.get_active_material(0)
	if active:
		g.material_override = active.duplicate()
	else:
		g.material_override = StandardMaterial3D.new()

	return g.material_override as StandardMaterial3D

"""
Set the color of the ghost part to a determined color, and saves the original color if it is not already saved
@type: void
@param: future color of the ghost part (Color)
"""
func _ghost_set_hover_color(color: Color) -> void:
	var mat := _get_or_make_unique_ghost_material()
	if not _ghost_hover_active:
		_ghost_saved_color = mat.albedo_color
		_ghost_hover_active = true
	mat.albedo_color = color

"""
Clear the current color of the ghost part and sets it to its original color
@type: void
@param: none
"""
func _ghost_clear_hover_color() -> void:
	if not _ghost_hover_active:
		return
	var mat := _get_or_make_unique_ghost_material()
	mat.albedo_color = _ghost_saved_color
	_ghost_hover_active = false

"""
Set the real outline visible or not
@type: void
@param: if the real outline is visible or not (bool)
"""
func _set_real_outline(v: bool) -> void:
	var outline := $Body/Outline
	if outline:
		outline.visible = v

"""
Set the part ghost review on/off
@type: void
@param: if it is visible or not (bool)
"""
func set_ghost_visible(v: bool) -> void:
	var showg := v and is_dismounted()
	if ghost:
		ghost.visible = showg
	if ghost_hit:
		ghost_hit.monitorable = showg
		ghost_hit.monitoring = showg
		ghost_hit.collision_layer = LAYER_GHOST if showg else 0
		ghost_hit.collision_mask = LAYER_GHOST if showg else 0
	if not showg:
		_ghost_clear_hover_color()

"""
See if the part has no dependencies to mount
@type: void
@param: none
"""
func is_mount_root() -> bool:
	return mount_requires_mounted.is_empty()

"""
Get the current mesh of the body
@type: void
@param: none
"""
func _get_mesh() -> MeshInstance3D:
	return $Body/Mesh
	
"""
Store original material and color of the part
@type: void
@param: none
"""
func _cache_original_appearance() -> void:
	var mesh := _get_mesh()

	_orig_has_override = mesh.material_override != null
	_orig_material_override = mesh.material_override

	var mat := mesh.get_active_material(0)

"""
Store original material and color of the part
@type: void
@param: none
"""
func _get_or_make_unique_override() -> StandardMaterial3D:
	var mesh := _get_mesh()

	# if there is already an override material, use it
	if mesh.material_override is StandardMaterial3D:
		return mesh.material_override as StandardMaterial3D

	# if there is no override, duplicate the active material (to avoid modifying shared resources)
	var active := mesh.get_active_material(0)
	if active:
		mesh.material_override = active.duplicate()
	else:
		mesh.material_override = StandardMaterial3D.new()

	return mesh.material_override as StandardMaterial3D
	
"""
Called when the node enters the scene tree for the first time. Saves the original position and
stores the original part appeareance
@type: void
@param: none
"""
func _ready() -> void:
	add_to_group("parts") # add part to the parts group
	_cache_original_appearance()
	mounted_pos = position
	mounted_global_pos = global_position
	dismounted_pos = mounted_pos + exploded_offset.normalized() * exploded_distance
	
	_orig_layer = $Body.collision_layer
	_orig_mask = $Body.collision_mask
	stored_pos = dismounted_pos

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
Attempts to mount a part based on its current state and the state
of the pieces on which this piece depends on
@type: void
@param: none
"""
func try_mount():
	if is_dismounted():
		if can_mount():
			mount()

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

"""
Dismount piece by changing its state to DISMOUNTED, and its position
@type: void
@param: none
"""
func dismount():
	state = State.DISMOUNTED
	stored = false
	_move_to(dismounted_pos)
	# When animation finishes, store and hide
	if move_tween:
		move_tween.finished.connect(_on_dismount_finished, CONNECT_ONE_SHOT)
	
"""
Called when the dismount animation finishes. Stores the part position and hides it
@type: void
@param: none
"""
func _on_dismount_finished() -> void:
	stored = true
	stored_pos = position # last position (dismounted)
	$Body/Mesh.visible = false
	$Body/Outline.visible = false
	$Body.collision_layer = 0
	$Body.collision_mask = 0
	
"""
Mount piece by changing its state to MOUNTED, and its position
@type: void
@param: none
"""
func mount():
	state = State.MOUNTED
	
	if stored:
		stored = false
		$Body/Mesh.visible = true
		$Body.collision_layer = _orig_layer
		$Body.collision_mask = _orig_mask
		position = stored_pos
	
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
Set the selection outline visible if the part is being hovered
@type: void
@param: if the object is hovered or not (bool)
"""
func set_hovered(is_hovered: bool, is_ghost: bool = false) -> void:
	if is_ghost:
		_set_real_outline(false)

		if ghost and ghost.visible:
			if is_hovered:
				_ghost_set_hover_color(Color(0.6, 1.0, 0.6, 1.0))
			else:
				_ghost_clear_hover_color()
		else:
			_ghost_clear_hover_color()
	else:
		_ghost_clear_hover_color()
		_set_real_outline(is_hovered)

"""
Set the ghost version of the part in the mounted position
@type: void
@param: current time elapsed (float)
"""
func _process(delta: float) -> void:
	if ghost and ghost.visible:
		var gp := mounted_global_pos
		ghost.global_position = gp
		ghost_hit.global_position = gp

"""
Set the color of the mechanic piece to a determined color if the part is marked to change its
color, otherwise it is set to change the its color, and its original color is saved
@type: void
@param: future color of the part (Color)
"""
func set_temp_color(color: Color) -> void:
	if not _temp_color_active:
		_temp_color_active = true
		_cache_original_appearance()

	var mat := _get_or_make_unique_override()
	mat.albedo_color = color

"""
Clear the current color of the part and sets it to its original color
@type: void
@param: none
"""
func clear_temp_color() -> void:
	if not _temp_color_active:
		return
	_temp_color_active = false

	var mesh := _get_mesh()

	if _orig_has_override:
		mesh.material_override = _orig_material_override
	else:
		mesh.material_override = null

"""
Get the list of direct children parts that are still mounted
@type: Array[Node3D]
@param: none
"""
func get_blocking_dismount_children() -> Array[Node3D]:
	var blockingParts: Array[Node3D] = []
	for path in dismount_requires_dismounted:
		var other := get_node_or_null(path)
		if other == null:
			continue
		# only direct children
		if other.is_mounted():
			blockingParts.append(other)
	return blockingParts
