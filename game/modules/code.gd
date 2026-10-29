extends SlopitectModule

# Slopitect: new code while the app runs.
# A live module is a GDScript file in the Slopitect folder's modules/ folder
# (/sdcard/Slopitect/modules/NAME.gd on the headset), written by you, the
# agent (files_write) or the PC. It works like the built-in modules: it
# extends SlopitectModule, gets the same ctx and registers commands.
#
# Code can do anything the app can, so it never loads without your Yes in
# the headset: code_load shows the code beside the question, with what it
# uses (files, the internet, other programs...). The Yes is for that exact
# file: its fingerprint (SHA-256) is kept, so at the next start an approved
# module loads by itself, and a module whose file changed since waits for a
# new Yes. Nothing in a file is compiled before its Yes, since compiling a
# script already runs some of it. If it then doesn't compile, the error goes
# back to whoever wrote it, and the fixed file needs a new Yes.

const SETTINGS_PATH := "user://code.json"
const REVIEW_PANEL := "code_review"
const MAX_SOURCE := 200000
const SHOWN_CHARS := 1800
# What a module's code uses, shown with the question. A hint for you, not a
# lock: code can reach the same things in other ways.
const USES := {
	"files": ["FileAccess", "DirAccess", "ResourceLoader", "ResourceSaver", "user://", "/sdcard"],
	"the internet": ["HTTPRequest", "HTTPClient", "StreamPeerTCP", "TCPServer", "PacketPeerUDP", "WebSocketPeer", "ENetConnection"],
	"other programs": ["OS.execute", "OS.create_process", "OS.shell_open", "OS.kill", "JavaClassWrapper", "JNISingleton"],
	"other modules' insides": ["get_node(", "get_parent(", "get_tree(", "ctx[\"modules\"]", "Engine.get_singleton"],
	"the app's settings and keys": ["api_key", "_key\"", "agent.json", "voice.json", "settings[", "module(\"agent\")"],
	"the microphone": ["AudioStreamMicrophone", "AudioEffectRecord"],
}

var _approved := {}  # module name -> SHA-256 of the file you said Yes to
var _errors := {}  # module name -> what went wrong last time
var _confirm: SlopitectModule
var _capture: _ErrorCapture


# Catches the engine's error messages while a script compiles, so the reason
# a module didn't compile can be told to whoever wrote it.
class _ErrorCapture extends Logger:
	var lines := PackedStringArray()
	var active := false
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		if active and lines.size() < 20:
			# A script compiled from text has no file of its own, so only its line means anything.
			lines.append("%s (line %d)" % [rationale if not rationale.is_empty() else code, line])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var taken := lines
		lines = PackedStringArray()
		_mutex.unlock()
		return taken


func setup() -> String:
	_confirm = ctx["modules"].module("confirm")
	if _confirm == null:
		return "code needs the confirm module (for your Yes on new code); list \"confirm\" before \"code\" in modules.json"
	_capture = _ErrorCapture.new()
	OS.add_logger(_capture)
	_load_settings()

	register("code_list", _list, "the live modules in the Slopitect folder's modules/ folder: loaded, approved, changed since, last error")
	register("code_load", _load_command, "load (or reload) a live module from modules/NAME.gd: name; new or changed code waits for the person's Yes in the headset")
	register("code_unload", _unload_command, "take a live module out: name")
	register("code_forget", _forget_command, "withdraw the Yes for a live module (it's taken out and needs a new Yes to load again): name")
	# The approved ones load once everything else is up.
	_start_approved.call_deferred()
	return ""


func _exit_tree() -> void:
	if _capture:
		OS.remove_logger(_capture)


# Whether a loaded module is a live one you approved (the agent may use its
# commands).
func is_live(module_name: String) -> bool:
	return _approved.has(module_name) and ctx["modules"].module(module_name) != null


func _folder() -> String:
	var files: SlopitectModule = ctx["modules"].module("files")
	var home: String = files.get("_home") if files else ""
	if home.is_empty():
		home = "/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home"
	return home + "/modules"


func _path(module_name: String) -> String:
	return _folder() + "/" + module_name + ".gd"


