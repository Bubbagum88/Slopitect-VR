extends SlopitectModule

# Slopitect live module: beatsaber, the Rhythm Sabers game.
# Red and blue notes come down a track toward you on the music's beat; cut
# each with the saber of its colour (right = red, left = blue), in the
# direction its arrow points (a dot note: any direction). Dark spiky bombs
# must not be touched. A cut splits the note in two along the blade's path.
#
# Its own world: the game has one world of its own, "rhythm_sabers" (a
# project, projects.gd), made the first time and reused after that.
# Getting in: the Rhythm tile on the Menu, or starting any song (the window,
# the Settings window's Start, beatsaber_start) takes you to that world
# first, saving the one you were in, and opens the Rhythm window (tabs:
# Songs, Options, Modifiers, Colours, Practice; Stop, Leave and the last
# results on each). Opening the world from the
# Worlds window does the same.
# Getting out: Leave (in the Rhythm window or the Settings window, or
# beatsaber_leave) stops the song and takes you back to the world you came
# from (remembered even across a restart). Going to any other world stops
# the song too. Without projects.gd and save.gd it plays where you are.
# The track is laid out where you stand, facing the way you look, when a
# song starts. A score board stands to its left.
#
# Songs: a folder per song in the Slopitect folder's songs/, holding the
# music (song.ogg, .mp3 or .wav, or the file "audio" names) and map.json:
#   {"title": "My song", "artist": "...", "bpm": 120, "offset": 0.0,
#    "audio": "song.ogg",
#    "notes": [[beat, lane, row, hand, dir], ...]}
# beat counts from offset (seconds into the music); lane 0-3 left to right;
# row 0-2 bottom to top; hand "l" (blue), "r" (red) or "b" (a bomb); dir
# one of u d l r ul ur dl dr (the way to cut) or a (any way, a dot note).
# A map.json without notes (just "bpm") gets notes made for the whole song,
# so any song can be played by giving its tempo. Free play needs no song:
# notes at the Settings window's tempo, 128 beats, no music.
# Made notes follow the swing flow (each hand alternates down and up, and
# the free hand's bombs sit where that hand isn't), from a fixed seed, so
# a song's made map is the same every time.
#
# Scoring, per cut, up to 100 points: 50 for the swing's direction against
# the arrow (full within about 15 degrees, none past about 50, where it
# stops counting as a cut), 30 for how near the blade passes the note's
# centre, 20 for a full swing (how far the tip travelled in the last fifth
# of a second). Points are multiplied by the combo: 1 + one for every 10
# notes in a row, up to 8. A miss, a wrong-way cut, a wrong-colour cut or a
# bomb ends the combo. At the end: accuracy (the share of the best possible
# points) and a rank S A B C D F, and the best score per song is kept.
# Haptics through controls.gd's pulse (directly without it).
#
# Quest 1: every note, bomb, half, label and sound is made once and reused
# (pools); all notes share a handful of meshes and materials; notes check
# for cuts only near you; nothing runs while no song plays (the sabers ride
# on the controller nodes, so they follow with no code each frame).
#
# Holding the saber: the controller nodes follow the "aim" pose, so the
# saber is turned up by fit["angle"] degrees onto the controller's handle,
# held fit["hold"] cm down its hilt with the hand at fit["grip"] (cm from
# the controller's point to the handle's middle, right hand; x mirrors for
# the left). beatsaber_config changes them from the PC only. They and the
# game settings are kept in user://beatsaber.json.
# The sabers show only when the hands module's Settings choice is Sabers
# (and Hide hands is off); without the hands module they always show.
#
# Ideas and formulas adapted (not copied files) from two MIT-licensed games,
# see live-modules/THIRD_PARTY_NOTICES.md: BeepSaber by Holger Dammertz
# (notes placed from beat time each frame, the cut plane through the blade's
# last two positions, the cut-distance falloff, the combo multiplier, swing
# size from recent tip travel, pooled notes) and Moon Rider by Supermedium
# (the blade's swept path tested between frames, the stroke direction over
# several frames, the 0.625 / 0.97 direction limits, the rank letters).
#
# Signals: started(title), stopped(), finished(results), scored(points,
# combo) (points 0 for a miss or a bad cut). `running` is true while a song
# plays (beatsaber_path follows started / stopped).

signal started(title: String)
signal stopped()
signal finished(results: Dictionary)
signal scored(points: int, combo: int)

const PANEL := "beatsaber"
const TITLE := "Rhythm Sabers"
const LANE_W := 0.45             # metres between lanes
const HIT_Z := -1.0              # track z a note reaches on its beat
const SPAWN_Z := -14.0           # where notes appear
const MISS_Z := 0.5              # a note past this is missed
const CUT_FROM := -2.6           # notes check for cuts only from here on
const NOTE_SIZE := 0.3
const NOTE_HALF := 0.15
const NOTE_ROUND := 0.03         # radius of the note's rounded edges
const HIT_MARGIN := 0.05
const POOL_NOTES := 32
const POOL_BOMBS := 8
const POOL_HALVES := 16
const POOL_POPS := 8
const HALF_LIFE := 0.6
const POP_LIFE := 0.8
const TRAIL_LEN := 10
const HISTORY := 16              # tip positions kept per hand (about 0.2 s)
const SWEEP_STEPS := 4           # blade positions tried between two frames
const JUMP := 0.6                # a tip moving more than this in one frame jumped (lost tracking)
const MIN_SPEED := 1.0           # tip speed (m/s) a cut needs
const WRONG_SPEED := 2.5         # a wrong-colour saber counts only above this
const DOT_MIN := 0.625           # direction below this (about 50 degrees off) is a wrong-way cut
const DOT_FULL := 0.97           # direction above this (about 15 degrees) scores full
const CENTRE_RANGE := 0.15       # metres off the centre where centre points run out
const SWING_FROM := 0.3          # tip travel (m) where swing points start
const SWING_FULL := 0.9          # and where they're full
const LEAD_MIN := 2.0            # seconds before the music starts
const FREE_BEATS := 128
const SABER_SCALE := 0.8
const SETTINGS_PATH := "user://beatsaber.json"
const DIRS := {"u": Vector2(0, 1), "d": Vector2(0, -1), "l": Vector2(-1, 0), "r": Vector2(1, 0),
	"ul": Vector2(-0.70710678, 0.70710678), "ur": Vector2(0.70710678, 0.70710678),
	"dl": Vector2(-0.70710678, -0.70710678), "dr": Vector2(0.70710678, -0.70710678), "a": Vector2.ZERO}
const DIFFICULTIES := ["easy", "normal", "hard"]
const DIFF_STEP := {"easy": 2.0, "normal": 1.0, "hard": 0.5}     # beats between notes
const DIFF_DOUBLES := {"easy": 0.0, "normal": 0.08, "hard": 0.15}
const DIFF_BOMBS := {"easy": 0.0, "normal": 0.04, "hard": 0.1}
const GAME_DEFAULTS := {"difficulty": "normal", "speed": 8.0, "bpm": 100.0, "hit_sounds": true, "trails": true}
const SPEED_RANGE := [4.0, 14.0]
const BPM_RANGE := [60.0, 200.0]
const RANKS := [[97.0, "S"], [90.0, "A"], [80.0, "B"], [70.0, "C"], [60.0, "D"], [0.0, "F"]]
const FIT_DEFAULTS := {"angle": 45.0, "grip": [0.0, -1.8, 4.8], "hold": 10.0}  # Touch: Chromium's WebXR grip is the aim turned up 45 degrees, 2.5 cm down; isaac saw the sabers too far forward on the headset, so 3 cm further back
const FIT_ANGLE_RANGE := [-30.0, 90.0]
const FIT_CM_MAX := 15.0
const SONG_ROWS := 5
const TABS := ["Songs", "Options", "Modifiers", "Colours", "Practice"]
const WIN := Vector2(0.74, 0.64)  # the Rhythm window's size
const WORLD := "rhythm_sabers"   # the game's own world (a project)

var running := false
var fit := FIT_DEFAULTS.duplicate(true)
var game := GAME_DEFAULTS.duplicate(true)
var best := {}  # song folder (or "free play") -> best score

var _lib: SlopitectModule
var _controls: SlopitectModule
var _hands: SlopitectModule
var _track: Node3D          # notes, halves, labels; placed where you stand at the start
var _board: Label3D
var _song_player: AudioStreamPlayer
var _hit_player: AudioStreamPlayer
var _hidden_boxes: Array = []
var _sabers := {}           # side -> Node3D on that controller
var _trails := {}           # side -> {"node", "mesh", "pts", "color"}

