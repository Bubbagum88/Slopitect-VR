extends SlopitectModule
# Headless checks for tool_front.gd. Run: tests/run.sh controls vrui tools paths lib tool_front zz_tool_front
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


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _holder(id_panel: String) -> Node3D:
	return ctx["modules"].module("vrui")._holders.get(id_panel)


# Where the menu is, seen from the camera: how far in front of it.
func _ahead(id_panel: String) -> float:
	var cam: Node3D = ctx["camera"]
	return (_holder(id_panel).global_position - cam.global_position).dot(-cam.global_basis.z)


func _go() -> void:
	await _wait(1.0)
	_check("idle", not ctx["modules"].module("tool_front").is_processing())
	# Open the Tools window, then turn round and open a tool's menu from it:
	# without tool_front it opens where the Tools window was (behind you now).
	await _r({"cmd": "ui_show", "id_panel": "tools", "visible": true})
	var cam: Node3D = ctx["camera"]
	cam.global_transform = Transform3D(Basis(Vector3.UP, PI), cam.global_position)
	await _wait(0.1)
	_check("Tools window now behind you", _ahead("tools") < 0, _ahead("tools"))
	var opened := await _r({"cmd": "ui_press", "id_panel": "tools", "id_element": "t_paths"})
	await _wait(0.2)
	var panel: Dictionary = (await _r({"cmd": "ui_get", "id_panel": "tools_t_paths"})).get("panel", {})
	_check("tool menu open", panel.get("visible", false), [opened, panel.keys()])
	_check("tool menu in front of you", _ahead("tools_t_paths") > 0.2, _ahead("tools_t_paths"))
	ctx["modules"].unload("tool_front")
	_check("unloads cleanly", ctx["modules"].module("vrui").panel_shown.get_connections().all(func(c): return is_instance_valid(c.callable.get_object()) and c.callable.get_object().name != "tool_front"))
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
