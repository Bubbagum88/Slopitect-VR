extends SlopitectModule

# AI message handling: watches agent_status and voice_status.
# Drives the avatar (thinking while the agent works, talking while it
# speaks, reply in the speech bubble) and rewrites the chat log with
# clean formatting: role tags, word wrap, markdown stripped, code marked.

const POLL := 0.4
const PAD := "     "
const OLD_SOURCE := {"chars": 600, "cmd": "agent_status", "empty": "agent ready. type below and press Send.", "field": "events", "last": 3}

var cols := 38
var rows := 16
var speak := false
var bubble := true
var enabled := true

var _t := 0.0
var _lines: Array = []
var _last_key := ""
var _first := true
var _busy := false
var _speaking := false
var _talk_t := 0.0
var _happy_t := 0.0
var _cur := ""
var _err := ""
var _dumped := false
var _replies := 0


func setup() -> String:
	register("aimsg_status", _do_status, "AI message handling: busy, speaking, avatar state, settings, last error")
	register("aimsg_set", _do_set, "AI message settings: any of cols (20-80), rows (4-40), speak (true: read replies aloud yourself), bubble (true/false), enabled (true/false)")
	register("aimsg_clear", _do_clear, "clear the formatted chat log")
	return ""


func _exit_tree() -> void:
	_restore_log()
	_avatar("idle")


func _run(c: Dictionary):
	var r = ctx["server"].run(c)
	return r if r is Dictionary else {}


func _restore_log() -> void:
	_run({"cmd": "ui_element_update", "id_panel": "chat", "id_element": "log", "source": OLD_SOURCE, "text": ""})


func _avatar(s: String) -> void:
	if s == _cur:
		return
	_cur = s
	_run({"cmd": "avatar_state", "state": s})


func _process(delta: float) -> void:
	if not enabled:
		return
	if _talk_t > 0.0:
		_talk_t -= delta
		if _talk_t <= 0.0 and not _speaking:
			_happy_t = 2.0
	if _happy_t > 0.0:
		_happy_t -= delta
	_t += delta
	if _t >= POLL:
		_t = 0.0
		_poll()
	var want := "idle"
	if _speaking or _talk_t > 0.0:
		want = "talking"
	elif _happy_t > 0.0:
		want = "happy"
	elif _busy:
		want = "thinking"
	_avatar(want)


func _poll() -> void:
	var r = _run({"cmd": "agent_status"})
	if not r.get("ok", false):
		_err = "agent_status: " + str(r.get("error", "no reply"))
		return
	if not _dumped:
		_dumped = true
		var ev0 = r.get("events")
		var sample = ev0.slice(max(0, ev0.size() - 3)) if ev0 is Array else ev0
		_run({"cmd": "files_write", "path": "aimsg_debug.json", "text": JSON.stringify({"keys": r.keys(), "status_line": r.get("status_line", ""), "events_sample": sample}, "\t")})
	_busy = _is_busy(r)
	var ev = r.get("events")
	if ev is Array:
		_take(ev)
	var v = _run({"cmd": "voice_status"})
	var spk := bool(v.get("speaking", false))
	if _speaking and not spk and _talk_t <= 0.0:
		_happy_t = 2.0
	_speaking = spk


func _is_busy(r: Dictionary) -> bool:
	for k in ["busy", "running", "thinking", "working"]:
		if r.has(k):
			return bool(r[k])
	if r.has("state"):
		var s := str(r["state"]).to_lower()
		return not (s in ["idle", "ready", "done", "stopped", ""])
	var line := str(r.get("status_line", "")).to_lower()
	for w in ["thinking", "working", "running", "calling", "waiting for"]:
		if w in line:
			return true
	return false


func _take(ev: Array) -> void:
	var keys: Array = []
	for e in ev:
		keys.append(e if e is String else JSON.stringify(e))
	var start := 0
	if _last_key != "":
		var i := keys.rfind(_last_key)
		start = i + 1 if i >= 0 else 0
	var changed := false
	for j in range(start, keys.size()):
		_add(ev[j], not _first)
		changed = true
	if keys.size() > 0:
		_last_key = keys[keys.size() - 1]
	if changed or _first:
		_render()
	_first = false


func _role(s: String) -> String:
	s = s.to_lower()
	if "err" in s or "fail" in s:
		return "err"
	if "user" in s or "person" in s or "human" in s or s == "you" or "prompt" in s or "ask" in s:
		return "you"
	if "tool" in s or "cmd" in s or "call" in s or "result" in s:
		return "tool"
	if "status" in s or "system" in s or "info" in s or "note" in s:
		return "sys"
	return "ai"


