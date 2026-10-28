extends SlopitectModule

# Slopitect: the agent's avatar, a small red cube with a face.
# No legs; two little red sphere hands float beside it. It bobs gently, blinks,
# turns to face you, and shows what the agent is doing: it thinks while the
# agent works, talks when a reply arrives, and shows the reply in a speech
# bubble. Outfits are data (a list of simple shapes), so new ones can be
# added while the app runs, by you or the agent.

const SAVE_PATH := "user://avatar.json"
const BODY_SIZE := 0.22
const BODY_COLOR := Color(0.88, 0.2, 0.22)
const HAND_RADIUS := 0.035
const STATES := ["idle", "thinking", "talking", "happy", "wave"]
const SHAPES := ["box", "sphere", "cylinder", "cone", "torus"]
const MAX_PARTS := 12
const SAY_SECONDS := 6.0
const TALK_SECONDS := 2.5
const TURN_SPEED := 3.0
const POLL_SECONDS := 0.25

# Built-in outfits. Positions are relative to the middle of the body, in
# metres; the face is on -z, the top of the head at y = 0.11.
const OUTFITS := {
	"none": [],
	"top_hat": [
		{"shape": "cylinder", "size": [0.2, 0.012, 0.2], "position": [0, 0.116, 0], "color": "#161616"},
		{"shape": "cylinder", "size": [0.12, 0.12, 0.12], "position": [0, 0.18, 0], "color": "#161616"},
		{"shape": "cylinder", "size": [0.124, 0.02, 0.124], "position": [0, 0.135, 0], "color": "#7a1c1c"},
	],
	"party_hat": [
		{"shape": "cone", "size": [0.1, 0.14, 0.1], "position": [0.03, 0.18, 0], "rotation": [0, 0, -12], "color": "#3b8be0"},
		{"shape": "sphere", "size": [0.03, 0.03, 0.03], "position": [0.045, 0.255, 0], "color": "#ffd23f"},
	],
	"crown": [
		{"shape": "cylinder", "size": [0.16, 0.05, 0.16], "position": [0, 0.135, 0], "color": "#f2c230"},
		{"shape": "sphere", "size": [0.025, 0.025, 0.025], "position": [0, 0.14, -0.08], "color": "#3bd16f"},
	],
	"bow_tie": [
		{"shape": "cone", "size": [0.045, 0.05, 0.015], "position": [-0.026, -0.095, -0.115], "rotation": [0, 0, -90], "color": "#2d2d8a"},
		{"shape": "cone", "size": [0.045, 0.05, 0.015], "position": [0.026, -0.095, -0.115], "rotation": [0, 0, 90], "color": "#2d2d8a"},
		{"shape": "sphere", "size": [0.022, 0.022, 0.016], "position": [0, -0.095, -0.12], "color": "#3d3db0"},
	],
	"headphones": [
		{"shape": "torus", "size": [0.25, 0.25, 0.25], "position": [0, 0.0, 0], "rotation": [90, 0, 0], "color": "#2a2a2a"},
		{"shape": "cylinder", "size": [0.06, 0.03, 0.06], "position": [-0.12, 0, 0], "rotation": [0, 0, 90], "color": "#d94f9b"},
		{"shape": "cylinder", "size": [0.06, 0.03, 0.06], "position": [0.12, 0, 0], "rotation": [0, 0, 90], "color": "#d94f9b"},
	],
}

var _root: Node3D      # follows the avatar's place; turns to face you
var _body: Node3D      # bobs and leans inside _root
var _outfit_holder: Node3D
var _eyes: Array[MeshInstance3D] = []
var _mouth: MeshInstance3D
var _hands: Array[MeshInstance3D] = []
var _bubble: Label3D

var _state := "idle"
var _outfit := "none"
var _custom_outfits := {}
var _time := 0.0
var _next_blink := 2.0
var _say_left := 0.0
var _talk_left := 0.0
var _seen_reply := ""
var _was_busy := false
var _since_poll := 0.0


func setup() -> String:
	_build()
	_load()
	_wear(_outfit)
	_root.global_position = Vector3(-0.6, 1.3, -1.0)

	register("avatar_move", _move_command, "move the avatar: position [x, y, z]")
	register("avatar_say", _say_command, "show text in the avatar's speech bubble: text")
	register("avatar_state", _state_command, "set the avatar's animation: state (%s)" % ", ".join(STATES))
	register("avatar_outfit", _outfit_command, "change the avatar's outfit: name (avatar_outfits lists them)")
	register("avatar_outfits", _outfits_command, "list the avatar's outfits")
	register("avatar_outfit_add", _outfit_add_command, "add or replace an outfit: name, parts [{shape (%s), size [x,y,z], position [x,y,z], optional rotation [x,y,z] degrees, color}]" % ", ".join(SHAPES))
	return ""


