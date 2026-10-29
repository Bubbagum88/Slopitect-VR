extends SlopitectModule

# Slopitect live module: projects.
# A project is a world of its own, a folder in the Slopitect folder's
# projects/: its saves (the save module's world and checkpoints), notes/,
# and project.json (its name, which live modules it uses, and whether it's
# private). Opening a project saves the world you're in, then puts back
# that project's world and loads its modules. Back them up from the PC with
# slopi-backup.ps1, which leaves private projects alone and never takes
# assets/ (downloaded or game-ripped files stay on the headset).

const STATE_PATH := "user://projects.json"
const FIRST := "start"  # the project the old saves/ folder becomes

var _root := ""
var _current := ""
var _attached := false  # joined the save module


func setup() -> String:
	var home := "/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home"
	_root = home + "/projects"
	if DirAccess.make_dir_recursive_absolute(_root) != OK:
		return "projects can't make its folder %s" % _root
	register("projects_list", _list, "every project: name, modules, private, last saved")
	register("projects_current", _current_command, "the project you're in")
	register("projects_new", _new, "make a new, empty project: name; optional modules (live modules it uses), open (true to go to it now)")
	register("projects_open", _open_command, "go to a project: name (your current world is saved first)")
	register("projects_modules", _modules, "set which live modules a project uses (they load when it opens): name, modules [names]")
	register("projects_config", _config, "from the PC only: mark a project private (never backed up) or not: name, private (true/false)")
	_current = _load_current()
	return ""


# Live modules load in no set order, so it joins the save module once that's
# loaded (it checks each frame until then).
func _process(_delta: float) -> void:
	if _attached:
		return
	var save: SlopitectModule = ctx["modules"].module("save")
	if save == null:
		return
	_attached = true
	var home := _root.get_base_dir()
	if _current.is_empty():
		_current = FIRST
		_make(FIRST, [], false)
		# The world saved before projects existed becomes the first project's.
		var old := home + "/saves"
		var into := "%s/%s/saves" % [_root, FIRST]
		if FileAccess.file_exists(old + "/world.json") and not FileAccess.file_exists(into + "/world.json"):
			_remove_tree(into)
			DirAccess.rename_absolute(old, into)
			print("Slopitect projects: the existing saves are now project \"%s\"" % FIRST)
		_store_current()
	if not DirAccess.dir_exists_absolute(_folder(_current)):
		_make(_current, [], false)
	var problem: String = save.call("use_folder", _folder(_current) + "/saves")
	if not problem.is_empty():
		push_error("Slopitect projects: " + problem)
	print("Slopitect projects: in project \"%s\"" % _current)


func _folder(project: String) -> String:
	return "%s/%s" % [_root, project]


func _good_name(project) -> bool:
	if typeof(project) != TYPE_STRING or project.is_empty() or project.length() > 40:
		return false
	for c in project:
		if not (c == "_" or c == "-" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return true


func _info(project: String) -> Dictionary:
	var path := _folder(project) + "/project.json"
	var info = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if typeof(info) != TYPE_DICTIONARY:
		info = {"name": project, "modules": [], "private": false}
	return info


func _write_info(project: String, info: Dictionary) -> String:
	var out := FileAccess.open(_folder(project) + "/project.json", FileAccess.WRITE)
	if out == null:
		return "couldn't write %s/project.json (error %d)" % [_folder(project), FileAccess.get_open_error()]
	out.store_string(JSON.stringify(info, "\t"))
	out.close()
	return ""


func _make(project: String, modules: Array, private: bool) -> String:
	for sub in ["saves/checkpoints", "notes"]:
		if DirAccess.make_dir_recursive_absolute("%s/%s" % [_folder(project), sub]) != OK:
			return "couldn't make %s/%s" % [_folder(project), sub]
	return _write_info(project, {"name": project, "created": Time.get_datetime_string_from_system(true), "modules": modules, "private": private})


func _module_list(value) -> Array:
	if typeof(value) != TYPE_ARRAY or value.size() > 30:
		return []
	for item in value:
		if not _good_name(item):
			return []
	return value


# --- Commands ------------------------------------------------------------------------

func _list(_request: Dictionary) -> Dictionary:
	var listed := []
	for project in DirAccess.get_directories_at(_root):
		if not _good_name(project):
			continue
		var info := _info(project)
		var world := _folder(project) + "/saves/world.json"
		listed.append({"name": project, "modules": info.get("modules", []), "private": info.get("private", false),
			"current": project == _current,
			"last_saved": Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(world)) if FileAccess.file_exists(world) else null})
	return {"ok": true, "projects": listed}


