extends SlopitectModule

# Textures on shapes. textures_apply puts an image from downloads/ (or a
# built-in "noise") on named shapes, tinted by the shape's colour. The
# texture is mapped on the shape itself (triplanar in its own space), so it
# moves, turns and is carried with the shape; it's scaled by the shape's
# size, so a tile is "scale" metres on a big box and a small one alike, and
# it's fitted again when the shape is resized. Optional metallic and
# roughness make things shiny. Kept per project in saves/textures.json and
# put back when the world loads (it follows projects' project_changed).
# While a shape has a texture it checks every CHECK_SECONDS that its
# material is still the one made here (a colour change replaces it) and
# that it hasn't been resized; with none it's idle.

const CHECK_SECONDS := 2.0

var _map := {}  # shape name -> {texture, scale, tint, metallic, roughness}
var _images := {}  # texture path -> Texture2D
var _mine := {}  # shape name -> the material we made
var _file := ""  # "" until lib is there
var _since := 0.0
var _lib: SlopitectModule


func setup() -> String:
	set_process(false)
	register("textures_apply", _apply_command, "texture shapes: names [..], texture (path under downloads/, like dl.polyhaven.org/tex/wood.jpg, or \"noise\"), optional scale (metres per tile, default 1), tint (true: times the shape's colour, default true), metallic (0-1, default 0), roughness (0-1, default 0.8; low is shiny)")
	register("textures_clear", _clear_command, "take textures off: names [..]")
	register("textures_status", _status_command, "which shapes have which texture")
	return ""


# The file is the open world's (lib.world_file): loaded once lib is there,
# again when save comes or another project opens.
func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		_file = ""
		return
	lib.watch(self, "save", _world_changed)
	lib.follow(self, "projects", "project_changed", _world_changed)
	_world_changed()


func _world_changed(_a = null, _b = null) -> void:
	var now: String = _lib.world_file("textures.json")
	if now == _file:
		return
	_file = now
	_mine.clear()
	_load()
	_check_now()


func _process(delta: float) -> void:
	_since += delta
	if _since >= CHECK_SECONDS:
		_since = 0.0
		_check_now()


func _check_now() -> void:
	for n in _map:
		var node := _find(n)
		if node and (not _mine.has(n) or node.material_override != _mine[n] or node.scale != _mine[n].get_meta("scale", node.scale)):
			_put(n, node)  # its material was replaced, or it was resized
	set_process(not _map.is_empty())


func _load() -> void:
	_map.clear()
	var data = _lib.read_json(_file)
	if typeof(data) == TYPE_DICTIONARY:
		for n in data:
			if typeof(data[n]) == TYPE_DICTIONARY:
				_map[n] = data[n]


func _save() -> void:
	set_process(not _map.is_empty())
	if _file.is_empty():
		return  # no lib yet: kept until it comes
	DirAccess.make_dir_recursive_absolute(_file.get_base_dir())
	var problem: String = _lib.write_json(_file, _map, "\t")
	if not problem.is_empty():
		push_error("Slopitect textures: " + problem)


# A shape (textures go on shapes, not placed models).
func _find(node_name) -> MeshInstance3D:
	return _lib.world_node(node_name) as MeshInstance3D if _lib else null


func _texture(path: String) -> Texture2D:
	if _images.has(path):
		return _images[path]
	var tex: Texture2D = null
	if path == "noise":
		var noise := FastNoiseLite.new()
		noise.frequency = 0.02
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.noise = noise
		nt.generate_mipmaps = true
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.8, 0.8, 0.8))
		ramp.set_color(1, Color(1, 1, 1))
		nt.color_ramp = ramp
		tex = nt
	else:
		if _lib == null:
			return null
		var img := Image.load_from_file(_lib.home() + "/downloads/" + path)
		if img == null or img.is_empty():
			return null
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	_images[path] = tex
	return tex


func _color_of(node: MeshInstance3D) -> Color:
	var mats := [node.material_override, node.get_surface_override_material(0)]
	if node.mesh and node.mesh.get_surface_count() > 0:
		mats.append(node.mesh.surface_get_material(0))
	for m in mats:
		if m and m != _mine.get(String(node.name)) and m is BaseMaterial3D:
			return (m as BaseMaterial3D).albedo_color
	var old = _mine.get(String(node.name))
	if old is BaseMaterial3D and old.has_meta("base"):
		return old.get_meta("base")
	return Color.WHITE


