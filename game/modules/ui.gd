extends SlopitectModule

# Slopitect: every window in the app, as data.
# A panel is a list of elements (text, buttons, input boxes, plain boxes)
# with a place: in front of you when it opens, on the left wrist, or fixed in
# the world. The menu bar, the wrist panel and the agent's chat window are
# all panels, and you or the agent can change, add, move and remove any of
# them while the app runs, with the ui_* commands. Everything is saved on the
# headset and loaded at the next start.
#
# In the headset: point with the right controller and pull the trigger to
# press a button or pick an input box; hold the right grip while pointing at
# a panel to move it (it then stays where you let go). A panel can have a
# controller button that shows and hides it ("toggle").
#
# A button's action is any command. In an action, "in_front" as a position
# means 1 m in front of you when pressed, and "{input:ID}" is replaced by
# what's typed in that panel's input box ID.
# A text element can show a live value: its "source" is a read-only command
# (list, modules, or one ending in _status or _list), run twice a second
# while the panel is shown.

const SAVE_PATH := "user://ui.json"
const OLD_MENU_PATH := "user://menu.json"  # the menu module's file, before panels
const UI_LAYER := 1 << 19  # physics layer 20, used only by panels
const LASER_LENGTH := 3.0
const POLL_SECONDS := 0.5
const NOTICE_SECONDS := 5.0
const MAX_PANELS := 30
const MAX_ELEMENTS := 150
const MAX_TEXT := 4000
const MAX_INPUT := 500
const PLACES := ["front", "wrist", "world"]
const LAYOUTS := ["free", "grid"]
const ELEMENT_TYPES := ["text", "button", "input", "box"]
const ALIGNS := {"left": HORIZONTAL_ALIGNMENT_LEFT, "center": HORIZONTAL_ALIGNMENT_CENTER, "right": HORIZONTAL_ALIGNMENT_RIGHT}
# Controller buttons a panel can be shown and hidden with. The right trigger
# and grip are kept for pointing and moving, and the left X always stops the
# agent (the agent module's), so no panel can take them.
const TOGGLES := {
	"": [],
	"left_menu": ["left", "menu_button"],
	"left_y": ["left", "by_button"],
	"right_b": ["right", "by_button"],
	"right_a": ["right", "ax_button"],
}
const SOURCE_COMMANDS := ["list", "modules"]  # plus any ending in _status or _list
const BUTTON_COLOR := Color(0.12, 0.13, 0.16)
const HOVER_COLOR := Color(0.25, 0.45, 0.9)
const TEXT_PIXEL := 0.0006

var panels: Array = []  # [panel dictionaries], see _check_panel
# While a question from the confirm module is up, the pointer only works on
# it, so no panel can sit in front of it or be pressed instead.
var pointer_blocked := false

var _server: Node
var _camera: XRCamera3D
var _left: XRController3D
var _right: XRController3D
var _holders := {}  # id_panel -> Node3D
var _inputs := {}  # "panel/element" -> typed text (not saved)
var _focus := ""  # "panel/element" of the input box that typing goes to
var _shift := false
var _ray: RayCast3D
var _laser: MeshInstance3D
var _hovered: StaticBody3D
var _dragging := ""  # id_panel being moved with the grip
var _drag_offset: Transform3D
var _since_poll := 0.0


