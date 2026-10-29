extends SlopitectModule

# Slopitect live module: pause.
# The pause menu, on the left home button (the "left_menu" action; this
# module takes it before the windows do), or its tile on the Menu.
# It doesn't stop the world; it's the one place for the world and the
# settings:
# - Resume closes it.
# - Save world keeps the whole world as a checkpoint (save.gd).
# - Load lists the newest checkpoints to go back to, and Worlds lists the
#   saved worlds (projects.gd) to open, each with a back arrow.
# - Settings opens settings.gd's window, when it's loaded.
# - All windows opens the Menu bar (every window's tile, and the shapes).
# - Hand menu shows or hides the hand menu (so does pressing the left
#   thumbstick in, the "left_stick" action).
# - Files & modules opens worlds.gd's window, when it's loaded.
# The hand menu sits above the left controller: Home (this menu), Settings,
# Undo / Redo (tools.gd's one list for every change), a button for each
# module with hand_info() (see _hand_items), and the wrist panel's buttons
# (the shapes, and any you added there): the wrist panel is hidden while
# this module is loaded, so there's one hand menu. Each button that opens a
# window closes it again.
# Each menu is a ui panel ("pause", "pause_load", "pause_worlds",
# "hand_menu"), kept by the window module like every
# panel; this fills them again each time the menu opens.
# A part whose module isn't loaded says so.

const PANEL := "pause"
const LOAD_PANEL := "pause_load"
const WORLDS_PANEL := "pause_worlds"
const HAND_PANEL := "hand_menu"
const WRIST_PANEL := "wrist"  # the window module's own small hand panel, folded into the hand menu
const MENUS := [PANEL, LOAD_PANEL, "pause_worlds"]
const PAGES := {"main": PANEL, "load": LOAD_PANEL, "worlds": "pause_worlds"}
const OLD_SETTINGS_PANEL := "pause_settings"  # settings.gd took the Settings page over
const HAND_BUTTON := [0.16, 0.07]
const CHECK_SECONDS := 1.0
const WIDTH := 0.42
const BUTTON := [0.42, 0.06]
const MAX_WORLDS := 6
const MAX_CHECKPOINTS := 6


func setup() -> String:
	register("pause_do", _do, "the pause menu: act = toggle, show (optional page: main, load, worlds), hide, hand_menu (show or hide it), toggle_panel (panel), refresh, save (optional label), open_world (name), restore (checkpoint)")
	register("pause_status", _status, "the world you're in and what the pause menu can reach, one line")
	return ""


func _exit_tree() -> void:
	if ctx["modules"].module(name) != null:
		return  # the app is closing, not unloading this: the menus stay for next time
	for id_panel in MENUS + [HAND_PANEL]:
		ctx["server"].run({"cmd": "ui_remove", "id_panel": id_panel})
	ctx["server"].run({"cmd": "ui_show", "id_panel": WRIST_PANEL, "visible": true})


var _hand_signature := ""  # what the hand menu was last built from
var _since_check := CHECK_SECONDS


func _process(delta: float) -> void:
	_since_check += delta
	if _since_check < CHECK_SECONDS:
		return
	_since_check = 0.0
	# The hand menu is built on whichever window module is there, again
	# when it's reloaded or the panel is gone, and when tools.gd (Undo /
	# Redo) or save.gd comes or goes.
	var ui := _ui()
	if ui == null:
		return
	var signature := JSON.stringify([ui.get_instance_id(), _has("tools"), _has("settings"), _hand_items(), _wrist_buttons(), _hand_statuses().map(func(st): return st["id"])])
	if signature != _hand_signature or not _run({"cmd": "ui_get", "id_panel": HAND_PANEL}).get("ok", false):
		_hand_signature = signature
		_build_hand()
	elif _shown(WRIST_PANEL):
		_run({"cmd": "ui_show", "id_panel": WRIST_PANEL, "visible": false})  # one hand menu


# The left home button opens and closes the pause menu. This module asks
# before the windows (0), so the Menu bar is reached from here (All windows).
func action_order() -> int:
	return -10


func on_action(action: String, down: bool) -> bool:
	if not action in ["left_menu", "left_stick"] or _ui() == null:
		return false
	if down:
		_do({"act": "toggle"} if action == "left_menu" else {"act": "hand_menu"})
	return true


func menu_info() -> Dictionary:
	return {"id": "pause", "label": "Pause", "order": 0, "action": {"cmd": "pause_do", "act": "toggle"}}


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


