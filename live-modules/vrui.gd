extends SlopitectModule

# Slopitect live module "vrui": every window in the app, as data. (It was
# ui.gd; the ui_* commands, user://ui.json and ui_config keep their names,
# so saved panels and other modules carry on. Modules find it with
# module("vrui"), or module("ui") for the older one.)
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
# Pointing gives feedback: the button lights up, a dot shows where you
# point, and the controller ticks (controls.pulse) on hover and press.
#
# Panels are drawn the way the vrui draft drew its windows (rounded, with
# real 2D panels and text, see Drawing), redrawn only when they change. A
# panel can be held by a hand ("hand" place), and its elements can flow in
# rows, columns and grids (layout column or row) instead of each having an
# "at", so a menu is a list of what's in it. A button with "open" opens
# another panel in its place, with a back arrow: menus inside menus.
# A text element with "scroll" keeps its newest lines in view (a terminal);
# ui_scroll moves it back and forth. Docs: docs/VR-UI.md.

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
const PLACES := ["front", "wrist", "world", "follow", "hand"]
const LAYOUTS := ["free", "grid", "column", "row"]
const ELEMENT_TYPES := ["text", "button", "input", "box", "toggle", "slider", "row", "column", "grid"]
const CONTAINERS := ["row", "column", "grid"]
const MAX_DEPTH := 6  # rows in columns in grids...
const ALIGNS := {"left": HORIZONTAL_ALIGNMENT_LEFT, "center": HORIZONTAL_ALIGNMENT_CENTER, "right": HORIZONTAL_ALIGNMENT_RIGHT}
const SOURCE_COMMANDS := ["list", "modules"]  # plus any ending in _status or _list
# Colours, sizes and text sizes every panel draws with unless it says
# otherwise. Text sizes are for about 0.6 m away; 24 is the smallest that
# reads comfortably on the Quest 1.
# The colours are the vrui draft's.
const DEFAULT_THEME := {
	"panel": "#0b0d11", "border": "#3a4560", "title_bar": "#151a26", "title": "#9fb4ff",
	"text": "#e8ecf4", "muted": "#8a93a6", "button": "#1f2129", "hover": "#3a4560",
	"press": "#4a6cff", "accent": "#4a6cff", "danger": "#a8322a", "ok": "#2f8f4e",
	"input": "#b3e6ff", "input_bg": "#07080b", "screen": "#08100a", "notice": "#ff7466",
	"laser": "#66b3ff", "cursor": "#ffffff",
	"font_title": 40, "font_body": 36, "font_small": 28,
}
const THEME_FONTS := ["font_title", "font_body", "font_small"]
# The text sizes ui_text_size picks from; "medium" is the default theme's.
const TEXT_SIZES := {
	"small": {"font_title": 34, "font_body": 30, "font_small": 24},
	"medium": {"font_title": 40, "font_body": 36, "font_small": 28},
	"large": {"font_title": 48, "font_body": 44, "font_small": 34},
}
const TYPE_COLORS := {"text": "text", "button": "button", "input": "input", "box": "screen", "toggle": "button", "slider": "accent"}
# The colours ui.gd used to write into every element, before the theme; an
# element saved with one of these follows the theme instead.
const OLD_DEFAULT_COLORS := {"text": "#ffffff", "button": "#1f2129", "input": "#b3e6ff", "box": "#08100a"}
const OLD_PANEL_COLOR := "#0b0d11"
const TITLE_BAR := 0.05  # metres
const TAB_BAR := 0.045
const GAP := 0.01  # between rows and elements
const PADDING := 0.016  # inside a window's edge
const BORDER := 0.0025
const PANEL_RADIUS := 0.022  # the rounded corners
const BUTTON_RADIUS := 0.014
const BUTTON_PADDING := 0.006
const SMALLEST_LABEL := 16  # the text size a button's label shrinks to before it's cut short
const PANEL_ALPHA := 0.94
const PX_PER_M := 1250.0  # a panel's picture: about what the Quest 1 shows at 0.6 m
const APP_COLUMNS := 5
const HAND_POSITION := [0.0, 0.12, -0.02]  # a hand panel's default place on the controller
const HAND_ROTATION := [-35.0, 0.0, 0.0]
const HAND_SCALE := 0.5
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
var _live_text := {}  # "panel/element" -> text set with set_text (not saved: it can be anything)
var _focus := ""  # "panel/element" of the input box that typing goes to
var _shift := false
var _ray: RayCast3D
var _laser: MeshInstance3D
var _cursor: MeshInstance3D
var _views := {}  # id_panel -> {viewport, controls: {id: Control}, pointables, notice, quad, px}
var _pointing := ""  # the panel the pointer is on
var _hovered: Control  # the element (or title bar, tab, tile) the pointer is on
var _openers := {}  # id_panel -> the panel whose "open" button opened it (for its back arrow)
var _scroll := {}  # "panel/element" -> lines scrolled back from the newest
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
	register("ui_add", _add, "add a panel: id_panel, optional title, place (front, wrist, world, follow, hand), hand (left/right), distance, height, position, rotation, scale, size, color, visible, toggle (an action from controls_status, like left_menu), chrome (title bar with close), menu (its tile's label), pages [tab names], page (the tab shown), apps (launcher tiles), layout (free, grid with columns and cell, or column / row to flow), elements")
	register("ui_update", _update, "change any of a panel's fields (elements replaces them all): id_panel, then the fields")
	register("ui_remove", _remove, "remove a panel: id_panel")
	register("ui_show", _show, "show or hide a panel: id_panel, visible (true/false)")
	register("ui_page", _page_command, "show one of a panel's tabs: id_panel, page (its name)")
	register("ui_back", _back_command, "go back from a panel another one's \"open\" button opened: id_panel")
	register("ui_scroll", _scroll_command, "scroll a text element with scroll: id_panel, id_element, lines (more goes back, fewer forward; 0 for the newest)")
	register("ui_element_add", _element_add, "add an element to a panel: id_panel, element ({type: text|button|input|box|toggle|slider|row|column|grid, id, at [x,y] or in a flow, ...}), optional parent (a row, column or grid's id), index")
	register("ui_element_update", _element_update, "change an element's fields: id_panel, id_element, then the fields")
	register("ui_element_remove", _element_remove, "remove an element: id_panel, id_element")
	register("ui_press", _press_command, "press a button or toggle, as if pointed at and clicked: id_panel, id_element")
	register("ui_slide", _slide_command, "set a slider and run its action: id_panel, id_element, value")
	register("ui_type", _type_command, "type text into the selected input box: text, optional id_panel and id_element to pick the box")
	register("ui_key", _key_command, "a key for the selected input box: key (shift, backspace, clear)")
	register("ui_reset", _reset, "put the default panels back: optional id_panel for just that one")
	register("ui_theme_status", _theme_status, "the theme every panel draws with: colours by name and text sizes")
	register("ui_config", _config, "from the PC only: theme {name: #rrggbb or a text size}, or reset true")
	register("ui_text_size", _text_size_command, "make every window's text smaller or bigger (a comfort setting, so it can change in the headset): size (%s)" % ", ".join(TEXT_SIZES.keys()))

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


