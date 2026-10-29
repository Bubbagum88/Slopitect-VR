extends SlopitectModule

# Errors: the app's own error messages, kept so they can be read back. Every
# error the engine reports (a script that hits a bug, a push_error, a failed
# load) is kept here, newest last, with the module it came from when it came
# from a live module. The agent is told about new errors from live modules
# after each step, so it can fix the code it wrote.

const KEEP := 100
const LIVE_PREFIX := "user://live-modules/"  # code.gd gives each live module's script this path
const TYPES := ["error", "warning", "script error", "shader error"]

var _logger: _Recorder


class _Recorder extends Logger:
	var entries: Array = []  # [{seq, ms, type, text, where, module}], newest last
	var next_seq := 1
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var where := "%s:%d (%s)" % [file, line, function]
		var module := ""
		# The innermost script frame says which script it really came from
		# (a push_error's own file is the engine's).
		for backtrace in script_backtraces:
			if backtrace.get_frame_count() > 0:
				var frame_file := backtrace.get_frame_file(0)
				where = "%s:%d (%s)" % [frame_file, backtrace.get_frame_line(0), backtrace.get_frame_function(0)]
				if frame_file.begins_with(LIVE_PREFIX):
					module = frame_file.trim_prefix(LIVE_PREFIX).trim_suffix(".gd")
					where = "%s.gd line %d (%s)" % [module, backtrace.get_frame_line(0), backtrace.get_frame_function(0)]
				break
		if file.begins_with(LIVE_PREFIX) and module.is_empty():
			module = file.trim_prefix(LIVE_PREFIX).trim_suffix(".gd")
			where = "%s.gd line %d (%s)" % [module, line, function]
		var text := code if rationale.is_empty() else "%s: %s" % [rationale, code]
		_mutex.lock()
		entries.append({"seq": next_seq, "ms": Time.get_ticks_msec(), "type": TYPES[error_type] if error_type < TYPES.size() else str(error_type),
			"text": text.left(500), "where": where.left(200), "module": module})
		next_seq += 1
		if entries.size() > KEEP:
			entries.pop_front()
		_mutex.unlock()

	func since(seq: int) -> Array:
		_mutex.lock()
		var found := []
		for entry in entries:
			if entry["seq"] > seq:
				found.append(entry.duplicate())
		_mutex.unlock()
		return found

	func clear() -> void:
		_mutex.lock()
		entries.clear()
		_mutex.unlock()


func setup() -> String:
	_logger = _Recorder.new()
	OS.add_logger(_logger)
	register("errors_recent", _recent, "the app's recent errors, newest last: optional since (a seq number, only newer ones), module (only one module's), max (default 20)")
	register("errors_clear", _clear, "forget the errors kept so far")
	return ""


func _exit_tree() -> void:
	OS.remove_logger(_logger)


# The newest error's seq number, so a caller can ask for only newer ones.
func last_seq() -> int:
	return _logger.next_seq - 1


# Errors newer than seq that came from live modules.
func live_errors_since(seq: int) -> Array:
	return _logger.since(seq).filter(func(e): return not e["module"].is_empty())


func _recent(request: Dictionary) -> Dictionary:
	var since = request.get("since", 0)
	var module = request.get("module", "")
	var most = request.get("max", 20)
	if (typeof(since) != TYPE_INT and typeof(since) != TYPE_FLOAT) or typeof(module) != TYPE_STRING \
			or (typeof(most) != TYPE_INT and typeof(most) != TYPE_FLOAT) or int(most) < 1:
		return {"ok": false, "error": "\"since\" and \"max\" must be numbers, \"module\" a module's name"}
	var found := _logger.since(int(since))
	if not module.is_empty():
		found = found.filter(func(e): return e["module"] == module)
	var now := Time.get_ticks_msec()
	for entry in found:
		entry["seconds_ago"] = (now - entry["ms"]) / 1000
		entry.erase("ms")
	return {"ok": true, "errors": found.slice(maxi(0, found.size() - int(most))), "count": found.size(), "last_seq": last_seq()}


func _clear(_request: Dictionary) -> Dictionary:
	_logger.clear()
	return {"ok": true}
