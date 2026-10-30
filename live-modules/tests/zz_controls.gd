extends SlopitectModule
# Headless checks for controls.gd's lib parts. Run: tests/run.sh controls lib landscape zz_controls
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


func _go() -> void:
	for i in 5: await get_tree().process_frame
	var c = ctx["modules"].module("controls")
	_check("confirm kept at hand", c.get("_confirm") == ctx["modules"].module("confirm"))
	_check("landscape followed", c.get("_landscape") == ctx["modules"].module("landscape"))
	await _r({"cmd": "landscape_sculpt", "position": [0, 0], "mode": "raise", "size": 2.0, "amount": 0.5})
	_check("ground under you is the landscape's", c.call("_ground_under", Vector3.ZERO) > 0.3)
	await _r({"cmd": "code_unload", "name": "landscape"})
	_check("landscape gone: let go", c.get("_landscape") == null and c.call("_ground_under", Vector3.ZERO) == 0.0)
	var touched := []
	ctx["modules"].module("lib").info_changed.connect(func(n): touched.append(n))
	var r := await _r({"cmd": "move_comfort", "speed": 2.0})
	_check("move_comfort", r.get("ok"), r)
	_check("tells the Settings window", "controls" in touched, touched)
	_check("value() works", c.call("value", "left", "grip") == 0.0)
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
