extends SlopitectModule

# Slopitect live module: tts (text to speech).
# The agent's replies are read aloud by the headset's own text-to-speech
# engine (an Android app such as SherpaTTS; tts_status says how many voices
# it has), and anything can speak with tts_say. Its settings (reading
# replies, voice, rate, pitch, volume) are comfort settings: they change in
# the headset's Settings window or with tts_set.
#
# Godot's Android speech sends the next utterance only after the engine says
# the last one is done. An engine that never says so (its process closed, or
# it dropped one) would hold everything after it silent, so speech that runs
# far past what its text could take is stopped and logged.

const SETTINGS_PATH := "user://tts.json"
const OLD_SETTINGS_PATH := "user://voice.json"  # the APK's voice module kept these before
const POLL_SECONDS := 0.5
const MAX_SAY := 2000
const SPEECH_GRACE_SECONDS := 15.0
const SPEECH_SECONDS_PER_CHAR := 0.2  # far slower than any voice at rate 1

const DEFAULTS := {
	"speak_replies": true,  # read the agent's replies aloud
	"voice": "",  # a voice id from tts_voices; "" picks the first
	"rate": 1.0,
	"pitch": 1.0,
	"volume": 80,
}

var settings := DEFAULTS.duplicate()

var _voice_cache := []  # the engine's voices, asked once it has some (each ask is a slow call into Android)
var _speech_deadline := 0.0  # when what is being said should have finished; 0 when nothing is
var _since_poll := 0.0
var _seen_reply := ""
var _last := ""  # what happened last, for tts_status


func setup() -> String:
	if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		return "this build has text to speech switched off (audio/general/text_to_speech)"
	_load_settings()
	# A reply already there when this loads isn't read out.
	_seen_reply = String(ctx["server"].run({"cmd": "agent_status"}).get("last_reply", ""))
	register("tts_say", _say, "say something aloud through the headset's speech engine: text, optional voice (an id from tts_voices); waits for anything already being said")
	register("tts_stop", _stop_command, "stop speaking, and drop anything waiting to be said")
	register("tts_voices", _voices_command, "the voices the headset's speech engine has")
	register("tts_status", _status, "whether the headset can speak, what it's saying, the settings, and what happened last")
	register("tts_set", _set_command, "a comfort setting, so it changes in the headset too: any of %s" % ", ".join(DEFAULTS.keys()))
	print("Slopitect tts: %d speech voices; reading replies %s" % [_voice_list().size(), "on" if settings["speak_replies"] else "off"])
	return ""


func _exit_tree() -> void:
	DisplayServer.tts_stop()


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
	var voices := _voice_list()
	if voices.is_empty():
		return "the headset has no text-to-speech voices (no speech engine installed, or it isn't ready yet)"
	if voice.is_empty():
		voice = settings["voice"]
	if voice.is_empty() or not voices.any(func(v): return v["id"] == voice):
		voice = voices[0]["id"]
	text = text.left(MAX_SAY)
	var now := Time.get_ticks_msec() / 1000.0
	var seconds := SPEECH_GRACE_SECONDS + text.length() * SPEECH_SECONDS_PER_CHAR / float(settings["rate"])
	# Queued speech starts after what is already being said.
	_speech_deadline = (maxf(_speech_deadline, now) if not interrupt and _speech_deadline > 0.0 else now) + seconds
	DisplayServer.tts_speak(text, voice, int(settings["volume"]), float(settings["pitch"]), float(settings["rate"]), 0, interrupt)
	return ""


# For other modules: whether the engine says it is speaking.
func speaking() -> bool:
	return _speech_deadline > 0.0 and DisplayServer.tts_is_speaking()


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
	DisplayServer.tts_stop()
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
		"speaking": engine_speaking,
		"speech_should_end_in": maxf(_speech_deadline - Time.get_ticks_msec() / 1000.0, 0.0) if _speech_deadline > 0.0 else 0.0,
		"settings": settings,
		"last": _last,
	}


func _set_command(request: Dictionary) -> Dictionary:
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
