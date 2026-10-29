extends SlopitectModule

# Slopitect live module: worlds.
# One window, opened from its tile on the Menu, with four tabs:
# - Worlds: every project's world; open one, or make a new one (projects.gd).
# - Checkpoints: keep the world as it is now, go back to a checkpoint, or
#   delete one (save.gd).
# - Files: look through the Slopitect folder.
# - Modules: the live modules; load or unload each (a new or changed one
#   still waits for your Yes in the headset).
# It keeps nothing of its own: each tab shows what those modules say, and
# its buttons run their commands. A tab whose module isn't loaded says so.
# Names are typed with the chat window's keyboard (the Keyboard button).

const PANEL := "worlds"
const PAGES := ["Worlds", "Checkpoints", "Files", "Modules"]
const SIZE := Vector2(0.72, 0.62)
const ROW := 0.065
const BUTTON_H := 0.055
const MAX_ROWS := 7  # list rows that fit under a tab's top line
const NAME_MAX := 40

var _folder := ""  # the Files tab's folder, inside the Slopitect folder
var _files_page := 0
var _modules_page := 0


func setup() -> String:
	register("worlds_do", _do, "the Worlds window: act = toggle, show (optional page), refresh, new_project (name), open_project (name), checkpoint (optional label), restore (checkpoint), delete_checkpoint (checkpoint), load_module (name), unload_module (name), folder (path, optional page), modules_page (page)")
	register("worlds_status", _status, "the world you're in, the projects, checkpoints and live modules, as the Worlds window shows them")
	return ""


func _exit_tree() -> void:
	ctx["server"].run({"cmd": "ui_remove", "id_panel": PANEL})


# A tile on the Menu (ui.gd's launcher). It opens through worlds_do, so the
# window always shows what's there now.
func menu_info() -> Dictionary:
	return {"id": "worlds", "label": "Worlds", "order": 20, "action": {"cmd": "worlds_do", "act": "toggle"}}


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


func _has(module_name: String) -> bool:
	return ctx["modules"].module(module_name) != null


# --- Commands ------------------------------------------------------------------------

func _do(request: Dictionary) -> Dictionary:
	var act = request.get("act")
	var reply := {}
	match act:
		"toggle":
			var shown := _panel()
			if not shown.is_empty() and shown.get("visible", false):
				return _run({"cmd": "ui_show", "id_panel": PANEL, "visible": false})
			return _show("")
		"show":
			var page = request.get("page", "")
			if not (page == "" or page in PAGES):
				return {"ok": false, "error": "\"page\" must be one of %s" % [PAGES]}
			return _show(page)
		"refresh":
			_build("")
			return {"ok": true}
		"modules_page":
			var page = request.get("page")
			if typeof(page) not in [TYPE_INT, TYPE_FLOAT]:
				return {"ok": false, "error": "\"page\" must be a number"}
			_modules_page = maxi(0, int(page))
			_build("Modules")
			return {"ok": true}
		"new_project":
			var typed = request.get("name")
			if typeof(typed) != TYPE_STRING or typed.strip_edges().is_empty():
				return {"ok": false, "error": "type a name for the new world first (Keyboard opens the keys)"}
			reply = _run({"cmd": "projects_new", "name": typed.strip_edges(), "open": true})
		"open_project":
			reply = _run({"cmd": "projects_open", "name": request.get("name")})
		"checkpoint":
			var label = request.get("label", "")
			reply = _run({"cmd": "save_checkpoint", "label": label} if typeof(label) == TYPE_STRING and not label.strip_edges().is_empty() else {"cmd": "save_checkpoint"})
		"restore":
			reply = _run({"cmd": "save_restore", "checkpoint": request.get("checkpoint")})
		"delete_checkpoint":
			reply = _run({"cmd": "save_delete", "checkpoint": request.get("checkpoint")})
		"load_module":
			reply = _run({"cmd": "code_load", "name": request.get("name")})
		"unload_module":
			if request.get("name") == name:
				return {"ok": false, "error": "the Worlds window can't unload itself; use code_unload"}
			reply = _run({"cmd": "code_unload", "name": request.get("name")})
		"folder":
			var path = request.get("path", _folder)
			if typeof(path) != TYPE_STRING or path.begins_with("/") or ".." in path.split("/"):
				return {"ok": false, "error": "\"path\" must be a folder inside the Slopitect folder, without .."}
			path = path.trim_suffix("/")
			if path != _folder:
				_files_page = 0
			_folder = path
			var page = request.get("page", _files_page)
			if typeof(page) in [TYPE_INT, TYPE_FLOAT]:
				_files_page = maxi(0, int(page))
			_build("Files")
			return {"ok": true, "path": _folder}
		_:
			return {"ok": false, "error": "\"act\" must be toggle, show, refresh, modules_page, new_project, open_project, checkpoint, restore, delete_checkpoint, load_module, unload_module or folder"}
	# Whatever it changed, the window shows it; a command that waits (a new
	# module waiting for your Yes) refreshes it again when it's answered.
	if reply.get("wait") is SlopitectPending:
		(reply["wait"] as SlopitectPending).done.connect(func(_final): _build(""), CONNECT_ONE_SHOT)
	_build("")
	return reply


