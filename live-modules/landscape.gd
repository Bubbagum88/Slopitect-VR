extends SlopitectModule

# Slopitect live module: landscape.
# Ground you can shape: 20 x 20 m around the middle of the play area, a
# height every 25 cm. It's a tool in the tools window (the tools module):
# point the right controller at the ground and hold the trigger to paint
# with the brush (raise, lower, smooth or flatten). Each stroke is one undo.
# While it's loaded it stands in for the flat floor, which comes back when
# it's unloaded. The heights are saved in the app's own storage
# (user://landscape.bin) after every change.
#
# Other modules can use height_at(x, z), and set_heights() / get_heights()
# with flatten_along() for things like paths; "changed" fires after each
# finished change.

signal changed

const SAVE_PATH := "user://landscape.bin"
const AREA := 20.0  # metres, each side
const STEP := 0.25  # metres between heights
const N := 81  # heights along each side: AREA / STEP + 1
const LOWEST := -5.0
const HIGHEST := 10.0
const MODES := ["raise", "lower", "smooth", "flatten"]
const RAY_LENGTH := 15.0
const RAY_STEP := 0.05

const SHADER := """
shader_type spatial;
uniform sampler2D heights : filter_nearest, repeat_disable;
uniform float step_size;
uniform float half_area;
uniform vec3 grass : source_color;
uniform vec3 rock : source_color;
varying float slope;

float h(ivec2 at) {
	ivec2 size = textureSize(heights, 0);
	return texelFetch(heights, clamp(at, ivec2(0), size - 1), 0).r;
}

void vertex() {
	ivec2 at = ivec2(round((VERTEX.xz + half_area) / step_size));
	VERTEX.y = h(at);
	float dx = h(at + ivec2(1, 0)) - h(at - ivec2(1, 0));
	float dz = h(at + ivec2(0, 1)) - h(at - ivec2(0, 1));
	NORMAL = normalize(vec3(-dx, 2.0 * step_size, -dz));
	slope = 1.0 - NORMAL.y;
}

void fragment() {
	ALBEDO = mix(grass, rock, smoothstep(0.15, 0.45, slope));
	ROUGHNESS = 0.95;
}
"""

var brush := {"mode": "raise", "size": 1.0, "strength": 1.0}  # size: radius in metres; strength: metres a second

var _heights := PackedFloat32Array()
var _image: Image
var _texture: ImageTexture
var _mesh: MeshInstance3D
var _marker: MeshInstance3D
var _floor: Node3D
var _tools: SlopitectModule
var _selected := false
var _painting := false
var _before := PackedFloat32Array()  # the heights when the stroke began
var _flatten_to := 0.0
var _since_upload := 0.0
var _lib: SlopitectModule
const UPLOAD_SECONDS := 0.05  # while painting, the ground is drawn again 20 times a second


func setup() -> String:
	_heights.resize(N * N)
	_heights.fill(0.0)
	_load()
	_image = Image.create_from_data(N, N, false, Image.FORMAT_RF, _heights.to_byte_array())
	_texture = ImageTexture.create_from_image(_image)

	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = SHADER
	material.set_shader_parameter("heights", _texture)
	material.set_shader_parameter("step_size", STEP)
	material.set_shader_parameter("half_area", AREA / 2.0)
	material.set_shader_parameter("grass", Color(0.35, 0.42, 0.35))
	material.set_shader_parameter("rock", Color(0.45, 0.4, 0.35))
	_mesh = MeshInstance3D.new()
	_mesh.name = "Ground"
	_mesh.mesh = _grid_mesh()
	_mesh.material_override = material
	add_child(_mesh)

	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.96
	ring.outer_radius = 1.0
	_marker.mesh = ring
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color(1, 1, 1, 0.8)
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_material.no_depth_test = true  # seen even where the ground bulges over it
	_marker.material_override = marker_material
	_marker.visible = false
	add_child(_marker)

	# The scene's flat floor would show through the ground where it's low.
	_floor = ctx["world"].get_parent().get_node_or_null("Floor")
	if _floor:
		_floor.visible = false

	register("landscape_status", _status, "the brush (mode, size, strength) and the ground's lowest and highest points")
	register("landscape_brush", _brush_command, "set the brush: any of mode (%s), size (radius, 0.25 to 5 m), size_step (1 bigger, -1 smaller), strength (0.1 to 5 m a second)" % ", ".join(MODES))
	register("landscape_sculpt", _sculpt_command, "shape the ground at one spot (one undo): position [x, z], mode (%s), size (radius in m), amount (m for raise/lower, 0 to 1 for smooth), height (for flatten)" % ", ".join(MODES))
	register("landscape_height", _height_command, "the ground's height at position [x, z]")
	register("landscape_reset", _reset_command, "make the ground flat again (one undo)")
	set_physics_process(false)  # only while it's the chosen tool
	return ""


