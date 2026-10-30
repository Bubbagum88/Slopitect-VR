extends SlopitectModule

# Slopitect live module: beatsaber_path.
# A black path on the floor under the beatsaber module's note lanes, from
# far away (z -12.5) to the player (z 1.5), shown only while its notes run.
# The path lies on beatsaber's track (track_transform(), laid out where you
# stand when a song starts). Made by the headset agent.
# It follows beatsaber's started and stopped signals, so it never runs per
# frame; without beatsaber it stays hidden.

const PATH_WIDTH := 1.4
const Z_FAR := -12.5
const Z_NEAR := 1.5
const LOCAL := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.01, (Z_FAR + Z_NEAR) * 0.5))  # on the track

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
	_strip.visible = false
	add_child(_strip)  # its own, not World's: it's no thing to save or select
	set_process(false)
	return ""



func lib_ready(lib) -> void:
	if lib:
		lib.follow(self, "beatsaber", "started", _on_started)
		lib.follow(self, "beatsaber", "stopped", _on_stopped)
		lib.watch(self, "beatsaber", _beat_here, _beat_gone)
	else:
		_beat_gone(null)


func _beat_here(beat: SlopitectModule) -> void:
	_beat = beat
	if beat.get("running") == true:
		_on_started("")


func _beat_gone(_old) -> void:
	_beat = null
	_strip.visible = false


func _on_started(_title: String) -> void:
	if is_instance_valid(_beat) and _beat.has_method("track_transform"):
		_strip.global_transform = _beat.call("track_transform") * LOCAL
	else:
		_strip.global_transform = LOCAL
	_strip.visible = true


func _on_stopped() -> void:
	_strip.visible = false
