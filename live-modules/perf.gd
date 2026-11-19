extends SlopitectModule

# Slopitect live module: perf.
# Shows how well the app runs, from inside it:
#   perf_status   frame rate, frame times and hitches over the last 10 s, the
#                 CPU time of scripts and physics, draw calls, objects and
#                 memory
#   perf_watch    starts (or stops) timing each module's _process and
#                 _physics_process; perf_modules lists them, costliest first
#   perf_load     how long each live module's file takes to compile
# Timing a module works by two small marker nodes beside it under the
# module loader, one just before it and one just after, with its priority:
# Godot runs _process in priority, then tree order, so the time between the
# two is that module's _process plus everything under it. An empty pair at
# the end measures what the markers themselves cost, and that is taken off.
# What a module hangs elsewhere (under the world, a hand), its _input and
# the GPU's work aren't counted; OVR Metrics Tool shows the GPU.
# Watching costs a little itself (two tiny calls per module per frame), so
# it is off until perf_watch turns it on, and off again after a restart.
#
# It also sets how the headset draws and how fast it runs (perf_config, from
# the PC only; kept in user://perf.json):
#   foveation          off, low, medium or high: the edges of each eye's view,
#                      which the lenses blur anyway, are drawn at a lower
#                      resolution, so the graphics chip has less to do
#   foveation_dynamic  true: the headset only lowers the edges as far as
#                      foveation allows when the graphics chip is busy
#   cpu_level,         power_savings, sustained_low, sustained_high or boost:
#   gpu_level          the clock speed asked of the headset (OpenXR
#                      performance settings); sustained_high is the fastest
#                      the Quest can keep up without overheating
#   physics_match_display  true: physics ticks as often as the headset shows
#                      frames (72 a second on the Quest 1, not Godot's 60),
#                      so things moved by physics don't judder every fifth frame
# The APK leaves foveation off and the clocks to the headset; these are put
# in place when the module loads and again when the VR session starts.
# Unloading puts foveation back; clock levels can't be read back, so they
# stay as last asked (perf_config sets them).

const HISTORY := 10.0  # seconds of frame times perf_status looks back over
const CHECK_EVERY := 1.0  # seconds between checks that the markers still fit the modules
const EMPTY := "(markers)"  # the empty pair's name
const SETTINGS_PATH := "user://perf.json"
const FOVEATION := {"off": 0, "low": 1, "medium": 2, "high": 3}
const LEVELS := {"power_savings": 0, "sustained_low": 1, "sustained_high": 2, "boost": 3}
const DEFAULTS := {"foveation": "high", "foveation_dynamic": true, "cpu_level": "sustained_high", "gpu_level": "sustained_high",
	"physics_match_display": true}


# Notes when this frame reached it.
class Before extends Node:
	var stamp := 0
	var physics_stamp := 0

	func _process(_delta: float) -> void:
		stamp = Time.get_ticks_usec()

	func _physics_process(_delta: float) -> void:
		physics_stamp = Time.get_ticks_usec()


# Adds up the time since its Before was reached, frame by frame.
class After extends Node:
	var before: Before
	var frames := 0
	var total := 0  # microseconds
	var worst := 0
	var ticks := 0
	var physics_total := 0
	var physics_worst := 0

	func _process(_delta: float) -> void:
		var spent := Time.get_ticks_usec() - before.stamp
		frames += 1
		total += spent
		worst = maxi(worst, spent)

	func _physics_process(_delta: float) -> void:
		var spent := Time.get_ticks_usec() - before.physics_stamp
		ticks += 1
		physics_total += spent
		physics_worst = maxi(physics_worst, spent)

	func clear() -> void:
		frames = 0
		total = 0
		worst = 0
		ticks = 0
		physics_total = 0
		physics_worst = 0


var _frame_ms := PackedFloat32Array()  # frame times; the last HISTORY seconds start at _first
var _frame_at := PackedFloat64Array()  # when each was, in seconds
var _first := 0  # the oldest frame still kept; older ones are cut off in one go now and then, not every frame
var settings := DEFAULTS.duplicate()
var _lib: SlopitectModule
var _xr: XRInterface
var _was_foveation := -1  # foveation as it was before this module set it, put back when it unloads
var _was_dynamic := false
var _was_physics_hz := 0  # physics ticks a second before this module changed them
var _level_changes := []  # what the headset said about its clocks (it slows them when it gets hot)
var _watching := false
var _watch_since := 0.0
var _pairs := {}  # module name -> [Before, After]
var _layout := ""  # the modules, their order and priorities the markers were put in for
var _check_in := 0.0


