extends SlopitectModule

# Slopitect live module: vtt (speech to text, "voice to text").
# Hold the "talk" button (the left trigger, with the controls module's
# default bindings) and talk; let go and the recording is turned into text,
# and the words land in the chat window's input box (or go straight to the
# agent, if you turn that on). The microphone records only while the button
# is held. A line on the hand menu (hand_status()) shows it: REC while it
# listens, then while the words are worked out, then what it heard. No
# command turns it on, not the agent's, not a panel button's; only the
# controls module does.
#
# Three ways to turn speech into text (vtt_engine, set with vtt_config from
# the PC):
# - "local" (the default): whisper.cpp on the headset itself (the
#   godot-whisper plugin built into the APK), with a model file in the
#   Slopitect folder. Nothing you say leaves the headset.
# - "sherpa": sherpa-onnx on the headset itself (its library is built into
#   the APK), with a streaming model folder in the Slopitect folder. It
#   works on your words while you talk, so they are ready about as soon as
#   you let go. Nothing you say leaves the headset either.
# - "web": a service at vtt_url that takes the OpenAI-style upload (a "file"
#   and a "model" in a multipart form, "text" in the JSON reply): OpenAI,
#   Groq, or a whisper.cpp server on your PC (its /inference address).
# Where the words go (send_to_agent) is a comfort setting: it changes in the
# headset's Settings window too. Everything else changes only from the PC.

const SETTINGS_PATH := "user://vtt.json"
const OLD_SETTINGS_PATHS := ["user://stt.json", "user://voice.json"]  # this module as stt.gd, then the APK's voice module, kept these before (as stt_ settings)
const OLD_VOICE_PATH := "user://voice.json"
const MIC_PERMISSION := "android.permission.RECORD_AUDIO"
const MIC_BUS := "SlopitectMic"
const MAX_SECONDS := 30.0
const MIN_SPEECH_SECONDS := 0.25  # less loud sound than this is a bump or a breath, not words
const HTTP_TIMEOUT := 60.0
const LOCAL_CLASS := "SpeechToText"  # from the godot-whisper plugin
const LOCAL_LANGUAGES := {"": 0, "en": 1}  # its Language enum: 0 Auto, 1 English
const SHERPA_PACKAGE := "com.k2fsa.sherpa.onnx."  # the sherpa-onnx library's Java classes, built into the APK
const SHERPA_THREADS := 2  # of the Quest 1's four fast cores; the game keeps the rest
const SHERPA_TAIL_SECONDS := 0.5  # quiet added after the last word, so it is worked out too
const TRIM_FRAME := 320  # 20 ms at 16 kHz, the steps quiet is measured in
const TRIM_RELATIVE := 0.1  # quieter than a tenth of the loudest 20 ms counts as quiet
const TRIM_FLOOR := 0.002  # and so does anything this quiet, however quiet the rest
const TRIM_PAD_SECONDS := 0.3  # kept either side of the words, so their edges aren't cut
const CHAT_INPUT := ["chat", "line"]  # the chat window's input box, where your words go

const DEFAULTS := {
	"vtt_engine": "local",  # "local": on the headset itself; "web": the service at vtt_url
	"vtt_local_model": "models/ggml-tiny.en.bin",  # for "local": a whisper.cpp model, in the Slopitect folder
	"vtt_sherpa_model": "models/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17",  # for "sherpa": a streaming model's folder, in the Slopitect folder
	"vtt_url": "",  # for "web"; "" means hold-to-talk is off there
	"vtt_key": "",
	"vtt_model": "whisper-1",
	"vtt_language": "",  # like "en"; "" lets it decide (an English-only model always hears English)
	"send_to_agent": false,  # false: words go in the chat's input box for you to check and Send
	"min_hold": 0.6,  # seconds: a shorter press is taken as an accident and not turned into text
}
const COMFORT := ["send_to_agent", "min_hold"]  # settings vtt_set may change in the headset

var settings := DEFAULTS.duplicate()