func setup() -> String:
	_server = ctx["server"]
	_camera = ctx["camera"]
	_left = ctx["left"]
	_right = ctx["right"]

	register("ui_list", _list, "list the panels: id, title, place, shown or not, toggle button, number of elements")
	register("ui_get", _get_panel, "a panel's full data, including what's typed in its input boxes: id_panel")
	register("ui_add", _add, "add a panel: id_panel, optional title, place (front, wrist, world), distance, height, position, rotation, size, color, visible, toggle (%s), layout (free or grid with columns and cell), elements" % ", ".join(TOGGLES.keys().slice(1)))
	register("ui_update", _update, "change any of a panel's fields (elements replaces them all): id_panel, then the fields")
	register("ui_remove", _remove, "remove a panel: id_panel")
	register("ui_show", _show, "show or hide a panel: id_panel, visible (true/false)")
	register("ui_element_add", _element_add, "add an element to a panel: id_panel, element ({type: text|button|input|box, id, at [x,y], ...}), optional index")
	register("ui_element_update", _element_update, "change an element's fields: id_panel, id_element, then the fields")
	register("ui_element_remove", _element_remove, "remove an element: id_panel, id_element")
	register("ui_press", _press_command, "press a button, as if pointed at and clicked: id_panel, id_element")
	register("ui_type", _type_command, "type text into the selected input box: text")
	register("ui_key", _key_command, "a key for the selected input box: key (shift, backspace, clear)")
	register("ui_reset", _reset, "put the default panels back: optional id_panel for just that one")

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -LASER_LENGTH)
	_ray.collision_mask = UI_LAYER
	_ray.collide_with_areas = false
	_right.add_child(_ray)

	_laser = MeshInstance3D.new()
	var laser_mesh := BoxMesh.new()
	laser_mesh.size = Vector3(0.002, 0.002, 1.0)
	_laser.mesh = laser_mesh
	var laser_material := StandardMaterial3D.new()
	laser_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_material.albedo_color = Color(0.4, 0.7, 1.0)
	_laser.material_override = laser_material
	_right.add_child(_laser)

	_left.button_pressed.connect(_on_button.bind("left"))
	_right.button_pressed.connect(_on_button.bind("right"))
	_right.button_released.connect(_on_right_released)

	_load()
	for panel in panels:
		# Panels that open in front of you start hidden: at start-up the
		# headset's position isn't known yet.
		if panel["place"] == "front":
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
		return
	var length := LASER_LENGTH
	if _hovered:
		length = _right.global_position.distance_to(_ray.get_collision_point())
	# Only show the laser while a panel is out that it can point at.
	_laser.visible = _hovered != null or _any_open()
	_laser.scale = Vector3(1, 1, length)
	_laser.position = Vector3(0, 0, -length / 2.0)


func _process(delta: float) -> void:
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


# --- Controllers ---------------------------------------------------------------

func _on_button(button: String, hand: String) -> void:
	if hand == "right" and button == "trigger_click":
		_on_point_pressed()
		return
	if hand == "right" and button == "grip_click":
		_start_drag()
		return
	for panel in panels:
		var toggle: Array = TOGGLES[panel["toggle"]]
		if not toggle.is_empty() and toggle[0] == hand and toggle[1] == button:
			_set_visible(panel, not panel["visible"])
			print("Slopitect ui: \"%s\" %s" % [panel["id_panel"], "shown" if panel["visible"] else "hidden"])


func _on_right_released(button: String) -> void:
	if button != "grip_click" or _dragging.is_empty():
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
	_save()
	print("Slopitect ui: moved \"%s\" to %s" % [panel["id_panel"], panel["position"]])


func _start_drag() -> void:
	if not _hovered:
		return
	var id_panel: String = _hovered.get_meta("panel")
	var index := _index_of(id_panel)
	if index == -1 or panels[index]["place"] == "wrist":
		return  # the wrist panel moves with your wrist
	_dragging = id_panel
	_drag_offset = _right.global_transform.affine_inverse() * _holders[id_panel].global_transform


func _on_point_pressed() -> void:
	if not _hovered:
		return
	var id_panel: String = _hovered.get_meta("panel")
	var id_element: String = _hovered.get_meta("element")
	var element := _element(id_panel, id_element)
	if element.is_empty():
		return
	if element["type"] == "input":
		_set_focus(id_panel + "/" + id_element)
	elif element["type"] == "button":
		press(id_panel, id_element)


func _set_visible(panel: Dictionary, on: bool) -> void:
	if on and panel["place"] == "front":
		_place_in_front(panel)
	panel["visible"] = on
	_holders[panel["id_panel"]].visible = on
	if on:
		_since_poll = POLL_SECONDS
		if _focus.is_empty() or not _element_visible(_focus):
			_focus_first_input(panel["id_panel"])
	if panel["place"] != "front":
		_save()  # panels that open in front always start hidden, so aren't saved for this


# In front of you, at the panel's distance and height, facing your eyes.
func _place_in_front(panel: Dictionary) -> void:
	var holder: Node3D = _holders[panel["id_panel"]]
	var head := _camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	holder.global_position = head.origin + forward * panel["distance"] + Vector3(0, panel["height"], 0)
	holder.look_at(head.origin, Vector3.UP, true)


