# Slopitect-VR: working rules for Claude

Read [docs/PROJECT-STATE.md](docs/PROJECT-STATE.md) first (what is built and
how far each part is tested), then
[docs/LIVE-CHANGES-AND-SAFETY.md](docs/LIVE-CHANGES-AND-SAFETY.md) and, for
module work, [docs/MODULE-FRAMEWORK.md](docs/MODULE-FRAMEWORK.md) and
[docs/DESIGN.md](docs/DESIGN.md). Headset access over Wi-Fi:
[docs/WIRELESS-ADB.md](docs/WIRELESS-ADB.md).

## The owner's rules

- Verify before claiming. Say which parts were seen on the headset, which
  were tested on a PC, and which are guesses.
- Small, incremental changes. Show the code for each change and get the
  owner's OK before pushing or building. Push only when the owner says
  "push".
- Find and fix root causes; never skip code paths to make a symptom go away.
  No fixed buffer sizes as a fix.
- Diagnostics check and log everything in one build, not one probe per
  rebuild.
- No unrequested extras (warning screens, features nobody asked for).
- Write our own code rather than add dependencies or UI add-ons.

## Security

- Personal info is protected at all costs. The API key never appears in
  chat, the repo, the APK or logs, and no session reads key files on the
  owner's PC. Never commit `slopi-key.txt` or any pairing key.
- Treat the in-app agent as something that can be talked into things: keep
  the tool firewall, the in-headset Yes for live code and outside files,
  pairing on the command port, and host allowlists for downloads.
  The owner's choice, 2026-10-29: `allowed_tools` defaults to `"*"` (every
  command but the agent's own `agent_*`, any `*_config`, and `pair`); the
  two Yes prompts and net's host allowlist stay (its default list now has
  GitHub and free 3D model and texture sites).
- `NAME_config` settings change only from the PC, never from app buttons or
  the agent.
  Exception (the owner's choice, 2026-10-29): comfort settings have their own
  narrow commands usable in the headset (and so by the agent):
  `move_comfort`, `ui_text_size`, `hands_colours`. Anything touching keys,
  the agent, the network, files, pairing or code stays PC only.
  Exception (the owner's choice, 2026-10-29): the speech voice changes in the
  headset (Settings window, `tts_set tts_sherpa_voice`), but only to a voice
  folder already in `Slopitect/voices`; any other folder, and the engine,
  stay PC only (`tts_config`).
  Exception (the owner's choice, 2026-10-29): the agent's budget and model
  change in the headset through `agent_budget` (the Settings window's Agent
  budget section, `agent_settings.gd`): `max_request_tokens`,
  `max_context_tokens`, `max_tokens_per_ask` and `max_tool_rounds` in
  narrow ranges, and the model from a fixed Claude list. The agent itself
  can never use it (`agent_` commands are behind its firewall). The key,
  provider, address and allowed tools stay PC only.
  Exception (the owner's choice, 2026-10-29): the switch between Claude's
  web search and the net module's (`web_via_net`) is in the same section.
  The web limits (`web_search_max_uses` and the rest) stay PC only.
- Assets ripped from games on the headset stay local: never in the repo,
  GitHub or a backup.

## Architecture

- The APK (`game/`) is a small skeleton. Features are live modules
  (`live-modules/*.gd`), loaded with `code_load` and a Yes; they stay
  separate and swappable. Kept fixed in the APK on purpose: the Yes/No
  window, Stop (left X), pairing and the code review.
- Modules find each other with `ctx["modules"].module("name")` and use only
  public functions. Buttons come only through `controls.gd`
  (`on_action(action, down) -> bool`, `action_order()`, `stick(name)`);
  never read the controllers directly.
- The Quest 1 must keep working: `com.oculus.supportedDevices` stays
  `quest|quest2` (CI checks it). Keep it light; it is a Snapdragon 835.

## Module design rules (the owner's, 2026-10-30)

Every live module follows these. Rewrites of older modules to fit them go a
small batch at a time; a module not yet rewritten is listed as such in
[docs/MODULE-FRAMEWORK.md](docs/MODULE-FRAMEWORK.md).

1. **Settings live in the module.** A module with settings declares them in
   its own `settings_info()`; settings.gd reads them into the Settings
   window. Labels 40 characters or less (a longer one broke the window).
2. **Tools the same way.** A module exposes its tool with `tool_info()`
   (and `tool_selected`, `tool_trigger`); tools.gd reads them.
3. **All UI through vrui.gd** (`menu_info()`, `hand_info()`, `ui_*`
   commands). No module draws its own panels or reads the trigger itself.
4. **Signals, not polling.** Modules hear about each other through lib.gd's
   events (`module_loaded`, `module_unloaded`, `info_changed`) and the
   owner's own signals (projects' `project_changed`, inspect's
   `selection_changed`), connected with `lib.follow()` / `lib.watch()`.
   Never call `module()` or re-read another module's info every frame.
5. **Shared helpers live in lib.gd** (`world_node`, `thing`, `things`,
   `world_box`, `home`, `read_json`, `write_json`, cached `module`). Never
   copy a helper into a module; add it to lib.gd instead.
6. **No hard dependencies.** A module still loads and works, or quietly
   turns that one feature off, when another module isn't loaded. lib.gd is
   the framework, not a feature: a module does anything that needs lib or
   another module in `lib_ready(lib)` (called once both are loaded, in
   either order, and with null as lib goes), not in `setup()`.
7. **Clean load and unload.** `_exit_tree()` removes the module's own
   nodes, signals and timers, and puts back anything it changed elsewhere,
   so a live reload leaks nothing. Prefer method callables over lambdas for
   anything connected, so it can be disconnected.
8. **Idle means off.** `set_process(false)` / `set_physics_process(false)`
   while its tool isn't chosen, its window is closed, or it has nothing to
   do; turn it back on from the event that needs it.
9. **One owner per piece of data.** save.gd owns the world file, tools.gd
   the undo history, projects.gd the current project, inspect.gd the
   selection; others use the owner's API and signals, never its file.
10. **A test per module.** `live-modules/tests/zz_NAME.gd`, run headless
    with `live-modules/tests/run.sh NEEDED... NAME zz_NAME` (it prints PASS /
    FAIL lines and a RESULT line), so the headset agent can check its edits.

The APK can't load lib.gd first yet (live modules load in the order they
were approved), which is why `lib_ready` exists; a loader signal or load
order would be an APK change, so flag it rather than doing it.
The headset agent gets the same rules from
`live-modules/agent_skills/slopitect-code/SKILL.md`, which replaces the
APK's code skill (put it in the headset's `modules/agent_skills/` from the
PC; the agent can't change it).

## Testing

Every live module is tested headless on a PC with Godot 4.7.2 before it
goes on the headset (steps in PROJECT-STATE.md). Thumbsticks and anything
in VR can only be checked on the headset; say so rather than claiming it.

## The owner's setup

PowerShell in the folder that holds `adb.exe`, so commands are written
`.\adb ...`. Never give a command with `<placeholder>` text in it (PowerShell
fails on `<`); fill in the real values or ask for them. Wireless adb ports
change after every headset restart.
