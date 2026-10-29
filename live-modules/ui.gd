extends SlopitectModule

# Slopitect live module: every window in the app, as data.
# A panel is a list of elements (text, buttons, input boxes, plain boxes)
# with a place: in front of you when it opens, on the left wrist, or fixed in
# the world. The menu bar, the wrist panel and the agent's chat window are
# all panels, and you or the agent can change, add, move and remove any of
# them while the app runs, with the ui_* commands. Everything is saved on the
# headset and loaded at the next start.
#
# In the headset: point with the right controller and pull the trigger to
# press a button or pick an input box; hold the right grip while pointing at
# a panel to move it (it then stays where you let go). A panel can have an
# action that shows and hides it ("toggle"). The buttons come from the
# controls module: "point" presses and picks, "grab_right" moves a panel,
# and any other action can be a panel's toggle (controls_status lists them).
#
# A button's action is any command. In an action, "in_front" as a position
# means 1 m in front of you when pressed, and "{input:ID}" is replaced by
# what's typed in that panel's input box ID.
# A text element can show a live value: its "source" is a read-only command
# (list, modules, or one ending in _status or _list), run twice a second
# while the panel is shown.
#
# The look comes from one theme (theme(), changed from the PC with
# ui_config): a colour can be a theme name ("accent", "danger", ...) as well
# as #rrggbb, and an element with no colour takes its type's theme colour.
# A panel with "chrome" gets a title bar: pull the trigger on it and move
# the controller to carry the panel, and its x closes it. "pages" puts tabs
# under the title; an element with a "page" shows only on that tab.
# The Menu bar is also the launcher: any module with menu_info() gets a
# tile on it (see _scan_apps), so a module needs no button of its own.
# Pointing gives feedback: the button lifts and lights up, a dot shows where
# you point, and the controller ticks (controls.pulse) on hover and press.
# Docs: docs/VR-UI.md.

const SAVE_PATH := "user://ui.json"
const CONFIG_PATH := "user://ui_config.json"  # the theme, from the PC only
const OLD_MENU_PATH := "user://menu.json"  # the menu module's file, before panels
const UI_LAYER := 1 << 19  # physics layer 20, used only by panels
const LASER_LENGTH := 3.0
const POLL_SECONDS := 0.5
const NOTICE_SECONDS := 5.0
const MAX_PANELS := 30
const MAX_ELEMENTS := 150
const MAX_TEXT := 4000
const MAX_INPUT := 500
const MAX_PAGES := 8
const PLACES := ["front", "wrist", "world", "follow"]
const LAYOUTS := ["free", "grid"]
const ELEMENT_TYPES := ["text", "button", "input", "box", "toggle", "slider"]
const ALIGNS := {"left": HORIZONTAL_ALIGNMENT_LEFT, "center": HORIZONTAL_ALIGNMENT_CENTER, "right": HORIZONTAL_ALIGNMENT_RIGHT}
const SOURCE_COMMANDS := ["list", "modules"]  # plus any ending in _status or _list
# Colours, sizes and text sizes every panel draws with unless it says
# otherwise. Text sizes are for about 0.6 m away; 24 is the smallest that
# reads comfortably on the Quest 1.
const DEFAULT_THEME := {
	"panel": "#10131a", "border": "#2b3346", "title_bar": "#1a2030", "title": "#c9d4ff",
	"text": "#e8ecf4", "muted": "#8a93a6", "button": "#1f2533", "hover": "#2f4a8a",
	"press": "#5b86ff", "accent": "#4a7dff", "danger": "#a8322a", "ok": "#2f8f4e",
	"input": "#b3e6ff", "input_bg": "#0b0e14", "screen": "#08100a", "notice": "#ff7466",
	"laser": "#66b3ff", "cursor": "#ffffff",
	"font_title": 30, "font_body": 28, "font_small": 24,
}
const THEME_FONTS := ["font_title", "font_body", "font_small"]
const TYPE_COLORS := {"text": "text", "button": "button", "input": "input", "box": "screen", "toggle": "button", "slider": "accent"}
# The colours ui.gd used to write into every element, before the theme; an
# element saved with one of these follows the theme instead.
const OLD_DEFAULT_COLORS := {"text": "#ffffff", "button": "#1f2129", "input": "#b3e6ff", "box": "#08100a"}
const OLD_PANEL_COLOR := "#0b0d11"
const TITLE_BAR := 0.05  # metres, above the panel's background
const TAB_BAR := 0.045
const HOVER_LIFT := 0.004  # a hovered button comes this far towards you
const PRESS_SECONDS := 0.12
const FOLLOW_ANGLE := 35.0  # degrees you turn away before a follow panel catches up
const FOLLOW_DISTANCE := 0.5  # or metres you walk
const FOLLOW_SPEED := 4.0
const APPS_SECONDS := 0.5
const APP_CELL := Vector2(0.15, 0.07)
const TEXT_PIXEL := 0.0006

var panels: Array = []  # [panel dictionaries], see _check_panel
# While a question from the confirm module is up, the pointer only works on
# it, so no panel can sit in front of it or be pressed instead.
var pointer_blocked := false

var theme_values := {}  # DEFAULT_THEME with the PC's changes (ui_config); read it with theme()

var _server: Node
var _camera: XRCamera3D
var _left: XRController3D
var _right: XRController3D
var _holders := {}  # id_panel -> Node3D
var _inputs := {}  # "panel/element" -> typed text (not saved)
var _live_text := {}  # "panel/element" -> text from set_text (not saved)
var _focus := ""  # "panel/element" of the input box that typing goes to
var _shift := false
var _ray: RayCast3D
var _laser: MeshInstance3D
var _cursor: MeshInstance3D
var _hovered: StaticBody3D
var _dragging := ""  # id_panel being carried, by the grip or by its title bar
var _drag_offset: Transform3D
var _sliding := ""  # "panel/element" of the slider the trigger is holding
var _slide_value := 0.0
var _since_poll := 0.0
var _apps: Array = []  # launcher tiles from menu_info(), see _scan_apps
var _apps_signature := ""
var _since_apps := APPS_SECONDS
var _following := {}  # id_panel -> the Transform3D a follow panel is easing to


func setup() -> String:
	_server = ctx["server"]
	_camera = ctx["camera"]
	_left = ctx["left"]
	_right = ctx["right"]
	_load_config()

	register("ui_list", _list, "list the panels: id, title, place, shown or not, toggle button, number of elements")
	register("ui_get", _get_panel, "a panel's full data, including what's typed in its input boxes: id_panel")
	register("ui_add", _add, "add a panel: id_panel, optional title, place (front, wrist, world, follow), distance, height, position, rotation, size, color, visible, toggle (an action from controls_status, like left_menu), chrome (title bar with close), pages [tab names], page (the tab shown), apps (launcher tiles), layout (free or grid with columns and cell), elements")
	register("ui_update", _update, "change any of a panel's fields (elements replaces them all): id_panel, then the fields")
	register("ui_remove", _remove, "remove a panel: id_panel")
	register("ui_show", _show, "show or hide a panel: id_panel, visible (true/false)")
	register("ui_page", _page_command, "show one of a panel's tabs: id_panel, page (its name)")
	register("ui_element_add", _element_add, "add an element to a panel: id_panel, element ({type: text|button|input|box|toggle|slider, id, at [x,y], ...}), optional index")
	register("ui_element_update", _element_update, "change an element's fields: id_panel, id_element, then the fields")
	register("ui_element_remove", _element_remove, "remove an element: id_panel, id_element")
	register("ui_press", _press_command, "press a button or toggle, as if pointed at and clicked: id_panel, id_element")
	register("ui_slide", _slide_command, "set a slider and run its action: id_panel, id_element, value")
	register("ui_type", _type_command, "type text into the selected input box: text")
	register("ui_key", _key_command, "a key for the selected input box: key (shift, backspace, clear)")
	register("ui_reset", _reset, "put the default panels back: optional id_panel for just that one")
	register("ui_theme_status", _theme_status, "the theme every panel draws with: colours by name and text sizes")
	register("ui_config", _config, "from the PC only: theme {name: #rrggbb or a text size}, or reset true")

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -LASER_LENGTH)
	_ray.collision_mask = UI_LAYER
	_ray.collide_with_areas = false
	_right.add_child(_ray)

	_laser = MeshInstance3D.new()
	var laser_mesh := BoxMesh.new()
	laser_mesh.size = Vector3(0.0015, 0.0015, 1.0)
	_laser.mesh = laser_mesh
	_laser.material_override = _flat_material(_theme_color("laser"))
	_right.add_child(_laser)

	# Where the pointer touches a panel: a small dot just in front of it.
	_cursor = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.004
	dot.height = 0.008
	dot.radial_segments = 8
	dot.rings = 4
	_cursor.mesh = dot
	_cursor.material_override = _flat_material(_theme_color("cursor"))
	_cursor.visible = false
	add_child(_cursor)

	_load()
	for panel in panels:
		# Panels that open in front of you start hidden: at start-up the
		# headset's position isn't known yet.
		if panel["place"] in ["front", "follow"]:
			panel["visible"] = false
		_build(panel["id_panel"])
	_focus_first_input()
	return ""


# The wrist panel, laser and ray hang off the controllers, not this node, so
# they are removed by hand when the module goes.
func _exit_tree() -> void:
	for node in _holders.values() + [_ray, _laser]:
		if node and is_instance_valid(node):
			node.queue_free()


func _physics_process(_delta: float) -> void:
	if not _dragging.is_empty() and _holders.has(_dragging):
		_holders[_dragging].global_transform = _right.global_transform * _drag_offset
	_ray.enabled = not pointer_blocked
	var hit: StaticBody3D = _ray.get_collider() as StaticBody3D if _ray.enabled and _ray.is_colliding() else null
	if hit != _hovered:
		_set_hover(_hovered, false)
		_hovered = hit
		_set_hover(_hovered, true)
	if pointer_blocked:
		_laser.visible = false  # the question draws its own
		_cursor.visible = false
		return
	if not _sliding.is_empty():
		_slide_follow()
	var length := LASER_LENGTH
	if _hovered:
		var point := _ray.get_collision_point()
		length = _right.global_position.distance_to(point)
		_cursor.global_position = point + _ray.get_collision_normal() * 0.002
	_cursor.visible = _hovered != null
	# Only show the laser while a panel is out that it can point at.
	_laser.visible = _hovered != null or _any_open()
	_laser.scale = Vector3(1, 1, length)
	_laser.position = Vector3(0, 0, -length / 2.0)


