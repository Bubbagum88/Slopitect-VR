extends SlopitectModule

# Slopitect live module: the agent's avatar, a small red cube with a face.
# It takes over from the avatar that was built into the APK, with the same
# avatar_* commands and the same saved outfits (user://avatar.json).
#
# - Animations: idle, thinking, talking, happy and wave move the body and the
#   two floating hands. It thinks while the agent works, all by itself.
# - Emotions: neutral, happy, sad, surprised, angry, confused and sleepy
#   change the eyes, brows and the resting shape of the mouth.
# - Mouth: while the headset's speech engine is talking, the mouth follows
#   the letters of what is being said (wide for a and e, round for o and u,
#   shut for m, b and p). With no speech engine it mouths the reply for as
#   long as it would take to say it.
# - Speech bubble: a panel with a tail, above the head (and above any hat),
#   turned to you and made bigger when the avatar is far away so it stays
#   readable. When the avatar is out of view the bubble waits at the edge of
#   your view on its side, so you still see what it says. Long replies are
#   shown a page at a time. Colours come from vrui.gd's theme when it has one.
# - Outfits: data (a list of simple shapes), so new ones can be added while
#   the app runs, by you or the agent.
#
# For other modules: body() is the node that bobs and leans (jelly squashes
# its scale; nothing here touches the scale), say(text), set_state(name),
# set_emotion(name, seconds) and speaking().
#
# The agent's state comes from agent_status, read four times a second, until
# agent.gd sends signals.

const SAVE_PATH := "user://avatar.json"
const BODY_SIZE := 0.22
const BODY_COLOR := Color(0.88, 0.2, 0.22)
const HAND_RADIUS := 0.035
const STATES := ["idle", "thinking", "talking", "happy", "wave"]
const SHAPES := ["box", "sphere", "cylinder", "cone", "torus"]
const MAX_PARTS := 12
const TURN_SPEED := 3.0
const POLL_SECONDS := 0.25
const ERROR_SECONDS := 4.0  # how long it looks confused after the agent fails
# A fallback: the headset's speech engine can keep saying it's speaking after
# it has stopped (Godot's Android TTS only clears that when the engine reports
# the end, and some engines never do). So the avatar follows it for at most
# ENGINE_SLACK times as long as the words would take plus ENGINE_EXTRA
# seconds, or ENGINE_UNKNOWN_SECONDS for speech it wasn't given the words of.
const ENGINE_SLACK := 3.0
const ENGINE_EXTRA := 5.0
const ENGINE_UNKNOWN_SECONDS := 30.0

# Each emotion is a face: smile (-1 frown to 1 grin), eyes (how open), brow
# height in metres, brow tilt in degrees (+ is the inner ends down, cross),
# a raised left brow, mouth width and how far the mouth rests open.
const EMOTIONS := {
	"neutral": {"smile": 0.2, "eyes": 1.0, "brow_y": 0.0, "brow_tilt": 0.0, "brow_lift": 0.0, "mouth_w": 1.0, "rest_open": 0.0},
	"happy": {"smile": 1.0, "eyes": 0.7, "brow_y": 0.005, "brow_tilt": -6.0, "brow_lift": 0.0, "mouth_w": 1.2, "rest_open": 0.3},
	"sad": {"smile": -0.8, "eyes": 0.8, "brow_y": 0.002, "brow_tilt": -20.0, "brow_lift": 0.0, "mouth_w": 0.85, "rest_open": 0.0},
	"surprised": {"smile": 0.0, "eyes": 1.3, "brow_y": 0.014, "brow_tilt": 0.0, "brow_lift": 0.0, "mouth_w": 0.6, "rest_open": 0.9},
	"angry": {"smile": -0.5, "eyes": 0.75, "brow_y": -0.006, "brow_tilt": 22.0, "brow_lift": 0.0, "mouth_w": 0.9, "rest_open": 0.0},
	"confused": {"smile": -0.25, "eyes": 1.0, "brow_y": 0.0, "brow_tilt": 0.0, "brow_lift": 0.012, "mouth_w": 0.8, "rest_open": 0.1},
	"sleepy": {"smile": 0.0, "eyes": 0.3, "brow_y": -0.004, "brow_tilt": -6.0, "brow_lift": 0.0, "mouth_w": 0.7, "rest_open": 0.15},
}

