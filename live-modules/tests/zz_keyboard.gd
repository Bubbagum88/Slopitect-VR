extends SlopitectModule
# Headless checks for keyboard.gd. Run: tests/run.sh controls vrui chat terminal keyboard lib zz_keyboard
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
	var kb = ctx["modules"].module("keyboard")
	_check("never polls", not kb.has_method("_process"))
	_check("its window is built", (await _r({"cmd": "ui_get", "id_panel": "keyboard"})).get("ok"))
	_check("chat window's keys taken off", not "shift" in await _ids("chat"))
	await _r({"cmd": "ui_show", "id_panel": "terminal", "visible": true})
	await _frames(2)
	var st := await _r({"cmd": "keyboard_status"})
	_check("types into the open terminal, command keys", st.get("typing_into") == "terminal" and st.get("layout") == "command", st)
	await _r({"cmd": "terminal_mode", "mode": "chat"})
	await _frames(2)
	_check("terminal in chat: word keys", (await _r({"cmd": "keyboard_status"})).get("layout") == "words")
	await _r({"cmd": "terminal_mode", "mode": "terminal"})
	await _frames(2)
	_check("back to command keys", (await _r({"cmd": "keyboard_status"})).get("layout") == "command")
	await _r({"cmd": "keyboard_type", "text": "ping"})
	var sent := await _r({"cmd": "keyboard_key", "key": "run"})
	_check("Run sends to the terminal", sent.get("ok"), sent)
	_check("terminal ran it", JSON.stringify(await _r({"cmd": "terminal_status"})).contains("pong"), await _r({"cmd": "terminal_status"}))
	await _r({"cmd": "ui_show", "id_panel": "terminal", "visible": false})
	await _frames(2)
	_check("terminal hidden: not its target", (await _r({"cmd": "keyboard_status"})).get("typing_into") != "terminal")
	await _r({"cmd": "ui_remove", "id_panel": "keyboard"})
	await _frames(2)
	_check("its window taken away: built again", (await _r({"cmd": "ui_get", "id_panel": "keyboard"})).get("ok"))
	_done()