# Whether the Yes/No window is asking. The APK's confirm module sets
# pointer_blocked only on a module called "ui"; this one is "vrui", so it
# asks confirm itself as well.
func _asking() -> bool:
	var confirm: SlopitectModule = ctx["modules"].module("confirm")
	return confirm != null and confirm.has_method("asking") and confirm.call("asking")


func _physics_process(_delta: float) -> void:
	if not _dragging.is_empty() and _holders.has(_dragging):
		_holders[_dragging].global_transform = _right.global_transform * _drag_offset
	var blocked := pointer_blocked or _asking()
	_ray.enabled = not blocked
	var hit: StaticBody3D = _ray.get_collider() as StaticBody3D if _ray.enabled and _ray.is_colliding() else null
	_pointing = String(hit.get_meta("panel", "")) if hit else ""
	var control: Control = null
	if not _pointing.is_empty() and _views.has(_pointing):
		control = _control_at(_pointing, _picture_point(_pointing, _ray.get_collision_point()))
	if control != _hovered:
		_set_hover(_hovered, false)
		_hovered = control
		_set_hover(_hovered, true)
	if blocked:
		_laser.visible = false  # the question draws its own
		_cursor.visible = false
		return
	if not _sliding.is_empty():
		_slide_follow()
	var length := LASER_LENGTH
	if hit:
		var point := _ray.get_collision_point()
		length = _right.global_position.distance_to(point)
		_cursor.global_position = point + _ray.get_collision_normal() * 0.002
	_cursor.visible = hit != null
	# Only show the laser while a panel is out that it can point at.
	_laser.visible = hit != null or _any_open()
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
		for element in _flat(panel["elements"]):
			if element["type"] == "text" and element.has("source"):
				_set_label_text(panel["id_panel"], element["id"], _read_source(element))


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
			if down and not _pointing.is_empty():
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
	# Where you let go is where it stays: it's now a panel in the world
	# (a hand panel too: you took it out of your hand).
	var panel: Dictionary = panels[index]
	var holder: Node3D = _holders[panel["id_panel"]]
	if holder.get_parent() != self:
		var at := holder.global_transform
		holder.get_parent().remove_child(holder)
		add_child(holder)
		holder.global_transform = at
	var p := holder.global_position
	var r := holder.global_rotation_degrees
	panel["place"] = "world"
	panel["position"] = [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]
	panel["rotation"] = [snappedf(r.x, 0.1), snappedf(r.y, 0.1), snappedf(r.z, 0.1)]
	_following.erase(panel["id_panel"])
	_save()
	print("Slopitect ui: moved \"%s\" to %s" % [panel["id_panel"], panel["position"]])


func _start_drag() -> bool:
	if _pointing.is_empty():
		return false
	var id_panel := _pointing
	var index := _index_of(id_panel)
	if index == -1 or panels[index]["place"] == "wrist":
		return true  # the wrist panel moves with your wrist; the grip is still the panel's
	_dragging = id_panel
	_drag_offset = _right.global_transform.affine_inverse() * _holders[id_panel].global_transform
	_pulse(0.3, 0.03)
	return true


func _on_point_pressed() -> void:
	if not _hovered:
		return  # the panel's background: the press is the panel's, and does nothing
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
			_pulse(0.4, 0.04)
			_back(id_panel)
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
	if not on and _openers.has(panel["id_panel"]):
		_openers.erase(panel["id_panel"])
		if panel["chrome"]:
			_build(panel["id_panel"])  # no back arrow the next time it opens
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


# A button's "open" (after its action works, if it has one): the other
# panel takes this one's place (and this one hides), with a back arrow in
# its title bar that brings this one back.
func _open_menu(from: String, to: String) -> Dictionary:
	var index := _index_of(to)
	if index == -1:
		var error := "no panel \"%s\" to open" % to
		_notice(from, error)
		return {"ok": false, "error": error}
	var target: Dictionary = panels[index]
	_openers[to] = from
	_build(to)
	var holder: Node3D = _holders[to]
	if target["place"] in ["front", "follow"] and _holders.has(from):
		holder.global_transform = _holders[from].global_transform
	target["visible"] = true
	holder.visible = true
	_set_pointable(holder, true)
	_since_poll = POLL_SECONDS
	var opener: Dictionary = panels[_index_of(from)]
	opener["visible"] = false
	_holders[from].visible = false
	_set_pointable(_holders[from], false)
	return {"ok": true}


func _back(id_panel: String) -> void:
	var from: String = _openers.get(id_panel, "")
	var index := _index_of(id_panel)
	if index == -1:
		return
	var at: Transform3D = _holders[id_panel].global_transform
	_set_visible(panels[index], false)
	var back := _index_of(from)
	if back == -1:
		return
	_set_visible(panels[back], true)
	if panels[back]["place"] in ["front", "follow"]:
		_holders[from].global_transform = at


func _back_command(request: Dictionary) -> Dictionary:
	var id_panel := str(request.get("id_panel"))
	if not _openers.has(id_panel):
		return {"ok": false, "error": "panel \"%s\" wasn't opened from another one" % id_panel}
	_back(id_panel)
	return {"ok": true}


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
	if not element.has("action"):
		return _open_menu(id_panel, element["open"])  # a button that only opens a menu
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
		if element.has("open"):
			_open_menu(id_panel, element["open"])
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


# The theme, with the PC's changes: {name: Color or text size}.
func theme() -> Dictionary:
	return theme_values.duplicate()


# --- Sliders ------------------------------------------------------------------------

