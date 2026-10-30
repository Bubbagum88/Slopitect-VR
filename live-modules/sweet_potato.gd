extends SlopitectModule

# Slopitect live module: sweet_potato.
# When a placed sweet potato (Poly Haven model id sweet_potato) is put down
# on the ground and sits still for a second, it shrinks away over 1 s, and a
# small tree grows up on the same spot over about 6 s. When a tree is fully
# grown, it grows 3 sweet potato fruit on its crown, then sprouts 2 smaller
# potato trees on the ground around it (60% size), and each of those sprouts
# 2 more (36%). 7 trees in all. Made by the headset agent.
# It hears about potatoes from assets' placed signal, and runs only while a
# potato is waiting or a tree is growing. The trees are ordinary shapes;
# growing them adds nothing to undo (delete them like any shape).

const POLL := 0.25  # seconds between checks that a waiting potato is still
const STILL_TIME := 1.0
const STILL_MOVE := 0.002  # metres a potato may move between checks and still count as still
const GROUND_NEAR := 0.3  # metres above the ground, the potato's centre must be this low
const SHRINK_TIME := 1.0
const GROW_TIME := 6.0
const MAX_GEN := 2  # tree generations after the first: sprouts stop here
const CHILDREN := 2  # trees each grown tree sprouts
const CHILD_SIZE := 0.6  # each new generation is this much of the one before
const CHILD_RING := [1.2, 1.8]  # metres from the parent's base, where children land
const MODEL := "sweet_potato"

# Fruit hanging under the crown, at full size: offset from the base.
const FRUIT := [[0.6, 1.1, 0.1], [-0.3, 1.05, 0.55], [0.05, 1.12, -0.6]]
const FRUIT_SCALE := [0.14, 0.08, 0.1]  # a little oval, like a sweet potato
const FRUIT_COLOR := "#9b5a2c"

# Tree parts at full size: centre offset from the ground spot, size, colour.
const PARTS := [
	{"tag": "trunk", "shape": "cylinder", "at": [0.0, 0.6, 0.0], "size": [0.25, 1.2, 0.25], "color": "#6b4a2b"},
	{"tag": "crown", "shape": "sphere", "at": [0.0, 1.5, 0.0], "size": [1.4, 1.2, 1.4], "color": "#2e7d32"},
	{"tag": "bough", "shape": "sphere", "at": [0.35, 1.15, 0.2], "size": [0.8, 0.8, 0.8], "color": "#388e3c"},
]

var _lib: SlopitectModule
var _pots := {}  # potato name -> {"last": Vector3, "still": seconds}
var _trees: Array = []  # {"base", "pot", "prefix", "pt", "gt", "gen", "k"}
var _poll_in := 0.0


func setup() -> String:
	register("sweet_potato_status", _status, "the sweet potatoes waiting to grow and the trees growing now")
	set_process(false)
	return ""


func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		_pots.clear()
		_update_process()
		return
	lib.follow(self, "assets", "placed", _placed)
	lib.watch(self, "assets", _assets_here)


# Potatoes already in the world when assets (or this) loads.
func _assets_here(assets: SlopitectModule) -> void:
	for node in _lib.things():
		if _lib.is_model(node) and assets.call("model_id", String(node.name)) == MODEL:
			_placed(String(node.name), MODEL)


func _placed(node_name: String, id: String) -> void:
	if id != MODEL or _pots.has(node_name):
		return
	var node: Node3D = _lib.world_node(node_name) if _lib else null
	if node == null:
		return
	_pots[node_name] = {"last": node.global_position, "still": 0.0}
	_update_process()


func _update_process() -> void:
	set_process(not _pots.is_empty() or not _trees.is_empty())


func _process(delta: float) -> void:
	_poll_in -= delta
	if _poll_in <= 0.0:
		_poll_in = POLL
		_check_pots()
	for i in range(_trees.size() - 1, -1, -1):
		if _grow(_trees[i], delta):
			_trees.remove_at(i)
	_update_process()


# A potato that has sat still on the ground for STILL_TIME starts a tree.
func _check_pots() -> void:
	var grab: SlopitectModule = _lib.module("grab") if _lib else null
	var held: Array = grab.call("held") if grab and grab.has_method("held") else []
	for pot_name in _pots.keys():
		var node: Node3D = _lib.world_node(pot_name) if _lib else null
		if node == null:
			_pots.erase(pot_name)  # removed (or undone) before it grew
			continue
		var pot: Dictionary = _pots[pot_name]
		var at: Vector3 = node.global_position
		pot["still"] = pot["still"] + POLL if at.distance_to(pot["last"]) < STILL_MOVE else 0.0
		pot["last"] = at
		if pot["still"] < STILL_TIME or node in held:
			continue
		var ground := _ground(at.x, at.z)
		if at.y - ground > GROUND_NEAR:
			continue
		_pots.erase(pot_name)
		_start_tree(pot_name, Vector3(at.x, ground, at.z), 0, 1.0)


