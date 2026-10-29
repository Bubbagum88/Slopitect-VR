# Project state

Everything built so far, how sure we are that each part works, the
decisions behind it, and what is still open. Updated 2026-10-29.

Three levels of "works" are used, and kept apart on purpose:

- **Headset**: seen working on the Quest 1.
- **PC**: tested headless on a PC with Godot 4.7.2 (and opengl3 renders);
  not yet seen on the headset.
- **Untested**: written, not run anywhere yet.

## What Slopitect is

A VR sandbox for the Oculus Quest 1 that an AI agent changes while you
stand in it. The APK is a small skeleton (command server, module loader,
safety window, agent, voice). Everything else is a **live module**:
a GDScript file pushed to the headset and loaded while the app runs, after
a Yes in the headset. Modules stay separate and swappable.

- Engine: Godot 4.7.2, Compatibility (GLES3) renderer, OpenXR through
  godot_openxr_vendors 5.1.0. GDScript everywhere; native code only for a
  measured hot spot.
- No outside UI add-ons or dependencies where we can write our own.
- Licence: MIT.

## Done

### The APK (in `game/`)

| Part | What it does | Works |
| --- | --- | --- |
| Empty room | Starts OpenXR on the Quest 1; logs GPU, runtime, resolution, frame rate, memory | Headset (72 Hz, about 71.7 fps, 34 MB) |
| Command server | Port 7777 on loopback, JSON lines; modules register commands | Headset |
| Modules | `game/modules.json`; a module that fails is logged and skipped | Headset |
| Agent | Claude (Anthropic) and OpenAI-style providers; tools are the app's commands; skills are `SKILL.md` files; `allowed_tools` firewall; prompt caching and token limits; short replies (caveman skill) | Headset with a real key (needs a workspace-scoped key) |
| Chat window | Y opens a terminal-style window with keyboard, Send and STOP; left X always stops the agent | Headset (typing) |
| Files | The agent's own `/sdcard/Slopitect` folder freely; anything else needs your Yes each time | Headset (`files_status`) |
| Voice | Speech out through Android TTS; hold-to-talk speech to text on the headset (godot-whisper) | TTS returns ok with SherpaTTS; audible not confirmed; STT: the headset couldn't load the whisper library (a missing function, fixed in CI; new APK not yet on the headset) |
| Live code | `code_load` loads a module after your Yes; `code_unload` turns it off | PC |
| Confirm | The Yes/No window only you can answer; shows a module's whole code on its own sheet (right stick scrolls, 5 min wait) | PC |
| View | `view_look` gives the agent a picture of the world | PC |
| Errors | Keeps the app's recent errors; tells the agent about its modules' errors | PC |
| Pairing | The command port only takes commands from programs you said Yes to (`slopi.ps1 -Pair`) | PC |

