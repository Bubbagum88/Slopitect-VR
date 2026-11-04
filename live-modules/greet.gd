extends SlopitectModule

# Wave at the avatar and it waves back. Make a finger gun near it (grip
# curled, trigger untouched) and it puts its hands up.

const NEAR := 2.0  # m, how close a hand must be to the avatar
const SWING := 0.1  # m a hand must travel to count as a swing
const WAVE_SWINGS := 3  # reversals within about 1.5 s make a wave
const GUN_GRIP := 0.6  # how far the grip must be squeezed
const GUN_HOLD := 0.4  # s the gun pose must hold
const COOL := 3.0  # s before the avatar reacts again

var _lib: SlopitectModule
var _avatar: SlopitectModule
var _controls: SlopitectModule
var _grab = null  # grab.gd: holds the things the hands have picked up
var _cool := 0.0
var _hold := {"left": 0.0, "right": 0.0}
var _swing := {"left": {}, "right": {}}


func setup() -> String:
	set_process(false)
	return ""


func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		_avatar = null
		_controls = null
		set_process(false)
		return
	lib.watch(self, "avatar", _avatar_here, _avatar_gone)
	lib.watch(self, "controls", _controls_here, _controls_gone)
	lib.watch(self, "grab", _grab_here, _grab_gone)


func _grab_here(m) -> void:
	_grab = m


func _grab_gone(_m) -> void:
	_grab = null


func _avatar_here(m: SlopitectModule) -> void:
	_avatar = m
	set_process(_avatar != null and _controls != null)


func _avatar_gone(_m: SlopitectModule) -> void:
	_avatar = null
	set_process(false)


func _controls_here(m: SlopitectModule) -> void:
	_controls = m
	set_process(_avatar != null and _controls != null)


func _controls_gone(_m: SlopitectModule) -> void:
	_controls = null
	set_process(false)


func _exit_tree() -> void:
	_avatar = null
	_controls = null


func _process(delta: float) -> void:
	if _avatar == null or _controls == null:
		return
	var root: Node3D = _avatar.root()
	if root == null:
		return
	var at: Vector3 = root.global_position
	_cool = maxf(_cool - delta, 0.0)
	for hand in ["left", "right"]:
		var c := ctx[hand] as XRController3D
		if c == null:
			continue
		var p := c.global_position
		var near := Vector2(p.x - at.x, p.z - at.z).length() < NEAR and absf(p.y - at.y) < 1.5
		# Wave: the hand swings side to side near the avatar.
		if _wave(hand, (ctx["camera"].global_transform.affine_inverse() * p).x, near) and _cool <= 0.0:
			_avatar.set_state("wave", 2.5)
			_avatar.set_emotion("cute", 2.5)
			_cool = COOL
		# Finger gun: grip curled, trigger untouched, held a moment. Not while a hand holds something.
		var gun: bool = near and _controls.value(hand, "grip") >= GUN_GRIP \
			and _controls.value(hand, "trigger") < 0.1 \
			and _controls.value(hand, "trigger_touch") == 0.0 \
			and (_grab == null or _grab.held().is_empty()) and _aimed_at(c, at)
		_hold[hand] = _hold[hand] + delta if gun else 0.0
		if _hold[hand] >= GUN_HOLD and _cool <= 0.0:
			_avatar.set_state("hands_up", 3.0)
			_avatar.set_emotion("surprised", 3.0)
			_cool = COOL
			_hold[hand] = 0.0


# True when the hand points at the avatar's face.
func _aimed_at(c: XRController3D, at: Vector3) -> bool:
	return (-c.global_basis.z).dot((at + Vector3(0, 0.1, 0) - c.global_position).normalized()) > 0.9


# True once a hand has swung side to side enough times near the avatar.
func _wave(hand: String, x: float, near: bool) -> bool:
	var s: Dictionary = _swing[hand]
	if not near:
		s.clear()
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if s.is_empty():
		s = {"dir": 0, "peak": x, "swings": 0, "t": now}
		_swing[hand] = s
		return false
	if now - s.t > 1.5:
		s.swings = 0
		s.t = now
	var turned := false
	if s.dir == 0:
		if absf(x - s.peak) > SWING:
			s.dir = 1 if x > s.peak else -1
			s.peak = x
	elif s.dir > 0:
		if x > s.peak:
			s.peak = x
		elif s.peak - x > SWING:
			s.dir = -1
			s.peak = x
			turned = true
	else:
		if x < s.peak:
			s.peak = x
		elif x - s.peak > SWING:
			s.dir = 1
			s.peak = x
			turned = true
	if turned:
		s.swings += 1
		s.t = now
		if s.swings >= WAVE_SWINGS:
			s.swings = 0
			return true
	return false
