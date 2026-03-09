extends Node3D

enum State {MOUNTED, DISMOUNTED}
const LAYER_GHOST := 1 << 1

# ---- Configurable properties ----
@export var part_name := "Part"
@export var dismount_requires_dismounted: Array[NodePath] = []
@export var mount_requires_mounted: Array[NodePath] = []
@export var exploded_offset: Vector3 = Vector3(0, 1, 0)
@export var exploded_distance: float = 1.0
@export var move_time: float = 0.18

# ---- Cached nodes (tolerant) ----
@onready var meshes_container: Node3D = _find_node3d("Meshes")
@onready var body: StaticBody3D = _find_body()
@onready var outline: Node3D = _find_under(body, "Outline") as Node3D
@onready var ghost_container: Node3D = _find_under(body, "Ghost") as Node3D
@onready var ghost_hit: Area3D = _find_under(body, "GhostHit") as Area3D

# ---- State ----
var state := State.MOUNTED
var mounted_pos: Vector3
var mounted_global_pos: Vector3
var dismounted_pos: Vector3
var stored := false
var stored_pos: Vector3
var _orig_layer: int
var _orig_mask: int
var _allow_real_outline := true

# ---- Temp color (for dependency highlighting) ----
var _temp_color_active := false
var _orig_surface_override_by_mesh: Dictionary = {} # MeshInstance3D -> Array[Material]

# ---- Ghost hover ----
var _ghost_hover_active := false
var _ghost_saved_colors: Dictionary = {} # MeshInstance3D -> Color

# ---- Tween ----
var move_tween: Tween

"""
Called by PartPlacer when placing parts. Sets up positions, 
caches collision layers, and ensures visuals are in a consistent default state.
@type: void
@param: none
"""
func _ready() -> void:
	add_to_group("parts")

	# Positions
	mounted_pos = position
	mounted_global_pos = global_position
	dismounted_pos = mounted_pos + exploded_offset.normalized() * exploded_distance
	stored_pos = dismounted_pos

	# Collision cache
	if body:
		_orig_layer = body.collision_layer
		_orig_mask = body.collision_mask

	_cache_original_appearance()

	# Ensure default visuals
	_set_real_outline(false)
	_set_meshes_visible(true)
	_set_ghost_visible_internal(false)
	

"""
Find a child Node3D by name, or return null if not found or wrong type.
@type: Node3D or null
@param: name of the child node to find (String)
"""
func _find_node3d(name_: String) -> Node3D:
	var n := get_node_or_null(name_)

	if n is Node3D:
		return n
	return null

"""
Find a StaticBody3D child, preferring one named "Body", or return null if not found.
@type: StaticBody3D or null
@param: none
"""
func _find_body() -> StaticBody3D:
	# Prefer exact "Body"
	var b := get_node_or_null("Body")

	if b is StaticBody3D:
		return b as StaticBody3D
		
	# Otherwise: first StaticBody3D child
	for c in get_children():
		if c is StaticBody3D:
			return c as StaticBody3D

	return null

"""
Find a child node by name under a given root, or return null if not found.
@type: Node or null
@param: root node to search under (Node), name of the child node to find (String)
"""
func _find_under(root: Node, child_name: String) -> Node:
	if root == null:
		return null

	return root.get_node_or_null(child_name)

"""
Helper to get all MeshInstance3D nodes under a given container, or an empty array if none.
@type: Array[MeshInstance3D]
@param: container node to search under (Node3D)
"""
func _get_meshes_from(container: Node3D) -> Array[MeshInstance3D]:
	var arr: Array[MeshInstance3D] = []

	if container == null:
		return arr

	for c in container.get_children():
		if c is MeshInstance3D:
			arr.append(c as MeshInstance3D)

	return arr

"""
Get all MeshInstance3D nodes under the meshes_container, or an empty array if none.
@type: Array[MeshInstance3D]
@param: none
"""
func _get_meshes() -> Array[MeshInstance3D]:
	return _get_meshes_from(meshes_container)

