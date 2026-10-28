extends SlopitectModule

# Slopitect: files on the headset, for you and the agent.
# The Slopitect folder (/sdcard/Slopitect on the headset) is free to read
# and write: projects, notes, assets the agent fetches. Anything else in
# shared storage (/sdcard) waits for your Yes in the headset every time,
# whoever asks: the agent, a button, or the PC. Some folders are blocked
# outright because they hold personal things (photos, videos, downloads,
# documents, the headset's screenshots) or the app's own settings (which
# hold your API key); only files_config, from the PC, can open one up.
# Nothing outside /sdcard can be reached (that would need root).
#
# Paths are text: "notes/todo.txt" is inside the Slopitect folder; a path
# starting with / is a full path, like "/sdcard/Android/obb".

const SETTINGS_PATH := "user://files.json"
const SHARED := "/sdcard"
const HOME_ON_HEADSET := "/sdcard/Slopitect"
# Personal folders, blocked until you unblock one with files_config.
const PRIVATE := ["/sdcard/DCIM", "/sdcard/Pictures", "/sdcard/Movies", "/sdcard/Music",
	"/sdcard/Download", "/sdcard/Documents", "/sdcard/Recordings", "/sdcard/Oculus"]
const PACKAGE := "io.github.bubbagum88.slopitect"
const STORAGE_PERMISSION := "android.permission.WRITE_EXTERNAL_STORAGE"
const MAX_READ := 1048576  # bytes in one files_read
const MAX_WRITE := 10485760  # bytes in one files_write
const MAX_LIST := 500
const COPY_CHUNK := 4194304  # bytes copied per frame, so a big copy doesn't stall the headset

var _home := ""
var _unblocked: Array = []  # private folders you opened up with files_config
var _confirm: SlopitectModule


func setup() -> String:
	_confirm = ctx["modules"].module("confirm")
	if _confirm == null:
		return "files needs the confirm module (for your Yes on anything outside the Slopitect folder); list \"confirm\" before \"files\" in modules.json"
	# Off the headset (testing on a PC) the Slopitect folder is in the app's
	# data folder, and there's no /sdcard.
	_home = HOME_ON_HEADSET if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home"
	_load_settings()

	register("files_status", _status, "what files can be reached: the Slopitect folder, the storage permission, blocked folders")
	register("files_list", _list, "list a folder: path (default the Slopitect folder)")
	register("files_info", _info, "a file's or folder's size and when it changed: path")
	register("files_read", _read, "read a file: path, optional offset and max_bytes (up to %d); text comes back as text, anything else as base64" % MAX_READ)
	register("files_write", _write, "write a file: path, and text or base64 (up to %d bytes), optional append" % MAX_WRITE)
	register("files_mkdir", _mkdir, "make a folder (and any above it): path")
	register("files_delete", _delete, "delete a file or an empty folder: path")
	register("files_move", _move, "move or rename: from, to")
	register("files_copy", _copy, "copy a file: from, to (big files copy in the background)")
	register("files_config", _config, "from the PC only: unblock or block a private folder: unblock or block (a path)")

	if OS.get_name() == "Android" and not _has_permission():
		print("Slopitect files: no storage permission yet; it's asked for the first time a file outside the app is used")
	else:
		var problem := _make_home()
		if not problem.is_empty():
			push_error("Slopitect files: " + problem)
	print("Slopitect files: the Slopitect folder is %s" % _home)
	return ""


# --- Where a path may go --------------------------------------------------------

# Turns a request's path into a full path and decides what it needs:
# {"path", "access": "free" | "ask"} or {"error"}.
func _resolve(value, field := "path") -> Dictionary:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 1000:
		return {"error": "\"%s\" must be a path, like \"notes/todo.txt\" or \"/sdcard/Android/obb\"" % field}
	var raw: String = value
	if "://" in raw or "\\" in raw or raw.contains(char(0)):
		return {"error": "\"%s\" must be a plain path with / (no res://, user:// or \\)" % field}
	var full := raw if raw.begins_with("/") else _home + "/" + raw
	full = full.simplify_path()
	if ".." in full.split("/"):
		return {"error": "\"%s\" can't go above the top folder with .." % field}
	# /sdcard is the same place as /storage/emulated/0 (and /storage/self/primary).
	for alias in ["/storage/emulated/0", "/storage/self/primary", "/mnt/sdcard"]:
		if _inside(full, alias):
			full = SHARED + full.substr(alias.length())
	# Model files (like the speech-to-text one) are read by native code, which
	# a doctored file could trick, so its folder needs the Yes like outside.
	if _inside(full, _home + "/models"):
		return {"path": full, "access": "ask"}
	if _inside(full, _home):
		return {"path": full, "access": "free"}
	# The app's own data folder holds its settings, including your API key.
	if _inside(full, OS.get_user_data_dir()) or _inside(full, SHARED + "/Android/data/" + PACKAGE):
		return {"error": "%s is the app's own settings (which hold your API key), so it's never reachable this way" % full}
	if not _inside(full, SHARED):
		return {"error": "%s is outside shared storage (%s); reaching it would need root" % [full, SHARED]}
	for folder in PRIVATE:
		if _inside(full, folder) and not _unblocked.any(func(open): return _inside(full, open)):
			return {"error": "%s is in %s, which is blocked because it holds personal things; only files_config from the PC can unblock it" % [full, folder]}
	return {"path": full, "access": "ask"}


