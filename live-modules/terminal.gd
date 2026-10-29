extends SlopitectModule

# Slopitect live module: terminal.
# A command line in the headset for the app's own commands, the same ones
# slopi.ps1 sends from the PC and the agent uses as tools. A on the right
# controller shows and hides it (or its tile on the Menu bar). Type a line
# on its keyboard and press Run; the reply is printed on its screen.
#
# A line is a command and its fields:
#   spawn shape=box scale=0.3 position=[0,1,-1]
#   agent_ask prompt="make the box red"
# A field's value is read as JSON when it can be (numbers, true/false,
# [lists], "quoted text"), and as plain text otherwise. A line that starts
# with { is sent as it is, as JSON.
#
# The tools beside the keyboard: Tab completes a command's name, Prev / Next
# step through the lines you ran, Help lists the commands (or, with a
# command typed, says what it takes), Up / Down scroll the screen, Cls
# clears it, and Ask sends what you typed to the agent with the last command
# and its reply, so it can help with what's on the screen; its answer is
# printed here when it's done.
#
# What the terminal won't run: settings (any *_config command, PC only) and
# terminal_run inside itself. A command run from here is yours, so one that
# needs your Yes (code_load, files outside the agent's folder) still asks in
# the headset; the agent using terminal_run is still held to its own
# allowed tools for everything the line runs.
#
# Needs ui.gd for its window; without it the terminal_* commands still work.

const PANEL := "terminal"
const COLS := 62  # characters per screen line at FONT on the screen's width
const ROWS := 13  # screen lines shown
const MAX_LINES := 400  # scrollback kept
const SCROLL_CHARS := 4000  # the most a text element holds (ui.gd's MAX_TEXT)
const MAX_LINE := 400  # characters in the line being typed
const MAX_HISTORY := 50
const FONT := 24
const LINE_FONT := 30
const LINE_COLS := 44  # characters of the typed line shown, at LINE_FONT
const KEY := 0.045
const GAP := 0.007
const ROWS_OF_KEYS := ["1234567890-", "qwertyuiop/", "asdfghjkl_=", "zxcvbnm,.[]"]
const CHECK_SECONDS := 1.0
const ASK_POLL_SECONDS := 0.5

var _line := ""
var _shift := false
var _screen: PackedStringArray = []  # printed lines, oldest first
var _scroll := 0  # lines up from the newest (the plain window; the new ui.gd keeps its own)
var _history: PackedStringArray = []  # lines run, oldest first
var _history_at := -1  # -1: not stepping through the history
var _last_run := ""  # the last line run and its reply, for Ask
var _last_reply := ""
var _asking := false
var _since_ask_poll := 0.0
var _ui_id := 0  # the ui module the window was built on (its instance id)
var _since_check := CHECK_SECONDS


func setup() -> String:
	register("terminal_run", _run_command, "run a line in the terminal as if typed there, and print it and its reply: line (like \"spawn shape=box\")")
	register("terminal_type", _type_command, "type into the terminal's line: text")
	register("terminal_key", _key_command, "a key for the terminal's line: key (shift, backspace, clear, tab, prev, next, run)")
	register("terminal_scroll", _scroll_command, "scroll the terminal's screen: by (lines, + is back), or end true")
	register("terminal_clear", _clear_command, "clear the terminal's screen")
	register("terminal_help", _help_command, "print the commands on the terminal, or one command's summary: optional name")
	register("terminal_ask", _ask_command, "send the terminal's line to the agent with the last command and its reply")
	register("terminal_status", _status, "the terminal's line, its last screen lines and its history")
	_print("Slopitect terminal. Type a command and press Run; Help lists them.")
	return ""


func _exit_tree() -> void:
	if _ui() != null:
		ctx["server"].run({"cmd": "ui_remove", "id_panel": PANEL})


# A tile on the Menu bar, when ui.gd has a launcher.
func menu_info() -> Dictionary:
	return {"id": "terminal", "label": "Terminal", "order": 50, "panel": PANEL}


