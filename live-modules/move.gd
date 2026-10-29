extends SlopitectModule

# Slopitect live module: move.
# Walking with the left stick (the way you look), turning with the right
# stick (in steps, or smoothly). With the landscape module loaded, you stand
# on its ground; elsewhere on the floor. Unload it and the sticks do nothing
# again. Its settings change from the PC only (move_config) and are kept in
# the app's own storage (user://move.json).

const SETTINGS_PATH := "user://move.json"
const DEFAULTS := {"speed": 1.5, "turn": "snap", "snap_degrees": 30.0, "smooth_degrees": 90.0, "follow_ground": true}
const DEADZONE := 0.2
const SNAP_ON := 0.7  # stick past this turns once...
const SNAP_OFF := 0.3  # ...and must come back under this before the next turn

var settings := DEFAULTS.duplicate()
var _origin: XROrigin3D
var _snapped := false


func setup() -> String:
	_origin = ctx["camera"].get_parent() as XROrigin3D
	if _origin == null:
		return "move can't find the XROrigin3D above the camera"
	_load()
	register("move_status", _status, "where the person stands and which way they face, and the move settings")
	register("move_to", _move_to, "put the person somewhere: position [x, z] (their head goes there), optional facing (degrees, 0 = -z)")
	register("move_config", _config, "from the PC only: any of speed (m/s), turn (snap or smooth), snap_degrees, smooth_degrees (a second), follow_ground (true/false)")
	return ""


func _physics_process(delta: float) -> void:
	var left: XRController3D = ctx["left"]
	var right: XRController3D = ctx["right"]
	var camera: Node3D = ctx["camera"]

	var stick := left.get_vector2("primary")
	if stick.length() > DEADZONE:
		var forward := -camera.global_basis.z
		forward.y = 0.0
		var side := camera.global_basis.x
		side.y = 0.0
		if forward.length() > 0.01 and side.length() > 0.01:
			var along := forward.normalized() * stick.y + side.normalized() * stick.x
			_origin.global_position += along.limit_length(1.0) * float(settings["speed"]) * delta

	var turn := right.get_vector2("primary").x
	if settings["turn"] == "snap":
		if not _snapped and absf(turn) > SNAP_ON:
			_snapped = true
			_turn_by(-signf(turn) * float(settings["snap_degrees"]))
		elif absf(turn) < SNAP_OFF:
			_snapped = false
	elif absf(turn) > DEADZONE:
		_turn_by(-turn * float(settings["smooth_degrees"]) * delta)

	if settings["follow_ground"]:
		var ground := _ground_under(camera.global_position)
		_origin.global_position.y = lerpf(_origin.global_position.y, ground, minf(1.0, delta * 10.0))


# Turns around the head, not the middle of the play area, so you stay put.
func _turn_by(degrees: float) -> void:
	var head: Vector3 = ctx["camera"].global_position
	var turn := Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3.ZERO)
	_origin.global_transform = Transform3D.IDENTITY.translated(head) * turn * Transform3D.IDENTITY.translated(-head) * _origin.global_transform


func _ground_under(at: Vector3) -> float:
	var landscape: SlopitectModule = ctx["modules"].module("landscape")
	if landscape and landscape.call("inside", at.x, at.z):
		return landscape.call("height_at", at.x, at.z)
	return 0.0


func _status(_request: Dictionary) -> Dictionary:
	var head: Vector3 = ctx["camera"].global_position
	var forward: Vector3 = -ctx["camera"].global_basis.z
	return {"ok": true, "head": _vec_out(head), "standing_on": snappedf(_origin.global_position.y, 0.01),
		"facing": snappedf(rad_to_deg(atan2(-forward.x, -forward.z)), 0.1), "settings": settings}


func _move_to(request: Dictionary) -> Dictionary:
	var position = request.get("position")
	if typeof(position) != TYPE_ARRAY or position.size() != 2 or not _number(position[0]) or not _number(position[1]):
		return {"ok": false, "error": "\"position\" must be [x, z] in metres"}
	if request.has("facing"):
		if not _number(request["facing"]):
			return {"ok": false, "error": "\"facing\" must be degrees"}
		var forward: Vector3 = -ctx["camera"].global_basis.z
		var now := rad_to_deg(atan2(-forward.x, -forward.z))
		_turn_by(float(request["facing"]) - now)
	var head: Vector3 = ctx["camera"].global_position
	_origin.global_position += Vector3(float(position[0]) - head.x, 0.0, float(position[1]) - head.z)
	_origin.global_position.y = _ground_under(Vector3(float(position[0]), 0.0, float(position[1])))
	return _status({})


func _number(value) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and not is_nan(float(value)) and absf(float(value)) <= 10000.0


func _vec_out(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


# --- Settings ------------------------------------------------------------------------

func _config(request: Dictionary) -> Dictionary:
	var changes := {}
	for key in request:
		if key in ["cmd", "id"]:
			continue
		if not DEFAULTS.has(key):
			return {"ok": false, "error": "unknown setting \"%s\" (one of: %s)" % [key, ", ".join(DEFAULTS.keys())]}
		var value = request[key]
		match key:
			"speed":
				if not _number(value) or float(value) <= 0.0 or float(value) > 10.0:
					return {"ok": false, "error": "\"speed\" must be above 0 and up to 10 m/s"}
			"snap_degrees", "smooth_degrees":
				if not _number(value) or float(value) < 1.0 or float(value) > 360.0:
					return {"ok": false, "error": "\"%s\" must be 1 to 360" % key}
			"turn":
				if not value in ["snap", "smooth"]:
					return {"ok": false, "error": "\"turn\" must be \"snap\" or \"smooth\""}
			"follow_ground":
				if typeof(value) != TYPE_BOOL:
					return {"ok": false, "error": "\"follow_ground\" must be true or false"}
		changes[key] = float(value) if _number(value) and typeof(value) != TYPE_BOOL else value
	settings.merge(changes, true)
	var out := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if out:
		out.store_string(JSON.stringify(settings, "\t"))
		out.close()
	return {"ok": true, "settings": settings}


func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var saved = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(saved) != TYPE_DICTIONARY:
		push_error("Slopitect move: %s isn't readable; using the defaults" % SETTINGS_PATH)
		return
	for key in saved:
		if DEFAULTS.has(key) and typeof(saved[key]) == typeof(DEFAULTS[key]):
			settings[key] = saved[key]
