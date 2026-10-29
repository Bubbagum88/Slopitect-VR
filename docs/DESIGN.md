# Design: how Slopitect is built and why

The ideas that every part of Slopitect follows. For what is built and how
far each part is tested, see [PROJECT-STATE.md](PROJECT-STATE.md); for the
safety rules in detail, [LIVE-CHANGES-AND-SAFETY.md](LIVE-CHANGES-AND-SAFETY.md).

## 1. A small APK, everything else live

The APK (`game/`) is a skeleton that rarely changes: the command server,
the module loader, the Yes/No window, Stop on left X, pairing, the code
review and the agent. Every feature is a **live module**
(`live-modules/*.gd`): a GDScript file pushed to the headset and loaded
while the app runs with `code_load`, after you have read its code and said
Yes in the headset.

- Prefer a live module over an APK change. A new APK is needed only for
  engine settings (renderer, physics engine), Android permissions, native
  plugins (whisper) or the parts kept fixed on purpose.
- Modules stay separate and swappable. Unloading one takes its windows,
  buttons and settings with it; nothing else names it.
- When a module grows several jobs (for example the avatar growing into
  different avatars), it is split into modules rather than made bigger.

## 2. How modules fit together

- **Finding each other:** `ctx["modules"].module("name")`, and only public
  functions are used. A module that needs another one checks that it's
  loaded and says so if not, instead of failing.
- **Input:** only `controls.gd` reads buttons and thumbsticks. Others get
  named actions through `on_action(action, down) -> bool`, `stick(name)`
  and `value()`, and buzz a hand with `pulse()`. Never read the
  controllers directly. (`controller.gd` is retired.)
- **Windows:** `vrui.gd` is the one window system. Every window is a panel
  of data (text, buttons, inputs, toggles, sliders) that you or the agent
  can change live. Modules look it up as `module("vrui")`, falling back to
  `module("ui")`. Shared names other modules rely on: `theme()`,
  `set_text()`, `scroll_text()`, text `"format"` sources. See
  [VR-UI.md](VR-UI.md).
- **Hooks instead of edits.** A module plugs into the menus by declaring
  what it offers, so nobody edits a menu to add a module:

  | Hook | Where it shows | Returns |
  | --- | --- | --- |
  | `menu_info()` | a tile on the Menu bar | `{id, label, order, panel or action}` |
  | `hand_info()` | a button on the hand menu | the same, one or a list |
  | `settings_info()` | a section of the Settings window | `{title, order, settings: [choice, slider, toggle or button]}`, each with the command that changes it |
  | `tool_info()` | the module's page in the Tools menu | its buttons |

- **Menus:** one hand menu (Home, Settings, Undo, Redo, Tools, Terminal and
  each module's `hand_info()`), which snaps on and off the left hand. The
  pause menu on the left home button holds Save, Load, Worlds and Settings.
  Windows go back to their usual spot unless their title-bar Pin is lit.
  Menu buttons toggle their window.
- **Undo:** every change goes through `tools.gd`'s single undo list.

## 3. Safety, because the agent can be talked into things

- The tool firewall (`allowed_tools`), a Yes in the headset for live code
  and for files outside the Slopitect folder, pairing on the command port,
  and downloads only over https from hosts allowed on the PC (`net_config`).
- `NAME_config` settings change only from the PC, never from a button or
  the agent. The only exception is the comfort settings (`move_comfort`,
  `ui_text_size`, `hands_colours`, `tts_set`, `vtt_set`). Anything touching
  keys, the agent, the network, files, pairing or code stays PC only.
- Personal info and API keys never go in issues, the repo, the APK or
  logs. Assets taken from games on the headset stay local, never in the
  repo or a GitHub backup. Downloaded assets record their source and licence.

## 4. Engines and the Quest 1

The Quest 1 is a Snapdragon 835 (ARMv8.0, Adreno 540, Android 10).
Everything is chosen to keep it working.

| Part | Choice | Why |
| --- | --- | --- |
| Engine | Godot 4.7.2, GDScript everywhere | compiles new scripts while the game runs, which makes live modules possible |
| Renderer | Compatibility (OpenGL ES 3) with multiview | the Quest 1's GPU handles it; both eyes in one pass |
| XR | OpenXR through godot_openxr_vendors 5.1.0 | has the Quest 1 export switch; `supportedDevices` stays `quest|quest2` (CI checks it) |
| Physics | **Jolt** (`3d/physics_engine="Jolt Physics"`, since PR #20) | faster and steadier; `physics_status` reports the engine (seen on the headset: Jolt) |
| Speech to text | whisper.cpp through godot-whisper, built into the APK | stays on the headset; built for plain armv8-a |
| Speech out | Android TTS (for example SherpaTTS), played inside the app | no extra library |

Rules that come out of this:

- Native code only for a measured hot spot, built for plain `armv8-a`
  (no dotprod, i8mm or SVE). The whisper crash came from a library built
  for a newer CPU.
- The Compatibility renderer has no compute shaders. Charts and similar
  are drawn from MultiMesh, ArrayMesh and Label3D. Heavy maths is done on
  the PC.
- Redraw only on change, keep pages small (the Library draws 12 small
  pictures at a time), and keep the frame rate at 72 Hz.
- Planned next: `perf.gd` (foveation, 72 physics ticks a second),
  `charts.gd`, `matrix.gd`, `shaders.gd`, then a first game.

## 5. How work is done

- **Three levels of "works", kept apart:** *headset* (seen working on the
  Quest 1), *PC* (tested headless with Godot 4.7.2), *untested*. A claim
  always says which. The project board's columns match them: Todo, In
  progress, Needs headset test, and Done (seen on the headset).
- **Small steps.** Each change is shown with its code and pushed only after
  the owner says "push". Each step is tested before the next one.
- **Root causes, not workarounds.** No skipped code paths and no fixed
  buffer sizes as a fix. Diagnostics log everything in one build rather
  than one probe per rebuild.
- **Our own code** rather than dependencies or UI add-ons. No unrequested
  extras.
- **Testing:** every live module is tested headless on a PC first (steps
  in PROJECT-STATE.md). Thumbsticks and anything that is only visible in
  VR can be checked only on the headset.
- **Two-way sync with the headset** ([WIRELESS-ADB.md](WIRELESS-ADB.md)):
  modules the in-app agent writes or changes on the headset are copied back
  into `live-modules/drafts/` with the date, never lost. On a conflict,
  the headset's copy is saved and then the PC's version wins. Drafts are
  reworked into proper modules before they leave `drafts/`.
