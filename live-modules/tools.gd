extends SlopitectModule

# Slopitect live module: tools.
# The Tools menu (B on the right controller, or its tile on the Menu, shows
# and hides it): a button for each tool, which chooses it and opens that
# tool's own menu (its buttons, Undo / Redo, and a back arrow), the windows
# that are tools (the terminal), and Undo / Redo.
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
# push_undo(label, undo: Callable, redo: Callable). Changes made between
# undo_batch_begin(label) and undo_batch_end() are one undo (undone newest
# first, redone oldest first), so a change made of many is one press;
# undo_batch_end(undo, redo) instead replaces what was pushed inside with
# that one pair (for a change that knows how to take itself back whole).

const PANEL := "tools"
const SCAN_SECONDS := 0.5
const MAX_UNDO := 50
const TOOL_PANEL_PREFIX := "tools_t_"  # each tool's own menu: tools_t_ID
const CELL := Vector2(0.2, 0.06)
const COLUMNS := 2
const MENU_WIDTH := 0.41

var _active := ""  # the chosen tool's id
var _tools := {}  # id -> the module
var _signature := ""  # what the panel was last built from
var _undo: Array = []  # [{label, undo, redo}], newest last
var _redo: Array = []
var _batch: Array = []  # [label, [entries]] while a batch is open
var _batch_depth := 0
var _stepping := false  # while an undo or redo runs, its own changes add nothing
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
	if ctx["modules"].module(name) != null:
		return  # the app is closing, not unloading this: the menus stay for next time
	for panel in ctx["server"].run({"cmd": "ui_list"}).get("panels", []):
		var id_panel := str(panel.get("id_panel", ""))
		if id_panel == PANEL or id_panel.begins_with(TOOL_PANEL_PREFIX):
			ctx["server"].run({"cmd": "ui_remove", "id_panel": id_panel})


func _process(delta: float) -> void:
	_since_scan += delta
	if _since_scan < SCAN_SECONDS:
		return
	_since_scan = 0.0
	_scan()


# --- Shared undo -------------------------------------------------------------------

func push_undo(label: String, undo: Callable, redo: Callable) -> void:
	if _stepping:
		return  # an undo putting a thing back through a command that keeps its own undo
	if _batch_depth > 0:
		_batch[1].append({"label": label, "undo": undo, "redo": redo})
		return
	_add({"label": label, "undo": undo, "redo": redo})


# Batches nest: only the outermost one's label is kept.
func undo_batch_begin(label: String) -> void:
	if _stepping:
		return
	if _batch_depth == 0:
		_batch = [label, []]
	_batch_depth += 1


func undo_batch_end(undo := Callable(), redo := Callable()) -> void:
	if _batch_depth == 0:
		return
	_batch_depth -= 1
	if _batch_depth > 0:
		return
	var label: String = _batch[0]
	var entries: Array = _batch[1]
	_batch = []
	if undo.is_valid() and redo.is_valid():
		_add({"label": label, "undo": undo, "redo": redo})
	elif entries.size() == 1:
		_add(entries[0])
	elif entries.size() > 1:
		var undo_all := func():
			for i in range(entries.size() - 1, -1, -1):
				if (entries[i]["undo"] as Callable).is_valid():
					(entries[i]["undo"] as Callable).call()
		var redo_all := func():
			for entry in entries:
				if (entry["redo"] as Callable).is_valid():
					(entry["redo"] as Callable).call()
		_add({"label": label, "undo": undo_all, "redo": redo_all})


func _add(entry: Dictionary) -> void:
	_undo.append(entry)
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
	_stepping = true
	(entry[key] as Callable).call()
	_stepping = false
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
	# Built again on a new or reloaded ui module too.
	var ui := _ui()
	var signature := JSON.stringify([_active, infos, _undo_label(), _redo.size(), _windows(), ui.get_instance_id() if ui != null else 0])
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


# A button on the hand menu (pause.gd).
func hand_info() -> Dictionary:
	return {"id": "tools", "label": "Tools", "order": 10, "panel": PANEL}


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