# Shared storage ignores letter case, so /sdcard/dcim is DCIM: compare that way.
func _inside(path: String, folder: String) -> bool:
	var p := path.to_lower()
	var f := folder.to_lower().trim_suffix("/")
	return p == f or p.begins_with(f + "/")


# Runs `act` (which returns the reply) at once inside the Slopitect folder;
# elsewhere, only after the person's Yes in the headset.
func _gate(targets: Array, question: String, act: Callable) -> Dictionary:
	var paths := []
	var ask := false
	for target in targets:
		if target.has("error"):
			return {"ok": false, "error": target["error"]}
		paths.append(target["path"])
		ask = ask or target["access"] == "ask"
	var problem := _storage_ready(paths)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	if not ask:
		return act.call()
	return _confirm.ask(question, " -> ".join(paths), act)


# On the headset, shared storage needs the storage permission. Asking shows
# Android's own Allow / Deny window in the headset.
func _storage_ready(paths: Array) -> String:
	if OS.get_name() != "Android":
		for path in paths:
			if _inside(path, SHARED):
				return "this isn't the headset, so there's no %s here" % SHARED
		return _make_home()
	if _has_permission():
		return _make_home()
	OS.request_permission(STORAGE_PERMISSION)
	return "Slopitect doesn't have storage permission yet. Android is asking for it in the headset now: choose Allow, then try again. (From the PC: .\\adb shell pm grant %s %s)" % [PACKAGE, STORAGE_PERMISSION]


func _has_permission() -> bool:
	return OS.get_name() != "Android" or STORAGE_PERMISSION in OS.get_granted_permissions()


func _make_home() -> String:
	if DirAccess.dir_exists_absolute(_home):
		return ""
	var err := DirAccess.make_dir_recursive_absolute(_home)
	if err != OK:
		return "couldn't make the Slopitect folder %s (%s)" % [_home, error_string(err)]
	print("Slopitect files: made the Slopitect folder %s" % _home)
	return ""


# --- Commands -------------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	var home_ok := DirAccess.dir_exists_absolute(_home)
	var writable := false
	if home_ok:
		var probe := _home + "/.write_check"
		var file := FileAccess.open(probe, FileAccess.WRITE)
		if file:
			file.close()
			writable = DirAccess.remove_absolute(probe) == OK
	return {
		"ok": true,
		"home": _home,
		"home_exists": home_ok,
		"home_writable": writable,
		"system": "%s %s" % [OS.get_name(), OS.get_version()],
		"storage_permission": _has_permission(),
		"granted_permissions": Array(OS.get_granted_permissions()) if OS.get_name() == "Android" else [],
		"shared_readable": DirAccess.dir_exists_absolute(SHARED) and DirAccess.open(SHARED) != null,
		"blocked": PRIVATE.filter(func(folder): return not _unblocked.any(func(open): return _inside(folder, open))),
		"unblocked": _unblocked.duplicate(),
		"rules": "inside home: free (but home/models: the person's Yes); elsewhere in %s: the person's Yes in the headset each time; blocked folders: never" % SHARED,
	}


func _list(request: Dictionary) -> Dictionary:
	var target := _resolve(request.get("path", _home))
	return _gate([target], "Let Slopitect see what's in this folder?", func():
		var dir := DirAccess.open(target["path"])
		if dir == null:
			return {"ok": false, "error": "can't open the folder %s (%s)" % [target["path"], error_string(DirAccess.get_open_error())]}
		dir.include_hidden = true
		var folders := Array(dir.get_directories())
		var files := []
		for name in dir.get_files():
			if files.size() >= MAX_LIST:
				break
			files.append({"name": name, "bytes": FileAccess.get_size(target["path"] + "/" + name)})
		return {"ok": true, "path": target["path"], "folders": folders.slice(0, MAX_LIST), "files": files,
			"more": folders.size() > MAX_LIST or dir.get_files().size() > MAX_LIST})


