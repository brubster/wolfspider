extends MeshInstance3D

@export var collider: CollisionShape3D

func _process(_delta: float) -> void:
	self.position.y = collider.position.y
	self.mesh.height = collider.shape.height
