extends SlopitectModule

# Slopitect live module: textEdit.
# Text editing for the line you type on the keyboard (keyboard.gd): a cursor,
# picking letters, cut, copy and paste, and other changes. The keyboard
# shows its keys (two rows over the letters) and its display line while this
# is loaded; without it the keyboard just adds letters at the end.
# - < > move the cursor a letter, << >> a word, Home and End to the ends.
#   With Sel on they pick the letters they pass over; All picks the line.
# - Cut, Copy and Paste use the app's own clipboard (vrui's, never
#   Android's). With nothing picked on the line, Copy takes the rows picked
#   on the focused window's screen (pull the trigger on the terminal's screen
#   and move along), otherwise the whole line.
# - Del> takes the letter after the cursor (the keyboard's Del, the one
#   before), Aa switches what's picked (or the word before the cursor)
#   between capitals and small letters, Undo and Redo step through changes.
# - Typing or Paste replaces what's picked.

const HISTORY := 50  # changes Undo can step back through

var _text := ""
var _caret := 0  # letters before the cursor
var _anchor := -1  # the other end of the letters picked, or -1: none
var _picking := false  # Sel: the cursor keys pick as they go
var _undo := []  # [text, caret] before each change, oldest first
var _redo := []


func setup() -> String:
	register("text_key", _key_command, "edit the line being typed on the keyboard: key (left, right, word_left, word_right, home, end, select, all, cut, copy, paste, delete, backspace, case, undo, redo, clear)")
	register("text_status", _status, "the line being typed: text, caret, what's picked, and whether Sel is on")
	return ""


func _ui() -> SlopitectModule:
	var ui: SlopitectModule = ctx["modules"].module("vrui")
	return ui if ui != null and ui.has_method("clipboard") else null


# --- For the keyboard ------------------------------------------------------------------

func text() -> String:
	return _text


# Puts new text on the line (Take, or emptied after Send), cursor at the end.
func set_text(text: String) -> void:
	if text != _text:
		_remember()
	_text = text
	_caret = text.length()
	_anchor = -1
	_picking = false
	_changed()


# Typing: in place of what's picked, or at the cursor.
func insert(text: String) -> void:
	_remember()
	_put(text)
	_changed()


func backspace() -> void:
	if _anchor == -1 and _caret == 0:
		return
	_remember()
	if _anchor == -1:
		_anchor = _caret - 1
	_put("")
	_changed()


# The line with the cursor as | and what's picked between ‹ and ›; a line
# longer than `shown` shows the part round the cursor.
func display(shown: int) -> String:
	var line := _text.left(_caret) + "|" + _text.substr(_caret)
	if _anchor != -1:
		line = _text.left(_from()) + "‹" + _text.substr(_from(), _to() - _from()) + "›" + _text.substr(_to())
	if line.length() > shown:
		var start := clampi(_caret + 1 - shown / 2, 0, line.length() - shown)
		line = ("..." if start > 0 else "") + line.substr(start, shown) + ("..." if start + shown < line.length() else "")
	return line + ("  [Sel]" if _picking else "")


# --- The keys ----------------------------------------------------------------------------

