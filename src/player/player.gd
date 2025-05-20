class_name Player
extends CharacterBody3D
## Self-contained player script
## 
## Handles control input and player movement.
## TODO: player/weapon logic?
## TODO: Camera "jitter" when crouching mid-air


@export_group("Debug")
@export var DEBUG_THIRD_PERSON: bool = false
@export_group("Controls")
@export var AUTO_BHOP: bool = false
@export var MOUSE_SENSITIVITY: float = 0.05
@export_group("Movement")
@export_subgroup("Ground")
@export var MAX_VELOCITY_AIR: float = 0.8
@export var MAX_VELOCITY_WALK: float = 5.0
@export var MAX_VELOCITY_SPRINT: float = 7.5
@export var MAX_VELOCITY_CROUCH: float = 3.0
@export var MAX_ACCELERATION: float = 80.0
@export var STOP_SPEED: float = 1.5
@export var FRICTION: float = 7.0
@export_subgroup("Air")
@export var GRAVITY: float = 15.34
@export var JUMP_IMPULSE: float = sqrt(2 * GRAVITY * 0.93)
@export_group("Crouch")
@export_range(0.5, 2.0) var CROUCH_HEIGHT: float = 1.0  # Should be less than collider.shape.height

@onready var camera_position := $CameraPosition as Node3D
@onready var camera_pivot := %CameraPivot as Node3D
@onready var collider := $Collider as CollisionShape3D
@onready var coyote_timer := $CoyoteTimer as Timer

# Values for crouch tweening
@onready var camera_position_original_y_position: float = camera_position.position.y
@onready var collider_original_height: float = collider.shape.height
@onready var collider_original_y_position: float = collider.position.y
@onready var camera_distance_from_collider_top: float = collider_original_height - camera_position_original_y_position
@onready var crouch_offset: float = collider_original_height - CROUCH_HEIGHT

# Input variables
var _wish_dir: Vector3
var _wish_jump: bool
var _wish_sprint: bool
var _wish_crouch: bool

## Whether the player collided with the floor on the previous frame
var was_on_floor: bool
## Whether the player is in "coyote time" - left the floor (without jumping) and should be allowed to jump
var coyote: bool

# State
# -- TODO: Mainly for tracking animation to play? Idk
enum State {
	IDLE,
	WALK,
	SPRINT,
	CROUCH,
	SLIDE,
	JUMP,  # TODO: needed?
	FALL,  #       needed?
}
#var _state: State = State.IDLE


enum CrouchState {
	STANDING,
	CROUCHED_GROUND,
	CROUCHED_AIR,
}
var _crouch_state: CrouchState = CrouchState.STANDING


func _ready() -> void:
	if DEBUG_THIRD_PERSON:
		camera_pivot.position.y = 2.0
		camera_pivot.position.z = 7.0
	
	Input.set_use_accumulated_input(false)  # https://yosoyfreeman.github.io/article/godot/tutorial/achieving-better-mouse-input-in-godot-4-the-perfect-camera-controller
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	self.floor_constant_speed = true  # Make player move at constant speed up slopes
	
	# Sanity checks
	CROUCH_HEIGHT = clampf(CROUCH_HEIGHT, 0.1, collider.shape.height)  # CROUCH_HEIGHT should not be higher than collider's height


func _exit_tree() -> void:
	Input.set_use_accumulated_input(true)  # Turn accumulated input back on when player is not instantiated to reduce CPU load


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build():
		if event.is_action_pressed(&"debug_quit"):
			get_tree().quit()
	
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_mouse_look(event as InputEventMouseMotion)


func _physics_process(delta: float) -> void:
	_process_input()
	
	if _wish_crouch:
		crouch(delta)
	elif _crouch_state != CrouchState.STANDING:
		uncrouch(delta)
	
	var jumped: bool
	if _wish_jump:
		jumped = jump(delta)
	
	if not jumped:
		_process_movement(delta)
	
	was_on_floor = is_on_floor()
	move_and_slide()


func _process_input() -> void:
	# Movement direction
	var input_dir: Vector2 = Input.get_vector(&"move_left", &"move_right",
			&"move_forward", &"move_backward")
	_wish_dir = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	
	# Jump
	_wish_jump = Input.is_action_just_pressed(&"jump") or \
			(AUTO_BHOP and Input.is_action_pressed(&"jump"))
	
	# Sprint
	_wish_sprint = Input.is_action_pressed(&"sprint")
	
	# Crouch
	_wish_crouch = Input.is_action_pressed(&"crouch")


