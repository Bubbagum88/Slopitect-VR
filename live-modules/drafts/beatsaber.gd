extends SlopitectModule

# Beat Saber remake: red and blue notes fly at you on a beat. Each hand holds
# a saber (right = red, left = blue): a long glowing cylinder blade and a
# cylinder handle with silver bands, with a fading trail behind the blade.
# The APK's controller boxes are hidden while this runs and come back after.
# The sabers show only when the hands module's Settings choice is Sabers (and
# Hide hands is off); without the hands module they always show.
# Every note is a block with rounded edges.
# Arrow notes: a squashed white triangle, 75% of its old size, on the front and
# pushed toward the edge, tip pointing at the edge the cut must go in. Dot
# notes: a small white round dot on the front, cut from any direction.
# A cut breaks the note into falling pieces.
# Scoring: each cut gives 10 to 100 points. Arrow notes: full points need the
# swing to run along the arrow, and the blade to pass through the block's
# centre; off by 15 degrees or to the edge scores less. Dot notes: only the
# centre counts. A Perfect / Good / OK label pops up at each cut.
# Holding the saber: the controller nodes follow the "aim" pose (where the
# controller points), so the saber is turned up by fit["angle"] degrees to
# lie along the controller's handle, held fit["hold"] cm down its hilt with
# the hand at fit["grip"] (cm from the controller's point to the handle's
# middle, right hand; x mirrors for the left). beatsaber_config changes
# them from the PC; they are kept in user://beatsaber.json.

const TRAIL_LEN := 12
const SHARD_LIFE := 0.6
const NOTE_HALF := 0.15
const NOTE_ROUND := 0.03    # radius of the note's rounded edges
const HIT_MARGIN := 0.04
const MIN_SWING := 0.5
const ARROW_CUT := 0.6
const ARROW_SHIFT := 0.03   # how far the arrow moves toward the block's edge (stays on the flat face)
const SABER_SCALE := 0.8
const POP_LIFE := 0.9
const FULL_ANGLE := 5.0     # degrees off the arrow that still score full angle points
const ZERO_ANGLE := 25.0    # degrees off the arrow at which the angle points run out
const CENTRE_RANGE := 0.2   # metres from the block's centre where centre points run out
const FIT_PATH := "user://beatsaber.json"
const FIT_DEFAULTS := {"angle": 45.0, "grip": [0.0, -1.8, 4.8], "hold": 10.0}  # Touch: Chromium's WebXR grip is the aim turned up 45 degrees, 2.5 cm down; isaac saw the sabers too far forward on the headset, so 3 cm further back
const FIT_ANGLE_RANGE := [-30.0, 90.0]
const FIT_CM_MAX := 15.0

var root: Node3D = null
var notes: Array = []
var shards: Array = []
var popups: Array = []
var timer := 0.0
var interval := 0.6
var running := false
var score := 0
var misses := 0
var cuts := 0
var last_points := 0
var last_angle := 0.0
var last_offset := 0.0
var spawn_count := 0
var hidden_boxes: Array = []
var mesh_box: Mesh
var shard_mesh: Mesh
var blade_mesh: CylinderMesh
var handle_mesh: CylinderMesh
var band_mesh: CylinderMesh
var guard_mesh: CylinderMesh
var pommel_mesh: CylinderMesh
var dot_mesh: CylinderMesh
var arrow_mesh: ArrayMesh
var mat_red: StandardMaterial3D
var mat_blue: StandardMaterial3D
var mat_marker: StandardMaterial3D
var mat_trail: StandardMaterial3D
var mat_silver: StandardMaterial3D
var mat_handle: StandardMaterial3D
var sabers := {}
var trails := {}
var blades := {}
var prev_tip := {}
var fit := FIT_DEFAULTS.duplicate(true)


