#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/kernel_patches/patchset.json"
WORKSPACE=""
MODE="prepare"

usage() {
  cat <<'EOF'
Usage:
  bash tools/oneplus13-workspace.sh --workspace PATH [--mode prepare|query]

Builds a public, reproducible OnePlus 13 / SM8750 kernel_platform workspace:
1. Google public common-android15-6.6 manifest supplies Kleaf/prebuilts.
2. OnePlus modules+DT OSS overlays Qualcomm/OPlus projects and build glue.
3. Exact OnePlus common and msm-kernel commits replace the generic trees.

The query mode additionally verifies //msm-kernel:sun_perf and
//msm-kernel:sun_perf_dist resolve in the composed workspace.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --manifest) MANIFEST="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$WORKSPACE" ] || { echo "--workspace is required" >&2; exit 2; }
case "$MODE" in prepare|query) ;; *) echo "invalid --mode: $MODE" >&2; exit 2 ;; esac

command -v python3 >/dev/null
command -v git >/dev/null
command -v rsync >/dev/null

eval "$(
python3 - "$MANIFEST" <<'PY'
import json, shlex, sys
d=json.load(open(sys.argv[1], encoding="utf-8"))
def e(k,v): print(f"{k}={shlex.quote(str(v))}")
e("COMMON_REPO", d["kernel"]["repository"])
e("COMMON_SHA", d["kernel"]["baseline_commit"])
e("VENDOR_REPO", d["vendor_kernel"]["repository"])
e("VENDOR_SHA", d["vendor_kernel"]["baseline_commit"])
e("MODULES_REPO", d["modules_and_devicetree"]["repository"])
e("MODULES_SHA", d["modules_and_devicetree"]["baseline_commit"])
PY
)"

REPO_BIN="$WORKSPACE/.repo-bin/repo"
MODULES_STAGE="$WORKSPACE/.oneplus-modules"

mkdir -p "$WORKSPACE/.repo-bin"
if [ ! -x "$REPO_BIN" ]; then
  curl --retry 3 --retry-all-errors -fsSL \
    https://storage.googleapis.com/git-repo-downloads/repo \
    -o "$REPO_BIN"
  chmod +x "$REPO_BIN"
fi

if [ ! -d "$WORKSPACE/.repo" ]; then
  (
    cd "$WORKSPACE"
    "$REPO_BIN" init \
      -u https://android.googlesource.com/kernel/manifest \
      -b common-android15-6.6 \
      --depth=1 \
      --no-repo-verify
  )
fi

(
  cd "$WORKSPACE"
  "$REPO_BIN" sync \
    -c -j4 --no-tags --prune --no-repo-verify
)

clone_exact() {
  local repo="$1" sha="$2" dst="$3"
  rm -rf "$dst"
  git init -q "$dst"
  git -C "$dst" remote add origin "$repo"
  git -C "$dst" fetch --depth=1 origin "$sha"
  git -C "$dst" checkout --detach FETCH_HEAD
  test "$(git -C "$dst" rev-parse HEAD)" = "$sha"
}

clone_exact "$MODULES_REPO" "$MODULES_SHA" "$MODULES_STAGE"

# Overlay OnePlus/QCOM build glue and external vendor projects while preserving
# public-manifest prebuilts that are intentionally absent from the OSS snapshot.
rsync -a \
  --exclude '.git/' \
  "$MODULES_STAGE/kernel_platform/" "$WORKSPACE/"

for top in vendor; do
  if [ -d "$MODULES_STAGE/$top" ]; then
    mkdir -p "$WORKSPACE/$top"
    rsync -a --exclude '.git/' \
      "$MODULES_STAGE/$top/" "$WORKSPACE/$top/"
  fi
done

clone_exact "$COMMON_REPO" "$COMMON_SHA" "$WORKSPACE/common"
clone_exact "$VENDOR_REPO" "$VENDOR_SHA" "$WORKSPACE/msm-kernel"

