extends SlopitectModule

# Slopitect live module: chat.
# The agent's chat window, made like the terminal's: a green screen that
# keeps the whole conversation (scroll back with Up / Down, End for the
# newest), what the agent is doing under it, the line you type, a keyboard
# with Send, and the tools in a column on the right: STOP, New chat (a new
# conversation), Cls (clear the screen) and the scroll buttons.
#
# It doesn't add a second chat window: it fills ui.gd's "chat" panel (Y on
# the left controller, or the Chat tile), keeping its element ids (log,
# state, line, send, stop, key_R_C), so where you put the window and its
# button stay. The elements it replaced are kept in user://chat_window.json
# and put back when this module is unloaded.
#
# Each message is laid out by aimsg.gd when it's loaded ("you>", "ai>",
# markdown taken out, tool calls on one line); otherwise it shows as the
# agent wrote it. The screen collects every event as it comes, so it keeps
# more than the agent's last 40.
#
# Needs ui.gd for its window; without it chat_status still works.

const PANEL := "chat"
const MARK := "chat_tools"  # an element only this window has
const ORIGINAL_PATH := "user://chat_window.json"
const ROWS := 13  # screen lines shown
const FONT := 24
const MAX_LINES := 600  # scrollback kept
const SCROLL_CHARS := 4000  # the most a text element holds (ui.gd's MAX_TEXT)
const KEY := 0.045
const GAP := 0.007
const ROWS_OF_KEYS := ["1234567890-", "qwertyuiop'", "asdfghjkl?!", "zxcvbnm,./:"]
const POLL_SECONDS := 0.5

var _screen: PackedStringArray = []  # laid-out lines, oldest first
var _seen: Array = []  # agent_status's events at the last look
var _ui_id := 0
var _since_poll := POLL_SECONDS
var _lib: SlopitectModule

# The conversation on the screen changed (transcript() has it); the terminal's
# Chat mode follows this instead of asking twice a second.
signal transcript_changed


func setup() -> String:
	register("chat_status", _status, "the chat window: how many lines its screen keeps, and the newest ones")
	register("chat_clear", _clear_command, "clear the chat window's screen (the conversation itself goes on)")
	return ""


# Unloaded, the chat panel gets back what it had before this module filled it.
func _exit_tree() -> void:
	if ctx["modules"].module(name) != null:
		return  # the app is closing, not unloading this: the window stays as it is
	if _ui() == null or not FileAccess.file_exists(ORIGINAL_PATH):
		return
	var saved = JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL_PATH))
	if typeof(saved) != TYPE_DICTIONARY or typeof(saved.get("elements")) != TYPE_ARRAY:
		push_error("Slopitect chat: %s isn't readable; the chat window keeps this module's layout" % ORIGINAL_PATH)
		return
	var update := {"cmd": "ui_update", "id_panel": PANEL, "elements": saved["elements"]}
	if typeof(saved.get("size")) == TYPE_ARRAY:
		update["size"] = saved["size"]
	var reply: Dictionary = ctx["server"].run(update)
	if not reply.get("ok", false):
		push_error("Slopitect chat: couldn't put the chat window back: %s" % reply.get("error"))


# vrui can load after this, or be reloaded, and the panel can be put back to
# its default: the window is filled again then (not checked every second).
func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		return
	lib.watch(self, "vrui", _ui_here)
	lib.follow(self, "vrui", "panel_changed", _on_changed)


func _ui_here(_ui_module: SlopitectModule) -> void:
	_fill_soon()


func _on_changed(id_panel: String) -> void:
	if id_panel == PANEL:
		_fill_soon()


func _fill_soon() -> void:
	_fill.call_deferred()


func _fill() -> void:
	if not is_inside_tree():
		return
	var ui := _ui()
	var id := ui.get_instance_id() if ui != null else 0
	if ui != null and (id != _ui_id or not _is_ours()):
		_build_panel()
	_ui_id = id


# The agent has no signals yet (that's an APK change), so its events are
# read twice a second; nothing else runs per frame.
func _process(delta: float) -> void:
	_since_poll += delta
	if _since_poll >= POLL_SECONDS:
		_since_poll = 0.0
		_poll()


