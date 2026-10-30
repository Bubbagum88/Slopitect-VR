extends SlopitectModule

# Slopitect live module: save.
# Keeps what's built: the shapes (the objects module's), the made shapes'
# recipes (the shapes module's), the placed models
# (the assets module's), the ground (landscape), the paths, the inspect
# tool's switches (hidden, grabbable) and the joints are saved by
# themselves to saves/world.json in the Slopitect folder whenever they
# change, and put back when the app starts. A part whose module isn't
# loaded is kept as it was saved and put back once the module loads.
# Checkpoints keep the whole world at a moment to go back to later; going
# back is one undo in the tools window (if the tools module is loaded).
# A checkpoint also keeps the groups, textures, doors and physics (each of
# those modules keeps its own file per project, so world.json doesn't), and
# deleting a checkpoint is one undo.
# With the projects module, each project has its own saves folder.

const CHECK_SECONDS := 5.0  # how often it looks for changes to save
const MAX_CHECKPOINTS := 50
const SLOW_MS := 4.0  # an autosave slower than this is logged, with where the time went
const PARTS := {"models": "assets", "landscape": "landscape", "paths": "paths", "switches": "inspect", "made": "shapes", "joints": "joints"}  # part -> the module it needs
# In checkpoints only: part -> [module, its getter, its setter].
const CHECKPOINT_PARTS := {"groups": ["multi", "get_grouping", "set_grouping"], "textures": ["textures", "get_textures", "set_textures"],
	"doors": ["doors", "get_doors", "set_doors"], "physics": ["physics", "get_physics", "set_physics"]}

var _folder := ""
var _last_saved := ""  # what world.json holds, to save only on a change
var _since_check := 0.0
var _pending := {}  # part -> its saved value, while its module isn't loaded; kept in every save until it is
var _kept := {}  # part -> its value at the last snapshot, kept if its module is unloaded later
var _restoring := false
var _ground := ""  # the landscape's heights as saved text, made again only when it changes
var _ground_from := 0  # the landscape module's instance id _ground was made from


func setup() -> String:
	var home := "/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home"
	_folder = home + "/saves"
	# In a project (the projects module), start in its folder rather than
	# load the old one and switch.
	var projects = JSON.parse_string(FileAccess.get_file_as_string("user://projects.json")) if FileAccess.file_exists("user://projects.json") else null
	if typeof(projects) == TYPE_DICTIONARY and typeof(projects.get("current")) == TYPE_STRING and projects["current"].is_valid_filename():
		_folder = "%s/projects/%s/saves" % [home, projects["current"]]
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
		_ground = ""
		_autosave()


func _exit_tree() -> void:
	_ground = ""
	_autosave()


func _process(delta: float) -> void:
	for part in _pending.keys():
		if ctx["modules"].module(PARTS[part]) != null:
			var value = _pending[part]
			_pending.erase(part)
			for problem in _put_part(part, value):
				push_error("Slopitect save: " + problem)
			print("Slopitect save: put back the saved %s now that its module is loaded" % part)
	_since_check += delta
	if _since_check >= CHECK_SECONDS:
		_since_check = 0.0
		_autosave()


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


# --- What the world is --------------------------------------------------------------

# The built-in shapes; made ones (the shapes module's) are saved as recipes.
func _shapes(made_too := false) -> Array:
	var world: Node3D = ctx["world"]
	return _run({"cmd": "list"}).get("objects", []).filter(func(shape):
		if made_too:
			return true
		var node := world.get_node_or_null(NodePath(str(shape.get("name", ""))))
		return node == null or not node.get_meta("made", false))


# The whole world, and with checkpoint the parts only checkpoints keep.
func _checkpoint_snapshot() -> Dictionary:
	var state := _snapshot()
	for part in CHECKPOINT_PARTS:
		var spec: Array = CHECKPOINT_PARTS[part]
		var module: SlopitectModule = ctx["modules"].module(spec[0])
		if module and module.has_method(spec[1]):
			state[part] = module.call(spec[1])
	return state