func _process(delta: float) -> void:
	_since_check += delta
	if _since_check >= CHECK_SECONDS:
		_since_check = 0.0
		# ui.gd can be loaded after this module, or reloaded, and ui_reset
		# takes the window away; it's built again on whichever ui.gd is there.
		var ui := _ui()
		var id := ui.get_instance_id() if ui != null else 0
		if ui != null and (id != _ui_id or not _has_panel()):
			_build_panel()
		_ui_id = id
	if _asking:
		_since_ask_poll += delta
		if _since_ask_poll >= ASK_POLL_SECONDS:
			_since_ask_poll = 0.0
			_check_ask()


func _has_panel() -> bool:
	for panel in ctx["server"].run({"cmd": "ui_list"}).get("panels", []):
		if panel.get("id_panel") == PANEL:
			return true
	return false


func _ui() -> SlopitectModule:
	var ui: SlopitectModule = ctx["modules"].module("vrui")
	return ui if ui != null else ctx["modules"].module("ui")  # before the rename to vrui


# --- Running a line ------------------------------------------------------------------

# Turns a typed line into a request: {"cmd": ..., fields...}, or why it can't.
func parse(line: String) -> Dictionary:
	line = line.strip_edges()
	if line.is_empty():
		return {"error": "nothing to run"}
	if line.begins_with("{"):
		var json := JSON.new()
		if json.parse(line) != OK:
			return {"error": "not valid JSON: %s" % json.get_error_message()}
		if typeof(json.data) != TYPE_DICTIONARY or typeof(json.data.get("cmd")) != TYPE_STRING:
			return {"error": "JSON must be an object with \"cmd\", like {\"cmd\": \"list\"}"}
		return {"request": json.data}
	var words := _split(line)
	if words.has("error"):
		return words
	var parts: Array = words["words"]
	var request := {"cmd": parts[0]}
	for i in range(1, parts.size()):
		var word: String = parts[i]
		var eq := word.find("=")
		if eq <= 0:
			return {"error": "\"%s\" should be field=value (like shape=box)" % word}
		request[word.left(eq)] = _value(word.substr(eq + 1))
	return {"request": request}


# Splits on spaces, keeping "quoted text" and [lists] in one piece.
func _split(line: String) -> Dictionary:
	var words := []
	var word := ""
	var quoted := false
	var depth := 0
	var escaped := false
	for ch in line:
		if quoted:
			word += ch
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == "\"":
				quoted = false
			continue
		match ch:
			"\"":
				quoted = true
				word += ch
			"[", "{":
				depth += 1
				word += ch
			"]", "}":
				depth -= 1
				word += ch
			" ":
				if depth > 0:
					word += ch
				elif not word.is_empty():
					words.append(word)
					word = ""
			_:
				word += ch
	if quoted:
		return {"error": "a \" isn't closed"}
	if depth != 0:
		return {"error": "a [ isn't closed" if depth > 0 else "a ] has no ["}
	if not word.is_empty():
		words.append(word)
	return {"words": words}


func _value(text: String):
	var json := JSON.new()
	if json.parse(text) == OK:
		return json.data
	return text


# Runs a line as if typed: prints it, runs it, prints the reply.
func run_line(line: String) -> Dictionary:
	line = line.strip_edges().left(MAX_LINE)
	if line.is_empty():
		return {"ok": false, "error": "nothing to run"}
	if _history.is_empty() or _history[-1] != line:
		_history.append(line)
		if _history.size() > MAX_HISTORY:
			_history.remove_at(0)
	_history_at = -1
	_print("$ " + line)
	var parsed := parse(line)
	if parsed.has("error"):
		return _finish(line, {"ok": false, "error": parsed["error"]})
	var request: Dictionary = parsed["request"]
	var cmd: String = request["cmd"]
	if cmd.ends_with("_config"):
		return _finish(line, {"ok": false, "error": "settings (%s) can only be changed from the PC, not in the headset" % cmd})
	if cmd == "terminal_run":
		return _finish(line, {"ok": false, "error": "terminal_run can't run inside the terminal"})
	var reply: Dictionary = ctx["server"].run(request)
	if reply.get("wait") is SlopitectPending:
		_print("(waiting: for your answer in the headset, or for a long job)")
		_after_wait(line, reply["wait"])
		return reply
	return _finish(line, reply)


