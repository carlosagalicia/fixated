@tool
extends Node


const REAL_COL_PREFIX := "Col_"
const GHOST_COL_PREFIX := "GhostCol_"

var _out_root: Node3D

@export var glb_root: NodePath = "Sketchfab_Scene/Sketchfab_model/V6EN_fbx/RootNode"
@export var parts_root: NodePath
@export var part_scene: PackedScene
@export var part_script: Script = preload("C:/Users/alexs/Documents/Robotica/Proyectos godot/fixated/scripts/Part.gd")
@export var outline_scale: float = 1.03
@export var outline_color: Color = Color(0.2, 1.0, 0.2, 1.0)
@export var make_ghost := true
@export var save_as_scene: bool = true
@export var also_populate_parts_root: bool = true
@export var run_convert := false: set = _set_run_convert

@export_range(0.0, 1.0, 0.01) var ghost_alpha := 0.25

@export_file("*.tscn") var save_path = "res://scenes/PartsRoot_generated.tscn"

"""
Convert an imported GLB (with Node3D hierarchy) into "parts" 
with a specific structure (Body, GhostHit, Ghost, Outline, Meshes).
@type: void
@param: convert (bool)
"""
func _set_run_convert(v: bool) -> void:
	run_convert = false

	if Engine.is_editor_hint() and v:
		_convert()

"""
Convert the GLB under glb_root into parts, and optionally save 
as a new scene or populate parts_root in the current scene.
@type: void
@param: none
"""
func _convert() -> void:
	var root := get_node_or_null(glb_root)

	if root == null:
		push_error("ConvertGlbToParts: invalid glb_root")
		return

	if part_scene == null:
		push_error("ConvertGlbToParts: part_scene is null")
		return

	if also_populate_parts_root:
		_out_root = get_node_or_null(parts_root)

		if _out_root == null:
			push_error("ConvertGlbToParts: invalid parts_root")
			return

		if _out_root.get_child_count() > 0:
			push_warning("ConvertGlbToParts: PartsRoot already has parts. Canceling conversion.")
			return

	# If it's already marked as converted, skip
	if root.has_meta("_converted") and root.get_meta("_converted") == true:
		push_warning("ConvertGlbToParts: glb_root already marked as converted.")
		return

	var pieces: Array[Node3D] = []

	for c in root.get_children():
		if c is Node3D:
			pieces.append(c as Node3D)

	if pieces.is_empty():
		push_warning("ConvertGlbToParts: No Node3D children under glb_root.")
		return

	# Target A: current scene
	var created_a := 0
	if also_populate_parts_root:
		var owner_a := get_tree().edited_scene_root
		for piece in pieces:
			if _wrap_piece_as_part(piece, _out_root, owner_a):
				created_a += 1
		print("ConvertGlbToParts: Finished. Parts created in scene PartsRoot: ", created_a)

	# Target B: temporary root for packing into new scene
	if save_as_scene:
		var temp_parts_root := Node3D.new()
		temp_parts_root.name = "PartsRoot"

		var owner_b := temp_parts_root

		for piece in pieces:
			_wrap_piece_as_part(piece, temp_parts_root, owner_b)

		temp_parts_root.owner = null
		_set_owner_recursive_for_pack(temp_parts_root, temp_parts_root)

		if save_path.ends_with("EngineModel.tscn"):
			_save_partsroot_into_existing_scene(save_path, temp_parts_root)
		else:
			_save_scene_direct(save_path, temp_parts_root)

	root.set_meta("_converted", true)
	if root is Node3D:
		(root as Node3D).visible = false

