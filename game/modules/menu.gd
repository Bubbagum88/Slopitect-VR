extends SlopitectModule

# Slopitect: the universal menu.
# The menu is data, not code: a list of buttons, each with a label and an
# action, which is any command the command server understands. Claude (or
# you) can add, change and remove buttons while the app runs, with the
# menu_* commands; the list is saved on the headset and loaded at start.
#
# It shows in two places, from the same list:
# - the bar: pops up in front of you when you press the left controller's
#   menu button, and hides again on a second press;
# - the wrist: a small panel on the left wrist, always there.
# Point with the right controller and pull the trigger to press a button.

const SAVE_PATH := "user://menu.json"
const PLACES := ["bar", "wrist"]
const MENU_LAYER := 1 << 19  # physics layer 20, used only by menu buttons
const BAR_DISTANCE := 0.6
const BAR_BUTTON_SIZE := Vector2(0.14, 0.07)
const WRIST_BUTTON_SIZE := Vector2(0.06, 0.025)
const LASER_LENGTH := 3.0
const BUTTON_COLOR := Color(0.12, 0.13, 0.16)
const HOVER_COLOR := Color(0.25, 0.45, 0.9)

var buttons: Array = []  # [{id, label, action, places}], in display order
var laser_wanted := false  # another module's panel is open and wants the laser

var _server: Node
var _camera: XRCamera3D
var _left: XRController3D
var _right: XRController3D
var _bar: Node3D
var _wrist: Node3D
var _ray: RayCast3D
var _laser: MeshInstance3D
var _hovered: StaticBody3D


func setup() -> String:
	_server = ctx["server"]
	_camera = ctx["camera"]
	_left = ctx["left"]
	_right = ctx["right"]

	register("menu_list", _list, "list the menu's buttons")
	register("menu_add", _add, "add a button: id_button, label, action (a command), optional places and index")
	register("menu_update", _update, "change a button's label, action and/or places")
	register("menu_remove", _remove, "remove a button")
	register("menu_press", _press, "press a button, as if pointed at and clicked")
	register("menu_reset", _reset, "put the default buttons back")

	_bar = Node3D.new()
	_bar.name = "Bar"
	_bar.visible = false
	add_child(_bar)

	# On the back of the left wrist, tilted to face you when you look at it.
	_wrist = Node3D.new()
	_wrist.name = "Wrist"
	_wrist.position = Vector3(0.0, 0.03, 0.08)
	_wrist.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
	_left.add_child(_wrist)

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -LASER_LENGTH)
	_ray.collision_mask = MENU_LAYER
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

	_left.button_pressed.connect(_on_left_pressed)
	_right.button_pressed.connect(_on_right_pressed)

	_load()
	_rebuild()
	return ""


# The wrist panel, laser and ray hang off the controllers, not this node, so
# they are removed by hand when the module goes.
func _exit_tree() -> void:
	for node in [_wrist, _ray, _laser]:
		if node and is_instance_valid(node):
			node.queue_free()


func _physics_process(_delta: float) -> void:
	var hit: StaticBody3D = _ray.get_collider() as StaticBody3D if _ray.is_colliding() else null
	if hit != _hovered:
		_set_hover(_hovered, false)
		_hovered = hit
		_set_hover(_hovered, true)
	var length := LASER_LENGTH
	if _hovered:
		length = _right.global_position.distance_to(_ray.get_collision_point())
	# Only show the laser while it can hit something.
	_laser.visible = _bar.visible or _hovered != null or laser_wanted
	_laser.scale = Vector3(1, 1, length)
	_laser.position = Vector3(0, 0, -length / 2.0)


func _on_left_pressed(button: String) -> void:
	if button == "menu_button":
		if _bar.visible:
			_bar.visible = false
		else:
			_place_bar()
			_bar.visible = true
		print("Slopitect menu: bar ", "shown" if _bar.visible else "hidden")


func _on_right_pressed(button: String) -> void:
	if button != "trigger_click" or not _hovered:
		return
	# Other modules' panels (like the chat keyboard) use the same laser: their
	# buttons carry the function to call when pressed.
	if _hovered.has_meta("on_press"):
		(_hovered.get_meta("on_press") as Callable).call()
	else:
		press(_hovered.get_meta("id"))


# Puts the bar in front of you at chest height, facing you.
func _place_bar() -> void:
	var head := _camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	_bar.global_position = head.origin + forward * BAR_DISTANCE + Vector3(0, -0.25, 0)
	_bar.look_at(head.origin - Vector3(0, 0.25, 0), Vector3.UP, true)


