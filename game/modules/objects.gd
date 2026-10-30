extends SlopitectModule

# Objects: simple shapes you (or Claude) can spawn, move, colour and delete.
# They live under the World node. With the tools live module loaded, each
# change is one undo there, and undoing a delete brings back what other
# modules kept about the shape (tools.gd's thing_snapshot).

const SHAPES := ["box", "sphere", "cylinder", "capsule"]

var _world: Node3D


func setup() -> String:
	_world = ctx["world"]
	register("list", _list, "list every object: name, shape, position, rotation, scale, colour")
	register("spawn", _spawn, "spawn a shape (%s); optional name, position, rotation, scale, color" % ", ".join(SHAPES))
	register("move", _move, "change an object's position, rotation and/or scale")
	register("color", _color, "recolour an object")
	register("delete", _delete, "delete an object")
	return ""


func _list(_request: Dictionary) -> Dictionary:
	var objects := []
	for child in _world.get_children():
		if child is MeshInstance3D:
			objects.append(_describe(child))
	return {"ok": true, "objects": objects}


func _describe(node: MeshInstance3D) -> Dictionary:
	var material := node.get_surface_override_material(0) as StandardMaterial3D
	return {
		"name": String(node.name),
		"shape": node.get_meta("shape", "?"),
		"position": _vec_out(node.position),
		"rotation": _vec_out(node.rotation_degrees),
		"scale": _vec_out(node.scale),
		"color": material.albedo_color.to_html(false) if material else null,
	}


func _spawn(request: Dictionary) -> Dictionary:
	var shape = request.get("shape", "box")
	if not shape in SHAPES:
		return {"ok": false, "error": "unknown shape \"%s\" (one of: %s)" % [shape, ", ".join(SHAPES)]}

	var node_name = request.get("name", "")
	if typeof(node_name) != TYPE_STRING:
		return {"ok": false, "error": "\"name\" must be a string"}
	if node_name.is_empty():
		node_name = _free_name(shape)
	elif node_name.validate_node_name() != node_name:
		return {"ok": false, "error": "name \"%s\" can't contain . : @ / \" %% or spaces at the ends" % node_name}
	elif _world.has_node(NodePath(node_name)):
		return {"ok": false, "error": "an object named \"%s\" already exists" % node_name}

	var color := Color.WHITE
	if request.has("color"):
		var parsed := _color_in(request["color"])
		if parsed.has("error"):
			return {"ok": false, "error": parsed["error"]}
		color = parsed["color"]

	var node := MeshInstance3D.new()
	node.name = node_name
	node.set_meta("shape", shape)
	match shape:
		"box":
			node.mesh = BoxMesh.new()
		"sphere":
			node.mesh = SphereMesh.new()
		"cylinder":
			node.mesh = CylinderMesh.new()
		"capsule":
			node.mesh = CapsuleMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.set_surface_override_material(0, material)

	var transform_error := _apply_transform(node, request)
	if not transform_error.is_empty():
		node.free()
		return {"ok": false, "error": transform_error}
	_world.add_child(node)
	var made := _describe(node)
	var again := _spawn_request(made)
	var take_away := func():
		_delete({"name": node_name})
		var tools := _tools()
		if tools and tools.has_method("thing_forget"):
			tools.call("thing_forget", node_name)
	_undo("spawn " + node_name, take_away, _spawn.bind(again))
	return {"ok": true, "object": made}


func _move(request: Dictionary) -> Dictionary:
	var found := _find(request)
	if found.has("error"):
		return found
	if not (request.has("position") or request.has("rotation") or request.has("scale")):
		return {"ok": false, "error": "move needs at least one of \"position\", \"rotation\", \"scale\""}
	var node: MeshInstance3D = found["node"]
	var before := node.transform
	var transform_error := _apply_transform(node, request)
	if not transform_error.is_empty():
		return {"ok": false, "error": transform_error}
	var after := node.transform
	if not before.is_equal_approx(after):
		_undo("move " + String(node.name), _put.bind(String(node.name), before), _put.bind(String(node.name), after))
	return {"ok": true, "object": _describe(node)}


func _color(request: Dictionary) -> Dictionary:
	var found := _find(request)
	if found.has("error"):
		return found
	if not request.has("color"):
		return {"ok": false, "error": "color needs \"color\", e.g. \"#ff8800\" or \"red\""}
	var parsed := _color_in(request["color"])
	if parsed.has("error"):
		return {"ok": false, "error": parsed["error"]}
	var node: MeshInstance3D = found["node"]
	var material := node.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		return {"ok": false, "error": "\"%s\" has no colour of its own to change" % node.name}
	var before := material.albedo_color
	material.albedo_color = parsed["color"]
	if before != material.albedo_color:
		_undo("colour " + String(node.name), _recolour.bind(String(node.name), before), _recolour.bind(String(node.name), material.albedo_color))
	return {"ok": true, "object": _describe(node)}


