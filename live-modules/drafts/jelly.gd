extends SlopitectModule

# Jelly physics for the avatar: a spring squashes and stretches it
# (volume kept) when it moves, starts or stops. jelly_poke wobbles it.

var _root: Node3D = null
var _base_scale := Vector3.ONE
var _last_pos := Vector3.ZERO
var _last_vel := Vector3.ZERO
var _s := 0.0      # squash amount (+ tall, - flat)
var _sv := 0.0     # its speed
var stiffness := 120.0
var damping := 6.0


func setup() -> String:
	_root = _find_avatar()
	if _root == null:
		return "avatar node not found"
	_base_scale = _root.scale
	_last_pos = _root.global_position
	register("jelly_poke", _poke, "wobble the avatar: optional strength (0.1 to 1, default 0.4)")
	register("jelly_set", _set, "jelly feel: optional stiffness (20 to 400), damping (1 to 30)")
	return ""


func _find_avatar() -> Node3D:
	var mod = null
	var m = ctx.get("modules")
	if typeof(m) == TYPE_DICTIONARY:
		mod = m.get("avatar")
	elif m is Node:
		mod = m.get_node_or_null("avatar")
	if mod is Object:
		for p in ["avatar", "root", "body", "_avatar", "_root", "_body", "node"]:
			var v = mod.get(p)
			if v is Node3D and is_instance_valid(v):
				return v
	if mod is Node:
		for c in mod.get_children():
			if c is Node3D:
				return c
	var top = get_tree().root if is_inside_tree() else null
	if top != null:
		var found = top.find_child("*vatar*", true, false)
		if found is Node3D:
			return found
	return null


func _process(delta: float) -> void:
	if _root == null or not is_instance_valid(_root) or delta <= 0.0:
		return
	var pos := _root.global_position
	var vel := (pos - _last_pos) / delta
	_last_pos = pos
	if vel.length() > 20.0:
		vel = Vector3.ZERO  # teleport, not motion
	var acc := (vel - _last_vel) / delta
	_last_vel = vel
	# rising stretches, landing/starting/stopping squashes
	var drive := acc.y * 0.002 - Vector2(acc.x, acc.z).length() * 0.0015
	_sv += (-stiffness * _s - damping * _sv) * delta + clampf(drive, -0.5, 0.5)
	_s = clampf(_s + _sv * delta, -0.4, 0.4)
	var side := 1.0 / sqrt(1.0 + _s)
	_root.scale = _base_scale * Vector3(side, 1.0 + _s, side)


func _poke(request: Dictionary) -> Dictionary:
	var k = request.get("strength", 0.4)
	if typeof(k) != TYPE_FLOAT and typeof(k) != TYPE_INT:
		return {"ok": false, "error": "strength must be a number"}
	if k < 0.1 or k > 1.0:
		return {"ok": false, "error": "strength must be 0.1 to 1"}
	_sv -= float(k) * 6.0
	return {"ok": true}


func _set(request: Dictionary) -> Dictionary:
	var s = request.get("stiffness", stiffness)
	var d = request.get("damping", damping)
	for v in [s, d]:
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return {"ok": false, "error": "stiffness and damping must be numbers"}
	if s < 20 or s > 400:
		return {"ok": false, "error": "stiffness must be 20 to 400"}
	if d < 1 or d > 30:
		return {"ok": false, "error": "damping must be 1 to 30"}
	stiffness = float(s)
	damping = float(d)
	return {"ok": true, "stiffness": stiffness, "damping": damping}


func _exit_tree() -> void:
	if _root != null and is_instance_valid(_root):
		_root.scale = _base_scale