func setup() -> String:
	register("beatsaber_start", _start, "start the notes: optional interval (seconds between notes, 0.3 to 2)")
	register("beatsaber_stop", _stop, "stop the notes and clear them")
	register("beatsaber_score", _score, "the points, misses, cuts, average, and the last cut's angle and centre offset")
	register("beatsaber_config", _config, "from the PC only: how the saber sits in the hand: any of angle (degrees it tilts up from where the controller points, -30 to 90), grip ([x, y, z] cm from the controller's point to the handle's middle, right hand), hold (cm down the hilt the hand holds it, 0 to 15), or reset true")
	_load_fit()
	mesh_box = _rounded_box(0.3, NOTE_ROUND, 4)
	shard_mesh = _rounded_box(0.14, 0.02, 2)
	blade_mesh = CylinderMesh.new()
	blade_mesh.top_radius = 0.02
	blade_mesh.bottom_radius = 0.02
	blade_mesh.height = 1.0
	blade_mesh.radial_segments = 12
	handle_mesh = CylinderMesh.new()
	handle_mesh.top_radius = 0.018
	handle_mesh.bottom_radius = 0.018
	handle_mesh.height = 0.22
	handle_mesh.radial_segments = 12
	band_mesh = CylinderMesh.new()
	band_mesh.top_radius = 0.024
	band_mesh.bottom_radius = 0.024
	band_mesh.height = 0.012
	band_mesh.radial_segments = 12
	guard_mesh = CylinderMesh.new()
	guard_mesh.top_radius = 0.035
	guard_mesh.bottom_radius = 0.035
	guard_mesh.height = 0.012
	guard_mesh.radial_segments = 12
	pommel_mesh = CylinderMesh.new()
	pommel_mesh.top_radius = 0.026
	pommel_mesh.bottom_radius = 0.026
	pommel_mesh.height = 0.02
	pommel_mesh.radial_segments = 12
	# Dot note marker: a flat round disc (cylinder), turned to face +z.
	dot_mesh = CylinderMesh.new()
	dot_mesh.top_radius = 0.05
	dot_mesh.bottom_radius = 0.05
	dot_mesh.height = 0.02
	dot_mesh.radial_segments = 24
	# Squashed triangle lying in the XY plane, facing +z, tip at +y, near the
	# block's edge. Sized at 75% of the previous arrow (base 0.22, height 0.12).
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.0825, 0.015, 0.0), Vector3(0.0825, 0.015, 0.0), Vector3(0.0, 0.09, 0.0)])
	arrow_mesh = ArrayMesh.new()
	arrow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mat_red = _glow(Color(1.0, 0.2, 0.2))
	mat_blue = _glow(Color(0.2, 0.4, 1.0))
	mat_marker = StandardMaterial3D.new()
	mat_marker.albedo_color = Color(1.0, 1.0, 1.0)
	mat_marker.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_marker.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_silver = StandardMaterial3D.new()
	mat_silver.albedo_color = Color(0.8, 0.8, 0.85)
	mat_silver.metallic = 1.0
	mat_silver.roughness = 0.25
	mat_handle = StandardMaterial3D.new()
	mat_handle.albedo_color = Color(0.12, 0.12, 0.14)
	mat_handle.metallic = 0.3
	mat_handle.roughness = 0.6
	mat_trail = StandardMaterial3D.new()
	mat_trail.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_trail.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_trail.vertex_color_use_as_albedo = true
	mat_trail.cull_mode = BaseMaterial3D.CULL_DISABLED
	root = Node3D.new()
	ctx["world"].add_child(root)
	for side in ["right", "left"]:
		var box := (ctx[side] as Node).get_node_or_null("Mesh") as Node3D
		if box != null and box.visible:
			box.visible = false
			hidden_boxes.append(box)
		var col: Color = Color(1.0, 0.2, 0.2) if side == "right" else Color(0.2, 0.4, 1.0)
		var sab := Node3D.new()
		root.add_child(sab)
		sabers[side] = sab
		# Blade: from the grip (z -0.05) out to z -1.05, before scaling.
		_part(sab, blade_mesh, mat_red if side == "right" else mat_blue, Vector3(0, 0, -0.55), Vector3(90, 0, 0))
		# Handle behind the grip, with silver bands, a guard and a pommel.
		_part(sab, handle_mesh, mat_handle, Vector3(0, 0, 0.1), Vector3(90, 0, 0))
		_part(sab, guard_mesh, mat_silver, Vector3(0, 0, -0.03), Vector3(90, 0, 0))
		for z in [0.0, 0.06, 0.12, 0.18]:
			_part(sab, band_mesh, mat_silver, Vector3(0, 0, z), Vector3(90, 0, 0))
		_part(sab, pommel_mesh, mat_silver, Vector3(0, 0, 0.215), Vector3(90, 0, 0))
		var tn := MeshInstance3D.new()
		var im := ImmediateMesh.new()
		tn.mesh = im
		tn.material_override = mat_trail
		root.add_child(tn)
		trails[side] = {"mesh": im, "pts": [], "color": col}
	return ""


