extends SlopitectModule

# Slopitect live module: save.
# Keeps what's built: the shapes (the objects module's) and the placed
# models (the assets module's, if loaded) are saved by themselves to
# saves/world.json in the Slopitect folder whenever they change, and put
# back when the app starts. Checkpoints keep the whole world at a moment,
# the ground (landscape) and paths too, to go back to later; going back is
# one undo in the tools window (if the tools module is loaded).

const CHECK_SECONDS := 5.0  # how often it looks for changes to save
const MAX_CHECKPOINTS := 50
const WAIT_FOR_MODULES_SECONDS := 30.0  # at start, how long it waits for assets to load before putting models back

var _folder := ""
var _last_saved := ""  # what world.json holds, to save only on a change
var _since_check := 0.0
var _pending_assets: Array = []  # placed models from world.json, waiting for the assets module
var _waited := 0.0
var _restoring := false


func setup() -> String:
	_folder = ("/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home") + "/saves"
	var made := DirAccess.make_dir_recursive_absolute(_folder + "/checkpoints")
	if made != OK:
		return "save can't make its folder %s (error %d)" % [_folder, made]
	register("save_status", _status, "what is saved: the world file, its time, how many shapes and models; and the checkpoints")
	register("save_now", _save_command, "save the shapes and models now (it also saves by itself when they change)")
	register("save_checkpoint", _checkpoint, "keep the whole world as it is now (shapes, models, ground, paths): optional label")
	register("save_checkpoints", _list, "the checkpoints, newest last: id, label, when, what's in it")
	register("save_restore", _restore_command, "go back to a checkpoint: checkpoint (its id); one undo")
	register("save_delete", _delete, "delete a checkpoint: checkpoint (its id)")
	_load_world()
	return ""


func _notification(what: int) -> void:
	# The headset can close the app at any time after this.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()


func _exit_tree() -> void:
	_autosave()


func _process(delta: float) -> void:
	if not _pending_assets.is_empty():
		_waited += delta
		if _assets() != null:
			var models := _pending_assets
			_pending_assets = []
			_put_models(models)
		elif _waited > WAIT_FOR_MODULES_SECONDS:
			print("Slopitect save: the assets module didn't load, so %d saved model(s) weren't put back (they stay in world.json until something changes)" % _pending_assets.size())
			_pending_assets = []
		return  # nothing is saved until the saved world is back
	_since_check += delta
	if _since_check >= CHECK_SECONDS:
		_since_check = 0.0
		_autosave()


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


func _assets() -> SlopitectModule:
	return ctx["modules"].module("assets")


# --- What the world is --------------------------------------------------------------

func _shapes() -> Array:
	return _run({"cmd": "list"}).get("objects", [])


func _models() -> Array:
	return _run({"cmd": "assets_placed"}).get("placed", []) if _assets() else []


# The whole world; with everything, also the ground and the paths.
func _snapshot(everything: bool) -> Dictionary:
	var state := {"version": 1, "saved": Time.get_datetime_string_from_system(true), "shapes": _shapes(), "models": _models()}
	if not everything:
		return state
	var landscape: SlopitectModule = ctx["modules"].module("landscape")
	if landscape:
		state["landscape"] = Marshalls.raw_to_base64((landscape.call("get_heights") as PackedFloat32Array).to_byte_array())
	var paths: SlopitectModule = ctx["modules"].module("paths")
	if paths:
		state["paths"] = paths.call("get_paths")
	return state