func _status(_request: Dictionary) -> Dictionary:
	var current := _run({"cmd": "projects_current"}) if _has("projects") else {}
	return {"ok": true, "world": current.get("name", ""),
		"projects": _run({"cmd": "projects_list"}).get("projects", []).map(func(p): return p["name"]) if _has("projects") else [],
		"checkpoints": _run({"cmd": "save_checkpoints"}).get("checkpoints", []).size() if _has("save") else 0,
		"modules": _run({"cmd": "code_list"}).get("modules", []).filter(func(m): return m["loaded"]).map(func(m): return m["name"])}


# --- The window ----------------------------------------------------------------------

func _panel() -> Dictionary:
	var got := _run({"cmd": "ui_get", "id_panel": PANEL})
	return got.get("panel", {}) if got.get("ok", false) else {}


func _show(page: String) -> Dictionary:
	var problem := _build(page)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return _run({"cmd": "ui_show", "id_panel": PANEL, "visible": true})


# Lays out every tab again, keeping the tab you're on (or going to page).
# Returns "" or what went wrong.
func _build(page: String) -> String:
	if not _has("ui"):
		return "the Worlds window needs the ui module"
	var elements := []
	elements.append_array(_worlds_tab())
	elements.append_array(_checkpoints_tab())
	elements.append_array(_files_tab())
	elements.append_array(_modules_tab())
	var existing := _panel()
	if existing.is_empty():
		var added := _run({"cmd": "ui_add", "id_panel": PANEL, "title": "Worlds", "place": "front", "distance": 0.6, "height": -0.15,
			"size": [SIZE.x, SIZE.y], "chrome": true, "pages": PAGES, "page": page if page != "" else PAGES[0], "visible": false, "elements": elements})
		return "" if added.get("ok", false) else str(added.get("error", "ui_add failed"))
	var update := {"cmd": "ui_update", "id_panel": PANEL, "elements": elements}
	if page != "":
		update["page"] = page
	var updated := _run(update)
	return "" if updated.get("ok", false) else str(updated.get("error", "ui_update failed"))


func _row_y(row: int) -> float:
	return SIZE.y / 2.0 - 0.05 - row * ROW


func _text(page: String, id: String, text: String, x: float, y: float, width: float, color := "text") -> Dictionary:
	return {"type": "text", "id": id, "page": page, "text": text.left(200), "at": [x, y], "width": width, "color": color}


func _button(page: String, id: String, label: String, x: float, y: float, width: float, action: Dictionary, color := "button") -> Dictionary:
	return {"type": "button", "id": id, "page": page, "label": label.left(NAME_MAX), "at": [x, y], "size": [width, BUTTON_H], "action": action, "color": color}


func _missing(page: String, prefix: String, module_name: String) -> Array:
	return [_text(page, prefix + "_missing", "Load %s.gd to use this tab." % module_name, 0.0, _row_y(1), SIZE.x - 0.06, "muted")]


