extends SlopitectModule

# Slopitect live module: audio, the one owner of sound playback.
# Other modules ask it to play a sound instead of making their own players,
# so every sound goes through the same buses, volumes and voice limit.
#
# Kinds of sound (the "mode" of a play):
#   stereo    plain 2D: the same whichever way you face (the default)
#   mono      2D, left and right mixed together (a stereo file centred)
#   surround  2D, spread over every speaker when the output has more than
#             two; the Quest's output is stereo, where it's the same as
#             stereo (on headphones "around you" means spatial)
#   spatial   3D: it comes from a point (at) or a node it follows (follow),
#             and gets quieter with distance and pans as you turn your head
#   proximity zones (zone_add / audio_zone): a sound at a point or node
#             that plays only while you're within its radius, fading in as
#             you come closer; loops, or plays once each time you walk in
#
# Buses, each with a volume in the Settings window ("Sound"): Master, and
# Music, Effects, Voice, Ambient, UI sending into it. A module that keeps
# its own player can still use them: player.bus = audio.bus("music").
# "Mono output" mixes everything to mono, for hearing with one ear.
#
# GDScript API (other modules, through lib.module("audio")):
#   play(sound, options) -> id    sound: an AudioStream, or a file (see
#       below). options: bus ("effects"), volume (0..1), pitch, loop,
#       mode, priority (higher steals from lower when the voices are full),
#       and for spatial: at (Vector3), follow (Node3D), max_distance,
#       unit_size (metres at full volume), attenuation (inverse, square,
#       log, none), muffle (true: duller with distance; costs a filter)
#   play_2d(sound, bus, volume, pitch), play_at(sound, position, options),
#   play_on(sound, node, options)   the common cases of play()
#   stop(id, fade), stop_all(fade), playing(id)
#   zone_add(name, sound, where, radius, options), zone_remove(name)
#       where: a Vector3 or a Node3D; options as play() plus inner (metres
#       at full volume) and loop (true)
#   load_sound(sound) -> AudioStream (cached), bus(kind) -> bus name
#   signal sound_finished(id)   a one-shot sound ended (or was stopped)
# -1 as an id means it didn't play; last_error() says why.
#
# Files: an .ogg, .wav or .mp3 in the Slopitect folder's sounds/ by name
# ("chime" or "doors/creak.ogg"), a full path inside the Slopitect folder, or
# res:// / user://. Nothing outside those. The folder needs lib.gd; without
# lib only res://, user:// and AudioStream objects play.
#
# Cost on the Quest 1: mixing is on Godot's audio thread. Here, nothing runs
# per frame unless a playing sound follows a node (then one position copy
# per such sound) and the zone check runs on a timer only while there are
# zones. Players are pooled and reused; doppler is off, and the distance
# filter is off unless a sound asks for muffle.
#
# Settings (user://audio.json): the volumes, mono and mute change in the
# headset (audio_set, the Settings window); the voice limit is PC only
# (audio_config).

signal sound_finished(id: int)

const SETTINGS_PATH := "user://audio.json"
const BUSES := {"music": "Music", "effects": "Effects", "voice": "Voice", "ambient": "Ambient", "ui": "UI"}
const LEVELS := ["master", "music", "effects", "voice", "ambient", "ui"]  # the volume settings, in percent
const DEFAULTS := {"master": 100, "music": 80, "effects": 100, "voice": 100, "ambient": 80, "ui": 70, "mono": false, "muted": false}
const LABELS := {"master": "Master volume (%)", "music": "Music (%)", "effects": "Effects (%)", "voice": "Voice (%)", "ambient": "Ambient (%)", "ui": "Menus and buttons (%)"}
const CONFIG_DEFAULTS := {"max_voices": 24}
const MAX_VOICES := [4, 64]
const MODES := ["stereo", "mono", "surround", "spatial"]
const ATTENUATION := {"inverse": AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE, "square": AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE, "log": AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC, "none": AudioStreamPlayer3D.ATTENUATION_DISABLED}
const EXTENSIONS := ["ogg", "wav", "mp3"]
const CACHE_SIZE := 48  # sounds kept loaded; the least recently played goes first
const ZONE_CHECK := 0.2  # seconds between checks of how near you are to the zones
const ZONE_LEAVE := 1.15  # a zone stops once you're this many radii away, so its edge doesn't flicker
const TEST_DIRECTIONS := {"left": Vector3.LEFT, "right": Vector3.RIGHT, "front": Vector3.FORWARD, "behind": Vector3.BACK, "above": Vector3.UP, "below": Vector3.DOWN}
const TEST_DISTANCE := 1.5
const MONO_SUFFIX := " Mono"

