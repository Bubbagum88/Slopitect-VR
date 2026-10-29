extends SlopitectModule

# World module: save, load and clear the whole world (objects, paths,
# landscape heights) as files in worlds/NAME.json in the Slopitect folder.
# Before a load or a clear, the current world is saved as "autosave".
# Also builds three pause-menu windows: worlds (named saves), files (a
# browser for the Slopitect folder) and mods (live modules).

const DIR := "worlds"
const ROW := 0.07
const MAX_ROWS := 9


func setup() -> String:
	register("world_save", _do_save, "save the world: name (letters, digits, _ -)")
	register("world_load", _do_load, "load a saved world (current one goes to autosave first): name")
	register("world_new", _do_new, "clear the world: objects, paths, landscape (current one goes to autosave first)")
	register("world_delete", _do_delete, "delete a saved world: name")
	register("world_list", _do_list, "saved worlds")
	register("world_status", _do_status, "a short line for panels: saved worlds and live modules")
	register("world_browse", _do_browse, "open the Worlds window (named saves, load, delete)")
	register("world_files", _do_files, "open the Files window: optional path in the Slopitect folder, optional page")
	register("world_mods", _do_mods, "open the Modules window (live modules, reload, unload)")
	_run({"cmd": "files_mkdir", "path": DIR})
	return ""


func _exit_tree() -> void:
	for id in ["worlds", "files", "mods"]:
		ctx["server"].run({"cmd": "ui_remove", "id_panel": id})


func _run(c: Dictionary) -> Dictionary:
	var r = ctx["server"].run(c)
	if r is Dictionary:
		return r
	return {"ok": false, "error": "no reply"}


func _land() -> Node:
	var m = ctx.get("modules")
	if m is Dictionary and m.has("landscape") and m["landscape"] is Node:
		return m["landscape"]
	var par := get_parent()
	if par != null:
		for c in par.get_children():
			if c != self and c.has_method("get_heights") and c.has_method("set_heights"):
				return c
	return null


