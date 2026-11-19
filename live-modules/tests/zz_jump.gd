extends SlopitectModule
# Headless checks for jump.gd. Run: tests/run.sh controls jump lib landscape zz_jump
var _fails := 0


func setup() -> String:
	_go.call_deferred()
	return ""


func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if not ok: _fails += 1


func _r(q: Dictionary) -> Dictionary:
	var r = ctx["server"].run(q)
	if r.get("wait") is SlopitectPending:
		var p: SlopitectPending = r["wait"]
		r = p.result if p.finished else await p.done
	return r


func _finish() -> void:
	print("RESULT done, %d failed" % _fails)
	get_tree().quit(_fails)

func _go() -> void:
	for i in 3: await get_tree().process_frame
	var m = ctx["modules"].module("jump")
	_check("loaded", m != null)
	var origin: Node3D = ctx["camera"].get_parent()
	var start := origin.global_position.y
	_check("A jumps", m.on_action("right_a", true))
	m.on_action("right_a", false)
	await get_tree().create_timer(0.25).timeout
	_check("rises", origin.global_position.y > start + 0.2, origin.global_position.y)
	await get_tree().create_timer(1.5).timeout
	_check("lands again", absf(origin.global_position.y - start) < 0.05, origin.global_position.y)
	_check("B on the ground isn't taken", not m.on_action("right_b", true))
	# The landscape is found through lib (not looked up every frame), and the
	# world's boxes are only measured when asked.
	var landscape = ctx["modules"].module("landscape")
	_check("landscape found through lib", landscape != null and m.get("_landscape") == landscape)
	_check("no box scan four times a second", (m.get("_boxes") as Array).is_empty())
	ctx["server"].run({"cmd": "spawn", "shape": "box", "name": "zz_step", "position": [5, 0.5, 5]})
	_check("boxes measured when asked", m.call("_top_under", 5.0, 5.0, 10.0) > 0.5, m.call("_top_under", 5.0, 5.0, 10.0))
	ctx["modules"].unload("landscape")
	await get_tree().process_frame
	_check("landscape gone: let go", m.get("_landscape") == null)
	await get_tree().create_timer(0.2).timeout
	_check("still on the floor without it", absf(origin.global_position.y - start) < 0.05, origin.global_position.y)
	_finish()