# Mouth shapes for letters: [how open (0 to 1), how wide (1 is normal)].
const VISEMES := {
	"a": [1.0, 1.05], "h": [0.7, 1.0], "e": [0.55, 1.2], "i": [0.45, 1.2], "y": [0.45, 1.15],
	"o": [0.8, 0.65], "u": [0.45, 0.5], "w": [0.35, 0.5], "q": [0.35, 0.55],
	"m": [0.0, 0.95], "b": [0.0, 0.95], "p": [0.0, 0.95], "f": [0.15, 1.0], "v": [0.15, 1.0],
}
const VISEME_OTHER := [0.3, 1.0]  # every other letter or digit
const VISEME_PAUSE := [0.0, 1.0]  # spaces and punctuation
const LETTERS_PER_SECOND := 14.0  # roughly how fast speech engines talk

# The bubble.
const BUBBLE_WIDTH := 0.42  # metres, at arm's length
const BUBBLE_PAGE := 180  # letters a page shows at most
const BUBBLE_LINGER := 3.0  # seconds a page stays after it's been said
const BUBBLE_PIXEL := 0.0006
const BUBBLE_FONT := 28
const BUBBLE_PAD := 0.018
const BUBBLE_GAP := 0.06  # between the top of the head (or hat) and the tail's tip
const READABLE_DISTANCE := 1.2  # beyond this the bubble grows with distance
const MAX_GROW := 3.0
const VIEW_HALF_ANGLE := 32.0  # degrees from the middle of your view where the bubble docks
const DOCK_DISTANCE := 1.1
const DEFAULT_THEME := {
	"panel": Color(0.97, 0.97, 0.95),
	"border": Color(0.15, 0.15, 0.18),
	"text": Color(0.08, 0.08, 0.1),
	"accent": Color(0.97, 0.97, 0.95),
}

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
var _brows: Array[MeshInstance3D] = []
var _mouth: MeshInstance3D
var _mouth_mesh: ImmediateMesh
var _mouth_material: StandardMaterial3D
var _hands: Array[MeshInstance3D] = []

var _bubble: Node3D    # not under _root, so it can leave the avatar to dock
var _bubble_panel: MeshInstance3D
var _bubble_tail: MeshInstance3D
var _bubble_label: Label3D
var _panel_material: StandardMaterial3D
var _border_material: StandardMaterial3D
var _bubble_size := Vector2.ZERO  # the panel, in metres
var _bubble_placed := false

var _state := "idle"
var _state_left := 0.0  # seconds until the state goes back to idle; 0 keeps it
var _emotion := "neutral"
var _emotion_left := 0.0
var _face := EMOTIONS["neutral"].duplicate()  # eases toward the emotion's face
var _outfit := "none"
var _outfit_top := BODY_SIZE / 2.0
var _custom_outfits := {}
var _time := 0.0
var _next_blink := 2.0
var _seen_reply := ""
var _seen_error := ""
var _was_busy := false
var _since_poll := 0.0

# What's being said: the text, how far the mouth is into it, and the pages
# of the bubble.
var _speech := ""
var _speech_at := 0.0
var _mouth_left := 0.0  # seconds of mouthing left when no speech engine talks
var _engine_now := false  # the speech engine is talking (read once a frame)
var _engine_for := 0.0  # seconds the engine has said so without a break
var _engine_limit := ENGINE_UNKNOWN_SECONDS
var _engine_stuck := false
var _mouth_open := 0.0
var _mouth_wide := 1.0
var _drawn_mouth := Vector3(-1, -1, -1)
var _pages := PackedStringArray()
var _page := 0
var _page_left := 0.0


