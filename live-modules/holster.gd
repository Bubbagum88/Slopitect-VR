extends SlopitectModule

# Slopitect live module: holster.
# Put the avatar away at your hip and pull it back out.
# - Point a hand at the avatar (or reach it) and squeeze the grip: it flies
#   to that hand and stays there while you hold the grip.
# - Let go with the hand at your hip (a ring shows each hip while you hold
#   it, and lights when you're there): it's stowed there, small, and goes
#   where you go.
# - Reach your hip and grip it to take it back. Flick the hand as you let
#   go and it flies out to a spot around you in the flick's direction:
#   further for a harder flick, higher or lower if you flick up or down.
#   It stays at that spot from you as you walk and turn with the
#   thumbstick (not as you turn your head, so it doesn't swing about).
# - Let go slowly anywhere else and it stays right there in the world.
# The hand menu has an Avatar button that stows it, or brings it out to
# the last spot it was flicked to. avatar_move (the agent's) still works:
# the avatar then stays where it was put.
# The grips are the controls module's "grab_left" and "grab_right"; this
# module is asked after the windows (vrui's right grip drags a panel you
# point at) and before grab.gd, and takes the grip only when the hand
# points at or reaches the avatar.

const AIM_RANGE := 8.0  # metres along the hand's pointing line
const AIM_RADIUS := 0.2  # how close the line passes to a full-size avatar
const REACH := 0.18  # metres from the hand to a full-size avatar's middle
const HIP_REACH := 0.22  # from the hand to a hip, to stow or take it
const HIP_SIDE := 0.2  # hips: this far to the side of your head,
const HIP_DOWN := 0.6  # this far below it,
const HIP_FORWARD := 0.05  # and this far forward
const HELD_SCALE := 0.5
const HOLSTER_SCALE := 0.3
const HELD_FORWARD := 0.1  # metres in front of the hand it's held
const PULL_SECONDS := 0.2  # to fly to the hand
const FLY_SECONDS := 0.45  # to fly out (or to the hip)
const FLICK_SPEED := 1.3  # metres a second: slower is a plain let go
const NEAREST := 0.7  # how far out a flick sends it, in metres
const FURTHEST := 2.5
const DISTANCE_PER_SPEED := 0.6  # metres further per metre a second of flick
const HIGHEST := 0.5  # from your head height
const LOWEST := -0.9
const FOLLOW_SPEED := 3.0
const SPEED_FRAMES := 6
const DEFAULT_OUT := Vector3(-0.6, -0.3, -1.0)  # front left, a little low

# "free": left in the world; "held": in a hand; "holstered": at a hip;
# "out": at a spot around you.
var _mode := "free"
var _hand := ""  # the hand holding it
var _side := "right"  # the hip it's at, or was last at
var _out := DEFAULT_OUT  # where "out" is, in the play area's directions from your head
var _fly := {}  # {"from": Vector3, "t": 0..1, "seconds", "scale_from"}: on its way to where it goes
var _scale := 1.0
var _placed := Vector3.INF  # where this module last put it, to notice avatar_move
var _aimed := {"left": false, "right": false}
var _trail := {"left": [], "right": []}  # recent [time, position in the play area] of each hand
var _rings := {}  # side -> MeshInstance3D at that hip, shown while it's held
var _at_hip := ""  # the hip the holding hand is at


func setup() -> String:
	register("holster_status", _status, "where the avatar is: free, held, holstered (at a hip) or out (around you)")
	register("holster_stow", _stow_command, "put the avatar away at a hip: side (left or right; default the last one)")
	register("holster_summon", _summon_command, "bring the avatar out to its spot around you, or to direction [x, y, z] (metres from your head: x right, y up, z back)")
	register("holster_toggle", _toggle_command, "stow the avatar, or bring it out if it's stowed")
	for side in ["left", "right"]:
		_rings[side] = _make_ring()
	set_process(false)  # on while there's an avatar to hold
	return ""


var _lib: SlopitectModule
var _avatar_module: SlopitectModule  # the avatar while it's loaded


func lib_ready(lib) -> void:
	_lib = lib
	if lib:
		lib.watch(self, "avatar", _avatar_here, _avatar_gone)


