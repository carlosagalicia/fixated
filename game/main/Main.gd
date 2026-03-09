extends Node3D

enum Mode {MOUNT, DISMOUNT}

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var radial: ColorRect = $UI/Crosshair/Radial
@onready var crosshair: Control = $UI/Crosshair

@export var crosshair_offset := Vector2.ZERO
@export var yaw_speed: float = 2.5
@export var pitch_speed: float = 2.0
@export var zoom_speed: float = 0.5
@export var min_distance: float = 2.0
@export var max_distance: float = 3.0
@export var zoom_time: float = 0.15
@export var hold_time_to_act: float = 0.5
@export var click_move_tolerance_px := 8.0

var raycaster: PartRaycaster
var camera_controller: CameraOrbitController
var hover_controller: HoverController
var interaction_controller: InteractionController
var mode: Mode = Mode.DISMOUNT
var parts: Array[Node] = []

"""
Called when the node enters the scene tree for the first time. Set to dismount
mode by default. Initialize camera rotation and distance. Get all parts in the scene.
@type: void
@param: none
"""
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_setup_camera_controller()
	_setup_mode_selector()
	_setup_parts()
	_setup_interaction_stack()
	_refresh_mount_ghosts()
	radial.visible = false

"""
Set up the camera controller to allow the player to orbit around the 
pivot point and zoom in/out. Configure the controller with the 
specified speeds, distance limits, and zoom time.
@type: void
@param: none
"""
func _setup_camera_controller() -> void:
	camera_controller = CameraOrbitController.new()
	camera_controller.setup(
		pivot,
		camera,
		{
			"yaw_speed": yaw_speed,
			"pitch_speed": pitch_speed,
			"zoom_speed": zoom_speed,
			"min_distance": min_distance,
			"max_distance": max_distance,
			"zoom_time": zoom_time
		}
	)
	camera_controller.initialize_from_scene()

"""
Set up the mode selector UI element to allow the player to 
switch between MOUNT and DISMOUNT modes.
@type: void
@param: none
"""
func _setup_mode_selector() -> void:
	var selector := $UI/ModeSelector
	if selector is OptionButton:
		selector.select(1)

"""
Get all nodes in the scene that are part of the "parts" group and store 
them in the parts array for later use in interaction logic.
@type: void
@param: none
"""
func _setup_parts() -> void:
	parts = get_tree().get_nodes_in_group("parts")

"""
Set up the interaction stack by initializing the raycaster, hover controller, 
and interaction controller. The raycaster will determine what part the player is 
pointing at, the hover controller will manage hover states, and the interaction 
controller will handle player input for mounting and dismounting parts based 
on the current mode.
@type: void
@param: none
"""
func _setup_interaction_stack() -> void:
	raycaster = PartRaycaster.new()
	raycaster.setup(self , camera, Callable(self , "_get_current_mode"))

	hover_controller = HoverController.new()
	hover_controller.setup(raycaster, Callable(self , "_get_current_mode"))

	interaction_controller = InteractionController.new()
	interaction_controller.setup(
		raycaster,
		camera_controller,
		hover_controller,
		Callable(self , "_get_current_mode"),
		Callable(self , "_refresh_mount_ghosts"),
		radial,
		{
			"hold_time_to_act": hold_time_to_act,
			"click_move_tolerance_px": click_move_tolerance_px
		}
	)

"""
Get the current mode (MOUNT or DISMOUNT) for the raycaster to determine valid interactions.
@type: int
@param: none
"""
func _get_current_mode() -> int:
	return mode

"""
Show all ghost parts that can be mounted in the MOUNT mode
mode by default
@type: void
@param: none
"""
func _refresh_mount_ghosts() -> void:
	for p in parts:
		if p:
			p.set_ghost_visible(false)

	if mode != Mode.MOUNT:
		return

	var mountables: Array[Node3D] = []

	for p in parts:
		if p and p.is_dismounted() and p.can_mount():
			mountables.append(p)

	if mountables.is_empty():
		for p in parts:
			if p and p.is_dismounted() and p.is_mount_root():
				p.set_ghost_visible(true)
		return

	for p in mountables:
		p.set_ghost_visible(true)

"""
Handle mode switching between MOUNT and DISMOUNT when the player selects an option from the UI.
@type: void
@param: index (int)
"""
func _on_mode_selector_item_selected(index: int) -> void:
	mode = Mode.MOUNT if index == 0 else Mode.DISMOUNT
	_refresh_mount_ghosts()
	interaction_controller.reset_hold_state()
	hover_controller.clear_hover()

	var enable_real_outline := (mode == Mode.DISMOUNT)
	for p in parts:
		if p:
			p.set_real_outline_enabled(enable_real_outline)

"""
Handle player input for hovering, clicking, and zooming. 
Left-click behavior depends on the current mode (MOUNT or DISMOUNT).
@type: void
@param: left-click event (InputEvent)
"""
func _unhandled_input(event: InputEvent) -> void: # called when an InputEvent happens
	interaction_controller.handle_input(event)

"""
Update the camera rotation based on player input. Handle hold-to-dismount logic in DISMOUNT mode.
@type: void
@param: current time elapsed (float)
"""
func _process(delta: float) -> void:
	camera_controller.update_rotation(delta)
	interaction_controller.update(delta, get_viewport().get_mouse_position())
	_update_crosshair()

"""
Update the position of the crosshair UI element to follow the mouse cursor, 
applying any specified offset.
@type: void
@param: none
"""
func _update_crosshair() -> void:
	var m := get_viewport().get_mouse_position() + crosshair_offset
	crosshair.position = m - crosshair.size * 0.5
