extends SlopitectModule
# Headless checks for player_column.gd. Run: tests/run.sh player_column lib zz_player_column
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
	for i in 3: await get_tree().physics_frame
	var m = ctx["modules"].module("player_column")
	_check("loaded", m != null)
	var col: Node3D = m.find_child("PlayerColumn", true, false)
	_check("column body made", col is AnimatableBody3D)
	var cam: Node3D = ctx["camera"]
	cam.global_position = Vector3(1.0, 1.7, 2.0)
	for i in 3: await get_tree().physics_frame
	_check("follows the head at hip height", col.global_position.distance_to(Vector3(1.0, m.HIP_Y, 2.0)) < 0.01, col.global_position)
	await _r({"cmd": "code_unload", "name": "player_column"})
	await get_tree().process_frame
	_check("column removed on unload", not is_instance_valid(col) or col.is_queued_for_deletion())
	_finish()