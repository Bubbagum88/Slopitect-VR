extends SlopitectModule
# Headless checks for pause.gd. Run: tests/run.sh pause controls vrui tools lib zz_pause
# (pause before lib and vrui: the hand menu is still built once they're there)
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


func _finish() -> void:
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


func _ids(id_panel: String) -> Array:
	var out := []
	var stack: Array = (await _r({"cmd": "ui_get", "id_panel": id_panel})).get("panel", {}).get("elements", []).duplicate()
	while not stack.is_empty():
		var element: Dictionary = stack.pop_front()
		stack.append_array(element.get("children", []))
		out.append(element.get("id"))
	return out


func _visible(id_panel: String) -> bool:
	for panel in (await _r({"cmd": "ui_list"})).get("panels", []):
		if panel.get("id_panel") == id_panel:
			return panel.get("visible", false)
	return false


func _go() -> void:
	await _frames(10)
	var loader: Node = ctx["modules"]
	var pause = loader.module("pause")
	_check("nothing per frame", not pause.is_processing() and not pause.is_physics_processing())
	var ids := await _ids("hand_menu")
	_check("hand menu built", "home" in ids and "undo" in ids and "redo" in ids, ids)
	_check("wrist panel hidden: one hand menu", not await _visible("wrist"))

	# A module going and coming: its buttons go and come with it.
	var tools_script: GDScript = loader.module("tools").get_script()
	loader.unload("tools")
	await _frames(3)
	ids = await _ids("hand_menu")
	_check("tools gone: no Undo", not "undo" in ids and "home" in ids, ids)
	loader.load_live("tools", tools_script)
	await _frames(3)
	ids = await _ids("hand_menu")
	_check("tools back: Undo again", "undo" in ids, ids)

	# Showing the wrist panel hides it again; removing the hand menu builds it again.
	await _r({"cmd": "ui_show", "id_panel": "wrist", "visible": true})
	await _frames(2)
	_check("wrist hidden again", not await _visible("wrist"))
	await _r({"cmd": "ui_remove", "id_panel": "hand_menu"})
	await _frames(2)
	_check("hand menu back after removal", "home" in await _ids("hand_menu"))

	# Rebuilding the menu's own panel doesn't set off another rebuild.
	var signature: String = pause.get("_hand_signature")
	loader.module("lib").touch(loader.module("tools"))
	await _frames(2)
	_check("a touch with nothing new keeps the menu", pause.get("_hand_signature") == signature and not pause.get("_hand_soon"))

	var shown := await _r({"cmd": "pause_do", "act": "toggle"})
	_check("pause menu opens", shown.get("ok", false) and await _visible("pause"), shown)
	await _r({"cmd": "pause_do", "act": "toggle"})
	_check("and closes", not await _visible("pause"))
	_finish()
