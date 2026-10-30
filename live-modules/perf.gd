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

const HISTORY := 10.0  # seconds of frame times perf_status looks back over
const CHECK_EVERY := 1.0  # seconds between checks that the markers still fit the modules
const EMPTY := "(markers)"  # the empty pair's name


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


var _frame_ms := PackedFloat32Array()  # the last HISTORY seconds of frame times
var _frame_at := PackedFloat64Array()  # when each was, in seconds
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
	return ""


func _exit_tree() -> void:
	_remove_markers()


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_frame_ms.append(delta * 1000.0)
	_frame_at.append(now)
	var old := 0
	while old < _frame_at.size() and _frame_at[old] < now - HISTORY:
		old += 1
	if old > 0:
		_frame_ms = _frame_ms.slice(old)
		_frame_at = _frame_at.slice(old)
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


# --- Commands ----------------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	var refresh := 0.0
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		refresh = xr.call("get_display_refresh_rate")
	if refresh <= 0.0:
		refresh = maxf(DisplayServer.screen_get_refresh_rate(), 0.0)  # -1 when it can't tell
	var budget := 1000.0 / refresh if refresh > 0.0 else 0.0
	var sorted := _frame_ms.duplicate()
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
