extends SlopitectModule

# Slopitect live module: settings.
# The Settings window: one section for each loaded module that has settings,
# so a module's settings are part of its own file. Load it and its section
# appears, unload it and it goes; nothing here names a module.
#
# A module with settings has a settings_info() function returning
#   {"title": "Moving", "order": 10 (optional, lower first, 100 by default),
#    "settings": [a setting, ...]}
# Each setting is a Dictionary:
#   "id"      letters, digits and _, unique in the module
#   "type"    "choice", "slider", "toggle" or "button"
#   "label"   what it's called ("choice": optional, shown above the options)
#   "value"   what it is now (not for "button")
#   "set"     the command that changes it, run through the command server;
#             any field that is "{value}" becomes the chosen value
#   "choice": "options" [{"label", "value", optional "color" #rrggbb (the
#             button is that colour)}], optional "columns" (1 to 4; one row
#             if left out)
#   "slider": "min", "max", "step"
#   "toggle": the value is true or false
#   "button": no value; pressing it runs "set" as it is
# settings_info() is asked again whenever the window is drawn, so it says
# what's true now (a setting can come and go with another one's value).
#
# Every change goes through settings_set, which checks the value against
# what the module declared before running its "set". A "set" may not be a
# NAME_config or code_ command: those change only from the PC (CLAUDE.md),
# so only the comfort commands belong here. Each module keeps its own
# settings across restarts (user://NAME.json); this keeps nothing.
#
# The window has tabs (pages), so it's short: each module's section sits
# on the tab PAGE_OF gives it (PAGE_OTHER if none).

const PANEL := "settings"
const WIDTH := 0.42
const FULL := [0.42, 0.055]
const SCAN_SECONDS := 1.0  # while the window is open: redraw if a module or a value changed
const KINDS := ["choice", "slider", "toggle", "button"]
const PAGES := ["Move", "Look", "Other", "Speech"]
const PAGE_OF := {"controls": "Move", "vrui": "Look", "hands": "Look", "avatar": "Look", "tts": "Speech", "vtt": "Speech"}
const PAGE_OTHER := "Other"

var _signature := ""  # what the window was last drawn from
var _since_scan := 0.0
var _reported := {}  # problems already logged, so an open window doesn't log one every second


func setup() -> String:
	register("settings_list", _list_command, "every loaded module's settings (settings_info()): title, and each setting's id, type, value and choices")
	register("settings_set", _set_command, "change a setting the Settings window shows: module, id_setting (its id), value (what settings_list allows; not for a button)")
	register("settings_do", _do, "the Settings window: act = toggle, show, hide, refresh, new_conversation")
	return ""


func _exit_tree() -> void:
	if ctx["modules"].module(name) != null:
		return  # the app is closing, not unloading this: the window stays for next time
	ctx["server"].run({"cmd": "ui_remove", "id_panel": PANEL})


func menu_info() -> Dictionary:
	return {"id": "settings", "label": "Settings", "order": 5, "action": {"cmd": "settings_do", "act": "toggle"}}


# Its own section: the agent lives in the APK, which can't declare settings.
func settings_info() -> Dictionary:
	return {"title": "The agent", "order": 900, "settings": [
		{"id": "new_conversation", "type": "button", "label": "New conversation", "set": {"cmd": "settings_do", "act": "new_conversation"}},
	]}


func _process(delta: float) -> void:
	_since_scan += delta
	if _since_scan < SCAN_SECONDS:
		return
	_since_scan = 0.0
	if _shown():
		_build()


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


func _ui() -> SlopitectModule:
	var ui: SlopitectModule = ctx["modules"].module("vrui")
	return ui if ui != null else ctx["modules"].module("ui")


# --- What the modules declare ----------------------------------------------------------

# [{module, title, order, settings}] for every loaded module with good
# settings, and {module, problem} for one whose settings_info() is wrong.
func _sections() -> Array:
	var out := []
	for child in ctx["modules"].get_children():
		if not child.has_method("settings_info"):
			continue
		var info = child.call("settings_info")
		var problem := _check_info(info)
		if not problem.is_empty():
			var report := "Slopitect settings: %s's settings_info() %s" % [child.name, problem]
			if not _reported.has(report):
				_reported[report] = true
				push_error(report)
			out.append({"module": str(child.name), "title": str(child.name), "order": 1000, "problem": problem})
			continue
		out.append({"module": str(child.name), "title": info["title"], "order": int(info.get("order", 100)), "settings": info["settings"]})
	out.sort_custom(func(x, y): return [x["order"], x["title"]] < [y["order"], y["title"]])
	return out


func _check_info(info) -> String:
	if typeof(info) != TYPE_DICTIONARY:
		return "must return a Dictionary"
	if typeof(info.get("title")) != TYPE_STRING or info["title"].is_empty():
		return "needs \"title\""
	if info.has("order") and typeof(info["order"]) not in [TYPE_INT, TYPE_FLOAT]:
		return "\"order\" must be a number"
	if typeof(info.get("settings")) != TYPE_ARRAY:
		return "needs \"settings\", a list"
	var ids := []
	for setting in info["settings"]:
		var problem := _check_setting(setting)
		if problem.is_empty() and setting["id"] in ids:
			problem = "uses the id twice"
		if not problem.is_empty():
			return "setting %s: %s" % [JSON.stringify(setting.get("id", "?") if setting is Dictionary else setting), problem]
		ids.append(setting["id"])
	return ""


