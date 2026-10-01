#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cc="${CC:-cc}"
includes=(-I"$root/kernel_patches/include/uapi" -I"$root/ksu_susfs/jni/includes" -I"$root/ksu_susfs/jni/features")
"$cc" -std=c11 -Wall -Wextra -Werror "${includes[@]}" "$root/tests/abi-layout.c" -o "$tmp/layout"
"$tmp/layout"
"$cc" -std=gnu11 -Wall -Wextra -Werror "${includes[@]}" \
  "$root/tests/control-replies.c" "$root/ksu_susfs/jni/features/show.c" -o "$tmp/replies"
for scenario in modern legacy legacy-einval permission bad-version bad-size bad-bits bad-string legacy-string; do
  "$tmp/replies" "$scenario" > "$tmp/$scenario.out"
  case "$scenario" in
    modern) grep -q '^abi_version=1$' "$tmp/$scenario.out" ;;
    legacy|legacy-einval) grep -q '^version=v2.3.0$' "$tmp/$scenario.out" ;;
  esac
  echo "[+] control reply: $scenario"
done
if [ -n "${ANDROID_NDK_HOME:-}" ]; then
  for target in aarch64-linux-android23 armv7a-linux-androideabi23; do
    "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/$target-clang" \
      -std=c11 -Wall -Wextra -Werror "${includes[@]}" -c "$root/tests/abi-layout.c" -o "$tmp/$target.o"
    echo "[+] ABI layout: $target"
  done
fi
