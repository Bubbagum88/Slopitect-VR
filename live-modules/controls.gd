extends SlopitectModule

# Slopitect live module: controls.
# The one place that reads the controllers. Each button is bound to a named
# action ("point", "grab_left", "talk", ...) and each thumbstick to a named
# stick ("walk", "turn"); other modules work with the actions, never with
# the buttons, so swapping this file changes the whole control scheme.
#
# A module takes actions with on_action(action: String, down: bool) -> bool.
# On a press the modules are asked in turn (lower action_order() first,
# 100 when a module has none) until one returns true; that one alone gets
# the release. A module reads a stick with
# ctx["modules"].module("controls").stick("walk") (a Vector2), buzzes a
# controller with pulse(hand, strength, seconds), and reads how far a
# grip or trigger is pressed, or whether a thumb or finger rests on the
# controller, with value(hand, name) (0 to 1; for hands and the like, never
# a press: presses are actions).
#
# A button can also run a command instead of giving an action: bound to
# {"cmd": ...} in controls_config, a press runs that command (with
# "position": "in_front" turned into the point 1 m in front of you). Never
# a *_config or agent_ command, so no button changes a setting. Bound to
# {"panel": id_panel}, a press shows that window, or hides it if it's shown
# (any vrui.gd panel, such as "chat" or "worlds").
#
# Walking and turning live here too, so the sticks and how they move you
# are in one file: the "walk" stick walks (the way you look) and the "turn"
# stick turns (in steps, or smoothly), around your head. With the landscape
# module loaded you stand on its ground; elsewhere on the floor. Speed,
# dead zone and turning are comfort settings (move_comfort, the Settings
# window's Moving section); follow_ground and wider ranges are move_config,
# from the PC. They're kept in user://move.json (where move.gd, which this
# replaces, kept them). controls_status shows both sticks live, and the log
# says when you start and stop walking and how far you went.
#
# Two things never go through here, so no module can take them away: X on
# the left controller always stops the agent (the agent module's), and the
# Yes / No window reads the right trigger (and the right thumbstick, to
# scroll) itself. While it's open, no action or command is sent and the
# sticks and values read zero.
# The bindings change from the PC only (controls_config).

const SETTINGS_PATH := "user://controls.json"
const RESERVED := ["left/ax_button"]  # the agent's Stop
const BUTTONS := ["trigger_click", "grip_click", "ax_button", "by_button", "menu_button", "primary_click"]
const DEFAULT_BUTTONS := {
	"right/trigger_click": "point",
	"right/grip_click": "grab_right",
	"left/grip_click": "grab_left",
	"left/trigger_click": "talk",
	"left/menu_button": "left_menu",
	"left/by_button": "left_y",
	"right/by_button": "right_b",
	"right/ax_button": "right_a",
	"left/primary_click": "left_stick",  # pressing the left thumbstick in
}
const DEFAULT_STICKS := {"left": "walk", "right": "turn"}
const VALUES := ["grip", "trigger", "trigger_touch", "thumb_touch"]
const THUMB_TOUCHES := ["ax_touch", "by_touch", "primary_touch"]
const MAX_COMMAND := 2000  # characters of a bound command, as JSON
const MOVE_PATH := "user://move.json"
const MOVE_DEFAULTS := {"speed": 1.5, "deadzone": 0.2, "turn": "snap", "snap_degrees": 30.0, "smooth_degrees": 90.0, "follow_ground": true}
# What move_comfort may set, and in what range (narrower than move_config's).
const COMFORT := {"speed": [0.5, 3.0], "deadzone": [0.05, 0.5], "snap_degrees": [15.0, 90.0], "smooth_degrees": [30.0, 180.0]}
const SNAP_ON := 0.7  # a stick past this turns once...
const SNAP_OFF := 0.3  # ...and must come back under this before the next turn

