---
name: slopitect-ui
description: How to change the app's windows (menu bar, wrist panel, chat window) and build new ones, live.
---

# Windows in Slopitect

Every window is a panel: data you change with the `ui_*` commands. The
defaults are `bar` (opens in front with the left menu button), `wrist` (on
the left wrist) and `chat` (your chat window, opens with Y).

- Look first: `ui_list` lists the panels; `ui_get` with `id_panel` gives one
  panel's full data, including every element and what's typed in its boxes.
- `ui_add` makes a panel. Fields: `id_panel`, `title`, `place` (`front`:
  opens in front of the person at `distance` and `height` metres; `wrist`;
  `world`: fixed at `position` and `rotation`), `size` [w, h] for a
  background and its `color`, `visible`, `toggle` (an action, from the
  controls module, that shows and hides it: by default left_menu (≡),
  left_y (Y), right_a (A), right_b (B); `controls_status` lists them), `layout`
  (`free`, or `grid` to lay buttons in rows of `columns`, each `cell` [w, h]
  big) and `elements`.
- Elements, each with a unique `id` and `at` [x, y] in metres from the
  panel's centre (x right, y up). `at` is an element's centre; for text it's
  the top-centre of the block, which wraps at `width`:
  - `text`: `text`, `width`, `font_size` (32 reads well), `color`, `mono`,
    `align`. A `source` shows a live value instead:
    {"cmd": "agent_status", "field": "events", "last": 5}. Only read-only
    commands (list, modules, or ones ending in _status or _list).
  - `button`: `label`, `size` [w, h], `action` (any command), `color`.
    In an action, "in_front" as a position is 1 m in front of the person
    when pressed, and "{input:ID}" is what's typed in that panel's input
    box. `clear_input` empties a box after a successful press.
  - `input`: a box the person types into with a keyboard's `ui_type` and
    `ui_key` buttons; `width`, `font_size`, `prompt`, `max_length`.
  - `box`: a plain coloured rectangle, `size` and `color`.
- Change things with `ui_update` (any panel fields), `ui_element_add`,
  `ui_element_update` (fields; null removes an optional one) and
  `ui_element_remove`. `ui_show` shows or hides a panel; `ui_remove`
  deletes it; `ui_reset` puts the defaults back.
- Keep text short and big enough to read in the headset: about 0.6 m away,
  font_size 26 is the smallest that's comfortable.
- A panel the person moves with the grip becomes a `world` panel where they
  left it. Don't move it back unless asked.
- Don't remove or break the `chat` panel's input, Send or STOP unless the
  person asks: it's how they talk to you.
