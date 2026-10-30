extends SlopitectModule
# Headless checks for worlds.gd. Run: tests/run.sh lib controls vrui projects save worlds zz_worlds
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


# Loads a module again from its file in the Slopitect modules folder.
func _load(module_name: String) -> String:
	var s := GDScript.new()
	s.source_code = FileAccess.get_file_as_string(OS.get_user_data_dir() + "/files_home/modules/%s.gd" % module_name)
	s.reload()
	var problem: String = ctx["modules"].load_live(module_name, s)
	await _wait(0.1)
	return problem


# The module loaded again with no lib, then lib loaded after it.
func _without_lib(module_name: String) -> void:
	ctx["modules"].unload("lib")
	ctx["modules"].unload(module_name)
	await _wait(0.1)
	_check(module_name + " loads without lib", await _load(module_name) == "")


func _finish() -> void:
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


func _go() -> void:
	await _wait(1.0)
	var status := await _r({"cmd": "worlds_status"})
	_check("worlds_status", status.get("ok", false) and "worlds" in status.get("modules", []), status)
	var shown := await _r({"cmd": "worlds_do", "act": "toggle"})
	_check("toggle opens the window", shown.get("ok", false), shown)
	_check("window visible", (await _r({"cmd": "ui_get", "id_panel": "worlds"})).get("panel", {}).get("visible", false))
	var made := await _r({"cmd": "worlds_do", "act": "new_project", "name": "zz_world"})
	_check("new_project", made.get("ok", false), made)
	status = await _r({"cmd": "worlds_status"})
	_check("in the new world", status.get("world") == "zz_world", status)
	_check("bad folder refused", not (await _r({"cmd": "worlds_do", "act": "folder", "path": "../x"})).get("ok", true))
	_check("can't unload itself", not (await _r({"cmd": "worlds_do", "act": "unload_module", "name": "worlds"})).get("ok", true))
	await _r({"cmd": "worlds_do", "act": "toggle"})
	_check("toggle closes it", not (await _r({"cmd": "ui_get", "id_panel": "worlds"})).get("panel", {}).get("visible", true))
	ctx["modules"].unload("worlds")
	_check("unload removes the window", not (await _r({"cmd": "ui_get", "id_panel": "worlds"})).get("ok", false))
	_finish()
