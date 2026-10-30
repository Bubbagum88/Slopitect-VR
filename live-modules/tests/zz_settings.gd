extends SlopitectModule
# Headless checks for settings.gd. Run: tests/run.sh settings controls vrui hands lib zz_settings
var _fails := 0
var _passes := 0
var _toggle := false
var _bad := false
var _lib: SlopitectModule


func setup() -> String:
	register("zz_flag", _flag, "test")
	_go.call_deferred()
	return ""


func lib_ready(lib) -> void:
	_lib = lib


func _flag(q: Dictionary) -> Dictionary:
	_toggle = q.get("on")
	return {"ok": true}


func settings_info() -> Dictionary:
	if _bad:
		return {"title": "Bad", "settings": [{"id": "x", "type": "button", "label": "x", "set": {"cmd": "controls_config", "speed": 9}}]}
	return {"title": "Test", "order": 50, "settings": [{"id": "flag", "type": "toggle", "label": "A flag", "value": _toggle, "set": {"cmd": "zz_flag", "on": "{value}"}}]}


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


func _ids() -> Array:
	var out := []
	var stack: Array = (await _r({"cmd": "ui_get", "id_panel": "settings"})).get("panel", {}).get("elements", []).duplicate()
	while not stack.is_empty():
		var e = stack.pop_front()
		out.append(e["id"])
		stack.append_array(e.get("children", []))
	return out


func _go() -> void:
	await _frames(10)
	var settings = ctx["modules"].module("settings")
	_check("never polls", not settings.has_method("_process"))
	var r = await _r({"cmd": "settings_do", "act": "toggle"})
	_check("window opens", r.ok and (await _r({"cmd": "ui_get", "id_panel": "settings"})).panel.visible, r)
	var ids = await _ids()
	_check("sections drawn", "zz_settings_flag" in ids and "hands_skin" in ids, ids)
	r = await _r({"cmd": "ui_press", "id_panel": "settings", "id_element": "zz_settings_flag"})
	_check("toggle through the window", r.ok and _toggle == true, r)
	_check("bad value refused", not (await _r({"cmd": "settings_set", "module": "zz_settings", "id_setting": "flag", "value": "yes"})).ok)

	# A change with no touch() isn't seen (nothing polls); with touch() it is.
	await _frames(2)
	_bad = true
	await _frames(70)
	_check("no redraw without touch", "zz_settings_flag" in await _ids())
	_lib.touch(self)
	await _frames(2)
	ids = await _ids()
	_check("touch redraws; _config setter shown as a problem", "zz_settings_problem" in ids and not "zz_settings_x" in ids, ids)
	_bad = false
	_lib.touch(self)

	# Modules coming and going.
	await _r({"cmd": "code_unload", "name": "hands"})
	await _frames(2)
	_check("unloaded module's section goes", not "hands_skin" in await _ids())
	await _r({"cmd": "code_load", "name": "hands"})
	await _frames(3)
	_check("loaded again: back", "hands_skin" in await _ids())
	r = await _r({"cmd": "ui_press", "id_panel": "settings", "id_element": "hands_skin_3"})
	await _frames(2)
	_check("hands setting through the window, ticked", r.ok and (await _r({"cmd": "hands_status"})).settings.skin.to_lower() == "#5c3a24", r)
	await _r({"cmd": "hands_config", "reset": true})

	# Closed: changes don't redraw it; opened: drawn fresh.
	await _r({"cmd": "settings_do", "act": "toggle"})
	_check("window closes", not (await _r({"cmd": "ui_get", "id_panel": "settings"})).panel.visible)
	_bad = true
	_lib.touch(self)
	await _frames(2)
	_check("closed: not redrawn", "zz_settings_flag" in await _ids())
	await _r({"cmd": "settings_do", "act": "toggle"})
	await _frames(2)
	_check("opened: drawn fresh", "zz_settings_problem" in await _ids())
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
