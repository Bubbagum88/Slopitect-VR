extends SlopitectModule
# Headless checks for greet.gd. Run: tests/run.sh controls avatar greet lib zz_greet
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
	for i in 5: await get_tree().process_frame
	var m = ctx["modules"].module("greet")
	_check("loaded", m != null)
	_check("runs with avatar and controls", m.is_processing())
	await _r({"cmd": "code_unload", "name": "avatar"})
	await get_tree().process_frame
	_check("idle without the avatar", not m.is_processing())
	_check("wave needs three swings", not m._wave("left", 0.0, true) and not m._wave("left", 0.2, true))
	_finish()