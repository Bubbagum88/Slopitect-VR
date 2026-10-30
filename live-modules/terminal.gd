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
# Commands that take text (agent_ask, tts_say, memory_note...) also take it
# as the rest of the line: agent_ask make the box red.
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
# Chat (top of the tools) turns the same window into the agent's chat: the
# screen shows the conversation, Run sends what you typed to the agent as
# it is, the keyboard has ' ? ! instead of the command symbols, and the
# tools are STOP, New chat, the scroll buttons and Cls. Terminal turns it
# back. The conversation is chat.gd's when it's loaded (with aimsg.gd's
# layout); without it, the agent's recent events as they are.
#
# What the terminal won't run: settings (any *_config command, PC only) and
# terminal_run inside itself. A command run from here is yours, so one that
# needs your Yes (code_load, files outside the agent's folder) still asks in
# the headset; the agent using terminal_run is still held to its own
# allowed tools for everything the line runs.
#
# Needs vrui.gd or ui.gd for its window; without either the terminal_*
# commands still work.

const PANEL := "terminal"
const CHAT_PANEL := "chat"  # the agent's own window (chat.gd fills it); Chat mode stands in for it
const COLS := 62  # characters per screen line at FONT on the screen's width
const ROWS := 13  # screen lines shown
const MAX_LINES := 400  # scrollback kept
# Commands whose main field is free text: "agent_ask can you..." needs no
# prompt= or quotes.
const TEXT_FIELDS := {"agent_ask": "prompt", "tts_say": "text", "avatar_say": "text", "ui_type": "text",
	"terminal_type": "text", "memory_note": "text", "memory_search": "query", "assets_search": "query"}
const SCROLL_CHARS := 4000  # the most a text element holds (ui.gd's MAX_TEXT)
const MAX_LINE := 400  # characters in the line being typed
const MAX_HISTORY := 50
const FONT := 24
const LINE_FONT := 30
const LINE_COLS := 44  # characters of the typed line shown, at LINE_FONT
const KEY := 0.045
const GAP := 0.007
const ROWS_OF_KEYS := ["1234567890-", "qwertyuiop/", "asdfghjkl_=", "zxcvbnm,.[]"]
const CHAT_KEYS := ["1234567890-", "qwertyuiop'", "asdfghjkl?!", "zxcvbnm,./:"]
const CHAT_POLL_SECONDS := 0.5
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
var _keyboard_id := 0  # the keyboard module there was when it was built (0: none, so it has its own keys)
var _lib: SlopitectModule
var _soon := false  # a window check is due at the end of this frame
var _visible := false  # the window is showing (vrui's panel_shown)
var _mode := "terminal"  # or "chat"
var _other_line := ""  # what's typed in the other mode, kept for when you switch back
var _chat_text := ""  # the conversation as last shown
var _since_chat_poll := CHAT_POLL_SECONDS


# The window switched between the command line and the chat (the keyboard
# follows it for its layout).
signal mode_changed(mode: String)


func setup() -> String:
	register("terminal_run", _run_command, "run a line in the terminal as if typed there, and print it and its reply: line (like \"spawn shape=box\")")
	register("terminal_type", _type_command, "type into the terminal's line: text")
	register("terminal_key", _key_command, "a key for the terminal's line: key (shift, backspace, clear, tab, prev, next, run)")
	register("terminal_scroll", _scroll_command, "scroll the terminal's screen: by (lines, + is back), or end true")
	register("terminal_clear", _clear_command, "clear the terminal's screen")
	register("terminal_help", _help_command, "print the commands on the terminal, or one command's summary: optional name")
	register("terminal_ask", _ask_command, "send the terminal's line to the agent with the last command and its reply")
	register("terminal_status", _status, "the terminal's mode (terminal or chat), line, last screen lines and history")
	register("terminal_mode", _mode_command, "switch the terminal's window between the command line and the agent's chat: mode (terminal or chat)")
	_print("Slopitect terminal. Type a command and press Run; Help lists them.")
	set_process(false)
	return ""


# No checks every frame: the window is looked at again when the window
# module or the keyboard comes or goes, when it's taken away, or when the
# agent's own chat window opens.
func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		return
	lib.follow(self, "vrui", "panel_shown", _on_shown)
	lib.follow(self, "vrui", "panel_changed", _on_changed)
	lib.follow(self, "lib", "module_loaded", _on_module)
	lib.follow(self, "lib", "module_unloaded", _on_module)
	lib.follow(self, "chat", "transcript_changed", _on_transcript)
	_check_soon()


func _on_transcript() -> void:
	if _mode == "chat" and _visible:
		_show_chat()