# A box with rounded edges and corners: radius r, n steps across each face.
func _rounded_box(size: float, r: float, n: int) -> Mesh:
	var h := size * 0.5
	var inner := h - r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axes := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
	for ax in 3:
		for sgn in [-1.0, 1.0]:
			var ua: Vector3 = axes[(ax + 1) % 3]
			var va: Vector3 = axes[(ax + 2) % 3]
			var origin: Vector3 = axes[ax] * sgn * h
			var grid: Array = []
			for i in range(n + 1):
				for j in range(n + 1):
					var p: Vector3 = origin + ua * lerpf(-h, h, float(i) / n) + va * lerpf(-h, h, float(j) / n)
					grid.append(_round_point(p, inner, r))
			for i in range(n):
				for j in range(n):
					var a: Dictionary = grid[i * (n + 1) + j]
					var b: Dictionary = grid[(i + 1) * (n + 1) + j]
					var c: Dictionary = grid[(i + 1) * (n + 1) + j + 1]
					var d: Dictionary = grid[i * (n + 1) + j + 1]
					_add_tri(st, a, b, c)
					_add_tri(st, a, c, d)
	return st.commit()


# Pulls a point on the cube's surface onto the rounded shape: position and normal.
func _round_point(p: Vector3, inner: float, r: float) -> Dictionary:
	var q := Vector3(clampf(p.x, -inner, inner), clampf(p.y, -inner, inner), clampf(p.z, -inner, inner))
	var nrm := (p - q).normalized()
	return {"pos": q + nrm * r, "nrm": nrm}


# Adds a triangle, flipping it if needed so it faces outward (along its normal).
func _add_tri(st: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	var pa: Vector3 = a["pos"]
	var pb: Vector3 = b["pos"]
	var pc: Vector3 = c["pos"]
	if (pb - pa).cross(pc - pa).dot(a["nrm"]) < 0.0:
		var t: Dictionary = b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(v["nrm"])
		st.add_vertex(v["pos"])


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3) -> void:
	var p := MeshInstance3D.new()
	p.mesh = mesh
	p.material_override = mat
	p.position = pos
	p.rotation_degrees = rot
	parent.add_child(p)


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.5
	return m


# The saber's place in the hand, seen from the controller: turned up onto
# the handle, the hold point on the handle's middle, scaled.
func _hilt(side: String) -> Transform3D:
	var g: Array = fit["grip"]
	var mirror := 1.0 if side == "right" else -1.0
	var grip := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(fit["angle"])), Vector3(mirror * g[0], g[1], g[2]) / 100.0)
	return grip * Transform3D(Basis.from_scale(Vector3.ONE * SABER_SCALE), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(0, 0, -fit["hold"] / 100.0))


func _config(request: Dictionary) -> Dictionary:
	if request.get("reset", false) == true:
		fit = FIT_DEFAULTS.duplicate(true)
		_save_fit()
		return {"ok": true, "fit": fit}
	var changed := fit.duplicate(true)
	for key in request:
		if key in ["cmd", "id"]:
			continue
		var v = request[key]
		match key:
			"angle":
				if not _number(v) or v < FIT_ANGLE_RANGE[0] or v > FIT_ANGLE_RANGE[1]:
					return {"ok": false, "error": "\"angle\" must be %d to %d degrees" % FIT_ANGLE_RANGE}
				changed["angle"] = float(v)
			"grip":
				if not _cm3(v):
					return {"ok": false, "error": "\"grip\" must be [x, y, z] in cm, each -%d to %d" % [FIT_CM_MAX, FIT_CM_MAX]}
				changed["grip"] = (v as Array).map(func(n): return float(n))
			"hold":
				if not _number(v) or v < 0.0 or v > FIT_CM_MAX:
					return {"ok": false, "error": "\"hold\" must be 0 to %d cm" % FIT_CM_MAX}
				changed["hold"] = float(v)
			_:
				return {"ok": false, "error": "unknown setting \"%s\" (one of: angle, grip, hold, reset)" % key}
	fit = changed
	_save_fit()
	return {"ok": true, "fit": fit}


func _number(v) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT]


