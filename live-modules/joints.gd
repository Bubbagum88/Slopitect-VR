extends SlopitectModule

# Slopitect live module: joints.
# Joins two things so one moves on the other: a hinge (doors, lids, wheels),
# a slider (drawers), a ball joint, or a fixed joint (glued on). A thing is
# anything in the world by its name: a shape, a placed model, whatever the
# shapes module makes; a part can also be joined to the world itself.
# Attach points are named spots on a thing's surface (where it joins), kept
# in the thing's own space so they move and scale with it. The ones added
# here are kept here; with the shapes module loaded, its shapes also bring
# the points it works out from their geometry (top, end, ...).
#
# Each joint has a base (a, or "" for the world) and a part that moves (b).
# The pivot and axis are fixed to the base. A hinge turns b round the axis,
# a slider moves it along the axis, a ball joint turns it any way about the
# pivot. Angles and distances count from where b was when it was joined.
#
# How b moves:
#  - b dynamic (physics.gd): the engine's own joint (Jolt), so it swings,
#    falls and collides. The base is its physics body, or a body that
#    follows it.
#  - otherwise b follows the base: carry the base and b comes with it; grab
#    b (or move it with a command) and it slides or turns only the way the
#    joint lets it. A motor turns or slides it by itself.
#  - b held in a hand (grab.gd): the same as following, for dynamic b too.
#
# The tool (Tools menu, the Joints tile, or the hand menu): Connect: pull
# the trigger on the part that stays, then on the part that moves; with
# Snap on, the second part is moved so the two spots touch. Add point:
# the trigger puts an attach point where you point; Connect snaps to it
# when you point near it. Remove: the trigger takes a thing's joints off
# (or an attach point, pointed at). Every change is one undo.
# Joints and points are kept with the world (save.gd).
# It runs each physics frame only while there are joints, and draws its
# marks only while they're shown (Show: always, or tool while chosen).

const TYPES := ["hinge", "slider", "ball", "fixed"]
const AXES := ["normal", "up", "side"]  # the tool's axis: out of the surface, straight up, along the surface level
const SHOW := ["tool", "always", "never"]
const MODES := ["connect", "point", "remove"]
const PREFS_PATH := "user://joints.json"
const REACH := 20.0  # metres the pointer reaches
const POINT_SNAP := 0.06  # pointing this close to an attach point uses it
const MAX_HINGE := 360.0  # degrees either way
const MAX_SLIDE := 10.0  # metres either way
const MAX_TURN_SPEED := 720.0  # degrees a second
const MAX_SLIDE_SPEED := 5.0  # metres a second
const MOTOR_IMPULSE := 50.0  # how hard an engine motor may push
const RADIAL := 0.02  # b's centre this close to a hinge's axis: turned by its own turn, not by where it is

var _joints: Array = []  # [{id, type, a, b, frame, rest, value, turn, lower, upper, motor}], parents first
var _live := {}  # joint id -> {"written": Transform3D, "joint": Joint3D, "proxy": StaticBody3D, "key": Array}
var _points := {}  # thing name -> {point id -> {"position": Vector3, "normal": Vector3}} in the thing's own space
var _next := 1
var _prefs := {"show": "tool", "snap": true}
var _mode := "connect"
var _type := "hinge"
var _axis := "normal"
var _first := {}  # the connect tool's first pick: {name, position, normal, point}
var _chosen := false
var _marks: MeshInstance3D
var _triangles := {}  # mesh instance id -> TriangleMesh, for pointing
var _lib: SlopitectModule
var _physics: SlopitectModule


func setup() -> String:
	set_process(false)
	set_physics_process(false)
	process_physics_priority = 10  # after grab.gd and physics.gd have moved things this frame
	_marks = MeshInstance3D.new()
	_marks.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_marks.material_override = material
	_marks.top_level = true
	add_child(_marks)
	register("joints_add", _add_command, "join two things: b (the part that moves), optional a (the part that stays; \"\" or left out: the world), type (hinge, slider, ball, fixed; default hinge), at [x, y, z] (the pivot; default a's point_a, else b's centre), axis [x, y, z] (default point_a's normal, else up), point_a / point_b (attach point ids), snap (move b so point_b touches the pivot; default on with point_b), lower / upper (hinge degrees, slider metres, from where b is now), motor (degrees or metres a second). One undo")
	register("joints_remove", _remove_command, "take joints off: id, or name (every joint of that thing). One undo")
	register("joints_set", _set_command, "change a joint: id, any of value (hinge degrees, slider metres: moves b there), motor (a second; 0 stops), lower, upper (null for no limit)")
	register("joints_list", _list_command, "every joint: id, type, a, b, value, limits, motor, pivot and axis, and how it moves (engine, follows, or waiting for a thing)")
	register("joints_point_add", _point_add_command, "an attach point on a thing: name, optional id, and position [x, y, z] (world) or face (top, bottom, left, right, front, back: its middle), optional normal [x, y, z]. One undo")
	register("joints_point_remove", _point_remove_command, "remove an attach point: name, id. One undo")
	register("joints_points", _points_command, "attach points, in world space: optional name (one thing)")
	register("joints_tool", _tool_command, "the Joints tool: any of mode (connect, point, remove), type, axis (normal, up, side), snap (true/false), act (open: show its menu or put it away; cancel: forget the first pick; world: join the first pick to the world)")
	register("joints_prefs", _prefs_command, "comfort: show (tool: marks while the tool is chosen, always, never), snap (true/false: the tool moves the second part onto the first)")
	return ""


# --- Hooks -------------------------------------------------------------------------

func menu_info() -> Dictionary:
	return {"id": "joints", "label": "Joints", "order": 40, "action": {"cmd": "joints_tool", "act": "open"}}


func hand_info() -> Dictionary:
	return {"id": "joints", "label": "Joints", "order": 40, "action": {"cmd": "joints_tool", "act": "open"}}


func settings_info() -> Dictionary:
	return {"title": "Joints", "order": 40, "settings": [
		{"id": "show", "type": "choice", "label": "Show joints and attach points", "value": _prefs["show"], "set": {"cmd": "joints_prefs", "show": "{value}"},
			"options": [{"label": "With the tool", "value": "tool"}, {"label": "Always", "value": "always"}, {"label": "Never", "value": "never"}]},
		{"id": "snap", "type": "toggle", "label": "Snap parts together", "value": _prefs["snap"], "set": {"cmd": "joints_prefs", "snap": "{value}"}},
	]}