func _on_shown(id_panel: String, on: bool) -> void:
	if id_panel == PANEL:
		_visible = on
		_since_chat_poll = CHAT_POLL_SECONDS  # shown: the chat straight away
		_update_process()
	elif id_panel == CHAT_PANEL and on:
		_check_soon()


func _on_changed(id_panel: String) -> void:
	if id_panel == PANEL:
		_check_soon()


func _on_module(module_name: String) -> void:
	if module_name in ["vrui", "ui", "keyboard"]:
		_check_soon()
	if module_name == "chat":
		_update_process.call_deferred()  # once it's in or out


func _check_soon() -> void:
	if _soon:
		return
	_soon = true
	_check_deferred.call_deferred()


func _check_deferred() -> void:
	_soon = false
	if is_inside_tree():
		_check_window()


# Runs only while an Ask waits for its answer, or the chat shows here and
# chat.gd isn't loaded to tell it of changes (the agent itself has no
# signals yet: an APK change).
func _update_process() -> void:
	var told: bool = _lib != null and _lib.module("chat") != null
	set_process((_mode == "chat" and _visible and not told) or _asking)
	if _mode == "chat" and _visible and told:
		_show_chat()


func _exit_tree() -> void:
	if _ui() != null:
		ctx["server"].run({"cmd": "ui_remove", "id_panel": PANEL})


# A tile on the Menu bar, when ui.gd has a launcher; "tools" also lists it
# in the Tools menu.
func menu_info() -> Dictionary:
	return {"id": "terminal", "label": "Terminal", "order": 50, "panel": PANEL, "tools": true}


# A button on the hand menu (pause.gd).
func hand_info() -> Dictionary:
	return {"id": "terminal", "label": "Terminal", "order": 20, "panel": PANEL}


func _process(delta: float) -> void:
	if _mode == "chat":
		_since_chat_poll += delta
		if _since_chat_poll >= CHAT_POLL_SECONDS:
			_since_chat_poll = 0.0
			_show_chat()
	if _asking:
		_since_ask_poll += delta
		if _since_ask_poll >= ASK_POLL_SECONDS:
			_since_ask_poll = 0.0
			_check_ask()


# ui.gd can be loaded after this module, or reloaded, and ui_reset takes
# the window away; it's built again on whichever ui.gd is there.
# The agent's own window shows the same conversation as Chat mode, so there
# is one chat window: whatever opens the agent's (its button, its Menu tile)
# opens this one in Chat mode instead, or closes it if it's showing the chat.
func _check_window() -> void:
	var ui := _ui()
	var id := ui.get_instance_id() if ui != null else 0
	if ui == null:
		_ui_id = id
		return
	var panels := {}
	for panel in ctx["server"].run({"cmd": "ui_list"}).get("panels", []):
		panels[panel.get("id_panel")] = panel
	var keyboard: Node = _lib.module("keyboard") if _lib else null
	var keyboard_id := keyboard.get_instance_id() if keyboard != null else 0
	if id != _ui_id or keyboard_id != _keyboard_id or not panels.has(PANEL):
		_build_panel()
	_ui_id = id
	_keyboard_id = keyboard_id
	if not panels.get(CHAT_PANEL, {}).get("visible", false):
		return
	ctx["server"].run({"cmd": "ui_show", "id_panel": CHAT_PANEL, "visible": false})
	var showing_chat: bool = panels.get(PANEL, {}).get("visible", false) and _mode == "chat"
	_set_mode("chat")
	ctx["server"].run({"cmd": "ui_show", "id_panel": PANEL, "visible": not showing_chat})


# Words heard by voice (vtt.gd): they go on the chat line, for you to check
# and Send, and the window shows the chat.
func hear(words: String) -> void:
	_set_mode("chat")
	_type(words)
	for panel in ctx["server"].run({"cmd": "ui_list"}).get("panels", []):
		# Shown only when hidden: showing it again would move it in front of you.
		if panel.get("id_panel") == PANEL and not panel.get("visible", false):
			ctx["server"].run({"cmd": "ui_show", "id_panel": PANEL, "visible": true})


func _has_panel() -> bool:
	for panel in ctx["server"].run({"cmd": "ui_list"}).get("panels", []):
		if panel.get("id_panel") == PANEL:
			return true
	return false


