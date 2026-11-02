extends SlopitectModule

# Slopitect live module: holdout, the "Rotwood Holdout" game.
# Round-based survival against the walking dead, in an old roofless hunting
# lodge deep in a dark wood. Each round more of them come, tougher and
# faster. They climb out of the ground outside, tear the boards off the
# lodge's windows and come in after you. Hold out as many rounds as you can.
#
# Points: 10 for every hit that doesn't kill, 60 for a kill, 100 for a
# kill to the head, 130 for a knife kill, 10 for each board you nail back
# on a window (up to 400 a round). You start with 500 and a Nailer pistol.
# Spend points on:
#   - guns on the walls (chalk outlines with a price): buy one, or its ammo
#     for half the price once you have it. You carry two; a third replaces
#     the one in your hand.
#   - the debris in the doorway to the Back Yard (the first map has one
#     barrier): clearing it opens the yard, and the dead come in through
#     its windows too from then on.
#   - the Lucky Crate (950): a random gun, some found nowhere else. It
#     shuffles, then offers one for a few seconds: take it or lose it.
#   - tonics from the old machines along the walls: Ironbark (more health),
#     Quickhands (faster reloads), Rattle Rum (faster shooting), Mending
#     Moss (heal sooner and faster). You keep them until the game ends.
# Your health comes back after a few seconds without a hit; with none left
# the game is over, and the best round per difficulty is kept.
#
# Controls (through controls.gd's actions, only while a game runs):
#   right trigger ("point") shoot; held for automatic guns
#   A ("right_a") buy, open, take, and held at a window, nail boards back
#   B ("right_b") reload (also on its own when the gun is empty)
#   Y ("left_y") switch guns
#   swing the left hand through one: the knife
# The guns ride on the right controller, pointing where it points (the
# controller follows the aim pose, so no turn is needed); the knife on the
# left. The round, points and health are on the left wrist, the ammo on
# the gun. Walls keep you in the open rooms (you're nudged back).
#
# Its own world: like Rhythm Sabers, the game has one world of its own,
# "holdout" (a project, projects.gd), made the first time. The Menu's
# Holdout tile, Start, or holdout_start takes you there (saving the world
# you were in) and opens the game's window; Leave takes you back. In the
# world the sky, sun and floor give way to the night wood and the lodge
# (put back when you leave or the module unloads). Without projects.gd it
# plays where you stand.
#
# Quest 1: every one of the dead is one instance of one MultiMesh (one draw
# for all of them), pooled; the walls are one MultiMesh, the trees two;
# no real lights (glowing materials and ambient light only); shots are
# rays tested against simple shapes (no physics bodies); sounds are made
# in code once at load and played through audio.gd (its own players
# without it). Nothing runs while no game is on.
#
# Signals: started(), stopped(), round_started(number),
# game_over(results), points_changed(points).

signal started()
signal stopped()
signal round_started(number: int)
signal game_over(results: Dictionary)
signal points_changed(points: int)

const TITLE := "Rotwood Holdout"
const PANEL := "holdout"
const PANEL_SIZE := Vector2(0.8, 0.7)
const WORLD := "holdout"
const SETTINGS_PATH := "user://holdout.json"
const DEFAULTS := {"map": "cabin", "difficulty": "normal", "max_zombies": 12, "sounds": true}
const DIFFICULTIES := ["easy", "normal", "hard"]
const DIFF_LABELS := {"easy": "Easy", "normal": "Normal", "hard": "Hard"}
const DIFF_HEALTH := {"easy": 0.7, "normal": 1.0, "hard": 1.4}
const DIFF_HIT := {"easy": 30.0, "normal": 45.0, "hard": 60.0}
const MAX_ZOMBIES := [6, 20]
# Sprint: hold the left grip while you walk. It runs out and comes back
# after a short rest.
const SPRINT_BOOST := 1.7        # times your walking speed
const SPRINT_TIME := 4.0         # seconds of it, full
const SPRINT_REST := 1.5         # seconds of not sprinting before it comes back
const POOL := 20                 # the most of the dead there can be at once

# --- The maps (metres; x right, z toward you; you start at 0, 0 facing -z) ---
# A map is data: rooms are [x, z, width, depth] on the ground ("start" is
# the room you begin in, "outdoor" rooms get a dirt floor); doors join two
# rooms; windows sit on a wall with "out" the way out of the room; things on
# the walls have "in", the way into the room. "lanterns" glow on the walls
# and "clearing" [x0, z0, x1, z1] is kept free of trees; the dead find
# their way across it (see Pathing). They rise at the "spawns" and walk
# round the "obstacles" [x, z, width, depth, height] to a window. The
# Holdout window lists every map in MAP_ORDER; add a map here and it shows
# up there.
const MAPS := {
	"cabin": {
		"name": "Rotwood Cabin",
		"about": "One room, one window: everything is inside with you.",
		"start": "cabin",
		"outdoor": [],
		"rooms": {"cabin": [-5.0, -5.0, 10.0, 10.0]},
		"room_names": {"cabin": "Cabin"},
		"doors": [],
		"windows": [
			{"id": "w1", "room": "cabin", "at": [-5.0, -2.0], "out": [-1.0, 0.0]},
		],
		"wall_guns": [
			{"gun": "double_barrel", "at": [-5.0, 1.5], "in": [1.0, 0.0]},
			{"gun": "mp5", "at": [-3.0, -5.0], "in": [0.0, 1.0]},
			{"gun": "m14", "at": [5.0, -3.0], "in": [-1.0, 0.0]},
			{"gun": "ak47", "at": [-3.2, 5.0], "in": [0.0, -1.0]},
			{"gun": "kar98k", "at": [-5.0, -4.0], "in": [1.0, 0.0]},
			{"gun": "thompson", "at": [4.35, -5.0], "in": [0.0, 1.0]},
		],
		"tonics": [
			{"tonic": "rattle_rum", "at": [-5.0, 3.6], "in": [1.0, 0.0]},
			{"tonic": "quickhands", "at": [5.0, -0.9], "in": [-1.0, 0.0]},
			{"tonic": "mending_moss", "at": [5.0, 1.3], "in": [-1.0, 0.0]},
			{"tonic": "ironbark", "at": [5.0, 3.5], "in": [-1.0, 0.0]},
		],
		"second_wind": {"tonic": "second_wind", "at": [-0.8, -5.0], "in": [0.0, 1.0]},
		"crate": {"at": [2.6, -5.0], "in": [0.0, 1.0]},
		"generator": {"at": [-0.8, 5.0], "in": [0.0, -1.0]},
		"anvil": {"at": [1.5, 5.0], "in": [0.0, -1.0]},
		"bench": {"at": [3.6, 5.0], "in": [0.0, -1.0]},
		"parts": [[3.9, -3.9], [-3.9, 3.9], [0.6, 1.8]],
		"lanterns": [[-4.85, 2.2, -3.6], [4.85, 2.2, 2.4], [0.0, 2.2, -4.85], [0.0, 2.2, 4.85]],
		"clearing": [-13.0, -13.0, 13.0, 13.0],
		# Round the back and the sides: those from the far side walk round.
		"spawns": [[-11.5, -9.0], [-11.5, 5.0], [-4.0, -11.5], [-3.0, 11.5], [9.0, -11.0], [11.0, 9.0]],
		# A woodpile and a cart by the window, a fence along the north side.
		"obstacles": [[-8.2, -4.4, 1.0, 2.4, 1.1], [-7.8, 1.4, 1.4, 1.0, 1.0], [0.5, -8.0, 7.0, 0.15, 1.1]],
	},
	"lodge": {
		"name": "Rotwood Lodge",
		"about": "The Great Hall and the Back Yard, one barrier between them.",
		"start": "hall",
		"outdoor": ["yard"],
		"rooms": {
			"hall": [-4.0, -4.0, 8.0, 8.0],
			"yard": [-4.0, 4.0, 8.0, 6.0],
		},
		"room_names": {"hall": "Great Hall", "yard": "Back Yard"},
		"doors": [
			{"id": "yard_door", "rooms": ["hall", "yard"], "at": [0.0, 4.0], "cost": 1000},
		],
		"windows": [
			{"id": "w1", "room": "hall", "at": [-2.0, -4.0], "out": [0.0, -1.0]},
			{"id": "w2", "room": "hall", "at": [-4.0, 1.5], "out": [-1.0, 0.0]},
			{"id": "w3", "room": "hall", "at": [4.0, 0.3], "out": [1.0, 0.0]},
			{"id": "w4", "room": "yard", "at": [4.0, 5.2], "out": [1.0, 0.0]},
			{"id": "w5", "room": "yard", "at": [-4.0, 7.0], "out": [-1.0, 0.0]},
			{"id": "w6", "room": "yard", "at": [0.0, 10.0], "out": [0.0, 1.0]},
		],
		"wall_guns": [
			{"gun": "double_barrel", "at": [-4.0, -2.0], "in": [1.0, 0.0]},
			{"gun": "mp5", "at": [4.0, -2.6], "in": [-1.0, 0.0]},
			{"gun": "m14", "at": [4.0, 2.6], "in": [-1.0, 0.0]},
			{"gun": "ak47", "at": [-2.4, 4.0], "in": [0.0, 1.0]},
			{"gun": "kar98k", "at": [0.4, -4.0], "in": [0.0, 1.0]},
			{"gun": "remington870", "at": [-4.0, -3.3], "in": [1.0, 0.0]},
			{"gun": "thompson", "at": [4.0, 9.2], "in": [-1.0, 0.0]},
		],
		"tonics": [
			{"tonic": "quickhands", "at": [-2.6, 4.0], "in": [0.0, -1.0]},
			{"tonic": "rattle_rum", "at": [-4.0, 5.2], "in": [1.0, 0.0]},
			{"tonic": "mending_moss", "at": [2.4, 10.0], "in": [0.0, -1.0]},
			{"tonic": "ironbark", "at": [-4.0, 8.8], "in": [1.0, 0.0]},
		],
		"second_wind": {"tonic": "second_wind", "at": [2.4, -4.0], "in": [0.0, 1.0]},
		"crate": {"at": [4.0, 7.4], "in": [-1.0, 0.0]},
		"generator": {"at": [-2.4, 10.0], "in": [0.0, -1.0]},
		"anvil": {"at": [2.4, 4.0], "in": [0.0, 1.0]},
		"bench": {"at": [2.2, 4.0], "in": [0.0, -1.0]},
		"parts": [[3.3, -3.3], [-3.2, 3.3], [3.2, 9.2]],  # where the shield's three parts lie
		"lanterns": [[-3.85, 2.2, -2.8], [3.85, 2.2, 1.5], [-3.85, 2.2, 6.2], [0.0, 2.2, -3.85]],
		"clearing": [-11.0, -11.0, 15.0, 16.0],
		"spawns": [[-8.0, -9.0], [6.0, -9.0], [-9.5, 1.0], [10.0, 0.0], [-9.5, 9.0], [10.0, 7.0], [-2.0, 14.0], [6.0, 14.0]],
		"obstacles": [[-7.0, -4.0, 1.0, 2.2, 1.1], [7.5, 4.5, 1.4, 1.0, 1.0]],
	},
}
const MAP_ORDER := ["cabin", "lodge"]
const WALL_H := 3.0
const WALL_T := 0.2
const DOOR_W := 1.6
const DOOR_H := 2.3
const WINDOW_W := 1.2
const SILL := 0.9
const LINTEL := 2.0
const PLANKS := 5

# --- Guns -------------------------------------------------------------------------
# damage per pellet, rate (seconds between shots), mag, reserve, reload
# (seconds), pellets, spread (degrees), auto, cost (on a wall; 0 = crate
# only), pierce (how many it goes through), splash (radius, m), chain (how
# many more it jumps to), chill (seconds slowed), colour, len (m).
const GUNS := {
	"m1911": {"name": "M1911", "damage": 40.0, "rate": 0.22, "mag": 8, "reserve": 64, "reload": 1.4, "pellets": 1, "spread": 1.0,
		"auto": false, "cost": 0, "pierce": 1, "len": 0.2},
	"double_barrel": {"name": "Double Barrel", "damage": 34.0, "rate": 0.35, "mag": 2, "reserve": 36, "reload": 2.0, "pellets": 8, "spread": 6.5,
		"auto": false, "cost": 500, "pierce": 1, "len": 0.5},
	"mp5": {"name": "MP5", "damage": 30.0, "rate": 0.075, "mag": 30, "reserve": 180, "reload": 1.8, "pellets": 1, "spread": 2.5,
		"auto": true, "cost": 1000, "pierce": 1, "len": 0.32},
	"m14": {"name": "M14", "damage": 80.0, "rate": 0.17, "mag": 20, "reserve": 120, "reload": 2.0, "pellets": 1, "spread": 0.8,
		"auto": false, "cost": 1200, "pierce": 1, "len": 0.6},
	"ak47": {"name": "AK-47", "damage": 50.0, "rate": 0.1, "mag": 30, "reserve": 180, "reload": 2.3, "pellets": 1, "spread": 1.8,
		"auto": true, "cost": 1500, "pierce": 1, "len": 0.52},
	"python": {"name": "Python", "damage": 160.0, "rate": 0.4, "mag": 6, "reserve": 48, "reload": 2.6, "pellets": 1, "spread": 0.5,
		"auto": false, "cost": 0, "pierce": 2, "len": 0.26},
	"m60": {"name": "M60", "damage": 60.0, "rate": 0.09, "mag": 100, "reserve": 400, "reload": 3.6, "pellets": 1, "spread": 2.2,
		"auto": true, "cost": 0, "pierce": 2, "len": 0.62},
	"barrett": {"name": "Barrett M82", "damage": 500.0, "rate": 0.8, "mag": 10, "reserve": 40, "reload": 3.0, "pellets": 1, "spread": 0.0,
		"auto": false, "cost": 0, "pierce": 5, "len": 0.85},
	"rpg7": {"name": "RPG-7", "damage": 700.0, "rate": 1.0, "mag": 1, "reserve": 12, "reload": 2.4, "pellets": 1, "spread": 0.0,
		"auto": false, "cost": 0, "pierce": 1, "splash": 3.0, "len": 0.78},
	"thunderjug": {"name": "Thunderjug", "damage": 400.0, "rate": 0.45, "mag": 12, "reserve": 60, "reload": 2.4, "pellets": 1, "spread": 0.0,
		"auto": false, "cost": 0, "pierce": 1, "chain": 4, "len": 0.34},
	"frostbite": {"name": "Frostbite", "damage": 150.0, "rate": 0.3, "mag": 15, "reserve": 75, "reload": 2.0, "pellets": 1, "spread": 0.0,
		"auto": false, "cost": 0, "pierce": 1, "chill": 4.0, "len": 0.36},
	# More you'll know: on the walls...
	"kar98k": {"name": "Kar98k", "damage": 150.0, "rate": 1.1, "mag": 5, "reserve": 50, "reload": 2.6, "pellets": 1, "spread": 0.3,
		"auto": false, "cost": 600, "pierce": 2, "len": 0.62},
	"thompson": {"name": "Thompson", "damage": 40.0, "rate": 0.085, "mag": 30, "reserve": 160, "reload": 2.2, "pellets": 1, "spread": 2.8,
		"auto": true, "cost": 1200, "pierce": 1, "len": 0.45},
	"remington870": {"name": "Remington 870", "damage": 30.0, "rate": 0.55, "mag": 6, "reserve": 48, "reload": 3.0, "pellets": 8, "spread": 5.5,
		"auto": false, "cost": 900, "pierce": 1, "len": 0.55},
	# ...and in the crate.
	"galil": {"name": "Galil", "damage": 55.0, "rate": 0.09, "mag": 35, "reserve": 245, "reload": 2.6, "pellets": 1, "spread": 1.6,
		"auto": true, "cost": 0, "pierce": 1, "len": 0.5},
	"spas12": {"name": "SPAS-12", "damage": 32.0, "rate": 0.3, "mag": 8, "reserve": 48, "reload": 3.0, "pellets": 8, "spread": 6.0,
		"auto": false, "cost": 0, "pierce": 1, "len": 0.55},
	"deagle": {"name": "Desert Eagle", "damage": 120.0, "rate": 0.3, "mag": 7, "reserve": 49, "reload": 1.6, "pellets": 1, "spread": 0.6,
		"auto": false, "cost": 0, "pierce": 2, "len": 0.24},
	"mp40": {"name": "MP40", "damage": 35.0, "rate": 0.11, "mag": 32, "reserve": 192, "reload": 2.0, "pellets": 1, "spread": 2.4,
		"auto": true, "cost": 0, "pierce": 1, "len": 0.4},
	# Our own odd ones, crate only, like the Thunderjug and Frostbite.
	# Emberwick sets the dead alight (it spreads to those next to them);
	# Gravebell's toll throws back everything in front of you; Rootsnare
	# holds them where they stand.
	"emberwick": {"name": "Emberwick", "damage": 120.0, "rate": 0.35, "mag": 10, "reserve": 60, "reload": 2.2, "pellets": 1, "spread": 0.0,
		"auto": false, "cost": 0, "pierce": 1, "burn": 5.0, "len": 0.4},
	"gravebell": {"name": "Gravebell", "damage": 220.0, "rate": 0.6, "mag": 4, "reserve": 24, "reload": 2.6, "pellets": 1, "spread": 0.0,
		"auto": false, "cost": 0, "pierce": 1, "cone": 4.5, "knock": 2.5, "len": 0.42},
	"rootsnare": {"name": "Rootsnare", "damage": 100.0, "rate": 0.35, "mag": 12, "reserve": 60, "reload": 2.0, "pellets": 1, "spread": 0.0,
		"auto": false, "cost": 0, "pierce": 2, "snare": 5.0, "len": 0.38},
}
# What each becomes on The Anvil: our own names.
const FORGED_NAMES := {
	"m1911": "Ember .45", "double_barrel": "Two-Bit Thunder", "mp5": "Wasp Nest", "m14": "Long Night", "ak47": "Red Harvest",
	"python": "Copperhead", "m60": "Lead Rain", "barrett": "Last Word", "rpg7": "Housewarmer", "thunderjug": "Stormcellar",
	"frostbite": "Deep Winter", "kar98k": "Old Faithful", "thompson": "Gangland", "remington870": "Barn Burner", "galil": "Desert Wind",
	"spas12": "Doorkicker", "deagle": "Hand Cannon", "mp40": "Night Shift", "emberwick": "Wildfire", "gravebell": "Deathknell",
	"rootsnare": "Old Growth",
}
const BURN_DPS := 60.0           # Emberwick's fire, health a second
const BELL_DEGREES := 35.0       # Gravebell's toll reaches this far each side of where you aim
# Real guns you'll know, plus our own odd ones in the crate.
const CRATE_GUNS := ["double_barrel", "mp5", "m14", "ak47", "python", "m60", "barrett", "rpg7", "thunderjug", "frostbite",
	"kar98k", "thompson", "remington870", "galil", "spas12", "deagle", "mp40", "emberwick", "gravebell", "rootsnare"]
const CRATE_COST := 950
const CRATE_SHUFFLE := 2.4       # seconds it shuffles
const CRATE_OFFER := 8.0         # seconds it offers the gun
const TONICS := {
	"ironbark": {"name": "Ironbark", "cost": 2500, "color": Color(0.85, 0.5, 0.15), "does": "250 health"},
	"quickhands": {"name": "Quickhands", "cost": 3000, "color": Color(0.2, 0.75, 0.35), "does": "reload twice as fast"},
	"rattle_rum": {"name": "Rattle Rum", "cost": 2000, "color": Color(0.8, 0.15, 0.2), "does": "shoot a third faster"},
	"mending_moss": {"name": "Mending Moss", "cost": 1500, "color": Color(0.35, 0.55, 0.9), "does": "heal sooner and faster"},
	"second_wind": {"name": "Second Wind", "cost": 500, "color": Color(0.95, 0.9, 0.3), "does": "get back up once (no power needed)"},
}
const NO_POWER_TONICS := ["second_wind"]  # works before the generator runs
const SECOND_WINDS := 3          # times a game it can be bought
const DOWN_TIME := 5.0           # seconds you're down before getting up
const DOWN_PUSH := 2.5           # the dead are pushed back this far as you fall
# The Anvil: makes the gun in your hand stronger (needs power).
const ANVIL_COST := 5000
const ANVIL_TIME := 3.0          # seconds it works
const ANVIL_OFFER := 10.0        # seconds to take it back
const FORGED_AMMO_COST := 2500   # a forged gun's ammo off its wall
# Drops: a killed one sometimes leaves one behind; walk over it to take it.
const DROPS := {
	"ammo": {"name": "Ammo Cache", "color": Color(0.4, 0.9, 0.4)},
	"one_shot": {"name": "One Shot", "color": Color(0.95, 0.3, 0.25)},
	"double_pay": {"name": "Double Pay", "color": Color(1.0, 0.85, 0.2)},
	"blackout": {"name": "Blackout", "color": Color(0.7, 0.5, 1.0)},
	"hammer": {"name": "Hammer & Nails", "color": Color(0.9, 0.6, 0.3)},
}
# A drop is earned by scoring: each time the points earned pass a goal
# (2000 at first, each gap 14% bigger than the last) one is "ready", and
# kills then release it (DROP_READY_CHANCE each); besides that, any kill
# has a small chance. Which kind comes from a shuffled deck, dealt in turn,
# so you see every kind before one comes twice.
const DROP_GOAL := 2000
const DROP_GOAL_GROWTH := 1.14
const DROP_READY_CHANCE := 0.35
const DROP_CHANCE := 0.02
const SPAWN_GAP := 2.0
const SPAWN_GAP_MIN := 0.25
const STUCK_TIME := 8.0          # a chasing one that's hardly moved this long goes back outside
const STUCK_MOVE := 0.5
const DROPS_A_ROUND := 4
const DROP_LIFE := 25.0
const DROP_REACH := 1.0
const DROP_EFFECT := 30.0        # seconds One Shot and Double Pay last
# The Barn-Door Shield: three parts, built at the workbench, worn on the
# left arm; it takes the hits from in front of it until it breaks.
const SHIELD_BLOCKS := 6
const SHIELD_REBUILD := 500
const SHIELD_FACING := 0.3       # how square on to the shield a hit must be

