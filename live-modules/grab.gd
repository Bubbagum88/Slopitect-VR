extends SlopitectModule

# Slopitect live module: grab.
# Hold the grip near a shape or a placed model to pick it up; it follows the
# hand until you let go. With the physics module loaded, a dynamic thing
# you let go of flies on with the hand's speed (a throw). Each pick-up is
# one undo in the tools window (if the tools module is loaded). The grips
# are the controls module's "grab_left" and "grab_right" actions; pointing
# at a panel, the right grip moves the panel instead (the ui module is
# asked first).
# A thing in a group (multi.gd) brings its group along, and the undo puts
# the whole group back.
# Grip a held thing with the other hand too and pull your hands apart or
# together to make it bigger or smaller; it keeps its shape. Letting go
# with either hand leaves it in the other. The whole hold, moves and resizes,
# is one undo.
# It runs each physics frame only while a hand holds something (the hand
# speed for a throw is taken while held). Shapes and models are lib's.

const REACH := 0.12  # metres from the hand to the thing's box
const SPEED_FRAMES := 6  # hand speed is taken over this many frames
const SMALLEST := 0.02  # metres: a resized thing's longest side stays at least this
const BIGGEST := 20.0  # and at most this

var _held := {}  # hand name -> {"node", "offset": Transform3D, "before": {name: Transform3D} of it and its group}
# While both hands hold one thing: {"node", "hand": the one it follows,
# "distance": between the hands when the second took it, "scale": its scale
# then, "longest": its longest side then, "from_middle": where it was from
# the point between the hands, in that hand's own directions}
var _resize := {}
var _trail := {"left": [], "right": []}  # recent [time, position] of each hand
var _lib: SlopitectModule


func setup() -> String:
	set_physics_process(false)
	register("grab_status", _status, "what each hand is holding")
	register("grab_release", _release_command, "make a hand let go: hand (left or right; default both)")
	return ""


func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		for hand in _held.keys():
			_let_go(hand)


func _exit_tree() -> void:
	for hand in _held.keys():
		_let_go(hand)


# For multi.gd: what the hands hold now, so a group follows the held one.
func held() -> Array:
	var out := []
	for hand in _held:
		if is_instance_valid(_held[hand]["node"]):
			out.append(_held[hand]["node"])
	return out


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for hand in ["left", "right"]:
		var trail: Array = _trail[hand]
		trail.append([now, (ctx[hand] as Node3D).global_position])
		if trail.size() > SPEED_FRAMES:
			trail.pop_front()
	for hand in _held.keys():
		var held: Dictionary = _held[hand]
		if not is_instance_valid(held["node"]) or not (held["node"] as Node3D).is_inside_tree():
			_held.erase(hand)  # deleted while held
			_resize.clear()
			continue
		if not _resize.is_empty() and _resize["node"] == held["node"]:
			if hand == _resize["hand"]:
				_follow_both()
			continue
		(held["node"] as Node3D).global_transform = (ctx[hand] as Node3D).global_transform * held["offset"]
	if _held.is_empty():
		set_physics_process(false)


# Both hands on one thing: it moves and turns with the hand that took it
# first, and its size goes with how far apart the hands are, growing or
# shrinking about the point between them (where it was from that point
# turns with the hand and scales with the size).
func _follow_both() -> void:
	var node: Node3D = _resize["node"]
	var hand: String = _resize["hand"]
	var left: Vector3 = (ctx["left"] as Node3D).global_position
	var right: Vector3 = (ctx["right"] as Node3D).global_position
	var factor: float = left.distance_to(right) / _resize["distance"]
	factor = clampf(factor, SMALLEST / _resize["longest"], BIGGEST / _resize["longest"])
	var turn: Basis = (ctx[hand] as Node3D).global_basis.orthonormalized()
	var follow: Transform3D = (ctx[hand] as Node3D).global_transform * _held[hand]["offset"]
	var start_scale: Vector3 = _resize["scale"]
	var from_middle: Vector3 = _resize["from_middle"]
	node.global_transform = Transform3D(follow.basis.orthonormalized() * Basis.from_scale(start_scale * factor),
		(left + right) / 2.0 + turn * from_middle * factor)


# --- Picking up ----------------------------------------------------------------------

func action_order() -> int:
	return 20


func on_action(action: String, down: bool) -> bool:
	if not action in ["grab_left", "grab_right"]:
		return false
	var hand := action.trim_prefix("grab_")
	if not down:
		_let_go(hand)
		return true
	return _grip(hand)


# Picks up the nearest thing in reach; whether there was one.
func _grip(hand: String) -> bool:
	var at: Vector3 = (ctx[hand] as Node3D).global_position
	var best: Node3D = null
	var best_distance := REACH
	for thing in _grabbable():
		if _held.has(hand) and _held[hand]["node"] == thing:
			continue
		if not thing.is_visible_in_tree() or thing.get_meta("slopitect_no_grab", false):
			continue  # hidden, or made ungrabbable with the inspect tool
		var distance := _distance_to(thing, at)
		if distance <= best_distance:
			best = thing
			best_distance = distance
	if best == null:
		return false
	var other := "right" if hand == "left" else "left"
	if _held.has(other) and _held[other]["node"] == best:
		_start_resize(hand, other, best)
		return true
	_held[hand] = {"node": best, "offset": (ctx[hand] as Node3D).global_transform.affine_inverse() * best.global_transform,
		"before": _where(_moving_with(best))}
	_trail[hand].clear()
	set_physics_process(true)
	var physics: SlopitectModule = ctx["modules"].module("physics")
	if physics:
		physics.call("hold", best, true)
	(ctx[hand] as XRController3D).trigger_haptic_pulse("haptic", 0.0, 0.3, 0.05, 0.0)
	print("Slopitect grab: %s hand took %s" % [hand, best.name])
	return true


