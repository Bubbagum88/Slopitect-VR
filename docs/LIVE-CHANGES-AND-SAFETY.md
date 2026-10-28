# What changes live, what needs a new APK, and how the agent is kept safe

## Changes you can make while the app runs

| What | How | Kept after a restart |
| --- | --- | --- |
| Objects in the world | `spawn`, `move`, `color`, `delete` (you, the agent, or a menu button) | Not yet (saves are roadmap step 5) |
| Menu buttons | `menu_add`, `menu_update`, `menu_remove`, `menu_reset` | Yes, `user://menu.json` |
| Which AI the agent uses | `agent_config` from the PC: `provider`, `model`, `base_url`, `api_key` | Yes, `user://agent.json` |
| What the agent may do | `agent_config` from the PC: `allowed_tools` | Yes |
| How the agent works | `agent_config`: `effort`, `max_tokens`, `max_tool_rounds`, `show_thinking` | Yes |
| The agent's skills | `SKILL.md` files in `user://skills/<name>/` (replace a shipped skill of the same name) | Yes |

## Changes that need a new APK today

- **A new module, or a change to a module's code.** Modules are loaded from
  inside the APK only. Roadmap step 9 adds loading modules and Godot
  resource packs from the headset's storage, so this moves to the table
  above. It comes after the safety rules below are in place, because a
  module is code: only you, from the PC, will be able to install one, and
  never the agent on its own.
- **Always a new APK, by design:**
  - Android permissions (microphone, storage and so on), the app's name,
    icon and package
  - native plugins (anything with a `.so`, such as speech recognition or an
    OpenXR plugin update) and the Godot version itself
  - project settings (renderer, XR settings)
  - the safety core: the command server, its guard, and the module loader.
    These can't be changed from inside the app on purpose, so nothing
    running in the app can switch the safety off.

The APK already declares the internet, microphone and file (storage)
permissions, so voice and file features won't need a new APK for that.
Declaring a permission doesn't grant it: Android asks you the first time a
feature needs it, and nothing uses the microphone or files yet.

A new APK installs over the old one (same signing key) and keeps the
settings, menu and skills.

## How the agent is kept safe

In place:

- **The API key** is hidden in every log line and never sent back by any
  command. Give it with `.\slopi.ps1 -SetKey`, which asks for it hidden, so
  it isn't on screen or in PowerShell's history. It is only ever sent to
  the address it was set for: changing `base_url` or `provider` without
  giving the key again clears it, so nothing can redirect it to another
  server.
- **A firewall on what the agent can do:** it can only use the commands in
  `allowed_tools`. A new module's commands are off for the agent until you
  add them. The agent can never use its own `agent_*` commands, so it can't
  change its key, its provider or its permissions. The check also covers
  commands run indirectly, like a menu button the agent presses.
- **Buttons can't change the agent's settings;** only the PC can.
- **Outside text is data, not orders.** The agent is told that only your
  messages tell it what to do, and that anything coming back from a tool,
  file, web page or asset is information, even if it claims otherwise.
- **Stop:** the STOP key in the chat window, or `agent_stop`, drops the
  request in flight and runs no more tools.
- **The command server** only listens on the headset itself, not on your
  network.

Known gaps, in the open:

- **Any other app on the headset could connect to port 7777.** It can't
  read the key, but it could send commands. Next safety step: a pairing
  code the PC has to send first.
- **What you type to the agent goes to that AI company.** With a
  self-hosted model on your PC, it stays at home.
- **The key is stored as plain text** in the app's private storage. Android
  keeps other apps out of it, but root apps can read it. Encrypting it
  inside the app wouldn't help, because the app would have to carry the
  key to decrypt it.
- **The log (`adb logcat`) shows the conversation** (never the key).

Planned, before the agent gets these powers:

- File access limited to the app's own folders and game folders you name.
  Personal folders (photos, downloads, documents, accounts) are never
  readable by the agent.
- Web access through an allowlist of sites you approve; the agent can't add
  sites itself.
- A "confirm in the headset" step for risky commands (installing a module,
  deleting files, pushing backups).
