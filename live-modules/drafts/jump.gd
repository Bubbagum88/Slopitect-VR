extends SlopitectModule

# Jump with the right A button, and stand on top of things in the world.
# A second A press in the air starts flying: hold A to rise, hold B to sink,
# and sinking onto the ground lands you. Runs after controls, so it sets the
# play area's height and lands you on boxes.

const GRAVITY := 9.8
const JUMP_SPEED := 4.8  # m/s up: about 1.2 m, enough for a 1 m box
const FLY_SPEED := 3.0  # m/s up or down while flying
const STEP := 0.6  # a step up or down this high is walked, taller falls
const SCAN_EVERY := 0.25  # seconds between looks at the world's things
const NONE := -1000.0

var _origin: Node3D = null
var _feet := 0.0  # the play area's height now
var _vy := 0.0
var _air := false
var _can_fly := false  # a second A press in the air starts flying
var _flying := false
var _a_down := false  # right A held
var _b_down := false  # right B held
var _boxes: Array = []  # world-space boxes of the things in the world
var _scan_left := 0.0
var _last_a := -10000  # ticks of the last A press while flying


func setup() -> String:
	set_process_priority(100)
	return ""


func on_action(action: String, down: bool) -> bool:
	if action == "right_a" and down and _flying:
		var now := Time.get_ticks_msec()
		if now - _last_a < 350:
			_flying = false
			_air = true
			_vy = 0.0
			_can_fly = false
			_last_a = -10000
			return true
		_last_a = now
	return _old_on_action(action, down)


func _old_on_action(action: String, down: bool) -> bool:
	if action == "right_a":
		if not down:
			var held := _a_down
			_a_down = false
			return held
		if _origin == null:
			return false
		if _flying:
			_a_down = true
			return true
		if _air:
			if _can_fly:
				_can_fly = false
				_flying = true
				_air = false
				_vy = 0.0
				_a_down = true
			return true
		_air = true
		_vy = JUMP_SPEED
		_can_fly = true
		return true
	if action == "right_b":
		if not down:
			var held_b := _b_down
			_b_down = false
			return held_b
		if _flying:
			_b_down = true
			return true
	return false


func _process(delta: float) -> void:
	var camera: Node3D = ctx["camera"]
	if _origin == null:
		_origin = camera.get_parent() as Node3D
		if _origin == null:
			return
		_feet = _origin.global_position.y
	# Moved by something else (a teleport): take the new height.
	if not _air and not _flying and absf(_origin.global_position.y - _feet) > 0.3:
		_feet = _origin.global_position.y
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = SCAN_EVERY
		_scan()
	var head := camera.global_position
	var target := _ground(head.x, head.z)
	if _flying:
		_fly(delta, target)
	elif _air:
		_vy -= GRAVITY * delta
		_feet += _vy * delta
		if _vy <= 0.0 and _feet <= target:
			_feet = target
			_air = false
			_can_fly = false
	elif target < _feet - STEP:
		_air = true  # walked off an edge: fall
		_vy = 0.0
		_can_fly = true
	else:
		_feet = target
	_origin.global_position.y = _feet


# Flying: no gravity. A rises, B sinks; sinking onto the ground lands.
func _fly(delta: float, target: float) -> void:
	_vy = 0.0
	if _a_down:
		_feet += FLY_SPEED * delta
	if _b_down:
		_feet -= FLY_SPEED * delta
	if _feet <= target:
		_feet = target
		if _b_down:
			_flying = false
			_can_fly = false


func _ground(x: float, z: float) -> float:
	var landscape: SlopitectModule = ctx["modules"].module("landscape")
	if landscape and landscape.call("inside", x, z):
		return float(landscape.call("height_at", x, z))
	return 0.0


# The highest top of a thing under (x, z) that is not above limit, or NONE.
func _top_under(x: float, z: float, limit: float) -> float:
	var best := NONE
	for b in _boxes:
		var box: AABB = b
		var top := box.end.y
		if top <= limit and top > best and x >= box.position.x and x <= box.end.x and z >= box.position.z and z <= box.end.z:
			best = top
	return best


func _scan() -> void:
	_boxes.clear()
	var world: Node = ctx["world"]
	for child in world.get_children():
		if child is Node3D and child.name != "Ground" and child.is_visible_in_tree():
			var box := _box_of(child)
			if box.size.y > 0.0:
				_boxes.append(box)


# A thing's box in world space, round all its meshes.
func _box_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array = [node] if node is MeshInstance3D else node.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		var mesh := m as MeshInstance3D
		var mesh_box: AABB = mesh.global_transform * mesh.get_aabb()
		box = mesh_box if first else box.merge(mesh_box)
		first = false
	return box