# Runs a button's action as if it came through the command server.
func press(id: String) -> Dictionary:
	var index := _index_of(id)
	if index == -1:
		return {"ok": false, "error": "no menu button \"%s\"" % id}
	var action: Dictionary = buttons[index]["action"].duplicate(true)
	if action.get("position") is String and action["position"] == "in_front":
		action["position"] = _in_front()
	print("Slopitect menu: pressed \"%s\"" % id)
	var reply: Dictionary = _server.run(action)
	if not reply.get("ok", false):
		print("Slopitect menu: \"%s\" failed: %s" % [id, reply.get("error", "?")])
	return reply


# A point 1 m in front of you at chest height, in World coordinates.
func _in_front() -> Array:
	var head := _camera.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var p := head.origin + forward * 1.0 + Vector3(0, -0.3, 0)
	return [p.x, p.y, p.z]


# --- Commands, registered with the command server ---------------------------

func _list(_request: Dictionary) -> Dictionary:
	return {"ok": true, "buttons": buttons.duplicate(true)}


func _press(request: Dictionary) -> Dictionary:
	var id = request.get("id_button")
	if typeof(id) != TYPE_STRING:
		return {"ok": false, "error": "menu_press needs \"id_button\""}
	return press(id)


func _reset(_request: Dictionary) -> Dictionary:
	buttons = _defaults()
	return _changed({"ok": true, "buttons": buttons.duplicate(true)})


func _add(request: Dictionary) -> Dictionary:
	var checked := _check_button(request, true)
	if checked.has("error"):
		return {"ok": false, "error": checked["error"]}
	var button: Dictionary = checked["button"]
	var at = request.get("index", buttons.size())
	if typeof(at) != TYPE_FLOAT and typeof(at) != TYPE_INT or int(at) < 0 or int(at) > buttons.size():
		return {"ok": false, "error": "\"index\" must be 0 to %d" % buttons.size()}
	buttons.insert(int(at), button)
	return _changed({"ok": true, "button": button})


func _update(request: Dictionary) -> Dictionary:
	var id = request.get("id_button")
	if typeof(id) != TYPE_STRING or _index_of(id) == -1:
		return {"ok": false, "error": "no menu button \"%s\" (menu_list shows them)" % str(id)}
	var merged: Dictionary = buttons[_index_of(id)].duplicate(true)
	for key in ["label", "action", "places"]:
		if request.has(key):
			merged[key] = request[key]
	var checked := _check_button(merged, false)
	if checked.has("error"):
		return {"ok": false, "error": checked["error"]}
	buttons[_index_of(id)] = checked["button"]
	return _changed({"ok": true, "button": checked["button"]})


func _remove(request: Dictionary) -> Dictionary:
	var id = request.get("id_button")
	if typeof(id) != TYPE_STRING or _index_of(id) == -1:
		return {"ok": false, "error": "no menu button \"%s\" (menu_list shows them)" % str(id)}
	var removed: Dictionary = buttons.pop_at(_index_of(id))
	return _changed({"ok": true, "removed": removed})


# Checks a button completely before anything changes. Buttons use
# "id_button" for their name, so it can't be mixed up with a request's "id".
func _check_button(data: Dictionary, is_new: bool) -> Dictionary:
	var id = data.get("id_button")
	if typeof(id) != TYPE_STRING or id.is_empty() or id.length() > 40:
		return {"error": "\"id_button\" must be a name of 1 to 40 characters"}
	if is_new and _index_of(id) != -1:
		return {"error": "a menu button \"%s\" already exists" % id}
	var label = data.get("label")
	if typeof(label) != TYPE_STRING or label.is_empty() or label.length() > 24:
		return {"error": "\"label\" must be text of 1 to 24 characters"}
	var action = data.get("action")
	if typeof(action) != TYPE_DICTIONARY or typeof(action.get("cmd")) != TYPE_STRING:
		return {"error": "\"action\" must be a command, like {\"cmd\": \"spawn\", \"shape\": \"box\"}"}
	if not action["cmd"] in _server.commands():
		return {"error": "\"action\" uses unknown cmd \"%s\"" % action["cmd"]}
	if action["cmd"] == "menu_press":
		return {"error": "a button can't press another button"}
	if action["cmd"] == "agent_config":
		return {"error": "the agent's settings can only be changed from the PC, not by a button"}
	var places = data.get("places", ["bar", "wrist"])
	if typeof(places) != TYPE_ARRAY or places.is_empty():
		return {"error": "\"places\" must be a list from %s" % [PLACES]}
	for place in places:
		if not place in PLACES:
			return {"error": "unknown place \"%s\" (use %s)" % [place, PLACES]}
	return {"button": {"id_button": id, "label": label, "action": action, "places": places}}


