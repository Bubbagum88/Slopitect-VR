# Slopitect-VR

A VR sandbox for the Oculus Quest 1 that an AI (Claude) can change while
you're standing in it. You ask for something, Claude builds it into the
running world: objects, behaviour, things pulled in from the internet. No
rebuild, no restart. You and the AI build the world together.

> **Status:** the empty room (step 2), the command server (step 3) and the
> agent inside the app run on a Quest 1; the agent builds with Claude there.
> The newer parts (every window as data, files, voice and live code) are
> built and tested on a PC with Godot, but not yet on the headset.

## Features

Working now:

- **Modular:** every feature is a module in `game/modules/`, listed in
  `game/modules.json`. Modules can be added, removed and swapped, and one
  that fails to load is logged and skipped without stopping the rest.
- **An AI agent inside the app** *(tested on a Quest 1 with Claude)*: works
  with Claude, or any OpenAI-style service, or a model on your own PC
  (Ollama, LM Studio, llama.cpp). Its tools are the app's commands, its
  skills are plain `SKILL.md` files, and a firewall decides what it may do.
- **Every window is data** *(built, waiting on a headset test)*: the menu
  bar, the wrist panel and the chat window are panels of text, buttons and
  input boxes that you or the agent can change, add, move and remove while
  the app runs. Grab a panel with the grip to move it. The panels and the
  controllers are live modules (`live-modules/vrui.gd`, `controls.gd`), not
  part of the APK, so they can be swapped and rewritten.
- **A chat window in the headset**: press Y to open a terminal-style window
  that shows each step the agent takes and a summary of its thinking, with
  a keyboard, Send and STOP. X on the left controller always stops the agent.
- **Files** *(built, waiting on a headset test)*: the agent can read and
  write its own Slopitect folder on the headset freely; anything else in
  the headset's storage needs your Yes in the headset each time, and
  personal folders (photos, videos, downloads, documents) stay blocked.
- **Voice** *(built, waiting on a headset test)*: the agent's replies are
  read aloud if the headset has a speech engine; hold the left trigger to
  talk, through a speech-to-text service you choose (off until you set one).
- **New code while you play** *(built, waiting on a headset test)*: the
  agent can write new modules that load into the running app, each only
  after you've seen the code and said Yes in the headset.

- **The agent's avatar** *(a live module, PC-tested, waiting on a headset
  test)*: a little red cube with a face and floating sphere hands. It bobs,
  blinks, faces you and thinks while the agent works. Its face shows
  emotions (happy, sad, surprised, angry, confused, sleepy), and its mouth
  follows the words while the speech engine talks. Replies show in a speech
  bubble above its head (and hat), a page at a time, that waits at the edge
  of your view when the avatar is out of sight. It has outfits (top hat,
  party hat, crown, headphones, bow tie), and new ones can be made from
  simple shapes while the app runs.

What you can change live, what needs a new APK, and how the agent is kept
safe: [docs/LIVE-CHANGES-AND-SAFETY.md](docs/LIVE-CHANGES-AND-SAFETY.md).
Everything built so far and how far each part is tested:
[docs/PROJECT-STATE.md](docs/PROJECT-STATE.md).

Planned:

- **Repurpose and rebuild:** the agent has access to the files on the
  Oculus, so you can use game assets that are already on your own hardware
  in your own world. Those assets stay on your headset and PC; they are
  never uploaded to this repo or the GitHub backups.