func setup() -> String:
	register("perf_status", _status, "how well the app runs now: frame rate, frame times and hitches over the last 10 s, script and physics time, draw calls, objects, memory")
	register("perf_watch", _watch, "time each module's _process and _physics_process: on true starts (clearing what was timed), on false stops")
	register("perf_modules", _modules, "what each module costs per frame since perf_watch started, costliest first; reset true starts the count again")
	register("perf_load", _load_times, "how long each live module's file takes to compile (the app stalls while it runs): optional name for just one")
	register("perf_config", _config, "from the PC only: any of foveation (off, low, medium, high: the edges of the view drawn at lower resolution), foveation_dynamic (true: only when the graphics chip is busy), cpu_level and gpu_level (power_savings, sustained_low, sustained_high, boost), physics_match_display (true: physics ticks at the headset's frame rate), or reset true")
	_was_physics_hz = Engine.physics_ticks_per_second
	_xr = XRServer.find_interface("OpenXR")
	if _xr != null:
		_was_foveation = int(_xr.get("foveation_level"))
		_was_dynamic = bool(_xr.get("foveation_dynamic"))
		_xr.connect("session_begun", _apply)
		_xr.connect("refresh_rate_changed", _refresh_changed)
		_xr.connect("cpu_level_changed", _cpu_level_changed)
		_xr.connect("gpu_level_changed", _gpu_level_changed)
	_apply()
	return ""


func lib_ready(lib) -> void:
	_lib = lib
	if lib != null:
		_load()
		_apply()


func _exit_tree() -> void:
	_remove_markers()
	if _xr != null and is_instance_valid(_xr):
		for pair in [["session_begun", _apply], ["refresh_rate_changed", _refresh_changed], ["cpu_level_changed", _cpu_level_changed], ["gpu_level_changed", _gpu_level_changed]]:
			if _xr.is_connected(pair[0], pair[1]):
				_xr.disconnect(pair[0], pair[1])
		if _xr.is_initialized() and _was_foveation >= 0:
			_xr.set("foveation_level", _was_foveation)
			_xr.set("foveation_dynamic", _was_dynamic)
	if _was_physics_hz > 0:
		Engine.physics_ticks_per_second = _was_physics_hz


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_frame_ms.append(delta * 1000.0)
	_frame_at.append(now)
	while _first < _frame_at.size() and _frame_at[_first] < now - HISTORY:
		_first += 1
	# Copying the kept frames down every frame made new arrays 72 times a
	# second; once the old ones are as many as the kept ones is enough.
	if _first > 0 and _first * 2 >= _frame_at.size():
		_frame_ms = _frame_ms.slice(_first)
		_frame_at = _frame_at.slice(_first)
		_first = 0
	if _watching:
		_check_in -= delta
		if _check_in <= 0.0:
			_check_in = CHECK_EVERY
			_place_markers()


# --- Markers -----------------------------------------------------------------------

func _loaded_modules() -> Array:
	return ctx["modules"].get_children().filter(func(child): return child is SlopitectModule)


# Puts a pair of markers around each module, again only when a module came,
# went or changed its priority (the counts so far are kept for the rest).
func _place_markers() -> void:
	var modules := _loaded_modules()
	var layout := JSON.stringify(modules.map(func(m): return [String(m.name), m.process_priority, m.process_physics_priority]))
	if layout == _layout:
		return
	var kept := {}
	for module_name in _pairs:
		kept[module_name] = _pairs[module_name][1]
	_remove_markers()
	_layout = layout
	var loader: Node = ctx["modules"]
	for module in modules:
		_add_pair(String(module.name), module.process_priority, module.process_physics_priority, kept)
		var pair: Array = _pairs[String(module.name)]
		loader.move_child(pair[0], module.get_index())
		loader.move_child(pair[1], module.get_index() + 1)
	_add_pair(EMPTY, 0, 0, kept)  # at the end, with nothing between