# Shared meshes and materials.
var _note_mesh: Mesh
var _half_mesh: BoxMesh
var _bomb_mesh: SphereMesh
var _spike_mesh: CylinderMesh
var _arrow_mesh: ArrayMesh
var _dot_mesh: CylinderMesh
var _mat := {}              # "l", "r", "marker", "bomb", "spike", "trail", "silver", "handle"

# Pools: nodes waiting to be used; active ones are in _active / _halves / _pops.
var _free_notes: Array = []
var _free_bombs: Array = []
var _free_halves: Array = []
var _free_pops: Array = []
var _active: Array = []     # {"node", "kind" ("note"/"bomb"), "hand", "dir", "time", "pos"}
var _halves: Array = []     # {"node", "vel", "spin", "life"}
var _pops: Array = []       # {"node", "life"}

# The song being played.
var _song := {}             # "id", "title", "bpm", "offset", "notes" (sorted), "audio"
var _next := 0
var _clock := 0.0           # seconds into the song (negative during the lead-in)
var _music_started := false
var _music_done := false
var _blade := {}            # side -> {"base", "tip", "pbase", "ptip", "hist", "speed", "ok"}

# The score.
var score := 0
var combo := 0
var max_combo := 0
var cuts := 0
var bad := 0
var missed := 0
var bombs_hit := 0
var _acc := 0.0             # sum of points / 100 over judged notes
var _last := {}             # the last cut's details
var _results := {}
var _song_page := 0
var _return_to := ""        # the world to go back to on Leave


func setup() -> String:
	register("beatsaber_start", _start, "start a song: optional song (a folder in songs/, or \"free\" for free play), difficulty (easy, normal, hard), bpm (free play, 60 to 200), interval (old: seconds between free-play notes, 0.3 to 2)")
	register("beatsaber_stop", _stop, "stop the song and clear the notes")
	register("beatsaber_score", _score, "the score, combo, multiplier, cuts, misses, bad cuts, bombs hit, accuracy, and the last cut's points, direction and centre offset; after a song, its results")
	register("beatsaber_songs", _songs_command, "the songs in the Slopitect folder's songs/ (folder, title, bpm, notes or made, best score)")
	register("beatsaber_set", _set_command, "the game's settings (usable in the headset): any of difficulty (easy, normal, hard), speed (note speed m/s, 4 to 14), bpm (free play tempo, 60 to 200), hit_sounds, trails (true/false)")
	register("beatsaber_do", _do, "the Rhythm window: act = toggle (goes to the Rhythm world first), show (optional page: a tab), refresh, page (page number for the song list), enter (go to the Rhythm world), leave (back to the world you came from)")
	register("beatsaber_leave", _leave, "stop the song and go back from the Rhythm world to the world you came from")
	register("beatsaber_config", _config, "from the PC only: how the saber sits in the hand: any of angle (degrees it tilts up from where the controller points, -30 to 90), grip ([x, y, z] cm from the controller's point to the handle's middle, right hand), hold (cm down the hilt the hand holds it, 0 to 15), or reset true")
	_make_assets()
	_track = Node3D.new()
	_track.name = "track"
	add_child(_track)  # its own, not World's: no thing to save or select
	_track.visible = false
	_make_pools()
	_board = Label3D.new()
	_board.font_size = 72
	_board.pixel_size = 0.003
	_board.outline_size = 14
	_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_board.position = Vector3(-2.0, 1.3, -4.0)
	_board.rotation_degrees = Vector3(0, 25, 0)
	_track.add_child(_board)
	_song_player = AudioStreamPlayer.new()
	_song_player.finished.connect(_on_music_done)
	add_child(_song_player)
	_hit_player = AudioStreamPlayer.new()
	_hit_player.stream = _hit_sound()
	_hit_player.max_polyphony = 4
	_hit_player.volume_db = -6.0
	add_child(_hit_player)
	for side in ["right", "left"]:
		_make_saber(side)
	_show_sabers()
	set_process(false)
	return ""


func lib_ready(lib) -> void:
	if _lib and _lib.info_changed.is_connected(_on_info_changed):
		_lib.info_changed.disconnect(_on_info_changed)
	_lib = lib
	if lib == null:
		_controls = null
		_hands = null
		_show_sabers()
		return
	_load_settings()
	lib.info_changed.connect(_on_info_changed)
	lib.watch(self, "controls", _controls_here, _controls_gone)
	lib.watch(self, "hands", _hands_here, _hands_gone)
	lib.follow(self, "projects", "project_changed", _on_world_changed)
	lib.touch(self)


func _controls_here(controls: SlopitectModule) -> void:
	_controls = controls


func _controls_gone(_old: SlopitectModule) -> void:
	_controls = null


func _hands_here(hands: SlopitectModule) -> void:
	_hands = hands
	_show_sabers()


func _hands_gone(_old: SlopitectModule) -> void:
	_hands = null
	_show_sabers()


# hands calls lib.touch when its style or hide switch changes.
func _on_info_changed(module_name: String) -> void:
	if module_name == "hands":
		_show_sabers()


func _exit_tree() -> void:
	if _lib and _lib.info_changed.is_connected(_on_info_changed):
		_lib.info_changed.disconnect(_on_info_changed)
	for box in _hidden_boxes:
		if is_instance_valid(box):
			box.visible = true
	_hidden_boxes.clear()
	for side in _sabers:
		if is_instance_valid(_sabers[side]):
			_sabers[side].queue_free()
	_sabers.clear()
	ctx["server"].run({"cmd": "ui_remove", "id_panel": PANEL})


# --- Menu, Settings and the window ------------------------------------------------

func menu_info() -> Dictionary:
	return {"id": "beatsaber", "label": "Rhythm", "order": 60, "action": {"cmd": "beatsaber_do", "act": "toggle"}}


func settings_info() -> Dictionary:
	var diffs := []
	for d in DIFFICULTIES:
		diffs.append({"label": d.capitalize(), "value": d})
	return {"title": TITLE, "order": 45, "settings": [
		{"id": "difficulty", "type": "choice", "label": "Difficulty", "value": game["difficulty"], "options": diffs, "columns": 3,
			"set": {"cmd": "beatsaber_set", "difficulty": "{value}"}},
		{"id": "speed", "type": "slider", "label": "Note speed (m/s)", "min": SPEED_RANGE[0], "max": SPEED_RANGE[1], "step": 0.5,
			"value": game["speed"], "set": {"cmd": "beatsaber_set", "speed": "{value}"}},
		{"id": "bpm", "type": "slider", "label": "Free play tempo (beats a minute)", "min": BPM_RANGE[0], "max": BPM_RANGE[1], "step": 5.0,
			"value": game["bpm"], "set": {"cmd": "beatsaber_set", "bpm": "{value}"}},
		{"id": "hit_sounds", "type": "toggle", "label": "Hit sounds", "value": game["hit_sounds"],
			"set": {"cmd": "beatsaber_set", "hit_sounds": "{value}"}},
		{"id": "trails", "type": "toggle", "label": "Saber trails", "value": game["trails"],
			"set": {"cmd": "beatsaber_set", "trails": "{value}"}},
		{"id": "start", "type": "button", "label": "Start free play", "set": {"cmd": "beatsaber_start", "song": "free"}},
		{"id": "stop", "type": "button", "label": "Stop", "set": {"cmd": "beatsaber_stop"}},
		{"id": "leave", "type": "button", "label": "Leave the Rhythm world", "set": {"cmd": "beatsaber_leave"}},
	]}


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


func _has_ui() -> bool:
	return ctx["modules"].module("vrui") != null or ctx["modules"].module("ui") != null


func _do(request: Dictionary) -> Dictionary:
	match request.get("act"):
		"toggle":
			var got := _run({"cmd": "ui_get", "id_panel": PANEL})
			if in_world() and got.get("ok", false) and got.get("panel", {}).get("visible", false):
				return _run({"cmd": "ui_show", "id_panel": PANEL, "visible": false})
			var problem := _enter()
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			return _show_window()
		"enter":
			var problem := _enter()
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			return _show_window()
		"leave":
			return _leave({})
		"show":
			var page = request.get("page", "")
			if not (page == "" or page in TABS):
				return {"ok": false, "error": "\"page\" must be one of %s" % [TABS]}
			return _show_window(page)
		"refresh":
			var problem := _build()
			return {"ok": problem.is_empty(), "error": problem} if not problem.is_empty() else {"ok": true}
		"page":
			var page = request.get("page")
			if typeof(page) not in [TYPE_INT, TYPE_FLOAT]:
				return {"ok": false, "error": "\"page\" must be a number"}
			_song_page = maxi(0, int(page))
			_build()
			return {"ok": true, "page": _song_page}
	return {"ok": false, "error": "\"act\" must be toggle, show, refresh, page, enter or leave"}


