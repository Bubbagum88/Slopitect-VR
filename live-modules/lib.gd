extends SlopitectModule

# Slopitect live module: lib, the shared helpers and the module events.
# The one place for code more than one module needs, so it's never
# copy-pasted: finding a thing in the world and its box, the Slopitect
# folder and the open world's files, reading and writing JSON. And the
# events modules use instead of checking on each other every frame:
#   module_loaded(name), module_unloaded(name)  any module coming or going
#   info_changed(name)  a module's menu_info/hand_info/tool_info/settings_info
#       changed (it calls lib.touch(self)), for the windows that show them
#   thing_entered(node)  a shape or placed model joined the world (made,
#       put back by save, an undo), once it's in place
#   thing_exited(name)  a shape or placed model left the world and isn't
#       back by the next frame (deleted, not just moved between parents)
#   watch(who, name, on_load, on_unload)  on_load(module) now if that module
#       is loaded and each time it loads; on_unload(module) as it goes
#   follow(who, name, signal, callable)  connects to another module's signal
#       whenever that module is loaded (projects' project_changed, inspect's
#       selection_changed), and lets go when either side goes
# A module joins in with one function of its own:
#   func lib_ready(lib) -> void  called once lib and the module are both
#       loaded, whichever loaded first, and again with null as lib goes.
#       Do anything that needs lib or another module there, not in setup().
# Everything lib connects it disconnects again when either side unloads, so
# live reloading leaks nothing. lib keeps no data and does nothing per frame.
# Until the APK loads lib first, a module may load before it: lib_ready is
# what makes that order not matter.

signal module_loaded(module_name: String)
signal module_unloaded(module_name: String)
signal info_changed(module_name: String)
signal thing_entered(node: Node3D)
signal thing_exited(node_name: String)

var _by_name := {}  # module name -> the loaded module (lib itself left out)
var _watches: Array[Dictionary] = []  # {who, name, on_load, on_unload}
var _follows: Array[Dictionary] = []  # {who, name, signal, callable}


func setup() -> String:
	var loader: Node = ctx["modules"]
	loader.child_entered_tree.connect(_entered)
	loader.child_exiting_tree.connect(_exiting)
	for child in loader.get_children():
		if child != self and child is SlopitectModule and loader.module(String(child.name)) == child:
			_by_name[String(child.name)] = child
	var world: Node3D = ctx["world"]
	world.child_entered_tree.connect(_world_entered)
	world.child_exiting_tree.connect(_world_exiting)
	if world.has_node("PolyHaven"):
		_join_holder(world.get_node("PolyHaven"))
	register("lib_status", _status, "the shared helper library: the modules it knows, and who watches or follows which module")
	_greet_all.call_deferred()
	return ""


func _exit_tree() -> void:
	var loader: Node = ctx["modules"]
	if loader.child_entered_tree.is_connected(_entered):
		loader.child_entered_tree.disconnect(_entered)
	if loader.child_exiting_tree.is_connected(_exiting):
		loader.child_exiting_tree.disconnect(_exiting)
	var world: Node3D = ctx["world"]
	if world.child_entered_tree.is_connected(_world_entered):
		world.child_entered_tree.disconnect(_world_entered)
	if world.child_exiting_tree.is_connected(_world_exiting):
		world.child_exiting_tree.disconnect(_world_exiting)
	var holder := world.get_node_or_null("PolyHaven")
	if holder and holder.child_entered_tree.is_connected(_model_entered):
		holder.child_entered_tree.disconnect(_model_entered)
	if holder and holder.child_exiting_tree.is_connected(_model_exiting):
		holder.child_exiting_tree.disconnect(_model_exiting)
	for f in _follows:
		_disconnect(f, module(f["name"]))
	_follows.clear()
	_watches.clear()
	for module in _by_name.values():
		if is_instance_valid(module) and module.has_method("lib_ready"):
			module.call("lib_ready", null)
	_by_name.clear()


