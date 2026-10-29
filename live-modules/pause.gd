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
# - Settings: the comfort settings, which change here in the headset
#   (turning, walk speed, text size, hand colours, the avatar's outfit), a
#   new conversation and stop speaking. Everything else changes from the PC
#   only (NAME_config).
# - All windows opens the Menu bar (every window's tile, and the shapes).
# - Hand menu shows or hides the hand menu.
# - Files & modules opens worlds.gd's window, when it's loaded.
# The hand menu sits above the left controller: Home (this menu), Save,
# Load, Worlds, and Undo / Redo (tools.gd's one list for every change).
# Each menu is a ui panel ("pause", "pause_load", "pause_worlds",
# "pause_settings", "hand_menu"), kept by the window module like every
# panel; this fills them again each time the menu opens.
# A part whose module isn't loaded says so.

const PANEL := "pause"
const LOAD_PANEL := "pause_load"
const WORLDS_PANEL := "pause_worlds"
const HAND_PANEL := "hand_menu"
const MENUS := [PANEL, LOAD_PANEL, "pause_worlds", "pause_settings"]
const PAGES := {"main": PANEL, "load": LOAD_PANEL, "worlds": "pause_worlds", "settings": "pause_settings"}
const HAND_BUTTON := [0.16, 0.07]
const CHECK_SECONDS := 1.0
const SETTINGS_PANEL := "pause_settings"
const WIDTH := 0.42
const BUTTON := [0.42, 0.06]
const HALF := [0.205, 0.055]
const MAX_WORLDS := 6
const MAX_CHECKPOINTS := 6
const MAX_OUTFITS := 6
const THIRD := [0.133, 0.055]
# The settings a Settings button may change: the comfort settings isaac chose
# to have in the headset (2026-10-29). Everything else stays PC only.
const SETTINGS_COMMANDS := ["move_comfort", "ui_text_size", "hands_colours", "avatar_outfit"]
const TEXT_SIZES := {"small": 30, "medium": 36, "large": 44}  # ui_text_size's body text
const SKINS := {"Light": "#f1c9a5", "Tan": "#e0ac80", "Brown": "#a86b45", "Dark": "#5c3a24", "Blue": "#5b7bd6"}
const NAILS := {"Pink": "#ff3b7a", "Red": "#d1263b", "Blue": "#3b6bff", "Black": "#16161c", "Clear": "#f4e6e0"}


func setup() -> String:
	register("pause_do", _do, "the pause menu: act = toggle, show (optional page: main, load, worlds, settings), hide, hand_menu (show or hide it), refresh, save (optional label), open_world (name), restore (checkpoint), setting (run: a comfort setting command), new_conversation")
	register("pause_status", _status, "the world you're in and what the pause menu can reach, one line")
	return ""


func _exit_tree() -> void:
	if ctx["modules"].module(name) != null:
		return  # the app is closing, not unloading this: the menus stay for next time
	for id_panel in MENUS + [HAND_PANEL]:
		ctx["server"].run({"cmd": "ui_remove", "id_panel": id_panel})


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
	var signature := "%d %s %s" % [ui.get_instance_id(), _has("tools"), _has("save")]
	if signature != _hand_signature or not _run({"cmd": "ui_get", "id_panel": HAND_PANEL}).get("ok", false):
		_hand_signature = signature
		_build_hand()


# The left home button opens and closes the pause menu. This module asks
# before the windows (0), so the Menu bar is reached from here (All windows).
func action_order() -> int:
	return -10


func on_action(action: String, down: bool) -> bool:
	if action != "left_menu" or _ui() == null:
		return false
	if down:
		_do({"act": "toggle"})
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
		"setting":
			var run = request.get("run")
			if typeof(run) != TYPE_DICTIONARY or not run.get("cmd") in SETTINGS_COMMANDS:
				return {"ok": false, "error": "\"run\" must be one of %s with its fields" % [SETTINGS_COMMANDS]}
			var reply := _run(run)
			_build_all()
			return reply
		"new_conversation":
			return _run({"cmd": "agent_reset"})
	return {"ok": false, "error": "\"act\" must be toggle, show, hide, hand_menu, refresh, save, open_world, restore, setting or new_conversation"}


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
	# The sub-menus first: the main menu's "open" buttons name them.
	for built in [[LOAD_PANEL, "Load", _load_elements()], [WORLDS_PANEL, "Worlds", _worlds_elements()],
			[SETTINGS_PANEL, "Settings", _settings_elements()], [PANEL, "Paused", _main_elements()]]:
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
		_opener("settings", "Settings", SETTINGS_PANEL),
		_opener("windows", "All windows", "bar"),
		_button("hand", "Hand menu", {"cmd": "pause_do", "act": "hand_menu"}),
	]
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
# window's half scale. Only the elements change after it's first added, so
# a hand menu you carried off stays where you put it.
func _build_hand() -> void:
	var buttons := [_button("home", "Home", {"cmd": "pause_do", "act": "toggle"}, "accent", HAND_BUTTON)]
	if _has("save"):
		buttons.append(_button("save", "Save", {"cmd": "pause_do", "act": "save"}, "ok", HAND_BUTTON))
		buttons.append(_button("load", "Load", {"cmd": "pause_do", "act": "show", "page": "load"}, "button", HAND_BUTTON))
	buttons.append(_button("worlds", "Worlds", {"cmd": "pause_do", "act": "show", "page": "worlds"}, "button", HAND_BUTTON))
	if _has("tools"):
		buttons.append(_button("undo", "Undo", {"cmd": "tools_undo"}, "button", HAND_BUTTON))
		buttons.append(_button("redo", "Redo", {"cmd": "tools_redo"}, "button", HAND_BUTTON))
	var elements := [{"type": "grid", "id": "buttons", "columns": 2, "children": buttons}]
	var reply: Dictionary
	if _run({"cmd": "ui_get", "id_panel": HAND_PANEL}).get("ok", false):
		reply = _run({"cmd": "ui_update", "id_panel": HAND_PANEL, "elements": elements})
	else:
		reply = _run({"cmd": "ui_add", "id_panel": HAND_PANEL, "title": "Menu", "place": "hand", "hand": "left",
			"chrome": true, "layout": "column", "visible": true, "elements": elements})
	if not reply.get("ok", false):
		push_error("Slopitect pause: the hand menu could not be built: %s" % reply.get("error", "?"))


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


