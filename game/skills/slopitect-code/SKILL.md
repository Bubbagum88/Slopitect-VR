---
name: slopitect-code
description: How to write a live module (new GDScript code) that loads into the running app after the person's Yes.
---

# Live modules

When the commands you have can't do something, you can write a module: a
GDScript file the app loads while it runs. Only do this when the person
wants a new feature; prefer existing commands and panels for everything else.

1. Write the file with `files_write`, path `modules/NAME.gd` (NAME is
   letters, digits and _). Then `code_load` with `name`.
2. The person sees the code and a Yes/No question in the headset. Say what
   the module does and why before you load it. Your tool waits for the
   answer; "the person said No" means don't retry without asking them.
3. If it doesn't compile, the error says which line. Fix the file and
   `code_load` again (a changed file needs a new Yes).
4. `code_list` shows each module, whether it's loaded and its last error;
   `code_unload` takes one out.

The shape of a module (Godot 4.7, GDScript, tabs for indents):

```gdscript
extends SlopitectModule

# What this module does, in a sentence or two.

func setup() -> String:
	# ctx has: server (the command server), world (where built things go),
	# camera (the headset), left and right (the controllers), modules.
	register("NAME_do", _do, "what it does: its fields")
	return ""  # or what went wrong; then the module isn't loaded


func _do(request: Dictionary) -> Dictionary:
	# Check every field you use; reply {"ok": false, "error": "..."} if bad.
	return {"ok": true}
```

- Name commands after the module (`NAME_...`). Once the module is loaded,
  its commands are your tools too (except any ending in `_config`, which
  are the person's). They appear in your tools the next time the person
  asks you something.
- Run other commands with `ctx["server"].run({"cmd": "spawn", ...})`.
- Put nodes you make under the module itself (`add_child`) or
  `ctx["world"]`; anything you hang on a controller must be freed in
  `_exit_tree()`, so unloading leaves nothing behind.
- Keep work per frame small: the Quest 1 must hold 72 frames a second.
- Never read or send the app's settings or keys, and don't reach outside
  the Slopitect folder without going through the files_* commands.