func _process(delta: float) -> void:
	_follow(delta)
	_since_apps += delta
	if _since_apps >= APPS_SECONDS:
		_since_apps = 0.0
		_scan_apps()
	_since_poll += delta
	if _since_poll < POLL_SECONDS:
		return
	_since_poll = 0.0
	for panel in panels:
		if not panel["visible"]:
			continue
		for element in panel["elements"]:
			if element["type"] == "text" and element.has("source"):
				var label := _find_node(panel["id_panel"], element["id"]) as Label3D
				if label:
					label.text = _read_source(element)


func _any_open() -> bool:
	for panel in panels:
		if panel["visible"] and panel["place"] != "wrist":
			return true
	return false


# A follow panel stays where it is while you look around, and catches up
# (easing, never snapping) once you've turned or walked away from it, so it's
# always near but never stuck to your face.
func _follow(delta: float) -> void:
	for panel in panels:
		if panel["place"] != "follow" or not panel["visible"] or panel["id_panel"] == _dragging:
			continue
		var id_panel: String = panel["id_panel"]
		var holder: Node3D = _holders[id_panel]
		var wanted := _front_transform(panel)
		if not _following.has(id_panel):
			var to_panel := holder.global_position - _camera.global_position
			to_panel.y = 0.0
			var ahead := wanted.origin - _camera.global_position
			ahead.y = 0.0
			var angle := rad_to_deg(to_panel.angle_to(ahead)) if to_panel.length() > 0.01 and ahead.length() > 0.01 else 0.0
			if angle < FOLLOW_ANGLE and holder.global_position.distance_to(wanted.origin) < FOLLOW_DISTANCE:
				continue
		_following[id_panel] = wanted
		var weight := clampf(delta * FOLLOW_SPEED, 0.0, 1.0)
		holder.global_transform = holder.global_transform.interpolate_with(wanted, weight)
		if holder.global_position.distance_to(wanted.origin) < 0.01:
			holder.global_transform = wanted
			_following.erase(id_panel)


# --- Controllers ---------------------------------------------------------------

# Asked first by the controls module: pointing at a panel, the trigger and
# grip are the panel's, not a tool's or a grab's.
func action_order() -> int:
	return 0


func on_action(action: String, down: bool) -> bool:
	match action:
		"point":
			if down and _hovered:
				_on_point_pressed()
				return true
			if not down:
				# This module took the press, so the release is its too.
				if not _sliding.is_empty():
					_end_slide()
				_end_drag()
				return true
			return false
		"grab_right":
			if down:
				return _start_drag()
			_end_drag()
			return true
	if not down:
		return false
	var toggled := false
	for panel in panels:
		if panel["toggle"] == action:
			_set_visible(panel, not panel["visible"])
			print("Slopitect ui: \"%s\" %s" % [panel["id_panel"], "shown" if panel["visible"] else "hidden"])
			toggled = true
	return toggled


func _end_drag() -> void:
	if _dragging.is_empty():
		return
	var index := _index_of(_dragging)
	_dragging = ""
	if index == -1:
		return
	# Where you let go is where it stays: it's now a panel in the world.
	var panel: Dictionary = panels[index]
	var holder: Node3D = _holders[panel["id_panel"]]
	var p := holder.global_position
	var r := holder.global_rotation_degrees
	panel["place"] = "world"
	panel["position"] = [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]
	panel["rotation"] = [snappedf(r.x, 0.1), snappedf(r.y, 0.1), snappedf(r.z, 0.1)]
	_following.erase(panel["id_panel"])
	_save()
	print("Slopitect ui: moved \"%s\" to %s" % [panel["id_panel"], panel["position"]])


func _start_drag() -> bool:
	if not _hovered:
		return false
	var id_panel: String = _hovered.get_meta("panel")
	var index := _index_of(id_panel)
	if index == -1 or panels[index]["place"] == "wrist":
		return true  # the wrist panel moves with your wrist; the grip is still the panel's
	_dragging = id_panel
	_drag_offset = _right.global_transform.affine_inverse() * _holders[id_panel].global_transform
	_pulse(0.3, 0.03)
	return true


func _on_point_pressed() -> void:
	if not _hovered:
		return
	var id_panel: String = _hovered.get_meta("panel")
	var index := _index_of(id_panel)
	if index == -1:
		return
	match _hovered.get_meta("kind", "element"):
		"title":
			_start_drag()
			return
		"close":
			_pulse(0.4, 0.04)
			_set_visible(panels[index], false)
			return
		"tab":
			_pulse(0.4, 0.04)
			_set_page(panels[index], _hovered.get_meta("value"))
			return
		"app":
			_pulse(0.4, 0.04)
			_flash(_hovered)
			_open_app(id_panel, _hovered.get_meta("value"))
			return
		"back":
			return
	var id_element: String = _hovered.get_meta("element")
	var element := _element(id_panel, id_element)
	if element.is_empty():
		return
	match element["type"]:
		"input":
			_pulse(0.2, 0.02)
			_set_focus(id_panel + "/" + id_element)
		"button", "toggle":
			_pulse(0.4, 0.04)
			_flash(_hovered)
			press(id_panel, id_element)
		"slider":
			_pulse(0.2, 0.02)
			_sliding = id_panel + "/" + id_element
			_slide_value = float(element["value"])
			_slide_follow()


func _set_visible(panel: Dictionary, on: bool) -> void:
	if on and panel["place"] in ["front", "follow"]:
		_holders[panel["id_panel"]].global_transform = _front_transform(panel)
		_following.erase(panel["id_panel"])
	panel["visible"] = on
	_holders[panel["id_panel"]].visible = on
	_set_pointable(_holders[panel["id_panel"]], on)
	if on:
		_since_poll = POLL_SECONDS
		if _focus.is_empty() or not _element_visible(_focus):
			_focus_first_input(panel["id_panel"])
	if not panel["place"] in ["front", "follow"]:
		_save()  # panels that open in front always start hidden, so aren't saved for this


# In front of you, at the panel's distance and height, facing your eyes and
# tipped back towards them when it sits below eye level.
func _front_transform(panel: Dictionary) -> Transform3D:
	var head := _camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var at: Vector3 = head.origin + forward * panel["distance"] + Vector3(0, panel["height"], 0)
	return Transform3D(Basis.looking_at(head.origin - at, Vector3.UP, true), at)


# A point 1 m in front of you at chest height, in World coordinates.
func _in_front() -> Array:
	var head := _camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var p := head.origin + forward * 1.0 + Vector3(0, -0.3, 0)
	return [p.x, p.y, p.z]


# A short tick on the right controller, through the controls module (the one
# place that talks to the controllers); nothing if it isn't loaded.
func _pulse(strength: float, seconds: float) -> void:
	var controls: SlopitectModule = ctx["modules"].module("controls")
	if controls and controls.has_method("pulse"):
		controls.call("pulse", "right", strength, seconds)


# --- Pressing and typing ---------------------------------------------------------

# Runs a button's action as if it came through the command server. A failure
# shows under the panel for a few seconds, so you see it in the headset.
# A toggle runs its action with "{on}" as what it's switching to, and
# switches only if that works.
func press(id_panel: String, id_element: String) -> Dictionary:
	var element := _element(id_panel, id_element)
	if element.is_empty() or not element["type"] in ["button", "toggle"]:
		return {"ok": false, "error": "no button or toggle \"%s\" on panel \"%s\" (ui_get shows its elements)" % [id_element, id_panel]}
	var fill := {}
	if element["type"] == "toggle":
		fill["{on}"] = not element["on"]
	return _run_element(id_panel, element, fill)


func _run_element(id_panel: String, element: Dictionary, fill: Dictionary) -> Dictionary:
	var action = _fill_action(element["action"].duplicate(true), id_panel, fill)
	print("Slopitect ui: pressed \"%s/%s\"" % [id_panel, element["id"]])
	var reply: Dictionary = _server.run(action)
	if reply.get("wait") is SlopitectPending:
		# It waits for your answer in the headset; this button's follow-up
		# (clearing its input, showing a failure) happens when it's given.
		_notice(id_panel, "%s: waiting for your answer" % element["label"])
		_after_press(id_panel, element, fill, reply["wait"])
		return reply
	_pressed(id_panel, element, fill, reply)
	return reply


func _after_press(id_panel: String, element: Dictionary, fill: Dictionary, pending: SlopitectPending) -> void:
	if not pending.finished:
		await pending.done
	_notice(id_panel, "")
	_pressed(id_panel, element, fill, pending.result)


func _pressed(id_panel: String, element: Dictionary, fill: Dictionary, reply: Dictionary) -> void:
	var id_element: String = element["id"]
	if reply.get("ok", false):
		if element.has("clear_input"):
			_inputs[id_panel + "/" + element["clear_input"]] = ""
			_show_input(id_panel, element["clear_input"])
		if element["type"] == "toggle":
			element["on"] = fill["{on}"]
			_save()
			_show_state(id_panel, element)
		elif element["type"] == "slider":
			element["value"] = fill["{value}"]
			_save()
			_show_state(id_panel, element)
	else:
		var error := String(reply.get("error", "?"))
		print("Slopitect ui: \"%s/%s\" failed: %s" % [id_panel, id_element, error])
		_notice(id_panel, "%s: %s" % [element["label"], error])
		if element["type"] == "slider":
			_show_state(id_panel, element)  # back to the value it has


# "in_front" as a position, "{input:ID}" for what's typed in box ID, and the
# placeholders in `fill` ("{on}" for a toggle, "{value}" for a slider).
func _fill_action(value, id_panel: String, fill := {}):
	if value is Dictionary:
		for key in value:
			if key == "position" and value[key] is String and value[key] == "in_front":
				value[key] = _in_front()
			else:
				value[key] = _fill_action(value[key], id_panel, fill)
	elif value is Array:
		for i in value.size():
			value[i] = _fill_action(value[i], id_panel, fill)
	elif value is String and fill.has(value):
		return fill[value]
	elif value is String and value.begins_with("{input:") and value.ends_with("}"):
		return _inputs.get(id_panel + "/" + value.trim_prefix("{input:").trim_suffix("}"), "")
	return value


# Changes what a text element shows, at once and without redrawing or saving
# the panel: for windows that change many times a second (a terminal's
# screen). The text isn't saved, since it can be anything a command replied;
# a redraw keeps it. Returns false when there's no such text element.
func set_text(id_panel: String, id_element: String, text: String) -> bool:
	var element := _element(id_panel, id_element)
	if element.is_empty() or element["type"] != "text":
		return false
	_live_text[id_panel + "/" + id_element] = text.left(MAX_TEXT)
	var label := _find_node(id_panel, id_element) as Label3D
	if label:
		label.text = _live_text[id_panel + "/" + id_element]
	return true