# While the trigger holds a slider, its knob follows where you point along it
# (even a little off it); the action runs once, when you let go.
func _slide_follow() -> void:
	var parts := _sliding.split("/")
	var element := _element(parts[0], parts[1])
	var control := _find_node(parts[0], parts[1]) as Control
	if element.is_empty() or control == null or not _holders.has(parts[0]):
		_sliding = ""
		return
	var screen := _holders[parts[0]].get_node("Screen") as Node3D
	var plane := Plane(screen.global_basis.z.normalized(), screen.global_position)
	var hit = plane.intersects_ray(_right.global_position, -_right.global_basis.z)
	if hit == null:
		return
	var track := (control.get_node("Inside") as Control).get_global_rect()
	var t := clampf((_picture_point(parts[0], hit).x - track.position.x) / maxf(track.size.x, 1.0), 0.0, 1.0)
	_slide_value = _snap_value(element, lerpf(element["min"], element["max"], t))
	_show_slider(control, element, _slide_value, parts[0])


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
	# A module can name the input box to type into (stt puts what was heard
	# in the chat line); it becomes the selected one.
	if request.has("id_panel") or request.has("id_element"):
		var id_panel := str(request.get("id_panel", ""))
		var id_element := str(request.get("id_element", ""))
		if _element(id_panel, id_element).get("type", "") != "input":
			return {"ok": false, "error": "\"%s\" has no input box \"%s\"" % [id_panel, id_element]}
		_set_focus(id_panel + "/" + id_element)
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
	_set_label_text(id_panel, id_element, _live_text[id_panel + "/" + id_element])
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
		for element in _flat(panel["elements"]):
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
	for element in _flat(panel["elements"]):
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
	var into: Array = merged["elements"]
	if request.has("parent"):
		var parent := _find_in(merged["elements"], str(request["parent"]))
		if not parent.get("type") in CONTAINERS:
			return {"ok": false, "error": "\"parent\" must be the id of a row, column or grid on panel \"%s\"" % merged["id_panel"]}
		into = parent["children"]
	var at = request.get("index", into.size())
	if typeof(at) != TYPE_FLOAT and typeof(at) != TYPE_INT or int(at) < 0 or int(at) > into.size():
		return {"ok": false, "error": "\"index\" must be 0 to %d" % into.size()}
	into.insert(int(at), request["element"])
	var checked := _check_panel(merged, false, true)
	if checked.has("error"):
		return {"ok": false, "error": checked["error"]}
	panels[index] = checked["panel"]
	return _changed(merged["id_panel"], {"ok": true, "element": _find_in(checked["panel"]["elements"], str(request["element"].get("id")))})


func _element_update(request: Dictionary) -> Dictionary:
	var index := _index_of(str(request.get("id_panel")))
	if index == -1:
		return {"ok": false, "error": "no panel \"%s\" (ui_list shows them)" % str(request.get("id_panel"))}
	var merged: Dictionary = panels[index].duplicate(true)
	var target := _find_in(merged["elements"], str(request.get("id_element")))
	if target.is_empty():
		return {"ok": false, "error": "no element \"%s\" on panel \"%s\" (ui_get shows them)" % [str(request.get("id_element")), merged["id_panel"]]}
	for key in request:
		if not key in ["cmd", "id", "id_panel", "id_element"]:
			if request[key] == null:
				target.erase(key)  # null takes an optional field off
			else:
				target[key] = request[key]
	var checked := _check_panel(merged, false, true)
	if checked.has("error"):
		return {"ok": false, "error": checked["error"]}
	panels[index] = checked["panel"]
	return _changed(merged["id_panel"], {"ok": true, "element": _find_in(checked["panel"]["elements"], target["id"])})


func _element_remove(request: Dictionary) -> Dictionary:
	var index := _index_of(str(request.get("id_panel")))
	if index == -1:
		return {"ok": false, "error": "no panel \"%s\" (ui_list shows them)" % str(request.get("id_panel"))}
	if not _remove_in(panels[index]["elements"], str(request.get("id_element"))):
		return {"ok": false, "error": "no element \"%s\" on panel \"%s\" (ui_get shows them)" % [str(request.get("id_element")), panels[index]["id_panel"]]}
	return _changed(panels[index]["id_panel"], {"ok": true, "removed": str(request.get("id_element"))})


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


# Its section of the Settings window (settings.gd): the text size, the one
# part of the theme that changes in the headset.
func settings_info() -> Dictionary:
	var now := ""
	for size in TEXT_SIZES:
		if int(theme_values.get("font_body", 0)) == TEXT_SIZES[size]["font_body"]:
			now = size
	var options := []
	for size in TEXT_SIZES:
		options.append({"label": size.capitalize(), "value": size})
	return {"title": "Text size", "order": 20, "settings": [
		{"id": "text_size", "type": "choice", "value": now, "options": options, "set": {"cmd": "ui_text_size", "size": "{value}"}},
	]}


# Text size is a comfort setting, so unlike the rest of the theme it can
# change in the headset (isaac's choice, 2026-10-29); colours stay PC only.
func _text_size_command(request: Dictionary) -> Dictionary:
	var size = request.get("size")
	if not size in TEXT_SIZES:
		return {"ok": false, "error": "\"size\" must be one of %s" % [TEXT_SIZES.keys()]}
	return _config({"theme": TEXT_SIZES[size]})


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
		if not key in ["id_panel", "title", "place", "distance", "height", "position", "rotation", "size", "color", "visible", "toggle", "layout", "columns", "cell", "elements", "chrome", "pages", "page", "apps", "menu", "hand", "scale"]:
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
	var in_hand: bool = panel["place"] == "hand"
	panel["hand"] = data.get("hand", "left")
	if not panel["hand"] in ["left", "right"]:
		return {"error": "panel %s: \"hand\" must be left or right" % id}
	panel["scale"] = data.get("scale", HAND_SCALE if in_hand else 1.0)
	if typeof(panel["scale"]) not in [TYPE_INT, TYPE_FLOAT] or panel["scale"] < 0.1 or panel["scale"] > 3.0:
		return {"error": "panel %s: \"scale\" must be 0.1 to 3" % id}
	panel["scale"] = float(panel["scale"])
	# For a hand panel, position and rotation are from the controller.
	for key in [["position", HAND_POSITION if in_hand else [0, 1.4, -1], 20.0], ["rotation", HAND_ROTATION if in_hand else [0, 0, 0], 360.0]]:
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
		return {"error": "panel %s: \"layout\" must be free (each element at its \"at\"), grid (buttons in rows), or column or row (elements flow, no \"at\" needed)" % id}
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
		for element in _flat([checked["element"]]):
			if seen.has(element["id"]):
				return {"error": "panel %s: two elements are called \"%s\"" % [id, element["id"]]}
			seen[element["id"]] = true
		panel["elements"].append(checked["element"])
	if seen.size() > MAX_ELEMENTS:
		return {"error": "panel %s: more than %d elements" % [id, MAX_ELEMENTS]}
	return {"panel": panel}