# --- You and the dead ---------------------------------------------------------------
const START_POINTS := 500
const HEALTH := 100.0
const IRON_HEALTH := 250.0
const REGEN_AFTER := 4.0
const REGEN_RATE := 60.0         # health a second
const ATTACK_RANGE := 1.1
const ATTACK_TIME := 1.2         # seconds between one zombie's swipes
const SWING_TIME := 0.65         # a swipe's wind-up: it rears back, then lunges; step out of reach to dodge it
const SWING_BACK := 0.3          # seconds it takes to straighten up after
const REACH := 1.4               # metres from a thing you can use it
const REPAIR_TIME := 0.7         # seconds a board
const REPAIR_CAP := 400          # points a round for boards
const TEAR_TIME := 1.6           # seconds a board, walking
const SPEEDS := {"walk": 0.75, "jog": 1.35, "run": 1.9}
const HEAD_Y := 1.58
const HEAD_R := 0.16
const BODY_FROM := 0.3
const BODY_TO := 1.25
const BODY_R := 0.25
const RISE_TIME := 1.2
const CLIMB_TIME := 1.0
const DIE_TIME := 1.4
const ROUND_BREAK := 9.0
const FIRST_BREAK := 3.0
const KNIFE_SPEED := 2.4         # m/s the left hand must swing
const KNIFE_REACH := 0.45
const KNIFE_DAMAGE := 150.0
const KNIFE_TIME := 0.5
const MARGIN := 0.3              # how near a wall you can stand
const ZOMBIE_GAP := 0.55         # the dead keep this far apart
const MAX_RANGE := 60.0

var running := false
var settings := DEFAULTS.duplicate(true)
var best := {}                   # difficulty -> best round

var points := 0
var round_number := 0
var health := HEALTH
var kills := 0
var headshots := 0
var earned := 0
var guns: Array = []             # [{"id", "mag", "reserve"}]
var gun_index := 0
var tonics: Array = []
var open_rooms := {"cabin": true}   # set from the map at each start
var planks := {}                 # window id -> boards on it
var results := {}
var power := false
var parts := []                  # the shield's parts found (indexes into _map["parts"])
var shield := 0                  # blocks the shield has left (0: none worn)
var shield_built := false        # built once this game (rebuilt for points after)
var effects := {}                # "one_shot" / "double_pay" -> seconds left
var downed := false
var second_winds := 0

var _lib: SlopitectModule
var _controls: SlopitectModule
var _audio: SlopitectModule
var _arena: Node3D               # the lodge, laid out where you stood
var _swapped := {}
var _zombie_mm: MultiMesh
var _zombies: Array = []         # active: {"slot", "state", "pos", "yaw", "hp", "speed", "room", "window", "t", "cd", "chill", "groan", "flash", "y"}
var _free_slots: Array = []
var _walls: Array = []           # AABBs (lodge space) shots stop at
var _plank_nodes := {}           # window id -> [MeshInstance3D]
var _debris := {}                # door id -> Node3D
var _uses: Array = []            # what A can work on: {"kind", "id", "at" (Vector3), "label" (Label3D or null)}
var _prompt: Label3D
var _sign: Label3D               # "Round 3"
var _sign_left := 0.0
var _crate_label: Label3D
var _crate_state := "idle"       # idle, shuffle, offer
var _crate_t := 0.0
var _crate_gun := ""
var _crate_show: MeshInstance3D  # the gun over the crate
var _gun_node: Node3D
var _gun_mesh: MeshInstance3D
var _flash: MeshInstance3D
var _ammo_label: Label3D
var _knife: Node3D
var _wrist: Label3D
var _hurt: MeshInstance3D        # red around your eyes when hit
var _tracer: MeshInstance3D
var _tracer_left := 0.0
var _boom: MeshInstance3D
var _boom_left := 0.0
var _hidden_boxes: Array = []
var _gun_meshes := {}
var _mats := {}
var _sounds := {}
var _players: Array = []         # without audio.gd
var _next_player := 0
var _rng := RandomNumberGenerator.new()
var _to_spawn := 0
var _spawn_t := 0.0
var _break_t := 0.0
var _round_hp := 150.0
var _repair_points := 0
var _cooldown := 0.0
var _reload_t := 0.0
var _trigger := false
var _use_held := false
var _repair_t := 0.0
var _use_target := {}
var _use_scan := 0.0
var _hit_t := 99.0               # seconds since you were last hit
var _player_room := "cabin"
var _map: Dictionary = MAPS["cabin"]   # the map being played (settings["map"])
var _held := false               # the game waits while its window is open
var _sprint_held := false        # the left grip is held
var _sprinting := false          # controls.gd's speed_boost is on
var _stamina := SPRINT_TIME      # seconds of sprint left
var _rest_t := 0.0               # seconds since the last sprint
# Pathing (see the Pathing section): the clearing as a grid of CELL squares.
var _grid_at := Vector2.ZERO     # the grid's corner (lodge space x, z)
var _gw := 0                     # cells across (x)
var _gh := 0                     # cells deep (z)
var _blocked := PackedByteArray()  # 1: a wall, sill or obstacle is here
var _cell_room := PackedInt32Array()  # the room a cell is in (index in rooms), -1 outside
var _out_fields := {}            # window id -> steps to that window from each outside cell
var _in_field := PackedInt32Array()  # steps to you from each cell of the open rooms
var _in_from := -2               # the cell _in_field leads to
var _in_dirty := true            # a door opened: make _in_field again
var _knife_prev := Vector3.ZERO
var _knife_cd := 0.0
var _groan_cd := 0.0
var _return_to := ""
var _wrist_text := ""
var _down_t := 0.0
var _drops: Array = []           # {"kind", "node", "pos", "life"}
var _drops_round := 0
var _drop_goal := float(DROP_GOAL)
var _drop_gap := float(DROP_GOAL)
var _drop_ready := false
var _drop_deck: Array = []
var _anvil_state := "idle"       # idle, working, offer
var _anvil_t := 0.0
var _anvil_gun := {}             # the gun on the Anvil
var _anvil_label: Label3D
var _anvil_show: MeshInstance3D
var _generator_label: Label3D
var _power_lamps: Array = []     # glow on the tonic machines and Anvil once the power's on
var _part_nodes: Array = []
var _shield_node: Node3D
var _up_specs := {}


func setup() -> String:
	register("holdout_start", _start, "start a game of Rotwood Holdout (goes to its world first): optional map (lodge), difficulty (easy, normal, hard), round (the round to start on, 1 to 50)")
	register("holdout_stop", _stop, "end the game that's on")
	register("holdout_status", _status, "the game: round, points, health, guns and ammo, tonics, open rooms, boards on each window, the dead alive and still to come, kills; after a game, its results")
	register("holdout_set", _set_command, "the game's settings (usable in the headset): any of map (lodge; not during a game), difficulty (easy, normal, hard), max_zombies (6 to 20 at once), sounds (true/false)")
	register("holdout_do", _do, "the Holdout window: act = toggle (goes to the Holdout world first; during a game the game waits while it's open), show, hide (back to the game), start, leave")
	register("holdout_leave", _leave, "end the game and go back from the Holdout world to the world you came from")
	_rng.randomize()
	_make_materials()
	_make_sounds()
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	set_process(false)
	return ""


func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		_controls = null
		_audio = null
		return
	_load_settings()
	lib.watch(self, "controls", _controls_here, _controls_gone)
	lib.watch(self, "audio", _audio_here, _audio_gone)
	lib.follow(self, "projects", "project_changed", _on_world_changed)
	for ui_name in ["vrui", "ui"]:
		lib.follow(self, ui_name, "panel_shown", _panel_shown)
	if _projects() != null and in_world():  # loaded while already in the Holdout world
		_stage_on()
	lib.touch(self)


func _controls_here(controls: SlopitectModule) -> void:
	_controls = controls


func _controls_gone(_old: SlopitectModule) -> void:
	_controls = null
	_sprinting = false  # its boost went with it


func _audio_here(audio: SlopitectModule) -> void:
	_audio = audio


func _audio_gone(_old: SlopitectModule) -> void:
	_audio = null


func _exit_tree() -> void:
	_end_game(false)
	_sprint(false)
	_stage_off()
	ctx["server"].run({"cmd": "ui_remove", "id_panel": PANEL})


# --- Menu, Settings and the window ------------------------------------------------

func menu_info() -> Dictionary:
	return {"id": "holdout", "label": "Holdout", "order": 61, "action": {"cmd": "holdout_do", "act": "toggle"}}


# The hand menu's way in and out: opens the Holdout window (taking you to
# its world first); during a game it's the game's menu, and the game waits.
func hand_info() -> Dictionary:
	return {"id": "holdout", "label": "Holdout", "order": 61, "action": {"cmd": "holdout_do", "act": "toggle"}}


func settings_info() -> Dictionary:
	var maps := []
	for m in MAP_ORDER:
		maps.append({"label": MAPS[m]["name"], "value": m})
	var diffs := []
	for d in DIFFICULTIES:
		diffs.append({"label": DIFF_LABELS[d], "value": d})
	return {"title": TITLE, "order": 46, "settings": [
		{"id": "map", "type": "choice", "label": "Map", "value": settings["map"], "options": maps, "columns": 2,
			"set": {"cmd": "holdout_set", "map": "{value}"}},
		{"id": "difficulty", "type": "choice", "label": "Difficulty", "value": settings["difficulty"], "options": diffs, "columns": 3,
			"set": {"cmd": "holdout_set", "difficulty": "{value}"}},
		{"id": "max_zombies", "type": "slider", "label": "Most of the dead at once", "min": MAX_ZOMBIES[0], "max": MAX_ZOMBIES[1], "step": 1.0,
			"value": settings["max_zombies"], "set": {"cmd": "holdout_set", "max_zombies": "{value}"}},
		{"id": "sounds", "type": "toggle", "label": "Game sounds", "value": settings["sounds"],
			"set": {"cmd": "holdout_set", "sounds": "{value}"}},
		{"id": "start", "type": "button", "label": "Start a game", "set": {"cmd": "holdout_start"}},
		{"id": "stop", "type": "button", "label": "End the game", "set": {"cmd": "holdout_stop"}},
		{"id": "leave", "type": "button", "label": "Leave the Holdout world", "set": {"cmd": "holdout_leave"}},
	]}


# Before vrui.gd (0), whose window toggles are on A and B and Y too (the
# terminal, tools and chat windows), and before doors.gd (-5); after pause
# (-10), so the hand menu still opens. Only while a game is on, and the
# trigger is left to vrui while you point at a window.
func action_order() -> int:
	return -6


func on_action(action: String, down: bool) -> bool:
	if not running or _held:
		return false  # the window has the buttons while the game waits
	match action:
		"point":
			if down and _pointing_at_window():
				return false
			_trigger = down
			if down:
				_fire()
			return true
		"right_a":
			_use_held = down
			_repair_t = 0.0
			if down:
				_use()
			return true
		"right_b":
			if down:
				_reload()
			return true
		"left_y":
			if down:
				_switch_gun()
			return true
		"grab_left":
			_sprint_held = down
			return true
	return false


func _pointing_at_window() -> bool:
	var ui: SlopitectModule = _lib.module("vrui") if _lib else null
	return ui != null and ui.has_method("pointing") and not String(ui.call("pointing")).is_empty()


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


func _has_ui() -> bool:
	return ctx["modules"].module("vrui") != null or ctx["modules"].module("ui") != null


func _do(request: Dictionary) -> Dictionary:
	match request.get("act"):
		"toggle":
			if in_world() and _shown():
				_hide_window()
				return {"ok": true, "shown": false}
			var problem := _enter()
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			return _show_window()
		"show":
			return _show_window()
		"hide":
			_hide_window()
			return {"ok": true, "shown": false}
		"start":
			return _start({})
		"leave":
			return _leave({})
	return {"ok": false, "error": "\"act\" must be toggle, show, hide, start or leave"}


func _shown() -> bool:
	var got := _run({"cmd": "ui_get", "id_panel": PANEL})
	return got.get("ok", false) and got.get("panel", {}).get("visible", false)


func _show_window() -> Dictionary:
	if not is_inside_tree():
		return {"ok": false, "error": "Holdout is unloading"}
	if not _has_ui():
		return {"ok": false, "error": "the Holdout window needs the vrui module"}
	var problem := _build()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	_run({"cmd": "ui_show", "id_panel": PANEL, "visible": true})
	return {"ok": true, "shown": true}


# The window is the game's menu: while it's open during a game, the game
# waits (the dead stand still, nothing counts down) and the buttons go to
# the window; closing it (Resume, its X, the hand menu) carries on.
func _panel_shown(id_panel: String, on: bool) -> void:
	if id_panel == PANEL:
		_hold(on and running)


func _hold(on: bool) -> void:
	_held = on
	_sprint_held = false
	_sprint(false)
	_trigger = false
	_use_held = false
	set_process(running and not on)
	if running:
		_update_hud()


# The window opens with the world, unless a game started on the way in.
func _show_if_idle() -> void:
	if not running and is_inside_tree():
		_show_window()


func _hide_window() -> void:
	if _has_ui() and _run({"cmd": "ui_get", "id_panel": PANEL}).get("ok", false):
		_run({"cmd": "ui_show", "id_panel": PANEL, "visible": false})


func _build() -> String:
	if not _has_ui():
		return "the Holdout window needs the vrui module"
	var els := []
	var w := PANEL_SIZE.x - 0.08
	var y := PANEL_SIZE.y / 2.0 - 0.07
	var third := [w / 3.0 - 0.02, 0.06]
	els.append({"type": "text", "id": "status", "text": _window_text(), "at": [0.0, y - 0.04], "width": w})
	y -= 0.19
	if running:
		# The game's menu: it waits until you go back.
		els.append({"type": "button", "id": "resume", "label": "Resume", "at": [-w / 3.0, y], "size": third, "color": "ok",
			"action": {"cmd": "holdout_do", "act": "hide"}})
		els.append({"type": "button", "id": "stop", "label": "End game", "at": [0.0, y], "size": third, "color": "notice",
			"action": {"cmd": "holdout_stop"}})
		els.append({"type": "button", "id": "leave", "label": "Leave", "at": [w / 3.0, y], "size": third, "color": "button",
			"action": {"cmd": "holdout_leave"}})
		y -= 0.12
	else:
		# The lobby: pick a map and how hard, then Start.
		els.append({"type": "text", "id": "map_head", "text": "Map", "color": "muted", "at": [0.0, y + 0.065], "width": w})
		for i in MAP_ORDER.size():
			var m: String = MAP_ORDER[i]
			var col := i % 3
			var row := i / 3
			els.append({"type": "button", "id": "map_" + m, "label": MAPS[m]["name"], "at": [(col - 1) * w / 3.0, y - row * 0.07],
				"size": third, "color": "accent" if settings["map"] == m else "button", "action": {"cmd": "holdout_set", "map": m}})
		y -= 0.07 * ceili(MAP_ORDER.size() / 3.0)
		els.append({"type": "text", "id": "map_about", "text": MAPS[settings["map"]]["about"], "color": "muted", "at": [0.0, y + 0.02], "width": w})
		y -= 0.08
		for i in DIFFICULTIES.size():
			var d: String = DIFFICULTIES[i]
			els.append({"type": "button", "id": "diff_" + d, "label": DIFF_LABELS[d], "at": [(i - 1) * w / 3.0, y], "size": [w / 3.0 - 0.02, 0.055],
				"color": "accent" if settings["difficulty"] == d else "button", "action": {"cmd": "holdout_set", "difficulty": d}})
		y -= 0.08
		els.append({"type": "button", "id": "start", "label": "Play again" if not results.is_empty() else "Start", "at": [-w / 6.0, y],
			"size": third, "color": "ok", "action": {"cmd": "holdout_start"}})
		els.append({"type": "button", "id": "leave", "label": "Leave", "at": [w / 6.0, y], "size": third, "color": "button",
			"action": {"cmd": "holdout_leave"}})
		y -= 0.1
	els.append({"type": "text", "id": "help", "color": "muted", "at": [0.0, y], "width": w,
		"text": "Trigger: shoot   A: buy, open, hold to board up\nB: reload   Y: switch guns   Hold left grip: sprint\nSwing left hand: knife"})
	var request := {"id_panel": PANEL, "elements": els}
	if _run({"cmd": "ui_get", "id_panel": PANEL}).get("ok", false):
		request["cmd"] = "ui_update"
	else:
		request.merge({"cmd": "ui_add", "title": TITLE, "size": [PANEL_SIZE.x, PANEL_SIZE.y], "chrome": true, "visible": false})
	var reply := _run(request)
	return "" if reply.get("ok", false) else "%s: %s" % [PANEL, reply.get("error", "couldn't be drawn")]


func _window_text() -> String:
	var diff: String = settings["difficulty"]
	var record := "Best on %s: round %d" % [DIFF_LABELS[diff], int(best.get(diff, 0))] if best.has(diff) else "No rounds held on %s yet" % DIFF_LABELS[diff]
	if running:
		return "%s, round %d, %d points. The game waits while this is open.\n%s" % [_map["name"], round_number, points, record]
	if not results.is_empty():
		return "Overrun on round %d. %d kills (%d to the head), %d points earned.\n%s" % [
			results["round"], results["kills"], results["headshots"], results["earned"], record]
	return "Hold out against the dead, round after round.\n%s" % record


# Switches the map; the buildings are put up again if you're in the world.
func _use_map(id: String) -> void:
	if settings["map"] == id:
		return
	settings["map"] = id
	_map = MAPS[id]
	if _arena != null:
		_stage_off()
		_stage_on()


# --- Settings ----------------------------------------------------------------------

func _set_command(request: Dictionary) -> Dictionary:
	var changed := []
	if request.has("map"):
		if not request["map"] in MAPS:
			return {"ok": false, "error": "\"map\" must be one of %s" % ", ".join(MAP_ORDER)}
		if running and request["map"] != settings["map"]:
			return {"ok": false, "error": "end the game first to change the map"}
		_use_map(request["map"])
		changed.append("map")
	if request.has("difficulty"):
		if not request["difficulty"] in DIFFICULTIES:
			return {"ok": false, "error": "\"difficulty\" must be easy, normal or hard"}
		settings["difficulty"] = request["difficulty"]
		changed.append("difficulty")
	if request.has("max_zombies"):
		var n = request["max_zombies"]
		if typeof(n) == TYPE_STRING and n.is_valid_float():
			n = float(n)
		if typeof(n) not in [TYPE_INT, TYPE_FLOAT] or n < MAX_ZOMBIES[0] or n > MAX_ZOMBIES[1]:
			return {"ok": false, "error": "\"max_zombies\" must be %d to %d" % MAX_ZOMBIES}
		settings["max_zombies"] = int(n)
		changed.append("max_zombies")
	if request.has("sounds"):
		var on = request["sounds"]
		if typeof(on) == TYPE_STRING:
			on = on == "true"
		if typeof(on) != TYPE_BOOL:
			return {"ok": false, "error": "\"sounds\" must be true or false"}
		settings["sounds"] = on
		changed.append("sounds")
	if changed.is_empty():
		return {"ok": false, "error": "give map, difficulty, max_zombies or sounds"}
	_save_settings()
	if _lib:
		_lib.touch(self)
	if _has_ui() and _run({"cmd": "ui_get", "id_panel": PANEL}).get("ok", false):
		_build()
	return {"ok": true, "settings": settings.duplicate(), "changed": changed}


