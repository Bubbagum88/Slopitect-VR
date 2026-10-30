extends SlopitectModule

# Slopitect live module: shapes.
# Shapes beyond the four built-in ones (box, sphere, cylinder, capsule):
# - extrude: a flat outline pushed out into a solid (stars, gears, beams,
#   arches, stairs, a floor plan), optionally tapered or twisted;
# - revolve: a side outline spun round the up axis (cones, domes, bowls,
#   vases, rings, a torus);
# - sweep: a tube along a path (pipes, an elbow, a spring, a handle);
# - loft: a solid through outlines stacked up (a pyramid, square to round);
# - surface: a sheet from a grid of heights or points (a curved panel, a
#   wave), with or without thickness;
# - cut: one shape cut out of another, joined to it or where they overlap
#   (a window in a wall, a hole through a plate).
# Each comes from a recipe (shapes_kinds lists them, with ready-made
# presets), so a shape can be changed later (shapes_edit) and is saved as
# its recipe, not its mesh (with save.gd). Made shapes sit under World like
# the built-in ones, so list, move, color, delete, grab, inspect, physics
# and textures all work on them.
#
# As a tool (the Tools menu): Place mode puts the chosen preset where you
# point; Draw mode puts down an outline with the trigger, on a wall in front
# of you (the controller's tip) or on the floor (where you point), then
# Extrude or Revolve turns it into a shape. One undo for each change.
#
# Attach points, for joints and anything that fixes things together: every
# shape (built-in ones too) has center, top, bottom, left, right, front (+z)
# and back (-z) from its box; a sweep also has start and end, a revolve
# axis_top and axis_bottom. Points of your own are joints.gd's
# (joints_point_add). Other modules use:
#   attach_points(name) -> [{id, position: Vector3, normal: Vector3}]
#                          in the shape's own space (before its scale)
#   attach_transform(name, id) -> Transform3D in the world (origin on the
#                          point, basis.y along the normal, no scale), or
#                          null when there's no such shape or point
#   is_made(name) -> bool, recipe(name) -> Dictionary
#   signal shape_changed(name, what)  what: made, edited, removed
# Kept light for the Quest 1: low segment counts, at most MAX_VERTS
# vertices a shape, meshes built once (not every frame).

signal shape_changed(name: String, what: String)

const KINDS := ["extrude", "revolve", "sweep", "loft", "surface"]
const PRIMITIVES := ["box", "sphere", "cylinder", "capsule"]
const OPS := {"subtract": CSGShape3D.OPERATION_SUBTRACTION, "union": CSGShape3D.OPERATION_UNION, "intersect": CSGShape3D.OPERATION_INTERSECTION}
const PRESETS := [
	{"name": "polygon", "kind": "extrude", "label": "Polygon", "params": {"sides": [3, 32, 6]}},
	{"name": "star", "kind": "extrude", "label": "Star", "params": {"points": [3, 24, 5], "inner": [0.1, 0.95, 0.45]}},
	{"name": "gear", "kind": "extrude", "label": "Gear", "params": {"teeth": [6, 40, 12]}},
	{"name": "cross", "kind": "extrude", "label": "Cross", "params": {}},
	{"name": "l_beam", "kind": "extrude", "label": "L beam", "params": {"wall": [0.05, 0.45, 0.2]}},
	{"name": "t_beam", "kind": "extrude", "label": "T beam", "params": {"wall": [0.05, 0.45, 0.2]}},
	{"name": "i_beam", "kind": "extrude", "label": "I beam", "params": {"wall": [0.05, 0.3, 0.15]}},
	{"name": "u_channel", "kind": "extrude", "label": "U channel", "params": {"wall": [0.05, 0.45, 0.15]}},
	{"name": "arch", "kind": "extrude", "label": "Arch", "params": {"opening": [0.2, 0.9, 0.6]}},
	{"name": "stairs", "kind": "extrude", "label": "Stairs", "params": {"steps": [2, 20, 5]}},
	{"name": "ramp", "kind": "extrude", "label": "Ramp", "params": {"rise": [0.05, 2.0, 0.5]}},
	{"name": "cone", "kind": "revolve", "label": "Cone", "params": {}},
	{"name": "frustum", "kind": "revolve", "label": "Frustum", "params": {"top": [0.0, 1.0, 0.5]}},
	{"name": "dome", "kind": "revolve", "label": "Dome", "params": {}},
	{"name": "bowl", "kind": "revolve", "label": "Bowl", "params": {"wall": [0.02, 0.5, 0.1]}},
	{"name": "vase", "kind": "revolve", "label": "Vase", "params": {}},
	{"name": "torus", "kind": "revolve", "label": "Torus", "params": {"thickness": [0.05, 0.9, 0.3]}},
	{"name": "ring", "kind": "revolve", "label": "Ring", "params": {"thickness": [0.05, 0.95, 0.3]}},
	{"name": "elbow", "kind": "sweep", "label": "Pipe elbow", "params": {"thickness": [0.05, 0.6, 0.25]}},
	{"name": "spring", "kind": "sweep", "label": "Spring", "params": {"turns": [1, 20, 4]}},
	{"name": "handle", "kind": "sweep", "label": "Handle", "params": {}},
	{"name": "pyramid", "kind": "loft", "label": "Pyramid", "params": {}},
	{"name": "square_round", "kind": "loft", "label": "Square to round", "params": {}},
	{"name": "panel", "kind": "surface", "label": "Curved panel", "params": {"bend": [0.0, 180.0, 60.0]}},
	{"name": "wave", "kind": "surface", "label": "Wave", "params": {"height": [0.0, 0.5, 0.1]}},
]
const MAX_SHAPES := 200
const MAX_VERTS := 20000
const MAX_OUTLINE := 64
const MAX_PATH := 128
const MAX_GRID := 48
const MAX_CUT_DEPTH := 8
const LIMIT := 20.0  # metres, for any coordinate in a recipe
const SHARP := 40.0  # degrees: a sharper turn in a revolve's outline gets its own edge
const COLORS := ["#d8d8d8", "#c0392b", "#e67e22", "#f1c40f", "#27ae60", "#2980b9", "#8e44ad", "#5d4037", "#333333"]
const MARKER_SECONDS := 0.5  # how often the attach-point markers follow the shapes, while shown
const RAY_LENGTH := 15.0
const RAY_STEP := 0.05
const TIP := 0.1  # metres in front of the controller where Draw puts a wall point
const PLACE_DISTANCE := 1.5
const MARKER_RANGE := 4.0  # attach points are shown on shapes this close

var _made := {}  # node name -> recipe
var _tool := {"mode": "place", "preset": "star", "size": 0.3, "depth": 0.1, "plane": "wall", "color": 0, "show_points": false}
var _draft: Array = []  # Vector3 points of the outline being drawn, in the world
var _draft_frame := {}  # {"origin", "basis": Basis (x right, y up, z out of the plane)}
var _draft_mesh: MeshInstance3D
var _marker: MeshInstance3D
var _markers: MultiMeshInstance3D
var _selected := false
var _since_markers := 0.0
var _lib: SlopitectModule
var _busy := 0  # cuts being built


func setup() -> String:
	_draft_mesh = MeshInstance3D.new()
	_draft_mesh.mesh = ImmediateMesh.new()
	_draft_mesh.material_override = _unshaded(Color(1, 0.85, 0.2))
	add_child(_draft_mesh)
	_marker = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.015
	ball.height = 0.03
	ball.radial_segments = 8
	ball.rings = 4
	_marker.mesh = ball
	_marker.material_override = _unshaded(Color(1, 1, 1))
	_marker.visible = false
	add_child(_marker)
	_markers = MultiMeshInstance3D.new()
	_markers.multimesh = MultiMesh.new()
	_markers.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_markers.multimesh.mesh = ball
	_markers.material_override = _unshaded(Color(0.3, 0.9, 1))
	_markers.visible = false
	add_child(_markers)
	set_process(false)
	set_physics_process(false)

	register("shapes_kinds", _kinds, "the kinds of shape and their fields, and the presets with their settings")
	register("shapes_make", _make_command, "make a shape (one undo): preset (shapes_kinds) with size, depth and its settings, or kind (extrude, revolve, sweep, loft, surface) with its fields; optional name, position, rotation, scale, color (in front of you without a position)")
	register("shapes_edit", _edit_command, "change a made shape's recipe (one undo): name, then any recipe fields to change (or recipe for a whole new one)")
	register("shapes_list", _list_command, "the made shapes: name, recipe, vertices; and the shapes with attach points you added")
	register("shapes_cut", _cut_command, "cut one shape with another (one undo): name (the shape kept), tool (the shape it's cut with, removed unless keep_tool), op (subtract, union or intersect; subtract by default)")
	register("shapes_points", _points_command, "a shape's attach points (any shape): name; each with its id, position and normal in the shape's space and in the world")
	register("shapes_tool", _tool_command, "the Shapes tool: any of mode (place, draw), preset (its name), preset_step (1 / -1), kind_step (1 / -1, jumps to the next kind's first preset), size (0.05 to 5 m), size_step, depth (0.005 to 5 m), depth_step, plane (wall, floor), color_step, show_points (true / false)")
	register("shapes_draft", _draft_command, "the outline being drawn with the Shapes tool: action finish (as extrude or revolve), remove_last or cancel")
	return ""


func _exit_tree() -> void:
	# The shapes stay in the world (save.gd keeps their recipes); only what
	# this module drew for itself goes.
	_clear_draft()


# A shape deleted another way (the delete command, inspect) is forgotten
# as it goes (lib's thing_exited).
func lib_ready(lib) -> void:
	_lib = lib
	if lib:
		lib.follow(self, "lib", "thing_exited", _gone)


func _gone(node_name: String) -> void:
	if _made.has(node_name):
		_made.erase(node_name)
		shape_changed.emit(node_name, "removed")


# Only while the attach points are shown: they follow the shapes near you.
func _process(delta: float) -> void:
	_since_markers += delta
	if _since_markers >= MARKER_SECONDS:
		_since_markers = 0.0
		_show_markers()


