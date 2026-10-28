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
#
# The server is only a switchboard: apart from ping, help and modules, every
# command belongs to a module (game/modules/), which registers it at start.

const PORT := 7777
const BIND_ADDRESS := "127.0.0.1"
const MAX_LINE_BYTES := 65536


var _server := TCPServer.new()
var _clients: Array[StreamPeerTCP] = []
var _buffers := {}  # StreamPeerTCP -> PackedByteArray of a partly received line
var _commands := {}  # cmd -> {"module": String, "call": Callable, "summary": String}


func _ready() -> void:
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


# --- The command registry ---------------------------------------------------

func register(module: String, cmd: String, call: Callable, summary: String) -> String:
	if cmd in ["ping", "help", "modules"]:
		return "\"%s\" is built into the server" % cmd
	if _commands.has(cmd):
		return "\"%s\" is already registered by module \"%s\"" % [cmd, _commands[cmd]["module"]]
	_commands[cmd] = {"module": module, "call": call, "summary": summary}
	return ""


func unregister_module(module: String) -> void:
	for cmd in _commands.keys():
		if _commands[cmd]["module"] == module:
			_commands.erase(cmd)


func commands() -> PackedStringArray:
	var names := PackedStringArray(["ping", "help", "modules"])
	names.append_array(PackedStringArray(_commands.keys()))
	return names


func run(request: Dictionary) -> Dictionary:
	var cmd = request.get("cmd")
	if typeof(cmd) != TYPE_STRING:
		return {"ok": false, "error": "missing \"cmd\" (\"help\" lists them)"}
	match cmd:
		"ping":
			return {"ok": true, "reply": "pong"}
		"help":
			var listed := {}
			for name in _commands:
				listed[name] = "%s (module %s)" % [_commands[name]["summary"], _commands[name]["module"]]
			return {"ok": true, "commands": listed}
		"modules":
			return {"ok": true, "modules": get_node("../Modules").describe()}
	if not _commands.has(cmd):
		return {"ok": false, "error": "unknown cmd \"%s\" (one of: %s)" % [cmd, ", ".join(commands())]}
	var reply = _commands[cmd]["call"].call(request)
	if typeof(reply) != TYPE_DICTIONARY or not reply.has("ok"):
		return {"ok": false, "error": "module \"%s\" gave no proper reply to \"%s\"" % [_commands[cmd]["module"], cmd]}
	return reply
