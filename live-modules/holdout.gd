extends SlopitectModule

# Slopitect live module: holdout, the "Rotwood Holdout" game.
# Round-based survival against the walking dead, in an old roofless hunting
# lodge deep in a dark wood. Each round more of them come, tougher and
# faster. They climb out of the ground outside, tear the boards off the
# lodge's windows and come in after you. Hold out as many rounds as you can.
#
# Points: 10 for every hit that doesn't kill, 60 for a kill, 100 for a
# kill to the head, 130 for a knife kill, 10 for each board you nail back
# on a window (up to 400 a round). You start with 500 and a Nailer pistol.
# Spend points on:
#   - guns on the walls (chalk outlines with a price): buy one, or its ammo
#     for half the price once you have it. You carry two; a third replaces
#     the one in your hand.
#   - debris in the doorways (Trophy Room, Back Yard): clearing it opens the
#     room, and the dead come in through its windows too from then on.
#   - the Lucky Crate (950): a random gun, some found nowhere else. It
#     shuffles, then offers one for a few seconds: take it or lose it.
#   - tonics from the old machines along the walls: Ironbark (more health),
#     Quickhands (faster reloads), Rattle Rum (faster shooting), Mending
#     Moss (heal sooner and faster). You keep them until the game ends.
# Your health comes back after a few seconds without a hit; with none left
# the game is over, and the best round per difficulty is kept.
#
# Controls (through controls.gd's actions, only while a game runs):
#   right trigger ("point") shoot; held for automatic guns
#   A ("right_a") buy, open, take, and held at a window, nail boards back
#   B ("right_b") reload (also on its own when the gun is empty)
#   Y ("left_y") switch guns
#   swing the left hand through one: the knife
# The guns ride on the right controller, pointing where it points (the
# controller follows the aim pose, so no turn is needed); the knife on the
# left. The round, points and health are on the left wrist, the ammo on
# the gun. Walls keep you in the open rooms (you're nudged back).
#
# Its own world: like Rhythm Sabers, the game has one world of its own,
# "holdout" (a project, projects.gd), made the first time. The Menu's
# Holdout tile, Start, or holdout_start takes you there (saving the world
# you were in) and opens the game's window; Leave takes you back. In the
# world the sky, sun and floor give way to the night wood and the lodge
# (put back when you leave or the module unloads). Without projects.gd it
# plays where you stand.
#
# Quest 1: every one of the dead is one instance of one MultiMesh (one draw
# for all of them), pooled; the walls are one MultiMesh, the trees two;
# no real lights (glowing materials and ambient light only); shots are
# rays tested against simple shapes (no physics bodies); sounds are made
# in code once at load and played through audio.gd (its own players
# without it). Nothing runs while no game is on.
#
# Signals: started(), stopped(), round_started(number),
# game_over(results), points_changed(points).

signal started()
signal stopped()
signal round_started(number: int)
signal game_over(results: Dictionary)
signal points_changed(points: int)

const TITLE := "Rotwood Holdout"
const PANEL := "holdout"
const PANEL_SIZE := Vector2(0.8, 0.6)
const WORLD := "holdout"
const SETTINGS_PATH := "user://holdout.json"
const DEFAULTS := {"difficulty": "normal", "max_zombies": 12, "sounds": true}
const DIFFICULTIES := ["easy", "normal", "hard"]
const DIFF_LABELS := {"easy": "Easy", "normal": "Normal", "hard": "Hard"}
const DIFF_HEALTH := {"easy": 0.7, "normal": 1.0, "hard": 1.4}
const DIFF_HIT := {"easy": 30.0, "normal": 45.0, "hard": 60.0}
const MAX_ZOMBIES := [6, 20]
const POOL := 20                 # the most of the dead there can be at once

# --- The lodge (metres; x right, z toward you; you start at 0, 0 facing -z) ---
# Rooms are [x, z, width, depth] on the ground.
const ROOMS := {
	"hall": [-4.0, -4.0, 8.0, 8.0],
	"trophy": [4.0, -3.0, 6.0, 6.0],
	"yard": [-4.0, 4.0, 8.0, 6.0],
}
const ROOM_NAMES := {"hall": "Great Hall", "trophy": "Trophy Room", "yard": "Back Yard"}
const DOORS := [
	{"id": "trophy_door", "rooms": ["hall", "trophy"], "at": [4.0, 0.0], "cost": 750},
	{"id": "yard_door", "rooms": ["hall", "yard"], "at": [0.0, 4.0], "cost": 1000},
]
# Windows: where on a wall, and "out" (the way out of the room).
const WINDOWS := [
	{"id": "w1", "room": "hall", "at": [-2.0, -4.0], "out": [0.0, -1.0]},
	{"id": "w2", "room": "hall", "at": [-4.0, 1.5], "out": [-1.0, 0.0]},
	{"id": "w3", "room": "trophy", "at": [7.0, -3.0], "out": [0.0, -1.0]},
	{"id": "w4", "room": "trophy", "at": [10.0, 0.0], "out": [1.0, 0.0]},
	{"id": "w5", "room": "yard", "at": [-4.0, 7.0], "out": [-1.0, 0.0]},
	{"id": "w6", "room": "yard", "at": [0.0, 10.0], "out": [0.0, 1.0]},
]
# Things on the walls: "in" is the way into the room.
const WALL_GUNS := [
	{"gun": "scattergun", "at": [-4.0, -2.0], "in": [1.0, 0.0]},
	{"gun": "buzzer", "at": [4.0, -2.6], "in": [-1.0, 0.0]},
	{"gun": "ridgeback", "at": [7.0, 3.0], "in": [0.0, -1.0]},
	{"gun": "longreach", "at": [5.4, -3.0], "in": [0.0, 1.0]},
]
const TONIC_SPOTS := [
	{"tonic": "quickhands", "at": [-2.6, 4.0], "in": [0.0, -1.0]},
	{"tonic": "rattle_rum", "at": [10.0, -1.8], "in": [-1.0, 0.0]},
	{"tonic": "mending_moss", "at": [8.8, 3.0], "in": [0.0, -1.0]},
	{"tonic": "ironbark", "at": [-4.0, 8.8], "in": [1.0, 0.0]},
]
const CRATE_SPOT := {"at": [4.0, 7.0], "in": [-1.0, 0.0]}
const WALL_H := 3.0
const WALL_T := 0.2
const DOOR_W := 1.6
const DOOR_H := 2.3
const WINDOW_W := 1.2
const SILL := 0.9
const LINTEL := 2.0
const PLANKS := 5

# --- Guns -------------------------------------------------------------------------
# damage per pellet, rate (seconds between shots), mag, reserve, reload
# (seconds), pellets, spread (degrees), auto, cost (on a wall; 0 = crate
# only), pierce (how many it goes through), splash (radius, m), chain (how
# many more it jumps to), chill (seconds slowed), colour, len (m).
const GUNS := {
	"nailer": {"name": "Nailer", "damage": 40.0, "rate": 0.22, "mag": 8, "reserve": 64, "reload": 1.4, "pellets": 1, "spread": 1.0,
		"auto": false, "cost": 0, "pierce": 1, "color": Color(0.45, 0.42, 0.38), "len": 0.2},
	"scattergun": {"name": "Scattergun", "damage": 32.0, "rate": 0.6, "mag": 6, "reserve": 36, "reload": 2.2, "pellets": 7, "spread": 6.0,
		"auto": false, "cost": 500, "pierce": 1, "color": Color(0.42, 0.28, 0.16), "len": 0.42},
	"buzzer": {"name": "Buzzer", "damage": 30.0, "rate": 0.08, "mag": 30, "reserve": 180, "reload": 1.8, "pellets": 1, "spread": 2.5,
		"auto": true, "cost": 1000, "pierce": 1, "color": Color(0.25, 0.3, 0.32), "len": 0.3},
	"ridgeback": {"name": "Ridgeback", "damage": 75.0, "rate": 0.16, "mag": 20, "reserve": 120, "reload": 2.0, "pellets": 1, "spread": 0.8,
		"auto": false, "cost": 1200, "pierce": 1, "color": Color(0.3, 0.33, 0.24), "len": 0.5},
	"longreach": {"name": "Longreach", "damage": 220.0, "rate": 0.7, "mag": 5, "reserve": 40, "reload": 2.6, "pellets": 1, "spread": 0.0,
		"auto": false, "cost": 1500, "pierce": 4, "color": Color(0.36, 0.24, 0.14), "len": 0.62},
	"thunderjug": {"name": "Thunderjug", "damage": 400.0, "rate": 0.45, "mag": 12, "reserve": 60, "reload": 2.4, "pellets": 1, "spread": 0.0,
		"auto": false, "cost": 0, "pierce": 1, "chain": 4, "color": Color(0.25, 0.45, 0.9), "len": 0.34},
	"grinder": {"name": "Grinder", "damage": 60.0, "rate": 0.09, "mag": 80, "reserve": 320, "reload": 3.2, "pellets": 1, "spread": 2.0,
		"auto": true, "cost": 0, "pierce": 2, "color": Color(0.2, 0.2, 0.22), "len": 0.55},
	"frostbite": {"name": "Frostbite", "damage": 150.0, "rate": 0.3, "mag": 15, "reserve": 75, "reload": 2.0, "pellets": 1, "spread": 0.0,
		"auto": false, "cost": 0, "pierce": 1, "chill": 4.0, "color": Color(0.6, 0.85, 1.0), "len": 0.36},
	"cinderpipe": {"name": "Cinderpipe", "damage": 600.0, "rate": 0.9, "mag": 4, "reserve": 24, "reload": 2.8, "pellets": 1, "spread": 0.0,
		"auto": false, "cost": 0, "pierce": 1, "splash": 2.5, "color": Color(0.7, 0.25, 0.1), "len": 0.6},
}
const CRATE_GUNS := ["scattergun", "buzzer", "ridgeback", "longreach", "thunderjug", "grinder", "frostbite", "cinderpipe"]
const CRATE_COST := 950
const CRATE_SHUFFLE := 2.4       # seconds it shuffles
const CRATE_OFFER := 8.0         # seconds it offers the gun
const TONICS := {
	"ironbark": {"name": "Ironbark", "cost": 2500, "color": Color(0.85, 0.5, 0.15), "does": "250 health"},
	"quickhands": {"name": "Quickhands", "cost": 3000, "color": Color(0.2, 0.75, 0.35), "does": "reload twice as fast"},
	"rattle_rum": {"name": "Rattle Rum", "cost": 2000, "color": Color(0.8, 0.15, 0.2), "does": "shoot a third faster"},
	"mending_moss": {"name": "Mending Moss", "cost": 1500, "color": Color(0.35, 0.55, 0.9), "does": "heal sooner and faster"},
}

# --- You and the dead ---------------------------------------------------------------
const START_POINTS := 500
const HEALTH := 100.0
const IRON_HEALTH := 250.0
const REGEN_AFTER := 4.0
const REGEN_RATE := 60.0         # health a second
const ATTACK_RANGE := 1.1
const ATTACK_TIME := 1.2         # seconds between one zombie's swipes
const REACH := 1.4               # metres from a thing you can use it
const REPAIR_TIME := 0.7         # seconds a board
const REPAIR_CAP := 400          # points a round for boards
const TEAR_TIME := 1.6           # seconds a board, walking
const SPEEDS := {"walk": 0.75, "jog": 1.35, "run": 1.9}
const HEAD_Y := 1.58
const HEAD_R := 0.16
const BODY_FROM := 0.3
const BODY_TO := 1.25
const BODY_R := 0.25
const RISE_TIME := 1.2
const CLIMB_TIME := 1.0
const DIE_TIME := 1.4
const ROUND_BREAK := 9.0
const FIRST_BREAK := 3.0
const KNIFE_SPEED := 2.4         # m/s the left hand must swing
const KNIFE_REACH := 0.45
const KNIFE_DAMAGE := 150.0
const KNIFE_TIME := 0.5
const MARGIN := 0.3              # how near a wall you can stand
const ZOMBIE_GAP := 0.55         # the dead keep this far apart
const MAX_RANGE := 60.0

var running := false
var settings := DEFAULTS.duplicate(true)
var best := {}                   # difficulty -> best round

