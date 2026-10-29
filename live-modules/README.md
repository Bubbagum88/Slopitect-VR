# Live modules

Modules that aren't built into the APK. Each one is a single file you put
in the headset's Slopitect folder and load while the app runs. You say Yes
to its code in the headset first, and you can take it out again with
`code_unload`. A module you said Yes to loads by itself at the next start,
unless its file has changed since.

| File | What it does |
|---|---|
| `controls.gd` | The only thing that reads the controllers: each button is bound to a named action (point, grab_left, grab_right, talk, left_menu, left_y, right_a, right_b) and each thumbstick to a stick (walk, turn). Other modules take the actions, and read how far a grip or trigger is pressed with `value()`. A button can also run a command (never a `*_config` or `agent_` one) or show and hide a window. `controls_status` shows the bindings; `controls_config` (PC only) changes them. X on the left controller always stops the agent and can't be bound |
| `vrui.gd` | Every window: the Menu (a launcher with a tile for every window), wrist panel, the agent's chat window and keyboard, and any panel you or the agent add (`ui_*` commands). Drawn the way the vrui draft drew windows (rounded, wrapped text), redrawn only on a change. Title bars to carry and close windows, tabs, toggles and sliders, a hand window on a controller, rows/columns/grids that lay themselves out, buttons that open a sub-menu with a back arrow, scrolling text, one theme. Needs controls.gd for its buttons. See [docs/VR-UI.md](../docs/VR-UI.md) |
| `tools.gd` | The Tools menu (B on the right controller, or its tile): a button for each loaded tool, which chooses it and opens that tool's own menu (its buttons, Undo / Redo, a back arrow); the windows that are tools (the terminal; any module whose `menu_info()` has `"tools": true`); and one Undo / Redo list for every tool |
| `pause.gd` | The pause menu (first tile on the Menu, or a button bound to `{"panel": "pause"}` with `controls_config`): Resume, Save world (a checkpoint), Load world (the worlds and the newest checkpoints, in a sub-menu), Settings (what each setting is now, the avatar's outfit, a new conversation, stop speaking; the rest change from the PC) and the Worlds window. It doesn't stop the world. Needs vrui.gd; save.gd and projects.gd for saving and loading |
| `chat.gd` | Makes the agent's chat window (Y on the left controller) like the terminal: a green screen that keeps the whole conversation (Up / Down / End scroll it, Cls clears it), the agent's state, the line you type, the keyboard with Send, and STOP and New chat beside the screen. It fills vrui.gd's chat panel, keeping its ids and where you put it, and puts the old layout back when it's unloaded. Uses aimsg.gd's layout when that's loaded |
| `landscape.gd` | Ground you can shape, 20 × 20 m: raise, lower, smooth and flatten brushes. It stands in for the flat floor while it's loaded |
| `paths.gd` | Roads and trails: put down points with the trigger, then press Finish. Optionally levels the ground under the path |
| `save.gd` | Keeps the shapes and models: saved by themselves when they change and put back at start. Checkpoints keep the whole world (ground and paths too) to go back to, with undo |
| `move.gd` | Walk with the left stick (the way you look), turn with the right (30° steps, or smooth); you stand on the landscape's ground |
| `grab.gd` | Hold the grip near a shape or model to pick it up; let go to drop it (or throw it, with physics). One undo per pick-up |
| `physics.gd` | Makes shapes and models fall, bounce and collide (the engine's own physics) once you set them dynamic; the ground is the floor or the landscape |
| `projects.gd` | A world per project (`projects/NAME/` in the Slopitect folder: its saves, notes, and the live modules it uses). Needs save.gd |
| `hands.gd` | Drawn hands with coloured nails in place of the controller boxes; the fingers curl with the grip, trigger and where your thumb rests. Colours from the PC (`hands_config`). Needs controls.gd to move |
| `inspect.gd` | A tool for one thing at a time: point and pull the trigger to select a shape or model, then switch its physics (none, static, dynamic), whether it can be grabbed, hide it, or delete it (one undo). Show hidden brings hidden things back. The switches are kept with each project's world |
| `terminal.gd` | A command line in the headset (A on the right controller): type any of the app's commands, like `spawn shape=box scale=0.3`, and press Run to see the reply. Tab completes a command's name, Prev / Next step through what you ran, Help lists the commands, Up / Down scroll, Cls clears, and Ask AI sends your line with the last command and its reply to the agent. Won't run `*_config` settings. Needs vrui.gd for its window |
| `avatar.gd` | The agent's avatar (it used to be built into the APK): a red cube with a face that thinks while the agent works, shows emotions (`avatar_emotion`), moves its mouth with the words while the speech engine talks, and shows replies a page at a time in a speech bubble above its head, which waits at the edge of your view when the avatar is out of sight. Outfits are made of simple shapes (`avatar_outfit_add`). Other modules use `body()`, `say()`, `set_state()`, `set_emotion()` and `speaking()` |
| `aimsg.gd` | Makes the chat log easier to read: "you>" and "ai>" tags, the agent's words wrapped, markdown marks taken out, code marked with "\|", tool calls and thinking on one short line. It changes no window: the chat log's source asks for it (`"format": "aimsg"`, which needs the vrui.gd from the VR UI work), and shows plain lines when it isn't loaded. Width and height from the PC (`aimsg_config`) |
| `net.gd` | Downloads from the internet, only https and only from hosts allowed on the PC (`net_config`; Poly Haven's to start). Files go in `downloads/HOST/` with a `.source.json` saying where they came from. Other modules download through its `fetch()` |
| `worlds.gd` | The Worlds window, from its tile on the Menu. Tabs: Worlds (open a project's world or make a new one), Checkpoints (keep the world now, go back, delete), Files (look through the Slopitect folder), Modules (load, reload or unload live modules). It keeps nothing itself; it shows and runs projects, save, files and code. Needs vrui.gd; a tab whose module is missing says so |
| `jelly.gd` | The avatar squashes and stretches like jelly as it moves, keeping its volume; `jelly_poke` wobbles it. Needs the live avatar module (its `body()`); spring from the PC (`jelly_config`) |
| `assets.gd` | 3D models from [Poly Haven](https://polyhaven.com) (all CC0): search, download to the headset, place in the world. Powered by Poly Haven |
| `memory.gd` | The agent's memory between conversations: notes it keeps (facts, decisions, troubleshooting, coding techniques), each question you asked in a world with its answer, tools and errors, older ones folded into digests, and each tool's failures. One memory per world (project) plus a global one. Keys and personal info are cleaned out before anything is kept |

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
.\adb push "C:\path\to\live-modules\move.gd" /sdcard/Slopitect/modules/
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
.\slopi.ps1 '{"cmd":"code_load","name":"controls"}'
.\slopi.ps1 '{"cmd":"code_load","name":"ui"}'
.\slopi.ps1 '{"cmd":"code_load","name":"tools"}'
.\slopi.ps1 '{"cmd":"code_load","name":"landscape"}'
.\slopi.ps1 '{"cmd":"code_load","name":"paths"}'
.\slopi.ps1 '{"cmd":"code_load","name":"assets"}'
.\slopi.ps1 '{"cmd":"code_load","name":"save"}'
.\slopi.ps1 '{"cmd":"code_load","name":"move"}'
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
- **Undo / Redo** in the window, or `tools_undo` / `tools_redo`, cover
  every stroke and path, including ones the agent made with commands.

What each saves: the ground's heights in `user://landscape.bin`, paths in
`user://paths.json` (the app's own storage, kept when you install a new
APK over the old one). The undo list is not saved.

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
| `paths_add` | `points` [[x, z], ...], optional `width`, `color`, `flatten`; one undo |
| `paths_delete` | `path` (its id); one undo |
| `paths_settings` | any of `width`, `width_step`, `color`, `flatten` |
| `paths_draft` | `action`: finish, cancel or remove_last |
| `assets_search` | `query` (words), optional `category`; lightest models first |
| `assets_get` | `id`, optional `resolution` (1k, 2k, 4k; default 1k); downloads in the background |
| `assets_status`, `assets_downloaded`, `assets_placed` | |
| `assets_place` | `id`, optional `resolution`, `name`, `position`, `rotation`, `scale` (a number or [x, y, z]) |
| `assets_move` | `name`, any of `position`, `rotation`, `scale` |
| `assets_remove` | `name` (the files stay on the headset) |

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
| `terminal_help` | optional `name` (a command) |

| `move_status` | |
| `move_to` | `position` [x, z], optional `facing` (degrees, 0 = -z) |
| `move_config` (PC only) | any of `speed`, `turn` (snap, smooth), `snap_degrees`, `smooth_degrees`, `follow_ground` |
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
