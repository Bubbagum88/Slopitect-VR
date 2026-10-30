extends SlopitectModule
# Headless checks for vrui.gd's Menu tiles following modules. Run: tests/run.sh controls vrui lib zz_menu
var _fails := 0
var _passes := 0
var _label := "Zz one"


func setup() -> String:
	_go.call_deferred()
	return ""


func menu_info() -> Dictionary:
	return {"id": "zz_menu", "label": _label, "order": 99, "action": {"cmd": "ping"}}


func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if ok: _passes += 1
	else: _fails += 1


func _labels(ui) -> Array:
	return ui.get("_apps").map(func(a): return a["label"])


func _go() -> void:
	for i in 5: await get_tree().process_frame
	var ui = ctx["modules"].module("vrui")
	_check("tile there", "Zz one" in _labels(ui), _labels(ui))
	_label = "Zz two"
	for i in 40: await get_tree().process_frame
	_check("no rescan without an event", "Zz one" in _labels(ui), _labels(ui))
	ctx["modules"].module("lib").touch(self)
	await get_tree().process_frame
	_check("touch: tile changes", "Zz two" in _labels(ui), _labels(ui))
	var s := GDScript.new()
	s.source_code = "extends SlopitectModule\nfunc menu_info() -> Dictionary:\n\treturn {\"id\": \"zz_new\", \"label\": \"Zz new\", \"action\": {\"cmd\": \"ping\"}}\n"
	s.reload()
	ctx["modules"].load_live("zz_new", s)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("new module: its tile", "Zz new" in _labels(ui), _labels(ui))
	ctx["modules"].unload("zz_new")
	await get_tree().process_frame
	await get_tree().process_frame
	_check("unloaded: tile gone", not "Zz new" in _labels(ui), _labels(ui))
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