- Saves and backups, free online assets, a safe web reader (see the roadmap).

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
- [x] 3. Command server: spawn, move, colour, delete and list objects from the PC *(tested on a Quest 1)*
- [ ] 4. Claude on the PC drives it through those commands (an MCP server)
- [ ] 5. Saves and backups: the world is saved as JSON before every change, with undo; backups go to a GitHub repo, so every version has a history
- [ ] 6. Claude can send scripts, so objects can have behaviour *(built as live modules, each behind your Yes; waiting on a headset test)*
- [ ] 7. Assets: Poly Haven (CC0, through its API) first; Kenney, Quaternius, Poly Pizza and Sketchfab (CC0 and CC-BY models only) as backups. Each asset's source and licence is recorded, and any that need credit are credited. Assets taken from games on your own headset are kept local and never backed up to GitHub
- [ ] 8. Talk to Claude from inside the headset *(typing tested on a Quest 1; voice built, waiting on a headset test)*
- [ ] 9. Upgrade while you play: new menus, tools and features loaded into the running app (scripts and Godot resource packs), with a new APK only for engine or permission changes *(menus and scripts built; resource packs not yet)*

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
.\slopi.ps1 -Pair
.\slopi.ps1 '{"cmd":"spawn","shape":"sphere","position":[0,1.5,-1],"color":"red"}'
```

The first line lets this PowerShell window run the script; the second
connects your PC's port 7777 to the app (again after each reconnect).
`-Pair` is needed once per PC: other apps on the headset can reach the port
too, so it only takes commands from programs you said Yes to. Say Yes in
the headset; the pairing key is saved in `slopi-key.txt` next to the script
(keep it private) and sent with every command. `pair_config` lists the
paired programs, and `{"cmd":"pair_config","remove":"NAME"}` unpairs one.

To talk to the agent from the PC and watch what it does, run
[`tools/slopi-chat.ps1`](tools/slopi-chat.ps1) from the same folder.

| Command | Fields | Example |
| --- | --- | --- |
| `ping` | | `{"cmd":"ping"}` |
| `help` | | `{"cmd":"help"}` |
| `list` | | `{"cmd":"list"}` |
| `spawn` | `shape` (box, sphere, cylinder, capsule), optional `name`, `position`, `rotation`, `scale`, `color` | `{"cmd":"spawn","shape":"box","name":"table","position":[1,0.4,-1.5],"scale":[1.2,0.8,0.6],"color":"#8b5a2b"}` |
| `move` | `name`, and any of `position`, `rotation`, `scale` | `{"cmd":"move","name":"table","rotation":[0,45,0]}` |
| `color` | `name`, `color` | `{"cmd":"color","name":"table","color":"blue"}` |
| `delete` | `name` | `{"cmd":"delete","name":"table"}` |
| `modules` | | `{"cmd":"modules"}` lists the loaded modules and why any failed |
| `agent_ask` | `prompt` | `{"cmd":"agent_ask","prompt":"build a small table in front of me"}` |
| `agent_status` | | `{"cmd":"agent_status"}`: what it's doing, its reply, recent steps |
| `agent_stop` | | `{"cmd":"agent_stop"}` |
| `agent_reset` | | `{"cmd":"agent_reset"}` starts a new conversation |
| `agent_config` | any of `provider`, `model`, `base_url`, `api_key`, `effort`, `max_tokens`, `max_tokens_field`, `max_tool_rounds`, `max_tokens_per_ask`, `max_context_tokens`, `max_tool_result_chars`, `fallbacks`, `show_thinking`, `allowed_tools` | `{"cmd":"agent_config"}` shows them |
| `agent_skills` | | `{"cmd":"agent_skills"}` |
| `avatar_move` | `position` | `{"cmd":"avatar_move","position":[0,1.4,-1]}` |
| `avatar_say` | `text` | `{"cmd":"avatar_say","text":"Hi!"}` |
| `avatar_state` | `state` (idle, thinking, talking, happy, wave), optional `seconds` | `{"cmd":"avatar_state","state":"wave","seconds":3}` |
| `avatar_emotion` | `emotion` (neutral, happy, sad, surprised, angry, confused, sleepy), optional `seconds` | `{"cmd":"avatar_emotion","emotion":"happy"}` |
| `avatar_status` | | `{"cmd":"avatar_status"}`: place, state, emotion, outfit, talking, what the bubble shows |
| `avatar_outfit` | `name` | `{"cmd":"avatar_outfit","name":"top_hat"}` |
| `avatar_outfits` | | `{"cmd":"avatar_outfits"}` |
| `avatar_outfit_remove` | `name` (an added outfit) | `{"cmd":"avatar_outfit_remove","name":"wizard"}` |
| `avatar_outfit_add` | `name`, `parts` (up to 12 of `shape`, `size`, `position`, optional `rotation`, `color`) | `{"cmd":"avatar_outfit_add","name":"wizard","parts":[{"shape":"cone","size":[0.18,0.25,0.18],"position":[0,0.23,0],"color":"purple"}]}` |

Windows (panels):

| Command | Fields | Example |
| --- | --- | --- |
| `ui_list` | | `{"cmd":"ui_list"}` |
| `ui_get` | `id_panel` | `{"cmd":"ui_get","id_panel":"bar"}` shows every element |
| `ui_add` | `id_panel`, and any of `title`, `place` (front, wrist, world), `distance`, `height`, `position`, `rotation`, `size`, `color`, `visible`, `toggle`, `layout` (free, grid), `columns`, `cell`, `elements` | `{"cmd":"ui_add","id_panel":"tools","place":"world","position":[0,1.4,-1],"size":[0.4,0.3],"visible":true,"elements":[{"type":"text","id":"t","at":[0,0.12],"width":0.36,"text":"Tools"}]}` |
| `ui_update` | `id_panel`, then any panel fields | `{"cmd":"ui_update","id_panel":"tools","color":"#203040"}` |
| `ui_remove` | `id_panel` | `{"cmd":"ui_remove","id_panel":"tools"}` |
| `ui_show` | `id_panel`, `visible` | `{"cmd":"ui_show","id_panel":"chat","visible":true}` |
| `ui_element_add` | `id_panel`, `element`, optional `index` | `{"cmd":"ui_element_add","id_panel":"bar","element":{"type":"button","id":"red","label":"Make red","action":{"cmd":"color","name":"table","color":"red"}}}` |
| `ui_element_update` | `id_panel`, `id_element`, then fields | `{"cmd":"ui_element_update","id_panel":"bar","id_element":"red","label":"Red!"}` |
| `ui_element_remove` | `id_panel`, `id_element` | `{"cmd":"ui_element_remove","id_panel":"bar","id_element":"red"}` |
| `ui_press` | `id_panel`, `id_element` | `{"cmd":"ui_press","id_panel":"bar","id_element":"spawn_box"}` |
| `ui_type`, `ui_key` | `text`; `key` (shift, backspace, clear) | types into the selected input box |
| `ui_reset` | optional `id_panel` | `{"cmd":"ui_reset"}` puts the default panels back |

Elements are `text` (optionally a live `source`: a read-only command's
reply), `button` (its `action` is any command), `input` and `box`; the
agent's [UI skill](game/skills/slopitect-ui/SKILL.md) lists their fields.
With the controls module's default bindings, press the left controller's
menu button (≡) for the bar and Y for the chat. Point with the right controller and pull the trigger to
press a button; hold the right grip to move a panel. A button's action can
use `"position":"in_front"` for 1 m in front of you and `"{input:ID}"` for
what's typed in a box. Panels are saved on the headset; menu buttons from
the earlier menu are moved onto them the first time.

Files, questions, voice and live code:

| Command | Fields | Example |
| --- | --- | --- |
| `files_status` | | `{"cmd":"files_status"}`: the folder, the storage permission, blocked folders |
| `files_list` | optional `path` | `{"cmd":"files_list","path":"/sdcard/Android/obb"}` |
| `files_info` | `path` | |
| `files_read` | `path`, optional `offset`, `max_bytes` | `{"cmd":"files_read","path":"notes/todo.txt"}` |
| `files_write` | `path`, `text` or `base64`, optional `append` | `{"cmd":"files_write","path":"notes/todo.txt","text":"paint the table"}` |
| `files_mkdir`, `files_delete` | `path` | |
| `files_move`, `files_copy` | `from`, `to` | `{"cmd":"files_copy","from":"/sdcard/Android/obb/some.obb","to":"extract/some.obb"}` |
| `files_config` | `unblock` or `block` (a personal folder) | PC only: `{"cmd":"files_config","unblock":"/sdcard/Download/models"}` |
| `confirm_status` | | the questions waiting for your answer in the headset |
| `voice_say` | `text`, optional `voice` | `{"cmd":"voice_say","text":"Hello!"}` |
| `voice_stop`, `voice_voices`, `voice_status` | | |
| `voice_config` | any of `speak_replies`, `voice`, `rate`, `pitch`, `volume`, `stt_engine`, `stt_local_model`, `stt_url`, `stt_key`, `stt_model`, `stt_language`, `send_to_agent` | PC only, see below |
| `code_list` | | the live modules and their state |
| `code_load` | `name` | loads `modules/NAME.gd` from the Slopitect folder after your Yes |
| `code_unload`, `code_forget` | `name` | take one out; withdraw its Yes |

A path without a leading `/` is in the Slopitect folder
(`/sdcard/Slopitect` on the headset). Commands that wait for your Yes in
the headset (or a long copy) answer once it's given; the PC script waits up
to 2 minutes.

Positions are in metres from the middle of your play area (y is up, -z is
forward); rotations are in degrees; colours are `#rrggbb` or names like
`red`. Every reply has `"ok"`, and a failed one says exactly what was wrong
in `"error"`, without changing anything. Every command is also logged
(`Slopitect cmd:` in `.\adb logcat -s godot`).

