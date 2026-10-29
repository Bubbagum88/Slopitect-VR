extends SlopitectModule

# Slopitect live module: tts (text to speech).
# The agent's replies are read aloud by the headset's own text-to-speech
# engine (an Android app such as SherpaTTS; tts_status says how many voices
# it has), and anything can speak with tts_say. Its settings (reading
# replies, voice, rate, pitch, volume) are comfort settings: they change in
# the headset's Settings window or with tts_set.
#
# On the headset the speech is played by Slopitect itself: the engine
# writes each sentence to a sound file (TextToSpeech.synthesizeToFile,
# reached through Godot's JavaClassWrapper) and the app plays it. The
# Quest 1 played the engine's own sound (Android showed it playing, at full
# volume, nothing muted) but nothing could be heard while Slopitect was in
# front. Where that can't work (not Android, or the Java calls fail; the
# reason is in tts_status and the log), the engine speaks for itself as before.
#
# Or (tts_engine "sherpa", set with tts_config from the PC) Slopitect makes
# the speech itself with sherpa-onnx, built into the APK, from a Piper voice
# folder in the Slopitect folder (tts_sherpa_voice). A thread makes one
# sentence at a time while the one before it plays, and the sound goes
# straight into one continuous stream: no files, no gap between sentences
# while the voice is faster than real time. Pitch doesn't apply to it.
#
# Then Godot's Android speech sends the next utterance only after the engine
# says the last one is done. An engine that never says so (its process
# closed, or it dropped one) would hold everything after it silent, so
# speech that runs far past what its text could take is stopped and logged.

const SETTINGS_PATH := "user://tts.json"
const OLD_SETTINGS_PATH := "user://voice.json"  # the APK's voice module kept these before
const POLL_SECONDS := 0.5
const FILE_POLL_SECONDS := 0.1
const SENTENCE_CHARS := 200  # sentences are joined up to about this long; the first plays while the rest are written
const ENGINE_NOT_HEARD := -99  # onInit hasn't come yet
const MAX_SAY := 2000
const SPEECH_GRACE_SECONDS := 15.0
const SPEECH_SECONDS_PER_CHAR := 0.2  # far slower than any voice at rate 1

const SHERPA_PACKAGE := "com.k2fsa.sherpa.onnx."  # the sherpa-onnx library's Java classes, built into the APK
const SHERPA_THREADS := 2  # of the Quest 1's four fast cores; the game keeps the rest
const SHERPA_BUFFER_SECONDS := 0.5  # sound handed to the player ahead of what it is playing

const DEFAULTS := {
	"speak_replies": true,  # read the agent's replies aloud
	"voice": "",  # a voice id from tts_voices; "" picks the first
	"rate": 1.0,
	"pitch": 1.0,
	"volume": 80,
	"tts_engine": "app",  # "app": the headset's speech engine app; "sherpa": sherpa-onnx in Slopitect
	"tts_sherpa_voice": "voices/vits-piper-en_US-amy-low",  # for "sherpa": a Piper voice's folder, in the Slopitect folder
}
const COMFORT := ["speak_replies", "voice", "rate", "pitch", "volume"]  # settings tts_set may change in the headset

# How replies are made sayable (speakable()).
var _speech_drop := [
	RegEx.create_from_string("^#+\\s*"),  # heading marks
	RegEx.create_from_string("^>\\s*"),  # quote marks
	RegEx.create_from_string("^([-*+]|\\d+[.)])\\s+"),  # list bullets and numbers
	RegEx.create_from_string("^\\|?[\\s:|-]+\\|[\\s:|-]*$"),  # a table's ---|--- line
	RegEx.create_from_string("^\\|\\s*|\\s*\\|$"),  # a table row's outer bars
	RegEx.create_from_string("[*~`]+"),  # bold, italic, code and strike marks (underscores become spaces below)
]
var _speech_link := RegEx.create_from_string("\\[([^\\]]*)\\]\\([^)]*\\)")
var _speech_url := RegEx.create_from_string("\\b(?:https?|res|user|file)://\\S+")
var _speech_path := RegEx.create_from_string("(?<![\\w/])(?:[\\w.-]*[A-Za-z][\\w.-]*/)+([\\w.-]+)")
const SPEECH_WORDS := [["->", " to "], ["=>", " to "], ["&", " and "], ["|", ", "], ["_", " "], ["\\", " "]]
var _speech_symbols := RegEx.create_from_string("[^\\p{L}\\p{N}\\s.,!?;:'\"()%°$€£+=/-]")
var _speech_spaces := RegEx.create_from_string("\\s+")

var settings := DEFAULTS.duplicate()