# The whole world. A part whose module isn't loaded is the one last saved.
func _snapshot() -> Dictionary:
	var state := {"version": 2, "saved": Time.get_datetime_string_from_system(true), "shapes": _shapes()}
	for part in PARTS:
		var module: SlopitectModule = ctx["modules"].module(PARTS[part])
		if module == null:
			if _pending.has(part):
				state[part] = _pending[part]
			elif _kept.has(part):
				state[part] = _kept[part]  # unloaded since: kept until it's back
			continue
		match part:
			"models":
				state["models"] = _run({"cmd": "assets_placed"}).get("placed", [])
			"landscape":
				state["landscape"] = _ground_text(module)
			"paths":
				state["paths"] = module.call("get_paths")
			"switches":
				state["switches"] = module.call("get_settings")
			"made":
				state["made"] = module.call("get_made")
			"joints":
				state["joints"] = module.call("get_joints")
		_kept[part] = state.get(part)
	return state


# Putting a world back isn't a change to undo: the deletes and spawns in it
# add nothing to the undo list.
func _put_back(state: Dictionary) -> PackedStringArray:
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools and tools.has_method("quiet"):
		return tools.call("quiet", _put_back_now.bind(state))
	return _put_back_now(state)


func _put_back_now(state: Dictionary) -> PackedStringArray:
	_restoring = true
	_pending.clear()
	_kept.clear()
	var problems := PackedStringArray()
	for shape in _shapes(true):
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
	for part in PARTS:
		if not state.has(part):
			continue
		if ctx["modules"].module(PARTS[part]) == null:
			_pending[part] = state[part]  # put back when its module loads
		else:
			problems.append_array(_put_part(part, state[part]))
	for part in CHECKPOINT_PARTS:
		var spec: Array = CHECKPOINT_PARTS[part]
		var module: SlopitectModule = ctx["modules"].module(spec[0])
		if state.has(part) and module and module.has_method(spec[2]):
			module.call(spec[2], state[part])
	_restoring = false
	for problem in problems:
		push_error("Slopitect save: " + problem)
	return problems


func _put_part(part: String, value) -> PackedStringArray:
	var module: SlopitectModule = ctx["modules"].module(PARTS[part])
	match part:
		"models":
			for model in _run({"cmd": "assets_placed"}).get("placed", []):
				_run({"cmd": "assets_remove", "name": model["name"]})
			return _put_models(value if typeof(value) == TYPE_ARRAY else [])
		"landscape":
			if typeof(value) == TYPE_STRING:
				module.call("set_heights", Marshalls.base64_to_raw(value).to_float32_array())
		"paths":
			if typeof(value) == TYPE_DICTIONARY:
				module.call("set_paths", value)
		"switches":
			if typeof(value) == TYPE_DICTIONARY:
				module.call("set_settings", value)
		"made":
			if typeof(value) == TYPE_DICTIONARY:
				module.call("set_made", value)
		"joints":
			if typeof(value) == TYPE_DICTIONARY:
				module.call("set_joints", value)
	return PackedStringArray()


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
		_last_saved = ""
		return
	var state = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(state) != TYPE_DICTIONARY:
		push_error("Slopitect save: %s isn't a save; nothing was put back, and it's kept as world.json.bad" % path)
		DirAccess.rename_absolute(path, path + ".bad")
		return
	var problems := _put_back(state)
	_last_saved = _comparable(_snapshot())
	print("Slopitect save: put back %d shape(s) from %s%s%s" % [state.get("shapes", []).size(), path,
		"" if _pending.is_empty() else "; waiting for modules to load for: " + ", ".join(_pending.keys()),
		"" if problems.is_empty() else "; problems: " + "; ".join(problems)])


