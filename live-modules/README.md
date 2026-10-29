# Live modules

Modules that aren't built into the APK. Each one is a single file you put
in the headset's Slopitect folder and load while the app runs. You say Yes
to its code in the headset first, and you can take it out again with
`code_unload`. A module you said Yes to loads by itself at the next start,
unless its file has changed since.

| File | What it does |
|---|---|
| `controls.gd` | The only thing that reads the controllers: each button is bound to a named action (point, grab_left, grab_right, talk, left_menu, left_y, right_a, right_b) and each thumbstick to a stick (walk, turn). Other modules take the actions. `controls_status` shows the bindings; `controls_config` (PC only) changes them. X on the left controller always stops the agent and can't be bound |
| `ui.gd` | Every window: the menu bar, wrist panel, the agent's chat window and keyboard, and any panel you or the agent add (`ui_*` commands). Needs controls.gd for its buttons |
| `tools.gd` | The tool window (B on the right controller): a button for each loaded tool, the chosen tool's buttons, and one Undo / Redo list for every tool |
| `landscape.gd` | Ground you can shape, 20 × 20 m: raise, lower, smooth and flatten brushes. It stands in for the flat floor while it's loaded |
| `paths.gd` | Roads and trails: put down points with the trigger, then press Finish. Optionally levels the ground under the path |
| `save.gd` | Keeps the shapes and models: saved by themselves when they change and put back at start. Checkpoints keep the whole world (ground and paths too) to go back to, with undo |
| `move.gd` | Walk with the left stick (the way you look), turn with the right (30° steps, or smooth); you stand on the landscape's ground |
| `grab.gd` | Hold the grip near a shape or model to pick it up; let go to drop it (or throw it, with physics). One undo per pick-up |
| `physics.gd` | Makes shapes and models fall, bounce and collide (the engine's own physics) once you set them dynamic; the ground is the floor or the landscape |
| `projects.gd` | A world per project (`projects/NAME/` in the Slopitect folder: its saves, notes, and the live modules it uses). Needs save.gd |
| `inspect.gd` | A tool for one thing at a time: point and pull the trigger to select a shape or model, then switch its physics (none, static, dynamic), whether it can be grabbed, hide it, or delete it (one undo). Show hidden brings hidden things back. The switches are kept with each project's world |
| `avatar.gd` | The agent's avatar (it used to be built into the APK): a red cube with a face that thinks while the agent works, shows emotions (`avatar_emotion`), moves its mouth with the words while the speech engine talks, and shows replies a page at a time in a speech bubble above its head, which waits at the edge of your view when the avatar is out of sight. Outfits are made of simple shapes (`avatar_outfit_add`). Other modules use `body()`, `say()`, `set_state()`, `set_emotion()` and `speaking()` |
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
.\adb push "C:\path\to\live-modules\ui.gd" /sdcard/Slopitect/modules/
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
.\adb push "C:\path\to\live-modules\avatar.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\memory.gd" /sdcard/Slopitect/modules/
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
.\slopi.ps1 '{"cmd":"code_load","name":"avatar"}'
.\slopi.ps1 '{"cmd":"code_load","name":"memory"}'
```

Each `code_load` shows the code in the headset and waits for your Yes
(the right thumbstick scrolls the code). Load controls.gd and ui.gd first:
until they're loaded, the buttons do nothing but the Yes/No question and
Stop, and there are no windows.

## Using them

Press B on the right controller for the tool window and pick a tool.
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

| `move_status` | |
| `move_to` | `position` [x, z], optional `facing` (degrees, 0 = -z) |
| `move_config` (PC only) | any of `speed`, `turn` (snap, smooth), `snap_degrees`, `smooth_degrees`, `follow_ground` |
| `grab_status` | |
| `grab_release` | optional `hand` |
| `physics_set` | `name`, `mode` (dynamic, static, off), optional `mass`, `bounce`, `friction` |
| `physics_push` | `name`, `velocity` [x, y, z] |
| `physics_status` | |
| `physics_config` (PC only) | `gravity` |

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
