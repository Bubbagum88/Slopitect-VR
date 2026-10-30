# Live modules: the framework and the review of the draft modules

Written 2026-10-29. A plan, not built yet: nothing here is done until it is
listed as done in [PROJECT-STATE.md](PROJECT-STATE.md).

## Summary

Eleven modules were handed in. Eight are new (now in
[`live-modules/drafts/`](../live-modules/drafts/)); landscape is the same as
the repo's, and paths and tools are older copies of the repo's.

The eight new ones work on their own, but they don't fit together yet. They
find each other by guessing at hidden variables, read the controllers
directly, and do things other modules already do. The fix is a small
framework: a few rules every module follows, so modules plug into each other
instead of reaching inside each other. Most of it can be done in live
modules; a few parts need the APK.

The biggest problems found:

- **Three pairs do the same job.** stick_move and move both move you, and
  stick_move puts walking on the right stick, which move uses for turning.
  controller and controls both bind buttons. world and save both save the
  world, and world's format leaves out models and the inspect switches.
- **aimsg and the avatar fight.** The avatar already shows "thinking" and
  puts replies in its bubble; aimsg does the same, so both set its state.
- **vrui gets around the safety rules.** It reads the trigger itself, so the
  same pull that answers a Yes/No question can also press a vrui button
  behind it.
- **web downloads from any address on the internet.** assets only allows
  Poly Haven; web_fetch would let the agent fetch any file onto the headset.
- **Settings are lost when the app restarts** (aimsg, jelly, hands,
  stick_move), and the agent can change them, which breaks the rule that
  settings only change from the PC.

## The framework

A set of plug-in points every module uses. tools.gd already works this way:
any module with a `tool_info()` function shows up as a tool. The framework
uses that same pattern everywhere, so a module joins in by having the right
function, and leaves cleanly when it's unloaded.

| Rule | What a module does | What it replaces | Where it lives |
| --- | --- | --- | --- |
| Find modules by name | `ctx["modules"].module("avatar")`, then call the public functions it documents | Guessing at hidden variables (`_panels`, `_holder`, `_root`) | Already there |
| Input only through controls | `on_action(action, down)` for buttons; `stick("walk")` for thumbsticks; a new `value(hand, "grip")` for how far a grip or trigger is pressed | Reading the controllers directly (controller, stick_move, vrui, hands) | controls.gd (live); `value()` is new |
| One settings helper | Lists its defaults once; they're kept in `user://NAME.json`, and `NAME_config` (PC only) changes them | Each module writing its own load and save, or not saving | module.gd (APK) |
| Save by plug-in | `save_part()` returns its data and `load_part(data)` puts it back; save finds every module that has them | The list of parts written into save.gd, and world's separate format | save.gd (live) |
| Settings by plug-in | `settings_info()` returns its section of the Settings window: a title and each setting's type (choice, slider, toggle, button), current value, range or options, and the comfort command that sets it | Each menu hard-coding every module's settings (pause.gd's Settings page) | settings.gd (live), contract at its top |
| Menus by plug-in | `menu_info()` returns a window's name and the panel it opens (or a command); the Menu shows a tile for each | Every module building its own way into its windows | vrui.gd (live), see [VR-UI.md](VR-UI.md) |
| Events, not polling | The agent sends signals (started, replied, stopped); modules connect to them | aimsg and the avatar asking agent_status 2 to 3 times a second | agent.gd (APK) |
| Internet through one gate | A download goes through one fetch function that only allows the hosts approved on the PC | web.gd downloading from anywhere | A net helper (live), hosts set with `net_config` |
| A header at the top | `const INFO := {"needs": ["controls", "ui"], "version": 1}` | Modules that silently do nothing when another is missing | code.gd (APK) reads it and loads what's needed first |

With these in place, the agent's code skill becomes a checklist: which
plug-in points to use, and never reach into another module's variables or
read the controllers directly. A module template and a PC test harness
(every module checked headless before it goes on the headset) come with it.

## Each module

Keep means tidy it but keep the idea; merge means fold it into a module we
already have; drop means the repo already does the same job.

| Module | What it does | Problems found | Plan |
| --- | --- | --- | --- |
| aimsg | Formats the chat log (role tags, wrapping, markdown stripped, code marked) and drives the avatar from the agent's state | The avatar part fights avatar.gd. It guesses at status fields when agent_status gives busy, round, last_reply, last_error, events and status_line. Writes a leftover debug file, aimsg_debug.json. aimsg_set lets the agent change settings, lost on restart. Polls twice a second | Keep the chat formatting only. Drop the avatar driving and the debug file, read the real fields, settings in aimsg_config. Later, signals instead of polling |
| controller | Binds a button to a command or a panel toggle; attaches vrui panels to a controller | Same job as controls.gd and reads the raw buttons too, so a press can fire twice. Takes over ui's toggles by blanking them. Treats ctx modules as a Dictionary (it is a node with module()), reaches into vrui's private `_panels`/`_holder`. Saves controller.json where the agent can write | Merge: "button runs a command" becomes a binding kind in controls_config; panel attaching moves into vrui (or ui) as a public command. Then drop it |
| hands | Drawn hands with nails; fingers curl with grip, trigger and touch; hides the box controller models | Reads the controllers directly; colours and sizes not saved. Otherwise clean | Keep. Read through controls.value(); save colours in hands_config |
| jelly | Squash and stretch on the avatar; jelly_poke wobbles it | Guesses the avatar's property names (avatar.gd's are private `_root`/`_body`), falls back to searching the scene for "vatar". Same modules mistake as controller. Settings agent-changeable and lost | Keep. avatar.gd gets a public body(); settings in jelly_config |
| stick_move | Smooth movement on the right stick | move.gd already walks on the left stick and the right stick turns, so both would run. Reads the stick directly | Drop. Walking on the right stick is one line in controls_config sticks |
| vrui | Real Godot buttons, sliders and text on a panel (idea from MT-ZD/Godot-3D-VR-UI, MIT) | Reads the trigger itself, so it can be pressed while a Yes/No question is open. Redraws every frame (UPDATE_ALWAYS), a real cost on the Quest 1. Panels lost on restart | Keep: the best start for our own widgets. Take "point" from controls, nothing while confirm asks, redraw only on change, save panels. Maybe become how ui.gd draws |
| web | Downloads any http(s) URL into assets/, up to 50 MB | No allowed-sites list, unlike assets.gd | Fold into one net helper with the allowed sites in net_config |
| world | Named worlds (save, load, new, delete, list, autosave) plus Worlds, Files and Modules windows | Own save format leaves out models and switches; duplicates save.gd and projects.gd; uses controller_toggle; guesses at landscape | Keep the three windows as menu entries on top of save and projects. Drop its save format |
| landscape | Terrain | Same as the repo's | Nothing |
| paths | Paths | Older copy, without get_paths/set_paths, so saving paths would break | Use the repo's |
| tools | Tool picker | The copy from before controls.gd; reads the trigger itself | Use the repo's |

