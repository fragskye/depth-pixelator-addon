class_name Freecam
extends Camera3D

@export var look_sensitivity: float = 1.0
@export var speed: float = 5.0
@export var speed_base: float = 0.8
@export var fov_base: float = 0.9
@export var smoothing: float = 0.1

var pitch: float = 0.0
var yaw: float = 0.0
var roll: float = 0.0

var _looking: bool = false
var _speed_log: float = 0.0
var _fov_log: float = 0.0
var _move: Vector3 = Vector3.ZERO

func _ready() -> void:
	pitch = rotation_degrees.x
	yaw = rotation_degrees.y
	roll = rotation_degrees.z
	_speed_log = log(speed) / log(speed_base)
	_fov_log = log(fov) / log(fov_base)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button_event.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_button_event.pressed:
				_looking = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				_looking = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if event is InputEventMouseMotion:
		var mouse_motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		if _looking:
			pitch -= mouse_motion_event.relative.y * 0.1 * look_sensitivity
			yaw -= mouse_motion_event.relative.x * 0.1 * look_sensitivity
			normalize_angles()
			update_angles()

func normalize_angles() -> void:
	pitch = clampf(pitch, -89.0, 89.0)
	
	while yaw > 180.0:
		yaw -= 360.0
	
	while yaw < -180.0:
		yaw += 360.0

func update_angles() -> void:
	basis = Basis.IDENTITY
	rotate_object_local(Vector3.UP, deg_to_rad(yaw))
	rotate_object_local(Vector3.RIGHT, deg_to_rad(pitch))
	rotate_object_local(Vector3.FORWARD, deg_to_rad(roll))

func _process(delta: float) -> void:
	var move_target_x: float = Input.get_axis(&"move_left", &"move_right")
	var move_target_y: float = Input.get_axis(&"move_down", &"move_up")
	var move_target_z: float = Input.get_axis(&"move_forward", &"move_backward")
	if Input.is_action_pressed(&"freecam_shift"):
		if Input.is_action_just_pressed(&"freecam_scroll_up"):
			_speed_log -= 1.0
		if Input.is_action_just_pressed(&"freecam_scroll_down"):
			_speed_log += 1.0
	else:
		if Input.is_action_just_pressed(&"freecam_scroll_up"):
			_fov_log += 1.0
		if Input.is_action_just_pressed(&"freecam_scroll_down"):
			_fov_log -= 1.0
	var move_target: Vector3 = Vector3(move_target_x, move_target_y, move_target_z).normalized()
	speed = pow(speed_base, _speed_log)
	_move = _move.lerp(speed * move_target, 1.0 - pow(1.0 - smoothing, delta * 60.0))
	_fov_log = log(clampf(pow(fov_base, _fov_log), 1.0, 179.0)) / log(fov_base)
	fov = lerpf(fov, pow(fov_base, _fov_log), 1.0 - pow(1.0 - smoothing, delta * 60.0))
	position += delta * (basis * _move)
