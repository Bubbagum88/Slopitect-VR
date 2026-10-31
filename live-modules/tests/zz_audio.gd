extends SlopitectModule
# Headless checks for audio.gd. Run: tests/run.sh audio lib zz_audio
var _fails := 0
var _passes := 0
var _finished_ids := []


func setup() -> String:
	_go.call_deferred()
	return ""


func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if ok: _passes += 1
	else: _fails += 1


func _r(q: Dictionary) -> Dictionary:
	var r = ctx["server"].run(q)
	if r.get("wait") is SlopitectPending:
		var p: SlopitectPending = r["wait"]
		r = p.result if p.finished else await p.done
	return r


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


# Loads a module again from its file in the Slopitect modules folder.
func _load(module_name: String) -> String:
	var s := GDScript.new()
	s.source_code = FileAccess.get_file_as_string(OS.get_user_data_dir() + "/files_home/modules/%s.gd" % module_name)
	s.reload()
	var problem: String = ctx["modules"].load_live(module_name, s)
	await _wait(0.1)
	return problem


func _finish() -> void:
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


func _bus_effect(bus_name: String, kind: String) -> AudioEffect:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return null
	for i in AudioServer.get_bus_effect_count(index):
		if AudioServer.get_bus_effect(index, i).is_class(kind):
			return AudioServer.get_bus_effect(index, i)
	return null


func _on_finished(id: int) -> void:
	_finished_ids.append(id)