func _after_wait(line: String, pending: SlopitectPending) -> void:
	if not pending.finished:
		await pending.done
	_finish(line, pending.result)


func _finish(line: String, reply: Dictionary) -> Dictionary:
	_last_run = line
	_last_reply = _describe(reply)
	_print(_last_reply)
	return reply


# A reply as lines: "ok" or "error: ...", then each field.
func _describe(reply: Dictionary) -> String:
	if not reply.get("ok", false):
		return "error: %s" % reply.get("error", "?")
	var lines := PackedStringArray(["ok"])
	for key in reply:
		if key in ["ok", "id"]:
			continue
		var value = reply[key]
		if value is Dictionary and not value.is_empty():
			lines.append("%s:" % key)
			for inner in value:
				lines.append("  %s: %s" % [inner, _short(value[inner])])
		elif value is Array and not value.is_empty():
			lines.append("%s: (%d)" % [key, value.size()])
			for item in value:
				lines.append("  " + _short(item))
		else:
			lines.append("%s: %s" % [key, _short(value)])
	return "\n".join(lines)


func _short(value) -> String:
	var text: String = value if value is String else JSON.stringify(value)
	return text.replace("\n", " ")


# --- The screen ----------------------------------------------------------------------

func _print(text: String) -> void:
	_screen.append_array(text.split("\n"))
	if _screen.size() > MAX_LINES:
		_screen = _screen.slice(_screen.size() - MAX_LINES)
	_scroll = 0  # new output brings you back to the end
	_show_screen()


# The new ui.gd (the vrui look) has a scrolling text area that wraps and
# keeps to the newest lines by itself; with an older one, the terminal
# wraps and scrolls its screen itself.
func _scrolling_ui() -> bool:
	var ui := _ui()
	return ui != null and ui.has_method("scroll_text")


# The screen's lines wrapped to COLS, for the older ui.gd.
func _wrapped() -> PackedStringArray:
	var wrapped := PackedStringArray()
	for raw in _screen:
		var line: String = raw
		if line.is_empty():
			wrapped.append("")
		while not line.is_empty():
			# Break after the last space or comma that fits, so words stay whole.
			var cut := COLS
			if line.length() > COLS:
				var at := maxi(line.rfind(" ", COLS - 1), line.rfind(",", COLS - 1))
				if at > COLS / 2:
					cut = at + 1
			wrapped.append(line.left(cut))
			line = line.substr(cut)
	return wrapped


func _visible_lines() -> PackedStringArray:
	var wrapped := _wrapped()
	var end := wrapped.size() - _scroll
	return wrapped.slice(maxi(0, end - ROWS), end)


func _show_screen() -> void:
	if _scrolling_ui():
		# The newest lines that fit in a text element; ui.gd wraps them.
		var text := "\n".join(_screen).right(SCROLL_CHARS)
		var first := text.find("\n")
		if text.length() == SCROLL_CHARS and first != -1:
			text = text.substr(first + 1)  # no half line at the top
		_set_text("screen_text", text)
		return
	var text := "\n".join(_visible_lines())
	if _scroll > 0:
		text += "\n(%d more lines below: Down)" % _scroll
	_set_text("screen_text", text)


func _show_line() -> void:
	var shown := _line.right(LINE_COLS)  # the end of a long line, where you type
	_set_text("line", "$ " + shown + "|" + (" (SHIFT)" if _shift else ""))


