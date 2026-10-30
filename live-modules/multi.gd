extends SlopitectModule

# Slopitect live module: multi.
# Multi-select and groups. Choose "Multi" in the tool window, point at
# shapes or models and pull the trigger to add or take them away (cyan
# boxes). Group them: a group then selects as one, and moving any member
# (grab, move, undo) moves the rest with it; while a member is held, the
# rest follow that one even if physics moves them too. Grouping, ungrouping,
# and the Delete / Hide / Grab buttons are each one undo. Groups are kept
# per project in saves/groups.json.

const REACH := 20.0
const NO_COLOR := Color(0.2, 0.9, 1.0)

var _selection := []  # names
var _groups := {}  # group name -> Array of member names
var _last := {}  # member name -> Transform3D last seen
var _chosen := false
var _outline: MeshInstance3D
var _file := ""
var _since_check := 0.0


func setup() -> String:
	process_physics_priority = 100  # after grab moves things
	_outline = MeshInstance3D.new()
	_outline.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = NO_COLOR
	_outline.material_override = material
	_outline.top_level = true
	_outline.visible = false
	add_child(_outline)
	_file = _groups_file()
	_load()
	register("multi_select", _select_command, "select several things: names [..], optional mode (add, remove, set; default add)")
	register("multi_clear", _clear_command, "select nothing")
	register("multi_status", _status, "the selection and the groups")
	register("multi_group", _group_command, "group things so they move together: optional names (default the selection), optional group (a name)")
	register("multi_ungroup", _ungroup_command, "break a group: optional group (default every group in the selection)")
	register("multi_move", _move_command, "move the selection (and its groups): offset [x, y, z] in m; one undo")
	register("multi_set", _set_command, "switches for every selected thing: grabbable and/or hidden (true/false)")
	register("multi_delete", _delete_command, "delete every selected thing (one undo)")
	return ""


func _process(delta: float) -> void:
	_since_check += delta
	if _since_check >= 2.0:
		_since_check = 0.0
		var now := _groups_file()
		if now != _file:  # another project opened
			_file = now
			_selection.clear()
			_load()
	_draw_outline()


func _physics_process(_delta: float) -> void:
	var held := []
	var grab: SlopitectModule = ctx["modules"].module("grab")
	if grab and grab.has_method("held"):
		held = grab.call("held")
	for g in _groups:
		var nodes := []
		var moved: Node3D = null
		var moved_count := 0
		var leader: Node3D = null  # a member in a hand leads, whatever else moved
		for m in _groups[g]:
			var n := _find(m)
			if n == null:
				continue
			nodes.append(n)
			if _last.has(m) and not (_last[m] as Transform3D).is_equal_approx(n.global_transform):
				moved_count += 1
				moved = n
				if leader == null and n in held:
					leader = n
		if leader != null:
			moved = leader
			moved_count = 1
		if moved_count == 1:
			var change: Transform3D = moved.global_transform * (_last[String(moved.name)] as Transform3D).affine_inverse()
			for n in nodes:
				if n != moved:
					n.global_transform = change * n.global_transform
		for n in nodes:
			_last[String(n.name)] = n.global_transform


# --- For other modules ---------------------------------------------------------------

# The things that move with node_name: its group, or just itself.
func members(node_name: String) -> Array:
	var g := _group_of(node_name)
	return _groups[g].duplicate() if not g.is_empty() else [node_name]


# Takes a deleted thing out of its group (a group left with one member
# goes); what put_in needs to put it back, or {} if it was in none.
func take_out(node_name: String) -> Dictionary:
	_selection.erase(node_name)
	_last.erase(node_name)
	var g := _group_of(node_name)
	if g.is_empty():
		return {}
	var info := {"group": g, "members": _groups[g].duplicate()}
	_groups[g].erase(node_name)
	if _groups[g].size() < 2:
		_groups.erase(g)
	_save()
	return info


