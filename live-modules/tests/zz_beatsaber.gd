extends SlopitectModule
# Headless checks for beatsaber.gd (Rhythm Sabers). Run: tests/run.sh lib vrui save projects beatsaber zz_beatsaber
# Real swings: the test moves the right controller through the notes of a
# small song it writes to songs/zz_test (no music), at a steady 60 frames a
# second, and checks a good cut, a miss, a wrong-colour cut, a bomb and a
# wrong-way cut, then the results.
var _fails := 0
var _passes := 0
var _beat
var _signals := []


func setup() -> String:
	_go.call_deferred()
	return ""


func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if ok: _passes += 1
	else: _fails += 1


func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


func _go() -> void:
	Engine.max_fps = 60
	await _frames(5)
	_beat = ctx["modules"].module("beatsaber")
	var lib = ctx["modules"].module("lib")
	_check("loaded and idle", _beat != null and not _beat.is_processing())
	var right: Node3D = ctx["right"]
	var saber := right.get_node_or_null("beatsaber_right") as Node3D
	_check("sabers ride on the controllers", saber != null and saber.visible and ctx["left"].has_node("beatsaber_left"))
	var labels_ok := true
	for s in _beat.settings_info()["settings"]:
		if s.has("label") and s["label"].length() > 40:
			labels_ok = false
	_check("settings labels 40 characters or less", labels_ok)
	_check("a Menu tile", _beat.menu_info().get("label") == "Rhythm")

	# Settings
	_check("bad setting refused", not _run({"cmd": "beatsaber_set", "speed": 99}).get("ok", true))
	_check("setting changes and is kept", _run({"cmd": "beatsaber_set", "speed": 4.0, "difficulty": "hard"}).get("ok", false)
		and lib.read_json("user://beatsaber.json").get("game", {}).get("speed") == 4.0)

	# Made notes follow the swing flow
	var notes: Array = _beat._generate(120.0, 200, "hard", 5)
	_check("made notes are repeatable", JSON.stringify(notes) == JSON.stringify(_beat._generate(120.0, 200, "hard", 5)))
	var flow_ok := true
	var down := {"l": true, "r": true}
	var bombs := 0
	for n in notes:
		if n[3] == "b":
			bombs += 1
			continue
		var d: String = n[4]
		if d != "a" and d.begins_with("d") != down[n[3]]:
			flow_ok = false
		if (n[3] == "l" and n[1] > 1) or (n[3] == "r" and n[1] < 2 and not _double(notes, n)):
			flow_ok = false
		down[n[3]] = not down[n[3]]
	_check("each hand alternates down and up, on its own side", flow_ok)
	_check("hard has bombs", bombs > 0, bombs)

	# Free play starts and stops
	var before: int = _beat.get_node("track").get_child_count()
	_beat.started.connect(func(t): _signals.append("started " + t))
	_beat.stopped.connect(func(): _signals.append("stopped"))
	_beat.finished.connect(func(r): _signals.append("finished"))
	var reply := _run({"cmd": "beatsaber_start", "song": "free"})
	_check("free play starts", reply.get("ok", false) and _beat.running and _beat.is_processing() and reply.get("notes", 0) > 50, reply)
	await get_tree().create_timer(1.0).timeout
	_run({"cmd": "beatsaber_stop"})
	await _frames(3)
	_check("stop: idle, signals", not _beat.running and not _beat.is_processing() and _signals == ["started Free play", "stopped"], _signals)

	# Its own world: made on the first start, left with Leave, reused after
	_check("starting took us to the Rhythm world", _world() == "rhythm_sabers", _world())
	reply = _run({"cmd": "beatsaber_leave"})
	_check("Leave goes back to where we were", reply.get("ok", false) and _world() == "start", [reply, _world()])
	_check("the tile takes us back in", _run({"cmd": "beatsaber_do", "act": "toggle"}).get("ok", false) and _world() == "rhythm_sabers")
	_check("one Rhythm world, not one per visit", _run({"cmd": "projects_list"})["projects"].filter(func(p): return p["name"] == "rhythm_sabers").size() == 1)
	_run({"cmd": "beatsaber_start", "song": "free"})
	await _frames(3)
	_run({"cmd": "projects_open", "name": "start"})
	await _frames(3)
	_check("going to another world stops the song", not _beat.running and not _beat.is_processing())
	_run({"cmd": "beatsaber_do", "act": "enter"})
	_signals.clear()

	# A song of our own
	var folder: String = lib.home() + "/songs/zz_test"
	DirAccess.make_dir_recursive_absolute(folder)
	lib.write_json(folder + "/map.json", {"title": "Test", "bpm": 120, "notes": [
		[1, 1, 1, "r", "d"], [3, 1, 1, "r", "a"], [5, 1, 1, "l", "u"], [7, 1, 1, "b", "a"], [9, 1, 1, "r", "u"]]})
	var songs: Array = _run({"cmd": "beatsaber_songs"}).get("songs", [])
	_check("songs/ is listed", songs.size() == 1 and songs[0]["title"] == "Test" and not songs[0]["made"], songs)
	_check("a bad map is refused", not _run({"cmd": "beatsaber_start", "song": "../x"}).get("ok", true))
	_check("window opens", _run({"cmd": "beatsaber_do", "act": "show"}).get("ok", false))
	_signals.clear()
	right.global_transform = Transform3D(Basis.IDENTITY, Vector3(30, 30, 0))
	_run({"cmd": "beatsaber_config", "angle": 0.0, "grip": [0, 0, 0], "hold": 0.0})
	reply = _run({"cmd": "beatsaber_start", "song": "zz_test"})
	_check("song starts", reply.get("ok", false) and reply.get("notes") == 5, reply)

	await _cut_at(0, -0.4)  # down, through the middle: a good cut
	_check("good cut scores", _beat.cuts == 1 and _beat.combo == 1 and _beat.score > 0, _beat._score({}))
	var first_points: int = _beat._last.get("last_points", 0)
	_check("down swing through the centre scores high", first_points >= 60, _beat._last)
	_check("swing size from the swing, not the jump to it", _beat._last.get("last_swing_cm", 0) <= 100, _beat._last)
	await _wait_until(_beat._song["notes"][1], -0.6)  # leave the next one go by
	_check("a missed note ends the combo", _beat.missed == 1 and _beat.combo == 0)
	await _cut_at(2, -0.4)  # blue note with the red saber
	_check("wrong saber is a bad cut", _beat.bad == 1 and _beat.cuts == 1, _beat._score({}))
	await _cut_at(3, -0.4)  # bomb
	_check("bomb hit counted", _beat.bombs_hit == 1, _beat._score({}))
	await _cut_at(4, -0.4)  # an up arrow cut down
	_check("wrong way is a bad cut", _beat.bad == 2 and _beat.cuts == 1, _beat._score({}))
	for i in 120:
		if not _beat.running:
			break
		await _frames(1)
	var results: Dictionary = _beat._results
	_check("song ends with results", not _beat.running and results.get("score") == _beat.score and results.get("rank") == "F" and results.get("new_best"), results)
	_check("finished and stopped signals", _signals == ["started Test", "finished", "stopped"], _signals)
	_check("songs play in the Rhythm world", _world() == "rhythm_sabers")
	_check("best score kept", lib.read_json("user://beatsaber.json").get("best", {}).get("zz_test") == _beat.score)
	await _frames(60)
	_check("idle again after the effects", not _beat.is_processing())
	_check("pools: nothing new made", _beat.get_node("track").get_child_count() == before, [before, _beat.get_node("track").get_child_count()])

	# A song with music and no notes gets notes made for it
	var music: String = lib.home() + "/songs/zz_music"
	DirAccess.make_dir_recursive_absolute(music)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 8000
	var pcm := PackedByteArray()
	pcm.resize(8000 * 2 * 20)
	wav.data = pcm
	wav.save_to_wav(music + "/song.wav")
	lib.write_json(music + "/map.json", {"title": "Music", "bpm": 90})
	reply = _run({"cmd": "beatsaber_start", "song": "zz_music", "difficulty": "easy"})
	_check("music read, notes made for it", reply.get("ok", false) and reply.get("notes", 0) > 5 and _beat._song["audio"] is AudioStreamWAV, reply)
	await get_tree().create_timer(0.5).timeout
	_run({"cmd": "beatsaber_stop"})
	_check("made songs are marked", _run({"cmd": "beatsaber_songs"})["songs"].filter(func(x): return x["folder"] == "zz_music")[0]["made"])

	_check("Leave after the songs", _run({"cmd": "beatsaber_leave"}).get("back_in") == "start" and _world() == "start")

	# Hands' Sabers choice hides them
	var s := GDScript.new()
	s.source_code = "extends SlopitectModule\nvar shown := false\nfunc sabers_shown() -> bool:\n\treturn shown\n"
	s.reload()
	ctx["modules"].load_live("hands", s)
	await _frames(3)
	_check("hands chosen: sabers hidden", not saber.visible)
	var hands = ctx["modules"].module("hands")
	hands.shown = true
	lib.touch(hands)
	_check("sabers chosen: shown", saber.visible)

	ctx["modules"].unload("beatsaber")
	await _frames(3)
	_check("unload takes the sabers and window", not is_instance_valid(saber) and not _run({"cmd": "ui_get", "id_panel": "beatsaber"}).get("ok", true))
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


