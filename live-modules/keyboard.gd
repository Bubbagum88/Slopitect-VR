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
# Editing, on the row over the letters: < and > move the cursor (with Sel
# on they pick the letters they pass over), All picks the whole line, Cut,
# Copy and Paste use the app's clipboard (vrui's), and Take brings in what's
# in the focused window's box (or the terminal's line) to change and Send
# back. With nothing picked on the line, Copy takes the rows picked on the
# focused window's screen (pull the trigger on the terminal's screen and
# move along), otherwise the whole line. Typing or Paste replaces what's
# picked.
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
const SHOWN := 36  # most characters the display line shows

var _since := CHECK_SECONDS
var _layout := ""  # "command" or "words": the keys the window was built with
var _text := ""  # typed on the display line, not sent yet
var _shift := false  # the next letter is a capital
var _caret := 0  # where typing goes on the display line (letters before it)
var _anchor := -1  # the other end of the letters picked on the line, or -1: none
var _picking := false  # Sel: the cursor keys pick the letters they pass over
var _collapsed := false  # the keys folded away: only the display line, Keys and Send
var _built_collapsed := false


func setup() -> String:
	register("keyboard_type", _type_command, "type on the keyboard's display line: text")
	register("keyboard_key", _key_command, "a key on the keyboard: key (shift, backspace, clear, left, right, select, all, cut, copy, paste, take: on the display line; run: send it; collapse: hide or show the keys)")
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
	if layout != _layout or _collapsed != _built_collapsed or not shown.has(PANEL):
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
	_insert(text)
	_show()
	return {"ok": true}


# Shift, Del and Clr work on the display line; Run sends it.
func _key_command(request: Dictionary) -> Dictionary:
	match request.get("key"):
		"shift":
			_shift = not _shift
		"backspace":
			if _anchor == -1 and _caret > 0:
				_anchor = _caret - 1
			_insert("")
		"clear":
			_set_text("")
		"left", "right":
			_move(-1 if request["key"] == "left" else 1)
		"select":
			_picking = not _picking
			if not _picking and _anchor == _caret:
				_anchor = -1
		"all":
			_anchor = 0
			_caret = _text.length()
		"copy", "cut":
			return _copy(request["key"] == "cut")
		"paste":
			var ui := _ui()
			var text: String = ui.call("clipboard") if ui != null else ""
			if text.is_empty():
				return {"ok": false, "error": "nothing has been copied"}
			_insert(text)
		"take":
			return _take()
		"run":
			return _send()
		"collapse":
			_collapsed = not _collapsed
			_build(_layout, _shown().has(PANEL))
			return {"ok": true, "collapsed": _collapsed}
		_:
			return {"ok": false, "error": "\"key\" must be shift, backspace, clear, left, right, select, all, cut, copy, paste, take, run or collapse"}
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
		_set_text("")
		_shift = false
		_show()
	return reply


# Puts text in place of what's picked on the line (or at the cursor).
func _insert(text: String) -> void:
	var from := _caret if _anchor == -1 else mini(_caret, _anchor)
	var to := _caret if _anchor == -1 else maxi(_caret, _anchor)
	_text = _text.left(from) + text + _text.substr(to)
	_caret = from + text.length()
	_anchor = -1


func _set_text(text: String) -> void:
	_text = text
	_caret = text.length()
	_anchor = -1
	_picking = false


# The cursor one letter left or right. With Sel on it picks as it goes;
# without, a pick is let go (the cursor goes to its edge).
func _move(step: int) -> void:
	if _picking:
		if _anchor == -1:
			_anchor = _caret
		_caret = clampi(_caret + step, 0, _text.length())
		return
	if _anchor != -1:
		_caret = mini(_caret, _anchor) if step < 0 else maxi(_caret, _anchor)
		_anchor = -1
		return
	_caret = clampi(_caret + step, 0, _text.length())


