extends SlopitectModule

# Slopitect live module: jelly.
# Makes the avatar squash and stretch like jelly: a spring that stretches it
# as it rises, squashes it as it lands, starts or stops, and wobbles back,
# keeping its volume. jelly_poke gives it a wobble. Needs the avatar module
# (its body(), whose scale jelly alone sets); without it jelly is off, and
# it starts when the avatar loads.
# The spring's feel changes from the PC only (jelly_config) and is kept in
# the app's own storage (user://jelly.json).

const SETTINGS_PATH := "user://jelly.json"
const DEFAULTS := {"stiffness": 120.0, "damping": 6.0}
const LIMITS := {"stiffness": [20.0, 400.0], "damping": [1.0, 30.0]}
const RISE := 0.144  # stretch per m/s² of upward acceleration, each second
const SWAY := 0.108  # squash per m/s² of sideways acceleration, each second
const MAX_PUSH := 36.0  # the most the movement can push the spring, each second
const MAX_SQUASH := 0.4
const TELEPORT := 20.0  # m/s; faster than this is a jump in place, not movement

var settings := DEFAULTS.duplicate()
var _body: Node3D
var _base_scale := Vector3.ONE
var _last_pos := Vector3.ZERO
var _last_vel := Vector3.ZERO
var _squash := 0.0  # + taller, - flatter
var _speed := 0.0  # how fast _squash changes
var _lib: SlopitectModule


func setup() -> String:
	set_process(false)  # on while there's an avatar to squash
	register("jelly_poke", _poke, "give the avatar a wobble: optional strength (0.1 to 1, default 0.4)")
	register("jelly_status", _status, "whether the avatar is found, how squashed it is now, and the spring's settings")
	register("jelly_config", _config, "from the PC only: any of stiffness (%d to %d), damping (%d to %d)" % [LIMITS["stiffness"][0], LIMITS["stiffness"][1], LIMITS["damping"][0], LIMITS["damping"][1]])
	return ""


func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		return
	_load()
	lib.watch(self, "avatar", _avatar_here, _avatar_gone)


func _avatar_here(_avatar: SlopitectModule) -> void:
	set_process(_find_body())


func _avatar_gone(_avatar: SlopitectModule) -> void:
	_let_go()
	set_process(false)


func _exit_tree() -> void:
	_let_go()


func _process(delta: float) -> void:
	if delta <= 0.0 or not (is_instance_valid(_body) or _find_body()):
		return
	# The body bobs a little by itself; its parent is what moves the avatar about.
	var mover: Node3D = _body.get_parent() as Node3D if _body.get_parent() is Node3D else _body
	var pos := mover.global_position
	var vel := (pos - _last_pos) / delta
	_last_pos = pos
	if vel.length() > TELEPORT:
		vel = _last_vel
	var acc := (vel - _last_vel) / delta
	_last_vel = vel
	var push := clampf(acc.y * RISE - Vector2(acc.x, acc.z).length() * SWAY, -MAX_PUSH, MAX_PUSH)
	_speed += (-float(settings["stiffness"]) * _squash - float(settings["damping"]) * _speed + push) * delta
	_squash = clampf(_squash + _speed * delta, -MAX_SQUASH, MAX_SQUASH)
	var side := 1.0 / sqrt(1.0 + _squash)
	_body.scale = _base_scale * Vector3(side, 1.0 + _squash, side)


# Finds the avatar's body, also after the avatar module is loaded again.
func _find_body() -> bool:
	var avatar: SlopitectModule = _lib.module("avatar") if _lib else null
	var body: Node3D = avatar.call("body") if avatar != null and avatar.has_method("body") else null
	if body == _body and is_instance_valid(_body):
		return true
	_let_go()
	if body == null or not is_instance_valid(body):
		return false
	_body = body
	_base_scale = body.scale
	var mover: Node3D = body.get_parent() as Node3D if body.get_parent() is Node3D else body
	_last_pos = mover.global_position
	_last_vel = Vector3.ZERO
	_squash = 0.0
	_speed = 0.0
	return true


func _let_go() -> void:
	if _body != null and is_instance_valid(_body):
		_body.scale = _base_scale
	_body = null


# --- Commands and settings -------------------------------------------------------------

func _poke(request: Dictionary) -> Dictionary:
	var strength = request.get("strength", 0.4)
	if typeof(strength) not in [TYPE_INT, TYPE_FLOAT] or strength < 0.1 or strength > 1.0:
		return {"ok": false, "error": "\"strength\" must be 0.1 to 1"}
	if not _find_body():
		return {"ok": false, "error": "no avatar to wobble (is the avatar module loaded?)"}
	_speed -= float(strength) * 6.0
	set_process(true)
	return {"ok": true}


func _status(_request: Dictionary) -> Dictionary:
	return {"ok": true, "avatar": _body != null and is_instance_valid(_body), "squash": snappedf(_squash, 0.001), "settings": settings}


func _config(request: Dictionary) -> Dictionary:
	var changes := {}
	for key in request:
		if key in ["cmd", "id"]:
			continue
		if not DEFAULTS.has(key):
			return {"ok": false, "error": "unknown setting \"%s\" (one of: %s)" % [key, ", ".join(DEFAULTS.keys())]}
		var value = request[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < LIMITS[key][0] or value > LIMITS[key][1]:
			return {"ok": false, "error": "\"%s\" must be %d to %d" % [key, LIMITS[key][0], LIMITS[key][1]]}
		changes[key] = float(value)
	settings.merge(changes, true)
	var problem: String = _lib.write_json(SETTINGS_PATH, settings, "\t") if _lib else "the lib module isn't loaded"
	if not problem.is_empty():
		push_error("Slopitect jelly: couldn't save %s: %s" % [SETTINGS_PATH, problem])
	return _status({})


func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var saved = _lib.read_json(SETTINGS_PATH)
	if typeof(saved) != TYPE_DICTIONARY:
		push_error("Slopitect jelly: %s isn't readable; using the defaults" % SETTINGS_PATH)
		return
	for key in DEFAULTS:
		var value = saved.get(key)
		if typeof(value) in [TYPE_INT, TYPE_FLOAT] and value >= LIMITS[key][0] and value <= LIMITS[key][1]:
			settings[key] = float(value)
