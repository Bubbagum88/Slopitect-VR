extends SlopitectModule
# Headless checks for edit.gd. Run: tests/run.sh edit zz_edit
var _fails := 0
var _passes := 0


func setup() -> String:
	_go.call_deferred()
	return ""


func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if ok: _passes += 1
	else: _fails += 1


func _r(q: Dictionary, agent := false) -> Dictionary:
	var r = ctx["server"].run_for_agent(q) if agent else ctx["server"].run(q)
	if r.get("wait") is SlopitectPending:
		var p: SlopitectPending = r["wait"]
		r = p.result if p.finished else await p.done
	return r


func _read(path: String) -> String:
	return String((await _r({"cmd": "files_read", "path": path, "max_bytes": 1048576})).get("text", ""))


func _go() -> void:
	await get_tree().create_timer(0.5).timeout
	var edit = ctx["modules"].module("edit")
	_check("loaded and idle", edit != null and not edit.is_processing() and not edit.is_physics_processing())
	# A module-sized file: 3000 lines, about 100 KB.
	var lines := PackedStringArray(["extends SlopitectModule", "", "func setup() -> String:", "\treturn \"\""])
	for i in 3000:
		lines.append("var v%d := %d  # filler line to make the file big, like holdout.gd" % [i, i])
	lines.append("func twice():\n\tpass\n\nfunc twice_b():\n\tpass")
	var body := "\n".join(lines) + "\n"
	_check("write the test file", (await _r({"cmd": "files_write", "path": "modules/zz_target.gd", "text": body})).get("ok", false))

	var v := await _r({"cmd": "edit_view", "path": "modules/zz_target.gd"})
	_check("view: numbered lines from 1", v.get("ok", false) and String(v.get("text", "")).begins_with("1\textends SlopitectModule"), v)
	_check("view: knows the file's size", v.get("total_lines", 0) == body.count("\n") + 1, v.get("total_lines"))
	_check("view: fits a tool reply", v.get("ok", false) and JSON.stringify(v).length() < 8000, JSON.stringify(v).length())
	_check("view: says where to go on", v.get("ok", false) and v.get("next_from", 0) == v.get("to", -1) + 1, [v.get("to"), v.get("next_from")])
	var v2 := await _r({"cmd": "edit_view", "path": "modules/zz_target.gd", "from": 2900, "lines": 5})
	_check("view: from a line deep in", String(v2.get("text", "")).begins_with("2900\tvar v2895 := 2895"), v2.get("text"))
	_check("view: bad from", "from" in String((await _r({"cmd": "edit_view", "path": "modules/zz_target.gd", "from": 0})).get("error", "")))
	_check("view: past the end", "only" in String((await _r({"cmd": "edit_view", "path": "modules/zz_target.gd", "from": 99999})).get("error", "")))

	var f := await _r({"cmd": "edit_find", "path": "modules/zz_target.gd", "text": "func twice"})
	_check("find: both lines", f.get("count", 0) == 2 and f["hits"][0]["line"] == 3005, f)
	var fc := await _r({"cmd": "edit_find", "path": "modules/zz_target.gd", "text": "FUNC TWICE", "case": false})
	_check("find: any case", fc.get("count", 0) == 2, fc)

	var once := await _r({"cmd": "edit_replace", "path": "modules/zz_target.gd", "old": "var v2500 := 2500", "new": "var v2500 := -1"})
	var after := await _read("modules/zz_target.gd")
	_check("replace: one place", once.get("ok", false) and once.get("line", 0) == 2505 and "var v2500 := -1  #" in after and not "var v2500 := 2500" in after, once)
	_check("replace: nothing else changed", after == body.replace("var v2500 := 2500", "var v2500 := -1"), [after.length(), body.length()])
	_check("replace: says to code_load", String(once.get("next", "")).contains("code_load name zz_target"), once)
	var twice := await _r({"cmd": "edit_replace", "path": "modules/zz_target.gd", "old": "\tpass", "new": "\treturn"})
	_check("replace: twice found -> refused with lines", not twice.get("ok", true) and "3006, 3009" in String(twice.get("error", "")), twice)
	var all := await _r({"cmd": "edit_replace", "path": "modules/zz_target.gd", "old": "\tpass", "new": "\treturn", "all": true})
	_check("replace: all", all.get("changed", 0) == 2 and not "\tpass" in (await _read("modules/zz_target.gd")), all)
	var spaces := await _r({"cmd": "edit_replace", "path": "modules/zz_target.gd", "old": "    return \"\"", "new": "x"})
	_check("replace: spaces for tabs -> points at the line", not spaces.get("ok", true) and "line 4" in String(spaces.get("error", "")), spaces)
	_check("replace: same text refused", "same" in String((await _r({"cmd": "edit_replace", "path": "modules/zz_target.gd", "old": "a", "new": "a"})).get("error", "")))
	_check("replace: empty old refused", "exact text" in String((await _r({"cmd": "edit_replace", "path": "modules/zz_target.gd", "old": "", "new": "a"})).get("error", "")))

	# files.gd's rules still hold.
	await _r({"cmd": "files_write", "path": "notes/zz.txt", "text": "one\ntwo\n"})
	var lock := await _r({"cmd": "edit_replace", "path": "modules/agent_tuning.gd", "old": "x", "new": "y"})
	_check("agent_* files stay locked", not lock.get("ok", true), lock)
	var outside := await _r({"cmd": "edit_view", "path": "/sdcard/Download/x.txt"})
	_check("outside the folder refused", not outside.get("ok", true) and "files_read" in String(outside.get("error", "")), outside)
	_check("missing file says so", "can't read" in String((await _r({"cmd": "edit_view", "path": "notes/none.txt"})).get("error", "")))
	await _r({"cmd": "files_write", "path": "notes/crlf.txt", "text": "a\r\nb\r\n"})
	_check("\\r\\n files refused", "line endings" in String((await _r({"cmd": "edit_replace", "path": "notes/crlf.txt", "old": "a", "new": "b"})).get("error", "")))
	var note := await _r({"cmd": "edit_replace", "path": "notes/zz.txt", "old": "two", "new": "three"})
	_check("any text file in the folder", note.get("ok", false) and not note.has("next") and await _read("notes/zz.txt") == "one\nthree\n", note)

	# As the agent: its guard covers edit_* and the files_* they run.
	var agent = ctx["modules"].module("agent")
	if agent != null:
		var as_agent := await _r({"cmd": "edit_replace", "path": "notes/zz.txt", "old": "three", "new": "four"}, true)
		_check("works for the agent", as_agent.get("ok", false), as_agent)
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
