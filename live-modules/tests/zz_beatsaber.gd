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
# A stand-in net module: fetch() keeps to "allowed" and hands back the
# list or the zip the test set, so nothing goes online.
const FAKE_NET := """extends SlopitectModule
var allow := false
var urls := []
var list := {}
var zip_from := ""
func setup() -> String:
	return ""
func fetch(url: String, path: String, max_bytes: int = 0) -> String:
	await get_tree().process_frame
	urls.append(url)
	if not allow:
		return "refused " + url + ": only https from the allowed hosts"
	if "/search/text/" in url:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(list))
		f.close()
		return ""
	if url.ends_with(".zip"):
		DirAccess.copy_absolute(zip_from, path)
		return ""
	return "no such file"
"""

const FAKE_HANDS := """extends SlopitectModule
var settings := {"style": "hand"}
func setup() -> String:
	register("hands_style", _style, "style")
	return ""
func _style(r: Dictionary) -> Dictionary:
	settings["style"] = r["style"]
	ctx["modules"].module("lib").touch(self)
	return {"ok": true}
func sabers_shown() -> bool:
	return settings["style"] == "saber"
"""


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
	# A stand-in hands module: its style, hands_style, and sabers_shown().
	var hs := GDScript.new()
	hs.source_code = FAKE_HANDS
	hs.reload()
	ctx["modules"].load_live("hands", hs)
	await _frames(3)
	var hands = ctx["modules"].module("hands")
	_check("hands chosen outside the game: sabers hidden", not saber.visible)
	var cut_sound = _beat._hit_player.stream
	var sound_ok: bool = cut_sound is AudioStreamRandomizer and cut_sound.streams_count == 3
	for take in (cut_sound.streams_count if sound_ok else 0):
		var w: AudioStreamWAV = cut_sound.get_stream(take)
		var loudest := 0
		for i in range(0, w.data.size(), 2):
			loudest = maxi(loudest, absi(w.data.decode_s16(i)))
		sound_ok = sound_ok and absf(w.get_length() - _beat.SLICE_SECONDS) < 0.01 and loudest > 12000 and loudest <= 32000
	_check("cut sound: three takes, full but not clipping", sound_ok)
	var fly_ok: bool = is_equal_approx(_beat._track_z(_beat._ahead()), _beat.SPAWN_Z) and is_equal_approx(_beat._track_z(_beat._lead()), _beat.SPAWN_Z + _beat.FLY_FROM)
	var last_z: float = _beat._track_z(_beat._lead())
	for i in range(1, 41):
		var z: float = _beat._track_z(_beat._lead() - _beat.FLY_TIME * i / 40.0)
		fly_ok = fly_ok and z > last_z
		last_z = z
	var join_speed: float = (_beat._track_z(_beat._ahead()) - _beat._track_z(_beat._ahead() + 0.01)) / 0.01
	_check("notes fly in fast and join the track at note speed", fly_ok and absf(join_speed - float(_beat.game["speed"])) < 0.5, join_speed)
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
	# Diagonal notes are the whole cube turned on its corner
	var seg := {"pbase": Vector3(0.17, 0.17, 0.5), "ptip": Vector3(0.17, 0.17, -0.5), "base": Vector3(0.17, 0.17, 0.5), "tip": Vector3(0.17, 0.17, -0.5)}
	_check("a turned cube is hit by its own shape", _beat._swept_hit(seg, Vector3.ZERO, 0.0, 0.0) and not _beat._swept_hit(seg, Vector3.ZERO, 0.0, PI / 4.0))

	# Free play starts and stops
	var before: int = _beat.get_node("track").get_child_count()
	_beat.started.connect(func(t): _signals.append("started " + t))
	_beat.stopped.connect(func(): _signals.append("stopped"))
	_beat.finished.connect(func(r): _signals.append("finished"))
	var sky_env: Environment = ctx["world"].get_parent().get_node("WorldEnvironment").environment
	var sun_energy: float = ctx["world"].get_parent().get_node("Sun").light_energy
	var reply := _run({"cmd": "beatsaber_start", "song": "free"})
	_check("free play starts", reply.get("ok", false) and _beat.running and _beat.is_processing() and reply.get("notes", 0) > 50, reply)
	await get_tree().create_timer(1.0).timeout
	_run({"cmd": "beatsaber_stop"})
	await _frames(3)
	_check("stop: idle, signals", not _beat.running and not _beat.is_processing() and _signals == ["started Free play", "stopped"], _signals)

	# Its own world: made on the first start, left with Leave, reused after
	_check("starting took us to the Rhythm world", _world() == "rhythm_sabers", _world())
	_check("in the game: sabers, automatically", hands.settings["style"] == "saber" and saber.visible)
	var scene: Node = ctx["world"].get_parent()
	var env_node: WorldEnvironment = scene.get_node("WorldEnvironment")
	var sun: DirectionalLight3D = scene.get_node("Sun")
	var main_floor: Node3D = scene.get_node("Floor")
	_check("the Rhythm world's own surroundings", _beat._stage != null and env_node.environment != sky_env
		and env_node.environment.background_mode == Environment.BG_COLOR and not main_floor.visible and sun.light_energy < sun_energy,
		[_beat._stage, env_node.environment, main_floor.visible, sun.light_energy])
	_check("its stage lies with the track", _beat._stage.global_transform.is_equal_approx(_beat.track_transform()))
	_check("haze and the sign over the windows", env_node.environment.fog_enabled and _beat._sign != null and _beat._sign.visible == _beat._shown("beatsaber"),
		[env_node.environment.fog_enabled, _beat._sign])
	reply = _run({"cmd": "beatsaber_leave"})
	_check("Leave goes back to where we were", reply.get("ok", false) and _world() == "start", [reply, _world()])
	_check("out of the game: hands back", hands.settings["style"] == "hand" and not saber.visible)
	_check("outside it the sky, sun and floor come back", _beat._stage == null and env_node.environment == sky_env and main_floor.visible
		and is_equal_approx(sun.light_energy, sun_energy))
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
	lib.write_json(folder + "/map.json", {"title": "Test", "pack": "Tests", "bpm": 120, "notes": [
		[1, 1, 1, "r", "d"], [3, 1, 1, "r", "a"], [5, 1, 1, "l", "u"], [7, 1, 1, "b", "a"], [9, 1, 1, "r", "u"]]})
	var songs: Array = _run({"cmd": "beatsaber_songs"}).get("songs", [])
	_check("songs/ is listed", songs.size() == 1 and songs[0]["title"] == "Test" and not songs[0]["made"], songs)
	_check("a bad map is refused", not _run({"cmd": "beatsaber_start", "song": "../x"}).get("ok", true))
	_check("windows open", _run({"cmd": "beatsaber_do", "act": "show"}).get("ok", false))
	var left: Dictionary = _run({"cmd": "ui_get", "id_panel": "rhythm_left"}).get("panel", {})
	var right_win: Dictionary = _run({"cmd": "ui_get", "id_panel": "rhythm_scores"}).get("panel", {})
	_check("three windows: settings left, songs middle, scores right", left.get("pages") == ["Modifiers", "Colours", "Settings"]
		and right_win.get("pages") == ["Local", "Global"] and left.get("visible") and right_win.get("visible")
		and (_beat.track_transform().affine_inverse() * Vector3(left["position"][0], left["position"][1], left["position"][2])).x < -0.5, [left.get("pages"), left.get("position")])
	_check("packs list has the song's album", _beat._packs() == ["Tests", "All songs", "Free play"], _beat._packs())
	_check("choosing a song shows it", _run({"cmd": "beatsaber_do", "act": "select", "song": "zz_test"}).get("ok", false)
		and _element("beatsaber", "song_title").get("text") == "Test")
	_check("Settings tab: slider changes the speed", _run({"cmd": "beatsaber_do", "act": "show", "page": "Settings"}).get("ok", false)
		and _run({"cmd": "ui_slide", "id_panel": "rhythm_left", "id_element": "speed", "value": 5.0}).get("ok", false) and _beat.game["speed"] == 5.0, _beat.game)
	_check("its toggle switches trails", _run({"cmd": "ui_press", "id_panel": "rhythm_left", "id_element": "trails"}).get("ok", false) and _beat.game["trails"] == false, _beat.game)
	_check("the tab stays after a change", _run({"cmd": "ui_get", "id_panel": "rhythm_left"})["panel"].get("page") == "Settings")
	_run({"cmd": "beatsaber_set", "speed": 4.0, "trails": true})
	_signals.clear()
	right.global_transform = Transform3D(Basis.IDENTITY, Vector3(30, 30, 0))
	_run({"cmd": "beatsaber_config", "angle": 0.0, "grip": [0, 0, 0], "hold": 0.0})
	reply = _run({"cmd": "beatsaber_do", "act": "play"})
	_check("Play starts the chosen song", reply.get("ok", false) and reply.get("notes") == 5, reply)
	_check("windows step aside while it plays", not _run({"cmd": "ui_get", "id_panel": "beatsaber"})["panel"]["visible"] and not _beat._sign.visible)

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
	_check("windows back with the score", _run({"cmd": "ui_get", "id_panel": "beatsaber"})["panel"]["visible"] and _beat._sign.visible
		and _element("rhythm_scores", "local_0").get("text", "").contains(str(_beat.score)), _element("rhythm_scores", "local_0"))
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

	# Custom song folders: Info.dat version 2 with v2 and v3 difficulty files,
	# and version 4 with a v4 file; music named in Info.dat.
	var custom := {
		"zz_v2": {"Info.dat": {"_version": "2.0.0", "_songName": "Two", "_songAuthorName": "Artist", "_levelAuthorName": "Mapper",
			"_beatsPerMinute": 120, "_songTimeOffset": 0, "_songFilename": "music.wav", "_coverImageFilename": "cover.jpg",
			"_difficultyBeatmapSets": [
				{"_beatmapCharacteristicName": "Standard", "_difficultyBeatmaps": [
					{"_difficulty": "Easy", "_beatmapFilename": "Easy.dat"}, {"_difficulty": "ExpertPlus", "_beatmapFilename": "ExpertPlus.dat"}]},
				{"_beatmapCharacteristicName": "OneSaber", "_difficultyBeatmaps": [{"_difficulty": "Expert", "_beatmapFilename": "One.dat"}]},
				{"_beatmapCharacteristicName": "Lightshow", "_difficultyBeatmaps": [{"_difficulty": "Easy", "_beatmapFilename": "Easy.dat"}]}]},
			"Easy.dat": {"_version": "2.0.0", "_notes": [
				{"_time": 2, "_lineIndex": 1, "_lineLayer": 0, "_type": 0, "_cutDirection": 6},
				{"_time": 3, "_lineIndex": 2, "_lineLayer": 1, "_type": 1, "_cutDirection": 1},
				{"_time": 4, "_lineIndex": 0, "_lineLayer": 2, "_type": 3, "_cutDirection": 0},
				{"_time": 5, "_lineIndex": 5, "_lineLayer": 0, "_type": 1, "_cutDirection": 1}],
				"_obstacles": [{"_time": 3, "_lineIndex": 0, "_type": 1, "_duration": 2, "_width": 4}], "_events": []},
			"ExpertPlus.dat": {"_version": "2.0.0", "_notes": [{"_time": 2, "_lineIndex": 3, "_lineLayer": 0, "_type": 1, "_cutDirection": 8}]},
			"One.dat": {"version": "3.0.0", "colorNotes": [{"b": 2, "x": 1, "y": 1, "c": 1, "d": 7}, {"b": 3, "x": 2, "y": 0, "c": 1, "d": 0}],
				"bombNotes": [{"b": 4, "x": 3, "y": 2}],
				"obstacles": [{"b": 2, "x": 0, "y": 0, "d": 1, "w": 1, "h": 5}, {"b": 3, "x": 0, "y": 0, "d": -1, "w": 1, "h": 5}],
				"sliders": [{"c": 1, "b": 2, "x": 1, "y": 1, "d": 7, "mu": 1, "tb": 3, "tx": 2, "ty": 0, "tc": 0, "tmu": 1, "m": 0}]}},
		"zz_v4": {"Info.dat": {"version": "4.0.0", "song": {"title": "Four", "author": "Band"}, "audio": {"songFilename": "music.wav", "bpm": 150},
			"coverImageFilename": "cover.png", "difficultyBeatmaps": [{"characteristic": "Standard", "difficulty": "Normal",
				"beatmapAuthors": {"mappers": ["Four mapper"]}, "beatmapDataFilename": "Normal.dat"}]},
			"Normal.dat": {"version": "4.0.0", "colorNotes": [{"b": 1, "i": 0}, {"b": 2, "i": 1}, {"b": 3, "i": 7}],
				"colorNotesData": [{"x": 0, "y": 0, "c": 0, "d": 4}, {"x": 3, "y": 1, "c": 1, "d": 3}],
				"bombNotes": [{"b": 4, "i": 0}], "bombNotesData": [{"x": 1, "y": 2}],
				"obstacles": [{"b": 2, "i": 0}], "obstaclesData": [{"d": 0.5, "x": 3, "y": 0, "w": 1, "h": 3}],
				"arcs": [{"hb": 1, "tb": 2, "hi": 0, "ti": 1, "ai": 0}], "arcsData": [{"m": 1.5, "tm": 0.5, "a": 0}]}},
		"zz_nomusic": {"Info.dat": {"_songName": "Silent", "_beatsPerMinute": 100, "_songFilename": "gone.egg",
			"_difficultyBeatmapSets": [{"_beatmapCharacteristicName": "Standard", "_difficultyBeatmaps": [{"_difficulty": "Hard", "_beatmapFilename": "Hard.dat"}]}]},
			"Hard.dat": {"_notes": [{"_time": 1, "_lineIndex": 0, "_lineLayer": 0, "_type": 0, "_cutDirection": 1}]}}}
	for song_dir in custom:
		var path: String = lib.home() + "/songs/" + song_dir
		DirAccess.make_dir_recursive_absolute(path)
		for file in custom[song_dir]:
			lib.write_json(path + "/" + file, custom[song_dir][file])
		if song_dir != "zz_nomusic":
			wav.save_to_wav(path + "/music.wav")
	var listed: Array = _run({"cmd": "beatsaber_songs"})["songs"].map(func(x): return x["folder"])
	_check("custom songs listed", "zz_v2" in listed and "zz_v4" in listed and "zz_nomusic" in listed, listed)
	_check("Custom songs pack", "Custom songs" in _beat._packs(), _beat._packs())
	_run({"cmd": "beatsaber_set", "difficulty": "normal"})
	_run({"cmd": "beatsaber_do", "act": "show"})
	_check("choosing a custom song picks its nearest difficulty", _run({"cmd": "beatsaber_do", "act": "select", "song": "zz_v2"}).get("ok", false)
		and _beat.game["difficulty"] == "easy" and _beat._mode == "Standard", [_beat.game["difficulty"], _beat._mode])
	_check("only its difficulties are shown", not _element("beatsaber", "diff_easy").is_empty() and not _element("beatsaber", "diff_expert_plus").is_empty()
		and _element("beatsaber", "diff_normal").is_empty() and _element("beatsaber", "diff_expert_plus").get("label") == "Expert+")
	_check("its modes are buttons (no Lightshow)", not _element("beatsaber", "mode_OneSaber").is_empty() and _element("beatsaber", "mode_Lightshow").is_empty()
		and _element("beatsaber", "mode_Standard").get("color") == "accent")
	_check("mapper shown", "mapped by Mapper" in str(_element("beatsaber", "song_info").get("text")), _element("beatsaber", "song_info"))
	reply = _run({"cmd": "beatsaber_do", "act": "play"})
	_check("v2 notes read, off-grid note left out", reply.get("ok", false) and reply.get("notes") == 3, reply)
	var read_notes: Array = _beat._song.get("notes", [])
	_check("v2 hands, diagonal and bomb", read_notes.size() == 3 and read_notes[0] == [2.0, 1, 0, "l", "dl"] and read_notes[1] == [3.0, 2, 1, "r", "d"]
		and read_notes[2] == [4.0, 0, 2, "b", "a"], read_notes)
	_check("v2 crouch wall read", _beat._song.get("walls") == [[3.0, 2.0, 0.0, 4.0, 2.0, 3.0]] and _beat._song.get("arcs") == [], _beat._song.get("walls"))
	_run({"cmd": "beatsaber_stop"})
	_check("No arrows isn't offered when it has none", not _run({"cmd": "beatsaber_do", "act": "mode", "mode": "NoArrows"}).get("ok", true))
	reply = _run({"cmd": "beatsaber_do", "act": "mode", "mode": "OneSaber"})
	_check("One saber mode moves to its difficulty", reply.get("ok", false) and reply.get("difficulty") == "expert"
		and not _element("beatsaber", "diff_expert").is_empty() and _element("beatsaber", "diff_easy").is_empty(), reply)
	reply = _run({"cmd": "beatsaber_do", "act": "play"})
	read_notes = _beat._song.get("notes", [])
	_check("v3 file read (colour and bomb notes)", reply.get("mode") == "OneSaber" and read_notes == [[2.0, 1, 1, "r", "dr"], [3.0, 2, 0, "r", "u"], [4.0, 3, 2, "b", "a"]],
		[reply, read_notes])
	_check("v3 wall (bad one left out) and arc read", _beat._song.get("walls") == [[2.0, 1.0, 0.0, 1.0, 0.0, 5.0]]
		and _beat._song.get("arcs") == [[2.0, 1, 1, "dr", 3.0, 2, 0, "u", "r", 1.0, 1.0]], [_beat._song.get("walls"), _beat._song.get("arcs")])
	await _frames(3)
	_check("one saber: the left blade doesn't cut", not _beat._blade.has("left") and _beat._blade.has("right"), _beat._blade.keys())
	_run({"cmd": "beatsaber_stop"})
	_check("modes keep their own scores", _beat._score_key("zz_v2", "expert", "OneSaber") == "zz_v2|expert|OneSaber"
		and _beat._score_key("zz_v2", "easy") == "zz_v2|easy")
	reply = _run({"cmd": "beatsaber_start", "song": "zz_v4"})
	read_notes = _beat._song.get("notes", [])
	_check("v4 Info and file read (data lists, bad index left out)", reply.get("ok", false) and reply.get("mode") == "Standard" and reply.get("difficulty") == "normal"
		and reply.get("bpm") == 150.0 and read_notes == [[1.0, 0, 0, "l", "ul"], [2.0, 3, 1, "r", "r"], [4.0, 1, 2, "b", "a"]], [reply, read_notes])
	_check("v4 wall and arc read (data lists)", _beat._song.get("walls") == [[2.0, 0.5, 3.0, 1.0, 0.0, 3.0]]
		and _beat._song.get("arcs") == [[1.0, 0, 0, "ul", 2.0, 3, 1, "r", "l", 1.5, 0.5]], [_beat._song.get("walls"), _beat._song.get("arcs")])
	_run({"cmd": "beatsaber_stop"})
	# A wall across the whole track comes through you; an arc rides along.
	_beat._begin({"id": "zz walls", "title": "Walls", "bpm": 60.0, "offset": 0.0, "audio": null, "notes": [[20.0, 0, 0, "r", "a"]], "mode": "Standard",
		"walls": [[1.0, 2.0, 0.0, 4.0, 0.0, 5.0]], "arcs": [[1.0, 0, 0, "d", 2.0, 3, 2, "u", "l", 1.0, 1.0]]})
	while _beat._clock < 0.3:
		await _frames(1)
	_check("wall and arc come down the track", _beat._walls_on.size() == 1 and _beat._arcs_on.size() == 1 and not _beat._in_wall)
	while _beat._clock < 1.6:
		await _frames(1)
	_check("in the wall: combo breaks, music quiet", _beat._in_wall and _beat.bumped == 1 and _beat.combo == 0 and _beat._song_player.volume_db < -10.0,
		[_beat._in_wall, _beat.bumped, _beat._song_player.volume_db])
	while _beat._clock < 3.6:
		await _frames(1)
	_check("out again: music back, counted once", not _beat._in_wall and _beat.bumped == 1 and _beat._song_player.volume_db == 0.0
		and _run({"cmd": "beatsaber_score"}).get("walls_hit") == 1)
	_run({"cmd": "beatsaber_stop"})
	_check("stop clears walls and arcs", _beat._walls_on.is_empty() and _beat._arcs_on.is_empty())
	reply = _run({"cmd": "beatsaber_start", "song": "zz_v4"})
	_check("v4 mapper shown", "mapped by Four mapper" in str(_beat._selected_info().get("detail")), _beat._selected_info())
	_run({"cmd": "beatsaber_stop"})
	reply = _run({"cmd": "beatsaber_start", "song": "zz_nomusic"})
	_check("missing music is an error", not reply.get("ok", true) and "isn't there" in str(reply.get("error")), reply)

	_check("Leave after the songs", _run({"cmd": "beatsaber_leave"}).get("back_in") == "start" and _world() == "start")

	# Online songs, through a stand-in net module
	_check("no Online pack without net", not "Online" in _beat._packs())
	var ns := GDScript.new()
	ns.source_code = FAKE_NET
	ns.reload()
	ctx["modules"].load_live("net", ns)
	await _frames(3)
	var net = ctx["modules"].module("net")
	_check("Online pack with net", "Online" in _beat._packs(), _beat._packs())
	_run({"cmd": "beatsaber_do", "act": "show"})
	_check("Latest asks BeatSaver", _run({"cmd": "beatsaber_do", "act": "online", "list": "latest"}).get("ok", false) and _beat._pack == "Online")
	await _frames(4)
	_check("not allowed yet: says which hosts to add", "net_config" in _beat._online_note and "api.beatsaver.com" in _beat._online_note
		and str(net.urls[-1]).begins_with("https://api.beatsaver.com/search/text/0?sortOrder=Latest"), [_beat._online_note, net.urls])
	net.allow = true
	var docs := []
	for i in 6:
		docs.append({"id": "%x" % (0xa10 + i), "name": "Map %d" % i, "metadata": {"songName": "Song %d" % i, "songAuthorName": "Band", "levelAuthorName": "Mapper",
			"bpm": 128, "duration": 95}, "versions": [{"hash": "abc%d" % i, "downloadURL": "https://r2cdn.beatsaver.com/abc%d.zip" % i,
			"diffs": [{"characteristic": "Standard", "difficulty": "Easy"}, {"characteristic": "Standard", "difficulty": "ExpertPlus"}]}]})
	docs.append({"id": "not hex!", "metadata": {}, "versions": [{"downloadURL": "https://r2cdn.beatsaver.com/x.zip"}]})
	docs.append({"id": "b00", "metadata": {}, "versions": []})
	net.list = {"docs": docs}
	_check("search needs words", not _run({"cmd": "beatsaber_do", "act": "online", "list": "search", "query": "  "}).get("ok", true))
	_run({"cmd": "beatsaber_do", "act": "online", "list": "search", "query": "a b"})
	await _frames(4)
	_check("search results (bad entries left out)", _beat._online.size() == 6 and str(net.urls[-1]).ends_with("sortOrder=Relevance&q=a%20b")
		and not _element("beatsaber", "online_0").is_empty() and _element("beatsaber", "online_4").is_empty(), [_beat._online.size(), net.urls[-1]])
	_run({"cmd": "beatsaber_do", "act": "online_page", "page": 1})
	_check("results page 2", not _element("beatsaber", "online_4").is_empty() and _element("beatsaber", "online_0").is_empty())
	_check("choose a result", _run({"cmd": "beatsaber_do", "act": "online_pick", "key": "a14"}).get("ok", false)
		and _element("beatsaber", "online_get").get("label") == "Download" and "mapped by Mapper" in str(_element("beatsaber", "song_info").get("text"))
		and _element("beatsaber", "online_levels").get("text") == "Levels: Easy, Expert+", _element("beatsaber", "online_levels"))
	# The zip: in a folder of its own (flattened), with a file that isn't a song's (left out)
	var scratch: String = lib.home() + "/zz_zips"
	DirAccess.make_dir_recursive_absolute(scratch)
	wav.save_to_wav(scratch + "/song.wav")
	var packer := ZIPPacker.new()
	packer.open(scratch + "/good.zip")
	var zip_files := {"My Song/Info.dat": JSON.stringify({"_songName": "Zipped", "_beatsPerMinute": 120, "_songFilename": "song.wav",
		"_difficultyBeatmapSets": [{"_beatmapCharacteristicName": "Standard", "_difficultyBeatmaps": [{"_difficulty": "Easy", "_beatmapFilename": "Easy.dat"}]}]}).to_utf8_buffer(),
		"My Song/Easy.dat": JSON.stringify({"_notes": [{"_time": 2, "_lineIndex": 1, "_lineLayer": 0, "_type": 1, "_cutDirection": 1}]}).to_utf8_buffer(),
		"My Song/song.wav": FileAccess.get_file_as_bytes(scratch + "/song.wav"), "My Song/run.exe": "nope".to_utf8_buffer()}
	for zip_name in zip_files:
		packer.start_file(zip_name)
		packer.write_file(zip_files[zip_name])
		packer.close_file()
	packer.close()
	net.zip_from = scratch + "/good.zip"
	_check("Download starts", _run({"cmd": "beatsaber_do", "act": "online_get", "key": "a14"}).get("downloading") == "a14")
	await _frames(4)
	var got: String = lib.home() + "/songs/bsv_a14"
	_check("unpacked flat, song files only", FileAccess.file_exists(got + "/Info.dat") and FileAccess.file_exists(got + "/Easy.dat") and FileAccess.file_exists(got + "/song.wav")
		and not FileAccess.file_exists(got + "/run.exe") and not DirAccess.dir_exists_absolute(got + ".part"), [DirAccess.get_files_at(got), _beat._online_note])
	_check("then chosen in Custom songs", _beat._pack == "Custom songs" and _beat._selected == "bsv_a14" and "Downloaded" in _beat._online_note
		and str(net.urls[-1]) == "https://r2cdn.beatsaver.com/abc4.zip")
	_run({"cmd": "beatsaber_do", "act": "pack", "pack": "Online"})
	_check("a downloaded one says Play", _element("beatsaber", "online_get").get("label") == "Play")
	reply = _run({"cmd": "beatsaber_do", "act": "online_get", "key": "a14"})
	_check("and plays", reply.get("ok", false) and reply.get("song") == "Zipped" and _beat.running, reply)
	_run({"cmd": "beatsaber_stop"})
	packer = ZIPPacker.new()
	packer.open(scratch + "/bad.zip")
	packer.start_file("cover.jpg")
	packer.write_file("x".to_utf8_buffer())
	packer.close_file()
	packer.close()
	net.zip_from = scratch + "/bad.zip"
	_run({"cmd": "beatsaber_do", "act": "online_get", "key": "a15"})
	await _frames(4)
	_check("a zip that isn't a song is refused, nothing left", not DirAccess.dir_exists_absolute(lib.home() + "/songs/bsv_a15")
		and not DirAccess.dir_exists_absolute(lib.home() + "/songs/bsv_a15.part") and "isn't a song" in _beat._online_note, _beat._online_note)

	# The Settings tab's Hands / Sabers buttons
	_run({"cmd": "beatsaber_do", "act": "enter"})
	_check("Settings tab: Hands button", _run({"cmd": "ui_press", "id_panel": "rhythm_left", "id_element": "style_hand"}).get("ok", false)
		and hands.settings["style"] == "hand" and not saber.visible)
	_check("Sabers button", _run({"cmd": "ui_press", "id_panel": "rhythm_left", "id_element": "style_saber"}).get("ok", false)
		and saber.visible and _element("rhythm_left", "style_saber").get("color") == "accent")

	ctx["modules"].unload("beatsaber")
	await _frames(3)
	_check("unload puts the sky, sun and floor back", ctx["world"].get_parent().get_node("WorldEnvironment").environment == sky_env
		and ctx["world"].get_parent().get_node("Floor").visible and is_equal_approx(ctx["world"].get_parent().get_node("Sun").light_energy, sun_energy))
	_check("unload takes the sabers and window", not is_instance_valid(saber) and not _run({"cmd": "ui_get", "id_panel": "beatsaber"}).get("ok", true))
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


func _element(id_panel: String, id: String) -> Dictionary:
	for e in _run({"cmd": "ui_get", "id_panel": id_panel}).get("panel", {}).get("elements", []):
		if e.get("id") == id:
			return e
	return {}


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
