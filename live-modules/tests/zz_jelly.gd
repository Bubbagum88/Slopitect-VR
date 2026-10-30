extends SlopitectModule
# Headless checks for jelly.gd. Run: tests/run.sh avatar jelly lib zz_jelly
# (lib after jelly on purpose: jelly must start once lib arrives).
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


func _go() -> void:
	await _frames(10)
	var jelly = ctx["modules"].module("jelly")
	var av = ctx["modules"].module("avatar")
	_check("loaded before lib, works after it", jelly != null and av != null and (await _r({"cmd": "jelly_status"})).avatar)
	_check("processing with an avatar", jelly.is_processing())
	await _r({"cmd": "jelly_config", "stiffness": 120, "damping": 6})
	await _frames(120)
	var b: Node3D = av.body()
	var base := b.scale
	var maxy := base.y
	var miny := base.y
	for i in 10:
		av.root().position.y += 0.03
		await get_tree().process_frame
		maxy = maxf(maxy, b.scale.y)
	for i in 200:
		await get_tree().process_frame
		maxy = maxf(maxy, b.scale.y); miny = minf(miny, b.scale.y)
	_check("stretches and squashes", maxy > base.y * 1.005 and miny < base.y * 0.995, [maxy, miny])
	_check("poke", (await _r({"cmd": "jelly_poke", "strength": 1})).ok)
	await _frames(5)
	_check("poke wobbles", absf(b.scale.y / base.y - 1.0) > 0.01, b.scale)
	for bad in [{"stiffness": 5}, {"damping": "x"}, {"bounce": 1}]:
		var q := {"cmd": "jelly_config"}; q.merge(bad)
		_check("config refuses " + str(bad), not (await _r(q)).ok)

	# Avatar unloaded: scale back, jelly idle; loaded again: on again.
	await _r({"cmd": "code_unload", "name": "avatar"})
	await _frames(3)
	_check("avatar gone: idle", not jelly.is_processing())
	_check("status says no avatar", (await _r({"cmd": "jelly_status"})).avatar == false)
	_check("poke without avatar fails", not (await _r({"cmd": "jelly_poke"})).ok)
	await _r({"cmd": "code_load", "name": "avatar"})
	await _frames(5)
	_check("avatar back: on again", jelly.is_processing() and (await _r({"cmd": "jelly_status"})).avatar)

	# Jelly unloaded: the avatar's scale is put back.
	av = ctx["modules"].module("avatar")
	b = av.body()
	await _frames(60)
	var rest := b.scale
	await _r({"cmd": "jelly_poke", "strength": 1})
	await _frames(3)
	await _r({"cmd": "code_unload", "name": "jelly"})
	await _frames(2)
	_check("unload puts scale back", b.scale.is_equal_approx(rest), [b.scale, rest])
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
