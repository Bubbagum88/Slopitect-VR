# Draft live modules

These are Bubbagum88's new modules as they were handed in on 2026-10-29,
kept here unchanged so they have a history. They have **not** been tidied
or tested yet, and they are not in the main `live-modules/` list. Each one
will move up into `live-modules/` once it has been reworked to the module
rules in [docs/MODULE-FRAMEWORK.md](../../docs/MODULE-FRAMEWORK.md).

Do not `code_load` them on the headset as they are:

| Draft | What it does | Why it waits |
| --- | --- | --- |
| `aimsg.gd` | Formats the chat log; drives the avatar from the agent's state | Fights `avatar.gd` over the avatar; writes a debug file; guesses status fields |
| `controller.gd` | Binds buttons to commands or panel toggles; attaches vrui panels to a hand | Same job as `controls.gd` (a press can fire twice); reaches into other modules' private fields |
| `hands.gd` | Drawn hands with nails that curl with grip and trigger | Reads the controllers directly; colours not saved |
| `jelly.gd` | Squash and stretch on the avatar | Guesses where the avatar's body is; settings not saved |
| `stick_move.gd` | Walking on the right stick | `move.gd` already walks, and the right stick turns |
| `vrui.gd` | Real Godot buttons and sliders on a panel (idea from MT-ZD/Godot-3D-VR-UI, MIT) | Reads the trigger itself, so it can be pressed while a Yes/No question is open; redraws every frame |
| `web.gd` | Downloads any URL into `assets/` | No list of allowed sites |
| `world.gd` | Named worlds, plus Worlds, Files and Modules windows | Its own save format leaves out models and switches; duplicates `save.gd`/`projects.gd` |

The full review, and what happens to each, is in
[docs/MODULE-FRAMEWORK.md](../../docs/MODULE-FRAMEWORK.md).
