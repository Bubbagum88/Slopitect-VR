extends SlopitectModule
# Headless checks for aimsg.gd. Run: tests/run.sh lib aimsg zz_aimsg
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
	var set := await _r({"cmd": "aimsg_config", "cols": 50, "rows": 10})
	_check("aimsg_config", set.get("ok", false), set)
	var saved = ctx["modules"].module("lib").read_json("user://aimsg.json")
	_check("saved through lib", typeof(saved) == TYPE_DICTIONARY and int(saved.get("cols", 0)) == 50, saved)
	var aimsg = ctx["modules"].module("aimsg")
	var text: String = aimsg.format(["agent: " + "word ".repeat(30)], {})
	_check("wraps at the new width", text.split("\n").size() > 1 and Array(text.split("\n")).all(func(l): return l.length() <= 50), text)

	await _without_lib("aimsg")
	aimsg = ctx["modules"].module("aimsg")
	_check("defaults until lib", int(aimsg.settings["cols"]) == 38, aimsg.settings)
	_check("lib loads after", await _load("lib") == "")
	_check("saved size once lib is there", int(aimsg.settings["cols"]) == 50 and int(aimsg.settings["rows"]) == 10, aimsg.settings)
	_finish()
