class_name HoverController
extends RefCounted

const MODE_DISMOUNT := 1

var raycaster: PartRaycaster
var mode_getter: Callable
var hovered_part: Node3D = null
var highlighted_children: Array[Node3D] = []

"""
Set up the HoverController with a reference to the PartRaycaster 
and a Callable to get the current mode.
@type: void
@param: raycaster_ref (PartRaycaster), get_mode (Callable)
"""
func setup(raycaster_ref: PartRaycaster, get_mode: Callable) -> void:
	raycaster = raycaster_ref
	mode_getter = get_mode

"""
Update the hovered part based on the current mouse position. 
Outline the hovered part in green, and if in DISMOUNT mode, 
also show red blockers for parts that would prevent dismounting.
@type: void
@param: current mouse position (Vector2)
"""
func update_hover(mouse_pos: Vector2) -> void:
	if raycaster == null:
		return

	var info: Variant = raycaster._raycast_from_screen(mouse_pos)
	var new_hover := info["part"] as Node3D
	var new_is_ghost := bool(info["is_ghost"])

	if new_hover != hovered_part:
		if hovered_part:
			hovered_part.set_hovered(false)

		clear_highlighted_children()

		hovered_part = new_hover

		if hovered_part:
			hovered_part.set_hovered(true, new_is_ghost)

			var mode: Variant = mode_getter.call()
			if mode == MODE_DISMOUNT:
				var blockers_list: Array[Node3D] = hovered_part.get_blocking_dismount_children()
				for b in blockers_list:
					if b:
						b.set_temp_color(Color.RED)
						highlighted_children.append(b)

"""
Clear the parts that were highlighted
@type: void
@param: none
"""
func clear_highlighted_children() -> void:
	for p in highlighted_children:
		if p:
			p.clear_temp_color()

	highlighted_children.clear()

"""
Clear the hovered part and any highlighted children
@type: void
@param: none
"""
func clear_hover() -> void:
	if hovered_part:
		hovered_part.set_hovered(false)

	hovered_part = null
	clear_highlighted_children()