func _start_approved() -> void:
	for module_name in _approved:
		var path := _path(module_name)
		if not FileAccess.file_exists(path):
			_errors[module_name] = "its file %s is gone" % path
			continue
		if FileAccess.get_sha256(path) != _approved[module_name]:
			_errors[module_name] = "its file changed since you said Yes, so it waits for code_load and a new Yes"
			print("Slopitect code: \"%s\" changed since it was approved; not loaded" % module_name)
			continue
		var reply := _load_now(module_name, _approved[module_name])
		print("Slopitect code: \"%s\" %s" % [module_name, "loaded" if reply["ok"] else "failed: " + reply["error"]])


# --- Commands -------------------------------------------------------------------

func _list(_request: Dictionary) -> Dictionary:
	var found := {}
	var dir := DirAccess.open(_folder())
	if dir:
		for file in dir.get_files():
			if file.ends_with(".gd"):
				found[file.get_basename()] = true
	for module_name in _approved:
		found[module_name] = true
	var listed := []
	for module_name in found:
		var path := _path(module_name)
		var exists := FileAccess.file_exists(path)
		listed.append({
			"name": module_name,
			"file": path if exists else "(gone)",
			"loaded": ctx["modules"].module(module_name) != null,
			"approved": _approved.has(module_name),
			"changed_since_approved": _approved.has(module_name) and exists and FileAccess.get_sha256(path) != _approved[module_name],
			"error": _errors.get(module_name, ""),
		})
	return {"ok": true, "folder": _folder(), "modules": listed}


func _load_command(request: Dictionary) -> Dictionary:
	var read := _read(request.get("name"))
	if read.has("error"):
		return {"ok": false, "error": read["error"]}
	var module_name: String = read["name"]
	# Not even compiled before your Yes: compiling a script already runs
	# some of it (its static variables).
	if _approved.get(module_name, "") == read["sha256"]:
		return _load_now(module_name, read["sha256"])  # this exact file already has your Yes
	var uses := _uses(read["source"])
	_show_review(module_name, read["source"])
	var reply: Dictionary = _confirm.ask(
		"Load new code \"%s\"?" % module_name,
		"%d lines. Uses: %s. The code is shown beside this." % [read["source"].count("\n") + 1, ", ".join(uses) if not uses.is_empty() else "nothing listed"],
		func():
			var now := _read(module_name)  # read again: the file may have changed while you looked
			if now.has("error") or now["sha256"] != read["sha256"]:
				return {"ok": false, "error": "the file changed while waiting for the answer; nothing was loaded"}
			_approved[module_name] = read["sha256"]
			_save_settings()
			return _load_now(module_name, read["sha256"]))
	if reply.get("wait") is SlopitectPending:
		(reply["wait"] as SlopitectPending).done.connect(func(_r): _hide_review(), CONNECT_ONE_SHOT)
	else:
		_hide_review()
	return reply


func _unload_command(request: Dictionary) -> Dictionary:
	var module_name = request.get("name")
	if typeof(module_name) != TYPE_STRING or not _approved.has(module_name):
		return {"ok": false, "error": "\"name\" must be a live module (code_list shows them); built-in modules can't be taken out"}
	var problem: String = ctx["modules"].unload(module_name)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	print("Slopitect code: unloaded \"%s\"" % module_name)
	return {"ok": true, "unloaded": module_name}


func _forget_command(request: Dictionary) -> Dictionary:
	var module_name = request.get("name")
	if typeof(module_name) != TYPE_STRING or not _approved.has(module_name):
		return {"ok": false, "error": "\"%s\" has no approval to withdraw" % str(module_name)}
	if ctx["modules"].module(module_name) != null:
		ctx["modules"].unload(module_name)
	_approved.erase(module_name)
	_save_settings()
	return {"ok": true, "forgotten": module_name}


# --- Loading --------------------------------------------------------------------

func _read(module_name) -> Dictionary:
	if typeof(module_name) != TYPE_STRING or not module_name.is_valid_identifier() or module_name.length() > 40:
		return {"error": "\"name\" must be a module name (letters, digits and _, not starting with a digit); its file is modules/NAME.gd"}
	if ctx["modules"].module(module_name) != null and not _approved.has(module_name):
		return {"error": "\"%s\" is a built-in module; pick another name" % module_name}
	var path := _path(module_name)
	if not FileAccess.file_exists(path):
		return {"error": "there's no %s; write it first (files_write with path \"modules/%s.gd\")" % [path, module_name]}
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty() or source.length() > MAX_SOURCE:
		return {"error": "%s is empty or bigger than %d characters" % [path, MAX_SOURCE]}
	return {"name": module_name, "source": source, "sha256": FileAccess.get_sha256(path)}


