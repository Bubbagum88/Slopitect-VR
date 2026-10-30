extends SlopitectModule
# Headless checks for library.gd. Run: tests/run.sh controls vrui pause net=net_stub assets textures prefabs inspect lib library zz_library
var _fails := 0
var _pic := 0
func setup() -> String:
	_go.call_deferred()
	return ""
func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if not ok: _fails += 1
func _r(q: Dictionary) -> Dictionary:
	var r = ctx["server"].run(q)
	if r.get("wait") is SlopitectPending:
		var p: SlopitectPending = r["wait"]
		r = p.result if p.finished else await p.done
	return r
func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func _panel() -> Dictionary:
	return (await _r({"cmd": "ui_get", "id_panel": "library"})).get("panel", {})
func _find(elements: Array, id: String) -> Dictionary:
	for e in elements:
		if e["id"] == id: return e
		var f := _find(e.get("children", []), id)
		if not f.is_empty(): return f
	return {}
func _el(id: String) -> Dictionary:
	return _find((await _panel()).get("elements", []), id)
func _shot(tag: String) -> void:
	if OS.get_environment("PICTURE") == "": return
	(ctx["camera"] as Node3D).rotation_degrees.x = -28
	await _frames(8)
	var look = await _r({"cmd": "view_look", "image": false})
	_pic += 1
	var dst := OS.get_environment("SHOTS") + "/%d-%s.jpg" % [_pic, tag]
	DirAccess.copy_absolute(look.get("saved", ""), dst)
	print("SHOT ", dst)
