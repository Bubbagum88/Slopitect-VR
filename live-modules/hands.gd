extends SlopitectModule

# Slopitect live module: hands.
# Drawn hands with coloured nails on both controllers, in place of the
# APK's box on each one. The fingers curl as the grip is pressed, the index
# finger with the trigger (a little when a finger only rests on it), and
# the thumb when it rests on a button or the thumbstick. How far each is
# pressed comes from the controls module (value()); without it the hands
# stay open. The boxes come back when the module is unloaded.
# The colours change from the PC only (hands_config) and are kept in the
# app's own storage (user://hands.json).

const SETTINGS_PATH := "user://hands.json"
const DEFAULTS := {
	"skin": "#e0ac80",
	"nails_left": ["#ff3b7a", "#ff3b7a", "#ff3b7a", "#ff3b7a", "#ff3b7a"],
	"nails_right": ["#ff3b7a", "#ff3b7a", "#ff3b7a", "#ff3b7a", "#ff3b7a"],
}
const FINGER_LEN := [0.072, 0.08, 0.075, 0.06]  # index to pinky, metres
const FINGER_R := [0.0095, 0.0095, 0.009, 0.008]
const SPLIT := [0.45, 0.3, 0.25]  # how a finger's length splits into its three bones
const CURL := [75.0, 95.0, 70.0]  # degrees each bone bends when fully curled
const FOLLOW := 18.0  # how fast a finger catches up with the press

# The colours the Settings window offers (isaac's comfort settings, 2026-10-29).
const SKINS := {"Light": "#f1c9a5", "Tan": "#e0ac80", "Brown": "#a86b45", "Dark": "#5c3a24", "Blue": "#5b7bd6"}
const NAILS := {"Pink": "#ff3b7a", "Red": "#d1263b", "Blue": "#3b6bff", "Black": "#16161c", "Clear": "#f4e6e0"}

var settings := DEFAULTS.duplicate(true)
var _hands := []  # {"node", "hand", "side", "fingers", "thumb", "tbase", "curl"}
var _skin: StandardMaterial3D
var _nails := {}  # "left"/"right" -> 5 materials, thumb to pinky
var _boxes := []  # the APK's controller boxes we hid


func setup() -> String:
	_load()
	_skin = StandardMaterial3D.new()
	_skin.roughness = 0.75
	for hand in ["left", "right"]:
		var materials := []
		for i in 5:
			var nail := StandardMaterial3D.new()
			nail.roughness = 0.2
			nail.metallic_specular = 0.9
			materials.append(nail)
		_nails[hand] = materials
	_apply_colours()
	_hands.append(_make_hand("left", 1.0))
	_hands.append(_make_hand("right", -1.0))
	for hand in ["left", "right"]:
		var box := (ctx[hand] as Node).get_node_or_null("Mesh") as Node3D
		if box != null and box.visible:
			box.visible = false
			_boxes.append(box)
	register("hands_status", _status, "the hands' colours")
	register("hands_colours", _colours_command, "change the hands' colours in the headset (a comfort setting): any of skin (#rrggbb), nails (#rrggbb, every nail)")
	register("hands_config", _config, "from the PC only: any of skin (#rrggbb), nails (#rrggbb, or 1 to 5 of them thumb to pinky, for both hands), nails_left, nails_right, or reset true")
	return ""


func _exit_tree() -> void:
	for box in _boxes:
		if is_instance_valid(box):
			box.visible = true
	_boxes.clear()
	for h in _hands:
		if is_instance_valid(h["node"]):
			h["node"].queue_free()
	_hands.clear()