func tool_info() -> Dictionary:
	var buttons := []
	for mode in [["connect", "Connect"], ["point", "Add point"], ["remove", "Remove"]]:
		buttons.append({"label": ("> " if _mode == mode[0] else "") + mode[1], "action": {"cmd": "joints_tool", "mode": mode[0]}})
	if _mode == "connect":
		for type in TYPES:
			buttons.append({"label": ("> " if _type == type else "") + type.capitalize(), "action": {"cmd": "joints_tool", "type": type}})
		var next_axis: String = AXES[(AXES.find(_axis) + 1) % AXES.size()]
		buttons.append({"label": "Axis: " + _axis, "action": {"cmd": "joints_tool", "axis": next_axis}})
		buttons.append({"label": "Snap: " + ("on" if _prefs["snap"] else "off"), "action": {"cmd": "joints_tool", "snap": not _prefs["snap"]}})
		if not _first.is_empty():
			buttons.append({"label": "Join to world", "action": {"cmd": "joints_tool", "act": "world"}})
			buttons.append({"label": "Cancel", "action": {"cmd": "joints_tool", "act": "cancel"}})
	return {"id": "joints", "label": "Joints", "order": 30, "buttons": buttons, "status": _line()}


func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		_physics = null
		return
	_load_prefs()
	lib.watch(self, "physics", _physics_here, _physics_gone)
	_update_running()


func _physics_here(physics: SlopitectModule) -> void:
	_physics = physics if physics.has_method("body") else null


func _physics_gone(_old) -> void:
	_physics = null


# Joints to keep: each physics frame. Marks to show: each frame.
func _update_running() -> void:
	set_physics_process(not _joints.is_empty())
	var marks: bool = _prefs["show"] == "always" or (_prefs["show"] == "tool" and _chosen)
	set_process(marks)
	if not marks:
		(_marks.mesh as ImmediateMesh).clear_surfaces()
		_marks.visible = false


func tool_selected(on: bool) -> void:
	_chosen = on
	if not on:
		_first = {}
	_update_running()


func tool_trigger(down: bool) -> void:
	if not down:
		return
	var hit := _pick()
	if hit.is_empty():
		return
	(ctx["right"] as XRController3D).trigger_haptic_pulse("haptic", 0.0, 0.3, 0.05, 0.0)
	match _mode:
		"point":
			_add_point(hit["name"], "", _find(hit["name"]), hit["position"], hit["normal"])
		"remove":
			if not hit["point"].is_empty():
				_point_remove_command({"name": hit["name"], "id": hit["point"]})
			else:
				_remove_command({"name": hit["name"]})
		"connect":
			if _first.is_empty():
				_first = hit
			elif hit["name"] != _first["name"]:
				var spec := {"type": _type, "a": _first["name"], "b": hit["name"], "at": _first["position"], "axis": _tool_axis(_first["normal"])}
				if _prefs["snap"]:
					spec["snap"] = {"from": hit["position"], "normal": hit["normal"], "to_normal": -(_first["normal"] as Vector3)}
				var reply := _join(spec)
				if not reply.get("ok", false):
					push_error("Slopitect joints: " + str(reply.get("error")))
				_first = {}


func _line() -> String:
	match _mode:
		"point":
			return "Point at a surface and pull the trigger to add an attach point"
		"remove":
			return "Pull the trigger on a thing to take its joints off, or on an attach point"
	if _first.is_empty():
		return "%s: pull the trigger on the part that stays" % _type.capitalize()
	return "%s on %s: now the part that moves (or Join to world)" % [_type.capitalize(), _first["name"]]


func _tool_axis(normal: Vector3) -> Vector3:
	match _axis:
		"up":
			return Vector3.UP
		"side":
			var side := Vector3.UP.cross(normal)
			return side.normalized() if side.length() > 0.1 else Vector3.RIGHT
	return normal


func _tool_command(request: Dictionary) -> Dictionary:
	if request.has("mode"):
		if not request["mode"] in MODES:
			return {"ok": false, "error": "\"mode\" must be one of %s" % [MODES]}
		_mode = request["mode"]
		_first = {}
	if request.has("type"):
		if not request["type"] in TYPES:
			return {"ok": false, "error": "\"type\" must be one of %s" % [TYPES]}
		_type = request["type"]
	if request.has("axis"):
		if not request["axis"] in AXES:
			return {"ok": false, "error": "\"axis\" must be one of %s" % [AXES]}
		_axis = request["axis"]
	if request.has("snap"):
		var got := _prefs_command({"snap": request["snap"]})
		if not got.get("ok", false):
			return got
	match request.get("act", ""):
		"", null:
			pass
		"cancel":
			_first = {}
		"world":
			if _first.is_empty():
				return {"ok": false, "error": "pick a part with the trigger first"}
			var reply := _join({"type": _type, "a": "", "b": _first["name"], "at": _first["position"], "axis": _tool_axis(_first["normal"])})
			_first = {}
			if not reply.get("ok", false):
				return reply
		"open":
			_open()
		_:
			return {"ok": false, "error": "\"act\" must be open, cancel or world"}
	if _lib:
		_lib.touch(self)  # its tool buttons show these
	return {"ok": true, "mode": _mode, "type": _type, "axis": _axis, "snap": _prefs["snap"], "first": _first.get("name", ""), "line": _line()}


# Chooses the tool and shows its menu (tools.gd's), or puts it away.
func _open() -> void:
	var panel := "tools_t_joints"
	var shown: bool = ctx["server"].run({"cmd": "ui_get", "id_panel": panel}).get("panel", {}).get("visible", false)
	if _chosen and shown:
		ctx["server"].run({"cmd": "ui_show", "id_panel": panel, "visible": false})
		return
	var chose: Dictionary = ctx["server"].run({"cmd": "tools_select", "tool": "joints"})
	if not chose.get("ok", false):
		push_error("Slopitect joints: the Joints tool needs tools.gd: %s" % chose.get("error"))
		return
	ctx["server"].run({"cmd": "ui_show", "id_panel": panel, "visible": true})


# --- Things ------------------------------------------------------------------------

