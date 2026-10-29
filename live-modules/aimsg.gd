extends SlopitectModule

# Slopitect live module: aimsg.
# Makes the agent's chat log easier to read: a tag for who is talking
# ("you>", "ai>"), the agent's words wrapped to the window, markdown marks
# taken out, code blocks marked with "|", and tool calls, thinking and
# notes kept to one short line each.
#
# It doesn't change any window. A text element in vrui.gd whose source has
# "format": "aimsg" is shown through format() while this module is loaded,
# and as plain lines when it isn't, so taking it out never breaks the chat
# window. The default chat window's log has it.
# The width and height change from the PC only (aimsg_config) and are kept
# in the app's own storage (user://aimsg.json).

const SETTINGS_PATH := "user://aimsg.json"
const DEFAULTS := {"cols": 38, "rows": 16}
const LIMITS := {"cols": [20, 80], "rows": [4, 40]}
const PAD := "     "
const TAGS := {"you": "you> ", "ai": "ai>  ", "err": "!!   ", "tool": "   + ", "think": "   ~ ", "note": "   - "}
# What agent.gd puts at the start of each event, and whose it is.
const PREFIXES := [["you: ", "you"], ["agent: ", "ai"], ["thinking: ", "think"], ["ERROR: ", "err"], ["tool ", "tool"]]

var settings := DEFAULTS.duplicate()
var _seen = null  # the events last formatted
var _text := ""  # and what they made


func setup() -> String:
	_load()
	register("aimsg_status", _status, "the chat log's width and height, and how many lines it has now")
	register("aimsg_config", _config, "from the PC only: any of cols (%d to %d characters), rows (%d to %d lines)" % [LIMITS["cols"][0], LIMITS["cols"][1], LIMITS["rows"][0], LIMITS["rows"][1]])
	return ""


# Called by vrui.gd for a text source with "format": "aimsg": the agent's
# events (agent_status's "events", a list of lines) as the chat log's text.
func format(value, _source: Dictionary) -> String:
	if not value is Array:
		return "" if value == null else str(value)
	if value == _seen:
		return _text
	var lines := []
	for event in value:
		lines.append_array(_event_lines(str(event)))
	while not lines.is_empty() and lines[-1] == "":
		lines.pop_back()
	_seen = value.duplicate()
	_text = "\n".join(PackedStringArray(lines.slice(maxi(0, lines.size() - int(settings["rows"])))))
	return _text


# One event as the chat log shows it, with a blank line after a message
# (chat.gd keeps its own scrollback with this).
func event_lines(event: String) -> Array:
	return _event_lines(event)


func _event_lines(event: String) -> Array:
	var role := "note"
	var text := event
	for prefix in PREFIXES:
		if event.begins_with(prefix[0]):
			role = prefix[1]
			text = event.substr(prefix[0].length())
			break
	var width: int = int(settings["cols"]) - PAD.length()
	if role in ["tool", "think", "note"]:
		var one := _plain(text)
		if one.length() > width:
			one = one.left(width - 3) + "..."
		return [TAGS[role] + one]
	var out := []
	var code := false
	for raw in text.split("\n"):
		var line := raw.strip_edges(false, true)
		if line.strip_edges().begins_with("```"):
			code = not code
			continue
		var lead: String = TAGS[role] if out.is_empty() else PAD
		if code:
			out.append(lead + "| " + line.left(width - 2))
			continue
		line = _unmark(line).strip_edges()
		if line.is_empty():
			if not out.is_empty() and out[-1] != "":
				out.append("")
			continue
		var hang := PAD
		if line.begins_with("- ") or line.begins_with("* ") or line.begins_with("• "):
			line = "- " + line.substr(2)
			hang = PAD + "  "
		var parts := _wrap(line, width)
		for i in parts.size():
			out.append((lead if i == 0 else hang) + parts[i])
	while not out.is_empty() and out[-1] == "":
		out.pop_back()
	if out.is_empty():
		out.append(TAGS[role])
	out.append("")  # a gap after each message
	return out


# Markdown marks out; a heading becomes capitals.
func _unmark(line: String) -> String:
	line = line.replace("**", "").replace("__", "").replace("`", "")
	var stripped := line.strip_edges()
	if stripped.begins_with("#"):
		return stripped.lstrip("#").strip_edges().to_upper()
	return line


func _plain(text: String) -> String:
	var words := PackedStringArray()
	for raw in text.split("\n"):
		var line := _unmark(raw).strip_edges()
		if not line.is_empty() and not line.begins_with("```"):
			words.append(line)
	return " ".join(words)


func _wrap(line: String, width: int) -> Array:
	var out := []
	var current := ""
	for word in line.split(" ", false):
		while word.length() > width:
			if not current.is_empty():
				out.append(current)
				current = ""
			out.append(word.left(width))
			word = word.substr(width)
		if current.is_empty():
			current = word
		elif current.length() + 1 + word.length() <= width:
			current += " " + word
		else:
			out.append(current)
			current = word
	if not current.is_empty():
		out.append(current)
	return out


# --- Commands and settings -------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	return {"ok": true, "settings": settings, "lines": 0 if _text.is_empty() else _text.count("\n") + 1}


func _config(request: Dictionary) -> Dictionary:
	var changes := {}
	for key in request:
		if key in ["cmd", "id"]:
			continue
		if not DEFAULTS.has(key):
			return {"ok": false, "error": "unknown setting \"%s\" (one of: %s)" % [key, ", ".join(DEFAULTS.keys())]}
		var value = request[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value != floorf(value) or value < LIMITS[key][0] or value > LIMITS[key][1]:
			return {"ok": false, "error": "\"%s\" must be a whole number from %d to %d" % [key, LIMITS[key][0], LIMITS[key][1]]}
		changes[key] = int(value)
	settings.merge(changes, true)
	_seen = null  # format again at the new size
	var out := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if out == null:
		push_error("Slopitect aimsg: couldn't save %s (error %d)" % [SETTINGS_PATH, FileAccess.get_open_error()])
	else:
		out.store_string(JSON.stringify(settings, "\t"))
		out.close()
	return _status({})


func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var saved = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(saved) != TYPE_DICTIONARY:
		push_error("Slopitect aimsg: %s isn't readable; using the defaults" % SETTINGS_PATH)
		return
	for key in DEFAULTS:
		var value = saved.get(key)
		if typeof(value) in [TYPE_INT, TYPE_FLOAT] and value >= LIMITS[key][0] and value <= LIMITS[key][1]:
			settings[key] = int(value)