func _process_movement(delta: float) -> void:
	# Checks that Player JUST left the floor
	# Does not count jumping itself because of velocity.y check
	if not is_on_floor() and was_on_floor and velocity.y <= 0.0:
		coyote = true
		coyote_timer.start()
	
	if is_on_floor():
		velocity = update_velocity_ground(get_max_speed_ground(), delta)
	else:
		# Only apply gravity while in air
		velocity.y -= GRAVITY * delta
		velocity = update_velocity_air(delta)


func _mouse_look(event: InputEventMouseMotion) -> void:
	# Rotate the player and camera pivot based on mouse movement
	rotate_y(deg_to_rad(-event.screen_relative.x * MOUSE_SENSITIVITY))
	orthonormalize()
	camera_pivot.rotate_x(deg_to_rad(-event.screen_relative.y * MOUSE_SENSITIVITY))
	camera_pivot.orthonormalize()
	
	# Stop from looking too far up or down
	camera_pivot.rotation.x = clampf(camera_pivot.rotation.x, deg_to_rad(-70.0), deg_to_rad(90.0))


## Returns a boolean; whether the player jumped or not
func jump(delta: float) -> bool:
	if is_on_floor() or coyote:
		# Don't apply friction for one frame to allow for "perfect" bunny hop
		velocity.y = JUMP_IMPULSE
		velocity = update_velocity_air(delta)  # Use "air" to skip ground friction this frame
		return true
	return false


func crouch(_delta: float) -> void:
	if _crouch_state != CrouchState.STANDING:
		return
	
	if is_on_floor():
		_crouch_ground()
	else:
		_crouch_air()


## Returns a boolean; whether the player could uncrouch or not
func uncrouch(_delta: float) -> bool:
	if test_move(global_transform, Vector3(0.0, collider_original_height - CROUCH_HEIGHT, 0.0)):
		return false
	
	match _crouch_state:
		CrouchState.CROUCHED_GROUND:
			_uncrouch_ground()
		CrouchState.CROUCHED_AIR:
			_uncrouch_air()
	
	return true


func _crouch_ground() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(collider, "shape:height", CROUCH_HEIGHT, 0.1)
	tween.tween_property(collider, "position:y", CROUCH_HEIGHT / 2, 0.1)
	tween.tween_property(camera_position, "position:y", CROUCH_HEIGHT - camera_distance_from_collider_top, 0.1)
	_crouch_state = CrouchState.CROUCHED_GROUND


func _uncrouch_ground() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(collider, "shape:height", collider_original_height, 0.1)
	tween.tween_property(collider, "position:y", collider_original_y_position, 0.1)
	tween.tween_property(camera_position, "position:y", camera_position_original_y_position, 0.1)
	_crouch_state = CrouchState.STANDING


func _crouch_air() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(collider, "shape:height", CROUCH_HEIGHT, 0.1)
	tween.tween_property(collider, "position:y", collider_original_height - CROUCH_HEIGHT / 2, 0.1)  # in this example, want 1.1? ==> 1.6 - 1.0 / 2
	_crouch_state = CrouchState.CROUCHED_AIR


func _uncrouch_air() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(collider, "shape:height", collider_original_height, 0.1)
	tween.tween_property(collider, "position:y", collider_original_y_position, 0.1)
	_crouch_state = CrouchState.STANDING


func accelerate(max_speed: float, delta: float) -> Vector3:
	# Get player's current speed as a projection of velocity onto the _wish_dir
	var current_speed: float = velocity.dot(_wish_dir)
	# How much we accelerate is the difference between the max speed and the
	# current speed clamped between 0.0 and MAX_ACCELERATION
	var add_speed: float = clampf(max_speed - current_speed, 0.0, MAX_ACCELERATION * delta)
	
	return velocity + add_speed * _wish_dir


func update_velocity_ground(max_speed: float, delta: float) -> Vector3:
	# Apply friction when on the ground, then accelerate
	var speed: float = velocity.length()
	
	if speed != 0.0:
		var control: float = maxf(STOP_SPEED, speed)
		var drop: float = control * FRICTION * delta
		
		# Scale the velocity based on friction
		velocity *= maxf(speed - drop, 0.0) / speed
	
	return accelerate(max_speed, delta)


func update_velocity_air(delta: float) -> Vector3:
	# Do not apply friction
	return accelerate(MAX_VELOCITY_AIR, delta)


func get_max_speed_ground() -> float:  # TODO: can this design be improved?
	if _crouch_state != CrouchState.STANDING:
		return MAX_VELOCITY_CROUCH
	return MAX_VELOCITY_SPRINT if _wish_sprint else MAX_VELOCITY_WALK


func _on_coyote_timer_timeout() -> void:
	coyote = false