# --- Modules coming and going -------------------------------------------------------

# A loaded module by name (lib too), or null. The same as the loader's
# module(), without looking through every module each time.
func module(module_name: String) -> SlopitectModule:
	if module_name == String(name):
		return self
	var found = _by_name.get(module_name)
	return found if found != null and is_instance_valid(found) else null


func watch(who: Node, module_name: String, on_load: Callable, on_unload := Callable()) -> void:
	for w in _watches:
		if w["who"] == who and w["name"] == module_name and w["on_load"] == on_load:
			return
	_watches.append({"who": who, "name": module_name, "on_load": on_load, "on_unload": on_unload})
	var there := module(module_name)
	if there != null:
		on_load.call(there)


func follow(who: Node, module_name: String, signal_name: String, callable: Callable) -> void:
	for f in _follows:
		if f["who"] == who and f["name"] == module_name and f["signal"] == signal_name and f["callable"] == callable:
			return
	var f := {"who": who, "name": module_name, "signal": signal_name, "callable": callable}
	_follows.append(f)
	var there := module(module_name)
	if there != null:
		_connect(f, there)


# A module says its *_info() changed, so the windows that show it build again.
func touch(who: Node) -> void:
	info_changed.emit(String(who.name))


func _greet_all() -> void:
	if not is_inside_tree():
		return  # lib's own setup failed
	for module in _by_name.values():
		if is_instance_valid(module) and module.has_method("lib_ready"):
			module.call("lib_ready", self)


func _entered(node: Node) -> void:
	if node != self and node is SlopitectModule:
		_arrived.call_deferred(node)  # after its setup(), which comes after it joins the tree


func _arrived(node) -> void:  # untyped: it may have been freed by now
	# A module whose setup failed was taken out again: it never loaded.
	if not is_instance_valid(node) or not node.is_inside_tree() or ctx["modules"].module(String(node.name)) != node:
		return
	var module_name := String(node.name)
	if _by_name.get(module_name) == node:
		return
	_by_name[module_name] = node
	for f in _follows:
		if f["name"] == module_name:
			_connect(f, node)
	for w in _watches.duplicate():
		if w["name"] == module_name and is_instance_valid(w["who"]):
			w["on_load"].call(node)
	module_loaded.emit(module_name)
	if node.has_method("lib_ready"):
		node.call("lib_ready", self)


func _exiting(node: Node) -> void:
	var module_name := String(node.name)
	if _by_name.get(module_name) != node:
		return
	_by_name.erase(module_name)
	# What it asked for goes with it.
	for f in _follows.filter(func(f): return f["who"] == node):
		_disconnect(f, module(f["name"]))
	_follows = _follows.filter(func(f): return f["who"] != node)
	_watches = _watches.filter(func(w): return w["who"] != node)
	# And whoever was following or watching it lets go.
	for f in _follows:
		if f["name"] == module_name:
			_disconnect(f, node)
	for w in _watches.duplicate():
		if w["name"] == module_name and w["on_unload"].is_valid() and is_instance_valid(w["who"]):
			w["on_unload"].call(node)
	module_unloaded.emit(module_name)


func _connect(f: Dictionary, there: Node) -> void:
	if there.has_signal(f["signal"]) and not there.is_connected(f["signal"], f["callable"]):
		there.connect(f["signal"], f["callable"])


func _disconnect(f: Dictionary, there: Node) -> void:
	if there != null and there.has_signal(f["signal"]) and there.is_connected(f["signal"], f["callable"]):
		there.disconnect(f["signal"], f["callable"])


# --- Things in the world ------------------------------------------------------------

# Shapes are World's own children (the objects and shapes modules'); placed
# models are under World/PolyHaven (the assets module's).