func _set_text(id_element: String, text: String) -> void:
	var ui := _ui()
	if ui == null:
		return
	if ui.has_method("set_text"):
		ui.call("set_text", PANEL, id_element, text)
	else:
		# An older ui.gd: change the element (it redraws the window).
		ctx["server"].run({"cmd": "ui_element_update", "id_panel": PANEL, "id_element": id_element, "text": text})


# --- Typing and the tools --------------------------------------------------------------

func _type(text: String) -> void:
	if _shift:
		text = text.left(1).to_upper() + text.substr(1)
		_shift = false
	_line = (_line + text).left(MAX_LINE)
	_show_line()


func _key(key: String) -> Dictionary:
	match key:
		"shift":
			_shift = not _shift
		"backspace":
			_line = _line.left(-1)
		"clear":
			_line = ""
			_history_at = -1
		"tab":
			_complete()
		"prev":
			if _history.is_empty():
				return {"ok": false, "error": "nothing run yet"}
			_history_at = _history.size() - 1 if _history_at == -1 else maxi(0, _history_at - 1)
			_line = _history[_history_at]
		"next":
			if _history_at == -1:
				return {"ok": false, "error": "already at a new line"}
			_history_at += 1
			if _history_at >= _history.size():
				_history_at = -1
				_line = ""
			else:
				_line = _history[_history_at]
		"run":
			# The reply is on the screen (a command that waits is followed
			# there too), so the button itself has nothing more to show.
			var line := _line
			if line.strip_edges().is_empty():
				return {"ok": false, "error": "nothing to run"}
			_line = ""
			_show_line()
			run_line(line)
			return {"ok": true, "ran": line}
		_:
			return {"ok": false, "error": "\"key\" must be shift, backspace, clear, tab, prev, next or run"}
	_show_line()
	return {"ok": true}


# Completes the command's name: in full when only one fits, else as far as
# they all agree, printing the ones that fit.
func _complete() -> void:
	if _line.contains(" ") or _line.begins_with("{"):
		_help(_line.split(" ")[0])
		return
	var fits := PackedStringArray()
	for cmd in _runnable():
		if cmd.begins_with(_line):
			fits.append(cmd)
	if fits.is_empty():
		_print("(no command starts with \"%s\")" % _line)
		return
	if fits.size() == 1:
		_line = fits[0] + " "
		return
	var common: String = fits[0]
	for cmd in fits:
		while not cmd.begins_with(common):
			common = common.left(-1)
	_line = common
	_print("  ".join(fits))


func _runnable() -> PackedStringArray:
	var listed := PackedStringArray()
	for cmd in ctx["server"].commands():
		if not cmd.ends_with("_config") and cmd != "terminal_run":
			listed.append(cmd)
	listed.sort()
	return listed


func _help(cmd_name := "") -> Dictionary:
	var described: Dictionary = ctx["server"].describe_commands()
	if not cmd_name.is_empty():
		if described.has(cmd_name):
			_print("%s (%s): %s" % [cmd_name, described[cmd_name]["module"], described[cmd_name]["summary"]])
			return {"ok": true, "summary": described[cmd_name]["summary"], "module": described[cmd_name]["module"]}
		if cmd_name in ctx["server"].commands():
			_print("%s is built into the app" % cmd_name)
			return {"ok": true}
		_print("(no command \"%s\"; Help lists them)" % cmd_name)
		return {"ok": false, "error": "no command \"%s\"" % cmd_name}
	var by_module := {}
	for cmd in _runnable():
		var module: String = described[cmd]["module"] if described.has(cmd) else "app"
		if not by_module.has(module):
			by_module[module] = PackedStringArray()
		by_module[module].append(cmd)
	var modules := by_module.keys()
	modules.sort()
	for module in modules:
		_print("%s: %s" % [module, ", ".join(by_module[module])])
	_print("Type a command and press Help for what it takes.")
	return {"ok": true, "commands": by_module}


# --- Ask the agent -----------------------------------------------------------------------

