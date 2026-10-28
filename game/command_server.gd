extends Node

# Slopitect, step 3: a command server.
# Listens on the headset's own loopback address, so only adb (or something
# running on the headset) can reach it, not the rest of the network. On the
# PC: `.\adb forward tcp:7777 tcp:7777`, then connect to localhost:7777.
#
# One JSON object per line in, one JSON object per line out. Every reply has
# "ok"; a failure also has "error" saying exactly what was wrong. The reply
# echoes the request's "id" if it had one. Every command and its result is
# logged with "Slopitect cmd:".

const PORT := 7777
const BIND_ADDRESS := "127.0.0.1"
const MAX_LINE_BYTES := 65536
const SHAPES := ["box", "sphere", "cylinder", "capsule"]

@export var world_path: NodePath

var _server := TCPServer.new()
var _clients: Array[StreamPeerTCP] = []
var _buffers := {}  # StreamPeerTCP -> PackedByteArray of a partly received line
var _world: Node3D


func _ready() -> void:
	_world = get_node(world_path)
	var err := _server.listen(PORT, BIND_ADDRESS)
	if err != OK:
		push_error("Slopitect cmd: could not listen on %s:%d (%s)" % [BIND_ADDRESS, PORT, error_string(err)])
		return
	print("Slopitect cmd: listening on %s:%d" % [BIND_ADDRESS, PORT])


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		_clients.append(peer)
		_buffers[peer] = PackedByteArray()
		print("Slopitect cmd: client connected from %s:%d" % [peer.get_connected_host(), peer.get_connected_port()])

	for peer: StreamPeerTCP in _clients.duplicate():
		peer.poll()
		var status := peer.get_status()
		if status != StreamPeerTCP.STATUS_CONNECTED:
			print("Slopitect cmd: client disconnected (status %d)" % status)
			_clients.erase(peer)
			_buffers.erase(peer)
			continue
		var available := peer.get_available_bytes()
		if available <= 0:
			continue
		var got := peer.get_data(available)
		if got[0] != OK:
			print("Slopitect cmd: read failed (%s), dropping client" % error_string(got[0]))
			peer.disconnect_from_host()
			continue
		var buffer: PackedByteArray = _buffers[peer] + got[1]
		var newline := buffer.find(10)
		while newline != -1:
			var line := buffer.slice(0, newline).get_string_from_utf8().strip_edges()
			buffer = buffer.slice(newline + 1)
			if not line.is_empty():
				_reply(peer, handle_line(line))
			newline = buffer.find(10)
		if buffer.size() > MAX_LINE_BYTES:
			_reply(peer, {"ok": false, "error": "line longer than %d bytes without a newline; dropped it" % MAX_LINE_BYTES})
			buffer = PackedByteArray()
		_buffers[peer] = buffer


func _reply(peer: StreamPeerTCP, reply: Dictionary) -> void:
	peer.put_data((JSON.stringify(reply) + "\n").to_utf8_buffer())


# Parses one line, runs it and returns the reply. Public so tests can call it
# without a socket.
func handle_line(line: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(line) != OK:
		return _log_result(line, {"ok": false, "error": "not valid JSON: %s" % json.get_error_message()})
	if typeof(json.data) != TYPE_DICTIONARY:
		return _log_result(line, {"ok": false, "error": "expected a JSON object like {\"cmd\": \"list\"}"})
	var request: Dictionary = json.data
	var reply := run(request)
	if request.has("id"):
		var id = request["id"]
		# JSON numbers arrive as floats; send 1 back as 1, not 1.0.
		if typeof(id) == TYPE_FLOAT and id == floorf(id) and absf(id) < 1e15:
			id = int(id)
		reply["id"] = id
	return _log_result(line, reply)


func _log_result(line: String, reply: Dictionary) -> Dictionary:
	if reply.get("ok", false):
		print("Slopitect cmd: ", line, " -> ok")
	else:
		print("Slopitect cmd: ", line, " -> FAILED: ", reply.get("error", "?"))
	return reply


func run(request: Dictionary) -> Dictionary:
	var cmd = request.get("cmd")
	if typeof(cmd) != TYPE_STRING:
		return {"ok": false, "error": "missing \"cmd\" (one of: %s)" % ", ".join(_commands())}
	match cmd:
		"ping":
			return {"ok": true, "reply": "pong"}
		"help":
			return {"ok": true, "commands": _commands(), "shapes": SHAPES}
		"list":
			return _list()
		"spawn":
			return _spawn(request)
		"move":
			return _move(request)
		"color":
			return _color(request)
		"delete":
			return _delete(request)
	return {"ok": false, "error": "unknown cmd \"%s\" (one of: %s)" % [cmd, ", ".join(_commands())]}


func _commands() -> PackedStringArray:
	return PackedStringArray(["ping", "help", "list", "spawn", "move", "color", "delete"])


func _list() -> Dictionary:
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
	return {"ok": true, "object": _describe(node)}


func _move(request: Dictionary) -> Dictionary:
	var found := _find(request)
	if found.has("error"):
		return found
	if not (request.has("position") or request.has("rotation") or request.has("scale")):
		return {"ok": false, "error": "move needs at least one of \"position\", \"rotation\", \"scale\""}
	var node: MeshInstance3D = found["node"]
	var transform_error := _apply_transform(node, request)
	if not transform_error.is_empty():
		return {"ok": false, "error": transform_error}
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
	(node.get_surface_override_material(0) as StandardMaterial3D).albedo_color = parsed["color"]
	return {"ok": true, "object": _describe(node)}


func _delete(request: Dictionary) -> Dictionary:
	var found := _find(request)
	if found.has("error"):
		return found
	var node: MeshInstance3D = found["node"]
	var described := _describe(node)
	_world.remove_child(node)
	node.queue_free()
	return {"ok": true, "deleted": described}


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