var _voice_cache := []  # the engine's voices, asked once it has some (each ask is a slow call into Android)
var _speech_deadline := 0.0  # when what is being said should have finished; 0 when nothing is
var _since_poll := 0.0
var _seen_reply := ""
var _last := ""  # what happened last, for tts_status

# Playing in the app (see the top).
var _in_app_problem := "not started"  # why speech can't be played in the app; "" when it can
var _java_tts  # android.speech.tts.TextToSpeech
var _java_listener  # its OnInitListener, kept so it isn't collected
var _java_file  # the java.io.File class
var _init_status := ENGINE_NOT_HEARD  # onInit's status: 0 ready, anything else failed
var _waiting := []  # what to say once the engine is ready: [text, voice]
var _jobs := []  # sentences being written, in order: {path, chars, since, stream}
var _player: AudioStreamPlayer
var _next_id := 0
var _has_word := RegEx.create_from_string("\\w")  # a piece with no letters or digits ("...") isn't a sentence on its own
var _last_written := 0  # when the engine last finished writing a piece (ms)
var _since_files := 0.0
var _voice_set := ""  # the voice the in-app engine was last set to

# Speech made by sherpa-onnx (tts_engine "sherpa"; see the top).
var _sherpa  # its OfflineTts (a Java object); made and used only on _sherpa_thread
var _sherpa_voice := ""  # the voice folder _sherpa has loaded
var _sherpa_thread: Thread  # makes the speech, one sentence at a time
var _sherpa_wake := Semaphore.new()  # posted when there is a sentence for it, or it should end
var _sherpa_lock := Mutex.new()  # guards the five below
var _sherpa_queue := []  # sentences waiting to be made: [text, speed]
var _sherpa_made := []  # made, waiting to play: [samples, sample rate]
var _sherpa_turn := 0  # goes up on each stop, so speech made for what was stopped is dropped
var _sherpa_making := false  # the thread is making a sentence
var _sherpa_quit := false
var _sherpa_unload := false  # give the voice's memory back (the engine was switched away)
var _sherpa_sound := PackedFloat32Array()  # the sentence being played, from _sherpa_at on
var _sherpa_at := 0
var _sherpa_rate := 0  # the sample rate the player's stream is set up for
var _sherpa_ends_at := 0.0  # when the sound handed to the player runs out
var _sherpa_in_build := -1  # whether the APK has sherpa-onnx: -1 not checked yet, 0 no, 1 yes
var _sherpa_problem := ""  # why the voice couldn't be loaded last time, for tts_status


func setup() -> String:
	if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		return "this build has text to speech switched off (audio/general/text_to_speech)"
	_load_settings()
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_in_app_problem = _start_in_app()
	if not _in_app_problem.is_empty():
		print("Slopitect tts: the speech engine plays its own sound (%s)" % _in_app_problem)
	# A reply already there when this loads isn't read out.
	_seen_reply = String(ctx["server"].run({"cmd": "agent_status"}).get("last_reply", ""))
	register("tts_say", _say, "say something aloud through the headset's speech engine: text, optional voice (an id from tts_voices); waits for anything already being said")
	register("tts_stop", _stop_command, "stop speaking, and drop anything waiting to be said")
	register("tts_voices", _voices_command, "the voices the headset's speech engine has")
	register("tts_status", _status, "whether the headset can speak, what it's saying, the settings, and what happened last")
	register("tts_set", _set_command, "a comfort setting, so it changes in the headset too: any of %s" % ", ".join(COMFORT))
	register("tts_config", _config, "from the PC only: show or change any of: %s" % ", ".join(DEFAULTS.keys()))
	print("Slopitect tts: %d speech voices; reading replies %s" % [_voice_list().size(), "on" if settings["speak_replies"] else "off"])
	return ""


func _exit_tree() -> void:
	if _sherpa_thread and _sherpa_thread.is_started():
		_sherpa_lock.lock()
		_sherpa_quit = true
		_sherpa_lock.unlock()
		_sherpa_wake.post()
		_sherpa_thread.wait_to_finish()
	DisplayServer.tts_stop()
	if _java_tts != null:
		_stop_in_app()
		_java_tts.shutdown()


