extends Node3D

enum State {MOUNTED, DISMOUNTED}

# ---- Configurable properties ----
@export var part_name := "Part"
@export var dismount_requires_dismounted: Array[NodePath] = []
@export var mount_requires_mounted: Array[NodePath] = []
@export var exploded_offset: Vector3 = Vector3(0, 1, 0)
@export var exploded_distance: float = 1.0
@export var move_time: float = 0.18

# ---- Helpers ----
var nodes: PartNodes
var visuals: PartVisuals
var ghost_component: PartGhost
var highlight_component: PartHighlight
var mover: PartMover

# ---- Cached nodes (tolerant) ----
var meshes_container: Node3D
var body: StaticBody3D
var outline: Node3D
var ghost_container: Node3D
var ghost_hit: Area3D

# ---- State ----
var state := State.MOUNTED
var mounted_pos: Vector3
var mounted_global_pos: Vector3
var dismounted_pos: Vector3
var stored := false
var stored_pos: Vector3
var _orig_layer: int
var _orig_mask: int

"""
Set up the PartMover component by initializing it with a reference to this part and the configured move time.
@type: void
@param: none
"""
func _setup_mover_component() -> void:
	mover = PartMover.new()
	mover.setup(self , move_time)

"""
Helper to get the main meshes for this part, used by the highlight component to apply temporary colors.
@type: Array[MeshInstance3D]
@param: none
"""
func _get_main_meshes() -> Array[MeshInstance3D]:
	return nodes.get_meshes(meshes_container)

"""
Set up the PartHighlight component by initializing it with a callable to get the main meshes.
@type: void
@param: none
"""
func _setup_highlight_component() -> void:
	highlight_component = PartHighlight.new()
	highlight_component.setup(Callable(self , "_get_main_meshes"))

"""
Set up the PartGhost component with the cached ghost nodes and node helper.
@type: void
@param: whether the ghost is hovered (bool)
"""
func _setup_ghost_component() -> void:
	ghost_component = PartGhost.new()
	ghost_component.setup(ghost_container, ghost_hit, nodes)

"""
Set up the PartVisuals component by initializing it with the cached meshes container and outline nodes.
@type: void
@param: none
"""
func _setup_visuals_component() -> void:
	visuals = PartVisuals.new()
	visuals.setup(meshes_container, outline)

"""
Set up the PartNodes helper for cached node lookups.
@type: void
@param: none
"""
func _setup_nodes_helper() -> void:
	nodes = PartNodes.new()
	nodes.setup(self )

"""
Cache the scene nodes for later use.
@type: void
@param: none
"""
func _cache_scene_nodes() -> void:
	meshes_container = nodes.find_node3d("Meshes")
	body = nodes.find_body()
	outline = nodes.find_under(body, "Outline") as Node3D
	ghost_container = nodes.find_under(body, "Ghost") as Node3D
	ghost_hit = nodes.find_under(body, "GhostHit") as Area3D

"""
Called by PartPlacer when placing parts. Sets up positions, 
caches collision layers, and ensures visuals are in a consistent default state.
@type: void
@param: none
"""
func _ready() -> void:
	add_to_group("parts")
	
	_setup_nodes_helper()
	_cache_scene_nodes()
	_setup_visuals_component()
	_setup_ghost_component()
	_setup_highlight_component()
	_setup_mover_component()

	# Positions
	mounted_pos = position
	mounted_global_pos = global_position
	dismounted_pos = mounted_pos + exploded_offset.normalized() * exploded_distance
	stored_pos = dismounted_pos

	# Collision cache
	if body:
		_orig_layer = body.collision_layer
		_orig_mask = body.collision_mask

	highlight_component.cache_original_appearance()

	# Ensure default visuals
	visuals.set_real_outline(false)
	visuals.set_meshes_visible(true)
	ghost_component.hide_immediately()