func _show_window(page := "") -> Dictionary:
	var problem := _build(page)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return _run({"cmd": "ui_show", "id_panel": PANEL, "visible": true})


# The Rhythm window: tabs for Songs (pick one to play), Options
# (difficulty, note speed, tempo, hit sounds, trails), and Modifiers,
# Colours and Practice (coming step by step). What's happening, Stop and
# Leave show on every tab. Built when it opens, when a setting changes and
# when a song starts, stops or ends; never per frame. The tab you're on
# stays when it's built again.
func _build(page := "") -> String:
	if not _has_ui():
		return "the Rhythm window needs the vrui module"
	var els := []
	var top := WIN.y / 2.0 - 0.05
	els.append({"type": "text", "id": "status", "text": _status_text(), "at": [0.0, top], "width": WIN.x - 0.06, "color": "text"})
	els.append_array(_songs_tab(top - 0.08))
	els.append_array(_options_tab(top - 0.08))
	for tab in ["Modifiers", "Colours", "Practice"]:
		els.append({"type": "text", "id": "soon_" + tab.to_lower(), "page": tab, "text": "%s: coming in a later step." % tab,
			"at": [0.0, top - 0.12], "width": WIN.x - 0.06, "color": "muted"})
	var bottom := -WIN.y / 2.0 + 0.04
	var leave := _projects() != null
	els.append({"type": "button", "id": "stop", "label": "Stop", "at": [-0.12 if leave else 0.0, bottom], "size": [0.2, 0.05],
		"color": "notice" if running else "button", "action": {"cmd": "beatsaber_stop"}})
	if leave:
		els.append({"type": "button", "id": "leave", "label": "Leave", "at": [0.12, bottom], "size": [0.2, 0.05],
			"color": "button", "action": {"cmd": "beatsaber_leave"}})
	var got := _run({"cmd": "ui_get", "id_panel": PANEL})
	var reply: Dictionary
	if got.get("ok", false):
		var update := {"cmd": "ui_update", "id_panel": PANEL, "elements": els}
		if page != "":
			update["page"] = page
		reply = _run(update)
	else:
		reply = _run({"cmd": "ui_add", "id_panel": PANEL, "title": TITLE, "place": "front", "distance": 0.6, "height": -0.15,
			"size": [WIN.x, WIN.y], "chrome": true, "pages": TABS, "page": page if page != "" else TABS[0], "visible": false, "elements": els})
	return "" if reply.get("ok", false) else str(reply.get("error", "the window couldn't be drawn"))


func _songs_tab(y: float) -> Array:
	var els := []
	var songs := _songs()
	var rows := [{"id": "free", "label": "Free play (%d beats a minute)" % int(game["bpm"])}]
	for s in songs:
		var label := str(s["title"])
		if best.has(s["id"]):
			label += "  best %d" % int(best[s["id"]])
		rows.append({"id": s["id"], "label": label})
	var pages := maxi(1, ceili(rows.size() / float(SONG_ROWS)))
	_song_page = clampi(_song_page, 0, pages - 1)
	for i in range(_song_page * SONG_ROWS, mini(rows.size(), (_song_page + 1) * SONG_ROWS)):
		els.append({"type": "button", "id": "song_%d" % i, "page": "Songs", "label": rows[i]["label"].left(40), "at": [0.0, y],
			"size": [WIN.x - 0.08, 0.05], "color": "button", "action": {"cmd": "beatsaber_start", "song": rows[i]["id"]}})
		y -= 0.058
	if songs.is_empty():
		els.append({"type": "text", "id": "hint", "page": "Songs", "text": "Add songs as folders in Slopitect/songs (see beatsaber.gd)",
			"at": [0.0, y], "width": WIN.x - 0.06, "color": "muted"})
	if pages > 1:
		var py := -WIN.y / 2.0 + 0.11
		els.append({"type": "button", "id": "prev", "page": "Songs", "label": "Back", "at": [-0.2, py], "size": [0.14, 0.05],
			"action": {"cmd": "beatsaber_do", "act": "page", "page": _song_page - 1}})
		els.append({"type": "text", "id": "pages", "page": "Songs", "text": "%d / %d" % [_song_page + 1, pages], "at": [0.0, py],
			"width": 0.12, "color": "muted"})
		els.append({"type": "button", "id": "next", "page": "Songs", "label": "More", "at": [0.2, py], "size": [0.14, 0.05],
			"action": {"cmd": "beatsaber_do", "act": "page", "page": _song_page + 1}})
	return els


func _options_tab(y: float) -> Array:
	var els := []
	els.append({"type": "text", "id": "diff_label", "page": "Options", "text": "Difficulty", "at": [0.0, y], "width": WIN.x - 0.06, "color": "muted"})
	y -= 0.06
	for i in DIFFICULTIES.size():
		var d: String = DIFFICULTIES[i]
		els.append({"type": "button", "id": "diff_" + d, "page": "Options", "label": d.capitalize(), "at": [-0.22 + i * 0.22, y],
			"size": [0.2, 0.055], "color": "accent" if game["difficulty"] == d else "button", "action": {"cmd": "beatsaber_set", "difficulty": d}})
	y -= 0.085
	els.append({"type": "slider", "id": "speed", "page": "Options", "label": "Note speed (m/s)", "at": [0.0, y], "size": [WIN.x - 0.12, 0.06],
		"min": SPEED_RANGE[0], "max": SPEED_RANGE[1], "step": 0.5, "value": game["speed"], "action": {"cmd": "beatsaber_set", "speed": "{value}"}})
	y -= 0.085
	els.append({"type": "slider", "id": "bpm", "page": "Options", "label": "Free play tempo (beats a minute)", "at": [0.0, y], "size": [WIN.x - 0.12, 0.06],
		"min": BPM_RANGE[0], "max": BPM_RANGE[1], "step": 5.0, "value": game["bpm"], "action": {"cmd": "beatsaber_set", "bpm": "{value}"}})
	y -= 0.085
	els.append({"type": "toggle", "id": "hit_sounds", "page": "Options", "label": "Hit sounds", "at": [-0.15, y], "size": [0.26, 0.055],
		"on": game["hit_sounds"], "action": {"cmd": "beatsaber_set", "hit_sounds": "{on}"}})
	els.append({"type": "toggle", "id": "trails", "page": "Options", "label": "Saber trails", "at": [0.15, y], "size": [0.26, 0.055],
		"on": game["trails"], "action": {"cmd": "beatsaber_set", "trails": "{on}"}})
	return els


func _rebuild_if_open() -> void:
	if _has_ui() and _run({"cmd": "ui_get", "id_panel": PANEL}).get("ok", false):
		_build()


func _status_text() -> String:
	if running:
		return "Playing %s. Stop to end it." % _song.get("title", "")
	if not _results.is_empty():
		return "%s: %d points, rank %s, %d%% accuracy, best combo %d%s" % [_results["title"], _results["score"], _results["rank"],
			int(_results["accuracy"]), _results["max_combo"], ", a new best!" if _results.get("new_best", false) else ""]
	return "Pick a song. Cut red with the right saber, blue with the left."


# --- Commands ----------------------------------------------------------------------

func _start(request: Dictionary) -> Dictionary:
	if request.has("difficulty"):
		if not request["difficulty"] in DIFFICULTIES:
			return {"ok": false, "error": "\"difficulty\" must be easy, normal or hard"}
		game["difficulty"] = request["difficulty"]
	var bpm: float = game["bpm"]
	if request.has("interval"):  # the old free-play command: seconds between notes
		var iv = request["interval"]
		if not _number(iv) or iv < 0.3 or iv > 2.0:
			return {"ok": false, "error": "interval must be 0.3 to 2 seconds"}
		bpm = clampf(60.0 / (float(iv) / DIFF_STEP[game["difficulty"]]), BPM_RANGE[0], BPM_RANGE[1])
	if request.has("bpm"):
		var b = request["bpm"]
		if not _number(b) or b < BPM_RANGE[0] or b > BPM_RANGE[1]:
			return {"ok": false, "error": "\"bpm\" must be %d to %d" % BPM_RANGE}
		bpm = float(b)
	var which = request.get("song", "free")
	var song := {}
	var problem := _enter()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	if which == "free" or which == "":
		song = {"id": "free play", "title": "Free play", "bpm": bpm, "offset": 0.0, "audio": null,
			"notes": _generate(bpm, FREE_BEATS, game["difficulty"], 1)}
	else:
		if typeof(which) != TYPE_STRING:
			return {"ok": false, "error": "\"song\" must be a folder name in songs/ or \"free\""}
		var loaded := _load_song(which)
		if loaded.has("error"):
			return {"ok": false, "error": loaded["error"]}
		song = loaded
	if running:
		_clear()
	_begin(song)
	return {"ok": true, "song": song["title"], "notes": song["notes"].size(), "bpm": song["bpm"], "difficulty": game["difficulty"]}


