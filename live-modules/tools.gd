extends SlopitectModule

# Slopitect live module: tools.
# A small tool window (B on the right controller, or its tile on the Menu,
# shows and hides it) with a button for each tool, the chosen tool's own
# buttons, and Undo / Redo.
#
# A tool is any other loaded module with a tool_info() function, so a tool
# is its own file: load it and its button appears, unload it and it goes.
# tool_info() returns {"id", "label", "order" (optional, lower first),
# "buttons": [{"label", "action": a command}], "status": one line}.
# The chosen tool gets:
#   tool_selected(on: bool)  when it's chosen or another one is
#   tool_trigger(down: bool) the "point" action (the right trigger), unless
#                            you're pointing at a panel or a question is open
# Any module can add to the shared undo list with
# push_undo(label, undo: Callable, redo: Callable).

const PANEL := "tools"
const SCAN_SECONDS := 0.5
const MAX_UNDO := 50
const CELL := Vector2(0.11, 0.05)
const GAP := 0.012

var _active := ""  # the chosen tool's id
var _tools := {}  # id -> the module
var _signature := ""  # what the panel was last built from
var _undo: Array = []  # [{label, undo, redo}], newest last
var _redo: Array = []
var _trigger_down := false
var _since_scan := SCAN_SECONDS


func setup() -> String:
	register("tools_list", _list, "the tools that are loaded, and which one is chosen")
	register("tools_select", _select, "choose a tool: tool (its id, or \"\" for none)")
	register("tools_undo", _undo_command, "undo the last change any tool made")
	register("tools_redo", _redo_command, "redo the last undone change")
	register("tools_status", _status, "the chosen tool, and what Undo and Redo would do")
	return ""


func _exit_tree() -> void:
	if _tools.has(_active) and is_instance_valid(_tools[_active]):
		_tools[_active].call("tool_selected", false)
	ctx["server"].run({"cmd": "ui_remove", "id_panel": PANEL})


func _process(delta: float) -> void:
	_since_scan += delta
	if _since_scan < SCAN_SECONDS:
		return
	_since_scan = 0.0
	_scan()


# --- Shared undo -------------------------------------------------------------------

func push_undo(label: String, undo: Callable, redo: Callable) -> void:
	_undo.append({"label": label, "undo": undo, "redo": redo})
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()
	_signature = ""  # the panel shows what Undo does


func _undo_command(_request: Dictionary) -> Dictionary:
	return _step(_undo, _redo, "undo", "undid")


func _redo_command(_request: Dictionary) -> Dictionary:
	return _step(_redo, _undo, "redo", "redid")


func _step(from: Array, to: Array, key: String, done: String) -> Dictionary:
	# A change whose module was unloaded can't be undone any more.
	while not from.is_empty() and not (from[-1][key] as Callable).is_valid():
		print("Slopitect tools: dropped \"%s\" from the %s list: its module is gone" % [from[-1]["label"], key])
		from.pop_back()
	if from.is_empty():
		return {"ok": false, "error": "nothing to %s" % key}
	var entry: Dictionary = from.pop_back()
	(entry[key] as Callable).call()
	to.append(entry)
	_signature = ""
	print("Slopitect tools: %s \"%s\"" % [done, entry["label"]])
	return {"ok": true, done: entry["label"]}


# --- Tools ---------------------------------------------------------------------------

func _scan() -> void:
	var found := {}
	var infos := {}
	for child in ctx["modules"].get_children():
		if child != self and child.has_method("tool_info"):
			var info = child.call("tool_info")
			if typeof(info) == TYPE_DICTIONARY and typeof(info.get("id")) == TYPE_STRING:
				found[info["id"]] = child
				info = info.duplicate()
				info.erase("status")  # shown live by the status line, so no rebuild for it
				infos[info["id"]] = info
	if not found.has(_active):
		_active = ""
		_trigger_down = false
	_tools = found
	var signature := JSON.stringify([_active, infos, _undo_label(), _redo.size()])
	if signature != _signature:
		_signature = signature
		_build_panel(infos)


func _select(request: Dictionary) -> Dictionary:
	var id = request.get("tool", "")
	_scan()
	if typeof(id) != TYPE_STRING or (not id.is_empty() and not _tools.has(id)):
		return {"ok": false, "error": "\"tool\" must be one of %s, or \"\" for none" % [_tools.keys()]}
	if id == _active:
		return {"ok": true, "tool": id}
	if _tools.has(_active):
		_end_trigger()
		_tools[_active].call("tool_selected", false)
	_active = id
	if not id.is_empty():
		_tools[id].call("tool_selected", true)
	_scan()
	print("Slopitect tools: chose \"%s\"" % id)
	return {"ok": true, "tool": id}


