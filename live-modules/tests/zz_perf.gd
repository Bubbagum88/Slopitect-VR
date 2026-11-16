extends SlopitectModule
# Headless checks for perf.gd's perf_load, perf_config and frame history. Run: tests/run.sh lib perf zz_perf
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
	var perf: SlopitectModule = ctx["modules"].module("perf")
	var status := await _r({"cmd": "perf_status"})
	_check("perf_status shows the headset settings, foveation high by default", status.get("headset", {}).get("foveation") == "high"
		and status["headset"].get("cpu_level") == "sustained_high" and status["headset"].get("foveation_now") == "no headset", status.get("headset"))
	_check("perf_config refuses a wrong foveation", not (await _r({"cmd": "perf_config", "foveation": "max"})).get("ok", true))
	_check("perf_config refuses a wrong level", not (await _r({"cmd": "perf_config", "gpu_level": "fast"})).get("ok", true))
	_check("perf_config refuses an unknown key", not (await _r({"cmd": "perf_config", "speed": 3})).get("ok", true))
	var set := await _r({"cmd": "perf_config", "foveation": "medium", "foveation_dynamic": "false", "cpu_level": "sustained_low"})
	_check("perf_config changes them", set.get("ok", false) and set["headset"]["foveation"] == "medium"
		and set["headset"]["foveation_dynamic"] == false and set["headset"]["cpu_level"] == "sustained_low" and not set.has("note"), set)
	var kept = JSON.parse_string(FileAccess.get_file_as_string("user://perf.json"))
	_check("perf_config keeps them in user://perf.json", typeof(kept) == TYPE_DICTIONARY and kept.get("foveation") == "medium", kept)
	perf.settings = perf.DEFAULTS.duplicate()
	perf.call("_load")
	_check("they're read back after a restart", perf.settings["foveation"] == "medium" and perf.settings["cpu_level"] == "sustained_low", perf.settings)
	_check("perf_config reset", (await _r({"cmd": "perf_config", "reset": true}))["headset"]["foveation"] == "high")
	_check("physics matches the display by default (left alone with no headset)", perf.settings["physics_match_display"] == true
		and Engine.physics_ticks_per_second == 60, Engine.physics_ticks_per_second)
	_check("perf_config refuses a wrong physics_match_display", not (await _r({"cmd": "perf_config", "physics_match_display": 72})).get("ok", true))
	Engine.physics_ticks_per_second = 72  # as if it had matched a 72 Hz headset
	perf._was_physics_hz = 50
	ctx["modules"].unload("perf")
	await _wait(0.1)
	_check("unload puts physics ticks back", Engine.physics_ticks_per_second == 50)
	Engine.physics_ticks_per_second = 60
	_check("loads again", await _load("perf") == "")
	perf = ctx["modules"].module("perf")
	# Frame history: old frames are cut off now and then, never more than HISTORY seconds kept.
	perf._frame_ms = PackedFloat32Array()
	perf._frame_at = PackedFloat64Array()
	perf._first = 0
	var now := Time.get_ticks_msec() / 1000.0
	for i in 100:
		perf._frame_ms.append(10.0 if i < 60 else 20.0)
		perf._frame_at.append(now - 30.0 if i < 60 else now - 1.0)
	perf.call("_process", 0.02)
	var f: Dictionary = (await _r({"cmd": "perf_status"}))["frames"]
	_check("perf_status counts only the last 10 s", f["count"] == 41 and f["median_ms"] == 20.0, f)
	_check("old frames are dropped once they're half", perf._first == 0 and perf._frame_at.size() == 41, [perf._first, perf._frame_at.size()])
	await _wait(0.3)
	_check("frames keep counting after the cut", (await _r({"cmd": "perf_status"}))["frames"]["count"] > 41)
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
