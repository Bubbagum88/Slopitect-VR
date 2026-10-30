# Module tests

Each zz_NAME.gd is a headless test: it runs a module's commands, prints PASS / FAIL lines and a RESULT line, then quits. On a PC with Godot 4.7.2:

```
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 live-modules/tests/run.sh MODULES... zz_NAME
```

The modules each test loads, in order (the order matters: some load lib last on purpose):

| Test | Run with |
| --- | --- |
| `zz_agent_settings.gd` | `agent_settings zz_agent_settings` |
| `zz_agent_tuning.gd` | `lib agent_tuning zz_agent_tuning` |
| `zz_aimsg.gd` | `lib aimsg zz_aimsg` |
| `zz_assets.gd` | `lib assets zz_assets` |
| `zz_avatar.gd` | `controls vrui tts avatar lib zz_avatar` |
| `zz_beatsaber_path.gd` | `lib beatsaber_path zz_beatsaber_path` |
| `zz_chat.gd` | `controls chat vrui lib zz_chat` |
| `zz_controls.gd` | `controls lib landscape zz_controls` |
| `zz_doors.gd` | `lib save projects tools doors zz_doors` |
| `zz_gaps.gd` | `lib controls vrui tools inspect shapes physics grab multi doors textures joints save projects prefabs zz_gaps` (FRESH=1 after an APK change: it checks objects.gd) |
| `zz_grab.gd` | `lib tools grab zz_grab` |
| `zz_hands.gd` | `hands lib controls zz_hands` |
| `zz_holster.gd` | `controls vrui tools pause avatar holster lib zz_holster` |
| `zz_inspect.gd` | `lib tools inspect zz_inspect` |
| `zz_jelly.gd` | `avatar jelly lib zz_jelly` |
| `zz_keyboard.gd` | `controls vrui chat terminal keyboard lib zz_keyboard` |
| `zz_landscape.gd` | `landscape lib tools zz_landscape` |
| `zz_lib.gd` | `lib zz_lib` |
| `zz_library.gd` | `controls vrui pause net=net_stub assets textures prefabs inspect lib library zz_library` |
| `zz_memory.gd` | `memory lib zz_memory` |
| `zz_memory_world.gd` | `save projects memory lib zz_memory_world` |
| `zz_menu.gd` | `controls vrui lib zz_menu` |
| `zz_multi.gd` | `lib save projects tools multi zz_multi` |
| `zz_net.gd` | `lib net zz_net` |
| `zz_paths.gd` | `paths lib landscape tools zz_paths` |
| `zz_perf.gd` | `lib perf zz_perf` |
| `zz_physics.gd` | `physics lib landscape zz_physics` |
| `zz_prefabs.gd` | `lib tools prefabs zz_prefabs` |
| `zz_projects.gd` | `save projects lib zz_projects` |
| `zz_settings.gd` | `settings controls vrui hands lib zz_settings` |
| `zz_sweet_potato.gd` | `lib assets tools sweet_potato zz_sweet_potato` |
| `zz_terminal.gd` | `controls vrui chat terminal lib zz_terminal` |
| `zz_textures.gd` | `lib save projects tools textures zz_textures` |
| `zz_tool_front.gd` | `controls vrui tools paths lib tool_front zz_tool_front` |
| `zz_undo.gd` | `lib controls vrui tools inspect shapes physics grab multi doors textures prefabs zz_undo` |
| `zz_voice.gd` | `controls vrui tts vtt lib pause zz_voice` |
| `zz_vrui.gd` | `controls vrui lib zz_vrui` |
| `zz_worlds.gd` | `lib controls vrui projects save worlds zz_worlds` |

`net_stub.gd` stands in for net.gd (a fake Poly Haven); load it as `net=net_stub`.
