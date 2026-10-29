extends SlopitectModule

# Slopitect live module: memory.
# The agent's long-term memory, kept between conversations and app starts.
# Each world (a project, with projects.gd) has its own memory, and one
# global memory holds what applies everywhere:
#   notes      things the agent chose to keep (memory_note): facts about a
#              world, decisions, troubleshooting that worked, coding
#              techniques. Techniques and troubleshooting are global unless
#              said otherwise; the rest belong to the world.
#   exchanges  each question the person asked in that world: the question,
#              the agent's answer, which tools it used and what failed. Kept
#              by themselves, from the agent's events.
#   digests    older exchanges folded together: the questions, tool counts
#              and errors, plus a summary once the agent writes one
#              (memory_compact). Old digests merge, so a world's memory
#              stays the same size however long it's used.
#   tools      each tool's ok and failed counts and its last error.
#
# Personal info and keys are never kept: everything is cleaned of anything
# that looks like a key, password, e-mail address, phone number or IP
# address before it's stored, and the agent's settings changes and thinking
# are never recorded. It lives in the app's own storage (user://memory/), not
# the Slopitect folder, so backups and other apps don't see it, and nothing
# it stores is printed to the log.
#
# Sized for the Quest 1: only the global memory and the current world's are
# in memory at once, every list has a fixed limit, and it's saved at most
# every 5 seconds (and when the headset pauses the app).
#
# Until agent.gd sends signals (MODULE-FRAMEWORK.md), it reads the agent's
# events from agent_status: twice a second while the agent works, every 2
# seconds otherwise. A stand-in, marked as such.

const FOLDER := "user://memory"
const CONFIG_PATH := "user://memory/config.json"
const SKILL_PATH := "user://skills/slopitect-memory/SKILL.md"
const DEFAULT_WORLD := "default"  # without projects.gd
const SAVE_DELAY := 5.0
const POLL_BUSY := 0.5  # stand-in for agent signals
const POLL_IDLE := 2.0

# Limits, so a world's memory has a ceiling (about 150 KB on disk at most).
const MAX_TEXT := 300  # an exchange's question or answer
const MAX_NOTE := 600
const MAX_NOTES := 150  # per world, and for global
const MAX_EXCHANGES := 40  # past this, the oldest half becomes a digest
const MAX_DIGESTS := 30  # past this, the two oldest merge
const MAX_DIGEST_ASKS := 12
const MAX_ERRORS := 5
const MAX_TAGS := 6
const KINDS := ["fact", "decision", "technique", "troubleshooting", "todo"]
const GLOBAL_KINDS := ["technique", "troubleshooting"]  # global unless "global": false

const DEFAULT_CONFIG := {"capture": true, "recall_chars": 4000}

const SKILL := """---
name: slopitect-memory
description: Your memory across conversations (the memory module).
always: true
---

You have a memory that outlasts conversations (memory_* tools). At the
start of a conversation, call memory_recall once before working. Keep what
will matter later with memory_note: decisions, what fixed a problem, coding
techniques that worked, what's left to do. Never put personal information,
keys or passwords in memory. When memory_recall says exchanges need a
summary, write one with memory_compact.
"""

var _config := DEFAULT_CONFIG.duplicate()
var _global := {}
var _world := {}
var _world_name := ""
var _dirty := {}  # "global" / the world's name -> true
var _save_timer := 0.0
var _poll_timer := 0.0
var _seen: Array = []  # the agent's events already read
var _was_busy := false
var _open = null  # the exchange in progress, or null
var _patterns: Array = []  # [RegEx, replacement]


