extends SlopitectModule
# Headless checks for prefabs.gd. Run: tests/run.sh lib tools prefabs zz_prefabs
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


func _finish() -> void:
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


func _go() -> void:
	await _wait(1.0)
	var lib = ctx["modules"].module("lib")
	await _r({"cmd": "spawn", "shape": "box", "name": "zz_p1", "position": [0, 0.5, -2], "scale": [0.3, 0.3, 0.3]})
	await _r({"cmd": "spawn", "shape": "sphere", "name": "zz_p2", "position": [0.5, 0.5, -2], "scale": [0.3, 0.3, 0.3]})
	var saved := await _r({"cmd": "prefabs_save", "name": "zz_set", "prefixes": ["zz_p"]})
	_check("prefabs_save", saved.get("ok", false) and saved.get("shapes") == 2, saved)
	_check("in the Slopitect folder", FileAccess.file_exists(lib.home() + "/prefabs/zz_set.json"))
	_check("listed", (await _r({"cmd": "prefabs_list"})).get("prefabs", []).any(func(p): return p.get("name") == "zz_set"))
	var placed := await _r({"cmd": "prefabs_place", "name": "zz_set", "position": [3, 0, -2]})
	_check("prefabs_place", placed.get("ok", false), placed)
	_check("copies in the world", lib.world_node("zz_p1_2") != null and lib.world_node("zz_p2_2") != null)
	await _r({"cmd": "tools_undo"})
	_check("one undo takes the copy away", lib.world_node("zz_p1_2") == null and lib.world_node("zz_p2_2") == null)
	ctx["modules"].unload("lib")
	await _wait(0.1)
	var waiting := await _r({"cmd": "prefabs_list"})
	_check("without lib: says it waits", not waiting.get("ok", true) and "lib" in str(waiting.get("error")), waiting)
	_finish()