func _add_pair(module_name: String, priority: int, physics_priority: int, kept: Dictionary) -> void:
	var before := Before.new()
	var after := After.new()
	before.name = "_perf_before_" + module_name.validate_node_name()
	after.name = "_perf_after_" + module_name.validate_node_name()
	after.before = before
	for marker in [before, after]:
		marker.process_priority = priority
		marker.process_physics_priority = physics_priority
		ctx["modules"].add_child(marker)
	if kept.has(module_name):
		var old: After = kept[module_name]
		for field in ["frames", "total", "worst", "ticks", "physics_total", "physics_worst"]:
			after.set(field, old.get(field))
	_pairs[module_name] = [before, after]


func _remove_markers() -> void:
	for pair in _pairs.values():
		for marker in pair:
			if is_instance_valid(marker):
				marker.get_parent().remove_child(marker)
				marker.queue_free()
	_pairs.clear()
	_layout = ""


# --- How the headset draws and how fast it runs ------------------------------------

func _apply() -> void:
	if _xr == null or not is_instance_valid(_xr) or not _xr.is_initialized():
		return  # no headset (a PC test): nothing to set
	_xr.set("foveation_level", FOVEATION[settings["foveation"]])
	_xr.set("foveation_dynamic", settings["foveation_dynamic"])
	_xr.call("set_cpu_level", LEVELS[settings["cpu_level"]])
	_xr.call("set_gpu_level", LEVELS[settings["gpu_level"]])
	var refresh := roundi(float(_xr.call("get_display_refresh_rate")))
	if settings["physics_match_display"] and refresh >= 30 and refresh <= 144:
		Engine.physics_ticks_per_second = refresh
	elif _was_physics_hz > 0:
		Engine.physics_ticks_per_second = _was_physics_hz
	print("Slopitect perf: foveation %s%s (supported: %s), CPU %s, GPU %s, physics %d a second" % [settings["foveation"],
		" when busy" if settings["foveation_dynamic"] else "", _xr.call("is_foveation_supported"), settings["cpu_level"], settings["gpu_level"],
		Engine.physics_ticks_per_second])


func _refresh_changed(_rate: float) -> void:
	_apply()


func _headset() -> Dictionary:
	var out := {"foveation": settings["foveation"], "foveation_dynamic": settings["foveation_dynamic"],
		"cpu_level": settings["cpu_level"], "gpu_level": settings["gpu_level"], "physics_match_display": settings["physics_match_display"],
		"level_changes": _level_changes}
	if _xr != null and is_instance_valid(_xr) and _xr.is_initialized():
		out["foveation_supported"] = _xr.call("is_foveation_supported")
		out["foveation_now"] = FOVEATION.find_key(int(_xr.get("foveation_level")))
	else:
		out["foveation_now"] = "no headset"
	return out


func _cpu_level_changed(sub_domain: int, from_level: int, to_level: int) -> void:
	_level_changed("CPU", sub_domain, from_level, to_level)


func _gpu_level_changed(sub_domain: int, from_level: int, to_level: int) -> void:
	_level_changed("GPU", sub_domain, from_level, to_level)


# The headset says when it's near its limits (or too hot): kept for perf_status and logged.
func _level_changed(chip: String, sub_domain: int, from_level: int, to_level: int) -> void:
	var names := ["normal", "warning", "impaired"]
	var domains := ["compositing", "rendering", "thermal"]
	var note := "%s %s: %s to %s" % [chip, domains[sub_domain] if sub_domain < domains.size() else str(sub_domain),
		names[from_level] if from_level < names.size() else str(from_level), names[to_level] if to_level < names.size() else str(to_level)]
	print("Slopitect perf: the headset says " + note)
	_level_changes.append({"at": Time.get_datetime_string_from_system(), "what": note})
	if _level_changes.size() > 20:
		_level_changes.pop_front()


