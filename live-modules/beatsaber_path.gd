extends SlopitectModule

# Slopitect live module: beatsaber_path.
# A black path on the floor under the beatsaber module's note lanes, from
# far away (z -12.5) to the player (z 1.5), shown only while its notes run.
# Separate from beatsaber.gd so that file stays as it is. Made by the
# headset agent.
# beatsaber has no signal for starting and stopping, so while it's loaded
# this checks its running flag each frame; without it, this is idle.

const PATH_WIDTH := 1.4
const Z_FAR := -12.5
const Z_NEAR := 1.5

var _strip: MeshInstance3D
var _beat: SlopitectModule


func setup() -> String:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(PATH_WIDTH, 0.02, Z_NEAR - Z_FAR)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.02, 0.02, 0.02)
	material.roughness = 0.9
	_strip = MeshInstance3D.new()
	_strip.mesh = mesh
	_strip.material_override = material
	_strip.position = Vector3(0.0, 0.01, (Z_FAR + Z_NEAR) * 0.5)
	_strip.visible = false
	add_child(_strip)  # its own, not World's: it's no thing to save or select
	set_process(false)
	return ""


func lib_ready(lib) -> void:
	if lib:
		lib.watch(self, "beatsaber", _beat_here, _beat_gone)
	else:
		_beat_gone(null)


func _beat_here(beat: SlopitectModule) -> void:
	_beat = beat
	set_process(true)


func _beat_gone(_old) -> void:
	_beat = null
	_strip.visible = false
	set_process(false)


func _process(_delta: float) -> void:
	_strip.visible = is_instance_valid(_beat) and _beat.get("running") == true
