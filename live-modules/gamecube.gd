extends SlopitectModule

# Slopitect live module: gamecube, the GameCube's start-up on a TV in VR.
# Plays the console's own boot intro (the cube drop, the rolling "G", the
# logo) and then the cube menu, as rebuilt in Rust by isaac's GameCoob-Bios
# from the decompiled IPL. The Rust runs in the APK's gamecoob extension
# (game/addons/gamecoob, class GameCoob) on threads of its own at the
# console's 60 frames a second, drawing each picture on the CPU at 640x448;
# this module shows the newest one on a TV that stands in front of you, so
# a slow picture never holds up the headset's frame.
#
# Your own dump: the intro's models, textures and layouts are read from the
# ipl.bin you dumped from your own GameCube, at Slopitect/gamecube/ipl.bin
# (on the headset /sdcard/Slopitect/gamecube/ipl.bin). Nothing from Nintendo
# is in the app, the repo or this module. No dump: Start says where to put it.
#
# Buttons while the TV is on: right A is the pad's A (hold it while the cube
# rolls to spin it, as on the console), right B is B, left Y is START. The
# GameCube window (the Menu's GameCube tile) has the d-pad, A, B and START
# as buttons for the cube menu, and Skip intro and Stop. The sticks still
# walk and turn. Game Play lists nothing to boot and Options and the
# calendar change nothing outside the console; there's no sound yet (the
# Rust has none). Without vrui the commands still work; without controls
# only the window's buttons press.
#
# Settings (the Settings window, kept in user://gamecube.json): raster
# threads, how many CPU cores draw each picture (the Quest 1 has 4 fast ones).
# Signals: started(), stopped(why) (why "" when you stopped it).

signal started()
signal stopped(why: String)

const PANEL := "gamecube"
const TITLE := "GameCube"
const SETTINGS_PATH := "user://gamecube.json"
const APP_THING := "slopitect_app_thing"  # lib's: a piece in the world's object list
const DUMP := "gamecube/ipl.bin"  # in the Slopitect folder
const DUMP_BYTES := 2 * 1024 * 1024  # a GameCube IPL is 2 MiB
const DEFAULTS := {"threads": 3}
const THREADS_RANGE := [1, 4]
const BITS := {"a": 1, "b": 2, "start": 4, "up": 8, "down": 16, "left": 32, "right": 64}
const ACTIONS := {"right_a": "a", "right_b": "b", "left_y": "start"}  # controls.gd action -> pad button
const TAP_SECONDS := 0.15  # a window button holds its pad button this long (A spins the cube while held)
const SCREEN := Vector2(1.6, 1.2)  # metres, 4:3 like a TV of the time
const SCREEN_AHEAD := 2.2  # metres in front of you
const SIZE := Vector2(0.5, 0.42)  # the window
const BUTTON_H := 0.06
const STATES := ["off", "intro", "menu", "stopped"]

var running := false
var settings := DEFAULTS.duplicate()

var _console: RefCounted  # the extension's GameCoob, while it runs
var _tv: Node3D
var _image: Image
var _texture: ImageTexture
var _held := {}  # pad button -> true while its controller button is down
var _taps := {}  # pad button -> seconds left of a window button's press
var _pressed := 0  # pad bits pressed since the last frame
var _clock_left := 0.0
var _status_left := 0.0
var _lib: SlopitectModule
var _vrui: SlopitectModule


func setup() -> String:
	register("gamecube_start", _start, "turn the GameCube on: the boot intro then the cube menu on a TV in front of you, from your own dump at Slopitect/gamecube/ipl.bin (needs the APK's gamecoob extension)")
	register("gamecube_stop", _stop_command, "turn the GameCube off")
	register("gamecube_pad", _pad, "press a pad button: button = a, b, start, up, down, left or right")
	register("gamecube_skip", _skip, "skip the intro, straight to the cube menu")
	register("gamecube_status", _status, "on or off, intro or menu, logic frames, pictures drawn, the last picture's draw time and threads; whether the extension and the dump are there")
	register("gamecube_set", _set_command, "the settings (usable in the headset): threads (raster threads, 1 to 4)")
	register("gamecube_do", _do, "the GameCube window: act = toggle (show or hide it), show")
	set_process(false)
	return ""