func lib_ready(lib) -> void:
	_lib = lib


func _exit_tree() -> void:
	if _floor and is_instance_valid(_floor):
		_floor.visible = true


# --- As a tool -----------------------------------------------------------------------

func tool_info() -> Dictionary:
	var buttons := []
	for mode in MODES:
		buttons.append({"label": ("> " if brush["mode"] == mode else "") + mode.capitalize(), "action": {"cmd": "landscape_brush", "mode": mode}})
	buttons.append({"label": "Smaller", "action": {"cmd": "landscape_brush", "size_step": -1}})
	buttons.append({"label": "Bigger", "action": {"cmd": "landscape_brush", "size_step": 1}})
	buttons.append({"label": "Weaker", "action": {"cmd": "landscape_brush", "strength_step": -1}})
	buttons.append({"label": "Stronger", "action": {"cmd": "landscape_brush", "strength_step": 1}})
	return {"id": "landscape", "label": "Landscape", "order": 10, "buttons": buttons,
		"status": "%s, size %.2f m, strength %.1f" % [brush["mode"], brush["size"], brush["strength"]]}


func tool_selected(on: bool) -> void:
	_selected = on
	set_physics_process(on)
	if not on:
		_finish_stroke()
		_marker.visible = false


func tool_trigger(down: bool) -> void:
	if down:
		var hit = _aim()
		if hit == null:
			return
		_painting = true
		_before = _heights.duplicate()
		_flatten_to = height_at(hit.x, hit.z)
	else:
		_finish_stroke()


func _physics_process(delta: float) -> void:
	if not _selected:
		return
	var hit = _aim()
	_marker.visible = hit != null
	if hit == null:
		return
	_marker.global_position = hit + Vector3(0, 0.02, 0)
	_marker.scale = Vector3.ONE * brush["size"]
	if _painting:
		_apply(brush["mode"], hit.x, hit.z, brush["size"], brush["strength"] * delta, _flatten_to)
		_since_upload += delta
		if _since_upload >= UPLOAD_SECONDS:
			_upload()


func _finish_stroke() -> void:
	if not _painting:
		return
	_painting = false
	_upload()
	_record("%s stroke" % brush["mode"], _before)


# --- Brushes -------------------------------------------------------------------------

# One dab of a brush. amount is metres for raise and lower, and how far
# (0 to 1) to move toward the target for smooth and flatten.
func _apply(mode: String, x: float, z: float, radius: float, amount: float, target: float) -> void:
	var c := _grid(x, z)
	var reach := ceili(radius / STEP)
	var source := _heights.duplicate() if mode == "smooth" else _heights
	for j in range(maxi(0, c.y - reach), mini(N, c.y + reach + 1)):
		for i in range(maxi(0, c.x - reach), mini(N, c.x + reach + 1)):
			var d := Vector2(i * STEP - AREA / 2.0 - x, j * STEP - AREA / 2.0 - z).length()
			if d > radius:
				continue
			var w := smoothstep(0.0, 1.0, 1.0 - d / radius)
			var k := j * N + i
			var h: float = _heights[k]
			match mode:
				"raise":
					h += amount * w
				"lower":
					h -= amount * w
				"smooth":
					var around := (source[k - 1 if i > 0 else k] + source[k + 1 if i < N - 1 else k]
						+ source[k - N if j > 0 else k] + source[k + N if j < N - 1 else k]) / 4.0
					h += (around - h) * minf(1.0, amount * 4.0 * w)
				"flatten":
					h += (target - h) * minf(1.0, amount * 4.0 * w)
			_heights[k] = clampf(h, LOWEST, HIGHEST)


# --- For other modules ---------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	var gx := clampf((x + AREA / 2.0) / STEP, 0.0, N - 1.0)
	var gz := clampf((z + AREA / 2.0) / STEP, 0.0, N - 1.0)
	var i := mini(int(gx), N - 2)
	var j := mini(int(gz), N - 2)
	var fx := gx - i
	var fz := gz - j
	var a := lerpf(_heights[j * N + i], _heights[j * N + i + 1], fx)
	var b := lerpf(_heights[(j + 1) * N + i], _heights[(j + 1) * N + i + 1], fx)
	return lerpf(a, b, fz)