var _recording := false
var _started_at := 0.0
var _record: AudioEffectRecord
var _capture: AudioEffectCapture  # the same sound as frames, for the local engine
var _frames := PackedVector2Array()
var _local: Node  # godot-whisper's SpeechToText, made on first use
var _local_model := ""  # the model file _local has loaded
var _local_thread: Thread
var _sherpa  # sherpa-onnx's OnlineRecognizer (a Java object), made on first use
var _sherpa_model := ""  # the model folder _sherpa has loaded
var _sherpa_thread: Thread  # hears one recording, from the press to the words
var _sherpa_wake := Semaphore.new()  # posted when there is sound for it, or the press ended
var _sherpa_lock := Mutex.new()  # guards the three below
var _sherpa_sound := PackedFloat32Array()  # heard since the thread last took it
var _sherpa_ending := false  # the button was let go
var _sherpa_dropped := false  # and the press was too short: the words aren't wanted
var _sherpa_in_build := -1  # whether the APK has sherpa-onnx: -1 not checked yet, 0 no, 1 yes
var _lone_i := RegEx.create_from_string("\\bi\\b")  # "i", "i'm": back to capitals after lower-casing
var _mic_player: AudioStreamPlayer
var _http: HTTPRequest
var _busy := false  # a recording is being turned into text
var _last := ""  # what happened last, for vtt_status
var _lib: SlopitectModule
var _filling := false  # changing the hand menu's line ourselves
var _status_shown := []  # [text, colour] last put on the hand menu
var _status_retry_at := 0.0  # when to try again while there's no hand menu


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

	register("vtt_status", _status, "whether hold-to-talk works, which engine, the model, and what it heard or what went wrong last")
	register("vtt_set", _set_command, "a comfort setting, so it changes in the headset too: send_to_agent (true: your words go straight to the agent)")
	register("vtt_config", _config, "from the PC only: show or change any of: %s" % ", ".join(DEFAULTS.keys()))
	var problem := _vtt_problem()
	print("Slopitect vtt: hold-to-talk %s (%s)" % ["on" if problem.is_empty() else "off: " + problem, settings["vtt_engine"]])
	return ""


# The hand menu (pause.gd's) may be built after this, or again: its status
# line is filled then.
func lib_ready(lib) -> void:
	_lib = lib
	if lib:
		lib.follow(self, "vrui", "panel_changed", _on_panel)


func _on_panel(id_panel: String) -> void:
	if id_panel == "hand_menu" and not _filling:
		_status_shown = []
		_status_retry_at = 0.0
		set_process(true)


func _exit_tree() -> void:
	if _recording:
		_record.set_recording_active(false)
		_mic_player.stop()
	if _local_thread and _local_thread.is_started():
		_local_thread.wait_to_finish()
	if _local:
		_local.free()
	if _sherpa_thread and _sherpa_thread.is_started():
		_sherpa_end(true)
		_sherpa_thread.wait_to_finish()
	if _sherpa:
		_sherpa.release()


func settings_info() -> Dictionary:
	return {"title": "Speech to text", "order": 41, "settings": [
		{"id": "send_to_agent", "type": "toggle", "label": "Send my words straight to the agent", "value": settings["send_to_agent"],
			"set": {"cmd": "vtt_set", "send_to_agent": "{value}"}},
		{"id": "min_hold", "type": "slider", "label": "Ignore presses shorter than (s)", "value": settings["min_hold"], "min": 0.2, "max": 3.0, "step": 0.1,
			"set": {"cmd": "vtt_set", "min_hold": "{value}"}},
	]}


# The hand menu's line for hold-to-talk (pause.gd puts it under the buttons).
func hand_status() -> Dictionary:
	var status := _status_now()
	return {"id": "vtt", "text": status[0], "color": status[1]}


# What hold-to-talk is doing, as [text, colour name from the window theme].
func _status_now() -> Array:
	if _recording:
		return ["REC  Listening... let go when you're done", "notice"]
	if _busy:
		return ["Turning your words into text...", "accent"]
	if _last.is_empty():
		return ["Hold the left trigger to talk", "muted"]
	return [_last.left(70) + ("..." if _last.length() > 70 else ""), "muted"]


# Changes the hand menu's line only when the status changed (each change
# redraws the menu).
func _show_status() -> void:
	var status := _status_now()
	var now := Time.get_ticks_msec() / 1000.0
	if status == _status_shown or now < _status_retry_at:
		return
	_filling = true
	var reply: Dictionary = ctx["server"].run({"cmd": "ui_element_update", "id_panel": "hand_menu", "id_element": "st_vtt", "text": status[0], "color": status[1]})
	_filling = false
	if reply.get("ok", false):
		_status_shown = status
		_status_retry_at = 0.0
	else:
		_status_retry_at = now + 1.0  # no hand menu (yet): pause.gd builds it, with this line


