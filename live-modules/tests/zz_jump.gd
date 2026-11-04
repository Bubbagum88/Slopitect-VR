extends SlopitectModule
# Headless checks for jump.gd. Run: tests/run.sh controls jump lib zz_jump
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
	_finish()