# Anything built in the world: the World node's children, and the placed
# models under World/PolyHaven.
func _things() -> Array:
	var found := []
	for child in (ctx["world"] as Node3D).get_children():
		if child.name == "PolyHaven":
			for model in child.get_children():
				if model is Node3D:
					found.append(model)
		elif child is Node3D:
			found.append(child)
	return found


func _find(node_name) -> Node3D:
	return _lib.world_node(node_name) if _lib else null


# Where a thing is and how it's turned, without its size.
func _pose(node: Node3D) -> Transform3D:
	return Transform3D(node.global_basis.orthonormalized(), node.global_position)


func _body(node: Node3D) -> RigidBody3D:
	return _physics.call("body", node) if is_instance_valid(_physics) else null


# What the right controller points at: {name, position, normal, point} on a
# thing's real surface, snapped to an attach point near it; {} for nothing.
func _pick() -> Dictionary:
	var hand: Node3D = ctx["right"]
	var from := hand.global_position
	var direction := -hand.global_basis.z.normalized()
	var best := {}
	var best_distance := REACH
	for thing: Node3D in _things():
		if not thing.is_visible_in_tree():
			continue
		var meshes: Array = [thing] if thing is MeshInstance3D else []
		meshes.append_array(thing.find_children("*", "MeshInstance3D", true, false))
		for mesh: MeshInstance3D in meshes:
			if mesh.mesh == null or not mesh.is_visible_in_tree():
				continue
			var key := mesh.mesh.get_instance_id()
			if not _triangles.has(key):
				_triangles[key] = mesh.mesh.generate_triangle_mesh()
			var triangles: TriangleMesh = _triangles[key]
			if triangles == null:
				continue
			var to_local := mesh.global_transform.affine_inverse()
			var hit := triangles.intersect_ray(to_local * from, (to_local.basis * direction).normalized())
			if hit.is_empty():
				continue
			var at: Vector3 = mesh.global_transform * hit["position"]
			var distance := from.distance_to(at)
			if distance < best_distance:
				var normal: Vector3 = (mesh.global_basis.inverse().transposed() * hit["normal"]).normalized()
				if normal.dot(direction) > 0.0:
					normal = -normal  # the inside of a face
				best_distance = distance
				best = {"name": String(thing.name), "position": at, "normal": normal, "point": ""}
	if best.is_empty():
		return best
	var node := _find(best["name"])
	var points := _points_of(best["name"])
	for id in points:
		var point := _point_world(node, points[id])
		if point["position"].distance_to(best["position"]) <= POINT_SNAP:
			best.merge({"position": point["position"], "normal": point["normal"], "point": id}, true)
			break
	return best


# --- Joints ------------------------------------------------------------------------

# A frame whose z is the axis.
func _frame_at(at: Vector3, axis: Vector3) -> Transform3D:
	var up := Vector3.UP if absf(axis.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(-axis, up), at)


# The joint's frame in the world now (null when its base is missing).
func _world_frame(joint: Dictionary):
	if joint["a"].is_empty():
		return joint["frame"]
	var a := _find(joint["a"])
	return _pose(a) * joint["frame"] if a else null


func _move_of(joint: Dictionary) -> Transform3D:
	match joint["type"]:
		"hinge":
			return Transform3D(Basis(Vector3.BACK, joint["value"]), Vector3.ZERO)
		"slider":
			return Transform3D(Basis(), Vector3(0, 0, joint["value"]))
		"ball":
			return Transform3D(Basis(joint["turn"] as Quaternion), Vector3.ZERO)
	return Transform3D()


# How far b is turned or slid now, from where it is: [value, turn].
func _measure(joint: Dictionary, frame: Transform3D, b_pose: Transform3D) -> Array:
	var inverse := frame.affine_inverse()
	var at := inverse * b_pose.origin
	var rest: Vector3 = joint["rest"].origin
	var own := (inverse * b_pose * (joint["rest"] as Transform3D).affine_inverse()).basis.get_rotation_quaternion()
	match joint["type"]:
		"hinge":
			var angle: float
			if Vector2(rest.x, rest.y).length() > RADIAL and Vector2(at.x, at.y).length() > RADIAL / 4.0:
				angle = Vector2(rest.x, rest.y).angle_to(Vector2(at.x, at.y))
			else:
				angle = 2.0 * atan2(own.z, own.w)  # its own twist round the axis
			# The nearest turn to the last, so a wheel's angle keeps counting.
			return [joint["value"] + wrapf(angle - joint["value"], -PI, PI), joint["turn"]]
		"slider":
			return [at.z - rest.z, joint["turn"]]
		"ball":
			if rest.length() > RADIAL and at.length() > RADIAL / 4.0:
				return [0.0, Quaternion(rest.normalized(), at.normalized())]
			return [0.0, own]
	return [0.0, joint["turn"]]


func _clamp(joint: Dictionary, value: float) -> float:
	if joint["lower"] != null:
		value = maxf(value, joint["lower"])
	if joint["upper"] != null:
		value = minf(value, joint["upper"])
	return value


func _physics_process(delta: float) -> void:
	for joint in _joints:
		var live: Dictionary = _live[joint["id"]]
		var frame = _world_frame(joint)
		var b := _find(joint["b"])
		if frame == null or b == null or not b.is_inside_tree():
			_drop_engine(live)  # waits for the thing to come back
			continue
		var body := _body(b)
		var held := body != null and body.freeze and body.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC
		if body != null and (not body.freeze or held):
			_engine_joint(joint, live, frame, body)
			if live.has("proxy") and is_instance_valid(live["proxy"]) and not joint["a"].is_empty():
				# A base without physics was carried or moved: b comes along
				# as it is, rather than being yanked after it by the joint.
				var proxy: Node3D = live["proxy"]
				var base_pose := _pose(_find(joint["a"]))
				if not base_pose.is_equal_approx(proxy.global_transform):
					var carry := base_pose * proxy.global_transform.affine_inverse()
					proxy.global_transform = base_pose
					if not held:
						body.global_transform = carry * body.global_transform
						body.linear_velocity = carry.basis * body.linear_velocity
						body.angular_velocity = carry.basis * body.angular_velocity
			if not held:
				continue  # the engine moves it
		else:
			_drop_engine(live)
		# b follows the base: moved by a hand or a command, it keeps only
		# what the joint allows; otherwise the motor moves it.
		if joint["type"] != "fixed":
			if held or not b.global_transform.is_equal_approx(live.get("written", Transform3D())):
				var measured := _measure(joint, frame, _pose(b))
				joint["value"] = measured[0]
				joint["turn"] = measured[1]
			elif joint["motor"] != 0.0:
				joint["value"] += joint["motor"] * delta
			joint["value"] = _clamp(joint, joint["value"])
		var pose: Transform3D = frame * _move_of(joint) * joint["rest"]
		b.global_transform = Transform3D(pose.basis * Basis.from_scale(b.global_basis.get_scale()), pose.origin)
		live["written"] = b.global_transform


