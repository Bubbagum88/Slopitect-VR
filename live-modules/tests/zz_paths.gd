extends SlopitectModule
# Headless checks for paths.gd. Run: tests/run.sh paths lib landscape tools zz_paths
var _fails := 0
var _passes := 0


func setup() -> String:
	_go.call_deferred()
	return ""


func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if ok: _passes += 1
	else: _fails += 1


func _r(q: Dictionary) -> Dictionary:
	var r = ctx["server"].run(q)
	if r.get("wait") is SlopitectPending:
		var p: SlopitectPending = r["wait"]
		r = p.result if p.finished else await p.done
	return r


func _frames(n: int) -> void:
	for i in n: await get_tree().physics_frame


# The highest point of the path's mesh, in world space.
func _top(paths: Node) -> float:
	var top := -INF
	for m in paths.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).mesh is ArrayMesh:
			top = maxf(top, ((m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()).end.y)
	return top


func _go() -> void:
	await _frames(5)
	var paths = ctx["modules"].module("paths")
	_check("no per-frame check", not paths.has_method("_process"))
	_check("idle until chosen", not paths.is_physics_processing())
	paths.tool_selected(true)
	_check("chosen: on", paths.is_physics_processing())
	paths.tool_selected(false)

	await _r({"cmd": "landscape_sculpt", "position": [0, 0], "mode": "raise", "size": 4.0, "amount": 1.0})
	var r := await _r({"cmd": "paths_add", "points": [[-1, 0], [1, 0]], "flatten": false})
	_check("path added", r.get("ok"), r)
	await _frames(2)
	var on_hill := _top(paths)
	_check("sits on the raised ground", on_hill > 0.5, on_hill)
	await _r({"cmd": "code_unload", "name": "landscape"})
	await _frames(2)
	_check("landscape gone: back on the floor", _top(paths) < 0.3, _top(paths))
	await _r({"cmd": "code_load", "name": "landscape"})
	await _frames(2)
	_check("landscape back: on it again", _top(paths) > 0.5, _top(paths))
	await _r({"cmd": "landscape_reset"})
	await _frames(2)
	_check("follows the landscape changing", _top(paths) < 0.3, _top(paths))

	# Textures from downloads/ (lib's Slopitect folder), one undo.
	var folder: String = ctx["modules"].module("lib").home() + "/downloads/zz"
	DirAccess.make_dir_recursive_absolute(folder)
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color(0, 1, 0))
	image.save_png(folder + "/green.png")
	var id: String = r["path"]
	_check("missing texture refused", not (await _r({"cmd": "paths_texture", "path": id, "texture": "zz/none.png"})).get("ok", true))
	_check("texture outside downloads refused", not (await _r({"cmd": "paths_texture", "path": id, "texture": "../modules/lib.gd"})).get("ok", true))
	_check("absolute texture refused", not (await _r({"cmd": "paths_texture", "path": id, "texture": "/etc/passwd"})).get("ok", true))
	var t := await _r({"cmd": "paths_texture", "path": id, "texture": "zz/green.png", "texture_scale": 1.5})
	_check("paths_texture", t.get("ok", false), t)
	var mesh: MeshInstance3D = paths._meshes[id]
	_check("wears the texture", (mesh.material_override as StandardMaterial3D).albedo_texture != null)
	var listed: Dictionary = (await _r({"cmd": "paths_list"}))["paths"][0]
	_check("listed with texture and scale", listed.get("texture") == "zz/green.png" and is_equal_approx(listed.get("texture_scale"), 1.5), listed)
	var tools = ctx["modules"].module("tools")
	if tools:
		await _r({"cmd": "tools_undo"})
		await _frames(1)
		_check("undo takes the texture off", (paths._meshes[id].material_override as StandardMaterial3D).albedo_texture == null)
		await _r({"cmd": "tools_redo"})
		await _frames(1)
	# A textured path loaded before lib is drawn again with its texture when lib comes.
	await _r({"cmd": "code_unload", "name": "lib"})
	await _r({"cmd": "code_unload", "name": "paths"})
	await _r({"cmd": "code_load", "name": "paths"})
	await _frames(2)
	paths = ctx["modules"].module("paths")
	_check("before lib: drawn plain", (paths._meshes[id].material_override as StandardMaterial3D).albedo_texture == null)
	await _r({"cmd": "code_load", "name": "lib"})
	await _frames(2)
	_check("lib comes: textured again", (paths._meshes[id].material_override as StandardMaterial3D).albedo_texture != null)
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
