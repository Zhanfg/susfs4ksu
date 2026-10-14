#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SUSFS_DIST_DIR:-$ROOT_DIR/.build/dist}"
TOOL_OUT="$DIST_DIR/ksu_susfs_arm64"
MODULE_OUT="$DIST_DIR/ksu_module_susfs.zip"
CLEAN=0

if [ "${1:-}" = "--clean" ]; then
	CLEAN=1
	shift
fi

if [ "$#" -ne 0 ]; then
	echo "Usage: ./build_all.sh [--clean]" >&2
	exit 2
fi

args=(--output "$TOOL_OUT")
if [ "$CLEAN" -eq 1 ]; then
	rm -rf "$DIST_DIR"
	args+=(--clean)
fi

mkdir -p "$DIST_DIR"

"$ROOT_DIR/build_ksu_susfs_tool.sh" "${args[@]}"
"$ROOT_DIR/build_ksu_module.sh" --tool "$TOOL_OUT" --output "$MODULE_OUT"

echo "[+] SUSFS build complete"
echo "    tool:   $TOOL_OUT"
echo "    module: $MODULE_OUT"
