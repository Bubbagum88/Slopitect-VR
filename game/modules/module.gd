class_name SlopitectModule
extends Node3D

# The base of every module. The loader (modules.gd) gives each module a ctx:
#   server  the command server, to register commands with and run them
#   world   the World node, where the things you build live
#   camera  the headset camera
#   left, right  the controllers
# then calls setup(). setup() returns "" when the module is ready, or what
# went wrong; a module that fails is logged and skipped, never half-loaded.

var ctx: Dictionary


func setup() -> String:
	return ""


# Registers a command for this module. A clash with another module's command
# is an error: the module fails to load and says which module has it.
func register(cmd: String, call: Callable, summary: String) -> void:
	var problem: String = ctx["server"].register(String(name), cmd, call, summary)
	if not problem.is_empty():
		_problems.append(problem)


var _problems: PackedStringArray = []


func registration_problems() -> PackedStringArray:
	return _problems
