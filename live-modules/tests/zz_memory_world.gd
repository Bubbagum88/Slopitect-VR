extends SlopitectModule
# Headless checks for memory.gd following the current project (zz_memory covers the rest).
# Run: tests/run.sh save projects memory lib zz_memory_world
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


func _go() -> void:
	for i in 5: await get_tree().process_frame
	_check("in the current project's world", (await _r({"cmd": "memory_status"})).get("world") == "start", await _r({"cmd": "memory_status"}))
	await _r({"cmd": "projects_new", "name": "zz_other", "open": true})
	_check("follows project_changed", (await _r({"cmd": "memory_status"})).get("world") == "zz_other", await _r({"cmd": "memory_status"}))
	await _r({"cmd": "code_unload", "name": "projects"})
	await get_tree().process_frame
	_check("no projects: the default world", (await _r({"cmd": "memory_status"})).get("world") == "default", await _r({"cmd": "memory_status"}))
	_check("never reads projects' file", not ctx["modules"].module("memory").get_script().source_code.contains("projects.json"))
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