func put_in(node_name: String, info: Dictionary) -> void:
	var g: String = info.get("group", "")
	if g.is_empty() or not _group_of(node_name).is_empty():
		return
	if not _groups.has(g):
		# It went when this one left: back with the members that aren't in
		# another group now.
		_groups[g] = (info.get("members", []) as Array).filter(func(m): return m == node_name or _group_of(m).is_empty())
	elif not node_name in _groups[g]:
		_groups[g].append(node_name)
	if _groups[g].size() < 2:
		_groups.erase(g)
	for m in _groups.get(g, []):
		var node := _find(m)
		if node:
			_last[m] = node.global_transform
	_save()


# --- The tool ------------------------------------------------------------------------

func tool_info() -> Dictionary:
	var buttons := []
	if _selection.size() >= 2:
		buttons.append({"label": "Group (%d)" % _selection.size(), "action": {"cmd": "multi_group"}})
	if not _groups_of(_selection).is_empty():
		buttons.append({"label": "Ungroup", "action": {"cmd": "multi_ungroup"}})
	if not _selection.is_empty():
		buttons.append({"label": "Grab off", "action": {"cmd": "multi_set", "grabbable": false}})
		buttons.append({"label": "Grab on", "action": {"cmd": "multi_set", "grabbable": true}})
		buttons.append({"label": "Hide", "action": {"cmd": "multi_set", "hidden": true}})
		buttons.append({"label": "Delete", "action": {"cmd": "multi_delete"}})
		buttons.append({"label": "Clear", "action": {"cmd": "multi_clear"}})
	return {"id": "multi", "label": "Multi", "order": 6, "buttons": buttons, "status": _line()}


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
	var names := [best]
	var g := _group_of(best)
	if not g.is_empty():
		names = _groups[g].duplicate()
	var all_in := names.all(func(n): return n in _selection)
	for n in names:
		if all_in:
			_selection.erase(n)
		elif not n in _selection:
			_selection.append(n)
	(ctx["right"] as XRController3D).trigger_haptic_pulse("haptic", 0.0, 0.3, 0.05, 0.0)


func _line() -> String:
	_prune()
	if _selection.is_empty():
		return "Point and pull the trigger to add things (%d groups)" % _groups.size()
	var shown := _selection.slice(0, 4)
	var text := "%d selected: %s" % [_selection.size(), ", ".join(PackedStringArray(shown))]
	if _selection.size() > 4:
		text += "..."
	var gs := _groups_of(_selection)
	if not gs.is_empty():
		text += " | groups: " + ", ".join(PackedStringArray(gs))
	return text


# --- Things --------------------------------------------------------------------------

func _things() -> Array:
	var found := []
	var world: Node3D = ctx["world"]
	for child in world.get_children():
		if child is MeshInstance3D:
			found.append(child)
		elif child.name == "PolyHaven":
			found.append_array(child.get_children())
	return found


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


func _prune() -> void:
	_selection = _selection.filter(func(n): return _find(n) != null)


func _group_of(node_name: String) -> String:
	for g in _groups:
		if node_name in _groups[g]:
			return g
	return ""


func _groups_of(names: Array) -> Array:
	var found := []
	for n in names:
		var g := _group_of(n)
		if not g.is_empty() and not g in found:
			found.append(g)
	return found


func _draw_outline() -> void:
	var mesh := _outline.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var boxes := []
	if _chosen:
		for n in _selection:
			var node := _find(n)
			if node and node.is_visible_in_tree():
				boxes.append(_box(node).grow(0.015))
	_outline.visible = not boxes.is_empty()
	if boxes.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for box: AABB in boxes:
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


# --- Keeping groups ------------------------------------------------------------------

func _groups_file() -> String:
	var home := "/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home"
	var folder := home + "/saves"
	if FileAccess.file_exists("user://projects.json"):
		var p = JSON.parse_string(FileAccess.get_file_as_string("user://projects.json"))
		if typeof(p) == TYPE_DICTIONARY and typeof(p.get("current")) == TYPE_STRING and p["current"].is_valid_filename():
			folder = "%s/projects/%s/saves" % [home, p["current"]]
	return folder + "/groups.json"


func _load() -> void:
	_groups.clear()
	_last.clear()
	if not FileAccess.file_exists(_file):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(_file))
	if typeof(data) != TYPE_DICTIONARY:
		return
	for g in data:
		if typeof(g) == TYPE_STRING and typeof(data[g]) == TYPE_ARRAY:
			_groups[g] = data[g].filter(func(n): return typeof(n) == TYPE_STRING)