# --- For other modules ---------------------------------------------------------------

func is_made(node_name: String) -> bool:
	return _made.has(node_name)


func recipe(node_name: String) -> Dictionary:
	return _made.get(node_name, {}).duplicate(true)


# A made shape's recipe and where it is (as get_made() has it), and making it
# again from that with no undo of its own: for undoing a delete.
func made_entry(node_name: String) -> Dictionary:
	for entry in get_made()["shapes"]:
		if entry["name"] == node_name:
			return entry
	return {}


func remake(entry: Dictionary) -> void:
	_recreate(entry)


func attach_points(node_name: String) -> Array:
	var node := _node(node_name)
	if node == null:
		return []
	var box := node.get_aabb()
	var c := box.get_center()
	var e := box.end
	var p := box.position
	var out := [
		{"id": "center", "position": c, "normal": Vector3.UP},
		{"id": "top", "position": Vector3(c.x, e.y, c.z), "normal": Vector3.UP},
		{"id": "bottom", "position": Vector3(c.x, p.y, c.z), "normal": Vector3.DOWN},
		{"id": "left", "position": Vector3(p.x, c.y, c.z), "normal": Vector3.LEFT},
		{"id": "right", "position": Vector3(e.x, c.y, c.z), "normal": Vector3.RIGHT},
		{"id": "front", "position": Vector3(c.x, c.y, e.z), "normal": Vector3.BACK},
		{"id": "back", "position": Vector3(c.x, c.y, p.z), "normal": Vector3.FORWARD},
	]
	var made: Dictionary = _expanded(_made.get(node_name, {}))
	match made.get("kind", ""):
		"sweep":
			var path: Array = made["path"]
			var first := _v3(path[0])
			var last := _v3(path[-1])
			out.append({"id": "start", "position": first, "normal": (first - _v3(path[1])).normalized()})
			out.append({"id": "end", "position": last, "normal": (last - _v3(path[-2])).normalized()})
		"revolve":
			out.append({"id": "axis_top", "position": Vector3(0, e.y, 0), "normal": Vector3.UP})
			out.append({"id": "axis_bottom", "position": Vector3(0, p.y, 0), "normal": Vector3.DOWN})
	return out


func attach_transform(node_name: String, id: String):
	var node := _node(node_name)
	if node == null:
		return null
	for point in attach_points(node_name):
		if point["id"] == id:
			var at: Vector3 = node.global_transform * (point["position"] as Vector3)
			var normal: Vector3 = (node.global_basis.inverse().transposed() * (point["normal"] as Vector3)).normalized()
			return Transform3D(_basis_up(normal), at)
	return null


# For save.gd: every made shape's recipe and where it is.
func get_made() -> Dictionary:
	var shapes := []
	for node_name in _made:
		var node := _node(node_name)
		if node == null:
			continue
		var material := node.get_surface_override_material(0) as StandardMaterial3D
		shapes.append({"name": node_name, "recipe": _made[node_name].duplicate(true), "position": _vec_out(node.position),
			"rotation": _vec_out(node.rotation_degrees), "scale": _vec_out(node.scale),
			"color": material.albedo_color.to_html(false) if material else null})
	return {"shapes": shapes}


func set_made(data) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	for node_name in _made.keys():
		_remove(node_name)
	for entry in data.get("shapes", []):
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("recipe")) != TYPE_DICTIONARY:
			continue
		var request: Dictionary = entry.duplicate()
		request.erase("recipe")
		var reply := _create(entry["recipe"], request, false)
		if reply.has("wait"):
			var pending: SlopitectPending = reply["wait"]
			reply = pending.result if pending.finished else await pending.done
		if not reply.get("ok", false):
			push_error("Slopitect shapes: couldn't put back %s: %s" % [entry.get("name"), reply.get("error")])


# --- As a tool -----------------------------------------------------------------------

func tool_info() -> Dictionary:
	var preset := _preset(_tool["preset"])
	var buttons := [{"label": "Mode: " + ("Draw" if _tool["mode"] == "draw" else "Place"), "action": {"cmd": "shapes_tool", "mode": "place" if _tool["mode"] == "draw" else "draw"}}]
	var status := ""
	if _tool["mode"] == "place":
		buttons.append_array([
			{"label": "Kind: " + preset["kind"].capitalize(), "action": {"cmd": "shapes_tool", "kind_step": 1}},
			{"label": "Next: " + _preset(_step_preset(1))["label"], "action": {"cmd": "shapes_tool", "preset_step": 1}},
			{"label": "Smaller", "action": {"cmd": "shapes_tool", "size_step": -1}},
			{"label": "Bigger", "action": {"cmd": "shapes_tool", "size_step": 1}},
		])
		status = "%s, %.2f m, %.2f deep; the trigger places it" % [preset["label"], _tool["size"], _tool["depth"]]
	else:
		buttons.append_array([
			{"label": "On: " + _tool["plane"].capitalize(), "action": {"cmd": "shapes_tool", "plane": "floor" if _tool["plane"] == "wall" else "wall"}},
			{"label": "Extrude", "action": {"cmd": "shapes_draft", "action": "finish", "as": "extrude"}},
			{"label": "Revolve", "action": {"cmd": "shapes_draft", "action": "finish", "as": "revolve"}},
			{"label": "Back a point", "action": {"cmd": "shapes_draft", "action": "remove_last"}},
			{"label": "Cancel", "action": {"cmd": "shapes_draft", "action": "cancel"}},
		])
		status = "%d points on the %s; %.2f deep; the trigger adds one" % [_draft.size(), _tool["plane"], _tool["depth"]]
	buttons.append_array([
		{"label": "Thinner", "action": {"cmd": "shapes_tool", "depth_step": -1}},
		{"label": "Thicker", "action": {"cmd": "shapes_tool", "depth_step": 1}},
		{"label": "Colour", "action": {"cmd": "shapes_tool", "color_step": 1}},
		{"label": "Points: " + ("on" if _tool["show_points"] else "off"), "action": {"cmd": "shapes_tool", "show_points": not _tool["show_points"]}},
	])
	return {"id": "shapes", "label": "Shapes", "order": 15, "buttons": buttons, "status": status}


func tool_selected(on: bool) -> void:
	_selected = on
	_marker.visible = false
	set_physics_process(on)  # the aiming marker


func tool_trigger(down: bool) -> void:
	if not down:
		return
	if _tool["mode"] == "place":
		var at = _aim_ground()
		var position: Vector3 = at if at != null else _in_front()
		var request := {"preset": _tool["preset"], "size": _tool["size"], "depth": _tool["depth"]}
		var reply := _create(request, {"position": _vec_out(position), "rotation": [0, _facing_yaw(), 0],
			"color": COLORS[_tool["color"]], "sit": at != null})
		if not reply.get("ok", false):
			push_error("Slopitect shapes: " + str(reply.get("error")))
		return
	var point = _draw_point()
	if point == null or _draft.size() >= MAX_OUTLINE:
		return
	if _draft.is_empty():
		_draft_frame = _frame_for(point)
	_draft.append(point)
	_show_draft()


func _physics_process(_delta: float) -> void:
	var hit = _aim_ground() if _tool["mode"] == "place" else _draw_point()
	_marker.visible = hit != null
	if hit != null:
		_marker.global_position = hit


# --- Commands ------------------------------------------------------------------------

func _kinds(_request: Dictionary) -> Dictionary:
	var presets := []
	for preset in PRESETS:
		var settings := {"size": "0.05 to 5 m, 0.3 by default", "depth": "0.005 to 5 m, 0.1 by default"}
		for key in preset["params"]:
			var r: Array = preset["params"][key]
			settings[key] = "%s to %s, %s by default" % r
		presets.append({"preset": preset["name"], "kind": preset["kind"], "label": preset["label"], "settings": settings})
	return {"ok": true, "kinds": {
		"extrude": "points [[x, y], ...] (3 to %d, an outline that doesn't cross itself), depth (along z, centred), optional taper (top size, 1 = same), twist (degrees)" % MAX_OUTLINE,
		"revolve": "points [[r, y], ...] (2 to %d; r is the distance from the up axis, the outline is closed back along the axis), optional segments (3 to 64, 24), angle (degrees, 360), closed (true joins the last point to the first: a torus)" % MAX_OUTLINE,
		"sweep": "path [[x, y, z], ...] (2 to %d), radius, optional radius_end, sides (3 to 24, 10), closed (a loop)" % MAX_PATH,
		"loft": "sections [{points [[x, z], ...], y, optional scale}, ...] (2 to 32, bottom up; outlines are evened out to the same number of points), optional smooth",
		"surface": "heights [[...], ...] (rows of numbers, 2 to %d each way) with size [width, depth], or points (rows of [x, y, z]); optional thickness (0 = a sheet), smooth" % MAX_GRID,
		"cut": "made by shapes_cut",
	}, "presets": presets}


func _make_command(request: Dictionary) -> Dictionary:
	var made := {}
	for key in request:
		if not key in ["cmd", "id", "name", "position", "rotation", "scale", "color"]:
			made[key] = request[key]
	if not made.has("preset") and not made.has("kind"):
		return {"ok": false, "error": "shapes_make needs a preset (shapes_kinds lists them) or a kind (%s)" % ", ".join(KINDS)}
	var where := {}
	for key in ["name", "position", "rotation", "scale", "color"]:
		if request.has(key):
			where[key] = request[key]
	if not where.has("position"):
		where["position"] = _vec_out(_in_front())
		if not where.has("rotation"):
			where["rotation"] = [0, _facing_yaw(), 0]
	return _create(made, where)


func _edit_command(request: Dictionary) -> Dictionary:
	var node_name = request.get("name")
	if typeof(node_name) != TYPE_STRING or not _made.has(node_name):
		return {"ok": false, "error": "no made shape named \"%s\" (shapes_list shows them)" % str(node_name)}
	var old: Dictionary = _made[node_name]
	var next: Dictionary
	if request.has("recipe"):
		if typeof(request["recipe"]) != TYPE_DICTIONARY:
			return {"ok": false, "error": "\"recipe\" must be an object, like shapes_list shows"}
		next = request["recipe"].duplicate(true)
	else:
		next = old.duplicate(true)
		for key in request:
			if not key in ["cmd", "id", "name", "recipe"]:
				next[key] = request[key]
	var reply := _rebuild(node_name, next)
	if reply.get("ok", false):
		_undo("edit " + node_name, _rebuild.bind(node_name, old), _rebuild.bind(node_name, next))
	return reply