# The window module, by either name (it may be renamed vrui).
func _ui() -> SlopitectModule:
	var ui: SlopitectModule = ctx["modules"].module("vrui")
	return ui if ui != null else ctx["modules"].module("ui")


func _panel() -> Dictionary:
	var got: Dictionary = ctx["server"].run({"cmd": "ui_get", "id_panel": PANEL})
	return got.get("panel", {}) if got.get("ok", false) else {}


func _is_ours() -> bool:
	for element in _panel().get("elements", []):
		if element.get("id") == MARK:
			return true
	return false


# --- The conversation ----------------------------------------------------------------

# New events since the last look. The agent keeps its last 40, dropping the
# oldest, so the new ones are what comes after the longest end of the last
# look that the list now starts with.
func _poll() -> void:
	var status: Dictionary = ctx["server"].run({"cmd": "agent_status"})
	if not status.get("ok", false) or typeof(status.get("events")) != TYPE_ARRAY:
		return
	var events: Array = status["events"]
	if events == _seen:
		return
	var kept := mini(_seen.size(), events.size())
	while kept > 0 and _seen.slice(_seen.size() - kept) != events.slice(0, kept):
		kept -= 1
	var fresh := events.slice(kept)
	_seen = events.duplicate()
	if fresh.is_empty():
		return
	for event in fresh:
		_screen.append_array(_lines(str(event)))
	if _screen.size() > MAX_LINES:
		_screen = _screen.slice(_screen.size() - MAX_LINES)
	_show_screen()


func _lines(event: String) -> PackedStringArray:
	var aimsg: SlopitectModule = ctx["modules"].module("aimsg")
	if aimsg != null and aimsg.has_method("event_lines"):
		return PackedStringArray(aimsg.call("event_lines", event))
	return PackedStringArray([event])


func _show_screen() -> void:
	transcript_changed.emit()
	var ui := _ui()
	if ui == null or not ui.has_method("set_text"):
		return
	var text := "\n".join(_screen).right(SCROLL_CHARS)
	var first := text.find("\n")
	if text.length() == SCROLL_CHARS and first != -1:
		text = text.substr(first + 1)  # no half line at the top
	if text.is_empty():
		text = "agent ready. type below and press Send."
	ui.call("set_text", PANEL, "log", text)


# The conversation as this window shows it, laid out, oldest line first
# (the terminal's chat mode shows the same).
func transcript() -> PackedStringArray:
	return _screen


func _status(_request: Dictionary) -> Dictionary:
	return {"ok": true, "lines": _screen.size(), "newest": _screen.slice(maxi(0, _screen.size() - ROWS)), "window": _is_ours()}


func _clear_command(_request: Dictionary) -> Dictionary:
	_screen.clear()
	_show_screen()
	return {"ok": true}


# --- The window ----------------------------------------------------------------------

# ui_get adds what's typed in each input box ("value"); that isn't a field
# ui_update takes, and isn't kept.
func _without_typing(elements: Array) -> Array:
	var out := elements.duplicate(true)
	for element in out:
		if element is Dictionary:
			element.erase("value")
			if element.get("children") is Array:
				element["children"] = _without_typing(element["children"])
	return out