# The theme, with the PC's changes: {name: Color or text size}.
func theme() -> Dictionary:
	return theme_values.duplicate()


# --- Sliders ------------------------------------------------------------------------

# While the trigger holds a slider, its knob follows where you point along it
# (even a little off it); the action runs once, when you let go.
func _slide_follow() -> void:
	var parts := _sliding.split("/")
	var element := _element(parts[0], parts[1])
	var node := _find_node(parts[0], parts[1]) as Node3D
	if element.is_empty() or node == null:
		_sliding = ""
		return
	var plane := Plane(node.global_basis.z.normalized(), node.global_position)
	var from := _right.global_position
	var hit = plane.intersects_ray(from, -_right.global_basis.z)
	if hit == null:
		return
	var local: Vector3 = node.global_transform.affine_inverse() * hit
	var width: float = element["size"][0]
	var t := clampf(local.x / width + 0.5, 0.0, 1.0)
	_slide_value = _snap_value(element, lerpf(element["min"], element["max"], t))
	_show_slider(node, element, _slide_value)


func _end_slide() -> void:
	var parts := _sliding.split("/")
	_sliding = ""
	var element := _element(parts[0], parts[1])
	if element.is_empty():
		return
	_pulse(0.3, 0.03)
	_run_element(parts[0], element, {"{value}": _slide_value})


func _snap_value(element: Dictionary, value: float) -> float:
	var step: float = element["step"]
	if step > 0.0:
		value = element["min"] + roundf((value - element["min"]) / step) * step
	return clampf(value, element["min"], element["max"])


func _slide_command(request: Dictionary) -> Dictionary:
	var id_panel := str(request.get("id_panel"))
	var element := _element(id_panel, str(request.get("id_element")))
	if element.is_empty() or element["type"] != "slider":
		return {"ok": false, "error": "no slider \"%s\" on panel \"%s\" (ui_get shows its elements)" % [str(request.get("id_element")), id_panel]}
	var value = request.get("value")
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return {"ok": false, "error": "ui_slide needs \"value\", a number from %s to %s" % [element["min"], element["max"]]}
	return _run_element(id_panel, element, {"{value}": _snap_value(element, float(value))})


# --- Pages ------------------------------------------------------------------------

func _set_page(panel: Dictionary, page: String) -> void:
	if panel["page"] == page:
		return
	panel["page"] = page
	_save()
	_build(panel["id_panel"])


func _page_command(request: Dictionary) -> Dictionary:
	var index := _index_of(str(request.get("id_panel")))
	if index == -1:
		return {"ok": false, "error": "no panel \"%s\" (ui_list shows them)" % str(request.get("id_panel"))}
	var panel: Dictionary = panels[index]
	if not request.get("page") in panel["pages"]:
		return {"ok": false, "error": "panel \"%s\" has the pages %s" % [panel["id_panel"], panel["pages"]]}
	_set_page(panel, request["page"])
	return {"ok": true, "page": panel["page"]}


# --- The launcher -------------------------------------------------------------------

# Any loaded module with menu_info() gets a tile on every panel with "apps"
# (the Menu bar). menu_info() returns {"id", "label", "order" (lower first,
# 100 by default), and "panel": the id_panel it shows and hides, or
# "action": a command to run}. Tiles come and go with their modules.
func _scan_apps() -> void:
	var found := []
	for panel in panels:
		if not panel["menu"].is_empty():
			found.append({"id": "panel_" + panel["id_panel"], "label": panel["menu"], "order": 50, "panel": panel["id_panel"], "action": {}})
	for child in ctx["modules"].get_children():
		if child == self or not child.has_method("menu_info"):
			continue
		var info = child.call("menu_info")
		var problem := _check_app(info)
		if not problem.is_empty():
			push_error("Slopitect ui: %s's menu_info() %s" % [child.name, problem])
			continue
		found.append({"id": info["id"], "label": info["label"], "order": int(info.get("order", 100)),
			"panel": info.get("panel", ""), "action": info.get("action", {})})
	found.sort_custom(func(x, y): return [x["order"], x["label"]] < [y["order"], y["label"]])
	# A tile is lit while its window is open, so that's part of what's drawn.
	var open := []
	for app in found:
		var index := _index_of(app["panel"]) if not app["panel"].is_empty() else -1
		open.append(index != -1 and panels[index]["visible"])
	var signature := JSON.stringify([found, open])
	if signature == _apps_signature:
		return
	_apps_signature = signature
	_apps = found
	for panel in panels:
		if panel["apps"]:
			_build(panel["id_panel"])


func _check_app(info) -> String:
	if typeof(info) != TYPE_DICTIONARY or not _good_id(info.get("id")):
		return "needs \"id\", a name of letters, digits and _"
	if typeof(info.get("label")) != TYPE_STRING or info["label"].is_empty() or info["label"].length() > 24:
		return "needs \"label\", text of 1 to 24 characters"
	if info.has("order") and typeof(info["order"]) not in [TYPE_INT, TYPE_FLOAT]:
		return "\"order\" must be a number"
	if info.has("panel") == info.has("action"):
		return "needs one of \"panel\" (an id_panel to show and hide) or \"action\" (a command)"
	if info.has("panel") and not _good_id(info["panel"]):
		return "\"panel\" must be an id_panel"
	if info.has("action"):
		return _check_action(info["action"], true)
	return ""


# A tile shows (or hides) its panel, or runs its command. Opening something
# closes the launcher, so it isn't left floating in front of what opened.
func _open_app(launcher: String, id_app: String) -> void:
	for app in _apps:
		if app["id"] != id_app:
			continue
		if not app["panel"].is_empty():
			var index := _index_of(app["panel"])
			if index == -1:
				_notice(launcher, "%s: its window isn't there yet" % app["label"])
				return
			var opening: bool = not panels[index]["visible"]
			_set_visible(panels[index], opening)
			if not opening:
				return
		else:
			var reply: Dictionary = _server.run(_fill_action(app["action"].duplicate(true), launcher))
			if not reply.get("ok", false) and not reply.get("wait") is SlopitectPending:
				_notice(launcher, "%s: %s" % [app["label"], reply.get("error", "?")])
				return
		var index := _index_of(launcher)
		if index != -1 and panels[index]["place"] in ["front", "follow"]:
			_set_visible(panels[index], false)
		return


func _type_command(request: Dictionary) -> Dictionary:
	var text = request.get("text")
	if typeof(text) != TYPE_STRING or text.is_empty():
		return {"ok": false, "error": "ui_type needs \"text\""}
	if _focus.is_empty():
		return {"ok": false, "error": "no input box is selected (point at one and pull the trigger)"}
	if _shift:
		text = text.left(1).to_upper() + text.substr(1)
		_shift = false
	var typed: String = _inputs.get(_focus, "") + text
	_inputs[_focus] = typed.left(_max_length(_focus))
	_show_focus()
	return {"ok": true}


func _key_command(request: Dictionary) -> Dictionary:
	if _focus.is_empty():
		return {"ok": false, "error": "no input box is selected (point at one and pull the trigger)"}
	match request.get("key"):
		"shift":
			_shift = not _shift
		"backspace":
			_inputs[_focus] = String(_inputs.get(_focus, "")).left(-1)
		"clear":
			_inputs[_focus] = ""
		_:
			return {"ok": false, "error": "\"key\" must be shift, backspace or clear"}
	_show_focus()
	return {"ok": true}


# Changes a text element's text live, for a module that updates often (the
# terminal's screen, on every key): only the label changes, the panel isn't
# redrawn or saved. The text is kept in memory (never in ui.json, since it
# can be anything a command replied), so a later redraw still shows it.
func set_text(id_panel: String, id_element: String, text: String) -> bool:
	var element := _element(id_panel, id_element)
	if element.get("type") != "text" or element.has("source"):
		return false
	_live_text[id_panel + "/" + id_element] = text.left(MAX_TEXT)
	var label := _find_node(id_panel, id_element) as Label3D
	if label:
		label.text = _live_text[id_panel + "/" + id_element]
	return true


func _max_length(key: String) -> int:
	var parts := key.split("/")
	var element := _element(parts[0], parts[1])
	return int(element.get("max_length", MAX_INPUT))


func _set_focus(key: String) -> void:
	var before := _focus
	_focus = key
	for k in [before, key]:
		if not k.is_empty():
			var parts: PackedStringArray = k.split("/")
			_show_input(parts[0], parts[1])


func _show_focus() -> void:
	if not _focus.is_empty():
		var parts := _focus.split("/")
		_show_input(parts[0], parts[1])


# Picks the first input box of a panel (or of any shown panel) to type into.
func _focus_first_input(only_panel := "") -> void:
	for panel in panels:
		if (only_panel.is_empty() and not panel["visible"]) or (not only_panel.is_empty() and panel["id_panel"] != only_panel):
			continue
		for element in panel["elements"]:
			if element["type"] == "input":
				_set_focus(panel["id_panel"] + "/" + element["id"])
				return


func _element_visible(key: String) -> bool:
	var parts := key.split("/")
	var index := _index_of(parts[0])
	return index != -1 and panels[index]["visible"] and not _element(parts[0], parts[1]).is_empty()


# --- Live values -------------------------------------------------------------------

func _read_source(element: Dictionary) -> String:
	var source: Dictionary = element["source"]
	var reply: Dictionary = _server.run({"cmd": source["cmd"]})
	if not reply.get("ok", false):
		return "(%s isn't available: %s)" % [source["cmd"], reply.get("error", "?")]
	var value = reply if not source.has("field") else reply.get(source["field"])
	# A module can lay the value out itself (aimsg formats the chat log);
	# without it, the value shows as it is.
	var formatter: SlopitectModule = ctx["modules"].module(source["format"]) if source.has("format") else null
	if formatter and formatter.has_method("format"):
		var formatted = formatter.call("format", value, source)
		if formatted is String or formatted is Array:
			value = formatted
	var chars := int(source.get("chars", 200))
	var text := ""
	if value is Array:
		var lines := PackedStringArray()
		for item in value.slice(-int(source.get("last", 12))):
			var line: String = (item if item is String else JSON.stringify(item)).replace("\n", " ")
			lines.append(line.left(chars) + ("..." if line.length() > chars else ""))
		text = "\n".join(lines)
	elif value is String:
		text = value
	elif value != null:
		text = JSON.stringify(value)
	if text.is_empty():
		text = source.get("empty", "")
	return text.left(MAX_TEXT)


