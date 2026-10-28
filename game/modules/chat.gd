extends SlopitectModule

# Slopitect: talk to the agent from inside the headset.
# Press Y on the left controller to show or hide the chat panel: a terminal
# window at the top showing every step the agent takes (your message, its
# thinking, each command it runs and how it went, its reply), the line
# you're typing, and a keyboard with Send and Stop.
# Type with the menu's laser (right controller, trigger). Send asks the
# agent, exactly like agent_ask from the PC.
# It uses the menu module's laser and buttons, so "menu" must load first.

const KEY_SIZE := Vector2(0.05, 0.05)
const GAP := 0.008
const ROWS := ["1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.?"]
const MAX_PROMPT := 500
const SHOWN_EVENTS := 12
const EVENT_CHARS := 160
const TERMINAL_COLOR := Color(0.03, 0.05, 0.04)
const TERMINAL_TEXT := Color(0.55, 1.0, 0.6)
const POLL_SECONDS := 0.5

var _menu: SlopitectModule
var _panel: Node3D
var _transcript: Label3D
var _line: Label3D
var _shift_key: StaticBody3D
var _typed := ""
var _shift := false
var _since_poll := 0.0


func setup() -> String:
	_menu = ctx["modules"].module("menu")
	if _menu == null:
		return "the chat needs the menu module (its laser and buttons); list \"menu\" before \"chat\" in modules.json"

	_panel = Node3D.new()
	_panel.name = "ChatPanel"
	_panel.visible = false
	add_child(_panel)

	var width := 10 * (KEY_SIZE.x + GAP)
	_add_terminal_background(Vector3(0, 0.205, -0.002), Vector2(width + 0.02, 0.22))
	_transcript = _make_text(Vector3(0, 0.31, 0), width, 26)
	_transcript.modulate = TERMINAL_TEXT
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["monospace"])
	_transcript.font = mono
	_transcript.text = "agent ready. type below and press Send."
	_line = _make_text(Vector3(0, 0.06, 0), width, 40)
	_line.modulate = Color(0.7, 0.9, 1.0)
	_show_line()

	for r in ROWS.size():
		var row: String = ROWS[r]
		for c in row.length():
			var ch := row[c]
			_add_key(ch, Vector3((c - 4.5) * (KEY_SIZE.x + GAP), -r * (KEY_SIZE.y + GAP), 0), KEY_SIZE, _type.bind(ch))
	var bottom := -ROWS.size() * (KEY_SIZE.y + GAP)
	var unit := KEY_SIZE.x + GAP
	_shift_key = _add_key("Shift", Vector3(-3.75 * unit, bottom, 0), Vector2(KEY_SIZE.x * 2 + GAP, KEY_SIZE.y), _toggle_shift)
	_add_key("Space", Vector3(-0.75 * unit, bottom, 0), Vector2(KEY_SIZE.x * 4 + GAP * 3, KEY_SIZE.y), _type.bind(" "))
	_add_key("Del", Vector3(1.75 * unit, bottom, 0), KEY_SIZE, _backspace)
	_add_key("Clear", Vector3(2.75 * unit, bottom, 0), KEY_SIZE, _clear)
	_add_key("Send", Vector3(4.25 * unit, bottom, 0), Vector2(KEY_SIZE.x * 2 + GAP, KEY_SIZE.y), _send)
	_add_key("STOP", Vector3(6.0 * unit, 0.2, 0), Vector2(KEY_SIZE.x * 1.5, KEY_SIZE.y * 1.5), _stop)

	ctx["left"].button_pressed.connect(_on_left_pressed)
	register("chat_show", _show_command, "show or hide the chat panel: visible (true/false)")
	return ""


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	_since_poll += delta
	if _since_poll < POLL_SECONDS:
		return
	_since_poll = 0.0
	# Read the agent through its command, like anything else would.
	var status: Dictionary = ctx["server"].run({"cmd": "agent_status"})
	if not status.get("ok", false):
		_transcript.text = "The agent isn't available: " + String(status.get("error", "?"))
		return
	var lines := PackedStringArray()
	for event in status["events"].slice(-SHOWN_EVENTS):
		var line := String(event).replace("\n", " ")
		lines.append(line.left(EVENT_CHARS) + ("..." if line.length() > EVENT_CHARS else ""))
	var text := "\n".join(lines)
	if status["busy"]:
		text += "\n(working... round %d)" % status["round"]
	elif not status["key_set"] and status["provider"] == "anthropic":
		text += "\n(no API key set yet: see the README)"
	_transcript.text = text


func _on_left_pressed(button: String) -> void:
	if button == "by_button":
		_set_visible(not _panel.visible)


func _show_command(request: Dictionary) -> Dictionary:
	var visible = request.get("visible")
	if typeof(visible) != TYPE_BOOL:
		return {"ok": false, "error": "chat_show needs \"visible\": true or false"}
	_set_visible(visible)
	return {"ok": true, "visible": visible}


func _set_visible(on: bool) -> void:
	if on:
		_place()
	_panel.visible = on
	_menu.laser_wanted = on
	_since_poll = POLL_SECONDS
	print("Slopitect chat: panel ", "shown" if on else "hidden")


# In front of you, a bit low, tilted up towards your eyes like a desk.
func _place() -> void:
	var head: Transform3D = ctx["camera"].global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	_panel.global_position = head.origin + forward * 0.55 + Vector3(0, -0.35, 0)
	_panel.look_at(head.origin, Vector3.UP, true)


func _type(ch: String) -> void:
	if _typed.length() >= MAX_PROMPT:
		return
	_typed += ch.to_upper() if _shift else ch
	if _shift:
		_toggle_shift()
	_show_line()


func _toggle_shift() -> void:
	_shift = not _shift
	(_shift_key.get_node("Label3D") as Label3D).text = "SHIFT" if _shift else "Shift"


func _backspace() -> void:
	_typed = _typed.left(-1)
	_show_line()


func _clear() -> void:
	_typed = ""
	_show_line()


func _send() -> void:
	if _typed.strip_edges().is_empty():
		return
	var reply: Dictionary = ctx["server"].run({"cmd": "agent_ask", "prompt": _typed})
	if reply.get("ok", false):
		_typed = ""
	else:
		_transcript.text += "\nCan't send: " + String(reply.get("error", "?"))
	_show_line()
	_since_poll = POLL_SECONDS


func _stop() -> void:
	var reply: Dictionary = ctx["server"].run({"cmd": "agent_stop"})
	if not reply.get("ok", false):
		_transcript.text += "\nCan't stop: " + String(reply.get("error", "?"))
	_since_poll = POLL_SECONDS


func _show_line() -> void:
	_line.text = "> " + _typed + "_"


func _add_key(label: String, at: Vector3, size: Vector2, on_press: Callable) -> StaticBody3D:
	var key: StaticBody3D = _menu.make_button(label, size, at)
	key.set_meta("on_press", on_press)
	var text := key.get_child(key.get_child_count() - 1) as Label3D
	text.name = "Label3D"
	_panel.add_child(key)
	return key


func _add_terminal_background(at: Vector3, size: Vector2) -> void:
	var back := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	back.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = TERMINAL_COLOR
	back.material_override = material
	back.position = at
	_panel.add_child(back)


func _make_text(at: Vector3, width: float, size: int) -> Label3D:
	var text := Label3D.new()
	text.position = at
	text.pixel_size = 0.0006
	text.font_size = size
	text.width = width / text.pixel_size
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_panel.add_child(text)
	return text
