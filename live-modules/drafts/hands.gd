extends SlopitectModule

# Smooth hands with coloured nails on both controllers.
# Fingers curl with grip, index with trigger, thumb when it touches the buttons.
# Each hand has its own nail colours.
# Hides the small box models (and old hand leftovers) on the controllers; shows them again on unload.

const FINGER_LEN: Array = [0.072, 0.08, 0.075, 0.06]
const FINGER_R: Array = [0.0095, 0.0095, 0.009, 0.008]
const SPLIT: Array = [0.45, 0.3, 0.25]
const CURL: Array = [75.0, 95.0, 70.0]

var _hands: Array = []
var _skin: StandardMaterial3D
var _nails: Dictionary = {}  # "left"/"right" -> Array of 5 materials
var _hidden: Array = []
var _rescan: float = 1.0


func setup() -> String:
	if ctx.get("left") == null or ctx.get("right") == null:
		return "controllers not found"
	_skin = StandardMaterial3D.new()
	_skin.albedo_color = Color("e0ac80")
	_skin.roughness = 0.75
	for side_name in ["left", "right"]:
		var arr: Array = []
		for i in range(5):
			var m := StandardMaterial3D.new()
			m.albedo_color = Color("ff3b7a")
			m.roughness = 0.2
			m.metallic_specular = 0.9
			arr.append(m)
		_nails[side_name] = arr
	_hands.append(_make_hand(ctx["left"], 1.0, _nails["left"]))
	_hands.append(_make_hand(ctx["right"], -1.0, _nails["right"]))
	_hide_blocks()
	register("hands_color", _color, "set the hands' skin colour: color (#rrggbb)")
	register("hands_nails", _nails_cmd, "set nail colour: color (#rrggbb) for all, or colors [5 x #rrggbb] thumb to pinky; optional hand (left, right, both; default both)")
	set_process(true)
	return ""


func _hide_blocks() -> void:
	for side in ["left", "right"]:
		var ctrl: Node = ctx[side]
		if is_instance_valid(ctrl):
			_hide_in(ctrl)


func _hide_in(n: Node) -> void:
	for c in n.get_children():
		if c.name == "smooth_hand":
			continue
		if c is Node3D and c.name == "human_hand" and (c as Node3D).visible:
			(c as Node3D).visible = false
			_hidden.append(c)
			continue
		if c is MeshInstance3D and (c as MeshInstance3D).visible:
			var mi := c as MeshInstance3D
			if mi.mesh is BoxMesh:
				var s: Vector3 = (mi.mesh as BoxMesh).size * mi.scale.abs()
				if maxf(s.x, maxf(s.y, s.z)) < 0.2:
					mi.visible = false
					_hidden.append(mi)
		_hide_in(c)