func _stop(_request: Dictionary) -> Dictionary:
	var was := running
	_clear()
	_track.visible = false
	set_process(false)
	if was:
		stopped.emit()
		_rebuild_if_open()
	return {"ok": true}


func _score(_request: Dictionary) -> Dictionary:
	var out := {"ok": true, "running": running, "song": _song.get("title", ""), "score": score, "combo": combo, "max_combo": max_combo,
		"multiplier": _multiplier(), "cuts": cuts, "misses": missed, "bad_cuts": bad, "bombs_hit": bombs_hit,
		"accuracy": snappedf(_accuracy(), 0.1), "average": int(round(_acc * 100.0 / cuts)) if cuts > 0 else 0}
	out.merge(_last)
	if not _results.is_empty():
		out["results"] = _results
	return out


func _songs_command(_request: Dictionary) -> Dictionary:
	var out := []
	for s in _songs():
		out.append({"folder": s["id"], "title": s["title"], "bpm": s["bpm"], "made": s["made"], "best": best.get(s["id"], 0)})
	return {"ok": true, "folder": _songs_folder(), "songs": out}


func _set_command(request: Dictionary) -> Dictionary:
	var changed := game.duplicate()
	for key in request:
		if key in ["cmd", "id"]:
			continue
		var v = request[key]
		match key:
			"difficulty":
				if not v in DIFFICULTIES:
					return {"ok": false, "error": "\"difficulty\" must be easy, normal or hard"}
				changed[key] = v
			"speed", "bpm":
				var r: Array = SPEED_RANGE if key == "speed" else BPM_RANGE
				if typeof(v) == TYPE_STRING and v.is_valid_float():
					v = v.to_float()
				if not _number(v) or v < r[0] or v > r[1]:
					return {"ok": false, "error": "\"%s\" must be %d to %d" % [key, r[0], r[1]]}
				changed[key] = float(v)
			"hit_sounds", "trails":
				if typeof(v) == TYPE_STRING:
					v = v == "true"
				if typeof(v) != TYPE_BOOL:
					return {"ok": false, "error": "\"%s\" must be true or false" % key}
				changed[key] = v
			_:
				return {"ok": false, "error": "unknown setting \"%s\" (one of: difficulty, speed, bpm, hit_sounds, trails)" % key}
	game = changed
	if not game["trails"]:
		for side in _trails:
			_trails[side]["pts"].clear()
			(_trails[side]["mesh"] as ImmediateMesh).clear_surfaces()
	_save_settings()
	if _lib:
		_lib.touch(self)
	_rebuild_if_open()
	return {"ok": true, "settings": game}


# --- The Rhythm world -----------------------------------------------------------------

func _projects() -> SlopitectModule:
	return _lib.module("projects") if _lib else null


# Whether you're in the game's world (always, without projects.gd).
func in_world() -> bool:
	return _projects() == null or _run({"cmd": "projects_current"}).get("name") == WORLD


# Takes you to the game's world, making it the first time. "" or what went wrong.
func _enter() -> String:
	if _projects() == null:
		return ""
	var here = _run({"cmd": "projects_current"}).get("name", "")
	if here == WORLD:
		return ""
	var exists: bool = _run({"cmd": "projects_list"}).get("projects", []).any(func(p): return p.get("name") == WORLD)
	var before := _return_to
	_return_to = here
	var reply: Dictionary
	if exists:
		reply = _run({"cmd": "projects_open", "name": WORLD})
	else:
		reply = _run({"cmd": "projects_new", "name": WORLD, "modules": ["beatsaber", "beatsaber_path"], "open": true})
	if not reply.get("ok", false):
		_return_to = before
		return "couldn't open the Rhythm world: %s" % reply.get("error", "?")
	_save_settings()
	return ""


func _leave(_request: Dictionary) -> Dictionary:
	_stop({})
	if _has_ui():
		_run({"cmd": "ui_show", "id_panel": PANEL, "visible": false})
	if _projects() == null or not in_world():
		return {"ok": true}
	var back := _return_to if not _return_to.is_empty() and _return_to != WORLD else "start"
	var reply := _run({"cmd": "projects_open", "name": back})
	if not reply.get("ok", false) and back != "start":
		back = "start"
		reply = _run({"cmd": "projects_open", "name": back})
	if not reply.get("ok", false):
		return {"ok": false, "error": "couldn't go back to %s: %s" % [back, reply.get("error", "?")]}
	_return_to = ""
	_save_settings()
	return {"ok": true, "back_in": back}


# Another world opened (from here or the Worlds window): the song stops
# outside the Rhythm world, and its window opens in it.
func _on_world_changed(project: String, _folder: String) -> void:
	if project == WORLD:
		_show_window.call_deferred()
	else:
		if running:
			_stop({})
		if _has_ui():
			_run({"cmd": "ui_show", "id_panel": PANEL, "visible": false})


# --- Songs and maps ------------------------------------------------------------------

func _songs_folder() -> String:
	return _lib.call("home") + "/songs" if _lib else ""


# Every song folder with a readable map.json: {"id", "title", "bpm", "made"}.
func _songs() -> Array:
	var out := []
	var folder := _songs_folder()
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		return out
	var names := DirAccess.get_directories_at(folder)
	names.sort()
	for dir_name in names:
		var map = _lib.call("read_json", folder + "/" + dir_name + "/map.json")
		if typeof(map) != TYPE_DICTIONARY or not _number(map.get("bpm")):
			continue
		var notes = map.get("notes")
		out.append({"id": dir_name, "title": str(map.get("title", dir_name)).left(60), "bpm": float(map["bpm"]),
			"made": typeof(notes) != TYPE_ARRAY or notes.is_empty()})
	return out


# A song ready to play, or {"error"}.
func _load_song(dir_name: String) -> Dictionary:
	if _lib == null:
		return {"error": "songs need the lib module"}
	if dir_name.is_empty() or "/" in dir_name or "\\" in dir_name or dir_name.begins_with("."):
		return {"error": "\"song\" must be a folder name in songs/"}
	var folder := _songs_folder() + "/" + dir_name
	var map = _lib.call("read_json", folder + "/map.json")
	if typeof(map) != TYPE_DICTIONARY:
		return {"error": "no readable %s/map.json" % folder}
	var bpm = map.get("bpm")
	if not _number(bpm) or bpm < 20 or bpm > 400:
		return {"error": "map.json needs \"bpm\" (20 to 400)"}
	var offset = map.get("offset", 0.0)
	if not _number(offset):
		return {"error": "map.json's \"offset\" must be seconds"}
	var audio_path := ""
	var named = map.get("audio")
	if typeof(named) == TYPE_STRING and not named.is_empty():
		if "/" in named or "\\" in named or ".." in named:
			return {"error": "map.json's \"audio\" must be a file in the song's folder"}
		audio_path = folder + "/" + named
	else:
		for ext in ["ogg", "mp3", "wav"]:
			if FileAccess.file_exists(folder + "/song." + ext):
				audio_path = folder + "/song." + ext
				break
	var stream: AudioStream = null
	if not audio_path.is_empty():
		stream = _load_audio(audio_path)
		if stream == null:
			return {"error": "couldn't read the music %s (ogg, mp3 or wav)" % audio_path}
	var notes := []
	var raw = map.get("notes")
	if typeof(raw) == TYPE_ARRAY and not raw.is_empty():
		for i in raw.size():
			var problem := _check_note(raw[i])
			if not problem.is_empty():
				return {"error": "map.json note %d %s" % [i, problem]}
			notes.append([float(raw[i][0]), int(raw[i][1]), int(raw[i][2]), raw[i][3], raw[i][4]])
		notes.sort_custom(func(a, b): return a[0] < b[0])
	else:
		var length := stream.get_length() if stream else 60.0
		var beats := int((length - float(offset)) * float(bpm) / 60.0) - 2
		notes = _generate(float(bpm), maxi(beats, 8), game["difficulty"], dir_name.hash())
	return {"id": dir_name, "title": str(map.get("title", dir_name)).left(60), "bpm": float(bpm), "offset": float(offset),
		"audio": stream, "notes": notes}


