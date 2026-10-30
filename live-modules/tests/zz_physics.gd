extends SlopitectModule
# Headless checks for physics.gd. Run: tests/run.sh physics lib landscape zz_physics
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


func _go() -> void:
	await _frames(5)
	var physics = ctx["modules"].module("physics")
	_check("idle with nothing physical", not physics.is_physics_processing() and not physics.is_processing())
	_check("ground is the landscape", (await _r({"cmd": "physics_status"})).get("ground") == "landscape")

	await _r({"cmd": "spawn", "shape": "box", "name": "zz_cube", "position": [0, 5, -2], "scale": [0.3, 0.3, 0.3]})
	var set := await _r({"cmd": "physics_set", "name": "zz_cube", "mode": "dynamic"})
	_check("physics_set dynamic", set.get("ok"), set)
	_check("on while something is physical", physics.is_physics_processing())
	var cube: Node3D = ctx["world"].get_node("zz_cube")
	await _frames(30)
	_check("it falls", cube.global_position.y < 4.9, cube.global_position)

	# Deleted: its body goes and physics idles; made again with the same
	# name: its body comes back by itself (no scanning).
	await _r({"cmd": "delete", "name": "zz_cube"})
	await _frames(3)
	_check("deleted: idle again", not physics.is_physics_processing())
	await _r({"cmd": "spawn", "shape": "box", "name": "zz_cube", "position": [0, 5, -2], "scale": [0.3, 0.3, 0.3]})
	await _frames(3)
	_check("made again: body back", physics.is_physics_processing()
		and (await _r({"cmd": "physics_status"})).things.any(func(t): return t.name == "zz_cube" and not t.has("in_world")))
	cube = ctx["world"].get_node("zz_cube")
	await _frames(30)
	_check("and falls again", cube.global_position.y < 4.9, cube.global_position)

	# The ground follows the landscape coming and going.
	await _r({"cmd": "code_unload", "name": "landscape"})
	await _frames(2)
	_check("landscape gone: floor", (await _r({"cmd": "physics_status"})).get("ground") == "floor")
	await _r({"cmd": "code_load", "name": "landscape"})
	await _frames(2)
	_check("landscape back: its ground", (await _r({"cmd": "physics_status"})).get("ground") == "landscape")

	_check("bad name refused", not (await _r({"cmd": "physics_set", "name": "nope", "mode": "dynamic"})).ok)
	await _r({"cmd": "physics_set", "name": "zz_cube", "mode": "off"})
	_check("off: idle", not physics.is_physics_processing())
	await _r({"cmd": "delete", "name": "zz_cube"})
	await _r({"cmd": "code_unload", "name": "physics"})
	await _frames(2)
	_check("unloaded cleanly", ctx["modules"].module("physics") == null
		and ctx["world"].get_signal_connection_list("child_entered_tree").filter(func(c): return not is_instance_valid(c.callable.get_object()) or c.callable.get_object().name == "physics").is_empty())
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
