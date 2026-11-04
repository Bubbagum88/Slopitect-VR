extends SlopitectModule

# Slopitect live module: scroll.
# The right thumbstick's up and down scroll the text windows that are shown
# (the terminal's screen and the chat log). Its left and right still turn.
# Button windows get tabs instead, so they're short enough not to scroll.

const LINES_PER_SECOND := 16.0  # full push
const DEAD := 0.2  # stick travel ignored around the middle
const CHECK_SECONDS := 0.5  # how often to look which windows are shown

var _owed := 0.0  # lines not yet sent
var _chat_at := 0  # the chat log's position: lines back from the newest
var _since_check := 0.0
var _terminal_on := false
var _chat_on := false


func setup() -> String:
	return ""


func _process(delta: float) -> void:
	var controls = ctx["modules"].module("controls")
	if controls == null:
		return
	_since_check += delta
	if _since_check >= CHECK_SECONDS:
		_since_check = 0.0
		_look()
	if not (_terminal_on or _chat_on):
		_owed = 0.0
		return
	var y: float = controls.stick("turn").y
	if absf(y) < DEAD:
		_owed = 0.0
		return
	var travel := (absf(y) - DEAD) / (1.0 - DEAD) * signf(y)
	_owed += travel * delta * LINES_PER_SECOND
	var lines := int(_owed)  # whole lines; the rest waits for the next frame
	if lines == 0:
		return
	_owed -= lines
	_scroll(lines)


# Which of the two windows are shown now.
func _look() -> void:
	_terminal_on = false
	_chat_on = false
	for panel in ctx["server"].run({"cmd": "ui_list"}).get("panels", []):
		if panel.get("id_panel") == "terminal":
			_terminal_on = panel.get("visible", false)
		elif panel.get("id_panel") == "chat":
			_chat_on = panel.get("visible", false)


# lines: positive is back (older), as the Up buttons do.
func _scroll(lines: int) -> void:
	if _terminal_on:
		ctx["server"].run({"cmd": "terminal_scroll", "by": lines})
	if _chat_on:
		_chat_at = maxi(0, _chat_at + lines)
		ctx["server"].run({"cmd": "ui_scroll", "id_panel": "chat", "id_element": "log", "lines": _chat_at})
