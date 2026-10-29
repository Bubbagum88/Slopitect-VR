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

## Testing

Every live module is tested headless on a PC with Godot 4.7.2 before it
goes on the headset (steps in PROJECT-STATE.md). Thumbsticks and anything
in VR can only be checked on the headset; say so rather than claiming it.

## The owner's setup

PowerShell in the folder that holds `adb.exe`, so commands are written
`.\adb ...`. Never give a command with `<placeholder>` text in it (PowerShell
fails on `<`); fill in the real values or ask for them. Wireless adb ports
change after every headset restart.