func _check_note(n) -> String:
	if typeof(n) != TYPE_ARRAY or n.size() != 5:
		return "must be [beat, lane, row, hand, dir]"
	if not _number(n[0]) or n[0] < 0:
		return "needs a beat of 0 or more"
	if not _number(n[1]) or n[1] < 0 or n[1] > 3 or int(n[1]) != n[1]:
		return "needs a lane 0 to 3"
	if not _number(n[2]) or n[2] < 0 or n[2] > 2 or int(n[2]) != n[2]:
		return "needs a row 0 to 2"
	if not n[3] in ["l", "r", "b"]:
		return "needs a hand l, r or b (bomb)"
	if not n[4] in DIRS:
		return "needs a dir: u d l r ul ur dl dr or a"
	return ""


func _load_audio(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null


# Notes for a tempo: one every DIFF_STEP beats, hands taking turns, each
# hand swinging down then up then down (so you never have to bring a saber
# back without cutting); some diagonals and dots, a few notes for both
# hands, and bombs where the free hand isn't. Seeded, so it's repeatable.
func _generate(bpm: float, beats: int, difficulty: String, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var step: float = DIFF_STEP[difficulty]
	var down := {"l": true, "r": true}
	var hand := "r"
	var notes := []
	var b := 4.0
	while b <= beats:
		var both: bool = rng.randf() < DIFF_DOUBLES[difficulty]
		for h in (["l", "r"] if both else [hand]):
			var d: bool = down[h]
			var roll := rng.randf()
			var dir := "d" if d else "u"
			if roll > 0.9:
				dir = "a"
			elif roll > 0.7:
				dir = ("dl" if h == "l" else "dr") if d else ("ul" if h == "l" else "ur")
			var lane := (1 if h == "l" else 2) if both else (rng.randi_range(0, 1) if h == "l" else rng.randi_range(2, 3))
			var row := rng.randi_range(1, 2) if d else rng.randi_range(0, 1)
			notes.append([b, lane, row, h, dir])
			down[h] = not d
		if not both and rng.randf() < DIFF_BOMBS[difficulty]:
			var free := "l" if hand == "r" else "r"
			# The free hand is high when its next swing is down, low when up.
			notes.append([b, 0 if free == "l" else 3, 0 if down[free] else 2, "b", "a"])
		hand = "l" if hand == "r" else "r"
		b += step
	return notes


# --- Playing -------------------------------------------------------------------------

func _begin(song: Dictionary) -> void:
	_song = song
	_next = 0
	score = 0
	combo = 0
	max_combo = 0
	cuts = 0
	bad = 0
	missed = 0
	bombs_hit = 0
	_acc = 0.0
	_last = {}
	_results = {}
	_music_started = false
	_music_done = false
	var notes: Array = song["notes"]
	var first: float = _beat_time(notes[0][0]) if not notes.is_empty() else 0.0
	_clock = -maxf(LEAD_MIN, _ahead() - first)
	_song_player.stream = song["audio"]
	_place_track()
	_track.visible = true
	_blade.clear()
	running = true
	_update_board()
	set_process(true)
	started.emit(song["title"])
	_rebuild_if_open()


# The track starts at your feet and runs the way you're looking.
func _place_track() -> void:
	var cam: Node3D = ctx.get("camera")
	if cam == null or not is_instance_valid(cam):
		_track.transform = Transform3D.IDENTITY
		return
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	var yaw := atan2(-fwd.x, -fwd.z) if fwd.length() > 0.01 else 0.0
	var floor_y := 0.0
	var origin := cam.get_parent() as Node3D
	if origin:
		floor_y = origin.global_position.y
	_track.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(cam.global_position.x, floor_y, cam.global_position.z))


# Where on the track the track's transform is (for beatsaber_path).
func track_transform() -> Transform3D:
	return _track.global_transform


func _clear() -> void:
	running = false
	_song_player.stop()
	for a in _active:
		_release(a)
	_active.clear()
	for hv in _halves:
		hv["node"].visible = false
		_free_halves.append(hv["node"])
	_halves.clear()
	for p in _pops:
		p["node"].visible = false
		_free_pops.append(p["node"])
	_pops.clear()
	for side in _trails:
		_trails[side]["pts"].clear()
		(_trails[side]["mesh"] as ImmediateMesh).clear_surfaces()


func _beat_time(beat: float) -> float:
	return float(_song["offset"]) + beat * 60.0 / float(_song["bpm"])


# Seconds a note takes from appearing to its beat.
func _ahead() -> float:
	return (HIT_Z - SPAWN_Z) / float(game["speed"])


func _on_music_done() -> void:
	_music_done = true


func _process(delta: float) -> void:
	if running:
		_tick_clock(delta)
		_spawn_due()
		_update_blades(delta)
		_move_and_cut(delta)
		if _song_over():
			_finish()
	_update_halves(delta)
	_update_pops(delta)
	if not running and _halves.is_empty() and _pops.is_empty():
		_track.visible = false
		set_process(false)


# Song time from the audio clock (what you hear), smoothed; our own clock
# during the lead-in and with no music.
func _tick_clock(delta: float) -> void:
	_clock += delta
	if _song_player.stream == null:
		return
	if not _music_started:
		if _clock >= 0.0:
			_song_player.play(_clock)
			_music_started = true
		return
	if _song_player.playing:
		var heard := _song_player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		if absf(heard - _clock) > 0.1:
			_clock = heard
		elif heard > _clock:
			_clock = lerpf(_clock, heard, 0.2)


func _spawn_due() -> void:
	var notes: Array = _song["notes"]
	var ahead := _ahead()
	while _next < notes.size() and _beat_time(notes[_next][0]) - _clock <= ahead:
		_spawn(notes[_next])
		_next += 1


func _note_pos(n: Array) -> Vector3:
	var head := 1.6
	var cam: Node3D = ctx.get("camera")
	if cam and is_instance_valid(cam):
		head = clampf(_track.to_local(cam.global_position).y, 1.0, 2.1) if cam.is_inside_tree() else head
	var rows := [head * 0.48, head * 0.71, head * 0.94]
	return Vector3((float(n[1]) - 1.5) * LANE_W, rows[int(n[2])], 0.0)


func _spawn(n: Array) -> void:
	var bomb: bool = n[3] == "b"
	var pool: Array = _free_bombs if bomb else _free_notes
	var node: MeshInstance3D = pool.pop_back() if not pool.is_empty() else null
	if node == null:
		node = _new_bomb() if bomb else _new_note()  # more at once than the pool holds
	var dir: Vector2 = DIRS[n[4]]
	if not bomb:
		node.material_override = _mat[n[3]]
		var arrow: Node3D = node.get_child(0)
		var dot: Node3D = node.get_child(1)
		arrow.visible = dir != Vector2.ZERO
		dot.visible = dir == Vector2.ZERO
		if arrow.visible:
			arrow.rotation = Vector3(0, 0, atan2(-dir.x, dir.y))
			arrow.position = Vector3(dir.x * 0.03, dir.y * 0.03, NOTE_HALF + 0.01)
	var pos := _note_pos(n)
	var t := _beat_time(n[0])
	pos.z = HIT_Z - (t - _clock) * float(game["speed"])
	node.position = pos
	node.visible = true
	_active.append({"node": node, "kind": "bomb" if bomb else "note", "hand": n[3], "dir": dir, "time": t, "pos": pos})


func _release(a: Dictionary) -> void:
	var node: MeshInstance3D = a["node"]
	node.visible = false
	(_free_bombs if a["kind"] == "bomb" else _free_notes).append(node)


# Each saber's blade in track space now and last frame, its tip's recent
# path, and how fast the tip moves.
func _update_blades(delta: float) -> void:
	for side in ["right", "left"]:
		var sab: Node3D = _sabers.get(side)
		if sab == null or not is_instance_valid(sab) or not sab.is_visible_in_tree():
			_blade.erase(side)
			continue
		var st: Transform3D = _track.global_transform.affine_inverse() * sab.global_transform
		var base := st * Vector3(0, 0, -0.05)
		var tip := st * Vector3(0, 0, -1.05)
		var b: Dictionary = _blade.get(side, {})
		if b.is_empty():
			b = {"base": base, "tip": tip, "hist": [], "speed": 0.0}
			_blade[side] = b
		var hist: Array = b["hist"]
		if tip.distance_to(b["tip"]) > JUMP:  # tracking came back somewhere else: no swing
			b["base"] = base
			b["tip"] = tip
			hist.clear()
		b["pbase"] = b["base"]
		b["ptip"] = b["tip"]
		b["base"] = base
		b["tip"] = tip
		b["speed"] = (tip - b["ptip"]).length() / maxf(delta, 0.0001)
		hist.push_back(tip)
		if hist.size() > HISTORY:
			hist.pop_front()
		if game["trails"]:
			_update_trail(side, sab.global_transform * Vector3(0, 0, -0.05), sab.global_transform * Vector3(0, 0, -1.05))


func _move_and_cut(delta: float) -> void:
	var speed: float = game["speed"]
	for i in range(_active.size() - 1, -1, -1):
		var a: Dictionary = _active[i]
		var node: MeshInstance3D = a["node"]
		var pos: Vector3 = a["pos"]
		var was_z := pos.z
		pos.z = HIT_Z - (float(a["time"]) - _clock) * speed
		a["pos"] = pos
		node.position = pos
		if pos.z >= CUT_FROM and pos.z <= MISS_Z:
			var hit := _which_blade(a, pos.z - was_z)
			if not hit.is_empty():
				_hit(a, hit)
				_active.remove_at(i)
				continue
		if pos.z > MISS_Z:
			if a["kind"] == "note":
				_judge(0, "Miss", pos)
				missed += 1
			_release(a)
			_active.remove_at(i)


# The blade that cut this note this frame, or "": its own colour first,
# then the other one if it swung hard (and any blade for a bomb).
func _which_blade(a: Dictionary, moved: float) -> String:
	var own := "right" if a["hand"] == "r" else "left"
	var order := [own, "left" if own == "right" else "right"] if a["kind"] == "note" else ["right", "left"]
	for side in order:
		if not _blade.has(side):
			continue
		var b: Dictionary = _blade[side]
		var need := MIN_SPEED if (side == own or a["kind"] == "bomb") else WRONG_SPEED
		if float(b["speed"]) >= need and _swept_hit(b, a["pos"], moved):
			return side
	return ""


# Does the blade's path between last frame and now pass through the note's
# box? Tested in the note's own frame (the note moved too): a few blade
# positions in between, each a segment against the box.
func _swept_hit(b: Dictionary, centre: Vector3, moved: float) -> bool:
	var was_centre := centre - Vector3(0, 0, moved)
	var pb: Vector3 = b["pbase"] - was_centre
	var pt: Vector3 = b["ptip"] - was_centre
	var nb: Vector3 = b["base"] - centre
	var nt: Vector3 = b["tip"] - centre
	for k in SWEEP_STEPS + 1:
		var s := float(k) / SWEEP_STEPS
		if _seg_hits_box(pb.lerp(nb, s), pt.lerp(nt, s), NOTE_HALF + HIT_MARGIN):
			return true
	return false


# Slab test: does segment a-b (relative to the box's centre) cross a box of
# half size h?
func _seg_hits_box(a: Vector3, b: Vector3, h: float) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 3:
		if absf(d[axis]) < 0.000001:
			if absf(a[axis]) > h:
				return false
		else:
			var ta := (-h - a[axis]) / d[axis]
			var tb := (h - a[axis]) / d[axis]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return false
	return true


func _hit(a: Dictionary, side: String) -> void:
	var pos: Vector3 = a["pos"]
	var b: Dictionary = _blade[side]
	var hand := "left" if side == "left" else "right"
	_release(a)
	if a["kind"] == "bomb":
		bombs_hit += 1
		_judge(0, "Bomb!", pos)
		_pulse(hand, 1.0, 0.15)
		return
	var hist: Array = b["hist"]
	var oldest: Vector3 = hist[maxi(0, hist.size() - 3)]
	var stroke: Vector3 = b["tip"] - oldest
	var swing := Vector2(stroke.x, stroke.y)
	swing = swing.normalized() if swing.length() > 0.0001 else Vector2.ZERO
	var own: bool = (a["hand"] == "r") == (side == "right")
	var dir: Vector2 = a["dir"]
	var dot := 1.0 if dir == Vector2.ZERO else swing.dot(dir)
	_split(pos, a["hand"], b, stroke)
	if not own or dot < DOT_MIN:
		bad += 1
		_judge(0, "Wrong saber" if not own else "Wrong way", pos)
		_pulse(hand, 0.3, 0.05)
		return
	# Centre: how far the cut's plane passes from the note's middle.
	var plane := Plane(b["base"], b["tip"], b["ptip"])
	var off: float
	if plane.normal.length() < 0.5:
		off = Geometry3D.get_closest_point_to_segment_uncapped(pos, b["base"], b["tip"]).distance_to(pos)
	else:
		off = absf(plane.distance_to(pos))
	var dir_pts := 50.0 * clampf((dot - DOT_MIN) / (DOT_FULL - DOT_MIN), 0.0, 1.0)
	var centre_pts := 30.0 * clampf(1.0 - off / CENTRE_RANGE, 0.0, 1.0)
	var box := AABB(hist[0], Vector3.ZERO)
	for p in hist:
		box = box.expand(p)
	var swing_pts := 20.0 * clampf((box.get_longest_axis_size() - SWING_FROM) / (SWING_FULL - SWING_FROM), 0.0, 1.0)
	var points := int(round(dir_pts + centre_pts + swing_pts))
	cuts += 1
	_last = {"last_points": points, "last_angle_off": snappedf(rad_to_deg(acos(clampf(dot, -1.0, 1.0))), 0.1),
		"last_centre_off_cm": snappedf(off * 100.0, 0.1), "last_swing_cm": snappedf(box.get_longest_axis_size() * 100.0, 1.0)}
	_judge(points, "", pos)
	_pulse(hand, 0.6, 0.06)
	if game["hit_sounds"]:
		_hit_player.play()


# A cut, miss or bad cut: the combo, the score, the label, the board.
func _judge(points: int, word: String, pos: Vector3) -> void:
	if points > 0:
		combo += 1
		max_combo = maxi(max_combo, combo)
		score += points * _multiplier()
	else:
		combo = 0
	_acc += points / 100.0
	if word.is_empty():
		word = "Perfect" if points >= 90 else ("Great" if points >= 70 else ("Good" if points >= 45 else "OK"))
		word += " %d" % points
	_pop(pos + Vector3(0, 0.25, 0), word, points)
	_update_board()
	scored.emit(points, combo)


func _multiplier() -> int:
	return 1 + mini(combo / 10, 7)


func _accuracy() -> float:
	var judged := cuts + bad + missed
	return 100.0 * _acc / judged if judged > 0 else 100.0


func _pulse(hand: String, strength: float, seconds: float) -> void:
	if _controls and _controls.has_method("pulse"):
		_controls.call("pulse", hand, strength, seconds)
	else:
		var c = ctx.get(hand)
		if c is XRController3D:
			(c as XRController3D).trigger_haptic_pulse("haptic", 0.0, strength, seconds, 0.0)


func _song_over() -> bool:
	if _next < _song["notes"].size() or _active.size() > 0:
		return false
	if _song_player.stream != null and _music_started and not _music_done and _song_player.playing:
		return false
	return true


func _finish() -> void:
	var acc := _accuracy()
	var rank := "F"
	for r in RANKS:
		if acc >= r[0]:
			rank = r[1]
			break
	var id: String = _song["id"]
	var new_best := score > int(best.get(id, 0))
	if new_best:
		best[id] = score
		_save_settings()
	_results = {"title": _song["title"], "score": score, "max_combo": max_combo, "accuracy": snappedf(acc, 0.1), "rank": rank,
		"cuts": cuts, "misses": missed, "bad_cuts": bad, "bombs_hit": bombs_hit, "new_best": new_best, "best": best.get(id, score)}
	running = false
	_song_player.stop()
	_board.text = "%s\n%d  rank %s\n%d%%  best combo %d" % [_song["title"], score, rank, int(acc), max_combo]
	finished.emit(_results)
	stopped.emit()
	_rebuild_if_open()


func _update_board() -> void:
	_board.text = "%d\nx%d   combo %d" % [score, _multiplier(), combo]


# --- Effects -------------------------------------------------------------------------

# The note splits along the cut: two halves fly apart across the blade's
# path and shrink away.
func _split(pos: Vector3, hand: String, b: Dictionary, stroke: Vector3) -> void:
	var blade_dir: Vector3 = (b["tip"] - b["base"]).normalized()
	var across := blade_dir.cross(stroke.normalized() if stroke.length() > 0.0001 else Vector3.FORWARD)
	if across.length() < 0.01:
		across = Vector3.RIGHT
	across = across.normalized()
	# The halves' thin side (x) faces across the cut, their length along the blade.
	var along := (blade_dir - across * blade_dir.dot(across)).normalized()
	if along.length() < 0.5:
		along = Vector3.UP
	var basis := Basis(across, along, across.cross(along).normalized())
	for sgn in [-1.0, 1.0]:
		var node: MeshInstance3D = _free_halves.pop_back() if not _free_halves.is_empty() else null
		if node == null:
			if _halves.is_empty():
				return
			var oldest: Dictionary = _halves.pop_front()
			node = oldest["node"]
		node.material_override = _mat[hand]
		node.transform = Transform3D(basis, pos + across * sgn * NOTE_HALF * 0.5)
		node.scale = Vector3.ONE
		node.visible = true
		var vel: Vector3 = across * sgn * randf_range(1.2, 2.0) + stroke.normalized() * 1.5 + Vector3(0, 0.8, 0)
		_halves.append({"node": node, "vel": vel, "spin": Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)), "life": HALF_LIFE})