var settings := DEFAULTS.duplicate()
var config := CONFIG_DEFAULTS.duplicate()
var _lib: SlopitectModule
var _holder: Node3D  # the players live here
var _voices := {}  # id -> {player, id, priority, loop, started, follow, zone, sound, bus, tween}
var _voice_of := {}  # player -> id
var _free_2d: Array[AudioStreamPlayer] = []
var _free_3d: Array[AudioStreamPlayer3D] = []
var _following := 0  # playing voices that follow a node (_process runs while there are any)
var _next_id := 1
var _cache := {}  # path (+ "#loop") -> AudioStream, least recently used first
var _zones := {}  # name -> {name, sound, at, follow, radius, inner, loop, options, id, inside}
var _zone_timer: Timer
var _made_buses: Array[String] = []  # buses this module added (and takes away again)
var _mono_effect: AudioEffectStereoEnhance  # on Master while "mono" is on
var _master_before := {"volume_db": 0.0, "mute": false}
var _beep: AudioStreamWAV
var _last_error := ""


func setup() -> String:
	set_process(false)  # on while a sound follows a node
	_holder = Node3D.new()
	_holder.name = "Sounds"
	add_child(_holder)
	_zone_timer = Timer.new()
	_zone_timer.wait_time = ZONE_CHECK
	_zone_timer.timeout.connect(_check_zones)
	add_child(_zone_timer)
	var master := AudioServer.get_bus_index("Master")
	_master_before = {"volume_db": AudioServer.get_bus_volume_db(master), "mute": AudioServer.is_bus_mute(master)}
	for kind in BUSES:
		_make_bus(BUSES[kind], "Master")
	_apply()
	register("audio_status", _status, "sound: the buses and their volumes, the speakers, what's playing, the proximity zones and the voice limit")
	register("audio_play", _play_command, "play a sound: sound (a name in the Slopitect folder's sounds/, or a path there or res:// / user://), optional bus (music, effects, voice, ambient, ui), volume 0..1, pitch, loop, mode (stereo, mono, surround, spatial), at [x,y,z] or follow (a thing's name) for spatial, max_distance, unit_size, attenuation (inverse, square, log, none), muffle, priority")
	register("audio_stop", _stop_command, "stop a sound: id (from audio_play), or all true; optional fade (seconds)")
	register("audio_zone", _zone_command, "a proximity sound that plays only while you're near: name, sound, at [x,y,z] or follow (a thing's name), radius (m), optional inner (m at full volume), loop (default true; false plays once each time you walk in), bus, volume; or name and remove true")
	register("audio_sounds", _sounds_command, "the sound files in the Slopitect folder's sounds/ (ogg, wav, mp3)")
	register("audio_test", _test_command, "a short beep to check where sound comes from: where = left, right, front, behind, above, below (1.5 m from your head) or center (2D); optional bus")
	register("audio_set", _set_command, "a comfort setting, so it changes in the headset too: master, music, effects, voice, ambient, ui (volume 0 to 100), mono (true: everything mixed to mono), muted (true or false)")
	register("audio_config", _config, "from the PC only: max_voices (%d to %d sounds at once; past it the lowest priority, then the oldest, stops)" % MAX_VOICES)
	return ""


func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		return
	_load()
	_apply()
	lib.touch(self)


func _exit_tree() -> void:
	stop_all()
	if _zone_timer.timeout.is_connected(_check_zones):
		_zone_timer.timeout.disconnect(_check_zones)
	_zones.clear()
	_set_mono_output(false)
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, _master_before["volume_db"])
	AudioServer.set_bus_mute(master, _master_before["mute"])
	_made_buses.reverse()  # mono buses send into the others: they go first
	for bus_name in _made_buses:
		var index := AudioServer.get_bus_index(bus_name)
		if index > 0:
			AudioServer.remove_bus(index)
	_made_buses.clear()
	# The players are children of _holder and go with it.


func _process(_delta: float) -> void:
	for voice in _voices.values():
		if not voice["follows"]:
			continue
		var node = voice["follow"]  # untyped: it may have been freed (a freed node also equals null)
		if not is_instance_valid(node) or not node.is_inside_tree():
			voice["follows"] = false  # its node is gone: let the sound go too
			_following -= 1
			_stop_voice.call_deferred(voice["id"], 0.1)
			continue
		voice["player"].global_position = node.global_position
	if _following <= 0:
		_following = 0
		set_process(false)