func _process(delta: float) -> void:
	var controls: SlopitectModule = ctx["modules"].module("controls")
	var k := clampf(delta * FOLLOW, 0.0, 1.0)
	for h in _hands:
		var grip := 0.0
		var trigger := 0.0
		var thumb_on := 0.0
		var finger_on := 0.0
		if controls:
			grip = controls.call("value", h["hand"], "grip")
			trigger = controls.call("value", h["hand"], "trigger")
			thumb_on = controls.call("value", h["hand"], "thumb_touch")
			finger_on = controls.call("value", h["hand"], "trigger_touch")
		var targets := [maxf(0.75 * thumb_on, grip * 0.6), maxf(trigger, 0.25 * finger_on), grip, grip, grip]
		var curl: Array = h["curl"]
		for i in 5:
			curl[i] = lerpf(curl[i], targets[i], k)
		for i in 4:
			var bones: Array = h["fingers"][i]
			for j in 3:
				(bones[j] as Node3D).rotation.x = -deg_to_rad(CURL[j]) * curl[i + 1]
		var side: float = h["side"]
		(h["tbase"] as Node3D).rotation_degrees = Vector3(-20.0 * curl[0], side * (-45.0 + 45.0 * curl[0]), 0.0)
		(h["thumb"][1] as Node3D).rotation.x = -deg_to_rad(30.0) * curl[0]
		(h["thumb"][2] as Node3D).rotation.x = -deg_to_rad(45.0) * curl[0]


# --- Building a hand -------------------------------------------------------------------

func _make_hand(hand: String, side: float) -> Dictionary:
	var root := Node3D.new()
	root.name = "hands_" + hand
	var palm := _blob(Vector3(0.082, 0.03, 0.095), _skin)
	palm.position = Vector3(0.0, 0.0, 0.02)
	root.add_child(palm)
	var wrist := _blob(Vector3(0.06, 0.028, 0.06), _skin)
	wrist.position = Vector3(0.0, -0.002, 0.07)
	root.add_child(wrist)
	var fingers := []
	for i in 4:
		var base := Node3D.new()
		base.position = Vector3(side * (0.0285 - 0.019 * i), 0.002, -0.022)
		base.rotation_degrees = Vector3(0.0, side * (-3.0 + 3.0 * i), 0.0)
		root.add_child(base)
		fingers.append(_chain(base, FINGER_R[i], FINGER_LEN[i], _nails[hand][i + 1]))
	var tbase := Node3D.new()
	tbase.position = Vector3(side * 0.038, -0.01, 0.025)
	tbase.rotation_degrees = Vector3(0.0, -45.0 * side, 0.0)
	root.add_child(tbase)
	var thumb := _chain(tbase, 0.0115, 0.065, _nails[hand][0])
	(ctx[hand] as Node3D).add_child(root)
	return {"node": root, "hand": hand, "side": side, "fingers": fingers, "thumb": thumb, "tbase": tbase, "curl": [0.0, 0.0, 0.0, 0.0, 0.0]}


# Three bones, each turning at its own pivot, and a nail on the last.
func _chain(parent: Node3D, radius: float, length: float, nail_material: Material) -> Array:
	var pivots := []
	var at := parent
	for j in 3:
		var pivot := Node3D.new()
		if j > 0:
			pivot.position = Vector3(0.0, 0.0, -length * SPLIT[j - 1])
		at.add_child(pivot)
		pivot.add_child(_bone(radius * (1.0 - 0.08 * j), length * SPLIT[j]))
		pivots.append(pivot)
		at = pivot
	var tip: float = length * SPLIT[2]
	var nail := _blob(Vector3(radius * 1.7, radius * 0.6, tip * 0.75), nail_material)
	nail.position = Vector3(0.0, radius * 0.75, -tip * 0.6)
	at.add_child(nail)
	return pivots


func _bone(radius: float, length: float) -> MeshInstance3D:
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = length + 2.0 * radius
	capsule.radial_segments = 12
	capsule.rings = 3
	var bone := MeshInstance3D.new()
	bone.mesh = capsule
	bone.material_override = _skin
	bone.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	bone.position = Vector3(0.0, 0.0, -length / 2.0)
	return bone


