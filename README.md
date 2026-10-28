# Slopitect-VR

A VR sandbox for the Oculus Quest 1 that an AI (Claude) can change while
you're standing in it. You ask for something, Claude builds it into the
running world: objects, behaviour, things pulled in from the internet. No
rebuild, no restart. You and the AI build the world together.

> **Status: step 3 of 9.** Step 2, an empty VR room (a floor, a sky, one
> cube and your two controllers), runs on a Quest 1 at 72 Hz. Step 3 adds a
> command server you can talk to from your PC; it's tested on a PC with
> Godot but not yet on the headset. Nothing after step 3 exists yet.

## Why the Quest 1

The Quest 1 (Snapdragon 835, Adreno 540, Android 10) is old and Meta no
longer supports it, so most new VR apps don't start on it. Slopitect is
built for it on purpose: it uses the OpenGL ES renderer and settings that
the Quest 1 is known to handle. It should also run on a Quest 2, but that
isn't a goal or tested.

## How it works

Built with [Godot 4](https://godotengine.org) (4.7.2), its OpenGL ES
"Compatibility" renderer, and OpenXR through the
[Godot OpenXR Vendors](https://github.com/GodotVR/godot_openxr_vendors)
plugin (5.1.0), which has a Quest 1 export switch.

The plan (from step 3 on): the app runs a small command server. Claude
sends it commands such as "spawn a cube here", "make it red", or "run this
script", and the world changes on the spot. Godot can compile new scripts
while the game runs, which is what makes live changes possible.

```
You (talking)  ->  Claude on your PC  ->  adb / Wi-Fi  ->  Slopitect on the Quest
                                                           (command server -> world)
```

## Roadmap

Each step is small and gets tested on the headset before the next one.

- [x] 1. Pick an engine (Godot 4, OpenGL ES)
- [x] 2. Empty VR room that starts on the Quest 1 *(tested on a Quest 1: 72 Hz, 34 MB)*
- [ ] 3. Command server: spawn, move, colour, delete and list objects from the PC *(built, waiting on a headset test)*
- [ ] 4. Claude on the PC drives it through those commands (an MCP server)
- [ ] 5. Saves and backups: the world is saved as JSON before every change, with undo; backups go to a GitHub repo, so every version has a history
- [ ] 6. Claude can send scripts, so objects can have behaviour (behind an on/off switch)
- [ ] 7. Free assets: Poly Haven (CC0, through its API) first; Kenney, Quaternius and Poly Pizza as backups. Each asset's source and licence is recorded, and any that need credit are credited
- [ ] 8. Talk to Claude from inside the headset
- [ ] 9. Upgrade while you play: new menus, tools and features loaded into the running app (scripts and Godot resource packs), with a new APK only for engine or permission changes

## Install on a Quest 1

You need developer mode on and `adb` on your PC.

1. Open the latest successful run under the repo's **Actions** tab
   ("Quest 1 APK") and download the `slopitect-quest1-debug` artifact. Unzip it.
2. Install it:
   ```
   .\adb install -r slopitect-quest1-debug.apk
   ```
3. On the headset, open **Apps > Unknown Sources > Slopitect**.

## Reading the log

Every line the app writes starts with `Slopitect:`. It logs the GPU, the
OpenXR runtime, the per-eye resolution and refresh rate at start, then the
frame rate, memory and controller tracking every 5 seconds.

```
.\adb logcat -s godot
```

## Talking to the app from your PC

The app listens on port 7777 on the headset itself (not on your Wi-Fi), so
you reach it through adb. Copy [`tools/slopi.ps1`](tools/slopi.ps1) into
your platform-tools folder, start Slopitect on the headset, then in
PowerShell in that folder:

```
Set-ExecutionPolicy -Scope Process Bypass
.\adb forward tcp:7777 tcp:7777
.\slopi.ps1 '{"cmd":"spawn","shape":"sphere","position":[0,1.5,-1],"color":"red"}'
```

The first line lets this PowerShell window run the script; the second
connects your PC's port 7777 to the app (again after each reconnect).

| Command | Fields | Example |
| --- | --- | --- |
| `ping` | | `{"cmd":"ping"}` |
| `help` | | `{"cmd":"help"}` |
| `list` | | `{"cmd":"list"}` |
| `spawn` | `shape` (box, sphere, cylinder, capsule), optional `name`, `position`, `rotation`, `scale`, `color` | `{"cmd":"spawn","shape":"box","name":"table","position":[1,0.4,-1.5],"scale":[1.2,0.8,0.6],"color":"#8b5a2b"}` |
| `move` | `name`, and any of `position`, `rotation`, `scale` | `{"cmd":"move","name":"table","rotation":[0,45,0]}` |
| `color` | `name`, `color` | `{"cmd":"color","name":"table","color":"blue"}` |
| `delete` | `name` | `{"cmd":"delete","name":"table"}` |

Positions are in metres from the middle of your play area (y is up, -z is
forward); rotations are in degrees; colours are `#rrggbb` or names like
`red`. Every reply has `"ok"`, and a failed one says exactly what was wrong
in `"error"`, without changing anything. Every command is also logged
(`Slopitect cmd:` in `.\adb logcat -s godot`).

## Building

GitHub Actions builds the APK on every push
([`.github/workflows/quest1-apk.yml`](.github/workflows/quest1-apk.yml)). It
downloads pinned versions of Godot, its export templates and the OpenXR
plugin, checks each file's SHA-512, exports a debug APK, and then checks the
APK itself: the build fails unless `com.oculus.supportedDevices` is exactly
`quest|quest2` (naming a newer headset makes the Quest 1 abort at start).

To build on your own PC instead: install the Godot OpenXR Vendors plugin
5.1.0 into `game/addons/`, open `game/` in Godot 4.7.2, install the Android
build template, and export the "Quest 1" preset. (Godot 4.7.2 crashes on
exit the first time it imports a project whose plugin was just added; the
import itself is fine, and the next start is clean. CI avoids it by
registering the plugin first.)

## Repository layout

| Path | What it is |
| --- | --- |
| `game/project.godot` | Project settings: OpenGL ES renderer, OpenXR on |
| `game/main.tscn` | The room: floor, sky, sun, cube, player and controllers |
| `game/main.gd` | Starts OpenXR and logs everything about the start-up |
| `game/command_server.gd` | The command server (port 7777, JSON lines) |
| `tools/slopi.ps1` | Sends one command from your PC and prints the reply |
| `ci/debug.keystore` | Debug signing key, so each build installs over the last |
| `game/export_presets.cfg` | The "Quest 1" Android export (Quest 1 and 2 only) |
| `.github/workflows/quest1-apk.yml` | Builds and checks the APK |

## Notes

- APKs from before step 3 were signed with a throwaway key: uninstall that
  one first (`.\adb uninstall io.github.bubbagum88.slopitect`). Later
  builds all use `ci/debug.keystore` and install over each other. It's a
  debug key, so anyone with this repo can sign an APK with it.
- The command server has no password. It only listens on the headset's
  loopback address, so only adb (or an app on the headset) can reach it.

## Credits

- [Godot Engine](https://godotengine.org), MIT licence
- [Godot OpenXR Vendors](https://github.com/GodotVR/godot_openxr_vendors), MIT licence
- Made by Bubbagum88 with Claude

## Licence

MIT, see [LICENSE](LICENSE).