var points := 0
var round_number := 0
var health := HEALTH
var kills := 0
var headshots := 0
var earned := 0
var guns: Array = []             # [{"id", "mag", "reserve"}]
var gun_index := 0
var tonics: Array = []
var open_rooms := {"hall": true}
var planks := {}                 # window id -> boards on it
var results := {}

var _lib: SlopitectModule
var _controls: SlopitectModule
var _audio: SlopitectModule
var _arena: Node3D               # the lodge, laid out where you stood
var _swapped := {}
var _zombie_mm: MultiMesh
var _zombies: Array = []         # active: {"slot", "state", "pos", "yaw", "hp", "speed", "room", "window", "t", "cd", "chill", "groan", "flash", "y"}
var _free_slots: Array = []
var _walls: Array = []           # AABBs (lodge space) shots stop at
var _plank_nodes := {}           # window id -> [MeshInstance3D]
var _debris := {}                # door id -> Node3D
var _uses: Array = []            # what A can work on: {"kind", "id", "at" (Vector3), "label" (Label3D or null)}
var _prompt: Label3D
var _sign: Label3D               # "Round 3"
var _sign_left := 0.0
var _crate_label: Label3D
var _crate_state := "idle"       # idle, shuffle, offer
var _crate_t := 0.0
var _crate_gun := ""
var _crate_show: MeshInstance3D  # the gun over the crate
var _gun_node: Node3D
var _gun_mesh: MeshInstance3D
var _flash: MeshInstance3D
var _ammo_label: Label3D
var _knife: Node3D
var _wrist: Label3D
var _hurt: MeshInstance3D        # red around your eyes when hit
var _tracer: MeshInstance3D
var _tracer_left := 0.0
var _boom: MeshInstance3D
var _boom_left := 0.0
var _hidden_boxes: Array = []
var _gun_meshes := {}
var _mats := {}
var _sounds := {}
var _players: Array = []         # without audio.gd
var _next_player := 0
var _rng := RandomNumberGenerator.new()
var _to_spawn := 0
var _spawn_t := 0.0
var _break_t := 0.0
var _round_hp := 150.0
var _repair_points := 0
var _cooldown := 0.0
var _reload_t := 0.0
var _trigger := false
var _use_held := false
var _repair_t := 0.0
var _use_target := {}
var _use_scan := 0.0
var _hit_t := 99.0               # seconds since you were last hit
var _player_room := "hall"
var _knife_prev := Vector3.ZERO
var _knife_cd := 0.0
var _groan_cd := 0.0
var _return_to := ""
var _wrist_text := ""


func setup() -> String:
	register("holdout_start", _start, "start a game of Rotwood Holdout (goes to its world first): optional difficulty (easy, normal, hard), round (the round to start on, 1 to 50)")
	register("holdout_stop", _stop, "end the game that's on")
	register("holdout_status", _status, "the game: round, points, health, guns and ammo, tonics, open rooms, boards on each window, the dead alive and still to come, kills; after a game, its results")
	register("holdout_set", _set_command, "the game's settings (usable in the headset): any of difficulty (easy, normal, hard), max_zombies (6 to 20 at once), sounds (true/false)")
	register("holdout_do", _do, "the Holdout window: act = toggle (goes to the Holdout world first), show, start, leave")
	register("holdout_leave", _leave, "end the game and go back from the Holdout world to the world you came from")
	_rng.randomize()
	_make_materials()
	_make_sounds()
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
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
	if _projects() != null and in_world():  # loaded while already in the Holdout world
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
	_end_game(false)
	_stage_off()
	ctx["server"].run({"cmd": "ui_remove", "id_panel": PANEL})


# --- Menu, Settings and the window ------------------------------------------------

func menu_info() -> Dictionary:
	return {"id": "holdout", "label": "Holdout", "order": 61, "action": {"cmd": "holdout_do", "act": "toggle"}}


func settings_info() -> Dictionary:
	var diffs := []
	for d in DIFFICULTIES:
		diffs.append({"label": DIFF_LABELS[d], "value": d})
	return {"title": TITLE, "order": 46, "settings": [
		{"id": "difficulty", "type": "choice", "label": "Difficulty", "value": settings["difficulty"], "options": diffs, "columns": 3,
			"set": {"cmd": "holdout_set", "difficulty": "{value}"}},
		{"id": "max_zombies", "type": "slider", "label": "Most of the dead at once", "min": MAX_ZOMBIES[0], "max": MAX_ZOMBIES[1], "step": 1.0,
			"value": settings["max_zombies"], "set": {"cmd": "holdout_set", "max_zombies": "{value}"}},
		{"id": "sounds", "type": "toggle", "label": "Game sounds", "value": settings["sounds"],
			"set": {"cmd": "holdout_set", "sounds": "{value}"}},
		{"id": "start", "type": "button", "label": "Start a game", "set": {"cmd": "holdout_start"}},
		{"id": "stop", "type": "button", "label": "End the game", "set": {"cmd": "holdout_stop"}},
		{"id": "leave", "type": "button", "label": "Leave the Holdout world", "set": {"cmd": "holdout_leave"}},
	]}


# Before vrui.gd (0), whose window toggles are on A and B and Y too (the
# terminal, tools and chat windows), and before doors.gd (-5); after pause
# (-10), so the hand menu still opens. Only while a game is on, and the
# trigger is left to vrui while you point at a window.
func action_order() -> int:
	return -6


func on_action(action: String, down: bool) -> bool:
	if not running:
		return false
	match action:
		"point":
			if down and _pointing_at_window():
				return false
			_trigger = down
			if down:
				_fire()
			return true
		"right_a":
			_use_held = down
			_repair_t = 0.0
			if down:
				_use()
			return true
		"right_b":
			if down:
				_reload()
			return true
		"left_y":
			if down:
				_switch_gun()
			return true
	return false


func _pointing_at_window() -> bool:
	var ui: SlopitectModule = _lib.module("vrui") if _lib else null
	return ui != null and ui.has_method("pointing") and not String(ui.call("pointing")).is_empty()


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


func _has_ui() -> bool:
	return ctx["modules"].module("vrui") != null or ctx["modules"].module("ui") != null


func _do(request: Dictionary) -> Dictionary:
	match request.get("act"):
		"toggle":
			if in_world() and _shown():
				_hide_window()
				return {"ok": true, "shown": false}
			var problem := _enter()
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			return _show_window()
		"show":
			return _show_window()
		"start":
			return _start({})
		"leave":
			return _leave({})
	return {"ok": false, "error": "\"act\" must be toggle, show, start or leave"}


func _shown() -> bool:
	var got := _run({"cmd": "ui_get", "id_panel": PANEL})
	return got.get("ok", false) and got.get("panel", {}).get("visible", false)


func _show_window() -> Dictionary:
	if not is_inside_tree():
		return {"ok": false, "error": "Holdout is unloading"}
	if not _has_ui():
		return {"ok": false, "error": "the Holdout window needs the vrui module"}
	var problem := _build()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	_run({"cmd": "ui_show", "id_panel": PANEL, "visible": true})
	return {"ok": true, "shown": true}


# The window opens with the world, unless a game started on the way in.
func _show_if_idle() -> void:
	if not running and is_inside_tree():
		_show_window()


func _hide_window() -> void:
	if _has_ui() and _run({"cmd": "ui_get", "id_panel": PANEL}).get("ok", false):
		_run({"cmd": "ui_show", "id_panel": PANEL, "visible": false})


func _build() -> String:
	if not _has_ui():
		return "the Holdout window needs the vrui module"
	var els := []
	var w := PANEL_SIZE.x - 0.08
	var y := PANEL_SIZE.y / 2.0 - 0.07
	els.append({"type": "text", "id": "status", "text": _window_text(), "at": [0.0, y - 0.05], "width": w})
	y -= 0.2
	for i in DIFFICULTIES.size():
		var d: String = DIFFICULTIES[i]
		els.append({"type": "button", "id": "diff_" + d, "label": DIFF_LABELS[d], "at": [(i - 1) * w / 3.0, y], "size": [w / 3.0 - 0.02, 0.055],
			"color": "accent" if settings["difficulty"] == d else "button", "action": {"cmd": "holdout_set", "difficulty": d}})
	y -= 0.08
	els.append({"type": "button", "id": "start", "label": "Play again" if not results.is_empty() else "Start", "at": [-w / 3.0, y],
		"size": [w / 3.0 - 0.02, 0.06], "color": "ok", "action": {"cmd": "holdout_start"}})
	els.append({"type": "button", "id": "stop", "label": "End game", "at": [0.0, y], "size": [w / 3.0 - 0.02, 0.06],
		"color": "notice" if running else "button", "action": {"cmd": "holdout_stop"}})
	els.append({"type": "button", "id": "leave", "label": "Leave", "at": [w / 3.0, y], "size": [w / 3.0 - 0.02, 0.06],
		"color": "button", "action": {"cmd": "holdout_leave"}})
	y -= 0.1
	els.append({"type": "text", "id": "help", "color": "muted", "at": [0.0, y], "width": w,
		"text": "Trigger: shoot   A: buy, open, hold to board up\nB: reload   Y: switch guns   Swing left hand: knife"})
	var request := {"id_panel": PANEL, "elements": els}
	if _run({"cmd": "ui_get", "id_panel": PANEL}).get("ok", false):
		request["cmd"] = "ui_update"
	else:
		request.merge({"cmd": "ui_add", "title": TITLE, "size": [PANEL_SIZE.x, PANEL_SIZE.y], "chrome": true, "visible": false})
	var reply := _run(request)
	return "" if reply.get("ok", false) else "%s: %s" % [PANEL, reply.get("error", "couldn't be drawn")]


func _window_text() -> String:
	var diff: String = settings["difficulty"]
	var record := "Best on %s: round %d" % [DIFF_LABELS[diff], int(best.get(diff, 0))] if best.has(diff) else "No rounds held on %s yet" % DIFF_LABELS[diff]
	if running:
		return "Round %d, %d points.\n%s" % [round_number, points, record]
	if not results.is_empty():
		return "Overrun on round %d. %d kills (%d to the head), %d points earned.\n%s" % [
			results["round"], results["kills"], results["headshots"], results["earned"], record]
	return "Hold the old lodge against the dead, round after round.\n%s" % record


# --- Settings ----------------------------------------------------------------------

func _set_command(request: Dictionary) -> Dictionary:
	var changed := []
	if request.has("difficulty"):
		if not request["difficulty"] in DIFFICULTIES:
			return {"ok": false, "error": "\"difficulty\" must be easy, normal or hard"}
		settings["difficulty"] = request["difficulty"]
		changed.append("difficulty")
	if request.has("max_zombies"):
		var n = request["max_zombies"]
		if typeof(n) == TYPE_STRING and n.is_valid_float():
			n = float(n)
		if typeof(n) not in [TYPE_INT, TYPE_FLOAT] or n < MAX_ZOMBIES[0] or n > MAX_ZOMBIES[1]:
			return {"ok": false, "error": "\"max_zombies\" must be %d to %d" % MAX_ZOMBIES}
		settings["max_zombies"] = int(n)
		changed.append("max_zombies")
	if request.has("sounds"):
		var on = request["sounds"]
		if typeof(on) == TYPE_STRING:
			on = on == "true"
		if typeof(on) != TYPE_BOOL:
			return {"ok": false, "error": "\"sounds\" must be true or false"}
		settings["sounds"] = on
		changed.append("sounds")
	if changed.is_empty():
		return {"ok": false, "error": "give difficulty, max_zombies or sounds"}
	_save_settings()
	if _lib:
		_lib.touch(self)
	if _has_ui() and _run({"cmd": "ui_get", "id_panel": PANEL}).get("ok", false):
		_build()
	return {"ok": true, "settings": settings.duplicate(), "changed": changed}


func _load_settings() -> void:
	if _lib == null:
		return
	var got = _lib.read_json(SETTINGS_PATH)
	if typeof(got) != TYPE_DICTIONARY:
		return
	var saved = got.get("settings", {})
	if typeof(saved) == TYPE_DICTIONARY:
		if saved.get("difficulty") in DIFFICULTIES:
			settings["difficulty"] = saved["difficulty"]
		if typeof(saved.get("max_zombies")) in [TYPE_INT, TYPE_FLOAT]:
			settings["max_zombies"] = clampi(int(saved["max_zombies"]), MAX_ZOMBIES[0], MAX_ZOMBIES[1])
		if typeof(saved.get("sounds")) == TYPE_BOOL:
			settings["sounds"] = saved["sounds"]
	if typeof(got.get("best")) == TYPE_DICTIONARY:
		best = got["best"]
	if typeof(got.get("return_to")) == TYPE_STRING:
		_return_to = got["return_to"]


