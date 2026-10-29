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
| Menus by plug-in | `menu_info()` returns a window's name and the panel it opens (or a command); the Menu shows a tile for each | Every module building its own way into its windows | ui.gd (live), see [VR-UI.md](VR-UI.md) |
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

1. Keep the repo's paths.gd and tools.gd; drop stick_move.gd.
2. controls.gd: add `value(hand, name)` for grip and trigger, and "run a
   command" as a binding kind. Then drop controller.gd.
3. hands.gd: read through controls, save colours.
4. aimsg.gd: chat formatting only, real fields, no debug file.
5. vrui.gd: take "point" from controls, respect the Yes/No window, redraw
   only on change, save panels, take over panel attaching.
6. world.gd: keep the windows, on top of save and projects.
7. web.gd: fold into a net helper with an allowed-sites list.

Needs the next APK:

- A settings helper in module.gd, so every `NAME_config` works the same way
  and is PC only.
- Signals from agent.gd (reply, busy, error), so modules stop polling.
- The INFO header that code.gd reads, so a module's needs load first.
- avatar.gd's `body()` accessor.

Until those land, the live modules use small stand-ins, marked as such in
the code.

Open decisions (the owner's):

- Drop stick_move, controller and world's save format in favour of move,
  controls and save? (Recommended: yes.)
- Should vrui become how all panels are drawn, or stay a separate kind of
  window? (Leaning: try it as ui's renderer once it is cheap enough on the
  Quest 1.)
- Which sites may web downloads come from? assets.gd's list is the start.