func _current_command(_request: Dictionary) -> Dictionary:
	var info := _info(_current)
	return {"ok": true, "name": _current, "folder": _folder(_current), "modules": info.get("modules", []), "private": info.get("private", false)}


func _new(request: Dictionary) -> Dictionary:
	var project = request.get("name")
	if not _good_name(project):
		return {"ok": false, "error": "\"name\" must be 1 to 40 letters, digits, - or _"}
	if DirAccess.dir_exists_absolute(_folder(project)):
		return {"ok": false, "error": "a project named \"%s\" already exists" % project}
	var modules := _module_list(request.get("modules", []))
	if request.has("modules") and modules.is_empty() and not (request["modules"] is Array and request["modules"].is_empty()):
		return {"ok": false, "error": "\"modules\" must be a list of live module names"}
	var problem := _make(project, modules, false)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	print("Slopitect projects: made \"%s\"" % project)
	if request.get("open", false) == true:
		return _open(project)
	return {"ok": true, "made": project}


func _open_command(request: Dictionary) -> Dictionary:
	var project = request.get("name")
	if not _good_name(project) or not DirAccess.dir_exists_absolute(_folder(project)):
		return {"ok": false, "error": "no project named %s (projects_list shows them)" % JSON.stringify(project)}
	return _open(project)


func _open(project: String) -> Dictionary:
	var save: SlopitectModule = ctx["modules"].module("save")
	if save == null or not _attached:
		return {"ok": false, "error": "the save module isn't loaded, so projects can't switch worlds"}
	# Its modules first, so the world's parts that need them go straight back.
	var loaded := []
	var waiting := []
	for module_name in _info(project).get("modules", []):
		if ctx["modules"].module(module_name) != null:
			continue
		var reply: Dictionary = ctx["server"].run({"cmd": "code_load", "name": module_name})
		if reply.get("wait") is SlopitectPending:
			waiting.append(module_name)  # waits for your Yes; its parts of the world follow once it loads
		elif reply.get("ok", false):
			loaded.append(module_name)
		else:
			push_error("Slopitect projects: %s didn't load: %s" % [module_name, reply.get("error")])
	var problem: String = save.call("use_folder", _folder(project) + "/saves")
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	_current = project
	_store_current()
	print("Slopitect projects: opened \"%s\"" % project)
	return {"ok": true, "opened": project, "modules_loaded": loaded, "modules_waiting_for_yes": waiting}


func _modules(request: Dictionary) -> Dictionary:
	var project = request.get("name")
	if not _good_name(project) or not DirAccess.dir_exists_absolute(_folder(project)):
		return {"ok": false, "error": "no project named %s" % JSON.stringify(project)}
	var modules := _module_list(request.get("modules"))
	if modules.is_empty() and not (request.get("modules") is Array and request["modules"].is_empty()):
		return {"ok": false, "error": "\"modules\" must be a list of live module names"}
	var info := _info(project)
	info["modules"] = modules
	var problem := _write_info(project, info)
	return {"ok": problem.is_empty(), "name": project, "modules": modules, "error": problem}


func _config(request: Dictionary) -> Dictionary:
	var project = request.get("name")
	if not _good_name(project) or not DirAccess.dir_exists_absolute(_folder(project)):
		return {"ok": false, "error": "no project named %s" % JSON.stringify(project)}
	if typeof(request.get("private")) != TYPE_BOOL:
		return {"ok": false, "error": "\"private\" must be true or false"}
	var info := _info(project)
	info["private"] = request["private"]
	var problem := _write_info(project, info)
	return {"ok": problem.is_empty(), "name": project, "private": info["private"], "error": problem}


# --- Which project you're in ---------------------------------------------------------

func _load_current() -> String:
	if not FileAccess.file_exists(STATE_PATH):
		return ""
	var state = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	if typeof(state) == TYPE_DICTIONARY and _good_name(state.get("current")):
		return state["current"]
	return ""


func _store_current() -> void:
	var out := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if out:
		out.store_string(JSON.stringify({"current": _current}))
		out.close()


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path + "/" + sub)
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + file)
	DirAccess.remove_absolute(path)
