extends SlopitectModule

# Gives the person a column body at hip height: a hidden column collider
# that follows them, so things with physics on bump into them.

const RADIUS := 0.11
const HEIGHT := 0.5
const HIP_Y := 0.95  # the column's middle, above the floor

var _collider: AnimatableBody3D
var _camera: Node3D


func setup() -> String:
	_camera = ctx["camera"]
	_collider = AnimatableBody3D.new()
	_collider.name = "PlayerColumn"
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = RADIUS
	cylinder.height = HEIGHT
	shape.shape = cylinder
	_collider.add_child(shape)
	add_child(_collider)
	set_physics_process(true)
	return ""


func _exit_tree() -> void:
	if is_instance_valid(_collider):
		_collider.queue_free()


func _physics_process(_delta: float) -> void:
	if _camera == null:
		return
	var p := _camera.global_position
	_collider.global_position = Vector3(p.x, HIP_Y, p.z)