"""
Get all MeshInstance3D nodes under the ghost_container, or an empty array if none.
@type: Array[MeshInstance3D]
@param: none
"""
func _get_ghost_meshes() -> Array[MeshInstance3D]:
	return _get_meshes_from(ghost_container)

"""
Set the visibility of the real outline, if it exists, based on 
the given value and whether real outlines are allowed.
@type: void
@param: whether the real outline should be visible (bool)
"""
func _set_real_outline(v: bool) -> void:
	if outline:
		outline.visible = v and _allow_real_outline

"""
Set the visibility of all meshes in the meshes_container based on the given value.
@type: void
@param: whether the meshes should be visible (bool)
"""
func _set_meshes_visible(v: bool) -> void:
	if meshes_container:
		meshes_container.visible = v

"""
Set the visibility and collision properties of the ghost based on 
the given value and whether the part is dismounted.
@type: void
@param: whether the ghost should be visible (bool)
"""
func set_ghost_visible(v: bool) -> void:
	var showg := v and is_dismounted()
	_set_ghost_visible_internal(showg)

	if not showg:
		_ghost_clear_hover_color()

"""
Set ghost visibility and collision properties.
@type: void
@param: whether the ghost should be visible (bool)
"""
func _set_ghost_visible_internal(showg: bool) -> void:
	if ghost_container:
		ghost_container.visible = showg

	if ghost_hit:
		ghost_hit.monitorable = showg
		ghost_hit.monitoring = showg
		ghost_hit.collision_layer = LAYER_GHOST if showg else 0
		ghost_hit.collision_mask = LAYER_GHOST if showg else 0

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
	_move_to(dismounted_pos)

	if move_tween:
		move_tween.finished.connect(_on_dismount_finished, CONNECT_ONE_SHOT)

"""
Called when the dismount animation finishes. Stores the part position and hides it
@type: void
@param: none
"""
func _on_dismount_finished() -> void:
	stored = true
	stored_pos = position
	_set_meshes_visible(false)
	_set_real_outline(false)

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
		_set_meshes_visible(true)

		if body:
			body.collision_layer = _orig_layer
			body.collision_mask = _orig_mask
		position = stored_pos

	_move_to(mounted_pos)