# The row at the top of a tab: an input box and what to do with it.
func _input_row(page: String, prefix: String, prompt: String, label: String, action: Dictionary) -> Array:
	var y := _row_y(0)
	return [
		{"type": "input", "id": prefix + "_input", "page": page, "at": [-0.13, y], "width": 0.38, "prompt": prompt, "max_length": NAME_MAX},
		_button(page, prefix + "_go", label, 0.15, y, 0.16, action, "ok"),
		_button(page, prefix + "_keys", "Keyboard", 0.29, y, 0.1, {"cmd": "ui_show", "id_panel": "chat", "visible": true}),
	]


func _worlds_tab() -> Array:
	var page := "Worlds"
	if not _has("projects"):
		return _missing(page, "w", "projects")
	var out := _input_row(page, "w", "new: ", "New world", {"cmd": "worlds_do", "act": "new_project", "name": "{input:w_input}"})
	var projects: Array = _run({"cmd": "projects_list"}).get("projects", [])
	for i in mini(projects.size(), MAX_ROWS):
		var project: Dictionary = projects[i]
		var y := _row_y(i + 1)
		var here: bool = project.get("current", false)
		out.append(_text(page, "w_n%d" % i, ("> " if here else "  ") + project["name"], -0.12, y, 0.42, "accent" if here else "text"))
		if here:
			out.append(_text(page, "w_h%d" % i, "you're here", 0.24, y, 0.2, "muted"))
		else:
			out.append(_button(page, "w_o%d" % i, "Open", 0.24, y, 0.18, {"cmd": "worlds_do", "act": "open_project", "name": project["name"]}))
	if projects.size() > MAX_ROWS:
		out.append(_text(page, "w_more", "and %d more (projects_list)" % (projects.size() - MAX_ROWS), 0.0, _row_y(MAX_ROWS + 1), SIZE.x - 0.06, "muted"))
	return out


func _checkpoints_tab() -> Array:
	var page := "Checkpoints"
	if not _has("save"):
		return _missing(page, "c", "save")
	var out := _input_row(page, "c", "label: ", "Checkpoint", {"cmd": "worlds_do", "act": "checkpoint", "label": "{input:c_input}"})
	var checkpoints: Array = _run({"cmd": "save_checkpoints"}).get("checkpoints", [])
	checkpoints.reverse()  # newest first
	if checkpoints.is_empty():
		out.append(_text(page, "c_none", "No checkpoints yet.", 0.0, _row_y(1), SIZE.x - 0.06, "muted"))
	for i in mini(checkpoints.size(), MAX_ROWS):
		var checkpoint: Dictionary = checkpoints[i]
		var y := _row_y(i + 1)
		var when := str(checkpoint.get("saved", "")).replace("T", " ").left(16)
		var label := str(checkpoint.get("label", ""))
		out.append(_text(page, "c_n%d" % i, "%s  %s  %s" % [checkpoint["checkpoint"], when, label], -0.11, y, 0.44))
		out.append(_button(page, "c_r%d" % i, "Go back", 0.18, y, 0.12, {"cmd": "worlds_do", "act": "restore", "checkpoint": checkpoint["checkpoint"]}))
		out.append(_button(page, "c_d%d" % i, "Delete", 0.3, y, 0.1, {"cmd": "worlds_do", "act": "delete_checkpoint", "checkpoint": checkpoint["checkpoint"]}, "danger"))
	if checkpoints.size() > MAX_ROWS:
		out.append(_text(page, "c_more", "and %d older (save_checkpoints)" % (checkpoints.size() - MAX_ROWS), 0.0, _row_y(MAX_ROWS + 1), SIZE.x - 0.06, "muted"))
	return out


