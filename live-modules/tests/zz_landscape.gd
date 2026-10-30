extends SlopitectModule
# Headless checks for landscape.gd. Run: tests/run.sh landscape lib tools zz_landscape
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
	var land = ctx["modules"].module("landscape")
	_check("idle until chosen", not land.is_physics_processing())
	land.tool_selected(true)
	_check("chosen: on", land.is_physics_processing())
	land.tool_selected(false)
	_check("not chosen: off", not land.is_physics_processing())

	var r := await _r({"cmd": "landscape_sculpt", "position": [1, 1], "mode": "raise", "size": 1.0, "amount": 0.5})
	_check("sculpt", r.get("ok"), r)
	var h: float = (await _r({"cmd": "landscape_height", "position": [1, 1]})).get("height", 0.0)
	_check("ground raised", h > 0.3, h)
	var undo := await _r({"cmd": "tools_undo"})
	_check("one undo through tools (via lib)", undo.get("ok"), undo)
	h = (await _r({"cmd": "landscape_height", "position": [1, 1]})).get("height", 1.0)
	_check("undone", absf(h) < 0.001, h)
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
