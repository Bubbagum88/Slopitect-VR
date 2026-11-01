extends SlopitectModule
# Headless checks for holdout.gd (Rotwood Holdout).
# Run: tests/run.sh lib controls vrui save projects audio holdout zz_holdout
# Presses real buttons on the controllers (through controls.gd's actions),
# aims the right controller at the dead, swings the left one through them,
# and checks points, buying, doors, boards, the crate, tonics, getting hurt,
# being overrun, the walls keeping you in, leaving and unloading.
# PICTURE=1 SHOTS=folder saves pictures of the lodge.
var _fails := 0
var _passes := 0
var _pic := 0
var _h


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


func _run(q: Dictionary) -> Dictionary:
	return ctx["server"].run(q)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame


func _shot(tag: String, from: Vector3, at: Vector3) -> void:
	if OS.get_environment("PICTURE") == "": return
	var arena: Node3D = _h._arena
	var f := arena.to_global(from)
	var a := arena.to_global(at)
	await _wait(0.2)
	var look = await _r({"cmd": "view_look", "position": [f.x, f.y, f.z], "look_at": [a.x, a.y, a.z], "image": false, "width": 960})
	_pic += 1
	var dst := OS.get_environment("SHOTS") + "/%d-%s.jpg" % [_pic, tag]
	DirAccess.copy_absolute(look.get("saved", ""), dst)
	print("SHOT ", dst)


func _button(hand: String, button: String, down: bool) -> void:
	var c := ctx[hand] as XRController3D
	if down: c.button_pressed.emit(button)
	else: c.button_released.emit(button)


# The right controller at a spot in the lodge, pointing at another.
func _aim(from: Vector3, at: Vector3) -> void:
	var arena: Node3D = _h._arena
	var f := arena.to_global(from)
	var a := arena.to_global(at)
	(ctx["right"] as Node3D).global_transform = Transform3D(Basis.looking_at(a - f, Vector3.UP), f)


func _shoot() -> void:
	_button("right", "trigger_click", true)
	await _frames(1)
	_button("right", "trigger_click", false)
	await _frames(1)


func _clear_dead() -> void:
	for z in _h._zombies.duplicate():
		_h._hide_slot(z["slot"])
		_h._free_slots.append(z["slot"])
	_h._zombies.clear()
	_h._to_spawn = 0


func _you() -> Vector3:
	return _h._cam_local()


