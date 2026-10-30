extends SlopitectModule
# Headless checks for memory.gd. Run: tests/run.sh memory lib zz_memory

var _fails := 0

func setup() -> String:
	_run.call_deferred()
	return ""

func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if not ok:
		_fails += 1

func _r(req: Dictionary) -> Dictionary:
	return ctx["server"].run(req)

func _agent(req: Dictionary) -> Dictionary:
	return ctx["server"].run_for_agent(req)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	await _frames(3)
	var mem = ctx["modules"].module("memory")
	_check("memory loaded", mem != null, _r({"cmd": "modules"}))
	if mem == null:
		get_tree().quit(1)
		return
	if OS.get_environment("PHASE") == "3":
		await _phase3(mem)
	elif OS.get_environment("PHASE") == "2":
		await _phase2(mem)
	else:
		await _phase1(mem)
	print("RESULT done, %d failed" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

func _phase1(mem) -> void:
	var st = _r({"cmd": "memory_status"})
	_check("status", st.ok and st.world == "default", st)
	_check("skill written", FileAccess.get_file_as_string("user://skills/slopitect-memory/SKILL.md").contains("memory_recall"))
	var agent = ctx["modules"].module("agent")
	agent.call("_load_skills")
	_check("agent sees the skill as always", agent.get("_skills").get("slopitect-memory", {}).get("always", false))

	# Agent may use memory_* but never memory_config.
	_check("agent can note", _agent({"cmd": "memory_note", "text": "Ground is 20x20 m; the pond is at [3, -4]"}).ok)
	_check("agent can't config", not _agent({"cmd": "memory_config", "capture": false}).ok)

	var r = _r({"cmd": "memory_note", "text": "ui panels: call ui_set_text, not rebuild, to avoid flicker", "kind": "technique", "tags": ["ui"]})
	_check("technique goes global", r.ok and r.id.begins_with("g") and r.world == "global", r)
	r = _r({"cmd": "memory_note", "text": "keep the bridge red", "kind": "decision", "global": false})
	_check("decision in world", r.ok and r.id.begins_with("w"), r)
	for bad in [{}, {"text": ""}, {"text": "x", "kind": "secret"}, {"text": "x", "tags": "ui"}, {"text": "x", "global": "yes"}, {"text": "x".repeat(601)}]:
		var q := {"cmd": "memory_note"}; q.merge(bad)
		_check("note refuses " + str(bad).left(40), not _r(q).ok)

	# Personal info and keys are cleaned out.
	var secrets := "my email is jo.smith@example.com, phone 555-123-4567, key sk-ant-api03-AbCdEf0123456789xyzXYZ, api_key=hunter2 password: swordfish on 192.168.1.95:5555 hash 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
	r = _r({"cmd": "memory_note", "text": secrets, "global": false})
	_check("note with secrets ok and says so", r.ok and r.has("note"), r)
	var saved: String = JSON.stringify(mem.get("_world"))
	for leak in ["jo.smith", "example.com", "555-123", "sk-ant", "AbCdEf0123", "hunter2", "swordfish", "192.168", "9f86d081"]:
		_check("cleaned " + leak, not saved.contains(leak), saved.left(600))
	_check("ordinary text kept", mem.call("_clean", "spawn a box at [0, 1.5, -2] with size 0.5, then paths_add", 300) == "spawn a box at [0, 1.5, -2] with size 0.5, then paths_add")

	# Exchanges from the agent's events.
	_check("new events after overlap", mem.call("_new_events", ["a", "b", "c"], ["b", "c", "d", "e"]) == ["d", "e"])
	_check("repeated events", mem.call("_new_events", ["x", "x"], ["x", "x", "x"]) == ["x"])
	_check("no overlap = all new", mem.call("_new_events", ["a"], ["q", "r"]) == ["q", "r"])
	_check("same = none", mem.call("_new_events", ["a", "b"], ["a", "b"]) == [])
	for e in ["you: build a bridge over the pond, my number is 555 123 4567", "thinking: secret thoughts", "tool spawn {\"shape\":\"box\"} -> ok",
			"tool spawn {} -> FAILED: {\"ok\":false,\"error\":\"unknown shape\"}", "tool memory_recall {} -> ok", "settings changed: {\"api_key\":\"(set)\"}", "agent: Built a bridge."]:
		mem.call("_record", e)
	mem.call("_close_exchange")
	var ex: Array = mem.get("_world")["exchanges"]
	_check("one exchange", ex.size() == 1, ex)
	if ex.size() == 1:
		_check("ask kept, number cleaned", ex[0].ask.begins_with("build a bridge") and not ex[0].ask.contains("4567"), ex[0])
		_check("reply kept", ex[0].reply == "Built a bridge.", ex[0])
		_check("tool counts", ex[0].tools.get("spawn") == [1, 1] and not ex[0].tools.has("memory_recall"), ex[0].tools)
		_check("error kept", ex[0].errors.size() == 1 and ex[0].errors[0].contains("unknown shape"), ex[0].errors)
		_check("no thinking or settings", not JSON.stringify(ex[0]).contains("secret thoughts") and not JSON.stringify(ex[0]).contains("api_key"))
	_check("tool stats", mem.get("_world")["tools"]["spawn"]["failed"] == 1, mem.get("_world")["tools"])

	# Overflow folds the oldest half into a digest.
	for i in 45:
		mem.call("_record", "you: question %d" % i)
		mem.call("_record", "tool move {} -> ok")
		mem.call("_record", "agent: answer %d" % i)
	mem.call("_close_exchange")
	var w: Dictionary = mem.get("_world")
	_check("exchanges bounded", w.exchanges.size() <= 40 and w.exchanges.size() >= 20, w.exchanges.size())
	_check("digest made", w.digests.size() == 1 and w.digests[0].exchanges == 20 and w.digests[0].tools.move[0] >= 19, w.digests)

	var rc = _r({"cmd": "memory_recall"})
	print("RECALL ", JSON.stringify(rc))
	_check("recall", rc.ok and rc.notes.size() == 4 and rc.recent.size() == 5 and rc.digests.size() == 1, rc)
	_check("recall size within budget", JSON.stringify(rc).length() < 5500, JSON.stringify(rc).length())
	_check("recall flags summary", rc.has("exchanges_need_a_summary"), rc)
	_check("failing tools listed", rc.tools_that_failed.size() == 1, rc.tools_that_failed)

	r = _r({"cmd": "memory_compact", "summary": "Built the bridge and asked many numbered questions; spawn fails on unknown shapes."})
	_check("compact", r.ok and r.exchanges >= 20, r)
	_check("compact emptied exchanges", mem.get("_world").exchanges.is_empty())
	r = _r({"cmd": "memory_compact", "digest": "d1", "summary": "early questions"})
	_check("summarise old digest", r.ok, r)
	_check("compact refuses bad digest", not _r({"cmd": "memory_compact", "digest": "d99", "summary": "x"}).ok)

	# Digests merge past their limit.
	for i in 35:
		mem.call("_add_digest", mem.get("_world"), {"from": i, "to": i, "exchanges": 1, "asks": ["a%d" % i], "tools": {"t": [1, 0]}, "errors": [], "summary": ""})
	_check("digests bounded", mem.get("_world").digests.size() == 30, mem.get("_world").digests.size())

	r = _r({"cmd": "memory_search", "query": "bridge"})
	_check("search finds", r.ok and r.results.size() >= 2, r)
	_check("search needs query", not _r({"cmd": "memory_search"}).ok)

	r = _r({"cmd": "memory_forget", "id": "w1"})
	_check("forget", r.ok, r)
	_check("forget again fails", not _r({"cmd": "memory_forget", "id": "w1"}).ok)
	_check("forget bad id", not _r({"cmd": "memory_forget", "id": "z1"}).ok)

	# Config (PC only) and capture off.
	_check("config refuses", not _r({"cmd": "memory_config", "recall_chars": 50}).ok)
	_check("capture off", _r({"cmd": "memory_config", "capture": false}).capture == false)
	mem.call("_record", "you: this should not be kept")
	mem.call("_close_exchange")
	_check("nothing kept while off", mem.get("_world").exchanges.is_empty())
	_r({"cmd": "memory_config", "capture": true})

	# Saving: within the delay, and only the user:// folder.
	await get_tree().create_timer(5.5).timeout
	_check("world saved", FileAccess.file_exists("user://memory/worlds/default.json"))
	_check("global saved", FileAccess.file_exists("user://memory/global.json"))
	_check("no temp files", not FileAccess.file_exists("user://memory/global.json.writing"))
	print("SIZES ", _r({"cmd": "memory_status"}))

	# Worlds follow projects: a second world.
	var f := FileAccess.open("user://projects.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"current": "castle"}))
	f.close()
	mem.set("_world_name", "default")  # projects isn't loaded in this test; stand in for it
	var orig = mem.call("_current_world")
	_check("without projects.gd it's default", orig == "default")

func _phase2(mem) -> void:
	var rc = _r({"cmd": "memory_recall"})
	print("RECALL2 ", JSON.stringify(rc))
	_check("notes kept over a restart", rc.ok and rc.notes.size() == 3, rc.notes)
	_check("digests kept", rc.digests.size() == 5, rc.digests.size())
	_check("capture setting kept", _r({"cmd": "memory_status"}).capture == true)
	_check("next id continues", _r({"cmd": "memory_note", "text": "after restart", "global": false}).id == "w4")
	# A broken file is set aside, not overwritten.
	var f := FileAccess.open("user://memory/worlds/broken.json", FileAccess.WRITE)
	f.store_string("{nope")
	f.close()
	var s = mem.call("_read_scope", "user://memory/worlds/broken.json")
	_check("broken file set aside", s.notes.is_empty() and FileAccess.file_exists("user://memory/worlds/broken.json.bad"))
	_check("search everywhere", _r({"cmd": "memory_search", "query": "pond", "everywhere": true}).ok)
	_check("recall other world refuses unknown", not _r({"cmd": "memory_recall", "world": "nowhere"}).ok)
	_check("clear", _r({"cmd": "memory_config", "clear": "global"}).ok)
	_check("global cleared", mem.get("_global").notes.is_empty())
	_r({"cmd": "code_unload", "name": "memory"})
	await _frames(2)
	_check("unload removes skill", not FileAccess.file_exists("user://skills/slopitect-memory/SKILL.md"))

func _phase3(mem) -> void:
	await _frames(5)
	_check("start world", _r({"cmd": "memory_status"}).world == "start", _r({"cmd": "memory_status"}))
	_r({"cmd": "memory_note", "text": "start note", "global": false})
	mem.call("_record", "you: in start")
	var r = _r({"cmd": "projects_new", "name": "castle", "open": true})
	_check("castle opened", r.ok, r)
	mem.call("_record", "agent: still answering in start")
	mem.call("_record", "you: in castle")
	mem.call("_close_exchange")
	_check("world follows project", _r({"cmd": "memory_status"}).world == "castle")
	_r({"cmd": "memory_note", "text": "castle note", "global": false})
	var rc = _r({"cmd": "memory_recall"})
	_check("castle recall has only castle", rc.notes.size() == 1 and rc.notes[0].contains("castle note") and rc.recent.size() == 1 and rc.recent[0].contains("in castle"), rc)
	rc = _r({"cmd": "memory_recall", "world": "start"})
	_check("start recall from castle", rc.ok and rc.notes[0].contains("start note") and rc.recent[0].contains("still answering in start"), rc)
