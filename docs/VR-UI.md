# VR UI: how the windows work

Written 2026-10-29, updated the same day when ui.gd took over the vrui
draft's look and was renamed `live-modules/vrui.gd`, the base for every
window. Covers vrui.gd and what it asks of other modules.

**The rename.** The module is now called `vrui`; modules find it with
`ctx["modules"].module("vrui")`, falling back to `module("ui")` for the
older file. Everything else kept its name: the `ui_*` commands, saved
panels in `user://ui.json`, the theme in `ui_config`. On the headset,
unload the old `ui` module and the old vrui draft, then load vrui.gd; your
panels come back from ui.json. The APK's Yes/No window still blocks the
pointer: vrui asks the confirm module itself, since the APK only tells a
module called "ui". Tested headless on a PC with Godot 4.7.2 (about 90 checks,
opengl3 pictures, and worlds.gd's window opening on it); **not yet seen on
the headset**. Hover, haptics, the hand window, follow panels, text sizes
and how fast a SubViewport panel draws on the Quest 1 can only be judged in
the headset.

## The pieces

```
controls.gd ── actions ("point", "grab_right", toggles) ──► vrui.gd ──► ui_* commands
     ▲                                                     │  ▲
     └──────────── pulse(hand, strength, seconds) ◄────────┘  │
                                                              │
  other modules: menu_info()  ──► a tile on the Menu          │
                 format(value) ──► lays out a live text       │
                 ui.theme()    ◄── colours and text sizes ────┘
                 ui.set_text() ──► change one text at once
```

- **One window system.** Every window is a panel in `vrui.gd`: data (a
  dictionary) that you, the agent or a module change with the `ui_*`
  commands. Each panel is drawn the way the vrui draft drew its windows:
  real 2D panels, rounded buttons and wrapped text in a SubViewport, shown
  on a quad. The picture is drawn again only when something on it changes
  (hover, press, a new text), never every frame, which matters on the
  Quest 1 (Snapdragon 835). The vrui draft is gone; its look lives here.
- **Input only through controls.gd.** vrui.gd takes "point" (right trigger),
  "grab_right" (right grip) and any action a panel uses as its toggle.
  The Yes/No window still reads the trigger itself, and while it asks, the
  pointer does nothing on panels (`pointer_blocked`).
- **Modules join by having a function**, the way tools join with
  `tool_info()`; they leave cleanly when unloaded.

## What a panel can have

| Field | What it does |
| --- | --- |
| `place` | `front` (opens in front of you), `follow` (opens in front, then catches up when you turn more than 35° away or walk 0.5 m), `wrist` (left wrist), `hand` (held by a controller, see below), `world` (fixed). A panel you carry becomes `world` where you let go |
| `keep_place`, `home` | `keep_place` false (the default): the window opens in front of you each time, also after a restart, even if you carried it somewhere (a `hand` panel goes back on its hand; `home` remembers where it first opened). true: it stays where you put it. The **Pin** button in the title bar switches it. A `hand` panel carried back within 12 cm of its spot shows a faint outline there and snaps on when you let go, pinned or not |
| `hand`, `scale` | For `hand`: which controller holds it (`left`, the default, or `right`) and its size (0.5 by default; any panel can have a `scale` from 0.1 to 3) |
| `size`, `color` | The area `at` elements sit in, and the background. No colour means the theme's `panel`. The window grows to fit what's in it |
| `chrome` | A title bar: the title, a close x, a back arrow when another panel's button opened it, and a handle. Pull the trigger on the bar and move the controller to carry the window |
| `pages`, `page` | Tabs under the title (up to 8). An element with `page` shows only on that tab. Needs `chrome` |
| `apps` | Show the launcher's tiles at the top (the Menu has it) |
| `menu` | A label: this panel gets a tile on the Menu that shows and hides it |
| `toggle` | An action from controls that shows and hides it |
| `focusable` | true (the default): pulling the trigger on the window, or opening it, gives it the focus (see Feedback). false: it never takes it (the keyboard's window) |
| `layout` | `free` (each element at its `at`, as before), `grid` (buttons in rows of `columns`, each `cell` big), or `column` / `row`: the elements flow down or across in order, with no `at` |

## Elements

`text`, `button`, `input`, `box` as before, and these:

- **toggle**: `label`, `on`, `action`. A press runs the action with
  `"{on}"` replaced by what it's switching to, and switches only if the
  command worked. A light on the right shows ON or OFF.
- **slider**: `label`, `min`, `max`, `step`, `value`, `action`. Hold the
  trigger on it and move along it; the action runs once when you let go,
  with `"{value}"` replaced by the value. `ui_slide` sets it by command.

- **row, column, grid**: containers. `children` is a list of elements laid
  out across, down, or in `columns`, with `gap` metres between them. They
  can sit inside each other (up to 6 deep), and every id must still be
  unique in the panel. `ui_element_add` takes a `parent` to add into one.
  Any element in a flow can have `grow: true` to take the spare room.
- **text `scroll`**: the text wraps at the element's real width and keeps
  its newest lines in view, like a terminal. `height` (metres) sets how
  tall the box is. `ui_scroll` with `lines` moves it back (0 is the
  newest); a module can call `ui.scroll_text(id_panel, id_element, lines)`.
- **button `image`**: a picture file (.png, .jpg or .webp) in the
  Slopitect folder or `user://`, shown over the label, which gets small:
  a tile in a browser (library.gd's thumbnails). Pictures are shrunk to
  160 px and kept loaded until their file changes; until the file is there
  the space stays empty. A module that just wrote one calls
  `ui.reload_image(path)` to show it without rebuilding the window.
- **button `open`**: names another panel. A press hides this one and shows
  that one in the same place, with a back arrow in its title bar that comes
  back (`ui_back` does the same). A button can have `open`, an `action`, or
  both. This is how menus inside menus are made: each menu is a panel.

A colour can be a theme name (`accent`, `danger`, `ok`, `muted`, ...) as
well as `#rrggbb`; leave it out to get the type's theme colour. Elements
saved with the old fixed colours follow the theme too.

A text `source` can name a `format` module: if that module is loaded and
has `format(value, source)`, its String (or list of lines) is shown. The
chat log uses `"format": "aimsg"`; without aimsg it shows the plain events.

## The hand window

`"place": "hand"` hangs a panel just above a controller, tipped towards
you, like the vrui draft's hand window. `position` and `rotation` move it on
the controller (defaults `[0, 0.12, -0.02]` and `[-35, 0, 0]`). Point at it
with the other hand. Pull it off with the grip or its title bar and it
stays in the world where you let go.

```
{"cmd":"ui_add","id_panel":"tools_hand","title":"Tools","place":"hand","chrome":true,
 "layout":"column","elements":[
   {"type":"button","id":"grab","label":"Grab","action":{"cmd":"modules"}},
   {"type":"button","id":"more","label":"More","open":"tools_more"}]}
```

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
- **Focus**: the window you last pulled the trigger on or opened has the
  focus, and its edge is lit in the accent colour; its input box (if any)
  is the one typed into. When it closes, the window before it gets the
  focus back. A keyboard module sends its text to the focused window.

## Plug-in points for other modules

| Function | Who has it | What it does |
| --- | --- | --- |
| `menu_info()` | any module | `{"id", "label", "order" (lower first, 100 default), "panel": id_panel}` or `{..., "action": a command}`: a tile on the Menu. A tile closes the Menu after opening its window |
| `format(value, source)` | any module | Lays out a text source's value (aimsg for the chat log) |
| `ui.theme()` | vrui.gd | The theme: colours as `Color`, `font_title` / `font_body` / `font_small` as text sizes |
| `ui.set_text(id_panel, id_element, text)` | vrui.gd | Changes one text element now, without rebuilding the panel or saving (a terminal's screen). The text isn't saved, since it can be anything. A `scroll` text keeps its newest lines in view |
| `ui.scroll_text(id_panel, id_element, lines)` | vrui.gd | Scrolls a `scroll` text back by `lines` from the newest (0 = newest) |
| `ui.focused_window()`, `ui.focus()` | vrui.gd | The window with the focus (`""` if none), and the input box typed into (`"panel/element"` or `""`) |
| `ui.press(id_panel, id_element)` | vrui.gd | Presses a button or toggle |
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

- Text: a panel's picture has 1250 pixels per metre (about what the
  Quest 1 shows at 0.6 m). `font_small` is 28, `font_body` 36, `font_title`
  40 there, so body text is about 2.9 cm tall at full scale. A hand window
  is drawn at half scale, so its text is half that and is meant to be
  brought close.
- Buttons at least 5 × 5 cm at arm's length (the keyboard's keys); 14 × 7 cm
  for menu buttons and launcher tiles.
- Panels open 0.55 to 0.6 m away and 0.25 to 0.35 m below your eyes, tipped
  back to face you, so you look slightly down (the comfortable range) and
  your arm can rest.
- Nothing is stuck to your face: `follow` panels lag and ease, never snap.
- Dark backgrounds with light text: less glare and less of the Quest 1's
  screen-door look than white panels.

## What was decided, and why

- **SubViewport panels, drawn only on change.** isaac liked the vrui
  draft's look (and its hand window) better than the first quads-and-Label3D
  version, so vrui.gd now draws that way. The cost vrui had came from drawing
  every frame; vrui.gd draws a panel's picture once and again only when it
  changes, and works out pointing itself (Godot's GUI input is off), so
  input still comes only through controls.gd and stops while a Yes/No
  question is up.
- **Text wrapping lives in vrui.gd**, not a separate module: only the window
  knows its real width, so it wraps there, and the terminal and chat get it
  through `set_text` and `scroll`.
- **The launcher lives in vrui.gd**, not a separate menu.gd as
  MODULE-FRAMEWORK.md first planned: the Menu bar was already vrui.gd's, and
  one module avoids two panels fighting over the left menu button.
- **The chat panel's element ids didn't change**, so aimsg and anything
  else that finds them keeps working.

## Open

- Headset test: text sizes, hover lift, haptic strength, follow speed, the
  hand window's place on the controller, and frame time with several
  panels changing at once (a busy terminal redraws its panel on each new
  line).
- The wrist panel has no title bar (it would be bigger than the buttons).