func _load_settings() -> void:
	if _lib == null:
		return
	var got = _lib.read_json(SETTINGS_PATH)
	if typeof(got) != TYPE_DICTIONARY:
		return
	var saved = got.get("settings", {})
	if typeof(saved) == TYPE_DICTIONARY:
		if saved.get("map") in MAPS:
			_use_map(saved["map"])
		if saved.get("difficulty") in DIFFICULTIES:
			settings["difficulty"] = saved["difficulty"]
		if typeof(saved.get("max_zombies")) in [TYPE_INT, TYPE_FLOAT]:
			settings["max_zombies"] = clampi(int(saved["max_zombies"]), MAX_ZOMBIES[0], MAX_ZOMBIES[1])
		if typeof(saved.get("sounds")) == TYPE_BOOL:
			settings["sounds"] = saved["sounds"]
	if typeof(got.get("best")) == TYPE_DICTIONARY:
		best = got["best"]
	if typeof(got.get("return_to")) == TYPE_STRING:
		_return_to = got["return_to"]


func _save_settings() -> void:
	if _lib:
		_lib.write_json(SETTINGS_PATH, {"settings": settings, "best": best, "return_to": _return_to})


# --- Its own world -----------------------------------------------------------------

func _projects() -> SlopitectModule:
	return _lib.module("projects") if _lib else null


func in_world() -> bool:
	return _projects() == null or _run({"cmd": "projects_current"}).get("name") == WORLD


# Takes you to the game's world, making it the first time. "" or what went wrong.
func _enter() -> String:
	if _projects() == null:
		_stage_on()
		return ""
	var here = _run({"cmd": "projects_current"}).get("name", "")
	if here == WORLD:
		_stage_on()
		return ""
	var exists: bool = _run({"cmd": "projects_list"}).get("projects", []).any(func(p): return p.get("name") == WORLD)
	var before := _return_to
	_return_to = here
	var reply: Dictionary
	if exists:
		reply = _run({"cmd": "projects_open", "name": WORLD})
	else:
		reply = _run({"cmd": "projects_new", "name": WORLD, "modules": ["holdout"], "open": true})
	if not reply.get("ok", false):
		_return_to = before
		return "couldn't open the Holdout world: %s" % reply.get("error", "?")
	_save_settings()
	_stage_on()  # project_changed does it too; this is for the window that opens now
	return ""


func _leave(_request: Dictionary) -> Dictionary:
	_end_game(false)
	_hide_window()
	if _projects() == null:
		_stage_off()
		return {"ok": true}
	if not in_world():
		return {"ok": true}
	var back := _return_to if not _return_to.is_empty() and _return_to != WORLD else "start"
	var reply := _run({"cmd": "projects_open", "name": back})
	if not reply.get("ok", false) and back != "start":
		back = "start"
		reply = _run({"cmd": "projects_open", "name": back})
	if not reply.get("ok", false):
		return {"ok": false, "error": "couldn't go back to %s: %s" % [back, reply.get("error", "?")]}
	_return_to = ""
	_save_settings()
	return {"ok": true, "back_in": back}


func _on_world_changed(project: String, _folder: String) -> void:
	if project == WORLD:
		_stage_on()
		_show_if_idle.call_deferred()
	else:
		_end_game(false)
		_hide_window()
		_stage_off()


# --- Starting and ending -------------------------------------------------------------

func _start(request: Dictionary) -> Dictionary:
	if request.has("map"):
		if not request["map"] in MAPS:
			return {"ok": false, "error": "\"map\" must be one of %s" % ", ".join(MAP_ORDER)}
		if not running:
			_use_map(request["map"])
		elif request["map"] != settings["map"]:
			_end_game(false)
			_use_map(request["map"])
		_save_settings()
	if request.has("difficulty"):
		if not request["difficulty"] in DIFFICULTIES:
			return {"ok": false, "error": "\"difficulty\" must be easy, normal or hard"}
		settings["difficulty"] = request["difficulty"]
		_save_settings()
	var first := 1
	if request.has("round"):
		var r = request["round"]
		if typeof(r) not in [TYPE_INT, TYPE_FLOAT] or r < 1 or r > 50:
			return {"ok": false, "error": "\"round\" must be 1 to 50"}
		first = int(r)
	var problem := _enter()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	_end_game(false)
	_stage_on()
	_reset_lodge()
	points = START_POINTS
	_stamina = SPRINT_TIME
	health = HEALTH
	kills = 0
	headshots = 0
	earned = 0
	tonics.clear()
	power = false
	parts.clear()
	shield = 0
	shield_built = false
	effects.clear()
	downed = false
	second_winds = 0
	_drop_goal = float(DROP_GOAL)
	_drop_gap = float(DROP_GOAL)
	_drop_ready = false
	_drop_deck.clear()
	_anvil_state = "idle"
	guns = [{"id": "m1911", "mag": GUNS["m1911"]["mag"], "reserve": GUNS["m1911"]["reserve"]}]
	gun_index = 0
	results = {}
	_cooldown = 0.0
	_reload_t = 0.0
	_trigger = false
	_use_held = false
	_hit_t = 99.0
	_player_room = _map["start"]
	_move_player_to(Vector3.ZERO)
	_hold_gear(true)
	_wear_shield(false)
	_reset_power()
	running = true
	round_number = first - 1
	_break_t = FIRST_BREAK
	_to_spawn = 0
	set_process(true)
	_hide_window()
	_update_hud()
	_show_gun()
	started.emit()
	points_changed.emit(points)
	return {"ok": true, "difficulty": settings["difficulty"], "round": first}


func _stop(_request: Dictionary) -> Dictionary:
	var was := running
	_end_game(false)
	if was and in_world():
		_show_window()
	return {"ok": true, "was_running": was}


# Ends the game: overrun (results kept and shown) or stopped.
func _end_game(overrun: bool) -> void:
	var was := running
	running = false
	_held = false
	_sprint_held = false
	_sprint(false)
	set_process(false)
	_trigger = false
	_use_held = false
	for z in _zombies:
		_hide_slot(z["slot"])
		_free_slots.append(z["slot"])
	_zombies.clear()
	_clear_drops()
	_wear_shield(false)
	downed = false
	effects.clear()
	_anvil_state = "idle"
	if _anvil_label:
		_anvil_label.text = "The Anvil  %d\nmakes your gun stronger" % ANVIL_COST
	if _anvil_show:
		_anvil_show.visible = false
	_crate_state = "idle"
	if _crate_label:
		_crate_label.text = "Lucky Crate\n%d" % CRATE_COST
		if _crate_show:
			_crate_show.visible = false
	if _sign:
		_sign.visible = false
	if _prompt:
		_prompt.visible = false
	if _tracer:
		_tracer.visible = false
	if _boom:
		_boom.visible = false
	_hold_gear(false)
	if overrun:
		results = {"round": round_number, "kills": kills, "headshots": headshots, "earned": earned, "points": points,
			"difficulty": settings["difficulty"]}
		var diff: String = settings["difficulty"]
		if round_number > int(best.get(diff, 0)):
			best[diff] = round_number
			results["new_best"] = true
		_save_settings()
		game_over.emit(results)
	if was:
		stopped.emit()


func _status(_request: Dictionary) -> Dictionary:
	var held := []
	for g in guns:
		held.append({"gun": g["id"], "name": _spec(g)["name"], "forged": g.get("up", false), "mag": g["mag"], "reserve": g["reserve"]})
	return {"ok": true, "running": running, "held": _held, "map": settings["map"], "round": round_number, "points": points, "health": health, "max_health": _max_health(),
		"guns": held, "in_hand": guns[gun_index]["id"] if gun_index < guns.size() else "", "tonics": tonics.duplicate(), "power": power, "parts": parts.size(), "shield": shield,
		"effects": effects.duplicate(), "downed": downed, "drops": _drops.map(func(d): return d["kind"]), "anvil": _anvil_state,
		"open_rooms": open_rooms.keys(), "boards": planks.duplicate(), "alive": _zombies.size(), "to_come": _to_spawn,
		"kills": kills, "headshots": headshots, "crate": _crate_state, "settings": settings.duplicate(), "best": best.duplicate(),
		"results": results.duplicate(), "in_world": in_world() if _lib else true}


# --- The lodge and the night wood -----------------------------------------------------

func _stage_on() -> void:
	if _arena != null:
		return
	var scene := ctx["world"].get_parent() as Node if ctx.get("world") else null
	if scene:
		var env := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if env:
			_swapped["environment"] = [env, env.environment]
			var night := Environment.new()
			night.background_mode = Environment.BG_COLOR
			night.background_color = Color(0.02, 0.025, 0.04)
			night.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			night.ambient_light_color = Color(0.5, 0.53, 0.62)
			night.ambient_light_energy = 1.3
			night.fog_enabled = true
			night.fog_light_color = Color(0.05, 0.07, 0.09)
			night.fog_density = 0.05
			night.fog_sky_affect = 0.0
			env.environment = night
		var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
		if sun:
			_swapped["sun"] = [sun, sun.light_energy, sun.light_color]
			sun.light_energy = 0.45
			sun.light_color = Color(0.6, 0.7, 1.0)  # moonlight
		var ground := scene.get_node_or_null("Floor") as Node3D
		if ground:
			_swapped["floor"] = [ground, ground.visible]
			ground.visible = false
	_arena = Node3D.new()
	_arena.name = "lodge"
	add_child(_arena)  # its own, not World's: nothing to save or select
	_place_arena()
	_build_lodge()
	if _lib and _lib.has_method("add_app_things"):
		_lib.call("add_app_things", self)


func _stage_off() -> void:
	if _swapped.has("environment") and is_instance_valid(_swapped["environment"][0]):
		_swapped["environment"][0].environment = _swapped["environment"][1]
	if _swapped.has("sun") and is_instance_valid(_swapped["sun"][0]):
		_swapped["sun"][0].light_energy = _swapped["sun"][1]
		_swapped["sun"][0].light_color = _swapped["sun"][2]
	if _swapped.has("floor") and is_instance_valid(_swapped["floor"][0]):
		_swapped["floor"][0].visible = _swapped["floor"][1]
	_swapped.clear()
	_hold_gear(false)
	if _arena != null and is_instance_valid(_arena):
		# Out of the tree now, not at the end of the frame: a new map's pieces
		# are built straight after, with the same names.
		if _arena.get_parent():
			_arena.get_parent().remove_child(_arena)
		_arena.queue_free()
	_arena = null
	_zombie_mm = null
	_zombies.clear()
	_free_slots.clear()
	_walls.clear()
	_plank_nodes.clear()
	_debris.clear()
	_uses.clear()
	_prompt = null
	_sign = null
	_crate_label = null
	_anvil_label = null
	_anvil_show = null
	_generator_label = null
	_power_lamps.clear()
	_part_nodes.clear()
	_drops.clear()
	_crate_show = null
	_tracer = null
	_boom = null


# The hall's middle goes where you stand, facing the way you look.
func _place_arena() -> void:
	var cam: Node3D = ctx.get("camera")
	if cam == null or not is_instance_valid(cam):
		_arena.transform = Transform3D.IDENTITY
		return
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	var yaw := atan2(-fwd.x, -fwd.z) if fwd.length() > 0.01 else 0.0
	var floor_y := 0.0
	var origin := cam.get_parent() as Node3D
	if origin:
		floor_y = origin.global_position.y
	_arena.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(cam.global_position.x, floor_y, cam.global_position.z))


func _build_lodge() -> void:
	# Ground, and each room's floorboards.
	_tag(_box(_arena, Vector3(90.0, 0.02, 90.0), Vector3(0.0, -0.02, 0.0), _mats["ground"]), "ground")
	for room in _map["rooms"]:
		var r: Array = _map["rooms"][room]
		_tag(_box(_arena, Vector3(r[2], 0.02, r[3]), Vector3(r[0] + r[2] / 2.0, 0.0, r[1] + r[3] / 2.0), _mats["dirt"] if room in _map["outdoor"] else _mats["boards"]), "floor_" + room)
	# Walls, with gaps for the doors and windows: one MultiMesh.
	var parts := []  # [size, centre]
	for room in _map["rooms"]:
		var r: Array = _map["rooms"][room]
		var x0: float = r[0]
		var z0: float = r[1]
		var x1: float = r[0] + r[2]
		var z1: float = r[1] + r[3]
		_wall_line(parts, Vector3(x0, 0, z0), Vector3(x1, 0, z0))
		_wall_line(parts, Vector3(x0, 0, z1), Vector3(x1, 0, z1))
		_wall_line(parts, Vector3(x0, 0, z0), Vector3(x0, 0, z1))
		_wall_line(parts, Vector3(x1, 0, z0), Vector3(x1, 0, z1))
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = unit
	mm.instance_count = parts.size()
	_walls.clear()
	for i in parts.size():
		var size: Vector3 = parts[i][0]
		var at: Vector3 = parts[i][1]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(size), at))
		_walls.append(AABB(at - size / 2.0, size))
	var walls := MultiMeshInstance3D.new()
	walls.name = "walls"
	_tag(walls, "walls")
	walls.multimesh = mm
	walls.material_override = _mats["wall"]
	_arena.add_child(walls)
	# Obstacles outside: they stop shots and the dead walk round them.
	var obstacles: Array = _map.get("obstacles", [])
	for oi in obstacles.size():
		var o: Array = obstacles[oi]
		var size := Vector3(o[2], o[4], o[3])
		var at := Vector3(o[0], o[4] / 2.0, o[1])
		_tag(_box(_arena, size, at, _mats["trunk"]), "obstacle_%d" % oi)
		_walls.append(AABB(at - size / 2.0, size))
	# Lanterns: glowing, no real light.
	var lanterns: Array = _map["lanterns"]
	for li in lanterns.size():
		var at: Array = lanterns[li]
		_tag(_box(_arena, Vector3(0.12, 0.2, 0.12), Vector3(at[0], at[1], at[2]), _mats["lantern"]), "lantern_%d" % li)
	_build_trees()
	_build_windows()
	_build_doors()
	_build_wall_things()
	_build_power_things()
	# The dead: one MultiMesh, every instance hidden until used.
	_zombie_mm = MultiMesh.new()
	_zombie_mm.transform_format = MultiMesh.TRANSFORM_3D
	_zombie_mm.use_colors = true
	_zombie_mm.mesh = _zombie_mesh()
	_zombie_mm.instance_count = POOL
	var dead := MultiMeshInstance3D.new()
	dead.name = "dead"
	_tag(dead, "dead")  # texturing it skins every one of them
	dead.multimesh = _zombie_mm
	dead.material_override = _mats["zombie"]
	dead.custom_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 15, 120))  # never culled: they move
	_arena.add_child(dead)
	_free_slots.clear()
	for i in POOL:
		_hide_slot(i)
		_free_slots.append(i)
	_zombies.clear()
	# What's shown while you play: the prompt, the round sign, shots.
	_prompt = _label(_arena, "", 40, Color(1.0, 0.95, 0.8))
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.visible = false
	_sign = _label(_arena, "", 160, Color(0.85, 0.08, 0.05))
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.visible = false
	_tracer = MeshInstance3D.new()
	_tracer.mesh = ImmediateMesh.new()
	_tracer.material_override = _mats["tracer"]
	_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tracer.visible = false
	_arena.add_child(_tracer)
	_boom = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 12
	ball.rings = 6
	_boom.mesh = ball
	_boom.material_override = _mats["boom"]
	_boom.visible = false
	_arena.add_child(_boom)
	_build_grid()
	_reset_lodge()


# A wall from a to b (on the ground), split round the doors and windows on it.
func _wall_line(parts: Array, a: Vector3, b: Vector3) -> void:
	var along := (b - a).normalized()
	var length := a.distance_to(b)
	var gaps := []  # [from, to, kind]
	for d in _map["doors"]:
		var at := Vector3(d["at"][0], 0, d["at"][1])
		var s := (at - a).dot(along)
		if (at - (a + along * s)).length() < 0.01 and s > 0.0 and s < length:
			gaps.append([s - DOOR_W / 2.0, s + DOOR_W / 2.0, "door"])
	for wnd in _map["windows"]:
		var at := Vector3(wnd["at"][0], 0, wnd["at"][1])
		var s := (at - a).dot(along)
		if (at - (a + along * s)).length() < 0.01 and s > 0.0 and s < length:
			gaps.append([s - WINDOW_W / 2.0, s + WINDOW_W / 2.0, "window"])
	gaps.sort_custom(func(p, q): return p[0] < q[0])
	var from := -WALL_T / 2.0
	for g in gaps:
		_wall_piece(parts, a, along, from, g[0], 0.0, WALL_H)
		if g[2] == "door":
			_wall_piece(parts, a, along, g[0], g[1], DOOR_H, WALL_H)
		else:
			_wall_piece(parts, a, along, g[0], g[1], 0.0, SILL)
			_wall_piece(parts, a, along, g[0], g[1], LINTEL, WALL_H)
		from = g[1]
	_wall_piece(parts, a, along, from, length + WALL_T / 2.0, 0.0, WALL_H)


func _wall_piece(parts: Array, a: Vector3, along: Vector3, s0: float, s1: float, y0: float, y1: float) -> void:
	if s1 - s0 < 0.01:
		return
	var mid := a + along * ((s0 + s1) / 2.0) + Vector3(0, (y0 + y1) / 2.0, 0)
	var size := Vector3(abs(along.x) * (s1 - s0) + abs(along.z) * WALL_T, y1 - y0, abs(along.z) * (s1 - s0) + abs(along.x) * WALL_T)
	parts.append([size, mid])


# The wood outside: dark trunks and pointed crowns, two draws, a fixed seed.
func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spots := []
	while spots.size() < 46:
		var at := Vector3(rng.randf_range(-28.0, 28.0), 0, rng.randf_range(-28.0, 28.0))
		var c: Array = _map["clearing"]
		if at.x > c[0] and at.x < c[2] and at.z > c[1] and at.z < c[3]:
			continue  # the clearing round the buildings
		spots.append([at, rng.randf_range(0.8, 1.5)])
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.2
	trunk.height = 1.0
	trunk.radial_segments = 6
	trunk.rings = 1
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 1.0
	crown.height = 1.0
	crown.radial_segments = 7
	crown.rings = 1
	for part in [[trunk, _mats["trunk"]], [crown, _mats["crown"]]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = spots.size()
		for i in spots.size():
			var at: Vector3 = spots[i][0]
			var s: float = spots[i][1]
			if part[0] == trunk:
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, 3.0 * s, s)), at + Vector3(0, 1.5 * s, 0)))
			else:
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.6 * s, 5.0 * s, 1.6 * s)), at + Vector3(0, 4.5 * s, 0)))
		var node := MultiMeshInstance3D.new()
		_tag(node, "trunks" if part[0] == trunk else "crowns")
		node.multimesh = mm
		node.material_override = part[1]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arena.add_child(node)


func _build_windows() -> void:
	_plank_nodes.clear()
	var board := BoxMesh.new()
	board.size = Vector3(WINDOW_W + 0.2, 0.13, 0.05)
	for wnd in _map["windows"]:
		var at := Vector3(wnd["at"][0], 0, wnd["at"][1])
		var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
		var yaw := atan2(out.x, out.z)
		var list := []
		for i in PLANKS:
			var p := MeshInstance3D.new()
			_tag(p, "plank_%s_%d" % [wnd["id"], i])
			p.mesh = board
			p.material_override = _mats["plank"]
			_arena.add_child(p)
			var tilt := deg_to_rad([-8.0, 6.0, -4.0, 9.0, -6.0][i])
			p.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, tilt), at - out * 0.14 + Vector3(0, SILL + 0.14 + i * 0.2, 0))
			list.append(p)
		_plank_nodes[wnd["id"]] = list
		_uses.append({"kind": "window", "id": wnd["id"], "at": at - out * 0.6, "label": null})


func _build_doors() -> void:
	_debris.clear()
	for d in _map["doors"]:
		var at := Vector3(d["at"][0], 0, d["at"][1])
		var pile := Node3D.new()
		_tag(pile, "debris_" + d["id"])
		_arena.add_child(pile)
		pile.position = at
		var inward0 := _into_room(at, d["rooms"][0])
		var across := Vector3(0, 0, 1) if absf(inward0.x) > 0.5 else Vector3(1, 0, 0)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(d["id"])
		for i in 7:
			var size := Vector3(rng.randf_range(0.4, 0.9), rng.randf_range(0.25, 0.6), rng.randf_range(0.3, 0.6))
			var spot := across * rng.randf_range(-0.6, 0.6) + Vector3(0, size.y / 2.0 + (0.45 if i >= 4 else 0.0), 0)
			var piece := _box(pile, size, spot, _mats["plank"] if i % 2 == 0 else _mats["debris"])
			piece.rotation.y = rng.randf_range(-0.6, 0.6)
		for room in d["rooms"]:
			var inward := _into_room(at, room)
			var label := _label(_arena, "", 46, Color(1.0, 0.9, 0.7))
			label.position = at + inward * 0.55 + Vector3(0, 1.75, 0)
			label.rotation.y = atan2(inward.x, inward.z)
			label.text = "Clear the debris\n%s  %d" % [_map["room_names"][d["rooms"][1]], d["cost"]]
			pile.set_meta("label_" + room, label)
			_uses.append({"kind": "door", "id": d["id"], "at": at + inward * 0.7, "label": label})
		_debris[d["id"]] = pile