func setup() -> String:
	_build()
	_load()
	_wear(_outfit)
	_root.global_position = Vector3(-0.6, 1.3, -1.0)

	register("avatar_move", _move_command, "move the avatar: position [x, y, z]")
	register("avatar_say", _say_command, "show text in the avatar's speech bubble (it mouths the words): text")
	register("avatar_state", _state_command, "set the avatar's animation: state (%s), optional seconds before it goes back to idle" % ", ".join(STATES))
	register("avatar_emotion", _emotion_command, "set the avatar's face: emotion (%s), optional seconds before it goes back to neutral" % ", ".join(PackedStringArray(EMOTIONS.keys())))
	register("avatar_status", _status_command, "the avatar's place, state, emotion, outfit, whether it's talking and what its bubble shows")
	register("avatar_outfit", _outfit_command, "change the avatar's outfit: name (avatar_outfits lists them)")
	register("avatar_outfits", _outfits_command, "list the avatar's outfits")
	register("avatar_outfit_add", _outfit_add_command, "add or replace an outfit: name, parts [{shape (%s), size [x,y,z], position [x,y,z], optional rotation [x,y,z] degrees, color}]" % ", ".join(SHAPES))
	register("avatar_outfit_remove", _outfit_remove_command, "remove an outfit that was added: name")
	return ""


# --- For other modules ----------------------------------------------------------

# The node that bobs and leans, with the cube, face and outfit in it.
func body() -> Node3D:
	return _body


func say(text: String) -> void:
	_say(text)


func set_state(state: String, seconds := 0.0) -> bool:
	if not state in STATES:
		return false
	_state = state
	_state_left = maxf(seconds, 0.0)
	return true


func set_emotion(emotion: String, seconds := 0.0) -> bool:
	if not EMOTIONS.has(emotion):
		return false
	_emotion = emotion
	_emotion_left = maxf(seconds, 0.0)
	return true


func speaking() -> bool:
	return _mouth_left > 0.0 or _engine_now


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
	# brows, pink cheeks and a mouth that's drawn fresh as it moves.
	var front := -BODY_SIZE / 2.0
	for side in [-1, 1]:
		var eye := _mesh_part("sphere", Vector3(0.04, 0.05, 0.015), Color(0.08, 0.06, 0.07))
		eye.position = Vector3(side * 0.045, 0.02, front)
		_body.add_child(eye)
		_eyes.append(eye)
		var shine := _mesh_part("sphere", Vector3(0.014, 0.014, 0.006), Color(1, 1, 1))
		# The shine is a child of the eye, so it's placed in eye-sized units.
		shine.position = Vector3(0.2, 0.22, -0.45)
		shine.scale = Vector3(1.0 / 0.04, 1.0 / 0.05, 1.0 / 0.015) * 0.014
		eye.add_child(shine)
		var brow := _mesh_part("box", Vector3(0.036, 0.007, 0.006), Color(0.3, 0.05, 0.07))
		brow.position = Vector3(side * 0.045, 0.058, front - 0.002)
		_body.add_child(brow)
		_brows.append(brow)
		var cheek := _mesh_part("sphere", Vector3(0.035, 0.02, 0.006), Color(1.0, 0.55, 0.6))
		cheek.position = Vector3(side * 0.075, -0.02, front)
		_body.add_child(cheek)

	_mouth_mesh = ImmediateMesh.new()
	_mouth_material = StandardMaterial3D.new()
	_mouth_material.albedo_color = Color(0.25, 0.05, 0.08)
	_mouth_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mouth_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mouth = MeshInstance3D.new()
	_mouth.mesh = _mouth_mesh
	_mouth.position = Vector3(0, -0.035, front - 0.0015)
	_body.add_child(_mouth)

	for side in [-1, 1]:
		var hand := _mesh_part("sphere", Vector3.ONE * HAND_RADIUS * 2.0, BODY_COLOR)
		_root.add_child(hand)
		_hands.append(hand)

	_outfit_holder = Node3D.new()
	_body.add_child(_outfit_holder)

	_build_bubble()


