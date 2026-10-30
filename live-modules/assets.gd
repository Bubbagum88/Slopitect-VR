extends SlopitectModule

# Slopitect live module: assets.
# 3D models from Poly Haven (polyhaven.com, every asset CC0), downloaded to
# the Slopitect folder and placed in the world. Powered by Poly Haven.
#
# What it may reach is fixed in this file, so changing it means a changed
# file and a new Yes in the headset:
# - only https, and only the hosts in HOSTS;
# - nothing about you is sent: no key, no cookies, no names, only the
#   User-Agent Poly Haven asks apps to send;
# - each file must be the size Poly Haven lists and match its MD5, and an
#   asset over MAX_ASSET_BYTES isn't downloaded at all;
# - files are written only under the Slopitect folder's assets/polyhaven/.
#
# Downloaded models stay on the headset (assets/polyhaven/ID/RES/) with a
# credits.json of who made them. Placed models aren't saved yet: they're
# gone when the app closes, the files stay.

# A model was put in the world (assets_place, an undo or a world put back).
signal placed(node_name: String, id: String)

const HOSTS := ["api.polyhaven.com", "dl.polyhaven.org"]
const USER_AGENT := "Slopitect/0.1"
const LIST_URL := "https://api.polyhaven.com/assets?t=models"
const FILES_URL := "https://api.polyhaven.com/files/%s"
const RESOLUTIONS := ["1k", "2k", "4k"]  # texture size; 1k is kindest to the Quest 1
const MAX_ASSET_BYTES := 80 * 1024 * 1024
const MAX_LIST_BYTES := 8 * 1024 * 1024  # the whole models list
const LIST_KEEP_SECONDS := 24 * 3600
const MAX_RESULTS := 20

var _home := ""
var _http: HTTPRequest
var _list := {}  # Poly Haven's models list, id -> info
var _list_time := 0.0  # unix time it was fetched
var _job := {}  # the download in progress: {id, res, files: [[rel, url, size, md5]], done, bytes, total}
var _queue: Array = []  # [id, res] waiting their turn
var _last_error := ""
var _log: Array = []  # recent events, newest last
var _placed := {}  # node name -> {id, res}
var _holder: Node3D
var _fetching := false  # one request at a time
var _lib: SlopitectModule


func setup() -> String:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 60.0
	add_child(_http)
	_holder = Node3D.new()
	_holder.name = "PolyHaven"
	ctx["world"].add_child(_holder)

	register("assets_search", _search, "find Poly Haven models (CC0): query (words), optional category; gives id, name, size in metres, polycount")
	register("assets_get", _get_model, "download a model: id, optional resolution (%s, default 1k); runs in the background, assets_status shows it" % ", ".join(RESOLUTIONS))
	register("assets_status", _status, "the download in progress, the queue, the last error, recent events")
	register("assets_downloaded", _downloaded, "the models on the headset, with their resolutions and credits")
	register("assets_place", _place, "place a downloaded model: id, optional resolution, name, position, rotation (degrees), scale")
	register("assets_move", _move, "move a placed model: name, and any of position, rotation, scale")
	register("assets_remove", _remove, "take a placed model out of the world (its files stay): name")
	register("assets_placed", _placed_list, "the placed models: name, id, position, rotation, scale")
	return ""


# Its folder is in the Slopitect folder (lib.home()); downloading and
# placing wait for lib.
func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		return
	var folder: String = lib.home() + "/assets/polyhaven"
	var made := DirAccess.make_dir_recursive_absolute(folder)
	if made != OK:
		push_error("Slopitect assets: can't make its folder %s (error %d; does the app have storage permission? files_status shows it)" % [folder, made])
		return
	_home = folder
	print("Slopitect assets: models go in %s (powered by Poly Haven)" % _home)


func _waiting() -> Dictionary:
	return {"ok": false, "error": "assets is waiting for the lib module (load lib.gd)"}


func _exit_tree() -> void:
	if _holder and is_instance_valid(_holder):
		_holder.queue_free()


# --- Requests ------------------------------------------------------------------------

# Every request goes through here, so nothing reaches a host not in HOSTS.
func _allowed(url: String) -> bool:
	for host in HOSTS:
		if url.begins_with("https://%s/" % host):
			return true
	return false


