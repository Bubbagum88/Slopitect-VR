extends SlopitectModule

# Real Godot UI panels in VR. Each panel is a 2D Control tree drawn into a
# SubViewport and shown on a quad. The right controller's ray acts as a
# mouse (trigger = click), with hover and press states.
# Idea ported from MT-ZD/Godot-3D-VR-UI (MIT, C#) to GDScript.

const PX_PER_M := 1200.0

var _holder: Node3D
var _cursor: MeshInstance3D
var _panels := {}  # id -> {quad, vp, size, px, status}
var _held := false
var _block := false
var _hover_id := ""
var _last_px := Vector2.ZERO


func setup() -> String:
	register("vrui_panel", _panel, "make or replace a panel: id, optional title, distance (m, default 0.6), height (m from eyes, default -0.15), size [w, h] m, columns (default 3), items [{type: button or label, label or text, action (a command; position \"in_front\" works), color}]")
	register("vrui_remove", _remove, "remove a panel: id")
	register("vrui_show", _show, "show or hide a panel: id, visible")
	register("vrui_list", _list, "the panels made with vrui")
	_holder = Node3D.new()
	add_child(_holder)
	_cursor = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.006
	m.height = 0.012
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1)
	m.material = mat
	_cursor.mesh = m
	_cursor.visible = false
	_holder.add_child(_cursor)
	return ""


func _style(c: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _panel(r: Dictionary) -> Dictionary:
	var id := str(r.get("id", ""))
	if id == "":
		return {"ok": false, "error": "id is needed"}
	var size := Vector2(0.4, 0.25)
	if r.has("size"):
		var s = r["size"]
		if not (s is Array) or s.size() != 2:
			return {"ok": false, "error": "size must be [w, h] in metres"}
		size = Vector2(clampf(float(s[0]), 0.1, 1.5), clampf(float(s[1]), 0.05, 1.5))
	var items = r.get("items", [])
	if not (items is Array):
		return {"ok": false, "error": "items must be a list"}
	for it in items:
		if not (it is Dictionary):
			return {"ok": false, "error": "each item must be an object"}
		var ty := str(it.get("type", "button"))
		if ty != "button" and ty != "label":
			return {"ok": false, "error": "item type must be button or label, got " + ty}
		if ty == "button" and it.has("action") and not (it["action"] is Dictionary and it["action"].has("cmd")):
			return {"ok": false, "error": "a button's action must be a command object with cmd"}
	var columns := clampi(int(r.get("columns", 3)), 1, 8)
	var dist := clampf(float(r.get("distance", 0.6)), 0.3, 3.0)
	var height := clampf(float(r.get("height", -0.15)), -1.5, 1.5)

	if _panels.has(id):
		_free_panel(id)

	var px := Vector2i(int(size.x * PX_PER_M), int(size.y * PX_PER_M))
	var quad := MeshInstance3D.new()
	_holder.add_child(quad)
	var vp := SubViewport.new()
	vp.size = px
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	quad.add_child(vp)

	var bg := PanelContainer.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(px)
	var bgs := _style(Color("#0b0d11f0"), 28)
	bgs.set_content_margin_all(22)
	bgs.border_color = Color("#3a4560")
	bgs.set_border_width_all(3)
	bg.add_theme_stylebox_override("panel", bgs)
	vp.add_child(bg)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	bg.add_child(vb)

	var title := str(r.get("title", ""))
	if title != "":
		var tl := Label.new()
		tl.text = title
		tl.add_theme_font_size_override("font_size", 40)
		tl.add_theme_color_override("font_color", Color("#9fb4ff"))
		vb.add_child(tl)

	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)

	for it in items:
		var ty := str(it.get("type", "button"))
		if ty == "label":
			var l := Label.new()
			l.text = str(it.get("text", it.get("label", "")))
			l.add_theme_font_size_override("font_size", 32)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(l)
		else:
			var b := Button.new()
			b.text = str(it.get("label", "?"))
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(0, 84)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 32)
			var base := Color(str(it.get("color", "#1f2129")))
			b.add_theme_stylebox_override("normal", _style(base, 18))
			b.add_theme_stylebox_override("hover", _style(base.lightened(0.25), 18))
			b.add_theme_stylebox_override("pressed", _style(Color("#4a6cff"), 18))
			b.pressed.connect(_on_press.bind(id, it.get("action", {})))
			grid.add_child(b)

	var status := Label.new()
	status.text = ""
	status.add_theme_font_size_override("font_size", 26)
	status.add_theme_color_override("font_color", Color("#8a93a6"))
	vb.add_child(status)

	var qm := QuadMesh.new()
	qm.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.albedo_texture = vp.get_texture()
	qm.material = mat
	quad.mesh = qm

	var cam: Node3D = ctx["camera"]
	var ct: Transform3D = cam.global_transform
	var fwd := -ct.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var pos := ct.origin + fwd * dist + Vector3(0, height, 0)
	quad.global_transform = Transform3D(Basis(), pos).looking_at(pos + fwd, Vector3.UP)

	_panels[id] = {"quad": quad, "vp": vp, "size": size, "px": Vector2(px), "status": status}
	return {"ok": true, "id": id, "pixels": [px.x, px.y]}


