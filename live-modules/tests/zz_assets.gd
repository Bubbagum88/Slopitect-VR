extends SlopitectModule
# Headless checks for assets.gd's lib parts (no network). Run: tests/run.sh lib assets zz_assets
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
	var home: String = ctx["modules"].module("lib").home()
	_check("models folder made", DirAccess.dir_exists_absolute(home + "/assets/polyhaven"))
	var place := await _r({"cmd": "assets_place", "id": "zz_none"})
	_check("place of a model not downloaded refused", not place.get("ok", true) and not "lib" in str(place.get("error")), place)
	var got := await _r({"cmd": "assets_get", "id": "../bad"})
	_check("bad id refused", not got.get("ok", true) and not "lib" in str(got.get("error")), got)

	await _without_lib("assets")
	var waiting := await _r({"cmd": "assets_get", "id": "zz_none"})
	_check("assets_get waits for lib", not waiting.get("ok", true) and "lib" in str(waiting.get("error")), waiting)
	waiting = await _r({"cmd": "assets_place", "id": "zz_none"})
	_check("assets_place waits for lib", not waiting.get("ok", true) and "lib" in str(waiting.get("error")), waiting)
	_check("assets_placed works without lib", (await _r({"cmd": "assets_placed"})).get("ok", false))
	_check("lib loads after", await _load("lib") == "")
	place = await _r({"cmd": "assets_place", "id": "zz_none"})
	_check("assets_place past the lib check", not "lib" in str(place.get("error")), place)
	_finish()