func _info(request: Dictionary) -> Dictionary:
	var target := _resolve(request.get("path"))
	return _gate([target], "Let Slopitect look at this?", func():
		var path: String = target["path"]
		if DirAccess.dir_exists_absolute(path):
			return {"ok": true, "path": path, "kind": "folder"}
		if not FileAccess.file_exists(path):
			return {"ok": false, "error": "%s doesn't exist" % path}
		return {"ok": true, "path": path, "kind": "file", "bytes": FileAccess.get_size(path),
			"modified": Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(path))})


func _read(request: Dictionary) -> Dictionary:
	var target := _resolve(request.get("path"))
	var offset = request.get("offset", 0)
	var limit = request.get("max_bytes", 65536)
	if typeof(offset) not in [TYPE_INT, TYPE_FLOAT] or offset < 0:
		return {"ok": false, "error": "\"offset\" must be 0 or more (bytes)"}
	if typeof(limit) not in [TYPE_INT, TYPE_FLOAT] or limit < 1 or limit > MAX_READ:
		return {"ok": false, "error": "\"max_bytes\" must be 1 to %d" % MAX_READ}
	return _gate([target], "Let Slopitect read this file?", func():
		var file := FileAccess.open(target["path"], FileAccess.READ)
		if file == null:
			return {"ok": false, "error": "can't read %s (%s)" % [target["path"], error_string(FileAccess.get_open_error())]}
		var size := file.get_length()
		file.seek(int(offset))
		var bytes := file.get_buffer(int(limit))
		file.close()
		var reply := {"ok": true, "path": target["path"], "bytes": size, "offset": int(offset), "read": bytes.size(),
			"more": int(offset) + bytes.size() < size}
		# Text if it's valid UTF-8, allowing for a character cut off at the
		# end (then "read" stops before it); anything else is base64.
		for cut in 4:
			var whole := bytes.slice(0, bytes.size() - cut)
			var text := whole.get_string_from_utf8()
			if not whole.is_empty() and text.to_utf8_buffer() == whole and not text.contains(char(0)):
				reply["text"] = text
				reply["read"] = whole.size()
				reply["more"] = int(offset) + whole.size() < size
				return reply
		reply["base64"] = Marshalls.raw_to_base64(bytes)
		return reply)


