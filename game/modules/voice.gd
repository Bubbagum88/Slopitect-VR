extends SlopitectModule

# Slopitect: talking with the agent.
# Speech out: the agent's replies are read aloud by the headset's own
# text-to-speech engine (if it has one: voice_status says), and anything can
# speak with voice_say.
# Speech in: hold the left trigger and talk; let go and the recording is
# turned into text, and the words land in the chat window's input box (or
# go straight to the agent, if you turn that on). The microphone records
# only while the trigger is held, a red dot on your left hand shows it, and
# nothing can turn it on by command: not the agent, not a button.
#
# Two ways to turn speech into text (stt_engine, set with voice_config from
# the PC):
# - "local": whisper.cpp on the headset itself (the godot-whisper plugin),
#   with a model file in the Slopitect folder. Nothing you say leaves the
#   headset.
# - "web": a service at stt_url that takes the OpenAI-style upload (a "file"
#   and a "model" in a multipart form, "text" in the JSON reply): OpenAI,
#   Groq, or a whisper.cpp server on your PC (its /inference address). Off
#   until you set stt_url; until then nothing you say leaves the headset.

const SETTINGS_PATH := "user://voice.json"
const MIC_PERMISSION := "android.permission.RECORD_AUDIO"
const MIC_BUS := "SlopitectMic"
const MAX_SECONDS := 30.0
const MIN_SECONDS := 0.4
const HTTP_TIMEOUT := 60.0
const POLL_SECONDS := 0.5
const MAX_SAY := 2000
const LOCAL_CLASS := "SpeechToText"  # from the godot-whisper plugin
const LOCAL_LANGUAGES := {"": 0, "en": 1}  # its Language enum: 0 Auto, 1 English

const DEFAULTS := {
	"speak_replies": true,  # read the agent's replies aloud
	"voice": "",  # a voice id from voice_voices; "" picks the first
	"rate": 1.0,
	"pitch": 1.0,
	"volume": 80,
	"stt_engine": "web",  # "web": the service at stt_url; "local": on the headset itself
	"stt_local_model": "models/ggml-tiny.en.bin",  # for "local": a whisper.cpp model, in the Slopitect folder
	"stt_url": "",  # for "web"; "" means hold-to-talk is off
	"stt_key": "",
	"stt_model": "whisper-1",
	"stt_language": "",  # like "en"; "" lets the service decide
	"send_to_agent": false,  # false: words go in the chat's input box for you to check and Send
}

var settings := DEFAULTS.duplicate()

var _recording := false
var _started_at := 0.0
var _record: AudioEffectRecord
var _capture: AudioEffectCapture  # the same sound as frames, for the local engine
var _frames := PackedVector2Array()
var _local: Node  # godot-whisper's SpeechToText, made on first use
var _local_model := ""  # the model file _local has loaded
var _local_thread: Thread
var _mic_player: AudioStreamPlayer
var _http: HTTPRequest
var _busy := false  # a recording is being turned into text
var _last := ""  # what happened last, for voice_status
var _dot: MeshInstance3D
var _since_poll := 0.0
var _seen_reply := ""


func setup() -> String:
	_load_settings()
	_http = HTTPRequest.new()
	_http.use_threads = true  # the connection and its TLS handshake off the frame
	_http.timeout = HTTP_TIMEOUT
	add_child(_http)

	# A muted bus with a recorder on it: the microphone plays into it, so it
	# can be recorded without you hearing yourself.
	var bus := AudioServer.get_bus_index(MIC_BUS)
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, MIC_BUS)
		AudioServer.add_bus_effect(bus, AudioEffectRecord.new())
		var capture := AudioEffectCapture.new()
		capture.buffer_length = 2.0  # emptied every frame while listening
		AudioServer.add_bus_effect(bus, capture)
		AudioServer.set_bus_mute(bus, true)
	_record = AudioServer.get_bus_effect(bus, 0) as AudioEffectRecord
	_capture = AudioServer.get_bus_effect(bus, 1) as AudioEffectCapture
	_mic_player = AudioStreamPlayer.new()
	_mic_player.bus = MIC_BUS
	add_child(_mic_player)

	_dot = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.008
	sphere.height = 0.016
	_dot.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.1, 0.1)
	_dot.material_override = material
	_dot.position = Vector3(0, 0.03, -0.02)
	_dot.visible = false
	ctx["left"].add_child(_dot)
	ctx["left"].button_pressed.connect(func(button): if button == "trigger_click": _start_listening())
	ctx["left"].button_released.connect(func(button): if button == "trigger_click": _stop_listening())

	register("voice_say", _say, "say something aloud through the headset's speech engine: text, optional voice, rate, pitch")
	register("voice_stop", _stop_speaking, "stop speaking")
	register("voice_voices", _voices, "the voices the headset's speech engine has")
	register("voice_status", _status, "whether speech out and hold-to-talk are working, and what happened last")
	register("voice_config", _config, "from the PC only: show or change any of: %s" % ", ".join(DEFAULTS.keys()))
	var problem := _stt_problem()
	print("Slopitect voice: %d speech voices; hold-to-talk %s (%s)" % [_voice_list().size(), "on" if problem.is_empty() else "off: " + problem, settings["stt_engine"]])
	return ""


