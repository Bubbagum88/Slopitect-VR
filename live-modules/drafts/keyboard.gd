extends SlopitectModule

# Slopitect live module: keyboard.
# A keyboard in its own free-floating window, "Keyboard", for the terminal
# and the agent's chat. Its keys type into the terminal (terminal_type,
# terminal_key), in the layout of the mode the terminal is in (terminal or
# chat). The keys are taken off the terminal and chat windows, which keep
# their screens, input and tools. Unloading it puts the terminal's keys back.
# A Menu tile and a hand menu button open it, like the terminal's.

const PANEL := "keyboard"
const TERMINAL := "terminal"
const CHAT := "chat"
const KEY := 0.045
const GAP := 0.007
const UNIT := KEY + GAP
const COLS := 11  # keys in a row
const ROW_Y := 0.14  # centre of the top row of keys, in the window
const CHECK_SECONDS := 0.25
const TERMINAL_KEYS := ["1234567890-", "qwertyuiop/", "asdfghjkl_=", "zxcvbnm,.[]"]
const CHAT_KEYS := ["1234567890-", "qwertyuiop'", "asdfghjkl?!", "zxcvbnm,./:"]
# Keyboard parts on the terminal and chat windows (the row keys are key_R_C).
const OTHER_IDS := ["space", "del", "clear", "quote", "shift"]

var _since := CHECK_SECONDS
var _mode := ""  # the layout the window was built with


func setup() -> String:
	return ""


func _exit_tree() -> void:
	ctx["server"].run({"cmd": "ui_remove", "id_panel": PANEL})
	# Back to the terminal's own keys: it's built again, in the mode it's in.
	var mode := _terminal_mode()
	var other := "terminal" if mode == "chat" else "chat"
	ctx["server"].run({"cmd": "terminal_mode", "mode": other})
	ctx["server"].run({"cmd": "terminal_mode", "mode": mode})


# A tile on the Menu bar, and a button on the hand menu (like the terminal's).
func menu_info() -> Dictionary:
	return {"id": "keyboard", "label": "Keyboard", "order": 55, "panel": PANEL, "tools": true}


func hand_info() -> Dictionary:
	return {"id": "keyboard", "label": "Keyboard", "order": 25, "panel": PANEL}


func _process(delta: float) -> void:
	_since += delta
	if _since < CHECK_SECONDS:
		return
	_since = 0.0
	_check()


func _check() -> void:
	var panels := {}
	for panel in ctx["server"].run({"cmd": "ui_list"}).get("panels", []):
		panels[panel.get("id_panel")] = panel
	if not panels.has(TERMINAL):
		return
	var mode := _terminal_mode()
	if mode != _mode or not panels.has(PANEL):
		_mode = mode
		_build(mode, panels.has(PANEL))
	_strip(TERMINAL)
	if panels.has(CHAT):
		_strip(CHAT)


func _terminal_mode() -> String:
	var term: SlopitectModule = ctx["modules"].module(TERMINAL)
	if term == null:
		return "terminal"
	return "chat" if term.get("_mode") == "chat" else "terminal"


# Takes the keys off a window. The shift key is there whenever the window
# has its keyboard, so a window without one costs a single call.
func _strip(panel: String) -> void:
	var first: Dictionary = ctx["server"].run({"cmd": "ui_element_remove", "id_panel": panel, "id_element": "shift"})
	if not first.get("ok", false):
		return
	for id in OTHER_IDS:
		ctx["server"].run({"cmd": "ui_element_remove", "id_panel": panel, "id_element": id})
	for r in 4:
		for c in COLS:
			ctx["server"].run({"cmd": "ui_element_remove", "id_panel": panel, "id_element": "key_%d_%d" % [r, c]})


# The window's keys, in the layout of the mode: letters and figures, then a
# row of Shift, Space, Del, Clr and Run (Send in chat).
func _build(mode: String, exists: bool) -> void:
	var chat := mode == "chat"
	var keys: Array = CHAT_KEYS if chat else TERMINAL_KEYS
	var width := COLS * UNIT - GAP
	var left := -width / 2.0
	var elements := []
	for r in keys.size():
		var row: String = keys[r]
		for c in row.length():
			var ch: String = row.substr(c, 1)
			elements.append({"type": "button", "id": "key_%d_%d" % [r, c], "label": ch,
				"at": [left + KEY / 2.0 + c * UNIT, ROW_Y - r * UNIT], "size": [KEY, KEY],
				"action": {"cmd": "terminal_type", "text": ch}})
	var bottom := ROW_Y - keys.size() * UNIT
	var bottom_row := [
		["shift", "Shift", 2, {"cmd": "terminal_key", "key": "shift"}],
		["quote", "\"", 1, {"cmd": "terminal_type", "text": "\""}],
		["space", "Space", 4, {"cmd": "terminal_type", "text": " "}],
		["del", "Del", 1, {"cmd": "terminal_key", "key": "backspace"}],
		["clear", "Clr", 1, {"cmd": "terminal_key", "key": "clear"}],
		["run", "Run", 2, {"cmd": "terminal_key", "key": "run"}]]
	if chat:
		bottom_row = [
			["shift", "Shift", 2, {"cmd": "terminal_key", "key": "shift"}],
			["space", "Space", 4, {"cmd": "terminal_type", "text": " "}],
			["del", "Del", 2, {"cmd": "terminal_key", "key": "backspace"}],
			["clear", "Clr", 1, {"cmd": "terminal_key", "key": "clear"}],
			["run", "Send", 2, {"cmd": "terminal_key", "key": "run"}]]
	var x := left
	for key in bottom_row:
		var w: float = key[2] * UNIT - GAP
		var button := {"type": "button", "id": key[0], "label": key[1],
			"at": [x + w / 2.0, bottom], "size": [w, KEY], "action": key[3]}
		if key[0] == "run":
			button["color"] = "#2a6f3a"
		elements.append(button)
		x += key[2] * UNIT
	if exists:
		# Only the elements: where you put the window stays.
		ctx["server"].run({"cmd": "ui_update", "id_panel": PANEL, "elements": elements})
	else:
		ctx["server"].run({"cmd": "ui_add", "id_panel": PANEL, "title": "Keyboard", "place": "front",
			"distance": 0.6, "height": -0.4, "chrome": true, "elements": elements})