func _put(n: String, node: MeshInstance3D) -> bool:
	var info: Dictionary = _map[n]
	var tex := _texture(String(info.get("texture", "")))
	if tex == null:
		return false
	var base := _color_of(node)
	var m := StandardMaterial3D.new()
	m.set_meta("base", base)
	m.albedo_texture = tex
	m.albedo_color = base if info.get("tint", true) else Color.WHITE
	# Triplanar in the shape's own space, not the world's, so the texture
	# goes where the shape goes. Its own space is before its scale, so the
	# scale is put back in to keep each tile the same size in metres.
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	var tile := maxf(float(info.get("scale", 1.0)), 0.01)
	m.uv1_scale = node.scale.abs().max(Vector3(0.001, 0.001, 0.001)) / tile
	m.set_meta("scale", node.scale)
	m.metallic = clampf(float(info.get("metallic", 0.0)), 0.0, 1.0)
	m.roughness = clampf(float(info.get("roughness", 0.8)), 0.0, 1.0)
	m.metallic_specular = 0.5 if m.roughness >= 0.5 else 0.9
	node.material_override = m
	_mine[n] = m
	return true


func _apply_command(request: Dictionary) -> Dictionary:
	var names = request.get("names")
	if typeof(names) != TYPE_ARRAY or names.is_empty():
		return {"ok": false, "error": "\"names\" must be a list of shape names"}
	for n in names:
		if _find(n) == null:
			return {"ok": false, "error": "no shape named %s (list shows them)" % JSON.stringify(n)}
	var path = request.get("texture")
	if typeof(path) != TYPE_STRING or path.is_empty() or ".." in path:
		return {"ok": false, "error": "\"texture\" must be a path under downloads/ or \"noise\""}
	if _texture(path) == null:
		return {"ok": false, "error": "can't load image downloads/%s" % path}
	var scale = request.get("scale", 1.0)
	if not typeof(scale) in [TYPE_INT, TYPE_FLOAT] or scale <= 0:
		return {"ok": false, "error": "\"scale\" must be a number above 0"}
	var tint = request.get("tint", true)
	if typeof(tint) != TYPE_BOOL:
		return {"ok": false, "error": "\"tint\" must be true or false"}
	var metallic = request.get("metallic", 0.0)
	if not typeof(metallic) in [TYPE_INT, TYPE_FLOAT] or metallic < 0 or metallic > 1:
		return {"ok": false, "error": "\"metallic\" must be 0 to 1"}
	var roughness = request.get("roughness", 0.8)
	if not typeof(roughness) in [TYPE_INT, TYPE_FLOAT] or roughness < 0 or roughness > 1:
		return {"ok": false, "error": "\"roughness\" must be 0 to 1"}
	var before := _entries(names)
	for n in names:
		_map[n] = {"texture": path, "scale": float(scale), "tint": tint, "metallic": float(metallic), "roughness": float(roughness)}
		_put(n, _find(n))
	_save()
	_undo("texture %s" % (names[0] if names.size() == 1 else "%d shapes" % names.size()), before, _entries(names))
	return {"ok": true, "textured": names}


func _clear_command(request: Dictionary) -> Dictionary:
	var names = request.get("names")
	if typeof(names) != TYPE_ARRAY:
		return {"ok": false, "error": "\"names\" must be a list of shape names"}
	var before := _entries(names)
	_take_off(names)
	_save()
	if not before.values().all(func(e): return e == null):
		_undo("untexture %s" % (names[0] if names.size() == 1 else "%d shapes" % names.size()), before, _entries(names))
	return {"ok": true}


func _take_off(names: Array) -> void:
	for n in names:
		_map.erase(n)
		var node := _find(n)
		if node and _mine.has(n) and node.material_override == _mine[n]:
			var base = _mine[n].get_meta("base")
			var m := StandardMaterial3D.new()
			m.albedo_color = base
			node.material_override = m
		_mine.erase(n)


# name -> its texture entry, or null for none.
func _entries(names: Array) -> Dictionary:
	var out := {}
	for n in names:
		out[n] = _map[n].duplicate() if _map.has(n) else null
	return out


func _put_entries(entries: Dictionary) -> void:
	for n in entries:
		if entries[n] == null:
			_take_off([n])
		else:
			_map[n] = entries[n].duplicate()
			var node := _find(n)
			if node:
				_put(n, node)
	_save()


func _undo(label: String, before: Dictionary, after: Dictionary) -> void:
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		tools.call("push_undo", label, _put_entries.bind(before), _put_entries.bind(after))


# --- For the save module, and for undoing a delete (tools.gd) ----------------------------

func get_textures() -> Dictionary:
	return _map.duplicate(true)


func set_textures(data) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	_take_off(_map.keys())
	for n in data:
		if typeof(n) == TYPE_STRING and typeof(data[n]) == TYPE_DICTIONARY:
			_map[n] = data[n].duplicate()
			var node := _find(n)
			if node:
				_put(n, node)
	_save()


func thing_state(node_name: String) -> Dictionary:
	return {"texture": _map[node_name].duplicate()} if _map.has(node_name) else {}


func thing_forget(node_name: String) -> void:
	if _map.has(node_name):
		_take_off([node_name])
		_save()


func thing_restore(node_name: String, state: Dictionary) -> void:
	if typeof(state.get("texture")) == TYPE_DICTIONARY:
		_put_entries({node_name: state["texture"]})


func _status_command(_request: Dictionary) -> Dictionary:
	return {"ok": true, "textures": _map}