func _exit_tree() -> void:
	if _dot and is_instance_valid(_dot):
		_dot.queue_free()
	if _local_thread and _local_thread.is_started():
		_local_thread.wait_to_finish()
	if _local:
		_local.free()


func _process(delta: float) -> void:
	if _recording and Time.get_ticks_msec() / 1000.0 - _started_at >= MAX_SECONDS:
		_note("stopped listening after %d seconds" % MAX_SECONDS)
		_stop_listening()
	if _recording and _capture.get_frames_available() > 0:
		_frames.append_array(_capture.get_buffer(_capture.get_frames_available()))
	_since_poll += delta
	if _since_poll < POLL_SECONDS:
		return
	_since_poll = 0.0
	# Read the agent's new replies aloud.
	var status: Dictionary = ctx["server"].run({"cmd": "agent_status"})
	if not status.get("ok", false):
		return
	var reply := String(status.get("last_reply", ""))
	if reply != _seen_reply:
		_seen_reply = reply
		if settings["speak_replies"] and not reply.is_empty():
			_speak(reply)


# --- Speech out -----------------------------------------------------------------

func _voice_list() -> Array:
	return DisplayServer.tts_get_voices() if ProjectSettings.get_setting("audio/general/text_to_speech", false) else []


func _speak(text: String, voice := "") -> String:
	var voices := _voice_list()
	if voices.is_empty():
		return "the headset has no text-to-speech voices (no speech engine installed, or it isn't ready yet)"
	if voice.is_empty():
		voice = settings["voice"]
	if voice.is_empty() or not voices.any(func(v): return v["id"] == voice):
		voice = voices[0]["id"]
	DisplayServer.tts_speak(text.left(MAX_SAY), voice, int(settings["volume"]), float(settings["pitch"]), float(settings["rate"]))
	return ""


func _say(request: Dictionary) -> Dictionary:
	var text = request.get("text")
	if typeof(text) != TYPE_STRING or text.strip_edges().is_empty():
		return {"ok": false, "error": "voice_say needs \"text\""}
	var voice = request.get("voice", "")
	if typeof(voice) != TYPE_STRING:
		return {"ok": false, "error": "\"voice\" must be a voice id from voice_voices"}
	var problem := _speak(text, voice)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return {"ok": true}


func _stop_speaking(_request: Dictionary) -> Dictionary:
	DisplayServer.tts_stop()
	return {"ok": true}


func _voices(_request: Dictionary) -> Dictionary:
	var voices := []
	for v in _voice_list():
		voices.append({"id": v["id"], "name": v["name"], "language": v["language"]})
	return {"ok": true, "voices": voices}


# --- Speech in --------------------------------------------------------------------

# Why hold-to-talk can't work now, or "" when it can.
func _stt_problem() -> String:
	if settings["stt_engine"] == "local":
		if not ClassDB.class_exists(LOCAL_CLASS):
			return "this build has no on-headset speech-to-text (the godot-whisper plugin isn't in it)"
		if not FileAccess.file_exists(_local_model_path()):
			return "no model at %s: put a whisper.cpp model there (ggml-tiny.en.bin is about 78 MB), or set stt_local_model" % _local_model_path()
		if not LOCAL_LANGUAGES.has(settings["stt_language"]):
			return "on the headset, stt_language can only be \"en\" or \"\" (any) for now"
		return ""
	if String(settings["stt_url"]).is_empty():
		return "set a speech-to-text service with voice_config from the PC"
	return ""


