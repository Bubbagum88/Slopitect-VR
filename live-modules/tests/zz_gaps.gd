extends SlopitectModule
# Headless checks for undo across modules (FRESH=1 the first time, for the APK's objects.gd). Run:
# tests/run.sh lib controls vrui tools inspect shapes physics grab multi doors textures joints save projects prefabs zz_gaps
var _fails := 0
var _passes := 0


func setup() -> String:
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


func _node(n: String) -> Node3D:
	var w: Node3D = ctx["world"]
	return w.get_node_or_null(NodePath(n)) as Node3D


func _undo_label() -> String:
	return (await _r({"cmd": "tools_status"})).undo


# What every module keeps about p1, as one comparable string.
func _kept(n: String) -> Dictionary:
	var out := {}
	out["texture"] = (await _r({"cmd": "textures_status"})).textures.get(n)
	var phys = null
	for t in (await _r({"cmd": "physics_status"})).things:
		if t.name == n: phys = t.mode
	out["physics"] = phys
	var doors := []
	for id in (await _r({"cmd": "doors_status"})).doors:
		doors.append(id)
	out["doors"] = doors
	var joints := []
	for j in (await _r({"cmd": "joints_list"})).joints:
		if n in [j.a, j.b]: joints.append(j.id)
	out["joints"] = joints
	var group := ""
	var groups: Dictionary = (await _r({"cmd": "multi_status"})).groups
	for g in groups:
		if n in groups[g]: group = g
	out["group"] = group
	out["grabbable"] = not _node(n).get_meta("slopitect_no_grab", false) if _node(n) else null
	return out


