extends MeshInstance3D

@export var collider: CollisionShape3D

func _physics_process(_delta: float) -> void:
	self.position.y = collider.position.y
	self.mesh.height = collider.shape.height