# The window module: vrui.gd if it's loaded and is the panel module (the old
# vrui draft has no set_text and no ui_* commands), else ui.gd.
func _ui() -> SlopitectModule:
	var vrui: SlopitectModule = ctx["modules"].module("vrui")
	if vrui != null and vrui.has_method("set_text"):
		return vrui
	return ctx["modules"].module("ui")


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
	# A command that takes text gets the rest of the line as it is, quotes,
	# apostrophes and all: agent_ask can you reach the internet?
	var space := line.find(" ")
	var cmd := line if space == -1 else line.left(space)
	var rest := "" if space == -1 else line.substr(space + 1).strip_edges()
	var close := _close_command(cmd) if not cmd in ctx["server"].commands() else ""
	if not close.is_empty():
		return {"error": "no command \"%s\"; did you mean %s?" % [cmd, close]}
	if TEXT_FIELDS.has(cmd) and not rest.is_empty() and not _is_field(rest):
		if rest.length() >= 2 and rest.begins_with("\"") and rest.ends_with("\""):
			rest = rest.substr(1, rest.length() - 2)
		return {"request": {"cmd": cmd, TEXT_FIELDS[cmd]: rest}}
	var words := _split(line)
	if words.has("error"):
		return words
	var parts: Array = words["words"]
	var request := {"cmd": parts[0]}
	for i in range(1, parts.size()):
		var word: String = parts[i]
		var eq := word.find("=")
		if eq <= 0:
			return {"error": "\"%s\" should be field=value (like shape=box)" % word.left(40)}
		request[word.left(eq)] = _value(word.substr(eq + 1))
	return {"request": request}


# Whether text starts like field=value (a name, then =).
func _is_field(text: String) -> bool:
	var eq := text.find("=")
	if eq <= 0:
		return false
	var name := text.left(eq)
	return not name.contains(" ") and not name.contains("\"") and name.is_valid_identifier()


# A command with the same words in another order (ask_agent for agent_ask).
func _close_command(cmd: String) -> String:
	var words := Array(cmd.split("_"))
	words.sort()
	for known in ctx["server"].commands():
		var known_words := Array(known.split("_"))
		known_words.sort()
		if known_words == words:
			return known
	return ""


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


# Lines wrapped to COLS, for the older ui.gd.
func _wrapped(lines: PackedStringArray = _screen) -> PackedStringArray:
	var wrapped := PackedStringArray()
	for raw in lines:
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


func _visible_lines(lines: PackedStringArray = _screen) -> PackedStringArray:
	var wrapped := _wrapped(lines)
	var end := wrapped.size() - _scroll
	return wrapped.slice(maxi(0, end - ROWS), end)


func _show_screen() -> void:
	if _mode == "chat":
		_chat_text = ""
		_show_chat()
		return
	_show_lines(_screen)


func _show_lines(lines: PackedStringArray) -> void:
	if _scrolling_ui():
		# The newest lines that fit in a text element; ui.gd wraps them.
		var text := "\n".join(lines).right(SCROLL_CHARS)
		var first := text.find("\n")
		if text.length() == SCROLL_CHARS and first != -1:
			text = text.substr(first + 1)  # no half line at the top
		_set_text("screen_text", text)
		return
	var text := "\n".join(_visible_lines(lines))
	if _scroll > 0:
		text += "\n(%d more lines below: Down)" % _scroll
	_set_text("screen_text", text)


# --- Chat ----------------------------------------------------------------------------

# The conversation: chat.gd's screen when it's loaded, else the agent's
# recent events (laid out by aimsg.gd when that's loaded).
func _chat_lines() -> PackedStringArray:
	var chat: SlopitectModule = _lib.module("chat") if _lib else ctx["modules"].module("chat")
	if chat != null and chat.has_method("transcript"):
		return PackedStringArray(chat.call("transcript"))
	var lines := PackedStringArray()
	var status: Dictionary = ctx["server"].run({"cmd": "agent_status"})
	if not status.get("ok", false):
		lines.append("(the agent isn't available: %s)" % status.get("error", "?"))
		return lines
	var aimsg: SlopitectModule = ctx["modules"].module("aimsg")
	for event in status.get("events", []):
		if aimsg != null and aimsg.has_method("event_lines"):
			lines.append_array(PackedStringArray(aimsg.call("event_lines", str(event))))
		else:
			lines.append(str(event))
	return lines


# Shows the conversation, only when it changed (it's checked twice a second).
func _show_chat() -> void:
	var lines := _chat_lines()
	if lines.is_empty():
		lines.append("agent ready. type below and press Send.")
	var text := "\n".join(lines)
	if text == _chat_text:
		return
	_chat_text = text
	_show_lines(lines)


func _set_mode(mode: String) -> void:
	if mode == _mode:
		return
	var typed := _line
	_line = _other_line
	_other_line = typed
	_mode = mode
	_shift = false
	_history_at = -1
	_scroll = 0
	_build_panel()
	_update_process()
	mode_changed.emit(mode)


