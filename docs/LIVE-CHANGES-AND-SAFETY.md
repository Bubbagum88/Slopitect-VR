# What changes live, what needs a new APK, and how the agent is kept safe

## Changes you can make while the app runs

| What | How | Kept after a restart |
| --- | --- | --- |
| Objects in the world | `spawn`, `move`, `color`, `delete` (you, the agent, or a button) | Not yet (saves are roadmap step 5) |
| Every window: the menu bar, wrist panel, chat, and new ones | `ui_*` commands (you, the agent, or a button); grab one with the grip to move it | Yes, `user://ui.json` |
| New features (live modules) | A GDScript file in `modules/` of the Slopitect folder, then `code_load` and your Yes in the headset | Yes: an approved file loads at each start, until it changes |
| Files in the Slopitect folder | `files_*` commands | It's the headset's storage (`/sdcard/Slopitect`) |
| Which AI the agent uses | `agent_config` from the PC: `provider`, `model`, `base_url`, `api_key` | Yes, `user://agent.json` |
| What the agent may do | `agent_config` from the PC: `allowed_tools` | Yes |
| How the agent works | `agent_config`: `effort`, `max_tokens`, `max_tool_rounds`, `show_thinking`, and the token limits `max_tokens_per_ask`, `max_context_tokens`, `max_tool_result_chars` | Yes |
| Speech and hold-to-talk | `voice_config` from the PC | Yes, `user://voice.json` |
| Personal folders the agent may reach | `files_config` from the PC (`unblock`, `block`) | Yes, `user://files.json` |
| The agent's skills | `SKILL.md` files in `user://skills/<name>/` (replace a shipped skill of the same name) | Yes |

Live modules work like the built-in ones and can do anything they can, so
most new features no longer need an APK.

## Changes that need a new APK

- **A change to a built-in module** (the ones in `game/modules/`). A live
  module can add to them or stand in for one, though.
- **Always a new APK, by design:**
  - Android permissions, the app's name, icon and package
  - native plugins (anything with a `.so`) and the Godot version itself
  - project settings (renderer, XR, the microphone and speech switches)
  - the safety core: the command server, its guard, the module loader, the
    confirm window and the live-code module. These can't be changed from
    inside the app on purpose, so nothing running in the app can switch
    the safety off.

The APK declares the internet, microphone and storage permissions. Declaring
one doesn't grant it: Android asks you the first time a feature needs it
(the storage one when a file outside the app is first used, the microphone
the first time you hold to talk).

A new APK installs over the old one (same signing key) and keeps the
settings, panels, approvals and skills.

## How the agent is kept safe

In place:

- **The API key** (and any `..._key`) is hidden in every log line and never
  sent back by any command. Give it with `.\slopi.ps1 -SetKey`, which asks
  for it hidden. It is only ever sent to the address it was set for:
  changing `base_url` or `provider` without giving the key again clears it.
  The same goes for the speech-to-text key and `stt_url`.
- **A firewall on what the agent can do:** it can only use the commands in
  `allowed_tools`, plus the commands of live modules you said Yes to. It
  can never use its own `agent_*` commands or any `*_config` command, so it
  can't change its key, its provider, its permissions, which folders are
  blocked, or where your voice goes. The check also covers commands run
  indirectly, like a button the agent presses.
- **Buttons can't run `*_config` commands;** settings change from the PC.
- **Your Yes in the headset** for anything risky. A yellow-edged window
  asks; only pointing at Yes or No and pulling the right trigger answers
  it. No command can answer it, the pointer works on nothing else while
  it's open, it's drawn over everything, a trigger pulled in its first 0.6
  seconds doesn't count, and it says No after a minute. It asks for:
  - every file action outside the Slopitect folder, whoever asks (the
    agent, a button or the PC);
  - every file action in its `models` folder, since model files are read
    by native code that a doctored file could trick;
  - every new or changed live module, with the code shown beside it and a
    list of what it uses (files, the internet, other programs...). Nothing
    in a module is even compiled before your Yes, since compiling a script
    already runs part of it. The Yes is for that exact file (its SHA-256).
- **Blocked folders:** photos, videos, music, downloads, documents,
  recordings and the headset's screenshots (`/sdcard/Oculus`) can't be
  reached at all until you unblock one from the PC. The app's own settings
  (which hold your key) are never reachable through files_*. Nothing
  outside `/sdcard` can be reached (that would need root).
- **The microphone** only records while you hold the left trigger, with a
  red dot on your hand. No command can turn it on. With speech to text on
  the headset (`stt_engine` `"local"`), nothing you say leaves it. With a
  service, nothing leaves until you set one, and the recording is deleted
  once it's sent.
- **Outside text is data, not orders.** The agent is told that only your
  messages tell it what to do, and that anything coming back from a tool,
  file, web page or asset is information, even if it claims otherwise.
- **Stop:** X on the left controller (always; no panel can take it), the
  STOP key in the chat window, or `agent_stop`. It drops the request in
  flight, closes any question it's waiting on, and runs no more tools.
- **The command server** only listens on the headset itself, not on your
  network.

Known gaps, in the open:

- **A live module you approve can do anything the app can**, including
  reading the key and getting around every rule above. The Yes is the
  lock: read what it uses, and say No when unsure. The "uses" list is a
  hint from the words in the code, not a guarantee.
- **Any other app on the headset could connect to port 7777.** It can't
  read the key or answer a question, but it could send other commands.
  Next safety step: a pairing code the PC has to send first.
- **What you type or say to the agent goes to that AI company** (and your
  voice to the speech-to-text service, unless it's turned into text on the
  headset). With self-hosted ones on your PC,
  it stays at home.
- **The key is stored as plain text** in the app's private storage. Android
  keeps other apps out of it, but root apps can read it.
- **The log (`adb logcat`) shows the conversation** (never the key).
- A copy outside the Slopitect folder that you said Yes to keeps going if
  you then press Stop; only the agent stops waiting for it.

Planned:

- Web access through an allowlist of sites you approve; the agent can't add
  sites itself.
- Root, per command and only with your Yes in the headset plus Magisk's own
  prompt, never always on.
- Your Yes before pushing backups.