## Order of work

Each step is shown with its code before it goes anywhere, and tested on the
PC first.

Live modules only (no new APK):

1. Keep the repo's paths.gd and tools.gd; drop stick_move.gd. *(Done.)*
2. controls.gd: add `value(hand, name)` for grip and trigger, and "run a
   command" as a binding kind. Then drop controller.gd. *(Done, PC-tested;
   panel attaching is vrui.gd's `hand` place, step 5.)*
3. hands.gd: read through controls, save colours. *(Done, PC-tested.)*
4. aimsg.gd: chat formatting only, real fields, no debug file. *(Done,
   PC-tested: vrui.gd shows a source through a module's format(), so aimsg
   changes no window; that vrui.gd part comes with the VR UI work.)*
5. vrui.gd: take "point" from controls, respect the Yes/No window, redraw
   only on change, save panels, take over panel attaching. *(Done,
   PC-tested: vrui.gd now draws every panel the vrui way, takes "point" from
   controls, does nothing while a question is up, draws again only on a
   change and saves panels; panel attaching is the `hand` place. The vrui
   draft is gone.)*
6. world.gd: keep the windows, on top of save and projects. *(Done,
   PC-tested: worlds.gd, one window with Worlds, Checkpoints, Files and
   Modules tabs, opened from its tile on the Menu; world's own save format
   is dropped.)*