func _build_panel() -> void:
	var existing := _panel()
	if existing.is_empty():
		return  # no chat panel to fill (ui_list shows the panels)
	if not _is_ours():
		# Keep what was there, to put back when this module goes.
		var out := FileAccess.open(ORIGINAL_PATH, FileAccess.WRITE)
		if out == null:
			push_error("Slopitect chat: couldn't keep the chat window's layout in %s (error %d); not changing it" % [ORIGINAL_PATH, FileAccess.get_open_error()])
			return
		var original := {"elements": _without_typing(existing.get("elements", []))}
		if existing.has("size"):
			original["size"] = existing["size"]
		out.store_string(JSON.stringify(original, "  "))
		out.close()

	var unit := KEY + GAP
	var width: float = ROWS_OF_KEYS[0].length() * unit - GAP
	var left := -width / 2.0
	var screen_height := ROWS * FONT * 0.0006 * 1.25 + 0.02
	var line_y := 0.09
	var state_y := line_y + 0.045
	var screen_y := state_y + 0.01 + screen_height / 2.0
	var elements := [
		{"type": "box", "id": "screen", "at": [0, screen_y], "size": [width + 0.02, screen_height], "color": "#08100a"},
		{"type": "text", "id": "log", "at": [0, screen_y + screen_height / 2.0 - 0.01], "width": width, "height": screen_height - 0.02,
			"scroll": true, "font_size": FONT, "color": "#8cff99", "mono": true, "text": ""},
		{"type": "text", "id": "state", "at": [0, state_y], "width": width, "font_size": 22, "color": "#5f9f6a", "mono": true,
			"source": {"cmd": "agent_status", "field": "status_line"}},
		{"type": "input", "id": "line", "at": [0, line_y], "width": width, "font_size": 30, "color": "#b3e6ff", "prompt": "> "},
	]
	for r in ROWS_OF_KEYS.size():
		var row: String = ROWS_OF_KEYS[r]
		for c in row.length():
			var ch := row[c]
			elements.append({"type": "button", "id": "key_%d_%d" % [r, c], "label": ch,
				"at": [left + KEY / 2.0 + c * unit, line_y - 0.055 - r * unit], "size": [KEY, KEY],
				"action": {"cmd": "ui_type", "text": ch}})
	var bottom := line_y - 0.055 - ROWS_OF_KEYS.size() * unit
	var x := left
	for key in [["shift", "Shift", 2, {"cmd": "ui_key", "key": "shift"}],
			["space", "Space", 4, {"cmd": "ui_type", "text": " "}],
			["del", "Del", 2, {"cmd": "ui_key", "key": "backspace"}],
			["clear", "Clr", 1, {"cmd": "ui_key", "key": "clear"}],
			["send", "Send", 2, {"cmd": "agent_ask", "prompt": "{input:line}"}]]:
		var w: float = key[2] * unit - GAP
		var button := {"type": "button", "id": key[0], "label": key[1], "at": [x + w / 2.0, bottom], "size": [w, KEY], "action": key[3]}
		if key[0] == "send":
			button["color"] = "#2a6f3a"
			button["clear_input"] = "line"
		elements.append(button)
		x += key[2] * unit
	# The tools, in a column on the right like the terminal's.
	var tools := [
		["stop", "STOP", {"cmd": "agent_stop"}, "danger"],
		["new_chat", "New chat", {"cmd": "agent_reset"}, "button"],
		["up", "Up", {"cmd": "ui_scroll", "id_panel": PANEL, "id_element": "log", "lines": ROWS - 1}, "button"],
		["down", "Down", {"cmd": "ui_scroll", "id_panel": PANEL, "id_element": "log", "lines": -(ROWS - 1)}, "button"],
		["end", "End", {"cmd": "ui_scroll", "id_panel": PANEL, "id_element": "log", "lines": 0}, "button"],
		["cls", "Cls", {"cmd": "chat_clear"}, "button"],
	]
	var tool_x := width / 2.0 + 0.02 + 0.065
	var top := screen_y + screen_height / 2.0 - KEY / 2.0
	for i in tools.size():
		elements.append({"type": "button", "id": "tool_" + tools[i][0] if tools[i][0] != "stop" else "stop", "label": tools[i][1],
			"at": [tool_x, top - i * unit], "size": [0.13, KEY], "action": tools[i][2], "color": tools[i][3]})
	elements.append({"type": "box", "id": MARK, "at": [tool_x, bottom], "size": [0.005, 0.005], "color": "panel"})
	# The window grows to fit what's in it, so its own background is tiny.
	var size := [0.02, 0.02]
	var reply: Dictionary = ctx["server"].run({"cmd": "ui_update", "id_panel": PANEL, "elements": elements, "size": size})
	if not reply.get("ok", false):
		push_error("Slopitect chat: the window could not be built: %s" % reply.get("error"))
		return
	_show_screen()