func _go() -> void:
	Engine.max_fps = 60
	await _frames(5)
	_h = ctx["modules"].module("holdout")
	_check("loaded and idle", _h != null and not _h.is_processing())
	_check("Menu tile", _h.menu_info().get("label") == "Holdout")
	var long_labels: Array = _h.settings_info()["settings"].filter(func(s): return s.get("label", "").length() > 40)
	_check("Settings labels 40 characters or less", long_labels.is_empty(), long_labels)
	_check("no game: actions pass through", not _h.on_action("point", true))
	var floor_node: Node3D = ctx["world"].get_parent().get_node_or_null("Floor")
	var sky_env = ctx["world"].get_parent().get_node("WorldEnvironment").environment

	# Start: its own world, the lodge, the gear.
	var started = await _r({"cmd": "holdout_start", "difficulty": "normal"})
	_check("holdout_start", started.get("ok", false), started)
	_check("in the Holdout world", _run({"cmd": "projects_current"}).get("name") == "holdout")
	_check("the night and the lodge are up", _h._arena != null and floor_node != null and not floor_node.visible
		and ctx["world"].get_parent().get_node("WorldEnvironment").environment != sky_env)
	_check("running and processing", _h.running and _h.is_processing())
	await _frames(2)
	_check("the window stays out of the way while you play", not _run({"cmd": "ui_get", "id_panel": "holdout"}).get("panel", {}).get("visible", false))
	_check("the Nailer in the right hand", ctx["right"].has_node("holdout_gun") and _h._gun().get("id") == "nailer")
	_check("500 points to start", _h.points == 500)
	_check("every window has 5 boards", _h.planks.values().all(func(n): return n == 5) and _h.planks.size() == 6)
	_check("you stand in the hall's middle", Vector2(_you().x, _you().z).length() < 0.05, _you())
	await _wait(3.3)
	_check("round 1 starts after a moment", _h.round_number == 1 and _h._to_spawn > 0, [_h.round_number, _h._to_spawn])
	await _shot("hall", Vector3(0, 1.7, 3.2), Vector3(0, 1.3, -4))
	await _wait(3.0)
	_check("the dead come up outside", _h._zombies.size() > 0 and _h._zombies.all(func(z): return _h._room_at(z["pos"]).is_empty()))
	await _shot("rising", Vector3(-2, 1.6, -2.5), Vector3(-2, 0.8, -8))

	# Shooting: a kill to the head, a hit to the body.
	_clear_dead()
	var you := _you()
	var z: Dictionary = _h.add_zombie_inside(Vector3(0, 0, -3.0), "hall", 60.0)
	_h._cooldown = 0.0
	_aim(Vector3(you.x + 0.2, 1.4, you.z), Vector3(0, 1.6, -3.0))
	var before: int = _h.points
	await _shoot()
	_check("a head shot kills: 100 points", z["state"] == "dying" and _h.points == before + 100 and _h.headshots == 1, [z["state"], _h.points - before])
	_check("one bullet less", _h._gun()["mag"] == 7)
	await _wait(0.4)
	var tough: Dictionary = _h.add_zombie_inside(Vector3(1.0, 0, -3.0), "hall", 5000.0)
	_aim(Vector3(you.x + 0.2, 1.2, you.z), Vector3(1.0, 1.0, -3.0))
	before = _h.points
	await _shoot()
	_check("a body hit: 10 points", _h.points == before + 10 and tough["hp"] < 5000.0, [_h.points - before, tough["hp"]])
	# Behind a wall: no hit.
	var outside: Dictionary = _h.add_zombie_inside(Vector3(0, 0, -6.0), "hall", 5000.0)
	outside["state"] = "approach"  # outside, walking to window w1
	_h._cooldown = 0.0
	await _wait(0.3)
	_aim(Vector3(outside["pos"].x, 1.2, -3.0), outside["pos"] + Vector3(0, 1.0, 0))
	var hp_before: float = outside["hp"]
	await _shoot()
	_check("walls stop shots", outside["hp"] == hp_before)
	_clear_dead()

	# Empty: it reloads by itself.
	_h._gun()["mag"] = 1
	_h._cooldown = 0.0
	_aim(Vector3(0, 1.4, 0), Vector3(0, 1.4, -3))
	await _shoot()
	_check("reloads by itself when empty", _h._reload_t > 0.0)
	await _wait(1.6)
	_check("reloaded from the reserve", _h._gun()["mag"] == 8 and _h._gun()["reserve"] < 64, _h._gun())
	_h._gun()["mag"] = 3
	_button("right", "by_button", true)
	_button("right", "by_button", false)
	_check("B reloads", _h._reload_t > 0.0)
	await _wait(1.6)

	# Buying: too poor, then a door, a wall gun, its ammo, a tonic.
	_h.points = 100
	_check("too poor to clear a door", not _h.open_door("trophy_door") and not _h.open_rooms.has("trophy"))
	_h.points = 9000
	_check("clearing the debris opens the Trophy Room", _h.open_door("trophy_door") and _h.open_rooms.has("trophy") and _h.points == 8250)
	_check("debris gone", not _h._debris["trophy_door"].visible)
	# A real press of A at the Scattergun's wall.
	_h._move_player_to(Vector3(-3.2, 0, -2.0))
	await _wait(0.25)
	_check("standing at the Scattergun: the prompt says so", _h._prompt.visible and "Scattergun" in _h._prompt.text, _h._prompt.text)
	await _shot("wall-gun", Vector3(-1.5, 1.6, -0.8), Vector3(-4, 1.4, -2.0))
	before = _h.points
	_button("right", "ax_button", true)
	_button("right", "ax_button", false)
	_check("A buys it: two guns, the Scattergun in hand", _h.guns.size() == 2 and _h._gun()["id"] == "scattergun" and _h.points == before - 500)
	_check("full ammo: buying ammo does nothing", not _h.buy_gun("scattergun"))
	_h._gun()["reserve"] = 0
	_check("ammo costs half", _h.buy_gun("scattergun") and _h._gun()["reserve"] == 36)
	_button("left", "by_button", true)
	_button("left", "by_button", false)
	_check("Y switches guns", _h._gun()["id"] == "nailer")
	_check("Ironbark: 250 health", _h.buy_tonic("ironbark") and _h._max_health() == 250.0 and _h.health == 250.0)
	_check("a tonic once only", not _h.buy_tonic("ironbark"))
	_check("Quickhands", _h.buy_tonic("quickhands"))
	_h._gun()["mag"] = 0
	_h._reload()
	_check("Quickhands halves the reload", absf(_h._reload_t - 0.7) < 0.05, _h._reload_t)
	await _wait(0.8)

	# The Lucky Crate (in the yard).
	_check("the yard is closed", not _h.open_rooms.has("yard"))
	_check("the Back Yard door", _h.open_door("yard_door") and _h.open_rooms.has("yard"))
	before = _h.points
	_check("the crate shuffles", _h.use_crate() and _h._crate_state == "shuffle" and _h.points == before - 950)
	await _shot("crate", Vector3(1.5, 1.6, 7.0), Vector3(4, 0.8, 7.0))
	await _wait(2.7)
	_check("then offers a gun you don't have", _h._crate_state == "offer" and _h._holding(_h._crate_gun) < 0, [_h._crate_state, _h._crate_gun])
	var offered: String = _h._crate_gun
	_check("taking it puts it in your hand", _h.use_crate() and _h._gun()["id"] == offered and _h.guns.size() == 2)
	_h.use_crate()
	await _wait(2.6)
	await _wait(8.3)
	_check("an offer not taken goes back", _h._crate_state == "idle")

	# Boards: held A at a window nails them back.
	_clear_dead()
	_h.planks["w1"] = 2
	_h._show_planks("w1")
	_h._move_player_to(Vector3(-2.0, 0, -3.4))
	await _wait(0.25)
	_check("at a broken window: Hold A", "board up" in _h._prompt.text, _h._prompt.text)
	before = _h.points
	_button("right", "ax_button", true)
	await _wait(1.6)
	_button("right", "ax_button", false)
	_check("holding A puts boards back, 10 points each", _h.planks["w1"] >= 4 and _h.points >= before + 20, [_h.planks["w1"], _h.points - before])

	# The walls keep you in.
	_h._move_player_to(Vector3(-8.0, 0, 0.0))
	await _frames(2)
	_check("walking out through a wall: nudged back in", _you().x > -4.0, _you())
	_h._move_player_to(Vector3(0, 0, 0))
	await _frames(2)

	# The knife: swing the left hand through one.
	var near: Dictionary = _h.add_zombie_inside(Vector3(0, 0, -0.9), "hall", 100.0)
	var left := ctx["left"] as Node3D
	var arena: Node3D = _h._arena
	for i in 8:
		var x := -0.6 + i * 0.17
		left.global_transform = Transform3D(Basis.IDENTITY, arena.to_global(Vector3(x, 1.2, -0.65)))
		await _frames(1)
	_check("the knife kills a weak one", near["state"] == "dying", near["state"])
	_clear_dead()

	# The dead tear the boards off, climb in and come for you.
	_h.planks["w1"] = 5
	_h._show_planks("w1")
	_h._move_player_to(Vector3(0, 0, 0))
	var climber: Dictionary = _h.add_zombie_inside(Vector3(-2.0, 0, -4.55), "hall")
	climber["state"] = "tear"
	climber["window"] = "w1"
	climber["speed"] = _h.SPEEDS["run"]
	_h.health = 100000.0  # not overrun yet
	Engine.time_scale = 4.0
	await _wait(8.0)
	Engine.time_scale = 1.0
	_check("it tore the boards off", _h.planks["w1"] < 5, _h.planks["w1"])
	await _shot("window", Vector3(-1.0, 1.7, -1.5), Vector3(-2, 1.0, -4.5))
	Engine.time_scale = 4.0
	await _wait(7.0)
	Engine.time_scale = 1.0
	_check("it climbed in and came for you", climber["state"] == "chase" and climber["pos"].distance_to(Vector3(_you().x, 0, _you().z)) < 1.5,
		[climber["state"], climber["pos"]])
	_check("and it hurts", _h.health < 100000.0, _h.health)
	_h.health = _h._max_health()
	await _shot("close", Vector3(0.6, 1.6, 1.2), climber["pos"] + Vector3(0, 1.3, 0))

	# Following you through a door into the Trophy Room.
	_clear_dead()
	var follower: Dictionary = _h.add_zombie_inside(Vector3(-2.0, 0, 0.0), "hall", 5000.0)
	follower["speed"] = _h.SPEEDS["run"]
	_h._move_player_to(Vector3(8.0, 0, 0.0))
	Engine.time_scale = 4.0
	await _wait(8.0)
	Engine.time_scale = 1.0
	_check("they follow you through the doors", follower["room"] == "trophy", [follower["room"], follower["pos"]])
	_clear_dead()

	# Overrun: the game ends, the round is kept.
	_h._move_player_to(Vector3(0, 0, 0))
	_h.round_number = 7
	var killer: Dictionary = _h.add_zombie_inside(Vector3(0, 0, -0.5), "hall", 5000.0)
	killer["cd"] = 0.0
	_h.health = 1.0
	await _frames(3)
	_check("overrun: the game ends", not _h.running and not _h.is_processing())
	_check("results and the best round kept", _h.results.get("round") == 7 and int(_h.best.get("normal", 0)) == 7, _h.results)
	_check("the window comes back", _run({"cmd": "ui_get", "id_panel": "holdout"}).get("panel", {}).get("visible", false))
	_check("the gear is put away", not is_instance_valid(ctx["right"].get_node_or_null("holdout_gun")))
	var st := _run({"cmd": "holdout_status"})
	_check("holdout_status", st.get("ok", false) and st.get("results", {}).get("round") == 7)
	_check("settings check their values", not _run({"cmd": "holdout_set", "max_zombies": 99}).get("ok", true)
		and _run({"cmd": "holdout_set", "max_zombies": 8}).get("ok", false) and _h.settings["max_zombies"] == 8)

	# A whole round with no help: they come, you shoot, a new round comes.
	await _r({"cmd": "holdout_start", "round": 1})
	_check("starting again: a fresh game", _h.running and _h.points == 500 and _h.guns.size() == 1 and _h.tonics.is_empty())
	_h.health = 100000.0  # can't lose
	Engine.time_scale = 4.0
	var waited := 0.0
	while _h.round_number < 2 and waited < 30.0:
		for zz in _h._zombies:
			if zz["state"] != "dying":
				_h._damage(zz, 100000.0, false, {"pierce": 1})
		await _wait(0.5)
		waited += 0.5
	Engine.time_scale = 1.0
	_check("round 1 cleared: round 2 comes", _h.round_number == 2, [_h.round_number, _h._to_spawn, _h._zombies.size()])
	_check("kills counted", _h.kills >= _h.round_count(1), _h.kills)

	# Leave: back to where you were; unload: everything back.
	var left_reply := _run({"cmd": "holdout_leave"})
	_check("Leave: back to the world you came from", left_reply.get("ok", false) and _run({"cmd": "projects_current"}).get("name") != "holdout", left_reply)
	await _frames(2)
	_check("the sky and floor are back", floor_node.visible and ctx["world"].get_parent().get_node("WorldEnvironment").environment == sky_env)
	_check("idle again", not _h.is_processing() and _h._arena == null)
	await _r({"cmd": "holdout_do", "act": "toggle"})
	await _frames(2)
	ctx["modules"].unload("holdout")
	await _frames(2)
	_check("unload puts the sky and floor back", floor_node.visible and ctx["world"].get_parent().get_node("WorldEnvironment").environment == sky_env)
	_check("unload takes the window", not _run({"cmd": "ui_get", "id_panel": "holdout"}).get("ok", true))
	print("RESULT %d passed, %d failed" % [_passes, _fails])
	get_tree().quit()
