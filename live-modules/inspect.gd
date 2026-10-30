extends SlopitectModule

# Slopitect live module: inspect.
# A tool for one thing at a time. Choose Inspect in the tool window, point
# at a shape or a placed model and pull the trigger: it's selected (a white
# box shows round it) and the tool window gets its switches: physics (none,
# static, dynamic, with the physics module loaded), grabbable or not,
# hide, and delete. Hidden things can't be pointed at, so "Show hidden"
# brings them all back. Delete is one undo in the tool window.
# The switches are kept with the world (the save module keeps them in each
# project's saves and checkpoints).

const REACH := 20.0  # metres the pointer reaches
const SCAN_SECONDS := 0.5
const NO_GRAB := "slopitect_no_grab"  # meta the grab module checks

var settings := {}  # thing's name -> {"grabbable": false, "hidden": true}; only switches that aren't the default
var _selected := ""
var _chosen := false  # the tool is chosen in the tool window
var _outline: MeshInstance3D
var _since_scan := 0.0


func setup() -> String:
	_outline = MeshInstance3D.new()
	_outline.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	_outline.material_override = material
	_outline.top_level = true
	_outline.visible = false
	add_child(_outline)
	register("inspect_select", _select_command, "select a shape or model to change: name (\"\" for none)")
	register("inspect_set", _set_command, "change a thing's switches: optional name (default: the selected one), grabbable (true/false), hidden (true/false)")
	register("inspect_delete", _delete_command, "delete a shape or model (one undo in the tool window): optional name (default: the selected one)")
	register("inspect_show_all", _show_all, "show every hidden thing again")
	register("inspect_status", _status, "the selected thing and its switches")
	register("inspect_list", _list, "every shape and model with its switches")
	return ""


func _exit_tree() -> void:
	# Taken out, it leaves nothing hidden or unholdable behind.
	for node_name in settings:
		var node := _find(node_name)
		if node:
			node.visible = true
			node.remove_meta(NO_GRAB)


func _process(delta: float) -> void:
	_since_scan += delta
	if _since_scan >= SCAN_SECONDS:
		_since_scan = 0.0
		_apply_all()  # things made or put back since keep their switches
	_draw_outline()


# --- The tool ------------------------------------------------------------------------

func tool_info() -> Dictionary:
	var hidden := settings.keys().filter(func(n): return settings[n].get("hidden", false)).size()
	var buttons := []
	var node := _find(_selected)
	if node:
		var physics: SlopitectModule = ctx["modules"].module("physics")
		if physics:
			var mode := _physics_mode(_selected)
			for choice in [["off", "No physics"], ["static", "Static"], ["dynamic", "Dynamic"]]:
				buttons.append({"label": ("> " if mode == choice[0] else "") + choice[1],
					"action": {"cmd": "physics_set", "name": _selected, "mode": choice[0]}})
		var grabbable := _flag(_selected, "grabbable")
		buttons.append({"label": "Grab: " + ("on" if grabbable else "off"),
			"action": {"cmd": "inspect_set", "name": _selected, "grabbable": not grabbable}})
		buttons.append({"label": "Hide", "action": {"cmd": "inspect_set", "name": _selected, "hidden": true}})
		buttons.append({"label": "Delete", "action": {"cmd": "inspect_delete", "name": _selected}})
		buttons.append({"label": "Unselect", "action": {"cmd": "inspect_select", "name": ""}})
	if hidden > 0:
		buttons.append({"label": "Show hidden (%d)" % hidden, "action": {"cmd": "inspect_show_all"}})
	return {"id": "inspect", "label": "Inspect", "order": 5, "buttons": buttons, "status": _line()}


func tool_selected(on: bool) -> void:
	_chosen = on


func tool_trigger(down: bool) -> void:
	if not down:
		return
	var hand: Node3D = ctx["right"]
	var from := hand.global_position
	var direction := -hand.global_basis.z.normalized()
	var best := ""
	var best_distance := REACH
	for thing in _things():
		if not thing.is_visible_in_tree():
			continue
		var box := _box(thing)
		var hit = box.intersects_ray(from, direction) if box.size != Vector3.ZERO else null
		if box.has_point(from):
			hit = from
		if hit != null and from.distance_to(hit) <= best_distance:
			best = String(thing.name)
			best_distance = from.distance_to(hit)
	if best.is_empty():
		return
	_selected = best
	(ctx["right"] as XRController3D).trigger_haptic_pulse("haptic", 0.0, 0.3, 0.05, 0.0)
	print("Slopitect inspect: selected %s" % best)