# The second hand on a held thing: from now on its size follows the hands.
func _start_resize(hand: String, other: String, node: Node3D) -> void:
	var distance := (ctx["left"] as Node3D).global_position.distance_to((ctx["right"] as Node3D).global_position)
	var box := _box(node)
	var longest := maxf(box.size[box.get_longest_axis_index()], 0.001)
	_held[hand] = {"node": node, "offset": (ctx[hand] as Node3D).global_transform.affine_inverse() * node.global_transform,
		"before": _held[other]["before"]}
	var middle := ((ctx["left"] as Node3D).global_position + (ctx["right"] as Node3D).global_position) / 2.0
	var from_middle: Vector3 = (ctx[other] as Node3D).global_basis.orthonormalized().inverse() * (node.global_position - middle)
	_resize = {"node": node, "hand": other, "distance": maxf(distance, 0.01), "scale": node.scale, "longest": longest,
		"from_middle": from_middle}
	(ctx[hand] as XRController3D).trigger_haptic_pulse("haptic", 0.0, 0.3, 0.05, 0.0)
	print("Slopitect grab: %s hand took %s too; pull apart or together to resize" % [hand, node.name])


func _let_go(hand: String) -> void:
	if not _held.has(hand):
		return
	var held: Dictionary = _held[hand]
	_held.erase(hand)
	var node: Node3D = held["node"]
	if not is_instance_valid(node):
		_resize.clear()
		return
	var other := "right" if hand == "left" else "left"
	if _held.has(other) and _held[other]["node"] == node:
		# Still in the other hand: it keeps the size it has now and follows
		# that hand alone.
		_resize.clear()
		_held[other]["offset"] = (ctx[other] as Node3D).global_transform.affine_inverse() * node.global_transform
		print("Slopitect grab: %s hand let go of %s; the %s hand still has it" % [hand, node.name, other])
		return
	var physics: SlopitectModule = ctx["modules"].module("physics")
	if physics:
		physics.call("hold", node, false)
		physics.call("throw", node, _hand_speed(hand))
	var before: Dictionary = held["before"]
	var after := _where(before.keys())
	var tools: SlopitectModule = ctx["modules"].module("tools")
	var node_name := String(node.name)
	if tools and before.has(node_name) and after.has(node_name) and not (before[node_name] as Transform3D).is_equal_approx(after[node_name]):
		var put := func(where: Dictionary):
			for n in where:
				var thing := _thing(n)
				if thing:
					thing.global_transform = where[n]
		var same_size := (before[node_name] as Transform3D).basis.get_scale().is_equal_approx((after[node_name] as Transform3D).basis.get_scale())
		var what := "move" if same_size else "resize"
		var label := "%s %s" % [what, node_name] if before.size() == 1 else "%s %s's group" % [what, node_name]
		tools.call("push_undo", label, put.bind(before), put.bind(after))
	print("Slopitect grab: %s hand let go of %s" % [hand, node.name])


func _hand_speed(hand: String) -> Vector3:
	var trail: Array = _trail[hand]
	if trail.size() < 2 or trail[-1][0] - trail[0][0] <= 0.0:
		return Vector3.ZERO
	return (trail[-1][1] - trail[0][1]) / (trail[-1][0] - trail[0][0])


# The shapes and placed models (lib's; none without it).
func _grabbable() -> Array:
	return _lib.things() if _lib else []


func _thing(node_name: String) -> Node3D:
	return _lib.thing(node_name) if _lib else null


# The names that move with node: its group in multi.gd, or just itself.
func _moving_with(node: Node3D) -> Array:
	var multi: SlopitectModule = ctx["modules"].module("multi")
	return multi.call("members", String(node.name)) if multi else [String(node.name)]


# name -> where it is now, for those that exist.
func _where(names: Array) -> Dictionary:
	var out := {}
	for n in names:
		var thing := _thing(n)
		if thing:
			out[n] = thing.global_transform
	return out


# From a point to the thing's box (0 inside it), in world space.
func _distance_to(thing: Node3D, at: Vector3) -> float:
	var box := _box(thing)
	if box.size == Vector3.ZERO:
		return thing.global_position.distance_to(at)
	var closest := at.clamp(box.position, box.end)
	return closest.distance_to(at)


func _box(thing: Node3D) -> AABB:
	return _lib.world_box(thing)


func _status(_request: Dictionary) -> Dictionary:
	var holding := {}
	for hand in _held:
		holding[hand] = String(_held[hand]["node"].name) if is_instance_valid(_held[hand]["node"]) else ""
	var resizing: String = String(_resize["node"].name) if not _resize.is_empty() and is_instance_valid(_resize["node"]) else ""
	return {"ok": true, "holding": holding, "resizing": resizing}


func _release_command(request: Dictionary) -> Dictionary:
	var hand = request.get("hand", "")
	if not hand in ["", "left", "right"]:
		return {"ok": false, "error": "\"hand\" must be left or right (or leave it out for both)"}
	for each in ["left", "right"]:
		if hand == "" or hand == each:
			_let_go(each)
	return _status({})