func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		_vrui = null
		return
	var saved = lib.read_json(SETTINGS_PATH)
	if saved is Dictionary and saved.get("threads") is float:
		settings["threads"] = clampi(int(saved["threads"]), THREADS_RANGE[0], THREADS_RANGE[1])
	lib.watch(self, "vrui", _vrui_here, _vrui_gone)
	lib.touch(self)


func _vrui_here(vrui: SlopitectModule) -> void:
	_vrui = vrui


func _vrui_gone(_old: SlopitectModule) -> void:
	_vrui = null


func _exit_tree() -> void:
	_turn_off()
	ctx["server"].run({"cmd": "ui_remove", "id_panel": PANEL})


# --- Menu, Settings, buttons ---------------------------------------------------------

func menu_info() -> Dictionary:
	return {"id": "gamecube", "label": TITLE, "order": 65, "action": {"cmd": "gamecube_do", "act": "toggle"}}


func settings_info() -> Dictionary:
	return {"title": TITLE, "order": 50, "settings": [
		{"id": "threads", "type": "slider", "label": "Raster threads", "min": THREADS_RANGE[0], "max": THREADS_RANGE[1], "step": 1,
			"value": settings["threads"], "set": {"cmd": "gamecube_set", "threads": "{value}"}},
		{"id": "start", "type": "button", "label": "Turn on", "set": {"cmd": "gamecube_start"}},
		{"id": "stop", "type": "button", "label": "Turn off", "set": {"cmd": "gamecube_stop"}},
	]}


func action_order() -> int:
	return 20  # ahead of the usual takers, but only while the TV is on


func on_action(action: String, down: bool) -> bool:
	if not ACTIONS.has(action) or (down and not running):
		return false
	var button: String = ACTIONS[action]
	if down:
		_held[button] = true
		_pressed |= BITS[button]
	else:
		_held.erase(button)
	return true


# --- Commands ----------------------------------------------------------------------

func _start(_request: Dictionary) -> Dictionary:
	if running:
		_place_tv()
		return {"ok": true, "already": true}
	if not ClassDB.class_exists("GameCoob"):
		return {"ok": false, "error": "this APK has no gamecoob extension yet; it comes with the next APK build"}
	var path := _dump_path()
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "no dump at %s: put the ipl.bin you dumped from your own GameCube there" % path}
	var rom := FileAccess.get_file_as_bytes(path)
	if rom.size() != DUMP_BYTES:
		return {"ok": false, "error": "%s is %d bytes; a GameCube IPL dump is %d" % [path, rom.size(), DUMP_BYTES]}
	var console: RefCounted = ClassDB.instantiate("GameCoob")
	console.call("set_threads", settings["threads"])
	_send_clock(console)
	var problem: String = console.call("open", rom)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	_console = console
	_make_tv()
	_place_tv()
	running = true
	_held.clear()
	_taps.clear()
	_pressed = 0
	_clock_left = 1.0
	_status_left = 0.0
	set_process(true)
	print("Slopitect gamecube: on, from %s" % path)
	started.emit()
	_show_window()
	return {"ok": true}


func _stop_command(_request: Dictionary) -> Dictionary:
	if not running:
		return {"ok": true, "already": true}
	_turn_off()
	stopped.emit("")
	_rebuild_if_shown()
	return {"ok": true}


func _pad(request: Dictionary) -> Dictionary:
	var button = request.get("button")
	if not BITS.has(button):
		return {"ok": false, "error": "\"button\" must be one of %s" % [BITS.keys()]}
	if not running:
		return {"ok": false, "error": "the GameCube is off (gamecube_start)"}
	_taps[button] = TAP_SECONDS
	_pressed |= BITS[button]
	return {"ok": true}


func _skip(_request: Dictionary) -> Dictionary:
	if not running:
		return {"ok": false, "error": "the GameCube is off (gamecube_start)"}
	_console.call("skip")
	return {"ok": true}