func inside(x: float, z: float) -> bool:
	return absf(x) <= AREA / 2.0 and absf(z) <= AREA / 2.0


func get_heights() -> PackedFloat32Array:
	return _heights.duplicate()


func set_heights(heights: PackedFloat32Array) -> void:
	if heights.size() != N * N:
		push_error("Slopitect landscape: set_heights got %d heights, needs %d" % [heights.size(), N * N])
		return
	_heights = heights.duplicate()
	_upload()
	_save()
	changed.emit()


# Levels the ground along a line of points (x, height, z), half_width to
# each side, blending back into the ground over the last 25 cm.
func flatten_along(points: PackedVector3Array, half_width: float) -> void:
	if points.size() < 2:
		return
	var reach := half_width + STEP
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var a := _grid(lo.x - reach, lo.y - reach)
	var b := _grid(hi.x + reach, hi.y + reach)
	for j in range(maxi(0, a.y), mini(N, b.y + 1)):
		for i in range(maxi(0, a.x), mini(N, b.x + 1)):
			var at := Vector2(i * STEP - AREA / 2.0, j * STEP - AREA / 2.0)
			var best := INF
			var best_y := 0.0
			for s in points.size() - 1:
				var p := Vector2(points[s].x, points[s].z)
				var q := Vector2(points[s + 1].x, points[s + 1].z)
				var t := clampf((at - p).dot(q - p) / maxf((q - p).length_squared(), 0.000001), 0.0, 1.0)
				var d := at.distance_to(p.lerp(q, t))
				if d < best:
					best = d
					best_y = lerpf(points[s].y, points[s + 1].y, t)
			if best > reach:
				continue
			var w := 1.0 if best <= half_width else 1.0 - (best - half_width) / STEP
			var k := j * N + i
			_heights[k] = clampf(lerpf(_heights[k], best_y, w), LOWEST, HIGHEST)
	_upload()


# --- Commands ------------------------------------------------------------------------

func _status(_request: Dictionary) -> Dictionary:
	var lo := INF
	var hi := -INF
	for h in _heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return {"ok": true, "brush": brush.duplicate(), "area": [AREA, AREA], "spacing": STEP, "lowest": snappedf(lo, 0.01), "highest": snappedf(hi, 0.01)}


func _brush_command(request: Dictionary) -> Dictionary:
	var next := brush.duplicate()
	for key in request:
		if key in ["cmd", "id"]:
			continue
		var value = request[key]
		match key:
			"mode":
				if not value in MODES:
					return {"ok": false, "error": "\"mode\" must be one of %s" % [MODES]}
				next["mode"] = value
			"size", "strength":
				var limits := [0.25, 5.0] if key == "size" else [0.1, 5.0]
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value < limits[0] or value > limits[1]:
					return {"ok": false, "error": "\"%s\" must be a number from %s to %s" % [key, limits[0], limits[1]]}
				next[key] = float(value)
			"size_step", "strength_step":
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value == 0:
					return {"ok": false, "error": "\"%s\" must be 1 (more) or -1 (less)" % key}
				var field: String = key.trim_suffix("_step")
				var limits := [0.25, 5.0] if field == "size" else [0.1, 5.0]
				next[field] = snappedf(clampf(next[field] * (1.25 if value > 0 else 0.8), limits[0], limits[1]), 0.01)
			_:
				return {"ok": false, "error": "unknown field \"%s\" (mode, size, size_step, strength, strength_step)" % key}
	brush = next
	return {"ok": true, "brush": brush.duplicate()}


