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
5. Errors a loaded module hits while it runs (a null, a bad index, its own
   `push_error`) come to you after your next step as "[Errors from live
   modules ...]", with the file and line. `errors_recent` (optional
   `module`) shows them all. Fix the file and `code_load` it again.

The shape of a module (Godot 4.7, GDScript, tabs for indents):

```gdscript
extends SlopitectModule

# What this module does, in a sentence or two.

var _lib: SlopitectModule  # lib.gd, the shared helpers; null until it's there


func setup() -> String:
	# ctx has: server (the command server), world (where built things go),
	# camera (the headset), left and right (the controllers), modules.
	register("NAME_do", _do, "what it does: its fields")
	set_process(false)  # idle until something needs it
	return ""  # or what went wrong; then the module isn't loaded


# Called once lib and this module are both loaded (either order), and with
# null when lib goes. Anything that needs another module goes here.
func lib_ready(lib) -> void:
	_lib = lib
	if lib == null:
		return
	lib.follow(self, "projects", "project_changed", _on_project)
	lib.watch(self, "avatar", _avatar_here, _avatar_gone)


func _exit_tree() -> void:
	pass  # free anything made outside this node; put back what you changed


func _do(request: Dictionary) -> Dictionary:
	# Check every field you use; reply {"ok": false, "error": "..."} if bad.
	return {"ok": true}
```

The rules every module follows:

1. Settings: declare them in your own `settings_info()` (the settings
   module's contract); the Settings window shows them. Labels 40
   characters or less.
2. A tool: `tool_info()`, `tool_selected(on)`, `tool_trigger(down)`; the
   tools module shows it and keeps its undo (`push_undo`).
3. Windows and buttons only through the vrui module (`menu_info()`,
   `hand_info()`, `ui_*` commands). Never draw your own panels.
4. Signals, not polling: `lib.follow(self, module, signal, method)` and
   `lib.watch(self, module, on_load, on_unload)`; lib's `module_loaded`,
   `module_unloaded`, `info_changed` (call `lib.touch(self)` when your
   *_info() changes). Never look up another module or its info every frame.
5. Shared helpers are in lib, never copied: `lib.world_node(name)`,
   `lib.thing(name)`, `lib.things()`, `lib.world_box(node)`, `lib.home()`
   (the Slopitect folder), `lib.read_json(path)`, `lib.write_json(path,
   data)`, `lib.module(name)`. A helper two modules need goes into lib.
6. No hard dependencies: when a module you use isn't loaded, keep working
   or quietly turn that feature off (say so in a command's reply).
7. Clean unload: `_exit_tree()` frees what you made outside your own node
   and puts back what you changed. Connect methods, not lambdas.
8. Idle means off: `set_process(false)` while your tool or window isn't in
   use or there is nothing to animate; turn it on from the event.
9. One owner per piece of data: save owns the world file, tools the undo
   history, projects the current project, inspect the selection. Use their
   commands and signals, never their files or private variables.
10. Write a test, `modules/zz_NAME.gd`: on load it runs your commands,
    prints PASS/FAIL lines and a RESULT line. Load it after your edit to
    check it, then `code_unload` it.

More:

- Name commands after the module (`NAME_...`). Once the module is loaded,
  its commands are your tools too (except any ending in `_config`, which
  are the person's). They appear in your tools the next time the person
  asks you something.
- Run other commands with `ctx["server"].run({"cmd": "spawn", ...})`.
- Put nodes you make under the module itself (`add_child`) or
  `ctx["world"]`; anything you hang on a controller must be freed in
  `_exit_tree()`, so unloading leaves nothing behind.
- Buttons and thumbsticks come from the controls module, never from the
  controllers directly: add `func on_action(action: String, down: bool)
  -> bool` and return true for the actions you take (then you alone get
  the release). `controls_status` lists the actions; the ui module is
  asked first, so pointing at a panel, the trigger and grip are its. Read
  a thumbstick with `ctx["modules"].module("controls").stick("walk")`.
- Keep work per frame small: the Quest 1 must hold 72 frames a second.
- Never read or send the app's settings or keys, and don't reach outside
  the Slopitect folder without going through the files_* commands.