"""
Wrap a piece (Node3D) as a part, creating the necessary sub-nodes for each component.
@type: bool
@param: piece (Node3D), target_root (Node3D), scene_owner (Node)
"""
func _wrap_piece_as_part(piece: Node3D, target_root: Node3D, scene_owner: Node) -> bool:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(piece, meshes)

	if meshes.is_empty():
		return false

	var nice_name := _clean_name(piece.name)

	# ROOT PART (no instance)
	var part := Node3D.new()
	part.name = nice_name

	if part_script != null:
		part.set_script(part_script)

	if part.has_method("set"):
		part.set("part_name", nice_name)
	part.add_to_group("parts")
	target_root.add_child(part)

	if Engine.is_editor_hint() and scene_owner != null:
		part.owner = scene_owner

	# BODY
	var body := StaticBody3D.new()
	body.name = "Body"
	part.add_child(body)

	if Engine.is_editor_hint() and scene_owner != null:
		body.owner = scene_owner

	# GhostHit (Area) + GhostCollision container
	var ghost_hit := Area3D.new()
	ghost_hit.name = "GhostHit"
	body.add_child(ghost_hit)

	if Engine.is_editor_hint() and scene_owner != null:
		ghost_hit.owner = scene_owner

	var ghost_collision := Node3D.new()
	ghost_collision.name = "GhostCollision"
	ghost_hit.add_child(ghost_collision)

	if Engine.is_editor_hint() and scene_owner != null:
		ghost_collision.owner = scene_owner

	# Ghost container
	var ghost := Node3D.new()
	ghost.name = "Ghost"
	body.add_child(ghost)

	if Engine.is_editor_hint() and scene_owner != null:
		ghost.owner = scene_owner

	# Outline container
	var outline := Node3D.new()
	outline.name = "Outline"
	body.add_child(outline)

	if Engine.is_editor_hint() and scene_owner != null:
		outline.owner = scene_owner

	# Meshes container
	var meshes_container := Node3D.new()
	meshes_container.name = "Meshes"
	part.add_child(meshes_container)

	if Engine.is_editor_hint() and scene_owner != null:
		meshes_container.owner = scene_owner

	part.global_transform = piece.global_transform
	var outline_mat := _make_outline_material_like_ghost()

	for m in meshes:
		if m.mesh == null:
			continue

		# Real mesh
		var copy := MeshInstance3D.new()
		copy.name = m.name
		copy.mesh = m.mesh
		copy.material_override = m.material_override

		for si in range(m.get_surface_override_material_count()):
			copy.set_surface_override_material(si, m.get_surface_override_material(si))
		meshes_container.add_child(copy)

		if Engine.is_editor_hint() and scene_owner != null:
			copy.owner = scene_owner
		copy.global_transform = m.global_transform

		# Real collision
		var col := CollisionShape3D.new()
		col.name = "%s%s" % [REAL_COL_PREFIX, m.name]
		col.shape = m.mesh.create_trimesh_shape()
		body.add_child(col)
		if Engine.is_editor_hint() and scene_owner != null:
			col.owner = scene_owner
		col.global_transform = m.global_transform

		# Outline
		var ol := MeshInstance3D.new()
		ol.name = "OL_%s" % m.name
		ol.mesh = m.mesh
		ol.material_override = _make_outline_material_like_ghost()
		ol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		outline.add_child(ol)

		if Engine.is_editor_hint() and scene_owner != null:
			ol.owner = scene_owner

		var local_xf := outline.global_transform.affine_inverse() * m.global_transform
		local_xf.basis = local_xf.basis.scaled(Vector3.ONE * outline_scale)
		ol.transform = local_xf

		# Ghost mesh + ghost collision
		if make_ghost:
			var g := MeshInstance3D.new()
			g.name = m.name
			g.mesh = m.mesh
			ghost.add_child(g)

			if Engine.is_editor_hint() and scene_owner != null:
				g.owner = scene_owner

			g.global_transform = m.global_transform

			var gmat := StandardMaterial3D.new()
			gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gmat.albedo_color = Color(1, 1, 1, ghost_alpha)
			gmat.cull_mode = BaseMaterial3D.CULL_BACK
			g.material_override = gmat

			var ghc := CollisionShape3D.new()
			ghc.name = "%s%s" % [GHOST_COL_PREFIX, m.name]
			ghc.shape = m.mesh.create_trimesh_shape()
			ghost_hit.add_child(ghc)

			if Engine.is_editor_hint() and scene_owner != null:
				ghc.owner = scene_owner
			ghc.global_transform = m.global_transform

	# defaults
	outline.visible = false
	ghost.visible = false
	ghost_hit.monitoring = make_ghost
	ghost_hit.monitorable = make_ghost
	ghost_hit.collision_layer = 1 if make_ghost else 0
	ghost_hit.collision_mask = 1 if make_ghost else 0

	piece.visible = false
	return true

"""
Recursively collect all MeshInstance3D nodes under n into out.
@type: void
@param: n (Node), out (Array[MeshInstance3D])
"""
func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			out.append(c as MeshInstance3D)
		_collect_meshes(c, out)

