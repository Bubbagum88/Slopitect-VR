extends SlopitectModule

# Sweet potato: when a placed sweet potato (model id sweet_potato) is put down
# on the ground and sits still for a second, it shrinks away over 1 s, and a
# small tree grows up on the same spot over about 6 s. When a tree is fully
# grown, it grows 3 sweet potato fruit on its crown, then sprouts 2 smaller
# potato trees on the ground around it (60% size), and each of those sprouts
# 2 more (36%). 7 trees in all. Checked 4 times a second.

const POLL := 0.25
const STILL_TIME := 1.0
const GROUND_NEAR := 0.3     # metres above the ground, the potato's centre must be this low
const SHRINK_TIME := 1.0
const GROW_TIME := 6.0
const MAX_GEN := 2           # tree generations after the first: sprouts stop here
const CHILDREN := 2          # trees each grown tree sprouts
const CHILD_SIZE := 0.6      # each new generation is this much of the one before
const CHILD_RING := [1.2, 1.8]   # metres from the parent's base, where children land

# Fruit hanging under the crown, at full size: offset from the base.
const FRUIT := [[0.6, 1.1, 0.1], [-0.3, 1.05, 0.55], [0.05, 1.12, -0.6]]
const FRUIT_SCALE := [0.14, 0.08, 0.1]   # a little oval, like a sweet potato
const FRUIT_COLOR := "#9b5a2c"

# Tree parts at full size: centre offset from the ground spot, size, colour.
const PARTS := [
	{"tag": "trunk", "shape": "cylinder", "at": [0.0, 0.6, 0.0], "size": [0.25, 1.2, 0.25], "color": "#6b4a2b"},
	{"tag": "crown", "shape": "sphere", "at": [0.0, 1.5, 0.0], "size": [1.4, 1.2, 1.4], "color": "#2e7d32"},
	{"tag": "bough", "shape": "sphere", "at": [0.35, 1.15, 0.2], "size": [0.8, 0.8, 0.8], "color": "#388e3c"},
]

var poll_timer := 0.0
var pots := {}   # potato name -> {"last": Vector3, "still": float}
var trees: Array = []
var counter := 0


func setup() -> String:
	return ""


func _process(delta: float) -> void:
	poll_timer += delta
	if poll_timer >= POLL:
		poll_timer = 0.0
		_poll()
	for i in range(trees.size() - 1, -1, -1):
		if _grow(trees[i], delta):
			trees.remove_at(i)


func _poll() -> void:
	var res: Dictionary = ctx["server"].run({"cmd": "assets_placed"})
	if not res.get("ok", false):
		return
	var held := str(ctx["server"].run({"cmd": "grab_status"}).get("holding", {}))
	var seen := {}
	for p in res.get("placed", []):
		if p.get("id", "") != "sweet_potato":
			continue
		var pname: String = p["name"]
		seen[pname] = true
		var pp: Array = p["position"]
		var pos := Vector3(pp[0], pp[1], pp[2])
		if not pots.has(pname):
			pots[pname] = {"last": pos, "still": 0.0}
			continue
		var pot: Dictionary = pots[pname]
		if pos.distance_to(pot["last"]) < 0.002:
			pot["still"] = float(pot["still"]) + POLL
		else:
			pot["still"] = 0.0
		pot["last"] = pos
		if float(pot["still"]) < STILL_TIME or held.find(pname) >= 0:
			continue
		var ground: float = _ground(pos.x, pos.z)
		if pos.y - ground > GROUND_NEAR:
			continue
		pot["still"] = -1000.0   # done: don't start a second tree for this potato
		_start_tree(pname, Vector3(pos.x, ground, pos.z), 0, 1.0)
	for pname in pots.keys():
		if not seen.has(pname):
			pots.erase(pname)


func _ground(x: float, z: float) -> float:
	var r: Dictionary = ctx["server"].run({"cmd": "landscape_height", "position": [x, z]})
	return float(r.get("height", 0.0))


