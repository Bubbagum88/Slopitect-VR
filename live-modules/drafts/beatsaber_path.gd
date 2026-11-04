extends SlopitectModule

# A black path on the floor under the Beat Saber note lanes, from far away
# (z -12.5) to the player (z 1.5). Shown only while the beatsaber module's
# notes run. Separate from beatsaber.gd so that file stays as it is.

const PATH_WIDTH := 1.4
const Z_FAR := -12.5
const Z_NEAR := 1.5

var strip: MeshInstance3D = null


func setup() -> String:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(PATH_WIDTH, 0.02, Z_NEAR - Z_FAR)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.02)
	mat.roughness = 0.9
	strip = MeshInstance3D.new()
	strip.mesh = mesh
	strip.material_override = mat
	strip.position = Vector3(0.0, 0.01, (Z_FAR + Z_NEAR) * 0.5)
	strip.visible = false
	ctx["world"].add_child(strip)
	return ""


func _process(_delta: float) -> void:
	if strip == null:
		return
	var bs = ctx["modules"].module("beatsaber")
	strip.visible = bs != null and bs.running


func _exit_tree() -> void:
	if strip != null:
		strip.queue_free()