# The bubble: a rounded panel with a border and a tail, and the words in
# front. It faces the camera as a whole, so the words and panel stay lined up.
func _build_bubble() -> void:
	_bubble = Node3D.new()
	_bubble.name = "Bubble"
	_bubble.top_level = true
	_bubble.visible = false
	add_child(_bubble)
	_panel_material = StandardMaterial3D.new()
	_panel_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_panel_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_border_material = _panel_material.duplicate()
	_bubble_panel = MeshInstance3D.new()
	_bubble.add_child(_bubble_panel)
	_bubble_tail = MeshInstance3D.new()
	_bubble.add_child(_bubble_tail)
	_bubble_label = Label3D.new()
	_bubble_label.pixel_size = BUBBLE_PIXEL
	_bubble_label.font_size = BUBBLE_FONT
	_bubble_label.width = (BUBBLE_WIDTH - BUBBLE_PAD * 2.0) / BUBBLE_PIXEL
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bubble_label.outline_size = 0
	# The camera looks down -z, so +z is toward you: the words sit just in
	# front of the panel.
	_bubble_label.position = Vector3(0, 0, 0.004)
	_bubble.add_child(_bubble_label)


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
	_check_engine(delta, _read_engine())
	_since_poll += delta
	if _since_poll >= POLL_SECONDS:
		_since_poll = 0.0
		_follow_agent()
	_count_down(delta)
	_face_player(delta)

	var talking := speaking()
	if not talking:
		_speech = ""  # so speech from elsewhere isn't mouthed with an old reply's letters
		_engine_limit = ENGINE_UNKNOWN_SECONDS
	var state := "talking" if talking and _state == "idle" else _state
	_animate_body(state)
	_animate_face(delta, state)
	_animate_mouth(delta, talking)
	_place_bubble(delta)


func _count_down(delta: float) -> void:
	_mouth_left = maxf(_mouth_left - delta, 0.0)
	if _state_left > 0.0:
		_state_left -= delta
		if _state_left <= 0.0:
			_state = "idle"
	if _emotion_left > 0.0:
		_emotion_left -= delta
		if _emotion_left <= 0.0:
			_emotion = "neutral"


# Body: a slow bob, and a lean that depends on the state. The hands float
# beside it, out of step with each other.
func _animate_body(state: String) -> void:
	var bob := sin(_time * 2.0) * 0.012
	var lean := 0.0
	var hop := 0.0
	match state:
		"thinking":
			lean = sin(_time * 1.3) * 8.0
		"talking":
			bob += absf(sin(_time * 9.0)) * 0.008
		"happy":
			hop = absf(sin(_time * 5.0)) * 0.06
	if _emotion == "sad":
		lean += 4.0
		bob *= 0.5
	_body.position = Vector3(0, bob + hop, 0)
	_body.rotation_degrees = Vector3(0, 0, lean)

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
		if _emotion == "sad":
			at.y -= 0.03
		_hands[i].position = at + Vector3(0, bob + hop, 0)


# Eyes, brows and the mouth's resting shape ease toward the emotion. A
# happy state shows a happy face unless another emotion was asked for.
func _animate_face(delta: float, state: String) -> void:
	var emotion := _emotion
	if emotion == "neutral" and state == "happy":
		emotion = "happy"
	var target: Dictionary = EMOTIONS[emotion]
	var blend := clampf(delta * 8.0, 0.0, 1.0)
	for key in target:
		_face[key] = lerpf(_face[key], target[key], blend)

	# Blink every few seconds.
	_next_blink -= delta
	var open: float = _face["eyes"]
	if _next_blink < 0.0:
		open = 0.12
		if _next_blink < -0.12:
			_next_blink = randf_range(2.0, 5.0)
	# Thinking looks up and to one side.
	var look := Vector2(0.006, 0.008) if state == "thinking" else Vector2.ZERO
	for i in _eyes.size():
		var side := -1.0 if i == 0 else 1.0
		_eyes[i].scale = Vector3(0.04, 0.05 * open, 0.015)
		_eyes[i].position = Vector3(side * 0.045 + look.x, 0.02 + look.y, -BODY_SIZE / 2.0)
		var lift: float = _face["brow_lift"] if i == 0 else 0.0
		_brows[i].position = Vector3(side * 0.045, 0.058 + _face["brow_y"] + lift + (0.004 if state == "thinking" else 0.0), -BODY_SIZE / 2.0 - 0.002)
		# The face looks out along -z, so the avatar's left is +x. A positive
		# tilt turns each brow's inner end down.
		_brows[i].rotation_degrees = Vector3(0, 0, side * _face["brow_tilt"])