"""
Recursively set owner of n and all its descendants to owner.
@type: void
@param: n (Node), owner (Node)
"""
func _set_owner_recursive(n: Node, owner: Node) -> void:
	n.owner = owner
	for c in n.get_children():
		_set_owner_recursive(c, owner)

"""
Free all children of n.
@type: void
@param: n (Node)
"""
func _free_children(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()

"""
Create a material for the outline meshes that looks like the ghost (emissive, unshaded, with outline_color).
@type: StandardMaterial3D
@param: none
"""
func _make_outline_material_like_ghost() -> StandardMaterial3D:
	var col := Color(0.2, 1.0, 0.2, 1.0)

	if typeof(outline_color) == TYPE_COLOR:
		col = outline_color

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col

	mat.cull_mode = BaseMaterial3D.CULL_FRONT

	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS

	return mat

"""
Clean up the piece name by removing specific suffixes and trailing "_0".
@type: String
@param: piece name (String)
"""
func _clean_name(s: String) -> String:
	var x := s
	x = x.replace("_Metal1_0", "").replace("_Metal2_0", "").replace("_Metal3_0", "").replace("_Trenie_C_0", "")
	x = x.replace("_0", "")
	return x

"""
Save the given root node as a scene to the specified path, 
handling uid:// paths and ensuring directories exist.
@type: void
@param: path (String), root (Node)
"""
func _save_scene_direct(path: String, root: Node) -> void:
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		var real_path := ResourceUID.get_id_path(id)

		if real_path.is_empty():
			push_error("Cannot resolve uid path: " + path)
			return
		path = real_path

	print("[Converter] About to save to: ", path)

	# Create target dir if it doesn't exist
	var dir_res := path.get_base_dir()
	var dir_abs := ProjectSettings.globalize_path(dir_res)

	if not DirAccess.dir_exists_absolute(dir_abs):
		var mk := DirAccess.make_dir_recursive_absolute(dir_abs)

		if mk != OK:
			push_error("Cannot create dir: %s err=%s" % [dir_abs, error_string(mk)])
			return

	var packed := PackedScene.new()
	var perr := packed.pack(root)

	if perr != OK:
		push_error("PackedScene.pack failed: " + error_string(perr))
		return

	var serr := ResourceSaver.save(packed, path)

	if serr != OK:
		push_error("ResourceSaver.save failed: " + error_string(serr) + " path=" + path)
		return

	print("[Converter] Saved scene OK -> ", path)

"""
Load an existing EngineModel scene, replace its PartsRoot with new_parts_root, and save it back.
@type: void
@param: engine_model_path (String), new_parts_root (Node3D)
"""
func _save_partsroot_into_existing_scene(engine_model_path: String, new_parts_root: Node3D) -> void:
	var base := load(engine_model_path)

	if base == null or not (base is PackedScene):
		push_error("Cannot load EngineModel scene: " + engine_model_path)
		return

	var inst := (base as PackedScene).instantiate()

	if inst == null:
		push_error("Cannot instantiate EngineModel scene.")
		return

	if not (inst is Node):
		push_error("EngineModel root invalid.")
		return

	# Erase old PartsRoot(s)
	for c in inst.get_children():
		if c.name == "PartsRoot" or String(c.name).begins_with("PartsRoot"):
			c.free()

	# Ensure new_parts_root is not in the scene already
	if new_parts_root.get_parent() != null:
		new_parts_root.get_parent().remove_child(new_parts_root)

	new_parts_root.name = "PartsRoot"
	inst.add_child(new_parts_root)

	_set_owner_recursive_for_pack(new_parts_root, inst)

	var packed := PackedScene.new()
	var err := packed.pack(inst)

	if err != OK:
		push_error("pack(EngineModel) failed: " + error_string(err))
		return

	err = ResourceSaver.save(packed, engine_model_path)

	if err != OK:
		push_error("save(EngineModel) failed: " + error_string(err))
		return

	print("[Converter] Updated EngineModel -> ", engine_model_path)

"""
Set the owner of a node and all its children recursively for proper packing.
@type: void
@param: root (Node), scene_root_owner (Node)
"""
func _set_owner_recursive_for_pack(root: Node, scene_root_owner: Node) -> void:
	for c in root.get_children():
		c.owner = scene_root_owner
		_set_owner_recursive_for_pack(c, scene_root_owner)