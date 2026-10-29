# Draft live modules

These are Bubbagum88's new modules as they were handed in on 2026-10-29,
kept here unchanged so they have a history. They have **not** been tidied
or tested yet, and they are not in the main `live-modules/` list. Each one
will move up into `live-modules/` once it has been reworked to the module
rules in [docs/MODULE-FRAMEWORK.md](../../docs/MODULE-FRAMEWORK.md).

All of them have been reworked or dropped (still in git history): `hands.gd` moved up into `live-modules/`;
`aimsg.gd` became `live-modules/aimsg.gd` (the chat formatting only; the
avatar already shows the agent's state); `web.gd` became
`live-modules/net.gd` (only hosts allowed on the PC); `jelly.gd` became
`live-modules/jelly.gd` (uses the live avatar's `body()`); `world.gd` became `live-modules/worlds.gd` (its windows as tabs, on top of `save.gd` and `projects.gd`, without its own save format);
`controller.gd`'s "button runs a command" and "button shows a window" are binding kinds in
`controls_config`, and right-stick walking is
`{"sticks": {"right": "walk", "left": "turn"}}` there, so `controller.gd` and
`stick_move.gd` are gone. `textures.gd` moved up into `live-modules/` (textures now move with their shape). `vrui.gd`'s look (rounded panels, real text and
buttons, the hand window) is now how `live-modules/vrui.gd` draws every
window, taking "point" from controls and drawing only on a change; panel
attaching from `controller.gd` is vrui.gd's `hand` place.

The full review, and what happens to each, is in
[docs/MODULE-FRAMEWORK.md](../../docs/MODULE-FRAMEWORK.md).