func _save_settings() -> void:
	if _lib:
		_lib.write_json(SETTINGS_PATH, {"settings": settings, "best": best, "return_to": _return_to})


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
		reply = _run({"cmd": "projects_new", "name": WORLD, "modules": ["holdout"], "open": true})
	if not reply.get("ok", false):
		_return_to = before
		return "couldn't open the Holdout world: %s" % reply.get("error", "?")
	_save_settings()
	_stage_on()  # project_changed does it too; this is for the window that opens now
	return ""


func _leave(_request: Dictionary) -> Dictionary:
	_end_game(false)
	_hide_window()
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
		_end_game(false)
		_hide_window()
		_stage_off()


# --- Starting and ending -------------------------------------------------------------

func _start(request: Dictionary) -> Dictionary:
	if request.has("difficulty"):
		if not request["difficulty"] in DIFFICULTIES:
			return {"ok": false, "error": "\"difficulty\" must be easy, normal or hard"}
		settings["difficulty"] = request["difficulty"]
		_save_settings()
	var first := 1
	if request.has("round"):
		var r = request["round"]
		if typeof(r) not in [TYPE_INT, TYPE_FLOAT] or r < 1 or r > 50:
			return {"ok": false, "error": "\"round\" must be 1 to 50"}
		first = int(r)
	var problem := _enter()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	_end_game(false)
	_stage_on()
	_reset_lodge()
	points = START_POINTS
	health = HEALTH
	kills = 0
	headshots = 0
	earned = 0
	tonics.clear()
	guns = [{"id": "nailer", "mag": GUNS["nailer"]["mag"], "reserve": GUNS["nailer"]["reserve"]}]
	gun_index = 0
	results = {}
	_cooldown = 0.0
	_reload_t = 0.0
	_trigger = false
	_use_held = false
	_hit_t = 99.0
	_player_room = "hall"
	_move_player_to(Vector3.ZERO)
	_hold_gear(true)
	running = true
	round_number = first - 1
	_break_t = FIRST_BREAK
	_to_spawn = 0
	set_process(true)
	_hide_window()
	_update_hud()
	_show_gun()
	started.emit()
	points_changed.emit(points)
	return {"ok": true, "difficulty": settings["difficulty"], "round": first}


func _stop(_request: Dictionary) -> Dictionary:
	var was := running
	_end_game(false)
	if was and in_world():
		_show_window()
	return {"ok": true, "was_running": was}


# Ends the game: overrun (results kept and shown) or stopped.
func _end_game(overrun: bool) -> void:
	var was := running
	running = false
	set_process(false)
	_trigger = false
	_use_held = false
	for z in _zombies:
		_hide_slot(z["slot"])
		_free_slots.append(z["slot"])
	_zombies.clear()
	_crate_state = "idle"
	if _crate_label:
		_crate_label.text = "Lucky Crate\n%d" % CRATE_COST
		if _crate_show:
			_crate_show.visible = false
	if _sign:
		_sign.visible = false
	if _prompt:
		_prompt.visible = false
	if _tracer:
		_tracer.visible = false
	if _boom:
		_boom.visible = false
	_hold_gear(false)
	if overrun:
		results = {"round": round_number, "kills": kills, "headshots": headshots, "earned": earned, "points": points,
			"difficulty": settings["difficulty"]}
		var diff: String = settings["difficulty"]
		if round_number > int(best.get(diff, 0)):
			best[diff] = round_number
			results["new_best"] = true
		_save_settings()
		game_over.emit(results)
	if was:
		stopped.emit()


func _status(_request: Dictionary) -> Dictionary:
	var held := []
	for g in guns:
		held.append({"gun": g["id"], "name": GUNS[g["id"]]["name"], "mag": g["mag"], "reserve": g["reserve"]})
	return {"ok": true, "running": running, "round": round_number, "points": points, "health": health, "max_health": _max_health(),
		"guns": held, "in_hand": guns[gun_index]["id"] if gun_index < guns.size() else "", "tonics": tonics.duplicate(),
		"open_rooms": open_rooms.keys(), "boards": planks.duplicate(), "alive": _zombies.size(), "to_come": _to_spawn,
		"kills": kills, "headshots": headshots, "crate": _crate_state, "settings": settings.duplicate(), "best": best.duplicate(),
		"results": results.duplicate(), "in_world": in_world() if _lib else true}


# --- The lodge and the night wood -----------------------------------------------------

func _stage_on() -> void:
	if _arena != null:
		return
	var scene := ctx["world"].get_parent() as Node if ctx.get("world") else null
	if scene:
		var env := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if env:
			_swapped["environment"] = [env, env.environment]
			var night := Environment.new()
			night.background_mode = Environment.BG_COLOR
			night.background_color = Color(0.02, 0.025, 0.04)
			night.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			night.ambient_light_color = Color(0.5, 0.53, 0.62)
			night.ambient_light_energy = 1.3
			night.fog_enabled = true
			night.fog_light_color = Color(0.05, 0.07, 0.09)
			night.fog_density = 0.05
			night.fog_sky_affect = 0.0
			env.environment = night
		var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
		if sun:
			_swapped["sun"] = [sun, sun.light_energy, sun.light_color]
			sun.light_energy = 0.45
			sun.light_color = Color(0.6, 0.7, 1.0)  # moonlight
		var ground := scene.get_node_or_null("Floor") as Node3D
		if ground:
			_swapped["floor"] = [ground, ground.visible]
			ground.visible = false
	_arena = Node3D.new()
	_arena.name = "lodge"
	add_child(_arena)  # its own, not World's: nothing to save or select
	_place_arena()
	_build_lodge()


func _stage_off() -> void:
	if _swapped.has("environment") and is_instance_valid(_swapped["environment"][0]):
		_swapped["environment"][0].environment = _swapped["environment"][1]
	if _swapped.has("sun") and is_instance_valid(_swapped["sun"][0]):
		_swapped["sun"][0].light_energy = _swapped["sun"][1]
		_swapped["sun"][0].light_color = _swapped["sun"][2]
	if _swapped.has("floor") and is_instance_valid(_swapped["floor"][0]):
		_swapped["floor"][0].visible = _swapped["floor"][1]
	_swapped.clear()
	_hold_gear(false)
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_zombie_mm = null
	_zombies.clear()
	_free_slots.clear()
	_walls.clear()
	_plank_nodes.clear()
	_debris.clear()
	_uses.clear()
	_prompt = null
	_sign = null
	_crate_label = null
	_crate_show = null
	_tracer = null
	_boom = null


# The hall's middle goes where you stand, facing the way you look.
func _place_arena() -> void:
	var cam: Node3D = ctx.get("camera")
	if cam == null or not is_instance_valid(cam):
		_arena.transform = Transform3D.IDENTITY
		return
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	var yaw := atan2(-fwd.x, -fwd.z) if fwd.length() > 0.01 else 0.0
	var floor_y := 0.0
	var origin := cam.get_parent() as Node3D
	if origin:
		floor_y = origin.global_position.y
	_arena.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(cam.global_position.x, floor_y, cam.global_position.z))


func _build_lodge() -> void:
	# Ground, and each room's floorboards.
	_box(_arena, Vector3(90.0, 0.02, 90.0), Vector3(0.0, -0.02, 0.0), _mats["ground"])
	for room in ROOMS:
		var r: Array = ROOMS[room]
		_box(_arena, Vector3(r[2], 0.02, r[3]), Vector3(r[0] + r[2] / 2.0, 0.0, r[1] + r[3] / 2.0), _mats["boards"] if room != "yard" else _mats["dirt"])
	# Walls, with gaps for the doors and windows: one MultiMesh.
	var parts := []  # [size, centre]
	for room in ROOMS:
		var r: Array = ROOMS[room]
		var x0: float = r[0]
		var z0: float = r[1]
		var x1: float = r[0] + r[2]
		var z1: float = r[1] + r[3]
		_wall_line(parts, Vector3(x0, 0, z0), Vector3(x1, 0, z0))
		_wall_line(parts, Vector3(x0, 0, z1), Vector3(x1, 0, z1))
		_wall_line(parts, Vector3(x0, 0, z0), Vector3(x0, 0, z1))
		_wall_line(parts, Vector3(x1, 0, z0), Vector3(x1, 0, z1))
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = unit
	mm.instance_count = parts.size()
	_walls.clear()
	for i in parts.size():
		var size: Vector3 = parts[i][0]
		var at: Vector3 = parts[i][1]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(size), at))
		_walls.append(AABB(at - size / 2.0, size))
	var walls := MultiMeshInstance3D.new()
	walls.name = "walls"
	walls.multimesh = mm
	walls.material_override = _mats["wall"]
	_arena.add_child(walls)
	# Lanterns: glowing, no real light.
	for at in [Vector3(-3.85, 2.2, -2.8), Vector3(3.85, 2.2, 2.6), Vector3(9.85, 2.2, 1.6), Vector3(-3.85, 2.2, 5.5), Vector3(0.0, 2.2, -3.85)]:
		_box(_arena, Vector3(0.12, 0.2, 0.12), at, _mats["lantern"])
	_build_trees()
	_build_windows()
	_build_doors()
	_build_wall_things()
	# The dead: one MultiMesh, every instance hidden until used.
	_zombie_mm = MultiMesh.new()
	_zombie_mm.transform_format = MultiMesh.TRANSFORM_3D
	_zombie_mm.use_colors = true
	_zombie_mm.mesh = _zombie_mesh()
	_zombie_mm.instance_count = POOL
	var dead := MultiMeshInstance3D.new()
	dead.name = "dead"
	dead.multimesh = _zombie_mm
	dead.material_override = _mats["zombie"]
	dead.custom_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 15, 120))  # never culled: they move
	_arena.add_child(dead)
	_free_slots.clear()
	for i in POOL:
		_hide_slot(i)
		_free_slots.append(i)
	_zombies.clear()
	# What's shown while you play: the prompt, the round sign, shots.
	_prompt = _label(_arena, "", 40, Color(1.0, 0.95, 0.8))
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.visible = false
	_sign = _label(_arena, "", 160, Color(0.85, 0.08, 0.05))
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.visible = false
	_tracer = MeshInstance3D.new()
	_tracer.mesh = ImmediateMesh.new()
	_tracer.material_override = _mats["tracer"]
	_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tracer.visible = false
	_arena.add_child(_tracer)
	_boom = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 12
	ball.rings = 6
	_boom.mesh = ball
	_boom.material_override = _mats["boom"]
	_boom.visible = false
	_arena.add_child(_boom)
	_reset_lodge()


# A wall from a to b (on the ground), split round the doors and windows on it.
func _wall_line(parts: Array, a: Vector3, b: Vector3) -> void:
	var along := (b - a).normalized()
	var length := a.distance_to(b)
	var gaps := []  # [from, to, kind]
	for d in DOORS:
		var at := Vector3(d["at"][0], 0, d["at"][1])
		var s := (at - a).dot(along)
		if (at - (a + along * s)).length() < 0.01 and s > 0.0 and s < length:
			gaps.append([s - DOOR_W / 2.0, s + DOOR_W / 2.0, "door"])
	for wnd in WINDOWS:
		var at := Vector3(wnd["at"][0], 0, wnd["at"][1])
		var s := (at - a).dot(along)
		if (at - (a + along * s)).length() < 0.01 and s > 0.0 and s < length:
			gaps.append([s - WINDOW_W / 2.0, s + WINDOW_W / 2.0, "window"])
	gaps.sort_custom(func(p, q): return p[0] < q[0])
	var from := -WALL_T / 2.0
	for g in gaps:
		_wall_piece(parts, a, along, from, g[0], 0.0, WALL_H)
		if g[2] == "door":
			_wall_piece(parts, a, along, g[0], g[1], DOOR_H, WALL_H)
		else:
			_wall_piece(parts, a, along, g[0], g[1], 0.0, SILL)
			_wall_piece(parts, a, along, g[0], g[1], LINTEL, WALL_H)
		from = g[1]
	_wall_piece(parts, a, along, from, length + WALL_T / 2.0, 0.0, WALL_H)