func _status(_request: Dictionary) -> Dictionary:
	var out := {"ok": true, "on": running, "extension": ClassDB.class_exists("GameCoob"), "dump": FileAccess.file_exists(_dump_path()),
		"dump_path": _dump_path(), "threads": settings["threads"]}
	if _console != null:
		out["state"] = STATES[clampi(int(_console.call("state")), 0, STATES.size() - 1)]
		out["logic_frames"] = _console.call("logic_frames")
		out["pictures"] = _console.call("pictures")
		out["draw_ms"] = snappedf(_console.call("draw_ms"), 0.1)
	return out


func _set_command(request: Dictionary) -> Dictionary:
	if not request.has("threads"):
		return {"ok": false, "error": "give threads (1 to 4)"}
	var threads = request["threads"]
	if typeof(threads) == TYPE_STRING and String(threads).is_valid_float():
		threads = float(threads)
	if not (threads is float or threads is int) or threads < THREADS_RANGE[0] or threads > THREADS_RANGE[1]:
		return {"ok": false, "error": "threads must be a number from 1 to 4"}
	settings["threads"] = int(threads)
	if _console != null:
		_console.call("set_threads", settings["threads"])
	if _lib:
		_lib.write_json(SETTINGS_PATH, settings)
		_lib.touch(self)
	return {"ok": true, "threads": settings["threads"]}


func _do(request: Dictionary) -> Dictionary:
	match request.get("act"):
		"toggle":
			if _shown():
				return ctx["server"].run({"cmd": "ui_show", "id_panel": PANEL, "visible": false})
			return _show_window()
		"show":
			return _show_window()
	return {"ok": false, "error": "\"act\" must be toggle or show"}


# --- Each frame while on ------------------------------------------------------------

func _process(delta: float) -> void:
	var state := int(_console.call("state"))
	if state == 3 or state == 0:
		var why: String = _console.call("why")
		push_error("Slopitect gamecube: stopped by itself: %s" % why)
		_turn_off()
		stopped.emit(why if not why.is_empty() else "the console stopped")
		_rebuild_if_shown()
		return
	var held := 0
	for button in _held:
		held |= BITS[button]
	for button in _taps.keys():
		held |= BITS[button]
		_taps[button] -= delta
		if _taps[button] <= 0.0:
			_taps.erase(button)
	_console.call("input", held, _pressed)
	_pressed = 0
	var picture: PackedByteArray = _console.call("picture")
	if not picture.is_empty():
		_image.set_data(_image.get_width(), _image.get_height(), false, Image.FORMAT_RGB8, picture)
		_texture.update(_image)
	_clock_left -= delta
	if _clock_left <= 0.0:
		_clock_left = 1.0
		_send_clock(_console)
	_status_left -= delta
	if _status_left <= 0.0 and _vrui != null and _shown():
		_status_left = 1.0
		_vrui.call("set_text", PANEL, "status", _status_line())


func _send_clock(console: RefCounted) -> void:
	var t := Time.get_datetime_dict_from_system()
	console.call("set_clock", t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"])


func _turn_off() -> void:
	running = false
	set_process(false)
	_held.clear()
	_taps.clear()
	if _console != null:
		_console.call("close")
		_console = null
	if _tv != null and is_instance_valid(_tv):
		_tv.queue_free()
	_tv = null
	_image = null
	_texture = null


func _dump_path() -> String:
	var home: String = _lib.home() if _lib else OS.get_user_data_dir() + "/files_home"
	return home.path_join(DUMP)


# --- The TV ---------------------------------------------------------------------------

func _make_tv() -> void:
	var w: int = _console.call("width")
	var h: int = _console.call("height")
	_image = Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	_texture = ImageTexture.create_from_image(_image)
	_tv = Node3D.new()
	_tv.name = "tv"
	_tv.set_meta(APP_THING, "gamecube_tv")
	add_child(_tv)  # its own, not World's: save never keeps it
	var screen := MeshInstance3D.new()
	screen.name = "screen"
	var quad := QuadMesh.new()
	quad.size = SCREEN
	screen.mesh = quad
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_texture = _texture
	glass.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	screen.material_override = glass
	_tv.add_child(screen)
	var case := MeshInstance3D.new()
	case.name = "case"
	case.set_meta(APP_THING, "gamecube_tv_case")
	var box := BoxMesh.new()
	box.size = Vector3(SCREEN.x + 0.16, SCREEN.y + 0.16, 0.3)
	case.mesh = box
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.12, 0.11, 0.16)
	case.material_override = plastic
	case.position = Vector3(0, 0, -0.151)
	_tv.add_child(case)
	# The TV and its case go in the world's object list (lib's), so they can
	# be picked, moved, textured and hidden like any thing. The screen stays
	# out: a texture on it would cover the picture.
	if _lib and _lib.has_method("add_app_things"):
		_lib.add_app_things(self)


