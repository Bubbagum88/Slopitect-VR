extends SlopitectModule

# Slopitect live module: paths.
# Roads and trails on the ground. It's a tool in the tools window (the tools
# module): point the right controller at the ground and pull the trigger to
# put down a point, then press Finish. The path is a smooth strip through
# the points that follows the ground (the landscape module's, if loaded, or
# the flat floor). With Flatten on, it also levels the ground under itself.
# A path can wear a texture from the downloads folder (paths_texture, or
# Texture on the settings), tiled every texture_scale metres.
# Each new or deleted path is one undo. Paths are saved in the app's own
# storage (user://paths.json).

const SAVE_PATH := "user://paths.json"
const MAX_PATHS := 100
const MAX_POINTS := 100
const SPACING := 0.2  # metres between the strip's cross-sections
const LIFT := 0.03  # how far above the ground the strip is drawn
const RAY_LENGTH := 15.0
const RAY_STEP := 0.05

var settings := {"width": 1.0, "color": "#8a7a5c", "flatten": true, "texture": "", "texture_scale": 2.0}

var _paths := {}  # id -> {"points": [[x, z]...], "width", "color", "flatten", "texture", "texture_scale"}
var _meshes := {}  # id -> MeshInstance3D
var _textures := {}  # texture path -> Texture2D
var _draft: Array = []  # [[x, z]...] of the path being put down
var _draft_node: Node3D
var _marker: MeshInstance3D
var _selected := false
var _landscape: SlopitectModule
var _lib: SlopitectModule
var _next := 1


func setup() -> String:
	_draft_node = Node3D.new()
	add_child(_draft_node)
	_marker = _ball(Color(1, 1, 1), 0.04)
	_marker.visible = false
	add_child(_marker)
	_load()
	_rebuild_all()

	register("paths_list", _list, "the paths: id, points ([x, z] each), width, colour, flatten, texture, texture_scale")
	register("paths_add", _add_command, "add a path (one undo): points (2 or more [x, z]), optional width (0.2 to 5 m), color, flatten (true levels the ground under it), texture (path under downloads/, or \"\"), texture_scale (m per tile, 0.2 to 20)")
	register("paths_delete", _delete_command, "delete a path (one undo): path (its id)")
	register("paths_settings", _settings_command, "for the next path you put down: any of width (0.2 to 5 m), width_step (1 wider, -1 narrower), color, flatten (true/false), texture (path under downloads/, or \"\"), texture_scale (0.2 to 20 m)")
	register("paths_draft", _draft_command, "the path being put down with the trigger: action finish, cancel or remove_last")
	register("paths_texture", _texture_command, "texture paths that exist (one undo): path (an id) or paths [ids] or all true; texture (path under downloads/, e.g. polyhaven/textures/concrete_floor_worn_001_1k.jpg, or \"\" for none); texture_scale (m per tile, 0.2 to 20, default 2)")
	set_physics_process(false)  # only while it's the chosen tool
	return ""


# The landscape can be loaded, unloaded or changed at any time; paths follow it.
# Textures come from lib's folder, so textured paths are drawn again with lib.
func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		return
	lib.watch(self, "landscape", _landscape_here, _landscape_gone)
	lib.follow(self, "landscape", "changed", _rebuild_all)
	if _paths.values().any(func(path): return not String(path.get("texture", "")).is_empty()):
		_rebuild_all()


func _landscape_here(landscape: SlopitectModule) -> void:
	_landscape = landscape
	_rebuild_all()


func _landscape_gone(_old: SlopitectModule) -> void:
	_landscape = null
	_rebuild_all()


# --- As a tool -----------------------------------------------------------------------