func _avatar_here(avatar: SlopitectModule) -> void:
	_avatar_module = avatar if avatar.has_method("root") else null
	set_process(_avatar_module != null)


func _avatar_gone(_old: SlopitectModule) -> void:
	_avatar_module = null
	_mode = "free"
	_show_rings(false)
	set_process(false)


func _exit_tree() -> void:
	var root := _root()
	if root:
		root.scale = Vector3.ONE


func hand_info() -> Dictionary:
	return {"id": "holster", "label": "Avatar", "order": 30, "action": {"cmd": "holster_toggle"}}


# --- Each frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for hand in ["left", "right"]:
		var trail: Array = _trail[hand]
		# In the play area, so walking with the thumbstick isn't a flick.
		trail.append([now, _origin().to_local((ctx[hand] as Node3D).global_position)])
		if trail.size() > SPEED_FRAMES:
			trail.pop_front()
	var root := _root()
	if root == null:
		_mode = "free"
		_show_rings(false)
		return
	if _mode in ["holstered", "out"] and _placed != Vector3.INF and root.global_position.distance_to(_placed) > 0.05:
		_set_free(root)  # someone else moved it (avatar_move)
	_tick_aim(root)

	var target := root.global_position
	var scale_to := 1.0
	var speed := 0.0  # 0 sets it right on target
	match _mode:
		"held":
			var hand := ctx[_hand] as Node3D
			target = hand.global_position - hand.global_basis.z * HELD_FORWARD
			scale_to = HELD_SCALE
			_tick_hips(hand.global_position)
		"holstered":
			target = _hip(_side)
			scale_to = HOLSTER_SCALE
		"out":
			target = _out_spot()
			speed = FOLLOW_SPEED
		_:
			_show_rings(false)
			if _fly.is_empty() and is_equal_approx(_scale, 1.0):
				return
	if not _fly.is_empty():
		_fly["t"] = minf(_fly["t"] + delta / _fly["seconds"], 1.0)
		var t: float = smoothstep(0.0, 1.0, _fly["t"])
		root.global_position = (_fly["from"] as Vector3).lerp(target, t)
		_scale = lerpf(_fly["scale_from"], scale_to, t)
		if _fly["t"] >= 1.0:
			_fly = {}
	elif speed > 0.0:
		root.global_position = root.global_position.lerp(target, clampf(delta * speed, 0.0, 1.0))
		_scale = scale_to
	else:
		root.global_position = target
		_scale = scale_to
	root.scale = Vector3.ONE * _scale
	_placed = root.global_position


# A light buzz when a hand starts pointing at the avatar, so you know a grip
# will take it.
func _tick_aim(root: Node3D) -> void:
	for hand in ["left", "right"]:
		var aimed := _mode != "held" and _can_take(hand, root)
		if aimed and not _aimed[hand]:
			_pulse(hand, 0.15, 0.03)
		_aimed[hand] = aimed


func _tick_hips(at: Vector3) -> void:
	var near := _hip_near(at)
	if near != _at_hip and not near.is_empty():
		_pulse(_hand, 0.4, 0.05)
	_at_hip = near
	for side in _rings:
		var ring: MeshInstance3D = _rings[side]
		ring.visible = true
		ring.global_transform = Transform3D(_flat_basis(), _hip(side))
		(ring.material_override as StandardMaterial3D).albedo_color = Color(0.3, 0.9, 0.5, 0.85) if side == near else Color(1, 1, 1, 0.35)


# --- Grips ---------------------------------------------------------------------------

func action_order() -> int:
	return 15  # after vrui (0) drags windows, before grab (20) picks up shapes


func on_action(action: String, down: bool) -> bool:
	if not action in ["grab_left", "grab_right"]:
		return false
	var hand := action.trim_prefix("grab_")
	if not down:
		if _mode == "held" and _hand == hand:
			_let_go(_hand_speed(hand))
		return true
	var root := _root()
	if root == null or (_mode == "held" and _hand != hand and not _can_take(hand, root)):
		return false
	if _mode != "held" and not _can_take(hand, root):
		return false
	_take(hand, root)
	return true