func _has(module_name: String) -> bool:
	return ctx["modules"].module(module_name) != null


# The window module, by either name (it may be renamed vrui).
func _ui() -> SlopitectModule:
	var ui: SlopitectModule = ctx["modules"].module("vrui")
	return ui if ui != null else ctx["modules"].module("ui")


# --- Commands ------------------------------------------------------------------------

func _do(request: Dictionary) -> Dictionary:
	match request.get("act"):
		"toggle":
			if MENUS.any(_shown):
				return _hide_all()
			return _open("main")
		"show":
			var page = request.get("page", "main")
			if not page in PAGES:
				return {"ok": false, "error": "\"page\" must be one of %s" % [PAGES.keys()]}
			return _open(page)
		"hand_menu":
			return _run({"cmd": "ui_show", "id_panel": HAND_PANEL, "visible": not _shown(HAND_PANEL)})
		"toggle_panel":
			var id_panel = request.get("panel")
			if typeof(id_panel) != TYPE_STRING or not _run({"cmd": "ui_get", "id_panel": id_panel}).get("ok", false):
				return {"ok": false, "error": "\"panel\" must be a window's id_panel (ui_list shows them)"}
			return _run({"cmd": "ui_show", "id_panel": id_panel, "visible": not _shown(id_panel)})
		"hide":
			return _hide_all()
		"refresh":
			var problem := _build_all()
			return {"ok": true} if problem.is_empty() else {"ok": false, "error": problem}
		"save":
			if not _has("save"):
				return {"ok": false, "error": "saving needs save.gd"}
			var label = request.get("label", "")
			if typeof(label) != TYPE_STRING or label.strip_edges().is_empty():
				label = "from the pause menu"
			var reply := _run({"cmd": "save_checkpoint", "label": label})
			_build_all()
			return reply
		"open_world":
			var reply := _run({"cmd": "projects_open", "name": request.get("name")})
			if reply.get("ok", false):
				_hide_all()
			return reply
		"restore":
			var reply := _run({"cmd": "save_restore", "checkpoint": request.get("checkpoint")})
			if reply.get("ok", false):
				_hide_all()
			return reply
	return {"ok": false, "error": "\"act\" must be toggle, show, hide, hand_menu, toggle_panel, refresh, save, open_world or restore"}


func _status(_request: Dictionary) -> Dictionary:
	var world := str(_run({"cmd": "projects_current"}).get("name", "")) if _has("projects") else ""
	var line := "World: %s" % (world if not world.is_empty() else "(projects.gd isn't loaded)")
	if _has("save"):
		var saved := _run({"cmd": "save_checkpoints"}).get("checkpoints", []) as Array
		line += "   Checkpoints: %d" % saved.size()
	return {"ok": true, "world": world, "line": line}


# Shows one of the menus (page) in front of you, and hides the others.
func _open(page: String) -> Dictionary:
	var problem := _build_all()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	for id_panel in MENUS:
		if id_panel != PAGES[page]:
			_run({"cmd": "ui_show", "id_panel": id_panel, "visible": false})
	return _run({"cmd": "ui_show", "id_panel": PAGES[page], "visible": true})


func _hide_all() -> Dictionary:
	for id_panel in MENUS:
		if _shown(id_panel):
			_run({"cmd": "ui_show", "id_panel": id_panel, "visible": false})
	return {"ok": true}


func _shown(id_panel: String) -> bool:
	for panel in _run({"cmd": "ui_list"}).get("panels", []):
		if panel.get("id_panel") == id_panel:
			return panel.get("visible", false)
	return false


# --- The menus -----------------------------------------------------------------------

# Fills all three panels again (they're added the first time). Returns ""
# or what went wrong.
func _build_all() -> String:
	if _ui() == null:
		return "the pause menu needs the ui module"
	if _run({"cmd": "ui_get", "id_panel": OLD_SETTINGS_PANEL}).get("ok", false):
		_run({"cmd": "ui_remove", "id_panel": OLD_SETTINGS_PANEL})
	# The sub-menus first: the main menu's "open" buttons name them.
	for built in [[LOAD_PANEL, "Load", _load_elements()], [WORLDS_PANEL, "Worlds", _worlds_elements()],
			[PANEL, "Paused", _main_elements()]]:
		var problem := _put(built[0], built[1], built[2])
		if not problem.is_empty():
			return problem
	return ""