# The mouth follows the letters being said, else rests in the emotion's
# shape, and is only drawn again when its shape changed.
func _animate_mouth(delta: float, talking: bool) -> void:
	var want_open: float = _face["rest_open"]
	var want_wide: float = _face["mouth_w"]
	if talking:
		var shape := _viseme()
		want_open = shape[0]
		want_wide = shape[1] * _face["mouth_w"]
		_speech_at += delta * LETTERS_PER_SECOND
	var blend := clampf(delta * 22.0, 0.0, 1.0)
	_mouth_open = lerpf(_mouth_open, want_open, blend)
	_mouth_wide = lerpf(_mouth_wide, want_wide, blend)
	var shape_now := Vector3(_mouth_open, _mouth_wide, _face["smile"])
	if shape_now.distance_to(_drawn_mouth) > 0.01:
		_drawn_mouth = shape_now
		_draw_mouth(_mouth_wide, _mouth_open, _face["smile"])


func _viseme() -> Array:
	if _speech.is_empty():
		# Speech that didn't come from a reply or avatar_say: a steady chatter.
		return [0.35 + 0.35 * absf(sin(_time * 11.0)), 1.0]
	var letter := _speech[int(_speech_at) % _speech.length()].to_lower()
	if VISEMES.has(letter):
		return VISEMES[letter]
	if letter.to_upper() != letter or letter.is_valid_int():
		return VISEME_OTHER
	return VISEME_PAUSE


# A lip shape: a strip between an upper and a lower curve. The middle line
# bends up at the corners for a smile and down for a frown; the opening is
# widest in the middle and closes at the corners.
func _draw_mouth(wide: float, open: float, smile: float) -> void:
	const SEGMENTS := 12
	var half := 0.017 * wide
	var lips := 0.0022
	_mouth_mesh.clear_surfaces()
	_mouth_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mouth_material)
	var last_top := Vector3.ZERO
	var last_bottom := Vector3.ZERO
	for i in SEGMENTS + 1:
		var t := -1.0 + 2.0 * i / SEGMENTS
		var middle := smile * 0.011 * (t * t - 0.4)
		var gap := (open * 0.011 + lips) * (1.0 - t * t) + lips * 0.4
		var top := Vector3(t * half, middle + gap, 0)
		var bottom := Vector3(t * half, middle - gap, 0)
		if i > 0:
			_mouth_mesh.surface_add_vertex(last_top)
			_mouth_mesh.surface_add_vertex(top)
			_mouth_mesh.surface_add_vertex(bottom)
			_mouth_mesh.surface_add_vertex(last_top)
			_mouth_mesh.surface_add_vertex(bottom)
			_mouth_mesh.surface_add_vertex(last_bottom)
		last_top = top
		last_bottom = bottom
	_mouth_mesh.surface_end()


func _read_engine() -> bool:
	return ProjectSettings.get_setting("audio/general/text_to_speech", false) and DisplayServer.tts_is_speaking()


# Reads the speech engine once a frame, and stops following it when it has
# said it's speaking for far longer than the words take (see ENGINE_SLACK).
func _check_engine(delta: float, engine: bool) -> void:
	if not engine:
		_engine_for = 0.0
		if _engine_stuck:
			_engine_stuck = false
			print("Slopitect avatar: the speech engine says it has stopped speaking; following it again")
	else:
		_engine_for += delta
		if not _engine_stuck and _engine_for > _engine_limit:
			_engine_stuck = true
			push_warning("Slopitect avatar: the speech engine still says it's speaking after %.0f s (the words take about %.1f s); not following it until it says it has stopped" % [_engine_for, (_engine_limit - ENGINE_EXTRA) / ENGINE_SLACK])
	_engine_now = engine and not _engine_stuck


