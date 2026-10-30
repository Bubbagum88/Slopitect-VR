extends SlopitectModule
# Headless checks for undo and groups. Run: tests/run.sh lib controls vrui tools inspect shapes physics grab multi doors textures prefabs zz_undo
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


func _groups() -> Dictionary:
	return (await _r({"cmd": "multi_status"})).groups


func _go() -> void:
	await _wait(3.5)
	var shapes = ctx["modules"].module("shapes")
	var multi = ctx["modules"].module("multi")
	var grab = ctx["modules"].module("grab")
	_check("modules loaded", shapes != null and multi != null and grab != null and ctx["modules"].module("prefabs") != null)

	# --- Undo of deleting a made shape brings back the real shape ---
	var r = await _r({"cmd": "shapes_make", "preset": "star", "size": 0.3, "depth": 0.1, "name": "starA", "position": [2, 1, 0], "color": "#ff0000"})
	_check("make star", r.get("ok", false), r)
	var recipe: Dictionary = shapes.recipe("starA")
	var verts: int = _node("starA").mesh.get_faces().size()
	r = await _r({"cmd": "inspect_delete", "name": "starA"})
	_check("delete star", r.get("ok", false) and _node("starA") == null, r)
	r = await _r({"cmd": "tools_undo"})
	await _wait(0.1)
	_check("undo puts the star back", r.get("ok", false) and _node("starA") != null, r)
	_check("as a made star, same recipe", shapes.is_made("starA") and shapes.recipe("starA") == recipe, shapes.recipe("starA"))
	_check("same mesh", _node("starA") != null and _node("starA").mesh.get_faces().size() == verts)
	_check("same place", _node("starA") != null and _node("starA").global_position.is_equal_approx(Vector3(2, 1, 0)))
	r = await _r({"cmd": "tools_redo"})
	_check("redo deletes it again", r.get("ok", false) and _node("starA") == null, r)
	await _r({"cmd": "tools_undo"})
	await _wait(0.7)  # past shapes' scan
	_check("still made after shapes' scan", shapes.is_made("starA"))

	# --- Group and ungroup undo ---
	for i in 3:
		await _r({"cmd": "spawn", "name": "b%d" % (i + 1), "shape": "box", "position": [i * 0.5, 1, -1], "scale": [0.2, 0.2, 0.2]})
	await _r({"cmd": "multi_select", "names": ["b1", "b2", "b3"], "mode": "set"})
	r = await _r({"cmd": "multi_group"})
	_check("group", r.get("ok", false) and r.members.size() == 3, r)
	await _r({"cmd": "tools_undo"})
	_check("undo group: no groups", (await _groups()).is_empty(), await _groups())
	await _r({"cmd": "tools_redo"})
	_check("redo group", (await _groups()).get("group1", []).size() == 3, await _groups())
	await _r({"cmd": "multi_ungroup"})
	_check("ungroup", (await _groups()).is_empty())
	await _r({"cmd": "tools_undo"})
	_check("undo ungroup", (await _groups()).get("group1", []).size() == 3, await _groups())

	# --- Multi delete is one undo, and members go back in their group ---
	await _r({"cmd": "multi_select", "names": ["b1", "b2", "b3"], "mode": "set"})
	r = await _r({"cmd": "multi_delete"})
	_check("multi delete", r.get("ok", false) and r.deleted.size() == 3, r)
	_check("deleted members leave the group", (await _groups()).is_empty(), await _groups())
	var st = await _r({"cmd": "tools_status"})
	_check("one undo entry for it", st.undo == "delete 3 things", st)
	await _r({"cmd": "tools_undo"})
	_check("one undo brings all 3 back", _node("b1") != null and _node("b2") != null and _node("b3") != null)
	var g: Dictionary = await _groups()
	_check("and back in their group", g.has("group1") and g["group1"].size() == 3, g)
	st = await _r({"cmd": "tools_status"})
	_check("redo has one entry", st.redo == 1, st)

	# --- Deleting one member, a new thing with its name doesn't join ---
	await _r({"cmd": "inspect_delete", "name": "b3"})
	g = await _groups()
	_check("one deleted member leaves", g.get("group1", []).size() == 2 and not "b3" in g["group1"], g)
	await _r({"cmd": "tools_undo"})
	g = await _groups()
	_check("undo: it's back in", g.get("group1", []).size() == 3 and "b3" in g.get("group1", []), g)
	await _r({"cmd": "inspect_delete", "name": "b3"})
	await _r({"cmd": "spawn", "name": "b3", "shape": "sphere", "position": [3, 1, 0]})
	g = await _groups()
	_check("a new b3 isn't in the group", not "b3" in g.get("group1", []), g)
	await _r({"cmd": "delete", "name": "b3"})
	await _r({"cmd": "spawn", "name": "b3", "shape": "box", "position": [1, 1, -1], "scale": [0.2, 0.2, 0.2]})
	await _r({"cmd": "multi_group", "names": ["b1", "b3"]})
	_check("regroup", (await _groups()).get("group1", []).size() == 3, await _groups())

	# --- Hide is one undo ---
	await _r({"cmd": "multi_select", "names": ["b1", "b2"], "mode": "set"})
	await _r({"cmd": "multi_set", "hidden": true})
	_check("hidden", not _node("b1").visible and not _node("b2").visible)
	st = await _r({"cmd": "tools_status"})
	_check("hide is an undo", st.undo == "hide 3 things" or st.undo == "hide 2 things", st)
	await _r({"cmd": "tools_undo"})
	_check("undo hide shows them", _node("b1").visible and _node("b2").visible)
	await _r({"cmd": "multi_select", "names": ["b1"], "mode": "set"})
	await _r({"cmd": "multi_set", "grabbable": false})
	await _r({"cmd": "tools_undo"})
	_check("undo grab off", not _node("b1").get_meta("slopitect_no_grab", false))

	# --- A held member leads its group even when physics moves the rest ---
	for n in ["b1", "b2", "b3"]:
		await _r({"cmd": "physics_set", "name": n, "mode": "dynamic"})
	await _wait(0.1)  # still falling when b1 is taken
	var before := {}
	for n in ["b1", "b2", "b3"]:
		before[n] = _node(n).global_transform
	var hand: Node3D = ctx["right"]
	hand.global_position = _node("b1").global_position
	_check("grab b1", grab.on_action("grab_right", true))
	var off2: Vector3 = _node("b2").global_position - _node("b1").global_position
	var off3: Vector3 = _node("b3").global_position - _node("b1").global_position
	for k in 30:
		hand.global_position += Vector3(0, 0.03, 0.01)
		await get_tree().physics_frame
	await get_tree().physics_frame
	var lifted: float = _node("b1").global_position.y - before["b1"].origin.y
	_check("b1 lifted", lifted > 0.7, lifted)
	var d2: Vector3 = _node("b2").global_position - _node("b1").global_position
	var d3: Vector3 = _node("b3").global_position - _node("b1").global_position
	_check("b2 keeps its place in the group", d2.distance_to(off2) < 0.05, [d2, off2])
	_check("b3 keeps its place in the group", d3.distance_to(off3) < 0.05, [d3, off3])
	grab.on_action("grab_right", false)
	await get_tree().physics_frame
	st = await _r({"cmd": "tools_status"})
	_check("one undo for the group's move", st.undo == "move b1's group", st)
	ctx["modules"].module("tools").quiet(func():
		for n in ["b1", "b2", "b3"]:
			ctx["server"].run({"cmd": "physics_set", "name": n, "mode": "off"}))
	st = await _r({"cmd": "tools_status"})
	_check("one undo for the group's move", st.undo == "move b1's group", st)
	await _r({"cmd": "tools_undo"})
	await get_tree().physics_frame
	await get_tree().physics_frame
	for n in ["b1", "b2", "b3"]:
		_check("undo puts %s back" % n, _node(n).global_position.distance_to(before[n].origin) < 0.01, [_node(n).global_position, before[n].origin])

	# --- One member moved alone: the rest still follow (as before) ---
	var p2: Vector3 = _node("b2").global_position
	_node("b1").global_position += Vector3(0, 0, 1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("group follows a lone move", _node("b2").global_position.distance_to(p2 + Vector3(0, 0, 1)) < 0.01, [_node("b2").global_position, p2])

	# --- Prefab place is one undo ---
	await _r({"cmd": "multi_select", "names": ["b1", "b2", "b3", "starA"], "mode": "set"})
	r = await _r({"cmd": "prefabs_save", "name": "testpf"})
	_check("save prefab", r.get("ok", false), r)
	r = await _r({"cmd": "prefabs_place", "name": "testpf", "position": [0, 0, 3]})
	_check("place prefab", r.get("ok", false) and r.placed == 4, r)
	var sfx: String = r.get("suffix", "")
	st = await _r({"cmd": "tools_status"})
	_check("one undo for the prefab", st.undo == "place prefab testpf", st)
	g = await _groups()
	_check("placed copy is grouped", g.size() == 2, g)
	await _r({"cmd": "tools_undo"})
	await _wait(0.1)
	_check("undo takes the copy away", _node("b1" + sfx) == null and _node("starA" + sfx) == null)
	_check("and its group", (await _groups()).size() == 1, await _groups())
	_check("originals stay", _node("b1") != null and _node("starA") != null)
	await _r({"cmd": "tools_redo"})
	await _wait(0.1)
	_check("redo places it again", _node("b1" + sfx) != null and _node("starA" + sfx) != null and shapes.is_made("starA" + sfx))
	_check("grouped again", (await _groups()).size() == 2, await _groups())
	st = await _r({"cmd": "tools_status"})
	_check("redo made no new entries", st.redo == 0 and st.undo == "place prefab testpf", st)

	# --- Batches ---
	var tools = ctx["modules"].module("tools")
	tools.undo_batch_begin("outer")
	tools.undo_batch_begin("inner")
	await _r({"cmd": "inspect_delete", "name": "b1" + sfx})
	tools.undo_batch_end()
	await _r({"cmd": "inspect_delete", "name": "b2" + sfx})
	tools.undo_batch_end()
	st = await _r({"cmd": "tools_status"})
	_check("nested batch is one entry with the outer label", st.undo == "outer", st)
	await _r({"cmd": "tools_undo"})
	_check("nested batch undo", _node("b1" + sfx) != null and _node("b2" + sfx) != null)

	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
