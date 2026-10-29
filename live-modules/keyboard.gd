extends SlopitectModule

# Slopitect live module: keyboard.
# One keyboard in its own floating window, "Keyboard", instead of keys on
# every window. What you type shows on its own display line (Shift makes the
# next letter a capital; Del and Clr work on it) and goes nowhere until Run
# (Send): then it goes to the window that has the focus (the last one you
# pulled the trigger on or opened; vrui lights its edge): the terminal's
# line, or that window's input box (the chat's line, a world's name, ...).
# With no such window it goes to the input box you last picked, otherwise
# the terminal if it's open. It's run there (the terminal's Run, or the
# window's "send" button if it has one). The keyboard never takes the focus
# itself. While the terminal is loaded it takes the chat window over, so
# chat goes through the terminal too. The layout follows where it sends:
# the command symbols for the terminal's command line, ' ? ! for words.
# Hide folds the keys away, leaving the display line, Keys and Send.
# With textEdit.gd loaded the line can be edited (a cursor, Sel, Cut, Copy,
# Paste, Undo, ...; see there): its keys are on two rows over the letters,
# with Take, which brings in what's in the focused window's box (or the
# terminal's line) to change and Send back. Without it, typing goes on the
# end of the line.
# The terminal builds itself without keys while this is loaded (and with
# them again when it's unloaded); the chat window's keys are taken off.
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
# Keyboard parts on the chat window (the row keys are key_R_C).
const OTHER_IDS := ["space", "del", "clear", "quote", "shift"]
const DISPLAY := "display"
# textEdit's keys, over the letters: [key, label, width in keys] (Take is this module's).
const EDIT_ROWS := [
	[["left", "<", 1.0], ["right", ">", 1.0], ["word_left", "<<", 1.0], ["word_right", ">>", 1.0],
		["home", "Home", 1.5], ["end", "End", 1.5], ["select", "Sel", 2.0], ["all", "All", 2.0]],
	[["cut", "Cut", 1.5], ["copy", "Copy", 1.5], ["paste", "Paste", 1.5], ["take", "Take", 1.5],
		["delete", "Del>", 1.5], ["case", "Aa", 1.0], ["undo", "Undo", 1.25], ["redo", "Redo", 1.25]]]
const SHOWN := 36  # most characters the display line shows

var _since := CHECK_SECONDS
var _layout := ""  # "command" or "words": the keys the window was built with
var _text := ""  # typed on the display line, not sent yet
var _shift := false  # the next letter is a capital
var _edit_id := 0  # the textEdit module the window was built with (0: none)
var _collapsed := false  # the keys folded away: only the display line, Keys and Send
var _built_collapsed := false


func setup() -> String:
	register("keyboard_type", _type_command, "type on the keyboard's display line: text")
	register("keyboard_key", _key_command, "a key on the keyboard: key (shift, backspace, clear: on the display line; take: bring in the focused box's text, with textEdit; run: send it; collapse: hide or show the keys)")
	register("keyboard_status", _status, "what the keyboard types into now (terminal, an input box, or nothing) and its layout")
	return ""


func _exit_tree() -> void:
	if ctx["modules"].module(name) != null:
		return  # the app is closing, not unloading this
	_run({"cmd": "ui_remove", "id_panel": PANEL})  # the terminal sees this gone and builds its own keys again


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
	var edit := _edit()
	var edit_id := edit.get_instance_id() if edit != null else 0
	if layout != _layout or _collapsed != _built_collapsed or edit_id != _edit_id or not shown.has(PANEL):
		_edit_id = edit_id
		_layout = layout
		_build(layout, shown.has(PANEL))
	if shown.has(CHAT):
		_strip(CHAT)


# Where the keys go: TERMINAL, "panel/element" (an input box), or "".
func _target(shown: Dictionary) -> String:
	var ui := _ui()
	if ui == null:
		return ""
	var terminal: bool = ctx["modules"].module(TERMINAL) != null and shown.get(TERMINAL, false)
	var focus: String = ui.call("focus")
	var window: String = ui.call("focused_window")
	if terminal and window == TERMINAL:
		return TERMINAL
	if not window.is_empty() and focus.begins_with(window + "/"):
		return focus
	# The focused window has no input box (or none is focused): as before.
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
	if _edit() != null:
		_edit().call("insert", text)
	else:
		_text += text
	_show()
	return {"ok": true}


# Shift, Del and Clr work on the display line; Run sends it.
func _key_command(request: Dictionary) -> Dictionary:
	match request.get("key"):
		"shift":
			_shift = not _shift
		"backspace":
			if _edit() != null:
				_edit().call("backspace")
			else:
				_text = _text.left(_text.length() - 1)
		"clear":
			_set_line("")
		"take":
			return _take()
		"run":
			return _send()
		"collapse":
			_collapsed = not _collapsed
			_build(_layout, _shown().has(PANEL))
			return {"ok": true, "collapsed": _collapsed}
		_:
			return {"ok": false, "error": "\"key\" must be shift, backspace, clear, take, run or collapse"}
	_show()
	return {"ok": true}