# --- Playing --------------------------------------------------------------------

func play(sound, options := {}) -> int:
	_last_error = ""
	var problem := _check_options(options)
	if not problem.is_empty():
		return _fail(problem)
	var loop: bool = options.get("loop", false)
	var stream := load_sound(sound, loop)
	if stream == null:
		return -1
	var priority := int(options.get("priority", 0))
	if not _make_room(priority):
		return _fail("all %d voices are playing sounds of higher priority" % config["max_voices"])
	var mode: String = options.get("mode", "spatial" if options.has("at") or options.has("follow") else "stereo")
	var bus_name := bus(options.get("bus", "effects"))
	var player: Node
	if mode == "spatial":
		var p3 := _take_3d()
		p3.max_distance = float(options.get("max_distance", 30.0))
		p3.unit_size = float(options.get("unit_size", 2.0))
		p3.attenuation_model = ATTENUATION[options.get("attenuation", "inverse")]
		p3.attenuation_filter_db = -24.0 if options.get("muffle", false) else 0.0  # 0 dB: no filter at all
		var follow = options.get("follow")
		p3.global_position = follow.global_position if follow is Node3D else options.get("at", Vector3.ZERO)
		player = p3
	else:
		var p2 := _take_2d()
		p2.mix_target = AudioStreamPlayer.MIX_TARGET_SURROUND if mode == "surround" and AudioServer.get_speaker_mode() != AudioServer.SPEAKER_MODE_STEREO else AudioStreamPlayer.MIX_TARGET_STEREO
		if mode == "mono":
			bus_name = _mono_bus(bus_name)
		player = p2
	player.stream = stream
	player.bus = bus_name
	var volume := float(options.get("volume", 1.0))
	player.volume_db = linear_to_db(volume) if volume > 0.0 else -80.0
	player.pitch_scale = float(options.get("pitch", 1.0))
	var id := _next_id
	_next_id += 1
	var voice := {"player": player, "id": id, "priority": priority, "loop": loop, "started": Time.get_ticks_msec(),
		"follow": null, "follows": false, "zone": options.get("zone", ""), "sound": sound if sound is String else "(stream)", "bus": bus_name, "mode": mode, "tween": null}
	if options.get("follow") is Node3D:
		voice["follow"] = options["follow"]
		voice["follows"] = true
		_following += 1
		set_process(true)
	_voices[id] = voice
	_voice_of[player] = id
	player.play()
	return id


func play_2d(sound, bus_kind := "effects", volume := 1.0, pitch := 1.0) -> int:
	return play(sound, {"bus": bus_kind, "volume": volume, "pitch": pitch})


func play_at(sound, position: Vector3, options := {}) -> int:
	var all := options.duplicate()
	all["at"] = position
	all["mode"] = "spatial"
	return play(sound, all)


func play_on(sound, node: Node3D, options := {}) -> int:
	var all := options.duplicate()
	all["follow"] = node
	all["mode"] = "spatial"
	return play(sound, all)


func playing(id: int) -> bool:
	return _voices.has(id)


func stop(id: int, fade := 0.0) -> void:
	_stop_voice(id, fade)


func stop_all(fade := 0.0) -> void:
	for id in _voices.keys():
		_stop_voice(id, fade)


func last_error() -> String:
	return _last_error


# The bus a kind of sound plays on ("music" -> "Music"); a bus name itself
# is fine too. Unknown kinds play on Effects.
func bus(kind) -> String:
	var key := str(kind).to_lower()
	if BUSES.has(key):
		return BUSES[key]
	if key == "master":
		return "Master"
	return str(kind) if AudioServer.get_bus_index(str(kind)) != -1 else BUSES["effects"]


func _fail(problem: String) -> int:
	_last_error = problem
	return -1