func _wall_piece(parts: Array, a: Vector3, along: Vector3, s0: float, s1: float, y0: float, y1: float) -> void:
	if s1 - s0 < 0.01:
		return
	var mid := a + along * ((s0 + s1) / 2.0) + Vector3(0, (y0 + y1) / 2.0, 0)
	var size := Vector3(abs(along.x) * (s1 - s0) + abs(along.z) * WALL_T, y1 - y0, abs(along.z) * (s1 - s0) + abs(along.x) * WALL_T)
	parts.append([size, mid])


# The wood outside: dark trunks and pointed crowns, two draws, a fixed seed.
func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spots := []
	while spots.size() < 46:
		var at := Vector3(rng.randf_range(-28.0, 28.0), 0, rng.randf_range(-28.0, 28.0))
		if at.x > -10.0 and at.x < 16.0 and at.z > -10.0 and at.z < 16.0:
			continue  # the clearing round the lodge
		spots.append([at, rng.randf_range(0.8, 1.5)])
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.2
	trunk.height = 1.0
	trunk.radial_segments = 6
	trunk.rings = 1
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 1.0
	crown.height = 1.0
	crown.radial_segments = 7
	crown.rings = 1
	for part in [[trunk, _mats["trunk"]], [crown, _mats["crown"]]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = spots.size()
		for i in spots.size():
			var at: Vector3 = spots[i][0]
			var s: float = spots[i][1]
			if part[0] == trunk:
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, 3.0 * s, s)), at + Vector3(0, 1.5 * s, 0)))
			else:
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.6 * s, 5.0 * s, 1.6 * s)), at + Vector3(0, 4.5 * s, 0)))
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = part[1]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arena.add_child(node)


func _build_windows() -> void:
	_plank_nodes.clear()
	var board := BoxMesh.new()
	board.size = Vector3(WINDOW_W + 0.2, 0.13, 0.05)
	for wnd in WINDOWS:
		var at := Vector3(wnd["at"][0], 0, wnd["at"][1])
		var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
		var yaw := atan2(out.x, out.z)
		var list := []
		for i in PLANKS:
			var p := MeshInstance3D.new()
			p.mesh = board
			p.material_override = _mats["plank"]
			_arena.add_child(p)
			var tilt := deg_to_rad([-8.0, 6.0, -4.0, 9.0, -6.0][i])
			p.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, tilt), at - out * 0.14 + Vector3(0, SILL + 0.14 + i * 0.2, 0))
			list.append(p)
		_plank_nodes[wnd["id"]] = list
		_uses.append({"kind": "window", "id": wnd["id"], "at": at - out * 0.6, "label": null})


func _build_doors() -> void:
	_debris.clear()
	for d in DOORS:
		var at := Vector3(d["at"][0], 0, d["at"][1])
		var pile := Node3D.new()
		_arena.add_child(pile)
		pile.position = at
		var inward0 := _into_room(at, d["rooms"][0])
		var across := Vector3(0, 0, 1) if absf(inward0.x) > 0.5 else Vector3(1, 0, 0)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(d["id"])
		for i in 7:
			var size := Vector3(rng.randf_range(0.4, 0.9), rng.randf_range(0.25, 0.6), rng.randf_range(0.3, 0.6))
			var spot := across * rng.randf_range(-0.6, 0.6) + Vector3(0, size.y / 2.0 + (0.45 if i >= 4 else 0.0), 0)
			var piece := _box(pile, size, spot, _mats["plank"] if i % 2 == 0 else _mats["debris"])
			piece.rotation.y = rng.randf_range(-0.6, 0.6)
		for room in d["rooms"]:
			var inward := _into_room(at, room)
			var label := _label(_arena, "", 46, Color(1.0, 0.9, 0.7))
			label.position = at + inward * 0.55 + Vector3(0, 1.75, 0)
			label.rotation.y = atan2(inward.x, inward.z)
			label.text = "Clear the debris\n%s  %d" % [ROOM_NAMES[d["rooms"][1]], d["cost"]]
			pile.set_meta("label_" + room, label)
			_uses.append({"kind": "door", "id": d["id"], "at": at + inward * 0.7, "label": label})
		_debris[d["id"]] = pile


# The way from a point on a room's wall into that room.
func _into_room(at: Vector3, room: String) -> Vector3:
	var r: Array = ROOMS[room]
	var mid := Vector3(r[0] + r[2] / 2.0, 0, r[1] + r[3] / 2.0)
	var d := mid - at
	return Vector3(signf(d.x), 0, 0) if absf(d.x) * r[3] > absf(d.z) * r[2] else Vector3(0, 0, signf(d.z))


func _build_wall_things() -> void:
	for spot in WALL_GUNS:
		var g: Dictionary = GUNS[spot["gun"]]
		var at := Vector3(spot["at"][0], 0, spot["at"][1])
		var inward := Vector3(spot["in"][0], 0, spot["in"][1])
		var yaw := atan2(inward.x, inward.z)
		var board := _box(_arena, Vector3(0.9, 0.5, 0.03), at + inward * (WALL_T / 2.0 + 0.02) + Vector3(0, 1.45, 0), _mats["chalkboard"])
		board.rotation.y = yaw
		# The gun's outline in chalk: its own shape, flat and pale.
		var outline := MeshInstance3D.new()
		outline.mesh = _gun_mesh_for(spot["gun"])
		outline.material_override = _mats["chalk"]
		_arena.add_child(outline)
		outline.transform = Transform3D(Basis(Vector3.UP, yaw + PI / 2.0) * Basis.from_scale(Vector3(1.2, 1.2, 1.2) * minf(1.0, 0.36 / g["len"])),
			at + inward * (WALL_T / 2.0 + 0.06) + Vector3(0, 1.5, 0))
		var label := _label(_arena, "%s  %d\nammo %d" % [g["name"], g["cost"], g["cost"] / 2], 44, Color(0.95, 0.95, 0.9))
		label.position = at + inward * (WALL_T / 2.0 + 0.05) + Vector3(0, 1.08, 0)
		label.rotation.y = yaw
		_uses.append({"kind": "gun", "id": spot["gun"], "at": at + inward * 0.7, "label": label})
	for spot in TONIC_SPOTS:
		var t: Dictionary = TONICS[spot["tonic"]]
		var at := Vector3(spot["at"][0], 0, spot["at"][1])
		var inward := Vector3(spot["in"][0], 0, spot["in"][1])
		var yaw := atan2(inward.x, inward.z)
		var body := _box(_arena, Vector3(0.7, 1.8, 0.45), at + inward * (WALL_T / 2.0 + 0.24) + Vector3(0, 0.9, 0), _mats["machine"])
		body.rotation.y = yaw
		var glow := _box(_arena, Vector3(0.5, 0.55, 0.02), at + inward * (WALL_T / 2.0 + 0.47) + Vector3(0, 1.3, 0), _flat_glow(t["color"]))
		glow.rotation.y = yaw
		var label := _label(_arena, "%s  %d\n%s" % [t["name"], t["cost"], t["does"]], 40, t["color"].lightened(0.4))
		label.position = at + inward * (WALL_T / 2.0 + 0.5) + Vector3(0, 0.75, 0)
		label.rotation.y = yaw
		_uses.append({"kind": "tonic", "id": spot["tonic"], "at": at + inward * 0.9, "label": label})
	var c_at := Vector3(CRATE_SPOT["at"][0], 0, CRATE_SPOT["at"][1])
	var c_in := Vector3(CRATE_SPOT["in"][0], 0, CRATE_SPOT["in"][1])
	var c_yaw := atan2(c_in.x, c_in.z)
	var chest := _box(_arena, Vector3(1.2, 0.6, 0.6), c_at + c_in * (WALL_T / 2.0 + 0.35) + Vector3(0, 0.3, 0), _mats["crate"])
	chest.rotation.y = c_yaw
	var rim := _box(_arena, Vector3(1.24, 0.04, 0.64), c_at + c_in * (WALL_T / 2.0 + 0.35) + Vector3(0, 0.6, 0), _flat_glow(Color(0.95, 0.75, 0.2)))
	rim.rotation.y = c_yaw
	_crate_label = _label(_arena, "Lucky Crate\n%d" % CRATE_COST, 52, Color(1.0, 0.85, 0.35))
	_crate_label.position = c_at + c_in * (WALL_T / 2.0 + 0.35) + Vector3(0, 1.05, 0)
	_crate_label.rotation.y = c_yaw
	# The gun it shows, floating over it while it shuffles and offers.
	_crate_show = MeshInstance3D.new()
	_crate_show.material_override = _mats["gun"]
	_crate_show.position = c_at + c_in * (WALL_T / 2.0 + 0.35) + Vector3(0, 0.85, 0)
	_crate_show.rotation.y = c_yaw + PI / 2.0
	_crate_show.scale = Vector3.ONE * 1.6
	_crate_show.visible = false
	_arena.add_child(_crate_show)
	_uses.append({"kind": "crate", "id": "crate", "at": c_at + c_in * 1.0, "label": _crate_label})


# Puts the boards and debris back for a new game.
func _reset_lodge() -> void:
	open_rooms = {"hall": true}
	for wnd in WINDOWS:
		planks[wnd["id"]] = PLANKS
		_show_planks(wnd["id"])
	for id in _debris:
		if is_instance_valid(_debris[id]):
			_debris[id].visible = true
			for room in ROOMS:
				if _debris[id].has_meta("label_" + room):
					_debris[id].get_meta("label_" + room).visible = true
	_crate_state = "idle"


func _show_planks(id: String) -> void:
	if not _plank_nodes.has(id):
		return
	var list: Array = _plank_nodes[id]
	for i in list.size():
		list[i].visible = i < int(planks.get(id, 0))


# --- You -----------------------------------------------------------------------------

func _cam_local() -> Vector3:
	var cam: Node3D = ctx.get("camera")
	if cam == null or _arena == null:
		return Vector3.ZERO
	return _arena.to_local(cam.global_position)


func _move_player_to(spot: Vector3) -> void:
	var cam: Node3D = ctx.get("camera")
	if cam == null or _arena == null:
		return
	var origin := cam.get_parent() as Node3D
	if origin == null:
		return
	var want := _arena.to_global(spot)
	var shift := want - cam.global_position
	shift.y = 0.0
	origin.global_position += shift


func _max_health() -> float:
	return IRON_HEALTH if "ironbark" in tonics else HEALTH


# The rooms you may stand in (open ones), less a margin, and the open doorways.
func _allowed_boxes() -> Array:
	var boxes := []
	for room in open_rooms:
		var r: Array = ROOMS[room]
		boxes.append(Rect2(r[0] + MARGIN, r[1] + MARGIN, r[2] - 2.0 * MARGIN, r[3] - 2.0 * MARGIN))
	for d in DOORS:
		if open_rooms.has(d["rooms"][0]) and open_rooms.has(d["rooms"][1]):
			var w := DOOR_W / 2.0 - MARGIN
			boxes.append(Rect2(d["at"][0] - w, d["at"][1] - w, 2.0 * w, 2.0 * w).grow(MARGIN * 1.5))
	return boxes


func _keep_in() -> void:
	var p := _cam_local()
	var here := Vector2(p.x, p.z)
	var boxes := _allowed_boxes()
	var nearest := here
	var gap := INF
	for b: Rect2 in boxes:
		if b.has_point(here):
			return
		var c := Vector2(clampf(here.x, b.position.x, b.end.x), clampf(here.y, b.position.y, b.end.y))
		if c.distance_to(here) < gap:
			gap = c.distance_to(here)
			nearest = c
	if gap < INF:
		_move_player_to(Vector3(nearest.x, 0, nearest.y))


func _room_at(p: Vector3) -> String:
	for room in ROOMS:
		var r: Array = ROOMS[room]
		if p.x >= r[0] and p.x <= r[0] + r[2] and p.z >= r[1] and p.z <= r[1] + r[3]:
			return room
	return ""