# --- Commands, registered with the command server ---------------------------------

func _list(_request: Dictionary) -> Dictionary:
	var list := []
	for panel in panels:
		list.append({
			"id_panel": panel["id_panel"], "title": panel["title"], "place": panel["place"],
			"visible": panel["visible"], "toggle": panel["toggle"], "elements": panel["elements"].size(),
		})
	return {"ok": true, "panels": list}


func _get_panel(request: Dictionary) -> Dictionary:
	var index := _index_of(str(request.get("id_panel")))
	if index == -1:
		return {"ok": false, "error": "no panel \"%s\" (ui_list shows them)" % str(request.get("id_panel"))}
	var panel: Dictionary = panels[index].duplicate(true)
	for element in panel["elements"]:
		if element["type"] == "input":
			element["value"] = _inputs.get(panel["id_panel"] + "/" + element["id"], "")
	return {"ok": true, "panel": panel}


func _add(request: Dictionary) -> Dictionary:
	if panels.size() >= MAX_PANELS:
		return {"ok": false, "error": "there are already %d panels, the most allowed" % MAX_PANELS}
	var data := request.duplicate(true)
	data.erase("cmd")
	data.erase("id")
	var checked := _check_panel(data, true, true)
	if checked.has("error"):
		return {"ok": false, "error": checked["error"]}
	panels.append(checked["panel"])
	return _changed(checked["panel"]["id_panel"], {"ok": true, "panel": checked["panel"]})


func _update(request: Dictionary) -> Dictionary:
	var index := _index_of(str(request.get("id_panel")))
	if index == -1:
		return {"ok": false, "error": "no panel \"%s\" (ui_list shows them)" % str(request.get("id_panel"))}
	var merged: Dictionary = panels[index].duplicate(true)
	for key in request:
		if not key in ["cmd", "id", "id_panel"]:
			merged[key] = request[key]
	var checked := _check_panel(merged, false, true)
	if checked.has("error"):
		return {"ok": false, "error": checked["error"]}
	panels[index] = checked["panel"]
	return _changed(merged["id_panel"], {"ok": true, "panel": checked["panel"]})


func _remove(request: Dictionary) -> Dictionary:
	var index := _index_of(str(request.get("id_panel")))
	if index == -1:
		return {"ok": false, "error": "no panel \"%s\" (ui_list shows them)" % str(request.get("id_panel"))}
	var removed: Dictionary = panels.pop_at(index)
	_drop_holder(removed["id_panel"])
	for key in _live_text.keys():
		if key.begins_with(removed["id_panel"] + "/"):
			_live_text.erase(key)
	if _focus.begins_with(removed["id_panel"] + "/"):
		_focus = ""
	for key in _live_text.keys():
		if key.begins_with(removed["id_panel"] + "/"):
			_live_text.erase(key)
	_following.erase(removed["id_panel"])
	_save()
	return {"ok": true, "removed": removed["id_panel"]}


func _show(request: Dictionary) -> Dictionary:
	var index := _index_of(str(request.get("id_panel")))
	if index == -1:
		return {"ok": false, "error": "no panel \"%s\" (ui_list shows them)" % str(request.get("id_panel"))}
	var visible = request.get("visible")
	if typeof(visible) != TYPE_BOOL:
		return {"ok": false, "error": "ui_show needs \"visible\": true or false"}
	_set_visible(panels[index], visible)
	return {"ok": true, "visible": visible}


func _element_add(request: Dictionary) -> Dictionary:
	var index := _index_of(str(request.get("id_panel")))
	if index == -1:
		return {"ok": false, "error": "no panel \"%s\" (ui_list shows them)" % str(request.get("id_panel"))}
	if typeof(request.get("element")) != TYPE_DICTIONARY:
		return {"ok": false, "error": "ui_element_add needs \"element\", like {\"type\": \"button\", \"id\": \"go\", \"label\": \"Go\", \"action\": {\"cmd\": \"list\"}}"}
	var merged: Dictionary = panels[index].duplicate(true)
	var at = request.get("index", merged["elements"].size())
	if typeof(at) != TYPE_FLOAT and typeof(at) != TYPE_INT or int(at) < 0 or int(at) > merged["elements"].size():
		return {"ok": false, "error": "\"index\" must be 0 to %d" % merged["elements"].size()}
	merged["elements"].insert(int(at), request["element"])
	var checked := _check_panel(merged, false, true)
	if checked.has("error"):
		return {"ok": false, "error": checked["error"]}
	panels[index] = checked["panel"]
	return _changed(merged["id_panel"], {"ok": true, "element": checked["panel"]["elements"][int(at)]})


func _element_update(request: Dictionary) -> Dictionary:
	var index := _index_of(str(request.get("id_panel")))
	if index == -1:
		return {"ok": false, "error": "no panel \"%s\" (ui_list shows them)" % str(request.get("id_panel"))}
	var merged: Dictionary = panels[index].duplicate(true)
	var at := _element_index(merged, str(request.get("id_element")))
	if at == -1:
		return {"ok": false, "error": "no element \"%s\" on panel \"%s\" (ui_get shows them)" % [str(request.get("id_element")), merged["id_panel"]]}
	for key in request:
		if not key in ["cmd", "id", "id_panel", "id_element"]:
			if request[key] == null:
				merged["elements"][at].erase(key)  # null takes an optional field off
			else:
				merged["elements"][at][key] = request[key]
	var checked := _check_panel(merged, false, true)
	if checked.has("error"):
		return {"ok": false, "error": checked["error"]}
	panels[index] = checked["panel"]
	return _changed(merged["id_panel"], {"ok": true, "element": checked["panel"]["elements"][at]})


func _element_remove(request: Dictionary) -> Dictionary:
	var index := _index_of(str(request.get("id_panel")))
	if index == -1:
		return {"ok": false, "error": "no panel \"%s\" (ui_list shows them)" % str(request.get("id_panel"))}
	var at := _element_index(panels[index], str(request.get("id_element")))
	if at == -1:
		return {"ok": false, "error": "no element \"%s\" on panel \"%s\" (ui_get shows them)" % [str(request.get("id_element")), panels[index]["id_panel"]]}
	var removed: Dictionary = panels[index]["elements"].pop_at(at)
	return _changed(panels[index]["id_panel"], {"ok": true, "removed": removed["id"]})


func _press_command(request: Dictionary) -> Dictionary:
	return press(str(request.get("id_panel")), str(request.get("id_element")))


func _reset(request: Dictionary) -> Dictionary:
	var defaults := _checked_defaults()
	if not request.has("id_panel"):
		for panel in panels:
			_drop_holder(panel["id_panel"])
		panels = defaults
		_focus = ""
		for panel in panels:
			_build(panel["id_panel"])
		_save()
		return {"ok": true, "panels": panels.size()}
	var id_panel := str(request["id_panel"])
	for panel in defaults:
		if panel["id_panel"] == id_panel:
			var index := _index_of(id_panel)
			if index == -1:
				panels.append(panel)
			else:
				panels[index] = panel
			return _changed(id_panel, {"ok": true, "panel": panel})
	return {"ok": false, "error": "\"%s\" isn't one of the default panels (%s)" % [id_panel, ", ".join(defaults.map(func(p): return p["id_panel"]))]}


func _theme_status(_request: Dictionary) -> Dictionary:
	var out := {}
	for key in theme_values:
		out[key] = theme_values[key] if key in THEME_FONTS else "#" + (theme_values[key] as Color).to_html(false)
	return {"ok": true, "theme": out, "names": DEFAULT_THEME.keys()}


# The theme changes from the PC only: every panel is drawn again with it.
func _config(request: Dictionary) -> Dictionary:
	var saved := {}
	if request.get("reset", false) != true:
		saved = _read_config()
		var asked = request.get("theme", {})
		if typeof(asked) != TYPE_DICTIONARY:
			return {"ok": false, "error": "\"theme\" must be {name: #rrggbb, or a text size for %s}" % ", ".join(THEME_FONTS)}
		for key in asked:
			var problem := _check_theme_value(key, asked[key])
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			saved[key] = asked[key]
	var out := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if out == null:
		return {"ok": false, "error": "couldn't save %s (%s)" % [CONFIG_PATH, error_string(FileAccess.get_open_error())]}
	out.store_string(JSON.stringify({"theme": saved}, "\t"))
	out.close()
	_load_config()
	_laser.material_override = _flat_material(_theme_color("laser"))
	_cursor.material_override = _flat_material(_theme_color("cursor"))
	for panel in panels:
		_build(panel["id_panel"])
	return _theme_status({})


func _check_theme_value(key, value) -> String:
	if not key in DEFAULT_THEME:
		return "%s isn't a theme name; they are %s" % [JSON.stringify(key), ", ".join(DEFAULT_THEME.keys())]
	if key in THEME_FONTS:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < 16 or value > 80:
			return "%s is a text size, 16 to 80" % key
	elif typeof(value) != TYPE_STRING or not Color.html_is_valid(value):
		return "%s must be a colour, #rrggbb" % key
	return ""


func _read_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var saved = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if typeof(saved) != TYPE_DICTIONARY or typeof(saved.get("theme")) != TYPE_DICTIONARY:
		push_error("Slopitect ui: %s isn't readable; using the default theme" % CONFIG_PATH)
		return {}
	return saved["theme"]


func _load_config() -> void:
	var saved := _read_config()
	theme_values = {}
	for key in DEFAULT_THEME:
		var value = DEFAULT_THEME[key]
		if saved.has(key):
			if _check_theme_value(key, saved[key]).is_empty():
				value = saved[key]
			else:
				push_error("Slopitect ui: %s has a bad %s; using the default" % [CONFIG_PATH, key])
		theme_values[key] = int(value) if key in THEME_FONTS else Color.html(value)


func _changed(id_panel: String, reply: Dictionary) -> Dictionary:
	_save()
	_build(id_panel)
	return reply


# --- Checking -----------------------------------------------------------------------

