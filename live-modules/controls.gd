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

var buttons := {}  # "hand/button" -> action, or a command {"cmd": ...}
var sticks := {}  # hand -> stick name
var _taken := {}  # "hand/button" -> the module that took its press
var _last := ""  # the last action, for controls_status


func setup() -> String:
	_load()
	for hand in ["left", "right"]:
		ctx[hand].button_pressed.connect(_on_button.bind(hand, true))
		ctx[hand].button_released.connect(_on_button.bind(hand, false))
	register("controls_status", _status, "what each button and thumbstick does, and the last action")
	register("controls_config", _config, "from the PC only: buttons {\"hand/button\": action, a command {\"cmd\": ...}, a window {\"panel\": id_panel} or \"\"}, sticks {hand: name or \"\"}, or reset true")
	return ""


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
	var confirm: SlopitectModule = ctx["modules"].module("confirm")
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


# --- Commands ------------------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	var held := []
	for key in _taken:
		held.append({"button": key, "action": buttons.get(key, ""), "module": String(_taken[key].name) if is_instance_valid(_taken[key]) else ""})
	return {"ok": true, "buttons": buttons, "sticks": sticks, "reserved": {"left/ax_button": "stop the agent"},
		"held": held, "last": _last}


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