func _hurt_you(amount: float) -> void:
	health -= amount
	_hit_t = 0.0
	_sound("hurt", null, 0.9)
	_pulse("left", 0.8, 0.2)
	_pulse("right", 0.8, 0.2)
	_update_hud()
	if health <= 0.0:
		health = 0.0
		_end_game(true)
		if in_world():
			_show_window()


# --- Each frame ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not running or _arena == null:
		set_process(false)
		return
	_keep_in()
	var here := _cam_local()
	var room := _room_at(here)
	if not room.is_empty() and open_rooms.has(room):
		_player_room = room
	# Health comes back.
	_hit_t += delta
	var wait := REGEN_AFTER * (0.5 if "mending_moss" in tonics else 1.0)
	if _hit_t > wait and health < _max_health():
		health = minf(_max_health(), health + REGEN_RATE * (2.0 if "mending_moss" in tonics else 1.0) * delta)
		_update_hud()
	_show_hurt()
	_rounds(delta)
	_move_dead(delta, here)
	if not running:
		return  # overrun this frame
	_gun_frame(delta)
	_knife_frame(delta)
	_use_frame(delta, here)
	_crate_frame(delta)
	if _sign_left > 0.0:
		_sign_left -= delta
		_sign.visible = _sign_left > 0.0
	if _tracer_left > 0.0:
		_tracer_left -= delta
		_tracer.visible = _tracer_left > 0.0
	if _boom_left > 0.0:
		_boom_left -= delta
		_boom.visible = _boom_left > 0.0
	if _flash and _flash.visible and _cooldown < _rate() - 0.05:
		_flash.visible = false


# --- Rounds ----------------------------------------------------------------------------

func _rounds(delta: float) -> void:
	if _break_t > 0.0:
		_break_t -= delta
		if _break_t <= 0.0:
			_next_round()
		return
	if _to_spawn > 0:
		_spawn_t -= delta
		if _spawn_t <= 0.0 and _zombies.size() < int(settings["max_zombies"]) and not _free_slots.is_empty():
			if _spawn_one():
				_to_spawn -= 1
			_spawn_t = maxf(0.5, 2.2 - 0.12 * round_number)
	elif _zombies.is_empty():
		_break_t = ROUND_BREAK
		_sound("bell", null, 0.6)


func _next_round() -> void:
	round_number += 1
	_to_spawn = round_count(round_number)
	_round_hp = round_health(round_number) * DIFF_HEALTH[settings["difficulty"]]
	_repair_points = 0
	_spawn_t = 1.0
	_sign.text = "Round %d" % round_number
	var cam_local := _cam_local()
	var ahead := _arena.global_transform.basis.inverse() * -(ctx["camera"] as Node3D).global_transform.basis.z if ctx.get("camera") else Vector3.FORWARD
	ahead.y = 0.0
	_sign.position = cam_local + ahead.normalized() * 3.0 + Vector3(0, 0.6, 0)
	_sign.visible = true
	_sign_left = 3.5
	_sound("bell", null, 1.0)
	_update_hud()
	if _has_ui() and _shown():
		_build()
	round_started.emit(round_number)


# How many come in a round, and how tough each is.
static func round_count(n: int) -> int:
	return mini(6 + 3 * n + int(n * n * 0.15), 90)


static func round_health(n: int) -> float:
	if n <= 9:
		return 150.0 + 100.0 * (n - 1)
	return 950.0 * pow(1.1, n - 9)


func _speed_for_round() -> float:
	var run_chance := clampf((round_number - 4) * 0.12, 0.0, 0.8)
	var jog_chance := clampf((round_number - 1) * 0.25, 0.0, 1.0)
	var roll := _rng.randf()
	if roll < run_chance:
		return SPEEDS["run"]
	if roll < run_chance + (1.0 - run_chance) * jog_chance:
		return SPEEDS["jog"]
	return SPEEDS["walk"]


# One more comes up out of the ground outside a window of an open room
# (more often your own room's). Whether one did.
func _spawn_one() -> bool:
	var choices := []
	for wnd in WINDOWS:
		if open_rooms.has(wnd["room"]):
			for i in (3 if wnd["room"] == _player_room else 1):
				choices.append(wnd)
	if choices.is_empty() or _free_slots.is_empty():
		return false
	var wnd: Dictionary = choices[_rng.randi() % choices.size()]
	var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
	var side := Vector3(-out.z, 0, out.x)
	var at := Vector3(wnd["at"][0], 0, wnd["at"][1]) + out * _rng.randf_range(3.0, 5.0) + side * _rng.randf_range(-2.0, 2.0)
	var z := {"slot": _free_slots.pop_back(), "state": "rise", "pos": at, "yaw": atan2(-out.x, -out.z), "hp": _round_hp,
		"speed": _speed_for_round(), "room": wnd["room"], "window": wnd["id"], "t": 0.0, "cd": 0.0, "chill": 0.0,
		"groan": _rng.randf_range(1.0, 6.0), "flash": 0.0, "y": -1.8, "phase": _rng.randf() * TAU, "fall": 0.0}
	_zombies.append(z)
	_place_zombie(z)
	return true


# Puts one in the game now (tests, and a later debug command): at a spot
# in a room, already inside.
func add_zombie_inside(spot: Vector3, room := "hall", hp := -1.0) -> Dictionary:
	if _free_slots.is_empty():
		return {}
	var z := {"slot": _free_slots.pop_back(), "state": "chase", "pos": spot, "yaw": 0.0, "hp": hp if hp > 0.0 else _round_hp,
		"speed": SPEEDS["walk"], "room": room, "window": "", "t": 0.0, "cd": ATTACK_TIME, "chill": 0.0, "groan": 5.0,
		"flash": 0.0, "y": 0.0, "phase": 0.0, "fall": 0.0}
	_zombies.append(z)
	_place_zombie(z)
	return z


# --- The dead ---------------------------------------------------------------------------

func _move_dead(delta: float, you: Vector3) -> void:
	_groan_cd -= delta
	var you_flat := Vector3(you.x, 0, you.z)
	for z in _zombies.duplicate():
		z["t"] += delta
		z["flash"] = maxf(0.0, z["flash"] - delta)
		z["chill"] = maxf(0.0, z["chill"] - delta)
		var speed: float = z["speed"] * (0.4 if z["chill"] > 0.0 else 1.0)
		match z["state"]:
			"rise":
				z["y"] = lerpf(-1.8, 0.0, minf(1.0, z["t"] / RISE_TIME))
				if z["t"] >= RISE_TIME:
					_set_state(z, "approach")
			"approach":
				var wnd := _window(z["window"])
				var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
				var spot := Vector3(wnd["at"][0], 0, wnd["at"][1]) + out * 0.55
				if _walk_to(z, spot, speed, delta):
					_set_state(z, "tear")
			"tear":
				var wnd := _window(z["window"])
				var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
				z["yaw"] = atan2(out.x, out.z)  # facing in
				if int(planks[z["window"]]) <= 0:
					_set_state(z, "climb")
				elif z["t"] >= TEAR_TIME * SPEEDS["walk"] / maxf(speed, 0.3) + 0.4:
					planks[z["window"]] = int(planks[z["window"]]) - 1
					_show_planks(z["window"])
					_sound("rip", _arena.to_global(Vector3(wnd["at"][0], 1.3, wnd["at"][1])), 0.8)
					z["t"] = 0.0
			"climb":
				var wnd := _window(z["window"])
				var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
				var at := Vector3(wnd["at"][0], 0, wnd["at"][1])
				var k := minf(1.0, z["t"] / CLIMB_TIME)
				z["pos"] = (at + out * 0.55).lerp(at - out * 0.7, k)
				z["y"] = sin(k * PI) * 0.7
				if z["t"] >= CLIMB_TIME:
					z["y"] = 0.0
					_set_state(z, "chase")
			"chase":
				var target := you_flat
				if z["room"] != _player_room:
					var door := _door_toward(z["room"], _player_room)
					if not door.is_empty():
						target = Vector3(door["at"][0], 0, door["at"][1])
						if (z["pos"] as Vector3).distance_to(target) < 0.4:
							z["room"] = door["rooms"][1] if door["rooms"][0] == z["room"] else door["rooms"][0]
				if (z["pos"] as Vector3).distance_to(you_flat) > ATTACK_RANGE * 0.7:
					_walk_to(z, target, speed, delta)
				else:
					var to: Vector3 = you_flat - z["pos"]
					z["yaw"] = atan2(-to.x, -to.z)
			"dying":
				z["fall"] = minf(1.0, z["t"] / 0.45)
				if z["t"] > 0.8:
					z["y"] = -1.2 * (z["t"] - 0.8) / (DIE_TIME - 0.8)
				if z["t"] >= DIE_TIME:
					_hide_slot(z["slot"])
					_free_slots.append(z["slot"])
					_zombies.erase(z)
					continue
		if z["state"] in ["tear", "chase"]:
			z["cd"] -= delta
			if (z["pos"] as Vector3).distance_to(you_flat) < ATTACK_RANGE and z["cd"] <= 0.0:
				z["cd"] = ATTACK_TIME
				_hurt_you(DIFF_HIT[settings["difficulty"]])
				if not running:
					return
		if z["state"] != "dying":
			z["groan"] -= delta
			if z["groan"] <= 0.0:
				z["groan"] = _rng.randf_range(4.0, 9.0)
				if _groan_cd <= 0.0:
					_groan_cd = 1.2
					_sound("groan", _arena.to_global(z["pos"] + Vector3(0, 1.5, 0)), 0.7, _rng.randf_range(0.85, 1.15))
		_place_zombie(z)
	_spread_out()


func _set_state(z: Dictionary, state: String) -> void:
	z["state"] = state
	z["t"] = 0.0


# Walks toward spot; whether it's there.
func _walk_to(z: Dictionary, spot: Vector3, speed: float, delta: float) -> bool:
	var to: Vector3 = spot - z["pos"]
	to.y = 0.0
	var d := to.length()
	if d < 0.05:
		return true
	var step := minf(d, speed * delta)
	z["pos"] += to / d * step
	z["yaw"] = atan2(-to.x, -to.z)
	z["phase"] += delta * speed * 5.0
	return d - step < 0.05


# The dead inside push apart a little, so they don't stand in one another.
func _spread_out() -> void:
	for i in _zombies.size():
		var a: Dictionary = _zombies[i]
		if a["state"] != "chase":
			continue
		for j in range(i + 1, _zombies.size()):
			var b: Dictionary = _zombies[j]
			if b["state"] != "chase":
				continue
			var d: Vector3 = b["pos"] - a["pos"]
			d.y = 0.0
			var l := d.length()
			if l < ZOMBIE_GAP and l > 0.001:
				var push := d / l * (ZOMBIE_GAP - l) * 0.5
				a["pos"] -= push
				b["pos"] += push
		a["pos"] = _inside(a["pos"], a["room"])


# Keeps a point in a room (or in an open doorway out of it).
func _inside(p: Vector3, room: String) -> Vector3:
	var r: Array = ROOMS[room]
	var m := 0.25
	if p.x >= r[0] + m and p.x <= r[0] + r[2] - m and p.z >= r[1] + m and p.z <= r[1] + r[3] - m:
		return p
	for d in DOORS:
		if room in d["rooms"] and open_rooms.has(d["rooms"][0]) and open_rooms.has(d["rooms"][1]):
			if absf(p.x - d["at"][0]) < DOOR_W / 2.0 and absf(p.z - d["at"][1]) < DOOR_W / 2.0:
				return p
	return Vector3(clampf(p.x, r[0] + m, r[0] + r[2] - m), p.y, clampf(p.z, r[1] + m, r[1] + r[3] - m))


func _window(id: String) -> Dictionary:
	for wnd in WINDOWS:
		if wnd["id"] == id:
			return wnd
	return WINDOWS[0]


# The open door to go through first from one room toward another ({} if none).
func _door_toward(from: String, to: String) -> Dictionary:
	if from == to:
		return {}
	var came := {from: {}}
	var queue := [from]
	while not queue.is_empty():
		var room: String = queue.pop_front()
		for d in DOORS:
			if not (room in d["rooms"]) or not (open_rooms.has(d["rooms"][0]) and open_rooms.has(d["rooms"][1])):
				continue
			var other: String = d["rooms"][1] if d["rooms"][0] == room else d["rooms"][0]
			if came.has(other):
				continue
			came[other] = {"door": d, "from": room}
			if other == to:
				var step: Dictionary = came[other]
				while step["from"] != from:
					step = came[step["from"]]
				return step["door"]
			queue.append(other)
	return {}


