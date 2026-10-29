extends SlopitectModule

# Controller module: one place for controller buttons and windows.
# Hangs vrui panels on a controller, binds buttons to commands or to
# showing/hiding any panel (vrui or built-in ui), takes over the built-in
# ui toggles, and saves its setup to controller.json.

const BUTTONS := ["ax_button", "by_button", "menu_button", "grip_click", "primary_click", "trigger_click"]
const UI_TOGGLES := {"left_menu": "left:menu_button", "left_y": "left:by_button", "right_b": "right:by_button", "right_a": "right:ax_button"}
const SAVE := "controller.json"

var _attach := {}  # panel id -> {hand, offset, rotation, scale}
var _binds := {}   # "hand:button" -> {action} or {toggle}
var _taken := {}   # ui panel id -> its old toggle, given back on unload
var _vrui: Node = null


func setup() -> String:
	register("controller_attach", _do_attach, "hang a vrui panel on a controller: id, optional hand (left/right, default left), offset [x,y,z] m, rotation [x,y,z] deg, scale (default 0.5)")
	register("controller_detach", _do_detach, "take a vrui panel off its controller, leaving it where it is: id")
	register("controller_bind", _do_bind, "bind a controller button: hand (left/right), button (ax_button, by_button, menu_button, grip_click, primary_click, trigger_click), and action (a command) or toggle (any panel id, vrui or ui)")
	register("controller_unbind", _do_unbind, "remove a button binding: hand, button")
	register("controller_toggle", _do_toggle, "show/hide any panel, vrui or ui: id")
	register("controller_status", _do_status, "attached panels, button bindings, ui toggles taken over, buttons held now")
	_load()
	_take_ui_toggles()
	for h in ["left", "right"]:
		var c = ctx.get(h)
		if c != null and c.has_signal("button_pressed"):
			c.button_pressed.connect(_on_button.bind(h))
	return ""


func _exit_tree() -> void:
	for h in ["left", "right"]:
		var c = ctx.get(h)
		if c != null and c.has_signal("button_pressed") and c.button_pressed.is_connected(_on_button):
			c.button_pressed.disconnect(_on_button)
	for id in _attach.keys():
		_release(id)
	_attach.clear()
	for id in _taken:
		ctx["server"].run({"cmd": "ui_update", "id_panel": id, "toggle": _taken[id]})
	_taken.clear()


# ---------- saving ----------

func _save() -> void:
	var att := {}
	for id in _attach:
		var a: Dictionary = _attach[id]
		var o: Vector3 = a["offset"]
		var rv: Vector3 = a["rotation"]
		att[id] = {"hand": a["hand"], "offset": [o.x, o.y, o.z], "rotation": [rv.x, rv.y, rv.z], "scale": a["scale"]}
	ctx["server"].run({"cmd": "files_write", "path": SAVE, "text": JSON.stringify({"attach": att, "binds": _binds}, "\t")})


func _load() -> void:
	var r = ctx["server"].run({"cmd": "files_read", "path": SAVE})
	if not (r is Dictionary) or not r.get("ok", false) or not (r.get("text") is String):
		return
	var d = JSON.parse_string(r["text"])
	if not (d is Dictionary):
		return
	if d.get("binds") is Dictionary:
		for k in d["binds"]:
			if d["binds"][k] is Dictionary:
				_binds[str(k)] = d["binds"][k]
	if d.get("attach") is Dictionary:
		for id in d["attach"]:
			var a = d["attach"][id]
			if not (a is Dictionary):
				continue
			var off = _vec(a, "offset", Vector3(0, 0.12, -0.02))
			var rot = _vec(a, "rotation", Vector3(-35, 0, 0))
			var hand := str(a.get("hand", "left"))
			if off == null or rot == null or (hand != "left" and hand != "right"):
				continue
			_attach[str(id)] = {"hand": hand, "offset": off, "rotation": rot, "scale": clampf(float(a.get("scale", 0.5)), 0.1, 2.0)}