# Checks a whole panel before anything changes, and fills in the defaults.
# `check_actions` also checks that each button's command exists; it's off
# when loading, since modules that load after this one add their commands
# later.
func _check_panel(data: Dictionary, is_new: bool, check_actions: bool) -> Dictionary:
	var id = data.get("id_panel")
	if not _good_id(id):
		return {"error": "\"id_panel\" must be a name of 1 to 40 letters, digits and _"}
	if is_new and _index_of(id) != -1:
		return {"error": "a panel \"%s\" already exists" % id}
	var panel := {"id_panel": id}
	for key in data:
		if not key in ["id_panel", "title", "place", "distance", "height", "position", "rotation", "size", "color", "visible", "toggle", "layout", "columns", "cell", "elements", "chrome", "pages", "page", "apps", "menu"]:
			return {"error": "panel %s: unknown field \"%s\"" % [id, key]}
	panel["title"] = data.get("title", id)
	if typeof(panel["title"]) != TYPE_STRING or panel["title"].length() > 60:
		return {"error": "panel %s: \"title\" must be text of up to 60 characters" % id}
	panel["place"] = data.get("place", "front")
	if not panel["place"] in PLACES:
		return {"error": "panel %s: \"place\" must be one of %s" % [id, PLACES]}
	for key in [["distance", 0.6, 0.2, 3.0], ["height", -0.25, -1.5, 1.0]]:
		var value = data.get(key[0], key[1])
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < key[2] or value > key[3]:
			return {"error": "panel %s: \"%s\" must be a number from %s to %s (metres)" % [id, key[0], key[2], key[3]]}
		panel[key[0]] = float(value)
	for key in [["position", [0, 1.4, -1], 20.0], ["rotation", [0, 0, 0], 360.0]]:
		var value = data.get(key[0], key[1])
		if not _numbers(value, 3, -key[2], key[2]):
			return {"error": "panel %s: \"%s\" must be [x, y, z], each from %s to %s" % [id, key[0], -key[2], key[2]]}
		panel[key[0]] = value
	if data.has("size"):
		if not _numbers(data["size"], 2, 0.01, 3.0):
			return {"error": "panel %s: \"size\" (its background) must be [width, height] in metres, 0.01 to 3" % id}
		panel["size"] = data["size"]
	if data.has("color") and data["color"] != OLD_PANEL_COLOR:
		if not _good_color(data["color"]):
			return {"error": "panel %s: \"color\" must be a theme name, a colour name or #rrggbb" % id}
		panel["color"] = data["color"]
	for key in ["chrome", "apps"]:
		panel[key] = data.get(key, false)
		if typeof(panel[key]) != TYPE_BOOL:
			return {"error": "panel %s: \"%s\" must be true or false" % [id, key]}
	if panel["chrome"] and not panel.has("size"):
		return {"error": "panel %s: a panel with \"chrome\" needs a \"size\" [width, height] for its background" % id}
	panel["menu"] = data.get("menu", "")
	if typeof(panel["menu"]) != TYPE_STRING or panel["menu"].length() > 24:
		return {"error": "panel %s: \"menu\" must be the label of its tile on the Menu (up to 24 characters), or \"\" for none" % id}
	panel["pages"] = data.get("pages", [])
	if typeof(panel["pages"]) != TYPE_ARRAY or panel["pages"].size() > MAX_PAGES \
			or panel["pages"].any(func(n): return typeof(n) != TYPE_STRING or n.is_empty() or n.length() > 20):
		return {"error": "panel %s: \"pages\" must be a list of up to %d tab names, each 1 to 20 characters" % [id, MAX_PAGES]}
	if not panel["pages"].is_empty() and not panel["chrome"]:
		return {"error": "panel %s: \"pages\" needs \"chrome\": true (the tabs sit under the title)" % id}
	panel["page"] = data.get("page", panel["pages"][0] if not panel["pages"].is_empty() else "")
	if not panel["pages"].is_empty() and not panel["page"] in panel["pages"]:
		return {"error": "panel %s: \"page\" must be one of its pages %s" % [id, panel["pages"]]}
	panel["visible"] = data.get("visible", false)
	if typeof(panel["visible"]) != TYPE_BOOL:
		return {"error": "panel %s: \"visible\" must be true or false" % id}
	panel["toggle"] = data.get("toggle", "")
	if not (panel["toggle"] == "" or _good_id(panel["toggle"])):
		return {"error": "panel %s: \"toggle\" must be an action's name (controls_status lists them), or \"\" for none" % id}
	panel["layout"] = data.get("layout", "free")
	if not panel["layout"] in LAYOUTS:
		return {"error": "panel %s: \"layout\" must be free (each element at its \"at\") or grid (buttons in rows)" % id}
	if panel["layout"] == "grid":
		var columns = data.get("columns", 4)
		if typeof(columns) not in [TYPE_INT, TYPE_FLOAT] or columns < 1 or columns > 20:
			return {"error": "panel %s: \"columns\" must be 1 to 20" % id}
		panel["columns"] = int(columns)
		var cell = data.get("cell", [0.14, 0.07])
		if not _numbers(cell, 2, 0.01, 1.0):
			return {"error": "panel %s: \"cell\" must be [width, height] of each button in metres, 0.01 to 1" % id}
		panel["cell"] = cell
	var elements = data.get("elements", [])
	if typeof(elements) != TYPE_ARRAY or elements.size() > MAX_ELEMENTS:
		return {"error": "panel %s: \"elements\" must be a list of up to %d elements" % [id, MAX_ELEMENTS]}
	panel["elements"] = []
	var seen := {}
	for item in elements:
		if typeof(item) != TYPE_DICTIONARY:
			return {"error": "panel %s: an element isn't an object: %s" % [id, JSON.stringify(item)]}
		var checked := _check_element(item, panel, check_actions)
		if checked.has("error"):
			return {"error": "panel %s, element %s: %s" % [id, JSON.stringify(item.get("id")), checked["error"]]}
		if checked["element"].has("page") and not checked["element"]["page"] in panel["pages"]:
			return {"error": "panel %s, element %s: \"page\" must be one of the panel's pages %s" % [id, checked["element"]["id"], panel["pages"]]}
		if seen.has(checked["element"]["id"]):
			return {"error": "panel %s: two elements are called \"%s\"" % [id, checked["element"]["id"]]}
		seen[checked["element"]["id"]] = true
		panel["elements"].append(checked["element"])
	return {"panel": panel}


func _check_element(data: Dictionary, panel: Dictionary, check_actions: bool) -> Dictionary:
	var type = data.get("type")
	if not type in ELEMENT_TYPES:
		return {"error": "\"type\" must be one of %s" % [ELEMENT_TYPES]}
	if not _good_id(data.get("id")):
		return {"error": "\"id\" must be a name of 1 to 40 letters, digits and _"}
	var fields := {
		"text": ["type", "id", "at", "width", "text", "font_size", "color", "mono", "align", "source"],
		"button": ["type", "id", "at", "size", "label", "action", "color", "clear_input"],
		"input": ["type", "id", "at", "width", "font_size", "color", "prompt", "max_length"],
		"box": ["type", "id", "at", "size", "color"],
		"toggle": ["type", "id", "at", "size", "label", "action", "color", "on"],
		"slider": ["type", "id", "at", "size", "label", "action", "color", "min", "max", "step", "value"],
	}
	for key in data:
		if not key in fields[type] and key != "page":
			return {"error": "unknown field \"%s\" for a %s (it has %s)" % [key, type, ", ".join(fields[type])]}
	var element := {"type": type, "id": data["id"]}
	if data.has("page"):
		if typeof(data["page"]) != TYPE_STRING:
			return {"error": "\"page\" must be the name of one of the panel's pages"}
		element["page"] = data["page"]
	var in_grid: bool = panel["layout"] == "grid" and type == "button"
	if not in_grid or data.has("at"):
		element["at"] = data.get("at", [0, 0])
		if not _numbers(element["at"], 2, -3.0, 3.0):
			return {"error": "\"at\" must be [x, y] in metres from the panel's centre, -3 to 3"}
	if type in ["text", "input"]:
		element["width"] = data.get("width", 0.5)
		if typeof(element["width"]) not in [TYPE_INT, TYPE_FLOAT] or element["width"] < 0.02 or element["width"] > 3.0:
			return {"error": "\"width\" must be 0.02 to 3 metres"}
		element["font_size"] = data.get("font_size", 32)
		if typeof(element["font_size"]) not in [TYPE_INT, TYPE_FLOAT] or element["font_size"] < 8 or element["font_size"] > 200:
			return {"error": "\"font_size\" must be 8 to 200"}
		element["font_size"] = int(element["font_size"])
	if type in ["button", "box", "toggle", "slider"] and not in_grid:
		element["size"] = data.get("size", [0.3, 0.06] if type == "slider" else [0.14, 0.07])
		if not _numbers(element["size"], 2, 0.005, 3.0):
			return {"error": "\"size\" must be [width, height] in metres, 0.005 to 3"}
	# No colour means the theme's colour for the type (and so does the
	# colour every element used to be saved with before there was a theme).
	if data.has("color") and data["color"] != OLD_DEFAULT_COLORS.get(type, ""):
		if not _good_color(data["color"]):
			return {"error": "\"color\" must be a theme name (%s), a colour name or #rrggbb" % ", ".join(_color_names())}
		element["color"] = data["color"]
	match type:
		"text":
			element["text"] = data.get("text", "")
			if typeof(element["text"]) != TYPE_STRING or element["text"].length() > MAX_TEXT:
				return {"error": "\"text\" must be text of up to %d characters" % MAX_TEXT}
			element["mono"] = data.get("mono", false)
			if typeof(element["mono"]) != TYPE_BOOL:
				return {"error": "\"mono\" (monospace font) must be true or false"}
			element["align"] = data.get("align", "left")
			if not element["align"] in ALIGNS:
				return {"error": "\"align\" must be left, center or right"}
			if data.has("source"):
				var problem := _check_source(data["source"])
				if not problem.is_empty():
					return {"error": problem}
				element["source"] = data["source"]
		"button", "toggle", "slider":
			element["label"] = data.get("label")
			if typeof(element["label"]) != TYPE_STRING or element["label"].is_empty() or element["label"].length() > 40:
				return {"error": "\"label\" must be text of 1 to 40 characters"}
			var problem := _check_action(data.get("action"), check_actions)
			if not problem.is_empty():
				return {"error": problem}
			element["action"] = data["action"]
			if type == "toggle":
				element["on"] = data.get("on", false)
				if typeof(element["on"]) != TYPE_BOOL:
					return {"error": "\"on\" must be true or false"}
			if type == "slider":
				for key in [["min", 0.0], ["max", 1.0], ["step", 0.0]]:
					element[key[0]] = data.get(key[0], key[1])
					if typeof(element[key[0]]) not in [TYPE_INT, TYPE_FLOAT] or absf(element[key[0]]) > 1e6:
						return {"error": "\"%s\" must be a number" % key[0]}
					element[key[0]] = float(element[key[0]])
				if element["max"] <= element["min"] or element["step"] < 0.0:
					return {"error": "a slider needs min below max, and a step of 0 (none) or more"}
				element["value"] = data.get("value", element["min"])
				if typeof(element["value"]) not in [TYPE_INT, TYPE_FLOAT]:
					return {"error": "\"value\" must be a number"}
				element["value"] = clampf(element["value"], element["min"], element["max"])
			if data.has("clear_input"):
				if not _good_id(data["clear_input"]):
					return {"error": "\"clear_input\" must be the id of an input box on this panel"}
				element["clear_input"] = data["clear_input"]
		"input":
			element["prompt"] = data.get("prompt", "")
			if typeof(element["prompt"]) != TYPE_STRING or element["prompt"].length() > 20:
				return {"error": "\"prompt\" must be text of up to 20 characters"}
			element["max_length"] = data.get("max_length", MAX_INPUT)
			if typeof(element["max_length"]) not in [TYPE_INT, TYPE_FLOAT] or element["max_length"] < 1 or element["max_length"] > MAX_INPUT:
				return {"error": "\"max_length\" must be 1 to %d" % MAX_INPUT}
			element["max_length"] = int(element["max_length"])
	return {"element": element}


