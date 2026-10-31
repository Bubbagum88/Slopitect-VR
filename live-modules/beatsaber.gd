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
# first, saving the one you were in, and opens the game's three windows
# (see _build: settings on the left, songs in the middle, scores on the
# right). They step aside while a song plays and come back after it with
# your score. Opening the world from the Worlds window does the same.
# Getting out: Leave (in the Rhythm window or the Settings window, or
# beatsaber_leave) stops the song and takes you back to the world you came
# from (remembered even across a restart). Going to any other world stops
# the song too. Without projects.gd and save.gd it plays where you are.
# In the Rhythm world the usual sky, sun and floor give way to its own dark
# stage (see _stage_on), put back when you leave.
# The track is laid out where you stand, facing the way you look, when a
# song starts. A score board stands to its left.
#
# Songs: a folder per song in the Slopitect folder's songs/, holding the
# music (song.ogg, .mp3 or .wav, or the file "audio" names) and map.json:
#   {"title": "My song", "artist": "...", "pack": "My album", "bpm": 120,
#    "offset": 0.0, "audio": "song.ogg",
#    "notes": [[beat, lane, row, hand, dir], ...]}
# beat counts from offset (seconds into the music); lane 0-3 left to right;
# row 0-2 bottom to top; hand "l" (blue), "r" (red) or "b" (a bomb); dir
# one of u d l r ul ur dl dr (the way to cut) or a (any way, a dot note).
# An album cover can sit beside it as cover.png (or .jpg / .webp); songs
# with the same "pack" are grouped as an album in the middle window.
# A map.json without notes (just "bpm") gets notes made for the whole song,
# so any song can be played by giving its tempo. Free play needs no song:
# notes at the Settings window's tempo, 128 beats, no music.
# Made notes follow the swing flow (each hand alternates down and up, and
# the free hand's bombs sit where that hand isn't), from a fixed seed, so
# a song's made map is the same every time.
# Custom song folders (the common community format) play too: Info.dat
# (version 2 or 4) naming the music (song.egg is Ogg) and cover, and a
# difficulty file per chart (versions 2, 3 or 4). They go in the "Custom
# songs" pack. The middle window shows only the difficulties (Easy to
# Expert+) and modes (Standard, One saber, No arrows) a song has; each mode
# keeps its own scores. Walls (keep your head out) and arcs (shown) come
# from the maps too; chains and lights aren't played yet.
# With net.gd loaded, an Online pack finds and downloads such folders from
# BeatSaver (see _online_elements), once its hosts are allowed on the PC.
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
const WALL_LAYERS := 5           # a full-height wall's layers (the map's units)
# Walls: see-through with glowing edges and slow bands of light rippling
# across them. The box is a unit cube scaled to size, so the edges are
# measured in metres from its scale; no texture.
const WALL_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 colour : source_color = vec4(1.0, 0.2, 0.35, 1.0);
varying vec3 local;
varying vec3 size;
varying vec3 world;
void vertex() {
	local = VERTEX;
	size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 d = (0.5 - abs(local)) * size;  // metres to each pair of faces
	float near = min(d.x, min(d.y, d.z));  // about 0: the face this is on
	float far = max(d.x, max(d.y, d.z));
	float edge = 1.0 - smoothstep(0.0, 0.035, d.x + d.y + d.z - near - far);  // the next nearest: an edge
	float shimmer = 0.5 + 0.5 * sin(world.y * 9.0 + world.x * 5.0 - TIME * 2.2) * sin(world.z * 3.0 + TIME * 1.3);
	ALBEDO = colour.rgb * (0.6 + 0.6 * shimmer) + edge * vec3(1.0, 0.75, 0.8);
	ALPHA = clamp(0.14 + 0.12 * shimmer + edge * 0.8, 0.0, 1.0);
}
"""
const MENU_DB := -10.0           # the menu music's level
const MENU_PREVIEW := 12.0       # seconds of a song's preview before it starts again
const MENU_FADE := 1.2           # seconds the menu music fades in
const SLICE_SECONDS := 0.42      # the cut sound's length
const SLICE_LOW_PASS := 2200.0   # Hz: the cut sound's final low-pass
const FLY_FROM := -40.0          # metres beyond the track's far end a note appears
const FLY_TIME := 0.45           # seconds it takes to fly in to the track
const ARC_STEPS := 20            # pieces along an arc
const ARC_WIDTH := 0.035
const ARC_PULL := 0.6            # metres an arc's ends pull out along their notes' cut directions
const ARROW_W := 0.2             # the arrow: a wide flat triangle
const ARROW_H := 0.075
const ARROW_EDGE := 0.025        # its flat end's gap from the block's edge
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
const DIFFICULTIES := ["easy", "normal", "hard", "expert", "expert_plus"]
const DIFF_LABELS := {"easy": "Easy", "normal": "Normal", "hard": "Hard", "expert": "Expert", "expert_plus": "Expert+"}
const DIFF_STEP := {"easy": 2.0, "normal": 1.0, "hard": 0.5, "expert": 0.5, "expert_plus": 0.5}  # beats between made notes
const DIFF_DOUBLES := {"easy": 0.0, "normal": 0.08, "hard": 0.15, "expert": 0.25, "expert_plus": 0.4}
const DIFF_BOMBS := {"easy": 0.0, "normal": 0.04, "hard": 0.1, "expert": 0.12, "expert_plus": 0.15}
const MODES := ["Standard", "OneSaber", "NoArrows"]
const MODE_LABELS := {"Standard": "Standard", "OneSaber": "One saber", "NoArrows": "No arrows"}
# Custom song folders (Info.dat): their difficulty names, cut directions and note types.
const DAT_DIFFS := {"Easy": "easy", "Normal": "normal", "Hard": "hard", "Expert": "expert", "ExpertPlus": "expert_plus"}
const DAT_DIRS := ["u", "d", "l", "r", "ul", "ur", "dl", "dr", "a"]
const DAT_PACK := "Custom songs"
const GAME_DEFAULTS := {"difficulty": "normal", "speed": 8.0, "bpm": 100.0, "hit_sounds": true, "trails": true, "auto_sabers": true, "menu_music": true}
const SPEED_RANGE := [4.0, 14.0]
const BPM_RANGE := [60.0, 200.0]
const RANKS := [[97.0, "S"], [90.0, "A"], [80.0, "B"], [70.0, "C"], [60.0, "D"], [0.0, "F"]]
const FIT_DEFAULTS := {"angle": 45.0, "grip": [0.0, -1.8, 4.8], "hold": 10.0}  # Touch: Chromium's WebXR grip is the aim turned up 45 degrees, 2.5 cm down; isaac saw the sabers too far forward on the headset, so 3 cm further back
const FIT_ANGLE_RANGE := [-30.0, 90.0]
const FIT_CM_MAX := 15.0
const SONG_ROWS := 5
const PANEL_LEFT := "rhythm_left"
const PANEL_SCORES := "rhythm_scores"
const PANELS := ["rhythm_left", "beatsaber", "rhythm_scores"]
const LEFT_TABS := ["Modifiers", "Colours", "Settings"]
const SCORE_TABS := ["Local", "Global"]
const LEFT_SIZE := Vector2(0.62, 0.56)
const MAIN_SIZE := Vector2(1.1, 0.62)
const SCORES_SIZE := Vector2(0.62, 0.56)
const ROWS := 6                  # packs and songs shown at once
const ALL_SONGS := "All songs"
const FREE_PACK := "Free play"
# Online: community song folders from BeatSaver's public site, through the
# net module (so only once its hosts are allowed on the PC).
const ONLINE_PACK := "Online"
const ONLINE_API := "https://api.beatsaver.com"
const ONLINE_HOSTS := ["api.beatsaver.com", "r2cdn.beatsaver.com", "cdn.beatsaver.com", "eu.cdn.beatsaver.com", "na.cdn.beatsaver.com"]
const ONLINE_SORTS := {"search": "Relevance", "latest": "Latest", "top": "Rating"}
const ONLINE_ROWS := 4                # results shown at once (under the search rows)
const ONLINE_LIST_BYTES := 2 * 1024 * 1024
const ONLINE_ZIP_BYTES := 40 * 1024 * 1024
const ONLINE_UNPACKED_BYTES := 80 * 1024 * 1024
const ONLINE_FILES := ["dat", "egg", "ogg", "wav", "mp3", "jpg", "jpeg", "png", "webp", "json"]  # what a song folder keeps
const TOP_SCORES := 10
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
var _menu_player: AudioStreamPlayer  # music while the menus are open
var _menu_loop: Timer                # brings a preview back to its start
var _menu_for := ""                  # what the menu music is playing ("calm" or a song folder)
var _menu_from := 0.0
var _calm: AudioStreamWAV            # the calm loop, made on a worker thread at load
var _calm_task := -1
var _hidden_boxes: Array = []
var _sabers := {}           # side -> Node3D on that controller
var _trails := {}           # side -> {"node", "mesh", "pts", "color"}

# Shared meshes and materials.
var _note_mesh: Mesh
var _half_mesh: BoxMesh
var _bomb_mesh: SphereMesh
var _spike_mesh: CylinderMesh
var _arrow_mesh: ArrayMesh
var _wall_mesh: BoxMesh
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
var _next_wall := 0
var _next_arc := 0
var _walls_on: Array = []   # {"node", "time", "end", "box" (AABB in track space at z 0, z from end to start)}
var _arcs_on: Array = []    # {"node", "time", "end"}
var _in_wall := false       # your head is inside a wall
var bumped := 0             # times your head went into a wall this song
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
var _pack := "All songs"    # the pack shown in the middle window
var _hands_before := ""     # the hands style to put back when you leave (auto sabers)
var _placed := false        # the track was laid out with the windows
var _stage: Node3D          # the Rhythm world's surroundings, laid out with the track
var _swapped := {}          # what the stage changed in the main scene, to put back
var _sign: Node3D           # the glowing title over the windows (menus only)
var _selected := "free"     # the song chosen there ("free" for free play)
var _mode := "Standard"     # its mode (a custom song's characteristic)
var _song_cache = null      # _songs() as last read; null to read the folder again
var _online := []           # the last list from BeatSaver: {key, title, artist, mapper, bpm, seconds, levels, url}
var _online_pick := ""      # the chosen result's key
var _online_query := ""
var _online_page := 0
var _online_note := "Search, or look at the latest or top rated songs."
var _online_busy := false   # a list or a download on its way
var scores := {}            # "song|difficulty" -> your top 10 [{score, rank, accuracy, combo, date}]


func setup() -> String:
	register("beatsaber_start", _start, "start a song: optional song (a folder in songs/, or \"free\" for free play), difficulty (easy, normal, hard, expert, expert_plus), mode (Standard, OneSaber, NoArrows), bpm (free play, 60 to 200), interval (old: seconds between free-play notes, 0.3 to 2)")
	register("beatsaber_stop", _stop, "stop the song and clear the notes")
	register("beatsaber_score", _score, "the score, combo, multiplier, cuts, misses, bad cuts, bombs hit, accuracy, and the last cut's points, direction and centre offset; after a song, its results")
	register("beatsaber_songs", _songs_command, "the songs in the Slopitect folder's songs/ (folder, title, bpm, notes or made, best score)")
	register("beatsaber_set", _set_command, "the game's settings (usable in the headset): any of difficulty (easy, normal, hard, expert, expert_plus), speed (note speed m/s, 4 to 14), bpm (free play tempo, 60 to 200), hit_sounds, trails, auto_sabers (sabers in the Rhythm world, hands back after; true/false), menu_music (true/false)")
	register("beatsaber_do", _do, "the Rhythm window: act = toggle (goes to the Rhythm world first), show (optional page: a tab), refresh, page (page number for the song list), pack (pack), select (song), mode (mode), play, enter (go to the Rhythm world), leave (back to the world you came from); online songs (needs net.gd and BeatSaver's hosts allowed): online (list = search with query, latest or top), online_pick (key), online_page (page), online_get (key: downloads it, or plays it once it's here)")
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
	_menu_player = AudioStreamPlayer.new()
	_menu_player.volume_db = MENU_DB
	add_child(_menu_player)
	_menu_loop = Timer.new()
	_menu_loop.one_shot = true
	_menu_loop.timeout.connect(_menu_again)
	add_child(_menu_loop)
	_calm_task = WorkerThreadPool.add_task(_make_calm, false, "Rhythm Sabers menu music")  # off the main thread: no hitch
	_hit_player = AudioStreamPlayer.new()
	_hit_player.stream = _hit_sound()
	_hit_player.max_polyphony = 4
	_hit_player.volume_db = -4.0
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
	if _projects() != null and in_world():  # loaded while already in the Rhythm world
		_stage_on()
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
		_rebuild_if_open()


func _exit_tree() -> void:
	if _calm_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_calm_task)
		_calm_task = -1
	if _lib and _lib.info_changed.is_connected(_on_info_changed):
		_lib.info_changed.disconnect(_on_info_changed)
	_stage_off()
	for box in _hidden_boxes:
		if is_instance_valid(box):
			box.visible = true
	_hidden_boxes.clear()
	for side in _sabers:
		if is_instance_valid(_sabers[side]):
			_sabers[side].queue_free()
	_sabers.clear()
	for id_panel in PANELS:
		ctx["server"].run({"cmd": "ui_remove", "id_panel": id_panel})


# --- Menu, Settings and the window ------------------------------------------------

func menu_info() -> Dictionary:
	return {"id": "beatsaber", "label": "Rhythm", "order": 60, "action": {"cmd": "beatsaber_do", "act": "toggle"}}


func settings_info() -> Dictionary:
	var diffs := []
	for d in DIFFICULTIES:
		diffs.append({"label": DIFF_LABELS[d], "value": d})
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
		{"id": "auto_sabers", "type": "toggle", "label": "Sabers in the Rhythm world", "value": game["auto_sabers"],
			"set": {"cmd": "beatsaber_set", "auto_sabers": "{value}"}},
		{"id": "menu_music", "type": "toggle", "label": "Music in the Rhythm menus", "value": game["menu_music"],
			"set": {"cmd": "beatsaber_set", "menu_music": "{value}"}},
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
			if in_world() and _shown(PANEL):
				_hide_windows()
				return {"ok": true, "shown": false}
			var problem := _enter()
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			return _show_windows()
		"enter":
			var problem := _enter()
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			return _show_windows()
		"leave":
			return _leave({})
		"show":
			var page = request.get("page", "")
			if not (page == "" or page in LEFT_TABS or page in SCORE_TABS):
				return {"ok": false, "error": "\"page\" must be one of %s or %s" % [LEFT_TABS, SCORE_TABS]}
			return _show_windows(page)
		"refresh":
			_rescan()
			var problem := _build()
			return {"ok": false, "error": problem} if not problem.is_empty() else {"ok": true}
		"pack":
			var pack = request.get("pack")
			if typeof(pack) != TYPE_STRING or not pack in _packs():
				return {"ok": false, "error": "\"pack\" must be one of %s" % [_packs()]}
			_pack = pack
			_song_page = 0
			var drawn := _build()
			if not drawn.is_empty():
				return {"ok": false, "error": drawn}
			return {"ok": true, "pack": _pack}
		"select":
			var song = request.get("song")
			if typeof(song) == TYPE_STRING and song != "free" and not _songs().any(func(x): return x["id"] == song):
				_rescan()  # a folder added since the windows opened
			if typeof(song) != TYPE_STRING or not (song == "free" or _songs().any(func(x): return x["id"] == song)):
				return {"ok": false, "error": "\"song\" must be \"free\" or a folder in songs/"}
			_selected = song
			_fit_choice()
			_menu_music()
			var drawn := _build()
			if not drawn.is_empty():
				return {"ok": false, "error": drawn}
			return {"ok": true, "selected": _selected}
		"online":
			var which = request.get("list", "search")
			if _net() == null:
				return {"ok": false, "error": "online songs need the net module (load net.gd)"}
			if not which in ONLINE_SORTS:
				return {"ok": false, "error": "\"list\" must be search, latest or top"}
			var query = request.get("query", "")
			if typeof(query) != TYPE_STRING or query.length() > 40:
				return {"ok": false, "error": "\"query\" must be text of up to 40 characters"}
			if _online_busy:
				return {"ok": false, "error": "still waiting for BeatSaver"}
			_online_query = query.strip_edges()
			if which == "search" and _online_query.is_empty():
				return {"ok": false, "error": "type something to search for first (Keys opens the keyboard)"}
			_pack = ONLINE_PACK
			_online_list(which, _online_query)
			return {"ok": true, "looking": true}
		"online_pick":
			if _online_item(str(request.get("key", ""))).is_empty():
				return {"ok": false, "error": "\"key\" must be one of the listed songs"}
			_online_pick = request["key"]
			var drawn := _build()
			return {"ok": drawn.is_empty(), "error": drawn} if not drawn.is_empty() else {"ok": true, "picked": _online_pick}
		"online_page":
			var page = request.get("page")
			if typeof(page) not in [TYPE_INT, TYPE_FLOAT]:
				return {"ok": false, "error": "\"page\" must be a number"}
			_online_page = maxi(0, int(page))
			var drawn := _build()
			return {"ok": false, "error": drawn} if not drawn.is_empty() else {"ok": true}
		"online_get":
			var key = request.get("key", "")
			if _online_item(str(key)).is_empty():
				return {"ok": false, "error": "\"key\" must be one of the listed songs"}
			if DirAccess.dir_exists_absolute(_songs_folder() + "/" + _online_folder(key)):
				_selected = _online_folder(key)
				_fit_choice()
				return _start({"song": _selected})
			if _online_busy:
				return {"ok": false, "error": "still waiting for BeatSaver"}
			_online_download(key)
			return {"ok": true, "downloading": key}
		"mode":
			var mode = request.get("mode")
			var info := {} if _selected == "free" else _song_info(_selected)
			if not mode in _modes_of(info):
				return {"ok": false, "error": "\"mode\" must be one of %s for this song" % [_modes_of(info)]}
			_mode = mode
			_fit_choice()
			var drawn := _build()
			if not drawn.is_empty():
				return {"ok": false, "error": drawn}
			return {"ok": true, "mode": _mode, "difficulty": game["difficulty"]}
		"play":
			return _start({"song": _selected})
		"practice":
			return {"ok": false, "error": "Practice comes in a later step"}
		"page":
			var page = request.get("page")
			if typeof(page) not in [TYPE_INT, TYPE_FLOAT]:
				return {"ok": false, "error": "\"page\" must be a number"}
			_song_page = maxi(0, int(page))
			var drawn := _build()
			if not drawn.is_empty():
				return {"ok": false, "error": drawn}
			return {"ok": true, "page": _song_page}
	return {"ok": false, "error": "\"act\" must be toggle, show, refresh, pack, select, play, practice, page, enter or leave"}


func _shown(id_panel: String) -> bool:
	var got := _run({"cmd": "ui_get", "id_panel": id_panel})
	return got.get("ok", false) and got.get("panel", {}).get("visible", false)


# The three windows come up in front of you, and the track will run
# between them the way you're facing now.
func _show_windows(page := "") -> Dictionary:
	if not is_inside_tree():  # a deferred show that lands after the module was unloaded
		return {"ok": false, "error": "Rhythm Sabers is unloading"}
	if not running:
		_place_track()
		_placed = true
	_rescan()
	var problem := _build(page, true)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	for id_panel in PANELS:
		_run({"cmd": "ui_show", "id_panel": id_panel, "visible": true})
	_sign_shown(true)
	_menu_music()
	return {"ok": true, "shown": true}


func _hide_windows() -> void:
	_sign_shown(false)
	_menu_stop()
	if not _has_ui():
		return
	for id_panel in PANELS:
		if _run({"cmd": "ui_get", "id_panel": id_panel}).get("ok", false):
			_run({"cmd": "ui_show", "id_panel": id_panel, "visible": false})


# The game's three windows, like a stage around you:
#   left ("rhythm_left"): tabs Modifiers, Colours, Settings
#   middle ("beatsaber"): song packs (albums) and their songs on its left
#       half; the chosen song's cover, its difficulty, the mode, Play and
#       Practice on its right
#   right ("rhythm_scores"): tabs Local (your top 10 for the song and
#       difficulty) and Global (needs an online score service; none yet)
# Built when they open, when a setting or the chosen song changes, and when
# a song starts or ends; never per frame. A tab you're on stays. With
# place_them, they go to their spots on the stage (from the track's place).
func _build(page := "", place_them := false) -> String:
	if not _has_ui():
		return "the Rhythm windows need the vrui module"
	var problems := []
	for spec in [[PANEL_LEFT, "Game settings", LEFT_SIZE, _left_elements(), LEFT_TABS, Vector3(-0.95, 1.3, -0.85), 50.0],
			[PANEL, TITLE, MAIN_SIZE, _main_elements(), [], Vector3(0.0, 1.35, -1.15), 0.0],
			[PANEL_SCORES, "Scores", SCORES_SIZE, _scores_elements(), SCORE_TABS, Vector3(0.95, 1.3, -0.85), -50.0]]:
		var id_panel: String = spec[0]
		var tabs: Array = spec[4]
		var at: Transform3D = _track.global_transform * Transform3D(Basis(Vector3.UP, deg_to_rad(spec[6])), spec[5])
		var where := {"place": "world", "position": [at.origin.x, at.origin.y, at.origin.z],
			"rotation": [0.0, rad_to_deg(at.basis.get_euler().y), 0.0]}
		var request := {"id_panel": id_panel, "elements": spec[3]}
		if page != "" and page in tabs:
			request["page"] = page
		if _run({"cmd": "ui_get", "id_panel": id_panel}).get("ok", false):
			request["cmd"] = "ui_update"
			if place_them:
				request.merge(where)
				request["home"] = where.duplicate()
				request["keep_place"] = true
		else:
			request.merge({"cmd": "ui_add", "title": spec[1], "size": [spec[2].x, spec[2].y], "chrome": true, "visible": false,
				"home": where.duplicate(), "keep_place": true})  # stage windows stay at their spots (vrui opens others in front)
			request.merge(where)
			if not tabs.is_empty():
				request["pages"] = tabs
				if not request.has("page"):
					request["page"] = tabs[0]
		var reply := _run(request)
		if not reply.get("ok", false):
			problems.append("%s: %s" % [id_panel, reply.get("error", "couldn't be drawn")])
	return "; ".join(problems)


func _left_elements() -> Array:
	var els := []
	var top := LEFT_SIZE.y / 2.0 - 0.06
	for tab in ["Modifiers", "Colours"]:
		els.append({"type": "text", "id": "soon_" + tab.to_lower(), "page": tab, "text": "%s: coming in a later step." % tab,
			"at": [0.0, top], "width": LEFT_SIZE.x - 0.06, "color": "muted"})
	var w := LEFT_SIZE.x - 0.1
	var y := top
	els.append({"type": "slider", "id": "speed", "page": "Settings", "label": "Note speed (m/s)", "at": [0.0, y], "size": [w, 0.06],
		"min": SPEED_RANGE[0], "max": SPEED_RANGE[1], "step": 0.5, "value": game["speed"], "action": {"cmd": "beatsaber_set", "speed": "{value}"}})
	y -= 0.085
	els.append({"type": "slider", "id": "bpm", "page": "Settings", "label": "Free play tempo (beats a minute)", "at": [0.0, y], "size": [w, 0.06],
		"min": BPM_RANGE[0], "max": BPM_RANGE[1], "step": 5.0, "value": game["bpm"], "action": {"cmd": "beatsaber_set", "bpm": "{value}"}})
	y -= 0.085
	var toggles := [["hit_sounds", "Hit sounds"], ["trails", "Trails"], ["menu_music", "Menu music"]]
	for i in toggles.size():
		var key: String = toggles[i][0]
		els.append({"type": "toggle", "id": key, "page": "Settings", "label": toggles[i][1], "at": [(i - 1) * w / 3.0, y], "size": [w / 3.0 - 0.015, 0.055],
			"on": game[key], "action": {"cmd": "beatsaber_set", key: "{on}"}})
	if _hands and is_instance_valid(_hands):
		y -= 0.085
		var style = _hands.get("settings").get("style") if typeof(_hands.get("settings")) == TYPE_DICTIONARY else ""
		els.append({"type": "text", "id": "style_label", "page": "Settings", "text": "Hands or sabers", "at": [0.0, y + 0.01], "width": w, "color": "muted"})
		y -= 0.055
		for i in 2:
			var v: String = ["hand", "saber"][i]
			els.append({"type": "button", "id": "style_" + v, "page": "Settings", "label": ["Hands", "Sabers"][i], "at": [(i - 0.5) * w / 2.0, y],
				"size": [w / 2.0 - 0.02, 0.055], "color": "accent" if style == v else "button", "action": {"cmd": "hands_style", "style": v}})
		y -= 0.075
		els.append({"type": "toggle", "id": "auto_sabers", "page": "Settings", "label": "Sabers in here, hands outside", "at": [0.0, y],
			"size": [w, 0.055], "on": game["auto_sabers"], "action": {"cmd": "beatsaber_set", "auto_sabers": "{on}"}})
	return els


# Packs: every "pack" named in a map.json, then All songs, then Free play.
func _packs() -> Array:
	var named := []
	for s in _songs():
		if not s["pack"].is_empty() and not s["pack"] in named:
			named.append(s["pack"])
	named.sort()
	var out: Array = named + [ALL_SONGS, FREE_PACK]
	if _net() != null:
		out.append(ONLINE_PACK)
	return out


func _net() -> SlopitectModule:
	return _lib.module("net") if _lib else null


func _main_elements() -> Array:
	var els := []
	var w := MAIN_SIZE.x
	var h := MAIN_SIZE.y
	var top := h / 2.0 - 0.06
	var bottom := -h / 2.0 + 0.04
	# Left half: the packs, then the songs in the chosen pack.
	var packs := _packs()
	if not _pack in packs:
		_pack = ALL_SONGS
	var pack_x := -w / 2.0 + 0.14
	els.append({"type": "text", "id": "packs_label", "text": "Packs", "at": [pack_x, top], "width": 0.24, "color": "muted"})
	for i in mini(packs.size(), ROWS):
		els.append({"type": "button", "id": "pack_%d" % i, "label": str(packs[i]).left(24), "at": [pack_x, top - 0.065 * (i + 1)], "size": [0.24, 0.055],
			"color": "accent" if packs[i] == _pack else "button", "action": {"cmd": "beatsaber_do", "act": "pack", "pack": packs[i]}})
	if _pack == ONLINE_PACK:
		els.append_array(_online_elements(top))
		_stop_leave(els, w / 4.0, bottom)
		return els
	var rows := []
	if _pack == FREE_PACK:
		rows.append({"id": "free", "label": "Free play (%d a minute)" % int(game["bpm"])})
	else:
		for s in _songs():
			if _pack == ALL_SONGS or s["pack"] == _pack:
				rows.append({"id": s["id"], "label": s["title"]})
	var song_x := -w / 2.0 + 0.45
	els.append({"type": "text", "id": "songs_label", "text": "Songs", "at": [song_x, top], "width": 0.34, "color": "muted"})
	var pages := maxi(1, ceili(rows.size() / float(ROWS)))
	_song_page = clampi(_song_page, 0, pages - 1)
	var y := top - 0.065
	for i in range(_song_page * ROWS, mini(rows.size(), (_song_page + 1) * ROWS)):
		els.append({"type": "button", "id": "song_%d" % i, "label": str(rows[i]["label"]).left(40), "at": [song_x, y], "size": [0.34, 0.055],
			"color": "accent" if rows[i]["id"] == _selected else "button", "action": {"cmd": "beatsaber_do", "act": "select", "song": rows[i]["id"]}})
		y -= 0.065
	if rows.is_empty():
		els.append({"type": "text", "id": "hint", "text": "No songs yet: add folders to Slopitect/songs", "at": [song_x, y], "width": 0.34, "color": "muted"})
	if pages > 1:
		els.append({"type": "button", "id": "prev", "label": "Back", "at": [song_x - 0.11, bottom + 0.07], "size": [0.12, 0.05],
			"action": {"cmd": "beatsaber_do", "act": "page", "page": _song_page - 1}})
		els.append({"type": "text", "id": "pages", "text": "%d / %d" % [_song_page + 1, pages], "at": [song_x, bottom + 0.07], "width": 0.1, "color": "muted"})
		els.append({"type": "button", "id": "next", "label": "More", "at": [song_x + 0.11, bottom + 0.07], "size": [0.12, 0.05],
			"action": {"cmd": "beatsaber_do", "act": "page", "page": _song_page + 1}})
	# Right half: the chosen song, its difficulty and mode, Play and Practice.
	var info := _selected_info()
	var right_x := w / 4.0
	var rw := w / 2.0 - 0.08
	var text_x := right_x
	var text_w := rw
	if not info["cover"].is_empty():
		els.append({"type": "button", "id": "cover", "label": "Play", "image": info["cover"], "at": [right_x - rw / 2.0 + 0.07, top - 0.035],
			"size": [0.14, 0.14], "color": "button", "action": {"cmd": "beatsaber_do", "act": "play"}})
		text_x = right_x + 0.08
		text_w = rw - 0.16
	els.append({"type": "text", "id": "song_title", "text": info["title"], "at": [text_x, top], "width": text_w, "font_size": 40, "color": "text"})
	els.append({"type": "text", "id": "song_info", "text": info["detail"], "at": [text_x, top - 0.07], "width": text_w, "color": "muted"})
	els.append({"type": "text", "id": "diff_label", "text": "Difficulty", "at": [right_x, top - 0.14], "width": rw, "color": "muted"})
	# Only the difficulties and modes the song has (all of them for made notes).
	var song := {} if _selected == "free" else _song_info(_selected)
	var diffs := _diffs_of(song, _mode)
	var dw := rw / float(maxi(diffs.size(), 3))
	for i in diffs.size():
		var d: String = diffs[i]
		els.append({"type": "button", "id": "diff_" + d, "label": DIFF_LABELS[d], "at": [right_x - rw / 2.0 + dw * (i + 0.5), top - 0.2],
			"size": [dw - 0.01, 0.055], "color": "accent" if game["difficulty"] == d else "button", "action": {"cmd": "beatsaber_set", "difficulty": d}})
	var modes := _modes_of(song)
	if modes.size() == 1:
		els.append({"type": "text", "id": "mode", "text": "Mode: " + MODE_LABELS[modes[0]], "at": [right_x, top - 0.27], "width": rw, "color": "muted"})
	else:
		var mw := rw / float(modes.size())
		for i in modes.size():
			var m: String = modes[i]
			els.append({"type": "button", "id": "mode_" + m, "label": MODE_LABELS[m], "at": [right_x - rw / 2.0 + mw * (i + 0.5), top - 0.27],
				"size": [mw - 0.01, 0.055], "color": "accent" if _mode == m else "button", "action": {"cmd": "beatsaber_do", "act": "mode", "mode": m}})
	els.append({"type": "button", "id": "play", "label": "Play", "at": [right_x - rw / 4.0, top - 0.35], "size": [rw / 2.0 - 0.02, 0.07],
		"color": "ok", "action": {"cmd": "beatsaber_do", "act": "play"}})
	els.append({"type": "button", "id": "practice", "label": "Practice", "at": [right_x + rw / 4.0, top - 0.35], "size": [rw / 2.0 - 0.02, 0.07],
		"color": "button", "action": {"cmd": "beatsaber_do", "act": "practice"}})
	els.append({"type": "text", "id": "status", "text": _status_text(), "at": [right_x, top - 0.43], "width": rw, "color": "text"})
	_stop_leave(els, right_x, bottom)
	return els


func _stop_leave(els: Array, right_x: float, bottom: float) -> void:
	var leave := _projects() != null
	els.append({"type": "button", "id": "stop", "label": "Stop", "at": [right_x - (0.11 if leave else 0.0), bottom], "size": [0.2, 0.05],
		"color": "notice" if running else "button", "action": {"cmd": "beatsaber_stop"}})
	if leave:
		els.append({"type": "button", "id": "leave", "label": "Leave", "at": [right_x + 0.11, bottom], "size": [0.2, 0.05],
			"color": "button", "action": {"cmd": "beatsaber_leave"}})


# --- Online songs (BeatSaver) ---------------------------------------------------------
# The Online pack: a search box (typed with the chat window's keyboard),
# Latest and Top rated, a page of results, and on the right the chosen
# one's details and Download. A download is the song's zip, unpacked into
# songs/bsv_KEY (only the song files: maps, music, cover), which then shows
# in Custom songs, chosen and ready to play. All through net.gd, so only
# from the hosts allowed on the PC (net_config); without net.gd there's no
# Online pack.

func _online_elements(top: float) -> Array:
	var els := []
	var w := MAIN_SIZE.x
	var song_x := -w / 2.0 + 0.45
	els.append({"type": "input", "id": "online_input", "at": [song_x, top], "width": 0.34, "prompt": "search: ", "max_length": 40})
	var acts := [["online_search", "Search", {"cmd": "beatsaber_do", "act": "online", "list": "search", "query": "{input:online_input}"}],
		["online_latest", "Latest", {"cmd": "beatsaber_do", "act": "online", "list": "latest"}],
		["online_top", "Top", {"cmd": "beatsaber_do", "act": "online", "list": "top"}],
		["online_keys", "Keys", {"cmd": "ui_show", "id_panel": "chat", "visible": true}]]
	for i in acts.size():
		els.append({"type": "button", "id": acts[i][0], "label": acts[i][1], "at": [song_x - 0.1275 + i * 0.085, top - 0.065], "size": [0.08, 0.05],
			"color": "ok" if i == 0 else "button", "action": acts[i][2]})
	var pages := maxi(1, ceili(_online.size() / float(ONLINE_ROWS)))
	_online_page = clampi(_online_page, 0, pages - 1)
	var y := top - 0.135
	for i in range(_online_page * ONLINE_ROWS, mini(_online.size(), (_online_page + 1) * ONLINE_ROWS)):
		var o: Dictionary = _online[i]
		els.append({"type": "button", "id": "online_%d" % i, "label": str(o["title"]).left(40), "at": [song_x, y], "size": [0.34, 0.055],
			"color": "accent" if o["key"] == _online_pick else "button", "action": {"cmd": "beatsaber_do", "act": "online_pick", "key": o["key"]}})
		y -= 0.065
	if pages > 1:
		var bottom := -MAIN_SIZE.y / 2.0 + 0.04
		els.append({"type": "button", "id": "online_prev", "label": "Back", "at": [song_x - 0.11, bottom + 0.07], "size": [0.12, 0.05],
			"action": {"cmd": "beatsaber_do", "act": "online_page", "page": _online_page - 1}})
		els.append({"type": "text", "id": "online_pages", "text": "%d / %d" % [_online_page + 1, pages], "at": [song_x, bottom + 0.07], "width": 0.1, "color": "muted"})
		els.append({"type": "button", "id": "online_next", "label": "More", "at": [song_x + 0.11, bottom + 0.07], "size": [0.12, 0.05],
			"action": {"cmd": "beatsaber_do", "act": "online_page", "page": _online_page + 1}})
	# Right half: the chosen result, and Download (or Play once it's here).
	var right_x := w / 4.0
	var rw := w / 2.0 - 0.08
	var o := _online_item(_online_pick)
	if o.is_empty():
		els.append({"type": "text", "id": "song_title", "text": "Online songs", "at": [right_x, top], "width": rw, "font_size": 40, "color": "text"})
		els.append({"type": "text", "id": "song_info", "text": "Community song folders from BeatSaver. Choose one on the left to see it here.",
			"at": [right_x, top - 0.07], "width": rw, "color": "muted"})
	else:
		els.append({"type": "text", "id": "song_title", "text": o["title"], "at": [right_x, top], "width": rw, "font_size": 40, "color": "text"})
		var detail := "%s, %d beats a minute, %d:%02d" % [o["artist"] if not o["artist"].is_empty() else "?", int(o["bpm"]), int(o["seconds"]) / 60, int(o["seconds"]) % 60]
		if not o["mapper"].is_empty():
			detail += ", mapped by " + o["mapper"]
		els.append({"type": "text", "id": "song_info", "text": detail, "at": [right_x, top - 0.07], "width": rw, "color": "muted"})
		els.append({"type": "text", "id": "online_levels", "text": o["levels"], "at": [right_x, top - 0.16], "width": rw, "color": "muted"})
		var here := DirAccess.dir_exists_absolute(_songs_folder() + "/" + _online_folder(o["key"]))
		els.append({"type": "button", "id": "online_get", "label": "Play" if here else "Download", "at": [right_x, top - 0.27], "size": [rw / 2.0, 0.07],
			"color": "ok", "action": {"cmd": "beatsaber_do", "act": "online_get", "key": o["key"]}})
	els.append({"type": "text", "id": "status", "text": _online_note, "at": [right_x, top - 0.37], "width": rw, "color": "text"})
	return els


func _online_item(key: String) -> Dictionary:
	for o in _online:
		if o["key"] == key:
			return o
	return {}


# A BeatSaver key is hex; its folder is bsv_KEY.
func _online_key_ok(key) -> bool:
	return typeof(key) == TYPE_STRING and not key.is_empty() and key.length() <= 12 and key.is_valid_hex_number()


func _online_folder(key: String) -> String:
	return "bsv_" + key.to_lower()


func _online_scratch() -> String:
	return _lib.call("home") + "/downloads/beatsaver" if _lib else ""


func _online_refused(problem: String) -> String:
	if problem.begins_with("refused"):
		return "BeatSaver isn't an allowed site yet. On the PC, add its hosts with net_config: %s." % ", ".join(ONLINE_HOSTS)
	return problem


# Gets a list from BeatSaver (search, latest or top rated) into _online.
func _online_list(which: String, query: String) -> void:
	var net := _net()
	if net == null:
		return
	_online_busy = true
	_online_note = "Looking on BeatSaver..."
	_build()
	var url := "%s/search/text/0?sortOrder=%s" % [ONLINE_API, ONLINE_SORTS[which]]
	if not query.is_empty():
		url += "&q=" + query.uri_encode()
	DirAccess.make_dir_recursive_absolute(_online_scratch())
	var path := _online_scratch() + "/list.json"
	var problem: String = await net.call("fetch", url, path, ONLINE_LIST_BYTES)
	if not is_inside_tree():
		return
	_online_busy = false
	if not problem.is_empty():
		_online_note = _online_refused(problem)
		_build()
		return
	var got = _lib.call("read_json", path) if _lib else null
	DirAccess.remove_absolute(path)
	_online = _online_parse(got)
	_online_page = 0
	_online_pick = ""
	_online_note = "%d songs. Choose one to see it." % _online.size() if not _online.is_empty() else "Nothing found."
	_build()


# BeatSaver's answer ({"docs": [...]}) as our short entries; ones without a
# download are left out.
func _online_parse(got) -> Array:
	var out := []
	if typeof(got) != TYPE_DICTIONARY or typeof(got.get("docs")) != TYPE_ARRAY:
		return out
	for d in got["docs"]:
		if typeof(d) != TYPE_DICTIONARY or not _online_key_ok(d.get("id")) or typeof(d.get("versions")) != TYPE_ARRAY or d["versions"].is_empty():
			continue
		var v = d["versions"][0]
		var meta = d.get("metadata", {})
		if typeof(v) != TYPE_DICTIONARY or typeof(v.get("downloadURL")) != TYPE_STRING or typeof(meta) != TYPE_DICTIONARY:
			continue
		var levels := []
		for diff in v.get("diffs", []) if typeof(v.get("diffs")) == TYPE_ARRAY else []:
			if typeof(diff) == TYPE_DICTIONARY and diff.get("characteristic") == "Standard" and diff.get("difficulty") in DAT_DIFFS:
				levels.append(DIFF_LABELS[DAT_DIFFS[diff["difficulty"]]])
		out.append({"key": str(d["id"]).to_lower(), "title": _text(meta.get("songName"), _text(d.get("name"), d["id"], 60), 60),
			"artist": _text(meta.get("songAuthorName"), "", 40), "mapper": _text(meta.get("levelAuthorName"), "", 40),
			"bpm": float(meta.get("bpm", 0.0)) if _number(meta.get("bpm")) else 0.0,
			"seconds": float(meta.get("duration", 0.0)) if _number(meta.get("duration")) else 0.0,
			"levels": ("Levels: " + ", ".join(levels)) if not levels.is_empty() else "", "url": v["downloadURL"]})
	return out


# Downloads a result's zip and unpacks it into songs/bsv_KEY, then chooses it.
func _online_download(key: String) -> void:
	var net := _net()
	var o := _online_item(key)
	if net == null or o.is_empty():
		return
	_online_busy = true
	_online_note = "Downloading %s..." % o["title"]
	_build()
	DirAccess.make_dir_recursive_absolute(_online_scratch())
	var zip := "%s/%s.zip" % [_online_scratch(), key]
	var problem: String = await net.call("fetch", o["url"], zip, ONLINE_ZIP_BYTES)
	if not is_inside_tree():
		return
	_online_busy = false
	if problem.is_empty():
		problem = _unpack_song(zip, _songs_folder() + "/" + _online_folder(key))
	DirAccess.remove_absolute(zip)
	if not problem.is_empty():
		_online_note = _online_refused(problem)
		_build()
		return
	_rescan()
	_online_note = "Downloaded. It's in Custom songs."
	_pack = DAT_PACK
	_selected = _online_folder(key)
	_fit_choice()
	_build()


# Unpacks a song zip into folder: only plain song files (maps, music,
# cover), any folder inside the zip flattened, within a size limit. It goes
# into FOLDER.part and is renamed only once whole and readable as a song.
func _unpack_song(zip_path: String, folder: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "the download isn't a zip"
	var part := folder + ".part"
	_remove_dir(part)
	DirAccess.make_dir_recursive_absolute(part)
	var total := 0
	var kept := 0
	var problem := ""
	for inside in zip.get_files():
		var file_name: String = inside.get_file()
		if inside.ends_with("/") or not _file_name_ok(file_name) or not file_name.get_extension().to_lower() in ONLINE_FILES \
				or FileAccess.file_exists(part + "/" + file_name):
			continue
		var bytes := zip.read_file(inside)
		total += bytes.size()
		if total > ONLINE_UNPACKED_BYTES:
			problem = "the song is bigger than %d MB unpacked" % (ONLINE_UNPACKED_BYTES / 1048576)
			break
		var out := FileAccess.open(part + "/" + file_name, FileAccess.WRITE)
		if out == null:
			problem = "couldn't write %s" % file_name
			break
		out.store_buffer(bytes)
		out.close()
		kept += 1
	zip.close()
	if problem.is_empty() and kept == 0:
		problem = "the zip had no song files"
	if problem.is_empty():
		_remove_dir(folder)
		if DirAccess.rename_absolute(part, folder) != OK:
			problem = "couldn't move the song into %s" % folder
		elif _song_info(folder.get_file()).is_empty():
			problem = "the download isn't a song we can play (it needs an Info.dat with a Standard, One saber or No arrows chart)"
			_remove_dir(folder)
	_remove_dir(part)
	return problem


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + file)
	DirAccess.remove_absolute(path)


# The chosen song's title and a line about it, for the middle window.
func _selected_info() -> Dictionary:
	if _selected == "free":
		return {"title": "Free play", "detail": "Notes at %d beats a minute, no music" % int(game["bpm"]), "cover": ""}
	for s in _songs():
		if s["id"] == _selected:
			var detail := "%d beats a minute" % int(s["bpm"])
			if not s["artist"].is_empty():
				detail = s["artist"] + ", " + detail
			if not s["mapper"].is_empty():
				detail += ", mapped by " + s["mapper"]
			if s["made"]:
				detail += ", notes made for it"
			return {"title": s["title"], "detail": detail, "cover": s["cover"]}
	_selected = "free"
	return _selected_info()


func _scores_elements() -> Array:
	var els := []
	var top := SCORES_SIZE.y / 2.0 - 0.06
	var w := SCORES_SIZE.x - 0.06
	var list: Array = scores.get(_score_key(_selected, game["difficulty"], _mode), [])
	var head := "%s, %s" % [_selected_info()["title"], DIFF_LABELS[game["difficulty"]]]
	if _mode != "Standard":
		head += ", " + MODE_LABELS[_mode]
	els.append({"type": "text", "id": "local_head", "page": "Local", "text": head,
		"at": [0.0, top], "width": w, "color": "muted"})
	if list.is_empty():
		els.append({"type": "text", "id": "local_none", "page": "Local", "text": "No scores yet. Play it!", "at": [0.0, top - 0.06], "width": w, "color": "muted"})
	for i in list.size():
		var e: Dictionary = list[i]
		els.append({"type": "text", "id": "local_%d" % i, "page": "Local", "mono": true, "color": "text", "at": [0.0, top - 0.06 - i * 0.042], "width": w,
			"text": "%2d. %8d  %s  %3d%%  %s" % [i + 1, int(e["score"]), e["rank"], int(e["accuracy"]), str(e.get("date", ""))]})
	els.append({"type": "text", "id": "global_none", "page": "Global", "text": "Global scores need an online score service, and there isn't one set up.",
		"at": [0.0, top], "width": w, "color": "muted"})
	return els


# "song|difficulty", with "|mode" added for modes other than Standard.
func _score_key(song: String, difficulty: String, mode := "Standard") -> String:
	var key := "%s|%s" % ["free play" if song == "free" else song, difficulty]
	return key if mode == "Standard" else key + "|" + mode


# After a song: the windows come back where they were, with the results.
func _bring_back() -> void:
	if not _has_ui() or not in_world() or not _run({"cmd": "ui_get", "id_panel": PANEL}).get("ok", false):
		return
	_build("Local")
	for id_panel in PANELS:
		_run({"cmd": "ui_show", "id_panel": id_panel, "visible": true})
	_sign_shown(true)
	_menu_music()


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
			return {"ok": false, "error": "\"difficulty\" must be one of %s" % [DIFFICULTIES]}
		game["difficulty"] = request["difficulty"]
	if request.has("mode"):
		if not request["mode"] in MODES:
			return {"ok": false, "error": "\"mode\" must be one of %s" % [MODES]}
		_mode = request["mode"]
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
		_mode = "Standard"
		song = {"id": "free play", "title": "Free play", "bpm": bpm, "offset": 0.0, "audio": null, "mode": "Standard",
			"notes": _generate(bpm, FREE_BEATS, game["difficulty"], 1)}
	else:
		if typeof(which) != TYPE_STRING:
			return {"ok": false, "error": "\"song\" must be a folder name in songs/ or \"free\""}
		if _song_dir_ok(which):
			_selected = which
			_fit_choice()
		var loaded := _load_song(which)
		if loaded.has("error"):
			return {"ok": false, "error": loaded["error"]}
		song = loaded
	_selected = "free" if song["id"] == "free play" else song["id"]
	if running:
		_clear()
	_begin(song)
	return {"ok": true, "song": song["title"], "notes": song["notes"].size(), "bpm": song["bpm"], "difficulty": game["difficulty"], "mode": song["mode"]}


func _stop(_request: Dictionary) -> Dictionary:
	var was := running
	_clear()
	_track.visible = false
	set_process(false)
	if was:
		stopped.emit()
		_bring_back()
		if _projects() == null:
			_hands_back()
	return {"ok": true}


func _score(_request: Dictionary) -> Dictionary:
	var out := {"ok": true, "running": running, "song": _song.get("title", ""), "score": score, "combo": combo, "max_combo": max_combo,
		"multiplier": _multiplier(), "cuts": cuts, "misses": missed, "bad_cuts": bad, "bombs_hit": bombs_hit, "walls_hit": bumped,
		"accuracy": snappedf(_accuracy(), 0.1), "average": int(round(_acc * 100.0 / cuts)) if cuts > 0 else 0}
	out.merge(_last)
	if not _results.is_empty():
		out["results"] = _results
	return out


func _songs_command(_request: Dictionary) -> Dictionary:
	_rescan()
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
					return {"ok": false, "error": "\"difficulty\" must be one of %s" % [DIFFICULTIES]}
				changed[key] = v
			"speed", "bpm":
				var r: Array = SPEED_RANGE if key == "speed" else BPM_RANGE
				if typeof(v) == TYPE_STRING and v.is_valid_float():
					v = v.to_float()
				if not _number(v) or v < r[0] or v > r[1]:
					return {"ok": false, "error": "\"%s\" must be %d to %d" % [key, r[0], r[1]]}
				changed[key] = float(v)
			"hit_sounds", "trails", "auto_sabers", "menu_music":
				if typeof(v) == TYPE_STRING:
					v = v == "true"
				if typeof(v) != TYPE_BOOL:
					return {"ok": false, "error": "\"%s\" must be true or false" % key}
				changed[key] = v
			_:
				return {"ok": false, "error": "unknown setting \"%s\" (one of: difficulty, speed, bpm, hit_sounds, trails, auto_sabers, menu_music)" % key}
	game = changed
	_menu_music()
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
	_hide_windows()
	_placed = false
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
		_sabers_on()
		_stage_on()
		_show_windows.call_deferred()
	else:
		if running:
			_stop({})
		_hide_windows()
		_hands_back()
		_stage_off()


# --- The Rhythm world's surroundings -----------------------------------------------
# In the Rhythm world the main scene's sky, sun and floor give way to a
# stage of our own: a deep blue night with a light haze and stars, a dim
# sun, a dark ground and runway, the lanes edged in the two note colours,
# glowing frames down the track, and the game's name in light over the
# windows (shown with them, hidden while you play).
# Everything it changed goes back when you leave or the module unloads.
# Glowing (emissive) materials, no screen-wide glow, and one draw per
# colour (MultiMesh), to stay light on the Quest 1.

const STAGE_SKY := Color(0.015, 0.03, 0.1)
const STAGE_AMBIENT := Color(0.3, 0.34, 0.5)
const STAGE_HAZE := Color(0.06, 0.12, 0.3)
const STAGE_HAZE_DENSITY := 0.035  # light fog: the track fades into blue far off
const STAGE_STARS := 260
const STAGE_SUN := 0.35          # the sun's energy while the stage is up
const STAGE_FRAMES := 6          # glowing frames down the track
const STAGE_FRAME_GAP := 3.5     # metres between them


func _stage_on() -> void:
	if _stage != null:
		return
	var scene := ctx["world"].get_parent() as Node if ctx.get("world") else null
	if scene:
		var env := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if env:
			_swapped["environment"] = [env, env.environment]
			var night := Environment.new()
			night.background_mode = Environment.BG_COLOR
			night.background_color = STAGE_SKY
			night.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			night.ambient_light_color = STAGE_AMBIENT
			night.fog_enabled = true
			night.fog_light_color = STAGE_HAZE
			night.fog_density = STAGE_HAZE_DENSITY
			night.fog_sky_affect = 0.0
			env.environment = night
		var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
		if sun:
			_swapped["sun"] = [sun, sun.light_energy]
			sun.light_energy = STAGE_SUN
		var ground := scene.get_node_or_null("Floor") as Node3D
		if ground:
			_swapped["floor"] = [ground, ground.visible]
			ground.visible = false
	_stage = Node3D.new()
	_stage.name = "stage"
	add_child(_stage)
	_stage.global_transform = _track.global_transform
	var dark := _flat(Color(0.04, 0.06, 0.13))
	var runway := _flat(Color(0.07, 0.09, 0.16))
	var length := -SPAWN_Z + 4.0
	_stage_box(Vector3(240.0, 0.02, 240.0), Vector3(0.0, -0.03, 0.0), dark)  # the ground, faded out by the haze
	_stage_box(Vector3(LANE_W * 4.0 + 0.5, 0.02, length), Vector3(0.0, -0.015, 2.0 - length / 2.0), runway)
	_stage_box(Vector3(2.4, 0.02, 2.4), Vector3(0.0, -0.01, 0.0), runway)  # where you stand
	# The lanes' edges: blue on the left, red on the right.
	for side in [-1, 1]:
		_stage_box(Vector3(0.04, 0.02, length), Vector3(side * (LANE_W * 2.0 + 0.25), 0.0, 2.0 - length / 2.0), _mat["l" if side < 0 else "r"])
	# Frames over the track: two posts and a bar each, in one MultiMesh.
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var frames := MultiMesh.new()
	frames.transform_format = MultiMesh.TRANSFORM_3D
	frames.mesh = unit
	frames.instance_count = STAGE_FRAMES * 3
	for i in STAGE_FRAMES:
		var z := HIT_Z - 5.0 - i * STAGE_FRAME_GAP
		frames.set_instance_transform(i * 3, Transform3D(Basis.from_scale(Vector3(0.06, 3.2, 0.06)), Vector3(-2.2, 1.6, z)))
		frames.set_instance_transform(i * 3 + 1, Transform3D(Basis.from_scale(Vector3(0.06, 3.2, 0.06)), Vector3(2.2, 1.6, z)))
		frames.set_instance_transform(i * 3 + 2, Transform3D(Basis.from_scale(Vector3(4.46, 0.06, 0.06)), Vector3(0.0, 3.2, z)))
	var frame_node := MultiMeshInstance3D.new()
	frame_node.multimesh = frames
	frame_node.material_override = _glow(Color(0.55, 0.7, 1.0))
	frame_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(frame_node)
	_stage.add_child(_stars())
	_sign = _make_sign()
	_stage.add_child(_sign)
	_sign.visible = _shown(PANEL)


# Stars on a dome above the horizon, one draw: small quads that face you,
# not in the fog. A fixed seed, so the sky is the same every visit.
func _stars() -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	var stars := MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	stars.mesh = quad
	stars.instance_count = STAGE_STARS
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in STAGE_STARS:
		var up := rng.randf_range(0.08, 1.0)  # height on the dome, 0 = horizon
		var around := rng.randf() * TAU
		var flat := sqrt(1.0 - up * up)
		var at := Vector3(cos(around) * flat, up, sin(around) * flat) * 70.0
		stars.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.5, 1.6)), at))
	var star := _flat(Color(0.85, 0.9, 1.0))
	star.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star.billboard_keep_scale = true
	star.disable_fog = true
	var node := MultiMeshInstance3D.new()
	node.multimesh = stars
	node.material_override = star
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


# The game's name in light over the middle window: RHYTHM in red over
# SABERS in blue, each with a soft outline of its own colour.
func _make_sign() -> Node3D:
	var sign := Node3D.new()
	sign.name = "sign"
	sign.position = Vector3(0.0, 2.25, -1.5)
	for i in 2:
		var word := Label3D.new()
		word.text = ["RHYTHM", "SABERS"][i]
		var c: Color = [Color(1.0, 0.25, 0.3), Color(0.35, 0.6, 1.0)][i]
		word.modulate = c.lightened(0.35)
		word.outline_modulate = Color(c, 0.55)
		word.font_size = 160
		word.outline_size = 28
		word.pixel_size = 0.0022
		word.position = Vector3(0.0, 0.2 - i * 0.36, 0.0)
		word.shaded = false
		word.fixed_size = false
		word.no_depth_test = false
		sign.add_child(word)
	return sign


# --- Menu music --------------------------------------------------------------------------
# While the windows are open in the Rhythm world (and no song plays): the
# chosen song's preview, over and over, or for Free play and songs without
# music a calm loop made here. Off with the Settings tab's Menu music.

func _menu_music() -> void:
	if not game["menu_music"] or running or not in_world() or not _shown(PANEL):
		_menu_stop()
		return
	var want := "calm"
	var info := {} if _selected == "free" else _song_info(_selected)
	if not info.is_empty() and not str(info.get("audio", "")).is_empty():
		want = _selected
	if want == _menu_for and _menu_player.playing:
		return
	var stream: AudioStream = null
	var from := 0.0
	var length := 0.0
	if want != "calm":
		stream = _load_audio(info["audio"])
		if stream != null:
			var preview: Array = info.get("preview", [-1.0, MENU_PREVIEW])
			var whole := stream.get_length()
			from = preview[0] if preview[0] >= 0.0 else whole * 0.3
			from = clampf(from, 0.0, maxf(whole - 2.0, 0.0))
			length = minf(preview[1], maxf(whole - from, 1.0))
	if stream == null:
		want = "calm"
		if _calm == null:
			_menu_stop()  # still being made; it starts when ready (_calm_made)
			return
		stream = _calm
	_menu_for = want
	_menu_from = from
	_menu_player.stream = stream
	_menu_player.volume_db = -40.0
	_menu_player.play(from)
	create_tween().tween_property(_menu_player, "volume_db", MENU_DB, MENU_FADE)
	_menu_loop.stop()
	if length > 0.0:
		_menu_loop.start(length)


func _menu_again() -> void:
	if _menu_player.playing and _menu_for != "calm":
		_menu_player.volume_db = -40.0
		_menu_player.play(_menu_from)
		create_tween().tween_property(_menu_player, "volume_db", MENU_DB, MENU_FADE)
		_menu_loop.start(_menu_loop.wait_time)


func _menu_stop() -> void:
	if _menu_player:
		_menu_player.stop()
	if _menu_loop:
		_menu_loop.stop()
	_menu_for = ""


func _make_calm() -> void:
	var made := _calm_loop()
	_calm_made.call_deferred(made)


func _calm_made(made: AudioStreamWAV) -> void:
	_calm = made
	_menu_music()


# The calm loop: eight seconds, two soft chords (pads of detuned sines with
# a slow swell) over a low note, looping cleanly; made once.
func _calm_loop() -> AudioStreamWAV:
	var rate := 16000
	var seconds := 8.0
	var count := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var chords := [[220.0, 261.63, 329.63, 392.0], [196.0, 246.94, 293.66, 369.99]]  # A minor 7, G major 7
	var bass := [110.0, 98.0]
	for i in count:
		var t := float(i) / rate
		var half := int(t / (seconds / 2.0))
		var local := fmod(t, seconds / 2.0) / (seconds / 2.0)
		var swell := sin(PI * local)  # each chord swells in and out, so the joins are silent
		var v := 0.0
		for f in chords[half]:
			v += sin(TAU * f * t) + 0.5 * sin(TAU * f * 1.004 * t)
		v = v / 6.0 * swell * swell
		v += 0.35 * sin(TAU * bass[half] * t) * swell
		data.encode_s16(i * 2, int(clampf(v * 0.5, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = count
	return s


func _sign_shown(on: bool) -> void:
	if _sign != null and is_instance_valid(_sign):
		_sign.visible = on


func _stage_box(size: Vector3, at: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var m := MeshInstance3D.new()
	m.mesh = box
	m.material_override = material
	m.position = at
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(m)


func _stage_off() -> void:
	if _swapped.has("environment") and is_instance_valid(_swapped["environment"][0]):
		_swapped["environment"][0].environment = _swapped["environment"][1]
	if _swapped.has("sun") and is_instance_valid(_swapped["sun"][0]):
		_swapped["sun"][0].light_energy = _swapped["sun"][1]
	if _swapped.has("floor") and is_instance_valid(_swapped["floor"][0]):
		_swapped["floor"][0].visible = _swapped["floor"][1]
	_swapped.clear()
	if _stage != null and is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null
	_sign = null


# Auto sabers: in the game you hold sabers; back out, the hands module's
# style goes back to what it was (kept across a restart). Without
# projects.gd, that's while a song plays.
func _sabers_on() -> void:
	if not game["auto_sabers"] or _hands == null or not is_instance_valid(_hands):
		return
	var style = _hands.get("settings").get("style") if typeof(_hands.get("settings")) == TYPE_DICTIONARY else null
	if style == null or style == "saber":
		return
	_hands_before = style
	_run({"cmd": "hands_style", "style": "saber"})
	_save_settings()


func _hands_back() -> void:
	if _hands_before.is_empty():
		return
	if _hands and is_instance_valid(_hands):
		_run({"cmd": "hands_style", "style": _hands_before})
	_hands_before = ""
	_save_settings()


# --- Songs and maps ------------------------------------------------------------------

func _songs_folder() -> String:
	return _lib.call("home") + "/songs" if _lib else ""


# Every song folder we can play, as _song_info() describes it, by folder
# name. Kept between window redraws; the folder is read again when the
# windows open, on Refresh, and for beatsaber_songs (_rescan).
func _songs() -> Array:
	if _song_cache != null:
		return _song_cache
	var out := []
	var folder := _songs_folder()
	if not folder.is_empty() and DirAccess.dir_exists_absolute(folder):
		var names := DirAccess.get_directories_at(folder)
		names.sort()
		for dir_name in names:
			var info := _song_info(dir_name)
			if not info.is_empty():
				out.append(info)
	_song_cache = out
	return out


func _rescan() -> void:
	_song_cache = null


func _song_dir_ok(dir_name) -> bool:
	return typeof(dir_name) == TYPE_STRING and not dir_name.is_empty() and not "/" in dir_name and not "\\" in dir_name \
		and not dir_name.begins_with(".")


# What a song folder holds, or {} when it isn't one:
#   {"id", "title", "artist", "mapper", "pack", "bpm", "offset", "audio"
#    (a path or ""), "cover", "made" (notes are made for it), "format"
#    ("slopitect" or "dat"), "charts": {mode: {difficulty: file}}}
# Our own map.json, or a custom song folder's Info.dat (versions 2 and 4).
func _song_info(dir_name: String) -> Dictionary:
	if _lib == null or not _song_dir_ok(dir_name):
		return {}
	var folder := _songs_folder() + "/" + dir_name
	var map = _lib.call("read_json", folder + "/map.json")
	if typeof(map) == TYPE_DICTIONARY and _number(map.get("bpm")):
		var notes = map.get("notes")
		var made: bool = typeof(notes) != TYPE_ARRAY or notes.is_empty()
		var audio := ""
		var named = map.get("audio")
		if typeof(named) == TYPE_STRING and not named.is_empty() and _file_name_ok(named):
			audio = folder + "/" + named
		else:
			for ext in ["ogg", "egg", "mp3", "wav"]:
				if FileAccess.file_exists(folder + "/song." + ext):
					audio = folder + "/song." + ext
					break
		return {"id": dir_name, "title": _text(map.get("title"), dir_name, 60), "artist": _text(map.get("artist"), "", 40), "mapper": "",
			"pack": _text(map.get("pack"), "", 24), "bpm": float(map["bpm"]), "offset": float(map.get("offset", 0.0)) if _number(map.get("offset", 0.0)) else 0.0,
			"audio": audio, "cover": _cover(folder, ""), "made": made, "format": "slopitect", "preview": _preview(map.get("preview_start"), map.get("preview_seconds")),
			"charts": {} if made else {"Standard": {"normal": "map.json"}}}
	var info = _lib.call("read_json", folder + "/Info.dat")
	if info == null:
		info = _lib.call("read_json", folder + "/info.dat")
	if typeof(info) != TYPE_DICTIONARY:
		return {}
	var charts := {}
	var out := {"id": dir_name, "pack": DAT_PACK, "made": false, "format": "dat", "offset": 0.0}
	if info.has("_beatsPerMinute"):  # version 2
		out["title"] = _text(info.get("_songName"), dir_name, 60)
		out["artist"] = _text(info.get("_songAuthorName"), "", 40)
		out["mapper"] = _text(info.get("_levelAuthorName"), "", 40)
		out["bpm"] = float(info["_beatsPerMinute"]) if _number(info["_beatsPerMinute"]) else 0.0
		out["offset"] = float(info.get("_songTimeOffset", 0.0)) if _number(info.get("_songTimeOffset", 0.0)) else 0.0
		out["audio"] = _named_file(folder, info.get("_songFilename"))
		out["cover"] = _cover(folder, info.get("_coverImageFilename"))
		out["preview"] = _preview(info.get("_previewStartTime"), info.get("_previewDuration"))
		for set in info.get("_difficultyBeatmapSets", []) if typeof(info.get("_difficultyBeatmapSets")) == TYPE_ARRAY else []:
			if typeof(set) != TYPE_DICTIONARY or not set.get("_beatmapCharacteristicName") in MODES:
				continue
			for d in set.get("_difficultyBeatmaps", []) if typeof(set.get("_difficultyBeatmaps")) == TYPE_ARRAY else []:
				if typeof(d) == TYPE_DICTIONARY and d.get("_difficulty") in DAT_DIFFS and _file_name_ok(d.get("_beatmapFilename")):
					charts.get_or_add(set["_beatmapCharacteristicName"], {})[DAT_DIFFS[d["_difficulty"]]] = d["_beatmapFilename"]
	elif typeof(info.get("song")) == TYPE_DICTIONARY and typeof(info.get("audio")) == TYPE_DICTIONARY:  # version 4
		var song: Dictionary = info["song"]
		var audio: Dictionary = info["audio"]
		out["title"] = _text(song.get("title"), dir_name, 60)
		out["artist"] = _text(song.get("author"), "", 40)
		out["mapper"] = ""
		out["bpm"] = float(audio.get("bpm", 0.0)) if _number(audio.get("bpm")) else 0.0
		out["audio"] = _named_file(folder, audio.get("songFilename"))
		out["cover"] = _cover(folder, info.get("coverImageFilename"))
		out["preview"] = _preview(audio.get("previewStartTime"), audio.get("previewDuration"))
		for d in info.get("difficultyBeatmaps", []) if typeof(info.get("difficultyBeatmaps")) == TYPE_ARRAY else []:
			if typeof(d) == TYPE_DICTIONARY and d.get("characteristic") in MODES and d.get("difficulty") in DAT_DIFFS and _file_name_ok(d.get("beatmapDataFilename")):
				charts.get_or_add(d["characteristic"], {})[DAT_DIFFS[d["difficulty"]]] = d["beatmapDataFilename"]
				var mappers = d.get("beatmapAuthors", {}).get("mappers") if typeof(d.get("beatmapAuthors")) == TYPE_DICTIONARY else null
				if out["mapper"].is_empty() and typeof(mappers) == TYPE_ARRAY and not mappers.is_empty():
					out["mapper"] = _text(mappers[0], "", 40)
	else:
		return {}
	if out["bpm"] < 20.0 or out["bpm"] > 1000.0 or charts.is_empty():
		return {}
	out["charts"] = charts
	return out


# [start, seconds] of a song's preview for the menu music; without one, a
# stretch a little way in.
func _preview(start, seconds) -> Array:
	var from: float = float(start) if _number(start) and start >= 0.0 else -1.0
	var length: float = clampf(float(seconds), 4.0, 30.0) if _number(seconds) and seconds > 0.0 else MENU_PREVIEW
	return [from, length]


func _text(v, fallback: String, most: int) -> String:
	return str(v).strip_edges().left(most) if typeof(v) == TYPE_STRING and not v.strip_edges().is_empty() else fallback


# A plain file name (no folders in it).
func _file_name_ok(v) -> bool:
	return typeof(v) == TYPE_STRING and not v.is_empty() and not "/" in v and not "\\" in v and not ".." in v


func _named_file(folder: String, v) -> String:
	return folder + "/" + v if _file_name_ok(v) and FileAccess.file_exists(folder + "/" + v) else ""


# The song's album cover: the file its Info.dat names, or cover.png / .jpg /
# .webp in its folder; "" without one.
func _cover(folder: String, named) -> String:
	var path := _named_file(folder, named)
	if not path.is_empty() and path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
		return path
	for ext in ["png", "jpg", "jpeg", "webp"]:
		if FileAccess.file_exists(folder + "/cover." + ext):
			return folder + "/cover." + ext
	return ""


# The difficulties and modes a song can be played at.
func _modes_of(info: Dictionary) -> Array:
	if info.is_empty() or info["made"]:
		return ["Standard"]
	return MODES.filter(func(m): return info["charts"].has(m))


func _diffs_of(info: Dictionary, mode: String) -> Array:
	if info.is_empty() or info["made"]:
		return DIFFICULTIES.duplicate()
	var have: Dictionary = info["charts"].get(mode, {})
	return DIFFICULTIES.filter(func(d): return have.has(d))


# Keeps the mode and difficulty to ones the chosen song has: the nearest
# difficulty to the one you had.
func _fit_choice() -> void:
	var info := {} if _selected == "free" else _song_info(_selected)
	var modes := _modes_of(info)
	if not _mode in modes:
		_mode = modes[0]
	var diffs := _diffs_of(info, _mode)
	if diffs.is_empty() or game["difficulty"] in diffs:
		return
	var want := DIFFICULTIES.find(game["difficulty"])
	var best_d: String = diffs[0]
	for d in diffs:
		if absi(DIFFICULTIES.find(d) - want) < absi(DIFFICULTIES.find(best_d) - want):
			best_d = d
	game["difficulty"] = best_d


# A song ready to play at the chosen mode and difficulty, or {"error"}.
func _load_song(dir_name: String) -> Dictionary:
	if _lib == null:
		return {"error": "songs need the lib module"}
	if not _song_dir_ok(dir_name):
		return {"error": "\"song\" must be a folder name in songs/"}
	var info := _song_info(dir_name)
	if info.is_empty():
		return {"error": "%s isn't a song folder (it needs a map.json with bpm, or an Info.dat with a Standard, One saber or No arrows chart)" % dir_name}
	var folder := _songs_folder() + "/" + dir_name
	var stream: AudioStream = null
	if not info["audio"].is_empty():
		stream = _load_audio(info["audio"])
		if stream == null:
			return {"error": "couldn't read the music %s (ogg/egg, mp3 or wav)" % info["audio"]}
	elif info["format"] == "dat":
		return {"error": "the music file named in %s/Info.dat isn't there" % folder}
	var bpm: float = info["bpm"]
	var notes := []
	var walls := []
	var arcs := []
	if info["made"]:
		var length := stream.get_length() if stream else 60.0
		var beats := int((length - float(info["offset"])) * bpm / 60.0) - 2
		notes = _generate(bpm, maxi(beats, 8), game["difficulty"], dir_name.hash())
	elif info["format"] == "slopitect":
		var raw = _lib.call("read_json", folder + "/map.json").get("notes")
		for i in raw.size():
			var problem := _check_note(raw[i])
			if not problem.is_empty():
				return {"error": "map.json note %d %s" % [i, problem]}
			notes.append([float(raw[i][0]), int(raw[i][1]), int(raw[i][2]), raw[i][3], raw[i][4]])
	else:
		var file = info["charts"].get(_mode, {}).get(game["difficulty"])
		if file == null:
			return {"error": "%s has no %s %s chart" % [info["title"], MODE_LABELS.get(_mode, _mode), DIFF_LABELS[game["difficulty"]]]}
		var read := _read_dat(folder + "/" + file)
		if read.has("error"):
			return read
		notes = read["notes"]
		walls = read["walls"]
		arcs = read["arcs"]
	if _mode == "NoArrows":
		for n in notes:
			n[4] = "a"
	notes.sort_custom(func(a, b): return a[0] < b[0])
	walls.sort_custom(func(a, b): return a[0] < b[0])
	arcs.sort_custom(func(a, b): return a[0] < b[0])
	return {"id": dir_name, "title": info["title"], "bpm": bpm, "offset": info["offset"], "audio": stream, "notes": notes, "mode": _mode,
		"walls": walls, "arcs": arcs}


# The notes of a custom song's difficulty file, in our [beat, lane, row,
# hand, dir] form: version 2 (_notes), 3 (colorNotes, bombNotes) or 4
# (colorNotes / bombNotes pointing into colorNotesData / bombNotesData).
# Also its walls ([beat, beats long, lane, lanes wide, layer, layers high])
# and arcs ([head beat, lane, row, dir, tail beat, lane, row, dir, hand,
# head pull, tail pull]) from the same versions (and v2.6 _sliders).
# Chains and lights aren't played yet; notes outside the 4 x 3 grid are
# left out. Returns {"notes", "walls", "arcs", "skipped"} or {"error"}.
func _read_dat(path: String) -> Dictionary:
	var data = _lib.call("read_json", path)
	if typeof(data) != TYPE_DICTIONARY:
		return {"error": "couldn't read %s" % path}
	var notes := []
	var skipped := 0
	if typeof(data.get("_notes")) == TYPE_ARRAY:
		for n in data["_notes"]:
			if typeof(n) != TYPE_DICTIONARY:
				continue
			var t = n.get("_type")
			var hand := "l" if t == 0 else ("r" if t == 1 else ("b" if t == 3 else ""))
			if hand.is_empty():
				continue
			if not _add_dat_note(notes, n.get("_time"), n.get("_lineIndex"), n.get("_lineLayer"), hand, n.get("_cutDirection", 8)):
				skipped += 1
	elif typeof(data.get("colorNotes")) == TYPE_ARRAY:
		var note_data = data.get("colorNotesData")
		var bomb_data = data.get("bombNotesData")
		for n in data["colorNotes"]:
			if typeof(n) != TYPE_DICTIONARY:
				continue
			var d = n
			if typeof(note_data) == TYPE_ARRAY:  # version 4
				var i = n.get("i", 0)
				d = note_data[int(i)] if _number(i) and i >= 0 and i < note_data.size() and typeof(note_data[int(i)]) == TYPE_DICTIONARY else null
			if d == null or not _add_dat_note(notes, n.get("b"), d.get("x", 0), d.get("y", 0), "r" if d.get("c", 0) == 1 else "l", d.get("d", 8)):
				skipped += 1
		for n in data.get("bombNotes", []) if typeof(data.get("bombNotes")) == TYPE_ARRAY else []:
			if typeof(n) != TYPE_DICTIONARY:
				continue
			var d = n
			if typeof(bomb_data) == TYPE_ARRAY:
				var i = n.get("i", 0)
				d = bomb_data[int(i)] if _number(i) and i >= 0 and i < bomb_data.size() and typeof(bomb_data[int(i)]) == TYPE_DICTIONARY else null
			if d == null or not _add_dat_note(notes, n.get("b"), d.get("x", 0), d.get("y", 0), "b", 8):
				skipped += 1
	else:
		return {"error": "%s isn't a difficulty file we know (versions 2, 3 and 4)" % path}
	if notes.is_empty():
		return {"error": "%s has no notes we can play" % path}
	return {"notes": notes, "walls": _read_walls(data), "arcs": _read_arcs(data), "skipped": skipped}


func _list(data: Dictionary, key: String) -> Array:
	return data[key] if typeof(data.get(key)) == TYPE_ARRAY else []


# A list's entry, or its data entry when version 4 points into one with "i".
func _entry(n, list_data) -> Variant:
	if typeof(n) != TYPE_DICTIONARY:
		return null
	if typeof(list_data) != TYPE_ARRAY:
		return n
	var i = n.get("i", 0)
	return list_data[int(i)] if _number(i) and i >= 0 and i < list_data.size() and typeof(list_data[int(i)]) == TYPE_DICTIONARY else null


func _read_walls(data: Dictionary) -> Array:
	var out := []
	for o in _list(data, "_obstacles"):  # version 2: full height or crouch
		if typeof(o) == TYPE_DICTIONARY:
			var crouch: bool = o.get("_type", 0) == 1
			_add_wall(out, o.get("_time"), o.get("_duration"), o.get("_lineIndex"), o.get("_width"), 2 if crouch else 0, 3 if crouch else WALL_LAYERS)
	var data4 = data.get("obstaclesData")
	for o in _list(data, "obstacles"):  # versions 3 and 4
		var d = _entry(o, data4)
		if d != null:
			_add_wall(out, o.get("b"), d.get("d"), d.get("x"), d.get("w"), d.get("y", 0), d.get("h", WALL_LAYERS))
	return out


func _add_wall(out: Array, beat, beats, lane, lanes, layer, layers) -> void:
	for v in [beat, beats, lane, lanes, layer, layers]:
		if not _number(v):
			return
	if beat < 0 or beats <= 0 or lanes <= 0 or layers <= 0 or lane < -2 or lane + lanes > 6 or layer < 0 or layer > WALL_LAYERS:
		return  # mapping tricks (negative or huge walls) aren't played
	out.append([float(beat), float(beats), float(lane), float(lanes), float(layer), minf(float(layers), WALL_LAYERS - float(layer))])


func _read_arcs(data: Dictionary) -> Array:
	var out := []
	for a in _list(data, "_sliders"):  # version 2.6
		if typeof(a) == TYPE_DICTIONARY:
			_add_arc(out, a.get("_headTime"), a.get("_headLineIndex"), a.get("_headLineLayer"), a.get("_headCutDirection"),
				a.get("_tailTime"), a.get("_tailLineIndex"), a.get("_tailLineLayer"), a.get("_tailCutDirection"), a.get("_colorType"),
				a.get("_headControlPointLengthMultiplier", 1.0), a.get("_tailControlPointLengthMultiplier", 1.0))
	if typeof(data.get("arcsData")) == TYPE_ARRAY:  # version 4: head and tail are notes in colorNotesData
		var notes4 = data.get("colorNotesData")
		for a in _list(data, "arcs"):
			if typeof(a) != TYPE_DICTIONARY or typeof(notes4) != TYPE_ARRAY:
				continue
			var ad = _entry({"i": a.get("ai", 0)}, data["arcsData"])
			var h = _entry({"i": a.get("hi", 0)}, notes4)
			var t = _entry({"i": a.get("ti", 0)}, notes4)
			if ad != null and h != null and t != null:
				_add_arc(out, a.get("hb"), h.get("x"), h.get("y"), h.get("d", 8), a.get("tb"), t.get("x"), t.get("y"), t.get("d", 8), h.get("c", 0),
					ad.get("m", 1.0), ad.get("tm", 1.0))
	else:
		for a in _list(data, "sliders"):  # version 3
			if typeof(a) == TYPE_DICTIONARY:
				_add_arc(out, a.get("b"), a.get("x"), a.get("y"), a.get("d", 8), a.get("tb"), a.get("tx"), a.get("ty"), a.get("tc", 8), a.get("c", 0),
					a.get("mu", 1.0), a.get("tmu", 1.0))
	return out


func _add_arc(out: Array, hb, hx, hy, hd, tb, tx, ty, td, colour, mu, tmu) -> void:
	for v in [hb, hx, hy, hd, tb, tx, ty, td, colour, mu, tmu]:
		if not _number(v):
			return
	if hb < 0 or tb <= hb or hx < 0 or hx > 3 or tx < 0 or tx > 3 or hy < 0 or hy > 2 or ty < 0 or ty > 2:
		return
	out.append([float(hb), int(hx), int(hy), _dat_dir(hd), float(tb), int(tx), int(ty), _dat_dir(td), "r" if colour == 1 else "l",
		clampf(float(mu), 0.0, 3.0), clampf(float(tmu), 0.0, 3.0)])


func _dat_dir(cut) -> String:
	return DAT_DIRS[int(cut)] if int(cut) >= 0 and int(cut) < DAT_DIRS.size() else "a"


func _add_dat_note(notes: Array, beat, lane, row, hand: String, cut) -> bool:
	if not (_number(beat) and _number(lane) and _number(row) and _number(cut)) or beat < 0:
		return false
	if int(lane) != lane or int(row) != row or lane < 0 or lane > 3 or row < 0 or row > 2:
		return false
	var dir: String = DAT_DIRS[int(cut)] if int(cut) >= 0 and int(cut) < DAT_DIRS.size() else "a"
	notes.append([float(beat), int(lane), int(row), hand, "a" if hand == "b" else dir])
	return true


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
		"ogg", "egg":  # a custom song's .egg is Ogg Vorbis
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
	_next_wall = 0
	_next_arc = 0
	bumped = 0
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
	_clock = -maxf(LEAD_MIN, _lead() - first)
	_song_player.stream = song["audio"]
	if _projects() == null:
		_sabers_on()
	if not _placed:
		_place_track()
	_track.visible = true
	_blade.clear()
	running = true
	_update_board()
	set_process(true)
	started.emit(song["title"])
	_hide_windows()  # out of the way while you play


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
	if _stage != null:
		_stage.global_transform = _track.global_transform


# Where on the track the track's transform is (for beatsaber_path).
func track_transform() -> Transform3D:
	return _track.global_transform


func _clear() -> void:
	running = false
	_song_player.stop()
	_clear_extras()
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
# Where on the track something due in `left` seconds is. On the track it
# moves at the note speed; before that it flies in: it appears far down
# (FLY_FROM), rushes up and slows to the note speed just as it reaches the
# track's far end, like coming in from a long way off (isaac).
func _track_z(left: float) -> float:
	var speed: float = game["speed"]
	var on_track := _ahead()
	if left <= on_track:
		return HIT_Z - left * speed
	# A cubic from FLY_FROM to SPAWN_Z over FLY_TIME seconds: fast at first,
	# ending at the note speed, so there's no jolt where it joins the track.
	var s := clampf(1.0 - (left - on_track) / FLY_TIME, 0.0, 1.0)
	var p0 := SPAWN_Z + FLY_FROM
	var p1 := SPAWN_Z
	var m1 := speed * FLY_TIME
	var m0 := 3.0 * (p1 - p0) - 2.0 * m1  # with this start slope the ease never overshoots
	m0 = maxf(m0, 0.0)
	var s2 := s * s
	var s3 := s2 * s
	return (2.0 * s3 - 3.0 * s2 + 1.0) * p0 + (s3 - 2.0 * s2 + s) * m0 + (-2.0 * s3 + 3.0 * s2) * p1 + (s3 - s2) * m1


# Seconds before its beat that something comes into view (it flies in first).
func _lead() -> float:
	return _ahead() + FLY_TIME


func _ahead() -> float:
	return (HIT_Z - SPAWN_Z) / float(game["speed"])


func _on_music_done() -> void:
	_music_done = true


func _process(delta: float) -> void:
	if running:
		_tick_clock(delta)
		_spawn_due()
		_spawn_extras()
		_update_blades(delta)
		_move_and_cut(delta)
		_move_extras()
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
	var ahead := _lead()
	while _next < notes.size() and _beat_time(notes[_next][0]) - _clock <= ahead:
		_spawn(notes[_next])
		_next += 1


func _note_pos(n: Array) -> Vector3:
	return Vector3((float(n[1]) - 1.5) * LANE_W, _row_heights()[int(n[2])], 0.0)


# The three note rows' heights, set by how tall you stand.
func _row_heights() -> Array:
	var head := 1.6
	var cam: Node3D = ctx.get("camera")
	if cam and is_instance_valid(cam):
		head = clampf(_track.to_local(cam.global_position).y, 1.0, 2.1) if cam.is_inside_tree() else head
	return [head * 0.48, head * 0.71, head * 0.94]


# A map layer's height in metres: the rows' spacing, layer 0 on the floor
# (a full wall stands on it), half a row under the bottom row from 1 up.
func _layer_y(layer: float) -> float:
	if layer <= 0.0:
		return 0.0
	var rows := _row_heights()
	var step: float = rows[1] - rows[0]
	return rows[0] + (layer - 0.5) * step


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
	# The whole cube turns to its direction (a diagonal note is a cube on
	# its corner), so the arrow always sits straight on the face, toward
	# the edge to cut through.
	var rot := atan2(-dir.x, dir.y) if dir != Vector2.ZERO else 0.0
	node.rotation = Vector3(0, 0, rot)
	var pos := _note_pos(n)
	var t := _beat_time(n[0])
	pos.z = _track_z(t - _clock)
	node.position = pos
	node.visible = true
	_active.append({"node": node, "kind": "bomb" if bomb else "note", "hand": n[3], "dir": dir, "time": t, "pos": pos, "rot": rot})


func _release(a: Dictionary) -> void:
	var node: MeshInstance3D = a["node"]
	node.visible = false
	(_free_bombs if a["kind"] == "bomb" else _free_notes).append(node)


# Each saber's blade in track space now and last frame, its tip's recent
# path, and how fast the tip moves.
func _update_blades(delta: float) -> void:
	for side in ["right", "left"]:
		var sab: Node3D = _sabers.get(side)
		if sab == null or not is_instance_valid(sab) or not sab.is_visible_in_tree() \
				or (side == "left" and _song.get("mode") == "OneSaber"):  # one saber: the right one
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


# --- Walls and arcs (from custom maps) ------------------------------------------------
# Walls come down the track like notes: keep your head out of them (lean or
# crouch). Going in breaks your combo; inside, the music goes quiet and both
# controllers buzz softly, as in BeepSaber (its _spawn_wall and
# _quiet_song, MIT, ideas only). Arcs are glowing lines from a note to a
# later one, the way to swing between them; they're only shown, not scored.

func _spawn_extras() -> void:
	var ahead := _lead()
	var walls: Array = _song.get("walls", [])
	while _next_wall < walls.size() and _beat_time(walls[_next_wall][0]) - _clock <= ahead:
		_spawn_wall(walls[_next_wall])
		_next_wall += 1
	var arcs: Array = _song.get("arcs", [])
	while _next_arc < arcs.size() and _beat_time(arcs[_next_arc][0]) - _clock <= ahead:
		_spawn_arc(arcs[_next_arc])
		_next_arc += 1


func _spawn_wall(w: Array) -> void:
	var start := _beat_time(w[0])
	var end := _beat_time(w[0] + w[1])
	var left: float = (w[2] - 2.0) * LANE_W
	var bottom := _layer_y(w[4])
	var top := _layer_y(w[4] + w[5])
	var depth := (end - start) * float(game["speed"])
	var node := MeshInstance3D.new()
	node.mesh = _wall_mesh
	node.material_override = _mat["wall"]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale = Vector3(w[3] * LANE_W, maxf(top - bottom, 0.05), maxf(depth, 0.05))
	_track.add_child(node)
	# The box is placed by its front face's z; its own frame has z running back.
	var box := AABB(Vector3(left, bottom, -depth), Vector3(w[3] * LANE_W, top - bottom, depth))
	_walls_on.append({"node": node, "time": start, "end": end, "box": box})
	_place_wall(_walls_on[-1])


func _place_wall(e: Dictionary) -> void:
	var front := _track_z(float(e["time"]) - _clock)
	var box: AABB = e["box"]
	(e["node"] as Node3D).position = Vector3(box.position.x + box.size.x / 2.0, box.position.y + box.size.y / 2.0, front - box.size.z / 2.0)
	e["front"] = front


func _spawn_arc(a: Array) -> void:
	var head := _note_pos([a[0], a[1], a[2]])
	var tail := _note_pos([a[4], a[5], a[6]])
	var start := _beat_time(a[0])
	var end := _beat_time(a[4])
	tail.z = -(end - start) * float(game["speed"])
	var hd: Vector2 = DIRS[a[3]]
	var td: Vector2 = DIRS[a[7]]
	var reach := absf(tail.z) / 3.0
	var p1: Vector3 = head + Vector3(hd.x, hd.y, 0.0) * ARC_PULL * float(a[9]) + Vector3(0, 0, -reach)
	var p2: Vector3 = tail - Vector3(td.x, td.y, 0.0) * ARC_PULL * float(a[10]) + Vector3(0, 0, reach)
	# A thin ribbon in two crossed strips, so it reads from any side.
	var verts := PackedVector3Array()
	var last := head
	for i in range(1, ARC_STEPS + 1):
		var t := float(i) / ARC_STEPS
		var p := head.bezier_interpolate(p1, p2, tail, t)
		for side in [Vector3(ARC_WIDTH, 0, 0), Vector3(0, ARC_WIDTH, 0)]:
			verts.append_array([last - side, last + side, p + side, last - side, p + side, p - side])
		last = p
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat["arc_" + a[8]]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_track.add_child(node)
	_arcs_on.append({"node": node, "time": start, "end": end})


func _move_extras() -> void:
	var speed: float = game["speed"]
	for i in range(_arcs_on.size() - 1, -1, -1):
		var e: Dictionary = _arcs_on[i]
		var z := HIT_Z - (float(e["time"]) - _clock) * speed
		(e["node"] as Node3D).position = Vector3(0, 0, z)
		if HIT_Z - (float(e["end"]) - _clock) * speed > MISS_Z:
			e["node"].queue_free()
			_arcs_on.remove_at(i)
	var head := Vector3(INF, INF, INF)
	var cam: Node3D = ctx.get("camera")
	if cam and is_instance_valid(cam) and cam.is_inside_tree():
		head = _track.to_local(cam.global_position)
	var inside := false
	for i in range(_walls_on.size() - 1, -1, -1):
		var e: Dictionary = _walls_on[i]
		_place_wall(e)
		var box: AABB = e["box"]
		var here := AABB(Vector3(box.position.x, box.position.y, e["front"] - box.size.z), box.size)
		if here.grow(0.05).has_point(head):
			inside = true
		if e["front"] - box.size.z > MISS_Z + 1.0:
			e["node"].queue_free()
			_walls_on.remove_at(i)
	_wall_feel(inside)


# Into a wall: the combo breaks once; while in, quiet music and a buzz.
func _wall_feel(inside: bool) -> void:
	if inside and not _in_wall:
		bumped += 1
		combo = 0
		_pop(_track.to_local(ctx["camera"].global_position) + Vector3(0, -0.3, -0.6), "Wall!", 0)
		_update_board()
	if inside != _in_wall:
		_song_player.volume_db = -15.0 if inside else 0.0
	_in_wall = inside
	if inside:
		_pulse("left", 0.15, 0.05)
		_pulse("right", 0.15, 0.05)


func _clear_extras() -> void:
	for e in _walls_on + _arcs_on:
		if is_instance_valid(e["node"]):
			e["node"].queue_free()
	_walls_on.clear()
	_arcs_on.clear()
	if _in_wall:
		_song_player.volume_db = 0.0
	_in_wall = false


func _move_and_cut(delta: float) -> void:
	var speed: float = game["speed"]
	for i in range(_active.size() - 1, -1, -1):
		var a: Dictionary = _active[i]
		var node: MeshInstance3D = a["node"]
		var pos: Vector3 = a["pos"]
		var was_z := pos.z
		pos.z = _track_z(float(a["time"]) - _clock)
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
		if float(b["speed"]) >= need and _swept_hit(b, a["pos"], moved, a["rot"]):
			return side
	return ""


# Does the blade's path between last frame and now pass through the note's
# box? Tested in the note's own frame (the note moved too): a few blade
# positions in between, each a segment against the box.
func _swept_hit(b: Dictionary, centre: Vector3, moved: float, rot: float) -> bool:
	var was_centre := centre - Vector3(0, 0, moved)
	var undo := Basis(Vector3.BACK, -rot)  # into the turned cube's own frame
	var pb: Vector3 = undo * (b["pbase"] - was_centre)
	var pt: Vector3 = undo * (b["ptip"] - was_centre)
	var nb: Vector3 = undo * (b["base"] - centre)
	var nt: Vector3 = undo * (b["tip"] - centre)
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
	var key := _score_key(id, game["difficulty"], _song.get("mode", "Standard"))
	var list: Array = scores.get(key, [])
	list.append({"score": score, "rank": rank, "accuracy": snappedf(acc, 0.1), "combo": max_combo,
		"date": Time.get_date_string_from_system()})
	list.sort_custom(func(a, b): return a["score"] > b["score"])
	scores[key] = list.slice(0, TOP_SCORES)
	_save_settings()
	_results = {"title": _song["title"], "score": score, "max_combo": max_combo, "accuracy": snappedf(acc, 0.1), "rank": rank,
		"cuts": cuts, "misses": missed, "bad_cuts": bad, "bombs_hit": bombs_hit, "walls_hit": bumped, "new_best": new_best, "best": best.get(id, score)}
	running = false
	_song_player.stop()
	_board.text = "%s\n%d  rank %s\n%d%%  best combo %d" % [_song["title"], score, rank, int(acc), max_combo]
	finished.emit(_results)
	stopped.emit()
	_bring_back()
	if _projects() == null:
		_hands_back()


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


# The cut sound, made here (no sound file): an energy blade slicing through.
# Three takes, picked at random with a little pitch and level change each
# time (AudioStreamRandomizer), so a run of cuts doesn't sound like one
# sample on repeat.
func _hit_sound() -> AudioStream:
	var takes := AudioStreamRandomizer.new()
	takes.random_pitch = 1.06
	takes.random_volume_offset_db = 1.5
	for take in 3:
		takes.add_stream(-1, _slice_take(take))
	return takes


# One take, about a third of a second, three layers mixed and softly
# clipped:
#   - the blade: two detuned low buzzes (saw-like, a few harmonics) whose
#     pitch falls as it passes, like a saber swung past your ear;
#   - the sizzle: noise through a band-pass filter that sweeps down from a
#     bright hiss, the "kssh" of it burning through;
#   - the hit: a short low thump that falls in pitch, so the cut lands;
#   - the swoosh: softer, wider noise that rises and falls, the air the
#     swing moves.
# isaac 2026-10-31: lower, with a little swoosh, then a low-pass over all.
func _slice_take(take: int) -> AudioStreamWAV:
	var rate := 32000
	var length := SLICE_SECONDS
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 101 + take * 17
	var base: float = [76.0, 68.0, 84.0][take]   # each take a little different
	var sweep: float = [2800.0, 2400.0, 3200.0][take]
	var phase_a := 0.0
	var phase_b := 0.0
	var phase_t := 0.0
	var bp1 := 0.0  # band-pass state (two passes of a simple state-variable filter)
	var bp2 := 0.0
	var lp1 := 0.0
	var lp2 := 0.0
	var wb := 0.0  # the swoosh's own band-pass
	var wl := 0.0
	var low_a := 0.0  # the final low-pass: two one-pole stages
	var low_b := 0.0
	var low_k := 1.0 - exp(-TAU * SLICE_LOW_PASS / rate)
	for i in count:
		var t := float(i) / rate
		# The blade's buzz.
		var bend := 1.0 + 0.35 * exp(-t * 14.0)  # starts high, settles
		phase_a = fmod(phase_a + base * bend / rate, 1.0)
		phase_b = fmod(phase_b + base * 1.013 * bend / rate, 1.0)
		var buzz := 0.0
		for h in [1, 2, 3, 5]:
			buzz += (sin(TAU * phase_a * h) + sin(TAU * phase_b * h)) / float(h)
		var buzz_env := minf(t / 0.006, 1.0) * exp(-t * 9.0)
		# The sizzle: noise through a sweeping band-pass.
		var centre := 600.0 + sweep * exp(-t * 18.0)
		var f := 2.0 * sin(PI * centre / rate)
		var q := 0.35
		var noise := rng.randf_range(-1.0, 1.0)
		var hp1 := noise - lp1 - q * bp1
		bp1 += f * hp1
		lp1 += f * bp1
		var hp2 := bp1 - lp2 - q * bp2
		bp2 += f * hp2
		lp2 += f * bp2
		var sizzle_env := minf(t / 0.003, 1.0) * exp(-t * 16.0)
		# The hit: a falling thump.
		phase_t = fmod(phase_t + (40.0 + 100.0 * exp(-t * 40.0)) / rate, 1.0)
		var thump := sin(TAU * phase_t) * exp(-t * 32.0)
		# The swoosh: wide band-passed noise, its centre rising then falling.
		var wf := 2.0 * sin(PI * (350.0 + 1100.0 * sin(PI * minf(t / 0.3, 1.0))) / rate)
		var whp := rng.randf_range(-1.0, 1.0) - wl - 1.2 * wb
		wb += wf * whp
		wl += wf * wb
		var swoosh_env := sin(PI * minf(t / 0.36, 1.0)) * exp(-t * 3.0)
		var v := 0.16 * buzz * buzz_env + 0.5 * bp2 * sizzle_env + 0.55 * thump + 0.35 * wb * swoosh_env
		v = tanh(v * 1.6)  # soft clip: full but never harsh
		low_a += low_k * (v - low_a)  # then a low-pass takes the hiss's edge off (isaac)
		low_b += low_k * (low_a - low_b)
		data.encode_s16(i * 2, int(clampf(low_b * 1.15, -1.0, 1.0) * 30000.0))
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
	# A wide flat triangle in the XY plane facing +z, flat end along y = 0
	# and its point up (isaac: the flat end lines up with the block's edge).
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-ARROW_W / 2.0, 0.0, 0.0), Vector3(0.0, ARROW_H, 0.0), Vector3(ARROW_W / 2.0, 0.0, 0.0)])
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
	_wall_mesh = BoxMesh.new()
	_wall_mesh.size = Vector3.ONE
	var wall_shader := Shader.new()
	wall_shader.code = WALL_SHADER
	var wall := ShaderMaterial.new()
	wall.shader = wall_shader
	_mat["wall"] = wall
	for hand in ["l", "r"]:
		var line := _flat(Color(1.0, 0.3, 0.3, 0.7) if hand == "r" else Color(0.3, 0.5, 1.0, 0.7))
		line.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		line.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat["arc_" + hand] = line
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
	# Pointing up the face, its flat end along the bottom edge: an up note's
	# arrow starts at the bottom, a down note (the cube turned over) at the top.
	a.position = Vector3(0, -NOTE_HALF + ARROW_EDGE, NOTE_HALF + 0.01)
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
	out["scores"] = scores
	out["return_to"] = _return_to
	out["hands_before"] = _hands_before
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
		for key in ["hit_sounds", "trails", "auto_sabers"]:
			if typeof(g.get(key)) == TYPE_BOOL:
				game[key] = g[key]
	var sc = saved.get("scores")
	if typeof(sc) == TYPE_DICTIONARY:
		for key in sc:
			if typeof(key) == TYPE_STRING and typeof(sc[key]) == TYPE_ARRAY:
				scores[key] = (sc[key] as Array).filter(func(e): return typeof(e) == TYPE_DICTIONARY and _number(e.get("score")) \
					and typeof(e.get("rank")) == TYPE_STRING and _number(e.get("accuracy"))).slice(0, TOP_SCORES)
	if saved.get("hands_before") in ["hand", "saber"]:
		_hands_before = saved["hands_before"]
	if typeof(saved.get("return_to")) == TYPE_STRING:
		_return_to = saved["return_to"]
	var b = saved.get("best")
	if typeof(b) == TYPE_DICTIONARY:
		for key in b:
			if typeof(key) == TYPE_STRING and _number(b[key]):
				best[key] = int(b[key])