func _cm3(v) -> bool:
	return typeof(v) == TYPE_ARRAY and v.size() == 3 and v.all(func(n): return _number(n) and absf(n) <= FIT_CM_MAX)


func _save_fit() -> void:
	var out := FileAccess.open(FIT_PATH, FileAccess.WRITE)
	if out == null:
		push_error("Slopitect beatsaber: couldn't save %s (error %d)" % [FIT_PATH, FileAccess.get_open_error()])
		return
	out.store_string(JSON.stringify(fit, "\t"))
	out.close()


func _load_fit() -> void:
	if not FileAccess.file_exists(FIT_PATH):
		return
	var saved = JSON.parse_string(FileAccess.get_file_as_string(FIT_PATH))
	if typeof(saved) != TYPE_DICTIONARY:
		push_error("Slopitect beatsaber: %s isn't readable; using the default fit" % FIT_PATH)
		return
	var a = saved.get("angle")
	if _number(a) and a >= FIT_ANGLE_RANGE[0] and a <= FIT_ANGLE_RANGE[1]:
		fit["angle"] = float(a)
	if _cm3(saved.get("grip")):
		fit["grip"] = (saved["grip"] as Array).map(func(n): return float(n))
	var h = saved.get("hold")
	if _number(h) and h >= 0.0 and h <= FIT_CM_MAX:
		fit["hold"] = float(h)


func _exit_tree() -> void:
	for box in hidden_boxes:
		if is_instance_valid(box):
			box.visible = true
	hidden_boxes.clear()
	popups.clear()
	if root != null:
		root.queue_free()


func _start(request: Dictionary) -> Dictionary:
	var iv: float = float(request.get("interval", 0.6))
	if iv < 0.3 or iv > 2.0:
		return {"ok": false, "error": "interval must be 0.3 to 2 seconds"}
	interval = iv
	score = 0
	misses = 0
	cuts = 0
	last_points = 0
	last_angle = 0.0
	last_offset = 0.0
	timer = interval
	running = true
	return {"ok": true, "interval": interval}


func _stop(_request: Dictionary) -> Dictionary:
	running = false
	for n in notes:
		n["node"].queue_free()
	notes.clear()
	for sh in shards:
		sh["node"].queue_free()
	shards.clear()
	for pu in popups:
		pu["node"].queue_free()
	popups.clear()
	return {"ok": true}


func _score(_request: Dictionary) -> Dictionary:
	var avg := 0
	if cuts > 0:
		avg = int(round(float(score) / cuts))
	return {
		"ok": true,
		"score": score,
		"misses": misses,
		"cuts": cuts,
		"average": avg,
		"last_points": last_points,
		"last_angle_off": snappedf(last_angle, 0.1),
		"last_centre_off_cm": snappedf(last_offset * 100.0, 0.1),
	}


# Dot note (dir zero): a block with a white round dot on the side facing you.
# Arrow note: a block with a white triangle on the side facing you, its tip
# pointing at the edge the cut must go toward (up, down, left or right).
func _build_note(red: bool, dir: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.material_override = mat_red if red else mat_blue
	m.mesh = mesh_box
	if dir == Vector3.ZERO:
		var d := MeshInstance3D.new()
		d.mesh = dot_mesh
		d.material_override = mat_marker
		d.position = Vector3(0, 0, 0.16)
		d.rotation = Vector3(90, 0, 0)
		m.add_child(d)
	else:
		var a := MeshInstance3D.new()
		a.mesh = arrow_mesh
		a.material_override = mat_marker
		a.position = Vector3(dir.x, dir.y, 0.0) * ARROW_SHIFT + Vector3(0, 0, 0.16)
		a.rotation = Vector3(0, 0, atan2(-dir.x, dir.y))
		m.add_child(a)
	return m


func _spawn_note() -> void:
	var red: bool = spawn_count % 2 == 0
	spawn_count += 1
	var dirs := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT]
	var dir := Vector3.ZERO
	if randi() % 2 == 0:
		dir = dirs[randi() % 4]
	var m := _build_note(red, dir)
	var xs := [-0.5, 0.0, 0.5]
	var ys := [1.0, 1.4, 1.8]
	m.position = Vector3(xs[randi() % 3], ys[randi() % 3], -12.0)
	root.add_child(m)
	notes.append({"node": m, "red": red, "dir": dir})