func _delete(request: Dictionary) -> Dictionary:
	var found := _find(request)
	if found.has("error"):
		return found
	var node: MeshInstance3D = found["node"]
	var described := _describe(node)
	var node_name := String(node.name)
	var tools := _tools()
	var snapshot: Dictionary = tools.call("thing_snapshot", node_name) if tools and tools.has_method("thing_snapshot") else {}
	_world.remove_child(node)
	node.queue_free()
	if tools and tools.has_method("thing_removed"):
		tools.call("thing_removed", node_name, snapshot, _spawn_request(described).merged({"cmd": "spawn"}), {"cmd": "delete", "name": node_name})
	return {"ok": true, "deleted": described}


# --- Undo (the tools live module, when it's loaded) -----------------------------------

func _tools() -> Node:
	return ctx["modules"].module("tools")


func _undo(label: String, undo: Callable, redo: Callable) -> void:
	var tools := _tools()
	if tools and tools.has_method("push_undo"):
		tools.call("push_undo", label, undo, redo)


func _spawn_request(described: Dictionary) -> Dictionary:
	var out := {"name": described["name"], "shape": described["shape"], "position": described["position"],
		"rotation": described["rotation"], "scale": described["scale"]}
	if described.get("color") != null:
		out["color"] = "#" + str(described["color"])
	return out


func _put(node_name: String, transform: Transform3D) -> void:
	var node := _world.get_node_or_null(NodePath(node_name)) as Node3D
	if node:
		node.transform = transform


func _recolour(node_name: String, color: Color) -> void:
	var node := _world.get_node_or_null(NodePath(node_name)) as MeshInstance3D
	if node and node.get_surface_override_material(0) is StandardMaterial3D:
		(node.get_surface_override_material(0) as StandardMaterial3D).albedo_color = color


# Checks every transform field before changing anything, so a bad field
# leaves the object as it was.
func _apply_transform(node: Node3D, request: Dictionary) -> String:
	var values := {}
	for key in ["position", "rotation", "scale"]:
		if request.has(key):
			var parsed := _vec_in(request[key], key)
			if parsed.has("error"):
				return parsed["error"]
			values[key] = parsed["vec"]
	if values.has("scale"):
		var s: Vector3 = values["scale"]
		if s.x <= 0.0 or s.y <= 0.0 or s.z <= 0.0:
			return "\"scale\" values must all be above 0, got %s" % [_vec_out(s)]
	if values.has("position"):
		node.position = values["position"]
	if values.has("rotation"):
		node.rotation_degrees = values["rotation"]
	if values.has("scale"):
		node.scale = values["scale"]
	return ""


func _find(request: Dictionary) -> Dictionary:
	var node_name = request.get("name")
	if typeof(node_name) != TYPE_STRING or node_name.is_empty():
		return {"ok": false, "error": "missing \"name\" of the object (\"list\" shows them)"}
	var node := _world.get_node_or_null(NodePath(node_name)) as MeshInstance3D
	if node == null:
		return {"ok": false, "error": "no object named \"%s\" (\"list\" shows them)" % node_name}
	return {"node": node}


func _free_name(shape: String) -> String:
	var n := 1
	while _world.has_node(NodePath("%s%d" % [shape, n])):
		n += 1
	return "%s%d" % [shape, n]


func _vec_in(value, key: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return {"error": "\"%s\" must be [x, y, z], got %s" % [key, JSON.stringify(value)]}
	for v in value:
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return {"error": "\"%s\" must be three numbers, got %s" % [key, JSON.stringify(value)]}
		if is_nan(float(v)) or is_inf(float(v)) or absf(float(v)) > 10000.0:
			return {"error": "\"%s\" values must be between -10000 and 10000, got %s" % [key, JSON.stringify(value)]}
	return {"vec": Vector3(value[0], value[1], value[2])}


func _vec_out(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


func _color_in(value) -> Dictionary:
	if typeof(value) != TYPE_STRING:
		return {"error": "\"color\" must be a string like \"#ff8800\" or \"red\", got %s" % JSON.stringify(value)}
	if Color.html_is_valid(value):
		return {"color": Color.html(value)}
	var named := Color.from_string(value, Color(-1, -1, -1))
	if named.r < 0.0:
		return {"error": "unknown color \"%s\" (use \"#rrggbb\" or a name like \"red\")" % value}
	return {"color": named}