# A command a button, toggle, slider or launcher tile may run.
func _check_action(action, check_exists: bool) -> String:
	if typeof(action) != TYPE_DICTIONARY or typeof(action.get("cmd")) != TYPE_STRING:
		return "\"action\" must be a command, like {\"cmd\": \"spawn\", \"shape\": \"box\"}"
	if check_exists and not action["cmd"] in _server.commands():
		return "\"action\" uses unknown cmd \"%s\"" % action["cmd"]
	if action["cmd"] in ["ui_press", "ui_slide"]:
		return "a button can't press another button"
	if action["cmd"].ends_with("_config"):
		return "settings (%s) can only be changed from the PC, not by a button" % action["cmd"]
	return ""


func _check_source(source) -> String:
	if typeof(source) != TYPE_DICTIONARY or typeof(source.get("cmd")) != TYPE_STRING:
		return "\"source\" must be {\"cmd\": a read-only command, optional field, last, chars, empty}"
	for key in source:
		if not key in ["cmd", "field", "last", "chars", "empty", "format"]:
			return "unknown \"source\" field \"%s\"" % key
	var cmd: String = source["cmd"]
	if not (cmd in SOURCE_COMMANDS or cmd.ends_with("_status") or cmd.ends_with("_list")):
		return "a \"source\" must be a read-only command (list, modules, or one ending in _status or _list), not \"%s\"" % cmd
	if source.has("field") and typeof(source["field"]) != TYPE_STRING:
		return "\"source\" field must be the name of a field in the command's reply"
	for key in [["last", 1, 50], ["chars", 10, 1000]]:
		if source.has(key[0]) and (typeof(source[key[0]]) not in [TYPE_INT, TYPE_FLOAT] or source[key[0]] < key[1] or source[key[0]] > key[2]):
			return "\"source\" %s must be %d to %d" % key
	if source.has("empty") and (typeof(source["empty"]) != TYPE_STRING or source["empty"].length() > 200):
		return "\"source\" empty must be text of up to 200 characters"
	if source.has("format") and not _good_id(source["format"]):
		return "\"source\" format must be the name of a module with format(value, source)"
	return ""