func _list_command(_request: Dictionary) -> Dictionary:
	var shapes := []
	for entry in get_made()["shapes"]:
		var node := _node(entry["name"])
		entry["vertices"] = _vertex_count(node.mesh) if node else 0
		shapes.append(entry)
	return {"ok": true, "shapes": shapes, "busy": _busy}


func _cut_command(request: Dictionary) -> Dictionary:
	var base := _node(str(request.get("name", "")))
	var cutter := _node(str(request.get("tool", "")))
	if base == null or cutter == null:
		return {"ok": false, "error": "shapes_cut needs name (the shape kept) and tool (the shape it's cut with), both shapes in the world (list shows them)"}
	if base == cutter:
		return {"ok": false, "error": "a shape can't cut itself"}
	var op = request.get("op", "subtract")
	if not OPS.has(op):
		return {"ok": false, "error": "\"op\" must be one of %s" % ", ".join(OPS.keys())}
	var base_recipe := _recipe_of(base)
	var tool_recipe := _recipe_of(cutter)
	if base_recipe.is_empty() or tool_recipe.is_empty():
		return {"ok": false, "error": "only shapes (built-in or made) can be cut, not models"}
	var cut := {"kind": "cut", "op": op, "base": base_recipe, "tool": tool_recipe,
		"base_at": _transform_out(base.global_transform), "tool_at": _transform_out(cutter.global_transform)}
	var problem := _check(cut, 0)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	var base_name := String(base.name)
	var tool_name := String(cutter.name)
	var was_made := _made.has(base_name)
	var old_mesh: Mesh = base.mesh
	var old_shape = base.get_meta("shape", "")
	var tool_copy := _describe_for_undo(cutter)
	var keep_tool: bool = request.get("keep_tool", false) == true
	var pending := SlopitectPending.new()
	_busy += 1
	_when(_mesh_async(cut), func(built: Dictionary):
		_busy -= 1
		if built.has("error"):
			pending.finish({"ok": false, "error": built["error"]})
			return
		if not is_instance_valid(base):
			pending.finish({"ok": false, "error": "%s was deleted while it was being cut" % base_name})
			return
		_put_mesh(base, built["mesh"], cut)
		_made[base_name] = cut
		if not keep_tool and is_instance_valid(cutter):
			_remove(tool_name)
		shape_changed.emit(base_name, "edited")
		_undo("cut " + base_name,
			_uncut.bind(base_name, old_mesh, old_shape, base_recipe if was_made else {}, tool_copy if not keep_tool else {}),
			_recut.bind(base_name, built["mesh"], cut, tool_name if not keep_tool else ""))
		pending.finish({"ok": true, "shape": _describe(base_name), "removed": "" if keep_tool else tool_name}))
	return {"ok": true, "wait": pending}


func _points_command(request: Dictionary) -> Dictionary:
	var node_name := str(request.get("name", ""))
	var node := _node(node_name)
	if node == null:
		return {"ok": false, "error": "no shape named \"%s\" (list shows them)" % node_name}
	var out := []
	for point in attach_points(node_name):
		var world: Transform3D = attach_transform(node_name, point["id"])
		out.append({"id": point["id"], "position": _vec_out(point["position"]), "normal": _vec_out(point["normal"]),
			"world": _vec_out(world.origin), "world_normal": _vec_out(world.basis.y)})
	return {"ok": true, "name": node_name, "points": out}


func _tool_command(request: Dictionary) -> Dictionary:
	var next := _tool.duplicate()
	for key in request:
		var value = request[key]
		match key:
			"cmd", "id":
				pass
			"mode":
				if not value in ["place", "draw"]:
					return {"ok": false, "error": "\"mode\" must be place or draw"}
				next["mode"] = value
			"preset":
				if _preset(str(value)).is_empty():
					return {"ok": false, "error": "no preset \"%s\" (shapes_kinds lists them)" % str(value)}
				next["preset"] = value
			"preset_step", "kind_step", "size_step", "depth_step", "color_step":
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value == 0:
					return {"ok": false, "error": "\"%s\" must be 1 or -1" % key}
				var sign := 1 if value > 0 else -1
				match key:
					"preset_step":
						next["preset"] = _step_preset(sign, next["preset"])
					"kind_step":
						next["preset"] = _step_kind(sign, next["preset"])
					"size_step":
						next["size"] = snappedf(clampf(next["size"] * (1.25 if sign > 0 else 0.8), 0.05, 5.0), 0.001)
					"depth_step":
						next["depth"] = snappedf(clampf(next["depth"] * (1.25 if sign > 0 else 0.8), 0.005, 5.0), 0.001)
					"color_step":
						next["color"] = posmod(next["color"] + sign, COLORS.size())
			"size", "depth":
				var low := 0.05 if key == "size" else 0.005
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < low or value > 5.0:
					return {"ok": false, "error": "\"%s\" must be %s to 5 m" % [key, low]}
				next[key] = float(value)
			"plane":
				if not value in ["wall", "floor"]:
					return {"ok": false, "error": "\"plane\" must be wall or floor"}
				if value != next["plane"]:
					_clear_draft()  # an outline is on one plane
				next["plane"] = value
			"show_points":
				if typeof(value) != TYPE_BOOL:
					return {"ok": false, "error": "\"show_points\" must be true or false"}
				next["show_points"] = value
			_:
				return {"ok": false, "error": "shapes_tool doesn't take \"%s\"" % key}
	if next["mode"] != _tool["mode"]:
		_clear_draft()
	_tool = next
	_markers.visible = _tool["show_points"]
	set_process(_tool["show_points"])
	if _tool["show_points"]:
		_show_markers()
	if _lib:
		_lib.touch(self)  # the tool's buttons show these
	return {"ok": true, "tool": _tool.duplicate(), "status": tool_info()["status"]}


func _draft_command(request: Dictionary) -> Dictionary:
	match request.get("action"):
		"cancel":
			_clear_draft()
			return {"ok": true, "points": 0}
		"remove_last":
			if not _draft.is_empty():
				_draft.pop_back()
			_show_draft()
			return {"ok": true, "points": _draft.size()}
		"finish":
			var kind = request.get("as", "extrude")
			if not kind in ["extrude", "revolve"]:
				return {"ok": false, "error": "\"as\" must be extrude or revolve"}
			return _finish_draft(kind)
	return {"ok": false, "error": "\"action\" must be finish, remove_last or cancel"}


# --- Making shapes -------------------------------------------------------------------

# Makes a shape from a recipe; where has name, position, rotation, scale,
# color, and sit (true: its bottom rests on position). One undo, unless
# with_undo is false (putting back a save, or a redo).
func _create(made: Dictionary, where: Dictionary, with_undo := true) -> Dictionary:
	if _made.size() >= MAX_SHAPES:
		return {"ok": false, "error": "there are already %d made shapes, the most allowed" % MAX_SHAPES}
	var problem := _check(made, 0)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	var world: Node3D = ctx["world"]
	var node_name = where.get("name", "")
	if typeof(node_name) != TYPE_STRING:
		return {"ok": false, "error": "\"name\" must be a string"}
	if node_name.is_empty():
		node_name = _free_name(str(made.get("preset", made.get("kind"))))
	elif node_name.validate_node_name() != node_name:
		return {"ok": false, "error": "name \"%s\" can't contain . : @ / \" %% or spaces at the ends" % node_name}
	elif world.has_node(NodePath(node_name)):
		return {"ok": false, "error": "something named \"%s\" already exists" % node_name}
	var values := {}
	for key in ["position", "rotation", "scale"]:
		if where.has(key):
			var parsed := _vec_in(where[key], key)
			if parsed.has("error"):
				return {"ok": false, "error": parsed["error"]}
			values[key] = parsed["vec"]
	if values.has("scale") and (values["scale"] as Vector3)[(values["scale"] as Vector3).min_axis_index()] <= 0.0:
		return {"ok": false, "error": "\"scale\" values must all be above 0"}
	var color := Color.from_string(COLORS[0], Color.WHITE)
	if where.get("color") != null:
		var parsed := _color_in(where["color"])
		if parsed.has("error"):
			return {"ok": false, "error": parsed["error"]}
		color = parsed["color"]

	var node := MeshInstance3D.new()
	node.name = node_name
	node.position = values.get("position", Vector3.ZERO)
	node.rotation_degrees = values.get("rotation", Vector3.ZERO)
	node.scale = values.get("scale", Vector3.ONE)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.set_meta("made", true)
	var sit: bool = where.get("sit", false) == true
	var finish := func(built: Dictionary) -> Dictionary:
		if built.has("error"):
			node.free()
			return {"ok": false, "error": built["error"]}
		if world.has_node(NodePath(node_name)):
			node.free()
			return {"ok": false, "error": "something named \"%s\" appeared while it was being made" % node_name}
		_put_mesh(node, built["mesh"], made, material)
		if sit:  # its lowest point on the ground
			node.position.y += node.position.y - (node.transform * (built["mesh"] as Mesh).get_aabb()).position.y
		world.add_child(node)
		_made[node_name] = made.duplicate(true)
		shape_changed.emit(node_name, "made")
		if with_undo:
			var copy := get_made()["shapes"].filter(func(e): return e["name"] == node_name)[0] as Dictionary
			_undo("make " + node_name, _remove.bind(node_name), _recreate.bind(copy))
		return {"ok": true, "shape": _describe(node_name)}
	if not _has_cut(made):
		return finish.call(_mesh(made))
	var pending := SlopitectPending.new()
	_busy += 1
	_when(_mesh_async(made), func(built: Dictionary):
		_busy -= 1
		pending.finish(finish.call(built)))
	return {"ok": true, "wait": pending}