func _check_element(data: Dictionary, panel: Dictionary, check_actions: bool, depth := 0) -> Dictionary:
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
		"row": ["type", "id", "children", "gap"],
		"column": ["type", "id", "children", "gap"],
		"grid": ["type", "id", "children", "gap", "columns"],
	}
	fields["text"].append_array(["scroll", "height"])
	fields["button"].append("open")
	for key in data:
		if not key in fields[type] and not key in ["page", "grow"]:
			return {"error": "unknown field \"%s\" for a %s (it has %s)" % [key, type, ", ".join(fields[type])]}
	var element := {"type": type, "id": data["id"]}
	if data.has("page"):
		if typeof(data["page"]) != TYPE_STRING:
			return {"error": "\"page\" must be the name of one of the panel's pages"}
		element["page"] = data["page"]
	if data.has("grow"):
		if typeof(data["grow"]) != TYPE_BOOL:
			return {"error": "\"grow\" (take the room left in its row) must be true or false"}
		element["grow"] = data["grow"]
	# In a row, column or grid, elements flow and have no "at".
	var flowing: bool = depth > 0 or panel["layout"] in ["column", "row"]
	if type in CONTAINERS:
		if not flowing:
			return {"error": "a %s goes in a panel with layout column or row, or inside another row, column or grid" % type}
		if depth >= MAX_DEPTH:
			return {"error": "rows, columns and grids go at most %d deep" % MAX_DEPTH}
		var gap = data.get("gap", GAP)
		if typeof(gap) not in [TYPE_INT, TYPE_FLOAT] or gap < 0.0 or gap > 0.2:
			return {"error": "\"gap\" must be 0 to 0.2 metres"}
		element["gap"] = float(gap)
		if type == "grid":
			element["columns"] = data.get("columns", 3)
			if typeof(element["columns"]) not in [TYPE_INT, TYPE_FLOAT] or element["columns"] < 1 or element["columns"] > 20:
				return {"error": "\"columns\" must be 1 to 20"}
			element["columns"] = int(element["columns"])
		var children = data.get("children", [])
		if typeof(children) != TYPE_ARRAY:
			return {"error": "\"children\" must be a list of elements"}
		element["children"] = []
		for child in children:
			if typeof(child) != TYPE_DICTIONARY:
				return {"error": "a child isn't an element: %s" % JSON.stringify(child).left(100)}
			var checked := _check_element(child, panel, check_actions, depth + 1)
			if checked.has("error"):
				return {"error": "in %s: element %s: %s" % [data["id"], JSON.stringify(child.get("id")), checked["error"]]}
			element["children"].append(checked["element"])
		return {"element": element}
	var in_grid: bool = panel["layout"] == "grid" and type == "button"
	if flowing:
		pass
	elif not in_grid or data.has("at"):
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
			if data.has("scroll"):
				if typeof(data["scroll"]) != TYPE_BOOL:
					return {"error": "\"scroll\" (keep the newest lines in view) must be true or false"}
				element["scroll"] = data["scroll"]
			if data.has("height"):
				if typeof(data["height"]) not in [TYPE_INT, TYPE_FLOAT] or data["height"] < 0.01 or data["height"] > 3.0:
					return {"error": "\"height\" must be 0.01 to 3 metres"}
				element["height"] = float(data["height"])
		"button", "toggle", "slider":
			element["label"] = data.get("label")
			if typeof(element["label"]) != TYPE_STRING or element["label"].is_empty() or element["label"].length() > 40:
				return {"error": "\"label\" must be text of 1 to 40 characters"}
			if data.has("open"):
				if not _good_id(data["open"]):
					return {"error": "\"open\" must be the id_panel of the menu it opens"}
				element["open"] = data["open"]
			if not (data.has("open") and not data.has("action")):
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


func _element(id_panel: String, id_element: String) -> Dictionary:
	var index := _index_of(id_panel)
	return {} if index == -1 else _find_in(panels[index]["elements"], id_element)


# Every element, including those inside rows, columns and grids.
func _flat(elements: Array) -> Array:
	var all := []
	for element in elements:
		all.append(element)
		if element.has("children"):
			all.append_array(_flat(element["children"]))
	return all


func _find_in(elements: Array, id_element: String) -> Dictionary:
	for element in _flat(elements):
		if element["id"] == id_element:
			return element
	return {}


func _remove_in(elements: Array, id_element: String) -> bool:
	for i in elements.size():
		if elements[i]["id"] == id_element:
			elements.remove_at(i)
			return true
		if elements[i].has("children") and _remove_in(elements[i]["children"], id_element):
			return true
	return false


# --- Drawing -------------------------------------------------------------------------
# Each panel is drawn the way the vrui draft drew its windows: a 2D picture
# made of Godot's own panels and labels, in a SubViewport, shown on a flat
# quad, with one box for the pointer to hit. The picture is drawn again only
# when something on it changes (_redraw), never every frame, so a window that
# isn't changing costs nothing on the Quest 1. The pointer finds the element
# under the dot from where that element sits in the picture (_control_at),
# so nothing in the picture reads the controllers.

func _drop_holder(id_panel: String) -> void:
	if _holders.has(id_panel):
		var holder: Node3D = _holders[id_panel]
		_holders.erase(id_panel)
		holder.get_parent().remove_child(holder)
		holder.queue_free()
	_views.erase(id_panel)
	if _pointing == id_panel:
		_pointing = ""
		_hovered = null


