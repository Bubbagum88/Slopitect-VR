extends SlopitectModule
# Headless checks for textures.gd. Run: tests/run.sh lib save projects tools textures zz_textures
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
	var textures = ctx["modules"].module("textures")
	var lib = ctx["modules"].module("lib")
	_check("idle with nothing textured", not textures.is_processing())
	await _r({"cmd": "spawn", "shape": "box", "name": "zz_t", "position": [0, 1, -2]})
	var put := await _r({"cmd": "textures_apply", "names": ["zz_t"], "texture": "noise"})
	_check("textures_apply", put.get("ok", false), put)
	_check("checking while something is textured", textures.is_processing())
	var file: String = lib.world_file("textures.json")
	_check("kept in the world's folder", "projects/" in file and (lib.read_json(file) as Dictionary).has("zz_t"), file)
	# A colour change replaces the material; the check puts the texture back.
	var node: MeshInstance3D = lib.world_node("zz_t")
	node.material_override = StandardMaterial3D.new()
	await _wait(2.5)
	_check("texture put back after a material change", (node.material_override as StandardMaterial3D).albedo_texture != null)
	# Another project: its own (empty) file, then back again.
	await _r({"cmd": "projects_new", "name": "zz_other", "open": true})
	await _wait(0.2)
	_check("other project: nothing textured, idle", (await _r({"cmd": "textures_status"})).get("textures", {"x": 1}).is_empty() and not textures.is_processing(), await _r({"cmd": "textures_status"}))
	await _r({"cmd": "projects_open", "name": "start"})
	await _wait(0.2)
	_check("back: textured again", lib.world_file("textures.json") == file and textures.is_processing())
	await _r({"cmd": "textures_clear", "names": ["zz_t"]})
	_check("cleared: idle", not textures.is_processing())
	_finish()