# The engine's joint for a dynamic b; made again when either body changes.
func _engine_joint(joint: Dictionary, live: Dictionary, frame: Transform3D, body: RigidBody3D) -> void:
	var a := _find(joint["a"])
	var base: PhysicsBody3D = _body(a) if a else null
	if base == null:
		if not (live.has("proxy") and is_instance_valid(live["proxy"])):
			var proxy := StaticBody3D.new()  # teleports with the base; a kinematic body would drag b with its speed
			proxy.name = "Base_" + joint["id"]
			add_child(proxy)
			proxy.global_transform = _pose(a) if a else Transform3D()
			live["proxy"] = proxy
		base = live["proxy"]
	elif live.has("proxy"):
		if is_instance_valid(live["proxy"]):
			live["proxy"].queue_free()
		live.erase("proxy")
	var key := [base.get_instance_id(), body.get_instance_id(), joint["lower"], joint["upper"], joint["motor"]]
	if live.get("key") == key and is_instance_valid(live.get("joint")):
		return
	if is_instance_valid(live.get("joint")):
		live["joint"].queue_free()
	# The engine counts from where b is now; the limits count from where it was joined.
	var now: float = _measure(joint, frame, _pose(body))[0] if joint["type"] in ["hinge", "slider"] else 0.0
	var made: Joint3D
	var place := frame
	match joint["type"]:
		"hinge":
			var hinge := HingeJoint3D.new()
			var limited: bool = joint["lower"] != null or joint["upper"] != null
			hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, limited)
			# The engine's hinge angle runs the other way round the axis
			# (seen with Jolt), so the limits swap and turn over.
			if limited:
				hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, now - (joint["upper"] if joint["upper"] != null else PI))
				hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, now - (joint["lower"] if joint["lower"] != null else -PI))
			hinge.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, joint["motor"] != 0.0)
			hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, -joint["motor"])
			hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, MOTOR_IMPULSE)
			made = hinge
		"slider":
			# Free along x only; x is turned onto the joint's axis.
			var slide := Generic6DOFJoint3D.new()
			slide.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, (joint["lower"] if joint["lower"] != null else -MAX_SLIDE) - now)
			slide.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, (joint["upper"] if joint["upper"] != null else MAX_SLIDE) - now)
			slide.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_MOTOR, joint["motor"] != 0.0)
			slide.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_MOTOR_TARGET_VELOCITY, joint["motor"])
			slide.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_MOTOR_FORCE_LIMIT, MOTOR_IMPULSE * 20.0)
			place = frame * Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3.ZERO)
			made = slide
		"ball":
			made = PinJoint3D.new()
		_:
			made = Generic6DOFJoint3D.new()  # everything locked
	made.name = "Joint_" + joint["id"]
	add_child(made)
	made.global_transform = place
	made.node_a = made.get_path_to(base)
	made.node_b = made.get_path_to(body)
	live["joint"] = made
	live["key"] = key


func _drop_engine(live: Dictionary) -> void:
	for key in ["joint", "proxy"]:
		if live.has(key):
			if is_instance_valid(live[key]):
				live[key].queue_free()
			live.erase(key)
	live.erase("key")


# Parents first, so a chain (a lid on a box on a cart) moves in one frame.
func _sort() -> void:
	var placed := []
	var left := _joints.duplicate()
	while not left.is_empty():
		var moved := false
		for joint in left.duplicate():
			if not left.any(func(other): return other != joint and other["b"] == joint["a"]):
				placed.append(joint)
				left.erase(joint)
				moved = true
		if not moved:
			placed.append_array(left)
			break
	_joints = placed
	_update_running()


# Makes a joint from world-space values: {type, a, b, at, axis, lower, upper,
# motor, snap: {from, normal, to_normal}}. One undo.
func _join(spec: Dictionary) -> Dictionary:
	var a_name: String = spec.get("a", "")
	var b_name: String = spec["b"]
	var a := _find(a_name)
	var b := _find(b_name)
	if b == null:
		return {"ok": false, "error": "no thing named %s to move (list and assets_placed show them)" % JSON.stringify(b_name)}
	if not a_name.is_empty() and a == null:
		return {"ok": false, "error": "no thing named %s to join to" % JSON.stringify(a_name)}
	if a_name == b_name:
		return {"ok": false, "error": "a thing can't be joined to itself"}
	for joint in _joints:
		if joint["b"] == b_name:
			return {"ok": false, "error": "%s already moves on joint %s; take that off first, or join others to %s instead" % [b_name, joint["id"], b_name]}
	# No loops: the base mustn't hang from b.
	var up_from := a_name
	while not up_from.is_empty():
		if up_from == b_name:
			return {"ok": false, "error": "%s already hangs from %s, so it can't be its base" % [a_name, b_name]}
		var parent := ""
		for joint in _joints:
			if joint["b"] == up_from:
				parent = joint["a"]
		up_from = parent
	var before := b.global_transform
	if spec.has("snap"):
		var snap: Dictionary = spec["snap"]
		var turn := Basis(Quaternion((snap["normal"] as Vector3).normalized(), (snap["to_normal"] as Vector3).normalized()))
		var pose := _pose(b)
		var pivot_offset: Vector3 = snap["from"] - pose.origin
		var turned := Transform3D(turn * pose.basis, Vector3.ZERO)
		var origin: Vector3 = spec["at"] - turn * pivot_offset
		b.global_transform = Transform3D(turned.basis * Basis.from_scale(b.global_basis.get_scale()), origin)
	var world := _frame_at(spec["at"], spec["axis"])
	var joint := {"id": "j%d" % _next, "type": spec["type"], "a": a_name, "b": b_name,
		"frame": _pose(a).affine_inverse() * world if a else world, "rest": world.affine_inverse() * _pose(b),
		"value": 0.0, "turn": Quaternion(), "lower": spec.get("lower"), "upper": spec.get("upper"), "motor": spec.get("motor", 0.0)}
	_next += 1
	var after := b.global_transform
	_insert(joint)
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		var saved := _out(joint)
		var undo := func():
			_take(saved["id"])
			var node := _find(b_name)
			if node:
				node.global_transform = before
		var redo := func():
			var node := _find(b_name)
			if node:
				node.global_transform = after
			_insert(_in(saved))
		tools.call("push_undo", "%s %s" % [joint["type"], b_name], undo, redo)
	print("Slopitect joints: %s %s joins %s to %s" % [joint["type"], joint["id"], b_name, a_name if a else "the world"])
	return {"ok": true, "joint": _describe(joint)}


