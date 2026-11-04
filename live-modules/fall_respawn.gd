extends SlopitectModule

# Things in the world that fall below -20 m go back to where they last
# came to rest, and stop moving.

const FLOOR := -20.0
const SCAN := 0.25  # seconds between checks
const STILL := 1.0  # seconds without moving before a spot counts as home

var _server
var _world: Node3D
var _seen := {}  # name -> {"home", "rot", "has_home", "pos", "still"}
var _timer := 0.0


func setup() -> String:
	_server = ctx["server"]
	_world = ctx["world"]
	set_process(true)
	return ""


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or _world == null:
		return
	_timer = SCAN
	for node in _world.get_children():
		if not (node is Node3D) or String(node.name) == "Ground":
			continue
		var key := String(node.name)
		var p: Vector3 = node.global_position
		if not _seen.has(key):
			_seen[key] = {"home": p, "rot": node.global_rotation_degrees, "has_home": false, "pos": p, "still": 0.0}
		var s: Dictionary = _seen[key]
		if p.y < FLOOR:
			_respawn(key, s)
			continue
		if p.distance_to(s["pos"]) < 0.001:
			s["still"] = float(s["still"]) + SCAN
			if float(s["still"]) >= STILL:
				s["home"] = p
				s["rot"] = node.global_rotation_degrees
				s["has_home"] = true
		else:
			s["still"] = 0.0
			s["pos"] = p


func _respawn(key: String, s: Dictionary) -> void:
	if not bool(s["has_home"]):
		return
	var h: Vector3 = s["home"]
	var r: Vector3 = s["rot"]
	_server.run({"cmd": "move", "name": key, "position": [h.x, h.y, h.z], "rotation": [r.x, r.y, r.z]})
	_server.run({"cmd": "physics_push", "name": key, "velocity": [0, 0, 0]})
	s["pos"] = h
	s["still"] = 0.0