func _settings_elements() -> Array:
	var out := []
	if _has("move"):
		var move: Dictionary = _run({"cmd": "move_status"}).get("settings", {})
		var snap: bool = move.get("turn") == "snap"
		out.append(_text("move_title", "Moving", "accent"))
		out.append({"type": "row", "id": "turn_row", "children": [
			_choice("turn_snap", "Snap turn", snap, {"cmd": "move_comfort", "turn": "snap"}),
			_choice("turn_smooth", "Smooth turn", not snap, {"cmd": "move_comfort", "turn": "smooth"}),
		]})
		out.append(_slider("speed", "Walk speed (m/s)", 0.5, 3.0, 0.25, move.get("speed", 1.5), {"cmd": "move_comfort", "speed": "{value}"}))
		if snap:
			out.append(_slider("snap", "Snap angle (°)", 15, 90, 15, move.get("snap_degrees", 30), {"cmd": "move_comfort", "snap_degrees": "{value}"}))
		else:
			out.append(_slider("smooth", "Turn speed (°/s)", 30, 180, 15, move.get("smooth_degrees", 90), {"cmd": "move_comfort", "smooth_degrees": "{value}"}))
	var theme: Dictionary = _run({"cmd": "ui_theme_status"}).get("theme", {})
	if not theme.is_empty():
		out.append(_text("text_title", "Text size", "accent"))
		var sizes := []
		for size in TEXT_SIZES:
			sizes.append(_choice("text_" + size, size.capitalize(), int(theme.get("font_body", 0)) == TEXT_SIZES[size], {"cmd": "ui_text_size", "size": size}, THIRD))
		out.append({"type": "row", "id": "text_row", "children": sizes})
	if _has("hands"):
		var hands: Dictionary = _run({"cmd": "hands_status"}).get("settings", {})
		out.append(_text("hands_title", "Hands", "accent"))
		for part in [["skin", SKINS, str(hands.get("skin", ""))], ["nails", NAILS, str(hands.get("nails_left", [""])[0])]]:
			var swatches := []
			for colour_name in part[1]:
				var colour: String = part[1][colour_name]
				var on: bool = colour.to_lower() == part[2].to_lower()
				# The swatch is the colour itself; the chosen one says so.
				swatches.append(_button("%s_%s" % [part[0], colour_name.to_lower()], ("✓ " if on else "") + colour_name,
					{"cmd": "pause_do", "act": "setting", "run": {"cmd": "hands_colours", part[0]: colour}}, colour, THIRD))
			out.append(_text(part[0] + "_label", part[0].capitalize(), "muted", 24))
			out.append({"type": "grid", "id": part[0] + "_grid", "columns": 3, "children": swatches})
	if _has("avatar"):
		out.append(_text("outfit_title", "The avatar's outfit", "accent"))
		var outfits := _run({"cmd": "avatar_outfits"})
		var grid := {"type": "grid", "id": "outfits", "columns": 2, "children": []}
		var names: Array = Array(outfits.get("outfits", []))
		for i in mini(names.size(), MAX_OUTFITS):
			grid["children"].append(_choice("o%d" % i, names[i], names[i] == outfits.get("wearing", ""), {"cmd": "avatar_outfit", "name": names[i]}))
		out.append(grid)
	out.append(_text("agent_title", "The agent", "accent"))
	out.append({"type": "row", "id": "agent_row", "children": [
		_button("new_chat", "New conversation", {"cmd": "pause_do", "act": "new_conversation"}, "button", HALF),
		_button("hush", "Stop speaking", {"cmd": "voice_stop"}, "button", HALF),
	]})
	out.append(_text("pc_only", "Voice speed and the rest change from the PC (voice_config and the other *_config).", "muted", 24))
	return out


# A button that is one of a set: lit when it's the one chosen. Pressing it
# changes the setting and fills the menu again to show it.
func _choice(id: String, label: String, on: bool, run: Dictionary, size := HALF) -> Dictionary:
	return _button(id, label, {"cmd": "pause_do", "act": "setting", "run": run}, "accent" if on else "button", size)


func _slider(id: String, label: String, lo: float, hi: float, step: float, value, action: Dictionary) -> Dictionary:
	return {"type": "slider", "id": id, "label": label, "min": lo, "max": hi, "step": step,
		"value": clampf(float(value), lo, hi), "size": [WIDTH, 0.07], "action": action}