func _put(id_panel: String, title: String, elements: Array) -> String:
	var reply: Dictionary
	if _run({"cmd": "ui_get", "id_panel": id_panel}).get("ok", false):
		# Only the elements: where you put it stays.
		reply = _run({"cmd": "ui_update", "id_panel": id_panel, "elements": elements})
	else:
		reply = _run({"cmd": "ui_add", "id_panel": id_panel, "title": title, "place": "front", "distance": 0.55, "height": -0.2,
			"chrome": true, "layout": "column", "visible": false, "elements": elements})
	return "" if reply.get("ok", false) else "%s: %s" % [id_panel, reply.get("error", "?")]


func _text(id: String, text: String, color := "text", font_size := 30) -> Dictionary:
	return {"type": "text", "id": id, "text": text.left(400), "width": WIDTH, "color": color, "font_size": font_size}


func _button(id: String, label: String, action: Dictionary, color := "button", size := BUTTON) -> Dictionary:
	return {"type": "button", "id": id, "label": label.left(40), "size": size, "action": action, "color": color}


func _opener(id: String, label: String, to: String) -> Dictionary:
	return {"type": "button", "id": id, "label": label, "size": BUTTON, "open": to}


func _main_elements() -> Array:
	var out := [
		{"type": "text", "id": "where", "width": WIDTH, "font_size": 26, "color": "muted", "source": {"cmd": "pause_status", "field": "line"}},
		_button("resume", "Resume", {"cmd": "pause_do", "act": "hide"}, "accent"),
		_button("save", "Save world", {"cmd": "pause_do", "act": "save"}, "ok") if _has("save") else _text("save_missing", "Load save.gd to save the world.", "muted", 26),
		_opener("load", "Load", LOAD_PANEL),
		_opener("worlds_list", "Worlds", WORLDS_PANEL),
		_opener("windows", "All windows", "bar"),
		_button("hand", "Hand menu", {"cmd": "pause_do", "act": "hand_menu"}),
	]
	if _has("settings"):
		# settings.gd fills its window, which opens in this menu's place.
		out.insert(5, {"type": "button", "id": "settings", "label": "Settings", "size": BUTTON,
			"action": {"cmd": "settings_do", "act": "refresh"}, "open": "settings"})
	if _has("worlds"):
		# Opens in this menu's place, with a back arrow to it.
		var worlds := _button("worlds", "Files & modules", {"cmd": "worlds_do", "act": "show"})
		worlds["open"] = "worlds"
		out.append(worlds)
	return out


func _worlds_elements() -> Array:
	var out := []
	if not _has("projects"):
		return [_text("worlds_missing", "Load projects.gd to switch worlds.", "muted", 26)]
	var projects: Array = _run({"cmd": "projects_list"}).get("projects", [])
	for i in mini(projects.size(), MAX_WORLDS):
		var project: Dictionary = projects[i]
		if project.get("current", false):
			out.append(_text("w%d" % i, "> %s (you're here)" % project["name"], "accent", 28))
		else:
			out.append(_button("w%d" % i, project["name"], {"cmd": "pause_do", "act": "open_world", "name": project["name"]}))
	if projects.size() > MAX_WORLDS:
		out.append(_text("worlds_more", "and %d more in Files & modules" % (projects.size() - MAX_WORLDS), "muted", 26))
	return out


# The hand menu: a few big buttons above the left controller, at the hand
# window's half scale: Home, Settings, Undo / Redo, then a button for each
# loaded module with hand_info() (the terminal, the Tools menu, the
# Library's Textures / Assets / Prefabs). hand_info() returns {"id", "label",
# "order" (optional, lower first), and "panel": an id_panel it shows and
# hides, or "action": a command}, or a list of those for several buttons.
# Only the elements change after the menu is first added, so a hand menu
# you carried off stays where you put it.
func _hand_items() -> Array:
	var items := []
	for child in ctx["modules"].get_children():
		if child == self or not child.has_method("hand_info"):
			continue
		var infos = child.call("hand_info")
		for info in (infos if typeof(infos) == TYPE_ARRAY else [infos]):
			if typeof(info) != TYPE_DICTIONARY or typeof(info.get("id")) != TYPE_STRING or typeof(info.get("label")) != TYPE_STRING \
					or not (typeof(info.get("panel")) == TYPE_STRING or typeof(info.get("action")) == TYPE_DICTIONARY):
				push_error("Slopitect pause: %s's hand_info() needs id, label, and panel or action" % child.name)
				continue
			items.append(info)
	items.sort_custom(func(a, b): return [a.get("order", 100), a["id"]] < [b.get("order", 100), b["id"]])
	return items