# The way from a point on a room's wall into that room.
func _into_room(at: Vector3, room: String) -> Vector3:
	var r: Array = _map["rooms"][room]
	var mid := Vector3(r[0] + r[2] / 2.0, 0, r[1] + r[3] / 2.0)
	var d := mid - at
	return Vector3(signf(d.x), 0, 0) if absf(d.x) * r[3] > absf(d.z) * r[2] else Vector3(0, 0, signf(d.z))


func _build_wall_things() -> void:
	for spot in _map["wall_guns"]:
		var g: Dictionary = GUNS[spot["gun"]]
		var at := Vector3(spot["at"][0], 0, spot["at"][1])
		var inward := Vector3(spot["in"][0], 0, spot["in"][1])
		var yaw := atan2(inward.x, inward.z)
		var board := _box(_arena, Vector3(0.9, 0.5, 0.03), at + inward * (WALL_T / 2.0 + 0.02) + Vector3(0, 1.45, 0), _mats["chalkboard"])
		_tag(board, "board_" + spot["gun"])
		board.rotation.y = yaw
		# The gun's outline in chalk: its own shape, flat and pale.
		var outline := MeshInstance3D.new()
		outline.mesh = _gun_mesh_for(spot["gun"])
		outline.material_override = _mats["chalk"]
		_tag(outline, "outline_" + spot["gun"])
		_arena.add_child(outline)
		outline.transform = Transform3D(Basis(Vector3.UP, yaw + PI / 2.0) * Basis.from_scale(Vector3(1.2, 1.2, 1.2) * minf(1.0, 0.36 / g["len"])),
			at + inward * (WALL_T / 2.0 + 0.06) + Vector3(0, 1.5, 0))
		var label := _label(_arena, "%s  %d\nammo %d" % [g["name"], g["cost"], g["cost"] / 2], 44, Color(0.95, 0.95, 0.9))
		label.position = at + inward * (WALL_T / 2.0 + 0.05) + Vector3(0, 1.08, 0)
		label.rotation.y = yaw
		_uses.append({"kind": "gun", "id": spot["gun"], "at": at + inward * 0.7, "label": label})
	for spot in _map["tonics"] + [_map["second_wind"]]:
		var t: Dictionary = TONICS[spot["tonic"]]
		var at := Vector3(spot["at"][0], 0, spot["at"][1])
		var inward := Vector3(spot["in"][0], 0, spot["in"][1])
		var yaw := atan2(inward.x, inward.z)
		var body := _box(_arena, Vector3(0.7, 1.8, 0.45), at + inward * (WALL_T / 2.0 + 0.24) + Vector3(0, 0.9, 0), _mats["machine"])
		_tag(body, "machine_" + spot["tonic"])
		body.rotation.y = yaw
		var glow := _box(_arena, Vector3(0.5, 0.55, 0.02), at + inward * (WALL_T / 2.0 + 0.47) + Vector3(0, 1.3, 0), _flat_glow(t["color"]))
		_tag(glow, "glow_" + spot["tonic"])
		glow.rotation.y = yaw
		var label := _label(_arena, "%s  %d\n%s" % [t["name"], t["cost"], t["does"]], 40, t["color"].lightened(0.4))
		label.position = at + inward * (WALL_T / 2.0 + 0.5) + Vector3(0, 0.75, 0)
		label.rotation.y = yaw
		_uses.append({"kind": "tonic", "id": spot["tonic"], "at": at + inward * 0.9, "label": label})
	var c_at := Vector3(_map["crate"]["at"][0], 0, _map["crate"]["at"][1])
	var c_in := Vector3(_map["crate"]["in"][0], 0, _map["crate"]["in"][1])
	var c_yaw := atan2(c_in.x, c_in.z)
	var chest := _box(_arena, Vector3(1.2, 0.6, 0.6), c_at + c_in * (WALL_T / 2.0 + 0.35) + Vector3(0, 0.3, 0), _mats["crate"])
	_tag(chest, "crate")
	chest.rotation.y = c_yaw
	var rim := _box(_arena, Vector3(1.24, 0.04, 0.64), c_at + c_in * (WALL_T / 2.0 + 0.35) + Vector3(0, 0.6, 0), _flat_glow(Color(0.95, 0.75, 0.2)))
	_tag(rim, "crate_rim")
	rim.rotation.y = c_yaw
	_crate_label = _label(_arena, "Lucky Crate\n%d" % CRATE_COST, 52, Color(1.0, 0.85, 0.35))
	_crate_label.position = c_at + c_in * (WALL_T / 2.0 + 0.35) + Vector3(0, 1.05, 0)
	_crate_label.rotation.y = c_yaw
	# The gun it shows, floating over it while it shuffles and offers.
	_crate_show = MeshInstance3D.new()
	_crate_show.material_override = _mats["gun"]
	_crate_show.position = c_at + c_in * (WALL_T / 2.0 + 0.35) + Vector3(0, 0.85, 0)
	_crate_show.rotation.y = c_yaw + PI / 2.0
	_crate_show.scale = Vector3.ONE * 1.6
	_crate_show.visible = false
	_arena.add_child(_crate_show)
	_uses.append({"kind": "crate", "id": "crate", "at": c_at + c_in * 1.0, "label": _crate_label})


# Puts the boards and debris back for a new game.
func _reset_lodge() -> void:
	open_rooms = {_map["start"]: true}
	_in_dirty = true
	planks.clear()
	for wnd in _map["windows"]:
		planks[wnd["id"]] = PLANKS
		_show_planks(wnd["id"])
	for id in _debris:
		if is_instance_valid(_debris[id]):
			_debris[id].visible = true
			for room in _map["rooms"]:
				if _debris[id].has_meta("label_" + room):
					_debris[id].get_meta("label_" + room).visible = true
	_crate_state = "idle"


func _show_planks(id: String) -> void:
	if not _plank_nodes.has(id):
		return
	var list: Array = _plank_nodes[id]
	for i in list.size():
		list[i].visible = i < int(planks.get(id, 0))


# --- You -----------------------------------------------------------------------------

func _cam_local() -> Vector3:
	var cam: Node3D = ctx.get("camera")
	if cam == null or _arena == null:
		return Vector3.ZERO
	return _arena.to_local(cam.global_position)


func _move_player_to(spot: Vector3) -> void:
	var cam: Node3D = ctx.get("camera")
	if cam == null or _arena == null:
		return
	var origin := cam.get_parent() as Node3D
	if origin == null:
		return
	var want := _arena.to_global(spot)
	var shift := want - cam.global_position
	shift.y = 0.0
	origin.global_position += shift


# A point this far in front of where you look, at eye height (lodge space).
func _ahead_of_you(metres: float) -> Vector3:
	var cam := ctx.get("camera") as Node3D
	var ahead := Vector3.FORWARD
	if cam and _arena:
		ahead = _arena.global_transform.basis.inverse() * -cam.global_transform.basis.z
		ahead.y = 0.0
		if ahead.length() < 0.01:
			ahead = Vector3.FORWARD
	return _cam_local() + ahead.normalized() * metres


func _max_health() -> float:
	return IRON_HEALTH if "ironbark" in tonics else HEALTH


# The rooms you may stand in (open ones), less a margin, and the open doorways.
func _allowed_boxes() -> Array:
	var boxes := []
	for room in open_rooms:
		var r: Array = _map["rooms"][room]
		boxes.append(Rect2(r[0] + MARGIN, r[1] + MARGIN, r[2] - 2.0 * MARGIN, r[3] - 2.0 * MARGIN))
	for d in _map["doors"]:
		if open_rooms.has(d["rooms"][0]) and open_rooms.has(d["rooms"][1]):
			var w := DOOR_W / 2.0 - MARGIN
			boxes.append(Rect2(d["at"][0] - w, d["at"][1] - w, 2.0 * w, 2.0 * w).grow(MARGIN * 1.5))
	return boxes


func _keep_in() -> void:
	var p := _cam_local()
	var here := Vector2(p.x, p.z)
	var boxes := _allowed_boxes()
	var nearest := here
	var gap := INF
	for b: Rect2 in boxes:
		if b.has_point(here):
			return
		var c := Vector2(clampf(here.x, b.position.x, b.end.x), clampf(here.y, b.position.y, b.end.y))
		if c.distance_to(here) < gap:
			gap = c.distance_to(here)
			nearest = c
	if gap < INF:
		_move_player_to(Vector3(nearest.x, 0, nearest.y))


func _room_at(p: Vector3) -> String:
	for room in _map["rooms"]:
		var r: Array = _map["rooms"][room]
		if p.x >= r[0] and p.x <= r[0] + r[2] and p.z >= r[1] and p.z <= r[1] + r[3]:
			return room
	return ""


func _hurt_you(amount: float) -> void:
	health -= amount
	_hit_t = 0.0
	_sound("hurt", null, 0.9)
	_pulse("left", 0.8, 0.2)
	_pulse("right", 0.8, 0.2)
	_update_hud()
	if health <= 0.0:
		health = 0.0
		if "second_wind" in tonics:
			_go_down()
			return
		_end_game(true)
		if in_world():
			_show_window()


# A swipe from one of the dead: the shield takes it when it's between you
# (it faces the way your left hand points); while you're down, nothing.
func _struck_by(z: Dictionary) -> void:
	if downed:
		return
	if shield > 0 and _shield_node != null:
		var left := ctx.get("left") as Node3D
		if left:
			var facing := _arena.global_transform.basis.inverse() * -left.global_transform.basis.z
			facing.y = 0.0
			var to: Vector3 = z["pos"] - _cam_local()
			to.y = 0.0
			if facing.length() > 0.01 and to.length() > 0.01 and facing.normalized().dot(to.normalized()) > SHIELD_FACING:
				shield -= 1
				_sound("nail", _arena.to_global(z["pos"] + Vector3(0, 1.2, 0)), 1.0, 0.6)
				_pulse("left", 1.0, 0.12)
				if shield <= 0:
					_wear_shield(false)
					_sound("rip", null, 1.0)
				_update_hud()
				return
	_hurt_you(DIFF_HIT[settings["difficulty"]])


# Second Wind: you fall, the dead nearby are thrown back, and after a few
# seconds you're up again with full health. The tonics are lost (Second
# Wind with them), like going down always costs.
func _go_down() -> void:
	downed = true
	_down_t = DOWN_TIME
	tonics.clear()
	effects.erase("one_shot")
	var you := _cam_local()
	you.y = 0.0
	for z in _zombies:
		if z["state"] != "chase":
			continue
		var away: Vector3 = z["pos"] - you
		away.y = 0.0
		if away.length() < DOWN_PUSH:
			z["pos"] = _inside(you + (away.normalized() if away.length() > 0.01 else Vector3.FORWARD) * DOWN_PUSH, z["room"])
			z["cd"] = ATTACK_TIME
	_sign.text = "Down!\nGetting back up..."
	_sign.position = _ahead_of_you(2.0) + Vector3(0, 0.2, 0)
	_sign.visible = true
	_sign_left = DOWN_TIME
	_sound("hurt", null, 1.0, 0.6)
	_update_hud()


func _get_up() -> void:
	downed = false
	health = _max_health()
	_hit_t = 99.0
	_sign.visible = false
	_sign_left = 0.0
	_sound("gulp", null, 0.8)
	_update_hud()


# --- Each frame ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not running or _arena == null or _held:
		_sprint(false)
		set_process(false)
		return
	_keep_in()
	var here := _cam_local()
	var room := _room_at(here)
	if not room.is_empty() and open_rooms.has(room):
		_player_room = room
	var cell := _cell_of(here)
	if _in_dirty or cell != _in_from:
		_make_in_field(cell)
	# Health comes back.
	_hit_t += delta
	var wait := REGEN_AFTER * (0.5 if "mending_moss" in tonics else 1.0)
	if _hit_t > wait and health < _max_health():
		health = minf(_max_health(), health + REGEN_RATE * (2.0 if "mending_moss" in tonics else 1.0) * delta)
		_update_hud()
	_show_hurt()
	_sprint_frame(delta, _controls != null and (_controls.call("stick", "walk") as Vector2).length() > 0.3)
	_rounds(delta)
	_move_dead(delta, here)
	if not running:
		return  # overrun this frame
	_gun_frame(delta)
	_knife_frame(delta)
	_use_frame(delta, here)
	_crate_frame(delta)
	_anvil_frame(delta)
	_drops_frame(delta, here)
	if downed:
		_down_t -= delta
		if _down_t <= 0.0:
			_get_up()
	for e in effects.keys():
		effects[e] -= delta
		if effects[e] <= 0.0:
			effects.erase(e)
			_update_hud()
	if not effects.is_empty() and int(effects.values().max() * 4.0) != int((effects.values().max() + delta) * 4.0):
		_update_hud()  # the countdown, four times a second
	if _sign_left > 0.0:
		_sign_left -= delta
		_sign.visible = _sign_left > 0.0
	if _tracer_left > 0.0:
		_tracer_left -= delta
		_tracer.visible = _tracer_left > 0.0
	if _boom_left > 0.0:
		_boom_left -= delta
		_boom.visible = _boom_left > 0.0
	if _flash and _flash.visible and _cooldown < _rate() - 0.05:
		_flash.visible = false


# --- Rounds ----------------------------------------------------------------------------

func _rounds(delta: float) -> void:
	if _break_t > 0.0:
		_break_t -= delta
		if _break_t <= 0.0:
			_next_round()
		return
	if _to_spawn > 0:
		_spawn_t -= delta
		if _spawn_t <= 0.0 and _zombies.size() < int(settings["max_zombies"]) and not _free_slots.is_empty():
			if _spawn_one():
				_to_spawn -= 1
			_spawn_t = spawn_gap(round_number)
	elif _zombies.is_empty():
		_break_t = ROUND_BREAK
		_sound("bell", null, 0.6)


func _next_round() -> void:
	round_number += 1
	_to_spawn = round_count(round_number)
	_round_hp = round_health(round_number) * DIFF_HEALTH[settings["difficulty"]]
	_repair_points = 0
	_drops_round = 0
	_spawn_t = 1.0
	_sign.text = "Round %d" % round_number
	_sign.position = _ahead_of_you(3.0) + Vector3(0, 0.6, 0)
	_sign.visible = true
	_sign_left = 3.5
	_sound("bell", null, 1.0)
	_update_hud()
	if _has_ui() and _shown():
		_build()
	round_started.emit(round_number)


# How many come in a round, and how tough each is.
static func round_count(n: int) -> int:
	return mini(6 + 3 * n + int(n * n * 0.15), 90)


# Seconds between the dead coming up: 2 on round 1, 5% less each round,
# never under a quarter second (the most at once holds them back anyway).
static func spawn_gap(n: int) -> float:
	return maxf(SPAWN_GAP_MIN, SPAWN_GAP * pow(0.95, n - 1))


static func round_health(n: int) -> float:
	if n <= 9:
		return 150.0 + 100.0 * (n - 1)
	return 950.0 * pow(1.1, n - 9)


func _speed_for_round() -> float:
	var run_chance := clampf((round_number - 4) * 0.12, 0.0, 0.8)
	var jog_chance := clampf((round_number - 1) * 0.25, 0.0, 1.0)
	var roll := _rng.randf()
	if roll < run_chance:
		return SPEEDS["run"]
	if roll < run_chance + (1.0 - run_chance) * jog_chance:
		return SPEEDS["jog"]
	return SPEEDS["walk"]


# One more comes up out of the ground outside a window of an open room
# (more often your own room's). Whether one did.
func _spawn_one() -> bool:
	var choices := []
	for wnd in _map["windows"]:
		if open_rooms.has(wnd["room"]):
			for i in (3 if wnd["room"] == _player_room else 1):
				choices.append(wnd)
	if choices.is_empty() or _free_slots.is_empty():
		return false
	var wnd: Dictionary = choices[_rng.randi() % choices.size()]
	var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
	var at := _spawn_spot(wnd)
	var to_window := Vector3(wnd["at"][0], 0, wnd["at"][1]) - at
	if to_window.length() > 0.1:
		out = -to_window.normalized()
	var z := {"slot": _free_slots.pop_back(), "state": "rise", "pos": at, "yaw": atan2(-out.x, -out.z), "hp": _round_hp,
		"speed": _speed_for_round(), "room": wnd["room"], "window": wnd["id"], "t": 0.0, "cd": 0.0, "chill": 0.0, "burn": 0.0, "snare": 0.0, "swing": -1.0,
		"groan": _rng.randf_range(1.0, 6.0), "flash": 0.0, "y": -1.8, "phase": _rng.randf() * TAU, "fall": 0.0}
	_zombies.append(z)
	_place_zombie(z)
	return true


# Puts one in the game now (tests, and a later debug command): at a spot
# in a room, already inside.
func add_zombie_inside(spot: Vector3, room := "", hp := -1.0) -> Dictionary:
	if _free_slots.is_empty():
		return {}
	if room.is_empty():
		room = _room_at(spot) if not _room_at(spot).is_empty() else _map["start"]
	var z := {"slot": _free_slots.pop_back(), "state": "chase", "pos": spot, "yaw": 0.0, "hp": hp if hp > 0.0 else _round_hp,
		"speed": SPEEDS["walk"], "room": room, "window": "", "t": 0.0, "cd": ATTACK_TIME, "chill": 0.0, "burn": 0.0, "snare": 0.0, "swing": -1.0, "groan": 5.0,
		"flash": 0.0, "y": 0.0, "phase": 0.0, "fall": 0.0}
	_zombies.append(z)
	_place_zombie(z)
	return z


# --- The dead ---------------------------------------------------------------------------

func _move_dead(delta: float, you: Vector3) -> void:
	_groan_cd -= delta
	var you_flat := Vector3(you.x, 0, you.z)
	for z in _zombies.duplicate():
		z["t"] += delta
		z["flash"] = maxf(0.0, z["flash"] - delta)
		z["chill"] = maxf(0.0, z["chill"] - delta)
		z["snare"] = maxf(0.0, z["snare"] - delta)
		if z["burn"] > 0.0 and z["state"] != "dying":
			z["burn"] = maxf(0.0, z["burn"] - delta)
			z["hp"] -= BURN_DPS * delta
			if z["hp"] <= 0.0:
				_kill(z, false, false)
		var speed: float = z["speed"] * (0.4 if z["chill"] > 0.0 else 1.0) * (0.0 if z["snare"] > 0.0 else 1.0)
		match z["state"]:
			"rise":
				z["y"] = lerpf(-1.8, 0.0, minf(1.0, z["t"] / RISE_TIME))
				if z["t"] >= RISE_TIME:
					_set_state(z, "approach")
			"approach":
				var wnd := _window(z["window"])
				var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
				var spot := Vector3(wnd["at"][0], 0, wnd["at"][1]) + out * 0.55
				var step := _path_step(_out_fields.get(z["window"], PackedInt32Array()), z["pos"])
				if step != Vector3.INF:
					_walk_to(z, step, speed, delta)
				elif _walk_to(z, spot, speed, delta):
					_set_state(z, "tear")
			"tear":
				var wnd := _window(z["window"])
				var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
				z["yaw"] = atan2(out.x, out.z)  # facing in
				if int(planks[z["window"]]) <= 0:
					_set_state(z, "climb")
				elif z["t"] >= TEAR_TIME * SPEEDS["walk"] / maxf(speed, 0.3) + 0.4:
					planks[z["window"]] = int(planks[z["window"]]) - 1
					_show_planks(z["window"])
					_sound("rip", _arena.to_global(Vector3(wnd["at"][0], 1.3, wnd["at"][1])), 0.8)
					z["t"] = 0.0
			"climb":
				var wnd := _window(z["window"])
				var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
				var at := Vector3(wnd["at"][0], 0, wnd["at"][1])
				var k := minf(1.0, z["t"] / CLIMB_TIME)
				z["pos"] = (at + out * 0.55).lerp(at - out * 0.7, k)
				z["y"] = sin(k * PI) * 0.7
				if z["t"] >= CLIMB_TIME:
					z["y"] = 0.0
					_set_state(z, "chase")
			"chase":
				if _stuck(z, delta):
					continue
				var now_in := _room_at(z["pos"])
				if not now_in.is_empty() and open_rooms.has(now_in):
					z["room"] = now_in
				var target := you_flat
				var step := _path_step(_in_field, z["pos"])
				if step != Vector3.INF:
					target = step
				if z["swing"] >= 0.0:
					pass  # stands its ground to swipe
				elif (z["pos"] as Vector3).distance_to(you_flat) > ATTACK_RANGE * 0.7:
					_walk_to(z, target, speed, delta)
				else:
					var to: Vector3 = you_flat - z["pos"]
					z["yaw"] = atan2(-to.x, -to.z)
			"dying":
				z["fall"] = minf(1.0, z["t"] / 0.45)
				if z["t"] > 0.8:
					z["y"] = -1.2 * (z["t"] - 0.8) / (DIE_TIME - 0.8)
				if z["t"] >= DIE_TIME:
					_hide_slot(z["slot"])
					_free_slots.append(z["slot"])
					_zombies.erase(z)
					continue
		# A swipe: it rears back for SWING_TIME, then lunges; it only lands if
		# you're still in reach then.
		if z["state"] in ["tear", "chase"] and z["snare"] <= 0.0:
			z["cd"] -= delta
			var reach: float = (z["pos"] as Vector3).distance_to(you_flat)
			if z["swing"] >= 0.0:
				var was: float = z["swing"]
				z["swing"] += delta
				if was < SWING_TIME and z["swing"] >= SWING_TIME:
					z["cd"] = ATTACK_TIME
					if reach < ATTACK_RANGE * 1.1:
						_struck_by(z)
						if not running:
							return
				if z["swing"] >= SWING_TIME + SWING_BACK:
					z["swing"] = -1.0
			elif reach < ATTACK_RANGE and z["cd"] <= 0.0:
				z["swing"] = 0.0
				_sound("groan", _arena.to_global(z["pos"] + Vector3(0, 1.5, 0)), 0.5, 1.4)
		elif z["swing"] >= 0.0:
			z["swing"] = -1.0  # held by roots, or climbing: the swipe's lost
		if z["state"] != "dying":
			z["groan"] -= delta
			if z["groan"] <= 0.0:
				z["groan"] = _rng.randf_range(4.0, 9.0)
				if _groan_cd <= 0.0:
					_groan_cd = 1.2
					_sound("groan", _arena.to_global(z["pos"] + Vector3(0, 1.5, 0)), 0.7, _rng.randf_range(0.85, 1.15))
		_place_zombie(z)
	_spread_out()