Fixed in the APK on purpose (owner's choice): the Yes/No window, Stop on
left X, pairing, and the code review.

### Live modules (in `live-modules/`)

All PC-tested, none yet on the headset. See
[live-modules/README.md](../live-modules/README.md) for commands.

| Module | What it does |
| --- | --- |
| controls | The only reader of buttons and thumbsticks; turns them into named actions; bindings changed from the PC (`controls_config`) |
| ui | Every window: panels of text, buttons, inputs, toggles and sliders that you or the agent can change live; title bars, tabs, a launcher Menu, one theme, hover and haptic feedback ([VR-UI.md](VR-UI.md)) |
| tools | Tool picker with shared undo |
| landscape | Terrain |
| paths | Paths |
| assets | Poly Haven models (CC0), only from allowed hosts |
| save | Checkpoints with undo; shapes, models, landscape, paths and inspect switches |
| projects | A folder (world) per project |
| move | Walk (left stick) and turn (right stick) |
| grab | Pick things up with the grip |
| physics | Static or dynamic bodies |
| inspect | Point at a thing to switch its physics, grabbing and hiding, or delete it |
| avatar | The agent's avatar, moved out of the APK: animations, emotions, a mouth that follows speech, a paged speech bubble that docks at the edge of view, outfits; `body()` for other modules (jelly). The APK avatar it replaces was seen on the headset; this one is PC-tested only |
| memory | The agent's memory per world and global: notes, past questions with their tools and errors, digests; keys and personal info cleaned out |

Drafts waiting to be reworked: [live-modules/drafts/](../live-modules/drafts/)
(aimsg, controller, hands, jelly, stick_move, vrui, web, world). The plan for
them is in [MODULE-FRAMEWORK.md](MODULE-FRAMEWORK.md).

### PC tools (in `tools/`)

`slopi.ps1` (one command; `-Pair`, `-SetKey`), `slopi-chat.ps1` (talk to the
agent from the PC), `slopi-backup.ps1` (back a project up into a git repo
on the PC). The last two are untested (no PowerShell in the build
container).

## Rules the project keeps

- **Personal info is protected.** The API key never goes in chat, the repo,
  the APK or logs; it is sent with `slopi.ps1 -SetKey` into app storage.
  Pairing keys (`slopi-key.txt`) are never committed.
- **The agent can be talked into things**, so: a tool firewall, a Yes in the
  headset for live code and for files outside its folder, pairing on the
  command port, and downloads only from allowed hosts.
- **Settings (`NAME_config`) change only from the PC**, never from buttons
  in the app or from the agent.
- **Assets taken from games on the headset stay local**, never in the repo
  or a GitHub backup. Downloaded assets record their source and licence
  (Poly Haven first; Kenney, Quaternius, Poly Pizza, Sketchfab CC0/CC-BY as
  backups).
- **Root causes, not workarounds.** Diagnostics log everything in one go.
- **Small steps**, each one tested before the next. A change is shown with
  its code before it is pushed or built.
- **Keep the Quest 1 working:** `com.oculus.supportedDevices` must stay
  `quest|quest2` (CI checks it); a newer headset name makes the Quest 1
  abort at start.

## How to build and test

- **APK:** every push builds one in GitHub Actions (`quest1-apk.yml`), signed
  with `ci/debug.keystore` so builds install over each other. Install with
  `.\adb install -r slopitect-quest1-debug.apk`.
- **Live module on the headset:** `.\adb push NAME.gd /sdcard/Slopitect/modules/`,
  then `.\slopi.ps1 code_load` and Yes in the headset. After a fresh APK,
  load `controls.gd` and `ui.gd` first, or there are no windows.
- **Headless on a PC** (how every live module so far was tested):
  1. Godot 4.7.2 Linux build; run `--headless --import` in `game/` once,
     then remove the `.uid` files and `openxr_action_map.tres` it writes.
  2. Approved modules go in `files_home/modules`, with their sha256 listed
     in the app's `code.json` user data.
  3. A test client writes `pairing.json` with a known key's sha256 and sends
     that `pair_key` with each command.
  4. A small helper module can press buttons by emitting the controllers'
     signals (for example `button_pressed` with `trigger_click`).
  5. Pictures: `xvfb-run -a` with `--rendering-driver opengl3`, then
     `view_look`.
  Thumbsticks can't be pressed this way; they are only tested on the
  headset.

## Open

- **Headset test of the next APK** (PR #7): view, errors, pairing, the code
  sheet, controls and ui as live modules, and every live module.
- **Speech to text** on the headset: the startup log showed `dlopen failed:
  cannot locate symbol _ZN12_GLOBAL__N_14loadI13__Float32x4_ttEET_PKT0_`.
  godot-whisper's own sgemm.cpp patch hid that function on CPUs without
  half-float vector maths (the Quest 1); `ci/patch-godot-whisper.py` keeps it,
  and CI now fails if the library is missing any of its own functions.
  Needs the new APK on the headset, then `voice_config` with
  `stt_engine` `"local"`. Whether speech out is audible is not confirmed.
- **Module framework** ([MODULE-FRAMEWORK.md](MODULE-FRAMEWORK.md)): the
  owner's decisions, then the live-module steps, then the APK pieces.
- **Roadmap** (README): Claude on the PC through MCP (step 4), backups to
  GitHub (step 5), resource packs for upgrades while playing (step 9).
- **VR UI revamp** ([VR-UI.md](VR-UI.md)): PC-tested; needs the headset
  test (text sizes, hover, haptics, follow panels).
- **Not started:** more shapes (lathe, extrude),
  an asset library, a safe browser, the game-asset extraction catalogue
  (drafted, never committed).
