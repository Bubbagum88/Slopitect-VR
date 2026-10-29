# Live modules

Modules that aren't built into the APK. Each one is a single file you put
in the headset's Slopitect folder and load while the app runs. You say Yes
to its code in the headset first, and you can take it out again with
`code_unload`. A module you said Yes to loads by itself at the next start,
unless its file has changed since.

| File | What it does |
|---|---|
| `tools.gd` | The tool window (B on the right controller): a button for each loaded tool, the chosen tool's buttons, and one Undo / Redo list for every tool |
| `landscape.gd` | Ground you can shape, 20 × 20 m: raise, lower, smooth and flatten brushes. It stands in for the flat floor while it's loaded |
| `paths.gd` | Roads and trails: put down points with the trigger, then press Finish. Optionally levels the ground under the path |
| `save.gd` | Keeps the shapes and models: saved by themselves when they change and put back at start. Checkpoints keep the whole world (ground and paths too) to go back to, with undo |
| `assets.gd` | 3D models from [Poly Haven](https://polyhaven.com) (all CC0): search, download to the headset, place in the world. Powered by Poly Haven |

A tool is any module with a `tool_info()` function, so a new tool is a new
file; `tools.gd` explains what a tool gets. Tools work without the tools
module (through their commands), but have no window or undo without it.

## Putting them on the headset

From the platform-tools folder:

```
.\adb shell mkdir -p /sdcard/Slopitect/modules
.\adb push "C:\path\to\live-modules\tools.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\landscape.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\paths.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\assets.gd" /sdcard/Slopitect/modules/
.\adb push "C:\path\to\live-modules\save.gd" /sdcard/Slopitect/modules/
.\slopi.ps1 '{"cmd":"code_load","name":"tools"}'
.\slopi.ps1 '{"cmd":"code_load","name":"landscape"}'
.\slopi.ps1 '{"cmd":"code_load","name":"paths"}'
.\slopi.ps1 '{"cmd":"code_load","name":"assets"}'
.\slopi.ps1 '{"cmd":"code_load","name":"save"}'
```

Each `code_load` shows the code in the headset and waits for your Yes.

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

Saves are in `/sdcard/Slopitect/saves/`: `world.json` (shapes and models,
saved within 5 seconds of a change and when the headset pauses the app) and
`checkpoints/`. The ground and paths keep saving themselves as before;
checkpoints hold them too.

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