func settings_info() -> Dictionary:
	var voices := [{"label": "First", "value": ""}]
	for v in _voice_list():
		voices.append({"label": String(v["name"]).left(16), "value": v["id"]})
	var list := [
		{"id": "speak_replies", "type": "toggle", "label": "Read replies aloud", "value": settings["speak_replies"],
			"set": {"cmd": "tts_set", "speak_replies": "{value}"}},
		{"id": "rate", "type": "slider", "label": "Speed", "value": settings["rate"], "min": 0.5, "max": 2.0, "step": 0.1,
			"set": {"cmd": "tts_set", "rate": "{value}"}},
		{"id": "pitch", "type": "slider", "label": "Pitch", "value": settings["pitch"], "min": 0.5, "max": 1.5, "step": 0.1,
			"set": {"cmd": "tts_set", "pitch": "{value}"}},
		{"id": "volume", "type": "slider", "label": "Volume", "value": settings["volume"], "min": 0, "max": 100, "step": 10,
			"set": {"cmd": "tts_set", "volume": "{value}"}},
	]
	if voices.size() > 2:
		list.append({"id": "voice", "type": "choice", "label": "Voice", "value": settings["voice"], "options": voices, "columns": 2,
			"set": {"cmd": "tts_set", "voice": "{value}"}})
	list.append({"id": "test", "type": "button", "label": "Test the voice", "set": {"cmd": "tts_say", "text": "This is how I sound."}})
	list.append({"id": "hush", "type": "button", "label": "Stop speaking", "set": {"cmd": "tts_stop"}})
	return {"title": "Speech out", "order": 40, "settings": list}


func _process(delta: float) -> void:
	_since_files += delta
	if _since_files >= FILE_POLL_SECONDS:
		_since_files = 0.0
		_update_in_app()
	if settings["tts_engine"] == "sherpa":
		_sherpa_play()
	_since_poll += delta
	if _since_poll < POLL_SECONDS:
		return
	_since_poll = 0.0
	_check_speech()
	# Read the agent's new replies aloud.
	var status: Dictionary = ctx["server"].run({"cmd": "agent_status"})
	if not status.get("ok", false):
		return
	var reply := String(status.get("last_reply", ""))
	if reply == _seen_reply:
		return
	_seen_reply = reply
	if settings["speak_replies"] and not reply.is_empty():
		var problem := speak(reply, "", true)  # a new reply replaces one still being read
		if not problem.is_empty():
			_note(problem)


# Asked again only while the engine has none (it may still be starting) or
# when tts_voices asks for a fresh list.
func _voice_list(fresh := false) -> Array:
	if fresh or _voice_cache.is_empty():
		_voice_cache = DisplayServer.tts_get_voices()
	return _voice_cache


# For other modules: says text aloud; "" when it's on its way, or why not.
# interrupt stops what is being said first; otherwise it waits its turn.
func speak(text: String, voice := "", interrupt := false) -> String:
	text = speakable(text).left(MAX_SAY)
	if text.is_empty():
		return ""
	if settings["tts_engine"] == "sherpa":
		return _sherpa_speak(text, interrupt)
	if _in_app_problem.is_empty():
		if interrupt:
			_stop_in_app()
		_waiting.append([text, voice])
		return ""
	var voices := _voice_list()
	if voices.is_empty():
		return "the headset has no text-to-speech voices (no speech engine installed, or it isn't ready yet)"
	if voice.is_empty():
		voice = settings["voice"]
	if voice.is_empty() or not voices.any(func(v): return v["id"] == voice):
		voice = voices[0]["id"]
	var now := Time.get_ticks_msec() / 1000.0
	var seconds := SPEECH_GRACE_SECONDS + text.length() * SPEECH_SECONDS_PER_CHAR / float(settings["rate"])
	# Queued speech starts after what is already being said.
	_speech_deadline = (maxf(_speech_deadline, now) if not interrupt and _speech_deadline > 0.0 else now) + seconds
	DisplayServer.tts_speak(text, voice, int(settings["volume"]), float(settings["pitch"]), float(settings["rate"]), 0, interrupt)
	return ""


# For other modules: the part of a text that should be said aloud. The
# chat window still shows everything; this leaves out what a voice would
# read as noise: code blocks (said as "the code is in the chat"), markdown
# marks, list bullets, table bars, web addresses and file paths (only
# their last part), emoji and other symbols. Each line becomes a sentence.
func speakable(text: String) -> String:
	var had_code := false
	var lines := PackedStringArray()
	var in_code := false
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("```"):
			in_code = not in_code
			had_code = true
			continue
		if in_code or line.is_empty():
			continue
		line = _speech_line(line)
		if line.is_empty():
			continue
		# A line without its own full stop (a heading, a list item) ends a sentence.
		if not line[line.length() - 1] in [".", "!", "?", ":", ";", ","]:
			line += "."
		lines.append(line)
	if had_code:
		lines.append("The code is in the chat.")
	return " ".join(lines)


func _speech_line(line: String) -> String:
	for pattern in _speech_drop:
		line = pattern.sub(line, "", true)
	line = _speech_link.sub(line, "$1", true)  # [words](address) -> words
	line = _speech_url.sub(line, "a link", true)
	line = _speech_path.sub(line, "$1", true)  # folder/name.gd -> name.gd
	for pair in SPEECH_WORDS:
		line = line.replace(pair[0], pair[1])
	line = _speech_symbols.sub(line, " ", true)
	return _speech_spaces.sub(line, " ", true).replace(" ,", ",").strip_edges()


