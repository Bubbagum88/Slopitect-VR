extends SlopitectModule
# Headless checks for perf.gd's perf_load. Run: tests/run.sh lib perf zz_perf
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
	var timed := await _r({"cmd": "perf_load"})
	_check("perf_load with lib", timed.get("ok", false), timed)
	_check("perf_load times the modules folder", "perf" in str(timed) and "lib" in str(timed), timed)
	var one := await _r({"cmd": "perf_load", "name": "perf"})
	_check("perf_load one module", one.get("ok", false), one)
	ctx["modules"].unload("lib")
	await _wait(0.1)
	var without := await _r({"cmd": "perf_load"})
	_check("perf_load says it needs lib", not without.get("ok", true) and "lib" in str(without.get("error")), without)
	_check("perf_status still works", (await _r({"cmd": "perf_status"})).get("ok", false))
	_finish()
