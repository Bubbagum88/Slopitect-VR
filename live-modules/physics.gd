extends SlopitectModule

# Slopitect live module: physics.
# Lets shapes and placed models fall, bounce and collide, using the engine's
# own physics (nothing is simulated by hand here). Nothing moves until it's
# made dynamic: physics_set {name, mode: "dynamic"}. A "static" thing stays
# put but others hit it; "off" (the default) leaves it alone. The ground is
# the floor, or the landscape module's ground while that's loaded. With the
# grab module, a dynamic thing you let go of is thrown with the hand's speed.
# Each thing's physics is kept in user://physics.json by its name, so it
# comes back with the save module's world.

const SETTINGS_PATH := "user://physics.json"
const MODES := ["off", "static", "dynamic"]
const LOST_BELOW := -30.0  # a thing that falls this far is put back where it was made dynamic
const SCAN_SECONDS := 1.0

var _bodies := {}  # node name -> {"node", "body": RigidBody3D, "written": Transform3D, "scale": Vector3, "home": Transform3D, "held": bool}
var _settings := {}  # node name -> {"mode", "mass", "bounce", "friction"}
var _ground: StaticBody3D
var _ground_landscape := false
var _since_scan := SCAN_SECONDS


func setup() -> String:
	_load()
	_ground = StaticBody3D.new()
	_ground.name = "Ground"
	add_child(_ground)
	_build_ground()
	register("physics_set", _set_command, "make a shape or model physical: name, mode (dynamic: falls and collides; static: stays, others hit it; off), optional mass (kg), bounce (0-1), friction (0-1)")
	register("physics_push", _push, "set a dynamic thing moving: name, velocity [x, y, z] in m/s")
	register("physics_status", _status, "every physical thing: mode, whether it's moving or resting, its speed")
	register("physics_config", _config, "from the PC only: gravity (m/s², default 9.8)")
	return ""


# --- The ground ----------------------------------------------------------------------

func _build_ground() -> void:
	for child in _ground.get_children():
		child.queue_free()
	var landscape: SlopitectModule = ctx["modules"].module("landscape")
	_ground_landscape = landscape != null
	var shape := CollisionShape3D.new()
	if landscape:
		# The landscape's heights as a height map, one cell per height step.
		var constants: Dictionary = landscape.get_script().get_script_constant_map()
		var n: int = constants["N"]
		var step: float = constants["STEP"]
		var heights: PackedFloat32Array = landscape.call("get_heights")
		for i in heights.size():
			heights[i] /= step  # the shape is scaled by step below
		var map := HeightMapShape3D.new()
		map.map_width = n
		map.map_depth = n
		map.map_data = heights
		shape.shape = map
		shape.scale = Vector3.ONE * step
		if not landscape.is_connected("changed", _build_ground):
			landscape.connect("changed", _build_ground)
	else:
		shape.shape = WorldBoundaryShape3D.new()  # the floor, y = 0, everywhere
	_ground.add_child(shape)


# --- Bodies --------------------------------------------------------------------------

func _find(node_name) -> Node3D:
	if typeof(node_name) != TYPE_STRING or node_name.is_empty() or node_name.validate_node_name() != node_name:
		return null
	var world: Node3D = ctx["world"]
	var node := world.get_node_or_null(NodePath(node_name)) as Node3D
	if node == null and world.has_node("PolyHaven"):
		node = world.get_node("PolyHaven").get_node_or_null(NodePath(node_name)) as Node3D
	return node


# The thing's box in its own space (without its scale), from its meshes.
func _local_box(node: Node3D) -> AABB:
	var meshes: Array = [node] if node is MeshInstance3D else node.find_children("*", "MeshInstance3D", true, false)
	var to_local := node.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in meshes:
		var part := (to_local * mesh.global_transform) * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