# Whether the hand reaches the avatar or points at it (a stowed one only by
# reaching your hip).
func _can_take(hand: String, root: Node3D) -> bool:
	var controller := ctx[hand] as Node3D
	var at := controller.global_position
	var middle := _middle(root)
	if _mode == "holstered":
		return at.distance_to(_hip(_side)) <= HIP_REACH
	if at.distance_to(middle) <= REACH * maxf(_scale, 0.5):
		return true
	var along := -controller.global_basis.z.normalized()
	var ahead := (middle - at).dot(along)
	if ahead <= 0.0 or ahead > AIM_RANGE:
		return false
	return (at + along * ahead).distance_to(middle) <= AIM_RADIUS * maxf(_scale, 0.5)


func _take(hand: String, root: Node3D) -> void:
	_mode = "held"
	_hand = hand
	_at_hip = ""
	_fly = {"from": root.global_position, "t": 0.0, "seconds": PULL_SECONDS, "scale_from": _scale}
	_pulse(hand, 0.3, 0.05)
	print("Slopitect holster: %s hand took the avatar" % hand)


# Let go with the hand moving at this speed: at a hip it's stowed; flicked,
# it flies out that way; otherwise it stays where it is.
func _let_go(velocity: Vector3) -> void:
	var root := _root()
	_show_rings(false)
	if root == null:
		_mode = "free"
		return
	var at := (ctx[_hand] as Node3D).global_position
	var hip := _hip_near(at)
	if not hip.is_empty():
		_stow(hip)
	elif velocity.length() >= FLICK_SPEED:
		_out = _flick_spot(velocity)
		_send_out()
	else:
		_set_free(root)
		_fly = {"from": root.global_position, "t": 0.0, "seconds": PULL_SECONDS, "scale_from": _scale}
		print("Slopitect holster: the avatar was put down")
	_hand = ""


# Where a flick sends it: the flick's direction across the floor, further
# for a faster flick; its up or down part raises or lowers it. The flick
# and the spot are in the play area's directions, from your head.
func _flick_spot(velocity: Vector3) -> Vector3:
	var direction := velocity.normalized()
	var across := Vector3(direction.x, 0.0, direction.z)
	if across.length() < 0.3:
		# Flicked straight up or down: in front of you.
		across = _origin().global_basis.orthonormalized().inverse() * -_flat_basis().z
		across.y = 0.0
	var distance := clampf(velocity.length() * DISTANCE_PER_SPEED, NEAREST, FURTHEST)
	var height := clampf(DEFAULT_OUT.y + direction.y * 0.8, LOWEST, HIGHEST)
	return across.normalized() * distance + Vector3.UP * height


func _stow(side: String) -> void:
	var root := _root()
	if root == null:
		return
	_mode = "holstered"
	_side = side
	_fly = {"from": root.global_position, "t": 0.0, "seconds": PULL_SECONDS if _hand != "" else FLY_SECONDS, "scale_from": _scale}
	if _hand != "":
		_pulse(_hand, 0.6, 0.08)
	print("Slopitect holster: the avatar is stowed at the %s hip" % side)


func _send_out() -> void:
	var root := _root()
	if root == null:
		return
	_mode = "out"
	_fly = {"from": root.global_position, "t": 0.0, "seconds": FLY_SECONDS, "scale_from": _scale}
	print("Slopitect holster: the avatar went out to %s" % str(_out))


func _set_free(root: Node3D) -> void:
	_mode = "free"
	_fly = {}
	_placed = Vector3.INF
	if _scale != 1.0:
		_fly = {"from": root.global_position, "t": 0.0, "seconds": PULL_SECONDS, "scale_from": _scale}


# --- Places --------------------------------------------------------------------------

# Your facing across the floor, from the headset (looking straight down or
# up, from the headset's top instead).
func _flat_basis() -> Basis:
	var head: Basis = (ctx["camera"] as Node3D).global_basis.orthonormalized()
	var forward := -head.z
	if Vector3(forward.x, 0, forward.z).length() < 0.4:
		forward = head.y if forward.y < 0.0 else -head.y
	forward = Vector3(forward.x, 0, forward.z).normalized()
	if forward == Vector3.ZERO:
		forward = Vector3.FORWARD
	return Basis.looking_at(forward, Vector3.UP)