func _check_options(options: Dictionary) -> String:
	var mode = options.get("mode", "spatial" if options.has("at") or options.has("follow") else "stereo")
	if not mode in MODES:
		return "\"mode\" must be one of %s" % ", ".join(MODES)
	for key in ["volume", "pitch", "max_distance", "unit_size", "priority"]:
		if options.has(key) and typeof(options[key]) not in [TYPE_INT, TYPE_FLOAT]:
			return "\"%s\" must be a number" % key
	if options.has("volume") and (options["volume"] < 0.0 or options["volume"] > 1.0):
		return "\"volume\" must be 0 to 1"
	if options.has("pitch") and (options["pitch"] < 0.25 or options["pitch"] > 4.0):
		return "\"pitch\" must be 0.25 to 4"
	if options.has("max_distance") and (options["max_distance"] <= 0.0 or options["max_distance"] > 1000.0):
		return "\"max_distance\" must be above 0 and up to 1000 m"
	if options.has("unit_size") and (options["unit_size"] <= 0.0 or options["unit_size"] > 100.0):
		return "\"unit_size\" must be above 0 and up to 100 m"
	if options.has("attenuation") and not ATTENUATION.has(options["attenuation"]):
		return "\"attenuation\" must be one of %s" % ", ".join(ATTENUATION.keys())
	if options.has("at") and not options["at"] is Vector3:
		return "\"at\" must be a Vector3"
	if options.has("follow") and not (options["follow"] is Node3D and is_instance_valid(options["follow"]) and options["follow"].is_inside_tree()):
		return "\"follow\" must be a Node3D in the scene"
	for key in ["loop", "muffle"]:
		if options.has(key) and typeof(options[key]) != TYPE_BOOL:
			return "\"%s\" must be true or false" % key
	if mode != "spatial" and (options.has("at") or options.has("follow")):
		return "\"at\" and \"follow\" are for mode spatial"
	return ""


# Room for one more sound: when every voice is busy, the lowest priority
# (then the oldest) at or under this one's priority stops.
func _make_room(priority: int) -> bool:
	if _voices.size() < int(config["max_voices"]):
		return true
	var victim := {}
	for voice in _voices.values():
		if voice["priority"] > priority:
			continue
		if victim.is_empty() or voice["priority"] < victim["priority"] or (voice["priority"] == victim["priority"] and voice["started"] < victim["started"]):
			victim = voice
	if victim.is_empty():
		return false
	_stop_voice(victim["id"], 0.0)
	return true


func _take_2d() -> AudioStreamPlayer:
	if not _free_2d.is_empty():
		return _free_2d.pop_back()
	var player := AudioStreamPlayer.new()
	player.finished.connect(_on_finished.bind(player))
	_holder.add_child(player)
	return player


func _take_3d() -> AudioStreamPlayer3D:
	if not _free_3d.is_empty():
		return _free_3d.pop_back()
	var player := AudioStreamPlayer3D.new()
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	player.finished.connect(_on_finished.bind(player))
	_holder.add_child(player)
	return player


func _on_finished(player: Node) -> void:
	if _voice_of.has(player):
		_release(_voice_of[player])


func _stop_voice(id: int, fade: float) -> void:
	if not _voices.has(id):
		return
	var voice: Dictionary = _voices[id]
	if fade <= 0.0 or not is_inside_tree():
		_release(id)
		return
	if voice["tween"] != null:
		return  # already fading out
	var tween: Tween = voice["player"].create_tween()
	tween.tween_property(voice["player"], "volume_db", -60.0, fade)
	tween.tween_callback(_release.bind(id))
	voice["tween"] = tween


# The sound ends and its player goes back to the pool.
func _release(id: int) -> void:
	if not _voices.has(id):
		return
	var voice: Dictionary = _voices[id]
	_voices.erase(id)
	var player: Node = voice["player"]
	_voice_of.erase(player)
	if voice["tween"] != null and voice["tween"].is_valid():
		voice["tween"].kill()
	if voice["follows"]:
		_following -= 1
	if not is_instance_valid(player):
		return
	player.stop()
	player.stream = null
	if player is AudioStreamPlayer3D:
		_free_3d.append(player)
	else:
		_free_2d.append(player)
	var zone = _zones.get(voice["zone"])
	if zone != null and zone["id"] == id:
		zone["id"] = -1
	sound_finished.emit(id)


# --- Sounds ---------------------------------------------------------------------

# An AudioStream for a sound: the stream itself, or the file loaded (once;
# kept while it's among the CACHE_SIZE most recently used). A looping copy
# is kept apart, so the same file can also play once.
func load_sound(sound, loop := false) -> AudioStream:
	if sound is AudioStream:
		return _looped(sound) if loop else sound
	if typeof(sound) != TYPE_STRING or sound.is_empty():
		_fail("\"sound\" must be a file name or path")
		return null
	var path := _resolve(sound)
	if path.is_empty():
		return null
	var key := path + ("#loop" if loop else "")
	if _cache.has(key):
		var cached: AudioStream = _cache[key]
		_cache.erase(key)
		_cache[key] = cached  # now the most recently used
		return cached
	var stream: AudioStream
	match path.get_extension().to_lower():
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(path)
		"wav":
			stream = AudioStreamWAV.load_from_file(path)
		"mp3":
			stream = AudioStreamMP3.load_from_file(path)
	if stream == null and path.begins_with("res://"):
		stream = load(path) as AudioStream  # an imported sound in the APK
	if stream == null:
		_fail("couldn't read %s as a sound" % path)
		return null
	if loop:
		stream = _looped(stream)
	_cache[key] = stream
	while _cache.size() > CACHE_SIZE:
		_cache.erase(_cache.keys()[0])
	return stream


