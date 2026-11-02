extends SlopitectModule
# Headless checks for apps' pieces in the world's object list (lib.gd's
# add_app_things; textures.gd and inspect.gd use them). This module plays the
# app. Run: tests/run.sh lib save projects tools inspect textures zz_app_things
# With beatsaber (and its needs) loaded too, it checks the Rhythm stage's
# pieces: lib vrui save projects tools inspect textures beatsaber zz_app_things
# (add gamecube before zz_app_things for its TV)
var _fails := 0
var _passes := 0
var _entered := []
var _exited := []
var _arena: Node3D


func setup() -> String:
	# Tagged before lib greets this module: lib's own look finds them.
	_build("early")
	_go.call_deferred()
	return ""


func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if ok: _passes += 1
	else: _fails += 1


func _r(q: Dictionary) -> Dictionary:
	var r = ctx["server"].run(q)
	if r.get("wait") is SlopitectPending:
		var p: SlopitectPending = r["wait"]
		r = p.result if p.finished else await p.done
	return r


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _finish() -> void:
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


# A small "app": a box, a MultiMesh and a group with a label, all tagged, and
# an untagged effect that must stay out of the list.
func _build(node_name: String) -> void:
	_arena = Node3D.new()
	_arena.name = node_name
	add_child(_arena)
	_arena.position = Vector3(0, 0, -3)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	var own := StandardMaterial3D.new()
	own.albedo_color = Color(0.2, 0.6, 0.2)
	box.material_override = own
	box.position = Vector3(0, 1, 0)
	box.set_meta("slopitect_app_thing", "zzapp_box")
	_arena.add_child(box)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 3
	for i in 3:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(i, 0, 0)))
	var many := MultiMeshInstance3D.new()
	many.multimesh = mm
	many.set_meta("slopitect_app_thing", "zzapp_walls")
	_arena.add_child(many)
	var group := Node3D.new()
	group.set_meta("slopitect_app_thing", "zzapp_sign")
	var word := Label3D.new()
	word.text = "HI"
	group.add_child(word)
	_arena.add_child(group)
	var fx := MeshInstance3D.new()
	fx.mesh = SphereMesh.new()
	fx.name = "zzapp_fx"
	_arena.add_child(fx)


func _names(list: Array) -> Array:
	return list.map(func(n): return String(n.name))


