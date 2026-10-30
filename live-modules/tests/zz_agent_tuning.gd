extends SlopitectModule
# Headless checks for agent_tuning.gd's skills folder. Run: tests/run.sh lib agent_tuning zz_agent_tuning
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
	await _wait(0.5)
	var folder: String = ctx["modules"].module("lib").home() + "/modules/agent_skills/zz-skill"
	DirAccess.make_dir_recursive_absolute(folder)
	var f := FileAccess.open(folder + "/SKILL.md", FileAccess.WRITE)
	f.store_string("---\nname: zz-skill\ndescription: a test skill\n---\nbody\n")
	f.close()
	var tuning = ctx["modules"].module("agent_tuning")
	var found: Dictionary = tuning.skills({})
	_check("finds a skill in the Slopitect folder", found.has("zz-skill") and found["zz-skill"]["description"] == "a test skill", found)
	_check("keeps the shipped ones", tuning.skills({"code": {"description": "x", "always": false}}).has("code"))
	ctx["modules"].unload("lib")
	await _wait(0.1)
	var without: Dictionary = tuning.skills({"code": {"description": "x", "always": false}})
	_check("without lib: shipped skills only", without.keys() == ["code"], without)
	_check("system prompt still builds", tuning.system_prompt([{"name": "code", "description": "x", "always": false, "body": ""}]).length() > 100)
	_finish()