# A point 1 m in front of you at chest height, in World coordinates.
func _in_front() -> Array:
	var head := _camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var p := head.origin + forward * 1.0 + Vector3(0, -0.3, 0)
	return [p.x, p.y, p.z]


# --- Pressing and typing ---------------------------------------------------------

# Runs a button's action as if it came through the command server. A failure
# shows under the panel for a few seconds, so you see it in the headset.
func press(id_panel: String, id_element: String) -> Dictionary:
	var element := _element(id_panel, id_element)
	if element.is_empty() or element["type"] != "button":
		return {"ok": false, "error": "no button \"%s\" on panel \"%s\" (ui_get shows its elements)" % [id_element, id_panel]}
	var action = _fill_action(element["action"].duplicate(true), id_panel)
	print("Slopitect ui: pressed \"%s/%s\"" % [id_panel, id_element])
	var reply: Dictionary = _server.run(action)
	if reply.get("wait") is SlopitectPending:
		# It waits for your answer in the headset; this button's follow-up
		# (clearing its input, showing a failure) happens when it's given.
		_notice(id_panel, "%s: waiting for your answer" % element["label"])
		_after_press(id_panel, element, reply["wait"])
		return reply
	_pressed(id_panel, element, reply)
	return reply


func _after_press(id_panel: String, element: Dictionary, pending: SlopitectPending) -> void:
	if not pending.finished:
		await pending.done
	_notice(id_panel, "")
	_pressed(id_panel, element, pending.result)


func _pressed(id_panel: String, element: Dictionary, reply: Dictionary) -> void:
	var id_element: String = element["id"]
	if reply.get("ok", false):
		if element.has("clear_input"):
			_inputs[id_panel + "/" + element["clear_input"]] = ""
			_show_input(id_panel, element["clear_input"])
	else:
		var error := String(reply.get("error", "?"))
		print("Slopitect ui: \"%s/%s\" failed: %s" % [id_panel, id_element, error])
		_notice(id_panel, "%s: %s" % [element["label"], error])


func _fill_action(value, id_panel: String):
	if value is Dictionary:
		for key in value:
			if key == "position" and value[key] is String and value[key] == "in_front":
				value[key] = _in_front()
			else:
				value[key] = _fill_action(value[key], id_panel)
	elif value is Array:
		for i in value.size():
			value[i] = _fill_action(value[i], id_panel)
	elif value is String and value.begins_with("{input:") and value.ends_with("}"):
		return _inputs.get(id_panel + "/" + value.trim_prefix("{input:").trim_suffix("}"), "")
	return value


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
	if _focus.begins_with(removed["id_panel"] + "/"):
		_focus = ""
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
		if not key in ["id_panel", "title", "place", "distance", "height", "position", "rotation", "size", "color", "visible", "toggle", "layout", "columns", "cell", "elements"]:
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
	panel["color"] = data.get("color", "#0b0d11")
	if not _good_color(panel["color"]):
		return {"error": "panel %s: \"color\" must be a colour name or #rrggbb" % id}
	panel["visible"] = data.get("visible", false)
	if typeof(panel["visible"]) != TYPE_BOOL:
		return {"error": "panel %s: \"visible\" must be true or false" % id}
	panel["toggle"] = data.get("toggle", "")
	if not panel["toggle"] in TOGGLES:
		return {"error": "panel %s: \"toggle\" must be one of %s (or \"\" for none)" % [id, TOGGLES.keys().slice(1)]}
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
	}
	for key in data:
		if not key in fields[type]:
			return {"error": "unknown field \"%s\" for a %s (it has %s)" % [key, type, ", ".join(fields[type])]}
	var element := {"type": type, "id": data["id"]}
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
	if type in ["button", "box"] and not in_grid:
		element["size"] = data.get("size", [0.14, 0.07])
		if not _numbers(element["size"], 2, 0.005, 3.0):
			return {"error": "\"size\" must be [width, height] in metres, 0.005 to 3"}
	var default_color := {"text": "#ffffff", "button": "#" + BUTTON_COLOR.to_html(false), "input": "#b3e6ff", "box": "#08100a"}
	element["color"] = data.get("color", default_color[type])
	if not _good_color(element["color"]):
		return {"error": "\"color\" must be a colour name or #rrggbb"}
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
		"button":
			element["label"] = data.get("label")
			if typeof(element["label"]) != TYPE_STRING or element["label"].is_empty() or element["label"].length() > 40:
				return {"error": "\"label\" must be text of 1 to 40 characters"}
			var action = data.get("action")
			if typeof(action) != TYPE_DICTIONARY or typeof(action.get("cmd")) != TYPE_STRING:
				return {"error": "\"action\" must be a command, like {\"cmd\": \"spawn\", \"shape\": \"box\"}"}
			if check_actions and not action["cmd"] in _server.commands():
				return {"error": "\"action\" uses unknown cmd \"%s\"" % action["cmd"]}
			if action["cmd"] == "ui_press":
				return {"error": "a button can't press another button"}
			if action["cmd"].ends_with("_config"):
				return {"error": "settings (%s) can only be changed from the PC, not by a button" % action["cmd"]}
			element["action"] = action
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