func _go() -> void:
	await _wait(0.5)
	var audio: SlopitectModule = ctx["modules"].module("audio")
	var master_db := AudioServer.get_bus_volume_db(0)
	var status := await _r({"cmd": "audio_status"})
	_check("audio_status", status.get("ok", false), status)
	for bus_name in ["Music", "Effects", "Voice", "Ambient", "UI"]:
		_check("bus %s made, sending to Master" % bus_name, AudioServer.get_bus_index(bus_name) != -1 and AudioServer.get_bus_send(AudioServer.get_bus_index(bus_name)) == "Master")
	_check("idle: not processing, no zone timer", not audio.is_processing() and status["zones"].is_empty(), status)
	_check("bus() maps kinds", audio.bus("music") == "Music" and audio.bus("nonsense") == "Effects")

	# Settings
	var set := await _r({"cmd": "audio_set", "master": 50})
	_check("audio_set master 50", set.get("ok", false), set)
	_check("Master bus at half volume", is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.5)), AudioServer.get_bus_volume_db(0))
	_check("settings saved", FileAccess.file_exists("user://audio.json"))
	await _r({"cmd": "audio_set", "music": 0})
	_check("volume 0 is silent", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) <= -80.0)
	_check("audio_set refuses 150", not (await _r({"cmd": "audio_set", "effects": 150})).get("ok", true))
	_check("audio_set refuses unknown keys", not (await _r({"cmd": "audio_set", "max_voices": 2})).get("ok", true))
	var info: Dictionary = audio.settings_info()
	var labels_ok := true
	for s in info["settings"]:
		labels_ok = labels_ok and s.get("label", "").length() <= 40
	_check("settings_info: 6 sliders + 2 toggles, labels <= 40", info["settings"].size() == 8 and labels_ok and info["settings"][0]["value"] == 50, info)
	await _r({"cmd": "audio_set", "mono": true})
	var enhance := _bus_effect("Master", "AudioEffectStereoEnhance") as AudioEffectStereoEnhance
	_check("mono output puts a mono mix on Master", enhance != null and enhance.pan_pullout == 0.0)
	await _r({"cmd": "audio_set", "mono": false})
	_check("mono output off takes it away", _bus_effect("Master", "AudioEffectStereoEnhance") == null)

	# Playing
	audio.sound_finished.connect(_on_finished)
	var beep := await _r({"cmd": "audio_test", "where": "center"})
	_check("audio_test center plays", beep.get("ok", false) and audio.playing(beep["id"]), beep)
	var left := await _r({"cmd": "audio_test", "where": "left"})
	var ear: Node3D = get_viewport().get_camera_3d() if get_viewport().get_camera_3d() else ctx["camera"]
	var left_player: Node3D = audio._voices[left["id"]]["player"] if left.get("ok", false) else null
	_check("audio_test left is a 3D sound to your left", left_player is AudioStreamPlayer3D and (ear.global_transform.affine_inverse() * left_player.global_position).x < -1.0, left)
	await _wait(0.6)
	_check("one-shot sounds end and go back to the pool", not audio.playing(beep["id"]) and beep["id"] in _finished_ids and audio._free_2d.size() >= 1, _finished_ids)

	var tone: AudioStreamWAV = audio._test_beep()
	var mono_id: int = audio.play(tone, {"mode": "mono", "bus": "ui", "loop": true})
	_check("mono plays on a mono twin of the bus", mono_id != -1 and audio._voices[mono_id]["bus"] == "UI Mono" and _bus_effect("UI Mono", "AudioEffectStereoEnhance") != null)
	await _wait(0.4)
	_check("a looped sound keeps playing", audio.playing(mono_id))
	_check("bad options are refused", audio.play(tone, {"volume": 3}) == -1 and "volume" in audio.last_error())
	_check("at needs spatial", audio.play(tone, {"mode": "stereo", "at": Vector3.ONE}) == -1)

	# Following a node
	var node := Node3D.new()
	ctx["world"].add_child(node)
	node.global_position = Vector3(3, 1, 0)
	var on_id: int = audio.play_on(tone, node, {"loop": true})
	_check("play_on follows: processing on", on_id != -1 and audio.is_processing())
	node.global_position = Vector3(-4, 2, 1)
	await _wait(0.1)
	_check("the sound moved with its node", audio._voices[on_id]["player"].global_position.is_equal_approx(Vector3(-4, 2, 1)))
	node.queue_free()
	await _wait(0.2)
	_check("its node gone: the sound stops, processing off", not audio.playing(on_id) and not audio.is_processing(), [audio.playing(on_id), audio.is_processing(), audio._following])

	# The voice limit
	_check("audio_config max_voices 4", (await _r({"cmd": "audio_config", "max_voices": 4})).get("ok", false))
	audio.stop_all()
	var ids := []
	for i in 6:
		ids.append(audio.play(tone, {"loop": true}))
	_check("only 4 at once; the oldest stopped", audio._voices.size() == 4 and not audio.playing(ids[0]) and not audio.playing(ids[1]) and audio.playing(ids[5]), audio._voices.keys())
	var high: int = audio.play(tone, {"loop": true, "priority": 5})
	_check("a higher priority takes a voice", audio.playing(high))
	for i in 3:
		audio.play(tone, {"loop": true, "priority": 5})
	_check("a lower priority can't steal from higher", audio.play(tone, {"loop": true}) == -1 and "priority" in audio.last_error())
	var stop_all := await _r({"cmd": "audio_stop", "all": true})
	_check("audio_stop all", stop_all.get("ok", false) and audio._voices.is_empty(), stop_all)
	await _r({"cmd": "audio_config", "max_voices": 24})
	var fade_id: int = audio.play(tone, {"loop": true})
	await _r({"cmd": "audio_stop", "id": fade_id, "fade": 0.2})
	_check("fading out still playing at first", audio.playing(fade_id))
	await _wait(0.4)
	_check("then stopped", not audio.playing(fade_id))

	# Proximity zones
	ear.global_position = Vector3.ZERO
	var problem: String = audio.zone_add("radio", tone, Vector3(10, 0, 0), 3.0)
	_check("zone_add", problem == "", problem)
	await _wait(0.3)
	_check("far from the zone: silent, timer on", audio._zones["radio"]["id"] == -1 and not audio._zone_timer.is_stopped())
	ear.global_position = Vector3(8, 0, 0)
	await _wait(0.3)
	_check("walk in: the zone plays", audio.playing(audio._zones["radio"]["id"]), audio._zones["radio"])
	ear.global_position = Vector3(6.7, 0, 0)  # 3.3 m: past the radius but inside the margin
	await _wait(0.3)
	_check("just past the edge: still playing", audio._zones["radio"]["id"] != -1)
	ear.global_position = Vector3(0, 0, 0)
	await _wait(0.6)
	_check("walk away: it fades out", audio._zones["radio"]["id"] == -1, audio._zones["radio"])
	var zone_cmd := await _r({"cmd": "audio_zone", "name": "radio", "remove": true})
	_check("audio_zone remove; the timer stops", zone_cmd.get("ok", false) and audio._zone_timer.is_stopped(), zone_cmd)
	var buzzer := Node3D.new()
	ctx["world"].add_child(buzzer)
	buzzer.global_position = Vector3(1, 0, 0)
	audio.zone_add("buzz", tone, buzzer, 2.0)
	await _wait(0.1)
	_check("a zone on a node plays when near, following it", audio.playing(audio._zones["buzz"]["id"]) and audio.is_processing())
	buzzer.queue_free()
	await _wait(0.5)
	_check("its node gone: the zone goes, all idle", not audio._zones.has("buzz") and audio._voices.is_empty() and not audio.is_processing() and audio._zone_timer.is_stopped(), audio._zones)

	# Files
	var lib: SlopitectModule = ctx["modules"].module("lib")
	DirAccess.make_dir_recursive_absolute(lib.home() + "/sounds/doors")
	tone.save_to_wav(lib.home() + "/sounds/doors/creak.wav")
	var file_play := await _r({"cmd": "audio_play", "sound": "doors/creak", "at": [0, 1, -2]})
	_check("audio_play a file by name", file_play.get("ok", false) and file_play["mode"] == "spatial", file_play)
	var listed := await _r({"cmd": "audio_sounds"})
	_check("audio_sounds lists it", "doors/creak.wav" in listed.get("sounds", []), listed)
	_check("the sound is cached", audio._cache.size() >= 1)
	_check("no .. in paths", not (await _r({"cmd": "audio_play", "sound": "../code.json"})).get("ok", true))
	_check("nothing outside the folder", not (await _r({"cmd": "audio_play", "sound": "/etc/hostname.wav"})).get("ok", true))
	_check("missing file", not (await _r({"cmd": "audio_play", "sound": "nope"})).get("ok", true))
	_check("audio_stop needs a playing id", not (await _r({"cmd": "audio_stop", "id": 99999})).get("ok", true))

	# Unload and load again
	audio.zone_add("hum", tone, Vector3.ZERO, 2.0)
	var buses_before := AudioServer.bus_count
	await _r({"cmd": "audio_set", "mono": true})
	ctx["modules"].unload("audio")
	await _wait(0.1)
	_check("unload removes its buses", AudioServer.get_bus_index("Music") == -1 and AudioServer.get_bus_index("UI Mono") == -1 and AudioServer.bus_count < buses_before)
	_check("unload takes the mono mix off Master", _bus_effect("Master", "AudioEffectStereoEnhance") == null)
	_check("unload puts Master's volume back", is_equal_approx(AudioServer.get_bus_volume_db(0), master_db), AudioServer.get_bus_volume_db(0))
	ctx["modules"].unload("lib")
	_check("audio loads without lib", await _load("audio") == "")
	audio = ctx["modules"].module("audio")
	_check("without lib it still plays streams", audio.play(tone) != -1)
	_check("without lib folder sounds say why", not (await _r({"cmd": "audio_play", "sound": "doors/creak"})).get("ok", true))
	_check("lib loads after", await _load("lib") == "")
	await _wait(0.2)
	_check("then its saved settings come back", audio.settings["master"] == 50 and audio.settings["mono"] == true, audio.settings)
	_finish()