# For other modules: whether something is being said (or about to be).
func speaking() -> bool:
	if settings["tts_engine"] == "sherpa":
		_sherpa_lock.lock()
		var busy := _sherpa_making or not _sherpa_queue.is_empty() or not _sherpa_made.is_empty()
		_sherpa_lock.unlock()
		return busy or _sherpa_at < _sherpa_sound.size() or Time.get_ticks_msec() / 1000.0 < _sherpa_ends_at
	if _in_app_problem.is_empty():
		return _player.playing or not _jobs.is_empty() or not _waiting.is_empty()
	return _speech_deadline > 0.0 and DisplayServer.tts_is_speaking()


# --- Speech made by sherpa-onnx (tts_engine "sherpa") ------------------------------

func _sherpa_built_in() -> bool:
	if _sherpa_in_build == -1:
		_sherpa_in_build = 0
		if OS.get_name() == "Android" and Engine.has_singleton("JavaClassWrapper"):
			var found = Engine.get_singleton("JavaClassWrapper").wrap(SHERPA_PACKAGE + "OfflineTts")
			_sherpa_in_build = 1 if found != null else 0
	return _sherpa_in_build == 1


# A path inside the Slopitect folder.
func _home_path(path: String) -> String:
	var files: SlopitectModule = ctx["modules"].module("files")
	var home: String = files.get("_home") if files else ""
	if home.is_empty():
		home = "/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home"
	return home.path_join(path)