func _save() -> void:
	DirAccess.make_dir_recursive_absolute(_file.get_base_dir())
	var f := FileAccess.open(_file, FileAccess.WRITE)
	if f == null:
		push_error("Slopitect multi: can't write %s" % _file)
		return
	f.store_string(JSON.stringify(_groups, "\t"))


# --- Commands ------------------------------------------------------------------------

func _names(request: Dictionary, fallback: Array) -> Array:
	# [names, error]
	if not request.has("names"):
		return [fallback.duplicate(), ""]
	var names = request["names"]
	if typeof(names) != TYPE_ARRAY:
		return [[], "\"names\" must be a list of names"]
	for n in names:
		if _find(n) == null:
			return [[], "no shape or model named %s (inspect_list shows them)" % JSON.stringify(n)]
	return [names.duplicate(), ""]


func _select_command(request: Dictionary) -> Dictionary:
	var got := _names(request, [])
	if not got[1].is_empty():
		return {"ok": false, "error": got[1]}
	var mode = request.get("mode", "add")
	if not mode in ["add", "remove", "set"]:
		return {"ok": false, "error": "\"mode\" must be add, remove or set"}
	if mode == "set":
		_selection.clear()
	for n in got[0]:
		if mode == "remove":
			_selection.erase(n)
		elif not n in _selection:
			_selection.append(n)
	return _status({})


func _clear_command(_request: Dictionary) -> Dictionary:
	_selection.clear()
	return _status({})


func _group_command(request: Dictionary) -> Dictionary:
	var got := _names(request, _selection)
	if not got[1].is_empty():
		return {"ok": false, "error": got[1]}
	var names: Array = got[0]
	if names.size() < 2:
		return {"ok": false, "error": "a group needs 2 or more things (select them first, or give names)"}
	var g = request.get("group", "")
	if typeof(g) != TYPE_STRING:
		return {"ok": false, "error": "\"group\" must be a name"}
	var joining := _groups_of(names)
	if g.is_empty() and not joining.is_empty():
		g = joining[0]  # adding to a group keeps its name
	if g.is_empty():
		var i := 1
		while _groups.has("group%d" % i):
			i += 1
		g = "group%d" % i
	var before := _groups.duplicate(true)
	# A thing is in one group at most; grouping groups merges them.
	var members := []
	for n in names:
		var old := _group_of(n)
		var adding: Array = [n] if old.is_empty() else _groups[old].duplicate()
		if not old.is_empty():
			_groups.erase(old)
		for m in adding:
			if not m in members:
				members.append(m)
	if _groups.has(g):
		for m in _groups[g]:
			if not m in members:
				members.append(m)
	_groups[g] = members
	_put_groups(_groups)
	_undo("group %d things" % members.size(), before)
	return {"ok": true, "group": g, "members": members}


func _ungroup_command(request: Dictionary) -> Dictionary:
	var gs := []
	if request.has("group"):
		if not _groups.has(request["group"]):
			return {"ok": false, "error": "no group named %s (multi_status shows them)" % JSON.stringify(request["group"])}
		gs = [request["group"]]
	else:
		gs = _groups_of(_selection)
	if gs.is_empty():
		return {"ok": false, "error": "nothing selected is in a group"}
	var before := _groups.duplicate(true)
	for g in gs:
		_groups.erase(g)
	_put_groups(_groups)
	_undo("ungroup " + ", ".join(PackedStringArray(gs)), before)
	return {"ok": true, "ungrouped": gs}


# Groups as they are now become one undo back to before.
func _undo(label: String, before: Dictionary) -> void:
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		tools.call("push_undo", label, _put_groups.bind(before), _put_groups.bind(_groups.duplicate(true)))


func _put_groups(groups: Dictionary) -> void:
	_groups = groups.duplicate(true)
	_last.clear()  # seen afresh, so nothing counts as moved
	for g in _groups:
		for m in _groups[g]:
			var node := _find(m)
			if node:
				_last[m] = node.global_transform
	_save()


