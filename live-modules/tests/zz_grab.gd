extends SlopitectModule
# Headless checks for grab.gd. Run: tests/run.sh lib tools grab zz_grab
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


func _hand(hand: String, at: Vector3) -> void:
	(ctx[hand] as Node3D).global_transform = Transform3D(Basis(), at)


func _go() -> void:
	await _wait(1.0)
	var grab = ctx["modules"].module("grab")
	var lib = ctx["modules"].module("lib")
	_check("idle with nothing held", not grab.is_physics_processing())
	await _r({"cmd": "spawn", "shape": "box", "name": "zz_box", "position": [0, 1, -0.5], "scale": [0.2, 0.2, 0.2]})
	_hand("right", Vector3(0, 1, -0.5))
	_check("grip near it takes it", grab.on_action("grab_right", true))
	_check("holding: running", grab.is_physics_processing() and (await _r({"cmd": "grab_status"}))["holding"].get("right") == "zz_box")
	_hand("right", Vector3(0.5, 1.5, -0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var box: Node3D = lib.world_node("zz_box")
	_check("follows the hand", box.global_position.is_equal_approx(Vector3(0.5, 1.5, -0.5)), box.global_position)
	grab.on_action("grab_right", false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("let go: idle", not grab.is_physics_processing())
	_check("the move is one undo", (await _r({"cmd": "tools_status"})).get("undo") == "move zz_box")
	_hand("right", Vector3(3, 1, 3))
	_check("nothing in reach: not taken", not grab.on_action("grab_right", true) and not grab.is_physics_processing())
	grab.on_action("grab_right", false)
	# Deleted while held: let go, idle.
	_hand("left", Vector3(0.5, 1.5, -0.5))
	grab.on_action("grab_left", true)
	box.free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("deleted while held: idle", not grab.is_physics_processing())
	_finish()
