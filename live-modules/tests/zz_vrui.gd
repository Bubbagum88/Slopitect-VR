extends SlopitectModule
# Headless checks for vrui.gd's window signals. Run: tests/run.sh controls vrui lib zz_vrui
var _fails := 0
var _passes := 0
var _heard := []


func setup() -> String:
	_go.call_deferred()
	return ""


func lib_ready(lib) -> void:
	if lib:
		lib.follow(self, "vrui", "panel_shown", _shown)
		lib.follow(self, "vrui", "page_changed", _page)
		lib.follow(self, "vrui", "panel_changed", _changed)


func _shown(id_panel: String, on: bool) -> void:
	_heard.append(["shown", id_panel, on])


func _page(id_panel: String, page: String) -> void:
	_heard.append(["page", id_panel, page])


func _changed(id_panel: String) -> void:
	_heard.append(["changed", id_panel])


func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if ok: _passes += 1
	else: _fails += 1


func _r(q: Dictionary) -> Dictionary:
	return ctx["server"].run(q)


func _go() -> void:
	await get_tree().process_frame
	var r := _r({"cmd": "ui_add", "id_panel": "zz_win", "title": "Test", "place": "front", "chrome": true,
		"pages": ["A", "B"], "elements": [{"id": "t", "type": "text", "text": "hi"}]})
	_check("added", r.get("ok"), r)
	_check("panel_changed on add, not shown", _heard == [["changed", "zz_win"]], _heard)
	_heard.clear()
	_r({"cmd": "ui_show", "id_panel": "zz_win", "visible": true})
	_check("panel_shown true", _heard == [["shown", "zz_win", true]], _heard)
	_heard.clear()
	_r({"cmd": "ui_show", "id_panel": "zz_win", "visible": true})
	_check("no repeat when already shown", _heard.is_empty(), _heard)
	_r({"cmd": "ui_page", "id_panel": "zz_win", "page": "B"})
	_check("page_changed", _heard == [["page", "zz_win", "B"]], _heard)
	_heard.clear()
	_r({"cmd": "ui_show", "id_panel": "zz_win", "visible": false})
	_check("panel_shown false", _heard == [["shown", "zz_win", false]], _heard)
	_heard.clear()
	_r({"cmd": "ui_update", "id_panel": "zz_win", "visible": true})
	_check("shown through ui_update", ["shown", "zz_win", true] in _heard and ["changed", "zz_win"] in _heard, _heard)
	# Several elements out in one call: one panel_changed, one save at the end of the frame.
	_r({"cmd": "ui_element_add", "id_panel": "zz_win", "element": {"id": "u", "type": "text", "text": "u"}})
	_r({"cmd": "ui_element_add", "id_panel": "zz_win", "element": {"id": "v", "type": "text", "text": "v"}})
	_heard.clear()
	r = _r({"cmd": "ui_element_remove", "id_panel": "zz_win", "ids": ["u", "v", "nope"]})
	var left: Array = _r({"cmd": "ui_get", "id_panel": "zz_win"}).get("panel", {}).get("elements", []).map(func(e): return e["id"])
	_check("ids: removed together, one change", r.get("removed") == ["u", "v"] and r.get("missing") == ["nope"]
		and _heard == [["changed", "zz_win"]] and left == ["t"], [r, _heard, left])
	_check("ids: none there is an error", not _r({"cmd": "ui_element_remove", "id_panel": "zz_win", "ids": ["nope"]}).get("ok", true))
	await get_tree().process_frame
	await get_tree().process_frame
	var saved_ids := []
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://ui.json"))
	for panel in (saved if saved is Array else []):
		if panel.get("id_panel") == "zz_win":
			saved_ids = panel.get("elements", []).map(func(e): return e["id"])
	_check("ui.json written by the end of the frame", saved_ids == ["t"], saved_ids)
	_heard.clear()
	_r({"cmd": "ui_remove", "id_panel": "zz_win"})
	_check("removed: changed and hidden", ["changed", "zz_win"] in _heard and ["shown", "zz_win", false] in _heard, _heard)
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