func tool_info() -> Dictionary:
	return {"id": "paths", "label": "Path", "order": 20, "buttons": [
		{"label": "Finish", "action": {"cmd": "paths_draft", "action": "finish"}},
		{"label": "Back a point", "action": {"cmd": "paths_draft", "action": "remove_last"}},
		{"label": "Cancel", "action": {"cmd": "paths_draft", "action": "cancel"}},
		{"label": "Narrower", "action": {"cmd": "paths_settings", "width_step": -1}},
		{"label": "Wider", "action": {"cmd": "paths_settings", "width_step": 1}},
		{"label": "Flatten: " + ("on" if settings["flatten"] else "off"), "action": {"cmd": "paths_settings", "flatten": not settings["flatten"]}},
	], "status": "%d points down; width %.2f m; trigger puts a point" % [_draft.size(), settings["width"]]}


func tool_selected(on: bool) -> void:
	_selected = on
	set_physics_process(on)
	_marker.visible = false


func tool_trigger(down: bool) -> void:
	if not down:
		return
	var hit = _aim()
	if hit == null or _draft.size() >= MAX_POINTS:
		return
	_draft.append([snappedf(hit.x, 0.01), snappedf(hit.z, 0.01)])
	_show_draft()


func _physics_process(_delta: float) -> void:
	if not _selected:
		return
	var hit = _aim()
	_marker.visible = hit != null
	if hit != null:
		_marker.global_position = hit + Vector3(0, 0.04, 0)


# --- Commands ------------------------------------------------------------------------

func _list(_request: Dictionary) -> Dictionary:
	var listed := []
	for id in _paths:
		var path: Dictionary = _paths[id].duplicate(true)
		path["id"] = id
		listed.append(path)
	return {"ok": true, "paths": listed, "draft": _draft.duplicate(true)}


func _add_command(request: Dictionary) -> Dictionary:
	var path := settings.duplicate()
	path["points"] = request.get("points")
	for key in ["width", "color", "flatten", "texture", "texture_scale"]:
		if request.has(key):
			path[key] = request[key]
	var problem := _check(path)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	problem = _texture_problem(path["texture"])
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return {"ok": true, "path": _add(path)}


func _delete_command(request: Dictionary) -> Dictionary:
	var id = request.get("path")
	if not _paths.has(id):
		return {"ok": false, "error": "no path \"%s\" (paths_list shows them)" % str(id)}
	var path: Dictionary = _paths[id]
	_remove(id)
	_undo_entry("delete " + id, _put.bind(id, path, PackedFloat32Array()), _remove.bind(id))
	return {"ok": true, "deleted": id}


func _settings_command(request: Dictionary) -> Dictionary:
	var next := settings.duplicate()
	for key in request:
		if key in ["cmd", "id"]:
			continue
		match key:
			"width", "color", "flatten", "texture", "texture_scale":
				next[key] = request[key]
			"width_step":
				if typeof(request[key]) not in [TYPE_INT, TYPE_FLOAT] or request[key] == 0:
					return {"ok": false, "error": "\"width_step\" must be 1 (wider) or -1 (narrower)"}
				next["width"] = snappedf(clampf(next["width"] * (1.25 if request[key] > 0 else 0.8), 0.2, 5.0), 0.01)
			_:
				return {"ok": false, "error": "unknown field \"%s\" (width, width_step, color, flatten, texture, texture_scale)" % key}
	next["points"] = [[0, 0], [1, 0]]
	var problem := _check(next)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	problem = _texture_problem(next["texture"])
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	next.erase("points")
	settings = next
	_show_draft()
	return {"ok": true, "settings": settings.duplicate()}


func _draft_command(request: Dictionary) -> Dictionary:
	match request.get("action"):
		"finish":
			if _draft.size() < 2:
				return {"ok": false, "error": "a path needs at least 2 points; %d down so far" % _draft.size()}
			var path := settings.duplicate()
			path["points"] = _draft.duplicate(true)
			_draft.clear()
			_show_draft()
			return {"ok": true, "path": _add(path)}
		"cancel":
			_draft.clear()
		"remove_last":
			if _draft.is_empty():
				return {"ok": false, "error": "no points down"}
			_draft.pop_back()
		_:
			return {"ok": false, "error": "\"action\" must be finish, cancel or remove_last"}
	_show_draft()
	return {"ok": true, "points": _draft.size()}


