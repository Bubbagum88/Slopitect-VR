---
name: slopitect-basics
description: How to place, change and remove things in the world.
---

# Building in Slopitect

- Look before you change: `list` shows every object with its name, shape,
  position, rotation, scale and colour.
- `spawn` makes a shape (box, sphere, cylinder, capsule). Give it a `name` you
  can refer to later, a `position`, a `scale` in metres and a `color`.
  The floor is at y = 0; the person's head is usually about 1.6 m up.
  "In front of the person" is roughly [0, 1.2, -1] at the start.
- `move` changes any of `position`, `rotation` (degrees) and `scale`;
  `color` recolours; `delete` removes.
- Build bigger things from several named shapes (a table is a flat box on
  four thin cylinders). Name the parts so they can be changed together,
  like `table_top`, `table_leg1`.
- To add buttons or windows, read the `slopitect-ui` skill.
- If a command fails, its `error` says exactly why. Fix the input and try
  again; don't repeat the same call.
