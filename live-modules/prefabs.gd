extends SlopitectModule

# Prefabs: save a set of shapes and models as a reusable asset in
# prefabs/NAME.json, with their textures, doors and groups, and place copies
# of it anywhere. The set is given by names, by name prefixes, or is what's
# selected with the Multi tool (multi.gd). Shapes made with shapes.gd keep
# their recipe. Doors should be closed when saving. The Library window's
# Prefabs tab (library.gd) shows them with a picture and places them.
# The prefabs folder is in the Slopitect folder (lib.home()); its commands
# wait for lib.

var _lib: SlopitectModule


func setup() -> String:
	register("prefabs_save", _save_command, "save things as a prefab asset: name (letters, digits, _ and -); which things: names [..] and/or prefixes [name starts], or (neither given) what the Multi tool has selected; optional origin [x, y, z] (default the middle of their footprint, on the floor)")
	register("prefabs_place", _place_command, "place a copy of a prefab: name, position [x, y, z] (where its origin goes); optional suffix for the new names (default _2, _3, ...); one undo")
	register("prefabs_list", _list_command, "the saved prefabs: name, how many shapes and models")
	register("prefabs_delete", _delete_command, "delete a saved prefab: name")
	return ""


func lib_ready(lib) -> void:
	_lib = lib


# "" without lib, which every command checks first.
func _folder() -> String:
	return _lib.home() + "/prefabs" if _lib else ""


func _waiting() -> Dictionary:
	return {"ok": false, "error": "prefabs is waiting for the lib module (load lib.gd)"}


func _run(req: Dictionary) -> Dictionary:
	var r = ctx["server"].run(req)
	return r if typeof(r) == TYPE_DICTIONARY else {}