func _local_model_path() -> String:
	var files: SlopitectModule = ctx["modules"].module("files")
	var home: String = files.get("_home") if files else ""
	if home.is_empty():
		home = "/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home"
	return home.path_join(settings["stt_local_model"])


func _start_listening() -> void:
	if _recording or _busy:
		return
	var problem := _stt_problem()
	if not problem.is_empty():
		_note("hold-to-talk is off: " + problem)
		return
	if OS.get_name() == "Android" and not MIC_PERMISSION in OS.get_granted_permissions():
		OS.request_permission(MIC_PERMISSION)
		_note("Slopitect needs the microphone: Android is asking in the headset; choose Allow, then hold the trigger again")
		return
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		_note("this build has the microphone switched off (audio/driver/enable_input)")
		return
	_mic_player.stream = AudioStreamMicrophone.new()
	_capture.clear_buffer()
	_frames = PackedVector2Array()
	_mic_player.play()
	_record.set_recording_active(true)
	_recording = true
	_started_at = Time.get_ticks_msec() / 1000.0
	_dot.visible = true
	print("Slopitect voice: listening")


func _stop_listening() -> void:
	if not _recording:
		return
	_recording = false
	_dot.visible = false
	_record.set_recording_active(false)
	_mic_player.stop()
	var seconds := Time.get_ticks_msec() / 1000.0 - _started_at
	var recording := _record.get_recording()
	if _capture.get_frames_available() > 0:
		_frames.append_array(_capture.get_buffer(_capture.get_frames_available()))
	if recording == null or seconds < MIN_SECONDS:
		_note("too short to hear anything (%.1f s); hold the trigger while you talk" % seconds)
		return
	if settings["stt_engine"] == "local":
		_transcribe_local(_frames, seconds)
		_frames = PackedVector2Array()
		return
	print("Slopitect voice: heard %.1f s, sending it to speech-to-text" % seconds)
	_transcribe(recording)


# --- On the headset (stt_engine "local") ---------------------------------------
# The model loads on first use and stays loaded; loading and turning speech
# into text take seconds, so both run on their own thread, and everything
# about the attempt is logged in one line when it's done.

func _transcribe_local(frames: PackedVector2Array, seconds: float) -> void:
	var path := _local_model_path()
	if _local == null:
		_local = ClassDB.instantiate(LOCAL_CLASS)
		if _local == null:
			_note("couldn't make godot-whisper's %s" % LOCAL_CLASS)
			return
	_local.set("language", LOCAL_LANGUAGES[settings["stt_language"]])
	_busy = true
	print("Slopitect voice: heard %.1f s (%d frames at %d Hz), turning it into text on the headset" % [seconds, frames.size(), int(AudioServer.get_mix_rate())])
	_local_thread = Thread.new()
	_local_thread.start(_local_work.bind(frames, path))


# Runs on the thread: touches only _local and its own values.
func _local_work(frames: PackedVector2Array, path: String) -> void:
	var report := {"model": path, "frames": frames.size(), "mix_rate": int(AudioServer.get_mix_rate())}
	var started := Time.get_ticks_msec()
	if path != _local_model:
		var model = ClassDB.instantiate("WhisperResource")
		model.set("file", path)
		_local.set("language_model", model)
		report["model_mb"] = snappedf(FileAccess.get_size(path) / 1048576.0, 0.1)
		report["load_ms"] = Time.get_ticks_msec() - started
		var load_error := String(_local.call("get_last_error"))
		if not load_error.is_empty():
			report["error"] = "loading the model: " + load_error
			call_deferred("_local_done", report, "")
			return
		_local_model = path
	started = Time.get_ticks_msec()
	var samples: PackedFloat32Array = _local.call("resample", frames, 2)  # SRC_SINC_FASTEST
	report["samples_16k"] = samples.size()
	report["resample_ms"] = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	var result: Array = _local.call("transcribe", samples, "", 0)
	var took := Time.get_ticks_msec() - started
	report["transcribe_ms"] = took
	if samples.size() > 0:
		report["x_realtime"] = snappedf(took / (samples.size() / 16.0), 0.01)  # under 1 is faster than you spoke
	var error := String(_local.call("get_last_error"))
	if not error.is_empty():
		report["error"] = error
	var words: String = String(result[0]) if not result.is_empty() else ""
	call_deferred("_local_done", report, words)