func _send_chat(text: String) -> Dictionary:
	var reply: Dictionary = ctx["server"].run({"cmd": "agent_ask", "prompt": text})
	if not reply.get("ok", false):
		_line = text  # kept, to send again once the agent is free
		_show_line()
	_since_chat_poll = CHAT_POLL_SECONDS  # show "you: ..." straight away
	return reply


func _show_line() -> void:
	var shown := _line.right(LINE_COLS)  # the end of a long line, where you type
	_set_text("line", ("> " if _mode == "chat" else "$ ") + shown + "|" + (" (SHIFT)" if _shift else ""))


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
			if _mode == "chat":
				return _send_chat(line)
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
	_update_process()
	return reply


func _check_ask() -> void:
	var status: Dictionary = ctx["server"].run({"cmd": "agent_status"})
	if not status.get("ok", false):
		_asking = false
		_update_process()
		_print("error: %s" % status.get("error", "?"))
		return
	if status.get("busy", false):
		return
	_asking = false
	_update_process()
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
	if _mode == "chat" and ctx["modules"].module("chat") != null:
		var reply: Dictionary = ctx["server"].run({"cmd": "chat_clear"})
		_show_screen()
		return reply
	_screen.clear()
	_scroll = 0
	_show_screen()
	return {"ok": true}


func _help_command(request: Dictionary) -> Dictionary:
	var cmd_name = request.get("name", _line.strip_edges().split(" ")[0])
	return _help(str(cmd_name))


func _ask_command(_request: Dictionary) -> Dictionary:
	return _ask()


func _mode_command(request: Dictionary) -> Dictionary:
	var mode = request.get("mode")
	if not mode in ["terminal", "chat"]:
		return {"ok": false, "error": "\"mode\" must be terminal or chat"}
	_set_mode(mode)
	return {"ok": true, "mode": _mode}


func _status(_request: Dictionary) -> Dictionary:
	var shown := _chat_lines() if _mode == "chat" else _screen
	return {"ok": true, "mode": _mode, "line": _line, "screen": _visible_lines(shown), "scroll": _scroll,
		"history": _history, "asking": _asking, "window": _ui() != null}


# --- The window ----------------------------------------------------------------------