func setup() -> String:
	if DirAccess.make_dir_recursive_absolute(FOLDER + "/worlds") != OK:
		return "memory can't make its folder %s" % FOLDER
	_load_config()
	_make_patterns()
	_global = _read_scope(FOLDER + "/global.json")
	_use_world(_current_world())
	_write_skill()
	register("memory_status", _status, "what memory holds: the world, counts, sizes on disk, whether conversations are kept")
	register("memory_recall", _recall, "what you remember about this world and in general: notes, recent exchanges, digests, tools that failed; optional world (another world's name)")
	register("memory_note", _note, "keep something for later: text; optional kind (fact, decision, technique, troubleshooting, todo), tags [words], global (true: for every world). No personal info or keys")
	register("memory_forget", _forget, "remove a note or digest: id (like w4, g2 or d3)")
	register("memory_search", _search, "find notes, digests and exchanges: query (words); optional everywhere (true: every world, not just this one and global)")
	register("memory_compact", _compact, "fold this world's recent exchanges into a digest with your summary: summary; or give a digest id to add a summary to that one")
	register("memory_config", _config_command, "from the PC only: any of capture (true/false: keep conversations), recall_chars (1000-8000), clear (\"global\" or a world's name: forget it all)")
	var agent := _agent_status()
	_seen = agent.get("events", [])  # events from before it loaded aren't recorded
	_was_busy = agent.get("busy", false)
	return ""


func _process(delta: float) -> void:
	_poll_timer -= delta
	if _poll_timer <= 0.0:
		_poll_timer = POLL_BUSY if _was_busy else POLL_IDLE
		_poll_agent()
	if not _dirty.is_empty():
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save_all()


func _notification(what: int) -> void:
	# The headset can close the app at any time after this.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_close_exchange()
		_save_all()


func _exit_tree() -> void:
	_close_exchange()
	_save_all()
	# Its tools are gone, so the agent shouldn't be told to use them.
	DirAccess.remove_absolute(SKILL_PATH)
	DirAccess.remove_absolute(SKILL_PATH.get_base_dir())


# --- Reading the agent's events --------------------------------------------------------

func _agent_status() -> Dictionary:
	if ctx["server"].module_of("agent_status").is_empty():
		return {}
	var status: Dictionary = ctx["server"].run({"cmd": "agent_status"})
	return status if status.get("ok", false) else {}


func _poll_agent() -> void:
	var status := _agent_status()
	if status.is_empty():
		return
	var events: Array = status.get("events", [])
	for event in _new_events(_seen, events):
		_record(String(event))
	_seen = events
	var busy: bool = status.get("busy", false)
	if _was_busy and not busy:
		_close_exchange()
	_was_busy = busy


# The agent keeps its last 40 events and drops the oldest, so the new ones
# are what's after the longest stretch the old list ends with.
func _new_events(old: Array, now: Array) -> Array:
	for overlap in range(mini(old.size(), now.size()), 0, -1):
		if old.slice(old.size() - overlap) == now.slice(0, overlap):
			return now.slice(overlap)
	return now


func _record(event: String) -> void:
	if not _config["capture"]:
		return
	if event.begins_with("you: "):
		_close_exchange()
		_use_world(_current_world())
		_open = {"t": int(Time.get_unix_time_from_system()), "ask": _clean(event.substr(5), MAX_TEXT), "reply": "", "tools": {}, "errors": []}
		return
	# Settings changes and thinking are never kept.
	if event.begins_with("thinking: ") or event.begins_with("settings changed"):
		return
	if event.begins_with("agent: "):
		_exchange()["reply"] = _clean(event.substr(7), MAX_TEXT)
	elif event.begins_with("tool "):
		_record_tool(event.substr(5))
	elif event.begins_with("ERROR: "):
		_add_error(_clean(event.substr(7), 200))
	elif event == "STOP pressed":
		_add_error("stopped by the person")


# "NAME {input} -> ok" or "NAME {input} -> FAILED: why"
func _record_tool(text: String) -> void:
	var tool := text.get_slice(" ", 0)
	if tool.begins_with("memory_"):
		return
	var failed := text.find(" -> FAILED: ")
	var why := _clean(text.substr(failed + 12), 200) if failed != -1 else ""
	var counts: Array = _exchange()["tools"].get(tool, [0, 0])
	counts[1 if failed != -1 else 0] += 1
	_exchange()["tools"][tool] = counts
	if failed != -1:
		_add_error("%s: %s" % [tool, why])
	var stats: Dictionary = _world["tools"]
	var stat: Dictionary = stats.get(tool, {"ok": 0, "failed": 0})
	stat["failed" if failed != -1 else "ok"] += 1
	if failed != -1:
		stat["last_error"] = why
	stat["last_used"] = int(Time.get_unix_time_from_system())
	stats[tool] = stat
	_touch(_world_name)


