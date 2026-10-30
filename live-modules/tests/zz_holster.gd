extends SlopitectModule
# Headless checks for holster.gd. Run: tests/run.sh controls vrui tools pause avatar holster lib zz_holster
var _fails := 0
var _passes := 0
var _pic := 0


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


func _shot(tag: String, from: Array, at: Array) -> void:
	if OS.get_environment("PICTURE") == "": return
	await _wait(0.2)
	var look = await _r({"cmd": "view_look", "position": from, "look_at": at, "image": false, "width": 960})
	_pic += 1
	var dst := OS.get_environment("SHOTS") + "/%d-%s.jpg" % [_pic, tag]
	DirAccess.copy_absolute(look.get("saved", ""), dst)
	print("SHOT ", dst)


func _hand(hand: String, at: Vector3, look: Vector3) -> void:
	(ctx[hand] as Node3D).global_transform = Transform3D(Basis.looking_at(look - at, Vector3.UP), at)


func _grip(hand: String, down: bool) -> void:
	if down: (ctx[hand] as XRController3D).button_pressed.emit("grip_click")
	else: (ctx[hand] as XRController3D).button_released.emit("grip_click")


func _mode() -> String:
	return (await _r({"cmd": "holster_status"})).get("mode", "?")


func _go() -> void:
	await _wait(1.5)
	var cam := ctx["camera"] as Node3D
	var origin := cam.get_parent() as Node3D
	cam.global_transform = Transform3D(Basis(), Vector3(0, 1.6, 0))
	var av = ctx["modules"].module("avatar")
	var hol = ctx["modules"].module("holster")
	_check("holster loaded", hol != null)
	var root: Node3D = av.call("root")
	_check("avatar root()", root != null and root.is_ancestor_of(av.call("body")))
	var st = await _r({"cmd": "holster_status"})
	_check("starts free", st.get("mode") == "free", st)
	await _r({"cmd": "pause_do", "act": "hand_menu"})
	var hm := JSON.stringify((await _r({"cmd": "ui_get", "id_panel": "hand_menu"})).get("panel", {}))
	_check("hand menu has Avatar", hm.contains("holster") and hm.contains("Avatar"), hm.left(300))
	await _r({"cmd": "pause_do", "act": "hand_menu"})

	# Pointing away: the grip isn't taken.
	var middle: Vector3 = av.call("body").global_position
	_hand("right", Vector3(0.2, 1.2, -0.3), Vector3(2, 1.2, -0.3))
	await _wait(0.1)
	_grip("right", true)
	await _wait(0.1)
	_check("pointing away: not taken", await _mode() == "free")
	_grip("right", false)

	# Point at it and grip: it comes to the hand, smaller.
	_hand("right", Vector3(0.2, 1.2, -0.3), middle)
	await _wait(0.1)
	_grip("right", true)
	await _wait(0.4)
	_check("pointed: held", await _mode() == "held")
	var front: Vector3 = (ctx["right"] as Node3D).global_position - (ctx["right"] as Node3D).global_basis.z * 0.1
	_check("in the hand", root.global_position.distance_to(front) < 0.02, root.global_position)
	_check("held scale 0.5", is_equal_approx(root.scale.x, 0.5), root.scale)
	await _shot("held", [0.6, 1.7, 0.8], [0.1, 1.2, -0.3])

	# To the right hip and let go: stowed, small, follows you.
	_hand("right", Vector3(0.2, 1.0, -0.05), Vector3(0.2, 1.0, -1))
	await _wait(0.3)
	_check("hip ring shows", hol.get("_rings")["right"].visible)
	_check("hip ring lit", hol.get("_at_hip") == "right", hol.get("_at_hip"))
	await _shot("hip-rings", [0.7, 1.6, 0.9], [0.0, 1.0, -0.05])
	_grip("right", false)
	await _wait(0.4)
	_check("stowed", await _mode() == "holstered")
	_check("rings hidden", not hol.get("_rings")["right"].visible)
	_check("at the right hip", root.global_position.distance_to(Vector3(0.2, 1.0, -0.05)) < 0.02, root.global_position)
	_check("stowed scale 0.3", is_equal_approx(root.scale.x, 0.3), root.scale)
	await _shot("stowed", [0.8, 1.5, 0.9], [0.1, 1.0, -0.05])
	cam.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90)), Vector3(1, 1.6, 0))
	await _wait(0.2)
	var hip: Vector3 = Vector3(1, 1.0, 0) + Vector3(0, 0, -0.2) + Vector3(-0.05, 0, 0)  # facing -x: right is -z
	_check("goes where you go and turn", root.global_position.distance_to(hip) < 0.02, [root.global_position, hip])
	cam.global_transform = Transform3D(Basis(), Vector3(0, 1.6, 0))
	await _wait(0.2)

	# Another hand pointing at it doesn't take it from the hip.
	_hand("left", Vector3(-0.3, 1.2, -0.4), root.global_position)
	await _wait(0.1)
	_grip("left", true)
	await _wait(0.1)
	_check("stowed: pointing doesn't take it", await _mode() == "holstered")
	_grip("left", false)

	# Reach the hip, grip, flick forward-left and up a bit.
	_hand("right", Vector3(0.2, 1.0, -0.05), Vector3(0.2, 1.0, -1))
	await _wait(0.1)
	_grip("right", true)
	await _wait(0.1)
	_check("taken from the hip", await _mode() == "held")
	var v := Vector3(-2.0, 0.6, -2.0)
	var at := Vector3(0.2, 1.0, -0.05)
	for i in 12:
		await get_tree().process_frame
		at += v * get_process_delta_time()
		_hand("right", at, at + Vector3(0, 0, -1))
	_grip("right", false)
	await _wait(1.0)
	st = await _r({"cmd": "holster_status"})
	_check("flicked: out", st.get("mode") == "out", st)
	var off: Vector3 = root.global_position - cam.global_position
	var flat := Vector3(off.x, 0, off.z)
	_check("went the flick's way", flat.normalized().dot(Vector3(-1, 0, -1).normalized()) > 0.95, off)
	_check("flick distance", flat.length() > 1.0 and flat.length() < 2.6, flat.length())
	_check("higher for an upward flick", off.y > -0.3, off.y)
	_check("full size again", is_equal_approx(root.scale.x, 1.0), root.scale)
	await _shot("out", [0.5, 1.8, 1.5], [-0.6, 1.4, -0.8])

	# Walk (move the play area) and thumbstick-turn: it keeps its spot from you.
	origin.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(180)), Vector3(3, 0, 0))
	await _wait(2.5)
	var expect: Vector3 = cam.global_position + origin.global_basis * Vector3(off.x, off.y, off.z)
	_check("follows walking and turning", root.global_position.distance_to(expect) < 0.05, [root.global_position, expect])
	# Turning only your head: it stays.
	var before := root.global_position
	cam.rotation.y += deg_to_rad(70)
	await _wait(0.5)
	_check("head turn doesn't swing it", root.global_position.distance_to(before) < 0.01)
	origin.global_transform = Transform3D()
	cam.transform = Transform3D(Basis(), Vector3(0, 1.6, 0))
	await _wait(2.5)

	# The agent's avatar_move: it stays put there.
	await _r({"cmd": "avatar_move", "position": [1, 1.2, -2]})
	await _wait(0.3)
	_check("avatar_move frees it", await _mode() == "free")
	_check("stays where moved", root.global_position.distance_to(Vector3(1, 1.2, -2)) < 0.01, root.global_position)

	# Hand menu button: toggle stows, toggles back out.
	await _r({"cmd": "holster_toggle"})
	await _wait(0.6)
	_check("toggle stows", await _mode() == "holstered" and is_equal_approx(root.scale.x, 0.3))
	await _r({"cmd": "holster_toggle"})
	await _wait(0.8)
	_check("toggle brings it out", await _mode() == "out" and is_equal_approx(root.scale.x, 1.0))
	var r = await _r({"cmd": "holster_summon", "direction": [0, 0, -9]})
	_check("summon too far refused", not r.get("ok", true))
	r = await _r({"cmd": "holster_summon", "direction": [0.5, -0.2, -1]})
	await _wait(2.5)
	_check("summon to a spot", root.global_position.distance_to(Vector3(0.5, 1.4, -1)) < 0.05, root.global_position)

	# Reach it, grip, let go slowly elsewhere: stays there, full size.
	var mid: Vector3 = av.call("body").global_position
	_hand("left", mid + Vector3(-0.1, 0, 0.05), mid + Vector3(0, 0, -1))
	await _wait(0.1)
	_grip("left", true)
	await _wait(0.4)
	_check("reached: held in left", (await _r({"cmd": "holster_status"})).get("hand") == "left")
	_hand("left", Vector3(-0.5, 1.5, -0.6), Vector3(-0.5, 1.5, -2))
	await _wait(0.3)
	_grip("left", false)
	await _wait(0.4)
	_check("slow let go: free", await _mode() == "free")
	_check("put down full size", is_equal_approx(root.scale.x, 1.0), root.scale)
	_check("put down where let go", root.global_position.distance_to(Vector3(-0.5, 1.5, -0.7)) < 0.03, root.global_position)

	# Unloading leaves the avatar full size.
	await _r({"cmd": "holster_stow"})
	await _wait(0.5)
	print(await _r({"cmd": "code_unload", "name": "holster"}))
	await _wait(0.3)
	_check("unload: full size", is_equal_approx(root.scale.x, 1.0), root.scale)

	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
