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


# A picture of a window, from 0.9 m in front of it.
func _shot_panel(tag: String, id_panel: String) -> void:
	if OS.get_environment("PICTURE") == "": return
	var ui: Node = ctx["modules"].module("vrui")
	var holder: Node3D = ui.find_child("Panel_" + id_panel, true, false) if ui else null
	if holder == null:
		return
	await _wait(0.3)
	var at := holder.global_position
	var f := at + holder.global_transform.basis.z * 0.9
	var look = await _r({"cmd": "view_look", "position": [f.x, f.y, f.z], "look_at": [at.x, at.y, at.z], "image": false, "width": 960})
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
	var started = await _r({"cmd": "holdout_start", "map": "lodge", "difficulty": "normal"})
	_check("holdout_start", started.get("ok", false), started)
	_check("in the Holdout world", _run({"cmd": "projects_current"}).get("name") == "holdout")
	_check("the night and the lodge are up", _h._arena != null and floor_node != null and not floor_node.visible
		and ctx["world"].get_parent().get_node("WorldEnvironment").environment != sky_env)
	_check("running and processing", _h.running and _h.is_processing())
	await _frames(2)
	_check("the window stays out of the way while you play", not _run({"cmd": "ui_get", "id_panel": "holdout"}).get("panel", {}).get("visible", false))
	_check("the M1911 in the right hand", ctx["right"].has_node("holdout_gun") and _h._gun().get("id") == "m1911")
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
	_check("too poor to clear a door", not _h.open_door("yard_door") and not _h.open_rooms.has("yard"))
	_h.points = 9000
	_check("clearing the debris opens the Back Yard", _h.open_door("yard_door") and _h.open_rooms.has("yard") and _h.points == 8000)
	_check("debris gone", not _h._debris["yard_door"].visible)
	# A real press of A at the Double Barrel's wall.
	_h._move_player_to(Vector3(-3.2, 0, -2.0))
	await _wait(0.25)
	_check("standing at the Double Barrel: the prompt says so", _h._prompt.visible and "Double Barrel" in _h._prompt.text, _h._prompt.text)
	await _shot("wall-gun", Vector3(-1.5, 1.6, -0.8), Vector3(-4, 1.4, -2.0))
	before = _h.points
	_button("right", "ax_button", true)
	_button("right", "ax_button", false)
	_check("A buys it: two guns, the Double Barrel in hand", _h.guns.size() == 2 and _h._gun()["id"] == "double_barrel" and _h.points == before - 500)
	_check("full ammo: buying ammo does nothing", not _h.buy_gun("double_barrel"))
	_h._gun()["reserve"] = 0
	_check("ammo costs half", _h.buy_gun("double_barrel") and _h._gun()["reserve"] == 36)
	_button("left", "by_button", true)
	_button("left", "by_button", false)
	_check("Y switches guns", _h._gun()["id"] == "m1911")
	_check("tonics need power", not _h.buy_tonic("ironbark") and "Needs power" == _h._prompt_text({"kind": "tonic", "id": "ironbark"}))
	_check("the Anvil needs power", not _h.use_anvil())
	_check("the generator turns the power on", _h.power_on() and _h.power and not _h.power_on())
	_check("Ironbark: 250 health", _h.buy_tonic("ironbark") and _h._max_health() == 250.0 and _h.health == 250.0)
	_check("a tonic once only", not _h.buy_tonic("ironbark"))
	_check("Quickhands", _h.buy_tonic("quickhands"))
	_h._gun()["mag"] = 0
	_h._reload()
	_check("Quickhands halves the reload", absf(_h._reload_t - 0.7) < 0.05, _h._reload_t)
	await _wait(0.8)

	# The Lucky Crate (in the yard).
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

	# Following you through the door into the Back Yard.
	_clear_dead()
	var follower: Dictionary = _h.add_zombie_inside(Vector3(-2.0, 0, 0.0), "hall", 5000.0)
	follower["speed"] = _h.SPEEDS["run"]
	_h.health = 100000.0
	_h._move_player_to(Vector3(-2.0, 0, 7.5))
	Engine.time_scale = 4.0
	await _wait(8.0)
	Engine.time_scale = 1.0
	_check("they follow you through the doors", follower["room"] == "yard", [follower["room"], follower["pos"]])
	_clear_dead()
	_h.health = _h._max_health()

	# The Anvil: the gun in your hand comes back forged.
	_h.points = 20000
	_h._give_gun("m1911")
	_check("the M1911 in hand for the Anvil", _h._gun()["id"] == "m1911")
	_check("the Anvil takes it and 5000", _h.use_anvil() and _h._anvil_state == "working" and _h.points == 15000 and _h._holding("m1911") < 0)
	await _wait(3.2)
	_check("then offers it back forged", _h._anvil_state == "offer")
	await _shot("anvil", Vector3(2.4, 1.6, 6.4), Vector3(2.4, 0.9, 4.4))
	_check("taking it: Forged M1911, twice the damage, half as much again in the mag",
		_h.use_anvil() and _h._gun().get("up", false) and _h._spec(_h._gun())["damage"] == 80.0 and _h._gun()["mag"] == 12, _h._gun())
	_check("the spawn gap shrinks 5% a round", absf(_h.spawn_gap(1) - 2.0) < 0.001 and absf(_h.spawn_gap(2) - 1.9) < 0.001 and _h.spawn_gap(80) == 0.25)
	_check("a forged gun can't be forged again", not _h.use_anvil())

	# Drops: walk over one to take it.
	_clear_dead()
	var at := _you()
	_h._gun()["reserve"] = 0
	_h._add_drop("ammo", Vector3(at.x, 0, at.z))
	await _frames(2)
	_check("Ammo Cache fills every gun", _h._drops.is_empty() and _h._gun()["reserve"] == _h._spec(_h._gun())["reserve"])
	_h._add_drop("double_pay", Vector3(at.x, 0, at.z))
	await _frames(2)
	var weak: Dictionary = _h.add_zombie_inside(Vector3(0, 0, -3.0), "hall", 10.0)
	before = _h.points
	_h._damage(weak, 50.0, false, {"pierce": 1})
	_check("Double Pay doubles the points", _h.effects.has("double_pay") and _h.points == before + 120, _h.points - before)
	_h._add_drop("one_shot", Vector3(at.x, 0, at.z))
	await _frames(2)
	var big: Dictionary = _h.add_zombie_inside(Vector3(1, 0, -3.0), "hall", 99999.0)
	_h._damage(big, 1.0, false, {"pierce": 1})
	_check("One Shot kills anything in one", big["state"] == "dying")
	_h.effects.clear()
	var a1: Dictionary = _h.add_zombie_inside(Vector3(-1, 0, -3.0), "hall", 99999.0)
	var a2: Dictionary = _h.add_zombie_inside(Vector3(2, 0, -2.0), "hall", 99999.0)
	_h._add_drop("blackout", Vector3(at.x, 0, at.z))
	await _frames(2)
	_check("Blackout kills them all", a1["state"] == "dying" and a2["state"] == "dying")
	_h.planks["w2"] = 0
	_h._show_planks("w2")
	_h._add_drop("hammer", Vector3(at.x, 0, at.z))
	await _frames(2)
	_check("Hammer & Nails boards every window", _h.planks.values().all(func(n): return n == 5))
	_h._add_drop("ammo", Vector3(at.x + 3.0, 0, at.z))
	await _shot("drop", Vector3(at.x, 1.6, at.z + 1.5), Vector3(at.x + 3.0, 0.9, at.z))
	_check("a drop away from you waits", _h._drops.size() == 1)
	_h._clear_drops()
	_h._drops_round = 0
	var drops_seen := 0
	for i in 400:
		var z2: Dictionary = _h.add_zombie_inside(Vector3(0, 0, -3.0), "hall", 1.0)
		_h._damage(z2, 5.0, false, {"pierce": 1})
		_clear_dead()
	var dealt := []
	_h._drop_deck.clear()
	for i in 5:
		dealt.append(_h._deal_drop())
	_check("drops come from a shuffled deck: every kind before a repeat", dealt.duplicate().filter(func(k): return dealt.count(k) == 1).size() == 5, dealt)
	_check("scoring past the goal readies a drop", _h.earned >= 2000 and _h._drop_goal > 2000.0)
	_check("kills leave drops sometimes, at most 4 a round", _h._drops.size() >= 1 and _h._drops.size() <= 4, _h._drops.size())
	_h._clear_drops()
	_h.effects.clear()

	# The shield: three parts, the workbench, then it takes hits in front.
	_check("no parts: no shield", not _h.build_shield())
	for i in 3:
		_check("pick up part %d" % (i + 1), _h.pick_part(i))
	_check("built at the workbench", _h.build_shield() and _h.shield == 6 and ctx["left"].has_node("holdout_shield"))
	var lefthand := ctx["left"] as Node3D
	var you2 := _you()
	lefthand.global_transform = Transform3D(Basis.looking_at(_h._arena.global_transform.basis * Vector3(0, 0, -1), Vector3.UP), _h._arena.to_global(Vector3(you2.x, 1.2, you2.z - 0.3)))
	var front: Dictionary = _h.add_zombie_inside(Vector3(you2.x, 0, you2.z - 0.8), "hall", 99999.0)
	var hp_now: float = _h.health
	_h._struck_by(front)
	_check("a hit from in front: the shield takes it", _h.health == hp_now and _h.shield == 5)
	front["pos"] = Vector3(you2.x, 0, you2.z + 0.8)
	_h._struck_by(front)
	_check("from behind: you take it", _h.health < hp_now and _h.shield == 5)
	_clear_dead()
	_h.health = _h._max_health()
	await _shot("shield", Vector3(you2.x + 0.6, 1.5, you2.z - 1.0), Vector3(you2.x, 1.2, you2.z - 0.3))

	# Second Wind: down, back up, the tonics gone.
	_check("Second Wind needs no power", "second_wind" in _h.NO_POWER_TONICS and _h.buy_tonic("second_wind"))
	var biter: Dictionary = _h.add_zombie_inside(Vector3(you2.x, 0, you2.z + 0.6), "hall", 99999.0)
	_h.health = 1.0
	_h._hurt_you(50.0)
	_check("at no health with Second Wind: down, not out", _h.running and _h.downed and _h.tonics.is_empty())
	_check("the dead nearby are thrown back", biter["pos"].distance_to(Vector3(you2.x, 0, you2.z)) >= 2.0, biter["pos"])
	_h._struck_by(biter)
	_check("no hurt while down", _h.downed and _h.health == 0.0)
	await _wait(5.3)
	_check("back up with full health", not _h.downed and _h.health == _h._max_health())
	_clear_dead()

	# Overrun: the game ends, the round is kept.
	_h._wear_shield(false)  # or it takes the hit
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

	# The game's menu: opening the window holds the game; Resume carries on.
	_clear_dead()
	_check("a Holdout button on the hand menu", _h.hand_info().get("label") == "Holdout" and _h.hand_info().get("action", {}).get("act") == "toggle")
	await _r({"cmd": "holdout_do", "act": "toggle"})
	await _frames(2)
	var menu: Array = _run({"cmd": "ui_get", "id_panel": "holdout"}).get("panel", {}).get("elements", [])
	var ids := menu.map(func(e): return e.get("id"))
	_check("mid-game the window opens as the game's menu", _run({"cmd": "ui_get", "id_panel": "holdout"}).get("panel", {}).get("visible", false)
		and "resume" in ids and "stop" in ids and "leave" in ids and not "start" in ids, ids)
	await _shot_panel("game-menu", "holdout")
	_check("the game waits while it's open", _h._held and not _h.is_processing() and _run({"cmd": "holdout_status"}).get("held", false))
	var gap_before: float = _h._spawn_t
	var round_before: int = _h.round_number
	var pts_before: int = _h.points
	await _wait(1.0)
	_check("nothing moves on while it waits", _h.round_number == round_before and _h.points == pts_before
		and _h._spawn_t == gap_before)
	_check("the buttons go to the window while it waits", not _h.on_action("point", true) and not _h.on_action("right_b", true))
	await _r({"cmd": "holdout_do", "act": "hide"})
	await _frames(2)
	_check("Resume: the game carries on", _h.running and not _h._held and _h.is_processing())
	_check("and the trigger shoots again", _h.on_action("point", true))
	_h.on_action("point", false)
	_run({"cmd": "holdout_stop"})
	await _frames(2)
	menu = _run({"cmd": "ui_get", "id_panel": "holdout"}).get("panel", {}).get("elements", [])
	ids = menu.map(func(e): return e.get("id"))
	await _shot_panel("lobby", "holdout")
	_check("after the game: the lobby with the maps and Start", "map_lodge" in ids and "start" in ids and "diff_normal" in ids and not "resume" in ids, ids)
	_check("maps: a wrong one is refused, the lodge is picked", not _run({"cmd": "holdout_set", "map": "nowhere"}).get("ok", true)
		and _run({"cmd": "holdout_set", "map": "lodge"}).get("ok", false) and _h.settings["map"] == "lodge")
	var map_setting: Array = _h.settings_info()["settings"].filter(func(e): return e["id"] == "map")
	_check("the map is in Settings too", map_setting.size() == 1 and map_setting[0]["options"].size() == _h.MAP_ORDER.size())
	_check("holdout_start takes a map", (await _r({"cmd": "holdout_start", "map": "lodge"})).get("ok", false) and _h.running
		and _h.open_rooms.keys() == [_h.MAPS["lodge"]["start"]])

	# The one-barrier map: one room, one window, and the dead find their way to it.
	_run({"cmd": "holdout_stop"})
	var cab = await _r({"cmd": "holdout_start", "map": "cabin"})
	_check("the Cabin starts", cab.get("ok", false) and _h.settings["map"] == "cabin" and _h._arena != null, cab)
	_check("one room, one window, no doors", _h._map["rooms"].size() == 1 and _h._map["windows"].size() == 1 and _h._map["doors"].is_empty()
		and _h.planks.size() == 1)
	_check("everything is in the room: guns, tonics, crate, power, Anvil, bench, parts",
		_h._uses.filter(func(u): return _h._room_at(u["at"]) != "cabin").map(func(u): return u["id"]) == [], 
		_h._uses.filter(func(u): return _h._room_at(u["at"]) != "cabin").map(func(u): return u["id"]))
	_check("the only cells into the room are through the window", _h._out_fields["w1"][_h._cell_of(Vector3(0, 0, 0))] == -1
		and _h._in_field.size() > 0 and _h._in_field[_h._cell_of(Vector3(-7, 0, 0))] == -1)
	_h.health = 100000.0
	_clear_dead()
	_h._to_spawn = 0
	await _shot("cabin", Vector3(0, 9.0, 9.0), Vector3(-3, 0, -1))
	# One from the far side (north-east), behind the fence: it must walk round.
	var far: Dictionary = _h.add_zombie_inside(Vector3(9.0, 0, -11.0), "", 99999.0)
	far["state"] = "approach"
	far["window"] = "w1"
	far["room"] = "cabin"
	var went_through := false
	var hit_wall := false
	Engine.time_scale = 4.0
	var t2 := 0.0
	while far["state"] == "approach" and t2 < 40.0:
		await _wait(0.25)
		t2 += 0.25
		var c: int = _h._cell_of(far["pos"])
		if c >= 0 and _h._blocked[c] == 1:
			hit_wall = true
		if _h._room_at(far["pos"]) == "cabin":
			went_through = true
	Engine.time_scale = 1.0
	_check("from the far side it walks round to the window", far["state"] == "tear", [far["state"], far["pos"], t2])
	_check("never through a wall, the fence or the woodpile", not hit_wall and not went_through)
	var sp: Vector3 = _h._spawn_spot(_h._map["windows"][0])
	_check("new ones come up at the spawns in the wood", _h._room_at(sp).is_empty()
		and _h._map["spawns"].any(func(q): return Vector3(q[0], 0, q[1]).distance_to(sp) < 1.5), sp)
	_clear_dead()
	_run({"cmd": "holdout_stop"})

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