func _line() -> String:
	var node := _find(_selected)
	if node == null:
		return "Point at a shape or model and pull the trigger"
	var parts := PackedStringArray([_selected + (" (model)" if node.get_parent().name == "PolyHaven" else " (shape)")])
	if ctx["modules"].module("physics"):
		parts.append("physics " + _physics_mode(_selected))
	parts.append("grabbable" if _flag(_selected, "grabbable") else "not grabbable")
	if _flag(_selected, "hidden"):
		parts.append("hidden")
	return ", ".join(parts)


# --- Things --------------------------------------------------------------------------

# The shapes (the objects module's, under World) and placed models (under
# World/PolyHaven, from the assets module), as the grab module finds them.
func _things() -> Array:
	var found := []
	var world: Node3D = ctx["world"]
	for child in world.get_children():
		if child is MeshInstance3D:
			found.append(child)
		elif child.name == "PolyHaven":
			found.append_array(child.get_children())
	return found


# A shape first, then a model, the same as the physics module.
func _find(node_name) -> Node3D:
	if typeof(node_name) != TYPE_STRING or node_name.is_empty() or node_name.validate_node_name() != node_name:
		return null
	var world: Node3D = ctx["world"]
	var node := world.get_node_or_null(NodePath(node_name)) as Node3D
	if node is MeshInstance3D:
		return node
	if world.has_node("PolyHaven"):
		return world.get_node("PolyHaven").get_node_or_null(NodePath(node_name)) as Node3D
	return null