func _list(_request: Dictionary) -> Dictionary:
	_scan()
	var listed := []
	for id in _tools:
		listed.append({"id": id, "label": _tools[id].call("tool_info").get("label", id), "module": String(_tools[id].name)})
	return {"ok": true, "tools": listed, "chosen": _active}


func _status(_request: Dictionary) -> Dictionary:
	var line := "Tool: %s" % (_active if not _active.is_empty() else "none")
	if _tools.has(_active):
		var status = _tools[_active].call("tool_info").get("status", "")
		if not str(status).is_empty():
			line += ". " + str(status)
	return {"ok": true, "chosen": _active, "undo": _undo_label(), "redo": _redo.size(), "line": line}


func _undo_label() -> String:
	return _undo[-1]["label"] if not _undo.is_empty() else ""


# --- The trigger ---------------------------------------------------------------------

# The controls module asks the ui module first, so a press on a panel
# never gets here, and it sends nothing while a question is open.
func action_order() -> int:
	return 10


func on_action(action: String, down: bool) -> bool:
	if action != "point":
		return false
	if not down:
		_end_trigger()
		return true
	if not _tools.has(_active):
		return false
	_trigger_down = true
	_tools[_active].call("tool_trigger", true)
	return true


func _end_trigger() -> void:
	if _trigger_down and _tools.has(_active) and is_instance_valid(_tools[_active]):
		_tools[_active].call("tool_trigger", false)
	_trigger_down = false


# --- The window ----------------------------------------------------------------------

func _build_panel(infos: Dictionary) -> void:
	var ids := infos.keys()
	ids.sort_custom(func(a, b): return [infos[a].get("order", 100), a] < [infos[b].get("order", 100), b])
	var rows := []
	var tool_row := [{"label": "No tool", "action": {"cmd": "tools_select", "tool": ""}}]
	for id in ids:
		var label := str(infos[id].get("label", id)).left(30)
		tool_row.append({"label": ("> " + label) if id == _active else label, "action": {"cmd": "tools_select", "tool": id}})
	rows.append(tool_row)
	if infos.has(_active) and typeof(infos[_active].get("buttons")) == TYPE_ARRAY:
		var own: Array = infos[_active]["buttons"]
		for start in range(0, own.size(), 5):
			rows.append(own.slice(start, start + 5))
	var undo_label := _undo_label()
	rows.append([
		{"label": ("Undo " + undo_label).left(40) if not undo_label.is_empty() else "Undo", "action": {"cmd": "tools_undo"}},
		{"label": "Redo (%d)" % _redo.size() if not _redo.is_empty() else "Redo", "action": {"cmd": "tools_redo"}},
	])

	var widest := 0
	for row in rows:
		widest = maxi(widest, row.size())
	var width := widest * (CELL.x + GAP) + GAP
	var height := (rows.size() + 1) * (CELL.y + GAP) + GAP
	var top := height / 2.0 - GAP - CELL.y / 2.0
	var elements := [{"type": "text", "id": "status", "at": [-width / 2.0 + GAP, top], "width": width - 2 * GAP,
		"font_size": 22, "source": {"cmd": "tools_status", "field": "line"}}]
	for r in rows.size():
		var row: Array = rows[r]
		for c in row.size():
			var button = row[c]
			if typeof(button) != TYPE_DICTIONARY or typeof(button.get("action")) != TYPE_DICTIONARY:
				continue
			var x := (c - (row.size() - 1) / 2.0) * (CELL.x + GAP)
			var y := top - (r + 1) * (CELL.y + GAP)
			elements.append({"type": "button", "id": "b%d_%d" % [r, c], "label": str(button.get("label", "?")).left(40),
				"at": [x, y], "size": [CELL.x, CELL.y], "action": button["action"],
				"color": "accent" if r == 0 and c > 0 and ids[c - 1] == _active else "button"})
	# A title bar to carry and close it, and a tile on the Menu (ui.gd).
	var panel := {"cmd": "ui_add", "id_panel": PANEL, "title": "Tools", "place": "front", "distance": 0.5, "height": -0.2,
		"toggle": "right_b", "chrome": true, "menu": "Tools", "size": [width, height], "elements": elements}
	var listed: Dictionary = ctx["server"].run({"cmd": "ui_list"})
	for existing in listed.get("panels", []):
		if existing.get("id_panel") == PANEL:
			panel["cmd"] = "ui_update"
			panel["visible"] = existing.get("visible", false)
	var reply: Dictionary = ctx["server"].run(panel)
	if not reply.get("ok", false):
		push_error("Slopitect tools: the window could not be built: %s" % reply.get("error"))
