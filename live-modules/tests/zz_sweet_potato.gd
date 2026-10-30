extends SlopitectModule
# Headless checks for sweet_potato.gd. Run: tests/run.sh lib assets tools sweet_potato zz_sweet_potato
var _fails := 0
var _passes := 0


func setup() -> String:
	_go.call_deferred()
	return ""


func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if ok: _passes += 1
	else: _fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _go() -> void:
	await _wait(0.5)
	var potato = ctx["modules"].module("sweet_potato")
	var lib = ctx["modules"].module("lib")
	_check("idle with no potatoes", not potato.is_processing())
	# A stand-in for a placed model (no download needed): a node under
	# World/PolyHaven, announced through assets' own signal.
	var world: Node3D = ctx["world"]
	var holder: Node3D = world.get_node_or_null("PolyHaven")
	if holder == null:
		holder = Node3D.new()
		holder.name = "PolyHaven"
		world.add_child(holder)
	var pot := Node3D.new()
	pot.name = "zz_pot"
	holder.add_child(pot)
	pot.global_position = Vector3(1, 0.1, -2)
	var other := Node3D.new()
	other.name = "zz_chair"
	holder.add_child(other)
	ctx["modules"].module("assets").placed.emit("zz_chair", "chair")
	_check("another model: still idle", not potato.is_processing())
	ctx["modules"].module("assets").placed.emit("zz_pot", "sweet_potato")
	_check("a potato: running", potato.is_processing())
	_check("waiting", ctx["server"].run({"cmd": "sweet_potato_status"})["waiting"] == ["zz_pot"])

	Engine.time_scale = 8.0
	await _wait(2.5)  # 1 s still, then 1 s shrinking (game time)
	_check("potato shrunk away", lib.world_node("zz_pot") == null)
	_check("first tree there", lib.world_node("sweet_tree_1_trunk") != null)
	await _wait(25.0)  # three generations of 6 s
	var trees := 0
	var fruit := 0
	for n in range(1, 12):
		if lib.world_node("sweet_tree_%d_trunk" % n):
			trees += 1
		for f in range(1, 4):
			if lib.world_node("sweet_tree_%d_fruit_%d" % [n, f]):
				fruit += 1
	_check("7 trees grew", trees == 7, trees)
	_check("each with 3 fruit", fruit == 21, fruit)
	var trunk: Node3D = lib.world_node("sweet_tree_1_trunk")
	_check("first tree full size", is_equal_approx(trunk.scale.y, 1.2), trunk.scale)
	_check("idle again when done", not potato.is_processing())
	Engine.time_scale = 1.0
	var undo = ctx["server"].run({"cmd": "tools_status"})
	_check("growing left no undo steps", not "sweet_tree" in str(undo.get("undo")) and not "zz_pot" in str(undo.get("undo")), undo)

	# A potato that's taken away before it grows is forgotten.
	var pot2 := Node3D.new()
	pot2.name = "zz_pot2"
	holder.add_child(pot2)
	pot2.global_position = Vector3(-3, 2.0, -2)  # in the air: waits
	ctx["modules"].module("assets").placed.emit("zz_pot2", "sweet_potato")
	await _wait(1.5)
	_check("in the air: no tree", lib.world_node("sweet_tree_8_trunk") == null and potato.is_processing())
	pot2.free()
	await _wait(0.5)
	_check("removed: forgotten, idle", not potato.is_processing())

	ctx["modules"].unload("sweet_potato")
	_check("unloads cleanly", ctx["modules"].module("sweet_potato") == null and ctx["modules"].module("assets").placed.get_connections().is_empty())
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
