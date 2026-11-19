extends SlopitectModule
# Headless checks for stackwild.gd (the Stackwild block game).
# Run: tests/run.sh lib controls vrui save projects audio stackwild zz_stackwild
# Makes a small world from a fixed seed, checks the land and its meshes,
# the greedy mesher, walking (walls, steps, falling, jumping), digging and
# placing with real button presses (Build and Gather), the Blocks window,
# the agent's block commands, saving and opening again, leaving and
# unloading. PICTURE=1 SHOTS=folder saves pictures.
var _fails := 0
var _passes := 0
var _pic := 0
var _g


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


func _run(q: Dictionary) -> Dictionary:
	return ctx["server"].run(q)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame


func _button(hand: String, button: String, down: bool) -> void:
	var c := ctx[hand] as XRController3D
	if down: c.button_pressed.emit(button)
	else: c.button_released.emit(button)


func _press(hand: String, button: String) -> void:
	_button(hand, button, true)
	await _frames(1)
	_button(hand, button, false)
	await _frames(1)


func _land() -> Node3D:
	return _g._land


# Land space <-> the scene.
func _g2l(p: Vector3) -> Vector3:
	return _land().to_local(p)


func _l2g(p: Vector3) -> Vector3:
	return _land().to_global(p)


func _head() -> Vector3:
	return _g2l((ctx["camera"] as Node3D).global_position)


# Puts your head over land spot (x, z), feet where the land says.
func _stand(x: float, z: float) -> void:
	var origin := (ctx["camera"] as Node3D).get_parent() as Node3D
	var h := _head()
	origin.global_position += Vector3(x - h.x, 0, z - h.z)
	_g._last_xz = Vector2.INF


# The right controller at land spot `from`, pointing at land spot `at`.
func _aim(from: Vector3, at: Vector3) -> void:
	var f := _l2g(from)
	var a := _l2g(at)
	(ctx["right"] as Node3D).global_transform = Transform3D(Basis.looking_at(a - f, Vector3.UP), f)


func _shot(tag: String, from: Vector3, at: Vector3) -> void:
	if OS.get_environment("PICTURE") == "": return
	var f := _l2g(from)
	var a := _l2g(at)
	await _wait(0.2)
	var look = await _r({"cmd": "view_look", "position": [f.x, f.y, f.z], "look_at": [a.x, a.y, a.z], "image": false, "width": 960})
	_pic += 1
	var dst := OS.get_environment("SHOTS") + "/%d-%s.jpg" % [_pic, tag]
	DirAccess.copy_absolute(look.get("saved", ""), dst)
	print("SHOT ", dst)


func _shot_panel(tag: String, id_panel: String) -> void:
	if OS.get_environment("PICTURE") == "": return
	var ui: Node = ctx["modules"].module("vrui")
	var holder: Node3D = ui.find_child("Panel_" + id_panel, true, false) if ui else null
	if holder == null:
		return
	await _wait(0.3)
	var at := holder.global_position
	var f := at + holder.global_transform.basis.z * 0.9
	var look = await _r({"cmd": "view_look", "position": [f.x, f.y, f.z], "look_at": [at.x, at.y, at.z], "image": false, "width": 960})
	_pic += 1
	var dst := OS.get_environment("SHOTS") + "/%d-%s.jpg" % [_pic, tag]
	DirAccess.copy_absolute(look.get("saved", ""), dst)
	print("SHOT ", dst)


func _built() -> bool:
	return _g._ready_now and _g._queue.is_empty() and _g._urgent.is_empty() and _g._busy.is_empty()


func _wait_built(limit := 1800) -> int:
	var n := 0
	while not _built() and n < limit:
		await _frames(1)
		n += 1
	await _frames(2)
	return n


func _quads(out: Dictionary) -> int:
	return (out.get("verts", PackedVector3Array()) as PackedVector3Array).size() / 4


func _pad_with(cells: Dictionary) -> PackedByteArray:
	var P := 18
	var pad := PackedByteArray()
	pad.resize(P * P * P)
	for c in cells:
		pad[((c.y + 1) * P + (c.z + 1)) * P + (c.x + 1)] = cells[c]
	return pad


