# VR UI: how the windows work

Written 2026-10-29. Covers `live-modules/ui.gd` (every window) and what it
asks of other modules. Tested headless on a PC with Godot 4.7.2 (60 checks,
opengl3 pictures); **not yet seen on the headset**. Hover, haptics, follow
panels and readable text sizes can only be judged in the headset.

## The pieces

```
controls.gd ── actions ("point", "grab_right", toggles) ──► ui.gd ──► ui_* commands
     ▲                                                     │  ▲
     └──────────── pulse(hand, strength, seconds) ◄────────┘  │
                                                              │
  other modules: menu_info()  ──► a tile on the Menu          │
                 format(value) ──► lays out a live text       │
                 ui.theme()    ◄── colours and text sizes ────┘
                 ui.set_text() ──► change one text at once
```

- **One window system.** Every window is a panel in `ui.gd`: data (a
  dictionary) that you, the agent or a module change with the `ui_*`
  commands. Panels are drawn with plain quads and `Label3D`, no
  SubViewport, so nothing is redrawn while nothing changes. That matters
  on the Quest 1 (Snapdragon 835).
- **Input only through controls.gd.** ui.gd takes "point" (right trigger),
  "grab_right" (right grip) and any action a panel uses as its toggle.
  The Yes/No window still reads the trigger itself, and while it asks, the
  pointer does nothing on panels (`pointer_blocked`).
- **Modules join by having a function**, the way tools join with
  `tool_info()`; they leave cleanly when unloaded.

## What a panel can have

| Field | What it does |
| --- | --- |
| `place` | `front` (opens in front of you), `follow` (opens in front, then catches up when you turn more than 35° away or walk 0.5 m), `wrist` (left wrist), `world` (fixed). A panel you carry becomes `world` where you let go |
| `size`, `color` | The background. No colour means the theme's `panel` |
| `chrome` | A title bar above the background: the title, a close x, and a handle. Pull the trigger on the bar and move the controller to carry the window. Needs `size` |
| `pages`, `page` | Tabs under the title (up to 8). An element with `page` shows only on that tab. Needs `chrome` |
| `apps` | Show the launcher's tiles at the top (the Menu has it) |
| `menu` | A label: this panel gets a tile on the Menu that shows and hides it |
| `toggle` | An action from controls that shows and hides it |
| `layout` | `free` (each element at its `at`) or `grid` (buttons in rows) |

## Elements

`text`, `button`, `input`, `box` as before, and two new ones:

- **toggle**: `label`, `on`, `action`. A press runs the action with
  `"{on}"` replaced by what it's switching to, and switches only if the
  command worked. A light on the right shows ON or OFF.
- **slider**: `label`, `min`, `max`, `step`, `value`, `action`. Hold the
  trigger on it and move along it; the action runs once when you let go,
  with `"{value}"` replaced by the value. `ui_slide` sets it by command.

A colour can be a theme name (`accent`, `danger`, `ok`, `muted`, ...) as
well as `#rrggbb`; leave it out to get the type's theme colour. Elements
saved with the old fixed colours follow the theme too.

A text `source` can name a `format` module: if that module is loaded and
has `format(value, source)`, its String (or list of lines) is shown. The
chat log uses `"format": "aimsg"`; without aimsg it shows the plain events.

## Feedback

Best practice for pointing in VR is to always show what the pointer will
do before you press:

- **Laser** from the right controller, only while a panel is out, ending
  where it touches.
- **Cursor dot** where it touches a panel.
- **Hover**: a button, toggle, slider, tile, tab or title bar lights up and
  comes 4 mm towards you, with a very light tick on the controller.
- **Press**: a short flash and a firmer tick. Failures show in red under the
  panel for 5 seconds.
- **Typing**: the input box being typed into is lit.

## Plug-in points for other modules

| Function | Who has it | What it does |
| --- | --- | --- |
| `menu_info()` | any module | `{"id", "label", "order" (lower first, 100 default), "panel": id_panel}` or `{..., "action": a command}`: a tile on the Menu. A tile closes the Menu after opening its window |
| `format(value, source)` | any module | Lays out a text source's value (aimsg for the chat log) |
| `ui.theme()` | ui.gd | The theme: colours as `Color`, `font_title` / `font_body` / `font_small` as text sizes |
| `ui.set_text(id_panel, id_element, text)` | ui.gd | Changes one text element now, without redrawing or saving (a terminal's screen). The text isn't saved, since it can be anything |
| `ui.press(id_panel, id_element)` | ui.gd | Presses a button or toggle |
| `controls.pulse(hand, strength, seconds)` | controls.gd | A buzz on a controller |

A tile's or button's command can't be a `*_config` command (settings are PC
only), `ui_press` or `ui_slide`.

## The theme

Read it with `ui_theme_status`; change it from the PC only:

```
.\slopi.ps1 '{"cmd":"ui_config","theme":{"accent":"#ff8800","font_body":30}}'
.\slopi.ps1 '{"cmd":"ui_config","reset":true}'
```

Kept in `user://ui_config.json`. Every panel is drawn again when it changes.

## Sizes that read well on the Quest 1

These are the defaults, picked for a panel about 0.6 m away:

- Text: 24 is the smallest comfortable size (`font_small`), 28 for body
  text, 30 for titles. At 0.0006 m per pixel, 24 is about 1.4 cm tall.
- Buttons at least 5 × 5 cm at arm's length (the keyboard's keys); 14 × 7 cm
  for menu buttons and launcher tiles.
- Panels open 0.55 to 0.6 m away and 0.25 to 0.35 m below your eyes, tipped
  back to face you, so you look slightly down (the comfortable range) and
  your arm can rest.
- Nothing is stuck to your face: `follow` panels lag and ease, never snap.
- Dark backgrounds with light text: less glare and less of the Quest 1's
  screen-door look than white panels.

## What was decided, and why

- **Not SubViewport panels (the vrui draft) for every window.** A
  SubViewport per panel costs a render target and a redraw; vrui drew every
  frame. Quads and Label3D cost nothing while still. vrui stays in
  `drafts/` as a possible way to draw rich widgets later, if a need comes up
  that quads can't meet.
- **The launcher lives in ui.gd**, not a separate menu.gd as
  MODULE-FRAMEWORK.md first planned: the Menu bar was already ui.gd's, and
  one module avoids two panels fighting over the left menu button.
- **The chat panel's element ids didn't change**, so aimsg and anything
  else that finds them keeps working.

## Open

- Headset test: text sizes, hover lift, haptic strength, follow speed.
- Rounded corners would need a shader; left out until the headset test says
  the panels need them.
- The wrist panel has no title bar (it would be bigger than the buttons).
