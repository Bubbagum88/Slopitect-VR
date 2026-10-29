extends SlopitectModule

# Slopitect live module: keyboard.
# One keyboard in its own floating window, "Keyboard", instead of keys on
# every window. What you type shows on its own display line (Shift makes the
# next letter a capital; Del and Clr work on it) and goes nowhere until Run
# (Send): then it's put in the terminal's line when you last pointed at the
# terminal, otherwise in the input box you picked in any window (the chat's
# line, a world's name, ...), otherwise in the terminal if it's open, and
# run there (the terminal's Run, or the window's "send" button if it has
# one). While the terminal is loaded it takes the chat window over, so chat
# goes through the terminal too. The layout follows where it sends: the
# command symbols for the terminal's command line, ' ? ! for words. The keys
# are taken off the terminal and chat windows while it's loaded; unloading
# it gives the terminal its own keys back.
# A Menu tile and a hand menu button open it, like the terminal's.
# From the headset agent's keyboard.gd, 2026-10-29.

const PANEL := "keyboard"
const TERMINAL := "terminal"
const CHAT := "chat"
const KEY := 0.045
const GAP := 0.007
const UNIT := KEY + GAP
const COLS := 11  # keys in a row
const ROW_Y := 0.14  # centre of the top row of keys, in the window
const CHECK_SECONDS := 0.25
const COMMAND_KEYS := ["1234567890-", "qwertyuiop/", "asdfghjkl_=", "zxcvbnm,.[]"]
const WORD_KEYS := ["1234567890-", "qwertyuiop'", "asdfghjkl?!", "zxcvbnm,./:"]
# Keyboard parts on the terminal and chat windows (the row keys are key_R_C).
const OTHER_IDS := ["space", "del", "clear", "quote", "shift"]
const DISPLAY := "display"
const SHOWN := 36  # most characters the display line shows

var _since := CHECK_SECONDS
var _layout := ""  # "command" or "words": the keys the window was built with
var _text := ""  # typed on the display line, not sent yet
var _shift := false  # the next letter is a capital


func setup() -> String:
	register("keyboard_type", _type_command, "type on the keyboard's display line: text")
	register("keyboard_key", _key_command, "a key on the keyboard: key (shift, backspace, clear: on the display line; run: send it)")
	register("keyboard_status", _status, "what the keyboard types into now (terminal, an input box, or nothing) and its layout")
	return ""


func _exit_tree() -> void:
	if ctx["modules"].module(name) != null:
		return  # the app is closing, not unloading this
	_run({"cmd": "ui_remove", "id_panel": PANEL})
	# Back to the terminal's own keys: it's built again, in the mode it's in.
	var mode: String = _run({"cmd": "terminal_status"}).get("mode", "")
	if mode in ["terminal", "chat"]:
		_run({"cmd": "terminal_mode", "mode": "chat" if mode == "terminal" else "terminal"})
		_run({"cmd": "terminal_mode", "mode": mode})


# A tile on the Menu bar, and a button on the hand menu (like the terminal's).
func menu_info() -> Dictionary:
	return {"id": "keyboard", "label": "Keyboard", "order": 55, "panel": PANEL, "tools": true}


func hand_info() -> Dictionary:
	return {"id": "keyboard", "label": "Keyboard", "order": 25, "panel": PANEL}


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


func _ui() -> SlopitectModule:
	var ui: SlopitectModule = ctx["modules"].module("vrui")
	return ui if ui != null and ui.has_method("focus") else null


func _process(delta: float) -> void:
	_since += delta
	if _since < CHECK_SECONDS:
		return
	_since = 0.0
	if _ui() == null:
		return
	var shown := _shown()
	var target := _target(shown)
	var layout := "command" if target == TERMINAL and _run({"cmd": "terminal_status"}).get("mode", "") == "terminal" else "words"
	if layout != _layout or not shown.has(PANEL):
		_layout = layout
		_build(layout, shown.has(PANEL))
	for id_panel in [TERMINAL, CHAT]:
		if shown.has(id_panel):
			_strip(id_panel)


# Where the keys go: TERMINAL, "panel/element" (an input box), or "".
func _target(shown: Dictionary) -> String:
	var ui := _ui()
	if ui == null:
		return ""
	var terminal: bool = ctx["modules"].module(TERMINAL) != null and shown.get(TERMINAL, false)
	if terminal and ui.call("last_pointed", PANEL) == TERMINAL:
		return TERMINAL
	var focus: String = ui.call("focus")
	if not focus.is_empty() and shown.get(focus.get_slice("/", 0), false):
		return focus
	return TERMINAL if terminal else ""


func _shown() -> Dictionary:
	var shown := {}
	for panel in _run({"cmd": "ui_list"}).get("panels", []):
		shown[panel.get("id_panel")] = panel.get("visible", false)
	return shown


# A key that types: it goes on the display line (a capital after Shift).
func _type_command(request: Dictionary) -> Dictionary:
	var text = request.get("text")
	if typeof(text) != TYPE_STRING or text.is_empty():
		return {"ok": false, "error": "keyboard_type needs \"text\""}
	if _shift and text.to_upper() != text.to_lower():
		text = text.to_upper()
		_shift = false
	_text += text
	_show()
	return {"ok": true}