func _changed(reply: Dictionary) -> Dictionary:
	_save()
	_rebuild()
	return reply


func _index_of(id: String) -> int:
	for i in buttons.size():
		if buttons[i]["id_button"] == id:
			return i
	return -1


# --- Drawing -----------------------------------------------------------------

func _rebuild() -> void:
	_hovered = null
	for holder in [_bar, _wrist]:
		for child in holder.get_children():
			holder.remove_child(child)
			child.queue_free()
	_lay_out(_bar, "bar", BAR_BUTTON_SIZE, 6)
	_lay_out(_wrist, "wrist", WRIST_BUTTON_SIZE, 3)


# Rows of up to `per_row` buttons, centred, filling downwards.
func _lay_out(holder: Node3D, place: String, size: Vector2, per_row: int) -> void:
	var shown := buttons.filter(func(b): return place in b["places"])
	var gap := size.y * 0.25
	for i in shown.size():
		var row := i / per_row
		var in_row := mini(per_row, shown.size() - row * per_row)
		var col := i % per_row
		var x := (col - (in_row - 1) / 2.0) * (size.x + gap)
		var y := -row * (size.y + gap)
		var button := make_button(shown[i]["label"], size, Vector3(x, y, 0))
		button.set_meta("id", shown[i]["id_button"])
		holder.add_child(button)


# A pressable button: point the laser at it and pull the trigger. Public so
# other modules can build panels that work with the same laser.
func make_button(label: String, size: Vector2, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = MENU_LAYER
	body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.01)
	shape.shape = box
	body.add_child(shape)

	var face := MeshInstance3D.new()
	face.name = "Face"
	var quad := QuadMesh.new()
	quad.size = size
	face.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = BUTTON_COLOR
	face.material_override = material
	body.add_child(face)

	var text := Label3D.new()
	text.text = label
	text.pixel_size = size.y / 140.0
	text.font_size = 48
	text.outline_size = 0
	text.position = Vector3(0, 0, 0.002)
	text.width = size.x / text.pixel_size * 0.95
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(text)
	return body


func _set_hover(body: StaticBody3D, on: bool) -> void:
	if body == null or not is_instance_valid(body):
		return
	var face := body.get_node("Face") as MeshInstance3D
	(face.material_override as StandardMaterial3D).albedo_color = HOVER_COLOR if on else BUTTON_COLOR


# --- Saving ------------------------------------------------------------------

func _defaults() -> Array:
	var list := []
	for shape in ["box", "sphere", "cylinder", "capsule"]:
		list.append({
			"id_button": "spawn_" + shape,
			"label": shape.capitalize(),
			"action": {"cmd": "spawn", "shape": shape, "position": "in_front", "scale": [0.3, 0.3, 0.3]},
			"places": ["bar", "wrist"],
		})
	list.append({
		"id_button": "list",
		"label": "List objects",
		"action": {"cmd": "list"},
		"places": ["bar"],
	})
	return list


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		buttons = _defaults()
		print("Slopitect menu: no saved menu, using the default %d buttons" % buttons.size())
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var json := JSON.new()
	var problem := ""
	if json.parse(text) != OK:
		problem = "not valid JSON: " + json.get_error_message()
	elif typeof(json.data) != TYPE_ARRAY:
		problem = "expected a list of buttons"
	else:
		var loaded := []
		for item in json.data:
			if typeof(item) != TYPE_DICTIONARY:
				problem = "an entry isn't a button: " + JSON.stringify(item)
				break
			var checked := _check_button(item, false)
			if checked.has("error"):
				problem = "button %s: %s" % [JSON.stringify(item.get("id_button")), checked["error"]]
				break
			loaded.append(checked["button"])
		if problem.is_empty():
			buttons = loaded
			print("Slopitect menu: loaded %d buttons from %s" % [buttons.size(), SAVE_PATH])
			return
	# Keep the broken file for inspection instead of overwriting it.
	var kept := SAVE_PATH + ".bad"
	DirAccess.rename_absolute(SAVE_PATH, kept)
	push_error("Slopitect menu: %s is broken (%s); kept it as %s and used the defaults" % [SAVE_PATH, problem, kept])
	buttons = _defaults()


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Slopitect menu: could not save %s (%s)" % [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(buttons, "  "))
	file.close()