func _sculpt_command(request: Dictionary) -> Dictionary:
	var position = request.get("position")
	if typeof(position) != TYPE_ARRAY or position.size() != 2 or typeof(position[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(position[1]) not in [TYPE_INT, TYPE_FLOAT]:
		return {"ok": false, "error": "\"position\" must be [x, z] in metres"}
	if not inside(position[0], position[1]):
		return {"ok": false, "error": "[%s, %s] is outside the ground (x and z from %s to %s)" % [position[0], position[1], -AREA / 2.0, AREA / 2.0]}
	var mode = request.get("mode", "raise")
	if not mode in MODES:
		return {"ok": false, "error": "\"mode\" must be one of %s" % [MODES]}
	var size = request.get("size", 1.0)
	if typeof(size) not in [TYPE_INT, TYPE_FLOAT] or size < 0.25 or size > 10.0:
		return {"ok": false, "error": "\"size\" (radius) must be 0.25 to 10 m"}
	var amount = request.get("amount", 0.5 if mode in ["raise", "lower"] else 1.0)
	if typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or amount < 0 or amount > (HIGHEST - LOWEST if mode in ["raise", "lower"] else 1.0):
		return {"ok": false, "error": "\"amount\" must be 0 to %s for %s" % [HIGHEST - LOWEST if mode in ["raise", "lower"] else 1, mode]}
	var height = request.get("height", height_at(position[0], position[1]))
	if typeof(height) not in [TYPE_INT, TYPE_FLOAT] or height < LOWEST or height > HIGHEST:
		return {"ok": false, "error": "\"height\" must be %s to %s m" % [LOWEST, HIGHEST]}
	var before := _heights.duplicate()
	# smooth and flatten are given as a fraction; a dab moves amount / 4 of the way.
	if mode in ["smooth", "flatten"]:
		for n in 8:
			_apply(mode, position[0], position[1], size, amount / 4.0, height)
	else:
		_apply(mode, position[0], position[1], size, amount, height)
	_upload()
	_record("%s at [%s, %s]" % [mode, position[0], position[1]], before)
	return {"ok": true, "height": snappedf(height_at(position[0], position[1]), 0.01)}


func _height_command(request: Dictionary) -> Dictionary:
	var position = request.get("position")
	if typeof(position) != TYPE_ARRAY or position.size() != 2 or typeof(position[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(position[1]) not in [TYPE_INT, TYPE_FLOAT]:
		return {"ok": false, "error": "\"position\" must be [x, z] in metres"}
	if not inside(position[0], position[1]):
		return {"ok": false, "error": "that's outside the ground (x and z from %s to %s)" % [-AREA / 2.0, AREA / 2.0]}
	return {"ok": true, "height": snappedf(height_at(position[0], position[1]), 0.001)}


func _reset_command(_request: Dictionary) -> Dictionary:
	var before := _heights.duplicate()
	_heights.fill(0.0)
	_upload()
	_record("flatten everything", before)
	return {"ok": true}


# --- Inside --------------------------------------------------------------------------

# A finished change: saved, announced, and one entry in the undo list.
func _record(label: String, before: PackedFloat32Array) -> void:
	var after := _heights.duplicate()
	if after == before:
		return
	_save()
	changed.emit()
	_tools = _lib.module("tools") if _lib else null
	if _tools:
		_tools.call("push_undo", "landscape: " + label, set_heights.bind(before), set_heights.bind(after))


# Where the right controller points at the ground, or null.
func _aim():
	var from: Vector3 = ctx["right"].global_position
	var along: Vector3 = -ctx["right"].global_basis.z
	var last := from
	var t := 0.0
	while t < RAY_LENGTH:
		t += RAY_STEP
		var p := from + along * t
		if inside(p.x, p.z) and p.y <= height_at(p.x, p.z):
			# Narrow it down between the last point above and this one below.
			var a := last
			var b := p
			for n in 8:
				var m := (a + b) / 2.0
				if m.y <= height_at(m.x, m.z):
					b = m
				else:
					a = m
			return b
		last = p
	return null


func _grid(x: float, z: float) -> Vector2i:
	return Vector2i(roundi((x + AREA / 2.0) / STEP), roundi((z + AREA / 2.0) / STEP))


func _grid_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for j in N:
		for i in N:
			vertices.append(Vector3(i * STEP - AREA / 2.0, 0.0, j * STEP - AREA / 2.0))
	for j in N - 1:
		for i in N - 1:
			var k := j * N + i
			indices.append_array([k, k + 1, k + N, k + 1, k + N + 1, k + N])
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader moves the points up and down, so the bounds cover every height.
	mesh.custom_aabb = AABB(Vector3(-AREA / 2.0, LOWEST, -AREA / 2.0), Vector3(AREA, HIGHEST - LOWEST, AREA))
	return mesh


func _upload() -> void:
	_since_upload = 0.0
	_image.set_data(N, N, false, Image.FORMAT_RF, _heights.to_byte_array())
	_texture.update(_image)


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Slopitect landscape: could not read %s (%s)" % [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return
	var size := file.get_32()
	var data := file.get_buffer(N * N * 4).to_float32_array()
	if size != N or data.size() != N * N:
		push_error("Slopitect landscape: %s is not a %dx%d ground; starting flat" % [SAVE_PATH, N, N])
		return
	_heights = data


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Slopitect landscape: could not save %s (%s)" % [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_32(N)
	file.store_buffer(_heights.to_byte_array())