func _seg(r: float, seg_len: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = seg_len + 2.0 * r
	c.radial_segments = 12
	c.rings = 3
	m.mesh = c
	m.material_override = _skin
	m.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	m.position = Vector3(0.0, 0.0, -seg_len / 2.0)
	return m


func _blob(size: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 16
	s.rings = 8
	m.mesh = s
	m.scale = size
	m.material_override = mat
	return m


func _chain(parent: Node3D, r: float, total: float, nail_mat: Material) -> Array:
	var pivots: Array = []
	var p: Node3D = parent
	for j in range(3):
		var seg_len: float = total * float(SPLIT[j])
		var piv := Node3D.new()
		if j > 0:
			piv.position = Vector3(0.0, 0.0, -total * float(SPLIT[j - 1]))
		p.add_child(piv)
		piv.add_child(_seg(r * (1.0 - 0.08 * j), seg_len))
		pivots.append(piv)
		p = piv
	var tip_len: float = total * float(SPLIT[2])
	var nail := _blob(Vector3(r * 1.7, r * 0.6, tip_len * 0.75), nail_mat)
	nail.position = Vector3(0.0, r * 0.75, -tip_len * 0.6)
	p.add_child(nail)
	return pivots


func _make_hand(ctrl: Node3D, side: float, nails: Array) -> Dictionary:
	var hand := Node3D.new()
	hand.name = "smooth_hand"
	var palm := _blob(Vector3(0.082, 0.03, 0.095), _skin)
	palm.position = Vector3(0.0, 0.0, 0.02)
	hand.add_child(palm)
	var wrist := _blob(Vector3(0.06, 0.028, 0.06), _skin)
	wrist.position = Vector3(0.0, -0.002, 0.07)
	hand.add_child(wrist)
	var fingers: Array = []
	for i in range(4):
		var base := Node3D.new()
		base.position = Vector3(side * (0.0285 - 0.019 * i), 0.002, -0.022)
		base.rotation_degrees = Vector3(0.0, side * (-3.0 + 3.0 * i), 0.0)
		hand.add_child(base)
		fingers.append(_chain(base, float(FINGER_R[i]), float(FINGER_LEN[i]), nails[i + 1]))
	var tbase := Node3D.new()
	tbase.position = Vector3(side * 0.038, -0.01, 0.025)
	tbase.rotation_degrees = Vector3(0.0, -45.0 * side, 0.0)
	hand.add_child(tbase)
	var thumb: Array = _chain(tbase, 0.0115, 0.065, nails[0])
	ctrl.add_child(hand)
	return {"node": hand, "ctrl": ctrl, "side": side, "fingers": fingers, "thumb": thumb, "tbase": tbase, "curl": [0.0, 0.0, 0.0, 0.0, 0.0]}


func _f(ctrl: Node, action: String) -> float:
	if ctrl.has_method("get_float"):
		return float(ctrl.call("get_float", action))
	return 0.0


func _b(ctrl: Node, action: String) -> bool:
	if ctrl.has_method("is_button_pressed"):
		return bool(ctrl.call("is_button_pressed", action))
	return false


func _process(delta: float) -> void:
	if _rescan > 0.0:
		_rescan -= delta
		if _rescan <= 0.0:
			_hide_blocks()
	var k: float = clampf(delta * 18.0, 0.0, 1.0)
	for h in _hands:
		var ctrl = h["ctrl"]
		if not is_instance_valid(ctrl):
			continue
		var grip: float = _f(ctrl, "grip")
		var trig: float = _f(ctrl, "trigger")
		var ttouch: bool = _b(ctrl, "ax_touch") or _b(ctrl, "by_touch") or _b(ctrl, "primary_touch") or _b(ctrl, "ax_button") or _b(ctrl, "by_button")
		var itouch: bool = _b(ctrl, "trigger_touch")
		var thumb_t: float = maxf(0.75 if ttouch else 0.0, grip * 0.6)
		var index_t: float = maxf(trig, 0.25 if itouch else 0.0)
		var targets: Array = [thumb_t, index_t, grip, grip, grip]
		var curl: Array = h["curl"]
		for i in range(5):
			curl[i] = lerpf(float(curl[i]), float(targets[i]), k)
		var fingers: Array = h["fingers"]
		for i in range(4):
			var c: float = float(curl[i + 1])
			var piv: Array = fingers[i]
			for j in range(3):
				(piv[j] as Node3D).rotation.x = -deg_to_rad(float(CURL[j])) * c
		var tc: float = float(curl[0])
		var side: float = float(h["side"])
		(h["tbase"] as Node3D).rotation_degrees = Vector3(-20.0 * tc, side * (-45.0 + 45.0 * tc), 0.0)
		var thumb: Array = h["thumb"]
		(thumb[1] as Node3D).rotation.x = -deg_to_rad(30.0) * tc
		(thumb[2] as Node3D).rotation.x = -deg_to_rad(45.0) * tc


func _color(request: Dictionary) -> Dictionary:
	var c = request.get("color")
	if typeof(c) != TYPE_STRING or not Color.html_is_valid(c):
		return {"ok": false, "error": "color must be #rrggbb"}
	_skin.albedo_color = Color.html(c)
	return {"ok": true}


func _nails_cmd(request: Dictionary) -> Dictionary:
	var which = request.get("hand", "both")
	var sides: Array = []
	if which == "left" or which == "right":
		sides = [which]
	elif which == "both":
		sides = ["left", "right"]
	else:
		return {"ok": false, "error": "hand must be left, right or both"}
	var cols = request.get("colors")
	if cols != null:
		if typeof(cols) != TYPE_ARRAY or cols.size() < 1 or cols.size() > 5:
			return {"ok": false, "error": "colors must be 1 to 5 #rrggbb, thumb to pinky"}
		for c in cols:
			if typeof(c) != TYPE_STRING or not Color.html_is_valid(c):
				return {"ok": false, "error": "bad colour: " + str(c)}
		for s in sides:
			for i in range(cols.size()):
				(_nails[s][i] as StandardMaterial3D).albedo_color = Color.html(cols[i])
		return {"ok": true}
	var col = request.get("color")
	if typeof(col) != TYPE_STRING or not Color.html_is_valid(col):
		return {"ok": false, "error": "give color (#rrggbb) or colors [..]"}
	for s in sides:
		for m in _nails[s]:
			(m as StandardMaterial3D).albedo_color = Color.html(col)
	return {"ok": true}


func _exit_tree() -> void:
	for n in _hidden:
		if is_instance_valid(n):
			(n as Node3D).visible = true
	_hidden.clear()
	for h in _hands:
		if is_instance_valid(h["node"]):
			h["node"].queue_free()
	_hands.clear()