# --- Sprint -----------------------------------------------------------------------------

# Holding the left grip while walking runs (controls.gd's speed_boost),
# until the stamina's gone; it comes back after SPRINT_REST of not running.
func _sprint_frame(delta: float, walking: bool) -> void:
	if _sprint_held and walking and _stamina > 0.0 and not downed:
		_stamina = maxf(0.0, _stamina - delta)
		_rest_t = 0.0
		_sprint(true)
		if _stamina == 0.0:
			_pulse("left", 0.4, 0.15)  # out of breath
		return
	_sprint(false)
	_rest_t += delta
	if _rest_t >= SPRINT_REST:
		_stamina = minf(SPRINT_TIME, _stamina + delta)


func _sprint(on: bool) -> void:
	if on == _sprinting:
		return
	_sprinting = on
	if _controls and _controls.has_method("speed_boost"):
		_controls.call("speed_boost", SPRINT_BOOST if on else 1.0)


# --- Pathing --------------------------------------------------------------------------
# The clearing is a grid of CELL-metre squares. Walls that reach the ground
# (window sills too) and the obstacles block the cells round them (by a
# body's width). Outside, each window has a field made once when the
# buildings go up: how many steps each cell is from that window. Inside,
# one field leads to you, made again only when you step into another cell
# or a door opens. A zombie steps to the neighbouring cell nearest its goal
# (diagonals only past free corners), so it walks round whatever's in the
# way; next to its goal it walks straight there.

const CELL := 0.5
const BODY := 0.25               # how far a zombie's middle keeps off a wall


func _build_grid() -> void:
	var c: Array = _map["clearing"]
	_grid_at = Vector2(c[0], c[1])
	_gw = int(ceil((c[2] - c[0]) / CELL))
	_gh = int(ceil((c[3] - c[1]) / CELL))
	_blocked = PackedByteArray()
	_blocked.resize(_gw * _gh)
	_cell_room = PackedInt32Array()
	_cell_room.resize(_gw * _gh)
	_cell_room.fill(-1)
	var rooms: Array = _map["rooms"].keys()
	for ri in rooms.size():
		var r: Array = _map["rooms"][rooms[ri]]
		_mark(Rect2(r[0], r[1], r[2], r[3]), _cell_room, ri)
	for box: AABB in _walls:
		if box.position.y < 0.3:  # reaches the ground
			_mark(Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(BODY), _blocked, 1)
	_out_fields.clear()
	for wnd in _map["windows"]:
		var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
		var seed := _cell_of(Vector3(wnd["at"][0], 0, wnd["at"][1]) + out * 0.55)
		_out_fields[wnd["id"]] = _field(seed, func(i): return _cell_room[i] == -1)
	_in_from = -2
	_in_dirty = true


# Sets every cell whose middle is in rect.
func _mark(rect: Rect2, cells, value: int) -> void:
	var x0 := maxi(0, int(ceil((rect.position.x - _grid_at.x) / CELL - 0.5)))
	var x1 := mini(_gw - 1, int(floor((rect.end.x - _grid_at.x) / CELL - 0.5)))
	var z0 := maxi(0, int(ceil((rect.position.y - _grid_at.y) / CELL - 0.5)))
	var z1 := mini(_gh - 1, int(floor((rect.end.y - _grid_at.y) / CELL - 0.5)))
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			cells[z * _gw + x] = value


func _cell_of(p: Vector3) -> int:
	var x := int(floor((p.x - _grid_at.x) / CELL))
	var z := int(floor((p.z - _grid_at.y) / CELL))
	if x < 0 or z < 0 or x >= _gw or z >= _gh:
		return -1
	return z * _gw + x


func _cell_middle(i: int) -> Vector3:
	return Vector3(_grid_at.x + (i % _gw + 0.5) * CELL, 0.0, _grid_at.y + (i / _gw + 0.5) * CELL)


# Steps from seed to each free cell where may(i) is true (-1: can't get there).
func _field(seed: int, may: Callable) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(_gw * _gh)
	dist.fill(-1)
	if seed < 0:
		return dist
	dist[seed] = 0
	var queue := PackedInt32Array([seed])
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % _gw
		for n in [i - 1 if x > 0 else -1, i + 1 if x < _gw - 1 else -1, i - _gw, i + _gw]:
			if n < 0 or n >= dist.size() or dist[n] != -1 or _blocked[n] == 1 or not may.call(n):
				continue
			dist[n] = dist[i] + 1
			queue.append(n)
	return dist


func _make_in_field(cell: int) -> void:
	_in_from = cell
	_in_dirty = false
	var rooms: Array = _map["rooms"].keys()
	var open := []
	for ri in rooms.size():
		open.append(open_rooms.has(rooms[ri]))
	_in_field = _field(cell, func(i): return _cell_room[i] >= 0 and open[_cell_room[i]])


# Where to walk next on a field: the middle of the neighbouring cell nearest
# the goal, or Vector3.INF when off the field or a cell or two from the goal
# (then walk straight to it).
func _path_step(field: PackedInt32Array, from: Vector3) -> Vector3:
	var i := _cell_of(from)
	if field.is_empty() or i < 0 or field[i] <= 1:
		return Vector3.INF
	var x := i % _gw
	var z := i / _gw
	var best := i
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = x + dx
			var nz: int = z + dz
			if (dx == 0 and dz == 0) or nx < 0 or nz < 0 or nx >= _gw or nz >= _gh:
				continue
			var n: int = nz * _gw + nx
			if field[n] < 0:
				continue
			if dx != 0 and dz != 0 and (field[z * _gw + nx] < 0 or field[nz * _gw + x] < 0):
				continue  # no cutting a corner
			if field[n] < field[best] or (field[n] == field[best] and dx != 0 and dz != 0):
				best = n
	return _cell_middle(best) if best != i else Vector3.INF


# Where one bound for this window comes up: one of the two spawns nearest
# it (by walking), a little to one side.
func _spawn_spot(wnd: Dictionary) -> Vector3:
	var field: PackedInt32Array = _out_fields.get(wnd["id"], PackedInt32Array())
	var near := []
	for sp in _map.get("spawns", []):
		var i := _cell_of(Vector3(sp[0], 0, sp[1]))
		if not field.is_empty() and i >= 0 and field[i] >= 0:
			near.append([field[i], Vector3(sp[0], 0, sp[1])])
	if near.is_empty():  # no spawns that reach it: just outside, as before
		var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
		return Vector3(wnd["at"][0], 0, wnd["at"][1]) + out * _rng.randf_range(3.0, 5.0)
	near.sort_custom(func(a, b): return a[0] < b[0])
	var at: Vector3 = near[_rng.randi() % mini(2, near.size())][1]
	var nudged := at + Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0))
	var ni := _cell_of(nudged)
	return nudged if ni >= 0 and field[ni] >= 0 else at


# --- Fixes ---------------------------------------------------------------------------------
# Known troubles in games like this, each handled in one place.

# A chasing one that has hardly moved for a while, and isn't next to you,
# is stuck (wedged in a corner or between others): it goes back out to a
# window of your room and comes in again. Whether it was moved.
func _stuck(z: Dictionary, delta: float) -> bool:
	var pos: Vector3 = z["pos"]
	if not z.has("anchor") or pos.distance_to(z["anchor"]) > STUCK_MOVE:
		z["anchor"] = pos
		z["still"] = 0.0
		return false
	z["still"] += delta
	if z["still"] < STUCK_TIME or pos.distance_to(Vector3(_cam_local().x, 0, _cam_local().z)) < ATTACK_RANGE * 1.5:
		return false
	var choices: Array = _map["windows"].filter(func(w): return w["room"] == _player_room)
	if choices.is_empty():
		return false
	var wnd: Dictionary = choices[_rng.randi() % choices.size()]
	var out := Vector3(wnd["out"][0], 0, wnd["out"][1])
	z["window"] = wnd["id"]
	z["room"] = wnd["room"]
	z["pos"] = Vector3(wnd["at"][0], 0, wnd["at"][1]) + out * 2.5
	z.erase("anchor")
	_set_state(z, "approach")
	_place_zombie(z)
	return true


func _set_state(z: Dictionary, state: String) -> void:
	z["state"] = state
	z["t"] = 0.0


# Walks toward spot; whether it's there.
func _walk_to(z: Dictionary, spot: Vector3, speed: float, delta: float) -> bool:
	var to: Vector3 = spot - z["pos"]
	to.y = 0.0
	var d := to.length()
	if d < 0.05:
		return true
	var step := minf(d, speed * delta)
	z["pos"] += to / d * step
	z["yaw"] = atan2(-to.x, -to.z)
	z["phase"] += delta * speed * 5.0
	return d - step < 0.05


# The dead push apart, so they never stand in one another: inside, on the
# way to a window, and at it. One tearing at a window keeps its place, so
# the next waits behind it (a queue, not a stack). Nobody is pushed into a
# wall or out of its room.
func _spread_out() -> void:
	for i in _zombies.size():
		var a: Dictionary = _zombies[i]
		if not a["state"] in ["chase", "approach", "tear"]:
			continue
		for j in range(i + 1, _zombies.size()):
			var b: Dictionary = _zombies[j]
			if not b["state"] in ["chase", "approach", "tear"]:
				continue
			var d: Vector3 = b["pos"] - a["pos"]
			d.y = 0.0
			var l := d.length()
			if l >= ZOMBIE_GAP:
				continue
			if l < 0.001:
				d = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
				l = maxf(d.length(), 0.001)
			var push := d / l * (ZOMBIE_GAP - l)
			var a_moves: bool = a["state"] != "tear"
			var b_moves: bool = b["state"] != "tear"
			if a_moves and b_moves:
				_nudge(a, -push * 0.5)
				_nudge(b, push * 0.5)
			elif a_moves:
				_nudge(a, -push)
			elif b_moves:
				_nudge(b, push)


func _nudge(z: Dictionary, by: Vector3) -> void:
	var to: Vector3 = z["pos"] + by
	if z["state"] == "chase":
		z["pos"] = _inside(to, z["room"])
		return
	var c := _cell_of(to)
	if c < 0 or _blocked.is_empty() or (_blocked[c] == 0 and _cell_room[c] == -1):
		z["pos"] = to


# Keeps a point in a room (or in an open doorway out of it).
func _inside(p: Vector3, room: String) -> Vector3:
	var r: Array = _map["rooms"][room]
	var m := 0.25
	if p.x >= r[0] + m and p.x <= r[0] + r[2] - m and p.z >= r[1] + m and p.z <= r[1] + r[3] - m:
		return p
	for d in _map["doors"]:
		if room in d["rooms"] and open_rooms.has(d["rooms"][0]) and open_rooms.has(d["rooms"][1]):
			if absf(p.x - d["at"][0]) < DOOR_W / 2.0 and absf(p.z - d["at"][1]) < DOOR_W / 2.0:
				return p
	return Vector3(clampf(p.x, r[0] + m, r[0] + r[2] - m), p.y, clampf(p.z, r[1] + m, r[1] + r[3] - m))


func _window(id: String) -> Dictionary:
	for wnd in _map["windows"]:
		if wnd["id"] == id:
			return wnd
	return _map["windows"][0]


func _place_zombie(z: Dictionary) -> void:
	if _zombie_mm == null:
		return
	var sway := sin(z["phase"]) * 0.08 if z["state"] in ["chase", "approach"] else 0.0
	var lean := 0.0  # the swipe: back as it winds up, forward as it lunges, then up again
	var sw: float = z.get("swing", -1.0)
	if sw >= 0.0:
		if sw < SWING_TIME * 0.75:
			lean = 0.3 * sw / (SWING_TIME * 0.75)
		elif sw < SWING_TIME:
			lean = lerpf(0.3, -0.45, (sw - SWING_TIME * 0.75) / (SWING_TIME * 0.25))
		else:
			lean = lerpf(-0.45, 0.0, minf(1.0, (sw - SWING_TIME) / SWING_BACK))
	var basis := Basis(Vector3.UP, z["yaw"]) * Basis(Vector3.BACK, sway) * Basis(Vector3.RIGHT, lean - z["fall"] * PI / 2.0)
	var at: Vector3 = z["pos"] + Vector3(0, z["y"] + absf(sway) * 0.3, 0)
	_zombie_mm.set_instance_transform(z["slot"], Transform3D(basis, at))
	var tint := Color(1, 1, 1)
	if z["flash"] > 0.0:
		tint = Color(1.8, 0.7, 0.6)
	elif z["chill"] > 0.0:
		tint = Color(0.6, 0.85, 1.6)
	elif z.get("burn", 0.0) > 0.0:
		tint = Color(1.8, 0.8, 0.3)
	elif z.get("snare", 0.0) > 0.0:
		tint = Color(0.6, 1.3, 0.5)
	_zombie_mm.set_instance_color(z["slot"], tint)


func _hide_slot(slot: int) -> void:
	if _zombie_mm != null:
		_zombie_mm.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0)))


# --- Shooting -----------------------------------------------------------------------------

# A held gun's numbers: a forged one has its own name, hits twice as hard,
# goes through one more, holds half as much again (twice the spare ammo),
# and its oddity (chain, chill, splash, fire, toll, roots) goes further.
func _spec(g: Dictionary) -> Dictionary:
	var id: String = g["id"]
	if not g.get("up", false):
		return GUNS[id]
	if not _up_specs.has(id):
		var s: Dictionary = GUNS[id].duplicate()
		s["name"] = FORGED_NAMES.get(id, "Forged " + s["name"])
		for k in ["chill", "burn", "snare", "knock", "cone"]:
			if s.has(k):
				s[k] = s[k] * 1.5
		if s.has("chain"):
			s["chain"] = int(s["chain"]) + 2
		if s.has("splash"):
			s["splash"] = s["splash"] + 1.0
		s["damage"] = s["damage"] * 2.0
		s["mag"] = int(ceil(s["mag"] * 1.5))
		s["reserve"] = int(s["reserve"]) * 2
		s["pierce"] = int(s["pierce"]) + 1
		_up_specs[id] = s
	return _up_specs[id]


func _gun() -> Dictionary:
	return guns[gun_index] if gun_index < guns.size() else {}


func _rate() -> float:
	var g := _gun()
	if g.is_empty():
		return 0.3
	return _spec(g)["rate"] / (1.33 if "rattle_rum" in tonics else 1.0)