func _box(thing: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array = [thing] if thing is MeshInstance3D else thing.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		var world_box := mesh.global_transform * mesh.get_aabb()
		box = world_box if first else box.merge(world_box)
		first = false
	return box


func _physics_mode(node_name: String) -> String:
	for thing in ctx["server"].run({"cmd": "physics_status"}).get("things", []):
		if thing.get("name") == node_name:
			return thing.get("mode", "off")
	return "off"


func _flag(node_name: String, key: String) -> bool:
	var defaults := {"grabbable": true, "hidden": false}
	return settings.get(node_name, {}).get(key, defaults[key])


func _apply(node_name: String) -> void:
	var node := _find(node_name)
	if node == null:
		return
	var hidden := _flag(node_name, "hidden")
	if node.visible == hidden:
		node.visible = not hidden
	if _flag(node_name, "grabbable"):
		node.remove_meta(NO_GRAB)
	else:
		node.set_meta(NO_GRAB, true)
	if hidden and node_name == _selected:
		_selected = ""


func _apply_all() -> void:
	for node_name in settings:
		_apply(node_name)


func _store(node_name: String, flags: Dictionary) -> void:
	var kept := {}
	if flags.get("grabbable", true) == false:
		kept["grabbable"] = false
	if flags.get("hidden", false) == true:
		kept["hidden"] = true
	if kept.is_empty():
		settings.erase(node_name)
	else:
		settings[node_name] = kept
	_apply(node_name)


func _draw_outline() -> void:
	var node := _find(_selected)
	var mesh := _outline.mesh as ImmediateMesh
	mesh.clear_surfaces()
	_outline.visible = _chosen and node != null and node.is_visible_in_tree()
	if not _outline.visible:
		return
	var box := _box(node).grow(0.01)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for a in 8:
		for axis in 3:
			var bit := 1 << axis
			if a & bit:
				continue
			for corner in [a, a | bit]:
				var p := box.position
				for k in 3:
					if corner & (1 << k):
						p[k] += box.size[k]
				mesh.surface_add_vertex(p)
	mesh.surface_end()


# --- For the save module ---------------------------------------------------------------

func get_settings() -> Dictionary:
	return settings.duplicate(true)


func set_settings(data: Dictionary) -> void:
	for node_name in settings.keys():
		_store(node_name, {})
	for node_name in data:
		if typeof(node_name) == TYPE_STRING and typeof(data[node_name]) == TYPE_DICTIONARY:
			_store(node_name, data[node_name])


# --- Commands ------------------------------------------------------------------------

func _named(request: Dictionary) -> Array:
	var node_name = request.get("name", _selected)
	if _find(node_name) == null:
		return ["", "no shape or model named %s (inspect_list shows them)" % JSON.stringify(node_name)]
	return [node_name, ""]


func _select_command(request: Dictionary) -> Dictionary:
	var node_name = request.get("name", "")
	if typeof(node_name) == TYPE_STRING and node_name.is_empty():
		_selected = ""
		return _status({})
	var named := _named(request)
	if not named[1].is_empty():
		return {"ok": false, "error": named[1]}
	_selected = named[0]
	return _status({})


func _set_command(request: Dictionary) -> Dictionary:
	var named := _named(request)
	if not named[1].is_empty():
		return {"ok": false, "error": named[1]}
	for key in ["grabbable", "hidden"]:
		if request.has(key) and typeof(request[key]) != TYPE_BOOL:
			return {"ok": false, "error": "\"%s\" must be true or false" % key}
	if not (request.has("grabbable") or request.has("hidden")):
		return {"ok": false, "error": "inspect_set needs grabbable and/or hidden"}
	var node_name: String = named[0]
	var flags := {"grabbable": _flag(node_name, "grabbable"), "hidden": _flag(node_name, "hidden")}
	for key in ["grabbable", "hidden"]:
		if request.has(key):
			flags[key] = request[key]
	_store(node_name, flags)
	print("Slopitect inspect: %s is %s" % [node_name, JSON.stringify(flags)])
	return {"ok": true, "name": node_name, "grabbable": flags["grabbable"], "hidden": flags["hidden"]}


func _delete_command(request: Dictionary) -> Dictionary:
	var named := _named(request)
	if not named[1].is_empty():
		return {"ok": false, "error": named[1]}
	var node_name: String = named[0]
	var is_model: bool = _find(node_name).get_parent().name == "PolyHaven"
	# What it takes to put it back exactly.
	var again := {}
	for item in ctx["server"].run({"cmd": "assets_placed" if is_model else "list"}).get("placed" if is_model else "objects", []):
		if item.get("name") == node_name:
			again = item
	if again.is_empty():
		return {"ok": false, "error": "couldn't read %s's details, so it wasn't deleted" % node_name}
	var make := {"name": node_name, "position": again["position"], "rotation": again["rotation"], "scale": again["scale"]}
	if is_model:
		make.merge({"cmd": "assets_place", "id": again["id"], "resolution": again["resolution"]})
	else:
		make.merge({"cmd": "spawn", "shape": again["shape"]})
		if again.get("color") != null:
			make["color"] = again["color"]
	var remove := {"cmd": "assets_remove" if is_model else "delete", "name": node_name}
	var flags: Dictionary = settings.get(node_name, {}).duplicate()
	# A shape made with shapes.gd comes back from its recipe, not as a primitive.
	var shapes: SlopitectModule = ctx["modules"].module("shapes")
	var made: Dictionary = shapes.call("made_entry", node_name) if shapes and not is_model else {}

	var reply: Dictionary = ctx["server"].run(remove)
	if not reply.get("ok", false):
		return {"ok": false, "error": "%s wasn't deleted: %s" % [node_name, reply.get("error")]}
	settings.erase(node_name)
	if _selected == node_name:
		_selected = ""
	# Out of its group (multi.gd), and back in on undo.
	var multi: SlopitectModule = ctx["modules"].module("multi")
	var group: Dictionary = multi.call("take_out", node_name) if multi else {}
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		var put_back := func():
			if not made.is_empty():
				var again_shapes: SlopitectModule = ctx["modules"].module("shapes")
				if again_shapes == null:
					push_error("Slopitect inspect: %s couldn't be put back: the shapes module isn't loaded" % node_name)
					return
				again_shapes.call("remake", made)
			else:
				var reply_back: Dictionary = ctx["server"].run(make)
				if not reply_back.get("ok", false):
					push_error("Slopitect inspect: %s couldn't be put back: %s" % [node_name, reply_back.get("error")])
					return
			if not flags.is_empty():
				_store(node_name, flags)
			var again_multi: SlopitectModule = ctx["modules"].module("multi")
			if again_multi and not group.is_empty():
				again_multi.call("put_in", node_name, group)
		var take_away := func():
			ctx["server"].run(remove)
			settings.erase(node_name)
			var again_multi: SlopitectModule = ctx["modules"].module("multi")
			if again_multi:
				again_multi.call("take_out", node_name)
		tools.call("push_undo", "delete %s" % node_name, put_back, take_away)
	print("Slopitect inspect: deleted %s" % node_name)
	return {"ok": true, "deleted": node_name, "undo": tools != null}


func _show_all(_request: Dictionary) -> Dictionary:
	var shown := []
	for node_name in settings.keys():
		if _flag(node_name, "hidden"):
			_store(node_name, {"grabbable": _flag(node_name, "grabbable"), "hidden": false})
			shown.append(node_name)
	return {"ok": true, "shown": shown}


func _status(_request: Dictionary) -> Dictionary:
	var reply := {"ok": true, "selected": _selected if _find(_selected) else "", "line": _line()}
	if not reply["selected"].is_empty():
		reply["grabbable"] = _flag(_selected, "grabbable")
		reply["hidden"] = _flag(_selected, "hidden")
	return reply


func _list(_request: Dictionary) -> Dictionary:
	var listed := []
	for thing in _things():
		var node_name := String(thing.name)
		listed.append({"name": node_name, "kind": "model" if thing.get_parent().name == "PolyHaven" else "shape",
			"grabbable": _flag(node_name, "grabbable"), "hidden": _flag(node_name, "hidden")})
	return {"ok": true, "things": listed}