## Setting up the agent

1. Get an API key at [console.anthropic.com](https://console.anthropic.com)
   (this is separate from a claude.ai plan; it's prepaid).
2. With Slopitect open on the headset, in PowerShell in platform-tools:
   ```
   Set-ExecutionPolicy -Scope Process Bypass
   .\adb forward tcp:7777 tcp:7777
   .\slopi.ps1 -SetKey
   ```
   Paste the key when asked. It isn't shown or saved in PowerShell's
   history, it's hidden in the app's logs, and it stays on the headset.
3. In the headset, press Y, type with the laser, press Send.

Settings that end in `_config` (`agent_config`, `files_config`,
`voice_config`) can only be changed from the PC: the agent can't use them
and no button can run them.

### Voice

The agent's replies are read aloud by the headset's speech engine, if it
has one (`voice_status` shows how many voices it found). If it has none,
a speech engine app has to be installed on the headset (for example
[SherpaTTS](https://f-droid.org/en/packages/org.woheller69.ttsengine/),
not yet tried on a Quest 1).

Hold-to-talk turns what you say into text in one of two ways.

**On the headset** (nothing you say leaves it): whisper.cpp, through
[godot-whisper](https://github.com/appsinacup/godot-whisper), built into
the APK. It needs a model file in the Slopitect folder. Download
[ggml-tiny.en.bin](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin)
(about 78 MB, English) on the PC, then:

```
.\adb shell mkdir -p /sdcard/Slopitect/models
.\adb push "C:\path\to\ggml-tiny.en.bin" /sdcard/Slopitect/models/
.\slopi.ps1 '{"cmd":"voice_config","stt_engine":"local"}'
```

A bigger model (`ggml-base.en.bin`, about 148 MB) hears better and takes
longer; set `stt_local_model` to its name. How fast it is on the Quest 1
isn't measured yet: each try logs how long it took.

**Through a service** (`stt_engine` `"web"`, the default; off until you set
one). For OpenAI's (paid), with its key in a text file:

```
.\slopi.ps1 (@{cmd="voice_config"; stt_url="https://api.openai.com/v1/audio/transcriptions"; stt_key=(Get-Content "C:\path\to\openai key.txt" -Raw).Trim()} | ConvertTo-Json -Compress)
```

Or a free one on your own PC with [whisper.cpp](https://github.com/ggml-org/whisper.cpp)'s
server (`whisper-server --host 0.0.0.0 --port 8080 -m <model>`), no key:

```
.\slopi.ps1 '{"cmd":"voice_config","stt_url":"http://192.168.1.50:8080/inference"}'
```

Then hold the left trigger, talk, and let go: the words go into the chat's
input box for you to check and Send (`"send_to_agent":true` sends them
straight away). Android asks once for the microphone.

The default is Claude Opus 5.5 (`claude-opus-5-5`), effort `medium`.

**Tokens** (what the AI company bills): `agent_status` shows them under
`tokens` (the conversation's size, this question, and since the app
started), and each round logs them. To keep them down:
- With Claude, everything already sent is cached, so each later round reads
  it back at a twentieth of the price instead of paying for it again.
- Replies are kept short (the `caveman` skill, which is always on).
- A tool reply over `max_tool_result_chars` (8000) is cut, and the agent is
  told to ask for less.
- One question stops after `max_tokens_per_ask` (300000) tokens; ask again
  to carry on.
- A conversation over `max_context_tokens` (80000) starts over at the next
  question (the world stays; the agent looks again with `list`).
- Lower `effort` (`low`) thinks less; a cheaper model (like
  `claude-haiku-5-5`) costs far less per token, but is less capable. If
Claude declines a request, the API runs it again on the model Anthropic
recommends (`fallbacks`; Claude API only).

To use another AI, set `provider` to `openai` and `base_url` to its address
up to `/v1`, for example a model on your PC with Ollama:
```
.\slopi.ps1 '{"cmd":"agent_config","provider":"openai","base_url":"http://192.168.1.50:11434/v1","model":"qwen2.5:7b"}'
```
then `-SetKey` again if that service needs a key. Changing the address or
provider clears the old key, so it is never sent anywhere else.

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
| `game/command_server.gd` | The command server (port 7777, JSON lines): a registry that modules add their commands to |
| `game/modules.gd` | Loads the modules listed in `game/modules.json` |
| `game/modules/module.gd` | The base every module extends |
| `game/modules/objects.gd` | Spawn, move, colour, delete and list objects |
| `live-modules/vrui.gd` | Every window: panels, the pointer, typing; the default bar, wrist panel and chat |
| `game/modules/confirm.gd` | The Yes/No questions only you can answer, in the headset |
| `game/modules/files.gd` | Files: the Slopitect folder, everything else behind your Yes |
| `game/modules/agent.gd` | The AI agent: settings, firewall, tool loop |
| `game/modules/voice.gd` | Speech out and hold-to-talk |
| `game/modules/code.gd` | Live modules: new code loaded after your Yes |
| `game/pending.gd` | A command's answer that comes later (after your Yes) |
| `game/agent/providers/` | One file per kind of AI service (`anthropic.gd`, `openai.gd`) |
| `game/skills/` | The agent's shipped skills, one `SKILL.md` per folder |
| `docs/LIVE-CHANGES-AND-SAFETY.md` | What changes live, what needs a new APK, and the safety rules |
| `docs/PROJECT-STATE.md` | Everything built so far, how sure we are each part works, the rules, and what's open |
| `docs/MODULE-FRAMEWORK.md` | The plan for live modules to plug into each other, and the review of the draft modules |
| `live-modules/` | The live modules; `live-modules/drafts/` holds new ones waiting to be reworked |
| `CLAUDE.md` | Working rules for Claude sessions on this repo |
| `tools/slopi.ps1` | Sends one command from your PC and prints the reply |
| `tools/slopi-chat.ps1` | Talks to the agent from your PC and shows its replies and tool calls as they happen |
| `tools/slopi-backup.ps1` | Backs up a project from the headset into a git repository on the PC, and pushes it with -Push (private projects and assets/ are never taken) |
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
- [godot-whisper](https://github.com/appsinacup/godot-whisper) and [whisper.cpp](https://github.com/ggml-org/whisper.cpp), MIT licence (on-headset speech to text)
- Made by Bubbagum88 with Claude

## Licence

MIT, see [LICENSE](LICENSE).