# In front of you at eye height, facing you.
func _place_tv() -> void:
	var cam: Node3D = ctx.get("camera")
	if _tv == null or cam == null or not is_instance_valid(cam):
		return
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var at := cam.global_position + fwd * SCREEN_AHEAD
	_tv.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP, true), at)


# --- The window -------------------------------------------------------------------------

func _shown() -> bool:
	return ctx["server"].run({"cmd": "ui_get", "id_panel": PANEL}).get("panel", {}).get("visible", false)


func _rebuild_if_shown() -> void:
	if _shown():
		_build()


func _show_window() -> Dictionary:
	var problem := _build()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return ctx["server"].run({"cmd": "ui_show", "id_panel": PANEL, "visible": true})


func _status_line() -> String:
	if not running:
		if not ClassDB.class_exists("GameCoob"):
			return "Needs the APK with the gamecoob extension."
		if not FileAccess.file_exists(_dump_path()):
			return "Put your ipl.bin in Slopitect/gamecube/."
		return "Off."
	var state: String = STATES[clampi(int(_console.call("state")), 0, STATES.size() - 1)]
	return "%s, picture %.1f ms" % [state.capitalize(), _console.call("draw_ms")]


func _button(id: String, label: String, x: float, y: float, w: float, action: Dictionary, color := "button") -> Dictionary:
	return {"type": "button", "id": id, "label": label, "at": [x, y], "size": [w, BUTTON_H], "action": action, "color": color}


func _build() -> String:
	if ctx["modules"].module("vrui") == null and ctx["modules"].module("ui") == null:
		return "the GameCube window needs the vrui module"
	var pad := func(button: String) -> Dictionary: return {"cmd": "gamecube_pad", "button": button}
	var elements := [{"type": "text", "id": "status", "text": _status_line(), "at": [0.0, 0.15], "width": SIZE.x - 0.04, "color": "muted"}]
	if running:
		elements.append_array([
			_button("up", "Up", -0.12, 0.07, 0.1, pad.call("up")),
			_button("left", "Left", -0.19, 0.0, 0.1, pad.call("left")),
			_button("right", "Right", -0.05, 0.0, 0.1, pad.call("right")),
			_button("down", "Down", -0.12, -0.07, 0.1, pad.call("down")),
			_button("a", "A", 0.15, 0.03, 0.1, pad.call("a"), "ok"),
			_button("b", "B", 0.06, -0.04, 0.08, pad.call("b")),
			_button("start", "Start", 0.17, -0.07, 0.12, pad.call("start")),
			_button("skip", "Skip intro", -0.11, -0.16, 0.2, {"cmd": "gamecube_skip"}),
			_button("off", "Turn off", 0.11, -0.16, 0.18, {"cmd": "gamecube_stop"}, "danger"),
		])
	else:
		elements.append(_button("on", "Turn on", 0.0, -0.05, 0.24, {"cmd": "gamecube_start"}, "ok"))
	var existing: Dictionary = ctx["server"].run({"cmd": "ui_get", "id_panel": PANEL})
	if not existing.get("ok", false):
		var added: Dictionary = ctx["server"].run({"cmd": "ui_add", "id_panel": PANEL, "title": TITLE, "place": "front", "distance": 0.6, "height": -0.25,
			"size": [SIZE.x, SIZE.y], "chrome": true, "visible": false, "elements": elements})
		return "" if added.get("ok", false) else str(added.get("error", "ui_add failed"))
	var updated: Dictionary = ctx["server"].run({"cmd": "ui_update", "id_panel": PANEL, "elements": elements})
	return "" if updated.get("ok", false) else str(updated.get("error", "ui_update failed"))
