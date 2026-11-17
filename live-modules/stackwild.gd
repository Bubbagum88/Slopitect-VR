extends SlopitectModule

# Slopitect live module: stackwild, the "Stackwild" block game.
# A world of blocks to dig and build in: rolling turf hills, sandy shores
# at the waterline, snow on the high tops, trees, slate underground with
# veins of ember ore and skyshard. Dig any block and put blocks back
# wherever you like, one at a time.
#
# Two ways to play (Settings, or the lobby):
#   Build   every block, as many as you like; blocks come out at once.
#   Gather  you start with nothing; digging takes a moment (longer for
#           harder blocks) and puts that block in your pack, and you can
#           only place what you've gathered.
# Deepstone, the bottom layer, can't be dug.
#
# Controls (through controls.gd's actions, only while a game runs):
#   right trigger ("point")      dig the block you point at (hold)
#   right grip ("grab_right")    place the chosen block on the face you
#                                point at (hold to keep placing)
#   A ("right_a")                jump
#   B ("right_b")                next block
#   Y ("left_y")                 the Blocks window: pick any block
# Walk with the stick as always; one-block steps are walked up, walls of
# two stop you, and you fall off edges. The chosen block rides in your
# right hand, its name (and in Gather, how many) on your left wrist. The
# trigger and grip go to a window while you point at one.
#
# Its own world: like Holdout and Rhythm Sabers, the game has one world of
# its own, "stackwild" (a project, projects.gd), made the first time. The
# Menu's Stackwild tile or stackwild_start takes you there (saving the
# world you were in); Leave takes you back. The blocks are kept in that
# world's folder (stackwild.dat, lib.world_file), saved when you leave, on
# Save, when the module unloads, and every minute while something changed.
# Without projects.gd it plays where you stand, in the saves folder.
#
# For the agent: stackwild_block reads or sets one block, stackwild_fill a
# box of them (up to 32768), so it can build with you.
#
# Quest 1: the world is cut into 16 x 16 x 16 sections, each one mesh
# (greedy meshing: faces of the same block side by side merge into one
# quad), made on worker threads, nearest first; a change remakes only its
# section (and the one next to it when it's on the edge). No lights and no
# physics bodies: one unshaded material over a 16-pixel texture sheet drawn
# in code at load, side shading baked into the vertices, depth fog hiding
# the far edge, sections past the view distance not drawn. Pointing is a
# voxel walk along the ray; walking into walls is checked against the
# blocks. Nothing runs outside the world.
#
# Signals: started(), stopped(), world_ready(), block_changed(cell, block).

signal started()
signal stopped()
signal world_ready()
signal block_changed(cell: Vector3i, block: int)

const TITLE := "Stackwild"
const PANEL := "stackwild"
const PICKER := "stackwild_blocks"
const PANEL_SIZE := Vector2(0.8, 0.62)
const PICKER_SIZE := Vector2(0.72, 0.46)
const WORLD := "stackwild"
const SETTINGS_PATH := "user://stackwild.json"
const SAVE_FILE := "stackwild.dat"
const SAVE_VERSION := 1
const DEFAULTS := {"mode": "build", "size": "medium", "view": 48, "sounds": true}
const MODES := ["build", "gather"]
const MODE_LABELS := {"build": "Build", "gather": "Gather"}
const SIZES := {"small": 4, "medium": 8, "large": 12}  # sections across
const SIZE_ORDER := ["small", "medium", "large"]
const SIZE_LABELS := {"small": "Small", "medium": "Medium", "large": "Large"}
const VIEW := [24, 96]          # metres you see, the slider's range
const MAX_FILL := 32768         # blocks one stackwild_fill may set
const AUTOSAVE := 60.0          # seconds between saves while something changed
const MAX_JOBS := 3             # worker tasks at once

# The world: columns of 16 x 16 blocks, 64 high, cut into four sections.
const CS := 16
const SECTIONS := 4
const HEIGHT := 64
const COL_BYTES := CS * CS * HEIGHT
const SEA := 14                 # the water's top is just under SEA + 1
const SNOW_LINE := 38
const PAD := 18                 # a section with a block of its neighbours all round

# You.
const BODY_R := 0.25
const STEP_UP := 1.05           # a step this high is walked up
const GRAVITY := 18.0
const JUMP_SPEED := 6.4         # about 1.15 m up
const REACH := 5.0              # metres you can dig and place
const REPEAT := 0.25            # seconds between blocks while held (Build digging, placing)
const GATHER_DIG := 0.9         # seconds of digging per point of hardness, in Gather

