class_name InteractionController
extends RefCounted

const MODE_MOUNT := 0
const MODE_DISMOUNT := 1

var raycaster: PartRaycaster
var camera_controller: CameraOrbitController
var hover_controller: HoverController
var mode_getter: Callable
var refresh_mount_ghosts_callback: Callable
var radial: ColorRect
var hold_time_to_act: float
var click_move_tolerance_px: float
var _hold_part: Node3D = null
var _hold_timer := 0.0
var _holding := false
var _press_pos := Vector2.ZERO
var _press_is_ghost := false
var _press_part: Node3D = null
var _hold_fired := false

"""
Set up the InteractionController with necessary references and configuration.
@type: void
@param: raycaster_ref (PartRaycaster), 
	camera_ref (CameraOrbitController), 
	hover_ref (HoverController), 
	get_mode (Callable), 
	refresh_callback (Callable), 
	radial_node (ColorRect), 
	config (Dictionary)
"""
func setup(
	raycaster_ref: PartRaycaster,
	camera_ref: CameraOrbitController,
	hover_ref: HoverController,
	get_mode: Callable,
	refresh_callback: Callable,
	radial_node: ColorRect,
	config: Dictionary
) -> void:
	raycaster = raycaster_ref
	camera_controller = camera_ref
	hover_controller = hover_ref
	mode_getter = get_mode
	refresh_mount_ghosts_callback = refresh_callback
	radial = radial_node

	hold_time_to_act = config.get("hold_time_to_act", 0.5)
	click_move_tolerance_px = config.get("click_move_tolerance_px", 8.0)

"""
Handle input events for mouse hover, clicks, and zooming.
@type: void
@param: event (InputEvent)
"""
func handle_input(event: InputEvent) -> void:
	if hover_controller == null or raycaster == null or camera_controller == null:
		return

	# mouse hover
	if event is InputEventMouseMotion:
		hover_controller.update_hover(event.position)

	# left click / hold logic
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		hover_controller.update_hover(event.position)

		if event.pressed:
			_press_pos = event.position
			_hold_fired = false

			var info := raycaster._raycast_from_screen(event.position)
			var part: Node3D = info["part"]
			var is_ghost: bool = info["is_ghost"]

			_press_part = part
			_press_is_ghost = is_ghost

			var mode: Variant = mode_getter.call()
			var valid_hold := false

			if mode == MODE_MOUNT:
				valid_hold = part != null and is_ghost
			else:
				valid_hold = part != null and not is_ghost

			if valid_hold:
				start_hold(part)
			else:
				reset_hold_state()

		else:
			var moved := _press_pos.distance_to(event.position) > click_move_tolerance_px

			if not _hold_fired and not moved and _press_part != null:
				camera_controller.focus_on_part(_press_part, _press_is_ghost)

			reset_hold_state()
			_press_part = null

	# zoom
	if event.is_action_pressed("zoom_in"):
		camera_controller.zoom_in()

	elif event.is_action_pressed("zoom_out"):
		camera_controller.zoom_out()

"""
Update the hold state each frame, checking if the player is still holding on 
the same part and if the hold time has been reached to trigger mount/dismount.
@type: void
@param: delta (float), mouse_pos (Vector2)
"""
func update(delta: float, mouse_pos: Vector2) -> void:
	if not _holding:
		return

	if _hold_part == null:
		reset_hold_state()
		return

	_hold_timer += delta
	var progress := _hold_timer / hold_time_to_act

	if radial:
		radial.visible = true
		_set_hold_progress(progress)

	var current := raycaster.get_part_under_mouse(mouse_pos)

	if current != _hold_part:
		_hold_part = current
		_hold_timer = 0.0

		if radial:
			radial.visible = _hold_part != null
		_set_hold_progress(0.0)

	if _hold_part != null and _hold_timer >= hold_time_to_act:
		var mode: Variant = mode_getter.call()

		if mode == MODE_MOUNT:
			_hold_part.try_mount()
		else:
			_hold_part.try_dismount()

		refresh_mount_ghosts_callback.call()
		_hold_fired = true
		reset_hold_state()

"""
Reset the hold state when the player releases the mouse button 
or moves the cursor away from the part.
@type: void
@param: none
"""
func reset_hold_state() -> void:
	_holding = false
	_hold_timer = 0.0
	_hold_part = null

	if radial:
		radial.visible = false

	_set_hold_progress(0.0)

"""
Start the hold process when the player clicks on a valid part.
@type: void
@param: the part that is being held (Node3D)
"""
func start_hold(part: Node3D) -> void:
	_holding = true
	_hold_timer = 0.0
	_hold_part = part

	if radial:
		radial.visible = true

	_set_hold_progress(0.0)

"""
Set the radial progress shader parameter to show hold-to-dismount progress.
@type: void
@param: progress value between 0.0 and 1.0 (float)
"""
func _set_hold_progress(p: float) -> void:
	if radial == null:
		return

	var mat := radial.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("progress", clampf(p, 0.0, 1.0))