# The avatar shows what the agent is doing, by reading agent_status like any
# other module would. Without the agent module it just idles.
func _follow_agent() -> void:
	if _engine_now:
		_mouth_left = 0.0  # the engine is talking; follow it, not the estimate
	var status: Dictionary = ctx["server"].run({"cmd": "agent_status"})
	if not status.get("ok", false):
		return
	if status["busy"] and not _was_busy and _state == "idle":
		_state = "thinking"
	elif not status["busy"] and _was_busy and _state == "thinking":
		_state = "idle"
	_was_busy = status["busy"]
	var reply := String(status.get("last_reply", ""))
	if reply != _seen_reply:
		_seen_reply = reply
		if not reply.is_empty():
			_say(reply)
	var error := String(status.get("last_error", ""))
	if error != _seen_error:
		_seen_error = error
		if not error.is_empty() and _emotion == "neutral":
			set_emotion("confused", ERROR_SECONDS)


func _face_player(delta: float) -> void:
	var head: Vector3 = ctx["camera"].global_position
	var to := head - _root.global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	# The face is on -z, so point -z at the player.
	var target := atan2(-to.x, -to.z)
	_root.rotation.y = lerp_angle(_root.rotation.y, target, clampf(delta * TURN_SPEED, 0.0, 1.0))


# --- Speaking and the bubble ------------------------------------------------------

func _say(text: String) -> void:
	_speech = text.strip_edges()
	_speech_at = 0.0
	# Mouthed for as long as it takes to say, unless the speech engine
	# starts talking (then the mouth follows it instead).
	_mouth_left = _speech.length() / LETTERS_PER_SECOND
	_engine_limit = _mouth_left * ENGINE_SLACK + ENGINE_EXTRA
	if not _engine_stuck:
		_engine_for = 0.0
	_pages = _paginate(_speech)
	_page = 0
	_show_page()


# Splits text into pages of up to BUBBLE_PAGE letters, at the end of a
# sentence when one is near, else between words.
func _paginate(text: String) -> PackedStringArray:
	var pages := PackedStringArray()
	var rest := text.replace("\n", " ").strip_edges()
	while rest.length() > BUBBLE_PAGE:
		var cut := -1
		for mark in [". ", "! ", "? ", "; ", ": "]:
			cut = maxi(cut, rest.rfind(mark, BUBBLE_PAGE - 1))
		if cut < BUBBLE_PAGE / 2:
			cut = rest.rfind(" ", BUBBLE_PAGE - 1)
		if cut <= 0:
			cut = BUBBLE_PAGE - 1
		pages.append(rest.left(cut + 1).strip_edges())
		rest = rest.substr(cut + 1).strip_edges()
	if not rest.is_empty():
		pages.append(rest)
	return pages


func _show_page() -> void:
	if _page >= _pages.size():
		_bubble.visible = false
		return
	var text := _pages[_page]
	_page_left = text.length() / LETTERS_PER_SECOND + BUBBLE_LINGER
	_bubble_label.text = text
	_draw_bubble()
	if not _bubble.visible:
		_bubble_placed = false
	_bubble.visible = true


func _theme() -> Dictionary:
	var colours := DEFAULT_THEME.duplicate()
	var ui = ctx["modules"].module("vrui")
	if ui == null or not ui.has_method("theme"):
		ui = ctx["modules"].module("ui")  # before the rename to vrui (or the old vrui draft)
	if ui != null and ui.has_method("theme"):
		var theme: Dictionary = ui.theme()
		for key in colours:
			if theme.get(key) is Color:
				colours[key] = theme[key]
		if theme.get("panel") is Color and not theme.get("accent") is Color:
			colours["accent"] = theme["panel"]
	return colours


