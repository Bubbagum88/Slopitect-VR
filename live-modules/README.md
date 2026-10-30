# Live modules

Modules that aren't built into the APK. Each one is a single file you put
in the headset's Slopitect folder and load while the app runs. You say Yes
to its code in the headset first, and you can take it out again with
`code_unload`. A module you said Yes to loads by itself at the next start,
unless its file has changed since.

| File | What it does |
|---|---|
| `lib.gd` | The shared helpers and the module events: finding a shape or model (`world_node`, `thing`, `things`), its box (`world_box`), the Slopitect folder (`home`), JSON files (`read_json`, `write_json`), a quick `module(name)`, and the signals modules use instead of checking on each other every frame (`module_loaded`, `module_unloaded`, `info_changed`, plus `follow()` and `watch()` to connect to another module's signals whenever it's loaded). A module joins in with `lib_ready(lib)`, so the order they load in doesn't matter. Load it first. `lib_status` shows who follows what. Rules: [CLAUDE.md](../CLAUDE.md#module-design-rules-the-owners-2026-10-30); tests in `tests/` |
| `controls.gd` | The only thing that reads the controllers: each button is bound to a named action (point, grab_left, grab_right, talk, left_menu, left_y, right_a, right_b, left_stick) and each thumbstick to a stick (walk, turn). It also walks you with the walk stick (the way you look) and turns you with the turn stick (30° steps, or smooth), so you stand on the landscape's ground; speed, stick dead zone and turning are in the Settings window (Moving). Other modules take the actions, and read how far a grip or trigger is pressed with `value()`. A button can also run a command (never a `*_config` or `agent_` one) or show and hide a window. `controls_status` shows the bindings; `controls_config` (PC only) changes them. X on the left controller always stops the agent and can't be bound |
| `vrui.gd` | Every window: the Menu (a launcher with a tile for every window), wrist panel, the agent's chat window and keyboard, and any panel you or the agent add (`ui_*` commands). Drawn the way the vrui draft drew windows (rounded, wrapped text), redrawn only on a change. Title bars to carry and close windows, tabs, toggles and sliders, a hand window on a controller, rows/columns/grids that lay themselves out, buttons that open a sub-menu with a back arrow, scrolling text (point at a window and push the right thumbstick up or down), one theme. Needs controls.gd for its buttons. See [docs/VR-UI.md](../docs/VR-UI.md) |
| `tools.gd` | The Tools menu (B on the right controller, or its tile): a button for each loaded tool, which chooses it and opens that tool's own menu (its buttons, Undo / Redo, a back arrow); the windows that are tools (the terminal; any module whose `menu_info()` has `"tools": true`); and one Undo / Redo list for every tool (a module can make many changes one undo with `undo_batch_begin` / `undo_batch_end`) |
| `pause.gd` | The pause menu, on the left home button (≡; or its tile): Resume, Save world (a checkpoint), Load (the newest checkpoints), Worlds (the saved worlds, to open one), Settings (settings.gd's window, when it's loaded), All windows (the Menu bar), Hand menu, and Files & modules (worlds.gd). Also the hand menu above the left controller: Home, Settings (with settings.gd), Undo, Redo (pressing the left thumbstick in shows and hides it), a button for each module with `hand_info()` (Tools, Terminal), and the wrist panel's buttons (the wrist panel is hidden, so there's one hand menu). Each button opens and closes its window. It doesn't stop the world. Needs vrui.gd; save.gd and projects.gd for saving and loading, tools.gd for Undo / Redo |
| `settings.gd` | The Settings window (its tile on the Menu): a section for each loaded module that has a `settings_info()` function (moving, text size, hands, the avatar's outfit, the agent), built from what each module declares, so a new module's settings appear on their own. Changes go through `settings_set`, which checks the value against the declaration; a `NAME_config` command can't be a setter, so PC-only settings stay PC only. The contract is at the top of the file. Needs vrui.gd |
| `agent_settings.gd` | The agent's token budget in the Settings window: the most one request may send (100,000 tokens to start, the point past which Claude Haiku 5.5 costs five times as much), when a conversation starts over, the most per question and the rounds per question. Changes go through the APK's `agent_budget` command, in narrow ranges; the agent itself can never change them. With Claude, the model too, from Haiku 5.5, Sonnet 5.5 and Opus 5.5 (a new model starts a new conversation). The key, provider, address and allowed tools stay with `agent_config`, from the PC. Needs settings.gd and an APK with `agent_budget` |
| `agent_tuning.gd` | How the agent talks and spends, so changing it needs no new APK: its instructions (`PROMPT`), which skills it always follows (`ALWAYS`; caveman is on), more skills from `modules/agent_skills/NAME/SKILL.md`, when a conversation starts over and what it carries, and the warning near the request cap. The APK keeps the key, provider, address, model, allowed tools, the firewall, its safety rules (always added after the instructions) and the token caps as hard stops; without this module it works the same way on its own. The agent can't write, move, delete, load or unload any `modules/agent_*` file, so this one goes on the headset from the PC. Needs an APK with the tuning hooks |
| `chat.gd` | Makes the agent's chat window (Y on the left controller) like the terminal: a green screen that keeps the whole conversation (Up / Down / End scroll it, Cls clears it), the agent's state, the line you type, the keyboard with Send, and STOP and New chat beside the screen. It fills vrui.gd's chat panel, keeping its ids and where you put it, and puts the old layout back when it's unloaded. Uses aimsg.gd's layout when that's loaded |
| `landscape.gd` | Ground you can shape, 20 × 20 m: raise, lower, smooth and flatten brushes. It stands in for the flat floor while it's loaded |
| `paths.gd` | Roads and trails: put down points with the trigger, then press Finish. Optionally levels the ground under the path. A path can wear a texture from `downloads/` (`paths_texture`), tiled every `texture_scale` metres. From the headset agent's version |
| `save.gd` | Keeps the shapes and models: saved by themselves when they change and put back at start. Checkpoints keep the whole world (ground and paths too) to go back to, with undo |
| `grab.gd` | Hold the grip near a shape or model to pick it up; let go to drop it (or throw it, with physics). Grip it with the other hand too and pull your hands apart or together to resize it (2 cm to 20 m); let go with either hand and the other keeps it. One undo per pick-up, resizes included |
| `physics.gd` | Makes shapes and models fall, bounce and collide (the engine's own physics) once you set them dynamic; the ground is the floor or the landscape |
| `projects.gd` | A world per project (`projects/NAME/` in the Slopitect folder: its saves, notes, and the live modules it uses). Other modules follow its `project_changed(project, folder)` signal. Needs save.gd and lib.gd |
| `hands.gd` | Drawn hands with coloured nails in place of the controller boxes; the fingers curl with the grip, trigger and where your thumb rests. Colours from the PC (`hands_config`). Needs controls.gd to move |
| `inspect.gd` | A tool for one thing at a time: point and pull the trigger to select a shape or model, then switch its physics (none, static, dynamic), whether it can be grabbed, hide it, or delete it (one undo; a shape made with shapes.gd comes back from its recipe, and back into its group). Show hidden brings hidden things back. The switches are kept with each project's world |
| `keyboard.gd` | One floating keyboard window (its Menu tile or the hand menu) instead of keys on every window: its display line goes to the window with the focus (the last one you pulled the trigger on or opened; its edge is lit): the terminal's line or that window's input box. Run / Send runs the line or presses the window's Send. Hide folds the keys away to just the line, Keys and Send. With textEdit.gd loaded it shows textEdit's editing keys over the letters, and Take (brings in the focused box's text or the terminal's line to change and send back). The terminal builds itself without keys while it's loaded; it takes the chat window's keys off. From the headset agent's version |
| `terminal.gd` | A command line in the headset (A on the right controller): type any of the app's commands, like `spawn shape=box scale=0.3`, and press Run to see the reply. Tab completes a command's name, Prev / Next step through what you ran, Help lists the commands, Up / Down scroll, Cls clears, and Ask AI sends your line with the last command and its reply to the agent. Won't run `*_config` settings. Chat turns the same window into the agent's chat (the conversation from chat.gd, Send, STOP, New chat, a keyboard with ' ? !); Terminal turns it back. Needs vrui.gd for its window |
| `textEdit.gd` | Editing for the line typed on keyboard.gd: < > move the cursor, << >> a word, Home / End; with Sel they pick letters, All picks the line; Cut, Copy and Paste (the app's own clipboard in vrui.gd; with nothing picked, Copy takes the rows picked on the terminal's screen with the trigger); Del> deletes forward, Aa switches capitals, Undo / Redo. Typing or Paste replaces what's picked |
| `avatar.gd` | The agent's avatar (it used to be built into the APK): a red cube with a face that thinks while the agent works, shows emotions (`avatar_emotion`), moves its mouth with the words while the speech engine talks, and shows replies a page at a time in a speech bubble above its head, which waits at the edge of your view when the avatar is out of sight. Outfits are made of simple shapes (`avatar_outfit_add`). Other modules use `root()` (the whole avatar), `body()`, `say()`, `set_state()`, `set_emotion()` and `speaking()` |
| `holster.gd` | Put the avatar away at your hip and pull it back out. Point at the avatar (or reach it) and grip: it flies to your hand. Let go at your hip (a ring shows each hip, lit when you're there) and it's stowed there, small. Grip it at your hip and flick as you let go: it flies out to a spot around you in the flick's direction (further for a harder flick, higher or lower for an up or down flick) and keeps that spot from you as you walk and thumbstick-turn. A slow let go anywhere else leaves it there. The hand menu's Avatar button stows it or brings it out; `holster_status`, `holster_stow`, `holster_summon`, `holster_toggle`. Needs avatar.gd with `root()` |
| `aimsg.gd` | Makes the chat log easier to read: "you>" and "ai>" tags, the agent's words wrapped, markdown marks taken out, code marked with "\|", tool calls and thinking on one short line. It changes no window: the chat log's source asks for it (`"format": "aimsg"`, which needs the vrui.gd from the VR UI work), and shows plain lines when it isn't loaded. Width and height from the PC (`aimsg_config`) |
| `net.gd` | Downloads from the internet, only https and only from hosts allowed on the PC (`net_config`; Poly Haven's to start). Files go in `downloads/HOST/` with a `.source.json` saying where they came from. Other modules download through its `fetch()` |
| `worlds.gd` | The Worlds window, from its tile on the Menu. Tabs: Worlds (open a project's world or make a new one), Checkpoints (keep the world now, go back, delete), Files (look through the Slopitect folder), Modules (load, reload or unload live modules). It keeps nothing itself; it shows and runs projects, save, files and code. Needs vrui.gd; a tab whose module is missing says so |
| `perf.gd` | How well the app runs, from inside it: `perf_status` (frame rate, frame times and hitches over 10 s, script and physics CPU time, draw calls, objects, memory), `perf_watch` then `perf_modules` (each module's `_process`/`_physics_process` cost per frame, costliest first), `perf_load` (compile time of each live module's file). Timing is off until `perf_watch` |
| `jelly.gd` | The avatar squashes and stretches like jelly as it moves, keeping its volume; `jelly_poke` wobbles it. Needs the live avatar module (its `body()`); spring from the PC (`jelly_config`) |
| `assets.gd` | 3D models from [Poly Haven](https://polyhaven.com) (all CC0): search, download to the headset, place in the world (placing, moving and removing are each one undo). Powered by Poly Haven. Other modules hear its `placed(name, id)` signal and ask `model_id(name)` |
| `tool_front.gd` | Each tool's own menu opens in front of you, not where the Tools window was; a menu with its Pin on stays put. From the headset agent. Needs vrui.gd and tools.gd |
| `sweet_potato.gd` | Put a placed sweet potato (Poly Haven `sweet_potato`) down on the ground and leave it a second: it shrinks away and a tree grows there, hangs 3 potatoes, and sprouts 2 smaller trees, which sprout 2 more (7 in all). Growing adds nothing to undo. `sweet_potato_status`. From the headset agent. Needs assets.gd |
| `beatsaber.gd` | Rhythm Sabers: red and blue notes come down a track on the music's beat; cut each with its own colour's saber in its arrow's direction (dots any way), and keep off the bombs. Points for direction, centre and a full swing, a combo multiplier up to 8, accuracy, a rank and the best score per song. Songs are folders in `songs/` with the music (ogg, mp3 or wav) and a `map.json` (our own simple format, in the file's top comment); a map with only `bpm` gets notes made for the whole song, and Free play needs no song. The Rhythm tile on the Menu opens its window; difficulty, note speed, tempo, hit sounds and trails are in the Settings window (`beatsaber_set`). Pooled notes and shared materials for the Quest 1, haptics through controls, idle when no song plays. The saber's fit in the hand is `beatsaber_config` (PC only). Shows its sabers when the hands module's choice is Sabers |
| `beatsaber_path.gd` | A black path on the floor under the beatsaber module's track while a song plays (follows its started / stopped signals). From the headset agent |
| `memory.gd` | The agent's memory between conversations: notes it keeps (facts, decisions, troubleshooting, coding techniques), each question you asked in a world with its answer, tools and errors, older ones folded into digests, and each tool's failures. One memory per world (project) plus a global one. Keys and personal info are cleaned out before anything is kept |
| `tts.gd` | Speech out (it used to be the APK's voice module): the agent's replies read aloud, and `tts_say` for anything else. Only the words are said: code blocks, markdown marks, symbols, emoji, links and paths are left out (`speakable()`). Slopitect makes the speech itself with the APK's sherpa-onnx library from a Piper voice folder in `voices/` (`tts_sherpa_voice`), each sentence made while the one before plays, into one continuous sound; the Android speech engine isn't used. Speed, volume, the voice (among those in `voices/`) and reading replies on or off are comfort settings, in the Settings window or with `tts_set`. Other modules use `speak()` and `speaking()` |
| `vtt.gd` | Hold-to-talk (it used to be the APK's voice module): hold the talk button (the left trigger), talk, let go, and the words land in the chat window's input box for you to check and Send, or go straight to the agent (`send_to_agent`, in the Settings window or with `vtt_set`). On the headset with whisper.cpp (the APK's godot-whisper plugin and a model in `models/`), on the headset with sherpa-onnx while you talk (`vtt_engine` `"sherpa"`, the APK's sherpa-onnx library and a streaming model folder in `models/`, chosen with `vtt_sherpa_model`), or a service at `vtt_url`; the engine, service and key change only from the PC (`vtt_config`). A line on the hand menu shows REC while it listens, then that it is turning your words into text, then what it heard. Presses shorter than `min_hold` are ignored |
| `textures.gd` | Textures on shapes (written by the in-app agent, moved up from drafts): `textures_apply` puts a picture from `downloads/` (or "noise") on named shapes, tinted by their colour, optionally shiny. The texture is mapped on the shape itself, so it moves, turns and is carried with it, and each tile stays `scale` metres when the shape is resized. Applying and clearing are each one undo. Kept per project in `saves/textures.json`. The Library's Textures tab uses it |
| `shapes.gd` | Shapes beyond box, sphere, cylinder and capsule, each from a recipe you can change later: extrude (an outline pushed into a solid, tapered or twisted), revolve (an outline spun round: cones, domes, bowls, vases, rings, a torus), sweep (a tube along a path: pipes, an elbow, a spring, a handle), loft (through stacked outlines), surface (a sheet or slab from heights or points), and cuts (one shape cut out of, joined to or overlapped with another: a window in a wall). 25 ready-made presets (`shapes_kinds`). As a tool: Place puts the chosen preset on the ground where you point; Draw puts down an outline with the trigger on a wall in front of you or on the floor, then Extrude or Revolve. Every shape has attach points (its faces, a pipe's ends, a spun shape's axis) that joints.gd uses. Made shapes work with list, move, color, delete, grab, inspect and physics, and save.gd keeps their recipes |
| `doors.gd` | Hinged doors (written by the in-app agent): `doors_add` turns shapes into a door that swings round a hinge (upright, or flat like an oven door). Put a hand near a door and press A (right) or Y (left) to open or close it; away from doors those buttons still show the terminal and chat. Making and removing a door are each one undo. Kept per project in `saves/doors.json`; doors load closed |
| `multi.gd` | Multi-select and groups (written by the in-app agent): the Multi tool adds things to a selection with the trigger (cyan boxes); group them and moving one member moves the rest (a held member leads, even while physics moves the others). Move, hide, lock or delete the whole selection; grouping, ungrouping and each of those is one undo. A deleted member leaves its group (undo puts it back). Groups are kept per project in `saves/groups.json` |
| `prefabs.gd` | Prefabs (written by the in-app agent): `prefabs_save` keeps a set of shapes and models (by names, name prefixes, or the Multi tool's selection) with their textures, doors and groups as `prefabs/NAME.json`; `prefabs_place` puts a copy anywhere (one undo). Shapes made with shapes.gd keep their recipe. The Library's Prefabs tab shows them with a picture |
| `library.gd` | The Library window (its tile on the Menu, or Textures / Assets / Prefabs on the hand menu): three tabs of pictures, 12 to a page with Prev / Next and a category button. Textures: Poly Haven's textures; pick a shape with the Inspect tool, then press one to download it and put it on that shape (textures.gd). Assets: Poly Haven's models, lightest first; press one to download it (assets.gd) and place it in front of you. Prefabs: the sets saved with `prefabs_save` (prefabs.gd), each with a picture drawn once from what it holds; press one to place a copy. The pictures are Poly Haven's 128 px thumbnails, kept in `library/`; they need `cdn.polyhaven.com` allowed on the PC (`net_config`). Needs vrui.gd and net.gd |
| `joints.gd` | Hinges, sliders, ball joints and fixed joints between any two things (shapes, placed models, anything built later), or between a thing and the world, plus attach points: named spots on a thing's surface to join others at. A part that's dynamic (physics.gd) swings, falls and collides on the engine's own joint (Jolt); otherwise it follows the part it's joined to, and grabbing or moving it turns or slides it only the way the joint lets it. A motor turns a hinge or moves a slider by itself. The Joints tool (Tools menu, its tile, or the hand menu): Connect (the part that stays, then the part that moves; Snap moves the second onto the first), Add point, Remove. Shows its pivots, axes and points while chosen (Settings: always or never). Kept with the world (save.gd); every change is one undo |

A tool is any module with a `tool_info()` function, so a new tool is a new
file; `tools.gd` explains what a tool gets. Tools work without the tools
module (through their commands), but have no window or undo without it.

## Putting them on the headset

From the platform-tools folder:

```
.\adb shell mkdir -p /sdcard/Slopitect/modules
.\adb push "C:\path\to\live-modules\controls.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\vrui.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\tools.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\landscape.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\paths.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\assets.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\save.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\grab.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\physics.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\projects.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\inspect.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\terminal.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\avatar.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\memory.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\hands.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\aimsg.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\net.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\jelly.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\worlds.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\pause.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\chat.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\tts.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\vtt.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\library.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\shapes.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\joints.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\agent_tuning.gd" /sdcard/Slopitect/modules/
.\slopi.ps1 '{"cmd":"code_load","name":"controls"}'
.\slopi.ps1 '{"cmd":"code_load","name":"ui"}'
.\slopi.ps1 '{"cmd":"code_load","name":"tools"}'
.\slopi.ps1 '{"cmd":"code_load","name":"landscape"}'
.\slopi.ps1 '{"cmd":"code_load","name":"paths"}'
.\slopi.ps1 '{"cmd":"code_load","name":"assets"}'
.\slopi.ps1 '{"cmd":"code_load","name":"save"}'
.\slopi.ps1 '{"cmd":"code_load","name":"grab"}'
.\slopi.ps1 '{"cmd":"code_load","name":"physics"}'
.\slopi.ps1 '{"cmd":"code_load","name":"projects"}'
.\slopi.ps1 '{"cmd":"code_load","name":"inspect"}'
.\slopi.ps1 '{"cmd":"code_load","name":"terminal"}'
.\slopi.ps1 '{"cmd":"code_load","name":"avatar"}'
.\slopi.ps1 '{"cmd":"code_load","name":"memory"}'
.\slopi.ps1 '{"cmd":"code_load","name":"hands"}'
.\slopi.ps1 '{"cmd":"code_load","name":"aimsg"}'
.\slopi.ps1 '{"cmd":"code_load","name":"net"}'
.\slopi.ps1 '{"cmd":"code_load","name":"jelly"}'
.\slopi.ps1 '{"cmd":"code_load","name":"worlds"}'
.\slopi.ps1 '{"cmd":"code_load","name":"pause"}'
.\slopi.ps1 '{"cmd":"code_load","name":"chat"}'
.\slopi.ps1 '{"cmd":"code_load","name":"tts"}'
.\slopi.ps1 '{"cmd":"code_load","name":"vtt"}'
.\slopi.ps1 '{"cmd":"code_load","name":"library"}'
.\slopi.ps1 '{"cmd":"code_load","name":"shapes"}'
.\slopi.ps1 '{"cmd":"code_load","name":"joints"}'
```

Each `code_load` shows the code in the headset and waits for your Yes
(the right thumbstick scrolls the code). Load controls.gd and vrui.gd first:
until they're loaded, the buttons do nothing but the Yes/No question and
Stop, and there are no windows.

## Using them

Press the left menu button (≡) for the Menu: a tile for each window (Chat,
Tools, and any module's), then the shapes. Point at a window's title bar and
hold the trigger to carry it; its x closes it.

Press B on the right controller (or the Tools tile) for the tool window and
pick a tool.
Pointing at a panel still presses its buttons; pointing anywhere else, the
right trigger is the tool's.

- **Landscape:** point at the ground; the white ring is the brush. Hold
  the trigger to paint. The window has the brush modes, Smaller / Bigger
  and Weaker / Stronger.
- **Path:** pull the trigger on the ground for each point, then press
  Finish ("Back a point" and Cancel fix mistakes). Narrower / Wider and
  Flatten are in the window.
- **Inspect:** point at a shape or model and pull the trigger; a white
  box shows round the one selected, and the window gets its switches:
  No physics / Static / Dynamic (with physics.gd loaded), Grab: on/off,
  Hide, Delete and Unselect. Hidden things can't be pointed at, so
  "Show hidden" appears while any are hidden.
- **Joints:** in Connect, pull the trigger on the part that stays (a
  green mark shows the spot), then on the part that moves. Pick Hinge,
  Slider, Ball or Fixed first, and the axis: Normal (out of the surface:
  a wheel), Up (a door), Side (level along the surface: a lid). With
  Snap on, the second part is moved so the two spots touch. "Join to
  world" joins the first pick to the world instead. Add point puts an
  attach point (yellow) where you point; Connect uses it when you point
  near it. Remove takes a thing's joints off, or an attach point.
- **Undo / Redo** in the window, or `tools_undo` / `tools_redo`, cover
  every stroke and path, including ones the agent made with commands.

What each saves: the ground's heights in `user://landscape.bin`, paths in
`user://paths.json` (the app's own storage, kept when you install a new
APK over the old one). The undo list is not saved, and opening another
project empties it (its changes are to the last world).

Undo covers every change to the world: shapes spawned, moved, recoloured
or deleted (by hand, a button or the agent's commands), made shapes,
models, textures, doors, physics, the inspect switches, joints, groups,
the ground, paths and checkpoints. Undoing a delete brings the thing back
with what other modules kept about it: its texture, door, physics,
switches, joints, attach points and group (a module that keeps something
by a thing's name gives `thing_state` / `thing_forget` / `thing_restore`,
see tools.gd). What isn't a change to undo: opening a door, a push, and
the tools' own settings.

## Commands

| Command | Fields |
|---|---|
| `tools_list`, `tools_status` | |
| `tools_select` | `tool` (`landscape`, `paths`, or `""`) |
| `tools_undo`, `tools_redo` | |
| `landscape_status` | |
| `landscape_brush` | any of `mode` (raise, lower, smooth, flatten), `size` (0.25–5 m radius), `size_step` (1 / -1), `strength` (0.1–5 m/s), `strength_step` |
| `landscape_sculpt` | `position` [x, z], `mode`, `size`, `amount`, `height` (for flatten); one undo |
| `landscape_height` | `position` [x, z] |
| `landscape_reset` | flat again; one undo |
| `paths_list` | |
| `paths_add` | `points` [[x, z], ...], optional `width`, `color`, `flatten`, `texture`, `texture_scale`; one undo |
| `paths_delete` | `path` (its id); one undo |
| `paths_settings` | any of `width`, `width_step`, `color`, `flatten`, `texture`, `texture_scale` |
| `paths_draft` | `action`: finish, cancel or remove_last |
| `paths_texture` | `path` (an id), `paths` [ids] or `all` true; `texture` (a file under `downloads/`, or "" for none), optional `texture_scale` (0.2 to 20 m a tile); one undo |
| `assets_search` | `query` (words), optional `category`; lightest models first |
| `assets_get` | `id`, optional `resolution` (1k, 2k, 4k; default 1k); downloads in the background |
| `assets_status`, `assets_downloaded`, `assets_placed` | |
| `assets_place` | `id`, optional `resolution`, `name`, `position`, `rotation`, `scale` (a number or [x, y, z]) |
| `assets_move` | `name`, any of `position`, `rotation`, `scale` |
| `assets_remove` | `name` (the files stay on the headset) |

| `joints_add` | `b` (the part that moves), optional `a` (the part that stays; left out: the world), `type` (hinge, slider, ball, fixed), `at` [x, y, z], `axis` [x, y, z], `point_a` / `point_b` (attach points), `snap`, `lower` / `upper` (hinge degrees, slider metres, counted from where b is now), `motor` (a second); one undo |
| `joints_set` | `id`, any of `value`, `motor`, `lower`, `upper` |
| `joints_remove` | `id`, or `name` (all of a thing's joints); one undo |
| `joints_list`, `joints_points` | (`joints_points`: optional `name`) |
| `joints_point_add` | `name`, optional `id`, `position` [x, y, z] or `face` (top, bottom, left, right, front, back), optional `normal`; one undo |
| `joints_point_remove` | `name`, `id`; one undo |
| `joints_tool` | any of `mode`, `type`, `axis`, `snap`, `act` (open, cancel, world) |
| `joints_prefs` | `show` (tool, always, never), `snap` |

| `ui_list`, `ui_get`, `ui_theme_status` | |
| `ui_add`, `ui_update` | a panel: `id_panel` and its fields (see docs/VR-UI.md) |
| `ui_show` | `id_panel`, `visible` |
| `ui_page` | `id_panel`, `page` |
| `ui_back` | `id_panel` (one a button's `open` opened) |
| `ui_scroll` | `id_panel`, `id_element` (a `scroll` text), `lines` back from the newest |
| `ui_element_add`, `ui_element_update`, `ui_element_remove` | `id_panel`, then `element` (and optional `parent`, a row/column/grid) or `id_element` |
| `ui_press` | `id_panel`, `id_element` (a button or toggle) |
| `ui_slide` | `id_panel`, `id_element`, `value` |
| `ui_type`, `ui_key` | `text`; `key` (shift, backspace, clear) |
| `ui_reset` | optional `id_panel` |
| `ui_config` (PC only) | `theme` {name: #rrggbb or a text size}, or `reset` true |

| `save_status`, `save_now`, `save_checkpoints` | |
| `save_checkpoint` | optional `label` |
| `save_restore` | `checkpoint` (its id, like "0003" or 3); one undo |
| `save_delete` | `checkpoint` |

Saves are in `/sdcard/Slopitect/saves/` (with projects.gd, in the project's
own `saves/`): `world.json` (shapes, models, ground and paths, saved within 5
seconds of a change and when the headset pauses the app) and `checkpoints/`.
A part whose module isn't loaded is kept as saved and put back when it loads.

| `projects_list`, `projects_current` | |
| `projects_new` | `name`, optional `modules` [names], `open` (true) |
| `projects_open` | `name` (the world you're in is saved first) |
| `projects_modules` | `name`, `modules` [names]: loaded when it opens |
| `projects_config` (PC only) | `name`, `private` (true: never backed up) |

The first time projects.gd loads, the existing saves become project `start`.

| `terminal_run` | `line` (like `"spawn shape=box"`; a line starting with `{` is JSON) |
| `terminal_type` | `text` |
| `terminal_key` | `key`: shift, backspace, clear, tab, prev, next, run |
| `terminal_scroll` | `by` (lines, + is back) or `end` true |
| `terminal_clear`, `terminal_ask`, `terminal_status` | |
| `terminal_mode` | `mode`: terminal or chat |
| `terminal_help` | optional `name` (a command) |

| `move_status` (controls.gd) | |
| `move_to` | `position` [x, z], optional `facing` (degrees, 0 = -z) |
| `move_comfort` | any of `turn` (snap, smooth), `speed` (0.5 to 3), `deadzone` (0.05 to 0.5), `snap_degrees` (15 to 90), `smooth_degrees` (30 to 180) |
| `move_config` (PC only) | any of `speed`, `deadzone`, `turn` (snap, smooth), `snap_degrees`, `smooth_degrees`, `follow_ground` |
| `grab_status` | |
| `grab_release` | optional `hand` |
| `physics_set` | `name`, `mode` (dynamic, static, off), optional `mass`, `bounce`, `friction` |
| `physics_push` | `name`, `velocity` [x, y, z] |
| `physics_status` | |
| `physics_config` (PC only) | `gravity` |
| `controls_status` | |
| `controls_config` (PC only) | `buttons` {"hand/button": an action, a command like `{"cmd": "spawn", "shape": "box", "position": "in_front"}`, a window to show and hide like `{"panel": "worlds"}`, or ""}, `sticks` {hand: name or ""}, or `reset` true |
| `hands_status` | |
| `aimsg_status` | |
| `aimsg_config` (PC only) | any of `cols` (20–80 characters), `rows` (4–40 lines) |
| `net_fetch` | `url` (https, an allowed host), optional `file` (name, `/` for folders; default the URL's last part), `licence`; returns an `id` |
| `net_status` | optional `id` |
| `net_config` (PC only) | `hosts` [names], or `add` / `remove` (a host) |
| `worlds_do` | `act`: toggle, show (optional `page`: Worlds, Checkpoints, Files, Modules), refresh, new_project / open_project (`name`), checkpoint (optional `label`), restore / delete_checkpoint (`checkpoint`), load_module / unload_module (`name`), folder (`path`, optional `page`), modules_page (`page`) |
| `worlds_status` | |
| `perf_status` | |
| `perf_watch` | `on` (true/false, default true) |
| `perf_modules` | optional `reset` true |
| `perf_load` | optional `name` (one module) |
| `jelly_poke` | optional `strength` (0.1–1) |
| `jelly_status` | |
| `jelly_config` (PC only) | any of `stiffness` (20–400), `damping` (1–30) |
| `hands_config` (PC only) | any of `skin` ("#rrggbb"), `nails` (a colour, or 1 to 5 thumb to pinky, both hands), `nails_left`, `nails_right`, or `reset` true |

| `memory_status` | |
| `memory_recall` | optional `world` (another world's name) |
| `memory_note` | `text` (up to 600 characters), optional `kind` (fact, decision, technique, troubleshooting, todo), `tags` [words], `global` (techniques and troubleshooting are global unless false) |
| `memory_forget` | `id` (w4: this world's note, g2: global note, d3: digest) |
| `memory_search` | `query` (words), optional `everywhere` (every world) |
| `memory_compact` | `summary`; folds this world's exchanges into a digest, or with `digest` (its id) summarises that one |
| `memory_config` (PC only) | any of `capture` (keep conversations, default true), `recall_chars` (1000–8000, default 4000), `clear` ("global" or a world's name) |

Memory is kept in the app's own storage, `user://memory/` (`global.json` and
`worlds/NAME.json`), not in the Slopitect folder, so backups never take it.
A world keeps its last 40 questions; older ones are folded into digests
(at most 30, the oldest merging), so a world's memory stays under about
150 KB. Before anything is stored, text that looks like a key, password,
e-mail address, phone number or IP address is removed, and the agent's
thinking and settings changes are never recorded. While it's loaded the
agent has a skill (`user://skills/slopitect-memory`) telling it to call
`memory_recall` at the start of a conversation; unloading takes it away.

### What assets.gd may reach

Only `https://api.polyhaven.com` and `https://dl.polyhaven.org`, fixed in the
file (changing them changes the file, which needs a new Yes). It sends no key,
cookies or names, only the User-Agent `Slopitect/0.1` that Poly Haven asks
for. Every file must be the size and MD5 Poly Haven lists, a model over 80 MB
isn't downloaded, and files are written only to
`/sdcard/Slopitect/assets/polyhaven/ID/RES/`, with a `credits.json`. Placed
models aren't saved yet; the files are.

The agent can use them too once they're loaded (it may use any live
module you said Yes to). It needs a new conversation to see new tools,
which it can start itself with `new_conversation` (from the next APK).
