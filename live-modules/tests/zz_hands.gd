extends SlopitectModule
# Headless checks for hands.gd. Run: tests/run.sh hands lib controls zz_hands
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


func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame


const FAKE_BEAT := "extends SlopitectModule\n"
const FAKE_CONTROLS := "extends SlopitectModule\nfunc value(_hand, what) -> float:\n\treturn 1.0 if what == \"grip\" else 0.0\n"


func _go() -> void:
	await _frames(10)
	var hands = ctx["modules"].module("hands")
	var left: Node3D = (ctx["left"] as Node).get_node_or_null("hands_left")
	_check("hands built", hands != null and left != null)
	_check("status sees controls", (await _r({"cmd": "hands_status"})).get("controls") == true)
	_check("moving with controls", hands.is_processing())
	_check("APK box hidden", not ((ctx["left"] as Node).get_node("Mesh") as Node3D).visible)

	# Hidden: idle. Shown again: moving.
	await _r({"cmd": "hands_hide", "hidden": true})
	_check("hidden: idle and invisible", not hands.is_processing() and not left.visible)
	await _r({"cmd": "hands_hide", "hidden": false})
	_check("shown: moving again", hands.is_processing() and left.visible)

	# beatsaber loaded hides them; unloaded brings them back.
	var s := GDScript.new()
	s.source_code = FAKE_BEAT
	s.reload()
	ctx["modules"].load_live("beatsaber", s)
	await _frames(2)
	_check("beatsaber hides them", not left.visible and not hands.is_processing())
	ctx["modules"].unload("beatsaber")
	await _frames(2)
	_check("beatsaber gone: back", left.visible and hands.is_processing())

	# Without controls: still shown, but idle.
	await _r({"cmd": "code_unload", "name": "controls"})
	await _frames(2)
	_check("no controls: idle, still shown", not hands.is_processing() and left.visible)
	_check("status says no controls", (await _r({"cmd": "hands_status"})).get("controls") == false)

	# A controls module comes (again): the hands pick it up and the grip curls them.
	var before := _curl(left)
	var c := GDScript.new()
	c.source_code = FAKE_CONTROLS
	c.reload()
	ctx["modules"].load_live("controls", c)
	await _frames(30)
	_check("controls back: moving", hands.is_processing())
	_check("grip curls the fingers", _curl(left) > before + 0.5, [before, _curl(left)])
	ctx["modules"].unload("controls")

	# Colours kept through lib.
	await _r({"cmd": "hands_colours", "skin": "#5b7bd6"})
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://hands.json"))
	_check("colours saved", typeof(saved) == TYPE_DICTIONARY and saved.get("skin") == "#5b7bd6", saved)
	await _r({"cmd": "hands_config", "reset": true})

	await _r({"cmd": "code_unload", "name": "hands"})
	await _frames(2)
	_check("unload: hands gone, box back", (ctx["left"] as Node).get_node_or_null("hands_left") == null
		and ((ctx["left"] as Node).get_node("Mesh") as Node3D).visible)
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


# How bent the fingers are, all bones added up (radians).
func _curl(hand: Node3D) -> float:
	var total := 0.0
	for n in hand.find_children("*", "Node3D", true, false):
		total += absf((n as Node3D).rotation.x)
	return total