func _compile(source: String, module_name: String) -> Dictionary:
	var script := GDScript.new()
	script.source_code = source
	# A path of its own, so its errors say which module they came from (the
	# errors module reads it). Nothing is at that path; it's only a name.
	script.take_over_path("user://live-modules/%s.gd" % module_name)
	_capture.take()
	_capture.active = true
	var err := script.reload()
	_capture.active = false
	var said := _capture.take()
	if err != OK or not script.can_instantiate():
		return {"error": "it doesn't compile: %s" % ("; ".join(said) if not said.is_empty() else error_string(err))}
	if script.get_instance_base_type() != &"Node3D":
		return {"error": "it must start with \"extends SlopitectModule\""}
	return {"script": script}


func _load_now(module_name: String, sha256: String) -> Dictionary:
	var read := _read(module_name)
	if read.has("error"):
		return {"ok": false, "error": read["error"]}
	if read["sha256"] != sha256:
		return {"ok": false, "error": "the file isn't the one approved"}
	var compiled := _compile(read["source"], module_name)
	if compiled.has("error"):
		_errors[module_name] = compiled["error"]
		return {"ok": false, "error": compiled["error"]}
	var loader = ctx["modules"]
	if loader.module(module_name) != null:
		loader.unload(module_name)  # a reload: the old one goes first
	_capture.take()
	_capture.active = true
	var problem: String = loader.load_live(module_name, compiled["script"])
	_capture.active = false
	var said := _capture.take()
	if not problem.is_empty():
		if not said.is_empty():
			problem += " (" + "; ".join(said) + ")"
		_errors[module_name] = problem
		return {"ok": false, "error": "it didn't load: " + problem}
	_errors.erase(module_name)
	print("Slopitect code: loaded \"%s\"" % module_name)
	return {"ok": true, "loaded": module_name, "commands": ctx["server"].describe_commands().keys().filter(
		func(cmd): return ctx["server"].describe_commands()[cmd]["module"] == module_name)}


func _uses(source: String) -> Array:
	var uses := []
	for what in USES:
		for word in USES[what]:
			if word in source:
				uses.append(what)
				break
	return uses


# The code to look at while you decide, on a panel beside the question.
func _show_review(module_name: String, source: String) -> void:
	var server: Node = ctx["server"]
	server.run({"cmd": "ui_remove", "id_panel": REVIEW_PANEL})
	var shown := source.left(SHOWN_CHARS) + ("\n... (%d more characters)" % (source.length() - SHOWN_CHARS) if source.length() > SHOWN_CHARS else "")
	server.run({"cmd": "ui_add", "id_panel": REVIEW_PANEL, "title": "Code: " + module_name, "place": "front",
		"distance": 0.8, "height": 0.25, "size": [0.95, 0.75], "color": "#0b0d11",
		"elements": [
			{"type": "text", "id": "title", "at": [0, 0.36], "width": 0.9, "font_size": 32, "color": "#ffcc1a", "text": "Code waiting for your Yes: modules/%s.gd" % module_name},
			{"type": "text", "id": "code", "at": [0, 0.31], "width": 0.9, "font_size": 22, "mono": true, "color": "#d0d0d0", "text": shown},
		]})
	server.run({"cmd": "ui_show", "id_panel": REVIEW_PANEL, "visible": true})


func _hide_review() -> void:
	ctx["server"].run({"cmd": "ui_remove", "id_panel": REVIEW_PANEL})


# --- Saving ---------------------------------------------------------------------

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(SETTINGS_PATH)) != OK or typeof(json.data) != TYPE_DICTIONARY \
			or typeof(json.data.get("approved")) != TYPE_DICTIONARY:
		DirAccess.rename_absolute(SETTINGS_PATH, SETTINGS_PATH + ".bad")
		push_error("Slopitect code: %s is broken; kept it as %s, and no live module is approved" % [SETTINGS_PATH, SETTINGS_PATH + ".bad"])
		return
	for module_name in json.data["approved"]:
		var sha = json.data["approved"][module_name]
		if typeof(module_name) == TYPE_STRING and module_name.is_valid_identifier() and typeof(sha) == TYPE_STRING and sha.length() == 64:
			_approved[module_name] = sha


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Slopitect code: could not save %s (%s)" % [SETTINGS_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({"approved": _approved}, "  "))
	file.close()