# --- Building ---------------------------------------------------------------

func _build() -> void:
	_root = Node3D.new()
	_root.name = "Avatar"
	add_child(_root)
	_body = Node3D.new()
	_root.add_child(_body)

	var cube := _mesh_part("box", Vector3.ONE * BODY_SIZE, BODY_COLOR)
	_body.add_child(cube)

	# The face is on the cube's -z side: big dark eyes with a light dot,
	# pink cheeks and a small mouth.
	for side in [-1, 1]:
		var eye := _mesh_part("sphere", Vector3(0.04, 0.05, 0.015), Color(0.08, 0.06, 0.07))
		eye.position = Vector3(side * 0.045, 0.02, -BODY_SIZE / 2.0)
		_body.add_child(eye)
		_eyes.append(eye)
		var shine := _mesh_part("sphere", Vector3(0.014, 0.014, 0.006), Color(1, 1, 1))
		# The shine is a child of the eye, so it's placed in eye-sized units.
		shine.position = Vector3(0.2, 0.22, -0.45)
		shine.scale = Vector3(1.0 / 0.04, 1.0 / 0.05, 1.0 / 0.015) * 0.014
		eye.add_child(shine)
		var cheek := _mesh_part("sphere", Vector3(0.035, 0.02, 0.006), Color(1.0, 0.55, 0.6))
		cheek.position = Vector3(side * 0.075, -0.02, -BODY_SIZE / 2.0)
		_body.add_child(cheek)
	_mouth = _mesh_part("sphere", Vector3(0.03, 0.012, 0.008), Color(0.25, 0.05, 0.08))
	_mouth.position = Vector3(0, -0.035, -BODY_SIZE / 2.0)
	_body.add_child(_mouth)

	for side in [-1, 1]:
		var hand := _mesh_part("sphere", Vector3.ONE * HAND_RADIUS * 2.0, BODY_COLOR)
		_root.add_child(hand)
		_hands.append(hand)

	_outfit_holder = Node3D.new()
	_body.add_child(_outfit_holder)

	_bubble = Label3D.new()
	_bubble.position = Vector3(0, 0.26, 0)
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.pixel_size = 0.0007
	_bubble.font_size = 32
	_bubble.width = 0.5 / _bubble.pixel_size
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.outline_size = 10
	_bubble.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_bubble.visible = false
	_root.add_child(_bubble)