"""
Move the part to the specified position
@type: void
@param: target position (Vector3)
"""
func _move_to(target_pos: Vector3) -> void:
	if move_tween and move_tween.is_running():
		move_tween.kill()

	move_tween = create_tween()
	move_tween.tween_property(self , "position", target_pos, move_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

"""
Set the hover state of the part, affecting the real outline and 
ghost hover color based on whether it's a ghost or not.
@type: void
@param: whether the part is hovered (bool), 
		whether the hover is for a ghost (bool, default false)
"""
func set_hovered(is_hovered: bool, is_ghost: bool = false) -> void:
	if is_ghost:
		_set_real_outline(false)

		if ghost_container and ghost_container.visible and is_hovered:
			_ghost_set_hover_color(Color(0.6, 1.0, 0.6, 1.0))
		else:
			_ghost_clear_hover_color()
			
	else:
		_ghost_clear_hover_color()
		_set_real_outline(is_hovered)

"""
Update the position of the ghost container and ghost hit area to match 
the mounted global position if the ghost is visible.
@type: void
@param: delta time since last frame (float)
"""
func _process(_delta: float) -> void:
	if ghost_container and ghost_container.visible:
		var gp := mounted_global_pos
		ghost_container.global_position = gp

		if ghost_hit:
			ghost_hit.global_position = gp

"""
Cache the original surface override materials of all meshes 
under the meshes_container. This allows temporary color changes to be applied 
and then reverted back to the original materials.
@type: void
@param: none
"""
func _cache_original_appearance() -> void:
	_orig_surface_override_by_mesh.clear()

	for m in _get_meshes():
		var arr: Array[Material] = []
		var surf_count := 0

		if m.mesh:
			surf_count = m.mesh.get_surface_count()

		for i in range(surf_count):
			arr.append(m.get_surface_override_material(i))

		_orig_surface_override_by_mesh[m] = arr

"""
Set a temporary color on all meshes under the meshes_container by 
duplicating their materials and changing the albedo color. 
This is used for dependency highlighting, and can be cleared 
to revert to the original materials.
@type: void
@param: color to set on the meshes (Color)
"""
func set_temp_color(color: Color) -> void:
	if not _temp_color_active:
		_temp_color_active = true
		_cache_original_appearance()

	for m in _get_meshes():
		if m.mesh == null:
			continue

		var surf_count := m.mesh.get_surface_count()

		for i in range(surf_count):
			var mat: Material = m.get_surface_override_material(i)
			if mat == null:
				mat = m.get_active_material(i)

			if mat == null:
				continue

			var dup := mat.duplicate()
			m.set_surface_override_material(i, dup)

			if dup is BaseMaterial3D:
				(dup as BaseMaterial3D).albedo_color = color

"""
Clear the temporary color from all meshes under the meshes_container 
by restoring their original surface override materials.
This is used to revert any changes made by set_temp_color.
@type: void
@param: none
"""
func clear_temp_color() -> void:
	if not _temp_color_active:
		return

	_temp_color_active = false

	for m in _get_meshes():
		var arr: Array = _orig_surface_override_by_mesh.get(m, [])

		if m.mesh:
			var surf_count := m.mesh.get_surface_count()

			for i in range(surf_count):
				var orig_surf: Material = arr[i] if i < arr.size() else null
				m.set_surface_override_material(i, orig_surf)

"""
Get or create a StandardMaterial3D for the given MeshInstance3D to be used for ghost hover coloring.
If the mesh already has a material override that is a StandardMaterial3D, it will be reused. 
Otherwise, a new material will be created by duplicating the active material or 
creating a new StandardMaterial3D if no active material exists.
@type: StandardMaterial3D
@param: MeshInstance3D for which to get or create the hover ghost material (MeshInstance3D)
"""
func _get_or_make_hover_ghost_material(g: MeshInstance3D) -> StandardMaterial3D:
	if g.material_override is StandardMaterial3D:
		return g.material_override as StandardMaterial3D

	var active := g.get_active_material(0)

	if active:
		g.material_override = active.duplicate()
	else:
		g.material_override = StandardMaterial3D.new()

	return g.material_override as StandardMaterial3D

"""
Set a hover color on all ghost meshes by getting or creating a hover 
ghost material and changing its albedo color.
The original colors are saved the first time this is called while hover is active,
and can be restored by calling _ghost_clear_hover_color.
@type: void
@param: color to set on the ghost meshes (Color)
"""
func _ghost_set_hover_color(color: Color) -> void:
	if not _ghost_hover_active:
		_ghost_saved_colors.clear()

		for g in _get_ghost_meshes():
			var mat := _get_or_make_hover_ghost_material(g)
			_ghost_saved_colors[g] = mat.albedo_color
		_ghost_hover_active = true

	for g in _get_ghost_meshes():
		var mat := _get_or_make_hover_ghost_material(g)
		mat.albedo_color = color

"""
Clear the hover color from all ghost meshes by restoring their 
original colors from the _ghost_saved_colors dictionary.
Called when hover is no longer active to revert 
the ghost meshes back to their original appearance.
@type: void
@param: none
"""
func _ghost_clear_hover_color() -> void:
	if not _ghost_hover_active:
		return

	for g in _get_ghost_meshes():
		var mat := _get_or_make_hover_ghost_material(g)
		if _ghost_saved_colors.has(g):
			mat.albedo_color = _ghost_saved_colors[g]

	_ghost_saved_colors.clear()
	_ghost_hover_active = false

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
	_allow_real_outline = v
	if not v:
		_set_real_outline(false)