func _place_zombie(z: Dictionary) -> void:
	if _zombie_mm == null:
		return
	var sway := sin(z["phase"]) * 0.08 if z["state"] in ["chase", "approach"] else 0.0
	var basis := Basis(Vector3.UP, z["yaw"]) * Basis(Vector3.BACK, sway) * Basis(Vector3.RIGHT, -z["fall"] * PI / 2.0)
	var at: Vector3 = z["pos"] + Vector3(0, z["y"] + absf(sway) * 0.3, 0)
	_zombie_mm.set_instance_transform(z["slot"], Transform3D(basis, at))
	var tint := Color(1, 1, 1)
	if z["flash"] > 0.0:
		tint = Color(1.8, 0.7, 0.6)
	elif z["chill"] > 0.0:
		tint = Color(0.6, 0.85, 1.6)
	_zombie_mm.set_instance_color(z["slot"], tint)


func _hide_slot(slot: int) -> void:
	if _zombie_mm != null:
		_zombie_mm.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0)))


# --- Shooting -----------------------------------------------------------------------------

func _gun() -> Dictionary:
	return guns[gun_index] if gun_index < guns.size() else {}


func _rate() -> float:
	var g := _gun()
	if g.is_empty():
		return 0.3
	return GUNS[g["id"]]["rate"] / (1.33 if "rattle_rum" in tonics else 1.0)