func _mesh_part(shape: String, size: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh: Mesh
	match shape:
		"box":
			mesh = BoxMesh.new()
			mesh.size = size
		"sphere":
			mesh = SphereMesh.new()
			mesh.radius = 0.5
			mesh.height = 1.0
			mesh.radial_segments = 16
			mesh.rings = 8
			part.scale = size
		"cylinder", "cone":
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.0 if shape == "cone" else 0.5
			mesh.bottom_radius = 0.5
			mesh.height = 1.0
			mesh.radial_segments = 16
			part.scale = size
		"torus":
			mesh = TorusMesh.new()
			mesh.inner_radius = 0.44
			mesh.outer_radius = 0.5
			mesh.rings = 24
			mesh.ring_segments = 8
			part.scale = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	part.mesh = mesh
	part.material_override = material
	return part


# --- Animation ----------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_since_poll += delta
	if _since_poll >= POLL_SECONDS:
		_since_poll = 0.0
		_follow_agent()
	_face_player(delta)

	# Body: a slow bob, and a lean that depends on the state.
	var bob := sin(_time * 2.0) * 0.012
	var lean := 0.0
	var hop := 0.0
	var state := "talking" if _talk_left > 0.0 and _state == "idle" else _state
	match state:
		"thinking":
			lean = sin(_time * 1.3) * 8.0
		"talking":
			bob += absf(sin(_time * 9.0)) * 0.008
		"happy":
			hop = absf(sin(_time * 5.0)) * 0.06
	_body.position = Vector3(0, bob + hop, 0)
	_body.rotation_degrees = Vector3(0, 0, lean)

	# Hands: floating beside the body, bobbing out of step with each other.
	for i in _hands.size():
		var side := -1.0 if i == 0 else 1.0
		var phase := _time * 2.2 + i * 1.7
		var at := Vector3(side * 0.19, -0.05 + sin(phase) * 0.018, -0.02 + cos(phase * 0.7) * 0.01)
		match state:
			"thinking":
				if i == 1:
					# One hand to the chin, tapping.
					at = Vector3(0.06, -0.09 + absf(sin(_time * 4.0)) * 0.01, -0.14)
			"wave":
				if i == 1:
					at = Vector3(0.2 + sin(_time * 10.0) * 0.03, 0.12, -0.02)
			"happy":
				at.y = 0.08 + sin(phase * 2.0) * 0.02
			"talking":
				at.y += sin(_time * 6.0 + i) * 0.015
		_hands[i].position = at + Vector3(0, bob + hop, 0)

	# Mouth: opens and closes while talking.
	var open := 1.0
	if state == "talking":
		open = 1.0 + absf(sin(_time * 14.0)) * 1.6
	elif state == "happy":
		open = 1.5
	_mouth.scale = Vector3(0.03, 0.012 * open, 0.008)

	# Blink every few seconds.
	_next_blink -= delta
	var eye_height := 0.05
	if _next_blink < 0.0:
		eye_height = 0.006
		if _next_blink < -0.12:
			_next_blink = randf_range(2.0, 5.0)
	for eye in _eyes:
		eye.scale = Vector3(0.04, eye_height, 0.015)

	_talk_left = maxf(_talk_left - delta, 0.0)
	if _say_left > 0.0:
		_say_left -= delta
		if _say_left <= 0.0:
			_bubble.visible = false


# The avatar shows what the agent is doing, by reading agent_status like any
# other module would. Without the agent module it just idles.
func _follow_agent() -> void:
	var status: Dictionary = ctx["server"].run({"cmd": "agent_status"})
	if not status.get("ok", false):
		return
	if status["busy"] and not _was_busy and _state == "idle":
		_state = "thinking"
	elif not status["busy"] and _was_busy and _state == "thinking":
		_state = "idle"
	_was_busy = status["busy"]
	if status["last_reply"] != _seen_reply:
		_seen_reply = status["last_reply"]
		if not _seen_reply.is_empty():
			_say(_seen_reply)


func _face_player(delta: float) -> void:
	var head: Vector3 = ctx["camera"].global_position
	var to := head - _root.global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	# The face is on -z, so point -z at the player.
	var target := atan2(-to.x, -to.z)
	_root.rotation.y = lerp_angle(_root.rotation.y, target, clampf(delta * TURN_SPEED, 0.0, 1.0))


func _say(text: String) -> void:
	_bubble.text = text.left(240) + ("..." if text.length() > 240 else "")
	_bubble.visible = true
	_say_left = SAY_SECONDS
	_talk_left = TALK_SECONDS


# --- Outfits --------------------------------------------------------------------

func _all_outfits() -> Dictionary:
	var all := OUTFITS.duplicate()
	all.merge(_custom_outfits, true)
	return all


func _wear(outfit_name: String) -> void:
	for child in _outfit_holder.get_children():
		child.queue_free()
	for part in _all_outfits().get(outfit_name, []):
		var piece := _mesh_part(part["shape"], _vec(part["size"]), Color.from_string(part["color"], Color.WHITE))
		piece.position = _vec(part["position"])
		if part.has("rotation"):
			piece.rotation_degrees = _vec(part["rotation"])
		_outfit_holder.add_child(piece)
	_outfit = outfit_name


func _check_parts(parts: Variant) -> String:
	if typeof(parts) != TYPE_ARRAY:
		return "\"parts\" must be a list"
	if parts.size() > MAX_PARTS:
		return "an outfit can have at most %d parts" % MAX_PARTS
	for i in parts.size():
		var part = parts[i]
		if typeof(part) != TYPE_DICTIONARY:
			return "part %d isn't an object" % i
		if not part.get("shape") in SHAPES:
			return "part %d: \"shape\" must be one of %s" % [i, ", ".join(SHAPES)]
		for key in ["size", "position"] + (["rotation"] if part.has("rotation") else []):
			if not _is_vec(part.get(key)):
				return "part %d: \"%s\" must be [x, y, z]" % [i, key]
		for n in part["size"]:
			if n <= 0.0 or n > 0.5:
				return "part %d: each size must be more than 0 and at most 0.5 m" % i
		for n in part["position"]:
			if absf(n) > 0.5:
				return "part %d: position must stay within 0.5 m of the body" % i
		if typeof(part.get("color")) != TYPE_STRING or Color.from_string(part["color"], Color(0, 0, 0, 0)).a == 0.0:
			return "part %d: \"color\" must be #rrggbb or a colour name" % i
	return ""


func _is_vec(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return false
	for n in value:
		if typeof(n) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(n)) or is_inf(float(n)):
			return false
	return true


func _vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


# --- Commands -------------------------------------------------------------------

func _move_command(request: Dictionary) -> Dictionary:
	var p = request.get("position")
	if not _is_vec(p):
		return {"ok": false, "error": "avatar_move needs \"position\": [x, y, z]"}
	if absf(p[0]) > 50 or p[1] < 0 or p[1] > 20 or absf(p[2]) > 50:
		return {"ok": false, "error": "position must be within 50 m and between 0 and 20 m up"}
	_root.global_position = _vec(p)
	return {"ok": true, "position": p}


func _say_command(request: Dictionary) -> Dictionary:
	var text = request.get("text")
	if typeof(text) != TYPE_STRING or text.strip_edges().is_empty():
		return {"ok": false, "error": "avatar_say needs \"text\""}
	_say(text)
	return {"ok": true}


func _state_command(request: Dictionary) -> Dictionary:
	var state = request.get("state")
	if not state in STATES:
		return {"ok": false, "error": "\"state\" must be one of %s" % ", ".join(STATES)}
	_state = state
	return {"ok": true, "state": state}


func _outfit_command(request: Dictionary) -> Dictionary:
	var outfit_name = request.get("name")
	if typeof(outfit_name) != TYPE_STRING or not _all_outfits().has(outfit_name):
		return {"ok": false, "error": "no outfit \"%s\" (one of: %s)" % [str(outfit_name), ", ".join(PackedStringArray(_all_outfits().keys()))]}
	_wear(outfit_name)
	_save()
	return {"ok": true, "outfit": outfit_name}


func _outfits_command(_request: Dictionary) -> Dictionary:
	return {"ok": true, "wearing": _outfit, "outfits": PackedStringArray(_all_outfits().keys()), "custom": _custom_outfits.duplicate(true)}


func _outfit_add_command(request: Dictionary) -> Dictionary:
	var outfit_name = request.get("name")
	if typeof(outfit_name) != TYPE_STRING or not outfit_name.is_valid_identifier() or outfit_name.length() > 32:
		return {"ok": false, "error": "\"name\" must be letters, digits and _ (up to 32)"}
	if OUTFITS.has(outfit_name):
		return {"ok": false, "error": "\"%s\" is a built-in outfit; pick another name" % outfit_name}
	var problem := _check_parts(request.get("parts"))
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	_custom_outfits[outfit_name] = request["parts"].duplicate(true)
	if _outfit == outfit_name:
		_wear(outfit_name)
	_save()
	return {"ok": true, "outfit": outfit_name}


# --- Saving -------------------------------------------------------------------

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var json := JSON.new()
	var problem := ""
	if json.parse(FileAccess.get_file_as_string(SAVE_PATH)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		problem = "not a JSON object"
	else:
		var custom = json.data.get("custom_outfits", {})
		if typeof(custom) != TYPE_DICTIONARY:
			problem = "\"custom_outfits\" isn't an object"
		else:
			for outfit_name in custom:
				var bad := _check_parts(custom[outfit_name])
				if not bad.is_empty():
					problem = "outfit %s: %s" % [outfit_name, bad]
					break
		if problem.is_empty():
			_custom_outfits = custom
			var wearing = json.data.get("outfit", "none")
			_outfit = wearing if _all_outfits().has(wearing) else "none"
			print("Slopitect avatar: wearing \"%s\", %d custom outfits" % [_outfit, _custom_outfits.size()])
			return
	var kept := SAVE_PATH + ".bad"
	DirAccess.rename_absolute(SAVE_PATH, kept)
	push_error("Slopitect avatar: %s is broken (%s); kept it as %s" % [SAVE_PATH, problem, kept])


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Slopitect avatar: could not save %s (%s)" % [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({"outfit": _outfit, "custom_outfits": _custom_outfits}, "  "))
	file.close()