func _go() -> void:
	Engine.max_fps = 60
	await _frames(5)
	_g = ctx["modules"].module("stackwild")
	_check("loaded and idle", _g != null and not _g.is_processing() and _g._land == null)
	_check("Menu tile and hand menu", _g.menu_info().get("label") == "Stackwild" and _g.hand_info().get("label") == "Stackwild")
	var long_labels: Array = _g.settings_info()["settings"].filter(func(s): return s.get("label", "").length() > 40)
	_check("Settings labels 40 characters or less", long_labels.is_empty(), long_labels)
	_check("no game: actions pass through", not _g.on_action("point", true) and not _g.on_action("grab_right", true))
	_check("no texture or sounds made at load (start-up speed)", _g._mat == null and _g._sounds.is_empty())

	# The greedy mesher on its own.
	var one: Dictionary = _g.mesh_pad(_pad_with({Vector3i(3, 3, 3): 3}))
	_check("one block: 6 quads", _quads(one) == 6, _quads(one))
	var row := {}
	for x in 16:
		row[Vector3i(x, 0, 5)] = 3
	_check("a row of 16 like blocks: still 6 quads", _quads(_g.mesh_pad(_pad_with(row))) == 6, _quads(_g.mesh_pad(_pad_with(row))))
	var slab := {}
	for x in 16:
		for z in 16:
			slab[Vector3i(x, 2, z)] = 1
	_check("a 16 x 16 slab: 6 quads", _quads(_g.mesh_pad(_pad_with(slab))) == 6)
	_check("two different blocks side by side: 10 quads", _quads(_g.mesh_pad(_pad_with({Vector3i(1, 1, 1): 3, Vector3i(2, 1, 1): 9}))) == 10)
	var hidden := _pad_with({Vector3i(0, 15, 0): 3})
	hidden[(17 * 18 + 1) * 18 + 1] = 3  # the section above has a block on top of it
	_check("a covered face isn't drawn", _quads(_g.mesh_pad(hidden)) == 5)
	var empty: Dictionary = _g.mesh_pad(_pad_with({}))
	_check("nothing: no mesh", empty.is_empty())

	# The same seed makes the same land.
	var a := {"kind": "gen", "cx": 1, "cz": 2, "seed": 777, "size": 64, "out": PackedByteArray()}
	var b := a.duplicate()
	_g._gen_job(a)
	_g._gen_job(b)
	_check("a seed always makes the same land", a["out"] == b["out"] and (a["out"] as PackedByteArray).size() == 16384)
	_check("the bottom is deepstone", (a["out"] as PackedByteArray)[0] == 21)

	# A new world: its own world, the sky, the land.
	var floor_node: Node3D = ctx["world"].get_parent().get_node_or_null("Floor")
	var sky_env = ctx["world"].get_parent().get_node("WorldEnvironment").environment
	var t0 := Time.get_ticks_msec()
	var made = await _r({"cmd": "stackwild_new", "seed": 4242, "size": "small"})
	_check("stackwild_new", made.get("ok", false) and made.get("seed") == 4242 and made.get("size") == 64, made)
	_check("in the Stackwild world", _run({"cmd": "projects_current"}).get("name") == "stackwild")
	_check("the day sky is up, the floor hidden", floor_node != null and not floor_node.visible
		and ctx["world"].get_parent().get_node("WorldEnvironment").environment != sky_env)
	var frames := await _wait_built()
	var ms := Time.get_ticks_msec() - t0
	var st := _run({"cmd": "stackwild_status"})
	print("INFO small world made and meshed in %d ms (%d frames): %d sections, %d triangles" % [ms, frames, st["sections"], st["triangles"]])
	_check("the land is made and meshed", st["ready"] and st["sections"] > 10 and st["triangles"] > 1000 and st["still_to_build"] == 0, st)
	_check("greedy: far fewer triangles than block faces", st["triangles"] < 64 * 64 * 2 * 3, st["triangles"])
	var hills := {}
	for x in range(0, 64, 4):
		for z in range(0, 64, 4):
			hills[_g._top_at(x, z)] = true
	_check("the land has hills (many heights)", hills.size() > 5, hills.keys())
	var kinds := {}
	for x in 64:
		for z in 64:
			var t: int = _g._top_at(x, z)
			kinds[_g.block_at(x, t - 1, z)] = true
	_check("turf and trees on top", kinds.has(1) and kinds.has(7), kinds.keys())
	_check("sounds made on the way in: steps, digging, breaking, placing for each surface", _g._sounds.size() == 30 and _g._sounds.has("step_wood") and _g._sounds.has("break_sand"), _g._sounds.size())
	var window := _run({"cmd": "ui_get", "id_panel": "stackwild"})
	_check("the window opens with the world", window.get("ok", false) and window["panel"].get("visible", false))
	await _shot_panel("lobby", "stackwild")

	# Standing on the land.
	await _frames(10)
	var h := _head()
	var top: int = _g._top_at(floori(h.x), floori(h.z))
	_check("you stand on the ground where you start", absf(_g._feet - top) < 0.05 and _g._on_ground, [_g._feet, top])
	_check("not processing anything but you while idle", _g._jobs.is_empty())
	await _shot("view", h + Vector3(0, 1.0, 0), h + Vector3(10, -3, -14))
	await _shot("hills", h + Vector3(-6, 9, 8), h + Vector3(10, -2, -14))

	# Play (Build): the block in your hand, the wrist.
	var started = await _r({"cmd": "stackwild_start", "mode": "build"})
	_check("stackwild_start", started.get("ok", false) and _g.running and _g.is_processing(), started)
	_check("the window gets out of the way", not _run({"cmd": "ui_get", "id_panel": "stackwild"})["panel"].get("visible", true))
	_check("a block in the right hand, its name on the left wrist", ctx["right"].has_node("stackwild_block") and ctx["left"].has_node("stackwild_wrist")
		and "Turf" in (ctx["left"].get_node("stackwild_wrist") as Label3D).text)

	# A flat patch to work on, made with the agent's fill.
	h = _head()
	var cx := floori(h.x)
	var cz := floori(h.z)
	var gy: int = _g._feet
	var fill := _run({"cmd": "stackwild_fill", "from": [cx - 4, gy, cz - 6], "to": [cx + 4, gy + 6, cz + 2], "block": "air"})
	_check("stackwild_fill clears a space", fill.get("ok", false) and fill["changed"] > 0, fill)
	fill = _run({"cmd": "stackwild_fill", "from": [cx - 4, gy - 1, cz - 6], "to": [cx + 4, gy - 1, cz + 2], "block": "boards"})
	_check("stackwild_fill lays a floor", fill.get("ok", false) and _g.block_at(cx, gy - 1, cz) == 8, fill)
	_check("too big a fill is refused", not _run({"cmd": "stackwild_fill", "from": [0, 0, 0], "to": [63, 63, 63], "block": "air"}).get("ok", true))
	await _wait_built()
	_check("only the changed sections were made again", _g._meshed < st["sections"] + 40, _g._meshed)

	# Digging (Build: at once) with a real trigger press.
	var target := Vector3i(cx, gy - 1, cz - 2)
	_aim(h + Vector3(0, -0.4, 0), Vector3(target) + Vector3(0.5, 1.0, 0.5))
	await _frames(2)
	var meshed_before: int = _g._meshed
	await _press("right", "trigger_click")
	_check("breaking boards sounds like wood", _g.last_sound == "break_wood", _g.last_sound)
	_check("trigger digs the block you point at", _g.block_at(target.x, target.y, target.z) == 0, _g.block_at(target.x, target.y, target.z))
	await _wait_built()
	_check("its section is made again", _g._meshed > meshed_before)
	_check("Build: nothing to carry", _g.counts.is_empty())
	# Deepstone can't be dug.
	_check("deepstone stays", not _g._run({"cmd": "stackwild_block", "position": [cx, 0, cz], "block": "air"}).get("ok", true))

	# Placing with the grip, on the face you point at.
	_run({"cmd": "stackwild_set", "block": "brick"})
	var floor_cell := Vector3i(cx + 2, gy - 1, cz - 2)
	_aim(h + Vector3(0, -0.4, 0), Vector3(floor_cell) + Vector3(0.5, 1.0, 0.5))
	await _frames(2)
	await _press("right", "grip_click")
	_check("grip places the chosen block on top", _g.block_at(floor_cell.x, floor_cell.y + 1, floor_cell.z) == 9, _g.block_at(floor_cell.x, floor_cell.y + 1, floor_cell.z))
	_check("the wrist says Brick", "Brick" in (ctx["left"].get_node("stackwild_wrist") as Label3D).text)
	# Not inside you.
	_aim(h + Vector3(0.6, 1.2, 0), Vector3(cx, gy - 1, cz) + Vector3(0.5, 1.0, 0.5))
	await _frames(2)
	await _press("right", "grip_click")
	_check("no block where you stand", _g.block_at(cx, gy, cz) == 0)
	await _shot("placed", h + Vector3(-1.5, 0.8, 1.5), Vector3(floor_cell) + Vector3(0.5, 1, 0.5))

	# B: the next block; Y: the Blocks window.
	var before_b: int = _g.selected
	await _press("right", "by_button")
	_check("B: the next block", _g.selected == before_b + 1, [before_b, _g.selected])
	await _press("left", "by_button")
	_check("Y opens the Blocks window", _run({"cmd": "ui_get", "id_panel": "stackwild_blocks"}).get("panel", {}).get("visible", false))
	await _shot_panel("blocks", "stackwild_blocks")
	var picked := _run({"cmd": "stackwild_do", "act": "pick", "block": "lamp"})
	_check("picking a block holds it and closes the window", picked.get("ok", false) and _g.selected == 13
		and not _run({"cmd": "ui_get", "id_panel": "stackwild_blocks"})["panel"].get("visible", true), picked)

	# Walls stop you; one-block steps are walked up.
	_run({"cmd": "stackwild_fill", "from": [cx - 3, gy, cz - 5], "to": [cx + 3, gy + 2, cz - 5], "block": "slate"})
	_run({"cmd": "stackwild_fill", "from": [cx - 3, gy, cz - 4], "to": [cx + 3, gy, cz - 4], "block": "fieldstone"})
	_run({"cmd": "stackwild_fill", "from": [cx - 3, gy, cz - 2], "to": [cx + 3, gy + 6, cz + 2], "block": "air"})
	await _frames(2)
	_stand(cx + 0.5, cz + 0.5)
	await _frames(3)
	_stand(cx + 0.5, cz - 3.5)  # onto the step
	await _frames(30)
	_check("a one-block step is walked up", absf(_g._feet - (gy + 1)) < 0.05, [_g._feet, gy + 1])
	var origin := (ctx["camera"] as Node3D).get_parent() as Node3D
	origin.global_position += Vector3(0, 0, -1.2)  # into the wall
	await _frames(3)
	_check("a wall two high stops you", _head().z > cz - 4 - 0.01, _head().z)
	# Off the step: you fall back down.
	_stand(cx + 1.5, cz - 1.5)
	await _wait(0.6)
	_check("off the edge you fall to the floor", absf(_g._feet - gy) < 0.05 and _g._on_ground, _g._feet)
	# Footsteps: walking on the boards sounds like wood.
	_g.last_sound = ""
	for i in 12:
		origin.global_position += Vector3(0.1, 0, 0)
		await _frames(1)
	_check("walking on boards: wooden footsteps", _g.last_sound == "step_wood", _g.last_sound)
	origin.global_position += Vector3(-1.2, 0, 0)
	_g._last_xz = Vector2.INF
	await _frames(2)
	# A: jump, and a thud when you land.
	_g.last_sound = ""
	await _press("right", "ax_button")
	_check("a jump is heard", _g.last_sound == "jump", _g.last_sound)
	await _wait(0.15)
	var up: float = _g._feet - gy
	await _wait(0.9)
	_check("A jumps up and you come down", up > 0.4 and absf(_g._feet - gy) < 0.05, [up, _g._feet])
	_check("landing thuds on the boards", _g.last_sound == "step_wood", _g.last_sound)

	# Gather: digging takes a while and fills your pack.
	_run({"cmd": "stackwild_set", "mode": "gather"})
	_run({"cmd": "stackwild_block", "position": [cx + 2, gy, cz - 2], "block": "turf"})
	_stand(cx + 0.5, cz + 0.5)
	await _frames(3)
	h = _head()
	_aim(h + Vector3(0, -0.4, 0), Vector3(cx + 2.5, gy + 0.9, cz - 1.5))
	await _frames(2)
	_button("right", "trigger_click", true)
	await _wait(0.25)
	_check("Gather: not dug yet after a moment", _g.block_at(cx + 2, gy, cz - 2) == 1)
	await _wait(0.6)
	_button("right", "trigger_click", false)
	await _frames(1)
	_check("Gather: dug after holding, one turf carried", _g.block_at(cx + 2, gy, cz - 2) == 0 and int(_g.counts.get("turf", 0)) == 1, _g.counts)
	_check("the first block gathered goes in your hand", _g.selected == 1)
	_aim(h + Vector3(0, -0.4, 0), Vector3(cx + 2.5, gy, cz - 1.5))
	await _frames(2)
	await _press("right", "grip_click")
	_check("Gather: placing uses it up", _g.block_at(cx + 2, gy, cz - 2) == 1 and int(_g.counts.get("turf", 0)) == 0, _g.counts)
	await _press("right", "grip_click")
	_check("Gather: nothing left, nothing placed", _g.block_at(cx + 2, gy + 1, cz - 2) == 0)
	_run({"cmd": "stackwild_set", "mode": "build"})

	# The window during a game: the buttons go to it.
	await _r({"cmd": "stackwild_do", "act": "toggle"})
	await _frames(2)
	_check("the window open during a game: buttons go to it", _g._held and not _g.on_action("point", true))
	await _shot_panel("game-menu", "stackwild")
	_run({"cmd": "stackwild_do", "act": "hide"})
	await _frames(2)
	_check("closed: back to the game", not _g._held)

	# Save, leave, come back: the same world.
	_run({"cmd": "stackwild_block", "position": [5, 40, 5], "block": "felt_red"})
	var saved := _run({"cmd": "stackwild_save"})
	_check("stackwild_save", saved.get("ok", false) and FileAccess.file_exists(saved.get("file", "")), saved)
	var left_reply := _run({"cmd": "stackwild_leave"})
	await _frames(2)
	_check("Leave: back to the world you came from", left_reply.get("ok", false) and _run({"cmd": "projects_current"}).get("name") != "stackwild", left_reply)
	_check("the sky and floor are back, the land gone", floor_node.visible and ctx["world"].get_parent().get_node("WorldEnvironment").environment == sky_env
		and _g._land == null and not _g.is_processing())
	t0 = Time.get_ticks_msec()
	await _r({"cmd": "stackwild_do", "act": "toggle"})
	_check("back in: the saved world opens at once", _g._ready_now and _g.world_seed == 4242 and _g.block_at(5, 40, 5) == 14)
	await _wait_built()
	print("INFO saved world opened and meshed in %d ms" % (Time.get_ticks_msec() - t0))
	_check("and is meshed again", _run({"cmd": "stackwild_status"})["sections"] > 10)
	_check("a new world needs replace", not _run({"cmd": "stackwild_new"}).get("ok", true))

	# Unload: everything back.
	_run({"cmd": "stackwild_start"})
	await _frames(2)
	ctx["modules"].unload("stackwild")
	await _frames(3)
	_check("unload puts the sky and floor back", floor_node.visible and ctx["world"].get_parent().get_node("WorldEnvironment").environment == sky_env)
	_check("unload takes the windows", not _run({"cmd": "ui_get", "id_panel": "stackwild"}).get("ok", true) and not _run({"cmd": "ui_get", "id_panel": "stackwild_blocks"}).get("ok", true))
	_check("unload takes the gear off your hands", not ctx["right"].has_node("stackwild_block") and not ctx["left"].has_node("stackwild_wrist"))
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
