extends CharacterBody3D


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
@export var JUMP_IMPULSE: float = sqrt(2 * GRAVITY * 0.85)


@onready var camera_pivot := %CameraPivot as Node3D
@onready var collider := $Collider as CollisionShape3D
@onready var uncrouch_shapecast := $UncrouchShapecast as ShapeCast3D
@onready var mesh := $Mesh as MeshInstance3D


# Input variables
var _wish_dir: Vector3
var _wish_jump: bool
var _wish_sprint: bool
var _wish_crouch: bool


# State
# -- TODO: Mainly for tracking animation to play? Idk
var _is_crouched: bool  # TODO: temp...
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


func _ready() -> void:
	Input.set_use_accumulated_input(false)  # TODO: https://yosoyfreeman.github.io/article/godot/tutorial/achieving-better-mouse-input-in-godot-4-the-perfect-camera-controller
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	self.floor_constant_speed = true  # Make player move at constant speed up slopes
	self.floor_snap_length = 0.1  # Default value


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
	#elif _is_crouched:
	else:  # TODO: should only be called when ACTUALLY crouched, but this is needed to prevent partially crouching and not uncrouching automatically (due to the scuffed crouch() function)
		try_uncrouch()
	
	_process_movement(delta)


func _process_input() -> void:
	# Movement direction
	var input_dir: Vector2 = Input.get_vector(&"move_left", &"move_right", \
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
	if is_on_floor():
		# If _wish_jump is true, we won't apply friction for one frame to allow
		# for "perfect" bunny hop
		if _wish_jump:
			velocity.y = JUMP_IMPULSE
			velocity = update_velocity_air(delta)  # Use "air" to skip friction
		else:
			velocity = update_velocity_ground(get_max_speed_ground(), delta)
	else:
		# Only apply gravity while in air
		velocity.y -= GRAVITY * delta
		velocity = update_velocity_air(delta)
	
	move_and_slide()


func _mouse_look(event: InputEventMouseMotion) -> void:
	# Rotate the player and camera pivot based on mouse movement
	rotate_y(deg_to_rad(-event.screen_relative.x * MOUSE_SENSITIVITY))
	orthonormalize()
	camera_pivot.rotate_x(deg_to_rad(-event.screen_relative.y * MOUSE_SENSITIVITY))
	camera_pivot.orthonormalize()
	
	# Stop from looking too far up or down
	camera_pivot.rotation.x = clampf(camera_pivot.rotation.x, deg_to_rad(-70.0), deg_to_rad(90.0))


func crouch(delta: float) -> void:
	if collider.scale.y <= 0.5:
		_is_crouched = true
		return
	
	collider.scale.y -= 5.0 * delta  # 1.8m * 5% = 0.09
	collider.scale.y = clampf(collider.scale.y, 0.5, 1.0)
	
	mesh.scale.y -= 5.0 * delta
	mesh.scale.y = clampf(mesh.scale.y, 0.5, 1.0)
	
	#if is_on_floor():
	#	move_and_collide(Vector3(0.0, -0.5 * delta, 0.0))
	#else:
	#	move_and_collide(Vector3(0.0, 0.5 * delta, 0.0))


# Returns a boolean whether the player can uncrouch or not
func try_uncrouch() -> bool:
	if uncrouch_shapecast.is_colliding():
		return false
	else:
		collider.scale.y = 1.0
		mesh.scale.y = 1.0
		#move_and_collide(Vector3(0.0, 0.1, 0.0))
		_is_crouched = false
		return true


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


func get_max_speed_ground() -> float:  # TODO
	if Input.is_action_pressed(&"crouch"):
		return MAX_VELOCITY_CROUCH
	return MAX_VELOCITY_SPRINT if _wish_sprint else MAX_VELOCITY_WALK
