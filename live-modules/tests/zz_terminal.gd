extends SlopitectModule
# Headless checks for terminal.gd. Run: tests/run.sh controls vrui chat terminal lib zz_terminal
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
	var t = ctx["modules"].module("terminal")
	_check("idle at start", not t.is_processing())
	_check("window built", (await _r({"cmd": "ui_get", "id_panel": "terminal"})).get("ok"))
	var r := await _r({"cmd": "terminal_run", "line": "ping"})
	_check("runs a line", JSON.stringify(await _r({"cmd": "terminal_status"})).contains("pong"), r)
	var modes := []
	t.mode_changed.connect(func(m): modes.append(m))
	await _r({"cmd": "ui_show", "id_panel": "terminal", "visible": true})
	await _r({"cmd": "terminal_mode", "mode": "chat"})
	_check("mode_changed", modes == ["chat"], modes)
	_check("chat shown, chat.gd loaded: still idle (it follows chat.gd)", not t.is_processing())
	await _r({"cmd": "code_unload", "name": "chat"})
	await _frames(2)
	_check("no chat.gd: reads the agent itself", t.is_processing())
	await _r({"cmd": "ui_show", "id_panel": "terminal", "visible": false})
	await _frames(1)
	_check("hidden: idle", not t.is_processing())
	await _r({"cmd": "terminal_mode", "mode": "terminal"})
	await _r({"cmd": "ui_remove", "id_panel": "terminal"})
	await _frames(2)
	_check("window taken away: built again", (await _r({"cmd": "ui_get", "id_panel": "terminal"})).get("ok"))
	await _r({"cmd": "ui_show", "id_panel": "chat", "visible": true})
	await _frames(2)
	var shown := {}
	for p in (await _r({"cmd": "ui_list"})).panels:
		shown[p.id_panel] = p.visible
	_check("the agent's window opens the terminal's Chat", not shown.get("chat", true) and shown.get("terminal") and (await _r({"cmd": "terminal_status"})).get("mode") == "chat", shown)
	_done()