func _exchange() -> Dictionary:
	if _open == null:
		_open = {"t": int(Time.get_unix_time_from_system()), "ask": "(the agent carried on by itself)", "reply": "", "tools": {}, "errors": []}
	return _open


func _add_error(text: String) -> void:
	var errors: Array = _exchange()["errors"]
	if errors.size() < MAX_ERRORS and not errors.has(text):
		errors.append(text)


func _close_exchange() -> void:
	if _open == null:
		return
	_world["exchanges"].append(_open)
	_open = null
	if _world["exchanges"].size() > MAX_EXCHANGES:
		var oldest: Array = _world["exchanges"].slice(0, MAX_EXCHANGES / 2)
		_world["exchanges"] = _world["exchanges"].slice(MAX_EXCHANGES / 2)
		_add_digest(_world, _digest_of(oldest, ""))
	_touch(_world_name)


# --- Digests -------------------------------------------------------------------------

func _digest_of(exchanges: Array, summary: String) -> Dictionary:
	var asks := []
	var tools := {}
	var errors := []
	for exchange in exchanges:
		if asks.size() < MAX_DIGEST_ASKS:
			asks.append(String(exchange["ask"]).left(80))
		for tool in exchange["tools"]:
			var counts: Array = tools.get(tool, [0, 0])
			tools[tool] = [counts[0] + exchange["tools"][tool][0], counts[1] + exchange["tools"][tool][1]]
		for error in exchange["errors"]:
			if errors.size() < MAX_ERRORS and not errors.has(error):
				errors.append(error)
	return {"from": exchanges[0]["t"], "to": exchanges[-1]["t"], "exchanges": exchanges.size(),
		"asks": asks, "tools": tools, "errors": errors, "summary": summary}


func _add_digest(scope: Dictionary, digest: Dictionary) -> void:
	scope["next_digest"] = int(scope["next_digest"]) + 1
	digest["id"] = "d%d" % scope["next_digest"]
	scope["digests"].append(digest)
	while scope["digests"].size() > MAX_DIGESTS:
		var a: Dictionary = scope["digests"].pop_front()
		var b: Dictionary = scope["digests"][0]
		var tools: Dictionary = a["tools"].duplicate()
		for tool in b["tools"]:
			var counts: Array = tools.get(tool, [0, 0])
			tools[tool] = [counts[0] + b["tools"][tool][0], counts[1] + b["tools"][tool][1]]
		var summary := (String(a["summary"]) + " " + String(b["summary"])).strip_edges().left(MAX_NOTE)
		var asks: Array = (a["asks"] + b["asks"]).slice(0, MAX_DIGEST_ASKS)
		var errors: Array = (b["errors"] + a["errors"]).slice(0, MAX_ERRORS)
		scope["digests"][0] = {"id": b["id"], "from": a["from"], "to": b["to"], "exchanges": a["exchanges"] + b["exchanges"],
			"asks": asks, "tools": tools, "errors": errors, "summary": summary}


# --- Commands ------------------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	_use_world(_current_world())
	var worlds := {}
	var total := 0
	for file in DirAccess.get_files_at(FOLDER + "/worlds"):
		if file.ends_with(".json"):
			var size := _size(FOLDER + "/worlds/" + file)
			worlds[file.get_basename()] = size
			total += size
	total += _size(FOLDER + "/global.json")
	return {"ok": true, "world": _world_name, "capture": _config["capture"], "recall_chars": _config["recall_chars"],
		"global": _counts(_global), "this_world": _counts(_world), "world_bytes": worlds, "total_bytes": total}