func _gun_frame(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			_finish_reload()
	var g := _gun()
	if _trigger and not g.is_empty() and GUNS[g["id"]]["auto"] and _cooldown <= 0.0:
		_fire()


func _fire() -> void:
	var g := _gun()
	if g.is_empty() or _cooldown > 0.0 or _reload_t > 0.0:
		return
	if int(g["mag"]) <= 0:
		_sound("click", null, 0.6)
		_reload()
		return
	var spec: Dictionary = GUNS[g["id"]]
	g["mag"] = int(g["mag"]) - 1
	_cooldown = _rate()
	var hand := ctx.get("right") as Node3D
	if hand == null or _arena == null:
		return
	var muzzle := _arena.to_local(hand.global_transform * Vector3(0, 0.02, -spec["len"] - 0.05))
	var ahead := (_arena.global_transform.basis.inverse() * -hand.global_transform.basis.z).normalized()
	var im := _tracer.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for p in int(spec["pellets"]):
		var dir := _spread(ahead, spec["spread"])
		var end := _shoot_ray(muzzle, dir, spec)
		im.surface_set_color(Color(1.0, 0.85, 0.4) if not spec.has("chill") else Color(0.6, 0.9, 1.0))
		im.surface_add_vertex(muzzle)
		im.surface_add_vertex(end)
		if spec.has("chain"):
			_chain_from(end, spec, im)
	im.surface_end()
	_tracer.visible = true
	_tracer_left = 0.05
	if _flash:
		_flash.visible = true
	var kind := "shot_heavy" if spec["damage"] >= 150.0 or spec["pellets"] > 1 else "shot"
	_sound(kind, hand.global_position, 0.9, 1.25 if spec["auto"] else 1.0)
	_pulse("right", 0.6 if kind == "shot" else 1.0, 0.06)
	_update_ammo()
	if int(g["mag"]) <= 0 and int(g["reserve"]) > 0:
		_reload()


func _spread(ahead: Vector3, degrees: float) -> Vector3:
	if degrees <= 0.0:
		return ahead
	var side := ahead.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var up := side.cross(ahead).normalized()
	var a := _rng.randf() * TAU
	var r := deg_to_rad(degrees) * sqrt(_rng.randf())
	return (ahead + (side * cos(a) + up * sin(a)) * tan(r)).normalized()


# One shot along dir: hits the nearest of the dead (through up to "pierce"
# of them) before a wall. Where it stops.
func _shoot_ray(from: Vector3, dir: Vector3, spec: Dictionary) -> Vector3:
	var wall_t := _wall_hit(from, dir)
	var hits := []  # [t, zombie, head]
	for z in _zombies:
		if z["state"] == "dying" or (z["state"] == "rise" and z["t"] < RISE_TIME * 0.5):
			continue
		var base: Vector3 = z["pos"] + Vector3(0, z["y"], 0)
		var th := _ray_sphere(from, dir, base + Vector3(0, HEAD_Y, 0), HEAD_R)
		var tb := _ray_capsule(from, dir, base + Vector3(0, BODY_FROM, 0), base + Vector3(0, BODY_TO, 0), BODY_R)
		var t := minf(th, tb)
		if t < wall_t:
			var head := (from + dir * t).y - base.y > HEAD_Y - HEAD_R - 0.02  # the neck counts
			hits.append([t, z, head])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	var end_t := minf(wall_t, MAX_RANGE)
	var through := 0
	for h in hits:
		_damage(h[1], spec["damage"] * (2.0 if h[2] else 1.0), h[2], spec)
		through += 1
		if through >= int(spec["pierce"]):
			end_t = h[0]
			break
	var end := from + dir * end_t
	if spec.has("splash"):
		_splash(end, spec)
	return end


func _wall_hit(from: Vector3, dir: Vector3) -> float:
	var best_t := INF
	for box: AABB in _walls:
		var t := _ray_box(from, dir, box)
		if t < best_t:
			best_t = t
	if dir.y < -0.001:
		best_t = minf(best_t, -from.y / dir.y)  # the ground
	return best_t


static func _ray_box(from: Vector3, dir: Vector3, box: AABB) -> float:
	var t0 := 0.0
	var t1 := INF
	for i in 3:
		var o := from[i]
		var d := dir[i]
		var lo := box.position[i]
		var hi := box.end[i]
		if absf(d) < 1e-6:
			if o < lo or o > hi:
				return INF
			continue
		var a := (lo - o) / d
		var b := (hi - o) / d
		if a > b:
			var s := a
			a = b
			b = s
		t0 = maxf(t0, a)
		t1 = minf(t1, b)
		if t0 > t1:
			return INF
	return t0


static func _ray_sphere(from: Vector3, dir: Vector3, centre: Vector3, r: float) -> float:
	var oc := from - centre
	var b := oc.dot(dir)
	var c := oc.dot(oc) - r * r
	var h := b * b - c
	if h < 0.0:
		return INF
	var t := -b - sqrt(h)
	return t if t >= 0.0 else INF


# A vertical-ish capsule: the nearest the ray passes the segment a-b.
static func _ray_capsule(from: Vector3, dir: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var best_t := INF
	var steps := 6
	for i in steps + 1:
		var c := a.lerp(b, float(i) / steps)
		var t := _ray_sphere(from, dir, c, r)
		if t < best_t:
			best_t = t
	return best_t


func _damage(z: Dictionary, amount: float, head: bool, spec: Dictionary) -> void:
	if z["state"] == "dying":
		return
	z["hp"] -= amount
	z["flash"] = 0.08
	if spec.has("chill"):
		z["chill"] = spec["chill"]
	if z["hp"] <= 0.0:
		_kill(z, head, spec.get("knife", false))
	else:
		_add_points(10)
		_sound("hit", _arena.to_global(z["pos"] + Vector3(0, 1.2, 0)), 0.5)


func _kill(z: Dictionary, head: bool, knife: bool) -> void:
	kills += 1
	if head:
		headshots += 1
	_add_points(130 if knife else (100 if head else 60))
	_set_state(z, "dying")
	z["chill"] = 0.0
	_sound("hit", _arena.to_global(z["pos"] + Vector3(0, 1.2, 0)), 0.8, 0.7)


func _splash(at: Vector3, spec: Dictionary) -> void:
	var radius: float = spec["splash"]
	for z in _zombies.duplicate():
		if z["state"] == "dying":
			continue
		var centre: Vector3 = z["pos"] + Vector3(0, 1.0, 0)
		var d := centre.distance_to(at)
		if d < radius:
			_damage(z, spec["damage"] * (1.0 - 0.6 * d / radius), false, {"pierce": 1})
	_boom.position = at
	_boom.scale = Vector3.ONE * radius * 0.6
	_boom.visible = true
	_boom_left = 0.18
	_sound("boom", _arena.to_global(at), 1.0)


# The Thunderjug's bolt jumps on to the nearest others.
func _chain_from(at: Vector3, spec: Dictionary, im: ImmediateMesh) -> void:
	var from := at
	var done := []
	for i in int(spec["chain"]):
		var next := {}
		var gap := 4.0
		for z in _zombies:
			if z["state"] == "dying" or z in done:
				continue
			var c: Vector3 = z["pos"] + Vector3(0, 1.2, 0)
			var d := c.distance_to(from)
			if d < gap and d > 0.3:
				gap = d
				next = z
		if next.is_empty():
			break
		done.append(next)
		var c: Vector3 = next["pos"] + Vector3(0, 1.2, 0)
		im.surface_set_color(Color(0.5, 0.7, 1.0))
		im.surface_add_vertex(from)
		im.surface_add_vertex(c)
		_damage(next, spec["damage"] * 0.7, false, {"pierce": 1})
		from = c
	if not done.is_empty():
		_sound("zap", _arena.to_global(at), 0.7)


func _reload() -> void:
	var g := _gun()
	if g.is_empty() or _reload_t > 0.0 or int(g["reserve"]) <= 0 or int(g["mag"]) >= int(GUNS[g["id"]]["mag"]):
		return
	_reload_t = GUNS[g["id"]]["reload"] * (0.5 if "quickhands" in tonics else 1.0)
	_sound("reload", null, 0.6)
	if _ammo_label:
		_ammo_label.text = "reloading"


func _finish_reload() -> void:
	_reload_t = 0.0
	var g := _gun()
	if g.is_empty():
		return
	var need: int = int(GUNS[g["id"]]["mag"]) - int(g["mag"])
	var take := mini(need, int(g["reserve"]))
	g["mag"] = int(g["mag"]) + take
	g["reserve"] = int(g["reserve"]) - take
	_sound("click", null, 0.5, 1.4)
	_update_ammo()


func _switch_gun() -> void:
	if guns.size() < 2:
		return
	gun_index = (gun_index + 1) % guns.size()
	_reload_t = 0.0
	_cooldown = 0.3
	_show_gun()
	_sound("click", null, 0.5, 0.8)


# --- The knife -----------------------------------------------------------------------------

func _knife_frame(delta: float) -> void:
	var hand := ctx.get("left") as Node3D
	if hand == null:
		return
	var tip := _arena.to_local(hand.global_transform * Vector3(0, 0, -0.18))
	var speed := tip.distance_to(_knife_prev) / maxf(delta, 0.001)
	_knife_prev = tip
	_knife_cd = maxf(0.0, _knife_cd - delta)
	if _knife_cd > 0.0 or speed < KNIFE_SPEED or speed > 30.0:
		return
	for z in _zombies:
		if z["state"] in ["dying", "rise", "climb"]:
			continue
		var body: Vector3 = z["pos"] + Vector3(0, clampf(tip.y, 0.6, HEAD_Y), 0)
		if body.distance_to(tip) < KNIFE_REACH:
			_knife_cd = KNIFE_TIME
			_damage(z, KNIFE_DAMAGE, false, {"knife": true, "pierce": 1})
			_pulse("left", 1.0, 0.1)
			return


# --- Using things (A) ------------------------------------------------------------------------

func _use_frame(delta: float, here: Vector3) -> void:
	_use_scan -= delta
	if _use_scan <= 0.0:
		_use_scan = 0.1
		var found := _nearest_use(here)
		if found != _use_target:
			_use_target = found
			_repair_t = 0.0
		_show_prompt()
	if _use_held and _use_target.get("kind") == "window":
		_repair_t += delta
		if _repair_t >= REPAIR_TIME * (0.6 if "quickhands" in tonics else 1.0):
			_repair_t = 0.0
			_repair(_use_target["id"])


func _nearest_use(here: Vector3) -> Dictionary:
	var flat := Vector3(here.x, 0, here.z)
	var found := {}
	var gap := REACH
	for u in _uses:
		if u["kind"] == "door" and not _debris[u["id"]].visible:
			continue
		var d := flat.distance_to(u["at"])
		if d < gap:
			gap = d
			found = u
	return found


func _show_prompt() -> void:
	if _prompt == null:
		return
	var text := _prompt_text(_use_target)
	_prompt.visible = not text.is_empty()
	if text.is_empty():
		return
	_prompt.text = text
	_prompt.position = (_use_target["at"] as Vector3) + Vector3(0, 1.3, 0)


func _prompt_text(u: Dictionary) -> String:
	match u.get("kind", ""):
		"gun":
			var g: Dictionary = GUNS[u["id"]]
			return ("A: ammo for %s  %d" % [g["name"], g["cost"] / 2]) if _holding(u["id"]) >= 0 else "A: buy %s  %d" % [g["name"], g["cost"]]
		"tonic":
			var t: Dictionary = TONICS[u["id"]]
			return "" if u["id"] in tonics else "A: drink %s  %d" % [t["name"], t["cost"]]
		"door":
			var d := _door(u["id"])
			return "A: clear the way  %d" % d["cost"]
		"crate":
			match _crate_state:
				"idle":
					return "A: Lucky Crate  %d" % CRATE_COST
				"offer":
					return "A: take the %s" % GUNS[_crate_gun]["name"]
			return ""
		"window":
			return "Hold A: board up" if int(planks[u["id"]]) < PLANKS else ""
	return ""


func _use() -> void:
	if _use_target.is_empty():
		_use_target = _nearest_use(_cam_local())
	var u := _use_target
	match u.get("kind", ""):
		"gun":
			buy_gun(u["id"])
		"tonic":
			buy_tonic(u["id"])
		"door":
			open_door(u["id"])
		"crate":
			use_crate()
	_show_prompt()


func _holding(id: String) -> int:
	for i in guns.size():
		if guns[i]["id"] == id:
			return i
	return -1


func _spend(cost: int) -> bool:
	if points < cost:
		_sound("deny", null, 0.6)
		return false
	points -= cost
	_sound("buy", null, 0.7)
	points_changed.emit(points)
	_update_hud()
	return true


func _add_points(n: int) -> void:
	points += n
	earned += n
	points_changed.emit(points)
	_update_hud()


# Buys a wall gun, or its ammo when you have it. Whether it was bought.
func buy_gun(id: String) -> bool:
	if not GUNS.has(id) or GUNS[id]["cost"] <= 0:
		return false
	var have := _holding(id)
	var cost: int = GUNS[id]["cost"] / 2 if have >= 0 else GUNS[id]["cost"]
	if have >= 0 and int(guns[have]["reserve"]) >= int(GUNS[id]["reserve"]) and int(guns[have]["mag"]) >= int(GUNS[id]["mag"]):
		return false  # full already
	if not _spend(cost):
		return false
	_give_gun(id)
	return true


func _give_gun(id: String) -> void:
	var have := _holding(id)
	var fresh := {"id": id, "mag": GUNS[id]["mag"], "reserve": GUNS[id]["reserve"]}
	if have >= 0:
		guns[have] = fresh
		gun_index = have
	elif guns.size() < 2:
		guns.append(fresh)
		gun_index = guns.size() - 1
	else:
		guns[gun_index] = fresh
	_reload_t = 0.0
	_show_gun()


func buy_tonic(id: String) -> bool:
	if not TONICS.has(id) or id in tonics:
		return false
	if not _spend(TONICS[id]["cost"]):
		return false
	tonics.append(id)
	if id == "ironbark":
		health = _max_health()
	_sound("gulp", null, 0.8)
	_update_hud()
	return true


func _door(id: String) -> Dictionary:
	for d in DOORS:
		if d["id"] == id:
			return d
	return {}


func open_door(id: String) -> bool:
	var d := _door(id)
	if d.is_empty() or not _debris.has(id) or not _debris[id].visible:
		return false
	if not _spend(d["cost"]):
		return false
	_debris[id].visible = false
	for room in ROOMS:
		if _debris[id].has_meta("label_" + room):
			_debris[id].get_meta("label_" + room).visible = false
	for room in d["rooms"]:
		open_rooms[room] = true
	_sound("rip", _arena.to_global(Vector3(d["at"][0], 1.0, d["at"][1])), 1.0, 0.7)
	return true


func _repair(id: String) -> void:
	if int(planks[id]) >= PLANKS:
		return
	var wnd := _window(id)
	for z in _zombies:
		if z["window"] == id and z["state"] == "climb":
			return  # one's coming through
	planks[id] = int(planks[id]) + 1
	_show_planks(id)
	if _repair_points < REPAIR_CAP:
		_repair_points += 10
		_add_points(10)
	_sound("nail", _arena.to_global(Vector3(wnd["at"][0], 1.3, wnd["at"][1])), 0.8)
	_pulse("right", 0.4, 0.05)
	_show_prompt()


# The Lucky Crate: pay to shuffle, then take what it offers.
func use_crate() -> bool:
	match _crate_state:
		"idle":
			if not _spend(CRATE_COST):
				return false
			var pool := CRATE_GUNS.filter(func(id): return _holding(id) < 0)
			_crate_gun = pool[_rng.randi() % pool.size()]
			_crate_state = "shuffle"
			_crate_t = CRATE_SHUFFLE
			_sound("crate", _arena.to_global(Vector3(CRATE_SPOT["at"][0], 1.0, CRATE_SPOT["at"][1])), 0.9)
			return true
		"offer":
			_give_gun(_crate_gun)
			_crate_state = "idle"
			_crate_label.text = "Lucky Crate\n%d" % CRATE_COST
			if _crate_show:
				_crate_show.visible = false
			_sound("buy", null, 0.8, 1.3)
			return true
	return false


func _crate_frame(delta: float) -> void:
	if _crate_state == "idle" or _crate_label == null:
		return
	_crate_t -= delta
	match _crate_state:
		"shuffle":
			var id: String = CRATE_GUNS[int(_crate_t * 12.0) % CRATE_GUNS.size()]
			_crate_label.text = GUNS[id]["name"]
			_crate_show.mesh = _gun_mesh_for(id)
			_crate_show.visible = true
			if _crate_t <= 0.0:
				_crate_state = "offer"
				_crate_t = CRATE_OFFER
				_crate_label.text = "%s!\nA to take it" % GUNS[_crate_gun]["name"]
				_crate_show.mesh = _gun_mesh_for(_crate_gun)
				_show_prompt()
		"offer":
			if _crate_t <= 0.0:
				_crate_state = "idle"
				_crate_label.text = "Lucky Crate\n%d" % CRATE_COST
				if _crate_show:
					_crate_show.visible = false
				_show_prompt()


# --- What you hold and see --------------------------------------------------------------------

# The gun on the right controller, the knife on the left, the wrist label,
# and the red haze when you're hurt; on while a game runs.
func _hold_gear(on: bool) -> void:
	if not on:
		for node in [_gun_node, _knife, _wrist, _hurt]:
			if node != null and is_instance_valid(node):
				node.queue_free()
		_gun_node = null
		_gun_mesh = null
		_flash = null
		_ammo_label = null
		_knife = null
		_wrist = null
		_hurt = null
		for box in _hidden_boxes:
			if is_instance_valid(box):
				box.visible = true
		_hidden_boxes.clear()
		return
	var right := ctx.get("right") as Node3D
	var left := ctx.get("left") as Node3D
	for hand in [right, left]:
		if hand == null:
			continue
		var box := hand.get_node_or_null("Mesh") as Node3D
		if box != null and box.visible:
			box.visible = false
			_hidden_boxes.append(box)
	if right and _gun_node == null:
		_gun_node = Node3D.new()
		_gun_node.name = "holdout_gun"
		right.add_child(_gun_node)
		_gun_mesh = MeshInstance3D.new()
		_gun_mesh.material_override = _mats["gun"]
		_gun_node.add_child(_gun_mesh)
		_flash = MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.04
		ball.height = 0.08
		ball.radial_segments = 8
		ball.rings = 4
		_flash.mesh = ball
		_flash.material_override = _mats["flash"]
		_flash.visible = false
		_gun_node.add_child(_flash)
		_ammo_label = Label3D.new()
		_ammo_label.font_size = 40
		_ammo_label.pixel_size = 0.0008
		_ammo_label.outline_size = 8
		_ammo_label.position = Vector3(0.0, 0.07, 0.03)
		_ammo_label.rotation_degrees = Vector3(-45, 0, 0)
		_gun_node.add_child(_ammo_label)
	if left and _knife == null:
		_knife = Node3D.new()
		_knife.name = "holdout_knife"
		left.add_child(_knife)
		var blade := _box(_knife, Vector3(0.006, 0.03, 0.16), Vector3(0, 0, -0.1), _mats["blade"])
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_box(_knife, Vector3(0.025, 0.03, 0.09), Vector3(0, 0, 0.02), _mats["grip"])
		_wrist = Label3D.new()
		_wrist.font_size = 40
		_wrist.pixel_size = 0.0009
		_wrist.outline_size = 8
		_wrist.position = Vector3(0.0, 0.06, 0.09)
		_wrist.rotation_degrees = Vector3(-50, 0, 0)
		left.add_child(_wrist)
	var cam := ctx.get("camera") as Node3D
	if cam and _hurt == null:
		_hurt = MeshInstance3D.new()
		var haze := SphereMesh.new()
		haze.radius = 0.25
		haze.height = 0.5
		haze.radial_segments = 12
		haze.rings = 6
		haze.flip_faces = true
		_hurt.mesh = haze
		_hurt.material_override = _mats["hurt"].duplicate()
		_hurt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hurt.visible = false
		cam.add_child(_hurt)


func _show_gun() -> void:
	var g := _gun()
	if _gun_mesh == null or g.is_empty():
		return
	_gun_mesh.mesh = _gun_mesh_for(g["id"])
	_flash.position = Vector3(0, 0.02, -GUNS[g["id"]]["len"] - 0.04)
	_update_ammo()
	_update_hud()


func _update_ammo() -> void:
	var g := _gun()
	if _ammo_label == null or g.is_empty():
		return
	_ammo_label.text = "%d / %d" % [g["mag"], g["reserve"]]
	_ammo_label.modulate = Color(1, 0.4, 0.3) if int(g["mag"]) <= 2 else Color(1, 1, 1)


func _update_hud() -> void:
	if _wrist == null:
		return
	var text := "Round %d\n%d points\nHealth %d" % [maxi(round_number, 1), points, int(round(health))]
	if text != _wrist_text:
		_wrist_text = text
		_wrist.text = text
		_wrist.modulate = Color(1, 0.45, 0.4) if health < _max_health() * 0.5 else Color(1, 0.95, 0.85)


func _show_hurt() -> void:
	if _hurt == null:
		return
	var hurt := 1.0 - health / _max_health()
	_hurt.visible = hurt > 0.05
	if _hurt.visible:
		(_hurt.material_override as StandardMaterial3D).albedo_color = Color(0.6, 0.0, 0.0, clampf(hurt * 0.55, 0.0, 0.5))


func _pulse(hand: String, strength: float, seconds: float) -> void:
	if _controls and _controls.has_method("pulse"):
		_controls.call("pulse", hand, strength, seconds)


# --- Meshes, materials, labels ----------------------------------------------------------

func _make_materials() -> void:
	_mats["ground"] = _flat(Color(0.07, 0.09, 0.06))
	_mats["boards"] = _flat(Color(0.28, 0.2, 0.13))
	_mats["dirt"] = _flat(Color(0.17, 0.14, 0.1))
	_mats["wall"] = _flat(Color(0.33, 0.26, 0.19))
	_mats["plank"] = _flat(Color(0.45, 0.33, 0.2))
	_mats["debris"] = _flat(Color(0.25, 0.22, 0.2))
	_mats["trunk"] = _flat(Color(0.12, 0.09, 0.07))
	_mats["crown"] = _flat(Color(0.05, 0.11, 0.07))
	_mats["chalkboard"] = _flat(Color(0.09, 0.12, 0.1))
	_mats["machine"] = _flat(Color(0.2, 0.18, 0.17))
	_mats["crate"] = _flat(Color(0.35, 0.22, 0.1))
	_mats["lantern"] = _flat_glow(Color(1.0, 0.7, 0.3))
	_mats["chalk"] = _flat_glow(Color(0.85, 0.88, 0.82))
	_mats["blade"] = _flat(Color(0.75, 0.78, 0.8))
	_mats["grip"] = _flat(Color(0.15, 0.1, 0.07))
	var zombie := StandardMaterial3D.new()
	zombie.vertex_color_use_as_albedo = true
	zombie.roughness = 1.0
	_mats["zombie"] = zombie
	var gun := StandardMaterial3D.new()
	gun.vertex_color_use_as_albedo = true
	gun.roughness = 0.6
	gun.metallic = 0.3
	_mats["gun"] = gun
	var tracer := StandardMaterial3D.new()
	tracer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer.vertex_color_use_as_albedo = true
	_mats["tracer"] = tracer
	_mats["flash"] = _flat_glow(Color(1.0, 0.8, 0.35))
	var boom := StandardMaterial3D.new()
	boom.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	boom.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	boom.albedo_color = Color(1.0, 0.5, 0.15, 0.55)
	_mats["boom"] = boom
	var hurt := StandardMaterial3D.new()
	hurt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hurt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hurt.no_depth_test = true
	hurt.albedo_color = Color(0.6, 0.0, 0.0, 0.0)
	hurt.render_priority = 10
	_mats["hurt"] = hurt


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


func _flat_glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node


func _label(parent: Node3D, text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0025
	l.outline_size = 10
	l.modulate = color
	l.double_sided = false  # signs on walls: not read backwards through a doorway
	parent.add_child(l)
	return l


# Boxes into one mesh with vertex colours: one draw.
func _add_box(st: SurfaceTool, centre: Vector3, size: Vector3, color: Color) -> void:
	var h := size / 2.0
	var faces := [
		[Vector3(1, 0, 0), [Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)]],
		[Vector3(0, 1, 0), [Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3(0, -1, 0), [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3(0, 0, 1), [Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
		[Vector3(0, 0, -1), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)]],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var v: Array = f[1]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(color)
			st.set_normal(n)
			st.add_vertex(centre + v[i])


# One of the dead: ragged clothes, grey-green skin, arms out, dim yellow
# eyes. About 1.75 m tall, facing -z.
func _zombie_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin := Color(0.42, 0.5, 0.38)
	var dark := Color(0.32, 0.38, 0.3)
	var shirt := Color(0.36, 0.31, 0.24)
	var trousers := Color(0.17, 0.16, 0.18)
	_add_box(st, Vector3(-0.1, 0.42, 0.0), Vector3(0.14, 0.84, 0.16), trousers)
	_add_box(st, Vector3(0.1, 0.42, 0.02), Vector3(0.14, 0.84, 0.16), trousers)
	_add_box(st, Vector3(0.0, 1.12, 0.0), Vector3(0.4, 0.6, 0.22), shirt)
	_add_box(st, Vector3(0.05, 0.88, -0.1), Vector3(0.22, 0.14, 0.04), dark)  # a tear in the shirt
	_add_box(st, Vector3(-0.25, 1.33, -0.24), Vector3(0.1, 0.1, 0.56), skin)
	_add_box(st, Vector3(0.25, 1.28, -0.2), Vector3(0.1, 0.1, 0.5), skin)
	_add_box(st, Vector3(-0.25, 1.33, -0.55), Vector3(0.11, 0.06, 0.1), dark)
	_add_box(st, Vector3(0.25, 1.28, -0.48), Vector3(0.11, 0.06, 0.1), dark)
	_add_box(st, Vector3(0.0, 1.45, 0.0), Vector3(0.1, 0.06, 0.1), skin)  # neck
	_add_box(st, Vector3(0.0, 1.6, 0.0), Vector3(0.24, 0.26, 0.24), skin)
	_add_box(st, Vector3(0.0, 1.49, -0.04), Vector3(0.18, 0.05, 0.17), dark)  # jaw hanging
	_add_box(st, Vector3(-0.06, 1.63, -0.121), Vector3(0.05, 0.03, 0.01), Color(1.0, 0.85, 0.25))
	_add_box(st, Vector3(0.06, 1.63, -0.121), Vector3(0.05, 0.03, 0.01), Color(1.0, 0.85, 0.25))
	return st.commit()


# A gun from a few boxes, pointing -z from the hand: body, barrel, grip,
# and a stock or magazine for the bigger ones. Made once each.
func _gun_mesh_for(id: String) -> ArrayMesh:
	if _gun_meshes.has(id):
		return _gun_meshes[id]
	var spec: Dictionary = GUNS[id]
	var c: Color = spec["color"]
	var metal := Color(0.22, 0.22, 0.24)
	var length: float = spec["len"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(st, Vector3(0, 0.02, -length * 0.35), Vector3(0.045, 0.06, length * 0.6), c)
	_add_box(st, Vector3(0, 0.03, -length * 0.8), Vector3(0.025, 0.025, length * 0.45), metal)
	_add_box(st, Vector3(0, -0.05, 0.0), Vector3(0.035, 0.11, 0.045), c.darkened(0.3))
	if length > 0.3:
		_add_box(st, Vector3(0, 0.0, 0.12), Vector3(0.04, 0.07, 0.18), c.darkened(0.2))
	if spec["mag"] >= 20:
		_add_box(st, Vector3(0, -0.06, -length * 0.3), Vector3(0.03, 0.1, 0.05), metal)
	if spec.has("chain") or spec.has("chill"):
		_add_box(st, Vector3(0, 0.03, -length * 0.5), Vector3(0.07, 0.07, 0.07), c.lightened(0.4))
	if spec.has("splash"):
		_add_box(st, Vector3(0, 0.03, -length * 0.75), Vector3(0.08, 0.08, length * 0.45), c)
	var mesh := st.commit()
	_gun_meshes[id] = mesh
	return mesh


# --- Sounds --------------------------------------------------------------------------------
# Made once at load, short and small; played through audio.gd (3D where
# they happen) or, without it, through this module's own players.

func _sound(kind: String, at, volume := 1.0, pitch := 1.0) -> void:
	if not settings["sounds"] or not _sounds.has(kind):
		return
	var stream: AudioStream = _sounds[kind]
	if _audio and is_instance_valid(_audio):
		if at is Vector3:
			_audio.call("play_at", stream, at, {"bus": "effects", "volume": volume, "pitch": pitch})
		else:
			_audio.call("play_2d", stream, "effects", volume, pitch)
		return
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream
	p.volume_db = linear_to_db(maxf(volume, 0.01))
	p.pitch_scale = pitch
	p.play()


func _make_sounds() -> void:
	_sounds["shot"] = _synth(0.22, {"noise": 0.9, "noise_decay": 18.0, "tone": [180.0, 60.0], "tone_amp": 0.6, "tone_decay": 14.0, "low": 4500.0})
	_sounds["shot_heavy"] = _synth(0.45, {"noise": 1.0, "noise_decay": 9.0, "tone": [120.0, 40.0], "tone_amp": 0.8, "tone_decay": 8.0, "low": 3000.0})
	_sounds["click"] = _synth(0.05, {"noise": 0.6, "noise_decay": 120.0, "tone": [2400.0, 1800.0], "tone_amp": 0.3, "tone_decay": 90.0, "low": 9000.0})
	_sounds["reload"] = _synth(0.35, {"noise": 0.5, "noise_decay": 30.0, "tone": [900.0, 500.0], "tone_amp": 0.2, "tone_decay": 25.0, "low": 6000.0, "second": 0.2})
	_sounds["hit"] = _synth(0.18, {"noise": 0.6, "noise_decay": 25.0, "tone": [140.0, 70.0], "tone_amp": 0.7, "tone_decay": 20.0, "low": 1500.0})
	_sounds["groan"] = _synth(1.1, {"noise": 0.15, "noise_decay": 1.5, "tone": [95.0, 70.0], "tone_amp": 0.7, "tone_decay": 1.6, "low": 900.0, "saw": true, "wobble": 5.0, "attack": 0.25})
	_sounds["rip"] = _synth(0.4, {"noise": 0.9, "noise_decay": 7.0, "tone": [300.0, 120.0], "tone_amp": 0.3, "tone_decay": 10.0, "low": 2500.0, "crackle": true})
	_sounds["nail"] = _synth(0.15, {"noise": 0.5, "noise_decay": 40.0, "tone": [700.0, 650.0], "tone_amp": 0.6, "tone_decay": 30.0, "low": 7000.0})
	_sounds["bell"] = _synth(2.0, {"noise": 0.0, "tone": [220.0, 218.0], "tone_amp": 0.5, "tone_decay": 1.4, "low": 4000.0, "overtone": 2.76})
	_sounds["buy"] = _synth(0.35, {"noise": 0.0, "tone": [660.0, 990.0], "tone_amp": 0.4, "tone_decay": 6.0, "low": 8000.0})
	_sounds["deny"] = _synth(0.3, {"noise": 0.0, "tone": [180.0, 150.0], "tone_amp": 0.45, "tone_decay": 6.0, "low": 3000.0, "saw": true})
	_sounds["gulp"] = _synth(0.5, {"noise": 0.2, "noise_decay": 8.0, "tone": [300.0, 520.0], "tone_amp": 0.5, "tone_decay": 5.0, "low": 2500.0, "wobble": 12.0})
	_sounds["crate"] = _synth(2.2, {"noise": 0.0, "tone": [520.0, 880.0], "tone_amp": 0.35, "tone_decay": 0.9, "low": 6000.0, "wobble": 9.0, "overtone": 1.5})
	_sounds["hurt"] = _synth(0.3, {"noise": 0.7, "noise_decay": 12.0, "tone": [90.0, 50.0], "tone_amp": 0.8, "tone_decay": 9.0, "low": 1200.0})
	_sounds["zap"] = _synth(0.4, {"noise": 0.8, "noise_decay": 9.0, "tone": [1200.0, 300.0], "tone_amp": 0.4, "tone_decay": 8.0, "low": 9000.0, "crackle": true})
	_sounds["boom"] = _synth(0.9, {"noise": 1.0, "noise_decay": 4.0, "tone": [80.0, 30.0], "tone_amp": 1.0, "tone_decay": 4.0, "low": 1200.0})


# A short sound: noise (low-passed, maybe crackling) and a tone sliding from
# one pitch to another (sine, or saw-like; maybe wobbling; maybe with an
# overtone, for the bell), each fading at its own rate. 22 kHz, 16-bit mono.
func _synth(seconds: float, p: Dictionary) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p)
	var phase := 0.0
	var phase2 := 0.0
	var low := 0.0
	var k := 1.0 - exp(-TAU * float(p.get("low", 5000.0)) / rate)
	var tone: Array = p.get("tone", [0.0, 0.0])
	var attack: float = p.get("attack", 0.005)
	var second: float = p.get("second", -1.0)
	for i in count:
		var t := float(i) / rate
		var f := lerpf(tone[0], tone[1], t / seconds)
		if p.has("wobble"):
			f *= 1.0 + 0.06 * sin(TAU * float(p["wobble"]) * t)
		phase = fmod(phase + f / rate, 1.0)
		var wave := (phase * 2.0 - 1.0) * 0.7 + sin(TAU * phase) * 0.3 if p.get("saw", false) else sin(TAU * phase)
		if p.has("overtone"):
			phase2 = fmod(phase2 + f * float(p["overtone"]) / rate, 1.0)
			wave = wave * 0.7 + sin(TAU * phase2) * 0.3
		var n := rng.randf_range(-1.0, 1.0)
		if p.get("crackle", false) and rng.randf() < 0.85:
			n *= 0.2
		var since := t
		if second > 0.0 and t >= second:
			since = t - second  # a second click (the reload)
		var v := wave * float(p.get("tone_amp", 0.0)) * exp(-float(p.get("tone_decay", 5.0)) * since) \
			+ n * float(p.get("noise", 0.0)) * exp(-float(p.get("noise_decay", 10.0)) * since)
		v *= minf(1.0, t / attack)
		v *= minf(1.0, (seconds - t) / 0.02)  # no click at the end
		low += (v - low) * k
		var s := clampi(int(tanh(low * 1.2) * 30000.0), -32768, 32767)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