var buttons := {}  # "hand/button" -> action, or a command {"cmd": ...}
var sticks := {}  # hand -> stick name
var _taken := {}  # "hand/button" -> the module that took its press
var _last := ""  # the last action, for controls_status
var move := MOVE_DEFAULTS.duplicate()  # the move settings
var _origin: XROrigin3D  # what walking and turning move (null: they're off)
var _snapped := false
var _walk_from = null  # where a walk started (Vector3), null when standing
var _walk_stick := Vector2.ZERO  # the biggest push of this walk, for the log
var _lib: SlopitectModule
var _confirm: SlopitectModule  # the APK's Yes/No window, asked many times a frame
var _landscape: SlopitectModule  # the ground walked on, while it's loaded


func setup() -> String:
	_load()
	_load_move()
	_origin = ctx["camera"].get_parent() as XROrigin3D
	if _origin == null:
		push_error("Slopitect controls: no XROrigin3D above the camera, so the sticks can't walk or turn")
	for hand in ["left", "right"]:
		ctx[hand].button_pressed.connect(_on_button.bind(hand, true))
		ctx[hand].button_released.connect(_on_button.bind(hand, false))
	register("controls_status", _status, "what each button and thumbstick does, and the last action")
	register("move_status", _move_status, "where the person stands and which way they face, the move settings, and both thumbsticks now")
	register("move_to", _move_to, "put the person somewhere: position [x, z] (their head goes there), optional facing (degrees, 0 = -z)")
	register("move_comfort", _comfort, "change how you move, in the headset (comfort settings): any of turn (snap or smooth), speed (%s to %s m/s), deadzone (%s to %s of the stick), snap_degrees (%s to %s), smooth_degrees (%s to %s a second)" % [COMFORT["speed"][0], COMFORT["speed"][1], COMFORT["deadzone"][0], COMFORT["deadzone"][1], COMFORT["snap_degrees"][0], COMFORT["snap_degrees"][1], COMFORT["smooth_degrees"][0], COMFORT["smooth_degrees"][1]])
	register("move_config", _move_config, "from the PC only: any of speed (m/s), deadzone (0 to 0.9), turn (snap or smooth), snap_degrees, smooth_degrees (a second), follow_ground (true/false)")
	register("controls_config", _config, "from the PC only: buttons {\"hand/button\": action, a command {\"cmd\": ...}, a window {\"panel\": id_panel} or \"\"}, sticks {hand: name or \"\"}, or reset true")
	return ""


# With lib, the modules asked every frame are kept at hand instead of looked
# up each time (before lib arrives, they're looked up).
func lib_ready(lib) -> void:
	_lib = lib
	_confirm = lib.module("confirm") if lib else null
	_landscape = null
	if lib:
		lib.watch(self, "landscape", _landscape_here, _landscape_gone)


func _landscape_here(landscape: SlopitectModule) -> void:
	_landscape = landscape


func _landscape_gone(_old: SlopitectModule) -> void:
	_landscape = null


func _exit_tree() -> void:
	for key in _taken.keys():
		_release(key)


# The value of a named stick (zero when no thumbstick is bound to it).
func stick(stick_name: String) -> Vector2:
	if _asking():
		return Vector2.ZERO  # the right thumbstick scrolls the question's sheet then
	for hand in sticks:
		if sticks[hand] == stick_name:
			return (ctx[hand] as XRController3D).get_vector2("primary")
	return Vector2.ZERO


# How far a grip or trigger is pressed (0 to 1), or 1 when a finger rests on
# the trigger (trigger_touch) or the thumb on a button or the thumbstick
# (thumb_touch); zero while the Yes / No window asks.
func value(hand: String, value_name: String) -> float:
	if not hand in ["left", "right"] or _asking():
		return 0.0
	var controller := ctx[hand] as XRController3D
	match value_name:
		"grip", "trigger":
			return clampf(controller.get_float(value_name), 0.0, 1.0)
		"trigger_touch":
			return 1.0 if controller.is_button_pressed("trigger_touch") else 0.0
		"thumb_touch":
			for touch in THUMB_TOUCHES:
				if controller.is_button_pressed(touch):
					return 1.0
			return 0.0
	return 0.0