func _insert(joint: Dictionary) -> void:
	_joints.append(joint)
	_live[joint["id"]] = {}
	_sort()


func _take(id: String) -> Dictionary:
	for joint in _joints:
		if joint["id"] == id:
			_joints.erase(joint)
			_drop_engine(_live.get(id, {}))
			_live.erase(id)
			_update_running()
			return joint
	return {}


# --- Attach points -----------------------------------------------------------------

# A thing's attach points: the ones the shapes module works out from a made
# shape's geometry (shapes.attach_points(): top, end, ...), then the ones
# added here, which win on the same id. Both are in the thing's own space.
func _points_of(node_name: String) -> Dictionary:
	var out := {}
	var shapes: SlopitectModule = ctx["modules"].module("shapes")
	if shapes and shapes.has_method("attach_points") and _find(node_name) != null:
		var given = shapes.call("attach_points", node_name)
		if typeof(given) == TYPE_ARRAY:
			for p in given:
				if typeof(p) == TYPE_DICTIONARY and typeof(p.get("id")) == TYPE_STRING and p.get("position") is Vector3 and p.get("normal") is Vector3:
					out[p["id"]] = {"position": p["position"], "normal": p["normal"]}
	out.merge(_points.get(node_name, {}), true)
	return out


# Every thing with attach points: the shapes module's made shapes, and any
# with points added here.
func _named_points() -> Array:
	var names := _points.keys()
	if ctx["modules"].module("shapes") != null:
		for thing in _things():
			if thing.get_meta("made", false) and not String(thing.name) in names:
				names.append(String(thing.name))
	return names


func _point_world(node: Node3D, point: Dictionary) -> Dictionary:
	return {"position": node.global_transform * (point["position"] as Vector3),
		"normal": (node.global_basis.inverse().transposed() * (point["normal"] as Vector3)).normalized()}


func _add_point(node_name: String, id: String, node: Node3D, at: Vector3, normal: Vector3) -> Dictionary:
	var points: Dictionary = _points.get(node_name, {})
	if id.is_empty():
		var n := 1
		while points.has("p%d" % n):
			n += 1
		id = "p%d" % n
	var to_local := node.global_transform.affine_inverse()
	var point := {"position": to_local * at, "normal": (node.global_basis.transposed() * normal).normalized()}
	var old = points.get(id)
	var put := func(value):
		if value == null:
			_points.get(node_name, {}).erase(id)
			if _points.get(node_name, {}).is_empty():
				_points.erase(node_name)
		else:
			if not _points.has(node_name):
				_points[node_name] = {}
			_points[node_name][id] = value
	put.call(point)
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		tools.call("push_undo", "point %s on %s" % [id, node_name], put.bind(old), put.bind(point))
	return {"ok": true, "name": node_name, "id": id, "position": _vec_out(at), "normal": _vec_out(normal)}


# The middle of a face of the thing's box, in its own space: [position, normal].
func _face(node: Node3D, face: String) -> Array:
	var meshes: Array = [node] if node is MeshInstance3D else []
	meshes.append_array(node.find_children("*", "MeshInstance3D", true, false))
	var to_local := node.global_transform.affine_inverse()
	var box := AABB()
	for i in meshes.size():
		var part: AABB = (to_local * (meshes[i] as MeshInstance3D).global_transform) * (meshes[i] as MeshInstance3D).get_aabb()
		box = part if i == 0 else box.merge(part)
	var normal: Vector3 = {"top": Vector3.UP, "bottom": Vector3.DOWN, "left": Vector3.LEFT, "right": Vector3.RIGHT,
		"front": Vector3.BACK, "back": Vector3.FORWARD}[face]
	return [box.get_center() + normal * box.size / 2.0, normal]


# --- For the save module ------------------------------------------------------------

func get_joints() -> Dictionary:
	var points := {}
	for node_name in _points:
		points[node_name] = {}
		for id in _points[node_name]:
			var p: Dictionary = _points[node_name][id]
			points[node_name][id] = {"position": _numbers(p["position"]), "normal": _numbers(p["normal"])}
	return {"joints": _joints.map(_out), "points": points, "next": _next}


func set_joints(data: Dictionary) -> void:
	for joint in _joints.duplicate():
		_take(joint["id"])
	_points.clear()
	_first = {}
	if typeof(data.get("joints")) == TYPE_ARRAY:
		for saved in data["joints"]:
			var joint = _in(saved) if typeof(saved) == TYPE_DICTIONARY else null
			if joint != null:
				_insert(joint)
	if typeof(data.get("points")) == TYPE_DICTIONARY:
		for node_name in data["points"]:
			if typeof(data["points"][node_name]) != TYPE_DICTIONARY:
				continue
			for id in data["points"][node_name]:
				var p = data["points"][node_name][id]
				if typeof(p) == TYPE_DICTIONARY and _is_numbers(p.get("position"), 3) and _is_numbers(p.get("normal"), 3):
					if not _points.has(node_name):
						_points[node_name] = {}
					_points[node_name][id] = {"position": _vector(p["position"]), "normal": _vector(p["normal"])}
	_next = maxi(int(data.get("next", 1)), _next)