# A tree at base. potato: the sweet potato it grows from ("" for a sprout, which
# has none to shrink). gen: 0 for the first tree. k: its size (1.0 = full).
func _start_tree(potato: String, base: Vector3, gen: int, k: float) -> void:
	counter += 1
	var prefix := "sweet_tree_%d" % counter
	var gt := -1.0 if potato != "" else 0.0
	trees.append({"base": base, "pot": potato, "prefix": prefix, "pt": 0.0, "gt": gt, "gen": gen, "k": k})
	for p in PARTS:
		var at: Array = p["at"]
		var sz: Array = p["size"]
		var f := 0.01 * k
		ctx["server"].run({
			"cmd": "spawn", "shape": p["shape"], "name": prefix + "_" + p["tag"],
			"position": [base.x + at[0] * f, base.y + at[1] * f, base.z + at[2] * f],
			"scale": [sz[0] * f, sz[1] * f, sz[2] * f], "color": p["color"],
		})


# Returns true when the tree is fully grown (then it's dropped from the list).
func _grow(tr: Dictionary, delta: float) -> bool:
	if float(tr["gt"]) < 0.0:
		# The potato shrinks to nothing, then goes.
		tr["pt"] = float(tr["pt"]) + delta
		var pt: float = tr["pt"]
		if pt < SHRINK_TIME:
			var s: float = 1.0 - pt / SHRINK_TIME
			ctx["server"].run({"cmd": "assets_move", "name": tr["pot"], "scale": [s, s, s]})
		else:
			ctx["server"].run({"cmd": "assets_remove", "name": tr["pot"]})
			tr["gt"] = 0.0
		return false
	tr["gt"] = float(tr["gt"]) + delta
	var g: float = clampf(float(tr["gt"]) / GROW_TIME, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - g, 3.0)   # quick start, slow finish
	_place_parts(tr, maxf(e, 0.01))
	if g >= 1.0:
		_fruit(tr)
		if int(tr["gen"]) < MAX_GEN:
			_sprout(tr)
		return true
	return false


func _place_parts(tr: Dictionary, e: float) -> void:
	var b: Vector3 = tr["base"]
	var f: float = e * float(tr["k"])
	for p in PARTS:
		var at: Array = p["at"]
		var sz: Array = p["size"]
		ctx["server"].run({
			"cmd": "move", "name": tr["prefix"] + "_" + p["tag"],
			"position": [b.x + at[0] * f, b.y + at[1] * f, b.z + at[2] * f],
			"scale": [sz[0] * f, sz[1] * f, sz[2] * f],
		})


# A fully grown tree hangs its sweet potato fruit under the crown.
func _fruit(tr: Dictionary) -> void:
	var b: Vector3 = tr["base"]
	var k: float = float(tr["k"])
	for i in FRUIT.size():
		var at: Array = FRUIT[i]
		var sz: Array = FRUIT_SCALE
		ctx["server"].run({
			"cmd": "spawn", "shape": "sphere", "name": tr["prefix"] + "_fruit_%d" % (i + 1),
			"position": [b.x + at[0] * k, b.y + at[1] * k, b.z + at[2] * k],
			"scale": [sz[0] * k, sz[1] * k, sz[2] * k], "color": FRUIT_COLOR,
		})


# A fully grown tree drops CHILDREN smaller trees on the ground around it.
func _sprout(tr: Dictionary) -> void:
	var b: Vector3 = tr["base"]
	for i in CHILDREN:
		var ang: float = randf() * TAU
		var dist: float = randf_range(CHILD_RING[0], CHILD_RING[1])
		var x: float = b.x + cos(ang) * dist
		var z: float = b.z + sin(ang) * dist
		var y: float = _ground(x, z)
		_start_tree("", Vector3(x, y, z), int(tr["gen"]) + 1, float(tr["k"]) * CHILD_SIZE)