# The Tools menu: a button for each tool, which chooses it and opens its own
# menu (its buttons, with a back arrow to this one); the windows that count
# as tools (a module whose menu_info() has "tools": true, like the
# terminal); and Undo / Redo. Each menu is a ui panel, kept by ui.gd: this
# only adds it the first time and replaces its elements after, so where you
# put it stays.
func _build_panel(infos: Dictionary) -> void:
	if _ui() == null:
		return
	var ids := infos.keys()
	ids.sort_custom(func(a, b): return [infos[a].get("order", 100), a] < [infos[b].get("order", 100), b])
	var tool_buttons := [_button("none", "No tool", {"cmd": "tools_select", "tool": ""}, "accent" if _active.is_empty() else "button")]
	for id in ids:
		var label := str(infos[id].get("label", id)).left(30)
		var button := _button("t_" + id, ("> " + label) if id == _active else label, {"cmd": "tools_select", "tool": id}, "accent" if id == _active else "button")
		button["open"] = _tool_panel(id)
		tool_buttons.append(button)
	var elements := [
		{"type": "text", "id": "status", "width": MENU_WIDTH, "font_size": 24, "color": "muted", "source": {"cmd": "tools_status", "field": "line"}},
		_heading("tools_title", "Tools"),
		{"type": "grid", "id": "tool_grid", "columns": COLUMNS, "children": tool_buttons},
	]
	var windows := _windows()
	if not windows.is_empty():
		elements.append(_heading("windows_title", "Windows"))
		elements.append({"type": "grid", "id": "window_grid", "columns": COLUMNS, "children": windows})
	elements.append(_undo_row(""))
	_put(PANEL, "Tools", elements, {"toggle": "right_b", "menu": "Tools"})

	# Each tool's own menu; the menus of tools that went are taken away.
	var wanted := {}
	for id in ids:
		wanted[_tool_panel(id)] = true
		var own := []
		if typeof(infos[id].get("buttons")) == TYPE_ARRAY:
			for i in infos[id]["buttons"].size():
				var button = infos[id]["buttons"][i]
				if typeof(button) == TYPE_DICTIONARY and typeof(button.get("action")) == TYPE_DICTIONARY:
					own.append(_button("b%d" % i, str(button.get("label", "?")), button["action"]))
		var tool_elements := [
			{"type": "text", "id": "status", "width": MENU_WIDTH, "font_size": 24, "color": "muted", "source": {"cmd": "tools_status", "field": "line"}},
			{"type": "grid", "id": "own", "columns": COLUMNS, "children": own},
			_undo_row("u"),
			_button("put_away", "Put it away" if id == _active else "Choose it", {"cmd": "tools_select", "tool": "" if id == _active else id}),
		]
		_put(_tool_panel(id), str(infos[id].get("label", id)).left(60), tool_elements, {})
	for panel in ctx["server"].run({"cmd": "ui_list"}).get("panels", []):
		var id_panel := str(panel.get("id_panel", ""))
		if id_panel.begins_with(TOOL_PANEL_PREFIX) and not wanted.has(id_panel):
			ctx["server"].run({"cmd": "ui_remove", "id_panel": id_panel})


func _tool_panel(id: String) -> String:
	return TOOL_PANEL_PREFIX + id


func _button(id: String, label: String, action: Dictionary, color := "button") -> Dictionary:
	return {"type": "button", "id": id, "label": label.left(40), "size": [CELL.x, CELL.y], "action": action, "color": color}


func _heading(id: String, text: String) -> Dictionary:
	return {"type": "text", "id": id, "text": text, "width": MENU_WIDTH, "font_size": 30, "color": "accent"}


func _undo_row(prefix: String) -> Dictionary:
	var undo_label := _undo_label()
	return {"type": "row", "id": prefix + "undo_row", "children": [
		_button(prefix + "undo", ("Undo " + undo_label) if not undo_label.is_empty() else "Undo", {"cmd": "tools_undo"}),
		_button(prefix + "redo", "Redo (%d)" % _redo.size() if not _redo.is_empty() else "Redo", {"cmd": "tools_redo"}),
	]}


# The windows that are tools: menu_info() with "tools": true. A window opens
# in this menu's place, with a back arrow; a command runs.
func _windows() -> Array:
	var out := []
	var infos := []
	for child in ctx["modules"].get_children():
		if child != self and child.has_method("menu_info"):
			var info = child.call("menu_info")
			if typeof(info) == TYPE_DICTIONARY and info.get("tools", false) == true and typeof(info.get("id")) == TYPE_STRING:
				infos.append(info)
	infos.sort_custom(func(a, b): return [a.get("order", 100), a["id"]] < [b.get("order", 100), b["id"]])
	for info in infos:
		var label := str(info.get("label", info["id"]))
		if typeof(info.get("panel")) == TYPE_STRING:
			out.append({"type": "button", "id": "w_" + info["id"], "label": label.left(40), "size": [CELL.x, CELL.y], "open": info["panel"]})
		elif typeof(info.get("action")) == TYPE_DICTIONARY:
			out.append(_button("w_" + info["id"], label, info["action"]))
	return out


# Adds the panel the first time, then changes only its elements. A panel
# from before the menus (laid out by "at") is made again as a column.
func _put(id_panel: String, title: String, elements: Array, extra: Dictionary) -> void:
	var got: Dictionary = ctx["server"].run({"cmd": "ui_get", "id_panel": id_panel})
	var visible := false
	if got.get("ok", false):
		if got["panel"].get("layout") == "column":
			var updated: Dictionary = ctx["server"].run({"cmd": "ui_update", "id_panel": id_panel, "elements": elements})
			if not updated.get("ok", false):
				push_error("Slopitect tools: %s could not be built: %s" % [id_panel, updated.get("error")])
			return
		visible = got["panel"].get("visible", false)
		ctx["server"].run({"cmd": "ui_remove", "id_panel": id_panel})
	var panel := {"cmd": "ui_add", "id_panel": id_panel, "title": title, "place": "front", "distance": 0.5, "height": -0.2,
		"chrome": true, "layout": "column", "visible": visible, "elements": elements}
	panel.merge(extra)
	var reply: Dictionary = ctx["server"].run(panel)
	if not reply.get("ok", false):
		push_error("Slopitect tools: %s could not be built: %s" % [id_panel, reply.get("error")])


# The window module, by either name (it may be renamed vrui).
func _ui() -> SlopitectModule:
	var ui: SlopitectModule = ctx["modules"].module("vrui")
	return ui if ui != null else ctx["modules"].module("ui")
