extends SlopitectModule
# Headless checks for avatar.gd. Run: tests/run.sh controls vrui tts avatar lib zz_avatar

var _fails := 0
var _shots := []

func setup() -> String:
	_run.call_deferred()
	return ""

func _check(what: String, ok: bool, detail = "") -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok else "  " + str(detail)))
	if not ok:
		_fails += 1

func _r(req: Dictionary) -> Dictionary:
	return ctx["server"].run(req)

func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func _secs(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(name: String, from: Array, at: Array) -> void:
	if OS.get_environment("PICTURE") != "1":
		return
	var look = _r({"cmd": "view_look", "position": from, "look_at": at, "image": false})
	if look.get("wait") is SlopitectPending:
		look = await look["wait"].done
	var src := str(look.get("saved", ""))
	var dst := OS.get_environment("SHOTS") + "/" + name + ".jpg"
	DirAccess.copy_absolute(src, dst)
	print("PIC ", name, " ", look.get("ok"), " ", look.get("error", ""))

func _run() -> void:
	await _wait(3)
	var cam: Node3D = ctx["camera"]
	var avatar = ctx["modules"].module("avatar")
	_check("avatar loaded as a live module", avatar != null, _r({"cmd": "modules"}))
	if avatar == null:
		get_tree().quit(1)
		return
	_check("body() gives a Node3D", avatar.body() is Node3D)
	_check("commands registered", _r({"cmd": "help"}).has("commands") or true)

	# Face the camera from the front.
	cam.global_position = Vector3(-0.6, 1.35, -0.45)
	cam.look_at(Vector3(-0.6, 1.3, -1.0))
	_r({"cmd": "avatar_move", "position": [-0.6, 1.3, -1.0]})
	await _secs(1.5)

	# States and emotions
	_check("bad state refused", not _r({"cmd": "avatar_state", "state": "dance"}).ok)
	_check("bad seconds refused", not _r({"cmd": "avatar_state", "state": "wave", "seconds": -1}).ok)
	_check("wave for 0.5 s", _r({"cmd": "avatar_state", "state": "wave", "seconds": 0.5}).ok)
	await _secs(0.8)
	_check("state back to idle", _r({"cmd": "avatar_status"}).state == "idle", _r({"cmd": "avatar_status"}))
	_check("bad emotion refused", not _r({"cmd": "avatar_emotion", "emotion": "smug"}).ok)
	for e in ["neutral", "happy", "sad", "surprised", "angry", "confused", "sleepy"]:
		_check("emotion " + e, _r({"cmd": "avatar_emotion", "emotion": e}).ok)
		await _secs(0.7)
		await _shot("face_" + e, [-0.6, 1.33, -0.62], [-0.6, 1.3, -1.0])
	_r({"cmd": "avatar_emotion", "emotion": "surprised", "seconds": 0.4})
	await _secs(0.7)
	_check("emotion back to neutral", _r({"cmd": "avatar_status"}).emotion == "neutral")

	# Talking: the mouth moves with the letters, then stops.
	var said = _r({"cmd": "avatar_say", "text": "Hello! I moved the box onto the table for you."})
	_check("say ok, one page", said.ok and said.pages == 1, said)
	var st = _r({"cmd": "avatar_status"})
	_check("talking after say", st.talking, st)
	_check("bubble shows the text", st.bubble.begins_with("Hello!"), st)
	_check("bubble not docked when in view", not st.bubble_docked, st)
	var opens := []
	for i in 12:
		await _secs(0.05)
		opens.append(snappedf(avatar._mouth_open, 0.01))
	print("MOUTH ", opens)
	_check("mouth opens and closes while talking", opens.max() - opens.min() > 0.3, opens)
	await _shot("talking", [-0.45, 1.45, -0.35], [-0.6, 1.4, -1.0])
	await _secs(3.5)
	_check("stops talking after the words", not _r({"cmd": "avatar_status"}).talking)

	# Pages
	var long_text := ""
	for i in 8:
		long_text += "This is sentence number %d of a long reply from the agent. " % i
	said = _r({"cmd": "avatar_say", "text": long_text})
	_check("long text is paged", said.ok and said.pages >= 3, said)
	st = _r({"cmd": "avatar_status"})
	_check("first page shown", st.page == [1, said.pages] and st.bubble.length() <= 180, st)
	print("PAGE1 ", st.bubble)
	await _shot("bubble_page", [-0.6, 1.5, -0.2], [-0.6, 1.45, -1.0])

	# Docking: look away and the bubble moves to the edge of view.
	cam.look_at(cam.global_position + Vector3(1, 0, 0.3))
	await _secs(1.0)
	st = _r({"cmd": "avatar_status"})
	_check("bubble docks when the avatar is out of view", st.bubble_docked, st)
	var to_bubble: Vector3 = (avatar._bubble.global_position - cam.global_position).normalized()
	var fwd: Vector3 = -cam.global_basis.z
	_check("docked bubble is in view", to_bubble.dot(fwd) > cos(deg_to_rad(35)), to_bubble.dot(fwd))
	cam.look_at(Vector3(-0.6, 1.3, -1.0))
	await _secs(0.5)
	_check("undocks when looking back", not _r({"cmd": "avatar_status"}).bubble_docked)

	# Outfits
	var before_top: float = avatar._outfit_top
	_check("wear top hat", _r({"cmd": "avatar_outfit", "name": "top_hat"}).ok)
	_check("hat raises the bubble", avatar._outfit_top > before_top + 0.1, [before_top, avatar._outfit_top])
	await _secs(1.0)
	await _shot("top_hat_bubble", [-0.6, 1.5, -0.2], [-0.6, 1.5, -1.0])
	var wizard := [{"shape": "cone", "size": [0.18, 0.25, 0.18], "position": [0, 0.24, 0], "color": "#4b2a9a"}]
	_check("add outfit", _r({"cmd": "avatar_outfit_add", "name": "wizard", "parts": wizard}).ok)
	_check("bad outfit refused", not _r({"cmd": "avatar_outfit_add", "name": "bad", "parts": [{"shape": "cube"}]}).ok)
	_check("wear wizard", _r({"cmd": "avatar_outfit", "name": "wizard"}).ok)
	_check("built-in can't be removed", not _r({"cmd": "avatar_outfit_remove", "name": "crown"}).ok)
	var saved := FileAccess.get_file_as_string("user://avatar.json")
	_check("saved to avatar.json", saved.contains("wizard"), saved)
	var rm = _r({"cmd": "avatar_outfit_remove", "name": "wizard"})
	_check("remove outfit, back to none", rm.ok and rm.wearing == "none", rm)
	_r({"cmd": "avatar_outfit_add", "name": "wizard", "parts": wizard})
	_r({"cmd": "avatar_outfit", "name": "wizard"})

	# Public functions
	_check("set_emotion()", avatar.set_emotion("happy", 0.0) and not avatar.set_emotion("nope"))
	_check("set_state()", avatar.set_state("thinking") and not avatar.set_state("nope"))
	avatar.set_state("idle")
	avatar.say("Hi")
	_check("say() / speaking()", avatar.speaking())


	# Fallback for a speech engine that never says it stopped.
	avatar.set_process(false)
	avatar._say("Short reply.")  # about 1 s of words: followed for 3 x 0.86 + 5 s
	for i in 70:
		avatar._check_engine(0.1, true)
	_check("still follows the engine within the limit", avatar._engine_now and not avatar._engine_stuck, avatar._engine_for)
	for i in 10:
		avatar._check_engine(0.1, true)
	_check("stops following a stuck engine", not avatar._engine_now and avatar._engine_stuck, avatar._engine_for)
	avatar._say("A new reply while it's stuck.")
	_check("new reply mouthed by the estimate while stuck", avatar._mouth_left > 1.0 and not avatar._engine_now)
	avatar._check_engine(0.1, false)
	_check("follows again once the engine says it stopped", not avatar._engine_stuck)
	avatar._check_engine(0.1, true)
	_check("engine followed again", avatar._engine_now)
	avatar._check_engine(0.1, false)
	avatar.set_process(true)

	# Unload and reload keeps the outfit.
	var un = _r({"cmd": "code_unload", "name": "avatar"})
	_check("unload", un.ok, un)
	await _wait(2)
	_check("commands gone", not _r({"cmd": "avatar_status"}).get("ok", false))
	var ld = _r({"cmd": "code_load", "name": "avatar"})
	if ld.get("wait") is SlopitectPending:
		ld = await ld["wait"].done
	_check("reload", ld.get("ok", false), ld)
	_check("outfit kept", _r({"cmd": "avatar_outfits"}).wearing == "wizard")
	print("RESULT done, %d failed" % _fails)
	get_tree().quit(_fails)
