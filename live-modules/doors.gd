extends SlopitectModule

# Hinged doors. doors_add turns shapes (a door and its handle) into a door
# that swings round a hinge line: vertical by default, or along x or z (like
# an oven door that drops down). Put a hand near a door and press A (right)
# or Y (left) to open or close it. Kept per project in saves/doors.json;
# doors load closed.
# A and Y come through controls.gd like every button. They also show the
# terminal and chat windows (vrui.gd), so this module is asked first, and
# takes the press only when that hand is near a door.
# It runs only while a door is swinging. The file is the open world's
# (lib.world_file), loaded again when another project opens.

const REACH := 0.15  # m from the door that counts as "near"
const SPEED := 2.0  # opens in half a second
const AXES := {"y": Vector3.UP, "x": Vector3.RIGHT, "z": Vector3.BACK}

var _doors := {}  # id -> {parts, pivot Vector3, axis String, angle deg, rest {name: Transform3D}, open bool, t float}
var _file := ""  # "" until lib is there
var _lib: SlopitectModule


func setup() -> String:
	set_process(false)
	register("doors_add", _add_command, "make a hinged door: name (an id), parts [shape names, door first], hinge [x, z] (a vertical hinge line) or [x, y, z] (a point on it), optional axis (y default, or x or z for a horizontal hinge, like an oven door), angle (degrees it opens, right-hand rule round the axis: for y + is anticlockwise seen from above; for x + tips the top toward +z; default 100). Records the parts as closed now")
	register("doors_toggle", _toggle_command, "open or close a door: name, optional open (true/false)")
	register("doors_remove", _remove_command, "stop a door being a door (it closes first): name")
	register("doors_status", _status_command, "the doors and whether they're open")
	return ""


func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		_file = ""
		return
	lib.watch(self, "save", _world_changed)
	lib.follow(self, "projects", "project_changed", _world_changed)
	_world_changed()


func _world_changed(_a = null, _b = null) -> void:
	var now: String = _lib.world_file("doors.json")
	if now != _file:
		_file = now
		_load()


func _find(node_name) -> Node3D:
	return _lib.world_node(node_name) if _lib else null


func _load() -> void:
	_doors.clear()
	_read(_lib.read_json(_file))


func _read(data) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	for id in data:
		var d = data[id]
		if typeof(d) != TYPE_DICTIONARY or typeof(d.get("parts")) != TYPE_ARRAY or typeof(d.get("rest")) != TYPE_DICTIONARY:
			continue
		var rest := {}
		for n in d["rest"]:
			var t = str_to_var(String(d["rest"][n]))
			if t is Transform3D:
				rest[n] = t
		var pv = d.get("pivot", [0, 0, 0])
		var axis := String(d.get("axis", "y"))
		if not AXES.has(axis):
			axis = "y"
		_doors[id] = {"parts": d["parts"], "pivot": Vector3(float(pv[0]), float(pv[1]), float(pv[2])), "axis": axis, "angle": float(d.get("angle", 100.0)), "rest": rest, "open": false, "t": 0.0}
	_place_all.call_deferred()  # doors load closed, once their parts are back


func _place_all() -> void:
	for id in _doors:
		_place(_doors[id])


func _save() -> void:
	if _file.is_empty():
		return  # no lib yet
	DirAccess.make_dir_recursive_absolute(_file.get_base_dir())
	var problem: String = _lib.write_json(_file, _written(), "\t")
	if not problem.is_empty():
		push_error("Slopitect doors: " + problem)


func _written() -> Dictionary:
	var out := {}
	for id in _doors:
		var d: Dictionary = _doors[id]
		var rest := {}
		for n in d["rest"]:
			rest[n] = var_to_str(d["rest"][n])
		var p: Vector3 = d["pivot"]
		out[id] = {"parts": d["parts"], "pivot": [p.x, p.y, p.z], "axis": d["axis"], "angle": d["angle"], "rest": rest}
	return out


# A door (closed), or none (null): it closes before it goes.
func _put_door(id: String, d) -> void:
	if _doors.has(id):
		_doors[id]["t"] = 0.0
		_place(_doors[id])
		_doors.erase(id)
	if d != null:
		_doors[id] = (d as Dictionary).duplicate(true)
		_doors[id]["open"] = false
		_doors[id]["t"] = 0.0
		_place(_doors[id])
	_save()


func _undo(label: String, id: String, before, after) -> void:
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		tools.call("push_undo", label, _put_door.bind(id, before), _put_door.bind(id, after))


# --- For the save module, and for undoing a delete (tools.gd) ----------------------------

func get_doors() -> Dictionary:
	return _written()


func set_doors(data) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	for id in _doors.keys():
		_put_door(id, null)
	_read(data)
	_save()


func thing_state(node_name: String) -> Dictionary:
	var found := {}
	for id in _doors:
		if node_name in _doors[id]["parts"]:
			found[id] = _doors[id].duplicate(true)
	return {"doors": found} if not found.is_empty() else {}


func thing_forget(node_name: String) -> void:
	for id in _doors.keys():
		if node_name in _doors[id]["parts"]:
			_put_door(id, null)


func thing_restore(_node_name: String, state: Dictionary) -> void:
	var doors = state.get("doors", {})
	for id in doors:
		if not _doors.has(id):
			_put_door(id, doors[id])


func _place(d: Dictionary) -> void:
	var a := deg_to_rad(float(d["angle"]) * float(d["t"]))
	var rot := Basis(AXES[d["axis"]], a)
	var pivot: Vector3 = d["pivot"]
	for n in d["parts"]:
		var node := _find(n)
		if node == null or not d["rest"].has(n):
			continue
		var r: Transform3D = d["rest"][n]
		node.global_transform = Transform3D(rot * r.basis, pivot + rot * (r.origin - pivot))