func _texture_command(request: Dictionary) -> Dictionary:
	var ids := []
	if request.get("all", false) == true:
		ids = _paths.keys()
	else:
		if request.has("path"):
			ids.append(request["path"])
		var many = request.get("paths", [])
		if typeof(many) != TYPE_ARRAY:
			return {"ok": false, "error": "\"paths\" must be a list of path ids"}
		ids.append_array(many)
	if ids.is_empty():
		return {"ok": false, "error": "say which paths: path (an id), paths [ids] or all true"}
	for id in ids:
		if not _paths.has(id):
			return {"ok": false, "error": "no path \"%s\" (paths_list shows them)" % str(id)}
	var texture = request.get("texture", "")
	if typeof(texture) != TYPE_STRING:
		return {"ok": false, "error": "\"texture\" must be a path under downloads/, or \"\" for none"}
	var problem := _texture_problem(texture)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	var tile = request.get("texture_scale", 2.0)
	if typeof(tile) not in [TYPE_INT, TYPE_FLOAT] or tile < 0.2 or tile > 20.0:
		return {"ok": false, "error": "\"texture_scale\" must be 0.2 to 20 m per tile"}
	var before := {}
	var after := {}
	for id in ids:
		before[id] = _paths[id].duplicate(true)
		var path: Dictionary = _paths[id].duplicate(true)
		path["texture"] = texture
		path["texture_scale"] = float(tile)
		after[id] = path
	_apply(after)
	_undo_entry("texture %d path(s)" % ids.size(), _apply.bind(before), _apply.bind(after))
	return {"ok": true, "textured": ids, "texture": texture, "texture_scale": float(tile)}


# --- Paths ---------------------------------------------------------------------------

func _add(path: Dictionary) -> String:
	var id := "path_%d" % _next
	while _paths.has(id):
		_next += 1
		id = "path_%d" % _next
	_next += 1
	var before := PackedFloat32Array()
	if path["flatten"] and _landscape:
		before = _landscape.call("get_heights")
	_put(id, path, PackedFloat32Array())
	var after := PackedFloat32Array()
	if not before.is_empty():
		after = _landscape.call("get_heights")
	_undo_entry("new " + id, _take_back.bind(id, before), _put.bind(id, path, after))
	return id


# Puts a path in. heights, when given, is the ground to restore (redo of a
# path that flattened); otherwise a flattening path levels the ground now.
func _put(id: String, path: Dictionary, heights: PackedFloat32Array) -> void:
	_paths[id] = path
	if _landscape and path["flatten"]:
		if not heights.is_empty():
			_landscape.call("set_heights", heights)
		else:
			_landscape.call("flatten_along", _centre_line(path, true), path["width"] / 2.0)
			_landscape.call("set_heights", _landscape.call("get_heights"))  # saves it and tells everyone
	_rebuild(id)
	_save()


# Puts changed paths in place (texture changes, undo and redo of them).
func _apply(data: Dictionary) -> void:
	for id in data:
		_paths[id] = data[id].duplicate(true)
		_rebuild(id)
	_save()


# For other modules (save): every path, and putting a whole set back. Putting
# a set back doesn't level the ground again; the ground is saved on its own.
func get_paths() -> Dictionary:
	return {"paths": _paths.duplicate(true), "next": _next}


func set_paths(data: Dictionary) -> void:
	for id in _meshes:
		_meshes[id].queue_free()
	_meshes.clear()
	_paths.clear()
	var given = data.get("paths", {})
	if typeof(given) == TYPE_DICTIONARY:
		for id in given:
			if typeof(id) == TYPE_STRING and typeof(given[id]) == TYPE_DICTIONARY and _check(given[id]).is_empty():
				_paths[id] = given[id].duplicate(true)
			else:
				push_error("Slopitect paths: set_paths skipped \"%s\"" % id)
	_next = maxi(int(data.get("next", 1)), _paths.size() + 1)
	_rebuild_all()
	_save()


func _take_back(id: String, heights: PackedFloat32Array) -> void:
	_remove(id)
	if _landscape and not heights.is_empty():
		_landscape.call("set_heights", heights)


