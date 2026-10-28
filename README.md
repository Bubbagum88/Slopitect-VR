# Slopitect-VR

A VR sandbox for the Oculus Quest 1 that an AI (Claude) can change while
you're standing in it. You ask for something, Claude builds it into the
running world: objects, behaviour, things pulled in from the internet. No
rebuild, no restart. You and the AI build the world together.

> **Status: step 2 of 8, untested.** Right now it's an empty VR room (a floor,
> a sky, one cube and your two controllers). It has been checked on a PC
> (the project loads and the scripts run), but it has **not been run on a
> Quest yet**. Nothing below "Step 2" exists yet.

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
- [ ] 2. Empty VR room that starts on the Quest 1 *(built, waiting on a headset test)*
- [ ] 3. Command server: spawn, move, colour, delete and list objects from the PC
- [ ] 4. Claude on the PC drives it through those commands (an MCP server)
- [ ] 5. Save the world before every change, and undo
- [ ] 6. Claude can send scripts, so objects can have behaviour (behind an on/off switch)
- [ ] 7. Load 3D models and images from the internet
- [ ] 8. Talk to Claude from inside the headset

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

## Building

GitHub Actions builds the APK on every push
([`.github/workflows/quest1-apk.yml`](.github/workflows/quest1-apk.yml)). It
downloads pinned versions of Godot, its export templates and the OpenXR
plugin, checks each file's SHA-512, exports a debug APK, and then checks the
APK itself: the build fails unless `com.oculus.supportedDevices` is exactly
`quest|quest2` (naming a newer headset makes the Quest 1 abort at start).

To build on your own PC instead: open `game/` in Godot 4.7.2, install the
Godot OpenXR Vendors plugin 5.1.0 into `game/addons/`, install the Android
build template, and export the "Quest 1" preset.

## Repository layout

| Path | What it is |
| --- | --- |
| `game/project.godot` | Project settings: OpenGL ES renderer, OpenXR on |
| `game/main.tscn` | The room: floor, sky, sun, cube, player and controllers |
| `game/main.gd` | Starts OpenXR and logs everything about the start-up |
| `game/export_presets.cfg` | The "Quest 1" Android export (Quest 1 and 2 only) |
| `.github/workflows/quest1-apk.yml` | Builds and checks the APK |

## Known unknowns

- The OpenXR plugin's manifest asks for Horizon OS SDK 69, newer than the
  Quest 1's last firmware. Android ignores tags it doesn't know, so this
  probably doesn't matter outside the Meta store, but that's a guess until
  the first headset test.
- Godot 4's Compatibility renderer hasn't been run on this Quest 1 before.

## Credits

- [Godot Engine](https://godotengine.org), MIT licence
- [Godot OpenXR Vendors](https://github.com/GodotVR/godot_openxr_vendors), MIT licence
- Made by Bubbagum88 with Claude
