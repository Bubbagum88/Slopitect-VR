extends SlopitectModule
# Headless checks for inspect.gd. Run: tests/run.sh lib tools inspect zz_inspect
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
	var inspect = ctx["modules"].module("inspect")
	var lib = ctx["modules"].module("lib")
	_check("idle: no scan, not chosen", not inspect.is_processing())
	inspect.tool_selected(true)
	_check("chosen: drawing", inspect.is_processing())
	inspect.tool_selected(false)
	_check("not chosen: idle", not inspect.is_processing())
	await _r({"cmd": "spawn", "shape": "box", "name": "zz_i", "position": [0, 1, -2]})
	var set := await _r({"cmd": "inspect_set", "name": "zz_i", "hidden": true, "grabbable": false})
	_check("inspect_set", set.get("ok", false), set)
	_check("hidden and not grabbable", not lib.world_node("zz_i").visible and lib.world_node("zz_i").get_meta("slopitect_no_grab", false))
	# A world put back (save sets the switches, then makes the things): the
	# switches land as each thing joins the world.
	inspect.set_settings({"zz_j": {"hidden": true, "grabbable": false}})
	await _r({"cmd": "spawn", "shape": "box", "name": "zz_j", "position": [1, 1, -2]})
	await get_tree().process_frame
	await get_tree().process_frame
	_check("made after its switches: hidden", not lib.world_node("zz_j").visible and lib.world_node("zz_j").get_meta("slopitect_no_grab", false))
	# Deleted with Inspect and undone: back hidden.
	await _r({"cmd": "inspect_set", "name": "zz_i", "hidden": true})
	await _r({"cmd": "inspect_delete", "name": "zz_i"})
	await _r({"cmd": "tools_undo"})
	await get_tree().process_frame
	_check("delete undone: still hidden", lib.world_node("zz_i") != null and not lib.world_node("zz_i").visible)
	await _r({"cmd": "inspect_show_all"})
	_check("show all", lib.world_node("zz_i").visible)
	ctx["modules"].unload("inspect")
	_check("unloads: lib lets go of it", lib.thing_entered.get_connections().all(func(c): return is_instance_valid(c.callable.get_object()) and c.callable.get_object().name != "inspect"))
	_finish()