func _name_ok(n: String) -> bool:
	if n == "" or n.length() > 40:
		return false
	for ch in n:
		if not (ch in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"):
			return false
	return true


# ---------- save / load ----------

func _snapshot() -> Dictionary:
	var d := {"version": 1, "objects": [], "paths": []}
	var lo := _run({"cmd": "list"})
	if lo.get("objects") is Array:
		d["objects"] = lo["objects"]
	var lp := _run({"cmd": "paths_list"})
	if lp.get("paths") is Array:
		d["paths"] = lp["paths"]
	var land := _land()
	if land != null:
		var h: PackedFloat32Array = land.get_heights()
		d["heights"] = Marshalls.raw_to_base64(h.to_byte_array())
	return d


func _write(n: String) -> Dictionary:
	var d := _snapshot()
	var w := _run({"cmd": "files_write", "path": DIR + "/" + n + ".json", "text": JSON.stringify(d)})
	if not w.get("ok", false):
		return {"ok": false, "error": "can't write: " + str(w.get("error", "?"))}
	return {"ok": true, "name": n, "objects": d["objects"].size(), "paths": d["paths"].size()}


func _clear() -> void:
	var lo := _run({"cmd": "list"})
	if lo.get("objects") is Array:
		for o in lo["objects"]:
			_run({"cmd": "delete", "name": o.get("name", "")})
	var lp := _run({"cmd": "paths_list"})
	if lp.get("paths") is Array:
		for p in lp["paths"]:
			_run({"cmd": "paths_delete", "path": p.get("id")})


func _do_save(r: Dictionary) -> Dictionary:
	var n := str(r.get("name", "")).strip_edges()
	if not _name_ok(n):
		return {"ok": false, "error": "name must be 1-40 letters, digits, _ or -"}
	var res := _write(n)
	_refresh("worlds")
	return res


func _do_load(r: Dictionary) -> Dictionary:
	var n := str(r.get("name", ""))
	if not _name_ok(n):
		return {"ok": false, "error": "name must be 1-40 letters, digits, _ or -"}
	var f := _run({"cmd": "files_read", "path": DIR + "/" + n + ".json", "max_bytes": 1048576})
	if not f.get("ok", false) or not (f.get("text") is String):
		return {"ok": false, "error": "no saved world called " + n}
	var d = JSON.parse_string(f["text"])
	if not (d is Dictionary):
		return {"ok": false, "error": "world file " + n + " is broken"}
	if n != "autosave":
		_write("autosave")
	_clear()
	var bad := 0
	for o in d.get("objects", []):
		if not (o is Dictionary):
			continue
		var c := {"cmd": "spawn"}
		for k in ["shape", "name", "position", "rotation", "scale"]:
			if o.has(k):
				c[k] = o[k]
		var col := str(o.get("color", ""))
		if col != "":
			c["color"] = col if col.begins_with("#") else "#" + col
		if not _run(c).get("ok", false):
			bad += 1
	for p in d.get("paths", []):
		if not (p is Dictionary) or not p.has("points"):
			continue
		var c := {"cmd": "paths_add", "points": p["points"]}
		for k in ["width", "color", "flatten"]:
			if p.has(k):
				c[k] = p[k]
		if not _run(c).get("ok", false):
			bad += 1
	var land := _land()
	if land != null and d.get("heights") is String:
		var h := Marshalls.base64_to_raw(d["heights"]).to_float32_array()
		land.set_heights(h)
	_refresh("worlds")
	return {"ok": true, "name": n, "objects": d.get("objects", []).size(), "paths": d.get("paths", []).size(), "failed": bad}


func _do_new(_r: Dictionary) -> Dictionary:
	_write("autosave")
	_clear()
	_run({"cmd": "landscape_reset"})
	_refresh("worlds")
	return {"ok": true, "saved_old_as": "autosave"}


func _do_delete(r: Dictionary) -> Dictionary:
	var n := str(r.get("name", ""))
	if not _name_ok(n):
		return {"ok": false, "error": "name must be 1-40 letters, digits, _ or -"}
	var d := _run({"cmd": "files_delete", "path": DIR + "/" + n + ".json"})
	if not d.get("ok", false):
		return {"ok": false, "error": "can't delete " + n + ": " + str(d.get("error", "?"))}
	_refresh("worlds")
	return {"ok": true}


func _names() -> Array:
	var out := []
	var l := _run({"cmd": "files_list", "path": DIR})
	if l.get("files") is Array:
		for f in l["files"]:
			var fn := str(f.get("name", ""))
			if fn.ends_with(".json"):
				out.append(fn.trim_suffix(".json"))
	out.sort()
	return out


func _do_list(_r: Dictionary) -> Dictionary:
	return {"ok": true, "worlds": _names()}


func _do_status(_r: Dictionary) -> Dictionary:
	var w := _names()
	var mods := []
	var errs := []
	var cl := _run({"cmd": "code_list"})
	if cl.get("modules") is Array:
		for m in cl["modules"]:
			if m.get("loaded", false):
				mods.append(str(m.get("name", "")))
			if str(m.get("error", "")) != "":
				errs.append(str(m.get("name", "")))
	var line := "Saves: " + (", ".join(w) if w.size() > 0 else "none")
	line += "\nModules (" + str(mods.size()) + "): " + ", ".join(mods)
	if errs.size() > 0:
		line += "\nErrors: " + ", ".join(errs)
	return {"ok": true, "line": line, "worlds": w, "modules": mods}


# ---------- windows ----------

var _files_path := ""
var _files_page := 0


func _is_open(id: String) -> bool:
	var l := _run({"cmd": "ui_list"})
	if l.get("panels") is Array:
		for p in l["panels"]:
			if str(p.get("id_panel", "")) == id:
				return bool(p.get("visible", false))
	return false


func _refresh(id: String) -> void:
	if not _is_open(id):
		return
	match id:
		"worlds":
			_build_worlds()
		"files":
			_build_files()
		"mods":
			_build_mods()


func _show_panel(id: String, title: String, rows: int, els: Array) -> void:
	var h := 0.2 + rows * ROW
	var top := h / 2.0
	for e in els:
		var at: Array = e["at"]
		at[1] = top - float(at[1])  # rows were laid out from the top
	_run({"cmd": "ui_remove", "id_panel": id})
	_run({"cmd": "ui_add", "id_panel": id, "title": title, "place": "front", "distance": 0.65, "height": -0.1,
		"size": [0.64, h], "color": "#0b0d11", "layout": "free", "visible": true, "elements": els})


func _btn(id: String, label: String, x: float, y: float, w: float, action: Dictionary, color := "#3a3f4a") -> Dictionary:
	return {"type": "button", "id": id, "label": label, "at": [x, y], "size": [w, 0.058], "action": action, "color": color}


func _txt(id: String, text: String, x: float, y: float, w: float, color := "#ffffff", fs := 26) -> Dictionary:
	return {"type": "text", "id": id, "text": text, "at": [x, y], "width": w, "font_size": fs, "color": color, "align": "left"}


func _close_btn(id: String, y: float) -> Dictionary:
	return _btn("back", "Back", 0.23, y, 0.13, {"cmd": "controller_toggle", "id": id}, "#2a5d9a")


func _build_worlds() -> void:
	var els := []
	els.append({"type": "input", "id": "wname", "at": [-0.08, 0.06], "width": 0.42, "font_size": 32, "prompt": "name: ", "max_length": 40})
	els.append(_btn("saveas", "Save as", 0.23, 0.06, 0.13, {"cmd": "world_save", "name": "{input:wname}"}, "#2f6b3a"))
	els.append(_txt("hint", "Point at box, type with Chat keys", -0.0, 0.1, 0.6, "#8a93a6", 24))
	var names := _names()
	var row := 0
	for n in names:
		if row >= MAX_ROWS:
			break
		var y := 0.2 + row * ROW
		els.append(_txt("n%d" % row, n, -0.13, y - 0.02, 0.32))
		els.append(_btn("l%d" % row, "Load", 0.1, y, 0.12, {"cmd": "world_load", "name": n}, "#2a5d9a"))
		els.append(_btn("d%d" % row, "Delete", 0.23, y, 0.12, {"cmd": "world_delete", "name": n}, "#8a2a2a"))
		row += 1
	if names.is_empty():
		els.append(_txt("none", "No saves yet.", 0.0, 0.18, 0.6, "#8a93a6"))
		row = 1
	var by := 0.2 + row * ROW + 0.01
	els.append(_btn("keys", "Keyboard", -0.2, by, 0.16, {"cmd": "controller_toggle", "id": "chat"}))
	els.append(_close_btn("worlds", by))
	_show_panel("worlds", "Worlds", row + 1, els)


func _do_browse(_r: Dictionary) -> Dictionary:
	_build_worlds()
	return {"ok": true}


func _parent(p: String) -> String:
	var i := p.rfind("/")
	return "" if i < 0 else p.substr(0, i)


func _build_files() -> void:
	var req := {"cmd": "files_list"}
	if _files_path != "":
		req["path"] = _files_path
	var l := _run(req)
	var els := []
	els.append(_txt("where", "/" + _files_path, 0.0, 0.02, 0.6, "#9fb4ff", 26))
	if not l.get("ok", false):
		els.append(_txt("err", "Can't open: " + str(l.get("error", "?")), 0.0, 0.1, 0.6, "#ff8a8a"))
		els.append(_btn("up", "Up", -0.2, 0.2, 0.13, {"cmd": "world_files", "path": _parent(_files_path)}))
		els.append(_close_btn("files", 0.2))
		_show_panel("files", "Files", 2, els)
		return
	var entries := []
	for f in l.get("folders", []):
		entries.append({"dir": true, "name": str(f)})
	for f in l.get("files", []):
		entries.append({"dir": false, "name": str(f.get("name", "")), "bytes": int(f.get("bytes", 0))})
	var pages := maxi(1, ceili(entries.size() / float(MAX_ROWS)))
	_files_page = clampi(_files_page, 0, pages - 1)
	var row := 0
	for i in range(_files_page * MAX_ROWS, mini(entries.size(), (_files_page + 1) * MAX_ROWS)):
		var e: Dictionary = entries[i]
		var y := 0.13 + row * ROW
		var sub: String = e["name"] if _files_path == "" else _files_path + "/" + e["name"]
		if e["dir"]:
			els.append(_btn("e%d" % row, e["name"] + "/", 0.0, y, 0.6, {"cmd": "world_files", "path": sub}, "#2a4d5a"))
		else:
			var b: int = e["bytes"]
			var sz := (str(b) + " B") if b < 1024 else (str(snappedf(b / 1024.0, 0.1)) + " KB")
			els.append(_txt("e%d" % row, e["name"] + "   " + sz, 0.0, y - 0.02, 0.6))
		row += 1
	if entries.is_empty():
		els.append(_txt("empty", "(empty)", 0.0, 0.11, 0.6, "#8a93a6"))
		row = 1
	var by := 0.13 + row * ROW + 0.01
	if _files_path != "":
		els.append(_btn("up", "Up", -0.23, by, 0.13, {"cmd": "world_files", "path": _parent(_files_path)}))
	if pages > 1:
		els.append(_btn("prev", "<", -0.08, by, 0.08, {"cmd": "world_files", "path": _files_path, "page": _files_page - 1}))
		els.append(_txt("pg", "%d/%d" % [_files_page + 1, pages], 0.04, by - 0.02, 0.1))
		els.append(_btn("next", ">", 0.1, by, 0.08, {"cmd": "world_files", "path": _files_path, "page": _files_page + 1}))
	els.append(_close_btn("files", by))
	_show_panel("files", "Files", row + 1, els)


func _do_files(r: Dictionary) -> Dictionary:
	var p := str(r.get("path", _files_path)).strip_edges().trim_prefix("/").trim_suffix("/")
	if ".." in p.split("/"):
		return {"ok": false, "error": "path can't use .."}
	if p != _files_path:
		_files_page = 0
	_files_path = p
	if r.has("page"):
		_files_page = int(r["page"])
	_build_files()
	return {"ok": true, "path": _files_path}


func _build_mods() -> void:
	var cl := _run({"cmd": "code_list"})
	var els := []
	var row := 0
	for m in cl.get("modules", []):
		if row >= 12:
			break
		var n := str(m.get("name", ""))
		var err := str(m.get("error", ""))
		var state := "on" if m.get("loaded", false) else "off"
		if err != "":
			state = "error"
		elif m.get("changed_since_approved", false):
			state += ", changed"
		var y := 0.06 + row * ROW
		var col := "#ff8a8a" if err != "" else ("#8cff99" if state.begins_with("on") else "#8a93a6")
		els.append(_txt("n%d" % row, n + "  (" + state + ")", -0.12, y - 0.02, 0.36, col))
		els.append(_btn("r%d" % row, "Reload", 0.12, y, 0.12, {"cmd": "code_load", "name": n}, "#2a5d9a"))
		if m.get("loaded", false):
			els.append(_btn("u%d" % row, "Unload", 0.25, y, 0.11, {"cmd": "code_unload", "name": n}, "#8a2a2a"))
		row += 1
	var by := 0.06 + row * ROW + 0.01
	els.append(_btn("refresh", "Refresh", -0.2, by, 0.16, {"cmd": "world_mods"}))
	els.append(_close_btn("mods", by))
	_show_panel("mods", "Modules", row + 1, els)


func _do_mods(_r: Dictionary) -> Dictionary:
	_build_mods()
	return {"ok": true}
