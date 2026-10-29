---
name: slopitect-ui
description: How to change the app's windows (menu bar, wrist panel, chat window) and build new ones, live.
---

# Windows in Slopitect

Every window is a panel: data you change with the `ui_*` commands. The
defaults are `bar` (the Menu: opens in front with the left menu button and
has a tile for every window), `wrist` (on the left wrist) and `chat` (your
chat window, opens with Y).

- Look first: `ui_list` lists the panels; `ui_get` with `id_panel` gives one
  panel's full data, including every element and what's typed in its boxes.
- `ui_add` makes a panel. Fields: `id_panel`, `title`, `place` (`front`:
  opens in front of the person at `distance` and `height` metres; `follow`:
  the same, then catches up when they turn away; `wrist`; `hand`: held
  just above a controller, `hand` `left` or `right`, half size unless
  `scale` says otherwise; `world`: fixed at `position` and `rotation`),
  `size` [w, h] for the area `at` elements sit in and `color`, `visible`,
  `toggle` (an action, from the controls module, that shows and hides it: by default left_menu (≡), left_y (Y), right_a (A),
  right_b (B); `controls_status` lists them), `layout` (`free`; `grid`
  to lay buttons in rows of `columns`, each `cell` [w, h] big; or
  `column` / `row`, where elements flow in order and need no `at`) and
  `elements`. The window grows to fit what's in it.
- Make new windows look like the rest: `chrome: true` (a title bar with a
  close x; the person carries the window by it), and
  `menu: "Label"` to give it a tile on the Menu instead of a new button.
  `pages: ["Main", "More"]` adds tabs; give each element a `page`.
- Menus: prefer `layout: "column"` with buttons in order over working out
  `at` positions. Group with `row`, `column` and `grid` elements
  (`children`, `gap`, `columns` for a grid); `grow: true` takes the spare
  room. A button with `open: "other_panel"` opens that panel in its place
  with a back arrow (`ui_back`); each sub-menu is its own panel.
- Colours: leave them out (the theme picks), or use a theme name: `accent`
  (the main action), `danger` (stop, delete), `ok`, `muted`, `button`,
  `panel`. `ui_theme_status` lists them. Only the person changes the theme.
- Elements, each with a unique `id` and (in a `free` layout) `at` [x, y] in metres from the
  panel's centre (x right, y up). `at` is an element's centre; for text it's
  the top-centre of the block, which wraps at `width`:
  - `text`: `text`, `width`, `font_size` (36 reads well), `color`, `mono`,
    `align`; `scroll: true` with a `height` makes a box that keeps its
    newest lines in view (`ui_scroll` moves it back). A `source` shows a
    live value instead:
    {"cmd": "agent_status", "field": "events", "last": 5}. Only read-only
    commands (list, modules, or ones ending in _status or _list).
  - `button`: `label`, `size` [w, h], `action` (any command) and/or
    `open` (a panel to open in its place), `color`.
    In an action, "in_front" as a position is 1 m in front of the person
    when pressed, and "{input:ID}" is what's typed in that panel's input
    box. `clear_input` empties a box after a successful press.
  - `input`: a box the person types into with a keyboard's `ui_type` and
    `ui_key` buttons; `width`, `font_size`, `prompt`, `max_length`.
  - `box`: a plain coloured rectangle, `size` and `color`.
  - `toggle`: an on/off switch: `label`, `size`, `on`, `action` with
    `"{on}"` where true or false goes, for commands that take a true/false
    field. It switches only if the command worked.
  - `slider`: `label`, `size`, `min`, `max`, `step`, `value`, `action`
    with `"{value}"` where the number goes; runs once when the person lets
    go. `ui_slide` sets it.
- Change things with `ui_update` (any panel fields), `ui_element_add`,
  `ui_element_update` (fields; null removes an optional one) and
  `ui_element_remove`. `ui_show` shows or hides a panel; `ui_page` picks a
  tab; `ui_remove` deletes it; `ui_reset` puts the defaults back and wipes
  the person's own panels, so only when they ask for it.
- Keep text short and big enough to read in the headset: about 0.6 m away,
  font_size 28 is the smallest that's comfortable; buttons at least 5 cm.
- A panel the person moves with the grip becomes a `world` panel where they
  left it. Don't move it back unless asked.
- Don't remove or break the `chat` panel's input, Send or STOP unless the
  person asks: it's how they talk to you.