# ---------- ui panels ----------

func _ui_panels() -> Array:
	var r = ctx["server"].run({"cmd": "ui_list"})
	if r is Dictionary and r.get("panels") is Array:
		return r["panels"]
	return []


func _take_ui_toggles() -> void:
	for p in _ui_panels():
		var t := str(p.get("toggle", ""))
		if t == "" or not UI_TOGGLES.has(t):
			continue
		var id := str(p.get("id_panel", ""))
		var k: String = UI_TOGGLES[t]
		if not _binds.has(k):
			_binds[k] = {"toggle": id}
		var u = ctx["server"].run({"cmd": "ui_update", "id_panel": id, "toggle": ""})
		if u is Dictionary and u.get("ok", false):
			_taken[id] = t


func _toggle(id: String) -> String:
	var q := _quad(id)
	if q != null:
		q.visible = not q.visible
		return ""
	for p in _ui_panels():
		if str(p.get("id_panel", "")) == id:
			ctx["server"].run({"cmd": "ui_show", "id_panel": id, "visible": not bool(p.get("visible", false))})
			return ""
	return "no panel called " + id


# ---------- vrui panels ----------

func _find_vrui() -> Node:
	if _vrui != null and is_instance_valid(_vrui):
		return _vrui
	var m = ctx.get("modules")
	if m is Dictionary and m.has("vrui") and m["vrui"] is Node:
		_vrui = m["vrui"]
		return _vrui
	var par := get_parent()
	if par != null:
		for c in par.get_children():
			if c != self and c.get("_panels") is Dictionary and c.get("_holder") is Node3D:
				_vrui = c
				return _vrui
	return null


func _quad(id: String) -> Node3D:
	var v := _find_vrui()
	if v == null:
		return null
	var ps: Dictionary = v.get("_panels")
	if not ps.has(id):
		return null
	var q = ps[id].get("quad")
	if q is Node3D and is_instance_valid(q):
		return q
	return null


func _vec(r: Dictionary, key: String, def: Vector3):
	if not r.has(key):
		return def
	var a = r[key]
	if not (a is Array) or a.size() != 3:
		return null
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _apply(id: String) -> void:
	var q := _quad(id)
	if q == null:
		return
	var a: Dictionary = _attach[id]
	var c: Node3D = ctx[a["hand"]]
	if q.get_parent() != c:
		q.get_parent().remove_child(q)
		c.add_child(q)
	var rv: Vector3 = a["rotation"]
	var b := Basis.from_euler(Vector3(deg_to_rad(rv.x), deg_to_rad(rv.y), deg_to_rad(rv.z)))
	q.transform = Transform3D(b.scaled(Vector3.ONE * float(a["scale"])), a["offset"])


func _release(id: String) -> void:
	var q := _quad(id)
	var v := _find_vrui()
	if q == null or v == null:
		return
	var holder: Node3D = v.get("_holder")
	if q.get_parent() == holder:
		return
	var gt := q.global_transform
	q.get_parent().remove_child(q)
	holder.add_child(q)
	q.global_transform = gt


# ---------- commands ----------

func _do_attach(r: Dictionary) -> Dictionary:
	var id := str(r.get("id", ""))
	if _find_vrui() == null:
		return {"ok": false, "error": "vrui module is not loaded"}
	if _quad(id) == null:
		return {"ok": false, "error": "no vrui panel called " + id + " (built-in ui panels can't be hung on a controller; use place wrist)"}
	var hand := str(r.get("hand", "left"))
	if hand != "left" and hand != "right":
		return {"ok": false, "error": "hand must be left or right"}
	if ctx.get(hand) == null:
		return {"ok": false, "error": "no " + hand + " controller"}
	var off = _vec(r, "offset", Vector3(0, 0.12, -0.02))
	if off == null:
		return {"ok": false, "error": "offset must be [x, y, z]"}
	var rot = _vec(r, "rotation", Vector3(-35, 0, 0))
	if rot == null:
		return {"ok": false, "error": "rotation must be [x, y, z]"}
	var sc := clampf(float(r.get("scale", 0.5)), 0.1, 2.0)
	_attach[id] = {"hand": hand, "offset": off, "rotation": rot, "scale": sc}
	_apply(id)
	_save()
	return {"ok": true}