func _counts(scope: Dictionary) -> Dictionary:
	return {"notes": scope["notes"].size(), "exchanges": scope["exchanges"].size(), "digests": scope["digests"].size(), "tools": scope["tools"].size()}


func _recall(request: Dictionary) -> Dictionary:
	_use_world(_current_world())
	var scope := _world
	var world_name := _world_name
	if request.has("world") and request["world"] != _world_name:
		if not _good_name(request["world"]) or not FileAccess.file_exists(_world_path(request["world"])):
			return {"ok": false, "error": "no memory of a world named %s (memory_status lists them)" % JSON.stringify(request.get("world"))}
		world_name = request["world"]
		scope = _read_scope(_world_path(world_name))
	var budget: int = _config["recall_chars"]
	var notes := []
	for note in _newest_first(scope["notes"]) + _newest_first(_global["notes"]):
		var line := "%s [%s] %s" % [note["id"], note["kind"], note["text"]]
		if not note.get("tags", []).is_empty():
			line += " (%s)" % ", ".join(PackedStringArray(note["tags"]))
		budget -= line.length()
		if budget < 0:
			break
		notes.append(line)
	var recent := []
	for exchange in _newest_first(scope["exchanges"]).slice(0, 5):
		var line := "%s: asked \"%s\"" % [_date(exchange["t"]), exchange["ask"]]
		if not String(exchange["reply"]).is_empty():
			line += "; answered \"%s\"" % String(exchange["reply"]).left(150)
		if not exchange["errors"].is_empty():
			line += "; problems: " + "; ".join(PackedStringArray(exchange["errors"])).left(200)
		budget -= line.length()
		if budget < 0:
			break
		recent.append(line)
	var digests := []
	for digest in _newest_first(scope["digests"]).slice(0, 5):
		var line := "%s (%s to %s, %d exchanges): " % [digest["id"], _date(digest["from"]), _date(digest["to"]), digest["exchanges"]]
		line += String(digest["summary"]) if not String(digest["summary"]).is_empty() else "asked: " + " | ".join(PackedStringArray(digest["asks"]))
		budget -= line.length()
		if budget < 0:
			break
		digests.append(line)
	var failing := []
	for tool in scope["tools"]:
		var stat: Dictionary = scope["tools"][tool]
		if stat["failed"] > 0 and stat.has("last_error"):
			failing.append("%s failed %d of %d, last: %s" % [tool, stat["failed"], stat["failed"] + stat["ok"], String(stat["last_error"]).left(120)])
	var reply := {"ok": true, "world": world_name, "notes": notes, "recent": recent, "digests": digests, "tools_that_failed": failing.slice(0, 8)}
	var unsummarised: int = scope["exchanges"].size()
	if world_name == _world_name and unsummarised >= MAX_EXCHANGES / 2:
		reply["exchanges_need_a_summary"] = "%d exchanges have no summary; fold them in with memory_compact" % unsummarised
	return reply


func _note(request: Dictionary) -> Dictionary:
	var text = request.get("text")
	if typeof(text) != TYPE_STRING or text.strip_edges().is_empty():
		return {"ok": false, "error": "memory_note needs \"text\": what to remember"}
	if text.length() > MAX_NOTE:
		return {"ok": false, "error": "a note is at most %d characters (this one is %d); keep the gist" % [MAX_NOTE, text.length()]}
	var kind = request.get("kind", "fact")
	if not (kind in KINDS):
		return {"ok": false, "error": "\"kind\" is one of: " + ", ".join(PackedStringArray(KINDS))}
	var tags = request.get("tags", [])
	if typeof(tags) != TYPE_ARRAY or tags.size() > MAX_TAGS or tags.any(func(tag): return typeof(tag) != TYPE_STRING or tag.length() > 30):
		return {"ok": false, "error": "\"tags\" is a list of up to %d short words" % MAX_TAGS}
	var global = request.get("global", kind in GLOBAL_KINDS)
	if typeof(global) != TYPE_BOOL:
		return {"ok": false, "error": "\"global\" is true or false"}
	_use_world(_current_world())
	var scope := _global if global else _world
	if scope["notes"].size() >= MAX_NOTES:
		return {"ok": false, "error": "%s memory is full (%d notes); forget some first (memory_recall lists them)" % ["global" if global else "this world's", MAX_NOTES]}
	var cleaned := _clean(text, MAX_NOTE)
	scope["next_note"] = int(scope["next_note"]) + 1
	var id := "%s%d" % ["g" if global else "w", scope["next_note"]]
	scope["notes"].append({"id": id, "kind": kind, "text": cleaned, "tags": tags.map(func(tag): return _clean(tag, 30)),
		"t": int(Time.get_unix_time_from_system())})
	_touch("global" if global else _world_name)
	var reply := {"ok": true, "id": id, "world": "global" if global else _world_name}
	if cleaned != text.strip_edges():
		reply["note"] = "parts that looked like personal info or keys were removed"
	return reply