# A short buzz on a controller: hand "left" or "right", strength 0 to 1, for
# seconds. Windows tick on hover and press; tools can mark a click.
func pulse(hand: String, strength: float, seconds: float) -> void:
	if not hand in ["left", "right"]:
		return
	(ctx[hand] as XRController3D).trigger_haptic_pulse("haptic", 0.0, clampf(strength, 0.0, 1.0), clampf(seconds, 0.0, 0.5), 0.0)


func _asking() -> bool:
	var confirm: SlopitectModule = _confirm if _confirm != null else ctx["modules"].module("confirm")
	return confirm != null and confirm.call("asking")


func _on_button(button: String, hand: String, down: bool) -> void:
	var key := hand + "/" + button
	if not down:
		_release(key)
		return
	if not buttons.has(key) or _asking():
		return
	if typeof(buttons[key]) == TYPE_DICTIONARY:
		_run_bound(key, buttons[key])
		return
	var action: String = buttons[key]
	_last = "%s (%s)" % [action, key]
	var takers := []
	for child in ctx["modules"].get_children():
		if child != self and child.has_method("on_action"):
			takers.append(child)
	takers.sort_custom(func(a, b): return _order(a) < _order(b))
	for module in takers:
		if module.call("on_action", action, true) == true:
			_taken[key] = module
			return


func _run_bound(key: String, command: Dictionary) -> void:
	if command.has("panel"):
		var got: Dictionary = ctx["server"].run({"cmd": "ui_get", "id_panel": command["panel"]})
		var request := {"cmd": "ui_show", "id_panel": command["panel"], "visible": not got.get("panel", {}).get("visible", false)}
		_report(key, "show/hide " + command["panel"], ctx["server"].run(request) if got.get("ok", false) else got)
		return
	var request := command.duplicate(true)
	if request.get("position") is String and request["position"] == "in_front":
		var head: Transform3D = (ctx["camera"] as Node3D).global_transform
		var forward := -head.basis.z
		forward.y = 0.0
		if forward.length() < 0.01:
			forward = Vector3(0, 0, -1)
		var at := head.origin + forward.normalized()
		request["position"] = [at.x, at.y, at.z]
	_report(key, request["cmd"], ctx["server"].run(request))


func _report(key: String, what: String, reply: Dictionary) -> void:
	_last = "%s (%s)" % [what, key]
	if not reply.get("ok", false):
		_last += " failed: %s" % reply.get("error", "?")
		push_error("Slopitect controls: %s ran %s, which failed: %s" % [key, what, reply.get("error", "?")])


func _release(key: String) -> void:
	if not _taken.has(key):
		return
	var module = _taken[key]
	_taken.erase(key)
	if is_instance_valid(module):
		module.call("on_action", buttons.get(key, ""), false)


func _order(module: Node) -> int:
	return int(module.call("action_order")) if module.has_method("action_order") else 100


# --- Walking and turning ---------------------------------------------------------------

# Every frame, after the headset has moved the camera, so a walk is smooth.
func _process(delta: float) -> void:
	if _origin == null:
		return
	var camera: Node3D = ctx["camera"]
	var deadzone := float(move["deadzone"])
	var walk := stick("walk")
	if walk.length() > deadzone:
		var forward := -camera.global_basis.z
		forward.y = 0.0
		var side := camera.global_basis.x
		side.y = 0.0
		if forward.length() > 0.01 and side.length() > 0.01:
			# Past the dead zone the speed starts from nothing, so there's no jump.
			var push := walk.limit_length(1.0)
			push *= (push.length() - deadzone) / (1.0 - deadzone) / push.length()
			if _walk_from == null:
				_walk_from = _origin.global_position
				_walk_stick = Vector2.ZERO
			if walk.length() > _walk_stick.length():
				_walk_stick = walk
			_origin.global_position += (forward.normalized() * push.y + side.normalized() * push.x) * float(move["speed"]) * delta
	elif _walk_from != null:
		var went: Vector3 = _origin.global_position - _walk_from
		print("Slopitect controls: walked %.2f m (stick pushed up to %.2f, %.2f)" % [Vector2(went.x, went.z).length(), _walk_stick.x, _walk_stick.y])
		_walk_from = null

	var turn := stick("turn").x
	if move["turn"] == "snap":
		if not _snapped and absf(turn) > SNAP_ON:
			_snapped = true
			_turn_by(-signf(turn) * float(move["snap_degrees"]))
		elif absf(turn) < SNAP_OFF:
			_snapped = false
	elif absf(turn) > deadzone:
		_turn_by(-signf(turn) * (absf(turn) - deadzone) / (1.0 - deadzone) * float(move["smooth_degrees"]) * delta)

	if move["follow_ground"]:
		var ground := _ground_under(camera.global_position)
		_origin.global_position.y = lerpf(_origin.global_position.y, ground, minf(1.0, delta * 10.0))