# On while you talk, while words are being turned into text, and until the
# hand menu shows the latest line; off the rest of the time.
func _process(_delta: float) -> void:
	_show_status()
	if not _recording:
		if not _busy and (_status_shown == _status_now() or _status_retry_at > 0.0):
			set_process(false)  # a hand menu that comes later is filled then (lib_ready)
		return
	if Time.get_ticks_msec() / 1000.0 - _started_at >= MAX_SECONDS:
		_note("stopped listening after %d seconds" % MAX_SECONDS)
		_stop_listening()
		return
	if _capture.get_frames_available() > 0:
		var frames := _capture.get_buffer(_capture.get_frames_available())
		if settings["vtt_engine"] == "sherpa":
			_sherpa_hear(frames)
		else:
			_frames.append_array(frames)


# Why hold-to-talk can't work now, or "" when it can.
func _vtt_problem() -> String:
	if settings["vtt_engine"] == "local":
		if not ClassDB.class_exists(LOCAL_CLASS):
			return "this build has no on-headset speech-to-text (the godot-whisper plugin isn't in it)"
		if not FileAccess.file_exists(_local_model_path()):
			return "no model at %s: put a whisper.cpp model there (ggml-tiny.en.bin is about 78 MB), or set vtt_local_model" % _local_model_path()
		if not LOCAL_LANGUAGES.has(settings["vtt_language"]):
			return "on the headset, vtt_language can only be \"en\" or \"\" (any) for now"
		return ""
	if settings["vtt_engine"] == "sherpa":
		if not _sherpa_built_in():
			return "this build has no sherpa-onnx (its library isn't in the APK)"
		return _sherpa_files(_home_path(settings["vtt_sherpa_model"])).get("error", "")
	if String(settings["vtt_url"]).is_empty():
		return "set a speech-to-text service with vtt_config from the PC"
	return ""


func _local_model_path() -> String:
	return _home_path(settings["vtt_local_model"])


# A path inside the Slopitect folder.
func _home_path(path: String) -> String:
	var files: SlopitectModule = ctx["modules"].module("files")
	var home: String = files.get("_home") if files else ""
	if home.is_empty():
		home = "/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home"
	return home.path_join(path)


# The controls module's "talk" action: held, it records.
func on_action(action: String, down: bool) -> bool:
	if action != "talk":
		return false
	if down:
		_start_listening()
	else:
		_stop_listening()
	return true


func _start_listening() -> void:
	if _recording or _busy:
		return
	var problem := _vtt_problem()
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
	if settings["vtt_engine"] == "sherpa":
		_sherpa_start()
	_mic_player.play()
	_record.set_recording_active(true)
	_recording = true
	set_process(true)  # the hand menu line follows; off again once idle
	_started_at = Time.get_ticks_msec() / 1000.0
	print("Slopitect vtt: listening")


func _stop_listening() -> void:
	if not _recording:
		return
	_recording = false
	_record.set_recording_active(false)
	_mic_player.stop()
	var seconds := Time.get_ticks_msec() / 1000.0 - _started_at
	var recording := _record.get_recording()
	var sherpa: bool = settings["vtt_engine"] == "sherpa"
	if _capture.get_frames_available() > 0:
		var frames := _capture.get_buffer(_capture.get_frames_available())
		if sherpa:
			_sherpa_hear(frames)
		else:
			_frames.append_array(frames)
	if recording == null or seconds < float(settings["min_hold"]):
		# Nothing is turned into text: the press was too short to be talking.
		if sherpa:
			_busy = true  # until its thread has stopped
			set_process(true)  # the hand menu line follows; off again once idle
			_sherpa_end(true)
		_note("ignored a %.1f s press (shorter than min_hold, %.1f s); hold the trigger while you talk" % [seconds, float(settings["min_hold"])])
		return
	if sherpa:
		_busy = true
		set_process(true)  # the hand menu line follows; off again once idle
		_sherpa_end(false)
		return
	if settings["vtt_engine"] == "local":
		_transcribe_local(_frames, seconds)
		_frames = PackedVector2Array()
		return
	print("Slopitect vtt: heard %.1f s, sending it to speech-to-text" % seconds)
	_transcribe(recording)


