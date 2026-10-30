extends SlopitectModule
# Headless checks for joints.gd's running. Run: tests/run.sh lib tools physics joints zz_joints
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
	var joints = ctx["modules"].module("joints")
	_check("idle with no joints", not joints.is_physics_processing() and not joints.is_processing())
	joints.tool_selected(true)
	_check("chosen: marks drawn", joints.is_processing())
	joints.tool_selected(false)
	_check("not chosen: no marks", not joints.is_processing())
	await _r({"cmd": "spawn", "shape": "box", "name": "zz_lid", "position": [0, 1, -2], "scale": [0.4, 0.05, 0.4]})
	var added := await _r({"cmd": "joints_add", "b": "zz_lid", "type": "hinge", "at": [0, 1, -2.2], "axis": [1, 0, 0]})
	_check("joints_add", added.get("ok", false), added)
	_check("a joint: running", joints.is_physics_processing())
	await _r({"cmd": "joints_set", "id": added["joint"]["id"], "value": 30})
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("the hinge turns its part", not ctx["modules"].module("lib").world_node("zz_lid").global_basis.is_equal_approx(Basis()))
	await _r({"cmd": "joints_remove", "id": added["joint"]["id"]})
	_check("removed: idle", not joints.is_physics_processing())
	await _r({"cmd": "joints_prefs", "show": "always"})
	_check("show always: marks drawn", joints.is_processing())
	await _r({"cmd": "joints_prefs", "show": "tool"})
	_check("show tool, not chosen: none", not joints.is_processing())
	_finish()