func _gun_frame(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			_finish_reload()
	var g := _gun()
	if _trigger and not g.is_empty() and _spec(g)["auto"] and _cooldown <= 0.0:
		_fire()


func _fire() -> void:
	var g := _gun()
	if g.is_empty() or _cooldown > 0.0 or _reload_t > 0.0:
		return
	if int(g["mag"]) <= 0:
		_sound("click", null, 0.6)
		_reload()
		return
	var spec: Dictionary = _spec(g)
	if effects.has("one_shot"):
		spec = spec.duplicate()
		spec["one_shot"] = true
	g["mag"] = int(g["mag"]) - 1
	_cooldown = _rate()
	var hand := ctx.get("right") as Node3D
	if hand == null or _arena == null:
		return
	var muzzle := _arena.to_local(hand.global_transform * Vector3(0, 0.02, -spec["len"] - 0.05))
	var ahead := (_arena.global_transform.basis.inverse() * -hand.global_transform.basis.z).normalized()
	var im := _tracer.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	if spec.has("cone"):
		_toll(muzzle, ahead, spec)
	for p in (0 if spec.has("cone") else int(spec["pellets"])):
		var dir := _spread(ahead, spec["spread"])
		var end := _shoot_ray(muzzle, dir, spec)
		im.surface_set_color(Color(0.6, 0.9, 1.0) if spec.has("chill") else Color(1.0, 0.45, 0.1) if spec.has("burn") \
			else Color(0.45, 0.8, 0.3) if spec.has("snare") else Color(1.0, 0.85, 0.4))
		im.surface_add_vertex(muzzle)
		im.surface_add_vertex(end)
		if spec.has("chain"):
			_chain_from(end, spec, im)
	im.surface_end()
	_tracer.visible = true
	_tracer_left = 0.05
	if _flash:
		_flash.visible = true
	var kind := "shot_heavy" if spec["damage"] >= 150.0 or spec["pellets"] > 1 else "shot"
	_sound(kind, hand.global_position, 0.9, 1.25 if spec["auto"] else 1.0)
	_pulse("right", 0.6 if kind == "shot" else 1.0, 0.06)
	_update_ammo()
	if int(g["mag"]) <= 0 and int(g["reserve"]) > 0:
		_reload()


func _spread(ahead: Vector3, degrees: float) -> Vector3:
	if degrees <= 0.0:
		return ahead
	var side := ahead.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var up := side.cross(ahead).normalized()
	var a := _rng.randf() * TAU
	var r := deg_to_rad(degrees) * sqrt(_rng.randf())
	return (ahead + (side * cos(a) + up * sin(a)) * tan(r)).normalized()


# One shot along dir: hits the nearest of the dead (through up to "pierce"
# of them) before a wall. Where it stops.
func _shoot_ray(from: Vector3, dir: Vector3, spec: Dictionary) -> Vector3:
	var wall_t := _wall_hit(from, dir)
	var hits := []  # [t, zombie, head]
	for z in _zombies:
		if z["state"] == "dying" or (z["state"] == "rise" and z["t"] < RISE_TIME * 0.5):
			continue
		var base: Vector3 = z["pos"] + Vector3(0, z["y"], 0)
		var th := _ray_sphere(from, dir, base + Vector3(0, HEAD_Y, 0), HEAD_R)
		var tb := _ray_capsule(from, dir, base + Vector3(0, BODY_FROM, 0), base + Vector3(0, BODY_TO, 0), BODY_R)
		var t := minf(th, tb)
		if t < wall_t:
			var head := (from + dir * t).y - base.y > HEAD_Y - HEAD_R - 0.02  # the neck counts
			hits.append([t, z, head])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	var end_t := minf(wall_t, MAX_RANGE)
	var through := 0
	for h in hits:
		_damage(h[1], spec["damage"] * (2.0 if h[2] else 1.0), h[2], spec)
		through += 1
		if through >= int(spec["pierce"]):
			end_t = h[0]
			break
	var end := from + dir * end_t
	if spec.has("splash"):
		_splash(end, spec)
	return end


func _wall_hit(from: Vector3, dir: Vector3) -> float:
	var best_t := INF
	for box: AABB in _walls:
		var t := _ray_box(from, dir, box)
		if t < best_t:
			best_t = t
	if dir.y < -0.001:
		best_t = minf(best_t, -from.y / dir.y)  # the ground
	return best_t


static func _ray_box(from: Vector3, dir: Vector3, box: AABB) -> float:
	var t0 := 0.0
	var t1 := INF
	for i in 3:
		var o := from[i]
		var d := dir[i]
		var lo := box.position[i]
		var hi := box.end[i]
		if absf(d) < 1e-6:
			if o < lo or o > hi:
				return INF
			continue
		var a := (lo - o) / d
		var b := (hi - o) / d
		if a > b:
			var s := a
			a = b
			b = s
		t0 = maxf(t0, a)
		t1 = minf(t1, b)
		if t0 > t1:
			return INF
	return t0


static func _ray_sphere(from: Vector3, dir: Vector3, centre: Vector3, r: float) -> float:
	var oc := from - centre
	var b := oc.dot(dir)
	var c := oc.dot(oc) - r * r
	var h := b * b - c
	if h < 0.0:
		return INF
	var t := -b - sqrt(h)
	return t if t >= 0.0 else INF


# A vertical-ish capsule: the nearest the ray passes the segment a-b.
static func _ray_capsule(from: Vector3, dir: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var best_t := INF
	var steps := 6
	for i in steps + 1:
		var c := a.lerp(b, float(i) / steps)
		var t := _ray_sphere(from, dir, c, r)
		if t < best_t:
			best_t = t
	return best_t


func _damage(z: Dictionary, amount: float, head: bool, spec: Dictionary) -> void:
	if z["state"] == "dying":
		return
	z["hp"] -= INF if spec.get("one_shot", false) or effects.has("one_shot") else amount
	z["flash"] = 0.08
	if spec.has("chill"):
		z["chill"] = spec["chill"]
	if spec.has("snare"):
		z["snare"] = spec["snare"]
	if spec.has("burn"):
		_set_alight(z, spec["burn"])
	if z["hp"] <= 0.0:
		_kill(z, head, spec.get("knife", false))
	else:
		_add_points(10)
		_sound("hit", _arena.to_global(z["pos"] + Vector3(0, 1.2, 0)), 0.5)


func _kill(z: Dictionary, head: bool, knife: bool) -> void:
	kills += 1
	if head:
		headshots += 1
	_add_points(130 if knife else (100 if head else 60))
	_set_state(z, "dying")
	if _drops_round < DROPS_A_ROUND and _rng.randf() < (DROP_READY_CHANCE if _drop_ready else DROP_CHANCE):
		_drop_ready = false
		_add_drop(_deal_drop(), z["pos"])
	z["chill"] = 0.0
	z["burn"] = 0.0
	z["snare"] = 0.0
	z["swing"] = -1.0
	_sound("hit", _arena.to_global(z["pos"] + Vector3(0, 1.2, 0)), 0.8, 0.7)


# Emberwick: it burns for a while, and those right next to it catch too
# (for half as long; they don't pass it on).
func _set_alight(z: Dictionary, seconds: float, spread := true) -> void:
	z["burn"] = maxf(z["burn"], seconds)
	if not spread:
		return
	for o in _zombies:
		if o != z and o["state"] != "dying" and o["burn"] <= 0.0 and (o["pos"] as Vector3).distance_to(z["pos"]) < 1.5:
			_set_alight(o, seconds * 0.5, false)


# Gravebell: hurts and throws back every one in front of you (in reach, in
# BELL_DEGREES of where you aim, no wall between), whether or not it hit.
func _toll(from: Vector3, ahead: Vector3, spec: Dictionary) -> bool:
	var reach: float = spec["cone"]
	var any := false
	for z in _zombies.duplicate():
		if z["state"] == "dying":
			continue
		var centre: Vector3 = z["pos"] + Vector3(0, 1.1, 0)
		var to := centre - from
		var d := to.length()
		if d > reach or d < 0.01 or rad_to_deg(ahead.angle_to(to)) > BELL_DEGREES or _wall_hit(from, to / d) < d:
			continue
		any = true
		_damage(z, spec["damage"] * (1.0 - 0.5 * d / reach), false, {"pierce": 1})
		if z["state"] in ["chase", "approach"]:
			var push := Vector3(to.x, 0, to.z).normalized()
			var moved := 0.0
			while moved < float(spec["knock"]):
				var next: Vector3 = z["pos"] + push * 0.25
				var c := _cell_of(next)
				if c < 0 or _blocked[c] == 1 or (z["state"] == "chase" and _room_at(next).is_empty()):
					break
				z["pos"] = next
				moved += 0.25
	_boom.position = from + ahead * 1.2
	_boom.scale = Vector3.ONE * 0.6
	_boom.visible = true
	_boom_left = 0.12
	_sound("boom", _arena.to_global(from), 0.8, 1.8)
	return any


func _splash(at: Vector3, spec: Dictionary) -> void:
	var radius: float = spec["splash"]
	for z in _zombies.duplicate():
		if z["state"] == "dying":
			continue
		var centre: Vector3 = z["pos"] + Vector3(0, 1.0, 0)
		var d := centre.distance_to(at)
		if d < radius:
			_damage(z, spec["damage"] * (1.0 - 0.6 * d / radius), false, {"pierce": 1})
	_boom.position = at
	_boom.scale = Vector3.ONE * radius * 0.6
	_boom.visible = true
	_boom_left = 0.18
	_sound("boom", _arena.to_global(at), 1.0)


# The Thunderjug's bolt jumps on to the nearest others.
func _chain_from(at: Vector3, spec: Dictionary, im: ImmediateMesh) -> void:
	var from := at
	var done := []
	for i in int(spec["chain"]):
		var next := {}
		var gap := 4.0
		for z in _zombies:
			if z["state"] == "dying" or z in done:
				continue
			var c: Vector3 = z["pos"] + Vector3(0, 1.2, 0)
			var d := c.distance_to(from)
			if d < gap and d > 0.3:
				gap = d
				next = z
		if next.is_empty():
			break
		done.append(next)
		var c: Vector3 = next["pos"] + Vector3(0, 1.2, 0)
		im.surface_set_color(Color(0.5, 0.7, 1.0))
		im.surface_add_vertex(from)
		im.surface_add_vertex(c)
		_damage(next, spec["damage"] * 0.7, false, {"pierce": 1})
		from = c
	if not done.is_empty():
		_sound("zap", _arena.to_global(at), 0.7)


func _reload() -> void:
	var g := _gun()
	if g.is_empty() or _reload_t > 0.0 or int(g["reserve"]) <= 0 or int(g["mag"]) >= int(_spec(g)["mag"]):
		return
	_reload_t = _spec(g)["reload"] * (0.5 if "quickhands" in tonics else 1.0)
	_sound("reload", null, 0.6)
	if _ammo_label:
		_ammo_label.text = "reloading"


func _finish_reload() -> void:
	_reload_t = 0.0
	var g := _gun()
	if g.is_empty():
		return
	var need: int = int(_spec(g)["mag"]) - int(g["mag"])
	var take := mini(need, int(g["reserve"]))
	g["mag"] = int(g["mag"]) + take
	g["reserve"] = int(g["reserve"]) - take
	_sound("click", null, 0.5, 1.4)
	_update_ammo()


func _switch_gun() -> void:
	if guns.size() < 2:
		return
	gun_index = (gun_index + 1) % guns.size()
	_reload_t = 0.0
	_cooldown = 0.3
	_show_gun()
	_sound("click", null, 0.5, 0.8)


# --- The knife -----------------------------------------------------------------------------

func _knife_frame(delta: float) -> void:
	var hand := ctx.get("left") as Node3D
	if hand == null:
		return
	var tip := _arena.to_local(hand.global_transform * Vector3(0, 0, -0.18))
	var speed := tip.distance_to(_knife_prev) / maxf(delta, 0.001)
	_knife_prev = tip
	_knife_cd = maxf(0.0, _knife_cd - delta)
	if _knife_cd > 0.0 or speed < KNIFE_SPEED or speed > 30.0:
		return
	for z in _zombies:
		if z["state"] in ["dying", "rise", "climb"]:
			continue
		var body: Vector3 = z["pos"] + Vector3(0, clampf(tip.y, 0.6, HEAD_Y), 0)
		if body.distance_to(tip) < KNIFE_REACH:
			_knife_cd = KNIFE_TIME
			_damage(z, KNIFE_DAMAGE, false, {"knife": true, "pierce": 1})
			_pulse("left", 1.0, 0.1)
			return


# --- Using things (A) ------------------------------------------------------------------------

func _use_frame(delta: float, here: Vector3) -> void:
	_use_scan -= delta
	if _use_scan <= 0.0:
		_use_scan = 0.1
		var found := _nearest_use(here)
		if found != _use_target:
			_use_target = found
			_repair_t = 0.0
		_show_prompt()
	if _use_held and _use_target.get("kind") == "window":
		_repair_t += delta
		if _repair_t >= REPAIR_TIME * (0.6 if "quickhands" in tonics else 1.0):
			_repair_t = 0.0
			_repair(_use_target["id"])


func _nearest_use(here: Vector3) -> Dictionary:
	var flat := Vector3(here.x, 0, here.z)
	var found := {}
	var gap := REACH
	for u in _uses:
		if u["kind"] == "door" and not _debris[u["id"]].visible:
			continue
		if u["kind"] == "part" and u["id"] in parts:
			continue
		var d := flat.distance_to(u["at"])
		if d < gap:
			gap = d
			found = u
	return found


func _show_prompt() -> void:
	if _prompt == null:
		return
	var text := _prompt_text(_use_target)
	_prompt.visible = not text.is_empty()
	if text.is_empty():
		return
	_prompt.text = text
	_prompt.position = (_use_target["at"] as Vector3) + Vector3(0, 1.3, 0)


func _prompt_text(u: Dictionary) -> String:
	match u.get("kind", ""):
		"gun":
			var g: Dictionary = GUNS[u["id"]]
			return ("A: ammo for %s  %d" % [g["name"], g["cost"] / 2]) if _holding(u["id"]) >= 0 else "A: buy %s  %d" % [g["name"], g["cost"]]
		"tonic":
			var t: Dictionary = TONICS[u["id"]]
			if u["id"] in tonics:
				return ""
			if not power and not u["id"] in NO_POWER_TONICS:
				return "Needs power"
			if u["id"] == "second_wind" and second_winds >= SECOND_WINDS:
				return "Empty"
			return "A: drink %s  %d" % [t["name"], t["cost"]]
		"door":
			var d := _door(u["id"])
			return "A: clear the way  %d" % d["cost"]
		"crate":
			match _crate_state:
				"idle":
					return "A: Lucky Crate  %d" % CRATE_COST
				"offer":
					return "A: take the %s" % GUNS[_crate_gun]["name"]
			return ""
		"window":
			return "Hold A: board up" if int(planks[u["id"]]) < PLANKS else ""
		"generator":
			return "" if power else "A: start the generator"
		"anvil":
			if not power:
				return "Needs power"
			match _anvil_state:
				"idle":
					var g := _gun()
					if g.is_empty() or g.get("up", false):
						return "Already forged"
					return "A: forge the %s  %d" % [GUNS[g["id"]]["name"], ANVIL_COST]
				"offer":
					return "A: take the %s" % _spec(_anvil_gun)["name"]
			return ""
		"part":
			return "" if u["id"] in parts else "A: pick up the shield part"
		"bench":
			if shield > 0:
				return ""
			if parts.size() < _map["parts"].size():
				return "Shield parts: %d of %d" % [parts.size(), _map["parts"].size()]
			return "A: build the Barn-Door Shield" if not shield_built else "A: rebuild the shield  %d" % SHIELD_REBUILD
	return ""


func _use() -> void:
	if _use_target.is_empty():
		_use_target = _nearest_use(_cam_local())
	var u := _use_target
	match u.get("kind", ""):
		"gun":
			buy_gun(u["id"])
		"tonic":
			buy_tonic(u["id"])
		"door":
			open_door(u["id"])
		"crate":
			use_crate()
		"generator":
			power_on()
		"anvil":
			use_anvil()
		"part":
			pick_part(u["id"])
		"bench":
			build_shield()
	_show_prompt()


func _holding(id: String) -> int:
	for i in guns.size():
		if guns[i]["id"] == id:
			return i
	return -1


func _spend(cost: int) -> bool:
	if points < cost:
		_sound("deny", null, 0.6)
		return false
	points -= cost
	_sound("buy", null, 0.7)
	points_changed.emit(points)
	_update_hud()
	return true


func _add_points(n: int) -> void:
	if effects.has("double_pay"):
		n *= 2
	points += n
	earned += n
	if earned >= _drop_goal:
		_drop_ready = true
		_drop_gap *= DROP_GOAL_GROWTH
		_drop_goal += _drop_gap
	points_changed.emit(points)
	_update_hud()


# Buys a wall gun, or its ammo when you have it. Whether it was bought.
func buy_gun(id: String) -> bool:
	if not GUNS.has(id) or GUNS[id]["cost"] <= 0:
		return false
	var have := _holding(id)
	var cost: int = GUNS[id]["cost"] / 2 if have >= 0 else GUNS[id]["cost"]
	if have >= 0:
		var spec := _spec(guns[have])
		if int(guns[have]["reserve"]) >= int(spec["reserve"]) and int(guns[have]["mag"]) >= int(spec["mag"]):
			return false  # full already
		if guns[have].get("up", false):
			cost = FORGED_AMMO_COST
		if not _spend(cost):
			return false
		guns[have]["mag"] = spec["mag"]
		guns[have]["reserve"] = spec["reserve"]
		_update_ammo()
		return true
	if not _spend(cost):
		return false
	_give_gun(id)
	return true


func _give_gun(id: String) -> void:
	var have := _holding(id)
	var fresh := {"id": id, "mag": GUNS[id]["mag"], "reserve": GUNS[id]["reserve"]}
	if have >= 0:
		guns[have] = fresh
		gun_index = have
	elif guns.size() < 2:
		guns.append(fresh)
		gun_index = guns.size() - 1
	else:
		guns[gun_index] = fresh
	_reload_t = 0.0
	_show_gun()


func buy_tonic(id: String) -> bool:
	if not TONICS.has(id) or id in tonics:
		return false
	if not power and not id in NO_POWER_TONICS:
		_sound("deny", null, 0.6)
		return false
	if id == "second_wind" and second_winds >= SECOND_WINDS:
		return false
	if not _spend(TONICS[id]["cost"]):
		return false
	tonics.append(id)
	if id == "second_wind":
		second_winds += 1
	if id == "ironbark":
		health = _max_health()
	_sound("gulp", null, 0.8)
	_update_hud()
	return true


func _door(id: String) -> Dictionary:
	for d in _map["doors"]:
		if d["id"] == id:
			return d
	return {}


func open_door(id: String) -> bool:
	var d := _door(id)
	if d.is_empty() or not _debris.has(id) or not _debris[id].visible:
		return false
	if not _spend(d["cost"]):
		return false
	_debris[id].visible = false
	for room in _map["rooms"]:
		if _debris[id].has_meta("label_" + room):
			_debris[id].get_meta("label_" + room).visible = false
	for room in d["rooms"]:
		open_rooms[room] = true
		_in_dirty = true
	_sound("rip", _arena.to_global(Vector3(d["at"][0], 1.0, d["at"][1])), 1.0, 0.7)
	return true


func _repair(id: String) -> void:
	if int(planks[id]) >= PLANKS:
		return
	var wnd := _window(id)
	for z in _zombies:
		if z["window"] == id and z["state"] == "climb":
			return  # one's coming through
	planks[id] = int(planks[id]) + 1
	_show_planks(id)
	if _repair_points < REPAIR_CAP:
		_repair_points += 10
		_add_points(10)
	_sound("nail", _arena.to_global(Vector3(wnd["at"][0], 1.3, wnd["at"][1])), 0.8)
	_pulse("right", 0.4, 0.05)
	_show_prompt()


# The Lucky Crate: pay to shuffle, then take what it offers.
func use_crate() -> bool:
	match _crate_state:
		"idle":
			if not _spend(CRATE_COST):
				return false
			var pool := CRATE_GUNS.filter(func(id): return _holding(id) < 0)
			_crate_gun = pool[_rng.randi() % pool.size()]
			_crate_state = "shuffle"
			_crate_t = CRATE_SHUFFLE
			_sound("crate", _arena.to_global(Vector3(_map["crate"]["at"][0], 1.0, _map["crate"]["at"][1])), 0.9)
			return true
		"offer":
			_give_gun(_crate_gun)
			_crate_state = "idle"
			_crate_label.text = "Lucky Crate\n%d" % CRATE_COST
			if _crate_show:
				_crate_show.visible = false
			_sound("buy", null, 0.8, 1.3)
			return true
	return false


func _crate_frame(delta: float) -> void:
	if _crate_state == "idle" or _crate_label == null:
		return
	_crate_t -= delta
	match _crate_state:
		"shuffle":
			var id: String = CRATE_GUNS[int(_crate_t * 12.0) % CRATE_GUNS.size()]
			_crate_label.text = GUNS[id]["name"]
			_crate_show.mesh = _gun_mesh_for(id)
			_crate_show.visible = true
			if _crate_t <= 0.0:
				_crate_state = "offer"
				_crate_t = CRATE_OFFER
				_crate_label.text = "%s!\nA to take it" % GUNS[_crate_gun]["name"]
				_crate_show.mesh = _gun_mesh_for(_crate_gun)
				_show_prompt()
		"offer":
			if _crate_t <= 0.0:
				_crate_state = "idle"
				_crate_label.text = "Lucky Crate\n%d" % CRATE_COST
				if _crate_show:
					_crate_show.visible = false
				_show_prompt()


# --- Power, the Anvil, the shield --------------------------------------------------------

func _build_power_things() -> void:
	_power_lamps.clear()
	# The generator: a squat engine on the yard's back wall.
	var g_at := Vector3(_map["generator"]["at"][0], 0, _map["generator"]["at"][1])
	var g_in := Vector3(_map["generator"]["in"][0], 0, _map["generator"]["in"][1])
	var g_yaw := atan2(g_in.x, g_in.z)
	var engine := _box(_arena, Vector3(1.0, 0.8, 0.6), g_at + g_in * (WALL_T / 2.0 + 0.32) + Vector3(0, 0.4, 0), _mats["machine"])
	_tag(engine, "generator")
	engine.rotation.y = g_yaw
	var tank := _box(_arena, Vector3(0.7, 0.25, 0.4), g_at + g_in * (WALL_T / 2.0 + 0.32) + Vector3(0, 0.92, 0), _mats["crate"])
	tank.rotation.y = g_yaw
	var lamp := _box(_arena, Vector3(0.12, 0.12, 0.02), g_at + g_in * (WALL_T / 2.0 + 0.63) + Vector3(0.3, 0.6, 0), _mats["off"])
	lamp.rotation.y = g_yaw
	_power_lamps.append(lamp)
	_generator_label = _label(_arena, "Generator\nno power", 46, Color(0.9, 0.9, 0.85))
	_generator_label.position = g_at + g_in * (WALL_T / 2.0 + 0.4) + Vector3(0, 1.45, 0)
	_generator_label.rotation.y = g_yaw
	_uses.append({"kind": "generator", "id": "generator", "at": g_at + g_in * 1.0, "label": _generator_label})
	# The Anvil: an anvil on a stump, glowing once the power's on.
	var a_at := Vector3(_map["anvil"]["at"][0], 0, _map["anvil"]["at"][1])
	var a_in := Vector3(_map["anvil"]["in"][0], 0, _map["anvil"]["in"][1])
	var a_yaw := atan2(a_in.x, a_in.z)
	var spot := a_at + a_in * (WALL_T / 2.0 + 0.45)
	_box(_arena, Vector3(0.5, 0.6, 0.5), spot + Vector3(0, 0.3, 0), _mats["trunk"]).rotation.y = a_yaw
	var anvil_top := _box(_arena, Vector3(0.7, 0.18, 0.28), spot + Vector3(0, 0.72, 0), _mats["iron"])
	anvil_top.rotation.y = a_yaw
	_tag(anvil_top, "anvil")
	_box(_arena, Vector3(0.3, 0.12, 0.18), spot + Vector3(0, 0.6, 0), _mats["iron"]).rotation.y = a_yaw
	var glow := _box(_arena, Vector3(0.72, 0.02, 0.3), spot + Vector3(0, 0.82, 0), _mats["off"])
	glow.rotation.y = a_yaw
	_power_lamps.append(glow)
	_anvil_label = _label(_arena, "The Anvil  %d\nmakes your gun stronger" % ANVIL_COST, 44, Color(1.0, 0.7, 0.4))
	_anvil_label.position = spot + Vector3(0, 1.5, 0)
	_anvil_label.rotation.y = a_yaw
	_anvil_show = MeshInstance3D.new()
	_anvil_show.material_override = _mats["forged"]
	_anvil_show.position = spot + Vector3(0, 1.05, 0)
	_anvil_show.rotation.y = a_yaw + PI / 2.0
	_anvil_show.scale = Vector3.ONE * 1.5
	_anvil_show.visible = false
	_arena.add_child(_anvil_show)
	_uses.append({"kind": "anvil", "id": "anvil", "at": a_at + a_in * 1.1, "label": _anvil_label})
	# The workbench, and the shield's parts lying about.
	var b_at := Vector3(_map["bench"]["at"][0], 0, _map["bench"]["at"][1])
	var b_in := Vector3(_map["bench"]["in"][0], 0, _map["bench"]["in"][1])
	var b_yaw := atan2(b_in.x, b_in.z)
	_box(_arena, Vector3(1.2, 0.08, 0.6), b_at + b_in * (WALL_T / 2.0 + 0.32) + Vector3(0, 0.85, 0), _mats["plank"]).rotation.y = b_yaw
	for side in [-0.5, 0.5]:
		var across := Vector3(-b_in.z, 0, b_in.x)
		_box(_arena, Vector3(0.08, 0.85, 0.5), b_at + b_in * (WALL_T / 2.0 + 0.32) + across * side + Vector3(0, 0.42, 0), _mats["plank"]).rotation.y = b_yaw
	var b_label := _label(_arena, "Workbench\nfind 3 shield parts", 40, Color(0.9, 0.85, 0.7))
	b_label.position = b_at + b_in * (WALL_T / 2.0 + 0.3) + Vector3(0, 1.6, 0)
	b_label.rotation.y = b_yaw
	_uses.append({"kind": "bench", "id": "bench", "at": b_at + b_in * 0.95, "label": b_label})
	_part_nodes.clear()
	for i in _map["parts"].size():
		var at := Vector3(_map["parts"][i][0], 0, _map["parts"][i][1])
		var bundle := Node3D.new()
		_arena.add_child(bundle)
		bundle.position = at
		bundle.rotation.y = 0.7 * i
		_box(bundle, [Vector3(0.6, 0.05, 0.16), Vector3(0.16, 0.06, 0.45), Vector3(0.3, 0.08, 0.3)][i], Vector3(0, 0.05, 0), _mats["plank"])
		_box(bundle, Vector3(0.06, 0.06, 0.06), Vector3(0.12, 0.12, 0.0), _flat_glow(Color(0.95, 0.85, 0.4)))  # a glint, so it can be found
		_part_nodes.append(bundle)
		_uses.append({"kind": "part", "id": i, "at": at, "label": null})


# A new game: no power, the parts back where they lie.
func _reset_power() -> void:
	power = false
	for lamp in _power_lamps:
		if is_instance_valid(lamp):
			lamp.material_override = _mats["off"]
	if _generator_label:
		_generator_label.text = "Generator\nno power"
	for node in _part_nodes:
		if is_instance_valid(node):
			node.visible = true


func power_on() -> bool:
	if power or _arena == null:
		return false
	power = true
	for lamp in _power_lamps:
		if is_instance_valid(lamp):
			lamp.material_override = _mats["lamp_on"]
	if _generator_label:
		_generator_label.text = "Generator\nrunning"
	_sound("boom", _arena.to_global(Vector3(_map["generator"]["at"][0], 1.0, _map["generator"]["at"][1])), 0.7, 1.6)
	_sound("bell", null, 0.5, 1.5)
	return true


# The Anvil: pay, leave the gun on it for a moment, take it back forged.
func use_anvil() -> bool:
	if not power:
		_sound("deny", null, 0.6)
		return false
	match _anvil_state:
		"idle":
			var g := _gun()
			if g.is_empty() or g.get("up", false) or guns.size() < 1:
				return false
			if not _spend(ANVIL_COST):
				return false
			_anvil_gun = g
			guns.remove_at(gun_index)
			if guns.is_empty():
				guns.append({"id": "m1911", "mag": 0, "reserve": 0})  # empty hands: a spent M1911 till it's back
			gun_index = 0
			_show_gun()
			_anvil_state = "working"
			_anvil_t = ANVIL_TIME
			_anvil_show.mesh = _gun_mesh_for(_anvil_gun["id"])
			_anvil_show.visible = true
			_anvil_label.text = "Forging..."
			_sound("nail", _arena.to_global(_anvil_show.position), 1.0, 0.5)
			return true
		"offer":
			var forged := {"id": _anvil_gun["id"], "up": true}
			var spec := _spec(forged)
			forged["mag"] = spec["mag"]
			forged["reserve"] = spec["reserve"]
			if guns.size() == 1 and guns[0]["id"] == "m1911" and int(guns[0]["mag"]) == 0 and int(guns[0]["reserve"]) == 0:
				guns.clear()  # the stand-in goes
			if guns.size() < 2:
				guns.append(forged)
				gun_index = guns.size() - 1
			else:
				guns[gun_index] = forged
			_anvil_done()
			_show_gun()
			_sound("buy", null, 0.8, 0.8)
			return true
	return false


func _anvil_frame(delta: float) -> void:
	if _anvil_state == "idle" or _anvil_label == null:
		return
	_anvil_t -= delta
	if _anvil_state == "working" and _anvil_t <= 0.0:
		_anvil_state = "offer"
		_anvil_t = ANVIL_OFFER
		_anvil_label.text = "%s!\nA to take it" % _spec({"id": _anvil_gun["id"], "up": true})["name"]
		_sound("bell", _arena.to_global(_anvil_show.position), 0.6, 2.0)
		_show_prompt()
	elif _anvil_state == "offer" and _anvil_t <= 0.0:
		_anvil_done()  # not taken: gone, like the crate's
		_show_prompt()


func _anvil_done() -> void:
	_anvil_state = "idle"
	_anvil_gun = {}
	if _anvil_show:
		_anvil_show.visible = false
	if _anvil_label:
		_anvil_label.text = "The Anvil  %d\nmakes your gun stronger" % ANVIL_COST


func pick_part(index) -> bool:
	if typeof(index) != TYPE_INT or index < 0 or index >= _map["parts"].size() or index in parts:
		return false
	parts.append(index)
	if index < _part_nodes.size() and is_instance_valid(_part_nodes[index]):
		_part_nodes[index].visible = false
	_sound("nail", null, 0.7, 1.4)
	_pulse("right", 0.5, 0.08)
	return true


func build_shield() -> bool:
	if shield > 0 or parts.size() < _map["parts"].size():
		if parts.size() < _map["parts"].size():
			_sound("deny", null, 0.6)
		return false
	if shield_built and not _spend(SHIELD_REBUILD):
		return false
	shield_built = true
	_wear_shield(true)
	_sound("nail", null, 1.0)
	_update_hud()
	return true


# The shield on the left forearm: planks nailed across a frame, facing out
# the way the hand points.
func _wear_shield(on: bool) -> void:
	if not on:
		shield = 0
		if _shield_node != null and is_instance_valid(_shield_node):
			_shield_node.queue_free()
		_shield_node = null
		return
	shield = SHIELD_BLOCKS
	var left := ctx.get("left") as Node3D
	if left == null or _shield_node != null:
		return
	_shield_node = Node3D.new()
	_shield_node.name = "holdout_shield"
	left.add_child(_shield_node)
	_shield_node.position = Vector3(0.0, -0.02, 0.12)
	for i in 4:
		var plank := _box(_shield_node, Vector3(0.5, 0.11, 0.025), Vector3(0, -0.18 + i * 0.12, 0), _mats["plank"])
		plank.rotation.z = deg_to_rad([3.0, -2.0, 4.0, -3.0][i])
	_box(_shield_node, Vector3(0.06, 0.48, 0.03), Vector3(-0.18, 0, 0.02), _mats["debris"])
	_box(_shield_node, Vector3(0.06, 0.48, 0.03), Vector3(0.18, 0, 0.02), _mats["debris"])
	_shield_node.rotation_degrees = Vector3(0, 90, 0)  # flat along the forearm, its face out to the side the hand points


# --- Drops -------------------------------------------------------------------------------

func _deal_drop() -> String:
	if _drop_deck.is_empty():
		_drop_deck = DROPS.keys()
		for i in range(_drop_deck.size() - 1, 0, -1):  # shuffled with the game's own dice
			var j := _rng.randi() % (i + 1)
			var keep = _drop_deck[i]
			_drop_deck[i] = _drop_deck[j]
			_drop_deck[j] = keep
	return _drop_deck.pop_back()


func _add_drop(kind: String, at: Vector3) -> void:
	if _arena == null or not DROPS.has(kind):
		return
	_drops_round += 1
	var spot := Vector3(at.x, 0, at.z)
	if _room_at(spot).is_empty():
		var wnd_room := _player_room
		spot = _inside(spot, wnd_room)  # dropped outside: put it just inside
	var node := Node3D.new()
	_arena.add_child(node)
	node.position = spot + Vector3(0, 0.9, 0)
	var token := _box(node, Vector3(0.28, 0.28, 0.06), Vector3.ZERO, _flat_glow(DROPS[kind]["color"]))
	token.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var label := _label(node, DROPS[kind]["name"], 40, DROPS[kind]["color"].lightened(0.3))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.double_sided = true
	label.position = Vector3(0, 0.3, 0)
	_drops.append({"kind": kind, "node": node, "pos": spot, "life": DROP_LIFE, "token": token})
	_sound("crate", _arena.to_global(node.position), 0.4, 1.8)


func _drops_frame(delta: float, here: Vector3) -> void:
	var flat := Vector3(here.x, 0, here.z)
	for d in _drops.duplicate():
		d["life"] -= delta
		var node: Node3D = d["node"]
		(d["token"] as Node3D).rotation.y += delta * 2.5
		node.visible = d["life"] > 5.0 or int(d["life"] * 4.0) % 2 == 0  # blinks as it's about to go
		if flat.distance_to(d["pos"]) < DROP_REACH:
			_take_drop(d["kind"])
			node.queue_free()
			_drops.erase(d)
		elif d["life"] <= 0.0:
			node.queue_free()
			_drops.erase(d)


func _take_drop(kind: String) -> void:
	_sound("bell", null, 0.7, 1.8)
	_sign.text = DROPS[kind]["name"]
	_sign.position = _ahead_of_you(3.0) + Vector3(0, 0.6, 0)
	_sign.visible = true
	_sign_left = 2.0
	match kind:
		"ammo":
			for g in guns:
				var spec := _spec(g)
				g["mag"] = spec["mag"]
				g["reserve"] = spec["reserve"]
			_reload_t = 0.0
			_update_ammo()
		"one_shot", "double_pay":
			effects[kind] = DROP_EFFECT
		"blackout":
			for z in _zombies:
				if z["state"] != "dying":
					_set_state(z, "dying")
					kills += 1
			_add_points(400)
		"hammer":
			for wnd in _map["windows"]:
				planks[wnd["id"]] = PLANKS
				_show_planks(wnd["id"])
			_add_points(200)
	_update_hud()


func _clear_drops() -> void:
	for d in _drops:
		if is_instance_valid(d["node"]):
			d["node"].queue_free()
	_drops.clear()


# --- What you hold and see --------------------------------------------------------------------

# The gun on the right controller, the knife on the left, the wrist label,
# and the red haze when you're hurt; on while a game runs.
func _hold_gear(on: bool) -> void:
	if not on:
		for node in [_gun_node, _knife, _wrist, _hurt]:
			if node != null and is_instance_valid(node):
				node.queue_free()
		_gun_node = null
		_gun_mesh = null
		_flash = null
		_ammo_label = null
		_knife = null
		_wrist = null
		_hurt = null
		for box in _hidden_boxes:
			if is_instance_valid(box):
				box.visible = true
		_hidden_boxes.clear()
		return
	var right := ctx.get("right") as Node3D
	var left := ctx.get("left") as Node3D
	for hand in [right, left]:
		if hand == null:
			continue
		var box := hand.get_node_or_null("Mesh") as Node3D
		if box != null and box.visible:
			box.visible = false
			_hidden_boxes.append(box)
	if right and _gun_node == null:
		_gun_node = Node3D.new()
		_gun_node.name = "holdout_gun"
		right.add_child(_gun_node)
		_gun_mesh = MeshInstance3D.new()
		_gun_mesh.material_override = _mats["gun"]
		_gun_node.add_child(_gun_mesh)
		_flash = MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.04
		ball.height = 0.08
		ball.radial_segments = 8
		ball.rings = 4
		_flash.mesh = ball
		_flash.material_override = _mats["flash"]
		_flash.visible = false
		_gun_node.add_child(_flash)
		_ammo_label = Label3D.new()
		_ammo_label.font_size = 40
		_ammo_label.pixel_size = 0.0008
		_ammo_label.outline_size = 8
		_ammo_label.position = Vector3(0.0, 0.07, 0.03)
		_ammo_label.rotation_degrees = Vector3(-45, 0, 0)
		_gun_node.add_child(_ammo_label)
	if left and _knife == null:
		_knife = Node3D.new()
		_knife.name = "holdout_knife"
		left.add_child(_knife)
		var blade := _box(_knife, Vector3(0.006, 0.03, 0.16), Vector3(0, 0, -0.1), _mats["blade"])
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_box(_knife, Vector3(0.025, 0.03, 0.09), Vector3(0, 0, 0.02), _mats["grip"])
		_wrist = Label3D.new()
		_wrist.font_size = 40
		_wrist.pixel_size = 0.0009
		_wrist.outline_size = 8
		_wrist.position = Vector3(0.0, 0.06, 0.09)
		_wrist.rotation_degrees = Vector3(-50, 0, 0)
		left.add_child(_wrist)
	var cam := ctx.get("camera") as Node3D
	if cam and _hurt == null:
		_hurt = MeshInstance3D.new()
		var haze := SphereMesh.new()
		haze.radius = 0.25
		haze.height = 0.5
		haze.radial_segments = 12
		haze.rings = 6
		haze.flip_faces = true
		_hurt.mesh = haze
		_hurt.material_override = _mats["hurt"].duplicate()
		_hurt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hurt.visible = false
		cam.add_child(_hurt)


func _show_gun() -> void:
	var g := _gun()
	if _gun_mesh == null or g.is_empty():
		return
	_gun_mesh.mesh = _gun_mesh_for(g["id"])
	_flash.position = Vector3(0, 0.02, -GUNS[g["id"]]["len"] - 0.04)
	_gun_mesh.material_override = _mats["forged"] if g.get("up", false) else _mats["gun"]
	_update_ammo()
	_update_hud()


func _update_ammo() -> void:
	var g := _gun()
	if _ammo_label == null or g.is_empty():
		return
	_ammo_label.text = "%d / %d" % [g["mag"], g["reserve"]]
	_ammo_label.modulate = Color(1, 0.4, 0.3) if int(g["mag"]) <= 2 else Color(1, 1, 1)


func _update_hud() -> void:
	if _wrist == null:
		return
	var text := "Round %d\n%d points\n%s" % [maxi(round_number, 1), points, "DOWN" if downed else "Health %d" % int(round(health))]
	if shield > 0:
		text += "\nShield %d/%d" % [shield, SHIELD_BLOCKS]
	for e in effects:
		text += "\n%s %d" % [DROPS[e]["name"], int(ceil(effects[e]))]
	if text != _wrist_text:
		_wrist_text = text
		_wrist.text = text
		_wrist.modulate = Color(1, 0.45, 0.4) if health < _max_health() * 0.5 else Color(1, 0.95, 0.85)


func _show_hurt() -> void:
	if _hurt == null:
		return
	var hurt := 1.0 - health / _max_health()
	_hurt.visible = hurt > 0.05
	if _hurt.visible:
		(_hurt.material_override as StandardMaterial3D).albedo_color = Color(0.6, 0.0, 0.0, clampf(hurt * 0.55, 0.0, 0.5))


func _pulse(hand: String, strength: float, seconds: float) -> void:
	if _controls and _controls.has_method("pulse"):
		_controls.call("pulse", hand, strength, seconds)


# --- Meshes, materials, labels ----------------------------------------------------------

func _make_materials() -> void:
	_mats["ground"] = _flat(Color(0.07, 0.09, 0.06))
	_mats["boards"] = _flat(Color(0.28, 0.2, 0.13))
	_mats["dirt"] = _flat(Color(0.17, 0.14, 0.1))
	_mats["wall"] = _flat(Color(0.33, 0.26, 0.19))
	_mats["plank"] = _flat(Color(0.45, 0.33, 0.2))
	_mats["debris"] = _flat(Color(0.25, 0.22, 0.2))
	_mats["trunk"] = _flat(Color(0.12, 0.09, 0.07))
	_mats["crown"] = _flat(Color(0.05, 0.11, 0.07))
	_mats["chalkboard"] = _flat(Color(0.09, 0.12, 0.1))
	_mats["machine"] = _flat(Color(0.2, 0.18, 0.17))
	_mats["crate"] = _flat(Color(0.35, 0.22, 0.1))
	_mats["lantern"] = _flat_glow(Color(1.0, 0.7, 0.3))
	_mats["chalk"] = _flat_glow(Color(0.85, 0.88, 0.82))
	_mats["off"] = _flat(Color(0.15, 0.15, 0.15))
	_mats["lamp_on"] = _flat_glow(Color(0.5, 1.0, 0.55))
	_mats["iron"] = _flat(Color(0.18, 0.18, 0.2))
	_mats["blade"] = _flat(Color(0.75, 0.78, 0.8))
	_mats["grip"] = _flat(Color(0.15, 0.1, 0.07))
	var zombie := StandardMaterial3D.new()
	zombie.vertex_color_use_as_albedo = true
	zombie.roughness = 1.0
	_mats["zombie"] = zombie
	var gun := StandardMaterial3D.new()
	gun.vertex_color_use_as_albedo = true
	gun.roughness = 0.6
	gun.metallic = 0.3
	_mats["gun"] = gun
	var forged := gun.duplicate() as StandardMaterial3D
	forged.emission_enabled = true
	forged.emission = Color(0.9, 0.35, 0.05)
	forged.emission_energy_multiplier = 0.6
	_mats["forged"] = forged
	var tracer := StandardMaterial3D.new()
	tracer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer.vertex_color_use_as_albedo = true
	_mats["tracer"] = tracer
	_mats["flash"] = _flat_glow(Color(1.0, 0.8, 0.35))
	var boom := StandardMaterial3D.new()
	boom.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	boom.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	boom.albedo_color = Color(1.0, 0.5, 0.15, 0.55)
	_mats["boom"] = boom
	var hurt := StandardMaterial3D.new()
	hurt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hurt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hurt.no_depth_test = true
	hurt.albedo_color = Color(0.6, 0.0, 0.0, 0.0)
	hurt.render_priority = 10
	_mats["hurt"] = hurt


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


func _flat_glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


# Marks a piece for the world's list (lib.gd's add_app_things, when it has
# it): the agent and the inspect / textures tools can then find it by name.
# The same name every time the buildings go up.
func _tag(node: Node, thing_name: String) -> void:
	node.set_meta("slopitect_app_thing", "holdout_" + thing_name)


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node


func _label(parent: Node3D, text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0025
	l.outline_size = 10
	l.modulate = color
	l.double_sided = false  # signs on walls: not read backwards through a doorway
	parent.add_child(l)
	return l


# Boxes into one mesh with vertex colours: one draw.
func _add_box(st: SurfaceTool, centre: Vector3, size: Vector3, color: Color) -> void:
	var h := size / 2.0
	var faces := [
		[Vector3(1, 0, 0), [Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)]],
		[Vector3(0, 1, 0), [Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3(0, -1, 0), [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3(0, 0, 1), [Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
		[Vector3(0, 0, -1), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)]],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var v: Array = f[1]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(color)
			st.set_normal(n)
			st.add_vertex(centre + v[i])


# One of the dead: ragged clothes, grey-green skin, arms out, dim yellow
# eyes. About 1.75 m tall, facing -z.
func _zombie_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin := Color(0.42, 0.5, 0.38)
	var dark := Color(0.32, 0.38, 0.3)
	var shirt := Color(0.36, 0.31, 0.24)
	var trousers := Color(0.17, 0.16, 0.18)
	_add_box(st, Vector3(-0.1, 0.42, 0.0), Vector3(0.14, 0.84, 0.16), trousers)
	_add_box(st, Vector3(0.1, 0.42, 0.02), Vector3(0.14, 0.84, 0.16), trousers)
	_add_box(st, Vector3(0.0, 1.12, 0.0), Vector3(0.4, 0.6, 0.22), shirt)
	_add_box(st, Vector3(0.05, 0.88, -0.1), Vector3(0.22, 0.14, 0.04), dark)  # a tear in the shirt
	_add_box(st, Vector3(-0.25, 1.33, -0.24), Vector3(0.1, 0.1, 0.56), skin)
	_add_box(st, Vector3(0.25, 1.28, -0.2), Vector3(0.1, 0.1, 0.5), skin)
	_add_box(st, Vector3(-0.25, 1.33, -0.55), Vector3(0.11, 0.06, 0.1), dark)
	_add_box(st, Vector3(0.25, 1.28, -0.48), Vector3(0.11, 0.06, 0.1), dark)
	_add_box(st, Vector3(0.0, 1.45, 0.0), Vector3(0.1, 0.06, 0.1), skin)  # neck
	_add_box(st, Vector3(0.0, 1.6, 0.0), Vector3(0.24, 0.26, 0.24), skin)
	_add_box(st, Vector3(0.0, 1.49, -0.04), Vector3(0.18, 0.05, 0.17), dark)  # jaw hanging
	_add_box(st, Vector3(-0.06, 1.63, -0.121), Vector3(0.05, 0.03, 0.01), Color(1.0, 0.85, 0.25))
	_add_box(st, Vector3(0.06, 1.63, -0.121), Vector3(0.05, 0.03, 0.01), Color(1.0, 0.85, 0.25))
	return st.commit()


# Each gun from a handful of boxes in its own colours, pointing -z from the
# hand (the hand holds the grip at the origin): enough of its outline to
# know it at a glance. Made once each, one draw.
func _gun_mesh_for(id: String) -> ArrayMesh:
	if _gun_meshes.has(id):
		return _gun_meshes[id]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steel := Color(0.2, 0.2, 0.22)
	var black := Color(0.09, 0.09, 0.1)
	var wood := Color(0.42, 0.24, 0.12)
	var olive := Color(0.27, 0.3, 0.2)
	for part in _gun_parts(id, steel, black, wood, olive):
		var b := Basis.IDENTITY
		if part.size() > 3:
			b = Basis(Vector3.RIGHT, deg_to_rad(part[3]))
		_add_box_turned(st, part[0], part[1], part[2], b)
	var mesh := st.commit()
	_gun_meshes[id] = mesh
	return mesh


# [centre, size, colour, (tilt about x, degrees)] for each box.
func _gun_parts(id: String, steel: Color, black: Color, wood: Color, olive: Color) -> Array:
	match id:
		"m1911":
			return [[Vector3(0, 0.03, -0.08), Vector3(0.03, 0.035, 0.2), steel],
				[Vector3(0, -0.04, 0.0), Vector3(0.03, 0.1, 0.045), Color(0.35, 0.22, 0.12), -12.0],
				[Vector3(0, -0.005, -0.035), Vector3(0.008, 0.02, 0.04), steel]]
		"double_barrel":
			return [[Vector3(-0.012, 0.03, -0.3), Vector3(0.022, 0.022, 0.5), steel], [Vector3(0.012, 0.03, -0.3), Vector3(0.022, 0.022, 0.5), steel],
				[Vector3(0, 0.015, -0.2), Vector3(0.045, 0.025, 0.2), wood],
				[Vector3(0, 0.01, -0.02), Vector3(0.04, 0.05, 0.08), steel],
				[Vector3(0, -0.01, 0.15), Vector3(0.04, 0.07, 0.26), wood, -10.0]]
		"mp5":
			return [[Vector3(0, 0.03, -0.1), Vector3(0.04, 0.05, 0.28), black],
				[Vector3(0, 0.03, -0.28), Vector3(0.018, 0.018, 0.1), black],
				[Vector3(0, -0.04, -0.14), Vector3(0.022, 0.12, 0.035), black, 18.0],
				[Vector3(0, -0.04, 0.0), Vector3(0.03, 0.09, 0.04), black, -12.0],
				[Vector3(0, 0.05, -0.02), Vector3(0.02, 0.025, 0.04), black],
				[Vector3(0, 0.03, 0.1), Vector3(0.02, 0.04, 0.14), black]]
		"m14":
			return [[Vector3(0, 0.03, -0.42), Vector3(0.018, 0.018, 0.36), steel],
				[Vector3(0, 0.02, -0.2), Vector3(0.045, 0.045, 0.42), wood],
				[Vector3(0, 0.05, -0.1), Vector3(0.03, 0.02, 0.2), steel],
				[Vector3(0, -0.04, -0.08), Vector3(0.03, 0.08, 0.06), black],
				[Vector3(0, -0.01, 0.15), Vector3(0.045, 0.08, 0.3), wood, -8.0]]
		"ak47":
			return [[Vector3(0, 0.03, -0.42), Vector3(0.018, 0.018, 0.22), steel],
				[Vector3(0, 0.025, -0.25), Vector3(0.045, 0.04, 0.16), wood],
				[Vector3(0, 0.04, -0.08), Vector3(0.045, 0.05, 0.22), steel],
				[Vector3(0, -0.05, -0.12), Vector3(0.028, 0.14, 0.045), Color(0.55, 0.33, 0.12), 25.0],
				[Vector3(0, -0.04, 0.0), Vector3(0.03, 0.08, 0.04), wood, -15.0],
				[Vector3(0, 0.0, 0.14), Vector3(0.04, 0.07, 0.24), wood, -10.0]]
		"python":
			return [[Vector3(0, 0.035, -0.15), Vector3(0.022, 0.03, 0.22), steel],
				[Vector3(0, 0.055, -0.15), Vector3(0.012, 0.012, 0.22), steel],
				[Vector3(0, 0.02, -0.03), Vector3(0.045, 0.045, 0.05), steel],
				[Vector3(0, -0.04, 0.01), Vector3(0.032, 0.1, 0.045), wood, -15.0]]
		"m60":
			return [[Vector3(0, 0.03, -0.5), Vector3(0.022, 0.022, 0.32), steel],
				[Vector3(0, 0.035, -0.15), Vector3(0.06, 0.07, 0.36), olive],
				[Vector3(0.05, -0.02, -0.12), Vector3(0.06, 0.08, 0.1), olive],
				[Vector3(0, -0.04, 0.0), Vector3(0.03, 0.08, 0.04), black, -12.0],
				[Vector3(0, 0.01, 0.17), Vector3(0.045, 0.07, 0.24), olive],
				[Vector3(-0.03, -0.04, -0.55), Vector3(0.008, 0.1, 0.008), steel, 30.0], [Vector3(0.03, -0.04, -0.55), Vector3(0.008, 0.1, 0.008), steel, 30.0]]
		"barrett":
			return [[Vector3(0, 0.03, -0.62), Vector3(0.025, 0.025, 0.38), steel],
				[Vector3(0, 0.03, -0.82), Vector3(0.05, 0.04, 0.06), steel],
				[Vector3(0, 0.03, -0.25), Vector3(0.06, 0.08, 0.5), black],
				[Vector3(0, 0.1, -0.2), Vector3(0.04, 0.04, 0.24), black],
				[Vector3(0, -0.06, -0.15), Vector3(0.04, 0.1, 0.07), black],
				[Vector3(0, -0.04, 0.0), Vector3(0.03, 0.08, 0.04), black, -12.0],
				[Vector3(0, 0.02, 0.14), Vector3(0.05, 0.1, 0.18), black]]
		"rpg7":
			return [[Vector3(0, 0.05, -0.15), Vector3(0.05, 0.05, 0.8), olive],
				[Vector3(0, 0.05, -0.18), Vector3(0.06, 0.06, 0.18), wood],
				[Vector3(0, 0.05, -0.62), Vector3(0.09, 0.09, 0.14), olive.darkened(0.3)],
				[Vector3(0, 0.05, -0.72), Vector3(0.04, 0.04, 0.08), olive.darkened(0.3)],
				[Vector3(0, -0.03, -0.05), Vector3(0.03, 0.09, 0.04), wood, -10.0],
				[Vector3(0, -0.03, -0.25), Vector3(0.03, 0.09, 0.04), wood, -10.0]]
		"thunderjug":
			return [[Vector3(0, 0.03, -0.16), Vector3(0.05, 0.06, 0.24), Color(0.25, 0.35, 0.6)],
				[Vector3(0, 0.04, -0.17), Vector3(0.08, 0.08, 0.08), Color(0.5, 0.75, 1.0)],
				[Vector3(0, 0.03, -0.33), Vector3(0.03, 0.03, 0.1), steel],
				[Vector3(0, -0.04, 0.0), Vector3(0.03, 0.1, 0.045), black, -12.0]]
		"frostbite":
			return [[Vector3(0, 0.03, -0.15), Vector3(0.045, 0.055, 0.26), Color(0.75, 0.88, 0.95)],
				[Vector3(0, 0.04, -0.3), Vector3(0.07, 0.07, 0.06), Color(0.55, 0.85, 1.0)],
				[Vector3(0, -0.04, 0.0), Vector3(0.03, 0.1, 0.045), steel, -12.0]]
		"kar98k":
			return [[Vector3(0, 0.03, -0.45), Vector3(0.016, 0.016, 0.36), steel],
				[Vector3(0, 0.02, -0.25), Vector3(0.04, 0.04, 0.46), wood],
				[Vector3(0, 0.045, -0.06), Vector3(0.025, 0.025, 0.12), steel],
				[Vector3(0.035, 0.045, -0.02), Vector3(0.04, 0.012, 0.012), steel],
				[Vector3(0, -0.02, 0.14), Vector3(0.04, 0.08, 0.28), wood, -10.0]]
		"thompson":
			return [[Vector3(0, 0.03, -0.32), Vector3(0.022, 0.022, 0.16), steel],
				[Vector3(0, 0.035, -0.14), Vector3(0.045, 0.05, 0.26), steel],
				[Vector3(0, -0.04, -0.22), Vector3(0.025, 0.08, 0.03), wood],
				[Vector3(0, -0.06, -0.1), Vector3(0.03, 0.06, 0.14), black],
				[Vector3(0, -0.04, 0.02), Vector3(0.03, 0.08, 0.04), wood, -12.0],
				[Vector3(0, 0.0, 0.16), Vector3(0.04, 0.07, 0.22), wood, -8.0]]
		"remington870":
			return [[Vector3(0, 0.035, -0.36), Vector3(0.022, 0.022, 0.42), black],
				[Vector3(0, 0.01, -0.3), Vector3(0.018, 0.018, 0.36), black],
				[Vector3(0, 0.005, -0.28), Vector3(0.04, 0.04, 0.12), wood],
				[Vector3(0, 0.025, -0.06), Vector3(0.045, 0.05, 0.14), black],
				[Vector3(0, -0.01, 0.15), Vector3(0.04, 0.08, 0.26), wood, -10.0]]
		"galil":
			return [[Vector3(0, 0.03, -0.4), Vector3(0.018, 0.018, 0.18), black],
				[Vector3(0, 0.03, -0.24), Vector3(0.045, 0.045, 0.16), black],
				[Vector3(0, 0.04, -0.06), Vector3(0.045, 0.05, 0.22), black],
				[Vector3(0, -0.06, -0.1), Vector3(0.028, 0.14, 0.045), black, 15.0],
				[Vector3(0, -0.04, 0.03), Vector3(0.03, 0.08, 0.04), black, -15.0],
				[Vector3(0, 0.02, 0.17), Vector3(0.02, 0.05, 0.22), steel]]
		"spas12":
			return [[Vector3(0, 0.04, -0.34), Vector3(0.025, 0.025, 0.38), black],
				[Vector3(0, 0.01, -0.3), Vector3(0.05, 0.035, 0.22), black],
				[Vector3(0, 0.03, -0.05), Vector3(0.05, 0.06, 0.16), black],
				[Vector3(0, -0.04, 0.03), Vector3(0.03, 0.08, 0.04), black, -15.0],
				[Vector3(0, 0.05, 0.14), Vector3(0.012, 0.012, 0.22), steel]]
		"deagle":
			return [[Vector3(0, 0.035, -0.09), Vector3(0.035, 0.04, 0.24), steel],
				[Vector3(0, -0.04, 0.0), Vector3(0.035, 0.11, 0.05), black, -12.0],
				[Vector3(0, -0.005, -0.04), Vector3(0.008, 0.02, 0.04), steel]]
		"mp40":
			return [[Vector3(0, 0.03, -0.3), Vector3(0.018, 0.018, 0.14), black],
				[Vector3(0, 0.035, -0.12), Vector3(0.04, 0.045, 0.24), black],
				[Vector3(0, -0.07, -0.13), Vector3(0.024, 0.15, 0.03), black],
				[Vector3(0, -0.04, 0.0), Vector3(0.03, 0.08, 0.04), black, -12.0],
				[Vector3(0, 0.03, 0.12), Vector3(0.012, 0.012, 0.18), steel]]
		"emberwick":
			return [[Vector3(0, 0.03, -0.18), Vector3(0.05, 0.05, 0.28), Color(0.3, 0.18, 0.1)],
				[Vector3(0, 0.05, -0.15), Vector3(0.07, 0.09, 0.07), Color(1.0, 0.5, 0.12)],
				[Vector3(0, 0.03, -0.36), Vector3(0.045, 0.045, 0.06), steel],
				[Vector3(0, -0.04, 0.0), Vector3(0.03, 0.1, 0.045), wood, -12.0]]
		"gravebell":
			return [[Vector3(0, 0.03, -0.18), Vector3(0.04, 0.04, 0.26), Color(0.35, 0.3, 0.22)],
				[Vector3(0, 0.03, -0.36), Vector3(0.12, 0.12, 0.08), Color(0.7, 0.55, 0.25)],
				[Vector3(0, 0.03, -0.41), Vector3(0.15, 0.15, 0.02), Color(0.7, 0.55, 0.25)],
				[Vector3(0, -0.04, 0.0), Vector3(0.03, 0.1, 0.045), wood, -12.0]]
		"rootsnare":
			return [[Vector3(0, 0.03, -0.17), Vector3(0.045, 0.05, 0.3), Color(0.32, 0.22, 0.12)],
				[Vector3(0.025, 0.05, -0.28), Vector3(0.015, 0.015, 0.14), Color(0.35, 0.6, 0.25), 20.0],
				[Vector3(-0.025, 0.01, -0.3), Vector3(0.015, 0.015, 0.12), Color(0.35, 0.6, 0.25), -20.0],
				[Vector3(0, -0.04, 0.0), Vector3(0.03, 0.1, 0.045), wood, -12.0]]
	return [[Vector3(0, 0.02, -0.1), Vector3(0.04, 0.06, 0.2), steel]]


func _add_box_turned(st: SurfaceTool, centre: Vector3, size: Vector3, color: Color, turn: Basis) -> void:
	var tmp := SurfaceTool.new()
	tmp.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(tmp, Vector3.ZERO, size, color)
	var arrays := tmp.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		st.set_color(color)
		st.set_normal(turn * normals[i])
		st.add_vertex(centre + turn * verts[i])


# --- Sounds --------------------------------------------------------------------------------
# Made once at load, short and small; played through audio.gd (3D where
# they happen) or, without it, through this module's own players.

func _sound(kind: String, at, volume := 1.0, pitch := 1.0) -> void:
	if not settings["sounds"] or not _sounds.has(kind):
		return
	var stream: AudioStream = _sounds[kind]
	if _audio and is_instance_valid(_audio):
		if at is Vector3:
			_audio.call("play_at", stream, at, {"bus": "effects", "volume": volume, "pitch": pitch})
		else:
			_audio.call("play_2d", stream, "effects", volume, pitch)
		return
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream
	p.volume_db = linear_to_db(maxf(volume, 0.01))
	p.pitch_scale = pitch
	p.play()


func _make_sounds() -> void:
	_sounds["shot"] = _synth(0.22, {"noise": 0.9, "noise_decay": 18.0, "tone": [180.0, 60.0], "tone_amp": 0.6, "tone_decay": 14.0, "low": 4500.0})
	_sounds["shot_heavy"] = _synth(0.45, {"noise": 1.0, "noise_decay": 9.0, "tone": [120.0, 40.0], "tone_amp": 0.8, "tone_decay": 8.0, "low": 3000.0})
	_sounds["click"] = _synth(0.05, {"noise": 0.6, "noise_decay": 120.0, "tone": [2400.0, 1800.0], "tone_amp": 0.3, "tone_decay": 90.0, "low": 9000.0})
	_sounds["reload"] = _synth(0.35, {"noise": 0.5, "noise_decay": 30.0, "tone": [900.0, 500.0], "tone_amp": 0.2, "tone_decay": 25.0, "low": 6000.0, "second": 0.2})
	_sounds["hit"] = _synth(0.18, {"noise": 0.6, "noise_decay": 25.0, "tone": [140.0, 70.0], "tone_amp": 0.7, "tone_decay": 20.0, "low": 1500.0})
	_sounds["groan"] = _synth(1.1, {"noise": 0.15, "noise_decay": 1.5, "tone": [95.0, 70.0], "tone_amp": 0.7, "tone_decay": 1.6, "low": 900.0, "saw": true, "wobble": 5.0, "attack": 0.25})
	_sounds["rip"] = _synth(0.4, {"noise": 0.9, "noise_decay": 7.0, "tone": [300.0, 120.0], "tone_amp": 0.3, "tone_decay": 10.0, "low": 2500.0, "crackle": true})
	_sounds["nail"] = _synth(0.15, {"noise": 0.5, "noise_decay": 40.0, "tone": [700.0, 650.0], "tone_amp": 0.6, "tone_decay": 30.0, "low": 7000.0})
	_sounds["bell"] = _synth(2.0, {"noise": 0.0, "tone": [220.0, 218.0], "tone_amp": 0.5, "tone_decay": 1.4, "low": 4000.0, "overtone": 2.76})
	_sounds["buy"] = _synth(0.35, {"noise": 0.0, "tone": [660.0, 990.0], "tone_amp": 0.4, "tone_decay": 6.0, "low": 8000.0})
	_sounds["deny"] = _synth(0.3, {"noise": 0.0, "tone": [180.0, 150.0], "tone_amp": 0.45, "tone_decay": 6.0, "low": 3000.0, "saw": true})
	_sounds["gulp"] = _synth(0.5, {"noise": 0.2, "noise_decay": 8.0, "tone": [300.0, 520.0], "tone_amp": 0.5, "tone_decay": 5.0, "low": 2500.0, "wobble": 12.0})
	_sounds["crate"] = _synth(2.2, {"noise": 0.0, "tone": [520.0, 880.0], "tone_amp": 0.35, "tone_decay": 0.9, "low": 6000.0, "wobble": 9.0, "overtone": 1.5})
	_sounds["hurt"] = _synth(0.3, {"noise": 0.7, "noise_decay": 12.0, "tone": [90.0, 50.0], "tone_amp": 0.8, "tone_decay": 9.0, "low": 1200.0})
	_sounds["zap"] = _synth(0.4, {"noise": 0.8, "noise_decay": 9.0, "tone": [1200.0, 300.0], "tone_amp": 0.4, "tone_decay": 8.0, "low": 9000.0, "crackle": true})
	_sounds["boom"] = _synth(0.9, {"noise": 1.0, "noise_decay": 4.0, "tone": [80.0, 30.0], "tone_amp": 1.0, "tone_decay": 4.0, "low": 1200.0})


# A short sound: noise (low-passed, maybe crackling) and a tone sliding from
# one pitch to another (sine, or saw-like; maybe wobbling; maybe with an
# overtone, for the bell), each fading at its own rate. 22 kHz, 16-bit mono.
func _synth(seconds: float, p: Dictionary) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p)
	var phase := 0.0
	var phase2 := 0.0
	var low := 0.0
	var k := 1.0 - exp(-TAU * float(p.get("low", 5000.0)) / rate)
	var tone: Array = p.get("tone", [0.0, 0.0])
	var attack: float = p.get("attack", 0.005)
	var second: float = p.get("second", -1.0)
	for i in count:
		var t := float(i) / rate
		var f := lerpf(tone[0], tone[1], t / seconds)
		if p.has("wobble"):
			f *= 1.0 + 0.06 * sin(TAU * float(p["wobble"]) * t)
		phase = fmod(phase + f / rate, 1.0)
		var wave := (phase * 2.0 - 1.0) * 0.7 + sin(TAU * phase) * 0.3 if p.get("saw", false) else sin(TAU * phase)
		if p.has("overtone"):
			phase2 = fmod(phase2 + f * float(p["overtone"]) / rate, 1.0)
			wave = wave * 0.7 + sin(TAU * phase2) * 0.3
		var n := rng.randf_range(-1.0, 1.0)
		if p.get("crackle", false) and rng.randf() < 0.85:
			n *= 0.2
		var since := t
		if second > 0.0 and t >= second:
			since = t - second  # a second click (the reload)
		var v := wave * float(p.get("tone_amp", 0.0)) * exp(-float(p.get("tone_decay", 5.0)) * since) \
			+ n * float(p.get("noise", 0.0)) * exp(-float(p.get("noise_decay", 10.0)) * since)
		v *= minf(1.0, t / attack)
		v *= minf(1.0, (seconds - t) / 0.02)  # no click at the end
		low += (v - low) * k
		var s := clampi(int(tanh(low * 1.2) * 30000.0), -32768, 32767)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