func _process(delta: float) -> void:
	var swinging := false
	for id in _doors:
		var d: Dictionary = _doors[id]
		var goal := 1.0 if d["open"] else 0.0
		if is_equal_approx(float(d["t"]), goal):
			continue
		d["t"] = move_toward(float(d["t"]), goal, delta * SPEED)
		_place(d)
		swinging = true
	set_process(swinging)


func _distance(node: Node3D, at: Vector3) -> float:
	var vi := node as VisualInstance3D
	if vi == null:
		return node.global_position.distance_to(at)
	var box := vi.get_aabb()
	var xf := node.global_transform
	var local := xf.affine_inverse() * at
	var s := xf.basis.get_scale()
	var c := box.get_center()
	var h := box.size * 0.5
	var dx := maxf(0.0, absf(local.x - c.x) - h.x) * s.x
	var dy := maxf(0.0, absf(local.y - c.y) - h.y) * s.y
	var dz := maxf(0.0, absf(local.z - c.z) - h.z) * s.z
	return Vector3(dx, dy, dz).length()


func _nearest(at: Vector3) -> String:
	var best := ""
	var best_d := REACH
	for id in _doors:
		for n in _doors[id]["parts"]:
			var node := _find(n)
			if node == null:
				continue
			var dist := _distance(node, at)
			if dist <= best_d:
				best_d = dist
				best = id
	return best


# Before vrui.gd (0), whose window toggles are on A and Y too.
func action_order() -> int:
	return -5


func on_action(action: String, down: bool) -> bool:
	var hand: Node3D = null
	if action == "right_a":
		hand = ctx.get("right")
	elif action == "left_y":
		hand = ctx.get("left")
	if hand == null:
		return false
	var id := _nearest(hand.global_position)
	if id == "":
		return false
	if down:
		_doors[id]["open"] = not _doors[id]["open"]
		set_process(true)
	return true


func _add_command(request: Dictionary) -> Dictionary:
	var id = request.get("name")
	if typeof(id) != TYPE_STRING or id.is_empty():
		return {"ok": false, "error": "\"name\" must be a door id"}
	var parts = request.get("parts")
	if typeof(parts) != TYPE_ARRAY or parts.is_empty():
		return {"ok": false, "error": "\"parts\" must be a list of shape names"}
	var rest := {}
	for n in parts:
		var node := _find(n)
		if node == null:
			return {"ok": false, "error": "no shape named %s" % JSON.stringify(n)}
		rest[n] = node.global_transform
	var hinge = request.get("hinge")
	if typeof(hinge) != TYPE_ARRAY or not hinge.size() in [2, 3]:
		return {"ok": false, "error": "\"hinge\" must be [x, z] or [x, y, z]"}
	for v in hinge:
		if not typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			return {"ok": false, "error": "\"hinge\" must be numbers"}
	var pivot := Vector3(float(hinge[0]), 0, float(hinge[1]))
	if hinge.size() == 3:
		pivot = Vector3(float(hinge[0]), float(hinge[1]), float(hinge[2]))
	var axis = request.get("axis", "y")
	if typeof(axis) != TYPE_STRING or not AXES.has(axis):
		return {"ok": false, "error": "\"axis\" must be \"y\", \"x\" or \"z\""}
	if axis != "y" and hinge.size() != 3:
		return {"ok": false, "error": "a horizontal hinge needs \"hinge\" as [x, y, z]"}
	var angle = request.get("angle", 100.0)
	if not typeof(angle) in [TYPE_INT, TYPE_FLOAT] or absf(angle) > 180:
		return {"ok": false, "error": "\"angle\" must be -180 to 180"}
	var before = _doors[id].duplicate(true) if _doors.has(id) else null
	var door := {"parts": parts, "pivot": pivot, "axis": axis, "angle": float(angle), "rest": rest, "open": false, "t": 0.0}
	_put_door(id, door)
	_undo("door " + id, id, before, door.duplicate(true))
	return {"ok": true, "door": id}


func _toggle_command(request: Dictionary) -> Dictionary:
	var id = request.get("name")
	if typeof(id) != TYPE_STRING or not _doors.has(id):
		return {"ok": false, "error": "no door named %s (doors_status lists them)" % JSON.stringify(id)}
	var want = request.get("open", not _doors[id]["open"])
	if typeof(want) != TYPE_BOOL:
		return {"ok": false, "error": "\"open\" must be true or false"}
	_doors[id]["open"] = want
	set_process(true)
	return {"ok": true, "door": id, "open": want}


func _remove_command(request: Dictionary) -> Dictionary:
	var id = request.get("name")
	if typeof(id) != TYPE_STRING or not _doors.has(id):
		return {"ok": false, "error": "no door named %s" % JSON.stringify(id)}
	var before: Dictionary = _doors[id].duplicate(true)
	_put_door(id, null)
	_undo("remove door " + id, id, before, null)
	return {"ok": true}


func _status_command(_request: Dictionary) -> Dictionary:
	var out := {}
	for id in _doors:
		var d: Dictionary = _doors[id]
		var p: Vector3 = d["pivot"]
		out[id] = {"parts": d["parts"], "open": d["open"], "axis": d["axis"], "angle": d["angle"], "hinge": [p.x, p.y, p.z] if d["axis"] != "y" else [p.x, p.z]}
	return {"ok": true, "doors": out}
