extends SlopitectModule
# Headless checks for lib.gd. Run: tests/run.sh lib zz_lib
var _fails := 0
var _passes := 0
var _lib: SlopitectModule
var _readies := 0  # lib_ready(lib) calls
var _goodbyes := 0  # lib_ready(null) calls
var _pings := []
var _loads := []
var _unloads := []


func setup() -> String:
	_go.call_deferred()
	return ""


func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		_goodbyes += 1
		return
	_readies += 1
	lib.follow(self, "zz_owner", "ping", _on_ping)
	lib.watch(self, "zz_owner", _on_load, _on_unload)


func _on_ping(x) -> void:
	_pings.append(x)


func _on_load(m) -> void:
	_loads.append(String(m.name))


func _on_unload(m) -> void:
	_unloads.append(String(m.name))


func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if ok: _passes += 1
	else: _fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _script(source: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = source
	s.reload()
	return s


const OWNER := "extends SlopitectModule\nsignal ping(x)\n"
const BROKEN := "extends SlopitectModule\nfunc setup() -> String:\n\treturn \"broken on purpose\"\n"


func _loader_links() -> int:
	var loader: Node = ctx["modules"]
	return loader.get_signal_connection_list("child_entered_tree").size() + loader.get_signal_connection_list("child_exiting_tree").size()


func _go() -> void:
	await _wait(0.5)
	var loader = ctx["modules"]
	_check("lib loaded", loader.module("lib") != null)
	_check("lib_ready called once", _readies == 1 and _lib == loader.module("lib"), _readies)
	_check("module() finds modules", _lib.module("zz_lib") == self and _lib.module("lib") == _lib and _lib.module("nope") == null)

	# An owner loads after its follower asked: connected when it arrives.
	var loaded_names := []
	_lib.module_loaded.connect(func(n): loaded_names.append(n))
	_check("owner loads", loader.load_live("zz_owner", _script(OWNER)) == "")
	await _wait(0.1)
	_check("module_loaded(zz_owner)", loaded_names == ["zz_owner"], loaded_names)
	_check("watch on_load", _loads == ["zz_owner"], _loads)
	loader.module("zz_owner").ping.emit(1)
	_check("follow connects on load", _pings == [1], _pings)

	# Unload it: its signal lets go, on_unload runs; reload: connected again.
	var owner_node = loader.module("zz_owner")
	loader.unload("zz_owner")
	_check("watch on_unload", _unloads == ["zz_owner"], _unloads)
	_check("follow let go", owner_node.get_signal_connection_list("ping").is_empty())
	loader.load_live("zz_owner", _script(OWNER))
	await _wait(0.1)
	loader.module("zz_owner").ping.emit(2)
	_check("follow again after reload", _pings == [1, 2], _pings)
	_check("on_load again", _loads == ["zz_owner", "zz_owner"], _loads)

	# A module whose setup fails never counts as loaded.
	loaded_names.clear()
	_check("broken module refused", loader.load_live("zz_broken", _script(BROKEN)) != "")
	await _wait(0.1)
	_check("no module_loaded for it", loaded_names.is_empty(), loaded_names)

	# Things in the world.
	var world: Node3D = ctx["world"]
	var shape := MeshInstance3D.new()
	shape.name = "zz_box"
	shape.mesh = BoxMesh.new()
	world.add_child(shape)
	shape.global_position = Vector3(1, 2, 3)
	var holder := Node3D.new()
	holder.name = "PolyHaven"
	world.add_child(holder)
	var model := Node3D.new()
	model.name = "zz_model"
	holder.add_child(model)
	var model_mesh := MeshInstance3D.new()
	model_mesh.mesh = BoxMesh.new()
	model.add_child(model_mesh)
	var other := Node3D.new()
	other.name = "zz_path"
	world.add_child(other)
	_check("world_node finds a shape", _lib.world_node("zz_box") == shape)
	_check("world_node finds a model", _lib.world_node("zz_model") == model)
	_check("world_node not the holder", _lib.world_node("PolyHaven") == null)
	_check("world_node bad names", _lib.world_node("") == null and _lib.world_node(3) == null and _lib.world_node("a/b") == null)
	_check("thing skips non-mesh world children", _lib.thing("zz_path") == null and _lib.world_node("zz_path") == other)
	_check("thing finds shape and model", _lib.thing("zz_box") == shape and _lib.thing("zz_model") == model)
	_check("things lists both", shape in _lib.things() and model in _lib.things() and not other in _lib.things())
	_check("is_model", _lib.is_model(model) and not _lib.is_model(shape))
	var box: AABB = _lib.world_box(shape)
	_check("world_box", box.get_center().is_equal_approx(Vector3(1, 2, 3)) and box.size.is_equal_approx(Vector3.ONE), box)

	# Files.
	var path: String = _lib.home() + "/zz_lib_test.json"
	DirAccess.make_dir_recursive_absolute(_lib.home())
	_check("write_json", _lib.write_json(path, {"a": 1}) == "")
	_check("read_json", _lib.read_json(path) == {"a": 1.0}, _lib.read_json(path))
	_check("read_json missing is null", _lib.read_json(path + ".none") == null)
	DirAccess.remove_absolute(path)
	_check("world_file without save: saves/", _lib.world_file("x.json") == _lib.home() + "/saves/x.json", _lib.world_file("x.json"))

	# touch() -> info_changed.
	var touched := []
	_lib.info_changed.connect(func(n): touched.append(n))
	_lib.touch(self)
	_check("touch emits info_changed", touched == ["zz_lib"], touched)

	var status: Dictionary = ctx["server"].run({"cmd": "lib_status"})
	_check("lib_status", status.get("ok") and "zz_lib follows zz_owner.ping" in status.get("follows", []), status)

	# lib unloads: modules are told, and nothing of it is left connected.
	var before := _loader_links()
	var owner_now = loader.module("zz_owner")
	loader.unload("lib")
	_check("lib_ready(null) on unload", _goodbyes == 1 and _lib == null, _goodbyes)
	_check("loader signals let go", _loader_links() == before - 2, [before, _loader_links()])
	_check("owner signal let go", owner_now.get_signal_connection_list("ping").is_empty())
	await _wait(0.1)

	# lib loads again, after the module: lib_ready again, links made again.
	var lib_source := FileAccess.get_file_as_string(_home_modules() + "/lib.gd")
	_check("lib reloads", loader.load_live("lib", _script(lib_source)) == "")
	await _wait(0.1)
	_check("lib_ready again", _readies == 2 and _lib != null, _readies)
	owner_now.ping.emit(3)
	_check("follow again after lib reload", _pings == [1, 2, 3], _pings)

	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


func _home_modules() -> String:
	return OS.get_user_data_dir() + "/files_home/modules"