func _check_source(source) -> String:
	if typeof(source) != TYPE_DICTIONARY or typeof(source.get("cmd")) != TYPE_STRING:
		return "\"source\" must be {\"cmd\": a read-only command, optional field, last, chars, empty}"
	for key in source:
		if not key in ["cmd", "field", "last", "chars", "empty"]:
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
	return ""


func _good_id(id) -> bool:
	if typeof(id) != TYPE_STRING or id.is_empty() or id.length() > 40:
		return false
	for ch in id:
		if not (ch == "_" or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")):
			return false
	return true


func _good_color(value) -> bool:
	return typeof(value) == TYPE_STRING and (Color.html_is_valid(value) or Color.from_string(value, Color(-1, -1, -1)) != Color(-1, -1, -1))


func _to_color(value: String) -> Color:
	return Color.html(value) if Color.html_is_valid(value) else Color.from_string(value, Color.WHITE)


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

	if panel.has("size"):
		var back := _make_body(id_panel, "", Vector2(panel["size"][0], panel["size"][1]), Vector3(0, 0, -0.004), _to_color(panel["color"]))
		holder.add_child(back)

	var grid_index := 0
	var grid_buttons: Array = panel["elements"].filter(func(e): return e["type"] == "button" and not e.has("at"))
	for element in panel["elements"]:
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
		holder.add_child(_make_element(id_panel, element, at, size))

	var notice := _make_label(Vector3(0, _bottom_of(panel) - 0.03, 0.002), 0.6, 26, Color(1.0, 0.45, 0.4), false, "center")
	notice.name = "Notice"
	holder.add_child(notice)
	if panel["visible"]:
		_since_poll = POLL_SECONDS


func _make_element(id_panel: String, element: Dictionary, at: Vector3, size: Vector2) -> Node3D:
	var node: Node3D
	match element["type"]:
		"box":
			node = MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = size
			node.mesh = quad
			node.material_override = _flat_material(_to_color(element["color"]))
			node.position = at + Vector3(0, 0, -0.002)
		"text":
			# A Label3D's text starts at its origin when left-aligned (ends there
			# when right-aligned), so shift it to put the block's top-centre at "at".
			var shift := {"left": -element["width"] / 2.0, "center": 0.0, "right": element["width"] / 2.0}
			node = _make_label(at + Vector3(shift[element["align"]], 0, 0), element["width"], element["font_size"], _to_color(element["color"]), element["mono"], element["align"])
			node.text = element["text"] if not element.has("source") else element["source"].get("empty", "")
		"button":
			node = _make_body(id_panel, element["id"], size, at, _to_color(element["color"]))
			node.set_meta("color", _to_color(element["color"]))
			var label := Label3D.new()
			label.text = element["label"]
			label.pixel_size = size.y / 140.0
			label.font_size = 48
			label.outline_size = 0
			label.position = Vector3(0, 0, 0.002)
			label.width = size.x / label.pixel_size * 0.95
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			node.add_child(label)
		"input":
			var height: float = element["font_size"] * TEXT_PIXEL * 1.6
			node = _make_body(id_panel, element["id"], Vector2(element["width"], height), at, Color(0.06, 0.07, 0.09))
			node.set_meta("color", Color(0.06, 0.07, 0.09))
			var label := _make_label(Vector3(-element["width"] / 2.0 + 0.01, 0, 0.002), element["width"] - 0.02, element["font_size"], _to_color(element["color"]), false, "left")
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.name = "Text"
			node.add_child(label)
	node.name = "E_" + element["id"]
	if element["type"] == "input":
		_show_input_node(id_panel, element, node)
	return node


# A flat, pointable quad: the laser hits it, the trigger presses it.
func _make_body(id_panel: String, id_element: String, size: Vector2, at: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = UI_LAYER
	body.collision_mask = 0
	body.set_meta("panel", id_panel)
	body.set_meta("element", id_element)
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


func _set_hover(body: StaticBody3D, on: bool) -> void:
	if body == null or not is_instance_valid(body) or not body.has_meta("color"):
		return
	var element := _element(body.get_meta("panel"), body.get_meta("element"))
	if element.get("type") != "button":
		return
	var face := body.get_node("Face") as MeshInstance3D
	(face.material_override as StandardMaterial3D).albedo_color = HOVER_COLOR if on else body.get_meta("color")


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
			"id_panel": "bar", "title": "Menu", "place": "front", "distance": 0.6, "height": -0.25,
			"toggle": "left_menu", "layout": "grid", "columns": 6, "cell": [0.14, 0.07], "elements": bar_buttons,
		},
		{
			"id_panel": "wrist", "title": "Wrist", "place": "wrist", "visible": true,
			"layout": "grid", "columns": 3, "cell": [0.06, 0.025], "elements": spawn_buttons,
		},
		_chat_panel(),
	]