func _looped(stream: AudioStream) -> AudioStream:
	var copy: AudioStream = stream.duplicate()  # the sound data itself is shared, not copied
	if copy is AudioStreamWAV:
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
		copy.loop_begin = 0
		copy.loop_end = int(copy.get_length() * copy.mix_rate)
	elif "loop" in copy:
		copy.set("loop", true)
	return copy


# A sound name or path to the file it means, or "" (and why) when it's not
# allowed or not there. Only the Slopitect folder, res:// and user://.
func _resolve(sound: String) -> String:
	if ".." in sound.split("/") or ".." in sound.split("\\"):
		_fail("a sound's path may not have .. in it")
		return ""
	if sound.begins_with("res://") or sound.begins_with("user://"):
		if not sound.get_extension().to_lower() in EXTENSIONS:
			_fail("a sound must be an .ogg, .wav or .mp3 file")
			return ""
		if not FileAccess.file_exists(sound) and not ResourceLoader.exists(sound):
			_fail("there's no %s" % sound)
			return ""
		return sound
	if _lib == null:
		_fail("sounds from the Slopitect folder need the lib module (load lib.gd)")
		return ""
	var home: String = _lib.home()
	var path := sound
	if not sound.begins_with("/"):
		path = home + "/sounds/" + sound
	elif not sound.begins_with(home + "/"):
		_fail("sounds must be in the Slopitect folder (%s), res:// or user://" % home)
		return ""
	if path.get_extension().is_empty():
		for extension in EXTENSIONS:
			if FileAccess.file_exists(path + "." + extension):
				return path + "." + extension
		_fail("there's no %s.ogg, .wav or .mp3" % path)
		return ""
	if not path.get_extension().to_lower() in EXTENSIONS:
		_fail("a sound must be an .ogg, .wav or .mp3 file")
		return ""
	if not FileAccess.file_exists(path):
		_fail("there's no %s" % path)
		return ""
	return path


# A short beep, made once, for audio_test.
func _test_beep() -> AudioStreamWAV:
	if _beep:
		return _beep
	var rate := 22050
	var count := int(rate * 0.25)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / rate
		var envelope := minf(1.0, minf(t / 0.01, (0.25 - t) / 0.05))
		data.encode_s16(i * 2, int(sin(TAU * 880.0 * t) * envelope * 20000.0))
	_beep = AudioStreamWAV.new()
	_beep.format = AudioStreamWAV.FORMAT_16_BITS
	_beep.mix_rate = rate
	_beep.stereo = false
	_beep.data = data
	return _beep


# --- Proximity zones --------------------------------------------------------------

func zone_add(zone_name: String, sound, where, radius: float, options := {}) -> String:
	if not zone_name.is_valid_identifier():
		return "a zone's name must be letters, digits and _"
	if not (where is Vector3 or (where is Node3D and is_instance_valid(where))):
		return "a zone is at a Vector3 or on a Node3D"
	if radius <= 0.0 or radius > 1000.0:
		return "\"radius\" must be above 0 and up to 1000 m"
	var inner := float(options.get("inner", radius / 4.0))
	if inner <= 0.0 or inner > radius:
		return "\"inner\" must be above 0 and up to the radius"
	var play_options := options.duplicate()
	play_options.erase("inner")
	play_options.erase("mode")
	var loop: bool = play_options.get("loop", true)
	play_options["loop"] = loop
	var problem := _check_options(play_options)
	if not problem.is_empty():
		return problem
	if load_sound(sound, loop) == null:
		return _last_error
	zone_remove(zone_name)
	_zones[zone_name] = {"name": zone_name, "sound": sound, "where": where, "radius": radius, "inner": inner,
		"loop": loop, "options": play_options, "id": -1, "inside": false}
	if _zone_timer.is_stopped():
		_zone_timer.start()
	_check_zones()
	return ""