func _config(request: Dictionary) -> Dictionary:
	if request.get("reset", false) == true:
		settings = DEFAULTS.duplicate()
	else:
		var changed := settings.duplicate()
		for key in request:
			if key in ["cmd", "id"]:
				continue
			var value = request[key]
			match key:
				"foveation":
					if not value in FOVEATION:
						return {"ok": false, "error": "\"foveation\" must be one of: " + ", ".join(FOVEATION.keys())}
				"foveation_dynamic", "physics_match_display":
					if typeof(value) == TYPE_STRING and value in ["true", "false"]:
						value = value == "true"
					if typeof(value) != TYPE_BOOL:
						return {"ok": false, "error": "\"%s\" must be true or false" % key}
				"cpu_level", "gpu_level":
					if not value in LEVELS:
						return {"ok": false, "error": "\"%s\" must be one of: %s" % [key, ", ".join(LEVELS.keys())]}
				_:
					return {"ok": false, "error": "perf_config takes foveation, foveation_dynamic, cpu_level, gpu_level, physics_match_display or reset"}
			changed[key] = value
		settings = changed
	_apply()
	var problem: String = _lib.write_json(SETTINGS_PATH, settings, "\t") if _lib else "the lib module isn't loaded, so it isn't kept after a restart"
	var reply := {"ok": true, "headset": _headset()}
	if not problem.is_empty():
		reply["note"] = problem
	return reply


func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var saved = _lib.read_json(SETTINGS_PATH)
	if typeof(saved) != TYPE_DICTIONARY:
		push_error("Slopitect perf: %s isn't readable; using the defaults" % SETTINGS_PATH)
		return
	if saved.get("foveation") in FOVEATION:
		settings["foveation"] = saved["foveation"]
	for key in ["foveation_dynamic", "physics_match_display"]:
		if typeof(saved.get(key)) == TYPE_BOOL:
			settings[key] = saved[key]
	for key in ["cpu_level", "gpu_level"]:
		if saved.get(key) in LEVELS:
			settings[key] = saved[key]