func _move_command(request: Dictionary) -> Dictionary:
	var offset = request.get("offset")
	if typeof(offset) != TYPE_ARRAY or offset.size() != 3 or not offset.all(func(v): return typeof(v) in [TYPE_INT, TYPE_FLOAT]):
		return {"ok": false, "error": "\"offset\" must be [x, y, z] in metres"}
	_prune()
	var names := _selection.duplicate()
	for g in _groups_of(_selection):
		for m in _groups[g]:
			if not m in names:
				names.append(m)
	if names.is_empty():
		return {"ok": false, "error": "nothing selected"}
	var shift := Vector3(offset[0], offset[1], offset[2])
	var before := {}
	var after := {}
	for n in names:
		var node := _find(n)
		if node == null:
			continue
		before[n] = node.global_transform
		node.global_position += shift
		after[n] = node.global_transform
		_last[n] = node.global_transform  # so the group sync doesn't move them twice
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		var put := func(where: Dictionary):
			for n in where:
				var node := _find(n)
				if node:
					node.global_transform = where[n]
					_last[n] = where[n]
		tools.call("push_undo", "move %d things" % before.size(), put.bind(before), put.bind(after))
	return {"ok": true, "moved": before.keys()}


func _set_command(request: Dictionary) -> Dictionary:
	_prune()
	if _selection.is_empty():
		return {"ok": false, "error": "nothing selected"}
	var request_out := {"cmd": "inspect_set"}
	for key in ["grabbable", "hidden"]:
		if request.has(key):
			if typeof(request[key]) != TYPE_BOOL:
				return {"ok": false, "error": "\"%s\" must be true or false" % key}
			request_out[key] = request[key]
	if request_out.size() == 1:
		return {"ok": false, "error": "multi_set needs grabbable and/or hidden"}
	var failed := []
	var before := {}  # name -> its switches before, for the undo
	var after := {}
	var inspect: SlopitectModule = ctx["modules"].module("inspect")
	var switches: Dictionary = inspect.call("get_settings") if inspect else {}
	for n in _selection:
		var was: Dictionary = switches.get(n, {})
		var r: Dictionary = ctx["server"].run(request_out.merged({"name": n}))
		if not r.get("ok", false):
			failed.append("%s: %s" % [n, r.get("error")])
			continue
		before[n] = {"grabbable": was.get("grabbable", true), "hidden": was.get("hidden", false)}
		after[n] = {"grabbable": r["grabbable"], "hidden": r["hidden"]}
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools and not before.is_empty():
		var put := func(where: Dictionary):
			for n in where:
				ctx["server"].run({"cmd": "inspect_set", "name": n, "grabbable": where[n]["grabbable"], "hidden": where[n]["hidden"]})
		var what := "grab on" if request_out.get("grabbable", false) else "grab off"
		if request_out.has("hidden"):
			what = "hide" if request_out["hidden"] else "show"
		tools.call("push_undo", "%s %d things" % [what, before.size()], put.bind(before), put.bind(after))
	if request_out.get("hidden", false):
		_selection.clear()
	return {"ok": failed.is_empty(), "error": "; ".join(PackedStringArray(failed))} if not failed.is_empty() else {"ok": true}


func _delete_command(_request: Dictionary) -> Dictionary:
	_prune()
	if _selection.is_empty():
		return {"ok": false, "error": "nothing selected"}
	var deleted := []
	var failed := []
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		tools.call("undo_batch_begin", "delete %d things" % _selection.size())
	for n in _selection.duplicate():
		var r: Dictionary = ctx["server"].run({"cmd": "inspect_delete", "name": n})
		if r.get("ok", false):
			deleted.append(n)
		else:
			failed.append("%s: %s" % [n, r.get("error")])
	if tools:
		tools.call("undo_batch_end")
	_selection.clear()
	var reply := {"ok": failed.is_empty(), "deleted": deleted}
	if not failed.is_empty():
		reply["error"] = "; ".join(PackedStringArray(failed))
	return reply


func _status(_request: Dictionary) -> Dictionary:
	_prune()
	return {"ok": true, "selected": _selection.duplicate(), "groups": _groups.duplicate(true), "line": _line()}