func _go() -> void:
	await get_tree().create_timer(1.5).timeout
	var home := OS.get_user_data_dir() + "/files_home"
	var ui = ctx["modules"].module("vrui")
	var net = ctx["modules"].module("net")
	_check("library loaded", ctx["modules"].module("library") != null)
	_check("menu tile", ui.get("_apps").any(func(a): return a["id"] == "library"), ui.get("_apps"))
	await get_tree().create_timer(2.5).timeout
	var hand = await _r({"cmd": "ui_get", "id_panel": "hand_menu"})
	var hand_ids := JSON.stringify(hand.get("panel", {}).get("elements", []))
	_check("hand menu has Textures, Assets, Prefabs", hand_ids.contains("m_library_t") and hand_ids.contains("m_library_a") and hand_ids.contains("m_library_p"), hand_ids.left(300))

	# Textures, before the cdn host is allowed
	var r = await _r({"cmd": "library_do", "act": "toggle", "tab": "Textures"})
	_check("opens on Textures", r.ok and (await _panel()).visible and (await _panel()).page == "Textures", r)
	await _frames(20)
	var grid = await _el("t_grid")
	_check("12 texture tiles", grid.get("children", []).size() == 12, grid)
	var first: Dictionary = grid.children[0] if grid.has("children") else {}
	_check("tile has image path and pick action", str(first.get("image", "")).ends_with("t_wood_00.png") and first.get("action", {}).get("act") == "pick", first)
	var st = await _r({"cmd": "library_status"})
	_check("asks for cdn host", "cdn.polyhaven.com" in st.status, st.status)
	_check("pages", st.tabs.Textures.pages == 3, st.tabs.Textures)

	net.allow_cdn = true
	await _r({"cmd": "library_do", "act": "refresh"})
	await _frames(60)
	_check("thumbnails fetched", FileAccess.file_exists(home + "/library/thumbs/t_wood_00.png") and FileAccess.file_exists(home + "/library/thumbs/t_metal_08.png"))
	var tex = ui.call("_image", home + "/library/thumbs/t_wood_00.png")
	_check("vrui loads the picture, shrunk", tex != null and tex.get_width() <= 160, tex)
	var view: Dictionary = ui.get("_views")["library"]
	var tile_control: Control = view["controls"]["t_i0"]
	var pic = ui.call("_picture_of", tile_control)
	_check("tile shows the picture", pic != null and pic.texture != null, pic)
	await _shot("textures")

	r = await _r({"cmd": "library_do", "act": "page", "tab": "Textures", "page": "next"})
	_check("next page", r.ok and (await _r({"cmd": "library_status"})).tabs.Textures.page == 2, r)
	r = await _r({"cmd": "ui_press", "id_panel": "library", "id_element": "t_cat"})
	st = await _r({"cmd": "library_status"})
	_check("category button cycles", st.tabs.Textures.category != "" and st.tabs.Textures.page == 1 and st.tabs.Textures.items.size() == 6, st.tabs.Textures)

	# picking a texture
	r = await _r({"cmd": "library_do", "act": "pick", "tab": "Textures", "id": "wood_00"})
	_check("pick with nothing selected says so", not r.ok and "Inspect" in r.error, r)
	await _r({"cmd": "spawn", "shape": "box", "name": "crate", "position": [0, 0.5, -1.5]})
	r = await _r({"cmd": "inspect_select", "name": "crate"})
	_check("inspect select", r.get("ok", false), r)
	r = await _r({"cmd": "library_do", "act": "pick", "tab": "Textures", "id": "wood_00"})
	_check("texture download starts", r.ok and r.get("downloading") == "wood_00", r)
	await _frames(30)
	var ts = await _r({"cmd": "textures_status"})
	_check("texture on the crate", ts.textures.get("crate", {}).get("texture") == "polyhaven/textures/wood_00_1k.jpg", ts)
	var crate: MeshInstance3D = ctx["world"].get_node("crate")
	_check("crate's material has the texture", crate.material_override is StandardMaterial3D and crate.material_override.albedo_texture != null)
	r = await _r({"cmd": "library_do", "act": "pick", "tab": "Textures", "id": "wood_00"})
	_check("second pick uses the file", r.get("ok", false) and not r.has("downloading"), r)

	# Assets: a model already on the headset
	var scene := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	scene.add_child(mesh)
	mesh.owner = scene
	DirAccess.make_dir_recursive_absolute(home + "/assets/polyhaven/furniture_00/1k")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(scene, state)
	doc.write_to_filesystem(state, home + "/assets/polyhaven/furniture_00/1k/furniture_00.gltf")
	r = await _r({"cmd": "library_do", "act": "toggle", "tab": "Assets"})
	_check("toggle to Assets switches tab", r.ok and (await _panel()).page == "Assets" and (await _panel()).visible, r)
	await _frames(40)
	var agrid = await _el("a_grid")
	_check("12 model tiles, lightest first", agrid.get("children", []).size() == 12 and agrid.children[0].label == "Furniture 0", agrid.get("children", []).slice(0, 1))
	_check("downloaded model is marked", agrid.children[0].get("color") == "ok", agrid.children[0])
	await _shot("assets")
	r = await _r({"cmd": "ui_press", "id_panel": "library", "id_element": "a_i0"})
	var placed = await _r({"cmd": "assets_placed"})
	_check("model placed in front", placed.placed.size() == 1 and placed.placed[0].id == "furniture_00", placed)

	# Prefabs
	await _r({"cmd": "spawn", "shape": "box", "name": "hut_base", "position": [3, 0.5, 0], "scale": [2, 1, 2], "color": "#996633"})
	await _r({"cmd": "spawn", "shape": "cylinder", "name": "hut_roof", "position": [3, 1.3, 0], "scale": [2.4, 0.6, 2.4], "color": "#aa2222"})
	await _r({"cmd": "spawn", "shape": "sphere", "name": "hut_ball", "position": [3.8, 1.9, 0], "scale": [0.4, 0.4, 0.4], "color": "#ffdd00"})
	r = await _r({"cmd": "prefabs_save", "name": "hut", "prefixes": ["hut_"]})
	_check("prefab saved", r.get("ok", false), r)
	r = await _r({"cmd": "library_do", "act": "toggle", "tab": "Prefabs"})
	await _frames(30)
	var pgrid = await _el("p_grid")
	_check("prefab tile", pgrid.get("children", []).size() == 1 and pgrid.children[0].label == "hut", pgrid)
	if OS.get_environment("PICTURE") != "":
		_check("prefab picture drawn", FileAccess.file_exists(home + "/library/thumbs/p_hut.png"))
	await _shot("prefabs")
	r = await _r({"cmd": "ui_press", "id_panel": "library", "id_element": "p_i0"})
	_check("prefab placed", r.get("ok", false) and ctx["world"].has_node("hut_base_2"), r)

	r = await _r({"cmd": "library_do", "act": "toggle", "tab": "Prefabs"})
	_check("same hand button closes", r.ok and not (await _panel()).visible, r)
	r = await _r({"cmd": "ui_element_add", "id_panel": "library", "element": {"type": "button", "id": "bad", "label": "x", "image": "/etc/passwd.png", "action": {"cmd": "list"}}})
	_check("image outside the Slopitect folder refused", not r.ok, r)
	print("RESULT %s, %d failed" % ["done", _fails])
	get_tree().quit()