# For undoing a delete (tools.gd): a thing's joints and attach points.
func thing_state(node_name: String) -> Dictionary:
	var joints := _joints.filter(func(j): return node_name in [j["a"], j["b"]]).map(_out)
	var points := {}
	for id in _points.get(node_name, {}):
		var p: Dictionary = _points[node_name][id]
		points[id] = {"position": p["position"], "normal": p["normal"]}
	if joints.is_empty() and points.is_empty():
		return {}
	return {"joints": joints, "points": points}


func thing_forget(node_name: String) -> void:
	for joint in _joints.duplicate():
		if node_name in [joint["a"], joint["b"]]:
			_take(joint["id"])
	_points.erase(node_name)
	if _first.get("name", "") == node_name:
		_first = {}


func thing_restore(node_name: String, state: Dictionary) -> void:
	var have := _joints.map(func(j): return j["id"])
	for saved in state.get("joints", []):
		if not saved["id"] in have:
			var joint = _in(saved)
			if joint != null:
				_insert(joint)
	if not (state.get("points", {}) as Dictionary).is_empty():
		if not _points.has(node_name):
			_points[node_name] = {}
		for id in state["points"]:
			_points[node_name][id] = state["points"][id].duplicate()


func _out(joint: Dictionary) -> Dictionary:
	var t: Quaternion = joint["turn"]
	return {"id": joint["id"], "type": joint["type"], "a": joint["a"], "b": joint["b"],
		"frame": _transform_out(joint["frame"]), "rest": _transform_out(joint["rest"]),
		"value": snappedf(joint["value"], 0.0001), "turn": [snappedf(t.x, 0.0001), snappedf(t.y, 0.0001), snappedf(t.z, 0.0001), snappedf(t.w, 0.0001)],
		"lower": joint["lower"], "upper": joint["upper"], "motor": joint["motor"]}


func _in(saved: Dictionary):
	if not saved.get("type") in TYPES or typeof(saved.get("id")) != TYPE_STRING or typeof(saved.get("b")) != TYPE_STRING or typeof(saved.get("a")) != TYPE_STRING:
		return null
	if not (_is_numbers(saved.get("frame"), 12) and _is_numbers(saved.get("rest"), 12) and _is_numbers(saved.get("turn"), 4)):
		return null
	var t: Array = saved["turn"]
	var limit := func(v): return float(v) if typeof(v) in [TYPE_FLOAT, TYPE_INT] else null
	return {"id": saved["id"], "type": saved["type"], "a": saved["a"], "b": saved["b"],
		"frame": _transform_in(saved["frame"]), "rest": _transform_in(saved["rest"]),
		"value": float(saved.get("value", 0.0)), "turn": Quaternion(t[0], t[1], t[2], t[3]).normalized(),
		"lower": limit.call(saved.get("lower")), "upper": limit.call(saved.get("upper")), "motor": float(saved.get("motor", 0.0))}


func _transform_out(t: Transform3D) -> Array:
	var out := []
	for v in [t.basis.x, t.basis.y, t.basis.z, t.origin]:
		out.append_array(_numbers(v))
	return out


func _transform_in(a: Array) -> Transform3D:
	return Transform3D(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]), Vector3(a[9], a[10], a[11]))