7. web.gd: fold into a net helper with an allowed-sites list. *(Done,
   PC-tested against a local https server: net.gd, hosts in net_config,
   redirects checked hop by hop. Poly Haven's two hosts to start.)*

Needs the next APK:

- A settings helper in module.gd, so every `NAME_config` works the same way
  and is PC only.
- Signals from agent.gd (reply, busy, error), so modules stop polling.
- The INFO header that code.gd reads, so a module's needs load first.
- The avatar out of the APK: live-modules/avatar.gd (with `body()`) takes
  its place, and can only load once the built-in one is gone.

Until those land, the live modules use small stand-ins, marked as such in
the code.

Open decisions (the owner's):

- Drop stick_move, controller and world's save format in favour of move,
  controls and save? (Recommended: yes.)
- ~~Should vrui become how all panels are drawn?~~ Decided 2026-10-29: yes,
  vrui.gd draws every panel the vrui way, only on a change. Still to see:
  frame time on the Quest 1 with several panels.
- Which sites may web downloads come from? assets.gd's list is the start.

## Rewriting every module to the design rules (from 2026-10-30)

The owner's ten rules are in [CLAUDE.md](../CLAUDE.md#module-design-rules-the-owners-2026-10-30).
The foundation is `live-modules/lib.gd` (shared helpers, module events,
`lib_ready`). Each module is rewritten in a small batch with a test in
`live-modules/tests/`. PC means tested headless; nothing below has been
seen on the headset yet.

| Module | State |
| --- | --- |
| lib | New; `world_file()` added in batch 4a, the `thing_entered(node)` event in 4b, `thing_exited(name)` in 4c. PC (tests/zz_lib.gd, 36 checks) |
| projects | Batch 1. Emits `project_changed(project, folder)`; joins save through `lib.watch` instead of checking every frame; no `_process`. PC (zz_projects, 13) |
| physics | Batch 1. Bodies come back when a thing joins the world (no 1 s scan); idle when nothing is physical; ground follows landscape through lib; `_find` is lib's `world_node`. A thing or body freed by something else is let go at once (a freed body is made again), not tripped over every frame (found by the headset agent). PC (zz_physics, 16) |
| jelly | Batch 1. Off without an avatar, on when it loads (`lib.watch`). PC (zz_jelly, 13) |
| hands | Batch 1. No `module()` lookups per frame; idle while hidden, while beatsaber's sabers are chosen, or without controls. PC (zz_hands, 15) |
| vrui | Batch 2 (signals only; its own polling comes later). `panel_shown(id_panel, on)`, `page_changed(id_panel, page)`, `panel_changed(id_panel)`, `focus_changed`. PC (zz_vrui, 8) |
| keyboard | Batch 2b. No 0.25 s check: looks again when a window opens, closes or changes, the focus moves, the terminal switches mode, or a module comes or goes. PC (zz_keyboard, 10) |
| terminal | Batch 2b. `mode_changed(mode)`; no 0.25 s window check; Chat mode follows chat.gd's `transcript_changed`, and reads the agent itself only when chat.gd isn't loaded; idle otherwise. PC (zz_terminal, 9) |
| chat | Batch 2b. `transcript_changed`; refills its window on vrui loading or its panel changing, not every second. Still reads agent_status twice a second: the agent has no signals (an APK change). PC (zz_chat, 4) |
| tts | Batch 2b. Sound files checked only while there's speech to write or play; tells Settings when a value changes. Still reads the agent's replies twice a second (APK). PC (zz_voice) |
| vtt | Batch 2b. Runs only while you talk, while words are turned into text, and until the hand menu shows the line; tells Settings when a value changes. PC (zz_voice, 8) |
| settings | Batch 2. No 1 s scan: draws when the window opens, and while open when a module comes, goes or calls `lib.touch(self)`. Modules with settings must call `lib.touch(self)` when a value changes outside the window (hands does; controls, avatar, tts, vtt, vrui, joints, agent_settings still to do). PC (zz_settings, 13) |
| library | Batch 2. Tabs through `page_changed`; runs only while a model waits for its download. PC (zz_library, 0 failed) |
| landscape | Batch 2. Physics only while it's the chosen tool; the ground is redrawn 20 times a second while painting, not every tick. PC (zz_landscape, 7) |
| paths | Batch 2. No per-frame landscape check (`lib.watch`/`follow`); aiming only while chosen. Textures from `downloads/` (the headset agent's `paths_texture`), through `lib.home()`, names kept inside downloads/. PC (zz_paths, 17) |
| vrui (Menu tiles) | Batch 3. The Menu's tiles are looked at again on module and window events, not every 0.5 s (still every 0.5 s without lib). Text `source`s stay polled while shown: that's their contract. PC (zz_menu, 5) |
| controls | Batch 3. confirm and landscape kept at hand (they were looked up several times a frame); tells Settings when move settings change. Walking and turning read the sticks every frame: that's input. PC (zz_controls, 7) |
| avatar | Batch 3. tts kept at hand (it was looked up every frame). Still reads agent_status twice a second (APK). PC (old test, all pass) |
| holster | Batch 3. Off without an avatar; no per-frame lookups. PC (old test, 35) |
| memory | Batch 3. Follows projects' `project_changed` instead of reading projects' own file (one owner per piece of data). Still reads agent_status (APK). PC (zz_memory, zz_memory_world, 4) |
| net | Batch 3b. Folder and saving through lib; `downloads/` made in `lib_ready`, `net_fetch` waits for lib. The allowed hosts still load in `setup()` so the safety list is never at its default. PC (zz_net, 10, no network) |
| assets | Batch 3b. Its models folder is made in `lib_ready` (no copied Slopitect-folder path); `assets_get` and `assets_place` wait for lib; tools found through lib. PC (zz_assets, 9, no network) |
| aimsg | Batch 3b. Its size loads and saves through lib's JSON helpers, once lib is there (the defaults until then). PC (zz_aimsg, 7) |
| perf | Batch 3b. `perf_load` finds the modules folder through `lib.home()` (says it needs lib otherwise); it still notes every frame time on purpose (perf_status looks back 10 s). PC (zz_perf, 5) |
| agent_tuning | Batch 3b. The extra skills folder comes from `lib.home()`; without lib only the shipped skills. PC (zz_agent_tuning, 4) |
| worlds, agent_settings | Batch 3b. Already fit (no per-frame work, no copied helpers); tests only. PC (zz_worlds, 9; zz_agent_settings, 3) |
| textures, doors, multi | Batch 4a. Their per-world files come from the new `lib.world_file()` (save's folder) instead of each reading user://projects.json every 2 s; they load again on projects' `project_changed`. textures checks its shapes only while one has a texture; doors runs only while one swings; multi draws only while it's the chosen tool and keeps groups together only while there are some (grab found through lib, not every physics frame). multi uses lib's `things`/`thing`/`world_box`. PC (zz_textures, 8; zz_doors, 9; zz_multi, 10; zz_undo, zz_gaps) |
| tool_front, sweet_potato, beatsaber_path | The headset agent's, rewritten to the rules. tool_front hears vrui's `panel_shown` (no 0.3 s scan of every module). sweet_potato hears assets' new `placed` signal and runs only while a potato waits or a tree grows, moving its shapes straight (not dozens of commands a second), and growing adds nothing to undo. beatsaber_path is idle without beatsaber; with it, it reads its `running` flag each frame (beatsaber has no signal and stays as it is). PC (zz_tool_front, 5; zz_sweet_potato, 14; zz_beatsaber_path, 7) |
| grab, inspect, prefabs | Batch 4b. grab runs each physics frame only while a hand holds something (the throw speed is taken while held). inspect has no 0.5 s scan: a thing made or put back gets its switches from lib's new `thing_entered` event, and the outline is drawn only while Inspect is chosen. prefabs' folder and files go through lib (commands wait for it). All three use lib's thing helpers instead of their own copies. PC (zz_grab, 8; zz_inspect, 9; zz_prefabs, 7; zz_undo, zz_gaps, zz_library) |
| tools, shapes, joints | Batch 4c. tools has no 0.5 s scan of every module: its menus are built again when a module comes, goes or calls `lib.touch(self)`, a button is pressed (vrui's new `pressed` signal), the trigger is used on a tool, the undo list changes or another project opens. Tools whose buttons change from a command (multi, inspect, shapes, joints) call `lib.touch(self)`. shapes forgets a deleted shape from lib's new `thing_exited` (no 0.5 s scan), aims only while chosen and moves its attach-point markers only while they're shown. joints runs each physics frame only while there are joints, finds physics through lib (not per joint per frame), and draws marks only while shown. PC (zz_tools, 8; zz_shapes, 7; zz_joints, 9; zz_undo, zz_gaps) |
| save, pause | Batch 4d. save has no per-frame check: a part waiting for its module goes back on lib's `module_loaded`; the world opens in `lib_ready` (after projects has named its folder, so it opens once and save no longer reads projects.json); the 5 s autosave is a Timer, stopped while lib is gone; it lets go of the landscape's signal on unload. pause has no 1 s scan: the hand menu is built again (once a frame at most) when a module comes, goes or calls `lib.touch(self)`, or vrui says the hand menu or wrist panel changed. PC (zz_save, 14; zz_pause, 10; zz_projects, zz_undo, zz_gaps) |
| everything else | Not started |

Still needs the APK (flagged, not done): loading lib.gd first, so `setup()`
could use it directly.