func _remove_note(i: int) -> void:
	notes[i]["node"].queue_free()
	notes.remove_at(i)


# Four pieces fly out from the hit point and shrink away.
func _break(pos: Vector3, mat: Material, swing: Vector3) -> void:
	for k in range(4):
		var off := Vector3((k % 2) * 2 - 1, (k / 2) * 2 - 1, 0.0) * 0.075
		var s := MeshInstance3D.new()
		s.mesh = shard_mesh
		s.material_override = mat
		s.position = root.to_local(pos + off)
		root.add_child(s)
		var vel: Vector3 = off.normalized() * randf_range(1.5, 2.5) + swing * 0.3
		vel += Vector3(0.0, randf_range(0.5, 1.5), 1.0)
		var spin := Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
		shards.append({"node": s, "vel": vel, "spin": spin, "life": SHARD_LIFE})


func _update_shards(delta: float) -> void:
	for i in range(shards.size() - 1, -1, -1):
		var sh: Dictionary = shards[i]
		var node: MeshInstance3D = sh["node"]
		sh["life"] = float(sh["life"]) - delta
		if sh["life"] <= 0.0:
			node.queue_free()
			shards.remove_at(i)
			continue
		var vel: Vector3 = sh["vel"]
		vel.y -= 9.8 * delta
		sh["vel"] = vel
		node.position += vel * delta
		node.rotation += sh["spin"] * delta
		node.scale = Vector3.ONE * clampf(float(sh["life"]) / SHARD_LIFE, 0.0, 1.0)


# Does the blade segment a-b (in the note's own space) pass through the note's
# box, grown by the margin? Slab test along each axis.
func _seg_hits_box(note: Node3D, a_world: Vector3, b_world: Vector3) -> bool:
	var a: Vector3 = note.to_local(a_world)
	var b: Vector3 = note.to_local(b_world)
	var h := NOTE_HALF + HIT_MARGIN
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 3:
		if absf(d[axis]) < 0.000001:
			if absf(a[axis]) > h:
				return false
		else:
			var ta := (-h - a[axis]) / d[axis]
			var tb := (h - a[axis]) / d[axis]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return false
	return true


# Scores one cut. Centre (all notes): how far the blade passes from the block's
# middle. Angle (arrow notes only): how far the swing is from the arrow's
# direction. Dot notes have no angle, so only the centre counts.
# Returns points (10 to 100), angle off (degrees) and centre offset (metres).
func _cut_score(note: Node3D, a_world: Vector3, b_world: Vector3, dir: Vector3, swing: Vector3) -> Dictionary:
	var a: Vector3 = note.to_local(a_world)
	var b: Vector3 = note.to_local(b_world)
	var d: Vector3 = b - a
	# Where the blade crosses the block's front plane (its middle if it runs along it).
	var t := 0.5
	if absf(d.z) > 0.000001:
		t = clampf(-a.z / d.z, 0.0, 1.0)
	var p: Vector3 = a + d * t
	var offset := Vector2(p.x, p.y).length()
	var centre := clampf(1.0 - offset / CENTRE_RANGE, 0.0, 1.0)
	var err := 0.0
	var angle := 1.0
	if dir != Vector3.ZERO:
		# Swing direction in the block's flat plane, against the arrow.
		var sw: Vector3 = note.global_transform.basis.transposed() * swing
		var s := Vector2(sw.x, sw.y)
		if s.length() > 0.000001:
			s = s.normalized()
			err = rad_to_deg(acos(clampf(s.dot(Vector2(dir.x, dir.y)), -1.0, 1.0)))
			angle = clampf(1.0 - maxf(0.0, err - FULL_ANGLE) / (ZERO_ANGLE - FULL_ANGLE), 0.0, 1.0)
	var points := int(round(10.0 + 90.0 * angle * (0.5 + 0.5 * centre)))
	return {"points": points, "angle": err, "offset": offset}


# Floating label at the cut: "Perfect 97", "Good 72" or "OK 31".
func _pop(pos: Vector3, points: int) -> void:
	var word := "OK"
	var col := Color(0.7, 0.7, 0.7)
	if points >= 90:
		word = "Perfect"
		col = Color(1.0, 0.85, 0.2)
	elif points >= 60:
		word = "Good"
		col = Color(1.0, 1.0, 1.0)
	var l := Label3D.new()
	l.text = "%s %d" % [word, points]
	l.font_size = 64
	l.pixel_size = 0.002
	l.modulate = col
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = root.to_local(pos)
	root.add_child(l)
	popups.append({"node": l, "life": POP_LIFE})


