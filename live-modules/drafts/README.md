# Draft live modules

These are Bubbagum88's new modules as they were handed in on 2026-10-29,
kept here unchanged so they have a history. They have **not** been tidied
or tested yet, and they are not in the main `live-modules/` list. Each one
will move up into `live-modules/` once it has been reworked to the module
rules in [docs/MODULE-FRAMEWORK.md](../../docs/MODULE-FRAMEWORK.md).

Do not `code_load` them on the headset as they are:

| Draft | What it does | Why it waits |
| --- | --- | --- |
| `jelly.gd` | Squash and stretch on the avatar | Guesses where the avatar's body is; settings not saved |
| `vrui.gd` | Real Godot buttons and sliders on a panel (idea from MT-ZD/Godot-3D-VR-UI, MIT) | Reads the trigger itself, so it can be pressed while a Yes/No question is open; redraws every frame |
| `world.gd` | Named worlds, plus Worlds, Files and Modules windows | Its own save format leaves out models and switches; duplicates `save.gd`/`projects.gd` |

Already reworked or dropped: `hands.gd` moved up into `live-modules/`;
`aimsg.gd` became `live-modules/aimsg.gd` (the chat formatting only; the
avatar already shows the agent's state); `web.gd` became
`live-modules/net.gd` (only hosts allowed on the PC);
`controller.gd`'s "button runs a command" is now a binding kind in
`controls_config`, and right-stick walking is
`{"sticks": {"right": "walk", "left": "turn"}}` there, so `controller.gd` and
`stick_move.gd` are gone (still in git history). Panel attaching from
`controller.gd` waits for the vrui rework.

The full review, and what happens to each, is in
[docs/MODULE-FRAMEWORK.md](../../docs/MODULE-FRAMEWORK.md).