func _update_halves(delta: float) -> void:
	for i in range(_halves.size() - 1, -1, -1):
		var hv: Dictionary = _halves[i]
		var node: MeshInstance3D = hv["node"]
		hv["life"] = float(hv["life"]) - delta
		if hv["life"] <= 0.0:
			node.visible = false
			_free_halves.append(node)
			_halves.remove_at(i)
			continue
		var vel: Vector3 = hv["vel"]
		vel.y -= 9.8 * delta
		hv["vel"] = vel
		node.position += vel * delta
		node.rotation += hv["spin"] * delta
		node.scale = Vector3.ONE * clampf(float(hv["life"]) / HALF_LIFE, 0.05, 1.0)


func _pop(pos: Vector3, text: String, points: int) -> void:
	var l: Label3D = _free_pops.pop_back() if not _free_pops.is_empty() else null
	if l == null:
		var oldest: Dictionary = _pops.pop_front()
		l = oldest["node"]
	l.text = text
	var col := Color(0.75, 0.75, 0.75)
	if points >= 90:
		col = Color(1.0, 0.85, 0.2)
	elif points >= 70:
		col = Color(0.6, 1.0, 0.6)
	elif points == 0:
		col = Color(1.0, 0.35, 0.3)
	l.modulate = col
	l.position = pos
	l.visible = true
	_pops.append({"node": l, "life": POP_LIFE})


