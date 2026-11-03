extends SlopitectModule

# Slopitect live module: edit.
# Lets the agent change part of a text file (a module, a skill, a note)
# without reading and writing the whole thing. files_write needs the whole
# file in one reply, and a reply is at most max_tokens long (16,000 tokens,
# about 45 KB), so the big modules (holdout, beatsaber, vrui: 130 KB and
# more) couldn't be changed at all. Here the agent looks at numbered lines
# (edit_view), finds text (edit_find) and swaps one exact piece for another
# (edit_replace).
# Every read and write goes through files.gd's files_read and files_write,
# so its rules hold: modules/agent_* stay locked, and a changed module still
# needs code_load and the person's Yes before it runs. Only files inside the
# Slopitect folder (a path without a leading /) can be edited here; anything
# else would need the Yes window, so use files_read and files_write for it.
# No settings, no window, no processing: it only runs when a command does.

const VIEW_LINES := 150  # lines edit_view shows when not told
const MOST_LINES := 400  # the most it shows at once
# The most characters it sends back at once: the agent cuts a tool reply at
# max_tool_result_chars (8000), and the JSON around the text needs room.
const MOST_CHARS := 6500
const FIND_HITS := 30
const LINE_CHARS := 200  # a found line is cut to this
const READ_CHUNK := 1048576  # files.gd's MAX_READ


func setup() -> String:
	set_process(false)
	set_physics_process(false)
	register("edit_view", _view, "show a text file's lines with their numbers: path (like modules/holdout.gd), optional from (line, default 1) and lines (default %d, up to %d); says the next line to ask for" % [VIEW_LINES, MOST_LINES])
	register("edit_find", _find, "find text in a file: path, text (exact, any case with case false); gives each line's number and text, up to max (default %d)" % FIND_HITS)
	register("edit_replace", _replace, "change part of a text file: path, old (exact text, tabs and all, found once; give more lines around it if it's in more places), new; optional all true changes every place. A module needs code_load after")
	return ""


func _view(request: Dictionary) -> Dictionary:
	var file := _load(request.get("path"))
	if file.has("error"):
		return {"ok": false, "error": file["error"]}
	var lines: PackedStringArray = file["text"].split("\n")
	var start = request.get("from", 1)
	var count = request.get("lines", VIEW_LINES)
	if typeof(start) not in [TYPE_INT, TYPE_FLOAT] or int(start) < 1:
		return {"ok": false, "error": "\"from\" must be a line number, 1 or more"}
	if typeof(count) not in [TYPE_INT, TYPE_FLOAT] or int(count) < 1 or int(count) > MOST_LINES:
		return {"ok": false, "error": "\"lines\" must be 1 to %d" % MOST_LINES}
	start = int(start)
	if start > lines.size():
		return {"ok": false, "error": "%s has only %d lines" % [file["path"], lines.size()]}
	var out := PackedStringArray()
	var chars := 0
	var last: int = start - 1
	for i in range(start - 1, mini(lines.size(), start - 1 + int(count))):
		var line := "%d\t%s" % [i + 1, lines[i]]
		if chars + line.length() + 1 > MOST_CHARS and not out.is_empty():
			break
		out.append(line.left(MOST_CHARS))
		chars += line.length() + 1
		last = i + 1
	var reply := {"ok": true, "path": file["path"], "total_lines": lines.size(), "from": start, "to": last, "text": "\n".join(out)}
	if last < lines.size():
		reply["next_from"] = last + 1
	return reply


func _find(request: Dictionary) -> Dictionary:
	var file := _load(request.get("path"))
	if file.has("error"):
		return {"ok": false, "error": file["error"]}
	var text = request.get("text")
	if typeof(text) != TYPE_STRING or text.is_empty() or "\n" in text:
		return {"ok": false, "error": "\"text\" must be some text on one line"}
	var most = request.get("max", FIND_HITS)
	if typeof(most) not in [TYPE_INT, TYPE_FLOAT] or int(most) < 1 or int(most) > 200:
		return {"ok": false, "error": "\"max\" must be 1 to 200"}
	var exact: bool = request.get("case", true) != false
	var hits := []
	var count := 0
	var lines: PackedStringArray = file["text"].split("\n")
	for i in lines.size():
		var found: bool = lines[i].contains(text) if exact else lines[i].containsn(text)
		if found:
			count += 1
			if hits.size() < int(most):
				hits.append({"line": i + 1, "text": lines[i].strip_edges().left(LINE_CHARS)})
	return {"ok": true, "path": file["path"], "total_lines": lines.size(), "count": count, "hits": hits}


