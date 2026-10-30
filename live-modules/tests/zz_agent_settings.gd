extends SlopitectModule
# Headless checks for agent_settings.gd. Run: tests/run.sh agent_settings zz_agent_settings
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
	var info: Dictionary = ctx["modules"].module("agent_settings").settings_info()
	_check("settings_info has a title", typeof(info.get("title")) == TYPE_STRING and not info["title"].is_empty(), info)
	var long := []
	for s in info.get("settings", []):
		if String(s.get("label", "")).length() > 40:
			long.append(s["label"])
		if not s.get("set", {}).get("cmd", "") == "agent_budget":
			long.append("not agent_budget: " + str(s))
	_check("labels 40 characters or less, all set through agent_budget", long.is_empty(), long)
	_check("title 40 characters or less", String(info["title"]).length() <= 40, info["title"])
	print("agent_settings: ", info["title"], ", ", info.get("settings", []).size(), " settings")
	_finish()