func _recreate(entry: Dictionary) -> void:
	var where: Dictionary = entry.duplicate()
	where.erase("recipe")
	_create(entry["recipe"], where, false)


func _rebuild(node_name: String, next: Dictionary) -> Dictionary:
	var node := _node(node_name)
	if node == null:
		return {"ok": false, "error": "no shape named \"%s\"" % node_name}
	var problem := _check(next, 0)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	if _has_cut(next):
		var pending := SlopitectPending.new()
		_when(_mesh_async(next), func(built: Dictionary):
			if built.has("error") or not is_instance_valid(node):
				pending.finish({"ok": false, "error": built.get("error", "the shape was deleted")})
				return
			_put_mesh(node, built["mesh"], next)
			_made[node_name] = next.duplicate(true)
			shape_changed.emit(node_name, "edited")
			pending.finish({"ok": true, "shape": _describe(node_name)}))
		return {"ok": true, "wait": pending}
	var built := _mesh(next)
	if built.has("error"):
		return {"ok": false, "error": built["error"]}
	_put_mesh(node, built["mesh"], next)
	_made[node_name] = next.duplicate(true)
	shape_changed.emit(node_name, "edited")
	return {"ok": true, "shape": _describe(node_name)}


func _remove(node_name: String) -> void:
	var node := _node(node_name)
	_made.erase(node_name)
	if node:
		node.get_parent().remove_child(node)
		node.queue_free()
	shape_changed.emit(node_name, "removed")


func _uncut(base_name: String, old_mesh: Mesh, old_shape, old_recipe: Dictionary, tool_copy: Dictionary) -> void:
	var node := _node(base_name)
	if node:
		node.mesh = old_mesh
		node.set_meta("shape", old_shape)
		if old_recipe.is_empty():
			_made.erase(base_name)
			node.remove_meta("made")
		else:
			_made[base_name] = old_recipe
		shape_changed.emit(base_name, "edited")
	if tool_copy.is_empty():
		return
	if tool_copy.has("recipe"):
		_recreate(tool_copy)
	else:
		ctx["server"].run(tool_copy)


func _recut(base_name: String, mesh: Mesh, cut: Dictionary, tool_name: String) -> void:
	var node := _node(base_name)
	if node:
		node.set_meta("made", true)
		_put_mesh(node, mesh, cut)
		_made[base_name] = cut
		shape_changed.emit(base_name, "edited")
	if not tool_name.is_empty() and _node(tool_name):
		if _made.has(tool_name):
			_remove(tool_name)
		else:  # the cut's own undo brings it back, so the delete adds none
			var tools: SlopitectModule = ctx["modules"].module("tools")
			if tools and tools.has_method("quiet"):
				tools.call("quiet", ctx["server"].run.bind({"cmd": "delete", "name": tool_name}))
			else:
				ctx["server"].run({"cmd": "delete", "name": tool_name})


func _put_mesh(node: MeshInstance3D, mesh: Mesh, made: Dictionary, material: Material = null) -> void:
	if material == null and node.mesh and node.mesh.get_surface_count() > 0:
		material = node.get_surface_override_material(0)
	node.mesh = mesh
	if material:
		var open := _is_open(made)
		(material as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED if open else BaseMaterial3D.CULL_BACK
		for i in mesh.get_surface_count():
			node.set_surface_override_material(i, material)
	node.set_meta("shape", str(made.get("preset", made.get("kind"))))


func _describe(node_name: String) -> Dictionary:
	var node := _node(node_name)
	var out := {"name": node_name, "position": _vec_out(node.position), "rotation": _vec_out(node.rotation_degrees),
		"scale": _vec_out(node.scale), "vertices": _vertex_count(node.mesh), "size": _vec_out(node.mesh.get_aabb().size * node.scale)}
	out["recipe"] = _made.get(node_name, {}).duplicate(true)
	return out


# What brings a cut's tool back: a made shape's recipe and place, or the
# spawn command for a built-in one.
func _describe_for_undo(node: MeshInstance3D) -> Dictionary:
	var node_name := String(node.name)
	if _made.has(node_name):
		return get_made()["shapes"].filter(func(e): return e["name"] == node_name)[0]
	var material := node.get_surface_override_material(0) as StandardMaterial3D
	var out := {"cmd": "spawn", "name": node_name, "shape": node.get_meta("shape", "box"), "position": _vec_out(node.position),
		"rotation": _vec_out(node.rotation_degrees), "scale": _vec_out(node.scale)}
	if material:
		out["color"] = "#" + material.albedo_color.to_html(false)
	return out


func _recipe_of(node: Node) -> Dictionary:
	if not node is MeshInstance3D:
		return {}
	if _made.has(String(node.name)):
		return _made[String(node.name)].duplicate(true)
	var shape = node.get_meta("shape", "")
	return {"kind": shape} if shape in PRIMITIVES else {}


# --- Drawing an outline --------------------------------------------------------------

func _draw_point():
	if _tool["plane"] == "floor":
		return _aim_ground()
	var hand: Node3D = ctx["right"]
	var tip: Vector3 = hand.global_position - hand.global_basis.z * TIP
	if _draft.is_empty():
		return tip
	var frame: Dictionary = _draft_frame
	var normal: Vector3 = frame["basis"].z
	return tip - normal * (tip - (frame["origin"] as Vector3)).dot(normal)


# The plane the outline is drawn on: x right, y up, z towards you (wall), or
# x east, y north, z up (floor).
func _frame_for(first: Vector3) -> Dictionary:
	if _tool["plane"] == "floor":
		return {"origin": first, "basis": Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)}
	var back: Vector3 = (ctx["camera"] as Node3D).global_basis.z
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	return {"origin": first, "basis": Basis(Vector3.UP.cross(back), Vector3.UP, back)}


func _finish_draft(kind: String) -> Dictionary:
	if _draft.size() < (3 if kind == "extrude" else 2):
		return {"ok": false, "error": "put down at least %d points first" % (3 if kind == "extrude" else 2)}
	if kind == "revolve" and _tool["plane"] == "floor":
		return {"ok": false, "error": "revolve needs an outline drawn on the wall (the side of the shape)"}
	var basis: Basis = _draft_frame["basis"]
	var origin: Vector3 = _draft_frame["origin"]
	var flat := PackedVector2Array()
	for p: Vector3 in _draft:
		flat.append(Vector2((p - origin).dot(basis.x), (p - origin).dot(basis.y)))
	var made: Dictionary
	var position: Vector3
	var rotation := Vector3.ZERO
	if kind == "extrude":
		var box := Rect2(flat[0], Vector2.ZERO)
		for p in flat:
			box = box.expand(p)
		var c := box.get_center()
		var points := []
		for p in flat:
			points.append([snappedf(p.x - c.x, 0.001), snappedf(p.y - c.y, 0.001)])
		made = {"kind": "extrude", "points": points, "depth": _tool["depth"]}
		position = origin + basis.x * c.x + basis.y * c.y
		if _tool["plane"] == "floor":
			var lowest := INF
			for p: Vector3 in _draft:
				lowest = minf(lowest, p.y)
			position.y = lowest + _tool["depth"] / 2.0
		rotation = basis.get_euler() * (180.0 / PI)
	else:
		var points := []
		for p in flat:
			points.append([snappedf(absf(p.x), 0.001), snappedf(p.y, 0.001)])
		made = {"kind": "revolve", "points": points}
		position = origin
	var reply := _create(made, {"position": _vec_out(position), "rotation": _vec_out(rotation), "color": COLORS[_tool["color"]]})
	if reply.get("ok", false):
		_clear_draft()
	return reply


func _show_draft() -> void:
	var lines: ImmediateMesh = _draft_mesh.mesh
	lines.clear_surfaces()
	if _draft.is_empty():
		return
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in _draft.size():
		var p: Vector3 = _draft[i]
		for d in [Vector3(0.01, 0, 0), Vector3(0, 0.01, 0), Vector3(0, 0, 0.01)]:
			lines.surface_add_vertex(p - d)
			lines.surface_add_vertex(p + d)
		if i > 0:
			lines.surface_add_vertex(_draft[i - 1])
			lines.surface_add_vertex(p)
	if _draft.size() > 2:
		lines.surface_add_vertex(_draft[-1])
		lines.surface_add_vertex(_draft[0])
	lines.surface_end()


func _clear_draft() -> void:
	_draft.clear()
	if _draft_mesh:
		(_draft_mesh.mesh as ImmediateMesh).clear_surfaces()


func _show_markers() -> void:
	var at := []
	var camera: Vector3 = (ctx["camera"] as Node3D).global_position
	for child in (ctx["world"] as Node3D).get_children():
		if not child is MeshInstance3D or not child.is_visible_in_tree():
			continue
		if child.global_position.distance_to(camera) > MARKER_RANGE:
			continue
		for point in attach_points(String(child.name)):
			at.append(child.global_transform * (point["position"] as Vector3))
	var multimesh := _markers.multimesh
	multimesh.instance_count = at.size()
	for i in at.size():
		multimesh.set_instance_transform(i, Transform3D(Basis(), at[i]))


# --- Recipes -------------------------------------------------------------------------

func _preset(preset_name: String) -> Dictionary:
	for preset in PRESETS:
		if preset["name"] == preset_name:
			return preset
	return {}


func _preset_index(preset_name: String) -> int:
	for i in PRESETS.size():
		if PRESETS[i]["name"] == preset_name:
			return i
	return 0


func _step_preset(sign: int, from: String = "") -> String:
	var i := _preset_index(from if not from.is_empty() else _tool["preset"])
	return PRESETS[posmod(i + sign, PRESETS.size())]["name"]


func _step_kind(sign: int, from: String) -> String:
	var kind: String = _preset(from)["kind"]
	var next: String = KINDS[posmod(KINDS.find(kind) + sign, KINDS.size())]
	for preset in PRESETS:
		if preset["kind"] == next:
			return preset["name"]
	return from