func _files_tab() -> Array:
	var page := "Files"
	var out := [_text(page, "f_where", "Slopitect/" + _folder, -0.06, _row_y(0), 0.56, "accent")]
	if not _folder.is_empty():
		out.append(_button(page, "f_up", "Up", 0.29, _row_y(0), 0.1, {"cmd": "worlds_do", "act": "folder", "path": _folder.get_base_dir()}))
	var listed := _run({"cmd": "files_list", "path": _folder} if not _folder.is_empty() else {"cmd": "files_list"})
	if not listed.get("ok", false) or listed.has("wait"):
		out.append(_text(page, "f_error", "Can't list it: %s" % listed.get("error", "it needs your Yes"), 0.0, _row_y(1), SIZE.x - 0.06, "danger"))
		return out
	var entries := []
	for folder in listed.get("folders", []):
		entries.append({"name": str(folder), "folder": true})
	for file in listed.get("files", []):
		entries.append({"name": str(file.get("name", "")), "bytes": int(file.get("bytes", 0)), "folder": false})
	var pages := maxi(1, ceili(entries.size() / float(MAX_ROWS)))
	_files_page = clampi(_files_page, 0, pages - 1)
	var shown := entries.slice(_files_page * MAX_ROWS, (_files_page + 1) * MAX_ROWS)
	if entries.is_empty():
		out.append(_text(page, "f_empty", "(empty)", 0.0, _row_y(1), SIZE.x - 0.06, "muted"))
	for i in shown.size():
		var entry: Dictionary = shown[i]
		var y := _row_y(i + 1)
		if entry["folder"]:
			var inside: String = entry["name"] if _folder.is_empty() else _folder + "/" + entry["name"]
			out.append(_button(page, "f_e%d" % i, entry["name"] + "/", 0.0, y, SIZE.x - 0.06, {"cmd": "worlds_do", "act": "folder", "path": inside}))
		else:
			out.append(_text(page, "f_e%d" % i, "%s   %s" % [entry["name"], String.humanize_size(entry["bytes"])], 0.0, y, SIZE.x - 0.06))
	out.append_array(_pager(page, "f", _files_page, pages, {"cmd": "worlds_do", "act": "folder", "path": _folder}))
	return out


func _modules_tab() -> Array:
	var page := "Modules"
	var out := [_button(page, "m_refresh", "Refresh", 0.29, _row_y(0), 0.1, {"cmd": "worlds_do", "act": "refresh"}),
		_text(page, "m_hint", "New or changed code waits for your Yes.", -0.07, _row_y(0), 0.54, "muted")]
	var modules: Array = _run({"cmd": "code_list"}).get("modules", [])
	modules.sort_custom(func(a, b): return a["name"] < b["name"])
	var pages := maxi(1, ceili(modules.size() / float(MAX_ROWS)))
	_modules_page = clampi(_modules_page, 0, pages - 1)
	var shown := modules.slice(_modules_page * MAX_ROWS, (_modules_page + 1) * MAX_ROWS)
	for i in shown.size():
		var module: Dictionary = shown[i]
		var y := _row_y(i + 1)
		var state := "on" if module.get("loaded", false) else "off"
		var color := "ok" if module.get("loaded", false) else "muted"
		if not str(module.get("error", "")).is_empty():
			state = "error"
			color = "danger"
		elif module.get("changed_since_approved", false):
			state += ", changed"
		out.append(_text(page, "m_n%d" % i, "%s  (%s)" % [module["name"], state], -0.1, y, 0.46, color))
		out.append(_button(page, "m_l%d" % i, "Reload" if module.get("loaded", false) else "Load", 0.19, y, 0.1, {"cmd": "worlds_do", "act": "load_module", "name": module["name"]}))
		if module.get("loaded", false) and module["name"] != name:
			out.append(_button(page, "m_u%d" % i, "Unload", 0.3, y, 0.1, {"cmd": "worlds_do", "act": "unload_module", "name": module["name"]}, "danger"))
	out.append_array(_pager(page, "m", _modules_page, pages, {"cmd": "worlds_do", "act": "modules_page"}))
	return out


# < 2 / 3 > under a list that has more than one page; "page" goes in action.
func _pager(page: String, prefix: String, at: int, pages: int, action: Dictionary) -> Array:
	if pages <= 1:
		return []
	var y := _row_y(MAX_ROWS + 1)
	var back := action.duplicate()
	back["page"] = at - 1
	var on := action.duplicate()
	on["page"] = at + 1
	return [_button(page, prefix + "_prev", "<", -0.12, y, 0.08, back),
		_text(page, prefix + "_page", "%d / %d" % [at + 1, pages], 0.0, y, 0.12, "muted"),
		_button(page, prefix + "_next", ">", 0.12, y, 0.08, on)]
