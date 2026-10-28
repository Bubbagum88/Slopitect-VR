extends Node

# Slopitect: the module loader.
# modules.json lists the modules to load, in order; each is a script in
# modules/ that extends SlopitectModule. Removing a name from the list takes
# a module out; adding a file and its name puts one in. A module that fails
# to load is logged and skipped, and the rest still load.

const LIST_PATH := "res://modules.json"
const MODULE_DIR := "res://modules/"

@export var command_server_path: NodePath
@export var world_path: NodePath
@export var camera_path: NodePath
@export var left_hand_path: NodePath
@export var right_hand_path: NodePath

var _loaded: Array[SlopitectModule] = []
var _failed := {}  # module name -> why it failed


func _ready() -> void:
	var ctx := {
		"server": get_node(command_server_path),
		"world": get_node(world_path),
		"camera": get_node(camera_path),
		"left": get_node(left_hand_path),
		"right": get_node(right_hand_path),
	}
	for module_name in _read_list():
		var problem := _load_module(module_name, ctx)
		if problem.is_empty():
			print("Slopitect modules: loaded \"%s\"" % module_name)
		else:
			_failed[module_name] = problem
			push_error("Slopitect modules: skipped \"%s\": %s" % [module_name, problem])
	print("Slopitect modules: %d loaded, %d failed" % [_loaded.size(), _failed.size()])


func _read_list() -> PackedStringArray:
	var text := FileAccess.get_file_as_string(LIST_PATH)
	if text.is_empty():
		push_error("Slopitect modules: could not read %s (%s)" % [LIST_PATH, error_string(FileAccess.get_open_error())])
		return []
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("Slopitect modules: %s is not valid JSON: %s" % [LIST_PATH, json.get_error_message()])
		return []
	if typeof(json.data) != TYPE_DICTIONARY or typeof(json.data.get("modules")) != TYPE_ARRAY:
		push_error("Slopitect modules: %s needs {\"modules\": [names]}" % LIST_PATH)
		return []
	var names := PackedStringArray()
	for item in json.data["modules"]:
		if typeof(item) != TYPE_STRING or not item.is_valid_identifier():
			push_error("Slopitect modules: %s lists %s, which is not a module name" % [LIST_PATH, JSON.stringify(item)])
			continue
		names.append(item)
	return names


func _load_module(module_name: String, ctx: Dictionary) -> String:
	var path := MODULE_DIR + module_name + ".gd"
	if not ResourceLoader.exists(path):
		return "no file %s" % path
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		return "%s did not compile (the error is above in the log)" % path
	var instance = script.new()
	if not instance is SlopitectModule:
		if instance is Node:
			instance.free()
		return "%s does not extend SlopitectModule" % path
	var module: SlopitectModule = instance
	module.name = module_name
	module.ctx = ctx
	add_child(module)
	var problem := module.setup()
	if problem.is_empty() and not module.registration_problems().is_empty():
		problem = "; ".join(module.registration_problems())
	if not problem.is_empty():
		ctx["server"].unregister_module(module_name)
		remove_child(module)
		module.queue_free()
		return problem
	_loaded.append(module)
	return ""


func describe() -> Dictionary:
	var loaded := []
	for module in _loaded:
		loaded.append(String(module.name))
	return {"loaded": loaded, "failed": _failed.duplicate()}