func _put_back(state: Dictionary) -> PackedStringArray:
	_restoring = true
	var problems := PackedStringArray()
	for shape in _shapes():
		_run({"cmd": "delete", "name": shape["name"]})
	for shape in state.get("shapes", []):
		if typeof(shape) != TYPE_DICTIONARY:
			continue
		var request := {"cmd": "spawn", "name": shape.get("name"), "shape": shape.get("shape"),
			"position": shape.get("position"), "rotation": shape.get("rotation"), "scale": shape.get("scale")}
		if shape.get("color") != null:
			request["color"] = shape["color"]
		var reply := _run(request)
		if not reply.get("ok", false):
			problems.append("shape %s: %s" % [shape.get("name"), reply.get("error")])
	if _assets():
		for model in _models():
			_run({"cmd": "assets_remove", "name": model["name"]})
		problems.append_array(_put_models(state.get("models", [])))
	elif not state.get("models", []).is_empty():
		problems.append("%d model(s) weren't put back: the assets module isn't loaded" % state["models"].size())
	var landscape: SlopitectModule = ctx["modules"].module("landscape")
	if landscape and typeof(state.get("landscape")) == TYPE_STRING:
		landscape.call("set_heights", Marshalls.base64_to_raw(state["landscape"]).to_float32_array())
	var paths: SlopitectModule = ctx["modules"].module("paths")
	if paths and typeof(state.get("paths")) == TYPE_DICTIONARY:
		paths.call("set_paths", state["paths"])
	_restoring = false
	for problem in problems:
		push_error("Slopitect save: " + problem)
	return problems


func _put_models(models: Array) -> PackedStringArray:
	var problems := PackedStringArray()
	for model in models:
		if typeof(model) != TYPE_DICTIONARY:
			continue
		var reply := _run({"cmd": "assets_place", "id": model.get("id"), "resolution": model.get("resolution"), "name": model.get("name"),
			"position": model.get("position"), "rotation": model.get("rotation"), "scale": model.get("scale")})
		if not reply.get("ok", false):
			problems.append("model %s: %s" % [model.get("name"), reply.get("error")])
	return problems


# --- The world file -----------------------------------------------------------------

func _load_world() -> void:
	var path := _folder + "/world.json"
	if not FileAccess.file_exists(path):
		return
	var state = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(state) != TYPE_DICTIONARY:
		push_error("Slopitect save: %s isn't a save; nothing was put back, and it's kept as world.json.bad" % path)
		DirAccess.rename_absolute(path, path + ".bad")
		return
	var models: Array = state.get("models", [])
	state["models"] = []
	var problems := _put_back(state)
	_pending_assets = models  # put back once the assets module has loaded
	_last_saved = _comparable(state.get("shapes", []), models)
	print("Slopitect save: put back %d shape(s); %d model(s) to follow%s" % [state.get("shapes", []).size(), models.size(),
		"" if problems.is_empty() else "; problems: " + "; ".join(problems)])


# Without the time, so the same world compares the same.
func _comparable(shapes: Array, models: Array) -> String:
	return JSON.stringify([shapes, models])


func _autosave() -> void:
	if _restoring or not _pending_assets.is_empty() or _folder.is_empty():
		return
	var state := _snapshot(false)
	var now := _comparable(state["shapes"], state["models"])
	if now == _last_saved:
		return
	var problem := _write(_folder + "/world.json", state)
	if problem.is_empty():
		_last_saved = now
	else:
		push_error("Slopitect save: " + problem)


# Writes to a temporary file first, so a save cut short never replaces a good one.
func _write(path: String, state: Dictionary) -> String:
	var temporary := path + ".writing"
	var out := FileAccess.open(temporary, FileAccess.WRITE)
	if out == null:
		return "couldn't write %s (error %d)" % [temporary, FileAccess.get_open_error()]
	out.store_string(JSON.stringify(state, "\t"))
	out.close()
	var moved := DirAccess.rename_absolute(temporary, path)
	return "" if moved == OK else "couldn't move %s into place (error %d)" % [temporary, moved]


func _save_command(_request: Dictionary) -> Dictionary:
	_last_saved = ""
	_autosave()
	return {"ok": _last_saved != "", "saved": _folder + "/world.json"}


func _status(_request: Dictionary) -> Dictionary:
	var path := _folder + "/world.json"
	var reply := {"ok": true, "world_file": path, "exists": FileAccess.file_exists(path), "checkpoints": _checkpoint_files().size()}
	if reply["exists"]:
		var state = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(state) == TYPE_DICTIONARY:
			reply["saved"] = state.get("saved")
			reply["shapes"] = state.get("shapes", []).size()
			reply["models"] = state.get("models", []).size()
	return reply


