extends SlopitectModule
# Headless checks for net.gd's lib parts (no network). Run: tests/run.sh lib net zz_net
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


# Loads a module again from its file in the Slopitect modules folder.
func _load(module_name: String) -> String:
	var s := GDScript.new()
	s.source_code = FileAccess.get_file_as_string(OS.get_user_data_dir() + "/files_home/modules/%s.gd" % module_name)
	s.reload()
	var problem: String = ctx["modules"].load_live(module_name, s)
	await _wait(0.1)
	return problem


# The module loaded again with no lib, then lib loaded after it.
func _without_lib(module_name: String) -> void:
	ctx["modules"].unload("lib")
	ctx["modules"].unload(module_name)
	await _wait(0.1)
	_check(module_name + " loads without lib", await _load(module_name) == "")


func _finish() -> void:
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()


func _go() -> void:
	await _wait(0.5)
	var home: String = ctx["modules"].module("lib").home()
	_check("downloads folder made", DirAccess.dir_exists_absolute(home + "/downloads"))
	var bad := await _r({"cmd": "net_fetch", "url": "https://example.invalid/x.bin"})
	_check("fetch from a host not allowed refused", not bad.get("ok", true) and not "lib" in str(bad.get("error")), bad)
	var added := await _r({"cmd": "net_config", "add": "zz.example.com"})
	_check("net_config adds a host", added.get("ok", false) and "zz.example.com" in added.get("hosts", []), added)
	var saved = ctx["modules"].module("lib").read_json("user://net.json")
	_check("hosts saved through lib", typeof(saved) == TYPE_DICTIONARY and "zz.example.com" in saved.get("hosts", []), saved)

	# Without lib: the saved hosts still load at once (they're the safety rule),
	# but downloading waits for lib.
	await _without_lib("net")
	var net = ctx["modules"].module("net")
	_check("hosts loaded in setup, before lib", "zz.example.com" in net.hosts, net.hosts)
	var waiting := await _r({"cmd": "net_fetch", "url": "https://zz.example.com/x.bin"})
	_check("net_fetch waits for lib", not waiting.get("ok", true) and "lib" in str(waiting.get("error")), waiting)
	_check("allowed() works without lib", net.allowed("https://zz.example.com/a") and not net.allowed("https://zz.example.com.evil/a"))
	_check("lib loads after", await _load("lib") == "")
	var ok := await _r({"cmd": "net_fetch", "url": "https://example.invalid/x.bin"})
	_check("net_fetch past the lib check", not "lib" in str(ok.get("error")), ok)
	_finish()
