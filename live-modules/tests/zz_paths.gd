extends SlopitectModule
# Headless checks for paths.gd. Run: tests/run.sh paths lib landscape zz_paths
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
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
