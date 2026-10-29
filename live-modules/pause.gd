extends SlopitectModule

# Slopitect live module: pause.
# The pause menu, from its tile on the Menu (first in the row), or from any
# button bound to it on the PC:
#   .\slopi.ps1 '{"cmd":"controls_config","buttons":{"left/menu_button":{"panel":"pause"}}}'
# It doesn't stop the world; it's the one place for the world and the
# settings:
# - Resume closes it.
# - Save world keeps the whole world as a checkpoint (save.gd).
# - Load world opens a list of the worlds (projects.gd) and the newest
#   checkpoints to go back to, with a back arrow.
# - Settings opens what each setting is now and the few things you can
#   change in the headset (the avatar's outfit, a new conversation, stop
#   speaking). The rest change from the PC only (NAME_config).
# - Worlds window opens worlds.gd's window, when it's loaded.
# Each menu is a ui panel ("pause", "pause_load", "pause_settings"), kept by
# ui.gd like every panel; this fills them again each time the menu opens.
# A part whose module isn't loaded says so.

const PANEL := "pause"
const LOAD_PANEL := "pause_load"
const SETTINGS_PANEL := "pause_settings"
const WIDTH := 0.42
const BUTTON := [0.42, 0.06]
const HALF := [0.205, 0.055]
const MAX_WORLDS := 6
const MAX_CHECKPOINTS := 4
const MAX_OUTFITS := 6


func setup() -> String:
	register("pause_do", _do, "the pause menu: act = toggle, show, hide, refresh, save (optional label), open_world (name), restore (checkpoint), outfit (name), new_conversation")
	register("pause_status", _status, "the world you're in and what the pause menu can reach, one line")
	return ""


func _exit_tree() -> void:
	if ctx["modules"].module(name) != null:
		return  # the app is closing, not unloading this: the menus stay for next time
	for id_panel in [PANEL, LOAD_PANEL, SETTINGS_PANEL]:
		ctx["server"].run({"cmd": "ui_remove", "id_panel": id_panel})


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
			if _shown(PANEL) or _shown(LOAD_PANEL) or _shown(SETTINGS_PANEL):
				return _hide_all()
			return _open()
		"show":
			return _open()
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
		"outfit":
			var reply := _run({"cmd": "avatar_outfit", "name": request.get("name")})
			_build_all()
			return reply
		"new_conversation":
			return _run({"cmd": "agent_reset"})
	return {"ok": false, "error": "\"act\" must be toggle, show, hide, refresh, save, open_world, restore, outfit or new_conversation"}


func _status(_request: Dictionary) -> Dictionary:
	var world := str(_run({"cmd": "projects_current"}).get("name", "")) if _has("projects") else ""
	var line := "World: %s" % (world if not world.is_empty() else "(projects.gd isn't loaded)")
	if _has("save"):
		var saved := _run({"cmd": "save_checkpoints"}).get("checkpoints", []) as Array
		line += "   Checkpoints: %d" % saved.size()
	return {"ok": true, "world": world, "line": line}


func _open() -> Dictionary:
	var problem := _build_all()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	for id_panel in [LOAD_PANEL, SETTINGS_PANEL]:
		_run({"cmd": "ui_show", "id_panel": id_panel, "visible": false})
	return _run({"cmd": "ui_show", "id_panel": PANEL, "visible": true})


func _hide_all() -> Dictionary:
	for id_panel in [PANEL, LOAD_PANEL, SETTINGS_PANEL]:
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
	for built in [[LOAD_PANEL, "Load world", _load_elements()], [SETTINGS_PANEL, "Settings", _settings_elements()], [PANEL, "Paused", _main_elements()]]:
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
		_opener("load", "Load world", LOAD_PANEL),
		_opener("settings", "Settings", SETTINGS_PANEL),
	]
	if _has("worlds"):
		# Opens in this menu's place, with a back arrow to it.
		var worlds := _button("worlds", "Worlds window", {"cmd": "worlds_do", "act": "show"})
		worlds["open"] = "worlds"
		out.append(worlds)
	return out


func _load_elements() -> Array:
	var out := []
	out.append(_text("worlds_title", "Worlds", "accent"))
	if not _has("projects"):
		out.append(_text("worlds_missing", "Load projects.gd to switch worlds.", "muted", 26))
	else:
		var projects: Array = _run({"cmd": "projects_list"}).get("projects", [])
		for i in mini(projects.size(), MAX_WORLDS):
			var project: Dictionary = projects[i]
			if project.get("current", false):
				out.append(_text("w%d" % i, "> %s (you're here)" % project["name"], "accent", 28))
			else:
				out.append(_button("w%d" % i, project["name"], {"cmd": "pause_do", "act": "open_world", "name": project["name"]}))
		if projects.size() > MAX_WORLDS:
			out.append(_text("worlds_more", "and %d more in the Worlds window" % (projects.size() - MAX_WORLDS), "muted", 26))
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
	var out := [_text("now_title", "Settings now", "accent")]
	var lines := PackedStringArray()
	if _has("move"):
		var move: Dictionary = _run({"cmd": "move_status"}).get("settings", {})
		var turn := "snap %d°" % int(move.get("snap_degrees", 0)) if move.get("turn") == "snap" else "smooth %d°/s" % int(move.get("smooth_degrees", 0))
		lines.append("Moving: %s m/s, turning %s" % [move.get("speed", "?"), turn])
	var theme: Dictionary = _run({"cmd": "ui_theme_status"}).get("theme", {})
	if not theme.is_empty():
		lines.append("Text size: %s (titles %s)" % [theme.get("font_body", "?"), theme.get("font_title", "?")])
	if _has("hands"):
		var hands: Dictionary = _run({"cmd": "hands_status"}).get("settings", {})
		lines.append("Hands: skin %s" % hands.get("skin", "?"))
	var voice := _run({"cmd": "voice_status"})
	if voice.get("ok", false):
		lines.append("Speech: %s; talk: %s" % ["on" if voice.get("speech_out", false) else "off", voice.get("hold_to_talk", "?")])
	out.append(_text("now", "\n".join(lines), "text", 26))
	out.append(_text("pc_only", "These change from the PC (move_config, ui_config, hands_config, voice_config).", "muted", 24))
	if _has("avatar"):
		out.append(_text("outfit_title", "The avatar's outfit", "accent"))
		var outfits := _run({"cmd": "avatar_outfits"})
		var row := {"type": "grid", "id": "outfits", "columns": 2, "children": []}
		var names: Array = Array(outfits.get("outfits", []))
		for i in mini(names.size(), MAX_OUTFITS):
			var wearing: bool = names[i] == outfits.get("wearing", "")
			row["children"].append(_button("o%d" % i, ("> " if wearing else "") + names[i], {"cmd": "pause_do", "act": "outfit", "name": names[i]}, "accent" if wearing else "button", HALF))
		out.append(row)
	out.append(_text("agent_title", "The agent", "accent"))
	out.append({"type": "row", "id": "agent_row", "children": [
		_button("new_chat", "New conversation", {"cmd": "pause_do", "act": "new_conversation"}, "button", HALF),
		_button("hush", "Stop speaking", {"cmd": "voice_stop"}, "button", HALF),
	]})
	return out
