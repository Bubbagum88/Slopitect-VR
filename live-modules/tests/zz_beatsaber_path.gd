extends SlopitectModule
# Headless checks for beatsaber_path.gd (with a stand-in beatsaber). Run: tests/run.sh lib beatsaber_path zz_beatsaber_path
var _fails := 0
var _passes := 0

const FAKE_BEAT := "extends SlopitectModule\nvar running := false\n"


func setup() -> String:
	_go.call_deferred()
	return ""


func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if ok: _passes += 1
	else: _fails += 1


func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame


func _go() -> void:
	await _frames(5)
	var path = ctx["modules"].module("beatsaber_path")
	var strip: MeshInstance3D = path.find_children("*", "MeshInstance3D", false, false)[0]
	_check("idle without beatsaber", not path.is_processing() and not strip.visible)
	_check("not one of World's things", strip.get_parent() == path and not strip in ctx["modules"].module("lib").things())
	var s := GDScript.new()
	s.source_code = FAKE_BEAT
	s.reload()
	ctx["modules"].load_live("beatsaber", s)
	await _frames(3)
	var beat = ctx["modules"].module("beatsaber")
	_check("beatsaber loaded: watching, still hidden", path.is_processing() and not strip.visible)
	beat.running = true
	await _frames(2)
	_check("notes running: shown", strip.visible)
	beat.running = false
	await _frames(2)
	_check("stopped: hidden", not strip.visible)
	beat.running = true
	await _frames(2)
	ctx["modules"].unload("beatsaber")
	await _frames(2)
	_check("beatsaber gone: hidden and idle", not strip.visible and not path.is_processing())
	ctx["modules"].unload("beatsaber_path")
	await _frames(2)
	_check("unloads with its strip", not is_instance_valid(strip))
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