func _numbers(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


func _is_numbers(value, count: int) -> bool:
	return typeof(value) == TYPE_ARRAY and value.size() == count and value.all(func(x): return typeof(x) in [TYPE_FLOAT, TYPE_INT])


func _vector(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _vec_out(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


# --- Marks --------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var mesh := _marks.mesh as ImmediateMesh
	mesh.clear_surfaces()
	_marks.visible = _prefs["show"] == "always" or (_prefs["show"] == "tool" and _chosen)
	if not _marks.visible:
		return
	var lines := []  # [from, to, colour]
	for node_name in _named_points():
		var node := _find(node_name)
		if node == null:
			continue
		var points := _points_of(node_name)
		for id in points:
			var p := _point_world(node, points[id])
			_cross(lines, p["position"], 0.02, Color.YELLOW)
			lines.append([p["position"], p["position"] + p["normal"] * 0.06, Color.YELLOW])
	for joint in _joints:
		var frame = _world_frame(joint)
		if frame == null:
			continue
		var at: Vector3 = frame.origin
		var axis: Vector3 = frame.basis.z
		match joint["type"]:
			"hinge":
				lines.append([at - axis * 0.12, at + axis * 0.12, Color.CYAN])
			"slider":
				var low: float = joint["lower"] if joint["lower"] != null else -0.3
				var high: float = joint["upper"] if joint["upper"] != null else 0.3
				lines.append([at + axis * low, at + axis * high, Color.CYAN])
			_:
				_cross(lines, at, 0.04, Color.CYAN)
	if not _first.is_empty():
		_cross(lines, _first["position"], 0.04, Color.GREEN)
		lines.append([_first["position"], _first["position"] + _tool_axis(_first["normal"]) * 0.12, Color.GREEN])
	if lines.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for line in lines:
		mesh.surface_set_color(line[2])
		mesh.surface_add_vertex(line[0])
		mesh.surface_add_vertex(line[1])
	mesh.surface_end()


func _cross(lines: Array, at: Vector3, size: float, colour: Color) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		lines.append([at - axis * size, at + axis * size, colour])


# --- Commands -----------------------------------------------------------------------

func _vec_in(request: Dictionary, key: String) -> Array:
	if not request.has(key):
		return ["", null]
	if not _is_numbers(request[key], 3):
		return ["\"%s\" must be [x, y, z]" % key, null]
	return ["", _vector(request[key])]


# Hinge degrees (stored as radians) or slider metres; [problem, value].
func _amount(type: String, request: Dictionary, key: String, speed: bool):
	var value = request[key]
	if value == null and not speed:
		return ["", null]
	if not typeof(value) in [TYPE_FLOAT, TYPE_INT]:
		return ["\"%s\" must be a number%s" % [key, "" if speed else " or null"], null]
	var most: float = (MAX_TURN_SPEED if speed else MAX_HINGE) if type == "hinge" else (MAX_SLIDE_SPEED if speed else MAX_SLIDE)
	if absf(value) > most:
		return ["\"%s\" must be %s to %s" % [key, -most, most], null]
	return ["", deg_to_rad(value) if type == "hinge" else float(value)]


func _shown(type: String, value) -> Variant:
	if value == null:
		return null
	return snappedf(rad_to_deg(value), 0.1) if type == "hinge" else snappedf(value, 0.001)


func _add_command(request: Dictionary) -> Dictionary:
	var type = request.get("type", "hinge")
	if not type in TYPES:
		return {"ok": false, "error": "\"type\" must be one of %s" % [TYPES]}
	var a_name = request.get("a", "")
	var b_name = request.get("b")
	if typeof(a_name) != TYPE_STRING or typeof(b_name) != TYPE_STRING:
		return {"ok": false, "error": "\"b\" (the part that moves) and \"a\" (the part that stays, or \"\" for the world) must be names"}
	var a := _find(a_name)
	var b := _find(b_name)
	if b == null or (not a_name.is_empty() and a == null):
		return {"ok": false, "error": "no thing named %s (list and assets_placed show them)" % JSON.stringify(b_name if b == null else a_name)}
	var spec := {"type": type, "a": a_name, "b": b_name}
	var point_a := {}
	var point_b := {}
	for which in [["point_a", a, a_name], ["point_b", b, b_name]]:
		if request.has(which[0]):
			var id = request[which[0]]
			if which[1] == null or typeof(id) != TYPE_STRING or not _points_of(which[2]).has(id):
				return {"ok": false, "error": "%s has no attach point %s (joints_points lists them)" % [which[2] if which[1] else "the world", JSON.stringify(id)]}
			var world := _point_world(which[1], _points_of(which[2])[id])
			if which[0] == "point_a":
				point_a = world
			else:
				point_b = world
	for key in ["at", "axis"]:
		var got := _vec_in(request, key)
		if not got[0].is_empty():
			return {"ok": false, "error": got[0]}
		if got[1] != null:
			spec[key] = got[1]
	if spec.has("axis") and (spec["axis"] as Vector3).length() < 0.001:
		return {"ok": false, "error": "\"axis\" can't be [0, 0, 0]"}
	if not spec.has("at"):
		spec["at"] = point_a["position"] if not point_a.is_empty() else (point_b["position"] if not point_b.is_empty() else b.global_position)
	if not spec.has("axis"):
		spec["axis"] = point_a["normal"] if not point_a.is_empty() else Vector3.UP
	spec["axis"] = (spec["axis"] as Vector3).normalized()
	var snap = request.get("snap", not point_b.is_empty())
	if typeof(snap) != TYPE_BOOL:
		return {"ok": false, "error": "\"snap\" must be true or false"}
	if snap:
		if point_b.is_empty():
			return {"ok": false, "error": "\"snap\" needs point_b, the spot on b that goes to the pivot"}
		spec["snap"] = {"from": point_b["position"], "normal": point_b["normal"],
			"to_normal": -(point_a["normal"] as Vector3) if not point_a.is_empty() else point_b["normal"]}
	for key in ["lower", "upper"]:
		if request.has(key):
			if type in ["ball", "fixed"]:
				return {"ok": false, "error": "a %s joint has no limits" % type}
			var got = _amount(type, request, key, false)
			if not got[0].is_empty():
				return {"ok": false, "error": got[0]}
			spec[key] = got[1]
	if spec.get("lower") != null and spec.get("upper") != null and spec["lower"] > spec["upper"]:
		return {"ok": false, "error": "\"lower\" must be below \"upper\""}
	if type == "slider" and not (request.has("lower") or request.has("upper")):
		spec["lower"] = -0.5  # a slider with no ends would let a drawer fly off
		spec["upper"] = 0.5
	if request.has("motor"):
		if not type in ["hinge", "slider"]:
			return {"ok": false, "error": "only hinges and sliders have a motor"}
		var got = _amount(type, request, "motor", true)
		if not got[0].is_empty():
			return {"ok": false, "error": got[0]}
		spec["motor"] = got[1]
	return _join(spec)


func _remove_command(request: Dictionary) -> Dictionary:
	var taken := []
	if request.has("id"):
		var joint := _take(str(request["id"]))
		if joint.is_empty():
			return {"ok": false, "error": "no joint %s (joints_list shows them)" % JSON.stringify(request["id"])}
		taken.append(joint)
	elif typeof(request.get("name")) == TYPE_STRING:
		for joint in _joints.duplicate():
			if request["name"] in [joint["a"], joint["b"]]:
				taken.append(_take(joint["id"]))
	else:
		return {"ok": false, "error": "joints_remove needs id or name"}
	var saved := taken.map(_out)
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools and not saved.is_empty():
		var put_back := func():
			for s in saved:
				_insert(_in(s))
		var take_again := func():
			for s in saved:
				_take(s["id"])
		tools.call("push_undo", "take off %d joint(s)" % saved.size(), put_back, take_again)
	return {"ok": true, "removed": saved.map(func(s): return s["id"])}


func _set_command(request: Dictionary) -> Dictionary:
	var joint := {}
	for j in _joints:
		if j["id"] == str(request.get("id", "")):
			joint = j
	if joint.is_empty():
		return {"ok": false, "error": "no joint %s (joints_list shows them)" % JSON.stringify(request.get("id"))}
	if not joint["type"] in ["hinge", "slider"]:
		return {"ok": false, "error": "a %s joint has nothing to set" % joint["type"]}
	var changes := {}
	for key in ["lower", "upper", "motor", "value"]:
		if request.has(key):
			var got = _amount(joint["type"], request, key, key in ["motor", "value"])
			if not got[0].is_empty():
				return {"ok": false, "error": got[0]}
			changes[key] = got[1]
	var lower = changes.get("lower", joint["lower"])
	var upper = changes.get("upper", joint["upper"])
	if lower != null and upper != null and lower > upper:
		return {"ok": false, "error": "\"lower\" must be below \"upper\""}
	var before := {}
	for key in changes:
		before[key] = joint[key]
	_change(joint["id"], changes)
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools and before != changes:
		tools.call("push_undo", "set joint " + joint["id"], _change.bind(joint["id"], before), _change.bind(joint["id"], changes.duplicate()))
	return {"ok": true, "joint": _describe(joint)}


# A joint's lower, upper, motor and value; a new value moves b there.
func _change(id: String, changes: Dictionary) -> void:
	var joint := {}
	for j in _joints:
		if j["id"] == id:
			joint = j
	if joint.is_empty():
		return
	for key in ["lower", "upper", "motor"]:
		if changes.has(key):
			joint[key] = changes[key]
	if changes.has("value"):
		joint["value"] = _clamp(joint, changes["value"])
		var frame = _world_frame(joint)
		var b := _find(joint["b"])
		if frame != null and b != null:
			var pose: Transform3D = frame * _move_of(joint) * joint["rest"]
			b.global_transform = Transform3D(pose.basis * Basis.from_scale(b.global_basis.get_scale()), pose.origin)
			_live[joint["id"]]["written"] = b.global_transform
			var body := _body(b)
			if body:
				body.global_transform = pose
				body.linear_velocity = Vector3.ZERO
				body.angular_velocity = Vector3.ZERO


func _describe(joint: Dictionary) -> Dictionary:
	var out := {"id": joint["id"], "type": joint["type"], "a": joint["a"] if not joint["a"].is_empty() else "(world)", "b": joint["b"]}
	var frame = _world_frame(joint)
	var b := _find(joint["b"])
	if frame == null or b == null:
		out["moves"] = "waiting for %s" % (joint["b"] if b == null else joint["a"])
	else:
		var body := _body(b)
		out["moves"] = "engine" if body != null and not body.freeze else "follows"
		out["pivot"] = _vec_out(frame.origin)
		out["axis"] = _vec_out(frame.basis.z)
		if joint["type"] in ["hinge", "slider"]:
			var value: float = joint["value"] if out["moves"] == "follows" else _measure(joint, frame, _pose(b))[0]
			out["value"] = _shown(joint["type"], value)
	if joint["type"] in ["hinge", "slider"]:
		out["lower"] = _shown(joint["type"], joint["lower"])
		out["upper"] = _shown(joint["type"], joint["upper"])
		out["motor"] = _shown(joint["type"], joint["motor"])
		out["units"] = "degrees" if joint["type"] == "hinge" else "metres"
	return out


func _list_command(_request: Dictionary) -> Dictionary:
	return {"ok": true, "joints": _joints.map(_describe)}


func _point_add_command(request: Dictionary) -> Dictionary:
	var node_name = request.get("name")
	var node := _find(node_name)
	if node == null:
		return {"ok": false, "error": "no thing named %s" % JSON.stringify(node_name)}
	var id = request.get("id", "")
	if typeof(id) != TYPE_STRING or (not id.is_empty() and not id.is_valid_ascii_identifier()):
		return {"ok": false, "error": "\"id\" must be letters, digits and _"}
	var at: Vector3
	var normal: Vector3
	if request.has("face"):
		if not request["face"] in ["top", "bottom", "left", "right", "front", "back"]:
			return {"ok": false, "error": "\"face\" must be top, bottom, left, right, front or back"}
		var face := _face(node, request["face"])
		var world := _point_world(node, {"position": face[0], "normal": face[1]})
		at = world["position"]
		normal = world["normal"]
	else:
		var got := _vec_in(request, "position")
		if not got[0].is_empty() or got[1] == null:
			return {"ok": false, "error": "joints_point_add needs position [x, y, z] or face"}
		at = got[1]
		normal = (at - node.global_position).normalized()
	var given := _vec_in(request, "normal")
	if not given[0].is_empty():
		return {"ok": false, "error": given[0]}
	if given[1] != null:
		if (given[1] as Vector3).length() < 0.001:
			return {"ok": false, "error": "\"normal\" can't be [0, 0, 0]"}
		normal = (given[1] as Vector3).normalized()
	if normal.length() < 0.001:
		normal = Vector3.UP
	return _add_point(String(node.name), id, node, at, normal)


func _point_remove_command(request: Dictionary) -> Dictionary:
	var node_name = request.get("name")
	var id = request.get("id")
	if typeof(node_name) != TYPE_STRING or not _points.get(node_name, {}).has(id):
		return {"ok": false, "error": "%s has no attach point %s" % [JSON.stringify(node_name), JSON.stringify(id)]}
	var old: Dictionary = _points[node_name][id]
	var put := func(value):
		if value == null:
			_points.get(node_name, {}).erase(id)
			if _points.get(node_name, {}).is_empty():
				_points.erase(node_name)
		else:
			if not _points.has(node_name):
				_points[node_name] = {}
			_points[node_name][id] = value
	put.call(null)
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		tools.call("push_undo", "remove point %s on %s" % [id, node_name], put.bind(old), put.bind(null))
	return {"ok": true, "removed": id}


func _points_command(request: Dictionary) -> Dictionary:
	var out := {}
	for node_name in _named_points():
		if request.has("name") and request["name"] != node_name:
			continue
		var node := _find(node_name)
		var points := _points_of(node_name)
		out[node_name] = {}
		for id in points:
			if node == null:
				out[node_name][id] = "waiting for %s" % node_name
			else:
				var p := _point_world(node, points[id])
				out[node_name][id] = {"position": _vec_out(p["position"]), "normal": _vec_out(p["normal"])}
	return {"ok": true, "points": out}


func _prefs_command(request: Dictionary) -> Dictionary:
	if request.has("show") and not request["show"] in SHOW:
		return {"ok": false, "error": "\"show\" must be one of %s" % [SHOW]}
	if request.has("snap") and typeof(request["snap"]) != TYPE_BOOL:
		return {"ok": false, "error": "\"snap\" must be true or false"}
	for key in ["show", "snap"]:
		if request.has(key):
			_prefs[key] = request[key]
	_update_running()
	var problem: String = _lib.write_json(PREFS_PATH, _prefs) if _lib else "the lib module isn't loaded"
	if not problem.is_empty():
		push_error("Slopitect joints: couldn't save %s: %s" % [PREFS_PATH, problem])
	if _lib:
		_lib.touch(self)  # its Settings section and tool buttons show them
	return {"ok": true, "show": _prefs["show"], "snap": _prefs["snap"]}


func _load_prefs() -> void:
	if not FileAccess.file_exists(PREFS_PATH):
		return
	var saved = _lib.read_json(PREFS_PATH)
	if typeof(saved) != TYPE_DICTIONARY:
		push_error("Slopitect joints: %s isn't readable; using the defaults" % PREFS_PATH)
		return
	if saved.get("show") in SHOW:
		_prefs["show"] = saved["show"]
	if typeof(saved.get("snap")) == TYPE_BOOL:
		_prefs["snap"] = saved["snap"]