# The screen on top, the line being typed, the keyboard, and the tools in a
# column on the right. The window's place is kept by ui.gd; this only adds it
# the first time and replaces its elements after.
func _build_panel() -> void:
	var chat := _mode == "chat"
	var keys: Array = CHAT_KEYS if chat else ROWS_OF_KEYS
	var unit := KEY + GAP
	var width: float = keys[0].length() * unit - GAP
	var left := -width / 2.0
	var tools := [
		["mode", "Chat", {"cmd": "terminal_mode", "mode": "chat"}],
		["tab", "Tab", {"cmd": "terminal_key", "key": "tab"}],
		["prev", "Prev", {"cmd": "terminal_key", "key": "prev"}],
		["next", "Next", {"cmd": "terminal_key", "key": "next"}],
		["help", "Help", {"cmd": "terminal_help"}],
		["up", "Up", {"cmd": "terminal_scroll", "by": ROWS - 1}],
		["down", "Down", {"cmd": "terminal_scroll", "by": -(ROWS - 1)}],
		["cls", "Cls", {"cmd": "terminal_clear"}],
		["ask", "Ask AI", {"cmd": "terminal_ask"}],
	]
	if chat:
		tools = [
			["mode", "Terminal", {"cmd": "terminal_mode", "mode": "terminal"}],
			["stop", "STOP", {"cmd": "agent_stop"}],
			["new_chat", "New chat", {"cmd": "agent_reset"}],
			["up", "Up", {"cmd": "terminal_scroll", "by": ROWS - 1}],
			["down", "Down", {"cmd": "terminal_scroll", "by": -(ROWS - 1)}],
			["cls", "Cls", {"cmd": "terminal_clear"}],
		]
	# With the keyboard module loaded its window has the keys: this one has
	# none, a taller screen down to the line, and Run beside the line.
	var own_keys := ctx["modules"].module("keyboard") == null
	var screen_height := ROWS * FONT * 0.0006 * 1.25 + 0.02
	if not own_keys:
		screen_height = maxf(screen_height, tools.size() * unit - GAP - 0.05 - KEY / 2.0)
	var line_y := 0.09
	var screen_y := line_y + 0.05 + screen_height / 2.0
	var elements := [
		{"type": "box", "id": "screen", "at": [0, screen_y], "size": [width + 0.02, screen_height], "color": "#08100a"},
		{"type": "text", "id": "screen_text", "at": [0, screen_y + screen_height / 2.0 - 0.01], "width": width,
			"font_size": FONT, "color": "#8cff99", "mono": true, "text": ""},
		{"type": "text", "id": "line", "at": [0 if own_keys else -0.06, line_y + 0.012], "width": width if own_keys else width - 0.12,
			"font_size": LINE_FONT, "color": "#b3e6ff", "mono": true, "text": "$ |"},
	]
	if chat:
		# What the agent is doing, between the conversation and your line.
		elements.append({"type": "text", "id": "state", "at": [0, line_y + 0.042], "width": width, "font_size": 20,
			"color": "#5f9f6a", "mono": true, "source": {"cmd": "agent_status", "field": "status_line"}})
	if _scrolling_ui():
		# The new ui.gd's text area: it wraps, clips at its box and keeps
		# to the newest lines, and Up / Down scroll it.
		elements[1]["height"] = screen_height - 0.02
		elements[1]["scroll"] = true
		elements[1]["select"] = true  # rows can be picked for the keyboard's Copy
	if not own_keys:
		elements.append({"type": "button", "id": "run", "label": "Send" if chat else "Run", "at": [width / 2.0 - 0.05, line_y + 0.012 - KEY / 2.0 + 0.012],
			"size": [0.1, KEY], "action": {"cmd": "terminal_key", "key": "run"}, "color": "#2a6f3a"})
		keys = []
	for r in keys.size():
		var row: String = keys[r]
		for c in row.length():
			var ch := row[c]
			elements.append({"type": "button", "id": "key_%d_%d" % [r, c], "label": ch,
				"at": [left + KEY / 2.0 + c * unit, line_y - 0.05 - r * unit], "size": [KEY, KEY],
				"action": {"cmd": "terminal_type", "text": ch}})
	var bottom := line_y - 0.05 - keys.size() * unit
	var x := left
	var bottom_row := [["shift", "Shift", 2, {"cmd": "terminal_key", "key": "shift"}],
			["quote", "\"", 1, {"cmd": "terminal_type", "text": "\""}],
			["space", "Space", 4, {"cmd": "terminal_type", "text": " "}],
			["del", "Del", 1, {"cmd": "terminal_key", "key": "backspace"}],
			["clear", "Clr", 1, {"cmd": "terminal_key", "key": "clear"}],
			["run", "Run", 2, {"cmd": "terminal_key", "key": "run"}]]
	if chat:
		bottom_row = [["shift", "Shift", 2, {"cmd": "terminal_key", "key": "shift"}],
			["space", "Space", 4, {"cmd": "terminal_type", "text": " "}],
			["del", "Del", 2, {"cmd": "terminal_key", "key": "backspace"}],
			["clear", "Clr", 1, {"cmd": "terminal_key", "key": "clear"}],
			["run", "Send", 2, {"cmd": "terminal_key", "key": "run"}]]
	if not own_keys:
		bottom_row = []
	for key in bottom_row:
		var w: float = key[2] * unit - GAP
		var button := {"type": "button", "id": key[0], "label": key[1], "at": [x + w / 2.0, bottom], "size": [w, KEY], "action": key[3]}
		if key[0] == "run":
			button["color"] = "#2a6f3a"
		elements.append(button)
		x += key[2] * unit
	var tool_x := width / 2.0 + 0.02 + 0.055
	var top := screen_y + screen_height / 2.0 - KEY / 2.0
	for i in tools.size():
		var tool := {"type": "button", "id": "tool_" + tools[i][0], "label": tools[i][1],
			"at": [tool_x, top - i * unit], "size": [0.11, KEY], "action": tools[i][2]}
		if tools[i][0] == "stop":
			tool["color"] = "#8c1f1f"
		elif tools[i][0] == "mode":
			tool["color"] = "#2a4f8f"
		elements.append(tool)
	var title := "Chat" if chat else "Terminal"
	var panel := {"cmd": "ui_add", "id_panel": PANEL, "title": title, "place": "front", "distance": 0.6, "height": -0.3,
		"toggle": "right_a", "chrome": true, "elements": elements}
	if _has_panel():
		# Only the title and elements: where you put the window, and its
		# toggle, stay.
		# The title bar (carry, Pin, close) is added to a window made before it had one.
		panel = {"cmd": "ui_update", "id_panel": PANEL, "title": title, "chrome": true, "elements": elements}
	var reply: Dictionary = ctx["server"].run(panel)
	if not reply.get("ok", false):
		push_error("Slopitect terminal: the window could not be built: %s" % reply.get("error"))
		return
	_show_screen()
	_show_line()