# OnePlus' msm-kernel repository intentionally contains symlinks such as:
#   kernel/oplus_cpu -> ../../../vendor/oplus/kernel/cpu
# In an Android source checkout those resolve outside kernel_platform, into
# ANDROID_BUILD_TOP/vendor. A standalone public Kleaf workspace has no such
# parent tree and Bazel sandboxes would preserve them as dangling links.
#
# Materialize only the exact external targets referenced by the pinned vendor
# kernel. Resolve each link against the original modules+DT Android-top layout;
# internal msm-kernel links are left untouched. This keeps the workspace
# self-contained without copying the complete vendor tree.
materialize_external_vendor_links() {
  local kernel_root="$WORKSPACE/msm-kernel"
  local original_kernel_root="$MODULES_STAGE/kernel_platform/msm-kernel"
  local link rel target source

  while IFS= read -r -d '' link; do
    rel="${link#"$kernel_root"/}"
    target="$(readlink "$link")"

    # Resolve the link as it exists in the official Android source layout.
    source="$(realpath -m "$original_kernel_root/$(dirname "$rel")/$target")"

    case "$source" in
      "$MODULES_STAGE"/vendor/*)
        [ -e "$source" ] || {
          echo "missing official symlink target for $rel: $source" >&2
          return 1
        }
        rm -f "$link"
        if [ -d "$source" ]; then
          mkdir -p "$link"
          rsync -a --exclude '.git/' "$source/" "$link/"
        else
          mkdir -p "$(dirname "$link")"
          cp -a "$source" "$link"
        fi
        ;;
    esac
  done < <(find "$kernel_root" -type l -print0)
}

materialize_external_vendor_links

# The first hard dependency exposed by sun_perf Kconfig and several WALT
# includes must now be a real in-tree directory, not an external symlink.
test -f "$WORKSPACE/msm-kernel/kernel/oplus_cpu/Kconfig"

# Match OnePlus build_with_bazel.py / prepare_vendor.sh glue. Qualcomm's
# msm-kernel rules intentionally load these extensions through //build.
mkdir -p "$WORKSPACE/build"
ln -sfn ../msm-kernel/msm_kernel_extensions.bzl \
  "$WORKSPACE/build/msm_kernel_extensions.bzl"
if [ -f "$WORKSPACE/bootable/bootloader/edk2/abl_extensions.bzl" ]; then
  ln -sfn ../bootable/bootloader/edk2/abl_extensions.bzl \
    "$WORKSPACE/build/abl_extensions.bzl"
fi

# The OnePlus msm-kernel BUILD graph imports OPlus Bazel helpers from the
# modules+DT overlay. Verify the structural contract before invoking Bazel.
for required in \
  "$WORKSPACE/tools/bazel" \
  "$WORKSPACE/build_with_bazel.py" \
  "$WORKSPACE/build/android/prepare_vendor.sh" \
  "$WORKSPACE/build/msm_kernel_extensions.bzl" \
  "$WORKSPACE/oplus/bazel/oplus_modules_define.bzl" \
  "$WORKSPACE/oplus/config/modules.ext.oplus" \
  "$WORKSPACE/msm-kernel/sun.bzl" \
  "$WORKSPACE/common/Makefile"; do
  [ -e "$required" ] || { echo "missing workspace input: $required" >&2; exit 1; }
done

actual="$(
  awk -F= '
    /^VERSION[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); v=$2}
    /^PATCHLEVEL[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); p=$2}
    /^SUBLEVEL[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); s=$2}
    END {print v "." p "." s}
  ' "$WORKSPACE/common/Makefile"
)"
[ "$actual" = "6.6.118" ] || {
  echo "unexpected OnePlus common version: $actual" >&2
  exit 1
}

if [ "$MODE" = "query" ]; then
  (
    cd "$WORKSPACE"
    ./tools/bazel query //msm-kernel:sun_perf
    ./tools/bazel query //msm-kernel:sun_perf_dist
    ./tools/bazel query //msm-kernel:sun16k_perf
  )
fi

cat <<EOF
workspace=$WORKSPACE
common_sha=$COMMON_SHA
vendor_sha=$VENDOR_SHA
modules_sha=$MODULES_SHA
kernel_version=$actual
mode=$MODE
EOF
