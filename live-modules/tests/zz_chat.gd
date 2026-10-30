extends SlopitectModule
# Headless checks for chat.gd. Run: tests/run.sh controls chat vrui lib zz_chat
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
	var chat = ctx["modules"].module("chat")
	_check("filled vrui's chat window (vrui loaded after it)", "chat_tools" in await _ids("chat"))
	var told := []
	chat.transcript_changed.connect(func(): told.append(1))
	await _r({"cmd": "chat_clear"})
	_check("transcript_changed", told.size() >= 1, told)
	await _r({"cmd": "ui_update", "id_panel": "chat", "elements": [{"id": "x", "type": "text", "text": "plain"}]})
	await _frames(2)
	_check("window changed away: filled again", "chat_tools" in await _ids("chat"))
	await _r({"cmd": "code_unload", "name": "vrui"})
	await _r({"cmd": "code_load", "name": "vrui"})
	await _frames(3)
	_check("vrui reloaded: filled again", "chat_tools" in await _ids("chat"))
	_done()