func _forget(request: Dictionary) -> Dictionary:
	var id = request.get("id")
	if typeof(id) != TYPE_STRING or id.length() < 2:
		return {"ok": false, "error": "memory_forget needs \"id\" (like w4, g2 or d3)"}
	_use_world(_current_world())
	var lists := {"w": [_world, "notes", _world_name], "g": [_global, "notes", "global"], "d": [_world, "digests", _world_name]}
	if not lists.has(id[0]):
		return {"ok": false, "error": "ids start with w (this world's notes), g (global notes) or d (digests)"}
	var found: Array = lists[id[0]]
	var items: Array = found[0][found[1]]
	for i in items.size():
		if items[i]["id"] == id:
			items.remove_at(i)
			_touch(found[2])
			return {"ok": true, "forgot": id}
	return {"ok": false, "error": "no %s in %s's memory" % [id, found[2]]}


func _search(request: Dictionary) -> Dictionary:
	var query = request.get("query")
	if typeof(query) != TYPE_STRING or query.strip_edges().is_empty():
		return {"ok": false, "error": "memory_search needs \"query\" (words)"}
	var words: PackedStringArray = String(query).to_lower().split(" ", false)
	_use_world(_current_world())
	var scopes := {"global": _global, _world_name: _world}
	if request.get("everywhere", false) == true:
		for file in DirAccess.get_files_at(FOLDER + "/worlds"):
			var other := file.get_basename()
			if file.ends_with(".json") and not scopes.has(other):
				scopes[other] = _read_scope(FOLDER + "/worlds/" + file)  # read, searched and let go
	var found := []
	for where in scopes:
		var scope: Dictionary = scopes[where]
		for note in scope["notes"]:
			_match(found, words, where, note["id"], "%s [%s] %s %s" % [note["id"], note["kind"], note["text"], " ".join(PackedStringArray(note.get("tags", [])))])
		for digest in scope["digests"]:
			_match(found, words, where, digest["id"], "%s %s asked: %s; errors: %s" % [digest["id"], digest["summary"], " | ".join(PackedStringArray(digest["asks"])), "; ".join(PackedStringArray(digest["errors"]))])
		for exchange in scope["exchanges"]:
			_match(found, words, where, "", "%s: asked \"%s\"; answered \"%s\"; problems: %s" % [_date(exchange["t"]), exchange["ask"], exchange["reply"], "; ".join(PackedStringArray(exchange["errors"]))])
	found.sort_custom(func(a, b): return a["score"] > b["score"])
	var results := []
	for hit in found.slice(0, 10):
		results.append({"world": hit["world"], "text": hit["text"].left(400)})
	return {"ok": true, "results": results}


func _match(found: Array, words: PackedStringArray, where: String, _id: String, text: String) -> void:
	var lower := text.to_lower()
	var score := 0
	for word in words:
		if lower.contains(word):
			score += 1
	if score > 0:
		found.append({"score": score, "world": where, "text": text})


