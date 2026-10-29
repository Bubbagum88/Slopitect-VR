extends SlopitectModule

# Slopitect live module: grab.
# Hold the grip near a shape or a placed model to pick it up; it follows the
# hand until you let go. With the physics module loaded, a dynamic thing
# you let go of flies on with the hand's speed (a throw). Each pick-up is
# one undo in the tools window (if the tools module is loaded). The right
# grip still drags a panel when you point at one.

const REACH := 0.12  # metres from the hand to the thing's box
const UI_LAYER := 1 << 19  # the ui module's panels
const SPEED_FRAMES := 6  # hand speed is taken over this many frames

var _ray: RayCast3D
var _held := {}  # hand name -> {"node", "offset": Transform3D, "before": Transform3D}
var _trail := {"left": [], "right": []}  # recent [time, position] of each hand


func setup() -> String:
	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -3.0)
	_ray.collision_mask = UI_LAYER
	ctx["right"].add_child(_ray)
	for hand in ["left", "right"]:
		ctx[hand].button_pressed.connect(func(button): if button == "grip_click": _grip(hand, true))
		ctx[hand].button_released.connect(func(button): if button == "grip_click": _grip(hand, false))
	register("grab_status", _status, "what each hand is holding")
	register("grab_release", _release_command, "make a hand let go: hand (left or right; default both)")
	return ""


func _exit_tree() -> void:
	for hand in _held.keys():
		_let_go(hand)
	if _ray and is_instance_valid(_ray):
		_ray.queue_free()


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
			continue
		(held["node"] as Node3D).global_transform = (ctx[hand] as Node3D).global_transform * held["offset"]


# --- Picking up ----------------------------------------------------------------------

func _grip(hand: String, down: bool) -> void:
	if not down:
		_let_go(hand)
		return
	if hand == "right" and _ray.is_colliding() and (_ray.get_collider() as Node3D).is_visible_in_tree():
		return  # that grip drags the panel
	var at: Vector3 = (ctx[hand] as Node3D).global_position
	var best: Node3D = null
	var best_distance := REACH
	for thing in _grabbable():
		if _held.values().any(func(h): return h["node"] == thing):
			continue
		var distance := _distance_to(thing, at)
		if distance <= best_distance:
			best = thing
			best_distance = distance
	if best == null:
		return
	_held[hand] = {"node": best, "offset": (ctx[hand] as Node3D).global_transform.affine_inverse() * best.global_transform,
		"before": best.global_transform}
	var physics: SlopitectModule = ctx["modules"].module("physics")
	if physics:
		physics.call("hold", best, true)
	(ctx[hand] as XRController3D).trigger_haptic_pulse("haptic", 0.0, 0.3, 0.05, 0.0)
	print("Slopitect grab: %s hand took %s" % [hand, best.name])


func _let_go(hand: String) -> void:
	if not _held.has(hand):
		return
	var held: Dictionary = _held[hand]
	_held.erase(hand)
	var node: Node3D = held["node"]
	if not is_instance_valid(node):
		return
	var physics: SlopitectModule = ctx["modules"].module("physics")
	if physics:
		physics.call("hold", node, false)
		physics.call("throw", node, _hand_speed(hand))
	var before: Transform3D = held["before"]
	var after := node.global_transform
	var tools: SlopitectModule = ctx["modules"].module("tools")
	if tools and not before.is_equal_approx(after):
		var put := func(t: Transform3D): if is_instance_valid(node): node.global_transform = t
		tools.call("push_undo", "move %s" % node.name, put.bind(before), put.bind(after))
	print("Slopitect grab: %s hand let go of %s" % [hand, node.name])


func _hand_speed(hand: String) -> Vector3:
	var trail: Array = _trail[hand]
	if trail.size() < 2 or trail[-1][0] - trail[0][0] <= 0.0:
		return Vector3.ZERO
	return (trail[-1][1] - trail[0][1]) / (trail[-1][0] - trail[0][0])


# The shapes (the objects module's, under World) and placed models (under
# World/PolyHaven, from the assets module).
func _grabbable() -> Array:
	var found := []
	var world: Node3D = ctx["world"]
	for child in world.get_children():
		if child is MeshInstance3D:
			found.append(child)
		elif child.name == "PolyHaven":
			found.append_array(child.get_children())
	return found


# From a point to the thing's box (0 inside it), in world space.
func _distance_to(thing: Node3D, at: Vector3) -> float:
	var box := _box(thing)
	if box.size == Vector3.ZERO:
		return thing.global_position.distance_to(at)
	var closest := at.clamp(box.position, box.end)
	return closest.distance_to(at)


func _box(thing: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array = [thing] if thing is MeshInstance3D else thing.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		var world_box := mesh.global_transform * mesh.get_aabb()
		box = world_box if first else box.merge(world_box)
		first = false
	return box


func _status(_request: Dictionary) -> Dictionary:
	var holding := {}
	for hand in _held:
		holding[hand] = String(_held[hand]["node"].name) if is_instance_valid(_held[hand]["node"]) else ""
	return {"ok": true, "holding": holding}


func _release_command(request: Dictionary) -> Dictionary:
	var hand = request.get("hand", "")
	if not hand in ["", "left", "right"]:
		return {"ok": false, "error": "\"hand\" must be left or right (or leave it out for both)"}
	for each in ["left", "right"]:
		if hand == "" or hand == each:
			_let_go(each)
	return _status({})