# Status lines under the hand menu's buttons, from each loaded module with
# hand_status() -> {"id", "text", "color" (a theme colour name)}. The
# module keeps its line ("st_" + id) up to date itself (ui_element_update);
# only which modules have one makes the menu rebuild.
func _hand_statuses() -> Array:
	var out := []
	for child in ctx["modules"].get_children():
		if child == self or not child.has_method("hand_status"):
			continue
		var status = child.call("hand_status")
		if typeof(status) != TYPE_DICTIONARY or typeof(status.get("id")) != TYPE_STRING or typeof(status.get("text")) != TYPE_STRING:
			push_error("Slopitect pause: %s's hand_status() needs id and text" % child.name)
			continue
		out.append(status)
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return out


func _build_hand() -> void:
	var buttons := [_button("home", "Home", {"cmd": "pause_do", "act": "toggle"}, "accent", HAND_BUTTON)]
	if _has("settings"):
		buttons.append(_button("settings", "Settings", {"cmd": "settings_do", "act": "toggle"}, "button", HAND_BUTTON))
	if _has("tools"):
		buttons.append(_button("undo", "Undo", {"cmd": "tools_undo"}, "button", HAND_BUTTON))
		buttons.append(_button("redo", "Redo", {"cmd": "tools_redo"}, "button", HAND_BUTTON))
	for info in _hand_items():
		var action: Dictionary = info["action"] if info.has("action") else {"cmd": "pause_do", "act": "toggle_panel", "panel": info["panel"]}
		buttons.append(_button("m_" + str(info["id"]).left(30), str(info["label"]), action, "button", HAND_BUTTON))
	for button in _wrist_buttons():
		buttons.append(_button("w_" + str(button["id"]).left(30), str(button.get("label", button["id"])), button["action"], "button", HAND_BUTTON))
	var elements := [{"type": "grid", "id": "buttons", "columns": 2, "children": buttons}]
	for status in _hand_statuses():
		elements.append(_text("st_" + str(status["id"]).left(30), str(status["text"]), str(status.get("color", "muted")), 24))
	var reply: Dictionary
	if _run({"cmd": "ui_get", "id_panel": HAND_PANEL}).get("ok", false):
		reply = _run({"cmd": "ui_update", "id_panel": HAND_PANEL, "elements": elements})
	else:
		reply = _run({"cmd": "ui_add", "id_panel": HAND_PANEL, "title": "Menu", "place": "hand", "hand": "left",
			"chrome": true, "layout": "column", "visible": true, "elements": elements})
	if not reply.get("ok", false):
		push_error("Slopitect pause: the hand menu could not be built: %s" % reply.get("error", "?"))
		return
	if _shown(WRIST_PANEL):
		_run({"cmd": "ui_show", "id_panel": WRIST_PANEL, "visible": false})


# The wrist panel's buttons that run a command, to go on the hand menu.
func _wrist_buttons() -> Array:
	var out := []
	var stack: Array = _run({"cmd": "ui_get", "id_panel": WRIST_PANEL}).get("panel", {}).get("elements", []).duplicate()
	while not stack.is_empty():
		var element: Dictionary = stack.pop_front()
		stack.append_array(element.get("children", []))
		if element.get("type") == "button" and typeof(element.get("action")) == TYPE_DICTIONARY:
			out.append(element)
	return out


func _load_elements() -> Array:
	var out := []
	out.append(_text("checkpoints_title", "Go back to a checkpoint", "accent"))
	if not _has("save"):
		out.append(_text("checkpoints_missing", "Load save.gd for checkpoints.", "muted", 26))
		return out
	var checkpoints: Array = _run({"cmd": "save_checkpoints"}).get("checkpoints", [])
	checkpoints.reverse()  # newest first
	if checkpoints.is_empty():
		out.append(_text("checkpoints_none", "No checkpoints yet: Save world makes one.", "muted", 26))
	for i in mini(checkpoints.size(), MAX_CHECKPOINTS):
		var checkpoint: Dictionary = checkpoints[i]
		var when := str(checkpoint.get("saved", "")).replace("T", " ").left(16)
		var label := ("%s %s" % [when, checkpoint.get("label", "")]).strip_edges()
		out.append(_button("c%d" % i, label, {"cmd": "pause_do", "act": "restore", "checkpoint": checkpoint["checkpoint"]}))
	return out