func _check_setting(setting) -> String:
	if typeof(setting) != TYPE_DICTIONARY:
		return "must be a Dictionary"
	var id = setting.get("id")
	if typeof(id) != TYPE_STRING or id.is_empty() or not id.is_valid_ascii_identifier():
		return "needs \"id\", letters, digits and _"
	if not setting.get("type") in KINDS:
		return "\"type\" must be one of %s" % [KINDS]
	if typeof(setting.get("set")) != TYPE_DICTIONARY or typeof(setting["set"].get("cmd")) != TYPE_STRING:
		return "needs \"set\", a command {\"cmd\": ...}"
	var cmd: String = setting["set"]["cmd"]
	if cmd.ends_with("_config") or cmd.begins_with("code_"):
		return "\"set\" can't be %s: it changes only from the PC" % cmd
	if setting["type"] != "choice" and (typeof(setting.get("label")) != TYPE_STRING or setting["label"].is_empty()):
		return "needs \"label\""
	match setting["type"]:
		"choice":
			if typeof(setting.get("options")) != TYPE_ARRAY or setting["options"].is_empty():
				return "a choice needs \"options\" [{\"label\", \"value\"}]"
			for option in setting["options"]:
				if typeof(option) != TYPE_DICTIONARY or typeof(option.get("label")) != TYPE_STRING or not option.has("value"):
					return "each option needs \"label\" and \"value\""
				if option.has("color") and (typeof(option["color"]) != TYPE_STRING or not Color.html_is_valid(option["color"])):
					return "an option's \"color\" must be #rrggbb"
			if setting.has("columns") and (typeof(setting["columns"]) not in [TYPE_INT, TYPE_FLOAT] or setting["columns"] < 1 or setting["columns"] > 4):
				return "\"columns\" must be 1 to 4"
		"slider":
			for key in ["min", "max", "step", "value"]:
				if typeof(setting.get(key)) not in [TYPE_INT, TYPE_FLOAT]:
					return "a slider needs \"%s\", a number" % key
			if setting["min"] >= setting["max"] or setting["step"] < 0:
				return "a slider's \"min\" must be under \"max\", and \"step\" not below 0"
		"toggle":
			if typeof(setting.get("value")) != TYPE_BOOL:
				return "a toggle's \"value\" must be true or false"
	return ""


func _find(module_name: String, id: String) -> Dictionary:
	for section in _sections():
		if section["module"] != module_name or section.has("problem"):
			continue
		for setting in section["settings"]:
			if setting["id"] == id:
				return setting
	return {}


# Numbers compare as numbers, colours and names without minding case.
func _same(a, b) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(a), float(b))
	if typeof(a) == TYPE_STRING and typeof(b) == TYPE_STRING:
		return a.to_lower() == b.to_lower()
	return typeof(a) == typeof(b) and a == b


func _fill(value, chosen):
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _fill(value[key], chosen)
		return out
	if value is Array:
		return value.map(func(item): return _fill(item, chosen))
	if value is String and value == "{value}":
		return chosen
	return value


# --- Commands --------------------------------------------------------------------------

func _list_command(_request: Dictionary) -> Dictionary:
	return {"ok": true, "sections": _sections()}


func _set_command(request: Dictionary) -> Dictionary:
	var module_name := str(request.get("module", ""))
	var id := str(request.get("id_setting", ""))
	var setting := _find(module_name, id)
	if setting.is_empty():
		return {"ok": false, "error": "no setting \"%s\" in module \"%s\" (settings_list shows them)" % [id, module_name]}
	var value = request.get("value")
	match setting["type"]:
		"choice":
			var found = null
			for option in setting["options"]:
				if _same(option["value"], value):
					found = option["value"]
			if found == null:
				return {"ok": false, "error": "\"value\" must be one of %s" % [setting["options"].map(func(o): return o["value"])]}
			value = found
		"slider":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < setting["min"] or value > setting["max"]:
				return {"ok": false, "error": "\"value\" must be a number from %s to %s" % [setting["min"], setting["max"]]}
			if typeof(setting["value"]) == TYPE_INT and typeof(value) == TYPE_FLOAT and is_equal_approx(value, roundf(value)):
				value = int(value)
		"toggle":
			if typeof(value) != TYPE_BOOL:
				return {"ok": false, "error": "\"value\" must be true or false"}
	var reply := _run(_fill(setting["set"], value))
	if _shown():
		_build()
	return reply