func _update_pops(delta: float) -> void:
	for i in range(_pops.size() - 1, -1, -1):
		var p: Dictionary = _pops[i]
		var l: Label3D = p["node"]
		p["life"] = float(p["life"]) - delta
		if p["life"] <= 0.0:
			l.visible = false
			_free_pops.append(l)
			_pops.remove_at(i)
			continue
		l.position.y += 0.35 * delta
		var c := l.modulate
		c.a = clampf(float(p["life"]) / POP_LIFE, 0.0, 1.0)
		l.modulate = c


func _update_trail(side: String, base: Vector3, tip: Vector3) -> void:
	var t: Dictionary = _trails[side]
	var pts: Array = t["pts"]
	pts.push_front([base, tip])
	while pts.size() > TRAIL_LEN:
		pts.pop_back()
	var im: ImmediateMesh = t["mesh"]
	im.clear_surfaces()
	if pts.size() < 2:
		return
	var col: Color = t["color"]
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, pts.size()):
		var a: Array = pts[i - 1]
		var b: Array = pts[i]
		var ca := Color(col.r, col.g, col.b, 0.6 * (1.0 - float(i - 1) / TRAIL_LEN))
		var cb := Color(col.r, col.g, col.b, 0.6 * (1.0 - float(i) / TRAIL_LEN))
		for v in [[ca, a[0]], [ca, a[1]], [cb, b[0]], [ca, a[1]], [cb, b[1]], [cb, b[0]]]:
			im.surface_set_color(v[0])
			im.surface_add_vertex(v[1])
	im.surface_end()


# A short soft click made here (no sound file).
func _hit_sound() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 0.05)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in count:
		var t := float(i) / rate
		var env := exp(-t * 90.0)
		var v := (0.6 * sin(TAU * 1800.0 * t) + 0.4 * rng.randf_range(-1.0, 1.0)) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	return s


# --- Building (once, at load) ---------------------------------------------------------

func _make_assets() -> void:
	_note_mesh = _rounded_box(NOTE_SIZE, NOTE_ROUND, 4)
	_half_mesh = BoxMesh.new()
	_half_mesh.size = Vector3(NOTE_HALF, NOTE_SIZE, NOTE_SIZE)
	_bomb_mesh = SphereMesh.new()
	_bomb_mesh.radius = 0.13
	_bomb_mesh.height = 0.26
	_bomb_mesh.radial_segments = 12
	_bomb_mesh.rings = 6
	_spike_mesh = CylinderMesh.new()
	_spike_mesh.top_radius = 0.0
	_spike_mesh.bottom_radius = 0.03
	_spike_mesh.height = 0.08
	_spike_mesh.radial_segments = 6
	_dot_mesh = CylinderMesh.new()
	_dot_mesh.top_radius = 0.05
	_dot_mesh.bottom_radius = 0.05
	_dot_mesh.height = 0.01
	_dot_mesh.radial_segments = 16
	# A chevron (two triangles) in the XY plane facing +z, tip up.
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.09, 0.0, 0.0), Vector3(0.0, 0.07, 0.0), Vector3(0.0, 0.035, 0.0),
		Vector3(0.0, 0.07, 0.0), Vector3(0.09, 0.0, 0.0), Vector3(0.0, 0.035, 0.0)])
	_arrow_mesh = ArrayMesh.new()
	_arrow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mat["r"] = _glow(Color(1.0, 0.2, 0.2))
	_mat["l"] = _glow(Color(0.2, 0.4, 1.0))
	_mat["marker"] = _flat(Color(1, 1, 1))
	_mat["marker"].cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat["bomb"] = _flat(Color(0.08, 0.08, 0.1))
	_mat["bomb"].shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mat["bomb"].roughness = 0.4
	_mat["spike"] = _glow(Color(0.5, 0.05, 0.4))
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.8, 0.8, 0.85)
	silver.metallic = 1.0
	silver.roughness = 0.25
	_mat["silver"] = silver
	var handle := StandardMaterial3D.new()
	handle.albedo_color = Color(0.12, 0.12, 0.14)
	handle.metallic = 0.3
	handle.roughness = 0.6
	_mat["handle"] = handle
	var trail := StandardMaterial3D.new()
	trail.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail.vertex_color_use_as_albedo = true
	trail.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat["trail"] = trail


func _make_pools() -> void:
	for i in POOL_NOTES:
		_free_notes.append(_new_note())
	for i in POOL_BOMBS:
		_free_bombs.append(_new_bomb())
	for i in POOL_HALVES:
		var h := MeshInstance3D.new()
		h.mesh = _half_mesh
		h.visible = false
		_track.add_child(h)
		_free_halves.append(h)
	for i in POOL_POPS:
		var l := Label3D.new()
		l.font_size = 64
		l.pixel_size = 0.002
		l.outline_size = 12
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.visible = false
		_track.add_child(l)
		_free_pops.append(l)


# A note: the rounded box, then its arrow (child 0) and dot (child 1).
func _new_note() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _note_mesh
	m.material_override = _mat["r"]
	m.visible = false
	var a := MeshInstance3D.new()
	a.mesh = _arrow_mesh
	a.material_override = _mat["marker"]
	m.add_child(a)
	var d := MeshInstance3D.new()
	d.mesh = _dot_mesh
	d.material_override = _mat["marker"]
	d.position = Vector3(0, 0, NOTE_HALF + 0.01)
	d.rotation_degrees = Vector3(90, 0, 0)
	m.add_child(d)
	_track.add_child(m)
	return m


func _new_bomb() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _bomb_mesh
	m.material_override = _mat["bomb"]
	m.visible = false
	for v in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var s := MeshInstance3D.new()
		s.mesh = _spike_mesh
		s.material_override = _mat["spike"]
		s.position = v * 0.13
		s.basis = Basis(Quaternion(Vector3.UP, v))
		m.add_child(s)
	_track.add_child(m)
	return m