func _do_detach(r: Dictionary) -> Dictionary:
	var id := str(r.get("id", ""))
	if not _attach.has(id):
		return {"ok": false, "error": "panel " + id + " is not attached"}
	_release(id)
	_attach.erase(id)
	_save()
	return {"ok": true}


func _check_hb(r: Dictionary) -> String:
	var hand := str(r.get("hand", ""))
	if hand != "left" and hand != "right":
		return "hand must be left or right"
	if not BUTTONS.has(str(r.get("button", ""))):
		return "button must be one of " + ", ".join(BUTTONS)
	return ""


func _do_bind(r: Dictionary) -> Dictionary:
	var e := _check_hb(r)
	if e != "":
		return {"ok": false, "error": e}
	var b := {}
	if r.has("toggle"):
		b["toggle"] = str(r["toggle"])
	elif r.has("action"):
		if not (r["action"] is Dictionary and r["action"].has("cmd")):
			return {"ok": false, "error": "action must be a command object with cmd"}
		b["action"] = r["action"].duplicate(true)
	else:
		return {"ok": false, "error": "action or toggle is needed"}
	_binds[str(r["hand"]) + ":" + str(r["button"])] = b
	_save()
	return {"ok": true}


func _do_unbind(r: Dictionary) -> Dictionary:
	var e := _check_hb(r)
	if e != "":
		return {"ok": false, "error": e}
	var k := str(r["hand"]) + ":" + str(r["button"])
	if not _binds.has(k):
		return {"ok": false, "error": "nothing bound to " + k}
	_binds.erase(k)
	_save()
	return {"ok": true}


func _do_toggle(r: Dictionary) -> Dictionary:
	var e := _toggle(str(r.get("id", "")))
	if e != "":
		return {"ok": false, "error": e}
	return {"ok": true}


func _do_status(_r: Dictionary) -> Dictionary:
	var att := []
	for id in _attach:
		var a: Dictionary = _attach[id]
		var o: Vector3 = a["offset"]
		var rv: Vector3 = a["rotation"]
		att.append({"id": id, "hand": a["hand"], "offset": [o.x, o.y, o.z], "rotation": [rv.x, rv.y, rv.z], "scale": a["scale"]})
	var held := []
	for h in ["left", "right"]:
		var c = ctx.get(h)
		if c != null and c.has_method("is_button_pressed"):
			for bn in BUTTONS:
				if c.is_button_pressed(bn):
					held.append(h + ":" + bn)
	return {"ok": true, "attached": att, "bindings": _binds, "ui_taken": _taken, "held": held}


func _on_button(name: String, hand: String) -> void:
	var k := hand + ":" + name
	if not _binds.has(k):
		return
	var b: Dictionary = _binds[k]
	if b.has("toggle"):
		_toggle(str(b["toggle"]))
	elif b.has("action"):
		var a: Dictionary = b["action"].duplicate(true)
		if a.get("position") is String and a["position"] == "in_front":
			var ct: Transform3D = (ctx["camera"] as Node3D).global_transform
			var f := -ct.basis.z
			f.y = 0.0
			if f.length() < 0.01:
				f = Vector3(0, 0, -1)
			var p := ct.origin + f.normalized()
			a["position"] = [p.x, p.y, p.z]
		ctx["server"].run(a)


func _process(_d: float) -> void:
	for id in _attach:
		var q := _quad(id)
		if q != null and q.get_parent() != ctx[_attach[id]["hand"]]:
			_apply(id)