# A preset's recipe as the kind it's made from; any other recipe as it is.
func _expanded(made: Dictionary) -> Dictionary:
	if not made.has("preset"):
		return made
	var preset := _preset(str(made["preset"]))
	var p := {}
	for key in preset["params"]:
		var r: Array = preset["params"][key]
		p[key] = clampf(float(made.get(key, r[2])), r[0], r[1])
	var s := clampf(float(made.get("size", 0.3)), 0.05, 5.0)
	var d := clampf(float(made.get("depth", 0.1)), 0.005, 5.0)
	var h := s / 2.0
	var out: Dictionary
	match preset["name"]:
		"polygon":
			out = {"kind": "extrude", "points": _circle(h, int(p["sides"]))}
		"star":
			var pts := []
			var n := int(p["points"])
			for i in n * 2:
				var a := PI / 2.0 + TAU * i / (n * 2)
				var r: float = h if i % 2 == 0 else h * p["inner"]
				pts.append([cos(a) * r, sin(a) * r])
			out = {"kind": "extrude", "points": pts}
		"gear":
			var pts := []
			var n := int(p["teeth"])
			var root := h * 0.8
			for i in n:
				var a := TAU * i / n
				var step := TAU / n
				for k in [[0.0, root], [0.2, h], [0.5, h], [0.7, root]]:
					pts.append([cos(a + step * k[0]) * k[1], sin(a + step * k[0]) * k[1]])
			out = {"kind": "extrude", "points": pts}
		"cross":
			var w := s / 6.0
			out = {"kind": "extrude", "points": [[-w, -h], [w, -h], [w, -w], [h, -w], [h, w], [w, w], [w, h], [-w, h], [-w, w], [-h, w], [-h, -w], [-w, -w]]}
		"l_beam":
			var t: float = s * p["wall"]
			out = {"kind": "extrude", "points": [[-h, -h], [h, -h], [h, -h + t], [-h + t, -h + t], [-h + t, h], [-h, h]]}
		"t_beam":
			var t: float = s * p["wall"]
			out = {"kind": "extrude", "points": [[-t / 2, -h], [t / 2, -h], [t / 2, h - t], [h, h - t], [h, h], [-h, h], [-h, h - t], [-t / 2, h - t]]}
		"i_beam":
			var t: float = s * p["wall"]
			out = {"kind": "extrude", "points": [[-h, -h], [h, -h], [h, -h + t], [t / 2, -h + t], [t / 2, h - t], [h, h - t], [h, h], [-h, h], [-h, h - t], [-t / 2, h - t], [-t / 2, -h + t], [-h, -h + t]]}
		"u_channel":
			var t: float = s * p["wall"]
			out = {"kind": "extrude", "points": [[-h, -h], [h, -h], [h, h], [h - t, h], [h - t, -h + t], [-h + t, -h + t], [-h + t, h], [-h, h]]}
		"arch":
			var r: float = h * p["opening"]
			var leg := s * 0.5
			var pts := [[-h, 0.0], [-h, leg]]
			for i in range(1, 12):
				var a := PI - PI * i / 12.0
				pts.append([cos(a) * h, leg + sin(a) * h])
			pts.append_array([[h, leg], [h, 0.0], [r, 0.0], [r, leg]])
			for i in range(1, 12):
				var a := PI * i / 12.0
				pts.append([cos(a) * r, leg + sin(a) * r])
			pts.append_array([[-r, leg], [-r, 0.0]])
			out = {"kind": "extrude", "points": _centred(pts)}
		"stairs":
			var n := int(p["steps"])
			var pts := [[0.0, 0.0], [s, 0.0]]
			for i in range(n, 0, -1):
				pts.append([s * i / n, s * i / n])
				pts.append([s * (i - 1) / n, s * i / n])
			pts.pop_back()
			pts.append([0.0, s / n])
			out = {"kind": "extrude", "points": _centred(pts)}
		"ramp":
			out = {"kind": "extrude", "points": _centred([[0.0, 0.0], [s, 0.0], [s, s * p["rise"]]])}
		"cone":
			out = {"kind": "revolve", "points": [[0, -h], [h, -h], [0, h]]}
		"frustum":
			out = {"kind": "revolve", "points": [[0, -h], [h, -h], [h * p["top"], h], [0, h]]}
		"dome":
			var pts := [[0, 0]]
			for i in 9:
				var a := PI / 2.0 * i / 8.0
				pts.append([cos(a) * h, sin(a) * h])
			out = {"kind": "revolve", "points": pts}
		"bowl":
			var t: float = h * p["wall"] * 2.0
			var r := maxf(h - t, h * 0.05)
			var pts := []
			for i in 9:
				var a := PI / 2.0 * i / 8.0
				pts.append([sin(a) * h, h - cos(a) * h])
			for i in range(8, -1, -1):
				var a := PI / 2.0 * i / 8.0
				pts.append([sin(a) * r, h - cos(a) * r])
			out = {"kind": "revolve", "points": _offset(pts, 0.0, -h / 2.0)}
		"vase":
			var shape := [[0, 0], [0.35, 0], [0.5, 0.2], [0.45, 0.5], [0.25, 0.75], [0.3, 1.0], [0.26, 1.0], [0.21, 0.76], [0.41, 0.5], [0.46, 0.2], [0.31, 0.04], [0, 0.04]]
			var pts := []
			for q in shape:
				pts.append([q[0] * h, (q[1] - 0.5) * s])
			out = {"kind": "revolve", "points": pts}
		"torus":
			var minor: float = h * p["thickness"] / 2.0
			var pts := []
			for i in 12:
				var a := TAU * i / 12.0
				pts.append([h - minor + cos(a) * minor, sin(a) * minor])
			out = {"kind": "revolve", "points": pts, "closed": true}
		"ring":
			var inner: float = h * (1.0 - p["thickness"])
			out = {"kind": "revolve", "points": [[inner, -d / 2], [h, -d / 2], [h, d / 2], [inner, d / 2]], "closed": true}
		"elbow":
			var path := []
			for i in 9:
				var a := PI / 2.0 * i / 8.0
				path.append([cos(a) * h - h / 2, sin(a) * h - h / 2, 0])
			out = {"kind": "sweep", "path": path, "radius": h * p["thickness"] / 2.0, "sides": 12}
		"spring":
			var path := []
			var turns := int(p["turns"])
			var count := mini(turns * 12 + 1, MAX_PATH)
			for i in count:
				var t := float(i) / (count - 1)
				var a := TAU * turns * t
				path.append([cos(a) * h * 0.8, s * (t - 0.5), sin(a) * h * 0.8])
			out = {"kind": "sweep", "path": path, "radius": s * 0.04, "sides": 8}
		"handle":
			var path := [[-h, -h / 3, 0]]
			for i in 9:
				var a := PI - PI * i / 8.0
				path.append([cos(a) * h, sin(a) * h * 0.6, 0])
			path.append([h, -h / 3, 0])
			out = {"kind": "sweep", "path": path, "radius": s * 0.05, "sides": 10}
		"pyramid":
			var square := [[-h, -h], [h, -h], [h, h], [-h, h]]
			out = {"kind": "loft", "sections": [{"points": square, "y": -h}, {"points": square, "y": h, "scale": 0.001}], "smooth": false}
		"square_round":
			out = {"kind": "loft", "sections": [{"points": [[-h, -h], [h, -h], [h, h], [-h, h]], "y": -h}, {"points": _circle(h, 16), "y": h}], "smooth": true}
		"panel":
			var bend: float = deg_to_rad(p["bend"])
			var rows := []
			for v in [-h, h]:
				var row := []
				for i in 13:
					var t := float(i) / 12.0 - 0.5
					if bend < 0.01:
						row.append([t * s, v, 0])
					else:
						var radius := s / bend
						var a := t * bend
						row.append([sin(a) * radius, v, radius - cos(a) * radius])
				rows.append(row)
			out = {"kind": "surface", "points": rows, "thickness": d}
		"wave":
			var heights := []
			for j in 16:
				var row := []
				for i in 16:
					row.append(sin(i / 15.0 * TAU) * cos(j / 15.0 * PI) * s * p["height"])
				heights.append(row)
			out = {"kind": "surface", "heights": heights, "size": [s, s], "thickness": 0}
	if preset["kind"] == "extrude":
		out["depth"] = d
	return out


func _circle(r: float, n: int) -> Array:
	var pts := []
	for i in n:
		var a := PI / 2.0 + TAU * i / n
		pts.append([cos(a) * r, sin(a) * r])
	return pts


func _centred(pts: Array) -> Array:
	var box := Rect2(Vector2(pts[0][0], pts[0][1]), Vector2.ZERO)
	for p in pts:
		box = box.expand(Vector2(p[0], p[1]))
	var c := box.get_center()
	return _offset(pts, -c.x, -c.y)


func _offset(pts: Array, x: float, y: float) -> Array:
	var out := []
	for p in pts:
		out.append([p[0] + x, p[1] + y])
	return out


func _has_cut(made: Dictionary) -> bool:
	return made.get("kind") == "cut"


func _is_open(made: Dictionary) -> bool:
	var full := _expanded(made)
	match full.get("kind"):
		"surface":
			return float(full.get("thickness", 0)) <= 0.0
		"revolve":
			return float(full.get("angle", 360)) < 360.0
	return false