# One request at a time; returns [error text or "", body]. With a path, the
# body goes straight to that file and the returned body is empty.
func _fetch(url: String, limit: int, path := "") -> Array:
	if not _allowed(url):
		return ["refused %s: only %s are allowed" % [url, ", ".join(HOSTS)], PackedByteArray()]
	if _fetching:
		return ["another request is still running", PackedByteArray()]
	_http.body_size_limit = limit
	_http.download_file = path
	var started := _http.request(url, ["User-Agent: " + USER_AGENT, "Accept: application/json"])
	if started != OK:
		return ["couldn't start the request to %s (error %d)" % [url, started], PackedByteArray()]
	_fetching = true
	var reply: Array = await _http.request_completed
	_fetching = false
	var result: int = reply[0]
	var code: int = reply[1]
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return ["%s was bigger than the %d bytes allowed" % [url, limit], PackedByteArray()]
	if result != HTTPRequest.RESULT_SUCCESS:
		return ["%s failed (HTTPRequest result %d; 3 = no connection, 4 = TLS, 13 = timeout)" % [url, result], PackedByteArray()]
	if code != 200:
		return ["%s answered HTTP %d" % [url, code], PackedByteArray()]
	return ["", reply[3]]


func _fail(problem: String) -> void:
	_last_error = problem
	_note("ERROR: " + problem)
	push_error("Slopitect assets: " + problem)


func _note(event: String) -> void:
	print("Slopitect assets: ", event)
	_log.append(event.left(300))
	if _log.size() > 20:
		_log.pop_front()


# --- Search --------------------------------------------------------------------------

func _search(request: Dictionary) -> Dictionary:
	var query = request.get("query", "")
	var category = request.get("category", "")
	if typeof(query) != TYPE_STRING or typeof(category) != TYPE_STRING:
		return {"ok": false, "error": "\"query\" and \"category\" must be text"}
	if _list.is_empty() or Time.get_unix_time_from_system() - _list_time > LIST_KEEP_SECONDS:
		if _fetching or not _job.is_empty():
			return {"ok": false, "error": "a download is running; search again when assets_status shows it's done"}
		_load_list()
		return {"ok": true, "loading": true, "note": "fetching Poly Haven's list of models; search again in a few seconds"}
	var words: PackedStringArray = query.to_lower().split(" ", false)
	var found := []
	for id in _list:
		var info: Dictionary = _list[id]
		var categories: Array = info.get("categories", [])
		if not category.is_empty() and not category.to_lower() in categories:
			continue
		var text := " ".join([id, info.get("name", ""), " ".join(info.get("tags", [])), " ".join(categories)]).to_lower()
		var matches := true
		for word in words:
			if not word in text:
				matches = false
				break
		if matches:
			found.append({"id": id, "name": info.get("name", id), "metres": _metres(info), "polycount": int(info.get("polycount", 0))})
	found.sort_custom(func(a, b): return a["polycount"] < b["polycount"])  # lightest first, for the Quest 1
	return {"ok": true, "found": found.size(), "models": found.slice(0, MAX_RESULTS)}


# Poly Haven gives dimensions in millimetres.
func _metres(info: Dictionary) -> Array:
	var d = info.get("dimensions", [])
	if typeof(d) != TYPE_ARRAY or d.size() != 3:
		return []
	return [snappedf(float(d[0]) / 1000.0, 0.01), snappedf(float(d[1]) / 1000.0, 0.01), snappedf(float(d[2]) / 1000.0, 0.01)]


