# Working with the headset over Wi-Fi (wireless adb)

How to reach the Quest 1 from the PC without a cable, then talk to
Slopitect, sync live modules and read the log. Every command runs in
PowerShell in the folder that holds `adb.exe` (Android platform-tools), so
it's written `.\adb`. Replace `192.168.1.60` (an example) with your headset's IP (in the
headset: Settings > Wi-Fi > your network).

You need developer mode on the headset and the PC on the same Wi-Fi.

## 1. Connect

There are two ways. Pick one.

### A. Wireless debugging with a pairing code (no cable)

1. On the headset, turn on **Wireless debugging** and choose **Pair device
   with pairing code**. It shows an IP with a *pairing* port and a
   six-digit code. The connect port is shown on the Wireless debugging
   screen itself, and it's a different number.
2. Pair once per PC, with the real numbers from that screen:
   ```
   .\adb pair 192.168.1.60:37099 123456
   ```
3. Connect, using the *connect* port:
   ```
   .\adb connect 192.168.1.60:41024
   .\adb devices
   ```

The connect port changes after every headset restart. You don't have to
look it up: `slopi-sync.ps1 -Device 192.168.1.60` (just the IP) tries the
headset's open ports and connects to the one that answers. Pairing is kept,
so you don't pair again.

### B. A fixed port, set once over USB

Plug the headset in, allow the PC in the headset, then:

```
.\adb tcpip 5555
.\adb connect 192.168.1.60:5555
```

Unplug it. The port stays 5555 until the headset restarts; after that, run
these two commands again with the cable.

PowerShell can't take commands that contain `<placeholder>` text, so always
fill in the real IP, port and code.

## 2. Start Slopitect and keep it awake

```
.\adb shell monkey -p io.github.bubbagum88.slopitect 1
```

The app pauses while the headset is asleep (off your head or display off),
and the command port stops answering. Wear it, or wake it, before sending
commands or loading modules. To stop the app: `.\adb shell am force-stop io.github.bubbagum88.slopitect`.

## 3. Talk to the app

The command server listens on port 7777 on the headset's loopback, so it's
reached through an adb forward (again after every reconnect):

```
Set-ExecutionPolicy -Scope Process Bypass
.\adb forward tcp:7777 tcp:7777
.\slopi.ps1 -Pair
.\slopi.ps1 '{"cmd":"ping"}'
```

`-Pair` is needed once per PC (say Yes in the headset). The pairing key is
kept in `slopi-key.txt` next to the script: keep it private and never
commit it. `-SetKey` sends the agent's API key into the app's storage
without showing or saving it. `slopi-chat.ps1` talks to the agent from the PC.

With more than one device on adb, add `-s 192.168.1.60:41024` after `.\adb`.

## 4. Sync live modules

[`tools/slopi-sync.ps1`](../tools/slopi-sync.ps1) runs from the repo clone
(not from platform-tools). Point `-Tools` at the platform-tools folder
(the one with `adb.exe` and the paired `slopi.ps1`), or set
`$env:SLOPI_TOOLS` to it once.

```
# What's on the headset, loaded and approved, compared with the PC
powershell -ExecutionPolicy Bypass -File C:\Ptojects\Slopitect-VR\tools\slopi-sync.ps1 -Tools D:\quest1-root-project\tools\platform-tools -Device 192.168.1.60 -Status

# Push the changed modules and load them (a Yes in the headset for each)
powershell -ExecutionPolicy Bypass -File C:\Ptojects\Slopitect-VR\tools\slopi-sync.ps1 -Tools D:\quest1-root-project\tools\platform-tools -Load

# Only some modules
powershell -ExecutionPolicy Bypass -File C:\Ptojects\Slopitect-VR\tools\slopi-sync.ps1 move,grab -Load
```

How it works:

- Only modules that differ from the headset's copy (by SHA-256) are pushed,
  and each push is checked by reading the hash back.
- With `-Load`, each changed module gets a `code_load` in the order they
  need each other (controls and the window system first). Its code shows in
  the headset and waits for your Yes, which nothing on the PC can answer.
- It's **two-way**: a module the in-app agent changed on the headset, or
  one only the headset has, is first copied into `live-modules\drafts\`
  with the date, so it's never lost. Then the PC's version wins.
- Keep git from changing line endings in the clone
  (`git config core.autocrlf false`). Otherwise every module's hash changes
  and modules you already approved ask for a Yes again.

By hand, one module:

```
.\adb push C:\Ptojects\Slopitect-VR\live-modules\joints.gd /sdcard/Slopitect/modules/
.\slopi.ps1 '{"cmd":"code_load","name":"joints"}'
```

After a fresh APK, load `controls` and `vrui` first, or there are no windows.

## 5. Install a new APK

Download the `slopitect-quest1-debug` artifact from the latest green
"Quest 1 APK" run under the repo's **Actions** tab, unzip it, then:

```
.\adb install -r --no-streaming slopitect-quest1-debug.apk
```

Over Wi-Fi, use `--no-streaming`: a streamed install of a large APK
dropped the adb connection on this Quest, and this way it works.

Every build is signed with `ci/debug.keystore`, so it installs over the
last one and keeps the app's data and approvals.

## 6. Read the log

```
.\adb logcat -s godot
```

Every app line starts with `Slopitect:` and every command with
`Slopitect cmd:`. To diagnose a crash or a plugin that doesn't load, take
the full log from the app's start instead (`.\adb logcat -c`, start the
app, then `.\adb logcat > start.txt`). Look for `dlopen failed` lines.
The log can show the conversation, so don't share it publicly.

## When something fails

| What you see | What it means |
| --- | --- |
| `no devices/emulators found` | The Wi-Fi link dropped or the headset restarted: connect again (`-Device` with just the IP) |
| `Nothing is listening on localhost:7777` | Run `.\adb forward tcp:7777 tcp:7777` again |
| `the headset is asleep` / the app isn't answering | Put the headset on with Slopitect showing |
| `The term '.\slopi-sync.ps1' is not recognized` | It's in the repo's `tools\`, not platform-tools: use the full path as above |
| A module you approved asks for a Yes again | Its file changed, often from line endings (see autocrlf above) |