"""
Set the visibility and collision properties of the ghost based on 
the given value and whether the part is dismounted.
@type: void
@param: whether the ghost should be visible (bool)
"""
func set_ghost_visible(v: bool) -> void:
	ghost_component.set_ghost_visible(v, is_dismounted())

"""
Determine if this part can be mounted without any dependencies, 
meaning it doesn't require any other parts to be mounted first.
@type: bool
@param: none
"""
func is_mount_root() -> bool:
	return mount_requires_mounted.is_empty()

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
Attempt to mount a part based on its current state and the state
of the pieces on which this piece depends on
@type: void
@param: none
"""
func try_mount() -> void:
	if is_dismounted() and can_mount():
		mount()

"""
Attempt to dismount a part based on its current state and the state
of the pieces on which this piece depends on
@type: void
@param: none
"""
func try_dismount() -> void:
	if is_mounted() and can_dismount():
		dismount()

"""
Dismount piece by changing its state to DISMOUNTED, and its position
@type: void
@param: none
"""
func dismount() -> void:
	state = State.DISMOUNTED
	stored = false

	var tween := mover.move_to(dismounted_pos)
	if tween:
		tween.finished.connect(_on_dismount_finished, CONNECT_ONE_SHOT)

"""
Called when the dismount animation finishes. Stores the part position and hides it
@type: void
@param: none
"""
func _on_dismount_finished() -> void:
	stored = true
	stored_pos = position
	visuals.set_meshes_visible(false)
	visuals.set_real_outline(false)

	if body:
		body.collision_layer = 0
		body.collision_mask = 0

"""
Mount piece by changing its state to MOUNTED, and its position
@type: void
@param: none
"""
func mount() -> void:
	state = State.MOUNTED

	if stored:
		stored = false
		visuals.set_meshes_visible(true)

		if body:
			body.collision_layer = _orig_layer
			body.collision_mask = _orig_mask
		position = stored_pos

	mover.move_to(mounted_pos)


"""
Set the hover state of the part, affecting the real outline and 
ghost hover color based on whether it's a ghost or not.
@type: void
@param: whether the part is hovered (bool), 
		whether the hover is for a ghost (bool, default false)
"""
func set_hovered(is_hovered: bool, is_ghost: bool = false) -> void:
	if is_ghost:
		visuals.set_real_outline(false)
		ghost_component.set_hovered(is_hovered)
			
	else:
		ghost_component.clear_hover()
		visuals.set_real_outline(is_hovered)

"""
Update the position of the ghost container and ghost hit area to match 
the mounted global position if the ghost is visible.
@type: void
@param: delta time since last frame (float)
"""
func _process(_delta: float) -> void:
	ghost_component.update_position(mounted_global_pos)

"""
Set a temporary color on all meshes under the meshes_container by 
duplicating their materials and changing the albedo color. 
This is used for dependency highlighting, and can be cleared 
to revert to the original materials.
@type: void
@param: color to set on the meshes (Color)
"""
func set_temp_color(color: Color) -> void:
	highlight_component.set_temp_color(color)

"""
Clear the temporary color from all meshes under the meshes_container 
by restoring their original surface override materials.
This is used to revert any changes made by set_temp_color.
@type: void
@param: none
"""
func clear_temp_color() -> void:
	highlight_component.clear_temp_color()

"""
Get an array of Node3D children that are currently blocking dismounting.
Used to identify which parts are preventing this part from being dismounted.
@type: Array[Node3D]
@param: none
"""
func get_blocking_dismount_children() -> Array[Node3D]:
	var blocking: Array[Node3D] = []
	for path in dismount_requires_dismounted:
		var other := get_node_or_null(path)

		if other == null:
			continue

		if other.is_mounted():
			blocking.append(other)

	return blocking

"""
Set whether the real outline is enabled.
@type: void
@param: whether the real outline is enabled (bool)
"""
func set_real_outline_enabled(v: bool) -> void:
	visuals.set_real_outline_enabled(v)