# The ground as text. Its heights aren't turned into text again at every
# check, only when the landscape says it changed (or another landscape
# module is loaded), and before the app closes, for a stroke not finished.
func _ground_text(landscape: SlopitectModule) -> String:
	var id := landscape.get_instance_id()
	if id != _ground_from or _ground.is_empty():
		if not landscape.is_connected("changed", _ground_changed):
			landscape.connect("changed", _ground_changed)
		_ground_from = id
		_ground = Marshalls.raw_to_base64((landscape.call("get_heights") as PackedFloat32Array).to_byte_array())
	return _ground


func _ground_changed() -> void:
	_ground = ""


# Without the time, so the same world compares the same.
func _comparable(state: Dictionary) -> String:
	var copy := state.duplicate()
	copy.erase("saved")
	return JSON.stringify(copy)


func _autosave() -> void:
	if _restoring or _folder.is_empty():
		return
	var started := Time.get_ticks_usec()
	var state := _snapshot()
	var taken := Time.get_ticks_usec()
	var now := _comparable(state)
	var compared := Time.get_ticks_usec()
	var wrote := compared
	if now != _last_saved:
		var problem := _write(_folder + "/world.json", state)
		wrote = Time.get_ticks_usec()
		if problem.is_empty():
			_last_saved = now
		else:
			push_error("Slopitect save: " + problem)
	if (wrote - started) / 1000.0 > SLOW_MS:
		print("Slopitect save: autosave took %.1f ms (snapshot %.1f, compare %.1f, write %s; %d shapes, %.0f KB)" % [
			(wrote - started) / 1000.0, (taken - started) / 1000.0, (compared - taken) / 1000.0,
			"%.1f" % ((wrote - compared) / 1000.0) if wrote != compared else "none, unchanged",
			state.get("shapes", []).size(), now.length() / 1024.0])


# For the projects module: saves this world where it belongs, then switches
# to another folder's world (an empty world if it has none yet).
func use_folder(folder: String) -> String:
	if folder == _folder:
		return ""
	if DirAccess.dir_exists_absolute(_folder):
		_autosave()
	var made := DirAccess.make_dir_recursive_absolute(folder + "/checkpoints")
	if made != OK:
		return "can't make %s (error %d)" % [folder, made]
	_folder = folder
	if FileAccess.file_exists(folder + "/world.json"):
		_load_world()
	else:
		var empty := {"shapes": [], "models": [], "paths": {"paths": {}, "next": 1}}
		var landscape: SlopitectModule = ctx["modules"].module("landscape")
		if landscape:
			var flat := PackedFloat32Array()
			flat.resize((landscape.call("get_heights") as PackedFloat32Array).size())
			empty["landscape"] = Marshalls.raw_to_base64(flat.to_byte_array())
		_put_back(empty)
		_last_saved = ""
		_autosave()
	print("Slopitect save: now saving in %s" % folder)
	return ""


func folder() -> String:
	return _folder


# Writes to a temporary file first, so a save cut short never replaces a good one.
func _write(path: String, state: Dictionary) -> String:
	var temporary := path + ".writing"
	var out := FileAccess.open(temporary, FileAccess.WRITE)
	if out == null:
		return "couldn't write %s (error %d)" % [temporary, FileAccess.get_open_error()]
	out.store_string(JSON.stringify(state))  # no indenting: less to write
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
	var state := _checkpoint_snapshot()
	state["label"] = label
	var problem := _write("%s/checkpoints/%s-checkpoint.json" % [_folder, id], state)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	print("Slopitect save: checkpoint %s \"%s\"" % [id, label])
	return {"ok": true, "checkpoint": id, "label": label, "shapes": state["shapes"].size(), "models": state.get("models", []).size(),
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
	var before := _checkpoint_snapshot()
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
	var path: String = read["path"]
	var kept := FileAccess.get_file_as_string(path)
	DirAccess.remove_absolute(path)
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		var put_back := func():
			var out := FileAccess.open(path, FileAccess.WRITE)
			if out:
				out.store_string(kept)
		tools.call("push_undo", "delete checkpoint %s" % read["id"], put_back, func(): DirAccess.remove_absolute(path))
	return {"ok": true, "deleted": read["id"]}
