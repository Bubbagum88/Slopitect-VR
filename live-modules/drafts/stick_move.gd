extends SlopitectModule

# Smooth locomotion: the right thumbstick moves the player where the headset faces.

var speed := 1.5
var deadzone := 0.15
var origin: Node3D = null


func setup() -> String:
	var cam = ctx.get("camera")
	if cam == null or not is_instance_valid(cam):
		return "no camera"
	origin = cam.get_parent() as Node3D
	if origin == null:
		return "camera has no origin to move"
	if ctx.get("right") == null:
		return "no right controller"
	register("stick_move_speed", _speed, "set walking speed: speed (metres per second, 0.2 to 5)")
	return ""


func _speed(request: Dictionary) -> Dictionary:
	var s = request.get("speed")
	if typeof(s) != TYPE_FLOAT and typeof(s) != TYPE_INT:
		return {"ok": false, "error": "speed must be a number"}
	if s < 0.2 or s > 5.0:
		return {"ok": false, "error": "speed must be between 0.2 and 5"}
	speed = float(s)
	return {"ok": true, "speed": speed}


func _process(delta: float) -> void:
	var right = ctx.get("right")
	var cam = ctx.get("camera")
	if origin == null or not is_instance_valid(origin) or right == null or not is_instance_valid(right) or cam == null or not is_instance_valid(cam):
		return
	var stick: Vector2 = right.get_vector2("primary")
	if stick.length() < deadzone:
		return
	var b: Basis = cam.global_transform.basis
	var forward := Vector3(-b.z.x, 0.0, -b.z.z)
	var side := Vector3(b.x.x, 0.0, b.x.z)
	if forward.length() < 0.01 or side.length() < 0.01:
		return
	forward = forward.normalized()
	side = side.normalized()
	var move := (side * stick.x + forward * stick.y) * speed * delta
	origin.global_position += move