func _remove(id: String) -> void:
	_paths.erase(id)
	if _meshes.has(id):
		_meshes[id].queue_free()
		_meshes.erase(id)
	_save()


func _undo_entry(label: String, undo: Callable, redo: Callable) -> void:
	var tools: SlopitectModule = _lib.module("tools") if _lib else null
	if tools:
		tools.call("push_undo", "paths: " + label, undo, redo)


func _check(path: Dictionary) -> String:
	var points = path.get("points")
	if typeof(points) != TYPE_ARRAY or points.size() < 2 or points.size() > MAX_POINTS:
		return "\"points\" must be 2 to %d points, each [x, z] in metres" % MAX_POINTS
	for p in points:
		if typeof(p) != TYPE_ARRAY or p.size() != 2 or typeof(p[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(p[1]) not in [TYPE_INT, TYPE_FLOAT] or absf(p[0]) > 50 or absf(p[1]) > 50:
			return "each point must be [x, z], each from -50 to 50 m; got %s" % JSON.stringify(p)
	if typeof(path["width"]) not in [TYPE_INT, TYPE_FLOAT] or path["width"] < 0.2 or path["width"] > 5.0:
		return "\"width\" must be 0.2 to 5 m"
	if typeof(path["color"]) != TYPE_STRING or not (Color.html_is_valid(path["color"]) or Color.from_string(path["color"], Color(0, 0, 0, 0)).a > 0):
		return "\"color\" must be #rrggbb or a colour name"
	if typeof(path["flatten"]) != TYPE_BOOL:
		return "\"flatten\" must be true or false"
	if typeof(path.get("texture", "")) != TYPE_STRING:
		return "\"texture\" must be a path under downloads/, or \"\" for none"
	var tile = path.get("texture_scale", 2.0)
	if typeof(tile) not in [TYPE_INT, TYPE_FLOAT] or tile < 0.2 or tile > 20.0:
		return "\"texture_scale\" must be 0.2 to 20 m per tile"
	if _paths.size() >= MAX_PATHS:
		return "there are already %d paths, the most allowed" % MAX_PATHS
	return ""


# The downloads folder textures come from (lib's Slopitect folder), or "".
func _textures_folder() -> String:
	return _lib.home() + "/downloads/" if _lib else ""


# A texture name must be a file under the downloads folder ("" is none).
func _texture_problem(name) -> String:
	if typeof(name) != TYPE_STRING or name.is_empty():
		return ""
	if name.begins_with("/") or ".." in name.split("/"):
		return "\"texture\" must be a path inside downloads/, without .."
	if _lib == null:
		return "textures need the lib module (load lib.gd)"
	if not FileAccess.file_exists(_textures_folder() + name):
		return "no texture file \"%s\" under downloads/ (files_list shows them)" % name
	return ""


# --- Drawing -------------------------------------------------------------------------

func _rebuild_all() -> void:
	for id in _paths:
		_rebuild(id)
	_show_draft()


# The strip: cross-sections every SPACING metres along a smooth curve
# through the points, each end following the ground. Texture coordinates:
# across the width and along the length, in texture_scale metres a tile.
func _rebuild(id: String) -> void:
	if _meshes.has(id):
		_meshes[id].queue_free()
	var path: Dictionary = _paths[id]
	var line := _centre_line(path, false)
	var half: float = path["width"] / 2.0
	var tile: float = maxf(float(path.get("texture_scale", 2.0)), 0.2)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var along := 0.0
	for s in line.size():
		if s > 0:
			along += Vector2(line[s].x - line[s - 1].x, line[s].z - line[s - 1].z).length()
		var ahead := line[mini(s + 1, line.size() - 1)] - line[maxi(s - 1, 0)]
		var side := Vector3(-ahead.z, 0, ahead.x).normalized() * half
		for edge in 2:
			var p: Vector3 = (line[s] + side) if edge == 0 else (line[s] - side)
			vertices.append(Vector3(p.x, _ground(p.x, p.z) + LIFT, p.z))
			normals.append(Vector3.UP)
			uvs.append(Vector2(float(edge) * path["width"] / tile, along / tile))
		if s > 0:
			var k := s * 2
			indices.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	var texture = _texture_for(path.get("texture", ""))
	if texture != null:
		material.albedo_texture = texture
		material.albedo_color = Color.WHITE
	else:
		material.albedo_color = Color.from_string(path["color"], Color(0.54, 0.48, 0.36))
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	node.material_override = material
	add_child(node)
	_meshes[id] = node


# A texture from the downloads folder, loaded once; null for none or if it won't load.
func _texture_for(name) -> Texture2D:
	if typeof(name) != TYPE_STRING or name.is_empty():
		return null
	if _textures.has(name):
		return _textures[name]
	if not _texture_problem(name).is_empty():
		return null
	var image := Image.load_from_file(_textures_folder() + name)
	if image == null or image.is_empty():
		push_error("Slopitect paths: can't load texture %s" % name)
		return null
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_textures[name] = texture
	return texture


# Points every SPACING metres along a Catmull-Rom curve through the path's
# points. Each has the ground's height, evened out (for flattening, so the
# road doesn't copy every bump) when smooth_height is on.
func _centre_line(path: Dictionary, smooth_height: bool) -> PackedVector3Array:
	var points: Array = path["points"]
	var curve := Curve3D.new()
	curve.bake_interval = SPACING
	for i in points.size():
		var p := Vector3(points[i][0], 0, points[i][1])
		var before := Vector3(points[maxi(i - 1, 0)][0], 0, points[maxi(i - 1, 0)][1])
		var after := Vector3(points[mini(i + 1, points.size() - 1)][0], 0, points[mini(i + 1, points.size() - 1)][1])
		var tangent := (after - before) / 6.0
		curve.add_point(p, -tangent, tangent)
	var baked := curve.get_baked_points()
	var line := PackedVector3Array()
	for p in baked:
		line.append(Vector3(p.x, _ground(p.x, p.z), p.z))
	if smooth_height and line.size() > 2:
		var even := line.duplicate()
		for s in line.size():
			var total := 0.0
			var count := 0
			for t in range(maxi(0, s - 5), mini(line.size(), s + 6)):
				total += line[t].y
				count += 1
			even[s].y = total / count
		line = even
	return line


func _show_draft() -> void:
	for child in _draft_node.get_children():
		child.queue_free()
	for p in _draft:
		var ball := _ball(Color.from_string(settings["color"], Color.WHITE).lightened(0.4), 0.06)
		ball.position = Vector3(p[0], _ground(p[0], p[1]) + 0.06, p[1])
		_draft_node.add_child(ball)


func _ball(color: Color, radius: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	node.material_override = material
	return node


# --- Inside --------------------------------------------------------------------------

func _ground(x: float, z: float) -> float:
	if _landscape and _landscape.call("inside", x, z):
		return _landscape.call("height_at", x, z)
	return 0.0


# Where the right controller points at the ground, or null.
func _aim():
	var from: Vector3 = ctx["right"].global_position
	var along: Vector3 = -ctx["right"].global_basis.z
	var t := 0.0
	while t < RAY_LENGTH:
		t += RAY_STEP
		var p := from + along * t
		if p.y <= _ground(p.x, p.z):
			return p
	return null


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("paths")) != TYPE_DICTIONARY:
		push_error("Slopitect paths: %s isn't a paths file; starting with none" % SAVE_PATH)
		return
	for id in data["paths"]:
		var path = data["paths"][id]
		if typeof(path) == TYPE_DICTIONARY and typeof(id) == TYPE_STRING and _check(path).is_empty():
			_paths[id] = path
		else:
			push_error("Slopitect paths: skipped \"%s\" in %s: %s" % [id, SAVE_PATH, _check(path) if typeof(path) == TYPE_DICTIONARY else "not an object"])
	_next = int(data.get("next", _paths.size() + 1))


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Slopitect paths: could not save %s (%s)" % [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({"paths": _paths, "next": _next}, "\t"))