func _go() -> void:
	await _wait(1.0)
	var lib = ctx["modules"].module("lib")
	var textures = ctx["modules"].module("textures")
	lib.thing_entered.connect(func(n): _entered.append(String(n.name)))
	lib.thing_exited.connect(func(n): _exited.append(n))
	var names := _names(lib.things())
	_check("pieces tagged before lib greeted the app are listed", names.has("zzapp_box") and names.has("zzapp_walls") and names.has("zzapp_sign"), names)
	_check("untagged pieces stay out", not names.has("zzapp_fx"))
	var box: Node3D = lib.thing("zzapp_box")
	_check("thing() and world_node() find a piece", box != null and lib.world_node("zzapp_walls") is MultiMeshInstance3D)
	_check("app_of names the app", lib.app_of(box) == String(name) and lib.app_of(null) == "", lib.app_of(box))
	_check("lib_status counts them", (await _r({"cmd": "lib_status"})).get("app_things", {}).get(String(name), 0) == 3)
	# inspect
	var listed: Array = (await _r({"cmd": "inspect_list"})).get("things", [])
	var kinds := {}
	for t in listed:
		kinds[t["name"]] = t["kind"]
	_check("inspect_list shows pieces with the app as kind", kinds.get("zzapp_box") == String(name), kinds)
	var del := await _r({"cmd": "inspect_delete", "name": "zzapp_box"})
	_check("inspect_delete refuses a piece (the app builds it)", not del.get("ok", true) and lib.thing("zzapp_box") != null, del)
	var hid := await _r({"cmd": "inspect_set", "name": "zzapp_sign", "hidden": true})
	_check("inspect can hide a piece", hid.get("ok", false) and not lib.thing("zzapp_sign").visible, hid)
	await _r({"cmd": "inspect_set", "name": "zzapp_sign", "hidden": false})
	# save never writes them
	await _r({"cmd": "spawn", "shape": "box", "name": "zz_world_box", "position": [1, 1, -2]})
	_check("a world shape has no app", lib.app_of(lib.thing("zz_world_box")) == "")
	await _r({"cmd": "save_now"})
	var saved = lib.read_json(lib.world_file("world.json"))
	var saved_text := JSON.stringify(saved)
	_check("save keeps world shapes but not pieces", "zz_world_box" in saved_text and not "zzapp_" in saved_text, saved_text.left(300))
	# textures on a mesh piece and a MultiMesh piece
	var own: Material = box.material_override
	var put := await _r({"cmd": "textures_apply", "names": ["zzapp_box", "zzapp_walls"], "texture": "noise"})
	_check("textures_apply on a piece and a MultiMesh piece", put.get("ok", false)
		and (box.material_override as StandardMaterial3D).albedo_texture != null
		and (lib.thing("zzapp_walls").material_override as StandardMaterial3D).albedo_texture != null, put)
	_check("tinted by the app's own colour", (box.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Color(0.2, 0.6, 0.2)))
	var label_put := await _r({"cmd": "textures_apply", "names": ["zzapp_sign"], "texture": "noise"})
	_check("a group/text piece doesn't take a texture", not label_put.get("ok", true), label_put)
	# The app tears down and builds again (a map change): gone, then back
	# with the same names and its texture straight away.
	_entered.clear()
	_exited.clear()
	_arena.free()
	await get_tree().process_frame
	await get_tree().process_frame
	names = _names(lib.things())
	_check("freed pieces leave the list", not names.has("zzapp_box") and _exited.has("zzapp_box") and _exited.has("zzapp_walls"), [names, _exited])
	_check("lib dropped its pointers", lib.thing("zzapp_box") == null and (await _r({"cmd": "lib_status"})).get("app_things", {}).is_empty())
	_build("again")
	var added: PackedStringArray = lib.add_app_things(self)
	await get_tree().process_frame
	await get_tree().process_frame
	box = lib.thing("zzapp_box")
	_check("rebuilt pieces come back with the same names", added.has("zzapp_box") and box != null and _entered.has("zzapp_box"), [added, _entered])
	_check("their texture comes back at once", box.material_override is StandardMaterial3D and (box.material_override as StandardMaterial3D).albedo_texture != null)
	_check("adding twice adds nothing", lib.add_app_things(self).is_empty())
	own = null
	var mine_before: Material = box.material_override
	await _r({"cmd": "textures_clear", "names": ["zzapp_box", "zzapp_walls"]})
	_check("clearing gives the piece the app's own material back", box.material_override != mine_before
		and (box.material_override as StandardMaterial3D).albedo_texture == null
		and (box.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Color(0.2, 0.6, 0.2)))
	_check("MultiMesh piece back to no override", lib.thing("zzapp_walls").material_override == null)
	_check("textures idle again", not textures.is_processing())
	# A world thing already has the name: the piece gets a number.
	await _r({"cmd": "spawn", "shape": "box", "name": "zzapp_crate"})
	var extra := MeshInstance3D.new()
	extra.mesh = BoxMesh.new()
	extra.set_meta("slopitect_app_thing", "zzapp_crate")
	_arena.add_child(extra)
	var clash: PackedStringArray = lib.add_app_things(self)
	_check("a taken name gets a number", clash.size() == 1 and clash[0] == "zzapp_crate_2" and lib.thing("zzapp_crate") is MeshInstance3D and lib.thing("zzapp_crate") != extra, clash)
	var objects: Array = (await _r({"cmd": "list"})).get("objects", [])
	_check("the APK's list (save's) still has only world shapes", not _names_of(objects).any(func(n): return n.begins_with("zzapp_") and n != "zzapp_crate"), _names_of(objects))
	# Rhythm Sabers' stage, when it's loaded.
	var rhythm = ctx["modules"].module("beatsaber")
	if rhythm:
		rhythm.call("_stage_on")
		await get_tree().process_frame
		names = _names(lib.things())
		_check("Rhythm stage pieces listed", ["beatsaber_ground", "beatsaber_runway", "beatsaber_pad", "beatsaber_edge_left", "beatsaber_edge_right", "beatsaber_frames", "beatsaber_stars", "beatsaber_sign"].all(func(n): return names.has(n)), names)
		var tex := await _r({"cmd": "textures_apply", "names": ["beatsaber_runway", "beatsaber_frames"], "texture": "noise"})
		_check("Rhythm stage pieces take textures", tex.get("ok", false), tex)
		rhythm.call("_stage_off")
		await get_tree().process_frame
		await get_tree().process_frame
		_check("Rhythm stage pieces leave with the stage", not _names(lib.things()).has("beatsaber_runway"))
	# GameCube's TV, when it's loaded: made with a stand-in console (the real
	# one needs the extension and the owner's own dump).
	var cube = ctx["modules"].module("gamecube")
	if cube:
		var fake := GDScript.new()
		fake.source_code = "extends RefCounted\nfunc width(): return 64\nfunc height(): return 48\n"
		fake.reload()
		cube.set("_console", fake.new())
		cube.call("_make_tv")
		await get_tree().process_frame
		names = _names(lib.things())
		_check("GameCube TV and case listed, the screen not", names.has("gamecube_tv") and names.has("gamecube_tv_case") and not names.has("screen"), names)
		var tv_tex := await _r({"cmd": "textures_apply", "names": ["gamecube_tv_case"], "texture": "noise"})
		_check("GameCube case takes a texture", tv_tex.get("ok", false), tv_tex)
		cube.set("_console", null)
		var tv = cube.get("_tv")
		cube.set("_tv", null)
		tv.free()
		await get_tree().process_frame
		_check("GameCube TV leaves the list when it goes", lib.thing("gamecube_tv") == null)
	_finish()


func _names_of(objects: Array) -> Array:
	return objects.map(func(o): return String(o.get("name", "")))