# --- On the headset (vtt_engine "local") ---------------------------------------
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
	# An English-only model (*.en.bin) can only hear English; left to guess,
	# it picks a random language and turns English into nonsense.
	var language: String = settings["vtt_language"]
	if language.is_empty() and path.get_file().contains(".en."):
		language = "en"
	_local.set("language", LOCAL_LANGUAGES[language])
	_busy = true
	set_process(true)  # the hand menu line follows; off again once idle
	print("Slopitect vtt: heard %.1f s (%d frames at %d Hz), turning it into text on the headset" % [seconds, frames.size(), int(AudioServer.get_mix_rate())])
	_local_thread = Thread.new()
	_local_thread.start(_local_work.bind(frames, path))


# Runs on the thread: touches only _local and its own values.
func _local_work(frames: PackedVector2Array, path: String) -> void:
	var report := {"model": path, "frames": frames.size(), "mix_rate": int(AudioServer.get_mix_rate()), "language": int(_local.get("language"))}
	# How loud the recording got (0 to 1): near 0 means the microphone gave silence.
	var peak := 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	report["peak"] = snappedf(peak, 0.001)
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
	# The quiet before and after the words is cut off: whisper's work grows
	# with the audio it is given, and trailing quiet is where it repeats itself.
	samples = _trim_quiet(samples)
	report["speech_s"] = snappedf(samples.size() / 16000.0, 0.01)
	if samples.is_empty():
		call_deferred("_local_done", report, "")
		return
	started = Time.get_ticks_msec()
	# Whisper's encoder covers a fixed 30 s window (an audio context of 1500,
	# 50 per second) however short the recording; covering only what was
	# said, plus a second, is what makes a 2 s phrase take seconds, not tens.
	var audio_ctx := mini(1500, ceili(samples.size() / 320.0) + 50)
	report["audio_ctx"] = audio_ctx
	var result: Array = _local.call("transcribe", samples, "", audio_ctx)
	var took := Time.get_ticks_msec() - started
	report["transcribe_ms"] = took
	if samples.size() > 0:
		report["x_realtime"] = snappedf(took / (samples.size() / 16.0), 0.01)  # under 1 is faster than you spoke
	var error := String(_local.call("get_last_error"))
	if not error.is_empty():
		report["error"] = error
	var words: String = String(result[0]) if not result.is_empty() else ""
	# The rest of the result is one entry per token whisper wrote: with the
	# time, it tells the listening (encoder) apart from the writing (decoder).
	report["tokens"] = maxi(result.size() - 1, 0)
	call_deferred("_local_done", report, words)


# The part of a 16 kHz recording from a little before the first loud 20 ms
# to a little after the last; "loud" is relative to the loudest part, so a
# quiet microphone works too. Empty when it was all quiet, or the loud part
# is too short to be words (a bump or a click).
func _trim_quiet(samples: PackedFloat32Array) -> PackedFloat32Array:
	var frame := TRIM_FRAME
	var count := samples.size() / frame
	if count == 0:
		return samples
	var levels := PackedFloat32Array()
	levels.resize(count)
	var loudest := 0.0
	for i in count:
		var sum := 0.0
		for j in range(i * frame, (i + 1) * frame):
			sum += samples[j] * samples[j]
		levels[i] = sqrt(sum / frame)
		loudest = maxf(loudest, levels[i])
	var threshold := maxf(loudest * TRIM_RELATIVE, TRIM_FLOOR)
	var first := -1
	var last := -1
	for i in count:
		if levels[i] >= threshold:
			if first == -1:
				first = i
			last = i
	if first == -1 or (last - first + 1) * frame < MIN_SPEECH_SECONDS * 16000:
		return PackedFloat32Array()
	var pad := int(TRIM_PAD_SECONDS * 16000)
	return samples.slice(maxi(first * frame - pad, 0), mini((last + 1) * frame + pad, samples.size()))


func _local_done(report: Dictionary, words: String) -> void:
	_local_thread.wait_to_finish()
	_local_thread = null
	_busy = false
	print("Slopitect vtt: on-headset speech-to-text: ", JSON.stringify(report))
	if report.has("error"):
		_note("on-headset speech-to-text failed: " + String(report["error"]))
		return
	words = words.strip_edges()
	if report.get("speech_s", 1.0) == 0.0:
		_note("no talking in the recording (only quiet or a short bump); nothing turned into text")
		return
	if words.is_empty():
		_note("on-headset speech-to-text heard nothing")
		return
	_note("heard: " + words)
	_deliver(words)