func _add(e, live: bool) -> void:
	var role := "ai"
	var text := ""
	if e is Dictionary:
		var found := false
		for k in ["role", "kind", "type", "who", "from", "source"]:
			if e.has(k):
				role = _role(str(e[k]))
				found = true
				break
		if not found and (e.has("cmd") or e.has("tool")):
			role = "tool"
		for k in ["text", "message", "content", "reply", "line", "summary", "cmd", "tool"]:
			if e.has(k) and str(e[k]) != "":
				text = str(e[k])
				break
		if text == "":
			text = JSON.stringify(e)
	else:
		text = str(e)
		var low := text.to_lower()
		for p in [["you: ", "you"], ["you> ", "you"], ["user: ", "you"], ["> ", "you"], ["agent: ", "ai"], ["ai: ", "ai"], ["error: ", "err"], ["tool: ", "tool"], ["-> ", "tool"]]:
			if low.begins_with(p[0]):
				role = p[1]
				text = text.substr(p[0].length())
				break
	_lines.append_array(_format(role, text))
	if _lines.size() > 300:
		_lines = _lines.slice(_lines.size() - 300)
	if live and role == "ai":
		_replies += 1
		var plain := _plain(text)
		if bubble:
			_run({"cmd": "avatar_say", "text": plain.substr(0, 160) + ("..." if plain.length() > 160 else "")})
		_talk_t = clampf(plain.length() * 0.06, 2.0, 12.0)
		if speak and not _speaking:
			_run({"cmd": "voice_say", "text": plain.substr(0, 400)})


func _clean(l: String) -> String:
	l = l.replace("**", "").replace("__", "").replace("`", "")
	var s := l.strip_edges()
	while s.begins_with("#"):
		s = s.substr(1)
	if s.length() != l.strip_edges().length():
		l = s.strip_edges().to_upper()
	return l


func _plain(text: String) -> String:
	var out := ""
	for raw in text.split("\n"):
		var l := _clean(raw).strip_edges()
		if l.begins_with("```") or l == "":
			continue
		out += (" " if out != "" else "") + l
	return out


func _wrap(s: String, w: int) -> Array:
	var out: Array = []
	var cur := ""
	for word in s.split(" ", false):
		while word.length() > w:
			if cur != "":
				out.append(cur)
				cur = ""
			out.append(word.substr(0, w))
			word = word.substr(w)
		if cur == "":
			cur = word
		elif cur.length() + 1 + word.length() <= w:
			cur += " " + word
		else:
			out.append(cur)
			cur = word
	if cur != "":
		out.append(cur)
	return out


func _format(role: String, text: String) -> Array:
	var tag: String = {"you": "you> ", "ai": "ai>  ", "tool": "   + ", "err": "!!   ", "sys": "   - "}[role]
	var w := cols - PAD.length()
	var out: Array = []
	if role == "tool" or role == "sys":
		var one := _plain(text)
		if one.length() > w:
			one = one.substr(0, w - 3) + "..."
		return [tag + one]
	var code := false
	var first := true
	for raw in text.split("\n"):
		var t := raw.strip_edges(false, true)
		if t.strip_edges().begins_with("```"):
			code = not code
			continue
		var pre := tag if first else PAD
		if code:
			out.append(pre + "| " + t.substr(0, w - 2))
			first = false
			continue
		t = _clean(t).strip_edges()
		if t == "":
			if out.size() > 0 and out[out.size() - 1] != "":
				out.append("")
			continue
		var cont := PAD
		if t.begins_with("- ") or t.begins_with("* ") or t.begins_with("• "):
			t = "- " + t.substr(2)
			cont = PAD + "  "
		var parts := _wrap(t, w)
		for i in parts.size():
			out.append((pre if i == 0 else cont) + parts[i])
		first = false
	while out.size() > 0 and out[out.size() - 1] == "":
		out.pop_back()
	if role == "ai" or role == "err":
		out.append("")
	return out


func _render() -> void:
	var show := _lines.slice(max(0, _lines.size() - rows))
	var txt := "\n".join(PackedStringArray(show))
	if txt.strip_edges() == "":
		txt = "agent ready. type below and press Send."
	var r = _run({"cmd": "ui_element_update", "id_panel": "chat", "id_element": "log", "source": null, "text": txt})
	if not r.get("ok", false):
		_err = "ui_element_update: " + str(r.get("error", "no reply"))


func _do_status(_r: Dictionary) -> Dictionary:
	return {"ok": true, "enabled": enabled, "busy": _busy, "speaking": _speaking, "avatar": _cur, "replies": _replies, "lines": _lines.size(), "cols": cols, "rows": rows, "speak": speak, "bubble": bubble, "error": _err}


func _do_set(r: Dictionary) -> Dictionary:
	if r.has("cols"):
		cols = clampi(int(r["cols"]), 20, 80)
	if r.has("rows"):
		rows = clampi(int(r["rows"]), 4, 40)
	if r.has("speak"):
		speak = bool(r["speak"])
	if r.has("bubble"):
		bubble = bool(r["bubble"])
	if r.has("enabled"):
		enabled = bool(r["enabled"])
		if enabled:
			_render()
		else:
			_restore_log()
			_avatar("idle")
	elif r.has("cols") or r.has("rows"):
		_render()
	return _do_status({})


func _do_clear(_r: Dictionary) -> Dictionary:
	_lines.clear()
	_render()
	return {"ok": true}