# A Piper voice's files in its folder: one .onnx model, tokens.txt, and how
# words become sounds (an espeak-ng-data folder, or a lexicon.txt).
# {"error": why} when the folder doesn't have them.
func _sherpa_files(folder: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(folder):
		return {"error": "no voice folder at %s: put a Piper voice there (like vits-piper-en_US-amy-low), or set tts_sherpa_voice" % folder}
	var names := DirAccess.get_files_at(folder)
	if not "tokens.txt" in names:
		return {"error": "the voice folder %s has no tokens.txt" % folder}
	var models := Array(names).filter(func(name: String) -> bool: return name.ends_with(".onnx"))
	if models.size() != 1:
		return {"error": "the voice folder %s should have one .onnx model; it has %s" % [folder, "none" if models.is_empty() else ", ".join(models)]}
	var found := {"model": folder.path_join(models[0]), "tokens": folder.path_join("tokens.txt")}
	if DirAccess.dir_exists_absolute(folder.path_join("espeak-ng-data")):
		found["data"] = folder.path_join("espeak-ng-data")
	if "lexicon.txt" in names:
		found["lexicon"] = folder.path_join("lexicon.txt")
	if not found.has("data") and not found.has("lexicon"):
		return {"error": "the voice folder %s has neither an espeak-ng-data folder nor a lexicon.txt" % folder}
	return found


func _sherpa_speak(text: String, interrupt: bool) -> String:
	if not _sherpa_built_in():
		return "this build has no sherpa-onnx speech (its library isn't in the APK, or this isn't the headset)"
	var folder := _home_path(settings["tts_sherpa_voice"])
	var problem: String = _sherpa_files(folder).get("error", "")
	if not problem.is_empty():
		return problem
	if interrupt:
		_sherpa_stop()
	_sherpa_lock.lock()
	for sentence in _sherpa_sentences(text):
		_sherpa_queue.append([sentence, float(settings["rate"]), folder])
	_sherpa_lock.unlock()
	if _sherpa_thread == null:
		_sherpa_thread = Thread.new()
		_sherpa_thread.start(_sherpa_work)
	_sherpa_wake.post()
	return ""


# One piece per sentence: each is made while the one before it plays. A
# piece with no letters or digits ("...") goes with the next.
func _sherpa_sentences(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var regex := RegEx.create_from_string("[^.!?\\n]*[.!?]+\\s*|[^.!?\\n]+|\\n+")
	for m in regex.search_all(text):
		current += m.get_string()
		if _has_word.search(current):
			out.append(current.strip_edges())
			current = ""
	if not current.strip_edges().is_empty():
		out.append(current.strip_edges())
	return out


# Drops what is waiting and being played; a sentence being made is dropped
# when it's done.
func _sherpa_stop() -> void:
	_sherpa_lock.lock()
	_sherpa_turn += 1
	_sherpa_queue.clear()
	_sherpa_made.clear()
	_sherpa_lock.unlock()
	_sherpa_sound = PackedFloat32Array()
	_sherpa_at = 0
	_sherpa_ends_at = 0.0
	if _player.stream is AudioStreamGenerator:
		_player.stop()


# Runs on the thread: the only place _sherpa is made or used.
func _sherpa_work() -> void:
	while true:
		_sherpa_wake.wait()
		while true:
			_sherpa_lock.lock()
			if _sherpa_quit:
				_sherpa_lock.unlock()
				if _sherpa:
					_sherpa.release()
				return
			if _sherpa_unload:
				_sherpa_unload = false
				if _sherpa:
					_sherpa.release()
					_sherpa = null
					_sherpa_voice = ""
			if _sherpa_queue.is_empty():
				_sherpa_lock.unlock()
				break
			var item: Array = _sherpa_queue.pop_front()
			var turn := _sherpa_turn
			_sherpa_making = true
			_sherpa_lock.unlock()
			_sherpa_make(item, turn)
			_sherpa_lock.lock()
			_sherpa_making = false
			_sherpa_lock.unlock()


# Runs on the thread: makes one sentence's sound, loading the voice first
# if it isn't loaded.
func _sherpa_make(item: Array, turn: int) -> void:
	var text: String = item[0]
	var folder: String = item[2]
	if folder != _sherpa_voice:
		var started := Time.get_ticks_msec()
		var problem := _sherpa_load(folder)
		if not problem.is_empty():
			_sherpa_lock.lock()
			_sherpa_queue.clear()
			_sherpa_lock.unlock()
			call_deferred("_sherpa_failed", "couldn't load the voice %s: %s" % [folder, problem])
			return
		print("Slopitect tts: loaded the voice %s in %d ms" % [folder, Time.get_ticks_msec() - started])
	var wrapper = Engine.get_singleton("JavaClassWrapper")
	var started := Time.get_ticks_msec()
	var audio = _sherpa.generate(text, 0, float(item[1]))
	var took := Time.get_ticks_msec() - started
	if audio == null:
		call_deferred("_sherpa_failed", "couldn't make speech for \"%s\" (%s)" % [text.left(60), _java_error(wrapper)])
		return
	var samples: PackedFloat32Array = audio.getSamples()
	var rate := int(audio.getSampleRate())
	var seconds := samples.size() / float(maxi(rate, 1))
	print("Slopitect tts: made %d characters (%.1f s of speech) in %d ms (x%.2f)" % [text.length(), seconds, took, took / maxf(seconds * 1000.0, 1.0)])
	_sherpa_lock.lock()
	if turn == _sherpa_turn and not samples.is_empty():
		_sherpa_made.append([samples, rate])
	_sherpa_lock.unlock()


# Runs on the thread: makes the OfflineTts for the voice in folder; "" when
# it worked, or why not.
func _sherpa_load(folder: String) -> String:
	var files := _sherpa_files(folder)
	if files.has("error"):
		return files["error"]
	var wrapper = Engine.get_singleton("JavaClassWrapper")
	var config = wrapper.wrap(SHERPA_PACKAGE + "OfflineTtsConfig").OfflineTtsConfig()
	if config == null:
		return "couldn't make an OfflineTtsConfig (%s)" % _java_error(wrapper)
	var model = config.getModel()
	var vits = model.getVits()
	vits.setModel(files["model"])
	vits.setTokens(files["tokens"])
	if files.has("data"):
		vits.setDataDir(files["data"])
	if files.has("lexicon"):
		vits.setLexicon(files["lexicon"])
	model.setNumThreads(SHERPA_THREADS)
	if _sherpa:
		_sherpa.release()
		_sherpa = null
		_sherpa_voice = ""
	_sherpa = wrapper.wrap(SHERPA_PACKAGE + "OfflineTts").OfflineTts(null, config)
	if _sherpa == null:
		return "the library wouldn't load it (%s)" % _java_error(wrapper)
	_sherpa_voice = folder
	return ""


func _sherpa_failed(problem: String) -> void:
	_sherpa_problem = problem
	_note(problem)


# Every frame: keeps the player's stream topped up with the sentences made.
func _sherpa_play() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _sherpa_at >= _sherpa_sound.size():
		_sherpa_lock.lock()
		var next: Array = _sherpa_made.pop_front() if not _sherpa_made.is_empty() else []
		_sherpa_lock.unlock()
		if next.is_empty():
			# Nothing more to say: the player stops once its sound has run out.
			if _player.playing and _player.stream is AudioStreamGenerator and now > _sherpa_ends_at + SHERPA_BUFFER_SECONDS:
				_player.stop()
			return
		_sherpa_sound = next[0]
		_sherpa_at = 0
		if next[1] != _sherpa_rate or not _player.stream is AudioStreamGenerator or not _player.playing:
			var stream := AudioStreamGenerator.new()
			stream.mix_rate = next[1]
			stream.buffer_length = SHERPA_BUFFER_SECONDS
			_player.stream = stream
			_player.play()
			_sherpa_rate = next[1]
	_player.volume_db = linear_to_db(maxf(float(settings["volume"]) / 100.0, 0.001))
	var playback := _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var count := mini(playback.get_frames_available(), _sherpa_sound.size() - _sherpa_at)
	if count <= 0:
		return
	var frames := PackedVector2Array()
	frames.resize(count)
	for i in count:
		var sample := _sherpa_sound[_sherpa_at + i]
		frames[i] = Vector2(sample, sample)
	playback.push_buffer(frames)
	_sherpa_at += count
	var queued := int(SHERPA_BUFFER_SECONDS * _sherpa_rate) - playback.get_frames_available()
	_sherpa_ends_at = now + maxi(queued, 0) / float(_sherpa_rate)


# --- Playing in the app ---------------------------------------------------------

# Makes the engine's TextToSpeech; "" when it worked, or why not.
func _start_in_app() -> String:
	if OS.get_name() != "Android":
		return "not on Android"
	if not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"):
		return "this build has no AndroidRuntime or JavaClassWrapper"
	var wrapper = Engine.get_singleton("JavaClassWrapper")
	var app = Engine.get_singleton("AndroidRuntime").getApplicationContext()
	if app == null:
		return "Android gave no application context"
	# onInit comes on an Android thread; it only sets the status.
	_java_listener = wrapper.create_sam_callback("android.speech.tts.TextToSpeech$OnInitListener", func(status: int) -> void: _init_status = status)
	if _java_listener == null:
		return "couldn't make the OnInitListener (%s)" % _java_error(wrapper)
	_java_tts = wrapper.wrap("android.speech.tts.TextToSpeech").TextToSpeech(app, _java_listener)
	if _java_tts == null:
		return "couldn't make a TextToSpeech (%s)" % _java_error(wrapper)
	_java_file = wrapper.wrap("java.io.File")
	if _java_file == null:
		return "couldn't reach java.io.File (%s)" % _java_error(wrapper)
	print("Slopitect tts: speech will play in the app; waiting for the speech engine to start")
	return ""


func _java_error(wrapper) -> String:
	var e = wrapper.get_exception()
	return "no Java exception" if e == null else String(e.toString())


# Hands what's waiting to the engine once it's ready, turns written files
# into sound, and plays them in order.
func _update_in_app() -> void:
	if not _in_app_problem.is_empty():
		return
	if _init_status == ENGINE_NOT_HEARD:
		return
	if _init_status != 0:
		_in_app_problem = "the speech engine failed to start (onInit status %d)" % _init_status
		_note(_in_app_problem + "; the engine plays its own sound instead")
		var waiting := _waiting.duplicate()
		_waiting.clear()
		for item in waiting:
			speak(item[0], item[1])
		return
	while not _waiting.is_empty():
		var item: Array = _waiting.pop_front()
		_write(item[0], item[1])
	var now := Time.get_ticks_msec() / 1000.0
	for job in _jobs:
		if job["stream"] == null and _written(job["path"]):
			job["stream"] = AudioStreamWAV.load_from_file(job["path"])
			DirAccess.remove_absolute(job["path"])
			if job["stream"] == null:
				job["stream"] = false
				_note("the speech engine wrote a sound file Godot couldn't read")
			else:
				# How fast the engine writes: it writes one piece at a time, so
				# a piece takes from when the one before it was done.
				var done := Time.get_ticks_msec()
				var took := done - maxi(job["asked"], _last_written)
				_last_written = done
				print("Slopitect tts: wrote %d characters (%.1f s of speech) in %d ms; %d ms after it was asked for" % [job["chars"], job["stream"].get_length(), took, done - job["asked"]])
	if _jobs.is_empty() or _player.playing:
		return
	var head: Dictionary = _jobs[0]
	if head["stream"] == null:
		# Written in order, so the first is late only if the engine is stuck.
		if now - head["since"] > SPEECH_GRACE_SECONDS + head["chars"] * SPEECH_SECONDS_PER_CHAR:
			_note("the speech engine never finished writing a sentence; skipped it")
			DirAccess.remove_absolute(head["path"])
			_jobs.pop_front()
			if not _jobs.is_empty():
				_jobs[0]["since"] = now
		return
	_jobs.pop_front()
	if not _jobs.is_empty():
		_jobs[0]["since"] = now
	if head["stream"] is AudioStreamWAV:
		_player.stream = head["stream"]
		_player.volume_db = linear_to_db(maxf(float(settings["volume"]) / 100.0, 0.001))
		_player.play()
		if head["first"]:
			print("Slopitect tts: started speaking %d ms after it was asked to" % (Time.get_ticks_msec() - head["asked"]))


# Asks the engine to write each sentence of text to its own file.
func _write(text: String, voice: String) -> void:
	var wrapper = Engine.get_singleton("JavaClassWrapper")
	_java_tts.setSpeechRate(float(settings["rate"]))
	_java_tts.setPitch(float(settings["pitch"]))
	if voice.is_empty():
		voice = settings["voice"]
	if voice != _voice_set:
		_voice_set = voice
		if not voice.is_empty():
			_set_java_voice(voice)
	var now := Time.get_ticks_msec() / 1000.0
	var first := true
	for sentence in _sentences(text):
		_next_id += 1
		var path := OS.get_cache_dir().path_join("slopitect-speech-%d.wav" % _next_id)
		DirAccess.remove_absolute(path)
		var result = _java_tts.synthesizeToFile(sentence, null, _java_file.File(path), "slopitect-%d" % _next_id)
		if typeof(result) != TYPE_INT or result != 0:
			_note("the speech engine wouldn't write the speech (synthesizeToFile gave %s; %s)" % [str(result), _java_error(wrapper)])
			return
		_jobs.append({"path": path, "chars": sentence.length(), "since": now, "stream": null, "asked": Time.get_ticks_msec(), "first": first})
		first = false


func _set_java_voice(voice: String) -> void:
	var voices = _java_tts.getVoices()
	if voices == null:
		_note("the speech engine listed no voices; using its default")
		return
	for v in voices.toArray():
		if String(v.getName()) == voice:
			_java_tts.setVoice(v)
			return
	_note("the speech engine has no voice \"%s\"; using its default" % voice)


# Sentences joined up to about SENTENCE_CHARS, so the first can play while
# the engine writes the rest.
func _sentences(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var regex := RegEx.create_from_string("[^.!?\\n]*[.!?]+\\s*|[^.!?\\n]+|\\n+")
	for m in regex.search_all(text):
		var piece := m.get_string()
		if not current.is_empty() and current.length() + piece.length() > SENTENCE_CHARS:
			out.append(current.strip_edges())
			current = ""
		current += piece
	if not current.strip_edges().is_empty():
		out.append(current.strip_edges())
	return out


# The engine writes the WAV header last, over zeros, when it has finished.
func _written(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 44:
		return false
	return file.get_buffer(4).get_string_from_ascii() == "RIFF"


func _stop_in_app() -> void:
	if _java_tts != null:
		_java_tts.stop()
	_player.stop()
	for job in _jobs:
		DirAccess.remove_absolute(job["path"])
	_jobs.clear()
	_waiting.clear()


# Speech the engine never finished blocks everything said after it, so it is
# stopped, and the next thing said goes through.
func _check_speech() -> void:
	if _speech_deadline == 0.0:
		return
	if not DisplayServer.tts_is_speaking():
		_speech_deadline = 0.0
		return
	if Time.get_ticks_msec() / 1000.0 < _speech_deadline:
		return
	_speech_deadline = 0.0
	DisplayServer.tts_stop()
	_note("the speech engine never said it finished speaking (it may have been closed); stopped it so the next speech can play")
	push_warning("Slopitect tts: the speech engine never finished an utterance; reset its queue")


func _say(request: Dictionary) -> Dictionary:
	var text = request.get("text")
	if typeof(text) != TYPE_STRING or text.strip_edges().is_empty():
		return {"ok": false, "error": "tts_say needs \"text\""}
	var voice = request.get("voice", "")
	if typeof(voice) != TYPE_STRING:
		return {"ok": false, "error": "\"voice\" must be a voice id from tts_voices"}
	var problem := speak(text, voice)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return {"ok": true}


func _stop_command(_request: Dictionary) -> Dictionary:
	_sherpa_stop()
	DisplayServer.tts_stop()
	if _in_app_problem.is_empty():
		_stop_in_app()
	_speech_deadline = 0.0
	return {"ok": true}


func _voices_command(_request: Dictionary) -> Dictionary:
	var voices := []
	for v in _voice_list(true):
		voices.append({"id": v["id"], "name": v["name"], "language": v["language"]})
	return {"ok": true, "voices": voices}


func _status(_request: Dictionary) -> Dictionary:
	var engine_speaking := DisplayServer.tts_is_speaking() if not _voice_list().is_empty() else false
	return {
		"ok": true,
		"voices": _voice_list().size(),
		"speaking": speaking() if _in_app_problem.is_empty() else engine_speaking,
		"plays": "in the app" if _in_app_problem.is_empty() else "through the speech engine (%s)" % _in_app_problem,
		"engine_started": "not yet" if _init_status == ENGINE_NOT_HEARD else ("yes" if _init_status == 0 else "failed (%d)" % _init_status),
		"sentences_waiting": _jobs.size() + _waiting.size(),
		"speech_should_end_in": maxf(_speech_deadline - Time.get_ticks_msec() / 1000.0, 0.0) if _speech_deadline > 0.0 else 0.0,
		"settings": settings,
		"sherpa_in_build": _sherpa_built_in(),
		"sherpa_voice": _home_path(settings["tts_sherpa_voice"]),
		"sherpa_voice_problem": _sherpa_files(_home_path(settings["tts_sherpa_voice"])).get("error", ""),
		"sherpa_voice_loaded": not _sherpa_voice.is_empty(),
		"sherpa_last_problem": _sherpa_problem,
		"last": _last,
	}


func _set_command(request: Dictionary) -> Dictionary:
	for key in request:
		if key in ["cmd", "id"]:
			continue
		if not key in COMFORT:
			return {"ok": false, "error": "tts_set changes only %s; \"%s\" changes from the PC with tts_config" % [", ".join(COMFORT), key]}
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
		var value = request[key]
		if key == "volume" and typeof(value) == TYPE_FLOAT:
			value = int(round(value))  # a slider gives a float
		var problem := _check_setting(key, value)
		if not problem.is_empty():
			return {"ok": false, "error": problem}
		changes[key] = value
	for key in changes:
		settings[key] = changes[key]
	if not changes.is_empty():
		_save_settings()
	if changes.has("speak_replies") and not settings["speak_replies"]:
		_stop_command({})
	if changes.has("tts_engine") or changes.has("tts_sherpa_voice"):
		_stop_command({})
		if settings["tts_engine"] != "sherpa" and _sherpa_thread:
			_sherpa_lock.lock()
			_sherpa_unload = true
			_sherpa_lock.unlock()
			_sherpa_wake.post()
	return {"ok": true, "settings": settings}


func _check_setting(key: String, value) -> String:
	match key:
		"speak_replies":
			if typeof(value) != TYPE_BOOL:
				return "\"speak_replies\" must be true or false"
		"voice":
			if typeof(value) != TYPE_STRING or value.length() > 300:
				return "\"voice\" must be a voice id from tts_voices, or \"\" for the first"
		"rate":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < 0.1 or value > 10.0:
				return "\"rate\" must be 0.1 to 10"
		"pitch":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < 0.0 or value > 2.0:
				return "\"pitch\" must be 0 to 2"
		"volume":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < 0 or value > 100:
				return "\"volume\" must be 0 to 100"
		"tts_engine":
			if not value in ["app", "sherpa"]:
				return "\"tts_engine\" must be \"app\" (the headset's speech engine app) or \"sherpa\" (sherpa-onnx in Slopitect)"
		"tts_sherpa_voice":
			if typeof(value) != TYPE_STRING or value.is_empty() or value.begins_with("/") or ".." in value or "\\" in value or "://" in value:
				return "\"tts_sherpa_voice\" must be a voice's folder inside the Slopitect folder, like \"voices/vits-piper-en_US-amy-low\""
	return ""


func _note(text: String) -> void:
	_last = text
	print("Slopitect tts: ", text)


# Its own file, or the voice settings the APK kept before (only the keys
# this module has); a broken file is kept aside and the defaults used.
func _load_settings() -> void:
	var path := SETTINGS_PATH if FileAccess.file_exists(SETTINGS_PATH) else OLD_SETTINGS_PATH
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		_set_aside(path, "not a JSON object")
		return
	for key in json.data:
		if not DEFAULTS.has(key):
			if path == SETTINGS_PATH:
				_set_aside(path, "unknown setting \"%s\"" % key)
				settings = DEFAULTS.duplicate()
				return
			continue
		var problem := _check_setting(key, json.data[key])
		if not problem.is_empty():
			_set_aside(path, problem)
			settings = DEFAULTS.duplicate()
			return
		settings[key] = json.data[key]
	if path == OLD_SETTINGS_PATH:
		_save_settings()


func _set_aside(path: String, problem: String) -> void:
	if path != SETTINGS_PATH:
		push_warning("Slopitect tts: %s is broken (%s); used the defaults" % [path, problem])
		return
	DirAccess.rename_absolute(path, path + ".bad")
	push_error("Slopitect tts: %s is broken (%s); kept it as %s and used the defaults" % [path, problem, path + ".bad"])


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Slopitect tts: could not save %s (%s)" % [SETTINGS_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(settings, "  "))
	file.close()