# Copy (or Cut): the letters picked on the line; with none, the rows picked
# on the focused window's screen (Copy only); otherwise the whole line.
func _copy(cut: bool) -> Dictionary:
	var ui := _ui()
	if ui == null:
		return {"ok": false, "error": "no vrui"}
	var text := ""
	if _anchor != -1 and _anchor != _caret:
		text = _text.substr(mini(_caret, _anchor), absi(_caret - _anchor))
		if cut:
			_insert("")
	else:
		var window: String = ui.call("focused_window")
		if not cut and not window.is_empty():
			text = ui.call("selected_text", window)
		if text.is_empty():
			text = _text
			if cut:
				_set_text("")
	if text.is_empty():
		return {"ok": false, "error": "nothing to copy: pick letters or rows, or type something"}
	ui.call("copy_text", text)
	_show()
	return {"ok": true, "copied": text.length()}


# Brings in what's in the box the keyboard sends to (or the terminal's line),
# to change it on the display line and Send it back.
func _take() -> Dictionary:
	var target := _target(_shown())
	var ui := _ui()
	if target.is_empty() or ui == null:
		return {"ok": false, "error": "nothing to take from: open the terminal or pick an input box"}
	var text: String
	if target == TERMINAL:
		text = str(_run({"cmd": "terminal_status"}).get("line", ""))
	else:
		text = ui.call("input_text", target)
	_set_text(text)
	_show()
	return {"ok": true, "took": text.length()}


# What the display line says: the cursor is |, the letters picked are
# between ‹ and ›. A long line shows the part round the cursor.
func _display() -> String:
	if _text.is_empty():
		return "> type here" + _flags()
	var line := _text.left(_caret) + "|" + _text.substr(_caret)
	if _anchor != -1:
		var from := mini(_caret, _anchor)
		var to := maxi(_caret, _anchor)
		line = _text.left(from) + "‹" + _text.substr(from, to - from) + "›" + _text.substr(to)
	var at := _caret + 1  # where the cursor is in `line`
	if line.length() > SHOWN:
		var start := clampi(at - SHOWN / 2, 0, line.length() - SHOWN)
		line = ("..." if start > 0 else "") + line.substr(start, SHOWN) + ("..." if start + SHOWN < line.length() else "")
	return "> " + line + _flags()


func _flags() -> String:
	return ("  [Shift]" if _shift else "") + ("  [Sel]" if _picking else "")


# Changes only the display line, without building the window again.
func _show() -> void:
	var ui := _ui()
	if ui != null and ui.has_method("set_text"):
		ui.call("set_text", PANEL, DISPLAY, _display())


func _status(_request: Dictionary) -> Dictionary:
	return {"ok": true, "typing_into": _target(_shown()), "layout": _layout, "text": _text, "shift": _shift, "collapsed": _collapsed,
		"caret": _caret, "picked": "" if _anchor == -1 else _text.substr(mini(_caret, _anchor), absi(_caret - _anchor))}


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


# The window's keys: the editing row, letters and figures, then Shift,
# Space, Del, Clr and Run (Send for words). Hide, beside the display line, folds the keys away;
# folded, the line has Keys (to unfold them) and Send beside it.
func _build(layout: String, exists: bool) -> void:
	var words := layout == "words"
	var keys: Array = WORD_KEYS if words else COMMAND_KEYS
	var width := COLS * UNIT - GAP
	var left := -width / 2.0
	var line_y := ROW_Y + KEY / 2.0 + 0.03 + (0.0 if _collapsed else UNIT)
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
	var edit_row := [
		["left", "<", 1.0], ["right", ">", 1.0], ["select", "Sel", 1.5], ["all", "All", 1.5],
		["cut", "Cut", 1.5], ["copy", "Copy", 1.5], ["paste", "Paste", 1.5], ["take", "Take", 1.5]]
	if not _collapsed:
		var edit_x := left
		for key in edit_row:
			var w: float = key[2] * UNIT - GAP
			elements.append({"type": "button", "id": "edit_" + key[0], "label": key[1],
				"at": [edit_x + w / 2.0, ROW_Y + UNIT], "size": [w, KEY], "action": {"cmd": "keyboard_key", "key": key[0]}})
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