func _ask() -> Dictionary:
	var question := _line.strip_edges()
	if question.is_empty() and _last_run.is_empty():
		return {"ok": false, "error": "type a question, or run a command first"}
	var prompt := "In the Slopitect terminal (the headset's command line) I"
	if not _last_run.is_empty():
		prompt += " ran: %s\nThe reply was:\n%s\n" % [_last_run, _last_reply.left(1500)]
	if question.is_empty():
		question = "What does that mean, and what should I run next?"
	prompt += "\n" + question
	var reply: Dictionary = ctx["server"].run({"cmd": "agent_ask", "prompt": prompt})
	if not reply.get("ok", false):
		_print("error: %s" % reply.get("error", "?"))
		return reply
	_print("? " + question)
	_print("(asked the agent; its answer is printed here when it's done)")
	_line = ""
	_show_line()
	_asking = true
	_since_ask_poll = 0.0
	return reply


func _check_ask() -> void:
	var status: Dictionary = ctx["server"].run({"cmd": "agent_status"})
	if not status.get("ok", false):
		_asking = false
		_print("error: %s" % status.get("error", "?"))
		return
	if status.get("busy", false):
		return
	_asking = false
	var error := String(status.get("last_error", ""))
	if not error.is_empty():
		_print("agent error: " + error)
	else:
		_print("agent: " + String(status.get("last_reply", "")))


# --- Commands, registered with the command server -------------------------------------

func _run_command(request: Dictionary) -> Dictionary:
	var line = request.get("line")
	if typeof(line) != TYPE_STRING or line.strip_edges().is_empty():
		return {"ok": false, "error": "terminal_run needs \"line\", like \"spawn shape=box\""}
	return run_line(line)


func _type_command(request: Dictionary) -> Dictionary:
	var text = request.get("text")
	if typeof(text) != TYPE_STRING or text.is_empty():
		return {"ok": false, "error": "terminal_type needs \"text\""}
	_type(text)
	return {"ok": true}


func _key_command(request: Dictionary) -> Dictionary:
	return _key(str(request.get("key")))


func _scroll_command(request: Dictionary) -> Dictionary:
	var by = request.get("by")
	var to_end: bool = request.get("end", false) == true
	if not to_end and typeof(by) not in [TYPE_INT, TYPE_FLOAT]:
		return {"ok": false, "error": "terminal_scroll needs \"by\" (lines, + is back) or \"end\": true"}
	if _scrolling_ui():
		var offset: int = _ui().call("scroll_text", PANEL, "screen_text", 0 if to_end else int(by))
		return {"ok": true, "scroll": offset}
	if to_end:
		_scroll = 0
	else:
		_scroll = clampi(_scroll + int(by), 0, maxi(0, _wrapped().size() - ROWS))
	_show_screen()
	return {"ok": true, "scroll": _scroll}


func _clear_command(_request: Dictionary) -> Dictionary:
	_screen.clear()
	_scroll = 0
	_show_screen()
	return {"ok": true}


func _help_command(request: Dictionary) -> Dictionary:
	var cmd_name = request.get("name", _line.strip_edges().split(" ")[0])
	return _help(str(cmd_name))


func _ask_command(_request: Dictionary) -> Dictionary:
	return _ask()


func _status(_request: Dictionary) -> Dictionary:
	return {"ok": true, "line": _line, "screen": _visible_lines(), "scroll": _scroll,
		"history": _history, "asking": _asking, "window": _ui() != null}


# --- The window ----------------------------------------------------------------------