# The agent's chat window: what it's doing at the top, the line you're typing,
# and a keyboard with Send and Stop. Everything in it is ordinary elements.
func _chat_panel() -> Dictionary:
	var key := 0.05
	var gap := 0.008
	var unit := key + gap
	var width := 10 * unit
	var elements := [
		{"type": "box", "id": "screen", "at": [0, 0.205], "size": [width + 0.02, 0.22], "color": "#08100a"},
		{"type": "text", "id": "log", "at": [0, 0.31], "width": width, "font_size": 26, "color": "#8cff99", "mono": true,
			"source": {"cmd": "agent_status", "field": "events", "last": 12, "chars": 160, "empty": "agent ready. type below and press Send."}},
		{"type": "text", "id": "state", "at": [0, 0.115], "width": width, "font_size": 24, "color": "#5f9f6a", "mono": true,
			"source": {"cmd": "agent_status", "field": "status_line"}},
		{"type": "input", "id": "line", "at": [0, 0.06], "width": width, "font_size": 40, "prompt": "> "},
	]
	var rows := ["1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.?"]
	for r in rows.size():
		for c in rows[r].length():
			var ch: String = rows[r][c]
			elements.append({"type": "button", "id": "key_%d_%d" % [r, c], "label": ch, "at": [(c - 4.5) * unit, -r * unit], "size": [key, key],
				"action": {"cmd": "ui_type", "text": ch}})
	var bottom := -rows.size() * unit
	elements.append_array([
		{"type": "button", "id": "shift", "label": "Shift", "at": [-3.75 * unit, bottom], "size": [key * 2 + gap, key], "action": {"cmd": "ui_key", "key": "shift"}},
		{"type": "button", "id": "space", "label": "Space", "at": [-0.75 * unit, bottom], "size": [key * 4 + gap * 3, key], "action": {"cmd": "ui_type", "text": " "}},
		{"type": "button", "id": "del", "label": "Del", "at": [1.75 * unit, bottom], "size": [key, key], "action": {"cmd": "ui_key", "key": "backspace"}},
		{"type": "button", "id": "clear", "label": "Clear", "at": [2.75 * unit, bottom], "size": [key, key], "action": {"cmd": "ui_key", "key": "clear"}},
		{"type": "button", "id": "send", "label": "Send", "at": [4.25 * unit, bottom], "size": [key * 2 + gap, key],
			"action": {"cmd": "agent_ask", "prompt": "{input:line}"}, "clear_input": "line"},
		{"type": "button", "id": "stop", "label": "STOP", "at": [6.0 * unit, 0.2], "size": [key * 1.5, key * 1.5], "color": "#8c1f1f",
			"action": {"cmd": "agent_stop"}},
	])
	return {"id_panel": "chat", "title": "Agent", "place": "front", "distance": 0.55, "height": -0.35,
		"toggle": "left_y", "elements": elements}


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