# Shift, Del and Clr work on the display line; Run sends it.
func _key_command(request: Dictionary) -> Dictionary:
	match request.get("key"):
		"shift":
			_shift = not _shift
		"backspace":
			_text = _text.left(_text.length() - 1)
		"clear":
			_text = ""
		"run":
			return _send()
		_:
			return {"ok": false, "error": "\"key\" must be shift, backspace, clear or run"}
	_show()
	return {"ok": true}


# Puts the display's text in what the keyboard types into, in one go, and
# runs it there: the terminal's Run, or the input box's window's "send".
func _send() -> Dictionary:
	var target := _target(_shown())
	var reply: Dictionary
	if target == TERMINAL:
		_run({"cmd": "terminal_key", "key": "clear"})
		if not _text.is_empty():
			_run({"cmd": "terminal_type", "text": _text})
		reply = _run({"cmd": "terminal_key", "key": "run"})
	elif target.is_empty():
		return {"ok": false, "error": "nothing to send to: open the terminal or pick an input box"}
	else:
		_run({"cmd": "ui_key", "key": "clear"})
		if not _text.is_empty():
			_run({"cmd": "ui_type", "text": _text})
		reply = _run({"cmd": "ui_press", "id_panel": target.get_slice("/", 0), "id_element": "send"})
		if not reply.get("ok", false) and str(reply.get("error", "")).begins_with("no button"):
			reply = {"ok": true, "typed_into": target}  # a window with no Send: the text in its box is the end of it
	if reply.get("ok", false) or reply.get("wait") != null:
		_text = ""
		_shift = false
		_show()
	return reply


# What the display line says.
func _display() -> String:
	var line := "> " + (_text if _text.length() <= SHOWN else "..." + _text.right(SHOWN))
	if _text.is_empty():
		line = "> type here"
	return line + ("  [Shift]" if _shift else "")


# Changes only the display line, without building the window again.
func _show() -> void:
	var ui := _ui()
	if ui != null and ui.has_method("set_text"):
		ui.call("set_text", PANEL, DISPLAY, _display())


func _status(_request: Dictionary) -> Dictionary:
	return {"ok": true, "typing_into": _target(_shown()), "layout": _layout, "text": _text, "shift": _shift}


# Takes the keys off a window. The shift key is there whenever the window
# has its keyboard, so a window without one costs a single call.
func _strip(id_panel: String) -> void:
	if not _run({"cmd": "ui_element_remove", "id_panel": id_panel, "id_element": "shift"}).get("ok", false):
		return
	for id in OTHER_IDS:
		_run({"cmd": "ui_element_remove", "id_panel": id_panel, "id_element": id})
	for r in 4:
		for c in COLS:
			_run({"cmd": "ui_element_remove", "id_panel": id_panel, "id_element": "key_%d_%d" % [r, c]})


# The window's keys: letters and figures, then Shift, Space, Del, Clr and
# Run (Send for words).
func _build(layout: String, exists: bool) -> void:
	var words := layout == "words"
	var keys: Array = WORD_KEYS if words else COMMAND_KEYS
	var width := COLS * UNIT - GAP
	var left := -width / 2.0
	var elements := [{"type": "text", "id": DISPLAY, "text": _display(), "at": [0.0, ROW_Y + KEY / 2.0 + 0.03], "width": width, "font_size": 28}]
	for r in keys.size():
		var row: String = keys[r]
		for c in row.length():
			var ch: String = row.substr(c, 1)
			elements.append({"type": "button", "id": "key_%d_%d" % [r, c], "label": ch,
				"at": [left + KEY / 2.0 + c * UNIT, ROW_Y - r * UNIT], "size": [KEY, KEY],
				"action": {"cmd": "keyboard_type", "text": ch}})
	var bottom := ROW_Y - keys.size() * UNIT
	var bottom_row := [
		["shift", "Shift", 2, {"cmd": "keyboard_key", "key": "shift"}],
		["quote", "\"", 1, {"cmd": "keyboard_type", "text": "\""}],
		["space", "Space", 4, {"cmd": "keyboard_type", "text": " "}],
		["del", "Del", 1, {"cmd": "keyboard_key", "key": "backspace"}],
		["clear", "Clr", 1, {"cmd": "keyboard_key", "key": "clear"}],
		["run", "Run", 2, {"cmd": "keyboard_key", "key": "run"}]]
	if words:
		bottom_row = [
			["shift", "Shift", 2, {"cmd": "keyboard_key", "key": "shift"}],
			["space", "Space", 4, {"cmd": "keyboard_type", "text": " "}],
			["del", "Del", 2, {"cmd": "keyboard_key", "key": "backspace"}],
			["clear", "Clr", 1, {"cmd": "keyboard_key", "key": "clear"}],
			["run", "Send", 2, {"cmd": "keyboard_key", "key": "run"}]]
	var x := left
	for key in bottom_row:
		var w: float = key[2] * UNIT - GAP
		var button := {"type": "button", "id": key[0], "label": key[1],
			"at": [x + w / 2.0, bottom], "size": [w, KEY], "action": key[3]}
		if key[0] == "run":
			button["color"] = "ok"
		elements.append(button)
		x += key[2] * UNIT
	if exists:
		# Only the elements: where you put the window stays.
		_run({"cmd": "ui_update", "id_panel": PANEL, "elements": elements})
	else:
		_run({"cmd": "ui_add", "id_panel": PANEL, "title": "Keyboard", "place": "front",
			"distance": 0.6, "height": -0.4, "chrome": true, "elements": elements})