# A collision shape the size of the thing, with its scale baked in (the
# engine doesn't take stretched shapes).
func _shape_for(node: Node3D) -> CollisionShape3D:
	var scale := node.global_basis.get_scale()
	var box := _local_box(node)
	var size := box.size * scale
	var holder := CollisionShape3D.new()
	holder.position = box.get_center() * scale
	var kind := String(node.get_meta("shape", "box")) if node is MeshInstance3D else "box"
	var even := is_equal_approx(scale.x, scale.y) and is_equal_approx(scale.y, scale.z)
	if kind == "sphere" and even:
		var sphere := SphereShape3D.new()
		sphere.radius = size.x / 2.0
		holder.shape = sphere
	elif kind == "cylinder" and is_equal_approx(scale.x, scale.z):
		var cylinder := CylinderShape3D.new()
		cylinder.radius = size.x / 2.0
		cylinder.height = size.y
		holder.shape = cylinder
	elif kind == "capsule" and is_equal_approx(scale.x, scale.z):
		var capsule := CapsuleShape3D.new()
		capsule.radius = size.x / 2.0
		capsule.height = maxf(size.y, size.x)
		holder.shape = capsule
	else:
		var cube := BoxShape3D.new()
		cube.size = size.max(Vector3.ONE * 0.01)
		holder.shape = cube
	return holder


func _make_body(node: Node3D, config: Dictionary) -> void:
	_drop_body(String(node.name))
	if config["mode"] == "off":
		return
	var body := RigidBody3D.new()
	body.name = "Body_" + String(node.name)
	body.add_child(_shape_for(node))
	body.mass = float(config["mass"])
	var material := PhysicsMaterial.new()
	material.bounce = float(config["bounce"])
	material.friction = float(config["friction"])
	body.physics_material_override = material
	body.continuous_cd = true
	if config["mode"] == "static":
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
	add_child(body)
	var unscaled := Transform3D(node.global_basis.orthonormalized(), node.global_position)
	body.global_transform = unscaled
	_bodies[String(node.name)] = {"node": node, "body": body, "written": node.global_transform, "scale": node.global_basis.get_scale(),
		"home": unscaled, "held": false}


func _drop_body(node_name: String) -> void:
	if _bodies.has(node_name):
		var body: RigidBody3D = _bodies[node_name]["body"]
		if is_instance_valid(body):
			body.queue_free()
		_bodies.erase(node_name)


func _physics_process(_delta: float) -> void:
	for node_name in _bodies.keys():
		var entry: Dictionary = _bodies[node_name]
		var node: Node3D = entry["node"]
		var body: RigidBody3D = entry["body"]
		if not is_instance_valid(node) or not node.is_inside_tree() or String(node.name) != node_name:
			_drop_body(node_name)  # deleted or renamed; the scan picks it up again by name
			continue
		var scale := node.global_basis.get_scale()
		if not scale.is_equal_approx(entry["scale"]):
			_make_body(node, _settings[node_name])  # resized: a new shape to match
			continue
		if entry["held"] or not node.global_transform.is_equal_approx(entry["written"]):
			# Moved by a hand or a command: the body goes where the thing is.
			body.global_transform = Transform3D(node.global_basis.orthonormalized(), node.global_position)
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			entry["written"] = node.global_transform
			continue
		if body.freeze:
			continue
		if body.global_position.y < LOST_BELOW:
			print("Slopitect physics: %s fell out of the world; put back" % node_name)
			body.global_transform = entry["home"]
			body.linear_velocity = Vector3.ZERO
		node.global_transform = Transform3D(body.global_basis * Basis.from_scale(scale), body.global_position)
		entry["written"] = node.global_transform


func _process(delta: float) -> void:
	_since_scan += delta
	if _since_scan < SCAN_SECONDS:
		return
	_since_scan = 0.0
	# Things with saved physics that came back (the save module, a restart).
	for node_name in _settings:
		if not _bodies.has(node_name) and _settings[node_name]["mode"] != "off":
			var node := _find(node_name)
			if node:
				_make_body(node, _settings[node_name])
	if (ctx["modules"].module("landscape") != null) != _ground_landscape:
		_build_ground()


# For the grab module: a held thing follows the hand, not the physics.
func hold(node: Node3D, on: bool) -> void:
	var node_name := String(node.name)
	if not _bodies.has(node_name):
		return
	var entry: Dictionary = _bodies[node_name]
	entry["held"] = on
	var body: RigidBody3D = entry["body"]
	if _settings[node_name]["mode"] == "dynamic":
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = on