func _make_saber(side: String) -> void:
	var hand := ctx.get(side) as Node3D
	if hand == null:
		return
	var box := hand.get_node_or_null("Mesh") as Node3D
	if box != null and box.visible:
		box.visible = false
		_hidden_boxes.append(box)
	var blade := CylinderMesh.new()
	blade.top_radius = 0.02
	blade.bottom_radius = 0.02
	blade.height = 1.0
	blade.radial_segments = 10
	var sab := Node3D.new()
	sab.name = "beatsaber_" + side
	hand.add_child(sab)
	sab.transform = _hilt(side)
	_sabers[side] = sab
	# Blade from the grip (z -0.05) out to z -1.05, before scaling.
	_part(sab, blade, _mat["r"] if side == "right" else _mat["l"], Vector3(0, 0, -0.55))
	_part(sab, _cyl(0.018, 0.22), _mat["handle"], Vector3(0, 0, 0.1))
	_part(sab, _cyl(0.035, 0.012), _mat["silver"], Vector3(0, 0, -0.03))
	var band := _cyl(0.024, 0.012)
	for z in [0.0, 0.06, 0.12, 0.18]:
		_part(sab, band, _mat["silver"], Vector3(0, 0, z))
	_part(sab, _cyl(0.026, 0.02), _mat["silver"], Vector3(0, 0, 0.215))
	var tn := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	tn.mesh = im
	tn.material_override = _mat["trail"]
	tn.top_level = true
	tn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tn)
	_trails[side] = {"node": tn, "mesh": im, "pts": [], "color": Color(1.0, 0.2, 0.2) if side == "right" else Color(0.2, 0.4, 1.0)}


func _show_sabers() -> void:
	var shown := true
	if _hands and is_instance_valid(_hands) and _hands.has_method("sabers_shown"):
		shown = _hands.call("sabers_shown")
	for side in _sabers:
		if is_instance_valid(_sabers[side]):
			_sabers[side].visible = shown
	if not shown:
		_blade.clear()
		for side in _trails:
			_trails[side]["pts"].clear()
			(_trails[side]["mesh"] as ImmediateMesh).clear_surfaces()


func _cyl(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 10
	return c


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var p := MeshInstance3D.new()
	p.mesh = mesh
	p.material_override = mat
	p.position = pos
	p.rotation_degrees = Vector3(90, 0, 0)
	parent.add_child(p)


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.5
	return m


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# A box with rounded edges and corners: radius r, n steps across each face.
func _rounded_box(size: float, r: float, n: int) -> Mesh:
	var h := size * 0.5
	var inner := h - r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axes := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
	for ax in 3:
		for sgn in [-1.0, 1.0]:
			var ua: Vector3 = axes[(ax + 1) % 3]
			var va: Vector3 = axes[(ax + 2) % 3]
			var origin: Vector3 = axes[ax] * sgn * h
			var grid: Array = []
			for i in range(n + 1):
				for j in range(n + 1):
					var p: Vector3 = origin + ua * lerpf(-h, h, float(i) / n) + va * lerpf(-h, h, float(j) / n)
					grid.append(_round_point(p, inner, r))
			for i in range(n):
				for j in range(n):
					var a: Dictionary = grid[i * (n + 1) + j]
					var b: Dictionary = grid[(i + 1) * (n + 1) + j]
					var c: Dictionary = grid[(i + 1) * (n + 1) + j + 1]
					var d: Dictionary = grid[i * (n + 1) + j + 1]
					_add_tri(st, a, b, c)
					_add_tri(st, a, c, d)
	return st.commit()


# Pulls a point on the cube's surface onto the rounded shape: position and normal.
func _round_point(p: Vector3, inner: float, r: float) -> Dictionary:
	var q := Vector3(clampf(p.x, -inner, inner), clampf(p.y, -inner, inner), clampf(p.z, -inner, inner))
	var nrm := (p - q).normalized()
	return {"pos": q + nrm * r, "nrm": nrm}


# Adds a triangle, flipping it if needed so it faces outward (along its normal).
func _add_tri(st: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	var pa: Vector3 = a["pos"]
	var pb: Vector3 = b["pos"]
	var pc: Vector3 = c["pos"]
	if (pb - pa).cross(pc - pa).dot(a["nrm"]) < 0.0:
		var t: Dictionary = b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(v["nrm"])
		st.add_vertex(v["pos"])


# --- The fit and the saved settings ----------------------------------------------------

# The saber's place in the hand, seen from the controller: turned up onto
# the handle, the hold point on the handle's middle, scaled.
func _hilt(side: String) -> Transform3D:
	var g: Array = fit["grip"]
	var mirror := 1.0 if side == "right" else -1.0
	var grip := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(fit["angle"])), Vector3(mirror * g[0], g[1], g[2]) / 100.0)
	return grip * Transform3D(Basis.from_scale(Vector3.ONE * SABER_SCALE), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(0, 0, -fit["hold"] / 100.0))


func _refit() -> void:
	for side in _sabers:
		if is_instance_valid(_sabers[side]):
			_sabers[side].transform = _hilt(side)


func _config(request: Dictionary) -> Dictionary:
	if request.get("reset", false) == true:
		fit = FIT_DEFAULTS.duplicate(true)
		_refit()
		_save_settings()
		return {"ok": true, "fit": fit}
	var changed := fit.duplicate(true)
	for key in request:
		if key in ["cmd", "id"]:
			continue
		var v = request[key]
		match key:
			"angle":
				if not _number(v) or v < FIT_ANGLE_RANGE[0] or v > FIT_ANGLE_RANGE[1]:
					return {"ok": false, "error": "\"angle\" must be %d to %d degrees" % FIT_ANGLE_RANGE}
				changed["angle"] = float(v)
			"grip":
				if not _cm3(v):
					return {"ok": false, "error": "\"grip\" must be [x, y, z] in cm, each -%d to %d" % [FIT_CM_MAX, FIT_CM_MAX]}
				changed["grip"] = (v as Array).map(func(n): return float(n))
			"hold":
				if not _number(v) or v < 0.0 or v > FIT_CM_MAX:
					return {"ok": false, "error": "\"hold\" must be 0 to %d cm" % FIT_CM_MAX}
				changed["hold"] = float(v)
			_:
				return {"ok": false, "error": "unknown setting \"%s\" (one of: angle, grip, hold, reset)" % key}
	fit = changed
	_refit()
	_save_settings()
	return {"ok": true, "fit": fit}


func _number(v) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT]


func _cm3(v) -> bool:
	return typeof(v) == TYPE_ARRAY and v.size() == 3 and v.all(func(n): return _number(n) and absf(n) <= FIT_CM_MAX)


# The fit (flat keys, as before), the game settings and the best scores.
func _save_settings() -> void:
	if _lib == null:
		return
	var out := fit.duplicate(true)
	out["game"] = game
	out["best"] = best
	out["return_to"] = _return_to
	var problem: String = _lib.call("write_json", SETTINGS_PATH, out, "\t")
	if not problem.is_empty():
		push_error("Slopitect beatsaber: " + problem)


func _load_settings() -> void:
	var saved = _lib.call("read_json", SETTINGS_PATH)
	if saved == null:
		return
	if typeof(saved) != TYPE_DICTIONARY:
		push_error("Slopitect beatsaber: %s isn't readable; using the defaults" % SETTINGS_PATH)
		return
	var a = saved.get("angle")
	if _number(a) and a >= FIT_ANGLE_RANGE[0] and a <= FIT_ANGLE_RANGE[1]:
		fit["angle"] = float(a)
	if _cm3(saved.get("grip")):
		fit["grip"] = (saved["grip"] as Array).map(func(n): return float(n))
	var h = saved.get("hold")
	if _number(h) and h >= 0.0 and h <= FIT_CM_MAX:
		fit["hold"] = float(h)
	_refit()
	var g = saved.get("game")
	if typeof(g) == TYPE_DICTIONARY:
		if g.get("difficulty") in DIFFICULTIES:
			game["difficulty"] = g["difficulty"]
		for key in ["speed", "bpm"]:
			var r: Array = SPEED_RANGE if key == "speed" else BPM_RANGE
			if _number(g.get(key)) and g[key] >= r[0] and g[key] <= r[1]:
				game[key] = float(g[key])
		for key in ["hit_sounds", "trails"]:
			if typeof(g.get(key)) == TYPE_BOOL:
				game[key] = g[key]
	if typeof(saved.get("return_to")) == TYPE_STRING:
		_return_to = saved["return_to"]
	var b = saved.get("best")
	if typeof(b) == TYPE_DICTIONARY:
		for key in b:
			if typeof(key) == TYPE_STRING and _number(b[key]):
				best[key] = int(b[key])