# Checks a recipe before anything is built; "" when it's fine.
func _check(made: Dictionary, depth: int) -> String:
	if depth > MAX_CUT_DEPTH:
		return "a shape can be cut at most %d times over" % MAX_CUT_DEPTH
	if made.has("preset"):
		if _preset(str(made["preset"])).is_empty():
			return "no preset \"%s\" (shapes_kinds lists them)" % str(made["preset"])
		for key in made:
			if key in ["preset", "size", "depth"] or _preset(made["preset"])["params"].has(key):
				if key != "preset" and typeof(made[key]) not in [TYPE_INT, TYPE_FLOAT]:
					return "\"%s\" must be a number" % key
			else:
				return "the %s preset doesn't take \"%s\" (shapes_kinds lists its settings)" % [made["preset"], key]
		return ""
	var kind = made.get("kind")
	if depth > 0 and kind in PRIMITIVES:
		return ""
	match kind:
		"extrude":
			var problem := _check_outline(made.get("points"), "points", 3)
			if not problem.is_empty():
				return problem
			if _triangles(_outline(made["points"])).is_empty():
				return "the outline crosses itself or is flat; its points must go round it in order"
			return _check_numbers(made, {"depth": [0.001, LIMIT, true], "taper": [0.0, 5.0, false], "twist": [-720.0, 720.0, false]})
		"revolve":
			var problem := _check_outline(made.get("points"), "points", 2)
			if not problem.is_empty():
				return problem
			for p in made["points"]:
				if p[0] < 0:
					return "a revolve's points are [r, y] with r (the distance from the axis) 0 or more"
			if made.has("closed") and typeof(made["closed"]) != TYPE_BOOL:
				return "\"closed\" must be true or false"
			return _check_numbers(made, {"segments": [3, 64, false], "angle": [1.0, 360.0, false]})
		"sweep":
			var path = made.get("path")
			if typeof(path) != TYPE_ARRAY or path.size() < 2 or path.size() > MAX_PATH:
				return "\"path\" must be 2 to %d points [x, y, z]" % MAX_PATH
			for p in path:
				if _vec_in(p, "path").has("error") or absf(p[0]) > LIMIT or absf(p[1]) > LIMIT or absf(p[2]) > LIMIT:
					return "each point of \"path\" must be [x, y, z] within %d m" % LIMIT
			for i in range(1, path.size()):
				if _v3(path[i]).distance_to(_v3(path[i - 1])) < 0.0005:
					return "two points of \"path\" in a row are in the same place"
			if made.has("closed") and typeof(made["closed"]) != TYPE_BOOL:
				return "\"closed\" must be true or false"
			return _check_numbers(made, {"radius": [0.001, 5.0, true], "radius_end": [0.0, 5.0, false], "sides": [3, 24, false]})
		"loft":
			var sections = made.get("sections")
			if typeof(sections) != TYPE_ARRAY or sections.size() < 2 or sections.size() > 32:
				return "\"sections\" must be 2 to 32 of {points, y, scale}"
			for section in sections:
				if typeof(section) != TYPE_DICTIONARY:
					return "each section must be {points [[x, z], ...], y, optional scale}"
				var problem := _check_outline(section.get("points"), "a section's points", 3)
				if problem.is_empty():
					problem = _check_numbers(section, {"y": [-LIMIT, LIMIT, true], "scale": [0.0, 10.0, false]})
				if not problem.is_empty():
					return problem
			if made.has("smooth") and typeof(made["smooth"]) != TYPE_BOOL:
				return "\"smooth\" must be true or false"
			return ""
		"surface":
			var rows = made.get("heights", made.get("points"))
			if typeof(rows) != TYPE_ARRAY or rows.size() < 2 or rows.size() > MAX_GRID:
				return "a surface needs heights (rows of numbers) with size, or points (rows of [x, y, z]): 2 to %d rows" % MAX_GRID
			var width := -1
			for row in rows:
				if typeof(row) != TYPE_ARRAY or row.size() < 2 or row.size() > MAX_GRID or (width != -1 and row.size() != width):
					return "every row must have the same number of entries, 2 to %d" % MAX_GRID
				width = row.size()
				for v in row:
					if made.has("heights"):
						if typeof(v) not in [TYPE_INT, TYPE_FLOAT] or absf(v) > LIMIT:
							return "each height must be a number within %d m" % LIMIT
					elif _vec_in(v, "points").has("error") or absf(v[0]) > LIMIT or absf(v[1]) > LIMIT or absf(v[2]) > LIMIT:
						return "each point must be [x, y, z] within %d m" % LIMIT
			if made.has("heights"):
				var size = made.get("size")
				if typeof(size) != TYPE_ARRAY or size.size() != 2 or typeof(size[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(size[1]) not in [TYPE_INT, TYPE_FLOAT] or size[0] <= 0 or size[1] <= 0 or size[0] > LIMIT or size[1] > LIMIT:
					return "a surface from heights needs size [width, depth] in metres"
			if made.has("smooth") and typeof(made["smooth"]) != TYPE_BOOL:
				return "\"smooth\" must be true or false"
			return _check_numbers(made, {"thickness": [0.0, 2.0, false]})
		"cut":
			if not OPS.has(made.get("op")):
				return "a cut's op must be one of %s" % ", ".join(OPS.keys())
			for key in ["base", "tool"]:
				if typeof(made.get(key)) != TYPE_DICTIONARY:
					return "a cut needs %s (a recipe)" % key
				var problem := _check(made[key], depth + 1)
				if not problem.is_empty():
					return problem
			for key in ["base_at", "tool_at"]:
				if _transform_in(made.get(key)) == null:
					return "a cut's %s must be 12 numbers (a transform)" % key
			return ""
	return "\"kind\" must be one of %s (or use a preset)" % ", ".join(KINDS)


func _check_outline(points, what: String, least: int) -> String:
	if typeof(points) != TYPE_ARRAY or points.size() < least or points.size() > MAX_OUTLINE:
		return "%s must be %d to %d points [x, y]" % [what, least, MAX_OUTLINE]
	for p in points:
		if typeof(p) != TYPE_ARRAY or p.size() != 2 or typeof(p[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(p[1]) not in [TYPE_INT, TYPE_FLOAT] or absf(p[0]) > LIMIT or absf(p[1]) > LIMIT:
			return "each of %s must be [x, y] within %d m; got %s" % [what, LIMIT, JSON.stringify(p)]
	return ""


# fields: name -> [low, high, needed]
func _check_numbers(made: Dictionary, fields: Dictionary) -> String:
	for key in fields:
		var r: Array = fields[key]
		if not made.has(key):
			if r[2]:
				return "this kind needs \"%s\" (%s to %s)" % [key, r[0], r[1]]
			continue
		var v = made[key]
		if typeof(v) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(v)) or v < r[0] or v > r[1]:
			return "\"%s\" must be %s to %s" % [key, r[0], r[1]]
	return ""


# --- Meshes --------------------------------------------------------------------------

# Builds a recipe's mesh (not a cut): {"mesh"} or {"error"}.
func _mesh(made: Dictionary) -> Dictionary:
	var full := _expanded(made)
	var geo := Geo.new()
	match full.get("kind"):
		"extrude":
			_extrude(geo, full)
		"revolve":
			_revolve(geo, full)
		"sweep":
			_sweep(geo, full)
		"loft":
			_loft(geo, full)
		"surface":
			_surface(geo, full)
		"box", "sphere", "cylinder", "capsule":
			return {"mesh": _primitive(full["kind"])}
		_:
			return {"error": "can't build a \"%s\"" % str(full.get("kind"))}
	if geo.v.size() > MAX_VERTS:
		return {"error": "that shape needs %d vertices, more than the %d allowed on the Quest 1; use fewer points or segments" % [geo.v.size(), MAX_VERTS]}
	if geo.idx.is_empty():
		return {"error": "that recipe makes nothing to see"}
	return {"mesh": geo.mesh()}


# Any recipe, cuts too; a cut is built by the engine's CSG a frame later.
# Finishes with {"mesh"} or {"error"}.
func _mesh_async(made: Dictionary) -> SlopitectPending:
	var pending := SlopitectPending.new()
	_build_async(made, pending)
	return pending


func _build_async(made: Dictionary, pending: SlopitectPending) -> void:
	if not _has_cut(made):
		pending.finish(_mesh(made))
		return
	var parts := []
	for key in ["base", "tool"]:
		var part := _mesh_async(made[key])
		var built: Dictionary = part.result if part.finished else await part.done
		if built.has("error"):
			pending.finish(built)
			return
		parts.append(built["mesh"])
	var base_at: Transform3D = _transform_in(made["base_at"])
	var combiner := CSGCombiner3D.new()
	combiner.visible = false
	add_child(combiner)
	var a := CSGMesh3D.new()
	a.mesh = parts[0]
	a.transform = base_at
	combiner.add_child(a)
	var b := CSGMesh3D.new()
	b.mesh = parts[1]
	b.transform = _transform_in(made["tool_at"])
	b.operation = OPS[made["op"]]
	combiner.add_child(b)
	await get_tree().process_frame
	var baked: ArrayMesh = combiner.bake_static_mesh()
	combiner.queue_free()
	if baked == null or baked.get_surface_count() == 0:
		pending.finish({"error": "the cut left nothing (do the two shapes overlap?)"})
		return
	# Back into the kept shape's own space.
	var to_local := base_at.affine_inverse()
	var normal_basis := base_at.basis.transposed()
	var out := ArrayMesh.new()
	var count := 0
	for s in baked.get_surface_count():
		var arrays := baked.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			verts[i] = to_local * verts[i]
			if i < normals.size():
				normals[i] = (normal_basis * normals[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		count += verts.size()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if count > MAX_VERTS:
		pending.finish({"error": "the cut needs %d vertices, more than the %d allowed on the Quest 1" % [count, MAX_VERTS]})
		return
	pending.finish({"mesh": out})


# The built-in shapes, the sizes the APK makes them, with fewer segments.
func _primitive(kind: String) -> Mesh:
	match kind:
		"sphere":
			var m := SphereMesh.new()
			m.radial_segments = 24
			m.rings = 12
			return m
		"cylinder":
			var m := CylinderMesh.new()
			m.radial_segments = 24
			m.rings = 1
			return m
		"capsule":
			var m := CapsuleMesh.new()
			m.radial_segments = 24
			m.rings = 6
			return m
	return BoxMesh.new()


func _outline(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		var v := Vector2(p[0], p[1])
		if out.is_empty() or out[-1].distance_to(v) > 0.0001:
			out.append(v)
	if out.size() > 1 and out[0].distance_to(out[-1]) <= 0.0001:
		out.remove_at(out.size() - 1)
	if _area(out) < 0.0:
		out.reverse()  # anticlockwise from here on
	return out


func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return a / 2.0


func _triangles(pts: PackedVector2Array) -> PackedInt32Array:
	if pts.size() < 3 or absf(_area(pts)) < 1e-8:
		return PackedInt32Array()
	return Geometry2D.triangulate_polygon(pts)


func _extrude(geo: Geo, made: Dictionary) -> void:
	var pts := _outline(made["points"])
	var tris := _triangles(pts)
	var depth: float = made["depth"]
	var taper := float(made.get("taper", 1.0))
	var twist := deg_to_rad(float(made.get("twist", 0.0)))
	var steps := maxi(1, ceili(absf(rad_to_deg(twist)) / 15.0))
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var layers := []
	for k in steps + 1:
		var t := float(k) / steps
		var layer := PackedVector3Array()
		for p in pts:
			var q := (p - c).rotated(twist * t) * lerpf(1.0, taper, t) + c
			layer.append(Vector3(q.x, q.y, -depth / 2.0 + depth * t))
		layers.append(layer)
	# The sides, a flat face for each edge so corners stay sharp.
	var n := pts.size()
	for k in steps:
		var along := 0.0
		for i in n:
			var j := (i + 1) % n
			var a: Vector3 = layers[k][i]
			var b: Vector3 = layers[k][j]
			var a2: Vector3 = layers[k + 1][i]
			var b2: Vector3 = layers[k + 1][j]
			var edge := pts[j] - pts[i]
			var out := Vector3(edge.y, -edge.x, 0.0)
			var length := edge.length()
			geo.quad(a, b, b2, a2, out, [Vector2(along, a.z), Vector2(along + length, b.z), Vector2(along + length, b2.z), Vector2(along, a2.z)])
			along += length
	# The two ends.
	for end in [[0, Vector3.FORWARD], [steps, Vector3.BACK]]:
		var layer: PackedVector3Array = layers[end[0]]
		var first := geo.v.size()
		for p in layer:
			geo.add(p, end[1], Vector2(p.x, -p.y))
		for t in range(0, tris.size(), 3):
			geo.tri(first + tris[t], first + tris[t + 1], first + tris[t + 2])


func _revolve(geo: Geo, made: Dictionary) -> void:
	var pts := PackedVector2Array()
	for p in made["points"]:
		pts.append(Vector2(p[0], p[1]))
	var closed: bool = made.get("closed", false)
	var segments := int(made.get("segments", 24))
	var angle := deg_to_rad(float(made.get("angle", 360.0)))
	var full := angle >= TAU - 0.001
	var columns := segments if full else maxi(1, ceili(segments * angle / TAU))
	# The outline split at sharp corners, so a cone's rim stays sharp.
	var ring := pts.duplicate()
	if closed:
		ring.append(pts[0])
	var runs := [[ring[0]]]
	for i in range(1, ring.size()):
		runs[-1].append(ring[i])
		if i < ring.size() - 1:
			var into := (ring[i] - ring[i - 1]).normalized()
			var out := (ring[i + 1] - ring[i]).normalized()
			if rad_to_deg(acos(clampf(into.dot(out), -1.0, 1.0))) > SHARP:
				runs.append([ring[i]])
	var centre := Vector3.ZERO
	for p in pts:
		centre.y += p.y
	centre.y /= pts.size()
	for run in runs:
		if run.size() < 2:
			continue
		var rows := []
		for p: Vector2 in run:
			var row := PackedVector3Array()
			for j in columns + (0 if full else 1):
				var a := angle * j / columns
				row.append(Vector3(cos(a) * p.x, p.y, -sin(a) * p.x))
			rows.append(row)
		geo.grid(rows, full, true, centre)
	if not full:
		# Flat ends where a part-turn stops: the outline closed along the axis.
		var cap := pts.duplicate()
		if not closed:
			if cap[-1].x > 0.0001:
				cap.append(Vector2(0, cap[-1].y))
			if cap[0].x > 0.0001:
				cap.insert(0, Vector2(0, cap[0].y))
		var tris := _triangles(cap)
		for a in [0.0, angle]:
			var normal := Vector3(sin(a), 0, cos(a)) * (1.0 if a == 0.0 else -1.0)
			var first := geo.v.size()
			for p in cap:
				geo.add(Vector3(cos(a) * p.x, p.y, -sin(a) * p.x), normal, p)
			for t in range(0, tris.size(), 3):
				geo.tri(first + tris[t], first + tris[t + 1], first + tris[t + 2])


func _sweep(geo: Geo, made: Dictionary) -> void:
	var path := PackedVector3Array()
	for p in made["path"]:
		path.append(_v3(p))
	var closed: bool = made.get("closed", false)
	var sides := int(made.get("sides", 10))
	var r0: float = made["radius"]
	var r1 := float(made.get("radius_end", r0))
	var n := path.size()
	# Frames carried along the path without twisting.
	var tangents := PackedVector3Array()
	for i in n:
		var prev := path[i - 1] if i > 0 else (path[n - 1] if closed else path[i])
		var next := path[i + 1] if i < n - 1 else (path[0] if closed else path[i])
		tangents.append((next - prev).normalized())
	var t0 := tangents[0]
	var side := Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var normal := side.cross(t0).normalized()
	var rows := []
	var centre := Vector3.ZERO
	for p in path:
		centre += p
	centre /= n
	for i in n:
		var t := tangents[i]
		normal = (normal - t * t.dot(normal)).normalized()
		var binormal := t.cross(normal)
		var r := lerpf(r0, r1, float(i) / (n - 1))
		var row := PackedVector3Array()
		for k in sides:
			var a := TAU * k / sides
			row.append(path[i] + (normal * cos(a) + binormal * sin(a)) * r)
		rows.append(row)
	if closed:
		rows.append(rows[0])
	# Round tubes are smooth; a square or six-sided one keeps its edges.
	geo.tube(rows, sides > 6)
	if not closed:
		for end in [[0, -tangents[0]], [n - 1, tangents[n - 1]]]:
			var row: PackedVector3Array = rows[end[0]]
			var first := geo.v.size()
			geo.add(path[end[0]], end[1], Vector2(0.5, 0.5))
			for k in sides:
				var a := TAU * k / sides
				geo.add(row[k], end[1], Vector2(0.5 + cos(a) / 2, 0.5 + sin(a) / 2))
			for k in sides:
				geo.tri(first, first + 1 + k, first + 1 + (k + 1) % sides)


func _loft(geo: Geo, made: Dictionary) -> void:
	var sections: Array = made["sections"]
	var count := 0
	for section in sections:
		count = maxi(count, _outline(section["points"]).size())
	var rows := []
	var centre := Vector3.ZERO
	for section in sections:
		var pts := _resample(_outline(section["points"]), count)
		var s := float(section.get("scale", 1.0))
		var y := float(section["y"])
		var row := PackedVector3Array()
		for p in pts:
			row.append(Vector3(p.x * s, y, -p.y * s))
		rows.append(row)
		centre.y += y / sections.size()
	geo.grid(rows, true, made.get("smooth", true), centre)
	for end in [[0, Vector3.DOWN], [rows.size() - 1, Vector3.UP]]:
		var row: PackedVector3Array = rows[end[0]]
		var flat := PackedVector2Array()
		for p in row:
			flat.append(Vector2(p.x, -p.z))
		var tris := _triangles(flat)
		var first := geo.v.size()
		for p in row:
			geo.add(p, end[1], Vector2(p.x, p.z))
		for t in range(0, tris.size(), 3):
			geo.tri(first + tris[t], first + tris[t + 1], first + tris[t + 2])


# An outline evened out to count points, spaced along its length, starting
# from the one nearest straight right of its middle so sections line up.
func _resample(pts: PackedVector2Array, count: int) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var start := 0
	var best := INF
	for i in pts.size():
		var a := absf((pts[i] - c).angle())
		if a < best:
			best = a
			start = i
	var ordered := PackedVector2Array()
	for i in pts.size():
		ordered.append(pts[(start + i) % pts.size()])
	if ordered.size() == count:
		return ordered
	var lengths := [0.0]
	for i in ordered.size():
		lengths.append(lengths[-1] + ordered[i].distance_to(ordered[(i + 1) % ordered.size()]))
	var total: float = lengths[-1]
	var out := PackedVector2Array()
	var seg := 0
	for k in count:
		var at := total * k / count
		while seg < ordered.size() - 1 and lengths[seg + 1] < at:
			seg += 1
		var span: float = lengths[seg + 1] - lengths[seg]
		var t: float = 0.0 if span <= 0.0 else (at - lengths[seg]) / span
		out.append(ordered[seg].lerp(ordered[(seg + 1) % ordered.size()], t))
	return out


func _surface(geo: Geo, made: Dictionary) -> void:
	var rows := []
	if made.has("heights"):
		var heights: Array = made["heights"]
		var size: Array = made["size"]
		var nz := heights.size()
		var nx: int = heights[0].size()
		for j in nz:
			var row := PackedVector3Array()
			for i in nx:
				row.append(Vector3((float(i) / (nx - 1) - 0.5) * size[0], float(heights[j][i]), (float(j) / (nz - 1) - 0.5) * size[1]))
			rows.append(row)
	else:
		for source in made["points"]:
			var row := PackedVector3Array()
			for p in source:
				row.append(_v3(p))
			rows.append(row)
	var thickness := float(made.get("thickness", 0.0))
	var smooth: bool = made.get("smooth", true)
	var top := geo.sheet(rows, smooth)
	if thickness <= 0.0:
		return
	# A slab: the same sheet moved back along its normals, and the edges joined.
	var bottom := []
	for j in rows.size():
		var row := PackedVector3Array()
		for i in rows[j].size():
			row.append(rows[j][i] - top[j][i] * thickness)
		bottom.append(row)
	geo.sheet(bottom, smooth, true)
	var nz := rows.size()
	var nx: int = rows[0].size()
	var edge := []
	for i in nx:
		edge.append(Vector2i(i, 0))
	for j in range(1, nz):
		edge.append(Vector2i(nx - 1, j))
	for i in range(nx - 2, -1, -1):
		edge.append(Vector2i(i, nz - 1))
	for j in range(nz - 2, 0, -1):
		edge.append(Vector2i(0, j))
	var middle := Vector3.ZERO
	for row in rows:
		for p in row:
			middle += p
	middle /= nz * nx
	for k in edge.size():
		var e: Vector2i = edge[k]
		var f: Vector2i = edge[(k + 1) % edge.size()]
		var a: Vector3 = rows[e.y][e.x]
		var b: Vector3 = rows[f.y][f.x]
		var a2: Vector3 = bottom[e.y][e.x]
		var b2: Vector3 = bottom[f.y][f.x]
		var out := (a + b) / 2.0 - middle
		geo.quad(a, b, b2, a2, out, [Vector2(0, 0), Vector2(a.distance_to(b), 0), Vector2(a.distance_to(b), thickness), Vector2(0, thickness)])


func _vertex_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var count := 0
	if mesh is ArrayMesh:
		for s in mesh.get_surface_count():
			count += (mesh as ArrayMesh).surface_get_array_len(s)
	else:
		for s in mesh.get_surface_count():
			count += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return count


# Vertices, normals, texture coordinates and triangles, wound the way the
# engine draws them (its front faces are clockwise).
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(p: Vector3, normal: Vector3, t: Vector2) -> int:
		v.append(p)
		n.append(normal)
		uv.append(t)
		return v.size() - 1

	# A triangle facing the way its vertices' normals point.
	func tri(a: int, b: int, c: int) -> void:
		var face := (v[b] - v[a]).cross(v[c] - v[a])
		if face.length_squared() < 1e-14:
			return
		if face.dot(n[a] + n[b] + n[c]) >= 0.0:
			idx.append_array([a, c, b])
		else:
			idx.append_array([a, b, c])

	# A flat four-sided face, facing out.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, t: Array) -> void:
		var normal := (c - a).cross(d - b)
		if normal.length_squared() < 1e-14:
			normal = (b - a).cross(c - a)
		if normal.dot(out) < 0.0:
			normal = -normal
		normal = normal.normalized()
		var first := add(a, normal, t[0])
		add(b, normal, t[1])
		add(c, normal, t[2])
		add(d, normal, t[3])
		tri(first, first + 1, first + 2)
		tri(first, first + 2, first + 3)

	# Rows of points joined into a skin, smooth or flat. wrap: each row is a
	# loop. Faces point away from centre.
	func grid(rows: Array, wrap: bool, smooth: bool, centre: Vector3) -> void:
		var normals := _normals(rows, wrap)
		# Turned round if most of it faces in.
		var facing := 0.0
		for j in rows.size():
			for i in rows[j].size():
				facing += normals[j][i].dot(rows[j][i] - centre)
		_skin(rows, normals, wrap, smooth, -1.0 if facing < 0.0 else 1.0)

	# A tube's rows (each a loop; the last row may repeat the first).
	func tube(rows: Array, smooth: bool) -> void:
		var normals := []
		for j in rows.size():
			var mid := Vector3.ZERO
			for p in rows[j]:
				mid += p
			mid /= rows[j].size()
			var row := PackedVector3Array()
			for p in rows[j]:
				row.append((p - mid).normalized())
			normals.append(row)
		_skin(rows, normals, true, smooth, 1.0)

	# An open sheet facing up (or down); returns its normals, row by row.
	func sheet(rows: Array, smooth: bool, down := false) -> Array:
		var normals := _normals(rows, false)
		var facing := 0.0
		for row in normals:
			for normal in row:
				facing += normal.y
		var sign := 1.0 if facing >= 0.0 else -1.0
		var out := []
		for row in normals:
			var flipped := PackedVector3Array()
			for normal in row:
				flipped.append(normal * sign)
			out.append(flipped)
		_skin(rows, normals, false, smooth, -sign if down else sign)
		return out

	func _normals(rows: Array, wrap: bool) -> Array:
		var normals := []
		var nz := rows.size()
		var nx: int = rows[0].size()
		for j in nz:
			var row := PackedVector3Array()
			row.resize(nx)
			normals.append(row)
		var cells := nx if wrap else nx - 1
		for j in nz - 1:
			for i in cells:
				var i2 := (i + 1) % nx
				var a: Vector3 = rows[j][i]
				var b: Vector3 = rows[j][i2]
				var c: Vector3 = rows[j + 1][i2]
				var d: Vector3 = rows[j + 1][i]
				var face := (c - a).cross(d - b)
				for at in [[j, i], [j, i2], [j + 1, i2], [j + 1, i]]:
					normals[at[0]][at[1]] += face
		for row in normals:
			for i in row.size():
				row[i] = row[i].normalized() if row[i].length_squared() > 1e-20 else Vector3.UP
		return normals

	func _skin(rows: Array, normals: Array, wrap: bool, smooth: bool, sign: float) -> void:
		var nz := rows.size()
		var nx: int = rows[0].size()
		var cells := nx if wrap else nx - 1
		if not smooth:
			for j in nz - 1:
				for i in cells:
					var i2 := (i + 1) % nx
					var a: Vector3 = rows[j][i]
					var b: Vector3 = rows[j][i2]
					var c: Vector3 = rows[j + 1][i2]
					var d: Vector3 = rows[j + 1][i]
					var out: Vector3 = (normals[j][i] + normals[j][i2] + normals[j + 1][i] + normals[j + 1][i2]) * sign
					quad(a, b, c, d, out, [Vector2(float(i) / cells, float(j) / (nz - 1)), Vector2(float(i + 1) / cells, float(j) / (nz - 1)),
						Vector2(float(i + 1) / cells, float(j + 1) / (nz - 1)), Vector2(float(i) / cells, float(j + 1) / (nz - 1))])
			return
		# The loop's seam gets its own copy of the first column, for the texture.
		var columns := nx + (1 if wrap else 0)
		var first := v.size()
		for j in nz:
			for i in columns:
				add(rows[j][i % nx], normals[j][i % nx] * sign, Vector2(float(i) / (columns - 1), float(j) / (nz - 1)))
		for j in nz - 1:
			for i in columns - 1:
				var a := first + j * columns + i
				var b := a + 1
				var c := a + columns + 1
				var d := a + columns
				tri(a, b, c)
				tri(a, c, d)

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = idx
		var out := ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return out


# --- Helpers -------------------------------------------------------------------------

func _node(node_name: String) -> MeshInstance3D:
	if node_name.is_empty() or node_name.validate_node_name() != node_name:
		return null
	return (ctx["world"] as Node3D).get_node_or_null(NodePath(node_name)) as MeshInstance3D


func _free_name(base: String) -> String:
	var world: Node3D = ctx["world"]
	var n := 1
	while world.has_node(NodePath("%s%d" % [base, n])):
		n += 1
	return "%s%d" % [base, n]


func _undo(label: String, undo: Callable, redo: Callable) -> void:
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools:
		tools.call("push_undo", "shapes: " + label, undo, redo)


# Runs then(reply) when pending finishes (now, if it already has).
func _when(pending: SlopitectPending, then: Callable) -> void:
	if pending.finished:
		then.call(pending.result)
	else:
		pending.done.connect(then, CONNECT_ONE_SHOT)


func _aim_ground():
	var hand: Node3D = ctx["right"]
	var from := hand.global_position
	var along := -hand.global_basis.z
	var landscape: SlopitectModule = ctx["modules"].module("landscape")
	var t := 0.0
	while t < RAY_LENGTH:
		t += RAY_STEP
		var p := from + along * t
		var ground: float = landscape.call("height_at", p.x, p.z) if landscape else 0.0
		if p.y <= ground:
			return Vector3(p.x, ground, p.z)
	return null


func _in_front() -> Vector3:
	var camera: Node3D = ctx["camera"]
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	return camera.global_position + forward * PLACE_DISTANCE + Vector3(0, -0.3, 0)


# The turn (degrees) that makes a shape's front (+z) face you.
func _facing_yaw() -> float:
	var back: Vector3 = (ctx["camera"] as Node3D).global_basis.z
	return snappedf(rad_to_deg(atan2(back.x, back.z)), 0.1)


func _basis_up(normal: Vector3) -> Basis:
	var y := normal.normalized()
	var x := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.BACK
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	return Basis(x, y, z)


func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	return material


func _v3(p) -> Vector3:
	return Vector3(p[0], p[1], p[2])


func _vec_in(value, key: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return {"error": "\"%s\" must be [x, y, z], got %s" % [key, JSON.stringify(value)]}
	for v in value:
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return {"error": "\"%s\" must be three numbers, got %s" % [key, JSON.stringify(value)]}
		if is_nan(float(v)) or is_inf(float(v)) or absf(float(v)) > 10000.0:
			return {"error": "\"%s\" values must be between -10000 and 10000, got %s" % [key, JSON.stringify(value)]}
	return {"vec": Vector3(value[0], value[1], value[2])}


func _vec_out(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


func _transform_out(t: Transform3D) -> Array:
	var out := []
	for v in [t.basis.x, t.basis.y, t.basis.z, t.origin]:
		out.append_array([snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)])
	return out


func _transform_in(value):
	if typeof(value) != TYPE_ARRAY or value.size() != 12:
		return null
	for v in value:
		if typeof(v) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(v)) or absf(float(v)) > 10000.0:
			return null
	var t := Transform3D(Basis(Vector3(value[0], value[1], value[2]), Vector3(value[3], value[4], value[5]), Vector3(value[6], value[7], value[8])),
		Vector3(value[9], value[10], value[11]))
	if absf(t.basis.determinant()) < 1e-9:
		return null
	return t


func _color_in(value) -> Dictionary:
	if typeof(value) != TYPE_STRING:
		return {"error": "\"color\" must be a string like \"#ff8800\" or \"red\", got %s" % JSON.stringify(value)}
	if Color.html_is_valid(value):
		return {"color": Color.html(value)}
	var named := Color.from_string(value, Color(-1, -1, -1))
	if named.r < 0.0:
		return {"error": "unknown color \"%s\" (use \"#rrggbb\" or a name like \"red\")" % value}
	return {"color": named}