# --- On the headset with sherpa-onnx (vtt_engine "sherpa") ---------------------
# One thread per recording: it loads the model if it isn't loaded yet, then
# works on the sound as it comes in while the button is held, so when it's
# let go only the last moment is left. The model stays loaded. Everything
# about the attempt is logged in one line when it's done.

func _sherpa_built_in() -> bool:
	if _sherpa_in_build == -1:
		_sherpa_in_build = 0
		if OS.get_name() == "Android" and Engine.has_singleton("JavaClassWrapper"):
			var found = Engine.get_singleton("JavaClassWrapper").wrap(SHERPA_PACKAGE + "OnlineRecognizer")
			_sherpa_in_build = 1 if found != null else 0
	return _sherpa_in_build == 1


# The model's files in its folder: tokens.txt, and a transducer's encoder,
# decoder and joiner (*.onnx). Where a part comes both ways, the int8
# encoder and joiner and the full decoder are used, as in sherpa-onnx's own
# Android app. {"error": why} when the folder doesn't have them.
func _sherpa_files(folder: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(folder):
		return {"error": "no model folder at %s: put a sherpa-onnx streaming model there (like sherpa-onnx-streaming-zipformer-en-20M-2023-02-17), or set vtt_sherpa_model" % folder}
	var names := DirAccess.get_files_at(folder)
	if not "tokens.txt" in names:
		return {"error": "the model folder %s has no tokens.txt" % folder}
	var found := {"tokens": folder.path_join("tokens.txt")}
	for part in ["encoder", "decoder", "joiner"]:
		var full := []
		var int8 := []
		for name in names:
			if name.begins_with(part) and name.ends_with(".onnx"):
				(int8 if name.ends_with(".int8.onnx") else full).append(name)
		full.sort()
		int8.sort()
		var choice: Array = full if part == "decoder" else int8
		if choice.is_empty():
			choice = int8 if part == "decoder" else full
		if choice.is_empty():
			return {"error": "the model folder %s has no %s*.onnx (only streaming transducer models, with an encoder, decoder and joiner, work for now)" % [folder, part]}
		found[part] = folder.path_join(choice[0])
	return found


# The press began: a thread starts hearing it.
func _sherpa_start() -> void:
	_sherpa_lock.lock()
	_sherpa_sound = PackedFloat32Array()
	_sherpa_ending = false
	_sherpa_dropped = false
	_sherpa_lock.unlock()
	_sherpa_thread = Thread.new()
	_sherpa_thread.start(_sherpa_work.bind(_home_path(settings["vtt_sherpa_model"]), int(AudioServer.get_mix_rate())))


# Hands the microphone's new sound to the thread, as one channel.
func _sherpa_hear(frames: PackedVector2Array) -> void:
	var sound := PackedFloat32Array()
	sound.resize(frames.size())
	for i in frames.size():
		sound[i] = (frames[i].x + frames[i].y) * 0.5
	_sherpa_lock.lock()
	_sherpa_sound.append_array(sound)
	_sherpa_lock.unlock()
	_sherpa_wake.post()


# The press ended; dropped: its words aren't wanted.
func _sherpa_end(dropped: bool) -> void:
	_sherpa_lock.lock()
	_sherpa_ending = true
	_sherpa_dropped = dropped
	_sherpa_lock.unlock()
	_sherpa_wake.post()


# Runs on the thread: touches only _sherpa, _sherpa_model and the guarded
# values, and calls only what reaches no Java class by name.
func _sherpa_work(folder: String, rate: int) -> void:
	var report := {"engine": "sherpa", "model": folder, "mix_rate": rate, "threads": SHERPA_THREADS}
	if folder != _sherpa_model:
		var started := Time.get_ticks_msec()
		var problem := _sherpa_load(folder, report)
		report["load_ms"] = Time.get_ticks_msec() - started
		if not problem.is_empty():
			report["error"] = problem
			_sherpa_wait_end()
			call_deferred("_sherpa_done", report, null)
			return
	var stream = _sherpa.createStream("")
	var heard := 0
	var peak := 0.0
	var decode_ms := 0
	var ended_at := 0
	var dropped := false
	while true:
		_sherpa_wake.wait()
		_sherpa_lock.lock()
		var sound := _sherpa_sound
		_sherpa_sound = PackedFloat32Array()
		var ending := _sherpa_ending
		dropped = _sherpa_dropped
		_sherpa_lock.unlock()
		if dropped:
			break
		if ending and ended_at == 0:
			ended_at = Time.get_ticks_msec()
		if not sound.is_empty():
			for sample in sound:
				peak = maxf(peak, absf(sample))
			heard += sound.size()
			stream.acceptWaveform(sound, rate)
		if ending:
			var tail := PackedFloat32Array()
			tail.resize(int(SHERPA_TAIL_SECONDS * rate))
			# At the same rate as the rest: a stream that is given another
			# rate stops the whole app (sherpa-onnx calls exit()).
			stream.acceptWaveform(tail, rate)
			stream.inputFinished()
		var started := Time.get_ticks_msec()
		while _sherpa.isReady(stream):
			_sherpa.decode(stream)
		decode_ms += Time.get_ticks_msec() - started
		if ending:
			break
	report["heard_s"] = snappedf(heard / float(maxi(rate, 1)), 0.01)
	report["peak"] = snappedf(peak, 0.001)  # how loud it got (0 to 1): near 0 means the microphone gave silence
	report["decode_ms"] = decode_ms
	if heard > 0:
		report["x_realtime"] = snappedf(decode_ms / (heard * 1000.0 / rate), 0.01)  # under 1 keeps up with you
	if ended_at > 0:
		report["after_letting_go_ms"] = Time.get_ticks_msec() - ended_at  # how long the words took once you let go
	report["dropped"] = dropped
	# The words are read on the main thread: sherpa-onnx makes its result
	# object with JNI's FindClass, which on a thread Java didn't start
	# can't see the app's classes, and the app crashes.
	call_deferred("_sherpa_done", report, stream)


# Runs on the thread: makes the recognizer for the model in folder; "" when
# it worked, or why not.
func _sherpa_load(folder: String, report: Dictionary) -> String:
	var files := _sherpa_files(folder)
	if files.has("error"):
		return files["error"]
	report["files"] = files.values().map(func(path: String) -> String: return path.get_file())
	var wrapper = Engine.get_singleton("JavaClassWrapper")
	var config = wrapper.wrap(SHERPA_PACKAGE + "OnlineRecognizerConfig").OnlineRecognizerConfig()
	if config == null:
		return "couldn't make an OnlineRecognizerConfig (%s)" % _java_error(wrapper)
	var model = config.getModelConfig()
	var transducer = model.getTransducer()
	transducer.setEncoder(files["encoder"])
	transducer.setDecoder(files["decoder"])
	transducer.setJoiner(files["joiner"])
	model.setTokens(files["tokens"])
	model.setNumThreads(SHERPA_THREADS)
	# The press marks where talking ends, not a pause.
	config.setEnableEndpoint(false)
	if _sherpa:
		_sherpa.release()
		_sherpa = null
		_sherpa_model = ""
	_sherpa = wrapper.wrap(SHERPA_PACKAGE + "OnlineRecognizer").OnlineRecognizer(null, config)
	if _sherpa == null:
		return "couldn't load the model (%s)" % _java_error(wrapper)
	_sherpa_model = folder
	return ""


# Runs on the thread: when the model didn't load, waits out the press.
func _sherpa_wait_end() -> void:
	while true:
		_sherpa_wake.wait()
		_sherpa_lock.lock()
		var ending := _sherpa_ending
		_sherpa_sound = PackedFloat32Array()
		_sherpa_lock.unlock()
		if ending:
			return


func _java_error(wrapper) -> String:
	var e = wrapper.get_exception()
	return "no Java exception" if e == null else String(e.toString())


func _sherpa_done(report: Dictionary, stream) -> void:
	_sherpa_thread.wait_to_finish()
	_sherpa_thread = null
	_busy = false
	var words := ""
	if stream != null:
		if not report["dropped"]:
			words = String(_sherpa.getResult(stream).getText())
		stream.release()
	print("Slopitect vtt: on-headset speech-to-text: ", JSON.stringify(report))
	if report.has("error"):
		_note("on-headset speech-to-text (sherpa) failed: " + String(report["error"]))
		return
	if report["dropped"]:
		return
	words = words.strip_edges()
	if words.is_empty():
		_note("on-headset speech-to-text heard nothing")
		return
	# Its English models write in capitals.
	if words == words.to_upper():
		words = _lone_i.sub(words.to_lower(), "I", true)
		words = words.left(1).to_upper() + words.substr(1)
	_note("heard: " + words)
	_deliver(words)


func _transcribe(recording: AudioStreamWAV) -> void:
	_busy = true
	set_process(true)  # the hand menu line follows; off again once idle
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
	var fields := {"model": settings["vtt_model"], "response_format": "json"}
	if not String(settings["vtt_language"]).is_empty():
		fields["language"] = settings["vtt_language"]
	for key in fields:
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, key, fields[key]]).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % boundary).to_utf8_buffer())
	body.append_array(audio)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	var headers := PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary])
	if not String(settings["vtt_key"]).is_empty():
		headers.append("Authorization: Bearer " + settings["vtt_key"])
	err = _http.request_raw(settings["vtt_url"], headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		_note("couldn't send the recording to %s (%s)" % [settings["vtt_url"], error_string(err)])
		return
	var result: Array = await _http.request_completed
	_busy = false
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		_note("no answer from %s (result %d: is the address right, and is the headset online?)" % [settings["vtt_url"], result[0]])
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


# Puts the words in the chat window's input box (showing the window if it's
# hidden), for you to check and Send, or sends them to the agent when
# send_to_agent is on.
func _deliver(words: String) -> void:
	var server: Node = ctx["server"]
	if settings["send_to_agent"]:
		var reply: Dictionary = server.run({"cmd": "agent_ask", "prompt": words})
		if not reply.get("ok", false):
			_note("couldn't send it to the agent: " + String(reply.get("error", "?")))
		return
	# The terminal's Chat mode is the one chat window while it's loaded.
	var terminal: SlopitectModule = ctx["modules"].module("terminal")
	if terminal != null and terminal.has_method("hear"):
		terminal.call("hear", words + " ")
		return
	var typed: Dictionary = server.run({"cmd": "ui_type", "text": words + " ", "id_panel": CHAT_INPUT[0], "id_element": CHAT_INPUT[1]})
	if not typed.get("ok", false):
		_note("heard \"%s\" but couldn't put it in the chat window: %s" % [words, String(typed.get("error", "?"))])
		return
	# Shown only when hidden: showing it again would move it in front of you.
	var shown: Dictionary = server.run({"cmd": "ui_list"})
	for panel in shown.get("panels", []):
		if panel["id_panel"] == CHAT_INPUT[0] and not panel["visible"]:
			server.run({"cmd": "ui_show", "id_panel": CHAT_INPUT[0], "visible": true})


func _note(text: String) -> void:
	_last = text
	set_process(true)  # the hand menu line follows; off again once idle
	print("Slopitect vtt: ", text)


# --- Status and settings ------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	var problem := _vtt_problem()
	return {
		"ok": true,
		"hold_to_talk": "on (hold the left trigger)" if problem.is_empty() else "off: " + problem,
		"vtt_engine": settings["vtt_engine"],
		"vtt_url": settings["vtt_url"],
		"send_to_agent": settings["send_to_agent"],
		"microphone_in_build": ProjectSettings.get_setting("audio/driver/enable_input", false),
		"microphone_permission": OS.get_name() != "Android" or MIC_PERMISSION in OS.get_granted_permissions(),
		"local_in_build": ClassDB.class_exists(LOCAL_CLASS),
		"local_model": _local_model_path(),
		"local_model_found": FileAccess.file_exists(_local_model_path()),
		"local_model_loaded": not _local_model.is_empty(),
		"sherpa_in_build": _sherpa_built_in(),
		"sherpa_model": _home_path(settings["vtt_sherpa_model"]),
		"sherpa_model_problem": _sherpa_files(_home_path(settings["vtt_sherpa_model"])).get("error", ""),
		"sherpa_model_loaded": not _sherpa_model.is_empty(),
		"listening": _recording,
		"transcribing": _busy,
		"last": _last,
	}


func _set_command(request: Dictionary) -> Dictionary:
	for key in request:
		if key in ["cmd", "id"]:
			continue
		if not key in COMFORT:
			return {"ok": false, "error": "vtt_set changes only %s; \"%s\" changes from the PC with vtt_config" % [", ".join(COMFORT), key]}
	return _change(request)


func _config(request: Dictionary) -> Dictionary:
	return _change(request)


func _change(request: Dictionary) -> Dictionary:
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
	if changes.has("vtt_url") and changes["vtt_url"] != settings["vtt_url"] and not changes.has("vtt_key"):
		changes["vtt_key"] = ""
	for key in changes:
		settings[key] = changes[key]
	if not changes.is_empty():
		_save_settings()
	# Off "local", the model's memory (100 MB or more) is given back.
	if settings["vtt_engine"] != "local" and _local and not _busy:
		_local.free()
		_local = null
		_local_model = ""
		print("Slopitect vtt: on-headset speech-to-text model unloaded")
	if settings["vtt_engine"] != "sherpa" and _sherpa and not _busy and not _recording:
		_sherpa.release()
		_sherpa = null
		_sherpa_model = ""
		print("Slopitect vtt: sherpa-onnx speech-to-text model unloaded")
	if _lib:
		_lib.touch(self)  # the Settings window shows the new values
	var shown := settings.duplicate()
	shown["vtt_key"] = "(set)" if not String(settings["vtt_key"]).is_empty() else "(not set)"
	return {"ok": true, "settings": shown}


func _check_setting(key: String, value) -> String:
	match key:
		"send_to_agent":
			if typeof(value) != TYPE_BOOL:
				return "\"send_to_agent\" must be true or false"
		"min_hold":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < 0.2 or value > 3.0:
				return "\"min_hold\" must be 0.2 to 3 seconds"
		"vtt_key", "vtt_model", "vtt_language":
			if typeof(value) != TYPE_STRING or value.length() > 300:
				return "\"%s\" must be text" % key
		"vtt_engine":
			if not value in ["web", "local", "sherpa"]:
				return "\"vtt_engine\" must be \"local\" (whisper.cpp on the headset), \"sherpa\" (sherpa-onnx on the headset) or \"web\" (the service at vtt_url)"
		"vtt_sherpa_model":
			if typeof(value) != TYPE_STRING or value.is_empty() or value.begins_with("/") or ".." in value or "\\" in value or "://" in value:
				return "\"vtt_sherpa_model\" must be a model's folder inside the Slopitect folder, like \"models/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17\""
		"vtt_local_model":
			if typeof(value) != TYPE_STRING or not value.ends_with(".bin") or value.begins_with("/") or ".." in value or "\\" in value or "://" in value:
				return "\"vtt_local_model\" must be a .bin file inside the Slopitect folder, like \"models/ggml-tiny.en.bin\""
		"vtt_url":
			if typeof(value) != TYPE_STRING or not (value.is_empty() or value.begins_with("https://") or value.begins_with("http://")):
				return "\"vtt_url\" must be an http(s) address (like https://api.openai.com/v1/audio/transcriptions or http://192.168.1.10:8080/inference), or \"\" to turn the web service off"
	return ""


# Its own file, or the speech-to-text settings the APK's voice module kept
# before (only the keys this module has, with the engine it used then); a
# broken file is kept aside and the defaults used.
func _load_settings() -> void:
	var path := SETTINGS_PATH
	for old in OLD_SETTINGS_PATHS:
		if not FileAccess.file_exists(path):
			path = old
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	var problem := ""
	var data := {}
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		problem = "not a JSON object"
	else:
		for key in json.data:
			# The old files called the settings stt_...
			var name := String(key)
			data["vtt_" + name.substr(4) if path != SETTINGS_PATH and name.begins_with("stt_") else name] = json.data[key]
		for key in data:
			if not DEFAULTS.has(key):
				if path == SETTINGS_PATH:
					problem = "unknown setting \"%s\"" % key
					break
				continue
			problem = _check_setting(key, data[key])
			if not problem.is_empty():
				break
	if problem.is_empty():
		for key in data:
			if DEFAULTS.has(key):
				settings[key] = data[key]
		# The old module's "web" was its default, kept even when no address was set.
		if path == OLD_VOICE_PATH:
			if settings["vtt_engine"] == "web" and String(settings["vtt_url"]).is_empty():
				settings["vtt_engine"] = "local"
		if path != SETTINGS_PATH:
			_save_settings()
		return
	settings = DEFAULTS.duplicate()
	if path != SETTINGS_PATH:
		push_warning("Slopitect vtt: %s is broken (%s); used the defaults" % [path, problem])
		return
	DirAccess.rename_absolute(path, path + ".bad")
	push_error("Slopitect vtt: %s is broken (%s); kept it as %s and used the defaults" % [path, problem, path + ".bad"])


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Slopitect vtt: could not save %s (%s)" % [SETTINGS_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(settings, "  "))
	file.close()