func _ground(x: float, z: float) -> float:
	var landscape: SlopitectModule = _lib.module("landscape") if _lib else null
	if landscape and landscape.call("inside", x, z):
		return landscape.call("height_at", x, z)
	return 0.0


# Runs commands without undo entries, when the tools module is there.
func _quietly(work: Callable) -> void:
	var tools: SlopitectModule = _lib.module("tools") if _lib else null
	if tools and tools.has_method("quiet"):
		tools.call("quiet", work)
	else:
		work.call()


# A tree at base. potato: the sweet potato it grows from ("" for a sprout, which
# has none to shrink). gen: 0 for the first tree. k: its size (1.0 = full).
func _start_tree(potato: String, base: Vector3, gen: int, k: float) -> void:
	var n := 1
	while _lib.world_node("sweet_tree_%d_trunk" % n) != null:
		n += 1
	var prefix := "sweet_tree_%d" % n
	_trees.append({"base": base, "pot": potato, "prefix": prefix, "pt": 0.0, "gt": -1.0 if potato != "" else 0.0, "gen": gen, "k": k})
	_quietly(func():
		for part in PARTS:
			_spawn(prefix + "_" + part["tag"], part["shape"], base, part["at"], part["size"], 0.01 * k, part["color"]))
	_update_process()


func _spawn(node_name: String, shape: String, base: Vector3, at: Array, size: Array, f: float, color: String) -> void:
	ctx["server"].run({"cmd": "spawn", "shape": shape, "name": node_name,
		"position": [base.x + at[0] * f, base.y + at[1] * f, base.z + at[2] * f],
		"scale": [size[0] * f, size[1] * f, size[2] * f], "color": color})


# Returns true when the tree is fully grown (then it's dropped from the list).
func _grow(tree: Dictionary, delta: float) -> bool:
	if tree["gt"] < 0.0:
		# The potato shrinks to nothing, then goes.
		tree["pt"] += delta
		var potato: Node3D = _lib.world_node(tree["pot"]) if _lib else null
		if tree["pt"] < SHRINK_TIME and potato:
			potato.scale = Vector3.ONE * (1.0 - tree["pt"] / SHRINK_TIME)
		else:
			if potato:
				_quietly(ctx["server"].run.bind({"cmd": "assets_remove", "name": tree["pot"]}))
			tree["gt"] = 0.0
		return false
	tree["gt"] += delta
	var g := clampf(tree["gt"] / GROW_TIME, 0.0, 1.0)
	_place_parts(tree, maxf(1.0 - pow(1.0 - g, 3.0), 0.01))  # quick start, slow finish
	if g >= 1.0:
		_quietly(_fruit.bind(tree))
		if tree["gen"] < MAX_GEN:
			_sprout(tree)
		return true
	return false


# Growing moves the tree's own shapes straight, each frame (not through
# commands, which would be dozens a second on a Quest 1).
func _place_parts(tree: Dictionary, e: float) -> void:
	var base: Vector3 = tree["base"]
	var f: float = e * tree["k"]
	for part in PARTS:
		var node: Node3D = _lib.world_node(tree["prefix"] + "_" + part["tag"]) if _lib else null
		if node == null:
			continue  # deleted while growing
		var at: Array = part["at"]
		var size: Array = part["size"]
		node.global_position = Vector3(base.x + at[0] * f, base.y + at[1] * f, base.z + at[2] * f)
		node.scale = Vector3(size[0], size[1], size[2]) * f


# A fully grown tree hangs its sweet potato fruit under the crown.
func _fruit(tree: Dictionary) -> void:
	for i in FRUIT.size():
		_spawn(tree["prefix"] + "_fruit_%d" % (i + 1), "sphere", tree["base"], FRUIT[i], FRUIT_SCALE, tree["k"], FRUIT_COLOR)


# A fully grown tree drops CHILDREN smaller trees on the ground around it.
func _sprout(tree: Dictionary) -> void:
	var base: Vector3 = tree["base"]
	for i in CHILDREN:
		var angle := randf() * TAU
		var distance := randf_range(CHILD_RING[0], CHILD_RING[1])
		var x := base.x + cos(angle) * distance
		var z := base.z + sin(angle) * distance
		_start_tree("", Vector3(x, _ground(x, z), z), tree["gen"] + 1, tree["k"] * CHILD_SIZE)


func _status(_request: Dictionary) -> Dictionary:
	return {"ok": true, "waiting": _pots.keys(), "growing": _trees.map(func(t): return t["prefix"]), "running": is_processing()}
