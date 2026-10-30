#!/bin/bash
# Runs live modules headless in Godot 4.7.2 on a PC, in the order given; the
# last one is the test (a zz_ module that prints PASS/FAIL lines and quits).
#   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 FRESH=1 live-modules/tests/run.sh lib zz_lib
# Names are looked up in live-modules/ then live-modules/tests/; a path works
# too, and NAME=FILE loads FILE as module NAME (a stand-in: net=net_stub). FRESH=1 copies and imports game/ again (needed the first time).
# PICTURE=1 renders with opengl3 under xvfb-run, for view_look pictures.
set -e
REPO=$(cd "$(dirname "$0")/../.." && pwd)
G=${GODOT:?set GODOT to the Godot 4.7.2 binary}
WORK=${WORK:-${TMPDIR:-/tmp}/slopitect-test}
export HOME=$WORK/home
W=$WORK/game
if [ "$FRESH" = 1 ] || [ ! -d "$W" ]; then
  rm -rf "$HOME" "$W"; mkdir -p "$HOME"
  cp -r "$REPO/game" "$W"
  (cd "$W" && timeout 300 "$G" --headless --import >/dev/null 2>&1 || true)
  find "$W" -name '*.uid' -delete; rm -f "$W/openxr_action_map.tres"
fi
U=$HOME/.local/share/godot/app_userdata/Slopitect
rm -rf "$U"; mkdir -p "$U/files_home/modules"  # each run starts with no saved data
python3 - "$U" "$REPO/live-modules" "$@" <<'PY'
import sys, hashlib, json, shutil, os
u, src, names = sys.argv[1], sys.argv[2], sys.argv[3:]
approved = {}
for n in names:
    name, _, n = n.rpartition("=") if "=" in n else ("", "", n)
    f = n if n.endswith(".gd") else next((p for p in (f"{src}/{n}.gd", f"{src}/tests/{n}.gd") if os.path.exists(p)), None)
    if f is None:
        sys.exit(f"no module {n}")
    name = name or os.path.basename(f)[:-3]
    d = f"{u}/files_home/modules/{name}.gd"
    shutil.copy(f, d)
    approved[name] = hashlib.sha256(open(d, "rb").read()).hexdigest()
json.dump({"approved": approved}, open(f"{u}/code.json", "w"))
PY
cd "$W"
if [ -n "$PICTURE" ]; then
  timeout 180 xvfb-run -a "$G" --rendering-driver opengl3 --path . 2>&1
else
  timeout 180 "$G" --headless --path . 2>&1
fi
