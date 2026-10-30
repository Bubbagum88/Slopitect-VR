extends SlopitectModule
# Headless checks for multi.gd. Run: tests/run.sh lib save projects tools multi zz_multi
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
	var multi = ctx["modules"].module("multi")
	var lib = ctx["modules"].module("lib")
	_check("idle: not chosen, no groups", not multi.is_processing() and not multi.is_physics_processing())
	multi.tool_selected(true)
	_check("chosen: drawing", multi.is_processing())
	multi.tool_selected(false)
	_check("not chosen: not drawing", not multi.is_processing())
	await _r({"cmd": "spawn", "shape": "box", "name": "zz_a", "position": [0, 1, -2], "scale": [0.2, 0.2, 0.2]})
	await _r({"cmd": "spawn", "shape": "box", "name": "zz_b", "position": [1, 1, -2], "scale": [0.2, 0.2, 0.2]})
	var grouped := await _r({"cmd": "multi_group", "names": ["zz_a", "zz_b"], "group": "g"})
	_check("multi_group", grouped.get("ok", false), grouped)
	_check("a group: keeping it together", multi.is_physics_processing())
	await _r({"cmd": "move", "name": "zz_a", "position": [0, 2, -2]})
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("moving one moves the other", is_equal_approx(lib.world_node("zz_b").global_position.y, 2.0), lib.world_node("zz_b").global_position)
	var file: String = lib.world_file("groups.json")
	_check("kept in the world's folder", "projects/" in file and (lib.read_json(file) as Dictionary).has("g"), file)
	await _r({"cmd": "projects_new", "name": "zz_other", "open": true})
	await _wait(0.2)
	_check("other project: no groups, idle", (await _r({"cmd": "multi_status"})).get("groups", {"x": 1}).is_empty() and not multi.is_physics_processing(), await _r({"cmd": "multi_status"}))
	await _r({"cmd": "projects_open", "name": "start"})
	await _wait(0.2)
	_check("back: the group again", multi.is_physics_processing() and multi.members("zz_a").size() == 2)
	await _r({"cmd": "multi_ungroup", "group": "g"})
	_check("ungrouped: idle", not multi.is_physics_processing())
	_finish()