func _local_done(report: Dictionary, words: String) -> void:
	_local_thread.wait_to_finish()
	_local_thread = null
	_busy = false
	print("Slopitect voice: on-headset speech-to-text: ", JSON.stringify(report))
	if report.has("error"):
		_note("on-headset speech-to-text failed: " + String(report["error"]))
		return
	words = words.strip_edges()
	if words.is_empty():
		_note("on-headset speech-to-text heard nothing")
		return
	_note("heard: " + words)
	_deliver(words)


func _transcribe(recording: AudioStreamWAV) -> void:
	_busy = true
	var path := OS.get_cache_dir().path_join("slopitect-speech.wav") if OS.get_cache_dir() != "" else "user://speech.wav"
	var err := recording.save_to_wav(path)
	var audio := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)  # the recording isn't kept
	if err != OK or audio.is_empty():
		_busy = false
		_note("couldn't save the recording (%s)" % error_string(err))
		return
	var boundary := "slopitect%d" % Time.get_ticks_usec()
	var body := PackedByteArray()
	var fields := {"model": settings["stt_model"], "response_format": "json"}
	if not String(settings["stt_language"]).is_empty():
		fields["language"] = settings["stt_language"]
	for key in fields:
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, key, fields[key]]).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % boundary).to_utf8_buffer())
	body.append_array(audio)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	var headers := PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary])
	if not String(settings["stt_key"]).is_empty():
		headers.append("Authorization: Bearer " + settings["stt_key"])
	err = _http.request_raw(settings["stt_url"], headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		_note("couldn't send the recording to %s (%s)" % [settings["stt_url"], error_string(err)])
		return
	var result: Array = await _http.request_completed
	_busy = false
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		_note("no answer from %s (result %d: is the address right, and is the headset online?)" % [settings["stt_url"], result[0]])
		return
	var text_body: String = (result[3] as PackedByteArray).get_string_from_utf8()
	if result[1] != 200:
		_note("speech-to-text said HTTP %d: %s" % [result[1], text_body.left(300)])
		return
	var json := JSON.new()
	if json.parse(text_body) != OK or typeof(json.data) != TYPE_DICTIONARY or typeof(json.data.get("text")) != TYPE_STRING:
		_note("speech-to-text's reply had no \"text\": %s" % text_body.left(300))
		return
	var words: String = json.data["text"].strip_edges()
	if words.is_empty():
		_note("speech-to-text heard nothing")
		return
	_note("heard: " + words)
	_deliver(words)


# Puts the words in the chat's input box (showing the chat if it's hidden),
# or sends them to the agent when send_to_agent is on.
func _deliver(words: String) -> void:
	var server: Node = ctx["server"]
	if settings["send_to_agent"]:
		var reply: Dictionary = server.run({"cmd": "agent_ask", "prompt": words})
		if not reply.get("ok", false):
			_note("couldn't send it to the agent: " + String(reply.get("error", "?")))
		return
	server.run({"cmd": "ui_show", "id_panel": "chat", "visible": true})
	var typed: Dictionary = server.run({"cmd": "ui_type", "text": words + " "})
	if not typed.get("ok", false):
		_note("couldn't put it in an input box: " + String(typed.get("error", "?")))


func _note(text: String) -> void:
	_last = text
	print("Slopitect voice: ", text)


# --- Status and settings ------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"speech_out": ProjectSettings.get_setting("audio/general/text_to_speech", false),
		"voices": _voice_list().size(),
		"speaking": DisplayServer.tts_is_speaking() if not _voice_list().is_empty() else false,
		"microphone_in_build": ProjectSettings.get_setting("audio/driver/enable_input", false),
		"microphone_permission": OS.get_name() != "Android" or MIC_PERMISSION in OS.get_granted_permissions(),
		"hold_to_talk": "on (hold the left trigger)" if _stt_problem().is_empty() else "off: " + _stt_problem(),
		"stt_engine": settings["stt_engine"],
		"stt_url": settings["stt_url"],
		"local_in_build": ClassDB.class_exists(LOCAL_CLASS),
		"local_model": _local_model_path(),
		"local_model_found": FileAccess.file_exists(_local_model_path()),
		"local_model_loaded": not _local_model.is_empty(),
		"listening": _recording,
		"transcribing": _busy,
		"last": _last,
	}


