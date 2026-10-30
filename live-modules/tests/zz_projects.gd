extends SlopitectModule
# Headless checks for projects.gd. Run: tests/run.sh save projects lib zz_projects
var _fails := 0
var _passes := 0
var _changes := []


func setup() -> String:
	_go.call_deferred()
	return ""


func lib_ready(lib) -> void:
	if lib:
		lib.follow(self, "projects", "project_changed", _on_project)


func _on_project(project: String, folder: String) -> void:
	_changes.append([project, folder.get_file()])


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


func _go() -> void:
	await _frames(5)
	var projects = ctx["modules"].module("projects")
	var save = ctx["modules"].module("save")
	_check("no per-frame work", not projects.has_method("_process"))
	_check("joined save once lib came", String(save.call("folder")).ends_with("projects/start/saves"), save.call("folder"))
	_check("in project start", (await _r({"cmd": "projects_current"})).get("name") == "start")

	var made := await _r({"cmd": "projects_new", "name": "zz_two", "open": true})
	_check("new and open", made.get("ok") and made.get("opened") == "zz_two", made)
	_check("project_changed on open", _changes.back() == ["zz_two", "zz_two"], _changes)
	_check("save follows", String(save.call("folder")).ends_with("projects/zz_two/saves"), save.call("folder"))
	_check("listed", (await _r({"cmd": "projects_list"})).projects.any(func(p): return p.name == "zz_two" and p.current))

	# save reloaded: projects joins it again, in the same project.
	await _r({"cmd": "code_unload", "name": "save"})
	await _frames(2)
	_check("no save: open refused", not (await _r({"cmd": "projects_open", "name": "start"})).ok)
	await _r({"cmd": "code_load", "name": "save"})
	await _frames(3)
	save = ctx["modules"].module("save")
	_check("save back: joined again", String(save.call("folder")).ends_with("projects/zz_two/saves"), save.call("folder"))
	_check("project_changed again", _changes.back() == ["zz_two", "zz_two"] and _changes.size() >= 2, _changes)

	var back := await _r({"cmd": "projects_open", "name": "start"})
	_check("open start", back.get("ok"), back)
	_check("project_changed to start", _changes.back() == ["start", "start"], _changes)
	_check("bad name refused", not (await _r({"cmd": "projects_new", "name": "a b"})).ok)
	DirAccess.remove_absolute(OS.get_user_data_dir() + "/files_home/projects/zz_two/project.json")
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