func _do(request: Dictionary) -> Dictionary:
	match request.get("act"):
		"toggle":
			if _shown():
				return _run({"cmd": "ui_show", "id_panel": PANEL, "visible": false})
			return _open()
		"show":
			return _open()
		"hide":
			return _run({"cmd": "ui_show", "id_panel": PANEL, "visible": false})
		"refresh":
			var problem := _build()
			return {"ok": true} if problem.is_empty() else {"ok": false, "error": problem}
		"new_conversation":
			return _run({"cmd": "agent_reset"})
	return {"ok": false, "error": "\"act\" must be toggle, show, hide, refresh or new_conversation"}


func _open() -> Dictionary:
	var problem := _build()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return _run({"cmd": "ui_show", "id_panel": PANEL, "visible": true})


func _shown() -> bool:
	for panel in _run({"cmd": "ui_list"}).get("panels", []):
		if panel.get("id_panel") == PANEL:
			return panel.get("visible", false)
	return false


# --- The window ------------------------------------------------------------------------

# Fills the window again if what it shows changed (it's added the first
# time). Returns "" or what went wrong.
func _build() -> String:
	if _ui() == null:
		return "the Settings window needs the ui module"
	var sections := _sections()
	var signature := JSON.stringify(sections)
	var exists: bool = _run({"cmd": "ui_get", "id_panel": PANEL}).get("ok", false)
	if exists and signature == _signature:
		return ""
	var elements := _elements(sections)
	var reply: Dictionary
	if exists:
		# Only the elements and tabs: where you put it stays.
		reply = _run({"cmd": "ui_update", "id_panel": PANEL, "elements": elements, "pages": PAGES})
	else:
		reply = _run({"cmd": "ui_add", "id_panel": PANEL, "title": "Settings", "place": "front", "distance": 0.55, "height": -0.2,
			"chrome": true, "layout": "column", "visible": false, "pages": PAGES, "page": PAGES[0], "elements": elements})
	if not reply.get("ok", false):
		return "%s: %s" % [PANEL, reply.get("error", "?")]
	_signature = signature
	return ""


func _elements(sections: Array) -> Array:
	var out := []
	for section in sections:
		var prefix := "%s_" % section["module"]
		var page: String = PAGE_OF.get(section["module"], PAGE_OTHER)
		var part := [_text(prefix + "title", section["title"], "accent")]
		if section.has("problem"):
			part.append(_text(prefix + "problem", "Its settings_info() %s." % section["problem"], "muted", 24))
		else:
			for setting in section["settings"]:
				part.append_array(_setting_elements(section["module"], prefix + setting["id"], setting))
		for element in part:
			element["page"] = page
			out.append(element)
	if sections.is_empty():
		var none := _text("none", "No loaded module has settings.", "muted", 26)
		none["page"] = PAGE_OTHER
		out.append(none)
	var pc_only := _text("pc_only", "Keys, services and the rest change from the PC (the *_config commands).", "muted", 24)
	pc_only["page"] = PAGE_OTHER
	out.append(pc_only)
	return out


func _setting_elements(module_name: String, id: String, setting: Dictionary) -> Array:
	var action := {"cmd": "settings_set", "module": module_name, "id_setting": setting["id"]}
	match setting["type"]:
		"slider":
			action["value"] = "{value}"
			return [{"type": "slider", "id": id, "label": setting["label"], "min": setting["min"], "max": setting["max"], "step": setting["step"],
				"value": clampf(float(setting["value"]), setting["min"], setting["max"]), "size": [WIDTH, 0.07], "action": action}]
		"toggle":
			action["value"] = "{on}"
			return [{"type": "toggle", "id": id, "label": setting["label"], "on": setting["value"], "size": FULL, "action": action}]
		"button":
			return [{"type": "button", "id": id, "label": setting["label"].left(40), "size": FULL, "action": action, "color": "button"}]
	# A choice: a button for each option, lit when it's the one chosen (a
	# colour swatch is its colour, so the chosen one says so instead).
	var out := []
	if setting.has("label") and not setting["label"].is_empty():
		out.append(_text(id + "_label", setting["label"], "muted", 24))
	var options: Array = setting["options"]
	var columns := int(setting.get("columns", options.size()))
	var cell := [snappedf((WIDTH - 0.01 * (columns - 1)) / columns, 0.001), 0.055]
	var buttons := []
	for i in options.size():
		var option: Dictionary = options[i]
		var on := _same(option["value"], setting.get("value"))
		var pick := action.duplicate()
		pick["value"] = option["value"]
		var label: String = option["label"]
		var color := "accent" if on else "button"
		if option.has("color"):
			color = option["color"]
			label = ("✓ " if on else "") + label
		buttons.append({"type": "button", "id": "%s_%d" % [id, i], "label": label.left(40), "size": cell, "action": pick, "color": color})
	if setting.has("columns"):
		out.append({"type": "grid", "id": id, "columns": columns, "children": buttons})
	else:
		out.append({"type": "row", "id": id, "children": buttons})
	return out


func _text(id: String, text: String, color := "text", font_size := 30) -> Dictionary:
	return {"type": "text", "id": id, "text": text.left(400), "width": WIDTH, "color": color, "font_size": font_size}