func throw(node: Node3D, velocity: Vector3) -> void:
	var node_name := String(node.name)
	if _bodies.has(node_name) and _settings[node_name]["mode"] == "dynamic":
		(_bodies[node_name]["body"] as RigidBody3D).linear_velocity = velocity.limit_length(30.0)


# --- Commands ------------------------------------------------------------------------

func _number_in(request: Dictionary, key: String, low: float, high: float, fallback: float) -> Array:
	if not request.has(key):
		return ["", fallback]
	var value = request[key]
	if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or float(value) < low or float(value) > high:
		return ["\"%s\" must be %s to %s" % [key, low, high], 0.0]
	return ["", float(value)]


func _set_command(request: Dictionary) -> Dictionary:
	var node := _find(request.get("name"))
	if node == null:
		return {"ok": false, "error": "no shape or model named %s (list and assets_placed show them)" % JSON.stringify(request.get("name"))}
	var node_name := String(node.name)
	var old: Dictionary = _settings.get(node_name, {"mode": "off", "mass": 1.0, "bounce": 0.2, "friction": 0.6})
	var mode = request.get("mode", old["mode"])
	if not mode in MODES:
		return {"ok": false, "error": "\"mode\" must be one of %s" % [MODES]}
	var config := {"mode": mode}
	for spec in [["mass", 0.01, 10000.0], ["bounce", 0.0, 1.0], ["friction", 0.0, 1.0]]:
		var got := _number_in(request, spec[0], spec[1], spec[2], old[spec[0]])
		if not got[0].is_empty():
			return {"ok": false, "error": got[0]}
		config[spec[0]] = got[1]
	_settings[node_name] = config
	_save()
	_make_body(node, config)
	return {"ok": true, "name": node_name, "physics": config}


func _push(request: Dictionary) -> Dictionary:
	var node := _find(request.get("name"))
	if node == null or not _bodies.has(String(node.name)) or _settings[String(node.name)]["mode"] != "dynamic":
		return {"ok": false, "error": "%s isn't a dynamic thing (physics_set it to dynamic first)" % JSON.stringify(request.get("name"))}
	var v = request.get("velocity")
	if typeof(v) != TYPE_ARRAY or v.size() != 3 or v.any(func(x): return typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT):
		return {"ok": false, "error": "\"velocity\" must be [x, y, z] in m/s"}
	var body: RigidBody3D = _bodies[String(node.name)]["body"]
	body.linear_velocity = Vector3(v[0], v[1], v[2]).limit_length(30.0)
	return {"ok": true}


func _status(_request: Dictionary) -> Dictionary:
	var listed := []
	for node_name in _settings:
		var item := {"name": node_name}
		item.merge(_settings[node_name])
		if _bodies.has(node_name):
			var body: RigidBody3D = _bodies[node_name]["body"]
			item["resting"] = body.sleeping or body.freeze
			item["speed"] = snappedf(body.linear_velocity.length(), 0.01)
		else:
			item["in_world"] = false
		listed.append(item)
	return {"ok": true, "things": listed, "ground": "landscape" if _ground_landscape else "floor",
		"gravity": PhysicsServer3D.area_get_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY),
		# Jolt's server class only exists when Jolt is the running engine.
		"engine": "Jolt" if ClassDB.class_exists("JoltPhysicsServer3D") else "Godot Physics"}


func _config(request: Dictionary) -> Dictionary:
	if request.has("gravity"):
		var got := _number_in(request, "gravity", 0.0, 100.0, 9.8)
		if not got[0].is_empty():
			return {"ok": false, "error": got[0]}
		PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, got[1])
	return _status({})


func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var saved = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(saved) != TYPE_DICTIONARY:
		push_error("Slopitect physics: %s isn't readable; starting with nothing physical" % SETTINGS_PATH)
		return
	for node_name in saved:
		var c = saved[node_name]
		if typeof(c) == TYPE_DICTIONARY and c.get("mode") in MODES:
			_settings[node_name] = {"mode": c["mode"], "mass": float(c.get("mass", 1.0)), "bounce": float(c.get("bounce", 0.2)), "friction": float(c.get("friction", 0.6))}


func _save() -> void:
	var out := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if out == null:
		push_error("Slopitect physics: couldn't save %s" % SETTINGS_PATH)
		return
	out.store_string(JSON.stringify(_settings, "\t"))
	out.close()