func _free_panel(id: String) -> void:
	var p: Dictionary = _panels[id]
	var q: Node = p["quad"]
	q.queue_free()
	_panels.erase(id)
	if _hover_id == id:
		_hover_id = ""
		_held = false


func _remove(r: Dictionary) -> Dictionary:
	var id := str(r.get("id", ""))
	if not _panels.has(id):
		return {"ok": false, "error": "no vrui panel called " + id}
	_free_panel(id)
	return {"ok": true}


func _show(r: Dictionary) -> Dictionary:
	var id := str(r.get("id", ""))
	if not _panels.has(id):
		return {"ok": false, "error": "no vrui panel called " + id}
	if not r.has("visible"):
		return {"ok": false, "error": "visible (true/false) is needed"}
	var p: Dictionary = _panels[id]
	var q: Node3D = p["quad"]
	q.visible = bool(r["visible"])
	return {"ok": true}


func _list(_r: Dictionary) -> Dictionary:
	var out := []
	for id in _panels:
		var p: Dictionary = _panels[id]
		var q: Node3D = p["quad"]
		var s: Vector2 = p["size"]
		out.append({"id": id, "visible": q.visible, "size": [s.x, s.y]})
	return {"ok": true, "panels": out}


func _on_press(id: String, action) -> void:
	if not (action is Dictionary) or action.is_empty():
		return
	var a: Dictionary = action.duplicate(true)
	if a.has("position") and a["position"] is String and a["position"] == "in_front":
		var cam: Node3D = ctx["camera"]
		var ct: Transform3D = cam.global_transform
		var f := -ct.basis.z
		f.y = 0.0
		if f.length() < 0.01:
			f = Vector3(0, 0, -1)
		var p := ct.origin + f.normalized()
		a["position"] = [p.x, p.y, p.z]
	var res = ctx["server"].run(a)
	if _panels.has(id) and res is Dictionary:
		var st: Label = _panels[id]["status"]
		if res.get("ok", false):
			st.text = "Done: " + str(a["cmd"])
		else:
			st.text = "Error: " + str(res.get("error", "?"))


func _push(id: String, ev: InputEvent) -> void:
	var p: Dictionary = _panels[id]
	var vp: SubViewport = p["vp"]
	vp.push_input(ev)


func _motion(id: String, pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = pos - _last_px
	if _held:
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	_push(id, ev)


func _process(_d: float) -> void:
	var hand = ctx.get("right")
	if hand == null or _panels.is_empty():
		_cursor.visible = false
		return
	var t: Transform3D = hand.global_transform
	var o := t.origin
	var dir := (-t.basis.z).normalized()

	var trig := false
	if hand.has_method("get_float"):
		var v: float = hand.get_float("trigger")
		trig = v > (0.4 if (_held or _block) else 0.6)

	var best := ""
	var best_s := 1e9
	var best_px := Vector2.ZERO
	var best_hit := Vector3.ZERO
	for id in _panels:
		var p: Dictionary = _panels[id]
		var q: Node3D = p["quad"]
		if not q.visible:
			continue
		var gt: Transform3D = q.global_transform
		var inv := gt.affine_inverse()
		var lo := inv * o
		var ld := inv.basis * dir
		if absf(ld.z) < 0.0001:
			continue
		var s := -lo.z / ld.z
		if s <= 0.0 or s > 5.0 or s >= best_s:
			continue
		var hit := lo + ld * s
		var sz: Vector2 = p["size"]
		if absf(hit.x) > sz.x * 0.5 or absf(hit.y) > sz.y * 0.5:
			continue
		var pxs: Vector2 = p["px"]
		best = id
		best_s = s
		best_px = Vector2((hit.x / sz.x + 0.5) * pxs.x, (0.5 - hit.y / sz.y) * pxs.y)
		best_hit = gt * Vector3(hit.x, hit.y, 0.003)

	var target := best
	var pos := best_px
	if target == "":
		if _held and _panels.has(_hover_id):
			target = _hover_id
			pos = _last_px
		else:
			if _hover_id != "" and _panels.has(_hover_id):
				_motion(_hover_id, Vector2(-1000, -1000))
			_hover_id = ""
			_cursor.visible = false
			_held = false
			_block = trig
			return
	if _block:
		if trig:
			_cursor.visible = best != ""
			if best != "":
				_cursor.global_position = best_hit
			return
		_block = false

	if target != _hover_id and _hover_id != "" and _panels.has(_hover_id):
		_motion(_hover_id, Vector2(-1000, -1000))
	_hover_id = target
	_cursor.visible = best != ""
	if best != "":
		_cursor.global_position = best_hit
	if pos != _last_px:
		_motion(target, pos)
		_last_px = pos
	if trig != _held:
		_held = trig
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = trig
		ev.position = pos
		ev.global_position = pos
		_push(target, ev)
