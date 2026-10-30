extends SlopitectModule
# Headless checks for shapes.gd's running and forgetting. Run: tests/run.sh lib tools shapes zz_shapes
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


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _finish() -> void:
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


func _go() -> void:
	await _wait(1.0)
	var shapes = ctx["modules"].module("shapes")
	_check("idle", not shapes.is_processing() and not shapes.is_physics_processing())
	shapes.tool_selected(true)
	_check("chosen: aiming", shapes.is_physics_processing())
	shapes.tool_selected(false)
	_check("not chosen: idle", not shapes.is_physics_processing())
	await _r({"cmd": "shapes_tool", "show_points": true})
	_check("points shown: markers follow", shapes.is_processing())
	await _r({"cmd": "shapes_tool", "show_points": false})
	_check("points hidden: idle", not shapes.is_processing())
	var made := await _r({"cmd": "shapes_make", "preset": "star", "name": "zz_star", "position": [0, 1, -2]})
	_check("shapes_make", made.get("ok", false) and shapes.is_made("zz_star"), made)
	var gone := []
	shapes.shape_changed.connect(func(n, what): gone.append([n, what]))
	await _r({"cmd": "delete", "name": "zz_star"})
	await get_tree().process_frame
	await get_tree().process_frame
	_check("deleted another way: forgotten", not shapes.is_made("zz_star") and ["zz_star", "removed"] in gone, gone)
	_finish()