func _write(request: Dictionary) -> Dictionary:
	var target := _resolve(request.get("path"))
	var bytes: PackedByteArray
	if typeof(request.get("text")) == TYPE_STRING:
		bytes = request["text"].to_utf8_buffer()
	elif typeof(request.get("base64")) == TYPE_STRING:
		bytes = Marshalls.base64_to_raw(request["base64"])
		if bytes.is_empty() and not request["base64"].is_empty():
			return {"ok": false, "error": "\"base64\" isn't valid base64"}
	else:
		return {"ok": false, "error": "files_write needs \"text\" or \"base64\""}
	if bytes.size() > MAX_WRITE:
		return {"ok": false, "error": "that's %d bytes; one files_write takes up to %d" % [bytes.size(), MAX_WRITE]}
	var append = request.get("append", false)
	if typeof(append) != TYPE_BOOL:
		return {"ok": false, "error": "\"append\" must be true or false"}
	return _gate([target], "Let Slopitect %s this file (%d bytes)?" % ["add to" if append else "write", bytes.size()], func():
		var path: String = target["path"]
		var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if err != OK and not DirAccess.dir_exists_absolute(path.get_base_dir()):
			return {"ok": false, "error": "can't make the folder %s (%s)" % [path.get_base_dir(), error_string(err)]}
		var file := FileAccess.open(path, FileAccess.READ_WRITE if append and FileAccess.file_exists(path) else FileAccess.WRITE)
		if file == null:
			return {"ok": false, "error": "can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())]}
		if append:
			file.seek_end()
		file.store_buffer(bytes)
		file.close()
		return {"ok": true, "path": path, "bytes": FileAccess.get_size(path)})


func _mkdir(request: Dictionary) -> Dictionary:
	var target := _resolve(request.get("path"))
	return _gate([target], "Let Slopitect make this folder?", func():
		var err := DirAccess.make_dir_recursive_absolute(target["path"])
		if err != OK:
			return {"ok": false, "error": "can't make %s (%s)" % [target["path"], error_string(err)]}
		return {"ok": true, "path": target["path"]})


func _delete(request: Dictionary) -> Dictionary:
	var target := _resolve(request.get("path"))
	if not target.has("error") and target["path"].to_lower() == _home.to_lower():
		return {"ok": false, "error": "the Slopitect folder itself can't be deleted"}
	return _gate([target], "Let Slopitect DELETE this?", func():
		var path: String = target["path"]
		if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
			return {"ok": false, "error": "%s doesn't exist" % path}
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			return {"ok": false, "error": "can't delete %s (%s; a folder must be empty first)" % [path, error_string(err)]}
		return {"ok": true, "deleted": path})


func _move(request: Dictionary) -> Dictionary:
	var from := _resolve(request.get("from"), "from")
	var to := _resolve(request.get("to"), "to")
	return _gate([from, to], "Let Slopitect move this?", func():
		if FileAccess.file_exists(to["path"]) or DirAccess.dir_exists_absolute(to["path"]):
			return {"ok": false, "error": "%s already exists; delete it first or pick another name" % to["path"]}
		DirAccess.make_dir_recursive_absolute(to["path"].get_base_dir())
		var err := DirAccess.rename_absolute(from["path"], to["path"])
		if err != OK:
			return {"ok": false, "error": "can't move %s to %s (%s)" % [from["path"], to["path"], error_string(err)]}
		return {"ok": true, "from": from["path"], "to": to["path"]})


func _copy(request: Dictionary) -> Dictionary:
	var from := _resolve(request.get("from"), "from")
	var to := _resolve(request.get("to"), "to")
	return _gate([from, to], "Let Slopitect copy this?", func():
		if not FileAccess.file_exists(from["path"]):
			return {"ok": false, "error": "%s isn't a file" % from["path"]}
		if FileAccess.file_exists(to["path"]):
			return {"ok": false, "error": "%s already exists; delete it first or pick another name" % to["path"]}
		var job := SlopitectPending.new()
		_copy_in_steps(from["path"], to["path"], job)
		return {"ok": true, "wait": job})


# Copies a slice each frame, so even a big game file doesn't freeze the view.
func _copy_in_steps(from: String, to: String, job: SlopitectPending) -> void:
	var source := FileAccess.open(from, FileAccess.READ)
	if source == null:
		job.finish({"ok": false, "error": "can't read %s (%s)" % [from, error_string(FileAccess.get_open_error())]})
		return
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	var dest := FileAccess.open(to + ".part", FileAccess.WRITE)
	if dest == null:
		job.finish({"ok": false, "error": "can't write %s (%s)" % [to, error_string(FileAccess.get_open_error())]})
		return
	var size := source.get_length()
	print("Slopitect files: copying %s to %s (%d bytes)" % [from, to, size])
	while source.get_position() < size:
		if job.cancelled:
			break
		dest.store_buffer(source.get_buffer(COPY_CHUNK))
		if dest.get_error() != OK:
			break
		await get_tree().process_frame
	var error := dest.get_error()
	source.close()
	dest.close()
	if job.cancelled or error != OK:
		DirAccess.remove_absolute(to + ".part")
		job.finish({"ok": false, "error": "copy stopped" if job.cancelled else "writing %s failed (%s); is the headset full?" % [to, error_string(error)]})
		return
	DirAccess.rename_absolute(to + ".part", to)
	print("Slopitect files: copied %s" % to)
	job.finish({"ok": true, "from": from, "to": to, "bytes": size})


# From the PC only (the agent can't use *_config commands, and buttons can't
# run them): opens up, or closes again, one of the private folders.
func _config(request: Dictionary) -> Dictionary:
	for key in ["unblock", "block"]:
		if not request.has(key):
			continue
		var path = request[key]
		if typeof(path) != TYPE_STRING or not PRIVATE.any(func(folder): return _inside(path, folder)):
			return {"ok": false, "error": "\"%s\" must be one of the private folders or a folder inside one: %s" % [key, ", ".join(PRIVATE)]}
		path = path.simplify_path()
		if key == "unblock" and not path in _unblocked:
			_unblocked.append(path)
		elif key == "block":
			_unblocked = _unblocked.filter(func(open): return not _inside(open, path))
		_save_settings()
		return {"ok": true, "unblocked": _unblocked.duplicate()}
	return {"ok": true, "unblocked": _unblocked.duplicate(), "private": PRIVATE}


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(SETTINGS_PATH)) != OK or typeof(json.data) != TYPE_DICTIONARY \
			or typeof(json.data.get("unblocked")) != TYPE_ARRAY:
		DirAccess.rename_absolute(SETTINGS_PATH, SETTINGS_PATH + ".bad")
		push_error("Slopitect files: %s is broken; kept it as %s and blocked every private folder" % [SETTINGS_PATH, SETTINGS_PATH + ".bad"])
		return
	for path in json.data["unblocked"]:
		if typeof(path) == TYPE_STRING and PRIVATE.any(func(folder): return _inside(path, folder)):
			_unblocked.append(path)


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Slopitect files: could not save %s (%s)" % [SETTINGS_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({"unblocked": _unblocked}, "  "))
	file.close()