# Draws a panel from its data, replacing what was there.
# From the top: the title bar (chrome), the tabs (pages), the launcher's
# tiles (apps), the elements, and a line for notices.
func _build(id_panel: String) -> void:
	var panel: Dictionary = panels[_index_of(id_panel)]
	var old_transform := Transform3D.IDENTITY
	var had_holder := _holders.has(id_panel)
	if had_holder:
		old_transform = _holders[id_panel].global_transform
	_drop_holder(id_panel)

	var holder := Node3D.new()
	holder.name = "Panel_" + id_panel
	_place_holder(holder, panel, had_holder, old_transform)
	_holders[id_panel] = holder
	holder.visible = panel["visible"]

	var viewport := SubViewport.new()
	viewport.name = "Picture"
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true  # the pointer is worked out here, not by Godot's mouse
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	holder.add_child(viewport)
	var view := {"viewport": viewport, "controls": {}, "pointables": []}
	_views[id_panel] = view

	# The window: rounded, with an edge, like the vrui draft's.
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := _to_color(panel["color"]) if panel.has("color") else _theme_color("panel")
	frame.add_theme_stylebox_override("panel", _box(Color(back, PANEL_ALPHA), PANEL_RADIUS, _theme_color("border"), BORDER, PADDING))
	viewport.add_child(frame)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", _px(GAP))
	frame.add_child(stack)
	var above := 0  # pixels of title, tabs and tiles above the elements
	for row in [_title_bar(panel, view) if panel["chrome"] else null,
			_tabs(panel, view) if not panel["pages"].is_empty() else null,
			_app_tiles(panel, view) if panel["apps"] and not _apps.is_empty() else null]:
		if row != null:
			stack.add_child(row)
			above += int(row.get_combined_minimum_size().y) + _px(GAP)
	var content := _content(panel, view)
	stack.add_child(content)
	var notice := _label("", theme_values["font_small"], _theme_color("notice"), false, "center")
	notice.custom_minimum_size.y = _font_px(theme_values["font_small"]) * 1.4
	notice.clip_text = true
	stack.add_child(notice)
	view["notice"] = notice

	var px := frame.get_combined_minimum_size().ceil()
	px.x = maxf(px.x, 16.0)
	px.y = maxf(px.y, 16.0)
	frame.size = px
	viewport.size = Vector2i(px)

	# Where the panel's own (0, 0) sits in the picture: the centre of its
	# background for panels laid out by "at", the middle otherwise.
	var origin := px / 2.0
	if view.has("origin"):
		var inner := px.x - 2 * _px(PADDING)
		var content_x := _px(PADDING) + (inner - content.custom_minimum_size.x) / 2.0
		origin = Vector2(content_x, _px(PADDING) + above) + view["origin"]
	var scale: float = panel["scale"]
	var size_m := px / PX_PER_M * scale
	var offset := Vector3((px.x / 2.0 - origin.x) / PX_PER_M * scale, (origin.y - px.y / 2.0) / PX_PER_M * scale, 0)
	view["quad"] = size_m
	view["px"] = px

	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = size_m
	screen.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.albedo_texture = viewport.get_texture()
	screen.material_override = material
	screen.position = offset
	holder.add_child(screen)

	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = UI_LAYER
	body.collision_mask = 0
	body.set_meta("panel", id_panel)
	body.position = offset
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size_m.x, size_m.y, 0.004)
	shape.shape = box
	body.add_child(shape)
	holder.add_child(body)

	_set_pointable(holder, panel["visible"])
	if panel["visible"]:
		_since_poll = POLL_SECONDS


func _place_holder(holder: Node3D, panel: Dictionary, had_holder: bool, old_transform: Transform3D) -> void:
	match panel["place"]:
		"wrist":
			# On the back of the left wrist, tilted to face you when you look at it.
			holder.position = Vector3(0.0, 0.03, 0.08)
			holder.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
			_left.add_child(holder)
		"hand":
			# Held by a controller, where its position and rotation say
			# (relative to the controller), like the vrui draft's hand window.
			var p: Array = panel["position"]
			var r: Array = panel["rotation"]
			holder.position = Vector3(p[0], p[1], p[2])
			holder.rotation_degrees = Vector3(r[0], r[1], r[2])
			(_left if panel["hand"] == "left" else _right).add_child(holder)
		"world":
			add_child(holder)
			var p: Array = panel["position"]
			var r: Array = panel["rotation"]
			holder.global_position = Vector3(p[0], p[1], p[2])
			holder.global_rotation_degrees = Vector3(r[0], r[1], r[2])
		_:
			add_child(holder)
			if had_holder:
				holder.global_transform = old_transform  # a front panel stays where it opened


