extends SlopitectModule
# Headless checks for save.gd. Run: tests/run.sh save paths projects tools lib zz_save
# (save before lib and projects: the world still opens once, in the project's folder)
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


func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame


func _finish() -> void:
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


func _go() -> void:
	await _frames(10)
	var loader: Node = ctx["modules"]
	var save = loader.module("save")
	var lib = loader.module("lib")
	_check("nothing per frame", not save.is_processing() and not save.is_physics_processing())
	_check("autosave timer running", not (save.get("_timer") as Timer).is_stopped())
	var status := await _r({"cmd": "save_status"})
	_check("opened the project's folder", "/projects/start/saves/world.json" in str(status.get("world_file")), status)
	_check("lib.world_file agrees", lib.world_file("world.json") == status.get("world_file"), lib.world_file("world.json"))

	await _r({"cmd": "spawn", "shape": "box", "name": "zz_box", "position": [0, 1, -2]})
	var saved := await _r({"cmd": "save_now"})
	var world = lib.read_json(lib.world_file("world.json"))
	_check("save_now writes the shape", saved.get("ok", false) and typeof(world) == TYPE_DICTIONARY
		and world.get("shapes", []).any(func(s): return s.get("name") == "zz_box"), world)

	# A part whose module isn't loaded waits, and goes back when lib says it loaded.
	var paths_script: GDScript = loader.module("paths").get_script()
	loader.unload("paths")
	await _frames(2)
	save.call("_put_back", {"shapes": [], "paths": {"paths": {}, "next": 7}})
	_check("paths waits for its module", (save.get("_pending") as Dictionary).has("paths"))
	_check("shapes put back now", lib.world_node("zz_box") == null)
	loader.load_live("paths", paths_script)
	await _frames(3)
	_check("put back once paths loaded", not (save.get("_pending") as Dictionary).has("paths")
		and loader.module("paths").call("get_paths").get("next") == 7, loader.module("paths").call("get_paths"))

	# lib reloading: autosave pauses, then picks up again without opening the world twice.
	var lib_script: GDScript = lib.get_script()
	await _r({"cmd": "spawn", "shape": "sphere", "name": "zz_ball", "position": [1, 1, -2]})
	loader.unload("lib")
	await _frames(2)
	_check("without lib: autosave stops", (save.get("_timer") as Timer).is_stopped())
	_check("and saved first", (JSON.parse_string(FileAccess.get_file_as_string(status["world_file"])) as Dictionary)
		.get("shapes", []).any(func(s): return s.get("name") == "zz_ball"))
	loader.load_live("lib", lib_script)
	await _frames(3)
	_check("lib back: autosave again", not (save.get("_timer") as Timer).is_stopped())
	_check("the world wasn't loaded again", ctx["world"].get_node_or_null("zz_ball") != null
		and (await _r({"cmd": "save_status"})).get("world_file") == status["world_file"])
	lib = loader.module("lib")

	# Unloading save writes the world one last time and lets go of everything.
	await _r({"cmd": "spawn", "shape": "box", "name": "zz_last", "position": [2, 1, -2]})
	loader.unload("save")
	await _frames(2)
	world = lib.read_json(status["world_file"])
	_check("unload saves first", world.get("shapes", []).any(func(s): return s.get("name") == "zz_last"), world)
	_check("lib lets go of it", not str(lib.call("_status", {}).get("follows")).contains("save follows"))
	_finish()