func _world() -> String:
	return _run({"cmd": "projects_current"}).get("name", "")


func _double(notes: Array, n: Array) -> bool:
	for m in notes:
		if m != n and m[0] == n[0] and m[3] != "b":
			return true
	return false


func _track_to_world(p: Vector3) -> Vector3:
	return _beat.track_transform() * p


func _wait_until(note: Array, before: float) -> void:
	var t: float = _beat._beat_time(note[0])
	while _beat.running and _beat._clock < t - before:
		await _frames(1)


# Swings the right saber down through note i's lane, from above to below,
# over 6 frames, timed so the note is at the blade then.
func _cut_at(i: int, controller_z: float) -> void:
	var note: Array = _beat._song["notes"][i]
	await _wait_until(note, 0.05)
	var pos: Vector3 = _beat._note_pos(note)
	var right: Node3D = ctx["right"]
	for k in 7:
		var y := pos.y + 0.45 - 0.9 * k / 6.0
		right.global_transform = Transform3D(_beat.track_transform().basis, _track_to_world(Vector3(pos.x, y, controller_z)))
		await _frames(1)
	right.global_transform = Transform3D(Basis.IDENTITY, _track_to_world(Vector3(3, pos.y - 0.45, controller_z)))
	await _frames(1)
	right.global_transform = Transform3D(Basis.IDENTITY, Vector3(30, 30, 0))
	await _frames(1)