# Sizes the panel to the words and draws it, its border and the tail. The
# panel is centred on the bubble's node; the tail hangs below it.
func _draw_bubble() -> void:
	var colours := _theme()
	_panel_material.albedo_color = colours["panel"]
	_border_material.albedo_color = colours["border"]
	_bubble_label.modulate = colours["text"]
	var font: Font = _bubble_label.font if _bubble_label.font != null else ThemeDB.fallback_font
	var most := (BUBBLE_WIDTH - BUBBLE_PAD * 2.0) / BUBBLE_PIXEL
	var px := font.get_multiline_string_size(_bubble_label.text, HORIZONTAL_ALIGNMENT_LEFT, most, BUBBLE_FONT, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var words := Vector2(minf(px.x, most), px.y) * BUBBLE_PIXEL
	# The words' box is exactly as wide as the words, so they sit in the
	# middle of the panel.
	_bubble_label.width = ceilf(minf(px.x, most)) + 2.0
	_bubble_size = words + Vector2.ONE * BUBBLE_PAD * 2.0

	var panel := ImmediateMesh.new()
	_rounded(panel, _bubble_size + Vector2.ONE * 0.006, -0.002, _border_material)
	_rounded(panel, _bubble_size, 0.0, _panel_material)
	_bubble_panel.mesh = panel
	var tail := ImmediateMesh.new()
	var w := 0.02
	var h := 0.035
	var top := -_bubble_size.y / 2.0 + 0.004
	tail.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _border_material)
	tail.surface_add_vertex(Vector3(-w / 2.0 - 0.004, top, -0.001))
	tail.surface_add_vertex(Vector3(w / 2.0 + 0.004, top, -0.001))
	tail.surface_add_vertex(Vector3(0, top - h - 0.005, -0.001))
	tail.surface_end()
	tail.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _panel_material)
	tail.surface_add_vertex(Vector3(-w / 2.0, top, 0.0))
	tail.surface_add_vertex(Vector3(w / 2.0, top, 0.0))
	tail.surface_add_vertex(Vector3(0, top - h, 0.0))
	tail.surface_end()
	_bubble_tail.mesh = tail


# A rounded rectangle in the bubble's plane, as a fan around its middle.
func _rounded(mesh: ImmediateMesh, size: Vector2, z: float, material: Material) -> void:
	const STEPS := 5
	var r := minf(0.02, minf(size.x, size.y) / 2.0)
	var inner := size / 2.0 - Vector2.ONE * r
	var outline := PackedVector2Array()
	for corner in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		var start: float = corner.angle()
		for i in STEPS + 1:
			var a := start - PI / 4.0 + PI / 2.0 * i / STEPS
			outline.append(inner * corner + Vector2(cos(a), sin(a)) * r)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		mesh.surface_add_vertex(Vector3(0, 0, z))
		mesh.surface_add_vertex(Vector3(a.x, a.y, z))
		mesh.surface_add_vertex(Vector3(b.x, b.y, z))
	mesh.surface_end()


# Above the head (and any hat) when you can see the avatar; at the edge of
# your view on the avatar's side when you can't. Always turned to you, and
# bigger with distance so the words stay readable.
func _place_bubble(delta: float) -> void:
	if not _bubble.visible:
		return
	# Pages turn as they're said; the last stays while the speech engine
	# still talks.
	_page_left -= delta
	if _page_left <= 0.0 and not (_page == _pages.size() - 1 and _engine_now):
		_page += 1
		_show_page()
		if not _bubble.visible:
			return

	var camera: Camera3D = ctx["camera"]
	var eye := camera.global_position
	var head := _body.global_position + Vector3.UP * (_outfit_top + BUBBLE_GAP)
	var to := head - eye
	var forward := -camera.global_basis.z
	var in_view := to.normalized().dot(forward) > cos(deg_to_rad(VIEW_HALF_ANGLE))
	var grow := clampf(to.length() / READABLE_DISTANCE, 1.0, MAX_GROW)
	var target: Vector3
	if in_view:
		# The tail's tip sits just above the head.
		target = head + Vector3.UP * (_bubble_size.y / 2.0 + 0.035) * grow
		_bubble_tail.visible = true
	else:
		# Dock at the edge of the view, turned from the middle toward the avatar.
		grow = 1.0
		var flat_forward := Vector3(forward.x, 0, forward.z).normalized()
		var flat_to := Vector3(to.x, 0, to.z).normalized()
		var side := signf(flat_forward.cross(flat_to).y)
		if side == 0.0:
			side = 1.0
		var toward := flat_forward.rotated(Vector3.UP, side * deg_to_rad(VIEW_HALF_ANGLE - 8.0))
		target = eye + toward * DOCK_DISTANCE + Vector3.DOWN * 0.1
		_bubble_tail.visible = false
	if not _bubble_placed:
		_bubble.global_position = target
		_bubble_placed = true
	else:
		_bubble.global_position = _bubble.global_position.lerp(target, clampf(delta * 6.0, 0.0, 1.0))
	# Face the camera: +z toward you, upright.
	var back := eye - _bubble.global_position
	back.y = 0.0
	if back.length() > 0.01:
		_bubble.global_basis = Basis.looking_at(-back.normalized(), Vector3.UP).scaled(Vector3.ONE * grow)