func _key_command(request: Dictionary) -> Dictionary:
	var key = request.get("key")
	match key:
		"left", "right":
			_move(_caret + (-1 if key == "left" else 1))
		"word_left":
			_move(_word_start(_caret))
		"word_right":
			_move(_word_end(_caret))
		"home":
			_move(0)
		"end":
			_move(_text.length())
		"select":
			_picking = not _picking
			if not _picking and _anchor == _caret:
				_anchor = -1
		"all":
			_anchor = 0
			_caret = _text.length()
		"copy", "cut":
			return _copy(key == "cut")
		"paste":
			var ui := _ui()
			var text: String = ui.call("clipboard") if ui != null else ""
			if text.is_empty():
				return {"ok": false, "error": "nothing has been copied"}
			insert(text)
		"delete":
			if _anchor == -1 and _caret < _text.length():
				_remember()
				_anchor = _caret + 1
				_put("")
			elif _anchor != -1:
				_remember()
				_put("")
		"backspace":
			backspace()
		"case":
			_switch_case()
		"undo", "redo":
			var from: Array = _undo if key == "undo" else _redo
			if from.is_empty():
				return {"ok": false, "error": "nothing to %s" % key}
			(_redo if key == "undo" else _undo).append([_text, _caret])
			var back: Array = from.pop_back()
			_text = back[0]
			_caret = back[1]
			_anchor = -1
		"clear":
			set_text("")
		_:
			return {"ok": false, "error": "\"key\" must be left, right, word_left, word_right, home, end, select, all, cut, copy, paste, delete, backspace, case, undo, redo or clear"}
	_changed()
	return {"ok": true}


func _status(_request: Dictionary) -> Dictionary:
	return {"ok": true, "text": _text, "caret": _caret, "picked": _picked(), "selecting": _picking}


# The cursor to `to`. With Sel on it picks as it goes; without, a pick is
# let go (a letter step goes to its edge instead).
func _move(to: int) -> void:
	to = clampi(to, 0, _text.length())
	if _picking:
		if _anchor == -1:
			_anchor = _caret
		_caret = to
		return
	if _anchor != -1 and absi(to - _caret) == 1:
		to = _from() if to < _caret else _to()
	_anchor = -1
	_caret = to


func _word_start(at: int) -> int:
	while at > 0 and _text[at - 1] == " ":
		at -= 1
	while at > 0 and _text[at - 1] != " ":
		at -= 1
	return at


func _word_end(at: int) -> int:
	while at < _text.length() and _text[at] == " ":
		at += 1
	while at < _text.length() and _text[at] != " ":
		at += 1
	return at


# Copy (or Cut): the letters picked; with none, the rows picked on the
# focused window's screen (Copy only); otherwise the whole line.
func _copy(cut: bool) -> Dictionary:
	var ui := _ui()
	if ui == null:
		return {"ok": false, "error": "the clipboard needs vrui"}
	var text := _picked()
	if not text.is_empty():
		if cut:
			_remember()
			_put("")
	else:
		var window: String = ui.call("focused_window")
		if not cut and not window.is_empty():
			text = ui.call("selected_text", window)
		if text.is_empty():
			text = _text
			if cut:
				set_text("")
	if text.is_empty():
		return {"ok": false, "error": "nothing to copy: pick letters or rows, or type something"}
	ui.call("copy_text", text)
	_changed()
	return {"ok": true, "copied": text.length()}


# Capitals to small letters, or the other way, for what's picked or the
# word before the cursor.
func _switch_case() -> void:
	var from := _from() if _anchor != -1 else _word_start(_caret)
	var to := _to() if _anchor != -1 else _caret
	var part := _text.substr(from, to - from)
	if part.is_empty():
		return
	_remember()
	part = part.to_lower() if part == part.to_upper() else part.to_upper()
	_text = _text.left(from) + part + _text.substr(to)


func _put(text: String) -> void:
	var from := _caret if _anchor == -1 else _from()
	var to := _caret if _anchor == -1 else _to()
	_text = _text.left(from) + text + _text.substr(to)
	_caret = from + text.length()
	_anchor = -1


func _from() -> int:
	return mini(_caret, _anchor)


func _to() -> int:
	return maxi(_caret, _anchor)


func _picked() -> String:
	return "" if _anchor == -1 else _text.substr(_from(), _to() - _from())


func _remember() -> void:
	_undo.append([_text, _caret])
	if _undo.size() > HISTORY:
		_undo.pop_front()
	_redo.clear()


# The keyboard shows the line again.
func _changed() -> void:
	var keyboard: Node = ctx["modules"].module("keyboard")
	if keyboard != null and keyboard.has_method("text_changed"):
		keyboard.call("text_changed")