func _go() -> void:
	await _wait(3.5)  # projects.gd moves the old saves/ into projects/start first; the modules follow within 2 s
	var tools = ctx["modules"].module("tools")
	_check("objects.gd has undo (new APK code)", ctx["modules"].module("objects") != null and ctx["modules"].module("objects").has_method("_undo"))

	# --- spawn, move, colour ---
	var r = await _r({"cmd": "spawn", "name": "s1", "shape": "box", "position": [0, 1, -1], "color": "#00ff00"})
	_check("spawn is an undo", await _undo_label() == "spawn s1")
	await _r({"cmd": "move", "name": "s1", "position": [1, 1, -1]})
	_check("move is an undo", await _undo_label() == "move s1")
	await _r({"cmd": "color", "name": "s1", "color": "#ff0000"})
	_check("colour is an undo", await _undo_label() == "colour s1")
	await _r({"cmd": "tools_undo"})
	_check("undo colour", (_node("s1") as MeshInstance3D).get_surface_override_material(0).albedo_color.is_equal_approx(Color("#00ff00")))
	await _r({"cmd": "tools_undo"})
	_check("undo move", _node("s1").position.is_equal_approx(Vector3(0, 1, -1)), _node("s1").position)
	await _r({"cmd": "tools_undo"})
	_check("undo spawn", _node("s1") == null)
	await _r({"cmd": "tools_redo"})
	_check("redo spawn", _node("s1") != null and _node("s1").position.is_equal_approx(Vector3(0, 1, -1)))
	await _r({"cmd": "tools_redo"})
	await _r({"cmd": "tools_redo"})
	_check("redo move and colour", _node("s1").position.is_equal_approx(Vector3(1, 1, -1)) and (_node("s1") as MeshInstance3D).get_surface_override_material(0).albedo_color.is_equal_approx(Color("#ff0000")))

	# --- each module's own changes ---
	await _r({"cmd": "spawn", "name": "p1", "shape": "box", "position": [0, 1, -2], "scale": [0.8, 1.8, 0.05]})
	await _r({"cmd": "spawn", "name": "p2", "shape": "box", "position": [1, 1, -2], "scale": [0.1, 2, 0.1]})
	await _r({"cmd": "textures_apply", "names": ["p1"], "texture": "noise"})
	_check("texture is an undo", await _undo_label() == "texture p1")
	await _r({"cmd": "tools_undo"})
	_check("undo texture", (await _kept("p1")).texture == null)
	await _r({"cmd": "tools_redo"})
	_check("redo texture", (await _kept("p1")).texture != null)
	await _r({"cmd": "textures_clear", "names": ["p1"]})
	await _r({"cmd": "tools_undo"})
	_check("undo untexture", (await _kept("p1")).texture != null)

	await _r({"cmd": "physics_set", "name": "p1", "mode": "static"})
	_check("physics is an undo", await _undo_label() == "physics static p1")
	await _r({"cmd": "tools_undo"})
	_check("undo physics", (await _kept("p1")).physics == null)
	await _r({"cmd": "tools_redo"})
	_check("redo physics", (await _kept("p1")).physics == "static")

	await _r({"cmd": "doors_add", "name": "d1", "parts": ["p1"], "hinge": [-0.4, -2]})
	_check("door is an undo", await _undo_label() == "door d1")
	await _r({"cmd": "tools_undo"})
	_check("undo door", (await _kept("p1")).doors.is_empty())
	await _r({"cmd": "tools_redo"})
	_check("redo door", (await _kept("p1")).doors == ["d1"])
	await _r({"cmd": "doors_remove", "name": "d1"})
	await _r({"cmd": "tools_undo"})
	_check("undo door remove", (await _kept("p1")).doors == ["d1"])

	await _r({"cmd": "inspect_set", "name": "p1", "grabbable": false})
	_check("inspect switch is an undo", await _undo_label() == "grab off p1")
	await _r({"cmd": "tools_undo"})
	_check("undo grab off", (await _kept("p1")).grabbable == true)
	await _r({"cmd": "tools_redo"})
	await _r({"cmd": "inspect_set", "name": "p2", "hidden": true})
	await _r({"cmd": "inspect_show_all"})
	_check("show all is an undo", await _undo_label() == "show 1 hidden")
	await _r({"cmd": "tools_undo"})
	_check("undo show all hides it again", not _node("p2").visible)
	await _r({"cmd": "tools_undo"})
	_check("undo hide", _node("p2").visible)

	r = await _r({"cmd": "joints_add", "a": "p2", "b": "s1", "type": "slider", "axis": [1, 0, 0], "lower": -1, "upper": 1})
	_check("joint", r.get("ok", false), r)
	var jid: String = r.joint.id
	var s1_at := _node("s1").global_position
	await _r({"cmd": "joints_set", "id": jid, "value": 0.5})
	_check("joint set is an undo", await _undo_label() == "set joint " + jid)
	await _wait(0.1)
	await _r({"cmd": "tools_undo"})
	await _wait(0.1)
	_check("undo joint set moves it back", _node("s1").global_position.distance_to(s1_at) < 0.01, [_node("s1").global_position, s1_at])

	await _r({"cmd": "multi_group", "names": ["p1", "p2"]})

	# --- deleting with the plain delete command takes everything with it, undo brings it all back ---
	var p1_before := await _kept("p1")
	var p2_before := await _kept("p2")
	_check("p1 has all of it", p1_before.texture != null and p1_before.physics == "static" and p1_before.doors == ["d1"] and p1_before.group != "" and p1_before.grabbable == false, p1_before)
	await _r({"cmd": "delete", "name": "p2"})
	_check("plain delete is an undo", await _undo_label() == "delete p2")
	_check("p2's joint went with it", (await _r({"cmd": "joints_list"})).joints.is_empty())
	await _r({"cmd": "delete", "name": "p1"})
	await _r({"cmd": "spawn", "name": "p1", "shape": "sphere", "position": [5, 1, 5]})
	var fresh := await _kept("p1")
	_check("a new p1 gets nothing of the old one's", fresh.texture == null and fresh.physics == null and fresh.doors.is_empty() and fresh.group == "" and fresh.grabbable == true, fresh)
	await _r({"cmd": "tools_undo"})  # the new p1
	await _r({"cmd": "tools_undo"})  # p1's delete
	await _wait(0.1)
	var back := await _kept("p1")
	var p1_no_group := p1_before.duplicate()
	p1_no_group["group"] = ""  # its group went when p2 (the other member) did; it comes back with p2
	_check("undo brings p1 back with all of it", JSON.stringify(back) == JSON.stringify(p1_no_group), [back, p1_before])
	_check("as a box again", _node("p1") is MeshInstance3D and (_node("p1") as MeshInstance3D).mesh is BoxMesh)
	await _r({"cmd": "tools_undo"})  # p2's delete
	await _wait(0.1)
	back = await _kept("p2")
	_check("undo brings p2 back with its joint and group", JSON.stringify(back) == JSON.stringify(p2_before) and back.joints == [jid], [back, p2_before])
	_check("and p1 is back in that group", (await _kept("p1")).group == p1_before.group)
	await _r({"cmd": "tools_redo"})
	_check("redo deletes p2 again", _node("p2") == null and (await _r({"cmd": "joints_list"})).joints.is_empty())
	await _r({"cmd": "tools_undo"})
	await _wait(0.1)

	# --- a made shape deleted with the plain delete comes back made ---
	r = await _r({"cmd": "shapes_make", "preset": "star", "size": 0.3, "depth": 0.1, "name": "st1", "position": [2, 1, 0]})
	await _r({"cmd": "textures_apply", "names": ["st1"], "texture": "noise"})
	await _r({"cmd": "delete", "name": "st1"})
	await _r({"cmd": "tools_undo"})
	await _wait(0.1)
	_check("made shape back as made, with its texture", ctx["modules"].module("shapes").is_made("st1") and (await _kept("st1")).texture != null)

	# --- checkpoints keep groups, textures, doors and physics ---
	r = await _r({"cmd": "save_checkpoint", "label": "all"})
	_check("checkpoint", r.get("ok", false), r)
	var cp: String = r.checkpoint
	await _r({"cmd": "multi_ungroup", "group": p1_before.group})
	await _r({"cmd": "textures_clear", "names": ["p1"]})
	await _r({"cmd": "doors_remove", "name": "d1"})
	await _r({"cmd": "physics_set", "name": "p1", "mode": "off"})
	r = await _r({"cmd": "save_restore", "checkpoint": cp})
	await _wait(0.2)
	back = await _kept("p1")
	_check("restore brings back group, texture, door, physics", back.group == p1_before.group and back.texture != null and back.doors == ["d1"] and back.physics == "static", back)
	_check("restore is one undo", await _undo_label() == "go back to checkpoint " + cp)
	await _r({"cmd": "tools_undo"})
	await _wait(0.2)
	back = await _kept("p1")
	_check("undo the restore: as it was before", back.group == "" and back.texture == null and back.doors.is_empty() and back.physics == "off", back)

	# --- deleting a checkpoint is an undo ---
	var path: String = ctx["modules"].module("save").folder() + "/checkpoints/%s-checkpoint.json" % cp
	await _r({"cmd": "save_delete", "checkpoint": cp})
	_check("checkpoint deleted", not FileAccess.file_exists(path))
	await _r({"cmd": "tools_undo"})
	_check("undo brings the checkpoint back", FileAccess.file_exists(path))

	# --- another project empties the list ---
	await _r({"cmd": "multi_group", "names": ["p1", "p2"], "group": "keep"})
	await _r({"cmd": "textures_apply", "names": ["p2"], "texture": "noise"})
	_check("list not empty before", await _undo_label() != "")
	r = await _r({"cmd": "projects_new", "name": "undo_test", "open": true})
	_check("new project", r.get("ok", false), r)
	await _wait(0.8)
	var st = await _r({"cmd": "tools_status"})
	_check("another project: nothing to undo", st.undo == "" and st.redo == 0, st)
	_check("the new world is empty", _node("p1") == null)
	r = await _r({"cmd": "projects_open", "name": "start"})
	await _wait(2.5)
	_check("back in start: p1 is there", _node("p1") != null, r)
	var groups: Dictionary = (await _r({"cmd": "multi_status"})).groups
	_check("start's group survived the switch", groups.get("keep", []).size() == 2, groups)
	_check("start's texture survived the switch", (await _kept("p2")).texture != null)

	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