func _replace(request: Dictionary) -> Dictionary:
	var old = request.get("old")
	var new = request.get("new")
	if typeof(old) != TYPE_STRING or old.is_empty():
		return {"ok": false, "error": "\"old\" must be the exact text to change (copy it from edit_view, without the line numbers)"}
	if typeof(new) != TYPE_STRING:
		return {"ok": false, "error": "\"new\" must be the text to put there (\"\" takes it out)"}
	if old == new:
		return {"ok": false, "error": "\"old\" and \"new\" are the same; nothing would change"}
	var all = request.get("all", false)
	if typeof(all) != TYPE_BOOL:
		return {"ok": false, "error": "\"all\" must be true or false"}
	var file := _load(request.get("path"))
	if file.has("error"):
		return {"ok": false, "error": file["error"]}
	var text: String = file["text"]
	var count := text.count(old)
	if count == 0:
		return {"ok": false, "error": "\"old\" isn't in %s exactly as given. %s" % [file["path"], _near(text, old)]}
	if count > 1 and not all:
		return {"ok": false, "error": "\"old\" is in %s %d times (lines %s); give more of the lines around the one to change, or all true to change every one" % [
			file["path"], count, ", ".join(_lines_of(text, old))]}
	var first_line := text.substr(0, text.find(old)).count("\n") + 1
	var changed := text.replace(old, new) if all else _replace_once(text, old, new)
	var wrote := _r({"cmd": "files_write", "path": request["path"], "text": changed})
	if not wrote.get("ok", false):
		return {"ok": false, "error": "couldn't write it: %s" % wrote.get("error", "?")}
	var reply := {"ok": true, "path": file["path"], "changed": count, "line": first_line,
		"total_lines": changed.count("\n") + 1, "bytes": wrote.get("bytes", changed.to_utf8_buffer().size())}
	var name := _module_name(String(request["path"]))
	if not name.is_empty():
		reply["next"] = "code_load name %s to run the change (it waits for the person's Yes)" % name
	return reply


# --- helpers ----------------------------------------------------------------

# A command run as whoever is running this one (the agent's guard still
# holds). A reply that waits for the person's Yes isn't expected here.
func _r(request: Dictionary) -> Dictionary:
	var reply: Dictionary = ctx["server"].run(request)
	var wait = reply.get("wait")
	if wait is SlopitectPending:
		if wait.finished:
			return wait.result
		wait.cancel("edit only works inside the Slopitect folder")
		return {"ok": false, "error": "that needs the person's Yes; use files_read and files_write for files outside the Slopitect folder"}
	return reply


# The whole text of a file in the Slopitect folder, or why not.
func _load(path) -> Dictionary:
	if typeof(path) != TYPE_STRING or path.is_empty():
		return {"error": "\"path\" must be a file in the Slopitect folder, like modules/holdout.gd"}
	if path.begins_with("/") or path.begins_with("models/"):
		return {"error": "edit works on files in the Slopitect folder only (a path like modules/holdout.gd); use files_read and files_write for %s" % path}
	var bytes := PackedByteArray()
	var where: String = path
	while true:
		var got := _r({"cmd": "files_read", "path": path, "offset": bytes.size(), "max_bytes": READ_CHUNK})
		if not got.get("ok", false):
			return {"error": got.get("error", "can't read %s" % path)}
		if not got.has("text"):
			return {"error": "%s isn't a text file" % path}
		where = got.get("path", path)
		bytes.append_array(String(got["text"]).to_utf8_buffer())
		if not got.get("more", false) or int(got.get("read", 0)) == 0:
			break
	var text := bytes.get_string_from_utf8()
	if "\r\n" in text:
		# The module hashes on the headset must match the PC's, which are \n.
		return {"error": "%s has Windows line endings (\\r\\n); edit can't keep them exact, so use files_write" % where}
	return {"path": where, "text": text}


func _replace_once(text: String, old: String, new: String) -> String:
	var at := text.find(old)
	return text.substr(0, at) + new + text.substr(at + old.length())


func _lines_of(text: String, old: String) -> PackedStringArray:
	var out := PackedStringArray()
	var at := text.find(old)
	while at != -1 and out.size() < 10:
		out.append(str(text.substr(0, at).count("\n") + 1))
		at = text.find(old, at + 1)
	return out


# Why "old" may not have matched: the lines where its first line is, ignoring
# the indents (tabs against spaces is the usual slip).
func _near(text: String, old: String) -> String:
	var first := ""
	for line in old.split("\n"):
		if not line.strip_edges().is_empty():
			first = line.strip_edges()
			break
	if first.is_empty():
		return "Copy it from edit_view (without the line numbers)."
	var lines: PackedStringArray = text.split("\n")
	var hits := PackedStringArray()
	for i in lines.size():
		if lines[i].strip_edges() == first:
			hits.append(str(i + 1))
	if hits.is_empty():
		return "Its first line isn't in the file either; edit_find a word from it."
	return "Its first line is at line %s, so check the indents (tabs) and the lines after it with edit_view." % ", ".join(hits.slice(0, 10))


func _module_name(path: String) -> String:
	var simple := path.simplify_path()
	if simple.begins_with("modules/") and simple.count("/") == 1 and simple.ends_with(".gd"):
		return simple.get_file().get_basename()
	return ""