func _blob(size: Vector3, material: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var blob := MeshInstance3D.new()
	blob.mesh = sphere
	blob.scale = size
	blob.material_override = material
	return blob


func _apply_colours() -> void:
	_skin.albedo_color = Color.html(settings["skin"])
	for hand in ["left", "right"]:
		for i in 5:
			(_nails[hand][i] as StandardMaterial3D).albedo_color = Color.html(settings["nails_" + hand][i])


# --- Commands and settings -------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	return {"ok": true, "settings": settings, "controls": ctx["modules"].module("controls") != null}


# Its section of the Settings window (settings.gd): a few skin and nail
# colours to pick from; any other colour is hands_colours or hands_config.
func settings_info() -> Dictionary:
	var out := []
	for part in [["skin", "Skin", SKINS, settings["skin"]], ["nails", "Nails", NAILS, settings["nails_left"][0]]]:
		var options := []
		for colour_name in part[2]:
			options.append({"label": colour_name, "value": part[2][colour_name], "color": part[2][colour_name]})
		out.append({"id": part[0], "type": "choice", "label": part[1], "value": part[3], "options": options, "columns": 3,
			"set": {"cmd": "hands_colours", part[0]: "{value}"}})
	return {"title": "Hands", "order": 30, "settings": out}


# Skin and nail colours can change in the headset (isaac's choice,
# 2026-10-29); one colour per nail and reset stay with hands_config.
func _colours_command(request: Dictionary) -> Dictionary:
	var changes := {}
	for key in request:
		if key in ["cmd", "id"]:
			continue
		if not key in ["skin", "nails"] or typeof(request[key]) != TYPE_STRING:
			return {"ok": false, "error": "hands_colours changes skin or nails, each a colour like \"#e0ac80\""}
		changes[key] = request[key]
	return _config(changes)


func _config(request: Dictionary) -> Dictionary:
	if request.get("reset", false) == true:
		settings = DEFAULTS.duplicate(true)
		_apply_colours()
		_save()
		return _status({})
	var changed := settings.duplicate(true)
	for key in request:
		if key in ["cmd", "id"]:
			continue
		match key:
			"skin":
				if not _colour(request[key]):
					return {"ok": false, "error": "\"skin\" must be a colour like \"#e0ac80\""}
				changed["skin"] = request[key]
			"nails", "nails_left", "nails_right":
				var colours = request[key]
				if typeof(colours) == TYPE_STRING:
					colours = [colours, colours, colours, colours, colours]
				if typeof(colours) != TYPE_ARRAY or colours.is_empty() or colours.size() > 5 or not colours.all(_colour):
					return {"ok": false, "error": "\"%s\" must be a colour like \"#ff3b7a\", or 1 to 5 of them, thumb to pinky" % key}
				for hand in (["left", "right"] if key == "nails" else [key.trim_prefix("nails_")]):
					for i in colours.size():
						changed["nails_" + hand][i] = colours[i]
			_:
				return {"ok": false, "error": "unknown setting \"%s\" (one of: skin, nails, nails_left, nails_right, reset)" % key}
	settings = changed
	_apply_colours()
	_save()
	return _status({})


func _colour(value) -> bool:
	return typeof(value) == TYPE_STRING and value.begins_with("#") and Color.html_is_valid(value)


func _save() -> void:
	var out := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if out == null:
		push_error("Slopitect hands: couldn't save %s (error %d)" % [SETTINGS_PATH, FileAccess.get_open_error()])
		return
	out.store_string(JSON.stringify(settings, "\t"))
	out.close()


func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var saved = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(saved) != TYPE_DICTIONARY:
		push_error("Slopitect hands: %s isn't readable; using the default colours" % SETTINGS_PATH)
		return
	if _colour(saved.get("skin")):
		settings["skin"] = saved["skin"]
	for key in ["nails_left", "nails_right"]:
		var colours = saved.get(key)
		if typeof(colours) == TYPE_ARRAY and colours.size() == 5 and colours.all(_colour):
			settings[key] = colours.duplicate()