func _good_id(id) -> bool:
	if typeof(id) != TYPE_STRING or id.is_empty() or id.length() > 40:
		return false
	for ch in id:
		if not (ch == "_" or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")):
			return false
	return true


func _good_color(value) -> bool:
	return typeof(value) == TYPE_STRING and (value in _color_names() or Color.html_is_valid(value) \
		or Color.from_string(value, Color(-1, -1, -1)) != Color(-1, -1, -1))


func _color_names() -> Array:
	return DEFAULT_THEME.keys().filter(func(k): return not k in THEME_FONTS)


func _to_color(value: String) -> Color:
	if value in theme_values and not value in THEME_FONTS:
		return theme_values[value]
	return Color.html(value) if Color.html_is_valid(value) else Color.from_string(value, Color.WHITE)


func _theme_color(name: String) -> Color:
	return theme_values.get(name, Color.WHITE)


# An element's colour: its own, or its type's from the theme.
func _color_of(element: Dictionary) -> Color:
	return _to_color(element["color"]) if element.has("color") else _theme_color(TYPE_COLORS[element["type"]])


func _numbers(value, count: int, lo: float, hi: float) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != count:
		return false
	for n in value:
		if typeof(n) not in [TYPE_INT, TYPE_FLOAT] or n < lo or n > hi:
			return false
	return true


func _index_of(id_panel: String) -> int:
	for i in panels.size():
		if panels[i]["id_panel"] == id_panel:
			return i
	return -1


func _element_index(panel: Dictionary, id_element: String) -> int:
	for i in panel["elements"].size():
		if panel["elements"][i]["id"] == id_element:
			return i
	return -1


func _element(id_panel: String, id_element: String) -> Dictionary:
	var index := _index_of(id_panel)
	if index == -1:
		return {}
	var at := _element_index(panels[index], id_element)
	return {} if at == -1 else panels[index]["elements"][at]


# --- Drawing -------------------------------------------------------------------------

func _drop_holder(id_panel: String) -> void:
	if _holders.has(id_panel):
		var holder: Node3D = _holders[id_panel]
		_holders.erase(id_panel)
		holder.get_parent().remove_child(holder)
		holder.queue_free()
	_hovered = null


# Draws a panel from its data, replacing what was there.
# From the top: the title bar and its x (chrome), the tabs (pages), the
# launcher's tiles (apps), then the background (size) with the elements on it.
func _build(id_panel: String) -> void:
	var panel: Dictionary = panels[_index_of(id_panel)]
	var old_transform := Transform3D.IDENTITY
	var had_holder := _holders.has(id_panel)
	if had_holder:
		old_transform = _holders[id_panel].global_transform
	_drop_holder(id_panel)

	var holder := Node3D.new()
	holder.name = "Panel_" + id_panel
	if panel["place"] == "wrist":
		# On the back of the left wrist, tilted to face you when you look at it.
		holder.position = Vector3(0.0, 0.03, 0.08)
		holder.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
		_left.add_child(holder)
	else:
		add_child(holder)
		if panel["place"] == "world":
			var p: Array = panel["position"]
			var r: Array = panel["rotation"]
			holder.global_position = Vector3(p[0], p[1], p[2])
			holder.global_rotation_degrees = Vector3(r[0], r[1], r[2])
		elif had_holder:
			holder.global_transform = old_transform  # a front panel stays where it opened
	_holders[id_panel] = holder
	holder.visible = panel["visible"]

	var top := 0.0
	if panel.has("size"):
		var size := Vector2(panel["size"][0], panel["size"][1])
		top = size.y / 2.0
		var back_color := _to_color(panel["color"]) if panel.has("color") else _theme_color("panel")
		var back := _make_body(id_panel, "", size, Vector3(0, 0, -0.004), back_color)
		back.set_meta("kind", "back")
		holder.add_child(back)
		if panel["apps"] and not _apps.is_empty():
			top = _build_apps(holder, panel, top, size.x, back_color)
		if not panel["pages"].is_empty():
			top = _build_tabs(holder, panel, top, size.x)
		if panel["chrome"]:
			top = _build_title(holder, panel, top, size.x)
		# A thin edge round the whole window, so it stands out from the world.
		var edge := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(size.x + 0.008, top + size.y / 2.0 + 0.008)
		edge.mesh = quad
		edge.material_override = _flat_material(_theme_color("border"))
		edge.position = Vector3(0, (top - size.y / 2.0) / 2.0, -0.006)
		holder.add_child(edge)
	elif panel["apps"] and not _apps.is_empty():
		_build_apps(holder, panel, _top_of(panel) + 0.01, _apps_width(), Color.TRANSPARENT)

	var grid_index := 0
	var grid_buttons: Array = panel["elements"].filter(func(e): return e["type"] == "button" and not e.has("at"))
	for element in panel["elements"]:
		var shown: bool = not element.has("page") or element["page"] == panel["page"]
		var at := Vector3.ZERO
		var size := Vector2.ZERO
		if element.has("at"):
			at = Vector3(element["at"][0], element["at"][1], 0)
		if element["type"] == "button" and not element.has("at"):
			var cell := Vector2(panel["cell"][0], panel["cell"][1])
			var per_row: int = panel["columns"]
			var gap := cell.y * 0.25
			var row := grid_index / per_row
			var in_row := mini(per_row, grid_buttons.size() - row * per_row)
			var col := grid_index % per_row
			at = Vector3((col - (in_row - 1) / 2.0) * (cell.x + gap), -row * (cell.y + gap), 0)
			size = cell
			grid_index += 1
		elif element.has("size"):
			size = Vector2(element["size"][0], element["size"][1])
		if shown:
			holder.add_child(_make_element(id_panel, element, at, size))

	var notice := _make_label(Vector3(0, _bottom_of(panel) - 0.03, 0.002), 0.6, theme_values["font_small"], _theme_color("notice"), false, "center")
	notice.name = "Notice"
	holder.add_child(notice)
	_set_pointable(holder, panel["visible"])
	if panel["visible"]:
		_since_poll = POLL_SECONDS


# The title bar: the title on the left, a close x on the right. Pull the
# trigger on the bar and move the controller to carry the window.
func _build_title(holder: Node3D, panel: Dictionary, top: float, width: float) -> float:
	var id_panel: String = panel["id_panel"]
	var bar := _make_body(id_panel, "", Vector2(width, TITLE_BAR), Vector3(0, top + TITLE_BAR / 2.0, -0.002), _theme_color("title_bar"))
	bar.set_meta("kind", "title")
	bar.set_meta("color", _theme_color("title_bar"))
	var title := _make_label(Vector3(-width / 2.0 + 0.015, 0, 0.002), width - TITLE_BAR - 0.03, theme_values["font_title"], _theme_color("title"), false, "left")
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text = panel["title"]
	bar.add_child(title)
	holder.add_child(bar)
	var side := TITLE_BAR * 0.8
	var close := _make_body(id_panel, "", Vector2(side, side), Vector3(width / 2.0 - TITLE_BAR / 2.0, top + TITLE_BAR / 2.0, 0.0), _theme_color("button"))
	close.set_meta("kind", "close")
	close.set_meta("color", _theme_color("button"))
	close.set_meta("hover", _theme_color("danger"))
	close.add_child(_button_label("x", Vector2(side, side), _theme_color("text")))
	holder.add_child(close)
	return top + TITLE_BAR


func _build_tabs(holder: Node3D, panel: Dictionary, top: float, width: float) -> float:
	var count: int = panel["pages"].size()
	var gap := 0.006
	var tab := Vector2((width - gap * (count + 1)) / count, TAB_BAR - gap)
	for i in count:
		var page: String = panel["pages"][i]
		var active: bool = page == panel["page"]
		var color := _theme_color("accent") if active else _theme_color("button")
		var x := -width / 2.0 + gap + tab.x / 2.0 + i * (tab.x + gap)
		var body := _make_body(panel["id_panel"], "", tab, Vector3(x, top + TAB_BAR / 2.0, -0.002), color)
		body.set_meta("kind", "tab")
		body.set_meta("value", page)
		body.set_meta("color", color)
		body.add_child(_button_label(page, tab, _theme_color("text")))
		holder.add_child(body)
	return top + TAB_BAR


# The launcher's tiles, a row (or more) above the panel's own elements.
func _build_apps(holder: Node3D, panel: Dictionary, top: float, width: float, back_color: Color) -> float:
	var gap := 0.01
	var per_row := maxi(1, int((width + gap) / (APP_CELL.x + gap)))
	var rows := ceili(_apps.size() / float(per_row))
	var height := rows * (APP_CELL.y + gap) + gap
	if back_color.a > 0.0:
		var strip := _make_body(panel["id_panel"], "", Vector2(width, height), Vector3(0, top + height / 2.0, -0.004), back_color)
		strip.set_meta("kind", "back")
		holder.add_child(strip)
	for i in _apps.size():
		var app: Dictionary = _apps[i]
		var row := i / per_row
		var in_row := mini(per_row, _apps.size() - row * per_row)
		var col := i % per_row
		var at := Vector3((col - (in_row - 1) / 2.0) * (APP_CELL.x + gap), top + height - gap - APP_CELL.y / 2.0 - row * (APP_CELL.y + gap), 0)
		var open: bool = not app["panel"].is_empty() and _index_of(app["panel"]) != -1 and panels[_index_of(app["panel"])]["visible"]
		var color := _theme_color("accent") if open else _theme_color("button")
		var body := _make_body(panel["id_panel"], "", APP_CELL, at, color)
		body.name = "App_" + app["id"]
		body.set_meta("kind", "app")
		body.set_meta("value", app["id"])
		body.set_meta("color", color)
		body.add_child(_button_label(app["label"], APP_CELL, _theme_color("text")))
		holder.add_child(body)
	return top + height


func _apps_width() -> float:
	return mini(_apps.size(), 6) * (APP_CELL.x + 0.01) + 0.01


# A hidden panel's buttons are still in the physics world; without this the
# pointer would find (and press) them where the panel was.
func _set_pointable(holder: Node3D, on: bool) -> void:
	for body in holder.find_children("*", "StaticBody3D", true, false):
		body.collision_layer = UI_LAYER if on else 0


func _make_element(id_panel: String, element: Dictionary, at: Vector3, size: Vector2) -> Node3D:
	var node: Node3D
	var color := _color_of(element)
	match element["type"]:
		"box":
			node = MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = size
			node.mesh = quad
			node.material_override = _flat_material(color)
			node.position = at + Vector3(0, 0, -0.002)
		"text":
			# A Label3D's text starts at its origin when left-aligned (ends there
			# when right-aligned), so shift it to put the block's top-centre at "at".
			var shift := {"left": -element["width"] / 2.0, "center": 0.0, "right": element["width"] / 2.0}
			node = _make_label(at + Vector3(shift[element["align"]], 0, 0), element["width"], element["font_size"], color, element["mono"], element["align"])
			node.text = element["text"] if not element.has("source") else element["source"].get("empty", "")
			node.text = _live_text.get(id_panel + "/" + element["id"], node.text)
		"button":
			node = _make_body(id_panel, element["id"], size, at, color)
			node.set_meta("color", color)
			node.add_child(_button_label(element["label"], size, _theme_color("text")))
		"toggle":
			# The label, and on the right a light that is lit while it's on.
			node = _make_body(id_panel, element["id"], size, at, color)
			node.set_meta("color", color)
			var light_size := Vector2(size.y * 0.9, size.y * 0.5)
			var label := _button_label(element["label"], Vector2(size.x - light_size.x - 0.02, size.y), _theme_color("text"))
			label.position.x = -light_size.x / 2.0 - 0.005
			node.add_child(label)
			var light := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = light_size
			light.mesh = quad
			light.material_override = _flat_material(_theme_color("ok") if element["on"] else _theme_color("input_bg"))
			light.position = Vector3(size.x / 2.0 - light_size.x / 2.0 - 0.008, 0, 0.001)
			node.add_child(light)
			var state := _button_label("ON" if element["on"] else "OFF", light_size, _theme_color("text") if element["on"] else _theme_color("muted"))
			state.position = light.position + Vector3(0, 0, 0.001)
			node.add_child(state)
		"slider":
			# The label and value on top, the track below with its filled part
			# and a knob; the whole area takes the pointer.
			node = _make_body(id_panel, element["id"], size, at, _theme_color("button"))
			node.set_meta("color", _theme_color("button"))
			var label := _make_label(Vector3(-size.x / 2.0 + 0.01, size.y / 2.0 - 0.004, 0.002), size.x - 0.02, theme_values["font_small"], _theme_color("text"), false, "left")
			label.name = "Label"
			node.add_child(label)
			for part in [["Track", _theme_color("input_bg")], ["Fill", color], ["Knob", _theme_color("text")]]:
				var mesh := MeshInstance3D.new()
				mesh.name = part[0]
				mesh.mesh = QuadMesh.new()
				mesh.material_override = _flat_material(part[1])
				node.add_child(mesh)
			_show_slider(node, element, element["value"])
		"input":
			var height: float = element["font_size"] * TEXT_PIXEL * 1.6
			node = _make_body(id_panel, element["id"], Vector2(element["width"], height), at, _theme_color("input_bg"))
			var label := _make_label(Vector3(-element["width"] / 2.0 + 0.01, 0, 0.002), element["width"] - 0.02, element["font_size"], color, false, "left")
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.name = "Text"
			node.add_child(label)
	node.name = "E_" + element["id"]
	if element["type"] == "input":
		_show_input_node(id_panel, element, node)
	return node


func _show_slider(node: Node3D, element: Dictionary, value: float) -> void:
	var size := Vector2(element["size"][0], element["size"][1])
	var t: float = (value - element["min"]) / (element["max"] - element["min"])
	var track := Vector2(size.x - 0.03, maxf(size.y * 0.18, 0.006))
	var y := -size.y / 2.0 + track.y / 2.0 + size.y * 0.15
	var left := -track.x / 2.0
	(node.get_node("Track") as MeshInstance3D).mesh.size = track
	node.get_node("Track").position = Vector3(0, y, 0.001)
	(node.get_node("Fill") as MeshInstance3D).mesh.size = Vector2(maxf(track.x * t, 0.001), track.y)
	node.get_node("Fill").position = Vector3(left + track.x * t / 2.0, y, 0.0015)
	var knob := track.y * 2.2
	(node.get_node("Knob") as MeshInstance3D).mesh.size = Vector2(knob * 0.6, knob)
	node.get_node("Knob").position = Vector3(left + track.x * t, y, 0.002)
	(node.get_node("Label") as Label3D).text = "%s  %s" % [element["label"], _value_text(element, value)]


func _value_text(element: Dictionary, value: float) -> String:
	if element["step"] >= 1.0 and is_equal_approx(element["step"], roundf(element["step"])):
		return str(int(roundf(value)))
	return String.num(value, 2)


# Draws a toggle or slider again after its state changed, in place.
func _show_state(id_panel: String, element: Dictionary) -> void:
	var old := _find_node(id_panel, element["id"]) as Node3D
	if old == null:
		return
	var index := _index_of(id_panel)
	var fresh := _make_element(id_panel, element, old.position, Vector2(element["size"][0], element["size"][1]))
	var holder := old.get_parent()
	if _hovered == old:
		_hovered = null
	holder.remove_child(old)
	old.queue_free()
	holder.add_child(fresh)
	if fresh is StaticBody3D:
		fresh.collision_layer = UI_LAYER if index != -1 and panels[index]["visible"] else 0


# A flat, pointable quad: the laser hits it, the trigger presses it.
func _make_body(id_panel: String, id_element: String, size: Vector2, at: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = UI_LAYER
	body.collision_mask = 0
	body.set_meta("panel", id_panel)
	body.set_meta("element", id_element)
	body.set_meta("z", at.z)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.004)
	shape.shape = box
	body.add_child(shape)
	var face := MeshInstance3D.new()
	face.name = "Face"
	var quad := QuadMesh.new()
	quad.size = size
	face.mesh = quad
	face.material_override = _flat_material(color)
	body.add_child(face)
	return body


# A button's centred label, sized to the button.
func _button_label(text: String, size: Vector2, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = "Label"
	label.text = text
	label.pixel_size = minf(size.y, 0.07) / 140.0
	label.font_size = 80 if text.length() == 1 and not text.is_valid_int() and size.y < 0.045 else 48  # a lone mark, like the close x
	label.outline_size = 0
	label.modulate = color
	label.position = Vector3(0, 0, 0.002)
	label.width = size.x / label.pixel_size * 0.95
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_label(at: Vector3, width: float, font_size: int, color: Color, mono: bool, align: String) -> Label3D:
	var label := Label3D.new()
	label.position = at
	label.pixel_size = TEXT_PIXEL
	label.font_size = font_size
	label.outline_size = 0
	label.width = width / TEXT_PIXEL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = ALIGNS[align]
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.modulate = color
	if mono:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["monospace"])
		label.font = font
	return label


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


# The lowest point of a panel's background or elements, for the notice line.
func _bottom_of(panel: Dictionary) -> float:
	var bottom := 0.0
	if panel.has("size"):
		bottom = -panel["size"][1] / 2.0
	var grid_count := 0
	for element in panel["elements"]:
		if element.has("at"):
			var half := 0.0
			if element.has("size"):
				half = element["size"][1] / 2.0
			bottom = minf(bottom, element["at"][1] - half)
		elif element["type"] == "button":
			grid_count += 1
	if grid_count > 0:
		var rows := ceili(grid_count / float(panel["columns"]))
		var cell_y: float = panel["cell"][1]
		bottom = minf(bottom, -(rows - 1) * cell_y * 1.25 - cell_y / 2.0)
	return bottom


# The highest point of a panel without a background, for the launcher's row.
func _top_of(panel: Dictionary) -> float:
	var top := 0.0
	for element in panel["elements"]:
		var half := 0.0
		if element.has("size"):
			half = element["size"][1] / 2.0
		elif element["type"] == "button":
			half = panel["cell"][1] / 2.0
		top = maxf(top, (element["at"][1] if element.has("at") else 0.0) + half)
	return top


func _find_node(id_panel: String, id_element: String) -> Node:
	if not _holders.has(id_panel):
		return null
	return _holders[id_panel].get_node_or_null("E_" + id_element)


func _show_input(id_panel: String, id_element: String) -> void:
	var node := _find_node(id_panel, id_element)
	var element := _element(id_panel, id_element)
	if node and not element.is_empty():
		_show_input_node(id_panel, element, node)


func _show_input_node(id_panel: String, element: Dictionary, node: Node) -> void:
	var key: String = id_panel + "/" + element["id"]
	var text: String = element["prompt"] + _inputs.get(key, "")
	if key == _focus:
		text += "_" + (" (SHIFT)" if _shift else "")
	(node.get_node("Text") as Label3D).text = text
	# The box being typed into has a lit edge.
	(node.get_node("Face") as MeshInstance3D).material_override.albedo_color = \
		_theme_color("hover").darkened(0.4) if key == _focus else _theme_color("input_bg")


func _notice(id_panel: String, text: String) -> void:
	if not _holders.has(id_panel):
		return
	var notice := _holders[id_panel].get_node_or_null("Notice") as Label3D
	if notice == null:
		return
	notice.text = text.left(200)
	get_tree().create_timer(NOTICE_SECONDS).timeout.connect(func():
		if is_instance_valid(notice) and notice.text == text.left(200):
			notice.text = "")


# Pointing at something you can press lights it up and brings it a few
# millimetres towards you, with a light tick; plain text and backgrounds
# don't react.
func _set_hover(body: StaticBody3D, on: bool) -> void:
	if body == null or not is_instance_valid(body) or not body.has_meta("color"):
		return
	var face := body.get_node("Face") as MeshInstance3D
	var hover: Color = body.get_meta("hover", _theme_color("hover"))
	(face.material_override as StandardMaterial3D).albedo_color = hover if on else body.get_meta("color")
	body.position.z = body.get_meta("z", 0.0) + (HOVER_LIFT if on else 0.0)
	if on:
		_pulse(0.1, 0.01)


# A press flashes the button for a moment, so you see it went in.
func _flash(body: StaticBody3D) -> void:
	if body == null or not is_instance_valid(body) or not body.has_meta("color"):
		return
	var material := (body.get_node("Face") as MeshInstance3D).material_override as StandardMaterial3D
	material.albedo_color = _theme_color("press")
	var id := body.get_instance_id()  # the press may redraw it (a toggle), so not the node itself
	get_tree().create_timer(PRESS_SECONDS).timeout.connect(func():
		var still := instance_from_id(id) as StaticBody3D
		if still and is_instance_valid(still):
			material.albedo_color = still.get_meta("hover", _theme_color("hover")) if still == _hovered else still.get_meta("color"))


# --- Defaults and saving -----------------------------------------------------------------

func _defaults() -> Array:
	var spawn_buttons := []
	for shape in ["box", "sphere", "cylinder", "capsule"]:
		spawn_buttons.append({
			"type": "button", "id": "spawn_" + shape, "label": shape.capitalize(),
			"action": {"cmd": "spawn", "shape": shape, "position": "in_front", "scale": [0.3, 0.3, 0.3]},
		})
	var bar_buttons := spawn_buttons.duplicate(true)
	bar_buttons.append({"type": "button", "id": "list", "label": "List objects", "action": {"cmd": "list"}})
	return [
		{
			# The Menu: the launcher's tiles (every module's window) above the
			# shapes you can add.
			"id_panel": "bar", "title": "Menu", "place": "front", "distance": 0.6, "height": -0.25,
			"toggle": "left_menu", "chrome": true, "apps": true, "size": [0.9, 0.11],
			"layout": "grid", "columns": 6, "cell": [0.14, 0.07], "elements": bar_buttons,
		},
		{
			"id_panel": "wrist", "title": "Wrist", "place": "wrist", "visible": true, "size": [0.21, 0.065],
			"layout": "grid", "columns": 3, "cell": [0.06, 0.025], "elements": spawn_buttons,
		},
		_chat_panel(),
	]


# The agent's chat window: what it's doing at the top, the line you're typing
# with STOP beside it, and a keyboard with Send. Everything in it is ordinary
# elements; the ids stay the same so other modules (aimsg) can find them.
func _chat_panel() -> Dictionary:
	var key := 0.05
	var gap := 0.008
	var unit := key + gap
	var width := 10 * unit
	var elements := [
		{"type": "box", "id": "screen", "at": [0, 0.18], "size": [width + 0.02, 0.21], "color": "screen"},
		{"type": "text", "id": "log", "at": [0, 0.275], "width": width, "font_size": 26, "color": "#8cff99", "mono": true,
			"source": {"cmd": "agent_status", "field": "events", "last": 10, "chars": 160, "empty": "agent ready. type below and press Send.", "format": "aimsg"}},
		{"type": "text", "id": "state", "at": [0, 0.1], "width": width, "font_size": 24, "color": "#5f9f6a", "mono": true,
			"source": {"cmd": "agent_status", "field": "status_line"}},
		{"type": "input", "id": "line", "at": [-0.06, 0.04], "width": width - 0.12, "font_size": 34, "prompt": "> "},
		{"type": "button", "id": "stop", "label": "STOP", "at": [width / 2.0 - 0.05, 0.04], "size": [0.1, 0.045], "color": "danger",
			"action": {"cmd": "agent_stop"}},
	]
	var rows := ["1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.?"]
	var first := -0.025
	for r in rows.size():
		for c in rows[r].length():
			var ch: String = rows[r][c]
			elements.append({"type": "button", "id": "key_%d_%d" % [r, c], "label": ch, "at": [(c - 4.5) * unit, first - r * unit], "size": [key, key],
				"action": {"cmd": "ui_type", "text": ch}})
	var bottom := first - rows.size() * unit
	elements.append_array([
		{"type": "button", "id": "shift", "label": "Shift", "at": [-3.75 * unit, bottom], "size": [key * 2 + gap, key], "action": {"cmd": "ui_key", "key": "shift"}},
		{"type": "button", "id": "space", "label": "Space", "at": [-0.75 * unit, bottom], "size": [key * 4 + gap * 3, key], "action": {"cmd": "ui_type", "text": " "}},
		{"type": "button", "id": "del", "label": "Del", "at": [1.75 * unit, bottom], "size": [key, key], "action": {"cmd": "ui_key", "key": "backspace"}},
		{"type": "button", "id": "clear", "label": "Clear", "at": [2.75 * unit, bottom], "size": [key, key], "action": {"cmd": "ui_key", "key": "clear"}},
		{"type": "button", "id": "send", "label": "Send", "at": [4.0 * unit, bottom], "size": [key * 2 + gap, key], "color": "accent",
			"action": {"cmd": "agent_ask", "prompt": "{input:line}"}, "clear_input": "line"},
	])
	return {"id_panel": "chat", "title": "Agent", "place": "front", "distance": 0.55, "height": -0.35,
		"toggle": "left_y", "chrome": true, "menu": "Chat", "size": [width + 0.06, 0.6], "elements": elements}


func _checked_defaults() -> Array:
	var checked := []
	for panel in _defaults():
		checked.append(_check_panel(panel, false, false)["panel"])
	return checked


func _load() -> void:
	var checked_defaults := _checked_defaults()
	if not FileAccess.file_exists(SAVE_PATH):
		panels = checked_defaults
		_bring_over_old_menu()
		print("Slopitect ui: no saved panels, using the default %d" % panels.size())
		return
	var json := JSON.new()
	var problem := ""
	if json.parse(FileAccess.get_file_as_string(SAVE_PATH)) != OK:
		problem = "not valid JSON: " + json.get_error_message()
	elif typeof(json.data) != TYPE_ARRAY or json.data.size() > MAX_PANELS:
		problem = "expected a list of up to %d panels" % MAX_PANELS
	else:
		var loaded := []
		for item in json.data:
			if typeof(item) != TYPE_DICTIONARY:
				problem = "an entry isn't a panel: " + JSON.stringify(item).left(100)
				break
			var checked := _check_panel(item, false, false)
			if checked.has("error"):
				problem = checked["error"]
				break
			if loaded.any(func(p): return p["id_panel"] == checked["panel"]["id_panel"]):
				problem = "two panels are called \"%s\"" % checked["panel"]["id_panel"]
				break
			loaded.append(checked["panel"])
		if problem.is_empty():
			panels = loaded
			print("Slopitect ui: loaded %d panels from %s" % [panels.size(), SAVE_PATH])
			return
	# Keep the broken file for inspection instead of overwriting it.
	var kept := SAVE_PATH + ".bad"
	DirAccess.rename_absolute(SAVE_PATH, kept)
	push_error("Slopitect ui: %s is broken (%s); kept it as %s and used the defaults" % [SAVE_PATH, problem, kept])
	panels = checked_defaults


# The menu module saved its buttons in menu.json. The first time the panels
# start, those buttons move onto the bar and wrist panels, so nothing you
# added is lost; menu.json is then renamed so it's only read once.
func _bring_over_old_menu() -> void:
	if not FileAccess.file_exists(OLD_MENU_PATH):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(OLD_MENU_PATH)) != OK or typeof(json.data) != TYPE_ARRAY:
		push_error("Slopitect ui: %s isn't a list of buttons; left it as it is" % OLD_MENU_PATH)
		return
	var moved := {"bar": [], "wrist": []}
	for item in json.data:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		for place in moved:
			if place in item.get("places", ["bar", "wrist"]):
				moved[place].append({"type": "button", "id": item.get("id_button"), "label": item.get("label"), "action": item.get("action")})
	for place in moved:
		var index := _index_of(place)
		var merged: Dictionary = panels[index].duplicate(true)
		merged["elements"] = moved[place]
		var checked := _check_panel(merged, false, false)
		if checked.has("error"):
			push_error("Slopitect ui: couldn't bring the old menu's %s buttons over (%s); using the defaults there" % [place, checked["error"]])
			continue
		panels[index] = checked["panel"]
	DirAccess.rename_absolute(OLD_MENU_PATH, OLD_MENU_PATH + ".moved")
	print("Slopitect ui: brought %d bar and %d wrist buttons over from %s" % [moved["bar"].size(), moved["wrist"].size(), OLD_MENU_PATH])
	_save()


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Slopitect ui: could not save %s (%s)" % [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(panels, "  "))
	file.close()