func _update_popups(delta: float) -> void:
	for i in range(popups.size() - 1, -1, -1):
		var pu: Dictionary = popups[i]
		var l: Label3D = pu["node"]
		pu["life"] = float(pu["life"]) - delta
		if pu["life"] <= 0.0:
			l.queue_free()
			popups.remove_at(i)
			continue
		l.position.y += 0.35 * delta
		var c := l.modulate
		c.a = clampf(float(pu["life"]) / POP_LIFE, 0.0, 1.0)
		l.modulate = c


func _update_trail(side: String, base: Vector3, tip: Vector3) -> void:
	var t: Dictionary = trails[side]
	var pts: Array = t["pts"]
	pts.push_front([root.to_local(base), root.to_local(tip)])
	while pts.size() > TRAIL_LEN:
		pts.pop_back()
	var im: ImmediateMesh = t["mesh"]
	im.clear_surfaces()
	if pts.size() < 2:
		return
	var col: Color = t["color"]
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, pts.size()):
		var a: Array = pts[i - 1]
		var b: Array = pts[i]
		var ca := Color(col.r, col.g, col.b, 0.6 * (1.0 - float(i - 1) / TRAIL_LEN))
		var cb := Color(col.r, col.g, col.b, 0.6 * (1.0 - float(i) / TRAIL_LEN))
		im.surface_set_color(ca)
		im.surface_add_vertex(a[0])
		im.surface_set_color(ca)
		im.surface_add_vertex(a[1])
		im.surface_set_color(cb)
		im.surface_add_vertex(b[0])
		im.surface_set_color(ca)
		im.surface_add_vertex(a[1])
		im.surface_set_color(cb)
		im.surface_add_vertex(b[1])
		im.surface_set_color(cb)
		im.surface_add_vertex(b[0])
	im.surface_end()


func _process(delta: float) -> void:
	if root == null:
		return
	for side in ["right", "left"]:
		var hand = ctx.get(side)
		var hands: SlopitectModule = ctx["modules"].module("hands")
		if hand == null or not is_instance_valid(hand) or (hands != null and not hands.call("sabers_shown")):
			sabers[side].visible = false
			blades.erase(side)
			prev_tip.erase(side)
			continue
		sabers[side].visible = true
		var st: Transform3D = hand.global_transform * _hilt(side)
		var base := st * Vector3(0, 0, -0.05)
		var tip := st * Vector3(0, 0, -1.05)
		sabers[side].global_transform = st
		var move := Vector3.ZERO
		if prev_tip.has(side) and delta > 0.0:
			move = tip - prev_tip[side]
		prev_tip[side] = tip
		blades[side] = {"base": base, "tip": tip, "move": move, "speed": move.length() / maxf(delta, 0.0001)}
		_update_trail(side, base, tip)
	_update_shards(delta)
	_update_popups(delta)
	if not running:
		return
	timer += delta
	if timer >= interval:
		timer = 0.0
		_spawn_note()
	for i in range(notes.size() - 1, -1, -1):
		var n: Dictionary = notes[i]
		var m: MeshInstance3D = n["node"]
		var dir: Vector3 = n["dir"]
		m.position.z += 4.0 * delta
		var side: String = "right" if n["red"] else "left"
		var ok := false
		var swing := Vector3.ZERO
		var bl: Dictionary = {}
		if blades.has(side):
			bl = blades[side]
			swing = bl["move"]
			if float(bl["speed"]) > MIN_SWING and _seg_hits_box(m, bl["base"], bl["tip"]):
				ok = dir == Vector3.ZERO or swing.normalized().dot(dir) > ARROW_CUT
		if ok:
			var sc := _cut_score(m, bl["base"], bl["tip"], dir, swing)
			var pts: int = sc["points"]
			score += pts
			cuts += 1
			last_points = pts
			last_angle = float(sc["angle"])
			last_offset = float(sc["offset"])
			_pop(m.global_position + Vector3(0.0, 0.22, 0.0), pts)
			_break(m.global_position, m.material_override, swing)
			_remove_note(i)
		elif m.position.z > 1.0:
			misses += 1
			_remove_note(i)
