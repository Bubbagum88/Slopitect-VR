extends SlopitectModule
# Headless checks for fall_respawn.gd. Run: tests/run.sh physics fall_respawn lib zz_fall_respawn
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
	var m = ctx["modules"].module("fall_respawn")
	_check("loaded", m != null)
	var box := Node3D.new()
	box.name = "zz_box"
	ctx["world"].add_child(box)
	box.global_position = Vector3(0, 1, 0)
	await get_tree().create_timer(1.6).timeout
	_check("rest spot learned", m._seen.get("zz_box", {}).get("has_home", false), m._seen.get("zz_box"))
	box.global_position = Vector3(0, -30, 0)
	await get_tree().create_timer(0.6).timeout
	_check("sent home after falling", box.global_position.y > -1.0, box.global_position)
	_finish()