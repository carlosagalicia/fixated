class_name PartHighlight
extends RefCounted

var meshes_getter: Callable
var _temp_color_active := false
var _orig_surface_override_by_mesh: Dictionary = {}

"""
Initialize the PartHighlight with a callable that returns 
the meshes to be highlighted.
@type: void
@param: callable that returns an array of MeshInstance3D 
	nodes to be highlighted (Callable)
"""
func setup(get_meshes_callable: Callable) -> void:
	meshes_getter = get_meshes_callable

"""
Cache the original surface override materials of all meshes 
under the meshes_container. This allows temporary color changes to be applied 
and then reverted back to the original materials.
@type: void
@param: none
"""
func cache_original_appearance() -> void:
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
		cache_original_appearance()

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
Helper function to retrieve the meshes to be highlighted by 
calling the provided meshes_getter callable.
@type: Array[MeshInstance3D]
@param: none
"""
func _get_meshes() -> Array[MeshInstance3D]:
	if not meshes_getter.is_valid():
		return []

	var result = meshes_getter.call()
	if result is Array:
		return result as Array[MeshInstance3D]

	return []
