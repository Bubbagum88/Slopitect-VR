extends SlopitectModule

# Slopitect live module: hand_style.
# Settings > "Hands or light sabers": Human hand (the hands module's hands) or
# Light saber (a glowing blade on each controller: blue left, red right).
# Hide hands (Settings > Hands) hides whichever is showing. The hands also stay
# hidden while beatsaber is loaded, as the hands module does; the sabers stay
# shown then. This module sets the hands' visibility to the same rule the
# hands module uses, so the two agree. Not saved: back to Human hand on reload.

const STYLES := {"hand": "Human hand", "saber": "Light saber"}
const BLADE := {"left": "#3b6bff", "right": "#d1263b"}
const CHECK_SECONDS := 0.25
const HILT_LEN := 0.22
const HILT_R := 0.014
const BLADE_LEN := 0.9
const BLADE_R := 0.011
const HANDLE_AT := Vector3(0.0, -0.018, 0.018)  # the handle's middle, in the controller's space (hands module's grip_offset)

var style := "hand"
var _since := 0.0
var _sabers := {}  # "left"/"right" -> the saber's root node
var _hidden := false  # Hide hands is on
var _beat := false  # the beatsaber module is loaded


func setup() -> String:
	for hand in ["left", "right"]:
		_sabers[hand] = _make_saber(hand)
	register("hand_style", _style_command, "the hands or the light sabers: style (hand or saber)")
	return ""


func _exit_tree() -> void:
	if ctx["modules"].module(name) != null:
		return  # the app is closing, not unloading this
	for hand in _sabers:
		if is_instance_valid(_sabers[hand]):
			(_sabers[hand] as Node).queue_free()
	_sabers.clear()
	_hidden = false
	_beat = false
	style = "hand"
	_apply()  # the hands come back as the hands module wants them


func _process(delta: float) -> void:
	_since += delta
	if _since < CHECK_SECONDS:
		return
	_since = 0.0
	var status: Dictionary = ctx["server"].run({"cmd": "hands_status"})
	_hidden = (status.get("settings", {}) as Dictionary).get("hidden", false) == true
	_beat = ctx["modules"].module("beatsaber") != null
	_apply()


# One saber on a controller: a grey hilt and a glowing blade pointing where the controller points.
func _make_saber(hand: String) -> Node3D:
	var root := Node3D.new()
	root.name = "saber_" + hand
	root.position = HANDLE_AT
	root.visible = false
	(ctx[hand] as Node).add_child(root)

	var hilt := MeshInstance3D.new()
	var hilt_mesh := CylinderMesh.new()
	hilt_mesh.top_radius = HILT_R
	hilt_mesh.bottom_radius = HILT_R
	hilt_mesh.height = HILT_LEN
	hilt.mesh = hilt_mesh
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color.html("#2a2a30")
	grip.roughness = 0.6
	hilt.material_override = grip
	hilt.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	root.add_child(hilt)

	var blade := MeshInstance3D.new()
	var blade_mesh := CylinderMesh.new()
	blade_mesh.top_radius = BLADE_R
	blade_mesh.bottom_radius = BLADE_R
	blade_mesh.height = BLADE_LEN
	blade.mesh = blade_mesh
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color.html(BLADE[hand])
	glow.emission_enabled = true
	glow.emission = Color.html(BLADE[hand])
	glow.emission_energy_multiplier = 3.0
	blade.material_override = glow
	blade.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	blade.position = Vector3(0.0, 0.0, -(HILT_LEN / 2.0 + BLADE_LEN / 2.0))
	root.add_child(blade)
	return root


# Shows the chosen one; Hide hands hides both.
func _apply() -> void:
	var on := not _hidden
	for hand in ["left", "right"]:
		var saber = _sabers.get(hand)
		if is_instance_valid(saber):
			(saber as Node3D).visible = on and style == "saber"
		var hand_node := (ctx[hand] as Node).get_node_or_null("hands_" + hand) as Node3D
		if hand_node != null:
			hand_node.visible = on and style == "hand" and not _beat


func _style_command(request: Dictionary) -> Dictionary:
	var chosen = request.get("style")
	if chosen == null:
		return {"ok": true, "style": style}
	if typeof(chosen) != TYPE_STRING or not STYLES.has(chosen):
		return {"ok": false, "error": "\"style\" must be hand or saber"}
	style = chosen
	_apply()
	return {"ok": true, "style": style}


func settings_info() -> Dictionary:
	var options := []
	for key in STYLES:
		options.append({"label": STYLES[key], "value": key})
	return {"title": "Hand style", "order": 31, "settings": [
		{"id": "style", "type": "choice", "label": "Hands or light sabers", "value": style, "options": options, "columns": 2,
			"set": {"cmd": "hand_style", "style": "{value}"}}]}
