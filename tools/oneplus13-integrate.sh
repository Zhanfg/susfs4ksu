#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/kernel_patches/patchset.json"
WORKSPACE=""

usage() {
  cat <<'EOF'
Usage:
  bash tools/oneplus13-integrate.sh --workspace PATH [--manifest PATH]

Integrates the pinned KernelSU + SUSFS patchset into an already composed
OnePlus 13 / SM8750 kernel_platform workspace.

Outputs:
- common/drivers/kernelsu/        patched KernelSU kernel sources
- common/fs/susfs.c               canonical SUSFS source
- common/include/linux/susfs*.h   canonical SUSFS headers
- common/susfs_defconfig          Kleaf defconfig fragment
- //common:susfs_defconfig        exported Bazel target
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --manifest) MANIFEST="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$WORKSPACE" ] || { echo "--workspace is required" >&2; exit 2; }
[ -d "$WORKSPACE/common/.git" ] || { echo "missing exact OnePlus common tree" >&2; exit 1; }
[ -d "$WORKSPACE/msm-kernel/.git" ] || { echo "missing exact OnePlus msm-kernel tree" >&2; exit 1; }

eval "$(
python3 - "$MANIFEST" <<'PY'
import json, shlex, sys
d=json.load(open(sys.argv[1], encoding="utf-8"))
for key, value in {
    "KSU_REPO": d["kernelsu"]["repository"],
    "KSU_SHA": d["kernelsu"]["baseline_commit"],
    "COMMON_SHA": d["kernel"]["baseline_commit"],
    "VENDOR_SHA": d["vendor_kernel"]["baseline_commit"],
}.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
)"

test "$(git -C "$WORKSPACE/common" rev-parse HEAD)" = "$COMMON_SHA"
test "$(git -C "$WORKSPACE/msm-kernel" rev-parse HEAD)" = "$VENDOR_SHA"

KSU_TREE="$WORKSPACE/.kernelsu-src"
rm -rf "$KSU_TREE"
git init -q "$KSU_TREE"
git -C "$KSU_TREE" remote add origin "$KSU_REPO"
git -C "$KSU_TREE" fetch --depth=1 origin "$KSU_SHA"
git -C "$KSU_TREE" checkout --detach FETCH_HEAD
test "$(git -C "$KSU_TREE" rev-parse HEAD)" = "$KSU_SHA"

bash "$ROOT_DIR/tools/susfs-patchctl.sh" apply   --manifest "$MANIFEST"   --require-direct   --kernel-tree "$WORKSPACE/common"   --ksu-tree "$KSU_TREE"

rm -rf "$WORKSPACE/common/drivers/kernelsu"
cp -a "$KSU_TREE/kernel" "$WORKSPACE/common/drivers/kernelsu"

python3 - "$WORKSPACE/common/drivers/Makefile" "$WORKSPACE/common/drivers/Kconfig" <<'PY'
from pathlib import Path
import sys

makefile = Path(sys.argv[1])
kconfig = Path(sys.argv[2])

m = makefile.read_text(encoding="utf-8")
entry = "obj-$(CONFIG_KSU) += kernelsu/"
if entry not in m:
    if not m.endswith("\n"):
        m += "\n"
    m += f"\n{entry}\n"
    makefile.write_text(m, encoding="utf-8")

k = kconfig.read_text(encoding="utf-8")
source = 'source "drivers/kernelsu/Kconfig"'
if source not in k:
    marker = "\nendmenu"
    pos = k.rfind(marker)
    if pos < 0:
        raise SystemExit("drivers/Kconfig has no top-level endmenu")
    k = k[:pos] + f"\n{source}\n" + k[pos:]
    kconfig.write_text(k, encoding="utf-8")
PY

cat > "$WORKSPACE/common/susfs_defconfig" <<'EOF'
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF

python3 - "$WORKSPACE/common/BUILD.bazel" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
needle = 'exports_files(["susfs_defconfig"])'
if needle not in s:
    if not s.endswith("\n"):
        s += "\n"
    s += "\n# Local OnePlus 13 SUSFS integration fragment.\n" + needle + "\n"
    p.write_text(s, encoding="utf-8")
PY

grep -q '^CONFIG_KSU=y$' "$WORKSPACE/common/susfs_defconfig"
grep -q '^CONFIG_KSU_SUSFS=y$' "$WORKSPACE/common/susfs_defconfig"
grep -q 'obj-$(CONFIG_KSU) += kernelsu/' "$WORKSPACE/common/drivers/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "$WORKSPACE/common/drivers/Kconfig"
grep -q 'exports_files(\["susfs_defconfig"\])' "$WORKSPACE/common/BUILD.bazel"

cat <<EOF
integrated=1
kernelsu_sha=$KSU_SHA
defconfig_target=//common:susfs_defconfig
kleaf_flag=--defconfig_fragment=//common:susfs_defconfig
EOF