func _load_list() -> void:
	_note("fetching the models list")
	var got: Array = await _fetch(LIST_URL, MAX_LIST_BYTES)
	if not got[0].is_empty():
		_fail(got[0])
		return
	var parsed = JSON.parse_string((got[1] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("Poly Haven's models list wasn't the JSON expected")
		return
	_list = parsed
	_list_time = Time.get_unix_time_from_system()
	_note("the models list has %d models" % _list.size())
	_next_job()


# --- Downloads -----------------------------------------------------------------------

func _good_id(id) -> bool:
	if typeof(id) != TYPE_STRING or id.is_empty() or id.length() > 80:
		return false
	for c in id:
		if not (c == "_" or c == "-" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return true


func _resolution(request: Dictionary) -> String:
	var res = request.get("resolution", "1k")
	return res if typeof(res) == TYPE_STRING and res in RESOLUTIONS else ""


func _get_model(request: Dictionary) -> Dictionary:
	if _home.is_empty():
		return _waiting()
	var id = request.get("id")
	var res := _resolution(request)
	if not _good_id(id):
		return {"ok": false, "error": "\"id\" must be a Poly Haven model id, like \"wooden_table_02\" (assets_search finds them)"}
	if res.is_empty():
		return {"ok": false, "error": "\"resolution\" must be one of %s" % [RESOLUTIONS]}
	if FileAccess.file_exists(_gltf_path(id, res)):
		return {"ok": true, "already": true, "note": "already downloaded; assets_place puts it in the world"}
	for waiting in _queue:
		if waiting == [id, res]:
			return {"ok": true, "queued": true}
	if not _job.is_empty() and _job["id"] == id and _job["res"] == res:
		return {"ok": true, "downloading": true}
	_queue.append([id, res])
	_next_job()
	return {"ok": true, "started": true, "note": "assets_status shows the progress"}


func _next_job() -> void:
	if not _job.is_empty() or _queue.is_empty() or _fetching:
		return
	var next: Array = _queue.pop_front()
	_job = {"id": next[0], "res": next[1], "files": [], "done": 0, "bytes": 0, "total": 0}
	await _download()
	# A failed first download leaves no empty folder behind.
	var id_folder := "%s/%s" % [_home, next[0]]
	if DirAccess.dir_exists_absolute(id_folder) and DirAccess.get_directories_at(id_folder).is_empty() and DirAccess.get_files_at(id_folder).is_empty():
		DirAccess.remove_absolute(id_folder)
	_job = {}
	_next_job()


func _download() -> void:
	var id: String = _job["id"]
	var res: String = _job["res"]
	_note("looking up %s (%s)" % [id, res])
	var got: Array = await _fetch(FILES_URL % id, 1024 * 1024)
	if not got[0].is_empty():
		_fail(got[0])
		return
	var files = JSON.parse_string((got[1] as PackedByteArray).get_string_from_utf8())
	if typeof(files) != TYPE_DICTIONARY or typeof(files.get("gltf")) != TYPE_DICTIONARY:
		_fail("%s has no glTF download (is it a model? assets_search lists models)" % id)
		return
	var entry = files["gltf"].get(res, {}).get("gltf") if typeof(files["gltf"].get(res)) == TYPE_DICTIONARY else null
	if typeof(entry) != TYPE_DICTIONARY:
		_fail("%s has no %s glTF (it has %s)" % [id, res, files["gltf"].keys()])
		return

	# Check every file before downloading any.
	var list := [[id + ".gltf", entry.get("url"), entry.get("size"), entry.get("md5")]]
	var include = entry.get("include", {})
	if typeof(include) != TYPE_DICTIONARY:
		_fail("%s's file list wasn't the shape expected" % id)
		return
	for rel in include:
		var part = include[rel]
		if typeof(part) != TYPE_DICTIONARY:
			_fail("%s's file list wasn't the shape expected" % id)
			return
		list.append([rel, part.get("url"), part.get("size"), part.get("md5")])
	var total := 0
	for file in list:
		if not _good_relative(file[0]) or typeof(file[1]) != TYPE_STRING or not _allowed(file[1]) \
				or (typeof(file[2]) != TYPE_INT and typeof(file[2]) != TYPE_FLOAT) or typeof(file[3]) != TYPE_STRING:
			_fail("%s lists a file that isn't allowed: %s" % [id, JSON.stringify(file).left(200)])
			return
		total += int(file[2])
	if total > MAX_ASSET_BYTES:
		_fail("%s at %s is %d MB, over the %d MB allowed; try a smaller resolution" % [id, res, total / 1048576, MAX_ASSET_BYTES / 1048576])
		return
	_job["files"] = list
	_job["total"] = total

	# Into a temporary folder first, so a half download is never mistaken
	# for a whole one.
	var folder := "%s/%s/%s" % [_home, id, res]
	var partial := folder + ".partial"
	_remove_tree(partial)
	for file in list:
		var path: String = partial + "/" + file[0]
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var fetched: Array = await _fetch(file[1], int(file[2]) + 1024, path)
		if not fetched[0].is_empty():
			_fail(fetched[0] + "; nothing was kept")
			_remove_tree(partial)
			return
		var size := -1
		if FileAccess.file_exists(path):
			size = FileAccess.open(path, FileAccess.READ).get_length()
		var problem := ""
		if size != int(file[2]):
			problem = "%s came down as %d bytes, but Poly Haven lists %d" % [file[0], size, int(file[2])]
		elif FileAccess.get_md5(path) != file[3]:
			problem = "%s's MD5 is %s, but Poly Haven lists %s" % [file[0], FileAccess.get_md5(path), file[3]]
		if not problem.is_empty():
			_fail(problem + "; nothing was kept")
			_remove_tree(partial)
			return
		_job["done"] += 1
		_job["bytes"] += size

	var info: Dictionary = _list.get(id, {})
	var credits := {"source": "https://polyhaven.com/a/" + id, "licence": "CC0", "name": info.get("name", id),
		"authors": (info.get("authors", {}) as Dictionary).keys() if typeof(info.get("authors")) == TYPE_DICTIONARY else [],
		"resolution": res, "downloaded": Time.get_datetime_string_from_system(true)}
	var out := FileAccess.open(partial + "/credits.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(credits, "\t"))
	out.close()
	_remove_tree(folder)
	var moved := DirAccess.rename_absolute(partial, folder)
	if moved != OK:
		_fail("couldn't move %s into place (error %d)" % [partial, moved])
		return
	_note("downloaded %s (%s, %d files, %.1f MB)" % [id, res, list.size(), total / 1048576.0])


# A path inside the asset's folder: no "..", no leading /, plain characters.
func _good_relative(rel) -> bool:
	if typeof(rel) != TYPE_STRING or rel.is_empty() or rel.length() > 200 or rel.begins_with("/"):
		return false
	for part in rel.split("/"):
		if part.is_empty() or part == "." or part == "..":
			return false
	for c in rel:
		if not (c in "_-./" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return true


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	for sub in dir.get_directories():
		_remove_tree(path + "/" + sub)
	for file in dir.get_files():
		DirAccess.remove_absolute(path + "/" + file)
	DirAccess.remove_absolute(path)


func _status(_request: Dictionary) -> Dictionary:
	var job := {}
	if not _job.is_empty():
		job = {"id": _job["id"], "resolution": _job["res"], "files": "%d of %d" % [_job["done"], _job["files"].size()],
			"mb": "%.1f of %.1f" % [_job["bytes"] / 1048576.0, _job["total"] / 1048576.0]}
	return {"ok": true, "downloading": job, "queue": _queue.duplicate(), "last_error": _last_error, "events": _log.duplicate(),
		"models_listed": _list.size()}


func _downloaded(_request: Dictionary) -> Dictionary:
	var models := []
	var dir := DirAccess.open(_home)
	if dir == null:
		return {"ok": true, "models": []}
	for id in dir.get_directories():
		var resolutions := []
		var credits = null
		for res in RESOLUTIONS:
			if FileAccess.file_exists(_gltf_path(id, res)):
				resolutions.append(res)
				if credits == null:
					credits = JSON.parse_string(FileAccess.get_file_as_string("%s/%s/%s/credits.json" % [_home, id, res]))
		if not resolutions.is_empty():
			models.append({"id": id, "resolutions": resolutions, "credits": credits})
	return {"ok": true, "models": models}


func _gltf_path(id: String, res: String) -> String:
	return "%s/%s/%s/%s.gltf" % [_home, id, res, id]


# --- Placing -------------------------------------------------------------------------

func _place(request: Dictionary) -> Dictionary:
	if _home.is_empty():
		return _waiting()
	var id = request.get("id")
	if not _good_id(id):
		return {"ok": false, "error": "\"id\" must be a downloaded model's id (assets_downloaded lists them)"}
	var res := _resolution(request)
	if res.is_empty():
		return {"ok": false, "error": "\"resolution\" must be one of %s" % [RESOLUTIONS]}
	var path := _gltf_path(id, res)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "%s isn't downloaded at %s (assets_get downloads it)" % [id, res]}
	var node_name = request.get("name", "")
	if typeof(node_name) != TYPE_STRING:
		return {"ok": false, "error": "\"name\" must be text"}
	if node_name.is_empty():
		var n := 1
		while _holder.has_node(NodePath("%s_%d" % [id, n])):
			n += 1
		node_name = "%s_%d" % [id, n]
	elif node_name.validate_node_name() != node_name or _holder.has_node(NodePath(node_name)):
		return {"ok": false, "error": "\"%s\" is taken or has . : @ / \" %% in it" % node_name}

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var started := Time.get_ticks_msec()
	var loaded := document.append_from_file(path, state)
	if loaded != OK:
		return {"ok": false, "error": "%s couldn't be read (error %d)" % [path, loaded]}
	var scene := document.generate_scene(state) as Node3D
	if scene == null:
		return {"ok": false, "error": "%s has nothing to show" % path}
	scene.name = node_name
	var problem := _transform(scene, request)
	if not problem.is_empty():
		scene.free()
		return {"ok": false, "error": problem}
	_holder.add_child(scene)
	_placed[node_name] = {"id": id, "res": res}
	_note("placed %s as %s (read in %d ms)" % [id, node_name, Time.get_ticks_msec() - started])
	placed.emit(node_name, id)
	var placed := _describe(scene)
	var again := _again(placed)
	var take_away := func():
		ctx["server"].run({"cmd": "assets_remove", "name": node_name})
		var tools: SlopitectModule = _lib.module("tools") if _lib else null
		if tools and tools.has_method("thing_forget"):
			tools.call("thing_forget", node_name)
	_undo("place " + node_name, take_away, ctx["server"].run.bind(again))
	return {"ok": true, "placed": placed}


func _move(request: Dictionary) -> Dictionary:
	var node := _find(request)
	if node == null:
		return {"ok": false, "error": "no placed model named %s (assets_placed lists them)" % JSON.stringify(request.get("name"))}
	var before := node.transform
	var problem := _transform(node, request)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	var after := node.transform
	if not before.is_equal_approx(after):
		var moved_name := String(node.name)
		var put := func(t: Transform3D):
			var again := _holder.get_node_or_null(NodePath(moved_name)) as Node3D
			if again:
				again.transform = t
		_undo("move " + moved_name, put.bind(before), put.bind(after))
	return {"ok": true, "placed": _describe(node)}


func _remove(request: Dictionary) -> Dictionary:
	var node := _find(request)
	if node == null:
		return {"ok": false, "error": "no placed model named %s (assets_placed lists them)" % JSON.stringify(request.get("name"))}
	var node_name := String(node.name)
	var again := _again(_describe(node))
	var tools: SlopitectModule = _lib.module("tools") if _lib else null
	var snapshot: Dictionary = tools.call("thing_snapshot", node_name) if tools and tools.has_method("thing_snapshot") else {}
	_placed.erase(node_name)
	_holder.remove_child(node)  # its name is free at once, for a new model
	node.queue_free()
	if tools and tools.has_method("thing_removed"):
		tools.call("thing_removed", node_name, snapshot, again, {"cmd": "assets_remove", "name": node_name})
	return {"ok": true, "removed": node_name}


# The assets_place that puts a placed model back as it is.
func _again(placed: Dictionary) -> Dictionary:
	return {"cmd": "assets_place", "id": placed["id"], "resolution": placed["resolution"], "name": placed["name"],
		"position": placed["position"], "rotation": placed["rotation"], "scale": placed["scale"]}


func _undo(label: String, undo: Callable, redo: Callable) -> void:
	var tools: SlopitectModule = _lib.module("tools") if _lib else null
	if tools:
		tools.call("push_undo", label, undo, redo)


func _placed_list(_request: Dictionary) -> Dictionary:
	var listed := []
	for child in _holder.get_children():
		listed.append(_describe(child))
	return {"ok": true, "placed": listed}


func _find(request: Dictionary) -> Node3D:
	var node_name = request.get("name")
	if typeof(node_name) != TYPE_STRING or node_name.is_empty() or node_name.validate_node_name() != node_name:
		return null
	return _holder.get_node_or_null(NodePath(node_name)) as Node3D


# Which Poly Haven model a placed model is ("" if it isn't one).
func model_id(node_name: String) -> String:
	return String(_placed.get(node_name, {}).get("id", ""))


func _describe(node: Node3D) -> Dictionary:
	var v := func(x: Vector3): return [snappedf(x.x, 0.001), snappedf(x.y, 0.001), snappedf(x.z, 0.001)]
	var from: Dictionary = _placed.get(String(node.name), {})
	return {"name": String(node.name), "id": from.get("id", "?"), "resolution": from.get("res", "?"),
		"position": v.call(node.position), "rotation": v.call(node.rotation_degrees), "scale": v.call(node.scale)}


# Checks every field before changing anything.
func _transform(node: Node3D, request: Dictionary) -> String:
	var values := {}
	for key in ["position", "rotation", "scale"]:
		if not request.has(key):
			continue
		var value = request[key]
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			if key != "scale":
				return "\"%s\" must be [x, y, z]" % key
			value = [value, value, value]
		if typeof(value) != TYPE_ARRAY or value.size() != 3:
			return "\"%s\" must be [x, y, z]" % key
		for x in value:
			if (typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT) or is_nan(float(x)) or absf(float(x)) > 10000.0:
				return "\"%s\" must be three numbers between -10000 and 10000" % key
		values[key] = Vector3(value[0], value[1], value[2])
	if values.has("scale") and (values["scale"].x <= 0.0 or values["scale"].y <= 0.0 or values["scale"].z <= 0.0):
		return "\"scale\" must be above 0"
	if values.has("position"):
		node.position = values["position"]
	if values.has("rotation"):
		node.rotation_degrees = values["rotation"]
	if values.has("scale"):
		node.scale = values["scale"]
	return ""