# A shape or a placed model by name, or null: anything under World but the
# PolyHaven holder itself, then the placed models.
func world_node(node_name) -> Node3D:
	if typeof(node_name) != TYPE_STRING or node_name.is_empty() or node_name == "PolyHaven" or node_name.validate_node_name() != node_name:
		return null
	var world: Node3D = ctx["world"]
	var node := world.get_node_or_null(NodePath(node_name)) as Node3D
	if node == null and world.has_node("PolyHaven"):
		node = world.get_node("PolyHaven").get_node_or_null(NodePath(node_name)) as Node3D
	return node


func _join_holder(holder: Node) -> void:
	if not holder.child_entered_tree.is_connected(_model_entered):
		holder.child_entered_tree.connect(_model_entered)
	if not holder.child_exiting_tree.is_connected(_model_exiting):
		holder.child_exiting_tree.connect(_model_exiting)


func _world_entered(node: Node) -> void:
	if node.name == "PolyHaven":
		_join_holder(node)
	elif node is MeshInstance3D:
		_tell_thing.call_deferred(node)  # once its maker has put it in place


func _model_entered(node: Node) -> void:
	_tell_thing.call_deferred(node)


func _world_exiting(node: Node) -> void:
	if node is MeshInstance3D:
		_tell_gone.call_deferred(String(node.name))


func _model_exiting(node: Node) -> void:
	_tell_gone.call_deferred(String(node.name))


func _tell_gone(node_name: String) -> void:
	if is_inside_tree() and thing(node_name) == null:
		thing_exited.emit(node_name)


func _tell_thing(node) -> void:  # untyped: it may have gone by now
	if is_instance_valid(node) and node.is_inside_tree() and thing(String(node.name)) == node:
		thing_entered.emit(node)


# The same, but only what you can point at: a shape is a mesh, so World's
# other children (paths, the landscape) don't count.
func thing(node_name) -> Node3D:
	var node := world_node(node_name)
	if node != null and node.get_parent() == ctx["world"] and not node is MeshInstance3D:
		return null
	return node


# Every shape and placed model, the ones thing() finds.
func things() -> Array:
	var found := []
	for child in (ctx["world"] as Node3D).get_children():
		if child is MeshInstance3D:
			found.append(child)
		elif child.name == "PolyHaven":
			found.append_array(child.get_children())
	return found


func is_model(node: Node) -> bool:
	return node != null and node.get_parent() != null and node.get_parent().name == "PolyHaven"


# A thing's box in world space, round all its meshes.
func world_box(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array = [node] if node is MeshInstance3D else node.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		var mesh_box := mesh.global_transform * mesh.get_aabb()
		box = mesh_box if first else box.merge(mesh_box)
		first = false
	return box


# --- Files -------------------------------------------------------------------------

# The Slopitect folder: on the headset /sdcard/Slopitect, on a PC the app's
# files_home.
func home() -> String:
	return "/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home"


# A file kept with the world that's open: in the save module's folder (each
# project has its own), or the Slopitect folder's saves/ without it. Modules
# with per-world files follow projects' project_changed to load again.
func world_file(file_name: String) -> String:
	var save := module("save")
	var folder: String = save.call("folder") if save and save.has_method("folder") else home() + "/saves"
	return folder + "/" + file_name


# A JSON file's contents, or null when it's missing or isn't JSON.
func read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# Writes data as JSON (indent "" keeps it on one line, which is quicker);
# returns "" or what went wrong.
func write_json(path: String, data, indent := "") -> String:
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return "couldn't write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	out.store_string(JSON.stringify(data, indent))
	out.close()
	return ""


# --- Commands ----------------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	var watches := []
	for w in _watches:
		watches.append("%s watches %s" % [w["who"].name if is_instance_valid(w["who"]) else "?", w["name"]])
	var follows := []
	for f in _follows:
		follows.append("%s follows %s.%s" % [f["who"].name if is_instance_valid(f["who"]) else "?", f["name"], f["signal"]])
	var known := _by_name.keys()
	known.sort()
	return {"ok": true, "modules": known, "watches": watches, "follows": follows}
