extends SlopitectModule
# Headless checks for tts.gd and vtt.gd. Run: tests/run.sh controls vrui tts vtt lib pause zz_voice
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
	for i in n: await get_tree().process_frame


func _ids(id_panel: String) -> Array:
	var out := []
	var stack: Array = (await _r({"cmd": "ui_get", "id_panel": id_panel})).get("panel", {}).get("elements", []).duplicate()
	while not stack.is_empty():
		var e = stack.pop_front()
		out.append(e["id"])
		stack.append_array(e.get("children", []))
	return out


func _done() -> void:
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


func _go() -> void:
	await _frames(10)
	var lib = ctx["modules"].module("lib")
	var vtt = ctx["modules"].module("vtt")
	var touched := []
	lib.info_changed.connect(func(n): touched.append(n))
	var r := await _r({"cmd": "tts_set", "rate": 1.2})
	_check("tts_set", r.get("ok"), r)
	_check("tts tells the Settings window", "tts" in touched, touched)
	r = await _r({"cmd": "vtt_set", "min_hold": 0.4})
	_check("vtt_set", r.get("ok"), r)
	_check("vtt tells the Settings window", "vtt" in touched, touched)
	_check("tts_config still refused through tts_set", not (await _r({"cmd": "tts_set", "tts_engine": "sherpa"})).ok)
	await _frames(5)
	_check("vtt idle once its line is on the hand menu", not vtt.is_processing())
	var line := ""
	for e in (await _r({"cmd": "ui_get", "id_panel": "hand_menu"})).get("panel", {}).get("elements", []):
		if e.get("id") == "st_vtt": line = e.get("text", "")
		for c in e.get("children", []):
			if c.get("id") == "st_vtt": line = c.get("text", "")
	_check("hand menu shows vtt's line", line.contains("talk") or line.contains("Hold"), line)
	await _frames(30)
	_check("and stays idle (no loop on its own update)", not vtt.is_processing())
	_done()
