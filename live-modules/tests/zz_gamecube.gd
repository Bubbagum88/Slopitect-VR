extends SlopitectModule
# Headless checks for gamecube.gd. Run: tests/run.sh lib vrui gamecube zz_gamecube
# Needs the gamecoob extension's Linux library in game/addons/gamecoob/bin
# (native/gamecoob/build.sh). With GAMECUBE_IPL set to your own dump's path
# it also plays the intro and the menu; without it those checks are skipped
# (no dump is ever kept with the tests).
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
	return ctx["server"].run(q)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _put_dump(bytes: PackedByteArray) -> void:
	var lib = ctx["modules"].module("lib")
	DirAccess.make_dir_recursive_absolute(lib.home().path_join("gamecube"))
	var f := FileAccess.open(lib.home().path_join("gamecube/ipl.bin"), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _go() -> void:
	await _wait(0.5)
	var gc = ctx["modules"].module("gamecube")
	_check("idle while off", not gc.is_processing())
	_check("extension loaded", ClassDB.class_exists("GameCoob"))
	var status := _r({"cmd": "gamecube_status"})
	_check("status off", status.get("ok") and not status.get("on") and not status.get("dump"), status)

	var none := _r({"cmd": "gamecube_start"})
	_check("no dump: says where", not none.get("ok") and "gamecube/ipl.bin" in str(none.get("error")), none)
	_put_dump(PackedByteArray([1, 2, 3]))
	var small := _r({"cmd": "gamecube_start"})
	_check("wrong size refused", not small.get("ok") and "bytes" in str(small.get("error")), small)
	var junk := PackedByteArray()
	junk.resize(2 * 1024 * 1024)
	_put_dump(junk)
	var bad := _r({"cmd": "gamecube_start"})
	_check("not a dump: the extension says so", not bad.get("ok") and "IPL" in str(bad.get("error")), bad)
	_check("still off, no TV", not gc.running and gc.get_node_or_null("tv") == null and not gc.is_processing())
	_check("buttons not taken while off", gc.on_action("right_a", true) == false)
	_check("pad refused while off", not _r({"cmd": "gamecube_pad", "button": "a"}).get("ok"))

	_check("threads set", _r({"cmd": "gamecube_set", "threads": 2}).get("threads") == 2)
	_check("threads range", not _r({"cmd": "gamecube_set", "threads": 9}).get("ok"))
	var saved = ctx["modules"].module("lib").read_json("user://gamecube.json")
	_check("threads saved", saved is Dictionary and int(saved.get("threads", 0)) == 2, saved)
	var labels_ok := true
	for s in gc.settings_info()["settings"]:
		labels_ok = labels_ok and String(s["label"]).length() <= 40
	_check("settings labels 40 or less", labels_ok)

	var shown := _r({"cmd": "gamecube_do", "act": "toggle"})
	_check("window opens", shown.get("ok") and _r({"cmd": "ui_get", "id_panel": "gamecube"}).get("panel", {}).get("visible"), shown)
	_r({"cmd": "gamecube_do", "act": "toggle"})
	_check("window closes", not _r({"cmd": "ui_get", "id_panel": "gamecube"}).get("panel", {}).get("visible", true))

	var ipl := OS.get_environment("GAMECUBE_IPL")
	if ipl.is_empty() or not FileAccess.file_exists(ipl):
		print("SKIP intro and menu checks (set GAMECUBE_IPL to your own dump to run them)")
	else:
		_put_dump(FileAccess.get_file_as_bytes(ipl))
		var on := _r({"cmd": "gamecube_start"})
		_check("turns on", on.get("ok"), on)
		_check("processing while on", gc.is_processing())
		var tv: Node3D = gc.get_node_or_null("tv")
		_check("TV in front of you", tv != null and (tv.global_position - ctx["camera"].global_position).dot(-ctx["camera"].global_basis.z) > 1.0)
		await _wait(1.5)
		var st := _r({"cmd": "gamecube_status"})
		_check("intro runs", st.get("state") == "intro" and st.get("logic_frames", 0) > 30 and st.get("pictures", 0) > 0, st)
		print("  picture draw time %.1f ms with %d threads" % [st.get("draw_ms", 0.0), st.get("threads", 0)])
		var lit := false
		var img: Image = tv.get_node("screen").material_override.albedo_texture.get_image()
		for i in 200:
			if img.get_pixel(randi() % img.get_width(), randi() % img.get_height()).v > 0.05:
				lit = true
				break
		_check("TV shows a picture", lit)
		_check("right A taken while on", gc.on_action("right_a", true) == true)
		gc.on_action("right_a", false)
		_check("skip", _r({"cmd": "gamecube_skip"}).get("ok"))
		await _wait(0.5)
		_check("cube menu after skip", _r({"cmd": "gamecube_status"}).get("state") == "menu")
		_check("pad press", _r({"cmd": "gamecube_pad", "button": "right"}).get("ok"))
		await _wait(0.3)
		_check("window has the pad while on", _r({"cmd": "ui_get", "id_panel": "gamecube"}).get("panel", {}).get("elements", []).size() > 5)
		_check("turns off", _r({"cmd": "gamecube_stop"}).get("ok"))
		await _wait(0.1)
		_check("off: TV gone, idle", gc.get_node_or_null("tv") == null and not gc.is_processing() and not gc.running)

	ctx["modules"].unload("gamecube")
	await _wait(0.1)
	_check("unloads cleanly", not _r({"cmd": "ui_get", "id_panel": "gamecube"}).get("ok", false))
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