# A prefab's name is its file's name and the Library's tile id.
func _good_name(n) -> bool:
	if typeof(n) != TYPE_STRING or n.is_empty() or n.length() > 80:
		return false
	for c in n:
		if not (c == "_" or c == "-" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return true


func _starts(n: String, prefixes: Array) -> bool:
	for p in prefixes:
		if n.begins_with(String(p)):
			return true
	return false


# What prefabs_save takes: [names, prefixes, error].
func _chosen(request: Dictionary) -> Array:
	var names = request.get("names", [])
	var prefixes = request.get("prefixes", [])
	if typeof(names) != TYPE_ARRAY or not names.all(func(n): return typeof(n) == TYPE_STRING):
		return [[], [], "\"names\" must be a list of names"]
	if typeof(prefixes) != TYPE_ARRAY or not prefixes.all(func(p): return typeof(p) == TYPE_STRING and not p.is_empty()):
		return [[], [], "\"prefixes\" must be a list of name starts"]
	if names.is_empty() and prefixes.is_empty():
		if ctx["modules"].module("multi") == null:
			return [[], [], "say which things: names or prefixes (or select them with the Multi tool, multi.gd)"]
		names = _run({"cmd": "multi_status"}).get("selected", [])
		if names.is_empty():
			return [[], [], "nothing is selected with the Multi tool; select things, or give names or prefixes"]
	return [names, prefixes, ""]


func _vec(v) -> Vector3:
	if typeof(v) == TYPE_ARRAY and v.size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


func _first_array(d: Dictionary) -> Array:
	for k in d:
		if typeof(d[k]) == TYPE_ARRAY:
			return d[k]
	return []


func _save_command(request: Dictionary) -> Dictionary:
	if _lib == null:
		return _waiting()
	var name = request.get("name")
	if not _good_name(name):
		return {"ok": false, "error": "\"name\" must be letters, digits, _ and -"}
	var chosen := _chosen(request)
	if not chosen[2].is_empty():
		return {"ok": false, "error": chosen[2]}
	var names: Array = chosen[0]
	var prefixes: Array = chosen[1]
	var wanted := func(n: String) -> bool: return n in names or _starts(n, prefixes)
	var shaper: SlopitectModule = ctx["modules"].module("shapes")
	var shapes := []
	for o in _first_array(_run({"cmd": "list"})):
		if typeof(o) == TYPE_DICTIONARY and wanted.call(String(o.get("name", ""))):
			if shaper != null and shaper.call("is_made", String(o["name"])):
				o["recipe"] = shaper.call("recipe", String(o["name"]))  # placed again with shapes_make
			shapes.append(o)
	var models := []
	for m in _run({"cmd": "assets_placed"}).get("placed", []):
		if typeof(m) == TYPE_DICTIONARY and wanted.call(String(m.get("name", ""))):
			models.append(m)
	if shapes.is_empty() and models.is_empty():
		return {"ok": false, "error": "none of those things are in the world: names %s, prefixes %s" % [JSON.stringify(names), JSON.stringify(prefixes)]}
	var origin := Vector3.ZERO
	if request.has("origin"):
		if typeof(request["origin"]) != TYPE_ARRAY or request["origin"].size() != 3:
			return {"ok": false, "error": "\"origin\" must be [x, y, z]"}
		origin = _vec(request["origin"])
	else:
		var lo := Vector3(INF, 0, INF)
		var hi := Vector3(-INF, 0, -INF)
		for o in shapes + models:
			var p := _vec(o.get("position"))
			lo.x = minf(lo.x, p.x)
			lo.z = minf(lo.z, p.z)
			hi.x = maxf(hi.x, p.x)
			hi.z = maxf(hi.z, p.z)
		origin = Vector3((lo.x + hi.x) * 0.5, 0, (lo.z + hi.z) * 0.5)
	var out_shapes := []
	for o in shapes:
		var s: Dictionary = o.duplicate()
		s["position"] = _arr(_vec(o.get("position")) - origin)
		out_shapes.append(s)
	var out_models := []
	for m in models:
		var s: Dictionary = m.duplicate()
		s["position"] = _arr(_vec(m.get("position")) - origin)
		out_models.append(s)
	var textures := {}
	var tex = _run({"cmd": "textures_status"}).get("textures", {})
	if typeof(tex) == TYPE_DICTIONARY:
		for n in tex:
			if wanted.call(String(n)):
				textures[n] = tex[n]
	var doors := {}
	var ds = _run({"cmd": "doors_status"}).get("doors", {})
	if typeof(ds) == TYPE_DICTIONARY:
		for id in ds:
			var d = ds[id]
			if typeof(d) != TYPE_DICTIONARY or typeof(d.get("parts")) != TYPE_ARRAY or d["parts"].is_empty():
				continue
			if not wanted.call(String(d["parts"][0])):
				continue
			var h: Array = d.get("hinge", [0, 0])
			var hv := Vector3(float(h[0]), float(h[1]) if h.size() == 3 else 0.0, float(h[h.size() - 1]))
			hv -= Vector3(origin.x, origin.y if h.size() == 3 else 0.0, origin.z)
			doors[id] = {"parts": d["parts"], "axis": d.get("axis", "y"), "angle": d.get("angle", 100.0), "hinge": _arr(hv) if h.size() == 3 else [hv.x, hv.z]}
	var groups := {}
	var gs = _run({"cmd": "multi_status"}).get("groups", {})
	if typeof(gs) == TYPE_DICTIONARY:
		for g in gs:
			var members := []
			for n in gs[g]:
				if wanted.call(String(n)):
					members.append(n)
			if members.size() >= 2:
				groups[g] = members
	DirAccess.make_dir_recursive_absolute(_folder())
	var problem: String = _lib.write_json("%s/%s.json" % [_folder(), name], {"shapes": out_shapes, "models": out_models, "textures": textures, "doors": doors, "groups": groups}, "\t")
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return {"ok": true, "file": "prefabs/%s.json" % name, "origin": _arr(origin), "shapes": out_shapes.size(), "models": out_models.size(), "textures": textures.size(), "doors": doors.size(), "groups": groups.size()}


func _load(name: String) -> Dictionary:
	var data = _lib.read_json("%s/%s.json" % [_folder(), name])
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _taken(n: String) -> bool:
	return _lib.world_node(n) != null


# Placing is one undo, which takes away all it placed; redo places it again.
func _place_command(request: Dictionary) -> Dictionary:
	if _lib == null:
		return _waiting()
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		tools.call("undo_batch_begin", "place prefab %s" % str(request.get("name")))
	var reply := _place(request)
	if tools:
		if reply.get("ok", false) and not reply["names"].is_empty():
			var again := request.duplicate()
			again["suffix"] = reply["suffix"]
			tools.call("undo_batch_end", _take_away.bind(reply["names"], reply["door_names"]), _place.bind(again))
		else:
			tools.call("undo_batch_end")
	return reply


func _take_away(names: Array, door_names: Array) -> void:
	for d in door_names:
		_run({"cmd": "doors_remove", "name": d})
	var tools: SlopitectModule = ctx["modules"].module("tools")
	for n in names:
		var world: Node3D = ctx["world"]
		_run({"cmd": "delete" if world.has_node(NodePath(n)) else "assets_remove", "name": n})
		if tools:
			tools.call("thing_forget", n)  # its group, texture and the rest


func _place(request: Dictionary) -> Dictionary:
	var name = request.get("name")
	if not _good_name(name):
		return {"ok": false, "error": "\"name\" must be a prefab name (prefabs_list)"}
	var data := _load(name)
	if data.is_empty():
		return {"ok": false, "error": "no prefab named %s (prefabs_list)" % JSON.stringify(name)}
	var pos = request.get("position")
	if typeof(pos) != TYPE_ARRAY or pos.size() != 3:
		return {"ok": false, "error": "\"position\" must be [x, y, z]"}
	var at := _vec(pos)
	var all_names := []
	for o in data.get("shapes", []) + data.get("models", []):
		all_names.append(String(o.get("name", "")))
	var suffix = request.get("suffix", "")
	if typeof(suffix) != TYPE_STRING:
		return {"ok": false, "error": "\"suffix\" must be text"}
	if suffix == "":
		var i := 2
		while true:
			var clash := false
			for n in all_names:
				if _taken(n + "_" + str(i)):
					clash = true
					break
			if not clash:
				break
			i += 1
		suffix = "_" + str(i)
	elif not _good_name("a" + suffix):
		return {"ok": false, "error": "\"suffix\" must be letters, digits and _"}
	for n in all_names:
		if _taken(n + suffix):
			return {"ok": false, "error": "%s already exists; pick another suffix" % (n + suffix)}
	var made := 0
	var names := []  # what was placed, for the undo
	var door_names := []
	var failed := []
	for o in data.get("shapes", []):
		var req := {"cmd": "spawn", "shape": o.get("shape", "box"), "name": String(o["name"]) + suffix, "position": _arr(_vec(o.get("position")) + at), "rotation": o.get("rotation", [0, 0, 0]), "scale": o.get("scale", [1, 1, 1])}
		if typeof(o.get("recipe")) == TYPE_DICTIONARY:
			# A shape made with shapes.gd: made again from its recipe.
			if ctx["modules"].module("shapes") == null:
				failed.append({"name": req["name"], "error": "it was made with shapes.gd, which isn't loaded"})
				continue
			req.erase("shape")
			req["cmd"] = "shapes_make"
			req.merge(o["recipe"])
		if o.has("color"):
			var c := String(o["color"])
			req["color"] = c if c.begins_with("#") else "#" + c
		var r := _run(req)
		if r.get("ok", false):
			made += 1
			names.append(req["name"])
		else:
			failed.append({"name": req["name"], "error": r.get("error", "?")})
	for m in data.get("models", []):
		var req := {"cmd": "assets_place", "id": m.get("id"), "name": String(m["name"]) + suffix, "position": _arr(_vec(m.get("position")) + at), "rotation": m.get("rotation", [0, 0, 0]), "scale": m.get("scale", [1, 1, 1])}
		if m.has("resolution"):
			req["resolution"] = m["resolution"]
		var r := _run(req)
		if r.get("ok", false):
			made += 1
			names.append(req["name"])
		else:
			failed.append({"name": req["name"], "error": r.get("error", "?")})
	var tex = data.get("textures", {})
	for n in tex:
		var t: Dictionary = tex[n]
		var req := {"cmd": "textures_apply", "names": [String(n) + suffix], "texture": t.get("texture", "noise"), "scale": t.get("scale", 1.0), "tint": t.get("tint", true)}
		for k in ["metallic", "roughness"]:
			if t.has(k):
				req[k] = t[k]
		var r := _run(req)
		if not r.get("ok", false):
			failed.append({"name": String(n) + suffix, "error": r.get("error", "?")})
	var doors = data.get("doors", {})
	for id in doors:
		var d: Dictionary = doors[id]
		var h: Array = d.get("hinge", [0, 0])
		var hinge: Array
		if h.size() == 3:
			hinge = _arr(_vec(h) + at)
		else:
			hinge = [float(h[0]) + at.x, float(h[1]) + at.z]
		var parts := []
		for p in d.get("parts", []):
			parts.append(String(p) + suffix)
		var r := _run({"cmd": "doors_add", "name": String(id) + suffix, "parts": parts, "hinge": hinge, "axis": d.get("axis", "y"), "angle": d.get("angle", 100.0)})
		if r.get("ok", false):
			door_names.append(String(id) + suffix)
		else:
			failed.append({"name": String(id) + suffix, "error": r.get("error", "?")})
	var groups = data.get("groups", {})
	for g in groups:
		var members := []
		for n in groups[g]:
			members.append(String(n) + suffix)
		_run({"cmd": "multi_group", "names": members, "group": String(g) + suffix})
	return {"ok": true, "placed": made, "names": names, "door_names": door_names, "suffix": suffix, "doors": doors.size(), "groups": groups.size(), "failed": failed}


func _list_command(_request: Dictionary) -> Dictionary:
	if _lib == null:
		return _waiting()
	var out := []
	var dir := DirAccess.open(_folder())
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json"):
				var d := _load(f.get_basename())
				out.append({"name": f.get_basename(), "shapes": d.get("shapes", []).size(), "models": d.get("models", []).size()})
	return {"ok": true, "prefabs": out}


func _delete_command(request: Dictionary) -> Dictionary:
	if _lib == null:
		return _waiting()
	var name = request.get("name")
	if not _good_name(name):
		return {"ok": false, "error": "\"name\" must be a prefab name"}
	var path := "%s/%s.json" % [_folder(), name]
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "no prefab named %s" % JSON.stringify(name)}
	DirAccess.remove_absolute(path)
	return {"ok": true}