# --- Commands ----------------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	var refresh := 0.0
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		refresh = xr.call("get_display_refresh_rate")
	if refresh <= 0.0:
		refresh = maxf(DisplayServer.screen_get_refresh_rate(), 0.0)  # -1 when it can't tell
	var budget := 1000.0 / refresh if refresh > 0.0 else 0.0
	var sorted := _frame_ms.slice(_first)
	sorted.sort()
	var count := sorted.size()
	var total := 0.0
	var late := 0
	for ms in sorted:
		total += ms
		if budget > 0.0 and ms > budget * 1.5:  # took the time of two frames or more
			late += 1
	var mb := func(bytes: float) -> float: return snappedf(bytes / 1048576.0, 0.1)
	var memory := OS.get_memory_info()
	return {"ok": true,
		"fps": Engine.get_frames_per_second(),
		"refresh_hz": snappedf(refresh, 0.1),
		"frame_budget_ms": snappedf(budget, 0.01),
		"frames": {"seconds": HISTORY, "count": count,
			"average_ms": snappedf(total / count, 0.01) if count else 0.0,
			"median_ms": snappedf(sorted[count / 2], 0.01) if count else 0.0,
			"worst_1_percent_ms": snappedf(sorted[mini(count - 1, int(count * 0.99))], 0.01) if count else 0.0,
			"worst_ms": snappedf(sorted[count - 1], 0.01) if count else 0.0,
			"hitches": late},
		"cpu_ms": {"scripts_process": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
			"physics_step": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
			"physics_hz": Engine.physics_ticks_per_second},
		"render": {"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			"objects_drawn": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))},
		"objects": {"all": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"physics_bodies_awake": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))},
		"memory_mb": {"app": mb.call(OS.get_static_memory_usage()),
			"video": mb.call(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
			"textures": mb.call(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
			"device_free": mb.call(memory.get("available", memory.get("free", 0))),
			"device_total": mb.call(memory.get("physical", 0))},
		"modules": _loaded_modules().size(),
		"headset": _headset(),
		"watching": _watching}


func _watch(request: Dictionary) -> Dictionary:
	var on = request.get("on", true)
	if typeof(on) != TYPE_BOOL:
		return {"ok": false, "error": "\"on\" must be true or false"}
	_watching = on
	_remove_markers()
	if on:
		_watch_since = Time.get_ticks_msec() / 1000.0
		_check_in = 0.0
		_place_markers()
	return {"ok": true, "watching": _watching}


func _modules(request: Dictionary) -> Dictionary:
	if not _watching:
		return {"ok": false, "error": "not timing modules; perf_watch starts it"}
	if not _pairs.has(EMPTY):
		return {"ok": false, "error": "the markers aren't in place yet; try again in a second"}
	var empty: After = _pairs[EMPTY][1]
	var base := float(empty.total) / empty.frames if empty.frames else 0.0
	var physics_base := float(empty.physics_total) / empty.ticks if empty.ticks else 0.0
	var rows := []
	var sum := 0.0
	for module in _loaded_modules():
		var module_name := String(module.name)
		if not _pairs.has(module_name):
			continue
		var after: After = _pairs[module_name][1]
		var per_frame := maxf(0.0, float(after.total) / after.frames - base) if after.frames else 0.0
		var per_tick := maxf(0.0, float(after.physics_total) / after.ticks - physics_base) if after.ticks else 0.0
		sum += per_frame
		rows.append({"module": module_name,
			"process_ms": snappedf(per_frame / 1000.0, 0.001),
			"process_worst_ms": snappedf(after.worst / 1000.0, 0.001),
			"physics_ms": snappedf(per_tick / 1000.0, 0.001),
			"physics_worst_ms": snappedf(after.physics_worst / 1000.0, 0.001),
			"nodes": _count_nodes(module),
			"runs": _runs(module)})
	rows.sort_custom(func(a, b): return a["process_ms"] + a["physics_ms"] > b["process_ms"] + b["physics_ms"])
	var reply := {"ok": true, "seconds": snappedf(Time.get_ticks_msec() / 1000.0 - _watch_since, 0.1),
		"frames": empty.frames,
		"modules_process_ms": snappedf(sum / 1000.0, 0.001),
		"all_scripts_process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.001),
		"marker_cost_ms": snappedf(base / 1000.0, 0.001),
		"modules": rows}
	if request.get("reset", false) == true:
		for pair in _pairs.values():
			pair[1].clear()
		_watch_since = Time.get_ticks_msec() / 1000.0
	return reply


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


# Which per-frame callbacks the module has switched on.
func _runs(module: Node) -> Array:
	var runs := []
	if module.is_processing():
		runs.append("process")
	if module.is_physics_processing():
		runs.append("physics")
	if module.is_processing_input():
		runs.append("input")
	if module.is_processing_unhandled_input():
		runs.append("unhandled_input")
	return runs


func _load_times(request: Dictionary) -> Dictionary:
	var only = request.get("name", "")
	if typeof(only) != TYPE_STRING or (not only.is_empty() and not only.is_valid_identifier()):
		return {"ok": false, "error": "\"name\" must be a module name"}
	var lib: SlopitectModule = ctx["modules"].module("lib")
	if lib == null:
		return {"ok": false, "error": "perf_load needs the lib module (load lib.gd)"}
	var folder: String = lib.home() + "/modules"
	var names := []
	if only.is_empty():
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".gd"):
				names.append(file.get_basename())
	else:
		names.append(only)
	if names.is_empty():
		return {"ok": false, "error": "no .gd files in %s" % folder}
	var rows := []
	var total := 0
	for module_name in names:
		var path := "%s/%s.gd" % [folder, module_name]
		if not FileAccess.file_exists(path):
			return {"ok": false, "error": "there's no %s" % path}
		var started := Time.get_ticks_usec()
		var source := FileAccess.get_file_as_string(path)
		var read_us := Time.get_ticks_usec() - started
		var script := GDScript.new()
		script.source_code = source
		started = Time.get_ticks_usec()
		var err := script.reload()
		var compile_us := Time.get_ticks_usec() - started
		total += read_us + compile_us
		rows.append({"module": module_name, "kb": snappedf(source.length() / 1024.0, 0.1), "lines": source.count("\n") + 1,
			"read_ms": snappedf(read_us / 1000.0, 0.01), "compile_ms": snappedf(compile_us / 1000.0, 0.01),
			"compiles": err == OK, "loaded": ctx["modules"].module(module_name) != null})
	rows.sort_custom(func(a, b): return a["compile_ms"] > b["compile_ms"])
	return {"ok": true, "folder": folder, "total_ms": snappedf(total / 1000.0, 0.01), "modules": rows,
		"note": "compile only; a module's setup() runs on top of this when it loads"}
