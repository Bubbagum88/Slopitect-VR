#!/bin/bash
# Builds the gamecoob extension into game/addons/gamecoob/bin: the Linux
# library (for headless tests on a PC) always, the Quest's (Android arm64)
# when ANDROID_NDK points at an Android NDK. CI does the same in
# .github/workflows/quest1-apk.yml.
#   native/gamecoob/build.sh                  needs ./GameCoob-Bios: a checkout of
#                                             github.com/Bubbagum88/GameCoob-Bios
#   ANDROID_NDK=/path/to/ndk native/gamecoob/build.sh
# Rust's aarch64-linux-android target is plain ARMv8-A (with NEON), which the
# Quest 1's Snapdragon 835 runs; nothing newer may be turned on.
set -euo pipefail
cd "$(dirname "$0")"
[ -f GameCoob-Bios/src/bs2/mod.rs ] || { echo "no GameCoob-Bios checkout in native/gamecoob/GameCoob-Bios"; exit 1; }
out=../../game/addons/gamecoob/bin
mkdir -p "$out"
cargo build --release --target x86_64-unknown-linux-gnu
cp target/x86_64-unknown-linux-gnu/release/libgamecoob.so "$out/libgamecoob.linux.x86_64.so"
if [ -n "${ANDROID_NDK:-}" ]; then
  linker="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang"
  [ -x "$linker" ] || { echo "no $linker"; exit 1; }
  CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$linker" cargo build --release --target aarch64-linux-android
  cp target/aarch64-linux-android/release/libgamecoob.so "$out/libgamecoob.android.arm64.so"
fi
ls -l "$out"