func _compact(request: Dictionary) -> Dictionary:
	var summary = request.get("summary")
	if typeof(summary) != TYPE_STRING or summary.strip_edges().is_empty():
		return {"ok": false, "error": "memory_compact needs \"summary\": what happened, what worked, what's left"}
	if summary.length() > MAX_NOTE:
		return {"ok": false, "error": "a summary is at most %d characters" % MAX_NOTE}
	_use_world(_current_world())
	var cleaned := _clean(summary, MAX_NOTE)
	if request.has("digest"):
		for digest in _world["digests"]:
			if digest["id"] == request["digest"]:
				digest["summary"] = cleaned
				_touch(_world_name)
				return {"ok": true, "digest": digest["id"]}
		return {"ok": false, "error": "no digest %s in this world (memory_recall lists them)" % JSON.stringify(request["digest"])}
	_close_exchange()
	if _world["exchanges"].is_empty():
		return {"ok": false, "error": "no exchanges to fold in; give \"digest\" to summarise an older digest"}
	var digest := _digest_of(_world["exchanges"], cleaned)
	_world["exchanges"] = []
	_add_digest(_world, digest)
	_touch(_world_name)
	return {"ok": true, "digest": digest["id"], "exchanges": digest["exchanges"]}


func _config_command(request: Dictionary) -> Dictionary:
	var changed := false
	if request.has("capture"):
		if typeof(request["capture"]) != TYPE_BOOL:
			return {"ok": false, "error": "\"capture\" is true or false"}
		_config["capture"] = request["capture"]
		if not request["capture"]:
			_open = null
		changed = true
	if request.has("recall_chars"):
		var chars = request["recall_chars"]
		if not (typeof(chars) in [TYPE_INT, TYPE_FLOAT]) or chars < 1000 or chars > 8000:
			return {"ok": false, "error": "\"recall_chars\" is 1000 to 8000"}
		_config["recall_chars"] = int(chars)
		changed = true
	if request.has("clear"):
		var what = request["clear"]
		if what == "global":
			_global = _empty_scope()
			_touch("global")
		elif _good_name(what) and FileAccess.file_exists(_world_path(what)):
			if what == _world_name:
				_world = _empty_scope()
				_open = null
				_dirty.erase(what)
			DirAccess.remove_absolute(_world_path(what))
		else:
			return {"ok": false, "error": "\"clear\" is \"global\" or the name of a world with memory (memory_status lists them)"}
		changed = true
	if changed:
		var out := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
		if out:
			out.store_string(JSON.stringify(_config))
			out.close()
	return {"ok": true, "capture": _config["capture"], "recall_chars": _config["recall_chars"]}


# --- Worlds and files ----------------------------------------------------------------

# The world is the current project (projects.gd keeps it in user://projects.json).
func _current_world() -> String:
	if ctx["modules"].module("projects") == null or not FileAccess.file_exists("user://projects.json"):
		return DEFAULT_WORLD
	var state = JSON.parse_string(FileAccess.get_file_as_string("user://projects.json"))
	if typeof(state) == TYPE_DICTIONARY and _good_name(state.get("current")):
		return state["current"]
	return DEFAULT_WORLD


func _use_world(world_name: String) -> void:
	if world_name == _world_name:
		return
	if not _world_name.is_empty():
		_close_exchange()
		_save_all()
	_world_name = world_name
	_world = _read_scope(_world_path(world_name))


func _world_path(world_name: String) -> String:
	return "%s/worlds/%s.json" % [FOLDER, world_name]


