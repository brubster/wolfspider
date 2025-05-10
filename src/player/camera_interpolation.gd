extends Camera3D
## Transform interpolation for the first-person camera
## 
## Ensures smooth movement and rotation, even when engine FPS is not divisible
## by physics ticks per second. (i.e. 144hz monitor, 60 physics UPS)

@export var follow_target: NodePath

var target: Node3D
var update: bool
var gt_prev: Transform3D
var gt_current: Transform3D


func _ready():
	set_as_top_level(true)
	target = get_node_or_null(follow_target) as Node3D
	if target == null:
		target = get_parent() as Node3D
	global_transform = target.global_transform
	
	gt_prev = target.global_transform
	gt_current = target.global_transform


func update_transform():
	gt_prev = gt_current
	gt_current = target.global_transform


func _process(_delta):
	if update:
		update_transform()
		update = false
	
	var f = clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	global_transform = gt_prev.interpolate_with(gt_current, f)


func _physics_process(_delta):
	update = true
