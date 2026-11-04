extends SlopitectModule

# Slopitect live module: tool_front.
# Each tool's own menu (panel tools_t_ID) comes up in front of you whenever
# it opens, not where it was last left. A menu whose title bar's Pin is on
# (keep_place) stays where you put it.

const CHECK_SECONDS := 0.3
const DISTANCE := 0.5
const HEIGHT := -0.2
const PREFIX := "tools_t_"

var _since := 0.0
var _was := {}  # panel id -> shown at the last check


func setup() -> String:
	return ""


func _process(delta: float) -> void:
	_since += delta
	if _since < CHECK_SECONDS:
		return
	_since = 0.0
	var camera: Camera3D = ctx["camera"]
	if camera == null:
		return
	for child in ctx["modules"].get_children():
		if child == self or not child.has_method("tool_info"):
			continue
		var info = child.call("tool_info")
		if typeof(info) != TYPE_DICTIONARY or typeof(info.get("id")) != TYPE_STRING:
			continue
		var id_panel: String = PREFIX + info["id"]
		var got: Dictionary = ctx["server"].run({"cmd": "ui_get", "id_panel": id_panel})
		if not got.get("ok", false):
			continue
		var panel: Dictionary = got["panel"]
		var shown: bool = panel.get("visible", false)
		var was: bool = _was.get(id_panel, false)
		_was[id_panel] = shown
		if shown and not was and not panel.get("keep_place", false):
			_front(id_panel, camera)


func _front(id_panel: String, camera: Camera3D) -> void:
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return
	forward = forward.normalized()
	var at := camera.global_position + forward * DISTANCE
	at.y += HEIGHT
	# Its front faces back toward you.
	var yaw := rad_to_deg(atan2(-forward.x, -forward.z))
	ctx["server"].run({"cmd": "ui_update", "id_panel": id_panel, "place": "front",
		"keep_place": false, "distance": DISTANCE, "height": HEIGHT,
		"position": [at.x, at.y, at.z], "rotation": [0.0, yaw, 0.0]})