# --- Checkpoints --------------------------------------------------------------------

func _checkpoint_files() -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(_folder + "/checkpoints"):
		if file.ends_with(".json"):
			found.append(file)
	found.sort()
	return found


func _checkpoint(request: Dictionary) -> Dictionary:
	var label = request.get("label", "")
	if typeof(label) != TYPE_STRING or label.length() > 60:
		return {"ok": false, "error": "\"label\" must be text of up to 60 characters"}
	var files := _checkpoint_files()
	if files.size() >= MAX_CHECKPOINTS:
		return {"ok": false, "error": "%d checkpoints already; delete one with save_delete first" % MAX_CHECKPOINTS}
	var number := 1
	if not files.is_empty():
		number = int(files[-1].get_slice("-", 0)) + 1
	var id := "%04d" % number
	var state := _snapshot(true)
	state["label"] = label
	var problem := _write("%s/checkpoints/%s-checkpoint.json" % [_folder, id], state)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	print("Slopitect save: checkpoint %s \"%s\"" % [id, label])
	return {"ok": true, "checkpoint": id, "label": label, "shapes": state["shapes"].size(), "models": state["models"].size(),
		"ground": state.has("landscape"), "paths": state.has("paths")}


func _read_checkpoint(id) -> Dictionary:
	if typeof(id) == TYPE_FLOAT or typeof(id) == TYPE_INT:
		id = "%04d" % int(id)
	if typeof(id) == TYPE_STRING and id.is_valid_int() and id.length() < 4 and int(id) > 0:
		id = "%04d" % int(id)  # "3" is checkpoint 0003
	if typeof(id) != TYPE_STRING or not id.is_valid_int() or id.length() != 4:
		return {"error": "\"checkpoint\" must be a checkpoint's id, like \"0003\" (save_checkpoints lists them)"}
	var path := "%s/checkpoints/%s-checkpoint.json" % [_folder, id]
	if not FileAccess.file_exists(path):
		return {"error": "no checkpoint %s (save_checkpoints lists them)" % id}
	var state = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(state) != TYPE_DICTIONARY:
		return {"error": "checkpoint %s isn't readable" % id}
	return {"state": state, "path": path, "id": id}


func _list(_request: Dictionary) -> Dictionary:
	var listed := []
	for file in _checkpoint_files():
		var read := _read_checkpoint(file.get_slice("-", 0))
		if read.has("state"):
			var state: Dictionary = read["state"]
			listed.append({"checkpoint": read["id"], "label": state.get("label", ""), "saved": state.get("saved"),
				"shapes": state.get("shapes", []).size(), "models": state.get("models", []).size(),
				"ground": state.has("landscape"), "paths": state.has("paths")})
	return {"ok": true, "checkpoints": listed}


func _restore_command(request: Dictionary) -> Dictionary:
	var read := _read_checkpoint(request.get("checkpoint"))
	if read.has("error"):
		return {"ok": false, "error": read["error"]}
	var before := _snapshot(true)
	var state: Dictionary = read["state"]
	var problems := _put_back(state)
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		tools.call("push_undo", "go back to checkpoint %s" % read["id"], func(): _put_back(before), func(): _put_back(state))
	_autosave()
	print("Slopitect save: went back to checkpoint %s" % read["id"])
	return {"ok": problems.is_empty(), "checkpoint": read["id"], "label": state.get("label", ""), "problems": problems,
		"error": "; ".join(problems) if not problems.is_empty() else ""}


func _delete(request: Dictionary) -> Dictionary:
	var read := _read_checkpoint(request.get("checkpoint"))
	if read.has("error"):
		return {"ok": false, "error": read["error"]}
	DirAccess.remove_absolute(read["path"])
	return {"ok": true, "deleted": read["id"]}