# Turns around the head, not the middle of the play area, so you stay put.
func _turn_by(degrees: float) -> void:
	var head: Vector3 = ctx["camera"].global_position
	var turn := Transform3D(Basis(Vector3.UP, deg_to_rad(degrees)), Vector3.ZERO)
	_origin.global_transform = Transform3D.IDENTITY.translated(head) * turn * Transform3D.IDENTITY.translated(-head) * _origin.global_transform


func _ground_under(at: Vector3) -> float:
	var landscape: SlopitectModule = _landscape if _lib else ctx["modules"].module("landscape")
	if landscape and landscape.call("inside", at.x, at.z):
		return landscape.call("height_at", at.x, at.z)
	return 0.0


# What each thumbstick reads now, straight from the controller (even while
# the Yes / No window asks), for controls_status and move_status.
func _sticks_now() -> Dictionary:
	var out := {}
	for hand in ["left", "right"]:
		var v := (ctx[hand] as XRController3D).get_vector2("primary")
		out[hand] = [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]
	return out


func _move_status(_request: Dictionary) -> Dictionary:
	if _origin == null:
		return {"ok": false, "error": "no XROrigin3D above the camera, so there's nothing to move"}
	var head: Vector3 = ctx["camera"].global_position
	var forward: Vector3 = -ctx["camera"].global_basis.z
	return {"ok": true, "head": _vec_out(head), "standing_on": snappedf(_origin.global_position.y, 0.01),
		"facing": snappedf(rad_to_deg(atan2(-forward.x, -forward.z)), 0.1), "settings": move,
		"sticks_now": _sticks_now(), "walking": _walk_from != null, "asking": _asking()}


func _move_to(request: Dictionary) -> Dictionary:
	if _origin == null:
		return {"ok": false, "error": "no XROrigin3D above the camera, so there's nothing to move"}
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
	return _move_status({})


func _number(value) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and not is_nan(float(value)) and absf(float(value)) <= 10000.0