func _good_name(value) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 40:
		return false
	for c in value:
		if not (c == "_" or c == "-" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return true


func _empty_scope() -> Dictionary:
	return {"version": 1, "notes": [], "exchanges": [], "digests": [], "tools": {}, "next_note": 0, "next_digest": 0}


# A file that can't be read is set aside (.bad), never overwritten.
func _read_scope(path: String) -> Dictionary:
	var scope := _empty_scope()
	if not FileAccess.file_exists(path):
		return scope
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Slopitect memory: %s couldn't be read; kept as %s.bad" % [path, path])
		DirAccess.rename_absolute(path, path + ".bad")
		return scope
	for key in scope:
		if data.has(key) and typeof(data[key]) == typeof(scope[key]):
			scope[key] = data[key]
		elif data.has(key) and typeof(scope[key]) == TYPE_INT and typeof(data[key]) == TYPE_FLOAT:
			scope[key] = int(data[key])
	return scope


func _touch(scope_name: String) -> void:
	if _dirty.is_empty():
		_save_timer = SAVE_DELAY
	_dirty[scope_name] = true


func _save_all() -> void:
	for scope_name in _dirty:
		var problem := ""
		if scope_name == "global":
			problem = _write(FOLDER + "/global.json", _global)
		elif scope_name == _world_name:
			problem = _write(_world_path(_world_name), _world)
		if not problem.is_empty():
			push_error("Slopitect memory: " + problem)
	_dirty.clear()


# Written to a temporary file first, so a save cut short never replaces a good one.
func _write(path: String, data: Dictionary) -> String:
	var temporary := path + ".writing"
	var out := FileAccess.open(temporary, FileAccess.WRITE)
	if out == null:
		return "couldn't write %s (error %d)" % [temporary, FileAccess.get_open_error()]
	out.store_string(JSON.stringify(data))
	out.close()
	var moved := DirAccess.rename_absolute(temporary, path)
	return "" if moved == OK else "couldn't move %s into place (error %d)" % [temporary, moved]


func _load_config() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else null
	if typeof(data) != TYPE_DICTIONARY:
		return
	if typeof(data.get("capture")) == TYPE_BOOL:
		_config["capture"] = data["capture"]
	if typeof(data.get("recall_chars")) in [TYPE_INT, TYPE_FLOAT]:
		_config["recall_chars"] = clampi(int(data["recall_chars"]), 1000, 8000)


# The skill that tells the agent it has a memory. It's taken away again
# when the module is unloaded.
func _write_skill() -> void:
	DirAccess.make_dir_recursive_absolute(SKILL_PATH.get_base_dir())
	if FileAccess.file_exists(SKILL_PATH) and FileAccess.get_file_as_string(SKILL_PATH) == SKILL:
		return
	var out := FileAccess.open(SKILL_PATH, FileAccess.WRITE)
	if out:
		out.store_string(SKILL)
		out.close()


func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file else 0


# --- Keeping personal info out ---------------------------------------------------------

func _make_patterns() -> void:
	for pair in [
		# A "..._key", password, token or secret field with its value.
		["(?i)\"?\\b(\\w*_key|key|password|passwd|pwd|token|secret)\\b\"?\\s*[:=]\\s*\"?[^\\s\",}]+\"?", "$1: (removed)"],
		# Keys by their look: Anthropic, OpenAI, GitHub, Slack, AWS, Google.
		["\\b(sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\\w{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,})", "(key removed)"],
		["[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "(e-mail removed)"],
		["(\\+?\\d{1,3}[\\s.-]?)?\\(?\\d{3}\\)?[\\s.-]?\\d{3}[\\s.-]?\\d{4}\\b", "(number removed)"],
		["\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}(:\\d+)?\\b", "(address removed)"],
		# Any other long run of letters and digits mixed, like a key or hash.
		["\\b(?=[A-Za-z_-]*\\d)(?=[\\d_-]*[A-Za-z])[A-Za-z0-9_-]{32,}\\b", "(removed)"],
	]:
		_patterns.append([RegEx.create_from_string(pair[0]), pair[1]])


func _clean(text: String, limit: int) -> String:
	var cleaned := text.strip_edges()
	for pair in _patterns:
		cleaned = pair[0].sub(cleaned, pair[1], true)
	return cleaned.left(limit)


func _newest_first(items: Array) -> Array:
	var copy := items.duplicate()
	copy.reverse()
	return copy


func _date(unix) -> String:
	return Time.get_datetime_string_from_unix_time(int(unix)).left(16).replace("T", " ")