# The title bar: a back arrow when another menu opened this one, the title,
# and a close x. Pull the trigger on the bar and move to carry the window.
func _title_bar(panel: Dictionary, view: Dictionary) -> Control:
	var id_panel: String = panel["id_panel"]
	var bar := PanelContainer.new()
	bar.custom_minimum_size.y = _px(TITLE_BAR)
	_pointable(view, bar, id_panel, "", "title", "", _theme_color("title_bar"), BUTTON_RADIUS)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", _px(GAP))
	bar.add_child(row)
	var side := Vector2(_px(TITLE_BAR) * 0.8, _px(TITLE_BAR) * 0.8)
	if _openers.has(id_panel):
		row.add_child(_small_button(view, id_panel, "back", "<", side, _theme_color("button")))
	var title := _label(panel["title"], theme_values["font_title"], _theme_color("title"), false, "left")
	_one_line(title, 0.0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var close := _small_button(view, id_panel, "close", "x", side, _theme_color("button"))
	close.set_meta("hover", _theme_color("danger"))
	row.add_child(close)
	return bar


func _small_button(view: Dictionary, id_panel: String, kind: String, text: String, size: Vector2, color: Color) -> Control:
	var button := PanelContainer.new()
	button.custom_minimum_size = size
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pointable(view, button, id_panel, "", kind, "", color, BUTTON_RADIUS)
	var label := _label(text, theme_values["font_title"], _theme_color("text"), false, "center")
	_one_line(label, size.x - 2 * _px(BUTTON_PADDING))
	button.add_child(label)
	return button


func _tabs(panel: Dictionary, view: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", _px(GAP))
	for page in panel["pages"]:
		var color := _theme_color("accent") if page == panel["page"] else _theme_color("button")
		var tab := PanelContainer.new()
		tab.custom_minimum_size = Vector2(_px(0.08), _px(TAB_BAR))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_pointable(view, tab, panel["id_panel"], "", "tab", page, color, BUTTON_RADIUS)
		var label := _label(page, theme_values["font_small"], _theme_color("text"), false, "center")
		_one_line(label, 0.0)
		tab.add_child(label)
		row.add_child(tab)
	return row


# The launcher's tiles, in rows above the panel's own elements. They share
# the panel's width (its "size") between them; a panel without one gets
# tiles APP_CELL wide.
func _app_tiles(panel: Dictionary, view: Dictionary) -> Control:
	var grid := GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = mini(_apps.size(), APP_COLUMNS)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var cell := APP_CELL
	if panel.has("size"):
		cell.x = (panel["size"][0] - GAP * (grid.columns - 1)) / grid.columns
	grid.add_theme_constant_override("h_separation", _px(GAP))
	grid.add_theme_constant_override("v_separation", _px(GAP))
	for app in _apps:
		var open: bool = not app["panel"].is_empty() and _index_of(app["panel"]) != -1 and panels[_index_of(app["panel"])]["visible"]
		var tile := PanelContainer.new()
		tile.name = "App_" + app["id"]
		tile.custom_minimum_size = (cell * PX_PER_M).floor()
		_pointable(view, tile, panel["id_panel"], "", "app", app["id"], _theme_color("accent") if open else _theme_color("button"), BUTTON_RADIUS)
		var label := _label(app["label"], theme_values["font_body"], _theme_color("text"), false, "center")
		_one_line(label, tile.custom_minimum_size.x - 2 * _px(BUTTON_PADDING))
		tile.add_child(label)
		grid.add_child(tile)
	view["apps"] = grid
	return grid


# The panel's elements: placed by their "at" (layout free or grid, as panels
# always were), or flowing in a column or row (layout column or row), where
# rows, columns and grids of elements can sit inside each other.
func _content(panel: Dictionary, view: Dictionary) -> Control:
	var id_panel: String = panel["id_panel"]
	var shown: Array = panel["elements"].filter(func(e): return not e.has("page") or e["page"] == panel["page"])
	if panel["layout"] in ["column", "row"]:
		var flow: BoxContainer = VBoxContainer.new() if panel["layout"] == "column" else HBoxContainer.new()
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flow.add_theme_constant_override("separation", _px(GAP))
		if panel.has("size"):
			flow.custom_minimum_size = Vector2(panel["size"][0], panel["size"][1]) * PX_PER_M
		for element in shown:
			flow.add_child(_control_for(id_panel, element, view, Vector2.ZERO))
		return flow

	# Placed by "at": the content is the box round the background and every
	# element, in metres from the panel's centre (y up).
	var placed := []  # [element, at, size]
	var grid_buttons: Array = panel["elements"].filter(func(e): return e["type"] == "button" and not e.has("at"))
	var grid_index := 0
	var left := 0.0
	var right := 0.0
	var top := 0.0
	var bottom := 0.0
	if panel.has("size"):
		left = -panel["size"][0] / 2.0
		right = -left
		top = panel["size"][1] / 2.0
		bottom = -top
	# Buttons with no "at" sit in a grid of "columns". In a panel with a
	# "size" the grid fills its width and sits in its middle; otherwise each
	# button is "cell" big and the first row is at the centre.
	var cell_size: Array = panel.get("cell", [0.14, 0.07])
	var cell := Vector2(cell_size[0], cell_size[1])
	var per_row: int = clampi(panel.get("columns", 4), 1, maxi(1, grid_buttons.size()))
	var cell_gap := cell.y * 0.25
	var first_row := 0.0
	if panel.has("size") and not grid_buttons.is_empty():
		cell.x = (panel["size"][0] - cell_gap * (per_row - 1)) / per_row
		var rows := ceili(grid_buttons.size() / float(per_row))
		first_row = (rows * cell.y + (rows - 1) * cell_gap) / 2.0 - cell.y / 2.0
	for element in panel["elements"]:
		var at := Vector2.ZERO
		var size := Vector2.ZERO
		if element.has("at"):
			at = Vector2(element["at"][0], element["at"][1])
		if element["type"] == "button" and not element.has("at"):
			var row := grid_index / per_row
			var in_row := mini(per_row, grid_buttons.size() - row * per_row)
			var col := grid_index % per_row
			at = Vector2((col - (in_row - 1) / 2.0) * (cell.x + cell_gap), first_row - row * (cell.y + cell_gap))
			size = cell
			grid_index += 1
		elif element.has("size"):
			size = Vector2(element["size"][0], element["size"][1])
		elif element["type"] == "input":
			size = Vector2(element["width"], element["font_size"] * TEXT_PIXEL * 1.6)
		var box := Rect2(at.x - size.x / 2.0, at.y - size.y / 2.0, size.x, size.y)
		if element["type"] == "text":
			# "at" is the top-centre of a block of text "width" wide, one line
			# or "height" tall.
			var tall: float = element.get("height", element["font_size"] * TEXT_PIXEL * 1.4)
			box = Rect2(at.x - element["width"] / 2.0, at.y - tall, element["width"], tall)
		left = minf(left, box.position.x)
		right = maxf(right, box.end.x)
		bottom = minf(bottom, box.position.y)
		top = maxf(top, box.end.y)
		if not element.has("page") or element["page"] == panel["page"]:
			placed.append([element, box])
	var area := Control.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.clip_contents = true
	area.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	area.custom_minimum_size = Vector2(right - left, top - bottom) * PX_PER_M
	for item in placed:
		var box: Rect2 = item[1]
		var control := _control_for(id_panel, item[0], view, box.size * PX_PER_M)
		control.position = Vector2(box.position.x - left, top - box.end.y) * PX_PER_M
		if item[0]["type"] == "text" and not item[0].has("height"):
			# Text runs on down the panel, as Label3D text did; it's cut off
			# at the bottom of the panel.
			control.size = Vector2(box.size.x * PX_PER_M, (top - bottom) * PX_PER_M - control.position.y)
			control.clip_text = true
		else:
			control.size = box.size * PX_PER_M
		area.add_child(control)
	view["origin"] = Vector2(-left, top) * PX_PER_M
	return area


# One element as a Control. `size` is its size in pixels when it's placed by
# "at"; in a row or column it takes its own "size" (or what it needs).
func _control_for(id_panel: String, element: Dictionary, view: Dictionary, size: Vector2) -> Control:
	var control: Control
	var own := Vector2(element["size"][0], element["size"][1]) * PX_PER_M if element.has("size") else Vector2.ZERO
	if size == Vector2.ZERO:
		size = own
	var color := _color_of(element) if TYPE_COLORS.has(element["type"]) else Color.TRANSPARENT
	match element["type"]:
		"text":
			var label := _label(element["text"] if not element.has("source") else element["source"].get("empty", ""), element["font_size"], color, element["mono"], element["align"])
			label.text = _live_text.get(id_panel + "/" + element["id"], label.text)
			label.custom_minimum_size.x = element["width"] * PX_PER_M
			# Wrapped text measures its height at its width; until the layout
			# runs it has none and would count a line per letter.
			label.size.x = label.custom_minimum_size.x
			if element.has("height"):
				label.custom_minimum_size.y = element["height"] * PX_PER_M
				label.clip_text = true
			if element.get("scroll", false):
				label.clip_text = true
				label.resized.connect(func(): _fit_scroll(id_panel, element["id"]))
			control = label
		"button":
			control = PanelContainer.new()
			_pointable(view, control, id_panel, element["id"], "element", "", color, BUTTON_RADIUS)
			var label := _label(element["label"], _button_font(size), _theme_color("text"), false, "center")
			_one_line(label, size.x - 2 * _px(BUTTON_PADDING) if size.x > 0.0 else 0.0)
			control.add_child(label)
		"input":
			control = PanelContainer.new()
			_pointable(view, control, id_panel, element["id"], "element", "", _theme_color("input_bg"), BUTTON_RADIUS * 0.5)
			control.remove_meta("hover")  # an input box doesn't light up; the one being typed into has an edge
			control.set_meta("still", true)
			var text := _label("", element["font_size"], color, false, "left")
			text.name = "Text"
			text.clip_text = true
			control.add_child(text)
			if size == Vector2.ZERO:
				size = Vector2(element["width"], element["font_size"] * TEXT_PIXEL * 1.6) * PX_PER_M
		"box":
			control = Panel.new()
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
			control.add_theme_stylebox_override("panel", _box(color, BUTTON_RADIUS * 0.5))
		"toggle":
			# The label, and on the right a light that is lit while it's on.
			control = PanelContainer.new()
			_pointable(view, control, id_panel, element["id"], "element", "", color, BUTTON_RADIUS)
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			control.add_child(row)
			var label := _label(element["label"], _button_font(size), _theme_color("text"), false, "left")
			_one_line(label, size.x - 2 * _px(BUTTON_PADDING) - _px(0.05) - _px(GAP) if size.x > 0.0 else 0.0)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(label)
			var light := PanelContainer.new()
			light.name = "Light"
			light.mouse_filter = Control.MOUSE_FILTER_IGNORE
			light.custom_minimum_size = Vector2(_px(0.05), 0)
			light.add_child(_label("", theme_values["font_small"], _theme_color("text"), false, "center"))
			row.add_child(light)
			_show_toggle(control, element)
		"slider":
			# The label and value on top, the track below with its filled part
			# and a knob; the whole area takes the pointer.
			control = PanelContainer.new()
			_pointable(view, control, id_panel, element["id"], "element", "", _theme_color("button"), BUTTON_RADIUS)
			var inside := Control.new()
			inside.name = "Inside"
			inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
			control.add_child(inside)
			var label := _label("", theme_values["font_small"], _theme_color("text"), false, "left")
			label.name = "Label"
			inside.add_child(label)
			for part in [["Track", _theme_color("input_bg")], ["Fill", color], ["Knob", _theme_color("text")]]:
				var piece := Panel.new()
				piece.name = part[0]
				piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
				piece.add_theme_stylebox_override("panel", _box(part[1], 0.003))
				inside.add_child(piece)
			inside.resized.connect(func(): _show_slider(control, _element(id_panel, element["id"]), element["value"], id_panel))
		"row", "column", "grid":
			var box: Container
			match element["type"]:
				"row":
					box = HBoxContainer.new()
				"column":
					box = VBoxContainer.new()
				_:
					box = GridContainer.new()
					box.columns = element["columns"]
			var gap := _px(element.get("gap", GAP))
			if box is BoxContainer:
				box.add_theme_constant_override("separation", gap)
			else:
				box.add_theme_constant_override("h_separation", gap)
				box.add_theme_constant_override("v_separation", gap)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for child in element["children"]:
				box.add_child(_control_for(id_panel, child, view, Vector2.ZERO))
			control = box
	control.name = "E_" + element["id"]
	control.custom_minimum_size = control.custom_minimum_size.max(size)
	if element.get("grow", false):
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view["controls"][element["id"]] = control
	if element["type"] == "input":
		_show_input_control(id_panel, element, control)
	return control


# Makes a Control something the pointer can hover and press.
func _pointable(view: Dictionary, control: Control, id_panel: String, id_element: String, kind: String, value: String, color: Color, radius: float) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _box(color, radius, Color.TRANSPARENT, 0.0, BUTTON_PADDING)
	control.add_theme_stylebox_override("panel", style)
	control.set_meta("panel", id_panel)
	control.set_meta("element", id_element)
	control.set_meta("kind", kind)
	control.set_meta("value", value)
	control.set_meta("color", color)
	control.set_meta("hover", color.lightened(0.25))
	control.set_meta("style", style)
	view["pointables"].append(control)


# The element under a point in a panel's picture, or null.
func _control_at(id_panel: String, point: Vector2) -> Control:
	if not _views.has(id_panel):
		return null
	var list: Array = _views[id_panel]["pointables"]
	for i in range(list.size() - 1, -1, -1):
		var control: Control = list[i]
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(point):
			return control
	return null


# Where a point in the world falls in a panel's picture, in pixels.
func _picture_point(id_panel: String, world: Vector3) -> Vector2:
	var view: Dictionary = _views[id_panel]
	var screen := _holders[id_panel].get_node("Screen") as Node3D
	var local := screen.global_transform.affine_inverse() * world
	var quad: Vector2 = view["quad"]
	var px: Vector2 = view["px"]
	return Vector2((local.x / quad.x + 0.5) * px.x, (0.5 - local.y / quad.y) * px.y)


# Draws a panel's picture once more, on the next frame.
func _redraw(id_panel: String) -> void:
	if _views.has(id_panel):
		(_views[id_panel]["viewport"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


func _set_label_text(id_panel: String, id_element: String, text: String) -> void:
	var label := _find_node(id_panel, id_element) as Label
	if label and label.text != text:
		label.text = text
		_fit_scroll(id_panel, id_element)
		_redraw(id_panel)


# A text with "scroll" shows its newest lines (or as far back as it's been
# scrolled), whatever its wrapped lines come to at its real width.
func _fit_scroll(id_panel: String, id_element: String) -> void:
	var label := _find_node(id_panel, id_element) as Label
	var element := _element(id_panel, id_element)
	if label == null or not element.get("scroll", false):
		return
	label.lines_skipped = 0
	# A row is the font's height plus the theme's line spacing.
	var spacing := label.get_theme_constant("line_spacing")
	var shown := maxi(1, int((label.size.y + spacing) / maxf(label.get_line_height() + spacing, 1.0)))
	var lines := label.get_line_count()
	var back := clampi(_scroll.get(id_panel + "/" + id_element, 0), 0, maxi(0, lines - shown))
	_scroll[id_panel + "/" + id_element] = back
	label.lines_skipped = maxi(0, lines - shown - back)
	label.max_lines_visible = shown


# Scrolls a text element with "scroll": `lines` more goes back (older), less
# goes forward, 0 returns to the newest. Returns how far back it now is.
func scroll_text(id_panel: String, id_element: String, lines: int) -> int:
	var key := id_panel + "/" + id_element
	_scroll[key] = 0 if lines == 0 else maxi(0, _scroll.get(key, 0) + lines)
	_fit_scroll(id_panel, id_element)
	_redraw(id_panel)
	return _scroll[key]


func _scroll_command(request: Dictionary) -> Dictionary:
	var id_panel := str(request.get("id_panel"))
	var element := _element(id_panel, str(request.get("id_element")))
	if not element.get("scroll", false):
		return {"ok": false, "error": "no text with \"scroll\" called \"%s\" on panel \"%s\"" % [str(request.get("id_element")), id_panel]}
	var lines = request.get("lines")
	if typeof(lines) not in [TYPE_INT, TYPE_FLOAT]:
		return {"ok": false, "error": "ui_scroll needs \"lines\": more to go back, fewer to go forward, 0 for the newest"}
	return {"ok": true, "back": scroll_text(id_panel, element["id"], int(lines))}


func _show_toggle(control: Control, element: Dictionary) -> void:
	var light := control.find_child("Light", true, false) as PanelContainer
	light.add_theme_stylebox_override("panel", _box(_theme_color("ok") if element["on"] else _theme_color("input_bg"), BUTTON_RADIUS * 0.5))
	var word := light.get_child(0) as Label
	word.text = "ON" if element["on"] else "OFF"
	word.add_theme_color_override("font_color", _theme_color("text") if element["on"] else _theme_color("muted"))


func _show_slider(control: Control, element: Dictionary, value: float, id_panel: String) -> void:
	if element.is_empty() or not is_instance_valid(control):
		return
	var inside := control.get_node("Inside") as Control
	var area := inside.size
	var t: float = (value - element["min"]) / (element["max"] - element["min"])
	var label := inside.get_node("Label") as Label
	label.text = "%s  %s" % [element["label"], _value_text(element, value)]
	label.position = Vector2.ZERO
	label.size = Vector2(area.x, area.y * 0.5)
	var track := Vector2(area.x, maxf(area.y * 0.18, 4.0))
	var y := area.y * 0.72 - track.y / 2.0
	(inside.get_node("Track") as Control).position = Vector2(0, y)
	(inside.get_node("Track") as Control).size = track
	(inside.get_node("Fill") as Control).position = Vector2(0, y)
	(inside.get_node("Fill") as Control).size = Vector2(maxf(track.x * t, 1.0), track.y)
	var knob := Vector2(track.y * 1.4, track.y * 2.4)
	(inside.get_node("Knob") as Control).position = Vector2(track.x * t - knob.x / 2.0, y + track.y / 2.0 - knob.y / 2.0)
	(inside.get_node("Knob") as Control).size = knob
	_redraw(id_panel)


func _value_text(element: Dictionary, value: float) -> String:
	if element["step"] >= 1.0 and is_equal_approx(element["step"], roundf(element["step"])):
		return str(int(roundf(value)))
	return String.num(value, 2)


# Shows a toggle's or slider's state after it changed, in place.
func _show_state(id_panel: String, element: Dictionary) -> void:
	var control := _find_node(id_panel, element["id"]) as Control
	if control == null:
		return
	if element["type"] == "toggle":
		_show_toggle(control, element)
		_redraw(id_panel)
	else:
		_show_slider(control, element, element["value"], id_panel)


# A hidden panel is still in the physics world; without this the pointer
# would find (and press) it where the panel was.
func _set_pointable(holder: Node3D, on: bool) -> void:
	var body := holder.get_node_or_null("Body") as StaticBody3D
	if body:
		body.collision_layer = UI_LAYER if on else 0


func _label(text: String, font_size: int, color: Color, mono: bool, align: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", _font_px(font_size))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = ALIGNS[align]
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if align == "center" else VERTICAL_ALIGNMENT_TOP
	if mono:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["monospace"])
		label.add_theme_font_override("font", font)
	return label


# A label that stays on one line: a button's, tile's, tab's or title's.
# Its text shrinks to fit `width` pixels (down to SMALLEST_LABEL) rather
# than breaking a word, and is cut short with "..." if it still doesn't fit.
# A width of 0 is unknown (it's set by the layout): it is only cut short.
func _one_line(label: Label, width: float) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	if width <= 0.0:
		return
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var smallest := mini(font_size, _font_px(SMALLEST_LABEL))
	while font_size > smallest and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


# Rounded corners and an optional edge, sizes in metres.
func _box(color: Color, radius: float, edge := Color.TRANSPARENT, edge_width := 0.0, padding := 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(_px(radius))
	style.anti_aliasing = true
	if edge_width > 0.0:
		style.border_color = edge
		style.set_border_width_all(maxi(1, _px(edge_width)))
	style.set_content_margin_all(_px(padding))
	return style


func _px(metres: float) -> int:
	return int(roundf(metres * PX_PER_M))


# A text size as panels have always given it (Label3D's, at TEXT_PIXEL metres
# a pixel) in this picture's pixels, so text stays the same size in the world.
func _font_px(font_size: int) -> int:
	return maxi(8, int(roundf(font_size * TEXT_PIXEL * PX_PER_M)))


func _button_font(size: Vector2) -> int:
	var fit: int = int(size.y / (TEXT_PIXEL * PX_PER_M) * 0.5) if size.y > 0.0 else theme_values["font_body"]
	return clampi(fit, 16, theme_values["font_body"])


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


func _find_node(id_panel: String, id_element: String) -> Node:
	if not _views.has(id_panel):
		return null
	return _views[id_panel]["controls"].get(id_element)


func _show_input(id_panel: String, id_element: String) -> void:
	var node := _find_node(id_panel, id_element) as Control
	var element := _element(id_panel, id_element)
	if node and not element.is_empty():
		_show_input_control(id_panel, element, node)


func _show_input_control(id_panel: String, element: Dictionary, control: Control) -> void:
	var key: String = id_panel + "/" + element["id"]
	var text: String = element["prompt"] + _inputs.get(key, "")
	if key == _focus:
		text += "_" + (" (SHIFT)" if _shift else "")
	(control.get_node("Text") as Label).text = text
	# The box being typed into has a lit edge.
	var style := control.get_meta("style") as StyleBoxFlat
	style.border_color = _theme_color("accent")
	style.set_border_width_all(maxi(2, _px(0.002)) if key == _focus else 0)
	_redraw(id_panel)


func _notice(id_panel: String, text: String) -> void:
	if not _views.has(id_panel):
		return
	var notice := _views[id_panel]["notice"] as Label
	notice.text = text.left(200)
	_redraw(id_panel)
	get_tree().create_timer(NOTICE_SECONDS).timeout.connect(func():
		if is_instance_valid(notice) and notice.text == text.left(200):
			notice.text = ""
			_redraw(id_panel))


# Pointing at something you can press lights it up, with a light tick;
# plain text and backgrounds don't react.
func _set_hover(control: Control, on: bool) -> void:
	if control == null or not is_instance_valid(control) or not control.has_meta("hover"):
		return
	(control.get_meta("style") as StyleBoxFlat).bg_color = control.get_meta("hover") if on else control.get_meta("color")
	_redraw(control.get_meta("panel"))
	if on:
		_pulse(0.1, 0.01)


# A press flashes the button for a moment, so you see it went in.
func _flash(control: Control) -> void:
	if control == null or not is_instance_valid(control) or not control.has_meta("style"):
		return
	var style := control.get_meta("style") as StyleBoxFlat
	var id_panel: String = control.get_meta("panel")
	style.bg_color = _theme_color("press")
	_redraw(id_panel)
	var id := control.get_instance_id()  # the press may redraw the panel, so not the control itself
	get_tree().create_timer(PRESS_SECONDS).timeout.connect(func():
		var still := instance_from_id(id) as Control
		if still and is_instance_valid(still):
			style.bg_color = still.get_meta("hover", still.get_meta("color")) if still == _hovered else still.get_meta("color")
			_redraw(id_panel))


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