func zone_remove(zone_name: String) -> void:
	var zone = _zones.get(zone_name)
	if zone == null:
		return
	_zones.erase(zone_name)
	if zone["id"] != -1:
		_stop_voice(zone["id"], 0.3)
	if _zones.is_empty():
		_zone_timer.stop()


func _check_zones() -> void:
	var ear := _listener()
	if ear == null:
		return
	var here := ear.global_position
	for zone in _zones.values():
		var where = zone["where"]
		if typeof(where) == TYPE_OBJECT and (not is_instance_valid(where) or not where.is_inside_tree()):
			zone_remove(zone["name"])  # its node is gone
			continue
		var spot: Vector3 = where.global_position if where is Node3D else where
		var distance := here.distance_to(spot)
		if not zone["inside"] and distance <= zone["radius"]:
			zone["inside"] = true
			_zone_start(zone)
		elif zone["inside"] and distance > zone["radius"] * ZONE_LEAVE:
			zone["inside"] = false
			if zone["loop"] and zone["id"] != -1:
				_stop_voice(zone["id"], 0.3)


func _zone_start(zone: Dictionary) -> void:
	if zone["id"] != -1 and playing(zone["id"]):
		return
	var options: Dictionary = zone["options"].duplicate()
	options["mode"] = "spatial"
	options["zone"] = zone["name"]
	options["max_distance"] = zone["radius"] * ZONE_LEAVE
	options["unit_size"] = zone["inner"]
	if zone["where"] is Node3D:
		options["follow"] = zone["where"]
	else:
		options["at"] = zone["where"]
	zone["id"] = play(zone["sound"], options)


# Where you hear from: the camera in use (your head in the headset).
func _listener() -> Node3D:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null and ctx.has("camera"):
		camera = ctx["camera"] as Camera3D
	return camera


# --- Buses and settings ---------------------------------------------------------

func _make_bus(bus_name: String, send: String) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index != -1:
		return index
	AudioServer.add_bus()
	index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)
	_made_buses.append(bus_name)
	return index


# A bus's mono twin (made the first time it's needed): left and right mixed
# together, then on into the bus.
func _mono_bus(bus_name: String) -> String:
	var mono := bus_name + MONO_SUFFIX
	if AudioServer.get_bus_index(mono) == -1:
		var index := _make_bus(mono, bus_name)
		var effect := AudioEffectStereoEnhance.new()
		effect.pan_pullout = 0.0
		AudioServer.add_bus_effect(index, effect)
	return mono


func _set_mono_output(on: bool) -> void:
	var master := AudioServer.get_bus_index("Master")
	var at := -1
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) == _mono_effect:
			at = i
	if on and at == -1:
		_mono_effect = AudioEffectStereoEnhance.new()
		_mono_effect.pan_pullout = 0.0
		AudioServer.add_bus_effect(master, _mono_effect)
	elif not on and at != -1:
		AudioServer.remove_bus_effect(master, at)
		_mono_effect = null


func _apply() -> void:
	for level in LEVELS:
		var index := AudioServer.get_bus_index("Master" if level == "master" else BUSES[level])
		if index != -1:
			var percent := float(settings[level])
			AudioServer.set_bus_volume_db(index, linear_to_db(percent / 100.0) if percent > 0.0 else -80.0)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), settings["muted"])
	_set_mono_output(settings["mono"])


# Its section of the Settings window (settings.gd).
func settings_info() -> Dictionary:
	var out := []
	for level in LEVELS:
		out.append({"id": level, "type": "slider", "label": LABELS[level], "min": 0, "max": 100, "step": 5,
			"value": settings[level], "set": {"cmd": "audio_set", level: "{value}"}})
	out.append({"id": "mono", "type": "toggle", "label": "Mono output (one ear)", "value": settings["mono"], "set": {"cmd": "audio_set", "mono": "{value}"}})
	out.append({"id": "muted", "type": "toggle", "label": "Mute all sound", "value": settings["muted"], "set": {"cmd": "audio_set", "muted": "{value}"}})
	return {"title": "Sound", "order": 40, "settings": out}


func _set_command(request: Dictionary) -> Dictionary:
	var changes := {}
	for key in request:
		if key in ["cmd", "id"]:
			continue
		if not DEFAULTS.has(key):
			return {"ok": false, "error": "audio_set changes %s" % ", ".join(DEFAULTS.keys())}
		var value = request[key]
		if key in LEVELS:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < 0 or value > 100:
				return {"ok": false, "error": "\"%s\" must be 0 to 100" % key}
			changes[key] = int(round(value))
		elif typeof(value) != TYPE_BOOL:
			return {"ok": false, "error": "\"%s\" must be true or false" % key}
		else:
			changes[key] = value
	if changes.is_empty():
		return {"ok": false, "error": "nothing to change (audio_set changes %s)" % ", ".join(DEFAULTS.keys())}
	settings.merge(changes, true)
	_apply()
	_save()
	return {"ok": true, "settings": settings}


