extends SlopitectModule

# Beat Saber section in the Settings window: Start and Stop buttons, and the
# gap between notes. Runs the beatsaber module's own commands, so that
# module is not changed.

var interval := 0.6


func setup() -> String:
	register("beatsaber_pace", _pace, "the Beat Saber note gap: seconds (0.3 to 2)")
	register("beatsaber_go", _go, "start the Beat Saber notes at the chosen gap")
	return ""


func settings_info() -> Dictionary:
	return {"title": "Beat Saber", "order": 45, "settings": [
		{"id": "pace", "type": "slider", "label": "Note gap (s)", "min": 0.3, "max": 2.0, "step": 0.1,
			"value": interval, "set": {"cmd": "beatsaber_pace", "seconds": "{value}"}},
		{"id": "start", "type": "button", "label": "Start", "set": {"cmd": "beatsaber_go"}},
		{"id": "stop", "type": "button", "label": "Stop", "set": {"cmd": "beatsaber_stop"}},
	]}


func _pace(request: Dictionary) -> Dictionary:
	var s: float = float(request.get("seconds", interval))
	if s < 0.3 or s > 2.0:
		return {"ok": false, "error": "seconds must be 0.3 to 2"}
	interval = s
	return {"ok": true, "seconds": interval}


func _go(_request: Dictionary) -> Dictionary:
	return ctx["server"].run({"cmd": "beatsaber_start", "interval": interval})
