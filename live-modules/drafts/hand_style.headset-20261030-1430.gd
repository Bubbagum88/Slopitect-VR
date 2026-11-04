extends SlopitectModule

# Slopitect live module: hand_style.
# Settings > "Beat Saber": "Show beat sabers" on or off. On: beatsaber's sabers
# show. Off: the human hands show (hands module). beatsaber keeps its sabers
# switched on every frame, so this hides their parts and trails instead.
# Makes no sabers of its own. Hide hands (Settings > Hands) hides the hands and the sabers.
# Not saved: sabers off on reload.

var style := "hand"
var _since := 0.0
var _hidden := false  # Hide hands is on


func setup() -> String:
	_remove_old_sabers()  # sabers left by an earlier version of this module
	register("hand_style", _style_command, "the hands or the beat sabers: style (hand or saber)")
	register("hand_style_show", _show_command, "show or hide the beat sabers: shown (true or false)")
	return ""


func _exit_tree() -> void:
	if ctx["modules"].module(name) != null:
		return  # the app is closing, not unloading this
	_remove_old_sabers()
	_hidden = false
	style = "hand"
	_show_beat(false)
	_apply()  # the hands come back as the hands module wants them


func _remove_old_sabers() -> void:
	for hand in ["left", "right"]:
		var old := (ctx[hand] as Node).get_node_or_null("saber_" + hand)
		if old != null:
			old.queue_free()


func _process(delta: float) -> void:
	_since += delta
	if _since < CHECK_SECONDS:
		return
	_since = 0.0
	var status: Dictionary = ctx["server"].run({"cmd": "hands_status"})
	_hidden = (status.get("settings", {}) as Dictionary).get("hidden", false) == true
	_apply()


const CHECK_SECONDS := 0.25


# Beat sabers on: the hands hide. Beat sabers off: the hands show.
func _apply() -> void:
	var on := not _hidden
	for hand in ["left", "right"]:
		var hand_node := (ctx[hand] as Node).get_node_or_null("hands_" + hand) as Node3D
		if hand_node != null:
			hand_node.visible = on and style == "hand"
	_show_beat(on and style == "saber")


# Shows or hides beatsaber's sabers: the parts of each saber, and its trails.
func _show_beat(want: bool) -> void:
	var bs = ctx["modules"].module("beatsaber")
	if bs == null:
		return
	var sabers = bs.get("sabers")
	if sabers is Dictionary:
		for side in sabers:
			var sab = sabers[side]
			if is_instance_valid(sab):
				for part in (sab as Node).get_children():
					if part is Node3D:
						(part as Node3D).visible = want
	var bs_root = bs.get("root")
	var trails = bs.get("trails")
	if bs_root is Node and trails is Dictionary:
		for side in trails:
			var trail = trails[side]
			var im = trail.get("mesh") if trail is Dictionary else null
			for node in (bs_root as Node).get_children():
				if node is MeshInstance3D and (node as MeshInstance3D).mesh == im:
					(node as MeshInstance3D).visible = want


func _style_command(request: Dictionary) -> Dictionary:
	var chosen = request.get("style")
	if chosen == null:
		return {"ok": true, "style": style}
	if typeof(chosen) != TYPE_STRING or not (chosen in ["hand", "saber"]):
		return {"ok": false, "error": "\"style\" must be hand or saber"}
	style = chosen
	_apply()
	return {"ok": true, "style": style}


func _show_command(request: Dictionary) -> Dictionary:
	var on = request.get("shown")
	if typeof(on) == TYPE_STRING:
		on = on == "true"
	if typeof(on) != TYPE_BOOL:
		return {"ok": false, "error": "\"shown\" must be true or false"}
	style = "saber" if on else "hand"
	_apply()
	return {"ok": true, "shown": on}


# Its own switch in the Beat Saber section, under beatsaber's own settings.
func settings_info() -> Dictionary:
	return {"title": "Beat Saber", "order": 46, "settings": [
		{"id": "shown", "type": "toggle", "label": "Show beat sabers", "value": style == "saber",
			"set": {"cmd": "hand_style_show", "shown": "{value}"}}]}