func _vec_out(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


# Its section of the Settings window (settings.gd): the comfort settings,
# in move_comfort's ranges. The angle shown is the one the turn uses.
func settings_info() -> Dictionary:
	var out := [
		{"id": "turn", "type": "choice", "value": move["turn"], "set": {"cmd": "move_comfort", "turn": "{value}"},
			"options": [{"label": "Snap turn", "value": "snap"}, {"label": "Smooth turn", "value": "smooth"}]},
		_comfort_slider("speed", "Walk speed (m/s)", 0.25),
		_comfort_slider("deadzone", "Stick dead zone", 0.05),
	]
	if move["turn"] == "snap":
		out.append(_comfort_slider("snap_degrees", "Snap angle (°)", 15.0))
	else:
		out.append(_comfort_slider("smooth_degrees", "Turn speed (°/s)", 15.0))
	return {"title": "Moving", "order": 10, "settings": out}


func _comfort_slider(key: String, label: String, step: float) -> Dictionary:
	return {"id": key, "type": "slider", "label": label, "min": COMFORT[key][0], "max": COMFORT[key][1], "step": step,
		"value": move[key], "set": {"cmd": "move_comfort", key: "{value}"}}


# The comfort settings can change in the headset (isaac's choice,
# 2026-10-29); follow_ground and wider ranges stay with move_config.
func _comfort(request: Dictionary) -> Dictionary:
	var changes := {"cmd": "move_config"}
	for key in request:
		if key in ["cmd", "id"]:
			continue
		if key == "turn":
			changes[key] = request[key]
			continue
		if not COMFORT.has(key):
			return {"ok": false, "error": "move_comfort changes turn, speed, deadzone, snap_degrees or smooth_degrees (the rest is move_config, from the PC)"}
		var value = request[key]
		if not _number(value) or float(value) < COMFORT[key][0] or float(value) > COMFORT[key][1]:
			return {"ok": false, "error": "\"%s\" must be %s to %s" % [key, COMFORT[key][0], COMFORT[key][1]]}
		changes[key] = value
	return _move_config(changes)


func _move_config(request: Dictionary) -> Dictionary:
	var changes := {}
	for key in request:
		if key in ["cmd", "id"]:
			continue
		if not MOVE_DEFAULTS.has(key):
			return {"ok": false, "error": "unknown setting \"%s\" (one of: %s)" % [key, ", ".join(MOVE_DEFAULTS.keys())]}
		var value = request[key]
		match key:
			"speed":
				if not _number(value) or float(value) <= 0.0 or float(value) > 10.0:
					return {"ok": false, "error": "\"speed\" must be above 0 and up to 10 m/s"}
			"deadzone":
				if not _number(value) or float(value) < 0.0 or float(value) > 0.9:
					return {"ok": false, "error": "\"deadzone\" must be 0 to 0.9"}
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
	move.merge(changes, true)
	var out := FileAccess.open(MOVE_PATH, FileAccess.WRITE)
	if out:
		out.store_string(JSON.stringify(move, "\t"))
		out.close()
	else:
		push_error("Slopitect controls: couldn't save %s (error %d)" % [MOVE_PATH, FileAccess.get_open_error()])
	if _lib:
		_lib.touch(self)  # the Settings window shows the new values
	return {"ok": true, "settings": move}


func _load_move() -> void:
	move = MOVE_DEFAULTS.duplicate()
	if not FileAccess.file_exists(MOVE_PATH):
		return
	var saved = JSON.parse_string(FileAccess.get_file_as_string(MOVE_PATH))
	if typeof(saved) != TYPE_DICTIONARY:
		push_error("Slopitect controls: %s isn't readable; using the default move settings" % MOVE_PATH)
		return
	for key in saved:
		if MOVE_DEFAULTS.has(key) and typeof(saved[key]) == typeof(MOVE_DEFAULTS[key]):
			move[key] = saved[key]


# --- Commands ------------------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	var held := []
	for key in _taken:
		held.append({"button": key, "action": buttons.get(key, ""), "module": String(_taken[key].name) if is_instance_valid(_taken[key]) else ""})
	return {"ok": true, "buttons": buttons, "sticks": sticks, "reserved": {"left/ax_button": "stop the agent"},
		"held": held, "last": _last, "sticks_now": _sticks_now(), "asking": _asking()}


func _config(request: Dictionary) -> Dictionary:
	if request.get("reset", false) == true:
		buttons = DEFAULT_BUTTONS.duplicate()
		sticks = DEFAULT_STICKS.duplicate()
		_save()
		return _status({})
	var new_buttons := buttons.duplicate()
	var new_sticks := sticks.duplicate()
	var asked = request.get("buttons", {})
	if typeof(asked) != TYPE_DICTIONARY:
		return {"ok": false, "error": "\"buttons\" must be {\"hand/button\": action}, e.g. {\"right/by_button\": \"right_b\"}"}
	for key in asked:
		var problem := _check_button(key, asked[key])
		if not problem.is_empty():
			return {"ok": false, "error": problem}
		if typeof(asked[key]) == TYPE_DICTIONARY:
			new_buttons[key] = asked[key].duplicate(true)
		elif asked[key].is_empty():
			new_buttons.erase(key)
		else:
			new_buttons[key] = asked[key]
	var asked_sticks = request.get("sticks", {})
	if typeof(asked_sticks) != TYPE_DICTIONARY:
		return {"ok": false, "error": "\"sticks\" must be {hand: name}, e.g. {\"left\": \"walk\"}"}
	for hand in asked_sticks:
		if not hand in ["left", "right"] or not (asked_sticks[hand] == "" or _good_name(asked_sticks[hand])):
			return {"ok": false, "error": "a stick is {\"left\" or \"right\": a name of letters, digits and _, or \"\"}"}
		if asked_sticks[hand].is_empty():
			new_sticks.erase(hand)
		else:
			new_sticks[hand] = asked_sticks[hand]
	for key in _taken.keys():
		_release(key)  # a held button's action may be changing
	buttons = new_buttons
	sticks = new_sticks
	_save()
	return _status({})


func _check_button(key, action) -> String:
	if typeof(key) != TYPE_STRING or key.get_slice_count("/") != 2 or not key.get_slice("/", 0) in ["left", "right"] \
			or not key.get_slice("/", 1) in BUTTONS:
		return "%s isn't a button: use \"left/\" or \"right/\" and one of %s" % [JSON.stringify(key), ", ".join(BUTTONS)]
	if key in RESERVED:
		return "%s always stops the agent; it can't be bound" % key
	if typeof(action) == TYPE_DICTIONARY:
		return _check_command(action)
	if typeof(action) != TYPE_STRING or not (action.is_empty() or _good_name(action)):
		return "an action is a name of 1 to 40 letters, digits and _ (or \"\" for none), a command {\"cmd\": ...} or a window {\"panel\": id_panel}"
	return ""


func _check_command(command: Dictionary) -> String:
	if command.has("panel"):
		if command.size() != 1 or not _good_name(command["panel"]):
			return "a window binding is {\"panel\": its id_panel} and nothing else (ui_list shows the ids)"
		return ""
	var cmd = command.get("cmd")
	if typeof(cmd) != TYPE_STRING or not _good_name(cmd):
		return "a bound command needs \"cmd\": a command's name (help lists them)"
	if cmd.ends_with("_config") or cmd.begins_with("agent_") or cmd == "help":
		return "a button can't run %s: settings change only from the PC, and the agent's commands only from its window" % cmd
	if command.has("pair_key") or JSON.stringify(command).length() > MAX_COMMAND:
		return "a bound command is at most %d characters of JSON, with no pair_key" % MAX_COMMAND
	return ""


func _good_name(text) -> bool:
	if typeof(text) != TYPE_STRING or text.is_empty() or text.length() > 40:
		return false
	for c in text:
		if not (c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return true


func _load() -> void:
	buttons = DEFAULT_BUTTONS.duplicate()
	sticks = DEFAULT_STICKS.duplicate()
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var saved = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(saved) != TYPE_DICTIONARY or typeof(saved.get("buttons")) != TYPE_DICTIONARY or typeof(saved.get("sticks")) != TYPE_DICTIONARY:
		push_error("Slopitect controls: %s isn't readable; using the default bindings" % SETTINGS_PATH)
		return
	buttons = {}
	for key in saved["buttons"]:
		if _check_button(key, saved["buttons"][key]).is_empty() and not (typeof(saved["buttons"][key]) == TYPE_STRING and saved["buttons"][key].is_empty()):
			buttons[key] = saved["buttons"][key]
	sticks = {}
	for hand in saved["sticks"]:
		if hand in ["left", "right"] and _good_name(saved["sticks"][hand]):
			sticks[hand] = saved["sticks"][hand]


func _save() -> void:
	var out := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if out == null:
		push_error("Slopitect controls: couldn't save %s (error %d)" % [SETTINGS_PATH, FileAccess.get_open_error()])
		return
	out.store_string(JSON.stringify({"buttons": buttons, "sticks": sticks}, "\t"))
	out.close()
	if _lib:
		_lib.touch(self)  # the Settings window shows the new values
