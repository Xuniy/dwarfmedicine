class_name ItemData
extends Resource

@export var id: StringName
@export var display_name: String = "Objet"
@export var model: PackedScene
@export var collision_shape: Shape3D
@export_range(0.01, 100.0, 0.01, "or_greater") var mass: float = 0.5
@export var held_position: Vector3 = Vector3.ZERO
@export var held_rotation_degrees: Vector3 = Vector3.ZERO


func get_held_transform() -> Transform3D:
	var angles := held_rotation_degrees * (PI / 180.0)
	return Transform3D(Basis.from_euler(angles), held_position)