# Puts the display's text in what the keyboard types into, in one go, and
# runs it there: the terminal's Run, or the input box's window's "send".
func _send() -> Dictionary:
	var target := _target(_shown())
	var text := _line()
	var reply: Dictionary
	if target == TERMINAL:
		_run({"cmd": "terminal_key", "key": "clear"})
		if not text.is_empty():
			_run({"cmd": "terminal_type", "text": text})
		reply = _run({"cmd": "terminal_key", "key": "run"})
	elif target.is_empty():
		return {"ok": false, "error": "nothing to send to: open the terminal or pick an input box"}
	else:
		_run({"cmd": "ui_key", "key": "clear"})
		if not text.is_empty():
			_run({"cmd": "ui_type", "text": text})
		reply = _run({"cmd": "ui_press", "id_panel": target.get_slice("/", 0), "id_element": "send"})
		if not reply.get("ok", false) and str(reply.get("error", "")).begins_with("no button"):
			reply = {"ok": true, "typed_into": target}  # a window with no Send: the text in its box is the end of it
	if reply.get("ok", false) or reply.get("wait") != null:
		_set_line("")
		_shift = false
		_show()
	return reply


func _edit() -> SlopitectModule:
	var edit: SlopitectModule = ctx["modules"].module("textEdit")
	return edit if edit != null and edit.has_method("insert") else null


# The line typed so far: textEdit's when it's loaded, else this one's.
func _line() -> String:
	return _edit().call("text") if _edit() != null else _text


func _set_line(text: String) -> void:
	if _edit() != null:
		_edit().call("set_text", text)
	else:
		_text = text


# textEdit changed the line (one of its keys).
func text_changed() -> void:
	_show()


# Brings in what's in the box the keyboard sends to (or the terminal's line),
# to change it and Send it back.
func _take() -> Dictionary:
	var target := _target(_shown())
	var ui := _ui()
	if target.is_empty() or ui == null or not ui.has_method("input_text"):
		return {"ok": false, "error": "nothing to take from: open the terminal or pick an input box"}
	var text: String
	if target == TERMINAL:
		text = str(_run({"cmd": "terminal_status"}).get("line", ""))
	else:
		text = ui.call("input_text", target)
	_set_line(text)
	_show()
	return {"ok": true, "took": text.length()}


# What the display line says.
func _display() -> String:
	var line := "> " + (_text if _text.length() <= SHOWN else "..." + _text.right(SHOWN))
	if _edit() != null:
		line = "> " + _edit().call("display", SHOWN)
	if _line().is_empty():
		line = "> type here"
	return line + ("  [Shift]" if _shift else "")


# Changes only the display line, without building the window again.
func _show() -> void:
	var ui := _ui()
	if ui != null and ui.has_method("set_text"):
		ui.call("set_text", PANEL, DISPLAY, _display())


func _status(_request: Dictionary) -> Dictionary:
	return {"ok": true, "typing_into": _target(_shown()), "layout": _layout, "text": _line(), "shift": _shift, "collapsed": _collapsed}


# Takes the keys off the chat window. The shift key is there whenever the window
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
# Run (Send for words). Hide, beside the display line, folds the keys away;
# folded, the line has Keys (to unfold them) and Send beside it.
func _build(layout: String, exists: bool) -> void:
	var words := layout == "words"
	var keys: Array = WORD_KEYS if words else COMMAND_KEYS
	var width := COLS * UNIT - GAP
	var left := -width / 2.0
	var editing := _edit() != null and not _collapsed
	var line_y := ROW_Y + KEY / 2.0 + 0.03 + (2 * UNIT if editing else 0.0)
	var toggle_w := 2 * UNIT - GAP
	var beside := 2 * UNIT * (2 if _collapsed else 1)  # room for Keys and Send, or Hide
	var elements := [{"type": "text", "id": DISPLAY, "text": _display(), "at": [-beside / 2.0, line_y + 0.012], "width": width - beside, "font_size": 28},
		{"type": "button", "id": "collapse", "label": "Keys" if _collapsed else "Hide",
			"at": [width / 2.0 - toggle_w / 2.0 - (2 * UNIT if _collapsed else 0.0), line_y], "size": [toggle_w, KEY],
			"action": {"cmd": "keyboard_key", "key": "collapse"}}]
	_built_collapsed = _collapsed
	if _collapsed:
		elements.append({"type": "button", "id": "run", "label": "Send" if words else "Run", "color": "ok",
			"at": [width / 2.0 - toggle_w / 2.0, line_y], "size": [toggle_w, KEY],
			"action": {"cmd": "keyboard_key", "key": "run"}})
		keys = []
	for r in keys.size():
		var row: String = keys[r]
		for c in row.length():
			var ch: String = row.substr(c, 1)
			elements.append({"type": "button", "id": "key_%d_%d" % [r, c], "label": ch,
				"at": [left + KEY / 2.0 + c * UNIT, ROW_Y - r * UNIT], "size": [KEY, KEY],
				"action": {"cmd": "keyboard_type", "text": ch}})
	if editing:
		for e in EDIT_ROWS.size():
			var edit_x := left
			for key in EDIT_ROWS[e]:
				var w: float = key[2] * UNIT - GAP
				var action := {"cmd": "keyboard_key", "key": "take"} if key[0] == "take" else {"cmd": "text_key", "key": key[0]}
				elements.append({"type": "button", "id": "edit_" + key[0], "label": key[1],
					"at": [edit_x + w / 2.0, ROW_Y + (2 - e) * UNIT], "size": [w, KEY], "action": action})
				edit_x += key[2] * UNIT
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
	if _collapsed:
		bottom_row = []
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
		_run({"cmd": "ui_update", "id_panel": PANEL, "elements": elements, "focusable": false})
	else:
		_run({"cmd": "ui_add", "id_panel": PANEL, "title": "Keyboard", "place": "front",
			"distance": 0.6, "height": -0.4, "chrome": true, "focusable": false, "elements": elements})