func _config(request: Dictionary) -> Dictionary:
	var changes := {}
	for key in request:
		if key in ["cmd", "id"]:
			continue
		if not DEFAULTS.has(key):
			return {"ok": false, "error": "unknown setting \"%s\" (one of: %s)" % [key, ", ".join(DEFAULTS.keys())]}
		var problem := _check_setting(key, request[key])
		if not problem.is_empty():
			return {"ok": false, "error": problem}
		changes[key] = request[key]
	# A key belongs to one service: a new address without a key clears it.
	if changes.has("stt_url") and changes["stt_url"] != settings["stt_url"] and not changes.has("stt_key"):
		changes["stt_key"] = ""
	for key in changes:
		settings[key] = changes[key]
	if not changes.is_empty():
		_save_settings()
	# Off "local", the model's memory (100 MB or more) is given back.
	if settings["stt_engine"] != "local" and _local and not _busy:
		_local.free()
		_local = null
		_local_model = ""
		print("Slopitect voice: on-headset speech-to-text model unloaded")
	var shown := settings.duplicate()
	shown["stt_key"] = "(set)" if not String(settings["stt_key"]).is_empty() else "(not set)"
	return {"ok": true, "settings": shown}


func _check_setting(key: String, value) -> String:
	match key:
		"speak_replies", "send_to_agent":
			if typeof(value) != TYPE_BOOL:
				return "\"%s\" must be true or false" % key
		"voice", "stt_key", "stt_model", "stt_language":
			if typeof(value) != TYPE_STRING or value.length() > 300:
				return "\"%s\" must be text" % key
		"stt_engine":
			if not value in ["web", "local"]:
				return "\"stt_engine\" must be \"web\" (the service at stt_url) or \"local\" (on the headset)"
		"stt_local_model":
			if typeof(value) != TYPE_STRING or not value.ends_with(".bin") or value.begins_with("/") or ".." in value or "\\" in value or "://" in value:
				return "\"stt_local_model\" must be a .bin file inside the Slopitect folder, like \"models/ggml-tiny.en.bin\""
		"stt_url":
			if typeof(value) != TYPE_STRING or not (value.is_empty() or value.begins_with("https://") or value.begins_with("http://")):
				return "\"stt_url\" must be an http(s) address (like https://api.openai.com/v1/audio/transcriptions or http://192.168.1.10:8080/inference), or \"\" to turn hold-to-talk off"
		"rate":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < 0.1 or value > 10.0:
				return "\"rate\" must be 0.1 to 10"
		"pitch":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < 0.0 or value > 2.0:
				return "\"pitch\" must be 0 to 2"
		"volume":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < 0 or value > 100:
				return "\"volume\" must be 0 to 100"
	return ""


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var json := JSON.new()
	var problem := ""
	if json.parse(FileAccess.get_file_as_string(SETTINGS_PATH)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		problem = "not a JSON object"
	else:
		for key in json.data:
			if not DEFAULTS.has(key):
				problem = "unknown setting \"%s\"" % key
				break
			problem = _check_setting(key, json.data[key])
			if not problem.is_empty():
				break
		if problem.is_empty():
			for key in json.data:
				settings[key] = json.data[key]
			return
	DirAccess.rename_absolute(SETTINGS_PATH, SETTINGS_PATH + ".bad")
	push_error("Slopitect voice: %s is broken (%s); kept it as %s and used the defaults" % [SETTINGS_PATH, problem, SETTINGS_PATH + ".bad"])


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Slopitect voice: could not save %s (%s)" % [SETTINGS_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(settings, "  "))
	file.close()