func _config(request: Dictionary) -> Dictionary:
	for key in request:
		if key in ["cmd", "id"]:
			continue
		if key != "max_voices":
			return {"ok": false, "error": "audio_config changes max_voices"}
		var value = request[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < MAX_VOICES[0] or value > MAX_VOICES[1]:
			return {"ok": false, "error": "\"max_voices\" must be %d to %d" % MAX_VOICES}
		config["max_voices"] = int(value)
		_save()
	return {"ok": true, "config": config}


func _save() -> void:
	if _lib == null:
		return
	var out := settings.duplicate()
	out.merge(config)
	var problem: String = _lib.write_json(SETTINGS_PATH, out, "\t")
	if not problem.is_empty():
		push_error("Slopitect audio: couldn't save %s: %s" % [SETTINGS_PATH, problem])
	_lib.touch(self)  # the Settings window shows the new values


func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var saved = _lib.read_json(SETTINGS_PATH)
	if typeof(saved) != TYPE_DICTIONARY:
		push_error("Slopitect audio: %s isn't readable; using the defaults" % SETTINGS_PATH)
		return
	for level in LEVELS:
		if typeof(saved.get(level)) in [TYPE_INT, TYPE_FLOAT] and saved[level] >= 0 and saved[level] <= 100:
			settings[level] = int(saved[level])
	for key in ["mono", "muted"]:
		if typeof(saved.get(key)) == TYPE_BOOL:
			settings[key] = saved[key]
	var voices = saved.get("max_voices")
	if typeof(voices) in [TYPE_INT, TYPE_FLOAT] and voices >= MAX_VOICES[0] and voices <= MAX_VOICES[1]:
		config["max_voices"] = int(voices)


# --- Commands ----------------------------------------------------------------------

func _vector(value):
	if typeof(value) == TYPE_ARRAY and value.size() == 3 and value.all(func(n): return typeof(n) in [TYPE_INT, TYPE_FLOAT]):
		return Vector3(value[0], value[1], value[2])
	return null


# A command's request to play() options: "at" from [x,y,z], "follow" from
# a thing's name.
func _options_from(request: Dictionary, keys: Array) -> Dictionary:
	var options := {}
	for key in keys:
		if request.has(key):
			options[key] = request[key]
	if request.has("at"):
		var at = _vector(request["at"])
		if at == null:
			return {"error": "\"at\" must be [x, y, z]"}
		options["at"] = at
	if request.has("follow"):
		var node: Node3D = _lib.thing(request["follow"]) if _lib else null
		if node == null:
			return {"error": "there's no thing called %s to follow" % str(request["follow"])}
		options["follow"] = node
	return options


func _play_command(request: Dictionary) -> Dictionary:
	var options := _options_from(request, ["bus", "volume", "pitch", "loop", "mode", "max_distance", "unit_size", "attenuation", "muffle", "priority"])
	if options.has("error"):
		return {"ok": false, "error": options["error"]}
	var id := play(request.get("sound"), options)
	if id == -1:
		return {"ok": false, "error": _last_error}
	return {"ok": true, "id": id, "mode": _voices[id]["mode"], "bus": _voices[id]["bus"]}


func _stop_command(request: Dictionary) -> Dictionary:
	var fade = request.get("fade", 0.0)
	if typeof(fade) not in [TYPE_INT, TYPE_FLOAT] or fade < 0.0 or fade > 10.0:
		return {"ok": false, "error": "\"fade\" must be 0 to 10 seconds"}
	if request.get("all", false) == true:
		var count := _voices.size()
		stop_all(fade)
		return {"ok": true, "stopped": count}
	var id = request.get("id")
	if typeof(id) not in [TYPE_INT, TYPE_FLOAT] or not playing(int(id)):
		return {"ok": false, "error": "no sound playing with id %s (audio_status lists them)" % str(id)}
	stop(int(id), fade)
	return {"ok": true, "stopped": 1}


func _zone_command(request: Dictionary) -> Dictionary:
	var zone_name := str(request.get("name", ""))
	if request.get("remove", false) == true:
		if not _zones.has(zone_name):
			return {"ok": false, "error": "no zone called %s" % zone_name}
		zone_remove(zone_name)
		return {"ok": true, "zones": _zones.keys()}
	var options := _options_from(request, ["bus", "volume", "pitch", "loop", "inner", "attenuation", "muffle", "priority"])
	if options.has("error"):
		return {"ok": false, "error": options["error"]}
	var where = options.get("follow", options.get("at"))
	if where == null:
		return {"ok": false, "error": "a zone needs at [x, y, z] or follow (a thing's name)"}
	options.erase("at")
	options.erase("follow")
	var radius = request.get("radius")
	if typeof(radius) not in [TYPE_INT, TYPE_FLOAT]:
		return {"ok": false, "error": "\"radius\" must be a number of metres"}
	var problem := zone_add(zone_name, request.get("sound"), where, float(radius), options)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return {"ok": true, "zone": _zone_out(_zones[zone_name])}


func _sounds_command(_request: Dictionary) -> Dictionary:
	if _lib == null:
		return {"ok": false, "error": "audio_sounds needs the lib module (load lib.gd)"}
	var folder: String = _lib.home() + "/sounds"
	var found := []
	_list_sounds(folder, "", found)
	return {"ok": true, "folder": folder, "sounds": found}


func _list_sounds(folder: String, prefix: String, found: Array) -> void:
	for file in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() in EXTENSIONS:
			found.append(prefix + file)
	for sub in DirAccess.get_directories_at(folder):
		_list_sounds(folder + "/" + sub, prefix + sub + "/", found)


func _test_command(request: Dictionary) -> Dictionary:
	var where = request.get("where", "center")
	var bus_kind = request.get("bus", "effects")
	var id := -1
	if where == "center":
		id = play(_test_beep(), {"bus": bus_kind})
	elif TEST_DIRECTIONS.has(where):
		var ear := _listener()
		if ear == null:
			return {"ok": false, "error": "no camera to put the sound beside"}
		var spot: Vector3 = ear.global_position + ear.global_basis * (TEST_DIRECTIONS[where] * TEST_DISTANCE)
		id = play_at(_test_beep(), spot, {"bus": bus_kind})
	else:
		return {"ok": false, "error": "\"where\" must be center, %s" % ", ".join(TEST_DIRECTIONS.keys())}
	if id == -1:
		return {"ok": false, "error": _last_error}
	return {"ok": true, "id": id}


func _zone_out(zone: Dictionary) -> Dictionary:
	var where = zone["where"]
	return {"name": zone["name"], "sound": zone["sound"] if zone["sound"] is String else "(stream)",
		"where": (String(where.name) if is_instance_valid(where) else "(gone)") if typeof(where) == TYPE_OBJECT else [snappedf(where.x, 0.01), snappedf(where.y, 0.01), snappedf(where.z, 0.01)],
		"radius": zone["radius"], "inner": zone["inner"], "loop": zone["loop"], "near": zone["inside"], "playing": zone["id"] != -1}


func _status(_request: Dictionary) -> Dictionary:
	var buses := []
	for i in AudioServer.bus_count:
		buses.append({"name": AudioServer.get_bus_name(i), "volume_db": snappedf(AudioServer.get_bus_volume_db(i), 0.1),
			"mute": AudioServer.is_bus_mute(i), "send": AudioServer.get_bus_send(i)})
	var sounds := []
	for voice in _voices.values():
		sounds.append({"id": voice["id"], "sound": voice["sound"], "mode": voice["mode"], "bus": voice["bus"], "loop": voice["loop"],
			"priority": voice["priority"], "follows": String(voice["follow"].name) if voice["follows"] and is_instance_valid(voice["follow"]) else "",
			"zone": voice["zone"]})
	var speakers := {AudioServer.SPEAKER_MODE_STEREO: "stereo", AudioServer.SPEAKER_SURROUND_31: "3.1", AudioServer.SPEAKER_SURROUND_51: "5.1", AudioServer.SPEAKER_SURROUND_71: "7.1"}
	return {"ok": true, "speakers": speakers.get(AudioServer.get_speaker_mode(), "?"), "driver": AudioServer.get_driver_name(),
		"buses": buses, "settings": settings, "config": config, "playing": sounds,
		"zones": _zones.values().map(_zone_out), "pool": {"2d": _free_2d.size(), "3d": _free_3d.size()},
		"cached_sounds": _cache.size(), "following": _following, "processing": is_processing(), "last_error": _last_error}