func _hip(side: String) -> Vector3:
	var flat := _flat_basis()
	var head: Vector3 = (ctx["camera"] as Node3D).global_position
	return head + flat.x * (HIP_SIDE if side == "right" else -HIP_SIDE) + Vector3.DOWN * HIP_DOWN - flat.z * HIP_FORWARD


func _hip_near(at: Vector3) -> String:
	var best := ""
	var best_distance := HIP_REACH
	for side in ["left", "right"]:
		var distance := at.distance_to(_hip(side))
		if distance <= best_distance:
			best = side
			best_distance = distance
	return best


func _out_spot() -> Vector3:
	return (ctx["camera"] as Node3D).global_position + _origin().global_basis.orthonormalized() * _out


func _origin() -> Node3D:
	return (ctx["camera"] as Node3D).get_parent() as Node3D


# --- The avatar ------------------------------------------------------------------------

func _avatar() -> SlopitectModule:
	return _avatar_module if is_instance_valid(_avatar_module) else null


# The node that holds the whole avatar (avatar.gd's root()).
func _root() -> Node3D:
	var avatar := _avatar()
	if avatar == null:
		return null
	var root = avatar.call("root")
	return root if root is Node3D and (root as Node3D).is_inside_tree() else null


func _middle(root: Node3D) -> Vector3:
	var avatar := _avatar()
	var body = avatar.call("body") if avatar else null
	return (body as Node3D).global_position if body is Node3D else root.global_position


func _make_ring() -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.075
	mesh.outer_radius = 0.09
	mesh.rings = 24
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 1, 1, 0.35)
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)
	return ring


func _show_rings(shown: bool) -> void:
	for side in _rings:
		(_rings[side] as MeshInstance3D).visible = shown


func _pulse(hand: String, strength: float, seconds: float) -> void:
	var controls: SlopitectModule = _lib.module("controls") if _lib else null
	if controls:
		controls.call("pulse", hand, strength, seconds)


func _hand_speed(hand: String) -> Vector3:
	var trail: Array = _trail[hand]
	if trail.size() < 2 or trail[-1][0] - trail[0][0] <= 0.0:
		return Vector3.ZERO
	return (trail[-1][1] - trail[0][1]) / (trail[-1][0] - trail[0][0])


# --- Commands ------------------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	if _avatar() == null:
		return {"ok": false, "error": "the avatar module isn't loaded (or is an older avatar.gd without root())"}
	var out := {"ok": true, "mode": _mode, "side": _side, "out": [snappedf(_out.x, 0.01), snappedf(_out.y, 0.01), snappedf(_out.z, 0.01)]}
	if _mode == "held":
		out["hand"] = _hand
	return out


func _stow_command(request: Dictionary) -> Dictionary:
	var side = request.get("side", _side)
	if not side in ["left", "right"]:
		return {"ok": false, "error": "\"side\" must be left or right"}
	if _root() == null:
		return _status({})
	_show_rings(false)
	_hand = ""
	_stow(side)
	return _status({})


func _summon_command(request: Dictionary) -> Dictionary:
	if request.has("direction"):
		var d = request["direction"]
		if typeof(d) != TYPE_ARRAY or d.size() != 3 or not d.all(func(n): return typeof(n) in [TYPE_INT, TYPE_FLOAT]):
			return {"ok": false, "error": "\"direction\" must be [x, y, z] in metres"}
		var spot := Vector3(d[0], d[1], d[2])
		if Vector3(spot.x, 0, spot.z).length() > FURTHEST or spot.y < LOWEST or spot.y > HIGHEST:
			return {"ok": false, "error": "keep it within %.1f m across and %.1f to %.1f m from your head height" % [FURTHEST, LOWEST, HIGHEST]}
		_out = spot
	if _root() == null:
		return _status({})
	_show_rings(false)
	_hand = ""
	_send_out()
	return _status({})


func _toggle_command(_request: Dictionary) -> Dictionary:
	if _mode == "holstered":
		return _summon_command({})
	return _stow_command({})