# --- Outfits --------------------------------------------------------------------

func _all_outfits() -> Dictionary:
	var all := OUTFITS.duplicate()
	all.merge(_custom_outfits, true)
	return all


func _wear(outfit_name: String) -> void:
	for child in _outfit_holder.get_children():
		child.queue_free()
	_outfit_top = BODY_SIZE / 2.0
	for part in _all_outfits().get(outfit_name, []):
		var size := _vec(part["size"])
		var piece := _mesh_part(part["shape"], size, Color.from_string(part["color"], Color.WHITE))
		piece.position = _vec(part["position"])
		if part.has("rotation"):
			piece.rotation_degrees = _vec(part["rotation"])
		_outfit_holder.add_child(piece)
		# The bubble goes above the highest part (roughly: its middle plus
		# half its biggest side, whichever way it's turned).
		_outfit_top = maxf(_outfit_top, piece.position.y + maxf(size.x, maxf(size.y, size.z)) / 2.0)
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
	return {"ok": true, "pages": _pages.size()}


func _seconds(request: Dictionary) -> Variant:
	var seconds = request.get("seconds", 0)
	if typeof(seconds) not in [TYPE_INT, TYPE_FLOAT] or seconds < 0 or seconds > 600:
		return null
	return float(seconds)


func _state_command(request: Dictionary) -> Dictionary:
	var seconds = _seconds(request)
	if seconds == null:
		return {"ok": false, "error": "\"seconds\" must be 0 to 600 (0 keeps the state)"}
	if not set_state(str(request.get("state")), seconds):
		return {"ok": false, "error": "\"state\" must be one of %s" % ", ".join(STATES)}
	return {"ok": true, "state": _state}


func _emotion_command(request: Dictionary) -> Dictionary:
	var seconds = _seconds(request)
	if seconds == null:
		return {"ok": false, "error": "\"seconds\" must be 0 to 600 (0 keeps the emotion)"}
	if not set_emotion(str(request.get("emotion")), seconds):
		return {"ok": false, "error": "\"emotion\" must be one of %s" % ", ".join(PackedStringArray(EMOTIONS.keys()))}
	return {"ok": true, "emotion": _emotion}


func _status_command(_request: Dictionary) -> Dictionary:
	var p := _root.global_position
	return {
		"ok": true,
		"position": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
		"state": _state,
		"emotion": _emotion,
		"outfit": _outfit,
		"talking": speaking(),
		"speech_engine_talking": _read_engine(),
		"speech_engine_ignored": _engine_stuck,
		"bubble": _bubble_label.text if _bubble.visible else "",
		"page": [_page + 1, _pages.size()] if _bubble.visible else [0, 0],
		"bubble_docked": _bubble.visible and not _bubble_tail.visible,
	}


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


func _outfit_remove_command(request: Dictionary) -> Dictionary:
	var outfit_name = request.get("name")
	if typeof(outfit_name) != TYPE_STRING or not _custom_outfits.has(outfit_name):
		return {"ok": false, "error": "no added outfit \"%s\" (built-in ones can't be removed)" % str(outfit_name)}
	_custom_outfits.erase(outfit_name)
	if _outfit == outfit_name:
		_wear("none")
	_save()
	return {"ok": true, "removed": outfit_name, "wearing": _outfit}


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
