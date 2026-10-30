extends SlopitectModule
# Headless checks for doors.gd. Run: tests/run.sh lib save projects tools doors zz_doors
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
	var doors = ctx["modules"].module("doors")
	var lib = ctx["modules"].module("lib")
	_check("idle with no doors", not doors.is_processing())
	await _r({"cmd": "spawn", "shape": "box", "name": "zz_door", "position": [0, 1, -2], "scale": [0.8, 2.0, 0.05]})
	var made := await _r({"cmd": "doors_add", "name": "d", "parts": ["zz_door"], "hinge": [-0.4, -2]})
	_check("doors_add", made.get("ok", false), made)
	_check("a door that isn't swinging: idle", not doors.is_processing())
	var file: String = lib.world_file("doors.json")
	_check("kept in the world's folder", "projects/" in file and (lib.read_json(file) as Dictionary).has("d"), file)
	var node: Node3D = lib.world_node("zz_door")
	var closed := node.global_transform
	await _r({"cmd": "doors_toggle", "name": "d", "open": true})
	_check("swinging: running", doors.is_processing())
	await _wait(0.8)
	_check("open, then idle", not doors.is_processing() and not node.global_transform.is_equal_approx(closed))
	await _r({"cmd": "doors_toggle", "name": "d", "open": false})
	await _wait(0.8)
	_check("closed again", node.global_transform.is_equal_approx(closed) and not doors.is_processing())
	await _r({"cmd": "projects_new", "name": "zz_other", "open": true})
	await _wait(0.2)
	_check("other project: no doors", (await _r({"cmd": "doors_status"})).get("doors", [1]).is_empty(), await _r({"cmd": "doors_status"}))
	await _r({"cmd": "projects_open", "name": "start"})
	await _wait(0.2)
	_check("back: the door again", not (await _r({"cmd": "doors_status"})).get("doors", []).is_empty())
	_finish()