# The screen on top, the line being typed, the keyboard, and the tools in a
# column on the right. The window's place is kept by ui.gd; this only adds it
# the first time and replaces its elements after.
func _build_panel() -> void:
	var unit := KEY + GAP
	var width: float = ROWS_OF_KEYS[0].length() * unit - GAP
	var left := -width / 2.0
	var screen_height := ROWS * FONT * 0.0006 * 1.25 + 0.02
	var line_y := 0.09
	var screen_y := line_y + 0.035 + screen_height / 2.0
	var elements := [
		{"type": "box", "id": "screen", "at": [0, screen_y], "size": [width + 0.02, screen_height], "color": "#08100a"},
		{"type": "text", "id": "screen_text", "at": [0, screen_y + screen_height / 2.0 - 0.01], "width": width,
			"font_size": FONT, "color": "#8cff99", "mono": true, "text": ""},
		{"type": "text", "id": "line", "at": [0, line_y + 0.012], "width": width, "font_size": LINE_FONT, "color": "#b3e6ff", "mono": true, "text": "$ |"},
	]
	if _scrolling_ui():
		# The new ui.gd's text area: it wraps, clips at its box and keeps
		# to the newest lines, and Up / Down scroll it.
		elements[1]["height"] = screen_height - 0.02
		elements[1]["scroll"] = true
	for r in ROWS_OF_KEYS.size():
		var row: String = ROWS_OF_KEYS[r]
		for c in row.length():
			var ch := row[c]
			elements.append({"type": "button", "id": "key_%d_%d" % [r, c], "label": ch,
				"at": [left + KEY / 2.0 + c * unit, line_y - 0.05 - r * unit], "size": [KEY, KEY],
				"action": {"cmd": "terminal_type", "text": ch}})
	var bottom := line_y - 0.05 - ROWS_OF_KEYS.size() * unit
	var x := left
	for key in [["shift", "Shift", 2, {"cmd": "terminal_key", "key": "shift"}],
			["quote", "\"", 1, {"cmd": "terminal_type", "text": "\""}],
			["space", "Space", 4, {"cmd": "terminal_type", "text": " "}],
			["del", "Del", 1, {"cmd": "terminal_key", "key": "backspace"}],
			["clear", "Clr", 1, {"cmd": "terminal_key", "key": "clear"}],
			["run", "Run", 2, {"cmd": "terminal_key", "key": "run"}]]:
		var w: float = key[2] * unit - GAP
		var button := {"type": "button", "id": key[0], "label": key[1], "at": [x + w / 2.0, bottom], "size": [w, KEY], "action": key[3]}
		if key[0] == "run":
			button["color"] = "#2a6f3a"
		elements.append(button)
		x += key[2] * unit
	var tools := [
		["tab", "Tab", {"cmd": "terminal_key", "key": "tab"}],
		["prev", "Prev", {"cmd": "terminal_key", "key": "prev"}],
		["next", "Next", {"cmd": "terminal_key", "key": "next"}],
		["help", "Help", {"cmd": "terminal_help"}],
		["up", "Up", {"cmd": "terminal_scroll", "by": ROWS - 1}],
		["down", "Down", {"cmd": "terminal_scroll", "by": -(ROWS - 1)}],
		["cls", "Cls", {"cmd": "terminal_clear"}],
		["ask", "Ask AI", {"cmd": "terminal_ask"}],
	]
	var tool_x := width / 2.0 + 0.02 + 0.055
	var top := screen_y + screen_height / 2.0 - KEY / 2.0
	for i in tools.size():
		elements.append({"type": "button", "id": "tool_" + tools[i][0], "label": tools[i][1],
			"at": [tool_x, top - i * unit], "size": [0.11, KEY], "action": tools[i][2]})
	var panel := {"cmd": "ui_add", "id_panel": PANEL, "title": "Terminal", "place": "front", "distance": 0.6, "height": -0.3,
		"toggle": "right_a", "elements": elements}
	if _has_panel():
		# Only the elements: where you put the window, and its toggle, stay.
		panel = {"cmd": "ui_update", "id_panel": PANEL, "elements": elements}
	var reply: Dictionary = ctx["server"].run(panel)
	if not reply.get("ok", false):
		push_error("Slopitect terminal: the window could not be built: %s" % reply.get("error"))
		return
	_show_screen()
	_show_line()