const AIR := 0
const DEEP := 21
# Blocks by id (the index). tiles: [top, side, bottom] in the texture sheet.
# hard: how long it takes to dig in Gather (-1: it can't be dug).
const BLOCKS := [
	{"id": "air", "name": "Air", "tiles": [0, 0, 0], "hard": 0.0, "sound": "soft"},
	{"id": "turf", "name": "Turf", "tiles": [0, 1, 2], "hard": 0.6, "sound": "soft"},
	{"id": "loam", "name": "Loam", "tiles": [2, 2, 2], "hard": 0.5, "sound": "soft"},
	{"id": "slate", "name": "Slate", "tiles": [3, 3, 3], "hard": 1.5, "sound": "hard"},
	{"id": "fieldstone", "name": "Fieldstone", "tiles": [4, 4, 4], "hard": 1.7, "sound": "hard"},
	{"id": "sand", "name": "Sand", "tiles": [5, 5, 5], "hard": 0.5, "sound": "soft"},
	{"id": "log", "name": "Log", "tiles": [7, 6, 7], "hard": 1.0, "sound": "wood"},
	{"id": "canopy", "name": "Canopy", "tiles": [8, 8, 8], "hard": 0.25, "sound": "soft"},
	{"id": "boards", "name": "Boards", "tiles": [9, 9, 9], "hard": 1.0, "sound": "wood"},
	{"id": "brick", "name": "Brick", "tiles": [10, 10, 10], "hard": 1.7, "sound": "hard"},
	{"id": "snow", "name": "Snow", "tiles": [11, 11, 11], "hard": 0.4, "sound": "soft"},
	{"id": "ember_ore", "name": "Ember ore", "tiles": [12, 12, 12], "hard": 2.2, "sound": "hard"},
	{"id": "skyshard", "name": "Skyshard", "tiles": [13, 13, 13], "hard": 2.6, "sound": "hard"},
	{"id": "lamp", "name": "Lamp", "tiles": [14, 14, 14], "hard": 0.6, "sound": "hard", "glow": true},
	{"id": "felt_red", "name": "Red felt", "tiles": [15, 15, 15], "hard": 0.4, "sound": "soft"},
	{"id": "felt_blue", "name": "Blue felt", "tiles": [16, 16, 16], "hard": 0.4, "sound": "soft"},
	{"id": "felt_yellow", "name": "Yellow felt", "tiles": [17, 17, 17], "hard": 0.4, "sound": "soft"},
	{"id": "felt_green", "name": "Green felt", "tiles": [18, 18, 18], "hard": 0.4, "sound": "soft"},
	{"id": "felt_white", "name": "White felt", "tiles": [19, 19, 19], "hard": 0.4, "sound": "soft"},
	{"id": "felt_black", "name": "Black felt", "tiles": [20, 20, 20], "hard": 0.4, "sound": "soft"},
	{"id": "rushes", "name": "Rushes", "tiles": [22, 22, 22], "hard": 0.3, "sound": "soft"},
	{"id": "deepstone", "name": "Deepstone", "tiles": [21, 21, 21], "hard": -1.0, "sound": "hard"},
]
const TILE_COLS := 8
const TILE_ROWS := 3
const TILE_PX := 16
const TURF := 1
const LOAM := 2
const SLATE := 3
const SAND := 5
const LOG := 6
const CANOPY := 7
const SNOW := 10
const EMBER := 11
const SKYSHARD := 12
const SHADE_TOP := 1.0
const SHADE_BOTTOM := 0.55
const SHADE_X := 0.82
const SHADE_Z := 0.7

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D sheet : filter_nearest, repeat_disable;
uniform vec2 tiles = vec2(8.0, 3.0);
varying flat vec2 tile;
void vertex() {
	tile = UV2;
}
void fragment() {
	vec2 at = (tile + fract(UV)) / tiles;
	ALBEDO = texture(sheet, at).rgb * COLOR.rgb;
}
"""

var running := false
var settings := DEFAULTS.duplicate(true)
var selected := TURF            # the block in your hand
var counts := {}                # Gather: block id (String) -> how many you carry
var world_seed := 0
var edits := 0                  # blocks dug and placed in this world

var _lib: SlopitectModule
var _controls: SlopitectModule
var _audio: SlopitectModule
var _land: Node3D               # the blocks, placed so you stand where you are
var _water: MeshInstance3D
var _swapped := {}
var _mat: ShaderMaterial
var _sheet: ImageTexture
var _n := 0                     # columns across
var _size := 0                  # blocks across
var _cols: Array = []           # PackedByteArray per column (empty until made)
var _packed: Array = []         # each column compressed for the file (empty: changed since)
var _ready_now := false         # every column made (or loaded)
var _world_id := 0              # results from an older world are dropped
var _jobs: Array = []           # {"task", "job"}
var _gen_queue: Array = []      # [cx, cz] still to make, nearest last
var _gen_left := 0
var _queue: Array = []          # sections to mesh, nearest last
var _urgent: Array = []         # sections changed by you: these first
var _queued := {}
var _busy := {}                 # sections being meshed now
var _again := {}                # changed while being meshed
var _sections := {}             # Vector3i -> MeshInstance3D
var _tris := {}                 # Vector3i -> triangles
var _meshed := 0                # sections meshed since the world opened
var _spawn := Vector3.ZERO      # land space
var _start_at = null            # where you stood when last saved (Vector3), or null
var _save_path := ""
var _dirty := false
var _autosave_t := 0.0
var _held := false
var _feet := 0.0                # land space
var _vy := 0.0
var _on_ground := false
var _last_xz := Vector2.INF
var _trigger := false
var _dig_cell = null            # Vector3i being dug, or null
var _dig_t := 0.0
var _place_held := false
var _place_t := 0.0
var _hit := {}                  # what you point at: {"cell", "normal", "dist"}
var _outline: MeshInstance3D
var _crack: MeshInstance3D
var _beam: MeshInstance3D
var _hand_block: MeshInstance3D
var _wrist: Label3D
var _hidden_boxes: Array = []
var _sounds := {}
var _sounds_task := -1
var _players: Array = []        # without audio.gd
var _next_player := 0
var _return_to := ""
var _confirm_new := false
var _tile_top := PackedInt32Array()
var _tile_side := PackedInt32Array()
var _tile_bottom := PackedInt32Array()
var _glow := PackedByteArray()
var _air_layer := PackedByteArray()
var _deep_layer := PackedByteArray()
var _air_row := PackedByteArray()


func setup() -> String:
	register("stackwild_start", _start, "start Stackwild (goes to its world first): optional mode (build, gather)")
	register("stackwild_stop", _stop, "stop playing (you stay in the Stackwild world)")
	register("stackwild_status", _status, "the game: running, loading, seed, size, mode, the chosen block, what you carry (Gather), where you stand, sections and triangles drawn")
	register("stackwild_set", _set_command, "the game's settings (usable in the headset): any of mode (build, gather), size (small, medium, large: for new worlds), view (%d to %d m), sounds (true/false), block (a block id to hold)" % VIEW)
	register("stackwild_do", _do, "the Stackwild windows: act = toggle (goes to the Stackwild world first), show, hide, start, leave, blocks (the Blocks window), pick (block = a block id)")
	register("stackwild_leave", _leave, "save, stop and go back from the Stackwild world to the world you came from")
	register("stackwild_new", _new_command, "make a new world: optional seed (a number), size (small, medium, large); replace true is needed when a world exists (it's lost)")
	register("stackwild_save", _save_command, "save the Stackwild world now")
	register("stackwild_block", _block_command, "read the block at position [x, y, z] (whole blocks, 0 to 63 high), or set it with block (a block id, or air)")
	register("stackwild_fill", _fill_command, "fill the box from [x, y, z] to [x, y, z] (both corners included, up to %d blocks) with block (a block id, or air)" % MAX_FILL)
	for b in BLOCKS:
		_tile_top.append(b["tiles"][0])
		_tile_side.append(b["tiles"][1])
		_tile_bottom.append(b["tiles"][2])
		_glow.append(1 if b.get("glow", false) else 0)
	_air_layer.resize(PAD * PAD)
	_deep_layer.resize(PAD * PAD)
	_deep_layer.fill(DEEP)
	_air_row.resize(CS)
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	set_process_priority(200)  # after controls.gd and jump.gd: the blocks decide your height
	set_process(false)
	return ""


func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		_controls = null
		_audio = null
		return
	_load_settings()
	lib.watch(self, "controls", _controls_here, _controls_gone)
	lib.watch(self, "audio", _audio_here, _audio_gone)
	lib.follow(self, "projects", "project_changed", _on_world_changed)
	for ui_name in ["vrui", "ui"]:
		lib.follow(self, ui_name, "panel_shown", _panel_shown)
	if _projects() != null and in_world():  # loaded while already in the Stackwild world
		_stage_on()
	lib.touch(self)


func _controls_here(controls: SlopitectModule) -> void:
	_controls = controls


func _controls_gone(_old: SlopitectModule) -> void:
	_controls = null


func _audio_here(audio: SlopitectModule) -> void:
	_audio = audio


func _audio_gone(_old: SlopitectModule) -> void:
	_audio = null


func _exit_tree() -> void:
	_wait_jobs()
	if _sounds_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_sounds_task)
		_sounds_task = -1
	_stop_game()
	_save_world()
	_stage_off()
	ctx["server"].run({"cmd": "ui_remove", "id_panel": PANEL})
	ctx["server"].run({"cmd": "ui_remove", "id_panel": PICKER})


# --- Menu, Settings and the windows ---------------------------------------------

func menu_info() -> Dictionary:
	return {"id": "stackwild", "label": "Stackwild", "order": 62, "action": {"cmd": "stackwild_do", "act": "toggle"}}


func hand_info() -> Dictionary:
	return {"id": "stackwild", "label": "Stackwild", "order": 62, "action": {"cmd": "stackwild_do", "act": "toggle"}}


func settings_info() -> Dictionary:
	var modes := []
	for m in MODES:
		modes.append({"label": MODE_LABELS[m], "value": m})
	var sizes := []
	for s in SIZE_ORDER:
		sizes.append({"label": SIZE_LABELS[s], "value": s})
	return {"title": TITLE, "order": 47, "settings": [
		{"id": "mode", "type": "choice", "label": "How you play", "value": settings["mode"], "options": modes, "columns": 2,
			"set": {"cmd": "stackwild_set", "mode": "{value}"}},
		{"id": "size", "type": "choice", "label": "Size of new worlds", "value": settings["size"], "options": sizes, "columns": 3,
			"set": {"cmd": "stackwild_set", "size": "{value}"}},
		{"id": "view", "type": "slider", "label": "How far you see (metres)", "min": VIEW[0], "max": VIEW[1], "step": 8.0,
			"value": settings["view"], "set": {"cmd": "stackwild_set", "view": "{value}"}},
		{"id": "sounds", "type": "toggle", "label": "Game sounds", "value": settings["sounds"],
			"set": {"cmd": "stackwild_set", "sounds": "{value}"}},
		{"id": "start", "type": "button", "label": "Play", "set": {"cmd": "stackwild_start"}},
		{"id": "save", "type": "button", "label": "Save the world now", "set": {"cmd": "stackwild_save"}},
		{"id": "leave", "type": "button", "label": "Leave the Stackwild world", "set": {"cmd": "stackwild_leave"}},
	]}


# Before vrui.gd (0), whose window toggles are on A, B and Y too, and grab.gd
# (on the grips); after pause (-10), so the hand menu still opens. Only while
# a game runs, and the trigger and grip go to a window you point at.
func action_order() -> int:
	return -6


func on_action(action: String, down: bool) -> bool:
	if not running or _held:
		return false
	match action:
		"point":
			if down and _pointing_at_window():
				return false
			_trigger = down
			_dig_cell = null
			_dig_t = 0.0
			if down and settings["mode"] == "build":
				_dig_now()
			return true
		"grab_right":
			if down and _pointing_at_window():
				return false
			_place_held = down
			_place_t = REPEAT
			if down:
				_place_now()
			return true
		"right_a":
			if down and _on_ground and _ready_now:
				_vy = JUMP_SPEED
				_on_ground = false
			return true
		"right_b":
			if down:
				_next_block()
			return true
		"left_y":
			if down:
				_toggle_picker()
			return true
	return false


func _pointing_at_window() -> bool:
	var ui: SlopitectModule = _lib.module("vrui") if _lib else null
	return ui != null and ui.has_method("pointing") and not String(ui.call("pointing")).is_empty()


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


func _has_ui() -> bool:
	return ctx["modules"].module("vrui") != null or ctx["modules"].module("ui") != null


func _panel_exists(id_panel: String) -> bool:
	return _has_ui() and _run({"cmd": "ui_get", "id_panel": id_panel}).get("ok", false)


func _shown(id_panel: String) -> bool:
	var got := _run({"cmd": "ui_get", "id_panel": id_panel}) if _has_ui() else {}
	return got.get("ok", false) and got.get("panel", {}).get("visible", false)


func _do(request: Dictionary) -> Dictionary:
	match request.get("act"):
		"toggle":
			if in_world() and _shown(PANEL):
				_hide(PANEL)
				return {"ok": true, "shown": false}
			var problem := _enter()
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			return _show_window()
		"show":
			return _show_window()
		"hide":
			_hide(PANEL)
			return {"ok": true, "shown": false}
		"start":
			return _start({})
		"leave":
			return _leave({})
		"new":
			# The lobby's New world: the first press asks, the second makes it.
			if not _confirm_new:
				_confirm_new = true
				_build()
				return {"ok": true, "asking": true}
			_confirm_new = false
			return _new_command({"replace": true})
		"blocks":
			return _toggle_picker()
		"pick":
			var b := _block_id(request.get("block"))
			if b <= 0 or b == DEEP:
				return {"ok": false, "error": "\"block\" must be one of %s" % ", ".join(_placeable_ids())}
			_choose(b)
			_hide(PICKER)
			return {"ok": true, "block": BLOCKS[b]["id"]}
	return {"ok": false, "error": "\"act\" must be toggle, show, hide, start, leave, new, blocks or pick"}


func _show_window() -> Dictionary:
	if not is_inside_tree():
		return {"ok": false, "error": "Stackwild is unloading"}
	if not _has_ui():
		return {"ok": false, "error": "the Stackwild window needs the vrui module"}
	var problem := _build()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	_run({"cmd": "ui_show", "id_panel": PANEL, "visible": true})
	return {"ok": true, "shown": true}


func _hide(id_panel: String) -> void:
	if _panel_exists(id_panel):
		_run({"cmd": "ui_show", "id_panel": id_panel, "visible": false})


# While the game's window is open during a game, the buttons go to it
# (walking still works); closing it carries on.
func _panel_shown(id_panel: String, on: bool) -> void:
	if id_panel == PANEL:
		_held = on and running
		_trigger = false
		_place_held = false
		_dig_cell = null
		_show_aim(false)


func _show_if_idle() -> void:
	if not running and is_inside_tree():
		_show_window()


func _build() -> String:
	if not _has_ui():
		return "the Stackwild window needs the vrui module"
	var els := []
	var w := PANEL_SIZE.x - 0.08
	var y := PANEL_SIZE.y / 2.0 - 0.07
	var third := [w / 3.0 - 0.02, 0.06]
	els.append({"type": "text", "id": "status", "text": _window_text(), "at": [0.0, y - 0.04], "width": w})
	y -= 0.19
	if running:
		els.append({"type": "button", "id": "resume", "label": "Resume", "at": [-w / 3.0, y], "size": third, "color": "ok",
			"action": {"cmd": "stackwild_do", "act": "hide"}})
		els.append({"type": "button", "id": "blocks", "label": "Blocks", "at": [0.0, y], "size": third, "color": "accent",
			"action": {"cmd": "stackwild_do", "act": "blocks"}})
		els.append({"type": "button", "id": "save", "label": "Save", "at": [w / 3.0, y], "size": third, "color": "button",
			"action": {"cmd": "stackwild_save"}})
		y -= 0.08
		els.append({"type": "button", "id": "stop", "label": "Stop playing", "at": [-w / 6.0, y], "size": third, "color": "notice",
			"action": {"cmd": "stackwild_stop"}})
		els.append({"type": "button", "id": "leave", "label": "Leave", "at": [w / 6.0, y], "size": third, "color": "button",
			"action": {"cmd": "stackwild_leave"}})
		y -= 0.1
	else:
		els.append({"type": "text", "id": "mode_head", "text": "How you play", "color": "muted", "at": [0.0, y + 0.065], "width": w})
		for i in MODES.size():
			var m: String = MODES[i]
			els.append({"type": "button", "id": "mode_" + m, "label": MODE_LABELS[m], "at": [(i - 0.5) * w / 2.0, y], "size": [w / 2.0 - 0.02, 0.055],
				"color": "accent" if settings["mode"] == m else "button", "action": {"cmd": "stackwild_set", "mode": m}})
		y -= 0.1
		els.append({"type": "text", "id": "size_head", "text": "Size of new worlds", "color": "muted", "at": [0.0, y + 0.065], "width": w})
		for i in SIZE_ORDER.size():
			var s: String = SIZE_ORDER[i]
			els.append({"type": "button", "id": "size_" + s, "label": SIZE_LABELS[s], "at": [(i - 1) * w / 3.0, y], "size": [w / 3.0 - 0.02, 0.055],
				"color": "accent" if settings["size"] == s else "button", "action": {"cmd": "stackwild_set", "size": s}})
		y -= 0.09
		els.append({"type": "button", "id": "start", "label": "Play", "at": [-w / 3.0, y], "size": third, "color": "ok",
			"action": {"cmd": "stackwild_start"}})
		els.append({"type": "button", "id": "new", "label": "Sure? Press again" if _confirm_new else "New world", "at": [0.0, y], "size": third,
			"color": "notice" if _confirm_new else "button", "action": {"cmd": "stackwild_do", "act": "new"}})
		els.append({"type": "button", "id": "leave", "label": "Leave", "at": [w / 3.0, y], "size": third, "color": "button",
			"action": {"cmd": "stackwild_leave"}})
		y -= 0.1
	els.append({"type": "text", "id": "help", "color": "muted", "at": [0.0, y], "width": w,
		"text": "Trigger: dig   Grip: place   A: jump\nB: next block   Y: Blocks window"})
	var request := {"id_panel": PANEL, "elements": els}
	if _panel_exists(PANEL):
		request["cmd"] = "ui_update"
	else:
		request.merge({"cmd": "ui_add", "title": TITLE, "size": [PANEL_SIZE.x, PANEL_SIZE.y], "chrome": true, "visible": false})
	var reply := _run(request)
	return "" if reply.get("ok", false) else "%s: %s" % [PANEL, reply.get("error", "couldn't be drawn")]


func _window_text() -> String:
	var mode: String = MODE_LABELS[settings["mode"]]
	if _land == null:
		return "Dig and build in a world of blocks."
	if not _ready_now:
		return "Raising the land... %d%%" % _progress()
	var where := "World %d (%d x %d blocks), %s." % [world_seed, _size, _size, mode]
	if running:
		return "%s\nThe buttons work this window while it's open." % where
	var building := "" if _queue.is_empty() else " Still building the far parts."
	return "%s%s\nPlay to dig and build; you can walk about now." % [where, building]


func _progress() -> int:
	if _n == 0:
		return 0
	return int(100.0 * float(_n * _n - _gen_left) / float(_n * _n))


# The Blocks window: every block, pressed to hold it.
func _toggle_picker() -> Dictionary:
	if not _has_ui():
		return {"ok": false, "error": "the Blocks window needs the vrui module"}
	if _shown(PICKER):
		_hide(PICKER)
		return {"ok": true, "shown": false}
	_build_picker()
	_run({"cmd": "ui_show", "id_panel": PICKER, "visible": true})
	return {"ok": true, "shown": true}


func _build_picker() -> void:
	var els := []
	var w := PICKER_SIZE.x - 0.06
	var cols := 4
	var cell := Vector2(w / cols, 0.075)
	var top := PICKER_SIZE.y / 2.0 - 0.07
	var ids := _placeable()
	for i in ids.size():
		var b: int = ids[i]
		var label: String = BLOCKS[b]["name"]
		if settings["mode"] == "gather":
			label += "  %d" % int(counts.get(BLOCKS[b]["id"], 0))
		els.append({"type": "button", "id": "b_" + BLOCKS[b]["id"], "label": label,
			"at": [(i % cols - (cols - 1) / 2.0) * cell.x, top - (i / cols) * cell.y], "size": [cell.x - 0.015, cell.y - 0.015],
			"color": "accent" if b == selected else "button", "action": {"cmd": "stackwild_do", "act": "pick", "block": BLOCKS[b]["id"]}})
	var request := {"id_panel": PICKER, "elements": els}
	if _panel_exists(PICKER):
		request["cmd"] = "ui_update"
	else:
		request.merge({"cmd": "ui_add", "title": "Blocks", "size": [PICKER_SIZE.x, PICKER_SIZE.y], "chrome": true, "visible": false})
	_run(request)


func _placeable() -> Array:
	var out := []
	for b in range(1, BLOCKS.size()):
		if b != DEEP:
			out.append(b)
	return out


func _placeable_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for b in _placeable():
		out.append(BLOCKS[b]["id"])
	return out


# A block id ("slate") or number to its number; -1 when it's no block.
func _block_id(value) -> int:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT] and int(value) >= 0 and int(value) < BLOCKS.size():
		return int(value)
	if typeof(value) == TYPE_STRING:
		for i in BLOCKS.size():
			if BLOCKS[i]["id"] == value:
				return i
	return -1


# --- Settings ----------------------------------------------------------------------

func _set_command(request: Dictionary) -> Dictionary:
	var changed := []
	if request.has("mode"):
		if not request["mode"] in MODES:
			return {"ok": false, "error": "\"mode\" must be build or gather"}
		settings["mode"] = request["mode"]
		_dig_cell = null
		changed.append("mode")
	if request.has("size"):
		if not request["size"] in SIZES:
			return {"ok": false, "error": "\"size\" must be small, medium or large"}
		settings["size"] = request["size"]
		changed.append("size")
	if request.has("view"):
		var v = request["view"]
		if typeof(v) == TYPE_STRING and v.is_valid_float():
			v = float(v)
		if typeof(v) not in [TYPE_INT, TYPE_FLOAT] or v < VIEW[0] or v > VIEW[1]:
			return {"ok": false, "error": "\"view\" must be %d to %d" % VIEW}
		settings["view"] = int(v)
		_apply_view()
		changed.append("view")
	if request.has("sounds"):
		var on = request["sounds"]
		if typeof(on) == TYPE_STRING:
			on = on == "true"
		if typeof(on) != TYPE_BOOL:
			return {"ok": false, "error": "\"sounds\" must be true or false"}
		settings["sounds"] = on
		changed.append("sounds")
	if request.has("block"):
		var b := _block_id(request["block"])
		if b <= 0 or b == DEEP:
			return {"ok": false, "error": "\"block\" must be one of %s" % ", ".join(_placeable_ids())}
		_choose(b)
		changed.append("block")
	if changed.is_empty():
		return {"ok": false, "error": "give mode, size, view, sounds or block"}
	_save_settings()
	if _lib:
		_lib.touch(self)
	if _panel_exists(PANEL):
		_build()
	if _panel_exists(PICKER):
		_build_picker()
	_update_hud()
	return {"ok": true, "settings": settings.duplicate(), "block": BLOCKS[selected]["id"], "changed": changed}


func _load_settings() -> void:
	if _lib == null:
		return
	var got = _lib.read_json(SETTINGS_PATH)
	if typeof(got) != TYPE_DICTIONARY:
		return
	var saved = got.get("settings", {})
	if typeof(saved) == TYPE_DICTIONARY:
		if saved.get("mode") in MODES:
			settings["mode"] = saved["mode"]
		if saved.get("size") in SIZES:
			settings["size"] = saved["size"]
		if typeof(saved.get("view")) in [TYPE_INT, TYPE_FLOAT]:
			settings["view"] = clampi(int(saved["view"]), VIEW[0], VIEW[1])
		if typeof(saved.get("sounds")) == TYPE_BOOL:
			settings["sounds"] = saved["sounds"]
	var b := _block_id(got.get("block"))
	if b > 0 and b != DEEP:
		selected = b
	if typeof(got.get("return_to")) == TYPE_STRING:
		_return_to = got["return_to"]


func _save_settings() -> void:
	if _lib:
		_lib.write_json(SETTINGS_PATH, {"settings": settings, "block": BLOCKS[selected]["id"], "return_to": _return_to})


# --- Its own world -----------------------------------------------------------------

func _projects() -> SlopitectModule:
	return _lib.module("projects") if _lib else null


func in_world() -> bool:
	return _projects() == null or _run({"cmd": "projects_current"}).get("name") == WORLD


# Takes you to the game's world, making it the first time. "" or what went wrong.
func _enter() -> String:
	if _projects() == null:
		_stage_on()
		return ""
	var here = _run({"cmd": "projects_current"}).get("name", "")
	if here == WORLD:
		_stage_on()
		return ""
	var exists: bool = _run({"cmd": "projects_list"}).get("projects", []).any(func(p): return p.get("name") == WORLD)
	var before := _return_to
	_return_to = here
	var reply: Dictionary
	if exists:
		reply = _run({"cmd": "projects_open", "name": WORLD})
	else:
		reply = _run({"cmd": "projects_new", "name": WORLD, "modules": ["stackwild"], "open": true})
	if not reply.get("ok", false):
		_return_to = before
		return "couldn't open the Stackwild world: %s" % reply.get("error", "?")
	_save_settings()
	_stage_on()  # project_changed does it too; this is for the window that opens now
	return ""


func _leave(_request: Dictionary) -> Dictionary:
	_stop_game()
	_save_world()
	_hide(PANEL)
	_hide(PICKER)
	if _projects() == null:
		_stage_off()
		return {"ok": true}
	if not in_world():
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


func _on_world_changed(project: String, _folder: String) -> void:
	if project == WORLD:
		_stage_on()
		_show_if_idle.call_deferred()
	else:
		_stop_game()
		_save_world()  # to the file it came from (_save_path), not the new world's
		_hide(PANEL)
		_hide(PICKER)
		_stage_off()


# --- Playing -----------------------------------------------------------------------

func _start(request: Dictionary) -> Dictionary:
	if request.has("mode"):
		if not request["mode"] in MODES:
			return {"ok": false, "error": "\"mode\" must be build or gather"}
		settings["mode"] = request["mode"]
		_save_settings()
	var problem := _enter()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	running = true
	_held = false
	_trigger = false
	_place_held = false
	_hold_gear(true)
	_hide(PANEL)
	set_process(true)
	_update_hud()
	started.emit()
	return {"ok": true, "mode": settings["mode"], "ready": _ready_now}


func _stop(_request: Dictionary) -> Dictionary:
	var was := running
	_stop_game()
	if was and in_world() and _land != null:
		_show_window()
	return {"ok": true, "was_running": was}


func _stop_game() -> void:
	var was := running
	running = false
	_held = false
	_trigger = false
	_place_held = false
	_dig_cell = null
	_hold_gear(false)
	if was:
		stopped.emit()


func _status(_request: Dictionary) -> Dictionary:
	var tris := 0
	for k in _tris:
		tris += int(_tris[k])
	var you := {}
	if _land != null and _ready_now:
		var head := _land.to_local((ctx["camera"] as Node3D).global_position)
		you = {"x": snappedf(head.x, 0.01), "z": snappedf(head.z, 0.01), "feet": snappedf(_feet, 0.01), "on_ground": _on_ground}
	return {"ok": true, "running": running, "in_world": in_world() if _lib else _land != null, "ready": _ready_now,
		"loading": _progress() if _land != null and not _ready_now else 100, "seed": world_seed, "size": _size,
		"mode": settings["mode"], "block": BLOCKS[selected]["id"], "carrying": counts.duplicate(), "edits": edits,
		"you": you, "pointing": _hit_out(), "sections": _sections.size(), "triangles": tris, "still_to_build": _queue.size() + _urgent.size() + _busy.size(),
		"settings": settings.duplicate(), "blocks": _placeable_ids(), "file": _save_path}


func _hit_out() -> Dictionary:
	if _hit.is_empty():
		return {}
	var c: Vector3i = _hit["cell"]
	return {"position": [c.x, c.y, c.z], "block": BLOCKS[block_at(c.x, c.y, c.z)]["id"]}


# --- The world: blocks -------------------------------------------------------------

# The block at a cell (land space, whole metres). Below the world is
# deepstone; above it and outside it is air.
func block_at(x: int, y: int, z: int) -> int:
	if y < 0:
		return DEEP
	if y >= HEIGHT or x < 0 or z < 0 or x >= _size or z >= _size:
		return AIR
	var col: PackedByteArray = _cols[(z >> 4) * _n + (x >> 4)]
	if col.is_empty():
		return AIR
	return col[(y * CS + (z & 15)) * CS + (x & 15)]


func inside(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.z >= 0 and cell.y >= 0 and cell.x < _size and cell.z < _size and cell.y < HEIGHT


# Sets one block; its section (and a neighbour's, on an edge) is made again.
# False when it's outside, unchanged, or the world isn't there yet.
func set_block(cell: Vector3i, b: int) -> bool:
	if not _ready_now or not inside(cell) or b < 0 or b >= BLOCKS.size():
		return false
	var ci := (cell.z >> 4) * _n + (cell.x >> 4)
	var col: PackedByteArray = _cols[ci]
	var at := (cell.y * CS + (cell.z & 15)) * CS + (cell.x & 15)
	if col[at] == b or col[at] == DEEP:
		return false  # unchanged, or the bottom (never dug: the world would leak)
	col[at] = b
	_cols[ci] = col  # packed arrays are values: put the changed one back
	_changed_column(ci)
	_changed_cell(cell, true)
	block_changed.emit(cell, b)
	return true


func _changed_column(ci: int) -> void:
	_packed[ci] = PackedByteArray()
	_dirty = true
	edits += 1


func _changed_cell(cell: Vector3i, urgent: bool) -> void:
	var key := Vector3i(cell.x >> 4, cell.y >> 4, cell.z >> 4)
	_mark(key, urgent)
	var l := Vector3i(cell.x & 15, cell.y & 15, cell.z & 15)
	if l.x == 0: _mark(key + Vector3i(-1, 0, 0), urgent)
	if l.x == 15: _mark(key + Vector3i(1, 0, 0), urgent)
	if l.y == 0: _mark(key + Vector3i(0, -1, 0), urgent)
	if l.y == 15: _mark(key + Vector3i(0, 1, 0), urgent)
	if l.z == 0: _mark(key + Vector3i(0, 0, -1), urgent)
	if l.z == 15: _mark(key + Vector3i(0, 0, 1), urgent)


func _block_command(request: Dictionary) -> Dictionary:
	if _land == null or not _ready_now:
		return {"ok": false, "error": "the Stackwild world isn't open (stackwild_do act toggle)"}
	var cell = _cell_from(request.get("position"))
	if cell == null:
		return {"ok": false, "error": "\"position\" must be [x, y, z], whole numbers"}
	if request.has("block"):
		var b := _block_id(request["block"])
		if b < 0 or b == DEEP:
			return {"ok": false, "error": "\"block\" must be air or one of %s" % ", ".join(_placeable_ids())}
		if not inside(cell):
			return {"ok": false, "error": "outside the world: x and z 0 to %d, y 0 to %d" % [_size - 1, HEIGHT - 1]}
		if block_at(cell.x, cell.y, cell.z) == DEEP:
			return {"ok": false, "error": "deepstone, the bottom of the world, can't be changed"}
		set_block(cell, b)
	return {"ok": true, "position": [cell.x, cell.y, cell.z], "block": BLOCKS[block_at(cell.x, cell.y, cell.z)]["id"]}


func _fill_command(request: Dictionary) -> Dictionary:
	if _land == null or not _ready_now:
		return {"ok": false, "error": "the Stackwild world isn't open (stackwild_do act toggle)"}
	var a = _cell_from(request.get("from"))
	var c = _cell_from(request.get("to"))
	if a == null or c == null:
		return {"ok": false, "error": "\"from\" and \"to\" must be [x, y, z], whole numbers"}
	var b := _block_id(request.get("block"))
	if b < 0 or b == DEEP:
		return {"ok": false, "error": "\"block\" must be air or one of %s" % ", ".join(_placeable_ids())}
	var lo := Vector3i(clampi(mini(a.x, c.x), 0, _size - 1), clampi(mini(a.y, c.y), 0, HEIGHT - 1), clampi(mini(a.z, c.z), 0, _size - 1))
	var hi := Vector3i(clampi(maxi(a.x, c.x), 0, _size - 1), clampi(maxi(a.y, c.y), 0, HEIGHT - 1), clampi(maxi(a.z, c.z), 0, _size - 1))
	var count := (hi.x - lo.x + 1) * (hi.y - lo.y + 1) * (hi.z - lo.z + 1)
	if count > MAX_FILL:
		return {"ok": false, "error": "that's %d blocks; at most %d at a time" % [count, MAX_FILL]}
	var changed := 0
	# A column at a time: each one copied once, changed, put back.
	for cz in range(lo.z >> 4, (hi.z >> 4) + 1):
		for cx in range(lo.x >> 4, (hi.x >> 4) + 1):
			var ci := cz * _n + cx
			var col: PackedByteArray = _cols[ci]
			var here := 0
			for y in range(lo.y, hi.y + 1):
				for z in range(maxi(lo.z, cz * CS), mini(hi.z, cz * CS + 15) + 1):
					for x in range(maxi(lo.x, cx * CS), mini(hi.x, cx * CS + 15) + 1):
						var at := (y * CS + (z & 15)) * CS + (x & 15)
						if col[at] != b and col[at] != DEEP:
							col[at] = b
							here += 1
			if here > 0:
				_cols[ci] = col
				_changed_column(ci)
				changed += here
	if changed > 0:
		for sz in range(lo.z >> 4, (hi.z >> 4) + 1):
			for sy in range(lo.y >> 4, (hi.y >> 4) + 1):
				for sx in range(lo.x >> 4, (hi.x >> 4) + 1):
					_mark(Vector3i(sx, sy, sz), true)
		# The sections touching the box's faces show new sides too.
		for cell in [lo, hi]:
			_changed_cell(cell, true)
		for cell in [Vector3i(lo.x, lo.y, hi.z), Vector3i(hi.x, hi.y, lo.z), Vector3i(lo.x, hi.y, lo.z), Vector3i(hi.x, lo.y, hi.z)]:
			_changed_cell(cell, true)
		_mark_box_edges(lo, hi)
		block_changed.emit(lo, b)
	return {"ok": true, "changed": changed, "from": [lo.x, lo.y, lo.z], "to": [hi.x, hi.y, hi.z], "block": BLOCKS[b]["id"]}


# Every section next to the box's faces, for a fill bigger than a section.
func _mark_box_edges(lo: Vector3i, hi: Vector3i) -> void:
	var slo := Vector3i(lo.x >> 4, lo.y >> 4, lo.z >> 4) - Vector3i.ONE
	var shi := Vector3i(hi.x >> 4, hi.y >> 4, hi.z >> 4) + Vector3i.ONE
	for sz in range(slo.z, shi.z + 1):
		for sy in range(slo.y, shi.y + 1):
			for sx in range(slo.x, shi.x + 1):
				var k := Vector3i(sx, sy, sz)
				# Only those whose blocks touch the box (one block out).
				var b0 := k * CS
				var b1 := b0 + Vector3i(15, 15, 15)
				if b1.x >= lo.x - 1 and b0.x <= hi.x + 1 and b1.y >= lo.y - 1 and b0.y <= hi.y + 1 and b1.z >= lo.z - 1 and b0.z <= hi.z + 1:
					_mark(k, true)


func _cell_from(value):
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return null
	for v in value:
		if typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
			return null
	return Vector3i(floori(value[0]), floori(value[1]), floori(value[2]))


# --- Making the world (worker threads) ---------------------------------------------

func _new_command(request: Dictionary) -> Dictionary:
	if request.has("size"):
		if not request["size"] in SIZES:
			return {"ok": false, "error": "\"size\" must be small, medium or large"}
		settings["size"] = request["size"]
		_save_settings()
	var new_seed := randi() % 1000000
	if request.has("seed"):
		if typeof(request["seed"]) not in [TYPE_INT, TYPE_FLOAT]:
			return {"ok": false, "error": "\"seed\" must be a number"}
		new_seed = int(request["seed"])
	var problem := _enter()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	if (_ready_now or FileAccess.file_exists(_world_path())) and request.get("replace") != true:
		return {"ok": false, "error": "a world is there; give replace true to make a new one (the old one is lost)"}
	_new_world(new_seed, SIZES[settings["size"]])
	if _panel_exists(PANEL):
		_build()
	return {"ok": true, "seed": world_seed, "size": _size}


func _world_path() -> String:
	return _lib.world_file(SAVE_FILE) if _lib else ""


func _clear_world() -> void:
	_wait_jobs()
	_world_id += 1
	for k in _sections:
		var mi: MeshInstance3D = _sections[k]
		if is_instance_valid(mi):
			mi.queue_free()
	_sections.clear()
	_tris.clear()
	_queue.clear()
	_urgent.clear()
	_queued.clear()
	_busy.clear()
	_again.clear()
	_gen_queue.clear()
	_cols.clear()
	_packed.clear()
	_ready_now = false
	_meshed = 0
	_hit = {}


func _new_world(new_seed: int, across: int) -> void:
	_clear_world()
	world_seed = new_seed
	_n = across
	_size = _n * CS
	_cols.resize(_n * _n)
	_packed.resize(_n * _n)
	for i in _cols.size():
		_cols[i] = PackedByteArray()
		_packed[i] = PackedByteArray()
	counts = {}
	edits = 0
	_start_at = null
	_dirty = true
	_gen_left = _n * _n
	var middle := Vector2(_n / 2.0 - 0.5, _n / 2.0 - 0.5)
	for cz in _n:
		for cx in _n:
			_gen_queue.append([cx, cz])
	_gen_queue.sort_custom(func(a, b): return Vector2(a[0], a[1]).distance_squared_to(middle) > Vector2(b[0], b[1]).distance_squared_to(middle))
	_place_water()
	set_process(true)


func _wait_jobs() -> void:
	for j in _jobs:
		WorkerThreadPool.wait_for_task_completion(j["task"])
	_jobs.clear()


func _start_jobs() -> void:
	while _jobs.size() < MAX_JOBS:
		var job := {}
		if not _gen_queue.is_empty():
			var at: Array = _gen_queue.pop_back()
			job = {"kind": "gen", "cx": at[0], "cz": at[1], "seed": world_seed, "size": _size, "world": _world_id, "out": PackedByteArray()}
			_jobs.append({"task": WorkerThreadPool.add_task(_gen_job.bind(job), false, "stackwild land"), "job": job})
			continue
		if not _ready_now:
			return
		var key = null
		if not _urgent.is_empty():
			key = _urgent.pop_front()
		elif not _queue.is_empty():
			key = _queue.pop_back()
		else:
			return
		_queued.erase(key)
		var cols := []
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				cols.append(_column(key.x + dx, key.z + dz))
		job = {"kind": "mesh", "key": key, "cols": cols, "sy": key.y, "world": _world_id, "out": {}}
		_busy[key] = true
		_jobs.append({"task": WorkerThreadPool.add_task(_mesh_job.bind(job), false, "stackwild mesh"), "job": job})


func _column(cx: int, cz: int) -> PackedByteArray:
	if cx < 0 or cz < 0 or cx >= _n or cz >= _n:
		return PackedByteArray()
	return _cols[cz * _n + cx]


func _collect_jobs() -> void:
	var applied := 0
	var i := 0
	while i < _jobs.size():
		var j: Dictionary = _jobs[i]
		if not WorkerThreadPool.is_task_completed(j["task"]) or applied >= 4:
			i += 1
			continue
		WorkerThreadPool.wait_for_task_completion(j["task"])
		_jobs.remove_at(i)
		var job: Dictionary = j["job"]
		if job["world"] != _world_id:
			continue
		applied += 1
		if job["kind"] == "gen":
			_cols[job["cz"] * _n + job["cx"]] = job["out"]
			_gen_left -= 1
			if _gen_left == 0:
				_land_made()
		else:
			_busy.erase(job["key"])
			_set_section(job["key"], job["out"])
			if _again.has(job["key"]):
				_again.erase(job["key"])
				_mark(job["key"], true)
			elif _queue.is_empty() and _urgent.is_empty() and _busy.is_empty() and _shown(PANEL):
				_build()  # its "still building" line goes


func _mark(key: Vector3i, urgent: bool) -> void:
	if key.x < 0 or key.z < 0 or key.y < 0 or key.x >= _n or key.z >= _n or key.y >= SECTIONS:
		return
	if _busy.has(key):
		_again[key] = true
		return
	if _queued.has(key):
		if urgent and not key in _urgent:
			_queue.erase(key)
			_urgent.append(key)
		return
	_queued[key] = true
	if urgent:
		_urgent.append(key)
	else:
		_queue.append(key)
	set_process(true)


# Every column made: find where to stand, then mesh, nearest first.
func _land_made() -> void:
	_ready_now = true
	_spawn = _find_spawn()
	var at: Vector3 = _start_at if _start_at != null else _spawn
	_place_land(at)
	_queue_all(at)
	if _panel_exists(PANEL):
		_build()
	world_ready.emit()


func _queue_all(near: Vector3) -> void:
	var keys := []
	for cz in _n:
		for sy in SECTIONS:
			for cx in _n:
				keys.append(Vector3i(cx, sy, cz))
	var c := Vector3(near.x / CS - 0.5, near.y / CS - 0.5, near.z / CS - 0.5)
	keys.sort_custom(func(a, b): return Vector3(a).distance_squared_to(c) > Vector3(b).distance_squared_to(c))
	for k in keys:
		_queued[k] = true
		_queue.append(k)


func _find_spawn() -> Vector3:
	var mid := _size / 2
	for r in range(0, mid - 2):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var top := _top_at(mid + dx, mid + dz)
				var b := block_at(mid + dx, top - 1, mid + dz)
				if top > SEA + 1 and b != CANOPY and b != LOG:
					return Vector3(mid + dx + 0.5, top, mid + dz + 0.5)
	return Vector3(mid + 0.5, _top_at(mid, mid), mid + 0.5)


# The height you'd stand at on this column: one above its highest block.
func _top_at(x: int, z: int) -> int:
	for y in range(HEIGHT - 1, -1, -1):
		if block_at(x, y, z) != AIR:
			return y + 1
	return 0


# One column of the land, on a worker: the hills, what they're made of,
# ore, and the trees (also the parts of trees rooted next door).
func _gen_job(job: Dictionary) -> void:
	var s: int = job["seed"]
	var cx: int = job["cx"]
	var cz: int = job["cz"]
	var size: int = job["size"]
	var noise := _noise(s, 0.007, 4)
	var hills := _noise(s + 7, 0.003, 2)
	var data := PackedByteArray()
	data.resize(COL_BYTES)
	var heights := PackedInt32Array()
	heights.resize(CS * CS)
	for lz in CS:
		for lx in CS:
			var h := _height(noise, hills, cx * CS + lx, cz * CS + lz)
			var at := lz * CS + lx
			heights[at] = h
			var top := TURF
			var under := LOAM
			if h <= SEA + 1:
				top = SAND
				under = SAND
			elif h >= SNOW_LINE:
				top = SNOW
				under = SLATE
			data[at] = DEEP
			for y in range(1, maxi(1, h - 3)):
				data[y * CS * CS + at] = SLATE
			for y in range(maxi(1, h - 3), h):
				data[y * CS * CS + at] = under
			data[h * CS * CS + at] = top
	# Ore: a few small veins in the slate.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([s, cx, cz])
	for v in 7:
		var lx := rng.randi_range(1, 14)
		var lz := rng.randi_range(1, 14)
		var ore := SKYSHARD if rng.randf() < 0.3 else EMBER
		var deepest := heights[lz * CS + lx] - 5
		if deepest < 3:
			continue
		var y := rng.randi_range(2, mini(deepest, 16 if ore == SKYSHARD else 30))
		for k in rng.randi_range(3, 7):
			var p := Vector3i(lx + rng.randi_range(-1, 1), y + rng.randi_range(-1, 1), lz + rng.randi_range(-1, 1))
			if p.x >= 0 and p.x < CS and p.z >= 0 and p.z < CS and p.y > 0:
				var i := (p.y * CS + p.z) * CS + p.x
				if data[i] == SLATE:
					data[i] = ore
	# Trees, from a hash of where they stand, so each column agrees with its neighbours.
	for tz in range(-2, CS + 2):
		for tx in range(-2, CS + 2):
			var wx := cx * CS + tx
			var wz := cz * CS + tz
			if wx < 2 or wz < 2 or wx >= size - 2 or wz >= size - 2 or _hash01(s, wx, wz, 1) > 0.011:
				continue
			var inside_col := tx >= 0 and tx < CS and tz >= 0 and tz < CS
			var h := heights[tz * CS + tx] if inside_col else _height(noise, hills, wx, wz)
			if h <= SEA + 1 or h >= SNOW_LINE - 2:
				continue
			var trunk := 4 + int(_hash01(s, wx, wz, 2) * 2.0)
			for dy in range(1, trunk + 1):
				_put(data, tx, h + dy, tz, LOG, false)
			for dy in range(trunk - 1, trunk + 3):
				var r := 2 if dy < trunk + 1 else 1
				for oz in range(-r, r + 1):
					for ox in range(-r, r + 1):
						if r == 2 and absi(ox) == 2 and absi(oz) == 2:
							continue  # round the corners
						if dy == trunk + 2 and absi(ox) + absi(oz) > 1:
							continue
						_put(data, tx + ox, h + dy, tz + oz, CANOPY, true)
	job["out"] = data


func _put(data: PackedByteArray, lx: int, y: int, lz: int, b: int, only_air: bool) -> void:
	if lx < 0 or lz < 0 or lx >= CS or lz >= CS or y <= 0 or y >= HEIGHT:
		return
	var i := (y * CS + lz) * CS + lx
	if not only_air or data[i] == AIR:
		data[i] = b


func _noise(s: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	return n


func _height(noise: FastNoiseLite, hills: FastNoiseLite, x: int, z: int) -> int:
	var m := hills.get_noise_2d(x, z) * 0.5 + 0.5
	var n := noise.get_noise_2d(x, z)
	return clampi(int(17.0 + n * (8.0 + 44.0 * m * m)), 3, HEIGHT - 12)


func _hash01(s: int, x: int, z: int, salt: int) -> float:
	var h: int = s * 73856093 ^ x * 19349663 ^ z * 83492791 ^ salt * 2654435761
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0xFFFFFF)


# One section's mesh, on a worker: the section with a block of its
# neighbours all round, then greedy quads.
func _mesh_job(job: Dictionary) -> void:
	var cols: Array = job["cols"]
	var mid: PackedByteArray = cols[4]
	var sy: int = job["sy"]
	if mid.is_empty() or mid.slice(sy * 4096, sy * 4096 + 4096).count(AIR) == 4096:
		job["out"] = {}
		return
	job["out"] = mesh_pad(_pad_for(cols, sy))


func _pad_for(cols: Array, sy: int) -> PackedByteArray:
	var pad := PackedByteArray()
	for py in PAD:
		var y := sy * CS + py - 1
		if y < 0:
			pad.append_array(_deep_layer)
			continue
		if y >= HEIGHT:
			pad.append_array(_air_layer)
			continue
		for pz in PAD:
			var lz := pz - 1
			var row := 1
			if lz < 0:
				lz = 15
				row = 0
			elif lz > 15:
				lz = 0
				row = 2
			var west: PackedByteArray = cols[row * 3]
			var here: PackedByteArray = cols[row * 3 + 1]
			var east: PackedByteArray = cols[row * 3 + 2]
			var at := (y * CS + lz) * CS
			pad.append(west[at + 15] if not west.is_empty() else AIR)
			if here.is_empty():
				pad.append_array(_air_row)
			else:
				pad.append_array(here.slice(at, at + CS))
			pad.append(east[at] if not east.is_empty() else AIR)
	return pad


# Greedy meshing of a padded 18^3 block (PAD): for each of the six sides,
# each slice gets a mask of the faces showing there, and runs of the same
# block are grown into rectangles, one quad each. UVs are in blocks (the
# shader repeats the tile with fract), the tile goes in UV2, the side's
# shade in the colour.
func mesh_pad(pad: PackedByteArray) -> Dictionary:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tiles := PackedVector2Array()
	var colors := PackedColorArray()
	var index := PackedInt32Array()
	var strides := [1, PAD * PAD, PAD]  # x, y, z
	var base := PAD * PAD + PAD + 1
	var mask := PackedInt32Array()
	mask.resize(CS * CS)
	for d in 3:
		var u := (d + 1) % 3
		var v := (d + 2) % 3
		var sd: int = strides[d]
		var su: int = strides[u]
		var sv: int = strides[v]
		for side in [1, -1]:
			var step: int = side * sd
			for s in CS:
				var any := false
				for j in CS:
					var row := base + s * sd + j * sv
					for i in CS:
						var at := row + i * su
						var b := pad[at]
						if b != AIR and pad[at + step] == AIR:
							mask[j * CS + i] = b
							any = true
						else:
							mask[j * CS + i] = 0
				if not any:
					continue
				for j in CS:
					var i := 0
					while i < CS:
						var b := mask[j * CS + i]
						if b == 0:
							i += 1
							continue
						var w := 1
						while i + w < CS and mask[j * CS + i + w] == b:
							w += 1
						var h := 1
						var grow := true
						while grow and j + h < CS:
							for k in w:
								if mask[(j + h) * CS + i + k] != b:
									grow = false
									break
							if grow:
								h += 1
						for jj in h:
							for k in w:
								mask[(j + jj) * CS + i + k] = 0
						# The quad: in the face's plane, w along u, h along v.
						var p := Vector3.ZERO
						p[d] = s + (1 if side > 0 else 0)
						p[u] = i
						p[v] = j
						var du := Vector3.ZERO
						du[u] = w
						var dv := Vector3.ZERO
						dv[v] = h
						var n := verts.size()
						var corners := [p, p + dv, p + du + dv, p + du] if side > 0 else [p, p + du, p + du + dv, p + dv]
						var tile: int
						var shade: float
						if d == 1:
							tile = _tile_top[b] if side > 0 else _tile_bottom[b]
							shade = SHADE_TOP if side > 0 else SHADE_BOTTOM
						else:
							tile = _tile_side[b]
							shade = SHADE_X if d == 0 else SHADE_Z
						if _glow[b] == 1:
							shade = 1.0
						var t := Vector2(tile % TILE_COLS, tile / TILE_COLS)
						var col := Color(shade, shade, shade)
						for q: Vector3 in corners:
							verts.append(q)
							if d == 1:
								uvs.append(Vector2(q.x, q.z))
							elif d == 0:
								uvs.append(Vector2(q.z, -q.y))
							else:
								uvs.append(Vector2(q.x, -q.y))
							tiles.append(t)
							colors.append(col)
						index.append_array([n, n + 1, n + 2, n, n + 2, n + 3])
						i += w
	if verts.is_empty():
		return {}
	return {"verts": verts, "uvs": uvs, "tiles": tiles, "colors": colors, "index": index}


func _arrays_of(out: Dictionary) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out["verts"]
	arrays[Mesh.ARRAY_TEX_UV] = out["uvs"]
	arrays[Mesh.ARRAY_TEX_UV2] = out["tiles"]
	arrays[Mesh.ARRAY_COLOR] = out["colors"]
	arrays[Mesh.ARRAY_INDEX] = out["index"]
	return arrays


func _set_section(key: Vector3i, out: Dictionary) -> void:
	_meshed += 1
	var mi: MeshInstance3D = _sections.get(key)
	if out.is_empty():
		if mi != null:
			mi.queue_free()
			_sections.erase(key)
			_tris.erase(key)
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays_of(out))
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "s_%d_%d_%d" % [key.x, key.y, key.z]
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(key) * CS
		mi.visibility_range_end = settings["view"] + CS
		_land.add_child(mi)
		_sections[key] = mi
	mi.mesh = mesh
	_tris[key] = (out["index"] as PackedInt32Array).size() / 3


func _apply_view() -> void:
	for k in _sections:
		(_sections[k] as MeshInstance3D).visibility_range_end = settings["view"] + CS
	var env = _swapped.get("environment")
	if env != null and is_instance_valid(env[0]):
		var e: Environment = env[0].environment
		e.fog_depth_begin = settings["view"] * 0.55
		e.fog_depth_end = settings["view"]


# --- The look: texture sheet and material ------------------------------------------

func _make_look() -> void:
	if _mat != null:
		return
	var img := Image.create(TILE_COLS * TILE_PX, TILE_ROWS * TILE_PX, false, Image.FORMAT_RGB8)
	for t in TILE_COLS * TILE_ROWS:
		_paint(img, t, (t % TILE_COLS) * TILE_PX, (t / TILE_COLS) * TILE_PX)
	_sheet = ImageTexture.create_from_image(img)
	var shader := Shader.new()
	shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("sheet", _sheet)
	_mat.set_shader_parameter("tiles", Vector2(TILE_COLS, TILE_ROWS))


# Each 16-pixel tile, drawn from a colour, some noise and a pattern.
func _paint(img: Image, t: int, x0: int, y0: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + t * 977
	var green := Color(0.36, 0.6, 0.24)
	var loam := Color(0.47, 0.33, 0.21)
	var slate := Color(0.48, 0.5, 0.54)
	var lip := PackedInt32Array()  # turf's side: how far the green hangs down
	for px in TILE_PX:
		lip.append(3 + rng.randi_range(0, 2))
	for py in TILE_PX:
		for px in TILE_PX:
			var k := rng.randf_range(0.86, 1.12)
			var c := Color.MAGENTA
			match t:
				0:  # turf top
					c = green * k
				1:  # turf side
					c = (green if py < lip[px] else loam) * k
				2:  # loam
					c = loam * k * (0.85 if rng.randf() < 0.12 else 1.0)
				3:  # slate: long flat streaks
					c = slate * k * (0.85 if (py + px / 6) % 5 == 0 else 1.0)
				4:  # fieldstone: rounded stones in mortar
					var sx := (px + (3 if (py / 5) % 2 == 1 else 0)) % 6
					var edge := py % 5 == 4 or sx == 5
					c = Color(0.36, 0.36, 0.37) * k if edge else Color(0.6, 0.6, 0.6) * k * (1.05 if sx < 2 and py % 5 < 2 else 1.0)
				5:  # sand
					c = Color(0.86, 0.8, 0.56) * k
				6:  # bark
					c = Color(0.4, 0.28, 0.16) * k * (0.75 if (px + rng.randi_range(0, 1)) % 4 == 0 else 1.0)
				7:  # log end: rings
					var r := Vector2(px - 7.5, py - 7.5).length()
					c = Color(0.4, 0.28, 0.16) * k if r > 6.8 else Color(0.72, 0.56, 0.34) * k * (0.82 if int(r) % 2 == 0 else 1.0)
				8:  # canopy
					c = Color(0.2, 0.44, 0.17) * k * (0.6 if rng.randf() < 0.2 else 1.0)
				9:  # boards
					var plank := py / 4
					var joint := (px + plank * 5) % 16 == 0
					c = Color(0.7, 0.53, 0.32) * k * (0.62 if py % 4 == 3 or joint else 1.0)
				10:  # brick
					var course := py / 4
					var bx := (px + (4 if course % 2 == 1 else 0)) % 8
					c = Color(0.78, 0.76, 0.7) * k if py % 4 == 3 or bx == 7 else Color(0.64, 0.3, 0.23) * k
				11:  # snow
					c = Color(0.93, 0.95, 1.0) * rng.randf_range(0.95, 1.03)
				12:  # ember ore
					c = slate * k
					if rng.randf() < 0.16:
						c = Color(0.95, 0.5, 0.15) * k
				13:  # skyshard
					c = slate * k
					if rng.randf() < 0.14:
						c = Color(0.35, 0.85, 1.0) * k
				14:  # lamp: a glowing pane in a frame
					var border := px == 0 or py == 0 or px == 15 or py == 15
					var bars := px == 8 or py == 8
					c = Color(0.35, 0.28, 0.2) if border else (Color(0.95, 0.78, 0.4) if bars else Color(1.0, 0.92, 0.6) * rng.randf_range(0.95, 1.05))
				15, 16, 17, 18, 19, 20:  # felt: a soft weave
					var felts := [Color(0.75, 0.16, 0.14), Color(0.17, 0.3, 0.72), Color(0.92, 0.78, 0.18),
						Color(0.24, 0.58, 0.2), Color(0.92, 0.92, 0.9), Color(0.13, 0.13, 0.15)]
					c = felts[t - 15] * rng.randf_range(0.93, 1.05) * (0.92 if (px + py) % 2 == 0 else 1.0)
				21:  # deepstone
					c = Color(0.16, 0.16, 0.18) * k * (0.6 if rng.randf() < 0.2 else 1.0)
				22:  # rushes: woven reeds
					var weave := (px / 4 + py / 4) % 2 == 0
					c = (Color(0.66, 0.62, 0.32) if weave else Color(0.54, 0.5, 0.25)) * k * (0.8 if (px if weave else py) % 4 == 0 else 1.0)
				_:
					c = Color(0.5, 0.5, 0.5)
			img.set_pixel(x0 + px, y0 + py, Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1)))


# --- The stage: sky, land, water ---------------------------------------------------

func _stage_on() -> void:
	if _land != null:
		return
	_make_look()
	_want_sounds()
	var scene := ctx["world"].get_parent() as Node if ctx.get("world") else null
	if scene:
		var env := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if env:
			_swapped["environment"] = [env, env.environment]
			var day := Environment.new()
			day.background_mode = Environment.BG_COLOR
			day.background_color = Color(0.55, 0.75, 0.95)
			day.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			day.ambient_light_color = Color(1, 1, 1)
			day.fog_enabled = true
			day.fog_mode = Environment.FOG_MODE_DEPTH
			day.fog_light_color = Color(0.62, 0.79, 0.96)
			day.fog_density = 1.0
			day.fog_sky_affect = 0.0
			day.fog_depth_curve = 1.0
			day.fog_depth_begin = settings["view"] * 0.55
			day.fog_depth_end = settings["view"]
			env.environment = day
		var ground := scene.get_node_or_null("Floor") as Node3D
		if ground:
			_swapped["floor"] = [ground, ground.visible]
			ground.visible = false
	_land = Node3D.new()
	_land.name = "stackwild_land"
	add_child(_land)  # its own, not World's: the blocks are saved by this module
	_save_path = _world_path()
	if not _load_world():
		_new_world(randi() % 1000000, SIZES[settings["size"]])
	set_process(true)


func _stage_off() -> void:
	_wait_jobs()
	_world_id += 1
	if _swapped.has("environment") and is_instance_valid(_swapped["environment"][0]):
		_swapped["environment"][0].environment = _swapped["environment"][1]
	if _swapped.has("floor") and is_instance_valid(_swapped["floor"][0]):
		_swapped["floor"][0].visible = _swapped["floor"][1]
	_swapped.clear()
	_hold_gear(false)
	if _land != null and is_instance_valid(_land):
		_land.get_parent().remove_child(_land)
		_land.queue_free()
	_land = null
	_water = null
	_outline = null
	_crack = null
	_beam = null
	_sections.clear()
	_tris.clear()
	_queue.clear()
	_urgent.clear()
	_queued.clear()
	_busy.clear()
	_again.clear()
	_gen_queue.clear()
	_cols.clear()
	_packed.clear()
	_ready_now = false
	_n = 0
	_size = 0
	_hit = {}
	_save_path = ""
	set_process(false)


func _place_water() -> void:
	if _land == null:
		return
	if _water == null:
		_water = MeshInstance3D.new()
		_water.name = "water"
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.2, 0.45, 0.8, 0.6)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_water.material_override = m
		_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_land.add_child(_water)
	var plane := PlaneMesh.new()
	plane.size = Vector2(_size, _size)
	_water.mesh = plane
	_water.position = Vector3(_size / 2.0, SEA + 0.85, _size / 2.0)


# The land is moved (never turned) so the spot `at` (land space, feet) is
# where you stand now.
func _place_land(at: Vector3) -> void:
	var cam := ctx.get("camera") as Node3D
	var floor_y := 0.0
	var head := Vector3.ZERO
	if cam != null and is_instance_valid(cam):
		head = cam.global_position
		var origin := cam.get_parent() as Node3D
		if origin:
			floor_y = origin.global_position.y
	_land.global_position = Vector3(head.x - at.x, floor_y - at.y, head.z - at.z)
	_feet = at.y
	_vy = 0.0
	_last_xz = Vector2.INF


func _process(delta: float) -> void:
	if _land == null:
		set_process(false)
		return
	_collect_jobs()
	_start_jobs()
	if _ready_now:
		_body(delta)
		if running and not _held:
			_hands(delta)
		_autosave_t += delta
		if _dirty and _autosave_t >= AUTOSAVE:
			_save_world()


# --- You: walking, stepping, falling ---------------------------------------------

func _solid(x: int, y: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= _size or z >= _size:
		return true  # the world's edge is a wall
	return block_at(x, y, z) != AIR


# Walls stop you: blocks at body height (above a walkable step) in your way.
func _blocked(xz: Vector2, head_h: float) -> bool:
	var y0 := floori(_feet + STEP_UP)
	var y1 := floori(_feet + head_h + 0.1)
	for x in range(floori(xz.x - BODY_R), floori(xz.x + BODY_R) + 1):
		for z in range(floori(xz.y - BODY_R), floori(xz.y + BODY_R) + 1):
			for y in range(y0, y1 + 1):
				if _solid(x, y, z):
					return true
	return false


# The top of the highest block under you no higher than limit.
func _ground_under(xz: Vector2, limit: float) -> float:
	var best := -100.0
	for x in range(floori(xz.x - BODY_R), floori(xz.x + BODY_R) + 1):
		for z in range(floori(xz.y - BODY_R), floori(xz.y + BODY_R) + 1):
			for y in range(mini(floori(limit) - 1, HEIGHT - 1), -1, -1):
				if block_at(x, y, z) != AIR:
					best = maxf(best, y + 1.0)
					break
	return best


func _body(delta: float) -> void:
	var cam := ctx.get("camera") as Node3D
	if cam == null:
		return
	var origin := cam.get_parent() as Node3D
	if origin == null:
		return
	var head := _land.to_local(cam.global_position)
	var head_h := clampf(cam.position.y, 0.6, 2.2)  # how tall you stand right now
	var xz := Vector2(head.x, head.z)
	if _last_xz == Vector2.INF:
		_last_xz = xz
	if _blocked(xz, head_h):
		var fix := _last_xz
		if not _blocked(Vector2(xz.x, _last_xz.y), head_h):
			fix = Vector2(xz.x, _last_xz.y)
		elif not _blocked(Vector2(_last_xz.x, xz.y), head_h):
			fix = Vector2(_last_xz.x, xz.y)
		if _blocked(fix, head_h):
			fix = xz  # already inside blocks (built round you): don't fight it
		var shift := fix - xz
		origin.global_position += Vector3(shift.x, 0.0, shift.y)
		xz = fix
	_last_xz = xz
	var ground := _ground_under(xz, _feet + STEP_UP)
	if _vy > 0.0 or ground < _feet - 0.01:
		_vy -= GRAVITY * delta
		var next := _feet + _vy * delta
		if _vy > 0.0:
			var top := floori(next + head_h + 0.1)
			for x in range(floori(xz.x - BODY_R), floori(xz.x + BODY_R) + 1):
				for z in range(floori(xz.y - BODY_R), floori(xz.y + BODY_R) + 1):
					if _solid(x, top, z) and x >= 0 and z >= 0 and x < _size and z < _size:
						_vy = 0.0
						next = _feet
		if next <= ground:
			next = ground
			_vy = 0.0
			_on_ground = true
		else:
			_on_ground = false
		_feet = next
	else:
		_feet = move_toward(_feet, ground, 6.0 * delta) if ground > _feet else ground
		_vy = 0.0
		_on_ground = true
	if _feet < -30.0:
		_place_land(_spawn)  # fell out of the world: back to the start
		return
	origin.global_position.y = _land.global_position.y + _feet


# --- Your hands: pointing, digging, placing ---------------------------------------

# Walks the ray block by block (land space). {"cell", "normal", "dist"}, or
# {} when nothing solid is within reach.
func raycast(from: Vector3, dir: Vector3, reach: float) -> Dictionary:
	if dir.length() < 0.0001:
		return {}
	dir = dir.normalized()
	var cell := Vector3i(floori(from.x), floori(from.y), floori(from.z))
	if block_at(cell.x, cell.y, cell.z) != AIR and inside(cell):
		return {"cell": cell, "normal": Vector3i.ZERO, "dist": 0.0}
	var step := Vector3i.ZERO
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for a in 3:
		if dir[a] > 0.0:
			step[a] = 1
			t_max[a] = (cell[a] + 1 - from[a]) / dir[a]
			t_delta[a] = 1.0 / dir[a]
		elif dir[a] < 0.0:
			step[a] = -1
			t_max[a] = (from[a] - cell[a]) / -dir[a]
			t_delta[a] = -1.0 / dir[a]
	while true:
		var a := 0
		if t_max.y < t_max[a]:
			a = 1
		if t_max.z < t_max[a]:
			a = 2
		var t := t_max[a]
		if t > reach:
			return {}
		cell[a] += step[a]
		t_max[a] += t_delta[a]
		if cell.y < 0:
			return {}
		if block_at(cell.x, cell.y, cell.z) != AIR:
			var normal := Vector3i.ZERO
			normal[a] = -step[a]
			return {"cell": cell, "normal": normal, "dist": t}
	return {}


func _aim() -> void:
	var hand := ctx.get("right") as Node3D
	if hand == null:
		_hit = {}
		return
	var from := _land.to_local(hand.global_position)
	var dir := -hand.global_transform.basis.z
	_hit = raycast(from, dir, REACH)
	_show_aim(true, from, dir)


func _hands(delta: float) -> void:
	_aim()
	if _trigger and not _hit.is_empty():
		var cell: Vector3i = _hit["cell"]
		if _dig_cell != cell:
			_dig_cell = cell
			_dig_t = 0.0
		var hard: float = BLOCKS[block_at(cell.x, cell.y, cell.z)]["hard"]
		_dig_t += delta
		if settings["mode"] == "build":
			if _dig_t >= REPEAT:
				_dig_now()
		elif hard >= 0.0:
			var need := maxf(0.15, hard * GATHER_DIG)
			if int(_dig_t * 4.0) != int((_dig_t - delta) * 4.0):
				_sound(BLOCKS[block_at(cell.x, cell.y, cell.z)]["sound"], Vector3(cell) + Vector3.ONE * 0.5, 0.5)
				if _controls:
					_controls.call("pulse", "right", 0.15, 0.03)
			if _dig_t >= need:
				_dig_now()
	elif _trigger:
		_dig_cell = null
		_dig_t = 0.0
	if _place_held:
		_place_t -= delta
		if _place_t <= 0.0:
			_place_t = REPEAT
			_place_now()
	_show_crack()


# Digs what you point at (Build: now; Gather: called once digging's done).
func _dig_now() -> void:
	if not _ready_now:
		return
	if _hit.is_empty():
		_aim()
	if _hit.is_empty():
		return
	var cell: Vector3i = _hit["cell"]
	var b := block_at(cell.x, cell.y, cell.z)
	if b == AIR or BLOCKS[b]["hard"] < 0.0 or not inside(cell):
		_sound("deny", null, 0.5)
		return
	set_block(cell, AIR)
	if settings["mode"] == "gather":
		counts[BLOCKS[b]["id"]] = int(counts.get(BLOCKS[b]["id"], 0)) + 1
		if int(counts[BLOCKS[b]["id"]]) == 1 and int(counts.get(BLOCKS[selected]["id"], 0)) == 0:
			_choose(b)  # the first block you gather goes in your hand
	_sound("break", Vector3(cell) + Vector3.ONE * 0.5, 0.8)
	if _controls:
		_controls.call("pulse", "right", 0.35, 0.05)
	_dig_cell = null
	_dig_t = 0.0
	_hit = {}
	_update_hud()


func _place_now() -> void:
	if not _ready_now:
		return
	_aim()
	if _hit.is_empty() or _hit["normal"] == Vector3i.ZERO:
		return
	var cell: Vector3i = _hit["cell"] + _hit["normal"]
	if not inside(cell) or block_at(cell.x, cell.y, cell.z) != AIR or _in_you(cell):
		_sound("deny", null, 0.4)
		return
	var key: String = BLOCKS[selected]["id"]
	if settings["mode"] == "gather":
		if int(counts.get(key, 0)) <= 0:
			_sound("deny", null, 0.4)
			return
		counts[key] = int(counts[key]) - 1
		if int(counts[key]) == 0:
			counts.erase(key)
	set_block(cell, selected)
	_sound("place", Vector3(cell) + Vector3.ONE * 0.5, 0.8)
	if _controls:
		_controls.call("pulse", "right", 0.25, 0.04)
	_update_hud()


# Would a block here be in your body?
func _in_you(cell: Vector3i) -> bool:
	var cam := ctx.get("camera") as Node3D
	if cam == null:
		return false
	var head := _land.to_local(cam.global_position)
	var top := _feet + clampf(cam.position.y, 0.6, 2.2)
	return cell.x < head.x + BODY_R and cell.x + 1 > head.x - BODY_R and cell.z < head.z + BODY_R and cell.z + 1 > head.z - BODY_R \
		and cell.y < top and cell.y + 1 > _feet


func _next_block() -> void:
	var ids := _placeable()
	if settings["mode"] == "gather":
		ids = ids.filter(func(b): return int(counts.get(BLOCKS[b]["id"], 0)) > 0)
		if ids.is_empty():
			_sound("deny", null, 0.4)
			return
	var at := ids.find(selected)
	_choose(ids[(at + 1) % ids.size()])


func _choose(b: int) -> void:
	selected = b
	_save_settings()
	_update_hud()
	if _panel_exists(PICKER):
		_build_picker()


# --- What you hold and see --------------------------------------------------------

func _hold_gear(on: bool) -> void:
	if not on:
		for node in [_hand_block, _wrist]:
			if node != null and is_instance_valid(node):
				node.queue_free()
		_hand_block = null
		_wrist = null
		for box in _hidden_boxes:
			if is_instance_valid(box):
				box.visible = true
		_hidden_boxes.clear()
		_show_aim(false)
		return
	_make_look()
	var right := ctx.get("right") as Node3D
	var left := ctx.get("left") as Node3D
	if right:
		var box := right.get_node_or_null("Mesh") as Node3D
		if box != null and box.visible:
			box.visible = false
			_hidden_boxes.append(box)
	if right and _hand_block == null:
		_hand_block = MeshInstance3D.new()
		_hand_block.name = "stackwild_block"
		_hand_block.material_override = _mat
		_hand_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hand_block.scale = Vector3.ONE * 0.07
		_hand_block.position = Vector3(-0.035, -0.06, -0.1)
		right.add_child(_hand_block)
	if left and _wrist == null:
		_wrist = Label3D.new()
		_wrist.name = "stackwild_wrist"
		_wrist.font_size = 40
		_wrist.pixel_size = 0.0009
		_wrist.outline_size = 8
		_wrist.position = Vector3(0.0, 0.06, 0.09)
		_wrist.rotation_degrees = Vector3(-50, 0, 0)
		left.add_child(_wrist)
	_update_hud()


func _update_hud() -> void:
	if _hand_block != null:
		var pad := PackedByteArray()
		pad.resize(PAD * PAD * PAD)
		pad[PAD * PAD + PAD + 1] = selected
		var out := mesh_pad(pad)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays_of(out))
		_hand_block.mesh = mesh
	if _wrist != null:
		var name_now: String = BLOCKS[selected]["name"]
		if settings["mode"] == "gather":
			_wrist.text = "%s  %d\nGather" % [name_now, int(counts.get(BLOCKS[selected]["id"], 0))]
		else:
			_wrist.text = "%s\nBuild" % name_now


# The outline round what you point at, a thin beam to it, and the cracks.
func _show_aim(on: bool, from := Vector3.ZERO, dir := Vector3.FORWARD) -> void:
	if not on or _land == null:
		for node in [_outline, _beam, _crack]:
			if node != null and is_instance_valid(node):
				node.visible = false
		return
	if _outline == null:
		_outline = MeshInstance3D.new()
		_outline.name = "outline"
		var lines := ArrayMesh.new()
		var pts := PackedVector3Array()
		var e := 0.004
		var c := [Vector3(-e, -e, -e), Vector3(1 + e, -e, -e), Vector3(1 + e, -e, 1 + e), Vector3(-e, -e, 1 + e)]
		for i in 4:
			var a: Vector3 = c[i]
			var b: Vector3 = c[(i + 1) % 4]
			var up := Vector3(0, 1 + 2 * e, 0)
			pts.append_array([a, b, a + up, b + up, a, a + up])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pts
		lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		_outline.mesh = lines
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.05, 0.05, 0.05)
		_outline.material_override = m
		_land.add_child(_outline)
		_beam = MeshInstance3D.new()
		_beam.name = "beam"
		var stick := BoxMesh.new()
		stick.size = Vector3(0.004, 0.004, 1.0)
		_beam.mesh = stick
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.albedo_color = Color(1, 1, 1, 0.35)
		_beam.material_override = bm
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_land.add_child(_beam)
		_crack = MeshInstance3D.new()
		_crack.name = "crack"
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * 1.01
		_crack.mesh = cube
		var cm := StandardMaterial3D.new()
		cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.albedo_color = Color(0, 0, 0, 0)
		_crack.material_override = cm
		_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_land.add_child(_crack)
	var length := REACH
	if not _hit.is_empty():
		var cell: Vector3i = _hit["cell"]
		_outline.position = Vector3(cell)
		_outline.visible = true
		length = _hit["dist"]
	else:
		_outline.visible = false
	_beam.visible = true
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	_beam.transform = Transform3D(basis.scaled_local(Vector3(1, 1, maxf(length, 0.01))), from + dir * length * 0.5)


func _show_crack() -> void:
	if _crack == null:
		return
	if _dig_cell == null or settings["mode"] == "build" or not _trigger:
		_crack.visible = false
		return
	var cell: Vector3i = _dig_cell
	var hard: float = BLOCKS[block_at(cell.x, cell.y, cell.z)]["hard"]
	if hard < 0.0:
		_crack.visible = false
		return
	_crack.visible = true
	_crack.position = Vector3(cell) + Vector3.ONE * 0.5
	(_crack.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, clampf(_dig_t / maxf(0.15, hard * GATHER_DIG), 0.0, 1.0) * 0.55)


# --- Saving -----------------------------------------------------------------------

func _save_command(_request: Dictionary) -> Dictionary:
	if _land == null or not _ready_now:
		return {"ok": false, "error": "the Stackwild world isn't open"}
	var problem := _save_world(true)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return {"ok": true, "file": _save_path}


# Writes the world: each column compressed (kept until it changes again).
# "" or what went wrong.
func _save_world(always := false) -> String:
	_autosave_t = 0.0
	if not _ready_now or _save_path.is_empty() or (not _dirty and not always):
		return ""
	var packed := []
	for i in _cols.size():
		if (_packed[i] as PackedByteArray).is_empty():
			_packed[i] = (_cols[i] as PackedByteArray).compress(FileAccess.COMPRESSION_ZSTD)
		packed.append(_packed[i])
	var you := _spawn
	var cam := ctx.get("camera") as Node3D
	if cam != null and _land != null:
		var head := _land.to_local(cam.global_position)
		you = Vector3(head.x, _feet, head.z)
	DirAccess.make_dir_recursive_absolute(_save_path.get_base_dir())
	var out := FileAccess.open(_save_path, FileAccess.WRITE)
	if out == null:
		return "couldn't write %s (%s)" % [_save_path, error_string(FileAccess.get_open_error())]
	out.store_var({"version": SAVE_VERSION, "seed": world_seed, "n": _n, "spawn": _spawn, "you": you, "counts": counts, "edits": edits, "cols": packed})
	out.close()
	_dirty = false
	return ""


# Opens the saved world, if there's one. False when there's none (or it's unreadable).
func _load_world() -> bool:
	if _save_path.is_empty() or not FileAccess.file_exists(_save_path):
		return false
	var f := FileAccess.open(_save_path, FileAccess.READ)
	if f == null:
		return false
	var got = f.get_var()
	f.close()
	if typeof(got) != TYPE_DICTIONARY or int(got.get("version", 0)) != SAVE_VERSION:
		push_warning("Slopitect stackwild: %s isn't a world this version reads; making a new one" % _save_path)
		return false
	var n := int(got.get("n", 0))
	var packed = got.get("cols", [])
	if n <= 0 or typeof(packed) != TYPE_ARRAY or packed.size() != n * n:
		return false
	_clear_world()
	_n = n
	_size = n * CS
	world_seed = int(got.get("seed", 0))
	for p in packed:
		var data: PackedByteArray = (p as PackedByteArray).decompress(COL_BYTES, FileAccess.COMPRESSION_ZSTD)
		if data.size() != COL_BYTES:
			_clear_world()
			return false
		_cols.append(data)
		_packed.append(p)
	counts = got.get("counts", {}) if typeof(got.get("counts")) == TYPE_DICTIONARY else {}
	edits = int(got.get("edits", 0))
	_spawn = got.get("spawn", Vector3(_size / 2.0, 30, _size / 2.0))
	_start_at = got.get("you") if got.get("you") is Vector3 else null
	_gen_left = 0
	_dirty = false
	_place_water()
	_land_made()
	return true


# --- Sounds -----------------------------------------------------------------------

func _want_sounds() -> void:
	if _sounds.is_empty() and _sounds_task < 0:
		_sounds_task = WorkerThreadPool.add_task(_make_sounds, false, "stackwild sounds")


func _make_sounds() -> void:
	var made := {}
	made["soft"] = _thud(0.12, 900.0, 0.0, 30.0)
	made["hard"] = _thud(0.1, 3200.0, 0.0, 45.0)
	made["wood"] = _thud(0.13, 1600.0, 300.0, 32.0)
	made["break"] = _thud(0.28, 2200.0, 0.0, 12.0, true)
	made["place"] = _thud(0.09, 2600.0, 190.0, 50.0)
	made["deny"] = _thud(0.12, 1200.0, 140.0, 25.0)
	_sounds_made.call_deferred(made)


func _sounds_made(made: Dictionary) -> void:
	if _sounds_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_sounds_task)
		_sounds_task = -1
	_sounds = made


# A short knock: filtered noise (crumbly for a break) and maybe a low tone.
func _thud(seconds: float, low_hz: float, tone_hz: float, decay: float, crumble := false) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(low_hz + tone_hz * 7.0 + decay * 13.0)
	var k := 1.0 - exp(-TAU * low_hz / rate)
	var low := 0.0
	for i in count:
		var t := float(i) / rate
		var n := rng.randf_range(-1.0, 1.0)
		if crumble and rng.randf() < 0.75:
			n *= 0.2
		var v := n * exp(-decay * t) + sin(TAU * tone_hz * t) * 0.6 * exp(-decay * 1.3 * t)
		v *= minf(1.0, (seconds - t) / 0.02)
		low += (v - low) * k
		data.encode_s16(i * 2, clampi(int(tanh(low * 1.5) * 28000.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


func _sound(kind: String, at, volume: float) -> void:
	if not settings["sounds"] or not _sounds.has(kind):
		return
	var stream: AudioStream = _sounds[kind]
	var pitch := randf_range(0.9, 1.1)
	if _audio and is_instance_valid(_audio):
		if at is Vector3 and _land != null:
			_audio.call("play_at", stream, _land.to_global(at), {"bus": "effects", "volume": volume, "pitch": pitch})
		else:
			_audio.call("play_2d", stream, "effects", volume, pitch)
		return
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream
	p.volume_db = linear_to_db(maxf(volume, 0.01))
	p.pitch_scale = pitch
	p.play()
