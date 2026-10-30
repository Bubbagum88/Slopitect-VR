extends SlopitectModule
# Headless checks for tools.gd. Run: tests/run.sh lib controls vrui save projects tools zz_tools
var _fails := 0
var _passes := 0


func setup() -> String:
	_go.call_deferred()
	return ""


func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if ok: _passes += 1
	else: _fails += 1


func _r(q: Dictionary) -> Dictionary:
	var r = ctx["server"].run(q)
	if r.get("wait") is SlopitectPending:
		var p: SlopitectPending = r["wait"]
		r = p.result if p.finished else await p.done
	return r


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _finish() -> void:
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


const FAKE_TOOL := "extends SlopitectModule\nvar label := \"Fake\"\nfunc tool_info() -> Dictionary:\n\treturn {\"id\": \"zz_fake\", \"label\": label, \"buttons\": []}\nfunc tool_selected(_on: bool) -> void:\n\tpass\nfunc tool_trigger(_down: bool) -> void:\n\tpass\n"


func _labels() -> Array:
	var got: Dictionary = (await _r({"cmd": "ui_get", "id_panel": "tools"})).get("panel", {})
	return [str(got.get("elements", []))]


func _go() -> void:
	await _wait(1.0)
	var tools = ctx["modules"].module("tools")
	_check("no scan", not tools.is_processing())
	_check("the Tools window is built", (await _r({"cmd": "ui_get", "id_panel": "tools"})).get("ok", false))
	var s := GDScript.new()
	s.source_code = FAKE_TOOL
	s.reload()
	ctx["modules"].load_live("zz_fake", s)
	await _wait(0.1)
	_check("a tool loads: its button appears", "Fake" in str(await _labels()), await _labels())
	var fake = ctx["modules"].module("zz_fake")
	fake.label = "Renamed"
	await _wait(0.1)
	_check("no rebuild without being told", not "Renamed" in str(await _labels()))
	ctx["modules"].module("lib").touch(fake)
	await _wait(0.1)
	_check("lib.touch: built again", "Renamed" in str(await _labels()), await _labels())
	tools.push_undo("zz step", func(): pass, func(): pass)
	await _wait(0.1)
	_check("undo label shown", "Undo zz step" in str(await _labels()), await _labels())
	await _r({"cmd": "projects_new", "name": "zz_other", "open": true})
	await _wait(0.2)
	_check("another project: undo list emptied", (await _r({"cmd": "tools_status"})).get("undo") == "")
	ctx["modules"].unload("zz_fake")
	await _wait(0.1)
	_check("a tool unloads: its button goes", not "Renamed" in str(await _labels()))
	_finish()
